#!/usr/bin/env bash
# =============================================================================
# SecLab — VPN autorizada multiperfil (Fase 7)
# =============================================================================
# Se carga con `source` desde bin/seclab. Depende de lib/comun.sh y de
# SECLAB_RAIZ.
#
# Toda la lógica de túneles (rutas, killswitch, OpenVPN) vive DENTRO de 'lab',
# en /usr/local/bin/seclab-vpn (docker/shell/seclab-vpn.sh). Este archivo sólo
# aporta las comprobaciones que el CLI del HOST puede hacer sin hablar con el
# contenedor —qué hay en vpn/<perfil>/, si tiene los permisos correctos— antes
# de delegar con `docker exec` (ver vpn_exec() en bin/seclab). El estado de
# qué perfil está activo ya no vive aquí ni en .env: se consulta al
# contenedor con vpn_perfiles_activos() (lib/docker.sh), mismo patrón que
# servicios_activos().
#
# Recordatorio del modelo de responsabilidad (docs/uso-autorizado.md): nada de
# lo que hay aquí valida ni bloquea contra qué objetivo se conecta el alumno
# dentro del túnel. El killswitch es sobre el ESTADO y la INTERFAZ del túnel,
# nunca sobre destinos.
# =============================================================================

# directorio_vpn PERFIL -> ruta absoluta de vpn/<perfil> en el host
directorio_vpn() { printf '%s/vpn/%s' "$SECLAB_RAIZ" "$1"; }

# archivo_perfil_env PERFIL -> ruta absoluta de vpn/<perfil>/perfil.env
archivo_perfil_env() { printf '%s/perfil.env' "$(directorio_vpn "$1")"; }

# leer_perfil_env PERFIL CLAVE -> valor de esa clave en el perfil.env real del
# alumno (nunca en la plantilla: aquí se decide si se puede operar, no se
# documenta un ejemplo).
leer_perfil_env() {
    local perfil="$1" clave="$2" archivo
    archivo="$(archivo_perfil_env "$perfil")"
    [ -f "$archivo" ] || return 0
    # El `|| true` final importa: bin/seclab corre con `set -euo pipefail`, y
    # una clave ausente hace que `grep` devuelva 1 sin que nada se haya roto de
    # verdad. Sin él, consultar un dato opcional abortaría todo el comando.
    grep -m1 "^${clave}=" "$archivo" 2>/dev/null | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' || true
}

# rangos_reales_del_perfil PERFIL -> SECLAB_VPN_RANGOS de su perfil.env real,
# vacío si no está configurado. A diferencia de rangos_del_perfil() en
# lib/labs.sh (que cae a la plantilla y lo anota como "ejemplo" para la ficha
# del lab), aquí no hay plantilla de respaldo: sirve para decidir si se puede
# operar, y un ejemplo no autoriza nada.
rangos_reales_del_perfil() { leer_perfil_env "$1" SECLAB_VPN_RANGOS; }

# ovpn_configurado PERFIL -> ruta absoluta del .ovpn si existe y está declarado
# en su perfil.env; falla (silenciosamente) en cualquier otro caso.
ovpn_configurado() {
    local perfil="$1" ruta archivo
    ruta="$(leer_perfil_env "$perfil" SECLAB_VPN_CONFIG)"
    [ -n "$ruta" ] || return 1
    archivo="$(directorio_vpn "$perfil")/${ruta}"
    [ -f "$archivo" ] || return 1
    printf '%s' "$archivo"
}

# permisos_de RUTA -> modo octal, compatible BSD (macOS) y GNU (Linux)
permisos_de() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }

# comprobar_permisos_vpn PERFIL -> 0 si el directorio y sus archivos son
# 700/600. Si no, avisa (nunca bloquea: es el mismo criterio que el resto de
# SecLab) y da la orden exacta para corregirlo.
comprobar_permisos_vpn() {
    local perfil="$1" dir correcciones=""
    dir="$(directorio_vpn "$perfil")"
    [ -d "$dir" ] || return 0

    [ "$(permisos_de "$dir")" = "700" ] || \
        correcciones="${correcciones}chmod 700 '${dir}'\n"

    local archivo
    while IFS= read -r archivo; do
        [ "$(permisos_de "$archivo")" = "600" ] || \
            correcciones="${correcciones}chmod 600 '${archivo}'\n"
    done < <(find "$dir" -maxdepth 1 -type f 2>/dev/null)

    if [ -n "$correcciones" ]; then
        aviso "Permisos demasiado abiertos en vpn/${perfil}."
        detalle "Un .ovpn es una credencial personal. Corrige con:"
        printf '%b' "$correcciones" | sed 's/^/    /' >&2
        return 1
    fi
    return 0
}
