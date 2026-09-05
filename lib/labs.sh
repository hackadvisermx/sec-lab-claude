#!/usr/bin/env bash
# =============================================================================
# SecLab — laboratorios del workspace
# =============================================================================
# Se carga con `source` desde bin/seclab. Depende de lib/comun.sh y de las
# variables SECLAB_RAIZ y ARCHIVO_ENV.
#
# Un lab es un directorio dentro del workspace con una estructura fija y una
# ficha (`scope.txt`) que dice contra qué se trabaja y con qué autorización.
# Nada de esto es un cortafuegos: SecLab no lee la ficha para decidir qué se
# puede hacer —eso es responsabilidad del alumno, ver docs/uso-autorizado.md—;
# sirve para que el trabajo quede ordenado y para que el informe salga solo.
#
# Los labs son independientes entre sí a propósito: se pueden tener varios
# abiertos, cada uno con su perfil de VPN, y el CLI avisa cuando el perfil
# activo no es el que declara el lab en el que estás trabajando.
# =============================================================================

readonly SECLAB_SLUG_MAX=64

# Subdirectorios de un lab. El orden es el que se enseña en clase: primero se
# reconoce, después se anota, y las evidencias se van clasificando.
readonly SECLAB_LAB_DIRS="recon notes loot screenshots exploits"

# --- Rutas -------------------------------------------------------------------

# ruta_workspace -> ruta absoluta del workspace configurado
#
# SECLAB_WORKSPACE puede ser relativa (./workspace, lo normal) o absoluta (un
# disco externo, por ejemplo). Se resuelve aquí una sola vez para que ningún
# comando tenga que volver a interpretarla.
ruta_workspace() {
    local ruta
    ruta="$(leer_variable "$ARCHIVO_ENV" SECLAB_WORKSPACE)"
    ruta="${ruta:-./workspace}"
    case "$ruta" in
        /*) printf '%s' "$ruta" ;;
        *)  printf '%s/%s' "$SECLAB_RAIZ" "${ruta#./}" ;;
    esac
}

# ruta_lab NOMBRE -> ruta absoluta de ese lab en el host
ruta_lab() {
    printf '%s/%s' "$(ruta_workspace)" "$1"
}

# ruta_lab_contenedor NOMBRE -> la ruta con la que se ve desde dentro del lab
ruta_lab_contenedor() {
    printf '/workspace/%s' "$1"
}

lab_existe() {
    [ -d "$(ruta_lab "$1")" ]
}

# labs_existentes -> nombres de los labs, alfabéticamente
#
# Se reconoce un lab por su ficha: un directorio cualquiera que el alumno haya
# dejado en el workspace no es un lab y no debe aparecer como si lo fuera.
labs_existentes() {
    local ws ficha
    ws="$(ruta_workspace)"
    [ -d "$ws" ] || return 0
    for ficha in "$ws"/*/scope.txt; do
        [ -f "$ficha" ] || continue
        basename "$(dirname "$ficha")"
    done
}

# --- Validación del nombre ---------------------------------------------------

# sugerir_slug TEXTO -> una versión del texto que sí sería válida
#
# Existe para que el mensaje de error diga «¿querías esto?» en lugar de sólo
# recitar la regla. Se hace con Python porque hay que quitar acentos, y hacerlo
# a mano en shell sale mal en cuanto aparece una ñ.
sugerir_slug() {
    printf '%s' "$1" | python3 -c '
import re, sys, unicodedata
texto = sys.stdin.read()
texto = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode()
texto = re.sub(r"[^a-zA-Z0-9]+", "-", texto).strip("-").lower()
sys.stdout.write(texto[:64].strip("-"))
' 2>/dev/null || true
}

# validar_slug NOMBRE -> 0 si es un nombre de lab utilizable
#
# La regla es estrecha a propósito: el nombre acaba siendo un directorio, parte
# de rutas dentro y fuera del contenedor, y argumento de comandos. Un espacio o
# un acento ahí se convierte en un problema que aparece tres pasos después, en
# otro sitio y sin relación aparente.
validar_slug() {
    local nombre="$1" sugerencia

    if [ -z "$nombre" ]; then
        error "Falta el nombre del lab." \
              "No se ha creado nada." \
              "Uso: seclab lab create NOMBRE [--vpn PERFIL]"
        return 1
    fi

    if [ "${#nombre}" -gt "$SECLAB_SLUG_MAX" ]; then
        error "El nombre tiene ${#nombre} caracteres y el máximo son ${SECLAB_SLUG_MAX}." \
              "No se ha creado nada." \
              "Usa algo más corto: el nombre es para localizar el lab, no para describirlo."
        return 1
    fi

    if printf '%s' "$nombre" | grep -Eq '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'; then
        return 0
    fi

    sugerencia="$(sugerir_slug "$nombre")"
    error "'${nombre}' no es un nombre de lab válido." \
          "No se ha creado nada." \
          "Sólo minúsculas, dígitos y guiones, empezando y acabando por letra o dígito."
    if [ -n "$sugerencia" ] && [ "$sugerencia" != "$nombre" ]; then
        detalle "¿Querías esto?  seclab lab create ${sugerencia}"
    fi
    detalle "El nombre acaba siendo un directorio y parte de rutas dentro y fuera"
    detalle "del contenedor: un espacio o un acento ahí da problemas más tarde."
    return 1
}

# --- Perfiles de VPN ---------------------------------------------------------

perfiles_vpn_validos() { echo "vpnhtb vpntry vpncli"; }

perfil_vpn_valido() {
    case " $(perfiles_vpn_validos) " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# rangos_del_perfil PERFIL -> los rangos declarados para ese perfil
#
# Se leen de vpn/<perfil>/perfil.env, que es del alumno, y si todavía no existe
# de la plantilla, que trae valores de ejemplo. Se distingue con claridad: unos
# rangos de ejemplo escritos en la ficha del lab como si fueran ciertos serían
# peores que no tener ninguno.
rangos_del_perfil() {
    local perfil="$1" propio plantilla valor
    propio="${SECLAB_RAIZ}/vpn/${perfil}/perfil.env"
    plantilla="${SECLAB_RAIZ}/templates/vpn/${perfil}/perfil.env.example"

    if [ -f "$propio" ]; then
        valor="$(grep -m1 '^SECLAB_VPN_RANGOS=' "$propio" 2>/dev/null | cut -d= -f2- | tr -d '"')"
        if [ -n "$valor" ]; then
            printf '%s' "$valor"
            return 0
        fi
    fi
    if [ -f "$plantilla" ]; then
        valor="$(grep -m1 '^SECLAB_VPN_RANGOS=' "$plantilla" 2>/dev/null | cut -d= -f2- | tr -d '"')"
        if [ -n "$valor" ]; then
            printf '%s (ejemplo de la plantilla: confírmalo con «seclab vpn status»)' "$valor"
            return 0
        fi
    fi
    printf 'sin declarar'
}

# perfil_vpn_del_lab NOMBRE -> el perfil que declara su ficha, o vacío
perfil_vpn_del_lab() {
    local ficha
    ficha="$(ruta_lab "$1")/scope.txt"
    [ -f "$ficha" ] || return 0
    grep -m1 '^Perfil:' "$ficha" 2>/dev/null | cut -d: -f2- | tr -d '[:space:]'
}

# avisar_desajuste_vpn NOMBRE
#
# Si el lab declara un perfil de VPN y no está entre los activos, se avisa. No
# se bloquea nada: puede haber razones para trabajar sin túnel, y el alumno es
# quien decide. Lo que no debe pasar es que lance un escaneo creyendo que va
# por el túnel de la plataforma cuando va por su red doméstica.
#
# Se consulta con vpn_perfiles_activos() (lib/docker.sh, `docker exec` a
# 'lab'), no leyendo .env: con el diseño de la Fase 7 pueden estar activos
# varios perfiles a la vez, y .env dejó de ser la fuente de verdad — ver
# docs/vpn.md.
avisar_desajuste_vpn() {
    local nombre="$1" del_lab activos
    del_lab="$(perfil_vpn_del_lab "$nombre")"
    if [ -z "$del_lab" ] || [ "$del_lab" = "ninguno" ]; then
        return 0
    fi

    activos="$(vpn_perfiles_activos)"
    if printf '%s\n' "$activos" | grep -qx "$del_lab"; then
        return 0
    fi

    if [ -z "$activos" ]; then
        aviso "El lab '${nombre}' declara el perfil de VPN '${del_lab}' y ninguno está activo."
        detalle "Tu tráfico saldría por tu red, no por el túnel de la plataforma."
        detalle "Actívalo con: seclab vpn up ${del_lab}"
    else
        aviso "El lab '${nombre}' declara '${del_lab}' pero el/los perfil(es) activo(s) son: $(printf '%s' "$activos" | tr '\n' ' ' | sed 's/ $//')."
        detalle "Comprueba que estás trabajando donde crees: seclab vpn status"
    fi
    return 0
}

# --- Plantillas --------------------------------------------------------------

# expandir_plantilla ORIGEN DESTINO NOMBRE PERFIL_VPN RANGOS
#
# Sustitución literal, sin `sed s///` sobre valores que pueden traer barras:
# los rangos llevan «/» y el separador de sed se rompería.
expandir_plantilla() {
    local origen="$1" destino="$2" nombre="$3" perfil="$4" rangos="$5"
    NOMBRE_LAB="$nombre" PERFIL_VPN="$perfil" RANGOS_VPN="$rangos" \
    FECHA="$(date '+%Y-%m-%d')" \
    python3 - "$origen" "$destino" <<'PY'
import os, sys
origen, destino = sys.argv[1], sys.argv[2]
with open(origen, encoding="utf-8") as f:
    contenido = f.read()
for clave in ("NOMBRE_LAB", "PERFIL_VPN", "RANGOS_VPN", "FECHA"):
    contenido = contenido.replace("{{%s}}" % clave, os.environ.get(clave, ""))
with open(destino, "w", encoding="utf-8") as f:
    f.write(contenido)
PY
}
