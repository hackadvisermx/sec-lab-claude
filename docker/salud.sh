#!/usr/bin/env bash
# =============================================================================
# SecLab — healthcheck
# =============================================================================
# Comprueba únicamente los servicios que están activos en este perfil. Un
# servicio deshabilitado no se evalúa y por tanto no puede reportar unhealthy.
#
# La comprobación de SSH no se limita a mirar si el proceso existe: abre una
# conexión y espera el saludo del protocolo. Un sshd vivo que no responde es
# indistinguible de un sshd sano si sólo se comprueba el pid, y para el alumno
# la diferencia es total —no puede entrar—.
#
# Las comprobaciones de escritorio, code-server y página de bienvenida se
# completan en la Fase 5, cuando esos servicios existan.
# =============================================================================

set -uo pipefail

problemas=()

# proceso_vivo NOMBRE
proceso_vivo() { pgrep -x "$1" >/dev/null 2>&1; }

# puerto_escuchando PUERTO
puerto_escuchando() {
    local puerto="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltn "sport = :${puerto}" 2>/dev/null | grep -q LISTEN
    else
        # Sin ss disponible, se consulta directamente la tabla del kernel.
        local hex
        hex="$(printf '%04X' "$puerto")"
        grep -qi ":${hex} " /proc/net/tcp /proc/net/tcp6 2>/dev/null
    fi
}

# sshd_responde: saludo real del protocolo. Todo servidor SSH anuncia su
# versión en la primera línea en cuanto se abre la conexión, antes de cualquier
# autenticación. Si esa línea no llega, el servicio no está utilizable, diga lo
# que diga la tabla de procesos.
sshd_responde() {
    local linea
    exec 3<>/dev/tcp/127.0.0.1/22 2>/dev/null || return 1
    if ! read -r -t 3 linea <&3; then
        exec 3<&- 3>&- 2>/dev/null
        return 1
    fi
    exec 3<&- 3>&- 2>/dev/null
    case "$linea" in
        SSH-2.0-*) return 0 ;;
        *) return 1 ;;
    esac
}

# --- SSH: siempre activo en todos los perfiles ------------------------------
# Las tres comprobaciones van en cascada de la causa más probable a la más
# concreta, para que el motivo del unhealthy diga qué ha pasado y no sólo que
# algo va mal.
if ! proceso_vivo sshd; then
    problemas+=("sshd no está corriendo")
elif ! puerto_escuchando 22; then
    problemas+=("sshd corre pero no escucha en el puerto 22")
elif ! sshd_responde; then
    problemas+=("sshd escucha en el 22 pero no completa el saludo del protocolo SSH")
fi

# --- Servicios opcionales ----------------------------------------------------
# La lista de servicios activos la escribe el entrypoint al arrancar, con los
# que de verdad ha levantado. No se vuelve a deducir de las variables de
# entorno: serían dos implementaciones de la misma decisión y algún día dirían
# cosas distintas. Sin lista, se evalúa sólo SSH.
servicio_activo() {
    [ -r /run/seclab/servicios ] || return 1
    grep -qx "$1" /run/seclab/servicios
}

# endpoint_responde PUERTO RUTA CÓDIGOS
# Un puerto abierto no significa que el servicio sirva: durante el arranque de
# code-server el puerto ya escucha antes de que la aplicación responda. Se pide
# una página y se comprueba el código.
endpoint_responde() {
    local puerto="$1" ruta="$2" aceptados="$3" codigo
    codigo="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 4 \
        "http://127.0.0.1:${puerto}${ruta}" 2>/dev/null)" || return 1
    case " ${aceptados} " in
        *" ${codigo} "*) return 0 ;;
        *) return 1 ;;
    esac
}

if servicio_activo escritorio; then
    # Xvnc escucha en el 5901 sólo dentro del contenedor; el navegador entra
    # por noVNC. Se comprueban los dos: si falla el primero, el segundo
    # respondería igual y mostraría una pantalla gris.
    puerto_escuchando 5901 || problemas+=("el servidor X con VNC no escucha en 5901")
    endpoint_responde 6080 "/vnc.html" "200" || \
        problemas+=("noVNC no sirve /vnc.html en el 6080")
fi

if servicio_activo code; then
    # Sin sesión, code-server redirige a /login: un 302 es la respuesta
    # correcta de un servicio sano y protegido.
    endpoint_responde 8443 "/" "200 302" || \
        problemas+=("code-server no responde en el 8443")
fi

if servicio_activo web; then
    endpoint_responde 8080 "/" "200" || \
        problemas+=("la página de bienvenida no responde en el 8080")
fi

if servicio_activo jupyter; then
    endpoint_responde 8888 "/" "200 302" || \
        problemas+=("Jupyter no responde en el 8888")
fi

if servicio_activo terminal; then
    # Sin credenciales, ttyd responde 401: esa es la respuesta correcta de un
    # servicio sano y protegido, igual que el 302 de code-server.
    endpoint_responde 7681 "/" "200 401" || \
        problemas+=("el terminal web (ttyd) no responde en el 7681")
fi

if [ ${#problemas[@]} -gt 0 ]; then
    printf 'NO SANO: %s\n' "$(IFS='; '; echo "${problemas[*]}")"
    exit 1
fi

printf 'SANO\n'
exit 0
