#!/usr/bin/env bash
# =============================================================================
# SecLab — ayuda de las herramientas instaladas
# =============================================================================
# Responde a la pregunta más frecuente del alumnado: ¿qué tengo aquí y cómo se
# usa? Se construye a partir del manifiesto y de la lista de paquetes, no de una
# lista escrita a mano: si algo no está instalado, no puede aparecer aquí.
#
#   herramientas            lista todo por categorías, con versión
#   herramientas nmap       para qué sirve, cómo se usa y dónde leer más
#   herramientas -b tcp     busca por nombre o descripción
# =============================================================================

set -uo pipefail

MANIFIESTO="/opt/seclab/manifiesto-herramientas.txt"
LISTA="/opt/seclab/paquetes-lite.txt"
EJEMPLOS="/opt/seclab/shell/ejemplos.txt"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    A=$'\033[36m'; V=$'\033[32m'; G=$'\033[90m'; N=$'\033[1m'; Y=$'\033[33m'; F=$'\033[0m'
else
    A='' V='' G='' N='' Y='' F=''
fi

version_de() {
    grep -m1 "^| $1 " "$MANIFIESTO" 2>/dev/null | awk -F'|' '{gsub(/ /,"",$3); print $3}'
}

aviso_uso() {
    printf '%s\n' "${G}Uso autorizado: se asume que tienes permiso sobre los objetivos contra los" >&2
    printf '%s\n\n' "que uses esto. Ver docs/uso-autorizado.md.${F}" >&2
}

listar() {
    aviso_uso
    local categoria=""
    while IFS= read -r linea; do
        case "$linea" in
            '# --- '*)
                categoria="${linea#\# --- }"; categoria="${categoria% ---}"
                printf '\n%s\n' "${N}${A}${categoria}${F}"
                ;;
            '#'*|'') continue ;;
            *)
                local v; v="$(version_de "$linea")"
                [ -z "$v" ] && continue
                printf '  %-24s %s\n' "$linea" "${G}${v}${F}"
                ;;
        esac
    done < "$LISTA"
    printf '\n%s\n\n' "${G}'herramientas <nombre>' explica una en concreto.${F}"
}

detallar() {
    local nombre="$1" v descripcion ejemplo
    v="$(version_de "$nombre")"

    if [ -z "$v" ] && ! command -v "$nombre" >/dev/null 2>&1; then
        printf '%s\n' "${Y}'${nombre}' no está en esta imagen.${F}" >&2
        printf '%s\n' "${G}Mira 'herramientas' para ver lo que sí hay, o 'herramientas -b ${nombre}' para buscar.${F}" >&2
        return 1
    fi

    printf '\n%s\n' "${N}${A}${nombre}${F}${v:+ ${G}${v}${F}}"

    # La descripción sale de dpkg: está en la propia imagen y no hay que
    # mantenerla a mano ni depende de la red.
    descripcion="$(dpkg-query -W -f='${Description}' "$nombre" 2>/dev/null | tail -n +2 | sed 's/^ //;s/^\.$//')"
    [ -n "$descripcion" ] && printf '\n%s\n' "$descripcion"

    if [ -r "$EJEMPLOS" ]; then
        ejemplo="$(awk -F'|' -v n="$nombre" '$1==n {print $2}' "$EJEMPLOS")"
        if [ -n "$ejemplo" ]; then
            printf '\n%s\n' "${N}Ejemplo${F}"
            printf '  %s\n' "$ejemplo"
        fi
    fi

    if command -v "$nombre" >/dev/null 2>&1; then
        printf '\n%s\n' "${G}Más: ${nombre} --help  ·  man ${nombre}${F}"
    fi
    printf '\n'
}

buscar() {
    local termino="$1" encontrados=0
    printf '\n%s\n\n' "${N}Coincidencias con '${termino}'${F}"
    while IFS= read -r linea; do
        case "$linea" in '#'*|'') continue ;; esac
        local v; v="$(version_de "$linea")"
        [ -z "$v" ] && continue
        local d; d="$(dpkg-query -W -f='${Description}' "$linea" 2>/dev/null | head -1)"
        if printf '%s %s' "$linea" "$d" | grep -qi -- "$termino"; then
            printf '  %-24s %s\n' "$linea" "${G}${d}${F}"
            encontrados=$((encontrados + 1))
        fi
    done < "$LISTA"
    [ "$encontrados" -eq 0 ] && printf '  %s\n' "${G}Nada.${F}"
    printf '\n'
}

case "${1:-}" in
    '')        listar ;;
    -b|--buscar) shift; [ $# -gt 0 ] || { echo "Indica qué buscar." >&2; exit 2; }; buscar "$1" ;;
    -h|--help) sed -n '4,14p' "$0" | sed 's/^# \?//' ;;
    *)         detallar "$1" ;;
esac
