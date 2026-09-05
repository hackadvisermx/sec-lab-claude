#!/usr/bin/env bash
# =============================================================================
# SecLab — manifiesto de herramientas
# =============================================================================
# Se ejecuta durante el build y registra las versiones que realmente quedaron
# instaladas: dice con exactitud qué hay dentro de esta imagen concreta, que es
# lo que permite saber si una herramienta está al día. Ver
# docs/politica-herramientas.md.
#
# Marca además qué herramientas se comportan de forma distinta en arm64, para
# que quien trabaje en un Mac con Apple Silicon lo sepa de antemano.
# =============================================================================

set -uo pipefail

PERFIL="${SECLAB_PERFIL:-lite}"
ARQ="${TARGETARCH:-$(dpkg --print-architecture 2>/dev/null || uname -m)}"

# Herramientas con salvedades conocidas en arm64.
notas_arm64() {
    case "$1" in
        whatweb) echo "intérprete Ruby; sin binario nativo, rendimiento menor" ;;
        libgl1-mesa-dri) echo "render por software; el escritorio no usa GPU" ;;
        hashcat) echo "sin OpenCL de GPU en el contenedor; sólo CPU" ;;
        binwalk) echo "" ;;
        *) echo "" ;;
    esac
}

version_de() {
    local herramienta="$1" v
    v="$(dpkg-query --showformat='${Version}' --show "$herramienta" 2>/dev/null)"
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
    printf 'no instalado'
}

printf '# Manifiesto de herramientas de SecLab\n'
printf '#\n'
printf '# Perfil:        %s\n' "$PERFIL"
printf '# Arquitectura:  %s\n' "$ARQ"
printf '# Generado:      %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '# Base:          %s\n' "$(grep -E '^(PRETTY_NAME|VERSION)=' /etc/os-release 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\"')"
printf '#\n'
printf '# La columna "vía" dice de dónde salió cada herramienta:\n'
printf '#   apt      del repositorio de Ubuntu LTS, con sus parches de seguridad\n'
printf '#   fijada   de la publicación oficial del proyecto, con versión y\n'
printf '#            checksum verificados en el build\n'
printf '#\n'
printf '# La columna "notas" señala diferencias de comportamiento en esta\n'
printf '# arquitectura. Vacía significa que no hay salvedades conocidas.\n'
printf '\n'
printf '| %-22s | %-28s | %-7s | %s\n' "herramienta" "versión" "vía" "notas"
printf '| %-22s | %-28s | %-7s | %s\n' "----------------------" "----------------------------" "-------" "-----"

ausentes=""

# SECLAB_LISTA_PAQUETES puede traer varias listas separadas por espacios: un
# perfil se construye sobre otro (desktop sobre lite) y el manifiesto tiene que
# reflejar todo lo que hay dentro, no sólo lo que añadió la última etapa.
for lista in ${SECLAB_LISTA_PAQUETES:-/opt/seclab/paquetes-lite.txt}; do
    [ -r "$lista" ] || continue
    while IFS= read -r paquete; do
        case "$paquete" in ''|\#*) continue ;; esac
        paquete="$(printf '%s' "$paquete" | tr -d '[:space:]')"
        [ -z "$paquete" ] && continue
        version="$(version_de "$paquete")"
        [ "$version" = "no instalado" ] && ausentes="${ausentes} ${paquete}"
        nota=""
        [ "$ARQ" = "arm64" ] && nota="$(notas_arm64 "$paquete")"
        printf '| %-22s | %-28s | %-7s | %s\n' "$paquete" "$version" "apt" "$nota"
    done < "$lista"
done

# Herramientas traídas de su publicación oficial con versión fijada. El build
# las anota en este archivo con su versión real, porque es el único momento en
# que se conoce. Formato: nombre|versión|nota
if [ -r /opt/seclab/herramientas-fijadas.txt ]; then
    while IFS='|' read -r nombre version nota; do
        case "$nombre" in ''|\#*) continue ;; esac
        printf '| %-22s | %-28s | %-7s | %s\n' "$nombre" "$version" "fijada" "$nota"
    done < /opt/seclab/herramientas-fijadas.txt
fi

# Un paquete de la lista que no aparece instalado suele significar que su
# nombre es transitorio y apt lo resolvió por otro. La herramienta puede estar
# ahí, pero el manifiesto ya no dice la verdad sobre lo que contiene la imagen,
# y un manifiesto que miente no sirve para nada. Se corta el build.
if [ -n "$ausentes" ]; then
    printf '\n' >&2
    printf 'ERROR: estos paquetes de la lista no figuran instalados:%s\n' "$ausentes" >&2
    printf 'Comprueba si su nombre es transitorio y usa el nombre real en la lista.\n' >&2
    exit 1
fi
