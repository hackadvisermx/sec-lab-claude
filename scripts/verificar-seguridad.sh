#!/usr/bin/env bash
# =============================================================================
# SecLab — revisión de seguridad de la configuración
# =============================================================================
# Comprueba lo que protege al usuario y a su máquina:
#   - que ningún secreto pueda llegar a Git
#   - que no haya contraseñas de relleno ni secretos vacíos
#   - que los servicios no queden expuestos a la red sin querer
#   - que los permisos de los archivos sensibles sean estrictos
#
# NO comprueba contra qué objetivos se usan las herramientas: eso queda fuera
# del alcance de SecLab (ver docs/uso-autorizado.md).
#
# Salida: 0 si no hay fallos. 1 si hay al menos un FALLO.
# Los AVISOs no hacen fallar la revisión.
# =============================================================================

set -euo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RAIZ
# shellcheck source=../lib/comun.sh
. "${RAIZ}/lib/comun.sh"

cd "$RAIZ"

n_fallos=0
n_avisos=0

pasa()  { printf '%s\n' "  ${C_VERDE}✓${C_FIN} $*" >&2; }
falla() { printf '%s\n' "  ${C_ROJO}✗ FALLO${C_FIN} $1" >&2
          [ -n "${2:-}" ] && printf '%s\n' "${C_GRIS}      → $2${C_FIN}" >&2
          n_fallos=$((n_fallos + 1)); }
avisa() { printf '%s\n' "  ${C_AMARILLO}!${C_FIN} $1" >&2
          [ -n "${2:-}" ] && printf '%s\n' "${C_GRIS}      → $2${C_FIN}" >&2
          n_avisos=$((n_avisos + 1)); }

hay_git() { [ -d .git ] && existe_comando git; }

# -----------------------------------------------------------------------------
titulo "1. Protección de secretos frente a Git"
# -----------------------------------------------------------------------------
if [ ! -f .gitignore ]; then
    falla "No existe .gitignore." "Créalo antes de inicializar el repositorio."
else
    faltan=""
    for patron in '.env' '*.pem' '*.key' '*.ovpn' '/vpn/' '/workspace/' '/terraform/**/*.tfvars'; do
        if ! grep -qxF "$patron" .gitignore; then
            faltan="${faltan} ${patron}"
        fi
    done
    if [ -n "$faltan" ]; then
        falla "Faltan patrones en .gitignore:${faltan}" \
              "Añádelos antes de hacer el primer commit."
    else
        pasa ".gitignore cubre secretos, VPN, workspace y estado de Terraform"
    fi
fi

if hay_git; then
    versionados="$(git ls-files -- '*.env' '.env' '*.pem' '*.key' '*.p12' '*.pfx' '*.ovpn' 'vpn/**' 'workspace/**')"
    if [ -n "$versionados" ]; then
        falla "Hay archivos sensibles versionados en Git:" \
              "$(printf '%s' "$versionados" | tr '\n' ' ')"
        printf '%s\n' "${C_GRIS}      → Sácalos del índice: git rm --cached <archivo>${C_FIN}" >&2
    else
        pasa "Git no está siguiendo ningún archivo sensible"
    fi
else
    avisa "Este directorio todavía no es un repositorio Git." \
          "Ejecuta 'git init' para que .gitignore empiece a protegerte."
fi

# -----------------------------------------------------------------------------
titulo "2. Secretos en .env"
# -----------------------------------------------------------------------------
if [ ! -f .env ]; then
    avisa "No existe .env todavía." \
          "Lo creará 'seclab init' a partir de .env.example."
else
    # Cada secreto pertenece a un servicio. Un secreto vacío sólo es un fallo si
    # su servicio está habilitado: exigir la clave de Tailscale a quien no usa
    # Tailscale sería ruido, y el ruido acaba enseñando a ignorar los avisos.
    # Es el mismo criterio que el healthcheck: lo apagado no se evalúa.
    #
    # Un valor de relleno, en cambio, es un fallo siempre: si está escrito, es
    # que alguien pensaba usarlo.
    servicio_de_secreto() {
        case "$1" in
            SECLAB_VNC_PASSWORD)     echo SECLAB_HABILITAR_DESKTOP ;;
            SECLAB_CODE_PASSWORD)    echo SECLAB_HABILITAR_CODE ;;
            SECLAB_JUPYTER_TOKEN)    echo SECLAB_HABILITAR_JUPYTER ;;
            SECLAB_MCP_TOKEN)        echo SECLAB_HABILITAR_MCP ;;
            TAILSCALE_AUTH_KEY)      echo SECLAB_HABILITAR_TAILSCALE ;;
            *)                       echo "" ;;
        esac
    }

    valor_env() { grep -m1 "^${1}=" .env 2>/dev/null | cut -d= -f2-; }

    inseguros=""
    faltantes=""
    inactivos=0

    for clave in SECLAB_VNC_PASSWORD SECLAB_CODE_PASSWORD SECLAB_JUPYTER_TOKEN \
                 SECLAB_MCP_TOKEN TAILSCALE_AUTH_KEY; do
        valor="$(valor_env "$clave")"
        interruptor="$(servicio_de_secreto "$clave")"
        activo="$(valor_env "$interruptor")"

        if [ -z "$valor" ]; then
            if [ "$activo" = "true" ]; then
                faltantes="${faltantes} ${clave}"
            else
                inactivos=$((inactivos + 1))
            fi
            continue
        fi
        if es_secreto_inseguro "$valor"; then
            inseguros="${inseguros} ${clave}"
        fi
    done

    if [ -n "$faltantes" ]; then
        falla "Servicios habilitados sin secreto:${faltantes}" \
              "SecLab se negará a arrancar. Ejecuta 'seclab init --regenerar-secretos'."
    fi
    if [ -n "$inseguros" ]; then
        falla "Secretos con valor de relleno o demasiado corto:${inseguros}" \
              "Regenéralos con 'seclab init --regenerar-secretos'."
    fi
    if [ -z "$faltantes" ] && [ -z "$inseguros" ]; then
        pasa "Los secretos de los servicios activos son válidos"
        [ "$inactivos" -gt 0 ] && \
            detalle "${inactivos} secreto(s) vacío(s) de servicios desactivados: correcto, no se evalúan."
    fi

    # La llave pública SSH no es opcional en ningún perfil: sin ella el
    # contenedor aborta el arranque, porque no hay acceso por contraseña.
    if [ -z "$(valor_env SECLAB_SSH_PUBKEY)" ]; then
        falla "No hay SECLAB_SSH_PUBKEY en .env." \
              "El contenedor no arrancará. Ejecuta 'seclab init'."
    else
        pasa "Llave pública SSH configurada"
    fi
fi

# -----------------------------------------------------------------------------
titulo "3. Permisos de archivos sensibles"
# -----------------------------------------------------------------------------
permisos_de() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }

comprobar_permisos() {
    local ruta="$1" esperado="$2" actual
    [ -e "$ruta" ] || return 0
    actual="$(permisos_de "$ruta")"
    if [ "$actual" != "$esperado" ]; then
        falla "${ruta} tiene permisos ${actual}, se esperaban ${esperado}." \
              "Corrige con: chmod ${esperado} ${ruta}"
    else
        pasa "${ruta} → ${actual}"
    fi
}

comprobar_permisos .env 600
comprobar_permisos vpn 700
for perfil in vpnhtb vpntry vpncli; do
    comprobar_permisos "vpn/${perfil}" 700
done
if [ -d vpn ]; then
    while IFS= read -r archivo; do
        comprobar_permisos "$archivo" 600
    done < <(find vpn -type f \( -name '*.ovpn' -o -name '*.creds' -o -name 'perfil.env' \))
else
    avisa "No existe el directorio vpn/ todavía." \
          "Lo creará 'seclab init' (Fase 2) desde templates/vpn/."
fi

# La llave SSH del laboratorio: ssh se niega a usar una privada con permisos
# abiertos, así que unos permisos flojos aquí no son teóricos, rompen el acceso.
comprobar_permisos secretos 700
if [ -d secretos ]; then
    while IFS= read -r archivo; do
        comprobar_permisos "$archivo" 600
    done < <(find secretos -type f ! -name '*.pub')
fi

# Las copias de seguridad llevan .env y la llave SSH en claro dentro. Una copia
# legible por cualquier usuario de la máquina entrega el laboratorio completo,
# y es fácil que pase: basta restaurarla o moverla con otra umask.
if [ -d backups ]; then
    while IFS= read -r archivo; do
        comprobar_permisos "$archivo" 600
    done < <(find backups -type f -name 'seclab-*.tar.gz')
fi

# -----------------------------------------------------------------------------
titulo "4. Exposición de servicios en Docker Compose"
# -----------------------------------------------------------------------------
# Se revisan TODOS los archivos de composición que el CLI puede aplicar, no
# sólo los que Compose carga por defecto. El override del escritorio publica
# tres puertos más, y revisar sin él daría por segura una configuración que en
# el perfil `desktop` expone bastante más.
archivos_compose=(-f "${RAIZ}/docker-compose.yml")
[ -f "${RAIZ}/docker-compose.override.yml" ] && \
    archivos_compose+=(-f "${RAIZ}/docker-compose.override.yml")
[ -f "${RAIZ}/docker-compose.desktop.yml" ] && \
    archivos_compose+=(-f "${RAIZ}/docker-compose.desktop.yml")
# El override de VPN (Fase 7) se valida también aquí. Con el diseño actual no
# depende de ningún estado en .env para resolver: sólo añade a 'lab' NET_ADMIN
# y /dev/net/tun, así que la composición es válida siempre, haya o no un
# túnel realmente activo dentro del contenedor.
[ -f "${RAIZ}/docker-compose.vpn.yml" ] && \
    archivos_compose+=(-f "${RAIZ}/docker-compose.vpn.yml")

if ! existe_comando docker; then
    avisa "Docker no está instalado; no se puede analizar la configuración de Compose."
elif ! ( cd "$RAIZ" && docker compose "${archivos_compose[@]}" config --quiet ) 2>/dev/null; then
    falla "La configuración de Compose no es válida." \
          "Revisa el error con: docker compose config"
else
    # El array lleva dos elementos por archivo (-f y la ruta).
    pasa "La configuración de Compose es válida ($(( ${#archivos_compose[@]} / 2 )) archivos revisados, incluido el override del escritorio)"
    if salida="$( ( cd "$RAIZ" && docker compose "${archivos_compose[@]}" config --format json ) 2>/dev/null | python3 "${RAIZ}/scripts/analizar-compose.py")"; then
        pasa "Sin puertos expuestos a la red, privilegios elevados ni nombres de contenedor fijos"
    else
        falla "La configuración de Compose expone la máquina más de lo necesario:"
        printf '%s\n' "$salida" >&2
    fi
fi

# docker-compose.tailscale.yml (Fase 9, opcional) se analiza APARTE, nunca
# combinado con los archivos de arriba: por diseño vive en su propio proyecto
# de Compose (${SECLAB_PROJECT}-tailscale), independiente del de 'lab' — ver
# docs/tailscale.md. Combinarlo aquí sería analizar una composición que el
# CLI nunca aplica junta de verdad.
if [ -f "${RAIZ}/docker-compose.tailscale.yml" ]; then
    if ! existe_comando docker; then
        : # ya avisado arriba
    elif ! ( cd "$RAIZ" && docker compose -f docker-compose.tailscale.yml config --quiet ) 2>/dev/null; then
        falla "La configuración de docker-compose.tailscale.yml no es válida." \
              "Revisa el error con: docker compose -f docker-compose.tailscale.yml config"
    else
        pasa "docker-compose.tailscale.yml es válido (proyecto propio, no combinado con 'lab')"
        if salida_ts="$( ( cd "$RAIZ" && docker compose -f docker-compose.tailscale.yml config --format json ) 2>/dev/null | python3 "${RAIZ}/scripts/analizar-compose.py")"; then
            pasa "Tailscale sin puertos expuestos, privilegios elevados ni nombre de contenedor fijo"
        else
            falla "docker-compose.tailscale.yml expone la máquina más de lo necesario:"
            printf '%s\n' "$salida_ts" >&2
        fi
    fi
fi

# -----------------------------------------------------------------------------
titulo "5. Rastro de secretos en archivos del repositorio"
# -----------------------------------------------------------------------------
patrones='BEGIN (RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY|tskey-auth-[A-Za-z0-9]|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{32}'
if hay_git; then
    archivos="$(git ls-files)"
else
    archivos="$(find . -type f -not -path './.git/*' -not -path './vpn/*' -not -path './workspace/*' -not -name '*.md')"
fi
encontrados=""
while IFS= read -r archivo; do
    [ -f "$archivo" ] || continue
    if grep -Eq "$patrones" "$archivo" 2>/dev/null; then
        encontrados="${encontrados} ${archivo}"
    fi
done <<< "$archivos"

if [ -n "$encontrados" ]; then
    falla "Posibles secretos en:${encontrados}" \
          "Revísalos y sácalos del repositorio antes de compartirlo."
else
    pasa "Sin claves privadas ni tokens reconocibles en los archivos del repositorio"
fi
detalle "Esta comprobación es un primer filtro. La CI de la Fase 8 añade gitleaks."

# -----------------------------------------------------------------------------
titulo "Resultado"
# -----------------------------------------------------------------------------
if [ "$n_fallos" -gt 0 ]; then
    printf '%s\n\n' "${C_ROJO}${n_fallos} fallo(s)${C_FIN} y ${n_avisos} aviso(s). Corrige los fallos antes de continuar." >&2
    exit 1
fi
printf '%s\n\n' "${C_VERDE}Sin fallos${C_FIN} y ${n_avisos} aviso(s)." >&2
exit 0
