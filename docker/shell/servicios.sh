#!/usr/bin/env bash
# =============================================================================
# SecLab — estado de los servicios del laboratorio, desde dentro
# =============================================================================
# Envoltura de supervisorctl con la configuración correcta. Existe porque la
# configuración de supervisor se genera en cada arranque en /run/seclab y
# supervisorctl, sin -c, busca en otro sitio y falla con un error que no dice
# qué pasa.
#
#   servicios              estado de todos los servicios
#   servicios restart NOMBRE
#   servicios tail -f NOMBRE
# =============================================================================

set -uo pipefail

CONF=/run/seclab/supervisord.conf

if [ ! -r "$CONF" ] && [ ! -e "$CONF" ]; then
    printf 'No hay configuración de supervisor en %s.\n' "$CONF" >&2
    printf 'El contenedor se arrancó de otra forma (por ejemplo con un comando propio).\n' >&2
    exit 1
fi

# La configuración es de root porque contiene la contraseña de code-server.
exec sudo /usr/bin/supervisorctl -c "$CONF" "${@:-status}"
