#!/usr/bin/env bash
# =============================================================================
# SecLab — smoke tests por perfil
# =============================================================================
# Comprueba, sobre un laboratorio ya arrancado, que lo que el perfil promete
# funciona de verdad: no que los archivos existan, sino que los servicios
# respondan, que la autenticación rechace lo que debe rechazar y que ningún
# secreto se escape por una salida pública.
#
#   scripts/smoke.sh              # el perfil configurado en .env
#   scripts/smoke.sh desktop      # exige además los servicios del escritorio
#
# Sale con 1 si falla algo. Cada comprobación dice qué se esperaba.
# =============================================================================

set -uo pipefail

SECLAB_RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SECLAB_RAIZ

# shellcheck source=../lib/comun.sh
. "${SECLAB_RAIZ}/lib/comun.sh"
# shellcheck source=../lib/plataforma.sh
. "${SECLAB_RAIZ}/lib/plataforma.sh"
# shellcheck source=../lib/docker.sh
. "${SECLAB_RAIZ}/lib/docker.sh"
# shellcheck source=../lib/secretos.sh
. "${SECLAB_RAIZ}/lib/secretos.sh"

readonly ARCHIVO_ENV="${SECLAB_RAIZ}/.env"

perfil_actual() {
    local p
    p="$(leer_variable "$ARCHIVO_ENV" SECLAB_PERFIL)"
    printf '%s' "${p:-lite}"
}

PERFIL="${1:-$(perfil_actual)}"
FALLOS=0
PRUEBAS=0

pasa() { PRUEBAS=$(( PRUEBAS + 1 )); printf '  %s %s\n' "${C_VERDE}✓${C_FIN}" "$1" >&2; }
falla() {
    PRUEBAS=$(( PRUEBAS + 1 )); FALLOS=$(( FALLOS + 1 ))
    printf '  %s %s\n' "${C_ROJO}✗${C_FIN}" "$1" >&2
    [ -n "${2:-}" ] && printf '      %s\n' "${C_GRIS}esperado: $2${C_FIN}" >&2
    return 0
}

# comprobar "descripción" "esperado" comando...
comprobar() {
    local descripcion="$1" esperado="$2"
    shift 2
    if "$@" >/dev/null 2>&1; then pasa "$descripcion"; else falla "$descripcion" "$esperado"; fi
}

# contiene "texto" comando... -> 0 si la salida del comando contiene el texto
#
# La salida se captura antes de filtrarla, y no se hace `comando | grep`: con
# `pipefail`, una herramienta que imprime lo correcto pero termina con código
# distinto de cero —msfvenom --help, ssh al rechazar una contraseña— haría
# fallar la tubería entera y la comprobación daría un falso negativo. Ya pasó
# dos veces al escribir este script.
contiene() {
    local texto="$1" salida
    shift
    salida="$("$@" 2>&1 || true)"
    printf '%s' "$salida" | grep -qF -- "$texto"
}

# --- Preparación -------------------------------------------------------------
if [ ! -f "$ARCHIVO_ENV" ]; then
    abortar "No hay .env: el laboratorio no está inicializado." \
            "No hay nada que probar." \
            "Ejecuta 'seclab init'."
fi

ID="$(id_contenedor)"
if [ -z "$ID" ] || [ "$(estado_contenedor)" != "running" ]; then
    abortar "El laboratorio no está en marcha." \
            "Los smoke tests se ejecutan contra un laboratorio arrancado." \
            "Ejecuta 'seclab start' y repite."
fi

USUARIO="$(leer_variable "$ARCHIVO_ENV" SECLAB_USUARIO)"; USUARIO="${USUARIO:-seclab}"
PUERTO_SSH="$(leer_variable "$ARCHIVO_ENV" SECLAB_PUERTO_SSH)"; PUERTO_SSH="${PUERTO_SSH:-2222}"
LLAVE="$(leer_variable "$ARCHIVO_ENV" SECLAB_SSH_LLAVE)"
BIND="$(leer_variable "$ARCHIVO_ENV" SECLAB_BIND)"; BIND="${BIND:-127.0.0.1}"

en_lab() { docker exec "$ID" "$@"; }
como_usuario() { docker exec -u "$USUARIO" "$ID" "$@"; }

# http_codigo URL -> imprime el código HTTP
http_codigo() {
    curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$1" 2>/dev/null
}
codigo_esperado() {
    local url="$1" aceptados="$2" codigo
    codigo="$(http_codigo "$url")"
    case " ${aceptados} " in *" ${codigo} "*) return 0 ;; *) return 1 ;; esac
}

titulo "Smoke tests del perfil '${PERFIL}'"
printf '  %-22s %s\n' "Contenedor" "$ID" >&2
printf '  %-22s %s\n' "Imagen" "$(leer_variable "$ARCHIVO_ENV" SECLAB_IMAGE)" >&2

# --- 1. Estado del contenedor -----------------------------------------------
titulo "1. Contenedor y salud"

comprobar "el contenedor está sano" "salud healthy" \
    test "$(salud_contenedor)" = "healthy"

comprobar "el healthcheck de la imagen devuelve SANO" "seclab-salud sale con 0" \
    en_lab /usr/local/bin/seclab-salud

# Todos los programas de supervisor deben estar RUNNING: uno en FATAL significa
# un servicio que se rindió tras sus reintentos.
estado_sup="$(en_lab supervisorctl -c /run/seclab/supervisord.conf status 2>/dev/null)"
if [ -z "$estado_sup" ]; then
    falla "supervisor responde" "supervisorctl devuelve el estado de los programas"
else
    no_running="$(printf '%s\n' "$estado_sup" | grep -vc 'RUNNING' || true)"
    if [ "$no_running" -eq 0 ]; then
        pasa "todos los servicios de supervisor están RUNNING ($(printf '%s\n' "$estado_sup" | grep -c .))"
    else
        falla "todos los servicios de supervisor están RUNNING" "ninguno en FATAL o EXITED"
        printf '%s\n' "$estado_sup" | grep -v RUNNING | sed 's/^/      /' >&2
    fi
fi

# --- 2. Acceso ---------------------------------------------------------------
titulo "2. Acceso"

if [ -n "$LLAVE" ] && [ -f "$LLAVE" ]; then
    quien="$(ssh -i "$LLAVE" -p "$PUERTO_SSH" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=10 \
        "${USUARIO}@127.0.0.1" 'whoami' 2>/dev/null)"
    if [ "$quien" = "$USUARIO" ]; then
        pasa "login SSH por llave como ${USUARIO}"
    else
        falla "login SSH por llave como ${USUARIO}" "whoami devuelve '${USUARIO}'"
    fi

    # El acceso por contraseña tiene que estar cerrado en todos los perfiles.
    #
    # La salida se captura antes de filtrarla: con `pipefail`, un `ssh | grep`
    # devuelve el fallo de ssh —que aquí es justo lo que se espera— y la
    # comprobación se daría por fallida cuando en realidad ha ido bien.
    salida_password="$(ssh -i "$LLAVE" -p "$PUERTO_SSH" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password -o PubkeyAuthentication=no \
        -o ConnectTimeout=10 -o NumberOfPasswordPrompts=0 \
        "${USUARIO}@127.0.0.1" 'true' 2>&1 || true)"
    if printf '%s' "$salida_password" | grep -q "Permission denied"; then
        pasa "el acceso SSH por contraseña se rechaza"
    else
        falla "el acceso SSH por contraseña se rechaza" "Permission denied (publickey)"
    fi
else
    falla "hay una llave SSH configurada" "SECLAB_SSH_LLAVE apunta a un archivo existente"
fi

comprobar "sudo funciona dentro del laboratorio" "sudo -n true sale con 0" \
    como_usuario sudo -n true

# --- 3. Herramientas y manifiesto -------------------------------------------
titulo "3. Herramientas"

entradas="$(en_lab sh -c "grep -c '^|' /opt/seclab/manifiesto-herramientas.txt 2>/dev/null" | tr -d '[:space:]')"
entradas="${entradas:-0}"
if [ "$entradas" -gt 20 ]; then
    pasa "el manifiesto declara ${entradas} entradas"
else
    falla "el manifiesto declara más de 20 entradas" "manifiesto generado en el build"
fi

comprobar "nmap se ejecuta sin privilegios" "nmap -V sale con 0" \
    como_usuario nmap -V
comprobar "nmap puede abrir sockets raw con sudo" "nmap -sn contra 127.0.0.1" \
    como_usuario sudo -n nmap -sn -n 127.0.0.1
comprobar "tcpdump se ejecuta" "tcpdump --version sale con 0" \
    como_usuario tcpdump --version
comprobar "el comando 'herramientas' responde" "lista las herramientas del manifiesto" \
    como_usuario herramientas

# --- 4. Sin fugas de secretos -----------------------------------------------
titulo "4. Secretos"

entorno_publico="$(en_lab cat /etc/seclab/entorno 2>/dev/null)"
pagina=""
if servicio_activo web; then
    pagina="$(curl -sS --max-time 10 "http://${BIND}:$(leer_variable "$ARCHIVO_ENV" SECLAB_PUERTO_WEB)/" 2>/dev/null)"
fi
fugas=0
for variable in SECLAB_VNC_PASSWORD SECLAB_CODE_PASSWORD SECLAB_JUPYTER_TOKEN SECLAB_MCP_TOKEN; do
    valor="$(leer_variable "$ARCHIVO_ENV" "$variable")"
    [ -z "$valor" ] && continue
    if printf '%s' "$entorno_publico" | grep -qF "$valor"; then
        falla "${variable} no aparece en /etc/seclab/entorno" "el entorno público no lleva secretos"
        fugas=$(( fugas + 1 ))
    fi
    if [ -n "$pagina" ] && printf '%s' "$pagina" | grep -qF "$valor"; then
        falla "${variable} no aparece en la página de bienvenida" "la página no muestra secretos"
        fugas=$(( fugas + 1 ))
    fi
done
[ "$fugas" -eq 0 ] && pasa "ningún secreto de .env aparece en las salidas públicas"

# --- 5. Servicios del escritorio --------------------------------------------
if perfil_con_escritorio "$PERFIL"; then
    titulo "5. Escritorio, code-server y página de bienvenida"

    for servicio in escritorio code web; do
        if servicio_activo "$servicio"; then
            pasa "el contenedor declara el servicio '${servicio}'"
        else
            falla "el contenedor declara el servicio '${servicio}'" \
                  "aparece en /run/seclab/servicios"
        fi
    done

    puerto_web="$(leer_variable "$ARCHIVO_ENV" SECLAB_PUERTO_WEB)"
    puerto_novnc="$(leer_variable "$ARCHIVO_ENV" SECLAB_PUERTO_NOVNC)"
    puerto_code="$(leer_variable "$ARCHIVO_ENV" SECLAB_PUERTO_CODE)"

    comprobar "la página de bienvenida responde" "HTTP 200 en el ${puerto_web:-8080}" \
        codigo_esperado "http://${BIND}:${puerto_web:-8080}/" "200"
    comprobar "noVNC sirve vnc.html" "HTTP 200 en el ${puerto_novnc:-6080}" \
        codigo_esperado "http://${BIND}:${puerto_novnc:-6080}/vnc.html" "200"
    comprobar "code-server responde" "HTTP 200 o 302 en el ${puerto_code:-8443}" \
        codigo_esperado "http://${BIND}:${puerto_code:-8443}/" "200 302"

    # Autenticación: una contraseña incorrecta no puede dar acceso.
    respuesta="$(curl -sS --max-time 10 -X POST \
        -d "password=contrasena-incorrecta-de-smoke-test" \
        "http://${BIND}:${puerto_code:-8443}/login" 2>/dev/null)"
    if printf '%s' "$respuesta" | grep -qiE "incorrect|error"; then
        pasa "code-server rechaza una contraseña incorrecta"
    else
        falla "code-server rechaza una contraseña incorrecta" "página de login con error"
    fi

    # El servidor X con VNC: tiene que exigir contraseña y no estar publicado.
    if en_lab python3 -c '
import socket, sys
s = socket.create_connection(("127.0.0.1", 5901), 5)
version = s.recv(12)
s.sendall(version)
n = s.recv(1)[0]
tipos = list(s.recv(n)) if n else []
# 1 = None (sin contraseña), 2 = VncAuth
sys.exit(0 if (2 in tipos and 1 not in tipos) else 1)
' >/dev/null 2>&1; then
        pasa "Xvnc exige contraseña y no ofrece acceso sin autenticación"
    else
        falla "Xvnc exige contraseña y no ofrece acceso sin autenticación" \
              "sólo el tipo de seguridad VncAuth"
    fi

    if curl -sS --max-time 3 "http://${BIND}:5901/" >/dev/null 2>&1; then
        falla "el puerto 5901 no está publicado en el host" "sólo accesible dentro del contenedor"
    else
        pasa "el puerto 5901 de VNC no está publicado en el host"
    fi

    # La sesión de escritorio: que haya gestor de ventanas y panel significa
    # que XFCE arrancó de verdad, no sólo que el servidor X está vivo.
    ventanas="$(como_usuario env DISPLAY=:1 xwininfo -root -children 2>/dev/null)"
    for componente in xfwm4 xfce4-panel xfdesktop; do
        if printf '%s' "$ventanas" | grep -qi "$componente"; then
            pasa "la sesión XFCE tiene ${componente}"
        else
            falla "la sesión XFCE tiene ${componente}" "ventana presente en el display :1"
        fi
    done

    resolucion="$(como_usuario env DISPLAY=:1 xdpyinfo 2>/dev/null | awk '/dimensions:/ {print $2}')"
    if [ -n "$resolucion" ]; then
        pasa "el display :1 responde a ${resolucion}"
    else
        falla "el display :1 responde" "xdpyinfo devuelve las dimensiones"
    fi

    comprobar "Firefox está instalado y arranca" "firefox --version sale con 0" \
        como_usuario firefox --version
    comprobar "code-server está instalado" "code-server --version sale con 0" \
        como_usuario code-server --version
    comprobar "la Nerd Font está en la imagen" "fc-list encuentra JetBrainsMono Nerd Font" \
        en_lab sh -c 'fc-list | grep -q "JetBrainsMono Nerd Font"'
fi

# --- 6. Herramientas del perfil full ----------------------------------------
perfil_con_full() {
    case "$1" in full|full-msf) return 0 ;; *) return 1 ;; esac
}

if perfil_con_full "$PERFIL"; then
    titulo "6. Web, Active Directory, privesc y wordlists"

    # nikto se instala fijado precisamente porque el de Ubuntu va cinco años
    # por detrás: se comprueba que el que responde es el nuevo.
    version_nikto="$(como_usuario nikto -Version 2>/dev/null | awk '/^Nikto/ {print $2}' | head -1)"
    case "$version_nikto" in
        2.6*) pasa "nikto es la versión fijada (${version_nikto}), no la de apt" ;;
        "")   falla "nikto responde" "nikto -Version imprime su versión" ;;
        *)    falla "nikto es la versión fijada" "2.6.x, no ${version_nikto}" ;;
    esac

    comprobar "sqlmap se ejecuta" "sqlmap --version sale con 0" \
        como_usuario sqlmap --version
    comprobar "ffuf se ejecuta" "ffuf -V sale con 0" \
        como_usuario ffuf -V
    comprobar "gobuster se ejecuta" "gobuster --version sale con 0" \
        como_usuario gobuster --version
    comprobar "hydra se ejecuta" "hydra -h sale con 0" \
        como_usuario sh -c 'hydra -h >/dev/null 2>&1 || [ $? -eq 255 ]'
    comprobar "impacket está importable" "python3 -c 'import impacket'" \
        como_usuario python3 -c 'import impacket'
    comprobar "pwntools está importable" "python3 -c 'import pwn'" \
        como_usuario python3 -c 'import pwn'
    comprobar "radare2 se ejecuta" "r2 -v sale con 0" \
        como_usuario r2 -v
    # El john de Ubuntu es el 1.9.0 de Openwall, no el «jumbo»: no entiende
    # --list, así que se comprueba por su banner.
    if contiene "John the Ripper" como_usuario john; then
        pasa "john se ejecuta"
    else
        falla "john se ejecuta" "el banner de John the Ripper"
    fi
    comprobar "linpeas está instalado y es ejecutable" "/usr/local/bin/linpeas -h" \
        en_lab test -x /opt/seclab/privesc/linpeas.sh

    # Las wordlists no pueden estar vacías: un archivo de 0 bytes pasaría
    # desapercibido hasta el día que alguien lance un fuzzing sin resultados.
    faltan=0
    for lista in web/common.txt web/raft-medium-directories.txt \
                 dns/subdominios-top20000.txt usuarios/top-usernames-shortlist.txt \
                 passwords/rockyou.txt.tar.gz; do
        if ! en_lab test -s "/opt/seclab/wordlists/${lista}"; then
            falla "la wordlist ${lista} existe y no está vacía" "archivo con contenido"
            faltan=$(( faltan + 1 ))
        fi
    done
    [ "$faltan" -eq 0 ] && pasa "las 5 wordlists fijadas están presentes y no están vacías"

    # pspy sólo tiene binario x86: en arm64 el manifiesto debe decirlo en lugar
    # de dejar un archivo que no ejecuta.
    arq_lab="$(en_lab dpkg --print-architecture 2>/dev/null | tr -d '[:space:]')"
    if [ "$arq_lab" = "amd64" ]; then
        comprobar "pspy está instalado (amd64)" "binario ejecutable" \
            en_lab test -x /opt/seclab/privesc/pspy64
    else
        if en_lab grep -q "^pspy|no instalado" /opt/seclab/herramientas-fijadas.txt; then
            pasa "el manifiesto declara que pspy no está en ${arq_lab}"
        else
            falla "el manifiesto declara que pspy no está en ${arq_lab}" \
                  "entrada 'pspy|no instalado' en herramientas-fijadas.txt"
        fi
    fi
fi

# --- 7. Metasploit -----------------------------------------------------------
if [ "$PERFIL" = "full-msf" ]; then
    titulo "7. Metasploit"

    # msfconsole escribe TODO por stderr, incluida la versión: con
    # `2>/dev/null` la comprobación no veía nada y daba por caído un
    # Metasploit que funcionaba. Se juntan las dos salidas.
    version_msf="$(en_lab msfconsole --version 2>&1 | awk -F': ' '/Framework Version/ {print $2}' | head -1)"
    if [ -n "$version_msf" ]; then
        pasa "msfconsole responde (Framework ${version_msf})"
    else
        falla "msfconsole responde" "msfconsole --version imprime la versión del framework"
    fi

    if contiene "-p, --payload" en_lab msfvenom --help; then
        pasa "msfvenom está disponible"
    else
        falla "msfvenom está disponible" "la ayuda de msfvenom menciona --payload"
    fi

    if en_lab grep -q "^metasploit-framework|" /opt/seclab/herramientas-fijadas.txt; then
        pasa "el manifiesto registra la versión fijada de Metasploit"
    else
        falla "el manifiesto registra la versión fijada de Metasploit" \
              "entrada 'metasploit-framework|...' en herramientas-fijadas.txt"
    fi
fi

# --- Resultado ---------------------------------------------------------------
titulo "Resultado"
if [ "$FALLOS" -eq 0 ]; then
    printf '%s\n\n' "${C_VERDE}${PRUEBAS} comprobaciones, ninguna falla.${C_FIN}" >&2
    exit 0
fi
printf '%s\n\n' "${C_ROJO}${PRUEBAS} comprobaciones, ${FALLOS} falla(s).${C_FIN}" >&2
exit 1
