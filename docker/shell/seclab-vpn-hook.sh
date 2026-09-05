#!/bin/sh
# =============================================================================
# SecLab — gancho --up/--down de OpenVPN para seclab-vpn (Fase 7)
# =============================================================================
# Instalado en la imagen como /usr/local/bin/seclab-vpn-hook. OpenVPN lo
# invoca (--script-security 2) cada vez que el túnel de un perfil cambia de
# estado: arranque inicial, cualquier reconexión y la caída final. Escribe
# únicamente metadatos públicos en /run/seclab-vpn/<perfil>/, que es lo que
# lee 'seclab-vpn status' (y, desde el host, 'seclab vpn status' vía
# `docker exec`). Nunca escribe ni imprime el contenido del .ovpn ni
# credenciales.
#
# Con varios perfiles activos a la vez, cada uno tiene su propio directorio de
# estado (a diferencia del diseño anterior, donde sólo existía un perfil por
# contenedor y bastaba con /run/seclab-vpn/ a secas).
#
# Argumentos con los que se invoca (ver seclab-vpn, función sub_up):
#   $1 modo (up|down)  $2 perfil
# A partir de ahí, los que añade OpenVPN (ver su manual, sección --up/--down):
#   $3 dev  $4 tun_mtu  $5 link_mtu  $6 ifconfig_local  $7 ifconfig_remote
# =============================================================================

set -eu

MODO="${1:?falta el modo (up|down)}"
PERFIL="${2:?falta el perfil}"
DIR="/run/seclab-vpn/${PERFIL}"
DEV="${3:-desconocida}"
IP_LOCAL="${6:-${ifconfig_local:-desconocida}}"

install -d -m 0755 "$DIR"

case "$MODO" in
    up)
        printf '%s\n' "$DEV" > "${DIR}/interfaz"
        printf '%s\n' "$IP_LOCAL" > "${DIR}/ip"
        date -u +%Y-%m-%dT%H:%M:%SZ > "${DIR}/desde"
        if [ -f "${DIR}/rangos-declarados" ]; then
            cp "${DIR}/rangos-declarados" "${DIR}/rangos"
        fi
        touch "${DIR}/arriba"
        printf '[seclab-vpn] %s: túnel arriba (%s, %s)\n' "$PERFIL" "$DEV" "$IP_LOCAL" >&2
        ;;
    down)
        rm -f "${DIR}/arriba"
        printf '[seclab-vpn] %s: túnel caído. El killswitch sigue bloqueando los rangos declarados.\n' "$PERFIL" >&2
        ;;
    *)
        printf '[seclab-vpn] Modo de gancho desconocido: %s\n' "$MODO" >&2
        exit 1
        ;;
esac
