#!/bin/sh
# =============================================================================
# SecLab — descarga con versión fijada y checksum verificado
# =============================================================================
# Es la vía 2 de la política de herramientas (docs/politica-herramientas.md):
# nada de `latest`, nada de `curl | sh`. Se pide una URL concreta, se compara el
# checksum antes de instalar y el build se detiene si no coincide.
#
#   descargar-fijado URL DESTINO SHA256 [MODO]
#
# Se usa desde el Dockerfile. Con un script en lugar de bloques repetidos en
# cada RUN, la comprobación existe una sola vez y shellcheck puede revisarla.
# =============================================================================

set -eu

if [ "$#" -lt 3 ]; then
    echo "uso: descargar-fijado URL DESTINO SHA256 [MODO]" >&2
    exit 2
fi

url="$1"
destino="$2"
esperado="$3"
modo="${4:-0644}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsSL --connect-timeout 20 --retry 5 --retry-delay 3 --retry-all-errors \
     -o "$tmp" "$url"

real="$(sha256sum "$tmp" | cut -d' ' -f1)"
if [ "$real" != "$esperado" ]; then
    echo "ERROR: checksum incorrecto para ${url}" >&2
    echo "  esperado: ${esperado}" >&2
    echo "  obtenido: ${real}" >&2
    exit 1
fi

install -D -m "$modo" "$tmp" "$destino"
echo "  ${destino}  (sha256 verificado)"
