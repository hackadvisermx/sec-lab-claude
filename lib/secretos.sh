#!/usr/bin/env bash
# =============================================================================
# SecLab — generación de secretos y llaves
# =============================================================================
# No hay contraseñas por defecto. Todo lo que se genera aquí es aleatorio y
# distinto en cada instalación.
# =============================================================================

# generar_secreto [BYTES] -> cadena segura para URL
generar_secreto() {
    local bytes="${1:-32}"
    if existe_comando openssl; then
        openssl rand -base64 "$bytes" | tr -d '\n=+/' | cut -c1-43
    else
        python3 -c "import secrets,sys; sys.stdout.write(secrets.token_urlsafe(int(sys.argv[1])))" "$bytes"
    fi
}

# localizar_llave_ssh -> imprime la ruta de la llave PRIVADA del laboratorio
#
# SecLab usa una llave dedicada, no la personal del usuario. Es más predecible
# en un aula (muchos alumnos no tienen llave propia), mantiene el laboratorio
# autocontenido para las copias de seguridad, y evita mezclar la identidad
# personal de alguien con un contenedor de prácticas.
#
# Quien prefiera usar su propia llave puede poner su parte pública en
# SECLAB_SSH_PUBKEY dentro de .env: init respeta lo que ya esté configurado.
localizar_llave_ssh() {
    local dedicada="${SECLAB_RAIZ}/secretos/seclab_ed25519"

    if [ -f "$dedicada" ] && [ -f "${dedicada}.pub" ]; then
        printf '%s' "$dedicada"
        return 0
    fi

    install -d -m 0700 "${SECLAB_RAIZ}/secretos"
    ssh-keygen -q -t ed25519 -N '' -C "seclab@$(hostname -s 2>/dev/null || echo local)" -f "$dedicada"
    chmod 600 "$dedicada"
    chmod 644 "${dedicada}.pub"
    printf '%s' "$dedicada"
}

# escribir_variable ARCHIVO CLAVE VALOR
# Sustituye la línea si existe; la añade si no. No duplica claves.
escribir_variable() {
    local archivo="$1" clave="$2" valor="$3" tmp
    tmp="$(mktemp)"
    if grep -q "^${clave}=" "$archivo" 2>/dev/null; then
        # El valor puede contener caracteres especiales para sed; se reconstruye
        # el archivo con awk pasando el valor como variable, no como patrón.
        awk -v c="$clave" -v v="$valor" \
            'BEGIN{FS=OFS="="} $1==c {print c "=" v; hecho=1; next} {print} END{if(!hecho) print c "=" v}' \
            "$archivo" > "$tmp"
    else
        cat "$archivo" > "$tmp"
        printf '%s=%s\n' "$clave" "$valor" >> "$tmp"
    fi
    cat "$tmp" > "$archivo"
    rm -f "$tmp"
}

# leer_variable ARCHIVO CLAVE
#
# El `|| true` del grep importa: bajo `pipefail` (bin/seclab hace
# `set -euo pipefail`), que la clave no exista en el archivo es un resultado
# perfectamente válido para quien llama (significa "vacía"), pero sin esto
# `grep` sin coincidencias devuelve 1 y `pipefail` propaga ese 1 como salida
# de toda la tubería, aunque `cut` sí haya terminado bien. Una asignación
# `var="$(leer_variable ...)"` para una clave ausente moriría en silencio
# bajo `set -e` — encontrado de verdad probando SECLAB_OCI_SHAPE (Fase 11),
# una clave opcional que no todos los .env tienen todavía.
leer_variable() {
    [ -f "$1" ] || return 0
    { grep -m1 "^${2}=" "$1" 2>/dev/null || true; } | cut -d= -f2-
}
