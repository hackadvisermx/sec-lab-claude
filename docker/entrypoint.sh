#!/usr/bin/env bash
# =============================================================================
# SecLab — arranque del contenedor
# =============================================================================
# Se ejecuta como root para preparar el entorno y luego deja el laboratorio
# corriendo. Si falta configuración segura, aborta: no hay degradación
# silenciosa ni contraseñas de emergencia.
# =============================================================================

set -euo pipefail

USUARIO="${SECLAB_USUARIO:-seclab}"
HOGAR="/home/${USUARIO}"
ESTADO="${HOGAR}/.seclab"

fallo() {
    printf '\n[SecLab] ERROR: %s\n' "$1" >&2
    [ -n "${2:-}" ] && printf '[SecLab]   Solución: %s\n' "$2" >&2
    exit 1
}

aviso() { printf '[SecLab] AVISO: %s\n' "$1" >&2; }
paso()  { printf '[SecLab] %s\n' "$1" >&2; }

# -----------------------------------------------------------------------------
# 1. Qué servicios levanta este contenedor
# -----------------------------------------------------------------------------
# Una variable SECLAB_HABILITAR_* vacía significa «lo que corresponda al
# perfil»; con `true` o `false` manda el alumno. Así elegir el perfil `desktop`
# trae escritorio sin tener que activar tres variables a mano, y quien no lo
# quiera puede apagarlo sin cambiar de perfil.
PERFIL="${SECLAB_PERFIL:-lite}"

por_perfil() {
    case "$PERFIL" in
        desktop|full|full-msf)
            case "$1" in
                escritorio|code|web) printf 'true' ;;
                *) printf 'false' ;;
            esac
            ;;
        *) printf 'false' ;;
    esac
}

resolver_servicio() {
    local nombre="$1" valor="$2"
    case "$valor" in
        true|false) printf '%s' "$valor" ;;
        '') por_perfil "$nombre" ;;
        *) fallo "SECLAB_HABILITAR_${3} sólo acepta 'true', 'false' o vacío (según el perfil). Valor recibido: ${valor}" \
                 "Corrige la variable en .env." ;;
    esac
}

SERVICIO_ESCRITORIO="$(resolver_servicio escritorio "${SECLAB_HABILITAR_DESKTOP:-}" DESKTOP)"
SERVICIO_CODE="$(resolver_servicio code "${SECLAB_HABILITAR_CODE:-}" CODE)"
SERVICIO_WEB="$(resolver_servicio web "${SECLAB_HABILITAR_WEB:-}" WEB)"
SERVICIO_JUPYTER="$(resolver_servicio jupyter "${SECLAB_HABILITAR_JUPYTER:-}" JUPYTER)"

# Un servicio activado que la imagen no trae no puede quedarse en un aviso: el
# healthcheck lo buscaría, no lo encontraría y el laboratorio se quedaría
# `unhealthy` para siempre sin explicar por qué.
exigir_binario() {
    local binario="$1" servicio="$2" variable="$3"
    command -v "$binario" >/dev/null 2>&1 && return 0
    fallo "${servicio} está activado pero el perfil '${PERFIL}' no lo trae (falta ${binario})." \
          "Usa el perfil 'desktop' o superior, o pon ${variable}=false en .env."
}

# En forma de `if` y no de `[ ... ] && ...`: con `set -e`, una lista AND que
# falla aborta el script, y aquí lo normal es justo que la condición sea falsa.
# Debian y Ubuntu renombran las herramientas de TigerVNC y dejan el nombre
# clásico como alternativa. Se resuelve aquí, una vez, en lugar de confiar en
# que la alternativa exista.
VNCPASSWD=""
for candidato in vncpasswd tigervncpasswd; do
    if command -v "$candidato" >/dev/null 2>&1; then
        VNCPASSWD="$candidato"
        break
    fi
done

if [ "$SERVICIO_ESCRITORIO" = "true" ]; then
    exigir_binario Xvnc "el escritorio" SECLAB_HABILITAR_DESKTOP
    exigir_binario websockify "el acceso web al escritorio" SECLAB_HABILITAR_DESKTOP
    if [ -z "$VNCPASSWD" ]; then
        fallo "El escritorio está activado pero falta vncpasswd en la imagen." \
              "Reconstruye la imagen: falta el paquete tigervnc-tools."
    fi
fi
if [ "$SERVICIO_CODE" = "true" ]; then
    exigir_binario code-server "code-server" SECLAB_HABILITAR_CODE
fi
if [ "$SERVICIO_JUPYTER" = "true" ]; then
    exigir_binario jupyter "Jupyter" SECLAB_HABILITAR_JUPYTER
fi

# -----------------------------------------------------------------------------
# 2. Validar la configuración de seguridad antes de tocar nada
# -----------------------------------------------------------------------------
# Valores de relleno que no se aceptan nunca, ni siquiera en un lab local.
RELLENO='^(change-this-password|changeme|cambiame|password|passwd|123456|admin|secret|seclab|toor|kali)$'

for variable in SECLAB_VNC_PASSWORD SECLAB_CODE_PASSWORD SECLAB_JUPYTER_TOKEN SECLAB_MCP_TOKEN; do
    valor="${!variable:-}"
    [ -z "$valor" ] && continue
    if printf '%s' "$valor" | grep -Eqi "$RELLENO"; then
        fallo "${variable} usa un valor de relleno prohibido." \
              "Regenera los secretos con 'seclab init --regenerar-secretos'."
    fi
    if [ "${#valor}" -lt 16 ]; then
        fallo "${variable} tiene menos de 16 caracteres." \
              "Regenera los secretos con 'seclab init --regenerar-secretos'."
    fi
done

# Un servicio con autenticación no arranca sin su secreto. No hay modo
# «sin contraseña por esta vez»: un escritorio abierto en el puerto de un
# portátil de clase es exactamente lo que no debe pasar.
exigir_secreto() {
    local variable="$1" servicio="$2"
    [ -n "${!variable:-}" ] && return 0
    fallo "${servicio} está activado y ${variable} está vacía." \
          "Genera los secretos con 'seclab init' (no sobrescribe los que ya tengas)."
}

if [ "$SERVICIO_ESCRITORIO" = "true" ]; then
    exigir_secreto SECLAB_VNC_PASSWORD "El escritorio"
fi
if [ "$SERVICIO_CODE" = "true" ]; then
    exigir_secreto SECLAB_CODE_PASSWORD "code-server"
fi
if [ "$SERVICIO_JUPYTER" = "true" ]; then
    exigir_secreto SECLAB_JUPYTER_TOKEN "Jupyter"
fi

if [ -z "${SECLAB_SSH_PUBKEY:-}" ]; then
    fallo "No hay llave pública SSH configurada y el acceso por contraseña está deshabilitado." \
          "Ejecuta 'seclab init', que genera o localiza tu llave y la inyecta."
fi

case "${SECLAB_SSH_PUBKEY}" in
    ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *|sk-ssh-*\ *) : ;;
    *) fallo "SECLAB_SSH_PUBKEY no parece una llave pública SSH válida." \
             "Debe empezar por ssh-ed25519, ssh-rsa o ecdsa-sha2-*." ;;
esac

# -----------------------------------------------------------------------------
# 3. Estado persistente
# -----------------------------------------------------------------------------
# Antes de crear nada: ¿es la primera vez que se prepara este volumen? Se sabe
# por la ausencia del directorio de estado, que sólo crea este entrypoint. La
# distinción importa para la marca de la imagen base de más abajo.
if [ -d "$ESTADO" ]; then VOLUMEN_NUEVO=no; else VOLUMEN_NUEVO=si; fi

install -d -m 0700 -o "$USUARIO" -g "$USUARIO" "$ESTADO"
install -d -m 0700 -o "$USUARIO" -g "$USUARIO" "${ESTADO}/ssh"
install -d -m 0700 -o "$USUARIO" -g "$USUARIO" "${HOGAR}/.ssh"

# El workspace viene del host: puede llegar con otro propietario según el
# sistema de archivos. Se ajusta sin recursión completa para no tardar una
# eternidad en workspaces grandes.
if [ -d /workspace ]; then
    chown "${USUARIO}:${USUARIO}" /workspace 2>/dev/null || \
        aviso "No se pudo cambiar el propietario de /workspace. Si el montaje es de sólo lectura, es lo esperado."
fi

# -----------------------------------------------------------------------------
# 4. Llave autorizada
# -----------------------------------------------------------------------------
printf '%s\n' "${SECLAB_SSH_PUBKEY}" > "${HOGAR}/.ssh/authorized_keys"
chmod 0600 "${HOGAR}/.ssh/authorized_keys"
chown "${USUARIO}:${USUARIO}" "${HOGAR}/.ssh/authorized_keys"

# -----------------------------------------------------------------------------
# 4a. Marca de la imagen base con la que se creó este volumen
# -----------------------------------------------------------------------------
# Un volumen nombrado sobrevive a la reconstrucción de la imagen. Al cambiar de
# base, el directorio personal conserva restos de la anterior: es el fallo que
# dejó un .bashrc de Kali dentro de un laboratorio Ubuntu. Para poder detectarlo
# se anota qué base creó el volumen, y esa anotación no se toca nunca más: si se
# actualizara en cada arranque, la discrepancia desaparecería justo cuando hay
# que verla.
DIGEST_BASE="$(cat /opt/seclab/base-digest 2>/dev/null || true)"
DIGEST_BASE="${DIGEST_BASE:-desconocido}"

if [ ! -f "${ESTADO}/base-origen" ]; then
    if [ "$VOLUMEN_NUEVO" = "si" ]; then
        printf '%s\n' "$DIGEST_BASE" > "${ESTADO}/base-origen"
    else
        # El volumen ya existía y viene de una versión de SecLab que no dejaba
        # marca. No se puede afirmar sobre qué base se creó, y decir que fue
        # esta sería mentir: se registra como desconocido.
        printf 'desconocido\n' > "${ESTADO}/base-origen"
    fi
    chown "${USUARIO}:${USUARIO}" "${ESTADO}/base-origen"
fi

BASE_ORIGEN="$(cat "${ESTADO}/base-origen" 2>/dev/null || echo desconocido)"
if [ "$BASE_ORIGEN" != "$DIGEST_BASE" ]; then
    aviso "El directorio personal se creó sobre otra imagen base."
    aviso "  creado con: ${BASE_ORIGEN}"
    aviso "  base actual: ${DIGEST_BASE}"
    aviso "Puede arrastrar configuración de la base anterior. 'seclab doctor' ofrece recrearlo."
fi

# -----------------------------------------------------------------------------
# 4b. Entorno visible para las sesiones SSH
# -----------------------------------------------------------------------------
# sshd NO hereda el entorno del proceso principal del contenedor: una sesión SSH
# arranca con un entorno limpio. Por eso los datos que el banner necesita se
# escriben en un archivo que cualquier sesión puede leer, venga de SSH o de
# `docker exec`.
#
# Aquí sólo van datos públicos. Ningún secreto, ningún token.
install -d -m 0755 /etc/seclab
cat > /etc/seclab/entorno <<ENTORNO
# Generado por el entrypoint en cada arranque. No editar a mano.
SECLAB_VERSION="${SECLAB_VERSION:-desconocida}"
SECLAB_PERFIL="${SECLAB_PERFIL:-lite}"
SECLAB_GLIFOS="${SECLAB_GLIFOS:-powerline}"
ENTORNO
chmod 0644 /etc/seclab/entorno

# La marca del volumen, publicada donde `seclab doctor` la pueda leer con un
# simple `docker exec cat`, sin tener que montar el volumen aparte.
printf '%s\n' "$BASE_ORIGEN" > /etc/seclab/base-origen
chmod 0644 /etc/seclab/base-origen

# 4c. Configuración de shell en el directorio personal
# -----------------------------------------------------------------------------
# El home es un volumen: sobrevive a la reconstrucción de la imagen. Por eso los
# archivos que se crean aquí son punteros mínimos a /opt/seclab/shell, que sí
# viaja en la imagen. Al reconstruir, la configuración se actualiza sola.
#
# Nunca se sobrescribe lo que ya exista: si el alumno editó algo, es suyo.
crear_si_falta() {
    local destino="$1" contenido="$2"
    [ -e "$destino" ] && return 0
    printf '%s\n' "$contenido" > "$destino"
    chown "${USUARIO}:${USUARIO}" "$destino"
}

paso "Preparando la configuración de shell"
crear_si_falta "${HOGAR}/.zshrc" \
    "# Cargado desde la imagen. Personaliza en ~/.zshrc.local, que no se toca.
source /opt/seclab/shell/zshrc"

# .tmux.conf tiene que ser un enlace al archivo real, no un envoltorio que lo
# cargue con source-file. Oh my tmux! aplica su tema ejecutando un script de
# shell incrustado en sus propios comentarios (`cut -c3- "$TMUX_CONF" | sh`), y
# para eso $TMUX_CONF debe apuntar a un archivo que contenga ese script. Con un
# envoltorio, tmux arranca sin errores pero se queda con el tema por defecto.
if [ ! -L "${HOGAR}/.tmux.conf" ]; then
    rm -f "${HOGAR}/.tmux.conf"
    ln -s /opt/seclab/shell/tmux/.tmux.conf "${HOGAR}/.tmux.conf"
    chown -h "${USUARIO}:${USUARIO}" "${HOGAR}/.tmux.conf"
fi

# Este sí es una copia y no un puntero: es el archivo que se espera que el
# alumno ajuste a su gusto.
#
# Hay dos variantes en la imagen: la del curso, con separadores Powerline, y una
# ASCII para terminales sin Nerd Font (SECLAB_GLIFOS=ascii, que activa
# `seclab doctor` tras preguntar si se ven los glifos).
#
# Cambiar de variante no puede pisar las ediciones del alumno. Se compara el
# archivo con las dos variantes de la imagen: si coincide con una, nadie lo ha
# tocado y se puede sustituir; si no coincide con ninguna, es suyo y sólo se
# le dice qué cambiar.
VARIANTE_TMUX=/opt/seclab/shell/tmux.conf.local
[ "${SECLAB_GLIFOS:-powerline}" = "ascii" ] && \
    VARIANTE_TMUX=/opt/seclab/shell/tmux.conf.local.ascii

sha_de() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

if [ ! -e "${HOGAR}/.tmux.conf.local" ]; then
    cp "$VARIANTE_TMUX" "${HOGAR}/.tmux.conf.local"
    chown "${USUARIO}:${USUARIO}" "${HOGAR}/.tmux.conf.local"
elif [ "$(sha_de "${HOGAR}/.tmux.conf.local")" != "$(sha_de "$VARIANTE_TMUX")" ]; then
    actual="$(sha_de "${HOGAR}/.tmux.conf.local")"
    if [ "$actual" = "$(sha_de /opt/seclab/shell/tmux.conf.local)" ] || \
       [ "$actual" = "$(sha_de /opt/seclab/shell/tmux.conf.local.ascii)" ]; then
        cp "$VARIANTE_TMUX" "${HOGAR}/.tmux.conf.local"
        chown "${USUARIO}:${USUARIO}" "${HOGAR}/.tmux.conf.local"
        paso "Barra de estado: variante '${SECLAB_GLIFOS:-powerline}' aplicada"
    else
        aviso "Tu ~/.tmux.conf.local está editado: no se toca."
        aviso "Para la variante '${SECLAB_GLIFOS:-powerline}', copia estas cuatro líneas de"
        aviso "${VARIANTE_TMUX} a tu archivo:"
        grep -E '^tmux_conf_theme_(left|right)_separator_(main|sub)=' "$VARIANTE_TMUX" >&2 || true
    fi
fi

# 5. Llaves de host persistentes
# -----------------------------------------------------------------------------
# Si se regeneraran en cada arranque, tu cliente SSH avisaría de un cambio de
# llave cada vez, y acabarías ignorando ese aviso. Que es justo lo contrario de
# lo que debe pasar.
if [ ! -f "${ESTADO}/ssh/ssh_host_ed25519_key" ]; then
    paso "Generando llaves de host SSH (primera vez)"
    ssh-keygen -q -t ed25519 -N '' -f "${ESTADO}/ssh/ssh_host_ed25519_key"
    ssh-keygen -q -t rsa -b 4096 -N '' -f "${ESTADO}/ssh/ssh_host_rsa_key"
    chown -R "${USUARIO}:${USUARIO}" "${ESTADO}/ssh"
fi
chmod 0600 "${ESTADO}/ssh/"*_key
chmod 0644 "${ESTADO}/ssh/"*_key.pub

cat > /etc/ssh/sshd_config.d/20-hostkeys.conf <<CONF
HostKey ${ESTADO}/ssh/ssh_host_ed25519_key
HostKey ${ESTADO}/ssh/ssh_host_rsa_key
CONF
chmod 0644 /etc/ssh/sshd_config.d/20-hostkeys.conf

# -----------------------------------------------------------------------------
# 6. Servicios
# -----------------------------------------------------------------------------
# Todo lo que hay que mantener vivo lo arranca supervisor, también cuando es un
# solo proceso. Dos caminos de arranque —uno para `lite` y otro para los
# perfiles con escritorio— serían dos verdades que acabarían discrepando.
#
# Los servicios que necesitan contraseña se preparan antes de escribir la
# configuración, para que un fallo aquí no deje a supervisor reintentando algo
# que no puede funcionar.

if ! /usr/sbin/sshd -t; then
    fallo "La configuración de SSH no es válida." \
          "Revisa la salida anterior; es un error de la imagen, no de tu instalación."
fi
install -d -m 0755 /run/sshd
install -d -m 0755 /run/seclab
# Estado de seclab-vpn (Fase 7): PID, log y directorio por perfil activo. Vive
# en /run, así que un contenedor recreado siempre arranca sin restos de una
# sesión de VPN anterior; uno simplemente reiniciado los limpia solo la
# primera vez que se intenta un 'seclab-vpn up' (comprueba que el PID siga
# vivo antes de confiar en cualquier estado que encuentre aquí).
install -d -m 0755 /run/seclab-vpn

# XFCE, dbus y code-server escriben en el directorio de ejecución del usuario.
# Sin él fallan de formas que no señalan la causa.
DIR_EJECUCION="/run/user/$(id -u "$USUARIO")"
install -d -m 0700 -o "$USUARIO" -g "$USUARIO" "$DIR_EJECUCION"

# --- Escritorio: contraseña de VNC ------------------------------------------
if [ "$SERVICIO_ESCRITORIO" = "true" ]; then
    install -d -m 0700 -o "$USUARIO" -g "$USUARIO" "${HOGAR}/.vnc"
    # El protocolo VNC trunca la contraseña a 8 caracteres: es una limitación
    # del propio VncAuth, no de SecLab, y está documentada en SECURITY.md. La
    # defensa real es que el puerto sólo se publica en 127.0.0.1 y que Xvnc
    # escucha con -localhost, de modo que sólo websockify puede conectarse.
    printf '%s' "$SECLAB_VNC_PASSWORD" | "$VNCPASSWD" -f > "${HOGAR}/.vnc/passwd"
    chmod 0600 "${HOGAR}/.vnc/passwd"
    chown "${USUARIO}:${USUARIO}" "${HOGAR}/.vnc/passwd"
    paso "Escritorio XFCE en :1, accesible por noVNC"
fi

# --- Página de bienvenida ----------------------------------------------------
if [ "$SERVICIO_WEB" = "true" ]; then
    install -d -m 0755 /run/seclab/web
    SECLAB_HABILITAR_DESKTOP="$SERVICIO_ESCRITORIO" \
    SECLAB_HABILITAR_CODE="$SERVICIO_CODE" \
    SECLAB_HABILITAR_JUPYTER="$SERVICIO_JUPYTER" \
        /usr/local/bin/seclab-bienvenida /run/seclab/web/index.html
    paso "Página de bienvenida generada"
fi

# --- Configuración de supervisor --------------------------------------------
# Se escribe en cada arranque a partir de los servicios resueltos: si un
# servicio está apagado, su programa no existe, y así no puede reportarse como
# caído ni aparecer en los logs.
CONF_SUP=/run/seclab/supervisord.conf

registrar_programa() {
    # registrar_programa NOMBRE USUARIO DIRECTORIO ENTORNO COMANDO...
    local nombre="$1" usuario="$2" directorio="$3" entorno="$4"
    shift 4
    {
        printf '\n[program:%s]\n' "$nombre"
        printf 'command=%s\n' "$*"
        printf 'user=%s\n' "$usuario"
        printf 'directory=%s\n' "$directorio"
        [ -n "$entorno" ] && printf 'environment=%s\n' "$entorno"
        printf 'autostart=true\n'
        printf 'autorestart=true\n'
        printf 'startretries=3\n'
        printf 'stopasgroup=true\n'
        printf 'killasgroup=true\n'
        # Los logs van a la salida del contenedor, para que `docker logs` y
        # `seclab logs` los vean sin entrar a buscarlos.
        printf 'stdout_logfile=/dev/fd/1\n'
        printf 'stdout_logfile_maxbytes=0\n'
        printf 'redirect_stderr=true\n'
    } >> "$CONF_SUP"
}

# El socket de control de supervisor lleva credenciales aleatorias de este
# arranque. Sin ellas, supervisor escribe en cada arranque un CRIT avisando de
# que el servidor de control no tiene autenticación: un aviso correcto, pero
# que aparecería siempre y acabaría enseñando a ignorar los avisos. El socket
# ya está limitado a root (0700) y el archivo también, así que la contraseña no
# es la defensa: es lo que permite que no haya ruido.
SUP_USUARIO=seclab-supervisor
SUP_CLAVE="$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | cut -c1-24)"

cat > "$CONF_SUP" <<SUPERVISOR
# Generado por el entrypoint en cada arranque. No editar a mano.
[supervisord]
nodaemon=true
user=root
logfile=/dev/null
logfile_maxbytes=0
pidfile=/run/seclab/supervisord.pid
loglevel=info

[unix_http_server]
file=/run/seclab/supervisor.sock
chmod=0700
username=${SUP_USUARIO}
password=${SUP_CLAVE}

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///run/seclab/supervisor.sock
username=${SUP_USUARIO}
password=${SUP_CLAVE}
SUPERVISOR

registrar_programa sshd root / "" /usr/sbin/sshd -D -e

if [ "$SERVICIO_ESCRITORIO" = "true" ]; then
    # Xvnc es servidor X y servidor VNC en un solo proceso. `-localhost` deja
    # el 5901 accesible sólo desde dentro del contenedor: quien entra de fuera
    # lo hace por noVNC, en el puerto publicado en 127.0.0.1.
    registrar_programa escritorio-x "$USUARIO" "$HOGAR" \
        "HOME=\"${HOGAR}\",USER=\"${USUARIO}\",XDG_RUNTIME_DIR=\"${DIR_EJECUCION}\"" \
        /usr/bin/Xvnc :1 \
            -geometry "${SECLAB_RESOLUCION:-1440x900}" \
            -depth 24 \
            -rfbport 5901 \
            -rfbauth "${HOGAR}/.vnc/passwd" \
            -SecurityTypes VncAuth \
            -localhost \
            -AlwaysShared \
            -desktop SecLab

    # La sesión de escritorio va en su propio programa: si XFCE se cae, se
    # reinicia sin tirar el servidor X ni la conexión del navegador.
    registrar_programa escritorio-sesion "$USUARIO" "$HOGAR" \
        "HOME=\"${HOGAR}\",USER=\"${USUARIO}\",DISPLAY=\":1\",XDG_RUNTIME_DIR=\"${DIR_EJECUCION}\",LANG=\"C.UTF-8\"" \
        /opt/seclab/desktop/xstartup

    # websockify hace el puente entre el WebSocket del navegador y el 5901.
    registrar_programa novnc "$USUARIO" "$HOGAR" "HOME=\"${HOGAR}\"" \
        /usr/bin/websockify --web=/usr/share/novnc 0.0.0.0:6080 127.0.0.1:5901
fi

if [ "$SERVICIO_CODE" = "true" ]; then
    # La contraseña llega por entorno: code-server la lee de PASSWORD y así no
    # queda escrita en ningún archivo de configuración del volumen.
    registrar_programa code-server "$USUARIO" /workspace \
        "HOME=\"${HOGAR}\",USER=\"${USUARIO}\",XDG_RUNTIME_DIR=\"${DIR_EJECUCION}\",PASSWORD=\"${SECLAB_CODE_PASSWORD}\"" \
        /usr/bin/code-server \
            --bind-addr 0.0.0.0:8443 \
            --auth password \
            --disable-telemetry \
            --disable-update-check \
            /workspace
fi

if [ "$SERVICIO_WEB" = "true" ]; then
    registrar_programa bienvenida "$USUARIO" /run/seclab/web "HOME=\"${HOGAR}\"" \
        /usr/bin/python3 -m http.server 8080 --bind 0.0.0.0 --directory /run/seclab/web
fi

# 0600 y de root: la línea de entorno de code-server lleva su contraseña. No
# añade exposición —el secreto ya viaja como variable del contenedor, visible
# con `docker inspect`— pero no hay razón para dejarlo legible de más.
chmod 0600 "$CONF_SUP"

# --- Servicios activos, para el healthcheck ---------------------------------
# El healthcheck tiene que evaluar exactamente los servicios que se han
# levantado, ni uno más. Si los resolviera por su cuenta a partir de las mismas
# variables, habría dos implementaciones de la misma decisión y algún día
# dirían cosas distintas. Se escribe aquí la lista y allí se lee.
{
    printf 'ssh\n'
    [ "$SERVICIO_ESCRITORIO" = "true" ] && printf 'escritorio\n'
    [ "$SERVICIO_CODE" = "true" ] && printf 'code\n'
    [ "$SERVICIO_WEB" = "true" ] && printf 'web\n'
    [ "$SERVICIO_JUPYTER" = "true" ] && printf 'jupyter\n'
    true
} > /run/seclab/servicios
chmod 0644 /run/seclab/servicios

# -----------------------------------------------------------------------------
# 7. Resumen y arranque
# -----------------------------------------------------------------------------
paso "Perfil: ${PERFIL} · usuario: ${USUARIO}"
if [ -r /opt/seclab/manifiesto-herramientas.txt ]; then
    total="$(grep -c '^|' /opt/seclab/manifiesto-herramientas.txt 2>/dev/null || echo 0)"
    paso "Manifiesto de herramientas: ${total} entradas en /opt/seclab/manifiesto-herramientas.txt"
fi
paso "Servicios: $(grep -c '^\[program:' "$CONF_SUP")"
paso "Laboratorio listo."

case "${1:-dormir}" in
    dormir)
        # supervisor queda como PID 1 (con `init: true` en Compose, como su
        # hijo directo): mantiene los servicios vivos y el healthcheck
        # comprueba que además respondan.
        exec /usr/bin/supervisord -c "$CONF_SUP"
        ;;
    *)
        exec "$@"
        ;;
esac
