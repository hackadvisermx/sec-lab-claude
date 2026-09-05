#!/usr/bin/env bash
# =============================================================================
# SecLab — .env mínimo de prueba para la CI (Fase 8)
# =============================================================================
# La CI necesita un .env válido para poder ejercitar 'bin/seclab' y
# 'scripts/verificar-seguridad.sh' de verdad, sin secretos reales ni
# credenciales de nadie: todo se genera aquí mismo, en el runner, con
# 'openssl rand' y una llave SSH desechable creada al vuelo.
#
# Se usa tal cual (variables por defecto) para los jobs de seguridad y smoke
# test, que corren en un checkout efímero y no arriesgan ninguna instalación
# real. NUNCA se ejecuta esto sobre un checkout de desarrollo con un .env
# de verdad: sobrescribiría su configuración real.
#
# Uso: scripts/ci/preparar-env.sh [PROYECTO] [PUERTO_SSH]
# =============================================================================

set -euo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$RAIZ"

# shellcheck source=../../lib/secretos.sh
# Se reutiliza escribir_variable() (awk, no sed -i) para no repetir una
# segunda implementación de "escribe esta clave en .env" que además tendría
# que llevar su propia cuenta de portabilidad BSD/GNU.
. "${RAIZ}/lib/secretos.sh"

PROYECTO="${1:-seclabci}"
PUERTO_SSH="${2:-2299}"

if [ -f .env ]; then
    echo "ERROR: ya existe .env en ${RAIZ}." >&2
    echo "Este script sólo se usa en un checkout efímero de CI; nunca sobre" >&2
    echo "una instalación de desarrollo con .env real. Se aborta sin tocar nada." >&2
    exit 1
fi

cp .env.example .env
chmod 600 .env

ssh-keygen -t ed25519 -N '' -f ./ci-ssh-key -q -C "seclab-ci"
PUBKEY="$(cat ./ci-ssh-key.pub)"

escribir_variable .env SECLAB_PROJECT "$PROYECTO"
escribir_variable .env SECLAB_PUERTO_SSH "$PUERTO_SSH"
escribir_variable .env SECLAB_VNC_PASSWORD "$(openssl rand -hex 16)"
escribir_variable .env SECLAB_CODE_PASSWORD "$(openssl rand -hex 16)"
escribir_variable .env SECLAB_JUPYTER_TOKEN "$(openssl rand -hex 16)"
escribir_variable .env SECLAB_MCP_TOKEN "$(openssl rand -hex 16)"

# SECLAB_SSH_LLAVE y SECLAB_SSH_PUBKEY no vienen en .env.example: normalmente
# los añade 'seclab init' (localizando la llave del alumno). Aquí se añaden a
# mano con la llave desechable recién creada; escribir_variable() las agrega
# porque todavía no existen en el archivo.
escribir_variable .env SECLAB_SSH_LLAVE "${RAIZ}/ci-ssh-key"
escribir_variable .env SECLAB_SSH_PUBKEY "$PUBKEY"

install -d -m 0700 vpn vpn/vpnhtb vpn/vpntry vpn/vpncli secretos backups workspace

echo "→ .env de prueba listo (proyecto=${PROYECTO}, puerto SSH=${PUERTO_SSH})"
