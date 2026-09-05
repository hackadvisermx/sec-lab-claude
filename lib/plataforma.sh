#!/usr/bin/env bash
# =============================================================================
# SecLab — detección de plataforma y comprobación de recursos
# =============================================================================
# Se carga con `source`. Depende de lib/comun.sh.
# =============================================================================

# --- Requisitos mínimos por perfil ------------------------------------------
# Formato: "RAM_GB DISCO_GB". La RAM es la que necesita el contenedor, no la de
# la máquina: en macOS y Windows lo que manda es la memoria asignada a la VM de
# Docker, que suele ser bastante menos que la del portátil.
requisitos_perfil() {
    case "$1" in
        lite)     echo "2 5"  ;;
        desktop)  echo "4 10" ;;
        full)     echo "8 25" ;;
        full-msf) echo "8 30" ;;
        *)        echo ""     ;;
    esac
}

perfiles_validos() { echo "lite desktop full full-msf"; }

# Perfiles que tienen etapa real en el Dockerfile hoy. El resto son diseño
# todavía: se recomiendan y se validan, pero no se pueden construir.
perfiles_implementados() { echo "lite desktop full full-msf"; }

perfil_implementado() {
    case " $(perfiles_implementados) " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# perfil_mas_ligero_que RAM_GB -> el perfil más capaz que cabe en esa RAM
perfil_recomendado() {
    local ram="$1" perfil req
    local mejor=""
    for perfil in lite desktop full full-msf; do
        req="$(requisitos_perfil "$perfil" | cut -d' ' -f1)"
        if [ "$ram" -ge "$req" ]; then mejor="$perfil"; fi
    done
    # `full-msf` nunca se recomienda solo: es opt-in explícito.
    [ "$mejor" = "full-msf" ] && mejor="full"
    [ -z "$mejor" ] && mejor=""
    printf '%s' "$mejor"
}

# --- Sistema operativo -------------------------------------------------------
# Devuelve: macos | wsl2 | linux | desconocido
detectar_so() {
    case "$(uname -s)" in
        Darwin) printf 'macos' ;;
        Linux)
            # WSL2 se identifica por el kernel de Microsoft. Es una distinción
            # que importa: cambia dónde debe vivir el repositorio y cómo se
            # accede a /dev/net/tun.
            if grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null; then
                printf 'wsl2'
            else
                printf 'linux'
            fi
            ;;
        *) printf 'desconocido' ;;
    esac
}

nombre_so() {
    case "$1" in
        macos) printf 'macOS' ;;
        wsl2)  printf 'Windows (WSL2)' ;;
        linux) printf 'Linux' ;;
        *)     printf 'sistema no reconocido' ;;
    esac
}

# --- Arquitectura ------------------------------------------------------------
# Devuelve la nomenclatura de Docker: amd64 | arm64
detectar_arquitectura() {
    case "$(uname -m)" in
        x86_64|amd64)   printf 'amd64' ;;
        arm64|aarch64)  printf 'arm64' ;;
        *)              printf '%s' "$(uname -m)" ;;
    esac
}

# --- Recursos ----------------------------------------------------------------

# RAM disponible para los contenedores, en GB enteros.
# Se pregunta a Docker, no al sistema: en macOS y Windows el contenedor vive
# dentro de una VM con su propio límite de memoria, casi siempre menor que la
# del equipo. Preguntar a `uname` daría una cifra tranquilizadora y falsa.
ram_docker_gb() {
    local bytes
    bytes="$(docker system info --format '{{.MemTotal}}' 2>/dev/null)"
    if [ -z "$bytes" ] || [ "$bytes" -le 0 ] 2>/dev/null; then
        printf '0'
        return 1
    fi
    printf '%d' $(( bytes / 1024 / 1024 / 1024 ))
}

# RAM física de la máquina, en GB enteros. Informativa.
ram_host_gb() {
    local kb bytes
    case "$(uname -s)" in
        Darwin)
            bytes="$(sysctl -n hw.memsize 2>/dev/null)"
            [ -n "$bytes" ] && printf '%d' $(( bytes / 1024 / 1024 / 1024 )) || printf '0'
            ;;
        Linux)
            kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)"
            [ -n "$kb" ] && printf '%d' $(( kb / 1024 / 1024 )) || printf '0'
            ;;
        *) printf '0' ;;
    esac
}

# Disco libre en GB para la ruta indicada.
disco_libre_gb() {
    local ruta="${1:-.}" kb
    kb="$(df -Pk "$ruta" 2>/dev/null | awk 'NR==2 {print $4}')"
    [ -n "$kb" ] && printf '%d' $(( kb / 1024 / 1024 )) || printf '0'
}

# --- Dispositivo TUN ---------------------------------------------------------
# Devuelve: disponible | ausente | en-vm
estado_tun() {
    local so="$1"
    case "$so" in
        macos)
            # /dev/net/tun vive dentro de la VM de Docker, no en macOS. No se
            # puede comprobar desde aquí sin arrancar un contenedor; se verifica
            # de verdad al levantar un perfil de VPN (Fase 7).
            printf 'en-vm'
            ;;
        linux|wsl2)
            [ -c /dev/net/tun ] && printf 'disponible' || printf 'ausente'
            ;;
        *) printf 'ausente' ;;
    esac
}

accion_tun() {
    case "$1" in
        linux) printf 'sudo modprobe tun' ;;
        wsl2)  printf 'cierra WSL con "wsl --shutdown" desde PowerShell y vuelve a entrar' ;;
        *)     printf 'consulta docs/plataformas.md' ;;
    esac
}

# --- Puertos -----------------------------------------------------------------
# puerto_libre PUERTO -> 0 si nadie escucha en 127.0.0.1:PUERTO
puerto_libre() {
    local puerto="$1"
    python3 - "$puerto" <<'PY'
import socket, sys
puerto = int(sys.argv[1])
s = socket.socket()
s.settimeout(0.5)
libre = s.connect_ex(("127.0.0.1", puerto)) != 0
s.close()
sys.exit(0 if libre else 1)
PY
}

# --- Docker ------------------------------------------------------------------
# Devuelve: ok | sin-docker | sin-compose | parado
estado_docker() {
    existe_comando docker || { printf 'sin-docker'; return; }
    docker compose version >/dev/null 2>&1 || { printf 'sin-compose'; return; }
    docker info >/dev/null 2>&1 || { printf 'parado'; return; }
    printf 'ok'
}

accion_docker() {
    local so="$2"
    case "$1" in
        sin-docker)
            case "$so" in
                macos) printf 'Instala Docker Desktop u OrbStack desde su web oficial.' ;;
                wsl2)  printf 'Instala Docker Desktop con la integración de WSL2 activada.' ;;
                *)     printf 'Instala Docker Engine y el plugin docker-compose-plugin.' ;;
            esac
            ;;
        sin-compose) printf 'Falta el plugin de Compose. Instala docker-compose-plugin.' ;;
        parado)
            case "$so" in
                macos|wsl2) printf 'Docker está instalado pero no responde. Abre Docker Desktop y espera a que arranque.' ;;
                *)          printf 'Arranca el servicio: sudo systemctl start docker' ;;
            esac
            ;;
        *) printf '' ;;
    esac
}
