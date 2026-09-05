#!/bin/sh
# =============================================================================
# SecLab — guardián de capacidades de fichero
# =============================================================================
# Se ejecuta en cada etapa del build que instale paquetes nuevos.
#
# Comprueba el invariante que de verdad importa: **ningún binario de la imagen
# puede reclamar una capacidad que el contenedor no tenga en su conjunto
# delimitador**. Si lo hace, el kernel rechaza su `exec` por completo y la
# herramienta no arranca ni para imprimir su versión —que es exactamente lo que
# le pasaba a nmap sobre la base anterior—.
#
# No se exige que ningún binario tenga capacidades: Ubuntu marca `ping` con
# cap_net_raw de forma perfectamente legítima. Lo que se exige es que las que
# haya estén dentro del conjunto concedido en docker-compose.yml.
#
# Mejor detener el build que entregar una imagen con una herramienta muerta.
# =============================================================================

set -eu

PERMITIDAS="${SECLAB_CAPACIDADES_PERMITIDAS:-cap_net_raw cap_net_bind_service}"
INFORME="${1:-/opt/seclab/capacidades.txt}"

getcap -r /usr /bin /sbin /opt 2>/dev/null | tee "$INFORME"

problemas=""
while read -r ruta caps; do
    [ -n "$ruta" ] || continue
    for cap in $(echo "${caps%%=*}" | tr ',' ' '); do
        case " $PERMITIDAS " in
            *" $cap "*) ;;
            *) problemas="${problemas} ${ruta}:${cap}" ;;
        esac
    done
done < "$INFORME"

if [ -n "$problemas" ]; then
    echo "ERROR: binarios que reclaman capacidades fuera del conjunto del contenedor:" >&2
    echo "$problemas" >&2
    echo "El kernel rechazaría su ejecución. Ajusta la imagen o el conjunto de capacidades." >&2
    exit 1
fi

echo "Capacidades de fichero dentro del conjunto permitido (${PERMITIDAS})."
