#!/usr/bin/env bash
# =============================================================================
# SecLab — utilidades comunes de shell
# =============================================================================
# Este archivo se carga con `source` desde bin/seclab y desde los scripts de
# scripts/. No se ejecuta por sí solo.
#
# Todos los mensajes al usuario van en español. Un error debe decir siempre
# tres cosas: qué pasó, qué implica y qué hacer a continuación.
# =============================================================================

# Códigos de salida con significado estable, para que los scripts y la CI
# puedan distinguir un fallo real de una funcionalidad aún no implementada.
readonly SALIDA_OK=0
readonly SALIDA_ERROR=1
readonly SALIDA_USO=2
readonly SALIDA_NO_IMPLEMENTADO=3

# --- Color -------------------------------------------------------------------
# Sólo si la salida es un terminal y el usuario no ha pedido lo contrario.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_ROJO=$'\033[31m'
    C_VERDE=$'\033[32m'
    C_AMARILLO=$'\033[33m'
    C_AZUL=$'\033[34m'
    C_GRIS=$'\033[90m'
    C_NEGRITA=$'\033[1m'
    C_FIN=$'\033[0m'
else
    C_ROJO='' C_VERDE='' C_AMARILLO='' C_AZUL='' C_GRIS='' C_NEGRITA='' C_FIN=''
fi

# --- Mensajería --------------------------------------------------------------
# Los diagnósticos van a stderr para no contaminar salidas que se puedan pipear.

info()  { printf '%s\n' "${C_AZUL}·${C_FIN} $*" >&2; }
ok()    { printf '%s\n' "${C_VERDE}✓${C_FIN} $*" >&2; }
aviso() { printf '%s\n' "${C_AMARILLO}!${C_FIN} $*" >&2; }
detalle() { printf '%s\n' "${C_GRIS}  $*${C_FIN}" >&2; }

titulo() {
    printf '\n%s\n' "${C_NEGRITA}$*${C_FIN}" >&2
}

# error "qué pasó" "qué implica" "qué hacer"
# Los dos últimos argumentos son opcionales pero muy recomendables.
error() {
    printf '%s\n' "${C_ROJO}✗ $1${C_FIN}" >&2
    [ -n "${2:-}" ] && printf '%s\n' "${C_GRIS}  Implica: $2${C_FIN}" >&2
    [ -n "${3:-}" ] && printf '%s\n' "${C_GRIS}  Solución: $3${C_FIN}" >&2
    return 0
}

# abortar "qué pasó" "qué implica" "qué hacer"
abortar() {
    error "$@"
    exit "$SALIDA_ERROR"
}

# no_implementado COMANDO FASE
# Se usa en lugar de fingir que algo funciona. Sale con un código propio para
# que quede claro que no es un fallo del entorno del usuario.
no_implementado() {
    local comando="$1" fase="$2"
    printf '%s\n' "${C_AMARILLO}!${C_FIN} ${C_NEGRITA}seclab ${comando}${C_FIN} todavía no está implementado." >&2
    detalle "Llega en la Fase ${fase} del plan de construcción (ver prompt_v3.md)."
    detalle "SecLab prefiere decírtelo a aparentar que funciona."
    exit "$SALIDA_NO_IMPLEMENTADO"
}

# --- Confirmación ------------------------------------------------------------
# confirmar "pregunta"  -> 0 si el usuario acepta
# Nunca asume que sí. Si no hay terminal interactivo, rechaza.
confirmar() {
    local pregunta="$1" respuesta
    if [ ! -t 0 ]; then
        error "Se necesita confirmación interactiva y no hay terminal disponible." \
              "La operación se cancela por seguridad." \
              "Ejecuta el comando desde una terminal interactiva."
        return 1
    fi
    printf '%s' "${C_AMARILLO}?${C_FIN} ${pregunta} [s/N] " >&2
    read -r respuesta
    case "$respuesta" in
        s|S|si|Si|SI|sí|Sí|SÍ) return 0 ;;
        *) return 1 ;;
    esac
}

# --- Utilidades --------------------------------------------------------------

# existe_comando NOMBRE
existe_comando() { command -v "$1" >/dev/null 2>&1; }

# valores considerados relleno inseguro; rechazados siempre
readonly SECLAB_SECRETOS_PROHIBIDOS='change-this-password|changeme|cambiame|password|passwd|123456|admin|secret|seclab|toor|kali'

# es_secreto_inseguro VALOR -> 0 si el valor es vacío o de relleno
es_secreto_inseguro() {
    local valor="$1"
    [ -z "$valor" ] && return 0
    printf '%s' "$valor" | grep -Eqi "^(${SECLAB_SECRETOS_PROHIBIDOS})$" && return 0
    [ "${#valor}" -lt 16 ] && return 0
    return 1
}
