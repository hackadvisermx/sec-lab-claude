#!/usr/bin/env bash
# =============================================================================
# SecLab — reproducción automatizada del test de VPN de la Fase 7 (CI, Fase 8)
# =============================================================================
# Reproduce en CI, contra un servidor OpenVPN local y efímero (nunca HTB ni
# TryHackMe), el mismo procedimiento que se verificó a mano en la Fase 7 (ver
# TESTING_GAPS.md): modo de clave estática (--secret, con
# --allow-deprecated-insecure-static-crypto y cipher AES-256-CBC, porque
# OpenVPN 2.7 ya no acepta BF-CBC por defecto).
#
# Cubre, en este orden, exactamente lo que exige prompt_v3.md sección "CI/CD":
#   1. SECLAB_HABILITAR_VPN=false  -> 'lab' arranca SIN NET_ADMIN ni /dev/net/tun
#   2. SECLAB_HABILITAR_VPN=true   -> 'lab' se recrea CON esas dos concesiones
#   3. 'seclab vpn up vpnhtb'      -> rutas EXACTAMENTE las declaradas,
#                                      ninguna ruta por defecto secuestrada
#   4. 'seclab vpn up vpncli' con rango solapado -> rechazado, vpnhtb no se toca
#   5. Se detiene el servidor de prueba -> killswitch: el túnel cae, la ruta
#      desaparece, pero las reglas DROP de iptables para el rango declarado
#      SIGUEN presentes
#
# Se ejecuta sobre el propio checkout (pensado para un runner de CI efímero,
# nunca sobre una instalación de desarrollo con vpn/ o .env reales: por eso
# aborta si ya existe .env, igual que preparar-env.sh). Limpia todo lo que
# crea, incluso si algo falla a medias (trap EXIT).
# =============================================================================

set -uo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$RAIZ" || exit 1

# shellcheck source=../../lib/secretos.sh
. "${RAIZ}/lib/secretos.sh"

PROYECTO="seclabvpnci"
# El servidor OpenVPN de prueba TIENE que estar en la MISMA red Docker que
# 'lab' (la que declara docker-compose.yml: 'networks: seclab: name:
# ${SECLAB_PROJECT}-net'), o 'lab' no podría resolver ni alcanzar
# "${SERVIDOR}:1195" por el DNS embebido de Docker. Por eso RED usa
# exactamente ese mismo nombre a propósito, en vez de una red aparte: no es
# una fuga de aislamiento (sigue siendo una red de prueba efímera, propia de
# este proyecto de Compose y de ningún otro), es la única forma de que el
# cliente dentro de 'lab' vea al servidor de prueba. La red la crea
# 'docker compose up -d lab' (paso 1, más abajo); aquí sólo se reutiliza.
RED="${PROYECTO}-net"
SERVIDOR="${PROYECTO}-servidor"
DIR_SERVIDOR="$(mktemp -d)"
FALLOS=0

log() { printf '\n>>> %s\n' "$1" >&2; }
pasa() { printf '  OK  %s\n' "$1" >&2; }
falla() { printf '  FALLO  %s\n' "$1" >&2; FALLOS=$((FALLOS + 1)); }

limpiar() {
    log "Limpiando recursos de la prueba"
    ./bin/seclab vpn down >/dev/null 2>&1 || true
    docker compose -f docker-compose.yml -f docker-compose.vpn.yml down --volumes --remove-orphans >/dev/null 2>&1 || true
    docker rm -f "$SERVIDOR" >/dev/null 2>&1 || true
    docker network rm "$RED" >/dev/null 2>&1 || true
    rm -rf "$DIR_SERVIDOR"
    rm -f ./ci-ssh-key ./ci-ssh-key.pub
    rm -rf ./vpn ./workspace ./backups ./secretos ./.env
}
trap limpiar EXIT

# --- Preparación -------------------------------------------------------------
log "Preparando .env e imagen"
"${RAIZ}/scripts/ci/preparar-env.sh" "$PROYECTO" 2399
# Siempre se (re)construye: garantiza que SECLAB_IMAGE en .env, calculado más
# abajo por 'seclab start', coincide con una imagen que existe de verdad. La
# caché de capas de Docker hace que un build repetido sin cambios sea barato.
./bin/seclab image build --profile lite

# --- 1. Arranque SIN SECLAB_HABILITAR_VPN -----------------------------------
log "1. Arrancando 'lab' con SECLAB_HABILITAR_VPN=false"
./bin/seclab start --profile lite
cap_add="$(docker inspect "${PROYECTO}-lab-1" --format '{{.HostConfig.CapAdd}}')"
if printf '%s' "$cap_add" | grep -q NET_ADMIN; then
    falla "'lab' NO debería tener NET_ADMIN con SECLAB_HABILITAR_VPN=false"
else
    pasa "'lab' arranca sin NET_ADMIN cuando SECLAB_HABILITAR_VPN=false"
fi

# --- Servidor OpenVPN de prueba (clave estática) -----------------------------
log "Creando servidor OpenVPN de prueba en la red de 'lab' (modo --secret, efímero, local)"
IMG="$(grep -m1 '^SECLAB_IMAGE=' .env | cut -d= -f2-)"
# 'docker compose up -d lab' ya creó esta red (paso 1): no se vuelve a crear,
# sólo se comprueba que existe. Si no existiera algo ha ido mal antes y es
# mejor abortar aquí, con un mensaje claro, que seguir con un servidor de
# prueba en una red que 'lab' nunca podría alcanzar.
if ! docker network inspect "$RED" >/dev/null 2>&1; then
    echo "ERROR: la red '${RED}' no existe; ¿arrancó 'lab' correctamente en el paso 1?" >&2
    exit 1
fi
# --user "$(id -u):$(id -g)": sin esto, el archivo lo escribe el usuario por
# defecto de la imagen (seclab, uid 1000) en el bind mount, y en un runner
# Linux real (uid del usuario 'runner' normalmente distinto de 1000) el `cp`
# de más abajo falla con "Permission denied" — encontrado ejecutando esto
# por primera vez en un runner de CI real, nunca visto en macOS/Docker
# Desktop, donde el mapeo de UID del volumen enmascaraba el problema.
docker run --rm --user "$(id -u):$(id -g)" --entrypoint /usr/sbin/openvpn -v "${DIR_SERVIDOR}:/k" "$IMG" --genkey secret /k/ta.key
# `--genkey secret` la crea en 600: la propia imagen del servidor (más abajo)
# corre como el usuario 'seclab' de la imagen, no como el UID del runner que
# acaba de crear el archivo, así que sin esto el servidor tampoco podría
# leerla. Es una clave de prueba desechable de este único job de CI, sin
# ninguna sensibilidad real: ampliar sus permisos aquí no expone nada.
chmod 644 "${DIR_SERVIDOR}/ta.key"
cat > "${DIR_SERVIDOR}/servidor.conf" <<EOF
dev tun-srv
dev-type tun
proto udp
port 1195
secret /k/ta.key
cipher AES-256-CBC
allow-deprecated-insecure-static-crypto
ifconfig 10.9.9.1 10.9.9.2
verb 3
keepalive 5 15
EOF
IMG="$(grep -m1 '^SECLAB_IMAGE=' .env | cut -d= -f2-)"
docker run -d --name "$SERVIDOR" --network "$RED" \
    --cap-add NET_ADMIN --device /dev/net/tun \
    --entrypoint /usr/sbin/openvpn \
    -v "${DIR_SERVIDOR}:/k" "$IMG" --config /k/servidor.conf
sleep 2

# --- Perfil vpnhtb apuntando al servidor de prueba --------------------------
cp "${DIR_SERVIDOR}/ta.key" vpn/vpnhtb/ta.key
cat > vpn/vpnhtb/cliente.ovpn <<EOF
dev tun
dev-type tun
proto udp
remote ${SERVIDOR} 1195
secret /etc/seclab/vpn/vpnhtb/ta.key
cipher AES-256-CBC
allow-deprecated-insecure-static-crypto
ifconfig 10.9.9.2 10.9.9.1
ping 5
ping-restart 15
resolv-retry infinite
verb 3
EOF
chmod 600 vpn/vpnhtb/ta.key vpn/vpnhtb/cliente.ovpn
cat > vpn/vpnhtb/perfil.env <<'EOF'
SECLAB_VPN_NOMBRE="Servidor de prueba CI (vpnhtb)"
SECLAB_VPN_CONFIG="cliente.ovpn"
SECLAB_VPN_RANGOS="10.61.1.0/24"
SECLAB_VPN_DNS=""
EOF
chmod 600 vpn/vpnhtb/perfil.env

# --- 2. Habilitar la VPN y recrear 'lab' con NET_ADMIN/tun ------------------
log "2. Habilitando SECLAB_HABILITAR_VPN y recreando 'lab'"
escribir_variable .env SECLAB_HABILITAR_VPN true
docker compose -f docker-compose.yml -f docker-compose.vpn.yml up -d lab
sleep 8
cap_add="$(docker inspect "${PROYECTO}-lab-1" --format '{{.HostConfig.CapAdd}}')"
devices="$(docker inspect "${PROYECTO}-lab-1" --format '{{.HostConfig.Devices}}')"
if printf '%s' "$cap_add" | grep -q NET_ADMIN && printf '%s' "$devices" | grep -q '/dev/net/tun'; then
    pasa "'lab' se recreó con NET_ADMIN y /dev/net/tun tras habilitar la VPN"
else
    falla "'lab' debería tener NET_ADMIN y /dev/net/tun tras SECLAB_HABILITAR_VPN=true"
fi

# --- 3. seclab vpn up vpnhtb: rutas y sin secuestro de la ruta por defecto --
log "3. Levantando el perfil vpnhtb"
if ./bin/seclab vpn up vpnhtb; then
    pasa "'seclab vpn up vpnhtb' conecta contra el servidor de prueba"
else
    falla "'seclab vpn up vpnhtb' no ha podido levantar el túnel"
fi

rutas="$(./bin/seclab vpn routes 2>&1)"
if printf '%s' "$rutas" | grep -q '^  default via .* dev eth0'; then
    pasa "la ruta por defecto sigue apuntando a eth0 (sin secuestro)"
else
    falla "la ruta por defecto debería seguir apuntando a eth0"
fi
if printf '%s' "$rutas" | grep -q '10\.61\.1\.0/24 via .* dev tun-htb'; then
    pasa "la ruta hacia el rango declarado (10.61.1.0/24) existe, por tun-htb"
else
    falla "debería existir una ruta hacia 10.61.1.0/24 por tun-htb"
fi

# --- 4. Rechazo por solape de rangos -----------------------------------------
log "4. Probando el rechazo por solape de rangos (vpncli contra vpnhtb activo)"
cp vpn/vpnhtb/ta.key vpn/vpncli/ta.key
cp vpn/vpnhtb/cliente.ovpn vpn/vpncli/cliente.ovpn
chmod 600 vpn/vpncli/ta.key vpn/vpncli/cliente.ovpn
cat > vpn/vpncli/perfil.env <<'EOF'
SECLAB_VPN_NOMBRE="Prueba de solape (vpncli)"
SECLAB_VPN_CONFIG="cliente.ovpn"
SECLAB_VPN_RANGOS="10.61.1.128/25"
SECLAB_VPN_DNS=""
EOF
chmod 600 vpn/vpncli/perfil.env

# La salida se captura ANTES de compararla con grep, nunca con
# `comando | grep -q`: bajo `pipefail`, si `grep -q` encuentra la coincidencia
# en una línea y el comando de la izquierda todavía tiene más que escribir,
# `grep -q` cierra su extremo de la tubería y el escritor recibe SIGPIPE (exit
# 141) — que `pipefail` propaga como el estado de la tubería aunque `grep` sí
# haya encontrado lo esperado. Ya pasó aquí mismo: `seclab vpn up vpncli`
# rechazaba el solape correctamente (se veía "se solapan" en la salida), pero
# la comprobación daba FALLO por el SIGPIPE, no porque el rechazo no
# funcionara. Es el mismo escollo que ya documenta `scripts/smoke.sh` con su
# función `contiene()`.
salida_vpncli="$(./bin/seclab vpn up vpncli 2>&1 || true)"
if printf '%s' "$salida_vpncli" | grep -q 'se solapan'; then
    pasa "'seclab vpn up vpncli' con rango solapado se rechaza explicando el conflicto"
else
    falla "'seclab vpn up vpncli' con rango solapado debería rechazarse"
fi
estado_vpnhtb="$(./bin/seclab vpn status vpnhtb 2>&1 || true)"
if printf '%s' "$estado_vpnhtb" | grep -q 'Estado: arriba'; then
    pasa "'vpnhtb' sigue arriba tras el intento rechazado de 'vpncli'"
else
    falla "'vpnhtb' no debería haberse visto afectado por el rechazo de 'vpncli'"
fi

# --- 5. Killswitch: cae el túnel, las reglas de iptables se mantienen -------
log "5. Deteniendo el servidor de prueba para forzar la caída del túnel"
docker stop "$SERVIDOR" >/dev/null

# El servidor de prueba usa clave estática (--secret, sin TLS): sin handshake,
# el cliente no tiene forma de confirmar que el peer sigue muerto al
# reconectar. 'ping-restart' (15s de inactividad) dispara --down, pero el
# propio cliente se remarca 'arriba' un par de segundos después con sólo
# reabrir la interfaz tun — sin haber verificado nada con un servidor que
# sigue parado. El túnel queda así oscilando entre 'arriba' y 'caído' cada
# ~15-17s mientras el servidor no vuelva (comprobado con
# /run/seclab-vpn/vpnhtb.log durante la depuración de este script: down a los
# 15s, arriba otra vez 2s después, down de nuevo 15s más tarde...). Dormir un
# tiempo fijo y comprobar una única vez sería una lotería (la ventana
# 'caído' es de sólo ~2 de cada ~17 segundos): se sondea en su lugar, y en
# cuanto se observa 'caído' se comprueba la ruta EN ESE MISMO instante, antes
# de que el ciclo vuelva a marcarlo 'arriba'.
caido_observado=false
rutas_en_caida=""
for _ in $(seq 1 60); do
    estado_caido="$(./bin/seclab vpn status vpnhtb 2>&1 || true)"
    if printf '%s' "$estado_caido" | grep -q 'caído (killswitch activo)'; then
        caido_observado=true
        rutas_en_caida="$(./bin/seclab vpn routes 2>&1)"
        break
    fi
    sleep 0.5
done

if [ "$caido_observado" = true ]; then
    pasa "'vpnhtb' pasa a 'caído (killswitch activo)' cuando el servidor desaparece"
else
    falla "'vpnhtb' debería reportarse 'caído (killswitch activo)' (no se observó en 30s de sondeo; revisa /run/seclab-vpn/vpnhtb.log dentro de 'lab')"
fi

# Las reglas del killswitch se instalan una única vez, al activar el perfil
# (antes incluso de arrancar OpenVPN), y no dependen de que el túnel esté
# arriba o caído en el instante de la comprobación: por eso este chequeo no
# necesita el sondeo anterior.
reglas="$(docker exec -u root "${PROYECTO}-lab-1" iptables -S)"
if printf '%s' "$reglas" | grep -q -- '-A OUTPUT -d 10.61.1.0/24 ! -o tun-htb -j DROP' && \
   printf '%s' "$reglas" | grep -q -- '-A FORWARD -d 10.61.1.0/24 ! -o tun-htb -j DROP'; then
    pasa "las reglas DROP del killswitch siguen presentes con el túnel caído"
else
    falla "las reglas DROP del killswitch deberían seguir presentes"
fi

if [ "$caido_observado" = true ]; then
    if printf '%s' "$rutas_en_caida" | grep -q '10\.61\.1\.0/24'; then
        falla "la ruta hacia 10.61.1.0/24 debería haber desaparecido con el túnel caído"
    else
        pasa "la ruta hacia el rango declarado desaparece cuando el túnel cae (el killswitch la sustituye)"
    fi
else
    falla "la ruta hacia el rango declarado desaparece cuando el túnel cae (no se pudo comprobar: nunca se observó el estado 'caído')"
fi

# --- Resultado ----------------------------------------------------------------
log "Resultado"
if [ "$FALLOS" -eq 0 ]; then
    echo "Todas las comprobaciones de VPN pasan." >&2
    exit 0
fi
echo "${FALLOS} comprobación(es) de VPN fallaron." >&2
exit 1
