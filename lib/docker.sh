#!/usr/bin/env bash
# =============================================================================
# SecLab — envoltura de Docker Compose
# =============================================================================
# Todas las invocaciones de Compose pasan por aquí, para que el nombre de
# proyecto y la lista de archivos sean siempre los mismos. Una segunda forma de
# llamar a Compose sería una segunda verdad, y acabarían discrepando.
# =============================================================================

# perfil_con_escritorio PERFIL -> 0 si ese perfil trae escritorio y servicios web
perfil_con_escritorio() {
    case "$1" in
        desktop|full|full-msf) return 0 ;;
        *) return 1 ;;
    esac
}

# compose_seclab ARGS...
#
# El override del escritorio se añade sólo cuando el perfil lo trae. Va aquí, en
# la única envoltura de Compose, y no en cada comando: si `start` publicara los
# puertos y `status` mirase otra composición, los dos tendrían razón por
# separado y ninguno diría la verdad.
#
# El override de VPN (docker-compose.vpn.yml, Fase 7) se añade sólo cuando
# SECLAB_HABILITAR_VPN=true en .env. No toca la red de 'lab' ni sus puertos:
# sólo le concede NET_ADMIN y /dev/net/tun, lo mínimo que 'seclab-vpn' (dentro
# de la imagen) necesita para poder operar un túnel. En false (el valor por
# defecto), 'lab' ni siquiera tiene esas capacidades — no las necesita si no
# vas a usar ninguna VPN de plataforma. 'seclab vpn up' activa la variable
# solo la primera vez que hace falta, pidiendo confirmación porque recrea
# 'lab' (ver vpn_up en bin/seclab).
compose_seclab() {
    local archivos=(-f "${SECLAB_RAIZ}/docker-compose.yml")
    [ -f "${SECLAB_RAIZ}/docker-compose.override.yml" ] && \
        archivos+=(-f "${SECLAB_RAIZ}/docker-compose.override.yml")

    if perfil_con_escritorio "$(perfil_actual)" && \
       [ -f "${SECLAB_RAIZ}/docker-compose.desktop.yml" ]; then
        archivos+=(-f "${SECLAB_RAIZ}/docker-compose.desktop.yml")
    fi

    if [ "$(leer_variable "${SECLAB_RAIZ}/.env" SECLAB_HABILITAR_VPN)" = "true" ] && \
       [ -f "${SECLAB_RAIZ}/docker-compose.vpn.yml" ]; then
        archivos+=(-f "${SECLAB_RAIZ}/docker-compose.vpn.yml")
    fi

    ( cd "$SECLAB_RAIZ" && docker compose "${archivos[@]}" "$@" )
}

# id_contenedor -> id del servicio lab, vacío si no existe
id_contenedor() {
    compose_seclab ps -q lab 2>/dev/null | head -1
}

# estado_contenedor -> running | exited | creado | ausente
estado_contenedor() {
    local id
    id="$(id_contenedor)"
    if [ -z "$id" ]; then printf 'ausente'; return; fi
    docker inspect -f '{{.State.Status}}' "$id" 2>/dev/null || printf 'ausente'
}

# salud_contenedor -> healthy | unhealthy | starting | sin-healthcheck | ausente
salud_contenedor() {
    local id salud
    id="$(id_contenedor)"
    if [ -z "$id" ]; then printf 'ausente'; return; fi
    salud="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}sin-healthcheck{{end}}' "$id" 2>/dev/null)"
    printf '%s' "${salud:-ausente}"
}

# detalle_salud -> última salida del healthcheck, para explicar un unhealthy
detalle_salud() {
    local id
    id="$(id_contenedor)"
    [ -z "$id" ] && return 0
    docker inspect -f '{{if .State.Health}}{{range $i, $e := .State.Health.Log}}{{if eq $i 0}}{{$e.Output}}{{end}}{{end}}{{end}}' "$id" 2>/dev/null | tr -d '\n'
}

# reinicios_contenedor -> cuántas veces lo ha reiniciado Docker
#
# Con `restart: unless-stopped`, un contenedor cuyo arranque falla no se queda
# en `exited`: entra en un bucle de reinicios y su estado sigue pareciendo
# `running`. Sin mirar este contador, esperar a que esté sano acaba en un
# tiempo de espera agotado y un mensaje que no dice la causa, aunque el
# contenedor la haya escrito en sus logs cinco veces.
reinicios_contenedor() {
    local id
    id="$(id_contenedor)"
    if [ -z "$id" ]; then printf '0'; return; fi
    docker inspect -f '{{.RestartCount}}' "$id" 2>/dev/null || printf '0'
}

# esperar_salud SEGUNDOS -> 0 si llega a healthy dentro del plazo
esperar_salud() {
    local limite="${1:-120}" transcurrido=0 salud estado
    while [ "$transcurrido" -lt "$limite" ]; do
        estado="$(estado_contenedor)"
        case "$estado" in
            exited|dead)
                return 2  # murió: quien llama debe mostrar los logs
                ;;
        esac
        # Dos reinicios ya no son un tropiezo: es un bucle. Un contenedor sano
        # con esta política no se reinicia nunca.
        if [ "$(reinicios_contenedor)" -ge 2 ] 2>/dev/null; then
            return 2
        fi
        salud="$(salud_contenedor)"
        case "$salud" in
            healthy|sin-healthcheck) return 0 ;;
            unhealthy)
                # Un unhealthy temprano puede ser el periodo de arranque; se
                # sigue esperando hasta agotar el plazo.
                : ;;
        esac
        sleep 2
        transcurrido=$(( transcurrido + 2 ))
        printf '.' >&2
    done
    printf '\n' >&2
    return 1
}

# imagen_existe TAG
imagen_existe() {
    docker image inspect "$1" >/dev/null 2>&1
}

# etiqueta_imagen TAG CLAVE
etiqueta_imagen() {
    docker image inspect -f "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null
}

# imagen_al_dia IMAGEN -> 0 si la imagen se construyó con la base que declara
#                        el Dockerfile actual
#
# Una etiqueta como seclab-lite:0.2.0-local no dice nada sobre lo que hay dentro:
# si el Dockerfile cambia de imagen base, la etiqueta sigue siendo la misma y una
# reconstrucción se daría por innecesaria. El alumno seguiría trabajando sobre la
# base antigua sin enterarse. Se compara el digest real.
imagen_al_dia() {
    local imagen="$1" digest_imagen digest_dockerfile

    digest_imagen="$(etiqueta_imagen "$imagen" org.opencontainers.image.base.digest)"
    digest_dockerfile="$(awk -F= '/^ARG UBUNTU_DIGEST=/ {print $2; exit}' \
        "${SECLAB_RAIZ}/docker/Dockerfile")"

    # Sin dato con el que comparar no se puede afirmar nada; se deja pasar y que
    # decida quien llama.
    [ -z "$digest_dockerfile" ] && return 0
    [ -z "$digest_imagen" ] && return 1

    [ "$digest_imagen" = "$digest_dockerfile" ]
}

# servicios_activos -> nombres de los servicios que el contenedor ha levantado
#
# La lista la escribe el entrypoint en cada arranque. Se lee de ahí y no se
# vuelve a deducir de .env: el contenedor ya decidió, y preguntarle es la única
# forma de no contradecirle.
servicios_activos() {
    local id
    id="$(id_contenedor)"
    [ -z "$id" ] && return 0
    [ "$(estado_contenedor)" = "running" ] || return 0
    docker exec "$id" cat /run/seclab/servicios 2>/dev/null || true
}

# servicio_activo NOMBRE -> 0 si ese servicio está levantado
servicio_activo() {
    servicios_activos | grep -qx "$1"
}

# vpn_perfiles_activos -> perfiles de VPN con túnel/proceso en marcha dentro de
# 'lab', uno por línea (ninguno, uno o los tres a la vez). Mismo patrón que
# servicios_activos(): la fuente de verdad vive dentro del contenedor
# (/run/seclab-vpn/, gestionado por seclab-vpn) y aquí sólo se pregunta con
# `docker exec`. Con el diseño de la Fase 7, varios perfiles pueden estar
# activos a la vez, así que un único valor en .env (como hacía
# SECLAB_VPN_PERFIL en el diseño anterior) dejó de poder representarlo — ver
# docs/vpn.md.
vpn_perfiles_activos() {
    local id
    id="$(id_contenedor)"
    [ -z "$id" ] && return 0
    [ "$(estado_contenedor)" = "running" ] || return 0
    docker exec "$id" /usr/local/bin/seclab-vpn activos 2>/dev/null || true
}
