#!/usr/bin/env bash
# =============================================================================
# SecLab — smoke test de Tailscale SIN conexión real (Fase 9, CI)
# =============================================================================
# prompt_v3.md prohíbe expresamente generar una auth key real de Tailscale, y
# este repositorio no tiene cuenta contra la que probar una conexión real.
# Este script verifica, en cambio, exactamente lo que SÍ se puede comprobar
# sin red externa ni cuenta:
#
#   1. SECLAB_HABILITAR_TAILSCALE=true + TAILSCALE_AUTH_KEY vacía
#      -> 'seclab tailscale up' se niega ANTES de tocar Docker (sin arrancar
#         ningún contenedor).
#   2. TAILSCALE_AUTH_KEY con un valor de prueba OBVIAMENTE inválido (nunca
#      una key real), CONTRA UN SERVIDOR DE CONTROL LOCAL INEXISTENTE
#      (--login-server=http://127.0.0.1:1, un puerto en el que nunca escucha
#      nada dentro del propio contenedor): tailscaled arranca, intenta
#      autenticarse, la conexión se rechaza LOCALMENTE (connection refused,
#      nunca sale un paquete de la máquina) y el contenedor sigue vivo
#      reintentando, sin caerse ni quedar en un estado ambiguo. Se comprueba
#      que el error queda en los logs y que la auth key NUNCA aparece en ellos.
#
#      Sin el --login-server local, este mismo paso intentaría alcanzar de
#      verdad controlplane.tailscale.com (se observó en el desarrollo de este
#      script: con una key inválida, tailscaled igualmente abre una conexión
#      TLS real a los servidores de Tailscale antes de que éstos la
#      rechacen). Eso SÍ sería "conectar de verdad a la red de Tailscale de
#      alguien", que prompt_v3.md prohíbe expresamente para esta fase, así
#      que aquí SIEMPRE se apunta a un servidor de control local inalcanzable
#      en vez de al real.
#   3. El volumen de estado (${PROYECTO}-tailscale-state) sobrevive a
#      'docker compose down' + 'up' de nuevo (recreación del contenedor): es
#      el mismo volumen nombrado, no se recrea vacío.
#   4. El contenedor 'tailscale' vive en su propio proyecto de Compose, en su
#      propio namespace de red (nunca 'network_mode: service:lab' ni
#      compartido con nada): la comprobación de convivencia con VPN que hace
#      'seclab doctor' depende de que esto sea cierto.
#
# Nunca se conecta a la red real de Tailscale ni se genera una key real. Lo
# que queda sin poder verificarse (unirse de verdad a una tailnet, `tailscale
# serve` sirviendo tráfico real) se documenta en TESTING_GAPS.md.
#
# Se ejecuta sobre el propio checkout (pensado para un runner de CI efímero,
# igual que scripts/ci/probar-vpn.sh: aborta si ya existe un .env real).
# Limpia todo lo que crea, incluso si algo falla a medias (trap EXIT).
# =============================================================================

set -uo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$RAIZ" || exit 1

# shellcheck source=../../lib/secretos.sh
. "${RAIZ}/lib/secretos.sh"

PROYECTO="seclabtsci"
FALLOS=0

log() { printf '\n>>> %s\n' "$1" >&2; }
pasa() { printf '  OK  %s\n' "$1" >&2; }
falla() { printf '  FALLO  %s\n' "$1" >&2; FALLOS=$((FALLOS + 1)); }

limpiar() {
    log "Limpiando recursos de la prueba"
    docker rm -f "${PROYECTO}-ts-prueba" >/dev/null 2>&1 || true
    docker compose -f docker-compose.yml down --volumes --remove-orphans >/dev/null 2>&1 || true
    docker compose -f docker-compose.tailscale.yml down --volumes --remove-orphans >/dev/null 2>&1 || true
    rm -f ./ci-ssh-key ./ci-ssh-key.pub
    rm -rf ./vpn ./workspace ./backups ./secretos ./.env
}
trap limpiar EXIT

# --- Preparación -------------------------------------------------------------
log "Preparando .env de prueba"
"${RAIZ}/scripts/ci/preparar-env.sh" "$PROYECTO" 2398
escribir_variable .env SECLAB_HABILITAR_TAILSCALE true

# --- 1. Sin TAILSCALE_AUTH_KEY: rechazo ANTES de tocar Docker ---------------
log "1. 'seclab tailscale up' sin TAILSCALE_AUTH_KEY"
escribir_variable .env TAILSCALE_AUTH_KEY ""
salida_sin_key="$(./bin/seclab tailscale up 2>&1 </dev/null || true)"
if printf '%s' "$salida_sin_key" | grep -q 'TAILSCALE_AUTH_KEY está vacía'; then
    pasa "'seclab tailscale up' rechaza arrancar sin TAILSCALE_AUTH_KEY, con mensaje claro"
else
    falla "'seclab tailscale up' debería rechazar arrancar sin TAILSCALE_AUTH_KEY"
fi
if [ -z "$(docker compose -f docker-compose.tailscale.yml ps -q tailscale 2>/dev/null)" ]; then
    pasa "no se ha creado ningún contenedor 'tailscale' sin auth key"
else
    falla "no debería existir un contenedor 'tailscale' sin auth key"
fi

# --- 1b. Red de seguridad dentro del propio contenedor -----------------------
# Aunque el CLI ya bloquea el caso anterior, se comprueba también que quien se
# salte el CLI (docker compose directo) tropieza con la misma comprobación
# dentro del 'command' de docker-compose.tailscale.yml.
log "1b. 'docker compose up' directo, sin TAILSCALE_AUTH_KEY (sin pasar por el CLI)"
salida_directa="$(docker compose -f docker-compose.tailscale.yml run --rm tailscale 2>&1 || true)"
if printf '%s' "$salida_directa" | grep -q 'TAILSCALE_AUTH_KEY vacía'; then
    pasa "el propio contenedor se niega a arrancar sin TAILSCALE_AUTH_KEY, incluso sin el CLI"
else
    falla "el contenedor debería negarse a arrancar sin TAILSCALE_AUTH_KEY, incluso invocado sin el CLI"
fi
docker compose -f docker-compose.tailscale.yml rm -f tailscale >/dev/null 2>&1 || true

# --- 2. Auth key de prueba OBVIAMENTE inválida, contra control local -------
# 'docker compose run' (no 'up', y no './bin/seclab tailscale up': el CLI no
# expone --login-server a propósito, no es una opción real de producción,
# sólo la usa esta prueba para no salir nunca a Internet) con TS_EXTRA_ARGS
# sobrescrito para apuntar a un puerto local sin nada escuchando.
log "2. Arranque con una auth key de prueba inválida, contra un servidor de control local inexistente"
# A propósito, este valor de prueba NO empieza por 'tskey-auth-' (el prefijo
# real de una auth key de Tailscale): scripts/verificar-seguridad.sh escanea
# el repositorio buscando justo ese prefijo (sección 5, detección de posibles
# secretos) para atrapar una key real filtrada por accidente. Un valor de
# prueba con el prefijo real, aunque evidentemente inválido, dispararía esa
# misma alarma sin necesidad — tailscaled rechaza cualquier cadena que no sea
# una key válida, tenga o no el prefijo real, así que el prefijo no aporta
# nada a esta prueba.
CLAVE_PRUEBA="clave-de-prueba-invalida-nunca-una-auth-key-real-000000000000"
# Se sobrescriben las variables de entorno del CONTENEDOR directamente
# (TS_AUTHKEY, no TAILSCALE_AUTH_KEY: esta última sólo existe en .env y se
# resuelve a TS_AUTHKEY en tiempo de interpolación de Compose, así que un
# '-e TAILSCALE_AUTH_KEY=...' en 'docker compose run' no llegaría al proceso
# que de verdad la lee).
docker compose -f docker-compose.tailscale.yml run -d --name "${PROYECTO}-ts-prueba" \
    -e TS_AUTHKEY="$CLAVE_PRUEBA" \
    -e TS_EXTRA_ARGS="--accept-routes=false --accept-dns=false --login-server=http://127.0.0.1:1" \
    tailscale >/dev/null 2>&1
sleep 5

log "2b. El intento de login se rechaza LOCALMENTE (nunca sale de la máquina), sin imprimir la key"
estado_final="$(docker inspect -f '{{.State.Status}}' "${PROYECTO}-ts-prueba" 2>/dev/null || echo ausente)"
logs_tailscale="$(docker logs "${PROYECTO}-ts-prueba" 2>&1 || true)"
if [ "$estado_final" = "running" ]; then
    pasa "el contenedor sigue vivo (${estado_final}) reintentando el login, sin caerse por una auth key inválida"
else
    falla "el contenedor debería seguir corriendo mientras reintenta el login (estado observado: ${estado_final})"
fi
if printf '%s' "$logs_tailscale" | grep -qF '127.0.0.1:1: connect: connection refused'; then
    pasa "el intento de login se rechaza LOCALMENTE (connection refused a 127.0.0.1:1): nunca ha salido tráfico real hacia Tailscale"
else
    falla "se esperaba ver 'connection refused' contra el servidor de control local de prueba en los logs"
fi
if printf '%s' "$logs_tailscale" | grep -qF "$CLAVE_PRUEBA"; then
    falla "la auth key de prueba ha aparecido en los logs del contenedor: NUNCA debe imprimirse"
else
    pasa "la auth key no aparece en los logs del contenedor, ni siquiera la de prueba"
fi
docker rm -f "${PROYECTO}-ts-prueba" >/dev/null 2>&1 || true

# --- 3. El volumen de estado sobrevive a una recreación ---------------------
log "3. Persistencia del volumen de estado tras 'down' + 'up'"
if docker volume inspect "${PROYECTO}-tailscale-state" >/dev/null 2>&1; then
    pasa "el volumen nombrado ${PROYECTO}-tailscale-state existe tras el primer arranque"
else
    falla "debería existir el volumen ${PROYECTO}-tailscale-state tras el primer arranque"
fi
# Se escribe una marca dentro del volumen (simulando estado real de
# tailscaled) usando un contenedor efímero que monta el MISMO volumen, sin
# depender de que 'tailscaled' haya llegado a escribir nada él solo con una
# key inválida.
docker run --rm -v "${PROYECTO}-tailscale-state:/var/lib/tailscale" busybox \
    sh -c 'echo "marca-de-prueba-fase9" > /var/lib/tailscale/.marca-ci' >/dev/null 2>&1
docker compose -f docker-compose.tailscale.yml down >/dev/null 2>&1 || true
docker compose -f docker-compose.tailscale.yml up -d tailscale >/dev/null 2>&1 || true
sleep 2
marca_leida="$(docker run --rm -v "${PROYECTO}-tailscale-state:/var/lib/tailscale" busybox \
    cat /var/lib/tailscale/.marca-ci 2>/dev/null || true)"
if [ "$marca_leida" = "marca-de-prueba-fase9" ]; then
    pasa "el volumen de estado sobrevive a 'docker compose down' + 'up' (recreación del contenedor)"
else
    falla "la marca escrita en el volumen de estado no sobrevivió a la recreación del contenedor"
fi

# --- 4. Aislamiento de red real (namespace propio, nunca compartido) -------
log "4. El contenedor 'tailscale' no comparte namespace de red con nada"
id_ts="$(docker compose -f docker-compose.tailscale.yml ps -q tailscale 2>/dev/null)"
if [ -n "$id_ts" ]; then
    modo="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$id_ts" 2>/dev/null)"
    case "$modo" in
        container:*|service:*)
            falla "'tailscale' comparte namespace de red (${modo}); debería tener el suyo propio"
            ;;
        *)
            pasa "'tailscale' vive en su propio namespace de red (${modo})"
            ;;
    esac
    proyecto_ts="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$id_ts" 2>/dev/null)"
    if [ "$proyecto_ts" = "${PROYECTO}-tailscale" ]; then
        pasa "'tailscale' vive en su propio proyecto de Compose (${proyecto_ts}), distinto del de 'lab' (${PROYECTO})"
    else
        falla "'tailscale' debería vivir en el proyecto '${PROYECTO}-tailscale', no en '${proyecto_ts}'"
    fi
else
    falla "no se ha podido localizar el contenedor 'tailscale' para comprobar su aislamiento de red"
fi

# --- 5. 'lab' arranca sin verse afectado por Tailscale ----------------------
log "5. 'lab' arranca normalmente con Tailscale habilitado, sin heredar NET_ADMIN por Tailscale"
./bin/seclab image build --profile lite >/dev/null
if ./bin/seclab start --profile lite </dev/null >/tmp/seclabtsci-start.log 2>&1; then
    cap_add="$(docker inspect "${PROYECTO}-lab-1" --format '{{.HostConfig.CapAdd}}' 2>/dev/null || echo '')"
    if printf '%s' "$cap_add" | grep -q NET_ADMIN; then
        falla "'lab' no debería tener NET_ADMIN sólo por tener Tailscale habilitado (SECLAB_HABILITAR_VPN sigue en false)"
    else
        pasa "'lab' arranca sin NET_ADMIN aunque Tailscale esté habilitado (proyectos de Compose independientes)"
    fi
else
    falla "'seclab start --profile lite' debería seguir funcionando con Tailscale habilitado (ver /tmp/seclabtsci-start.log)"
fi

# --- Resultado ----------------------------------------------------------------
log "Resultado"
rm -f /tmp/seclabtsci-salida-up.log /tmp/seclabtsci-start.log
if [ "$FALLOS" -eq 0 ]; then
    echo "Todas las comprobaciones de Tailscale (sin conexión real) pasan." >&2
    exit 0
fi
echo "${FALLOS} comprobación(es) de Tailscale fallaron." >&2
exit 1
