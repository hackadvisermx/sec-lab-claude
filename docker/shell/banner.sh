#!/usr/bin/env bash
# =============================================================================
# SecLab — banner de bienvenida
# =============================================================================
# Corto a propósito: cinco líneas que se leen de un vistazo. Un banner de media
# pantalla se ignora a partir del segundo día.
#
# Se genera del estado real en cada arranque, no es un texto fijo que pueda
# quedar desfasado. NUNCA imprime secretos: ni contraseñas, ni tokens, ni la IP
# pública. La IP del túnel sí, que hace falta para trabajar.
# =============================================================================

set -uo pipefail

MANIFIESTO="/opt/seclab/manifiesto-herramientas.txt"

# sshd no hereda el entorno del contenedor, así que los datos se leen de aquí.
# Sólo contiene información pública; los secretos nunca pasan por este archivo.
# shellcheck source=/dev/null
[ -r /etc/seclab/entorno ] && . /etc/seclab/entorno

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    A=$'\033[36m'; V=$'\033[32m'; G=$'\033[90m'; N=$'\033[1m'; F=$'\033[0m'
else
    A='' V='' G='' N='' F=''
fi

version="${SECLAB_VERSION:-desconocida}"
perfil="${SECLAB_PERFIL:-lite}"
arquitectura="$(uname -m)"
herramientas=0
[ -r "$MANIFIESTO" ] && herramientas="$(grep -c '^| [a-z0-9]' "$MANIFIESTO" 2>/dev/null || echo 0)"

# Perfiles de VPN activos ahora mismo. Se consultan aquí dentro, en vivo
# (seclab-vpn activos), en vez de leerse de una variable fijada al arranque
# del contenedor: con el diseño de la Fase 7 pueden ser varios perfiles a la
# vez, y cambian sin recrear 'lab', así que un valor estático quedaría
# desfasado en cuanto alguien hiciera 'seclab-vpn up'/'down'. Sólo los
# nombres: el detalle (interfaz, IP, rangos) se consulta con
# 'seclab vpn status', que no tiene sentido en un banner corto.
activos=""
if command -v seclab-vpn >/dev/null 2>&1; then
    activos="$(seclab-vpn activos 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
fi
if [ -n "$activos" ]; then
    vpn="${V}${activos}${F}"
else
    vpn="${G}ninguna activa${F}"
fi

printf '\n'
printf '  %s\n' "${N}${A}SecLab${F}${N} ${version}${F} ${G}·${F} perfil ${perfil} ${G}·${F} ${arquitectura}"
printf '  %s\n' "${G}────────────────────────────────────────────────────${F}"
printf '  %-13s %s\n' "Workspace" "/workspace"
printf '  %-13s %s\n' "VPN" "$vpn"
printf '  %-13s %s\n' "Herramientas" "${herramientas} instaladas ${G}·${F} escribe ${N}herramientas${F} para ver cuáles"
printf '\n'
