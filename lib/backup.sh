#!/usr/bin/env bash
# =============================================================================
# SecLab — copias de seguridad
# =============================================================================
# Se carga con `source` desde bin/seclab. Depende de lib/comun.sh, lib/docker.sh
# y lib/secretos.sh, y de las variables SECLAB_RAIZ y ARCHIVO_ENV.
#
# Qué entra en una copia y por qué:
#
#   .env         la configuración y los secretos generados. Sin él, el
#                laboratorio restaurado no arranca.
#   secretos/    la llave SSH dedicada. Sin ella no se puede entrar.
#   vpn/         los perfiles y los .ovpn del alumno.
#   workspace/   el trabajo: labs, notas y evidencias. Lo único irreemplazable.
#   home.tar     el volumen del directorio personal, con el historial de shell
#                y las llaves de host SSH. Restaurarlas evita que el cliente
#                avise de un cambio de llave después de una restauración.
#
# El directorio personal se guarda como un tar dentro del tar, y no como una
# copia de archivos: así se conservan propietarios y permisos exactos con
# independencia del sistema de archivos del host, que en macOS y en Windows no
# los representa igual.
#
# Una copia contiene secretos en claro, así que se crea con permisos 600 y
# `backups/` está en .gitignore.
# =============================================================================

# Miembros sin los cuales una copia no sirve de nada. Se comprueban al crearla
# y al verificarla: es la defensa contra la copia vacía silenciosa, que es el
# peor fallo posible en una herramienta de respaldo —se descubre el día que hace
# falta restaurar—.
readonly SECLAB_COPIA_MIEMBROS='MANIFIESTO .env home.tar'

# Por debajo de esto no hay copia posible: sólo .env y el manifiesto comprimidos
# ya pasan de 1 KB.
readonly SECLAB_COPIA_MINIMO_BYTES=1024

readonly SECLAB_COPIA_FORMATO=1

# --- Utilidades --------------------------------------------------------------

directorio_copias() {
    local dir
    dir="$(leer_variable "$ARCHIVO_ENV" SECLAB_BACKUP_DIR)"
    printf '%s' "${dir:-${SECLAB_RAIZ}/backups}"
}

# sha256_de ARCHIVO -> sólo el hash
sha256_de() {
    if existe_comando sha256sum; then
        sha256sum "$1" | cut -d' ' -f1
    elif existe_comando shasum; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
    fi
}

tamano_bytes() {
    wc -c < "$1" | tr -d ' '
}

# Tamaño legible, sin depender de `du -h` ni de numfmt.
tamano_legible() {
    local bytes="$1"
    python3 - "$bytes" <<'PY'
import sys
b = float(sys.argv[1])
for unidad in ("B", "KB", "MB", "GB", "TB"):
    if b < 1024 or unidad == "TB":
        print(f"{b:.0f} {unidad}" if unidad == "B" else f"{b:.1f} {unidad}")
        break
    b /= 1024
PY
}

volumen_home() {
    local proyecto
    proyecto="$(leer_variable "$ARCHIVO_ENV" SECLAB_PROJECT)"
    printf '%s-home' "${proyecto:-seclab}"
}

volumen_existe() {
    docker volume inspect "$1" >/dev/null 2>&1
}

# --- Directorio personal (volumen nombrado) ----------------------------------
# El volumen no se puede leer desde el host: en macOS y Windows vive dentro de
# la VM de Docker. Se usa un contenedor auxiliar de la propia imagen del
# laboratorio, que ya está descargada, en lugar de traer otra imagen sólo para
# esto. Hay que sobreescribir el entrypoint: el de SecLab valida secretos y
# arranca sshd, que no es lo que queremos aquí.

# exportar_home RUTA_TAR
#   0 correcto · 2 el volumen no existe · 3 no hay imagen · 1 falló el tar
exportar_home() {
    local destino="$1" vol imagen
    vol="$(volumen_home)"
    imagen="$(leer_variable "$ARCHIVO_ENV" SECLAB_IMAGE)"

    volumen_existe "$vol" || return 2
    imagen_existe "$imagen" || return 3

    docker run --rm \
        -v "${vol}:/origen:ro" \
        -v "$(dirname "$destino"):/salida" \
        --entrypoint /usr/bin/tar \
        "$imagen" -cf "/salida/$(basename "$destino")" -C /origen . >/dev/null
}

# importar_home RUTA_TAR
# Vacía el volumen y lo repuebla. Destructivo: quien llama debe haber
# confirmado y haber detenido el laboratorio.
importar_home() {
    local origen="$1" vol imagen
    vol="$(volumen_home)"
    imagen="$(leer_variable "$ARCHIVO_ENV" SECLAB_IMAGE)"

    imagen_existe "$imagen" || return 3

    docker run --rm \
        -v "${vol}:/destino" \
        -v "$(dirname "$origen"):/origen:ro" \
        --entrypoint /bin/sh \
        "$imagen" -c "find /destino -mindepth 1 -delete && tar -xpf '/origen/$(basename "$origen")' -C /destino" >/dev/null
}

# marca_base_home -> el digest de la imagen base con la que se creó el volumen
#                    del directorio personal, o vacío si no se puede leer
#
# La marca la escribe el entrypoint la primera vez que prepara un volumen nuevo,
# y no se toca después: es la única forma de saber si el directorio personal
# viene de otra imagen base.
marca_base_home() {
    local vol imagen id
    vol="$(volumen_home)"
    volumen_existe "$vol" || return 0

    id="$(id_contenedor)"
    if [ -n "$id" ] && [ "$(estado_contenedor)" = "running" ]; then
        docker exec "$id" cat /etc/seclab/base-origen 2>/dev/null | tr -d '[:space:]'
        return 0
    fi

    imagen="$(leer_variable "$ARCHIVO_ENV" SECLAB_IMAGE)"
    imagen_existe "$imagen" || return 0
    docker run --rm -v "${vol}:/origen:ro" --entrypoint /bin/cat "$imagen" \
        /origen/.seclab/base-origen 2>/dev/null | tr -d '[:space:]'
}

# digest_base_dockerfile -> la base que declara el Dockerfile de este repositorio
digest_base_dockerfile() {
    awk -F= '/^ARG UBUNTU_DIGEST=/ {print $2; exit}' "${SECLAB_RAIZ}/docker/Dockerfile"
}

# --- Manifiesto --------------------------------------------------------------
# Formato clave=valor para que `restore` pueda leerlo sin interpretar nada.
escribir_manifiesto() {
    local ruta="$1" contenido="$2" con_workspace="$3" nombre_ws="$4" imagen
    imagen="$(leer_variable "$ARCHIVO_ENV" SECLAB_IMAGE)"

    cat > "$ruta" <<MANIFIESTO
# SecLab — manifiesto de copia de seguridad
# Generado automáticamente. No contiene secretos: los secretos van en .env,
# dentro de esta misma copia.
formato=${SECLAB_COPIA_FORMATO}
seclab_version=${SECLAB_VERSION}
fecha_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
proyecto=$(leer_variable "$ARCHIVO_ENV" SECLAB_PROJECT)
perfil=$(perfil_actual)
imagen=${imagen}
base_digest=$(digest_base_dockerfile)
sistema=$(detectar_so)
arquitectura=$(detectar_arquitectura)
contenido=${contenido}
workspace_incluido=${con_workspace}
# Nombre con el que el workspace viaja dentro de la copia. Se anota porque
# SECLAB_WORKSPACE es configurable: sin este dato, restaurar una copia hecha
# cuando el directorio se llamaba de otra forma no encontraría el contenido.
workspace_miembro=${nombre_ws}
MANIFIESTO
}

# valor_manifiesto ARCHIVO_MANIFIESTO CLAVE
valor_manifiesto() {
    grep -m1 "^${2}=" "$1" 2>/dev/null | cut -d= -f2-
}

# --- Listado -----------------------------------------------------------------

# copias_existentes -> rutas, de la más reciente a la más antigua
copias_existentes() {
    local dir
    dir="$(directorio_copias)"
    [ -d "$dir" ] || return 0
    # `ls -t` es suficiente y portable; los nombres los genera SecLab y no
    # contienen saltos de línea.
    ls -t "${dir}"/seclab-*.tar.gz 2>/dev/null || true
}

copia_reciente() {
    copias_existentes | head -1
}

# --- Verificación ------------------------------------------------------------
# La misma función se usa al terminar de crear una copia y desde
# `seclab backup verify`. Una copia recién creada se verifica siempre: si no se
# comprueba en el momento, el fallo aparece el día de la restauración.
#
# verificar_copia ARCHIVO -> 0 si la copia es utilizable
verificar_copia() {
    local archivo="$1" fallos=0 bytes hash_real hash_guardado miembros miembro modo

    if [ ! -f "$archivo" ]; then
        error "No existe la copia: ${archivo}" \
              "No hay nada que verificar." \
              "Lista las copias disponibles con 'seclab backup list'."
        return 1
    fi

    bytes="$(tamano_bytes "$archivo")"
    printf '  %-24s %s\n' "Archivo" "$(basename "$archivo")" >&2
    printf '  %-24s %s\n' "Tamaño" "$(tamano_legible "$bytes")" >&2

    if [ "$bytes" -lt "$SECLAB_COPIA_MINIMO_BYTES" ]; then
        error "La copia pesa ${bytes} bytes: está vacía o truncada." \
              "No serviría para restaurar nada." \
              "Bórrala y vuelve a ejecutar 'seclab backup'."
        fallos=$(( fallos + 1 ))
    fi

    # Permisos: la copia contiene .env y la llave SSH en claro. GNU `-c`
    # primero: en Linux, `stat -f` es una opción válida pero distinta ("info
    # del sistema de archivos"), así que nunca fallaría y el `||` no caería a
    # `-c` — devolvería basura en silencio en vez de permisos reales.
    modo="$(stat -c '%a' "$archivo" 2>/dev/null || stat -f '%Lp' "$archivo" 2>/dev/null)"
    if [ -n "$modo" ] && [ "$modo" != "600" ]; then
        aviso "Los permisos de la copia son ${modo}, no 600."
        detalle "Contiene secretos en claro. Corrígelo con: chmod 600 '${archivo}'"
    fi

    # Suma de comprobación
    if [ -f "${archivo}.sha256" ]; then
        hash_guardado="$(cut -d' ' -f1 < "${archivo}.sha256")"
        hash_real="$(sha256_de "$archivo")"
        if [ "$hash_guardado" = "$hash_real" ]; then
            printf '  %s %s\n' "${C_VERDE}✓${C_FIN}" "Suma SHA-256 correcta" >&2
        else
            error "La suma SHA-256 no coincide." \
                  "La copia está corrupta o se ha modificado desde que se creó." \
                  "No la uses para restaurar. Crea una nueva con 'seclab backup'."
            fallos=$(( fallos + 1 ))
        fi
    else
        aviso "No hay archivo .sha256 junto a la copia; no se puede comprobar su integridad."
    fi

    # Integridad del contenedor tar y miembros mínimos
    if ! miembros="$(tar -tzf "$archivo" 2>/dev/null)"; then
        error "El archivo no es un tar.gz legible." \
              "La copia no se puede restaurar." \
              "Crea una nueva con 'seclab backup'."
        return 1
    fi

    for miembro in $SECLAB_COPIA_MIEMBROS; do
        # Comparación literal de línea completa, sin expresiones regulares: los
        # nombres llevan puntos y una regex daría falsos positivos.
        if printf '%s\n' "$miembros" | sed 's|^\./||' | grep -Fqx "$miembro"; then
            continue
        fi
        error "Falta '${miembro}' dentro de la copia." \
              "Una copia sin ese archivo no permite restaurar el laboratorio." \
              "Crea una nueva con 'seclab backup' y revisa los avisos."
        fallos=$(( fallos + 1 ))
    done

    printf '  %-24s %s\n' "Entradas" "$(printf '%s\n' "$miembros" | grep -c . )" >&2

    # Resumen del manifiesto, extraído a memoria: da contexto de qué se
    # restauraría antes de tocar nada.
    local manifiesto
    if manifiesto="$(tar -xzOf "$archivo" ./MANIFIESTO 2>/dev/null || tar -xzOf "$archivo" MANIFIESTO 2>/dev/null)"; then
        local fecha perfil version workspace
        fecha="$(printf '%s\n' "$manifiesto" | grep -m1 '^fecha_utc=' | cut -d= -f2-)"
        perfil="$(printf '%s\n' "$manifiesto" | grep -m1 '^perfil=' | cut -d= -f2-)"
        version="$(printf '%s\n' "$manifiesto" | grep -m1 '^seclab_version=' | cut -d= -f2-)"
        workspace="$(printf '%s\n' "$manifiesto" | grep -m1 '^workspace_incluido=' | cut -d= -f2-)"
        printf '  %-24s %s\n' "Creada" "${fecha:-desconocida}" >&2
        printf '  %-24s %s\n' "SecLab / perfil" "${version:-?} / ${perfil:-?}" >&2
        printf '  %-24s %s\n' "Workspace incluido" "${workspace:-?}" >&2
        if [ "$workspace" = "no" ]; then
            aviso "Esta copia se creó con --sin-workspace: no contiene tu trabajo."
        fi
    fi

    [ "$fallos" -eq 0 ]
}
