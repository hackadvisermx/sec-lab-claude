#!/usr/bin/env bash
# =============================================================================
# SecLab — gestor interno de VPN autorizada multiperfil (Fase 7)
# =============================================================================
# Vive dentro de la imagen como /usr/local/bin/seclab-vpn. A diferencia del
# diseño anterior (un contenedor de VPN dedicado por perfil), toda la lógica
# de túneles vive AHORA dentro de 'lab': OpenVPN e iptables se instalan en la
# propia imagen, y docker-compose.vpn.yml sólo añade a 'lab' lo mínimo que
# hace falta para manipularlos (cap_add: NET_ADMIN, /dev/net/tun). 'lab'
# conserva siempre su propia red y sus propios puertos: nada de
# network_mode, nada de namespaces compartidos.
#
# Por qué este cambio (decisión del dueño del proyecto): un contenedor de VPN
# aparte no protegía de nada que 'lab' compartiendo su interfaz TUN no
# resolviera igual — quien comparte la plataforma (HTB, THM, un cliente) ya
# puede alcanzar por tun0 a cualquiera que use la misma VPN, y eso no depende
# de en qué contenedor viva la interfaz. La única mitigación real es una
# regla de firewall sobre esa interfaz (ver el killswitch de entrada, más
# abajo), no una topología de contenedores distinta.
#
# Se invoca de dos formas:
#   - Desde el host: `seclab vpn <subcomando>` hace `docker exec -u root lab
#     seclab-vpn <subcomando>` (ver vpn_exec() en bin/seclab).
#   - Desde dentro de una sesión `seclab shell`: `sudo seclab-vpn <subcomando>`
#     (el usuario de laboratorio tiene sudo sin contraseña, ver SECURITY.md).
#
# Recordatorio del modelo de responsabilidad (docs/uso-autorizado.md): nada de
# lo que hay aquí valida ni bloquea contra qué objetivo se conecta el alumno
# dentro del túnel.
#   - El killswitch de SALIDA (OUTPUT/FORWARD) es sobre el ESTADO del túnel
#     (arriba/caído): si cae, el tráfico hacia los rangos declarados se sigue
#     bloqueando en vez de escapar por la interfaz normal.
#   - El killswitch de ENTRADA (INPUT) es sobre la INTERFAZ por la que llega
#     una conexión, nunca sobre destinos: bloquea que alguien que comparte la
#     misma VPN de plataforma abra una conexión nueva hacia 'lab' a través del
#     túnel. No es un filtro de a qué IP te conectas TÚ dentro del rango.
#
# Los tres perfiles pueden estar arriba a la vez de verdad: cada uno usa su
# propia interfaz TUN (tun-htb, tun-thm, tun-cli) y sus propias reglas de
# iptables. El único motivo real de rechazo al levantar uno es que sus rangos
# se solapen con los de un perfil YA activo: con rangos solapados no hay forma
# de decidir por qué túnel debe salir un paquete.
# =============================================================================

set -uo pipefail

PERFILES_VALIDOS="vpnhtb vpntry vpncli"
BASE_PERFILES="/etc/seclab/vpn"
ESTADO="/run/seclab-vpn"
GANCHO="/usr/local/bin/seclab-vpn-hook"

log()   { printf '[seclab-vpn] %s\n' "$1" >&2; }

fallo() {
    # fallo QUE_PASO [QUE_IMPLICA] [QUE_HACER]
    printf '[seclab-vpn] ERROR: %s\n' "$1" >&2
    [ -n "${2:-}" ] && printf '[seclab-vpn]   Implica: %s\n' "$2" >&2
    [ -n "${3:-}" ] && printf '[seclab-vpn]   Solución: %s\n' "$3" >&2
    exit 1
}

exigir_root() {
    [ "$(id -u)" -eq 0 ] || fallo \
        "seclab-vpn necesita privilegios de root para ${1:-esta operación}." \
        "Manipula interfaces, rutas e iptables; un usuario normal no puede." \
        "Ejecuta 'sudo seclab-vpn ...' desde dentro del laboratorio, o 'seclab vpn ...' desde el host."
}

perfil_valido() {
    case " $PERFILES_VALIDOS " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

exigir_perfil_valido() {
    [ -n "$1" ] || fallo "Falta el perfil." "No se ha hecho nada." "Perfiles válidos: ${PERFILES_VALIDOS}"
    perfil_valido "$1" || fallo "Perfil desconocido: $1" "No se ha hecho nada." "Perfiles válidos: ${PERFILES_VALIDOS}"
}

sufijo_de() {
    case "$1" in
        vpnhtb) printf 'htb' ;;
        vpntry) printf 'thm' ;;
        vpncli) printf 'cli' ;;
    esac
}

# interfaz_de PERFIL -> nombre de interfaz TUN explícito de ese perfil. Nunca
# numerado (tun0, tun1...): con varios perfiles arriba a la vez, un nombre fijo
# por perfil es lo único que deja identificar sin ambigüedad de quién es cada
# interfaz en 'ip route', 'iptables -S' o un log.
interfaz_de() { printf 'tun-%s' "$(sufijo_de "$1")"; }

dir_perfil() { printf '%s/%s' "$BASE_PERFILES" "$1"; }
dir_estado() { printf '%s/%s' "$ESTADO" "$1"; }
pid_de()     { printf '%s/%s.pid' "$ESTADO" "$1"; }
log_de()     { printf '%s/%s.log' "$ESTADO" "$1"; }

# leer_env PERFIL CLAVE -> valor de esa clave en el perfil.env real del
# alumno, montado de sólo lectura en /etc/seclab/vpn/<perfil>/perfil.env.
#
# El `|| true` final importa: este script corre con `set -uo pipefail` (sin
# `-e` a propósito, para poder validar todo antes de fallar con un mensaje
# claro), pero una clave ausente hace que `grep` devuelva 1, y encadenado con
# `&&`/`if` en el resto del script eso podría interpretarse como "vacío" de
# formas inconsistentes. Mejor que el pipeline siempre salga 0.
leer_env() {
    local archivo="$(dir_perfil "$1")/perfil.env"
    [ -f "$archivo" ] || return 0
    grep -m1 "^${2}=" "$archivo" 2>/dev/null | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' || true
}

# proceso_vivo PERFIL -> 0 si su PID (guardado por OpenVPN con --writepid) está
# en /run/seclab-vpn/<perfil>.pid y el proceso sigue vivo.
proceso_vivo() {
    local pid
    pid="$(cat "$(pid_de "$1")" 2>/dev/null || true)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# perfiles_activos -> un perfil por línea, los que tienen proceso de OpenVPN
# vivo ahora mismo. Es lo que consulta 'seclab vpn list/status' y también
# vpn_perfiles_activos() en lib/docker.sh (mismo patrón que servicios_activos()
# leyendo /run/seclab/servicios): el host pregunta al contenedor en vez de
# llevar la cuenta por su lado.
perfiles_activos() {
    local p
    for p in $PERFILES_VALIDOS; do
        proceso_vivo "$p" && printf '%s\n' "$p"
    done
    return 0
}

# solapan_rangos RANGOS_A RANGOS_B -> 0 si algún CIDR de A se solapa con
# alguno de B. Mismo criterio que usaba lib/vpn.sh en el diseño anterior:
# módulo `ipaddress` de Python, ya presente en la imagen (paquetes-lite.txt).
solapan_rangos() {
    python3 -c '
import ipaddress, sys

def redes(csv):
    out = []
    for trozo in csv.split(","):
        trozo = trozo.strip()
        if not trozo:
            continue
        try:
            out.append(ipaddress.ip_network(trozo, strict=False))
        except ValueError:
            pass
    return out

a, b = redes(sys.argv[1]), redes(sys.argv[2])
for ra in a:
    for rb in b:
        if ra.overlaps(rb):
            sys.exit(0)
sys.exit(1)
' "$1" "$2"
}

# deshacer_killswitch PERFIL DEV -> retira exactamente las reglas de iptables
# que instaló 'up' para ese perfil, a partir de los rangos que quedaron
# anotados en su estado. Los `|| true`: si una regla ya no está (por ejemplo,
# tras un `down` repetido), no es un error.
deshacer_killswitch() {
    local perfil="$1" dev="$2" archivo="$(dir_estado "$1")/rangos-declarados" r
    if [ -f "$archivo" ]; then
        while IFS= read -r r; do
            [ -n "$r" ] || continue
            iptables -D OUTPUT -d "$r" ! -o "$dev" -j DROP 2>/dev/null || true
            iptables -D FORWARD -d "$r" ! -o "$dev" -j DROP 2>/dev/null || true
        done < "$archivo"
    fi
    iptables -D INPUT -i "$dev" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i "$dev" -m conntrack --ctstate NEW -j DROP 2>/dev/null || true
}

# limpiar_restos PERFIL -> deja el perfil como si nunca se hubiera levantado:
# retira sus reglas, su PID viejo y su directorio de estado. Se usa antes de
# un 'up' cuando el proceso anterior murió sin pasar por 'down' (un `kill -9`,
# o un fallo de OpenVPN), para no acumular reglas de iptables huérfanas.
limpiar_restos() {
    local perfil="$1" dev
    dev="$(interfaz_de "$perfil")"
    deshacer_killswitch "$perfil" "$dev"
    rm -f "$(pid_de "$perfil")"
    rm -rf "$(dir_estado "$perfil")"
}

# -----------------------------------------------------------------------------
# up PERFIL
# -----------------------------------------------------------------------------
sub_up() {
    local perfil="${1:-}"
    exigir_perfil_valido "$perfil"
    install -d -m 0755 "$ESTADO"

    if proceso_vivo "$perfil"; then
        log "El perfil '${perfil}' ya está activo."
        sub_status "$perfil"
        return 0
    fi
    limpiar_restos "$perfil"

    local dir="$(dir_perfil "$perfil")" env_archivo
    env_archivo="${dir}/perfil.env"
    [ -f "$env_archivo" ] || fallo \
        "No existe perfil.env en ${dir}." \
        "No se ha levantado nada." \
        "En el host: copia templates/vpn/${perfil}/perfil.env.example a vpn/${perfil}/perfil.env y ajústalo."

    local nombre config_rel rangos dns creds_rel ruta_defecto
    nombre="$(leer_env "$perfil" SECLAB_VPN_NOMBRE)"
    config_rel="$(leer_env "$perfil" SECLAB_VPN_CONFIG)"
    rangos="$(leer_env "$perfil" SECLAB_VPN_RANGOS)"
    dns="$(leer_env "$perfil" SECLAB_VPN_DNS)"
    creds_rel="$(leer_env "$perfil" SECLAB_VPN_CREDENCIALES)"
    ruta_defecto="$(leer_env "$perfil" SECLAB_VPN_RUTA_DEFECTO)"

    [ -n "$config_rel" ] || fallo \
        "SECLAB_VPN_CONFIG no está definido en ${env_archivo}." \
        "No hay nada que conectar." \
        "Indica el nombre del .ovpn que colocaste en vpn/${perfil}/ (en el host)."

    local ovpn="${dir}/${config_rel}"
    [ -f "$ovpn" ] || fallo \
        "No se encuentra el archivo declarado en SECLAB_VPN_CONFIG (${config_rel})." \
        "No hay nada que conectar." \
        "Colócalo en vpn/${perfil}/ (en el host)."

    [ -n "$rangos" ] || fallo \
        "SECLAB_VPN_RANGOS está vacío en ${env_archivo}." \
        "Con --route-nopull y sin rangos declarados, el túnel no enrutaría nada." \
        "Conecta manualmente una vez para ver qué negocia la plataforma, o consulta docs/vpn.md."

    # --- Solapamiento con perfiles ya activos --------------------------------
    local otro rangos_otro
    for otro in $(perfiles_activos); do
        [ "$otro" = "$perfil" ] && continue
        rangos_otro="$(leer_env "$otro" SECLAB_VPN_RANGOS)"
        if [ -n "$rangos_otro" ] && solapan_rangos "$rangos" "$rangos_otro"; then
            fallo "Los rangos de '${perfil}' (${rangos}) se solapan con los de '${otro}' (${rangos_otro}), que ya está activo." \
                  "Con rangos solapados no hay forma de decidir por qué túnel debe salir un paquete." \
                  "Baja '${otro}' con 'seclab-vpn down ${otro}', o ajusta los rangos para que no se solapen."
        fi
    done

    local dev="$(interfaz_de "$perfil")"
    install -d -m 0755 "$(dir_estado "$perfil")"
    log "Perfil: ${nombre:-(sin nombre)} · interfaz: ${dev}"

    # --- Killswitch de salida: se instala ANTES de levantar el túnel --------
    # Fail-closed: cualquier paquete hacia un rango declarado que no salga por
    # la interfaz de ESTE perfil se descarta. Cubre el arranque (todavía no hay
    # interfaz) y una caída posterior (la ruta desaparece, y sin esta regla el
    # paquete probaría la interfaz normal del contenedor).
    IFS=',' read -r -a rangos_arr <<< "$rangos"
    local rangos_validos=() r
    for r in "${rangos_arr[@]}"; do
        r="$(printf '%s' "$r" | tr -d '[:space:]')"
        [ -z "$r" ] && continue
        python3 -c "import ipaddress,sys; ipaddress.ip_network(sys.argv[1], strict=False)" "$r" 2>/dev/null || \
            fallo "Rango inválido en SECLAB_VPN_RANGOS de '${perfil}': '${r}'" \
                  "No se ha levantado nada." \
                  "Usa notación CIDR, por ejemplo 10.10.10.0/24."
        iptables -A OUTPUT -d "$r" ! -o "$dev" -j DROP
        iptables -A FORWARD -d "$r" ! -o "$dev" -j DROP
        rangos_validos+=("$r")
    done
    [ "${#rangos_validos[@]}" -gt 0 ] || fallo \
        "Ningún rango de SECLAB_VPN_RANGOS de '${perfil}' es una red válida." \
        "No se ha levantado nada." \
        "Revisa el formato en ${env_archivo}."

    printf '%s\n' "${rangos_validos[@]}" > "$(dir_estado "$perfil")/rangos-declarados"

    # --- Killswitch de entrada: mitiga a "los jugadores en tun0 me pueden
    # alcanzar" -------------------------------------------------------------
    # Cualquiera que comparta la misma VPN de plataforma comparte también, de
    # su lado, la interfaz del túnel. Sin esta regla, nada impide que abran
    # una conexión NUEVA hacia un servicio de 'lab' a través de ese túnel. Las
    # respuestas a conexiones que 'lab' inicia sí se permiten
    # (ESTABLISHED,RELATED): esto es sobre por qué interfaz ENTRA una conexión,
    # nunca sobre a qué IP te conectas tú dentro del rango.
    iptables -A INPUT -i "$dev" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i "$dev" -m conntrack --ctstate NEW -j DROP

    log "Killswitch instalado para: ${rangos_validos[*]} (interfaz ${dev}, entrada y salida)"

    # --- Argumentos de OpenVPN -----------------------------------------------
    local args=(
        --config "$ovpn"
        --dev "$dev" --dev-type tun
        --route-nopull
        --script-security 2
        --up "${GANCHO} up ${perfil}"
        --down "${GANCHO} down ${perfil}"
        --daemon "seclab-vpn-${perfil}"
        --writepid "$(pid_de "$perfil")"
        --log "$(log_de "$perfil")"
    )

    for r in "${rangos_validos[@]}"; do
        # openvpn --route quiere "red máscara", no notación CIDR.
        local red_y_mascara
        red_y_mascara="$(python3 -c '
import ipaddress, sys
n = ipaddress.ip_network(sys.argv[1], strict=False)
print(n.network_address, n.netmask)
' "$r")"
        # shellcheck disable=SC2206  # se quiere el split en dos palabras a propósito
        args+=(--route ${red_y_mascara})
    done

    if [ -n "$creds_rel" ]; then
        local creds="${dir}/${creds_rel}"
        [ -f "$creds" ] || fallo \
            "SECLAB_VPN_CREDENCIALES declara '${creds_rel}' pero el archivo no existe." \
            "No se ha levantado nada." \
            "Colócalo en vpn/${perfil}/ (en el host) con permisos 600."
        args+=(--auth-user-pass "$creds")
    fi

    if [ -n "$dns" ]; then
        log "DNS declarado en perfil.env (no se imprime aquí el valor)."
        log "SecLab no lo aplica automáticamente al resolver del sistema: ver límites reales por plataforma en docs/vpn.md."
    fi

    if [ "$ruta_defecto" = "true" ]; then
        log "AVISO: SECLAB_VPN_RUTA_DEFECTO=true para '${perfil}'. Override consciente: todo el tráfico del contenedor podría salir por este túnel."
        args+=(--redirect-gateway def1)
    fi

    log "Arrancando OpenVPN en segundo plano (PID en $(pid_de "$perfil"), log en $(log_de "$perfil"))"
    if ! openvpn "${args[@]}"; then
        deshacer_killswitch "$perfil" "$dev"
        rm -rf "$(dir_estado "$perfil")"
        fallo "OpenVPN no ha podido arrancar para '${perfil}'." \
              "El perfil no ha quedado activo." \
              "Revisa 'seclab-vpn logs ${perfil}'."
    fi

    # --daemon deja el proceso en segundo plano de inmediato; se espera aquí a
    # que el gancho --up confirme el túnel arriba (hasta 60 s), igual que antes
    # hacía 'seclab vpn up' desde el host.
    local intentos=0
    while [ "$intentos" -lt 30 ]; do
        [ -f "$(dir_estado "$perfil")/arriba" ] && break
        proceso_vivo "$perfil" || break
        sleep 2
        intentos=$(( intentos + 1 ))
    done

    if [ -f "$(dir_estado "$perfil")/arriba" ]; then
        log "Túnel de '${perfil}' arriba."
    elif proceso_vivo "$perfil"; then
        log "AVISO: el túnel de '${perfil}' no ha confirmado estar arriba en 60 s; el proceso sigue vivo."
        log "Puede seguir negociando. Revisa la causa con: seclab-vpn logs ${perfil}"
    else
        deshacer_killswitch "$perfil" "$dev"
        rm -rf "$(dir_estado "$perfil")"
        fallo "OpenVPN de '${perfil}' murió antes de levantar el túnel." \
              "No ha quedado activo." \
              "Revisa 'seclab-vpn logs ${perfil}'. Si no era el .ovpn correcto, corrígelo y repite."
    fi
}

# -----------------------------------------------------------------------------
# down [PERFIL]
# -----------------------------------------------------------------------------
sub_down_uno() {
    local perfil="$1" dev pid
    dev="$(interfaz_de "$perfil")"

    if ! proceso_vivo "$perfil"; then
        log "El perfil '${perfil}' no estaba activo."
        limpiar_restos "$perfil"
        return 0
    fi

    pid="$(cat "$(pid_de "$perfil")" 2>/dev/null || true)"
    log "Deteniendo OpenVPN de '${perfil}' (PID ${pid})"
    kill -TERM "$pid" 2>/dev/null || true

    local intentos=0
    while kill -0 "$pid" 2>/dev/null && [ "$intentos" -lt 15 ]; do
        sleep 1
        intentos=$(( intentos + 1 ))
    done
    if kill -0 "$pid" 2>/dev/null; then
        log "AVISO: '${perfil}' no respondió a TERM en 15 s; se fuerza con KILL."
        kill -KILL "$pid" 2>/dev/null || true
    fi

    deshacer_killswitch "$perfil" "$dev"
    rm -f "$(pid_de "$perfil")"
    rm -rf "$(dir_estado "$perfil")"
    log "Perfil '${perfil}' desactivado."
}

sub_down() {
    local perfil="${1:-}"
    if [ -n "$perfil" ]; then
        exigir_perfil_valido "$perfil"
        sub_down_uno "$perfil"
        return 0
    fi

    local p encontrado=false
    for p in $PERFILES_VALIDOS; do
        if proceso_vivo "$p"; then
            encontrado=true
            sub_down_uno "$p"
        fi
    done
    [ "$encontrado" = true ] || log "Ningún perfil de VPN activo."
}

# -----------------------------------------------------------------------------
# status [PERFIL]
# -----------------------------------------------------------------------------
sub_status() {
    local filtro="${1:-}" p
    for p in $PERFILES_VALIDOS; do
        [ -n "$filtro" ] && [ "$p" != "$filtro" ] && continue

        printf 'Perfil: %s\n' "$p"
        local dir="$(dir_perfil "$p")"
        if [ ! -f "${dir}/perfil.env" ]; then
            printf '  Estado: no configurado (falta vpn/%s/perfil.env en el host)\n\n' "$p"
            continue
        fi

        if ! proceso_vivo "$p"; then
            printf '  Estado: inactivo\n\n'
            continue
        fi

        local est="$(dir_estado "$p")"
        if [ -f "${est}/arriba" ]; then
            printf '  Estado: arriba\n'
        else
            printf '  Estado: caído (killswitch activo)\n'
        fi
        printf '  Interfaz: %s\n' "$(cat "${est}/interfaz" 2>/dev/null || printf -- '—')"
        printf '  IP del túnel: %s\n' "$(cat "${est}/ip" 2>/dev/null || printf -- '—')"
        local declarados efectivos
        declarados="$(leer_env "$p" SECLAB_VPN_RANGOS)"
        efectivos="$(cat "${est}/rangos" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || true)"
        printf '  Rangos efectivos: %s\n' "${efectivos:-—}"
        printf '  Conectado desde: %s\n' "$(cat "${est}/desde" 2>/dev/null || printf -- '—')"
        if [ -n "$declarados" ] && [ -n "$efectivos" ] && [ "$declarados" != "$efectivos" ]; then
            printf '  AVISO: los rangos declarados en perfil.env (%s) no coinciden con los efectivos (%s).\n' \
                "$declarados" "$efectivos"
        fi
        printf '\n'
    done
}

# -----------------------------------------------------------------------------
# routes
# -----------------------------------------------------------------------------
sub_routes() {
    ip route show
}

# -----------------------------------------------------------------------------
# logs PERFIL
# -----------------------------------------------------------------------------
sub_logs() {
    local perfil="${1:-}"
    exigir_perfil_valido "$perfil"
    local archivo="$(log_de "$perfil")"
    [ -f "$archivo" ] || fallo \
        "No hay registro todavía para '${perfil}'." \
        "" \
        "Levántalo con: seclab-vpn up ${perfil}"
    tail -n 100 "$archivo"
}

# -----------------------------------------------------------------------------
# activos — salida interna, en bruto, para lib/docker.sh (host)
# -----------------------------------------------------------------------------
sub_activos() { perfiles_activos; }

main() {
    local sub="${1:-ayuda}"
    shift || true
    case "$sub" in
        up)      exigir_root "levantar un túnel"; sub_up "$@" ;;
        down)    exigir_root "bajar un túnel"; sub_down "$@" ;;
        status)  sub_status "$@" ;;
        routes)  sub_routes "$@" ;;
        logs)    sub_logs "$@" ;;
        activos) sub_activos ;;
        ayuda|-h|--help)
            cat >&2 <<AYUDA
seclab-vpn — gestor interno de VPN (dentro de 'lab', Fase 7)

  up PERFIL       Levanta el túnel de ese perfil (necesita root)
  down [PERFIL]   Baja ese perfil, o todos los activos si se omite (necesita root)
  status [PERFIL] Estado de uno o de todos los perfiles conocidos
  routes          'ip route show' del contenedor
  logs PERFIL     Últimas 100 líneas del registro de OpenVPN de ese perfil
  activos         Uso interno: un perfil activo por línea

Perfiles válidos: ${PERFILES_VALIDOS}
AYUDA
            ;;
        *) fallo "Subcomando no reconocido: ${sub}" \
                  "No se ha hecho nada." \
                  "Ejecuta 'seclab-vpn ayuda'." ;;
    esac
}

main "$@"
