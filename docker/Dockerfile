# syntax=docker/dockerfile:1.7
# =============================================================================
# SecLab — imagen del laboratorio
# =============================================================================
# Etapas compartidas para aprovechar la caché y que los perfiles no se
# confundan entre sí:
#
#   base  → dependencias comunes, usuario y locale
#   lite  → shell, red, recon básico, escritorio XFCE y acceso SSH (Fase 2/5)
#   full, full-msf                                     (Fase 5/12)
#
# A petición explícita del dueño del proyecto (sesión posterior a las Fases
# 2/5): los antiguos perfiles `lite` y `desktop` se fusionaron en uno solo.
# Ya no existe un perfil "sin escritorio" — todo despliegue trae XFCE,
# code-server, ttyd y noVNC desde el nivel más básico. `full`/`full-msf` ya
# no significan "con escritorio", sólo "con más herramientas ofensivas". El
# nombre que sobrevive es `lite`, no `desktop`.
#
# Soporta linux/amd64 y linux/arm64. La imagen base se ancla por el digest de
# su lista de manifiestos, de modo que cada arquitectura resuelve dentro del
# mismo conjunto verificado.
#
# Base: Ubuntu 26.04 LTS. No Kali. El soporte LTS de años encaja con el ciclo de
# una asignatura, y sus paquetes van prácticamente al día (nmap 7.98 frente al
# 7.99 de Kali, Python 3.14, OpenSSH 10.2). Debian estable pesa 10 MB menos pero
# va un ciclo entero por detrás en todo, que es justo lo que había que evitar.
#
# Para las herramientas ofensivas de evolución rápida, el repositorio de la
# distribución nunca va a bastar: esas se instalan desde su publicación oficial
# con versión fijada y checksum verificado. Ver docs/politica-herramientas.md.
# =============================================================================

ARG UBUNTU_DIGEST=sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b

# -----------------------------------------------------------------------------
FROM ubuntu@${UBUNTU_DIGEST} AS base
# -----------------------------------------------------------------------------

ARG DEBIAN_FRONTEND=noninteractive
ARG SECLAB_UID=1000
ARG SECLAB_GID=1000
ARG SECLAB_USUARIO=seclab

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    PIP_BREAK_SYSTEM_PACKAGES=1

# Usuario de laboratorio no privilegiado para el uso diario.
#
# Ubuntu trae de fábrica un usuario `ubuntu` ocupando el UID 1000, que es el que
# necesitamos para que los archivos del workspace montado desde el host tengan
# el propietario correcto en Linux. Se elimina antes de crear el nuestro.
#
# La configuración de sudo se hace en la etapa `lite`: la imagen base no trae
# sudo instalado y /etc/sudoers.d todavía no existe aquí.
RUN set -eux; \
    if getent passwd "${SECLAB_UID}" >/dev/null; then \
        usuario_previo="$(getent passwd "${SECLAB_UID}" | cut -d: -f1)"; \
        echo "Liberando el UID ${SECLAB_UID}, ocupado por '${usuario_previo}'"; \
        userdel --remove "$usuario_previo"; \
    fi; \
    groupadd --gid "${SECLAB_GID}" "${SECLAB_USUARIO}"; \
    useradd --uid "${SECLAB_UID}" --gid "${SECLAB_GID}" \
            --shell /bin/bash --create-home "${SECLAB_USUARIO}"; \
    install -d -m 0750 -o "${SECLAB_USUARIO}" -g "${SECLAB_USUARIO}" /workspace

# -----------------------------------------------------------------------------
FROM base AS lite
# -----------------------------------------------------------------------------
# `lite` = shell, red, recon básico, acceso SSH y escritorio XFCE por
# navegador (noVNC) + code-server + terminal web (ttyd) + Firefox. Fusiona lo
# que antes eran dos perfiles separados: no hay ganancia real en mantener un
# perfil sin escritorio cuando el peso adicional (XFCE ligero, sin Burp ni
# wordlists) es pequeño frente a la comodidad de tenerlo siempre disponible.
#
# Ningún servicio de esta etapa se publica fuera de 127.0.0.1, y ninguno
# arranca si su secreto no está configurado.

ARG SECLAB_USUARIO=seclab
ARG TARGETARCH

# La lista se conserva dentro de la imagen: el manifiesto de herramientas la
# lee más abajo, y sirve de referencia para saber qué se pidió instalar.
COPY docker/paquetes-lite.txt /opt/seclab/paquetes-lite.txt

# La caché de apt se monta en lugar de copiarse, para no engordar la capa.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    grep -vE '^\s*(#|$)' /opt/seclab/paquetes-lite.txt | xargs \
        apt-get install --yes --no-install-recommends; \
    rm -rf /var/log/apt/*

# --- Capacidades de fichero -------------------------------------------------
# El paquete de nmap de Ubuntu no trae capacidades de fichero, así que sin
# privilegios no puede abrir sockets raw y falla incluso el descubrimiento de
# hosts. Se le conceden las dos que el contenedor tiene en su conjunto
# delimitador. (Ubuntu sí se las pone a `ping`, y ahí no hay nada que tocar.)
#
# Después se comprueba el invariante que de verdad importa: **ningún binario
# puede reclamar una capacidad que el contenedor no tenga**. Si lo hace, el
# kernel rechaza el `exec` entero y la herramienta no arranca ni para imprimir
# su versión —que es exactamente lo que le pasaba a nmap sobre la base
# anterior—. Mejor detener el build que entregar una imagen con una herramienta
# muerta dentro.
COPY docker/verificar-capacidades.sh /usr/local/bin/seclab-capacidades
COPY docker/descargar-fijado.sh /usr/local/bin/seclab-descargar
RUN set -eux; \
    chmod 0755 /usr/local/bin/seclab-capacidades /usr/local/bin/seclab-descargar; \
    setcap 'cap_net_raw,cap_net_bind_service=eip' "$(readlink -f /usr/bin/nmap)"; \
    /usr/local/bin/seclab-capacidades /opt/seclab/capacidades.txt

# --- Sudo del usuario de laboratorio ----------------------------------------
# El sudo sin contraseña es deliberado y está documentado en SECURITY.md: es un
# entorno local de entrenamiento donde el alumno necesita instalar herramientas
# y manipular interfaces de red durante la práctica. El contenedor arranca con
# cap_drop: ALL, así que sudo no concede ninguna capacidad sobre el host.
RUN set -eux; \
    install -d -m 0750 /etc/sudoers.d; \
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${SECLAB_USUARIO}" \
        > "/etc/sudoers.d/10-${SECLAB_USUARIO}"; \
    chmod 0440 "/etc/sudoers.d/10-${SECLAB_USUARIO}"; \
    visudo --check --file "/etc/sudoers.d/10-${SECLAB_USUARIO}"

# --- SSH: sólo por llave, sin root, sin contraseña -------------------------
COPY docker/sshd-seclab.conf /etc/ssh/sshd_config.d/10-seclab.conf
RUN set -eux; \
    install -d -m 0755 /run/sshd; \
    chmod 0644 /etc/ssh/sshd_config.d/10-seclab.conf; \
    rm -f /etc/ssh/ssh_host_*; \
    passwd --lock root

# --- Experiencia de terminal ------------------------------------------------
# Oh My Zsh, sus dos plugins externos y Oh my tmux!, todos fijados por commit y
# con el checksum verificado antes de instalar nada. Es la vía 2 de la política
# de herramientas (docs/politica-herramientas.md): nunca `curl | sh`, que sería
# entregar la imagen a quien controle ese servidor.
#
# Se instalan en /opt/seclab/shell, dentro de la capa de imagen, y no en el
# directorio personal. El home es un volumen nombrado que sobrevive a la
# reconstrucción de la imagen: si la configuración viviera ahí, una imagen nueva
# seguiría arrancando con la de la anterior. Así basta reconstruir.
ARG OMZ_COMMIT=9112b53fa8b5ab556c7c893aa8be8a247ac512a0
ARG OMZ_SHA256=b8c77c58f1cbd065738bbffb613095805cbf732dd2b5d48edb0beefe319c3cfe
ARG ZSH_AUTOSUGGESTIONS_REF=v0.7.1
ARG ZSH_AUTOSUGGESTIONS_SHA256=0df7affff21cd87ed298e6a3970ed08a1dd66a6efa676454ee5b091ad503badf
ARG ZSH_HIGHLIGHTING_REF=0.8.0
ARG ZSH_HIGHLIGHTING_SHA256=5981c19ebaab027e356fe1ee5284f7a021b89d4405cc53dc84b476c3aee9cc32
ARG OH_MY_TMUX_COMMIT=58a3dcc0d718ec0fa1c0d5a2fddd640a1ad7a5b7
ARG OH_MY_TMUX_SHA256=5189baec2b8ba2cea62008faf959b1ea20fd394b09a277e0c78d61a8d092390c

# Las descargas van a codeload.github.com, que es donde github.com redirige las
# URLs /archive/. Se pide el destino final a propósito: el salto intermedio se
# quedaba colgado detrás del proxy de Docker Desktop —y un proxy es la norma en
# la red de una universidad—, así que el build fallaba a los tres minutos con un
# «connection timed out» que no dice nada. Menos saltos, menos formas de fallar;
# el checksum sigue garantizando el contenido igual.
#
# Los reintentos son generosos por el mismo motivo: una descarga que tropieza no
# debe tirar un build de varios minutos.
RUN set -eux; \
    descargar() { \
        url="$1"; destino="$2"; esperado="$3"; \
        curl -fsSL --connect-timeout 20 --retry 5 --retry-delay 3 \
             --retry-all-errors -o /tmp/descarga.tar.gz "$url"; \
        real="$(sha256sum /tmp/descarga.tar.gz | cut -d" " -f1)"; \
        if [ "$real" != "$esperado" ]; then \
            echo "ERROR: checksum incorrecto para ${url}" >&2; \
            echo "  esperado: ${esperado}" >&2; \
            echo "  obtenido: ${real}" >&2; \
            exit 1; \
        fi; \
        mkdir -p "$destino"; \
        tar -xzf /tmp/descarga.tar.gz -C "$destino" --strip-components=1; \
        rm -f /tmp/descarga.tar.gz; \
    }; \
    descargar "https://codeload.github.com/ohmyzsh/ohmyzsh/tar.gz/${OMZ_COMMIT}" \
              /opt/seclab/shell/oh-my-zsh "${OMZ_SHA256}"; \
    descargar "https://codeload.github.com/zsh-users/zsh-autosuggestions/tar.gz/${ZSH_AUTOSUGGESTIONS_REF}" \
              /opt/seclab/shell/custom/plugins/zsh-autosuggestions "${ZSH_AUTOSUGGESTIONS_SHA256}"; \
    descargar "https://codeload.github.com/zsh-users/zsh-syntax-highlighting/tar.gz/${ZSH_HIGHLIGHTING_REF}" \
              /opt/seclab/shell/custom/plugins/zsh-syntax-highlighting "${ZSH_HIGHLIGHTING_SHA256}"; \
    descargar "https://codeload.github.com/gpakosz/.tmux/tar.gz/${OH_MY_TMUX_COMMIT}" \
              /opt/seclab/shell/tmux "${OH_MY_TMUX_SHA256}"; \
    test -r /opt/seclab/shell/oh-my-zsh/oh-my-zsh.sh; \
    test -r /opt/seclab/shell/tmux/.tmux.conf; \
    chmod -R go-w /opt/seclab/shell

# Configuración propia: la del curso, versionada en el repositorio.
COPY docker/shell/zshrc /opt/seclab/shell/zshrc
COPY docker/shell/ejemplos.txt /opt/seclab/shell/ejemplos.txt
COPY templates/shell/tmux.conf.local /opt/seclab/shell/tmux.conf.local
COPY docker/shell/banner.sh /usr/local/bin/seclab-banner
COPY docker/shell/herramientas.sh /usr/local/bin/herramientas
COPY docker/shell/servicios.sh /usr/local/bin/servicios

# seclab-vpn (Fase 7): gestor interno de VPN, privilegiado (necesita root para
# iptables/openvpn/ip). No hace falta un permiso de fichero especial: comprueba
# su propio UID y explica cómo invocarlo (sudo, o docker exec -u root) si no lo
# es. seclab-vpn-hook lo invoca OpenVPN mismo (--up/--down), nunca a mano.
COPY docker/shell/seclab-vpn.sh /usr/local/bin/seclab-vpn
COPY docker/shell/seclab-vpn-hook.sh /usr/local/bin/seclab-vpn-hook

# Variante ASCII de la barra de estado, para terminales sin Nerd Font. Sólo
# cambian los cuatro separadores Powerline (los emoji del resto de la barra se
# ven en cualquier terminal moderno). Se genera de la configuración del curso en
# lugar de mantenerse a mano, para que no puedan divergir; y el build falla si
# la sustitución no cambia nada, que sería el aviso de que el nombre de alguna
# variable ha cambiado en Oh my tmux!.
RUN set -eux; \
    sed -e "s/^tmux_conf_theme_use_nerd_fonts=.*/tmux_conf_theme_use_nerd_fonts=false/" \
        -e "s/^tmux_conf_theme_left_separator_main=.*/tmux_conf_theme_left_separator_main=''/" \
        -e "s/^tmux_conf_theme_left_separator_sub=.*/tmux_conf_theme_left_separator_sub='|'/" \
        -e "s/^tmux_conf_theme_right_separator_main=.*/tmux_conf_theme_right_separator_main=''/" \
        -e "s/^tmux_conf_theme_right_separator_sub=.*/tmux_conf_theme_right_separator_sub='|'/" \
        /opt/seclab/shell/tmux.conf.local > /opt/seclab/shell/tmux.conf.local.ascii; \
    if cmp -s /opt/seclab/shell/tmux.conf.local /opt/seclab/shell/tmux.conf.local.ascii; then \
        echo "ERROR: la variante ASCII es idéntica a la Powerline." >&2; \
        echo "Los nombres de las variables de separador han cambiado. Revisa el sed." >&2; \
        exit 1; \
    fi; \
    chmod 0644 /opt/seclab/shell/tmux.conf.local.ascii

RUN set -eux; \
    chmod 0755 /usr/local/bin/seclab-banner /usr/local/bin/herramientas \
               /usr/local/bin/servicios /usr/local/bin/seclab-vpn \
               /usr/local/bin/seclab-vpn-hook; \
    chmod 0644 /opt/seclab/shell/zshrc /opt/seclab/shell/ejemplos.txt \
               /opt/seclab/shell/tmux.conf.local; \
    ln -sf /usr/local/bin/herramientas /usr/local/bin/tools; \
    chsh --shell /usr/bin/zsh "${SECLAB_USUARIO}"; \
    rm -f /etc/update-motd.d/* /etc/legal /etc/motd; \
    touch "/home/${SECLAB_USUARIO}/.hushlogin"; \
    chown "${SECLAB_USUARIO}:${SECLAB_USUARIO}" "/home/${SECLAB_USUARIO}/.hushlogin"

# --- Scripts de la imagen ---------------------------------------------------
COPY docker/entrypoint.sh /usr/local/bin/seclab-entrypoint
COPY docker/salud.sh /usr/local/bin/seclab-salud
COPY docker/generar-manifiesto.sh /usr/local/bin/seclab-manifiesto
RUN chmod 0755 /usr/local/bin/seclab-entrypoint \
                /usr/local/bin/seclab-salud \
                /usr/local/bin/seclab-manifiesto

# --- code-server -------------------------------------------------------------
# No está en el repositorio de Ubuntu. Se instala el .deb oficial de la versión
# fijada, con el checksum comprobado antes de tocar dpkg. Un checksum por
# arquitectura: son binarios distintos.
ARG CODE_SERVER_VERSION=4.135.0
ARG CODE_SERVER_SHA256_AMD64=f87d0d49c6c0a59d41214c9510f506e4123991f2d27b41f6d56f3f5c96458d3e
ARG CODE_SERVER_SHA256_ARM64=565e77cf74820d1cc3f473a17f41adb0703bbb07dc1243ded66a4740c595fdad

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) esperado="${CODE_SERVER_SHA256_AMD64}" ;; \
        arm64) esperado="${CODE_SERVER_SHA256_ARM64}" ;; \
        *) echo "ERROR: arquitectura sin checksum fijado: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_${TARGETARCH}.deb"; \
    curl -fsSL --connect-timeout 20 --retry 5 --retry-delay 3 --retry-all-errors \
        -o /tmp/code-server.deb "$url"; \
    real="$(sha256sum /tmp/code-server.deb | cut -d' ' -f1)"; \
    if [ "$real" != "$esperado" ]; then \
        echo "ERROR: checksum incorrecto para ${url}" >&2; \
        echo "  esperado: ${esperado}" >&2; \
        echo "  obtenido: ${real}" >&2; \
        exit 1; \
    fi; \
    apt-get install --yes --no-install-recommends /tmp/code-server.deb; \
    rm -f /tmp/code-server.deb; \
    code-server --version

# --- ttyd (terminal por navegador) --------------------------------------------
# Tampoco está en el repositorio de Ubuntu. Binario oficial estático (sin
# dependencias de tiempo de ejecución), versión fijada y checksum comprobado
# antes de instalarlo — mismo criterio que code-server arriba. Un checksum
# por arquitectura: son binarios distintos.
ARG TTYD_VERSION=1.7.7
ARG TTYD_SHA256_AMD64=8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55
ARG TTYD_SHA256_ARM64=b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) esperado="${TTYD_SHA256_AMD64}"; arch="x86_64" ;; \
        arm64) esperado="${TTYD_SHA256_ARM64}"; arch="aarch64" ;; \
        *) echo "ERROR: arquitectura sin checksum fijado: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${arch}"; \
    curl -fsSL --connect-timeout 20 --retry 5 --retry-delay 3 --retry-all-errors \
        -o /usr/local/bin/ttyd "$url"; \
    real="$(sha256sum /usr/local/bin/ttyd | cut -d' ' -f1)"; \
    if [ "$real" != "$esperado" ]; then \
        echo "ERROR: checksum incorrecto para ${url}" >&2; \
        echo "  esperado: ${esperado}" >&2; \
        echo "  obtenido: ${real}" >&2; \
        exit 1; \
    fi; \
    chmod 0755 /usr/local/bin/ttyd; \
    ttyd --version

# --- Firefox ESR -------------------------------------------------------------
# Los paquetes `firefox` y `chromium-browser` de Ubuntu son transiciones a snap,
# y snapd no funciona dentro de un contenedor: instalarlos dejaría un navegador
# que no arranca. Se usa el tarball oficial de Mozilla, versión fijada y
# checksum tomado del SHA256SUMS de esa misma publicación.
#
# ESR y no la versión de canal rápido: el soporte extendido encaja con el ciclo
# de una asignatura y no cambia de comportamiento en mitad del curso.
ARG FIREFOX_VERSION=140.15.0esr
ARG FIREFOX_SHA256_AMD64=c93aae610f1177df7ada7823bdef433ded4ff6bfe4e6baeda6941abf4e992f3f
ARG FIREFOX_SHA256_ARM64=5639dbc9984b9902a167c397d8a70913c4476fcff01b061f0651b8b099e114ab

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) esperado="${FIREFOX_SHA256_AMD64}"; plataforma="linux-x86_64" ;; \
        arm64) esperado="${FIREFOX_SHA256_ARM64}"; plataforma="linux-aarch64" ;; \
        *) echo "ERROR: arquitectura sin checksum fijado: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://ftp.mozilla.org/pub/firefox/releases/${FIREFOX_VERSION}/${plataforma}/en-US/firefox-${FIREFOX_VERSION}.tar.xz"; \
    curl -fsSL --connect-timeout 20 --retry 5 --retry-delay 3 --retry-all-errors \
        -o /tmp/firefox.tar.xz "$url"; \
    real="$(sha256sum /tmp/firefox.tar.xz | cut -d' ' -f1)"; \
    if [ "$real" != "$esperado" ]; then \
        echo "ERROR: checksum incorrecto para ${url}" >&2; \
        echo "  esperado: ${esperado}" >&2; \
        echo "  obtenido: ${real}" >&2; \
        exit 1; \
    fi; \
    tar -xJf /tmp/firefox.tar.xz -C /opt; \
    rm -f /tmp/firefox.tar.xz; \
    ln -sf /opt/firefox/firefox /usr/local/bin/firefox; \
    /usr/local/bin/firefox --version

# --- Nerd Font ---------------------------------------------------------------
# La barra de estado de tmux usa separadores Powerline. En el escritorio la
# fuente la pone la imagen, así que ahí se ven siempre; en una sesión SSH
# depende del terminal del alumno, y para eso está la variante ASCII
# (SECLAB_GLIFOS=ascii).
#
# Del archivo, que trae más de cien variantes, se instalan tres: el resto sería
# peso muerto dentro de la imagen.
ARG NERD_FONT_VERSION=v3.5.1
ARG NERD_FONT_SHA256=04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf

RUN set -eux; \
    url="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_VERSION}/JetBrainsMono.tar.xz"; \
    curl -fsSL --connect-timeout 20 --retry 5 --retry-delay 3 --retry-all-errors \
        -o /tmp/nerdfont.tar.xz "$url"; \
    real="$(sha256sum /tmp/nerdfont.tar.xz | cut -d' ' -f1)"; \
    if [ "$real" != "${NERD_FONT_SHA256}" ]; then \
        echo "ERROR: checksum incorrecto para ${url}" >&2; \
        echo "  esperado: ${NERD_FONT_SHA256}" >&2; \
        echo "  obtenido: ${real}" >&2; \
        exit 1; \
    fi; \
    install -d -m 0755 /usr/local/share/fonts/nerd-fonts; \
    # Se instala la variante **Mono**, que es la que sirve para un terminal: sus
    # glifos de icono ocupan una celda. La variante proporcional los dibuja a
    # doble ancho y descoloca la barra de estado de tmux.
    tar -xJf /tmp/nerdfont.tar.xz -C /usr/local/share/fonts/nerd-fonts \
        JetBrainsMonoNerdFontMono-Regular.ttf \
        JetBrainsMonoNerdFontMono-Bold.ttf \
        JetBrainsMonoNerdFontMono-Italic.ttf; \
    rm -f /tmp/nerdfont.tar.xz; \
    fc-cache -f >/dev/null; \
    # El nombre de familia tiene que ser exactamente el que pide terminalrc:
    # si no, fontconfig sustituye por otra fuente y los glifos vuelven a ser
    # cuadros, sin un solo mensaje de error.
    fc-list | grep -q "JetBrainsMono Nerd Font Mono"

# --- Guardián de capacidades, otra vez --------------------------------------
# La etapa ha instalado cientos de binarios nuevos. El invariante se comprueba
# de nuevo aquí: si alguno reclamara una capacidad fuera del conjunto del
# contenedor, el kernel se negaría a ejecutarlo.
RUN /usr/local/bin/seclab-capacidades /opt/seclab/capacidades-desktop.txt

# --- Configuración del escritorio y de los servicios ------------------------
# La configuración por defecto del panel no se copia aquí: se toma en el
# arranque de /etc/xdg/xfce4/panel/default.xml, que trae el propio paquete de
# XFCE. Mantener una copia nuestra sería mantener una divergencia.
COPY docker/desktop/xstartup /opt/seclab/desktop/xstartup
COPY docker/desktop/xfce4-panel.xml /opt/seclab/desktop/xfce4-panel.xml
COPY docker/desktop/xfce4-desktop.xml /opt/seclab/desktop/xfce4-desktop.xml
COPY docker/desktop/xsettings.xml /opt/seclab/desktop/xsettings.xml
COPY docker/desktop/gtk-settings.ini /opt/seclab/desktop/gtk-settings.ini
COPY docker/desktop/terminalrc /opt/seclab/desktop/terminalrc
COPY docker/shell/bienvenida.sh /usr/local/bin/seclab-bienvenida

# Firefox viene de un tarball y no trae entrada de menú: sin este archivo no
# aparece en el menú de aplicaciones de XFCE ni se puede usar como lanzador.
COPY docker/desktop/firefox.desktop /usr/share/applications/firefox.desktop

RUN set -eux; \
    chmod 0755 /opt/seclab/desktop/xstartup /usr/local/bin/seclab-bienvenida; \
    chmod 0644 /opt/seclab/desktop/xfce4-panel.xml \
               /opt/seclab/desktop/xfce4-desktop.xml \
               /opt/seclab/desktop/xsettings.xml \
               /opt/seclab/desktop/gtk-settings.ini \
               /opt/seclab/desktop/terminalrc \
               /usr/share/applications/firefox.desktop; \
    test -r /etc/xdg/xfce4/panel/default.xml; \
    # Los lanzadores de la barra y del escritorio apuntan a estos dos archivos:
    # si cambiaran de nombre, la barra saldría con huecos y nadie sabría por qué.
    test -r /usr/share/applications/xfce4-terminal.desktop; \
    test -r /usr/share/applications/firefox.desktop; \
    update-desktop-database /usr/share/applications 2>/dev/null || true

# --- Manifiesto de herramientas --------------------------------------------
# Se genera aquí, en el build, porque es el único momento en que se conocen las
# versiones que realmente quedaron instaladas.
ARG TARGETARCH
RUN set -eux; \
    { \
      echo "oh-my-zsh|${OMZ_COMMIT}|commit fijado, checksum verificado"; \
      echo "zsh-autosuggestions|${ZSH_AUTOSUGGESTIONS_REF}|checksum verificado"; \
      echo "zsh-syntax-highlighting|${ZSH_HIGHLIGHTING_REF}|checksum verificado"; \
      echo "oh-my-tmux|${OH_MY_TMUX_COMMIT}|commit fijado, checksum verificado"; \
      echo "code-server|${CODE_SERVER_VERSION}|.deb oficial, checksum verificado"; \
      echo "ttyd|${TTYD_VERSION}|binario oficial estático, checksum verificado"; \
      echo "firefox|${FIREFOX_VERSION}|tarball oficial de Mozilla, checksum verificado"; \
      echo "JetBrainsMono Nerd Font|${NERD_FONT_VERSION}|checksum verificado"; \
    } > /opt/seclab/herramientas-fijadas.txt; \
    chmod 0644 /opt/seclab/herramientas-fijadas.txt; \
    SECLAB_PERFIL=lite \
    TARGETARCH="${TARGETARCH}" \
    SECLAB_LISTA_PAQUETES=/opt/seclab/paquetes-lite.txt \
        /usr/local/bin/seclab-manifiesto > /opt/seclab/manifiesto-herramientas.txt; \
    cat /opt/seclab/manifiesto-herramientas.txt

# --- Metadatos --------------------------------------------------------------
ARG SECLAB_VERSION=0.0.0
ARG SECLAB_COMMIT=desconocido
ARG SECLAB_FECHA=desconocida
ARG UBUNTU_DIGEST

ENV SECLAB_VERSION="${SECLAB_VERSION}" \
    SECLAB_PERFIL="lite"

# El digest de la imagen base, también como archivo: las etiquetas OCI sólo se
# pueden leer desde el host, y el entrypoint necesita este dato dentro del
# contenedor para marcar con qué base se creó el volumen del directorio
# personal. Sin esa marca no hay forma de detectar un home que arrastra restos
# de otra base (ver `seclab doctor`).
RUN printf '%s\n' "${UBUNTU_DIGEST}" > /opt/seclab/base-digest; \
    chmod 0644 /opt/seclab/base-digest; \
    test -s /opt/seclab/base-digest

LABEL org.opencontainers.image.title="SecLab lite" \
      org.opencontainers.image.description="Laboratorio de ciberseguridad reproducible — perfil lite (con escritorio XFCE)" \
      org.opencontainers.image.version="${SECLAB_VERSION}" \
      org.opencontainers.image.revision="${SECLAB_COMMIT}" \
      org.opencontainers.image.created="${SECLAB_FECHA}" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="ubuntu:26.04" \
      org.opencontainers.image.base.digest="${UBUNTU_DIGEST}" \
      dev.seclab.perfil="lite" \
      dev.seclab.arquitectura="${TARGETARCH}" \
      dev.seclab.manifiesto="/opt/seclab/manifiesto-herramientas.txt"

ENV SECLAB_PERFIL=lite \
    SECLAB_USUARIO=${SECLAB_USUARIO}

WORKDIR /workspace

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD /usr/local/bin/seclab-salud

ENTRYPOINT ["/usr/local/bin/seclab-entrypoint"]
CMD ["dormir"]

# -----------------------------------------------------------------------------
FROM lite AS full
# -----------------------------------------------------------------------------
# `full` = `lite` + web, Active Directory, escalada de privilegios, wordlists,
# recon/fuzzing, pivoting y utilidades de CTF. Es el perfil para máquinas
# complejas y CTFs largos, y el que más pesa: pide 8 GB de RAM y 25 GB de
# disco.
#
# Los paquetes opt-in de la Fase 12 (`web`, `ad`, `pwn` completo) no están
# aquí: llegan como paquetes instalables sobre cualquier perfil, sin
# reconstruir la imagen.

ARG SECLAB_USUARIO=seclab
ARG TARGETARCH

COPY docker/paquetes-full.txt /opt/seclab/paquetes-full.txt

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    grep -vE '^\s*(#|$)' /opt/seclab/paquetes-full.txt | xargs \
        apt-get install --yes --no-install-recommends; \
    rm -rf /var/log/apt/*; \
    # El paquete 'bat' de Ubuntu instala el binario como 'batcat' (choca con
    # otro paquete de nombre 'bat' ya existente en Debian/Ubuntu). Se enlaza
    # al nombre esperado para no sorprender a quien ya conoce la herramienta.
    ln -sf /usr/bin/batcat /usr/local/bin/bat

# --- nikto -------------------------------------------------------------------
# El paquete de Ubuntu es la versión 2.1.5 y la actual es la 2.6.1: cinco años
# de plugins y de firmas de diferencia en un escáner de vulnerabilidades web,
# que es justo donde eso importa. Se instala de su publicación oficial.
ARG NIKTO_VERSION=2.6.1
ARG NIKTO_SHA256=d1ca1acb05d81a5a6f374c0afdd76b33afa0089278631a20673c0210a71d992f

RUN set -eux; \
    seclab-descargar \
        "https://codeload.github.com/sullo/nikto/tar.gz/${NIKTO_VERSION}" \
        /tmp/nikto.tar.gz "${NIKTO_SHA256}"; \
    install -d -m 0755 /opt/nikto; \
    tar -xzf /tmp/nikto.tar.gz -C /opt/nikto --strip-components=1; \
    rm -f /tmp/nikto.tar.gz; \
    printf '#!/bin/sh\nexec /usr/bin/perl /opt/nikto/program/nikto.pl "$@"\n' \
        > /usr/local/bin/nikto; \
    chmod 0755 /usr/local/bin/nikto; \
    # La comprobación exige la cadena de versión, no sólo que el comando
    # termine: nikto imprime «Required module not found» y sale con 0, así que
    # un `| head` habría dejado pasar una instalación que no arranca. Pasó de
    # verdad, con XML::Writer.
    nikto -Version | grep -qE "^Nikto ${NIKTO_VERSION}" || { \
        echo "ERROR: nikto no arranca correctamente:" >&2; \
        nikto -Version >&2; \
        exit 1; \
    }; \
    nikto -Version | head -1

# --- linPEAS, winPEAS y pspy -------------------------------------------------
# No están en ningún repositorio de distribución: son scripts y binarios que se
# publican por release. Van a /opt/seclab/privesc, desde donde se sirven a la
# máquina objetivo durante una práctica.
#
# pspy sólo publica binarios x86: en arm64 no se instala, y el manifiesto lo
# dice en lugar de dejar un archivo que no ejecuta.
ARG PEASS_VERSION=20260901-a029e205
ARG LINPEAS_SHA256=8f5f81b0f1b6293f9da63817b55872263d60bf4a0dff65ff2911badf2d53c88f
ARG WINPEAS_EXE_SHA256=369352c50dca44e661e620d3fe1775671d09ce3e6ad761aa05f018e5a4c7bbc8
ARG WINPEAS_BAT_SHA256=11e4ea92ce2465f3d30c5a56fd4aeba2aecaf4d1c2670ac42bd61c4db2becf87
ARG PSPY_VERSION=v1.2.1
ARG PSPY64_SHA256=c93f29a5cc1347bdb90e14a12424e6469c8cfea9a20b800bc249755f0043a3bb

RUN set -eux; \
    base="https://github.com/peass-ng/PEASS-ng/releases/download/${PEASS_VERSION}"; \
    seclab-descargar "${base}/linpeas.sh" /opt/seclab/privesc/linpeas.sh "${LINPEAS_SHA256}" 0755; \
    seclab-descargar "${base}/winPEASx64.exe" /opt/seclab/privesc/winPEASx64.exe "${WINPEAS_EXE_SHA256}"; \
    seclab-descargar "${base}/winPEAS.bat" /opt/seclab/privesc/winPEAS.bat "${WINPEAS_BAT_SHA256}"; \
    if [ "${TARGETARCH}" = "amd64" ]; then \
        seclab-descargar \
            "https://github.com/DominicBreuker/pspy/releases/download/${PSPY_VERSION}/pspy64" \
            /opt/seclab/privesc/pspy64 "${PSPY64_SHA256}" 0755; \
    else \
        echo "pspy: sin binario para ${TARGETARCH}; se omite (queda anotado en el manifiesto)"; \
    fi; \
    ln -sf /opt/seclab/privesc/linpeas.sh /usr/local/bin/linpeas; \
    ls -l /opt/seclab/privesc

# --- Wordlists ---------------------------------------------------------------
# Un subconjunto de SecLists, no el repositorio entero: completo son más de
# 1,5 GB y en una asignatura se usan siempre las mismas cuatro listas. Cada
# archivo va fijado por tag y checksum.
#
# rockyou llega comprimido y se deja comprimido: descomprimido son 134 MB
# dentro de la imagen para algo que se usa un par de veces. `zcat` lo lee tal
# cual, y quien lo necesite plano lo extrae en su workspace.
ARG SECLISTS_VERSION=2026.1
ARG SL_COMMON_SHA256=fc320bacd30d93f5080029912b93667cd739401f81634579a7125fc0c027e6d5
ARG SL_RAFT_SHA256=a9626959f818d9e198259665c5a88053b7b061c538f46da215d172bcba305fe9
ARG SL_SUBDOMINIOS_SHA256=685fad386d19c3b7ecbcd18645606bc5c47a3b2339fa3d79f44c46bd9e79c1ef
ARG SL_USUARIOS_SHA256=dc44775d12dcdb4027017623ffaa935a018944839ce4b204ccb0c6ef566db5dd
ARG SL_ROCKYOU_SHA256=47c070a029bcdb4cbd0e02c69fed136ef46dce4048ddbadf177daa5e885b8172

RUN set -eux; \
    base="https://raw.githubusercontent.com/danielmiessler/SecLists/${SECLISTS_VERSION}"; \
    seclab-descargar "${base}/Discovery/Web-Content/common.txt" \
        /opt/seclab/wordlists/web/common.txt "${SL_COMMON_SHA256}"; \
    seclab-descargar "${base}/Discovery/Web-Content/raft-medium-directories.txt" \
        /opt/seclab/wordlists/web/raft-medium-directories.txt "${SL_RAFT_SHA256}"; \
    seclab-descargar "${base}/Discovery/DNS/subdomains-top1million-20000.txt" \
        /opt/seclab/wordlists/dns/subdominios-top20000.txt "${SL_SUBDOMINIOS_SHA256}"; \
    seclab-descargar "${base}/Usernames/top-usernames-shortlist.txt" \
        /opt/seclab/wordlists/usuarios/top-usernames-shortlist.txt "${SL_USUARIOS_SHA256}"; \
    seclab-descargar "${base}/Passwords/Leaked-Databases/rockyou.txt.tar.gz" \
        /opt/seclab/wordlists/passwords/rockyou.txt.tar.gz "${SL_ROCKYOU_SHA256}"; \
    du -sh /opt/seclab/wordlists

# --- Recon/fuzzing: ProjectDiscovery (subfinder, nuclei, httpx) --------------
# Binarios Go oficiales de GitHub releases, sin apt disponible en Ubuntu. Cada
# release publica un archivo de checksums propio (*_checksums.txt); los
# valores de aquí se tomaron de ahí, un checksum por arquitectura.
#
# El binario de ProjectDiscovery se llama 'httpx' dentro de su propio zip,
# pero ese mismo nombre lo usa también el paquete de PyPI 'httpx' (cliente
# HTTP en Python, dependencia transitiva de netexec y pwncat-cs más abajo):
# su script de consola se instala en la misma ruta /usr/local/bin/httpx y
# sobrescribe el binario de Go sin avisar (comprobado construyendo la imagen
# de verdad: tras instalar netexec, 'httpx -version' pasó a ser el cliente
# HTTP de Python). Kali empaqueta la herramienta de ProjectDiscovery como
# 'httpx-toolkit' precisamente por este choque de nombres; aquí se hace lo
# mismo, sin depender del orden en que se instale cada cosa.
ARG SUBFINDER_VERSION=2.16.0
ARG SUBFINDER_SHA256_AMD64=1b7f9c608e9a5bd59e609a5e09710d63c5485e92d3d49dc2c16eb4fdbe10cb60
ARG SUBFINDER_SHA256_ARM64=c81d49559c0f630177be9e347e502e7a3d474aacc6ff78291ffcb4964367d63d
ARG NUCLEI_VERSION=3.11.1
ARG NUCLEI_SHA256_AMD64=ea63d4ae232808cd7c6bc00d0142428e231fab59dae01042246097d195835ab6
ARG NUCLEI_SHA256_ARM64=8044e3d9768ba0a744b2872c1a87e813006f013da97ca9f50f7661a4203bec07
ARG HTTPX_VERSION=1.11.0
ARG HTTPX_SHA256_AMD64=5dce96e7315cff24be7aab3b032f23f7a71b7711a17f8189ebe601f2588f2f87
ARG HTTPX_SHA256_ARM64=2b5d9ec3d3750df41e04e4216b1400d2ad862d1cb9ebe68ae501b2299cb5b3a5

RUN set -eux; \
    instalar_zip_pd() { \
        nombre="$1"; version="$2"; esperado="$3"; binario="$4"; instalado="${5:-$4}"; \
        url="https://github.com/projectdiscovery/${nombre}/releases/download/v${version}/${nombre}_${version}_linux_${TARGETARCH}.zip"; \
        curl -fsSL --connect-timeout 20 --retry 5 --retry-delay 3 --retry-all-errors \
            -o /tmp/pd.zip "$url"; \
        real="$(sha256sum /tmp/pd.zip | cut -d' ' -f1)"; \
        if [ "$real" != "$esperado" ]; then \
            echo "ERROR: checksum incorrecto para ${url}" >&2; \
            echo "  esperado: ${esperado}" >&2; \
            echo "  obtenido: ${real}" >&2; \
            exit 1; \
        fi; \
        unzip -oq /tmp/pd.zip -d /tmp/pd_extraido "$binario"; \
        install -m 0755 "/tmp/pd_extraido/${binario}" "/usr/local/bin/${instalado}"; \
        rm -rf /tmp/pd.zip /tmp/pd_extraido; \
    }; \
    case "${TARGETARCH}" in \
        amd64) sf="${SUBFINDER_SHA256_AMD64}"; nc="${NUCLEI_SHA256_AMD64}"; hx="${HTTPX_SHA256_AMD64}" ;; \
        arm64) sf="${SUBFINDER_SHA256_ARM64}"; nc="${NUCLEI_SHA256_ARM64}"; hx="${HTTPX_SHA256_ARM64}" ;; \
        *) echo "ERROR: arquitectura sin checksum fijado: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    instalar_zip_pd subfinder "${SUBFINDER_VERSION}" "$sf" subfinder; \
    instalar_zip_pd nuclei "${NUCLEI_VERSION}" "$nc" nuclei; \
    instalar_zip_pd httpx "${HTTPX_VERSION}" "$hx" httpx httpx-toolkit; \
    subfinder -version; nuclei -version; httpx-toolkit -version

# --- Recon/fuzzing: feroxbuster y rustscan -----------------------------------
# Igual que arriba (binarios Go/Rust de GitHub release, sin apt), pero de
# repositorios distintos y con su propio empaquetado por arquitectura: ambos
# publican un .zip, y el de rustscan para amd64 envuelve además un .tar.gz
# (arm64 no). Se maneja cada caso explícitamente en vez de asumir que los dos
# se empaquetan igual.
ARG FEROXBUSTER_VERSION=2.13.1
ARG FEROXBUSTER_SHA256_AMD64=0978619a10049ccaad290b2d1241bc4d8a6aac18da07d6231186fb9d343f99de
ARG FEROXBUSTER_SHA256_ARM64=1e5244e1f52e55a647b65e0c76ae7afe0b9983c1fbea30ed7c67e477175eb381
ARG RUSTSCAN_VERSION=2.4.1
ARG RUSTSCAN_SHA256_AMD64=f3a4365d939e3b81f25ba8c37852ce9ac9e938c3cc882c5b3e6fff6152c740be
ARG RUSTSCAN_SHA256_ARM64=4f49103e2dfc9e9709a36da2cd61f1f81613f8d0a203307f750439fc3ce39eae

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) fx_arch="x86_64"; fx_esperado="${FEROXBUSTER_SHA256_AMD64}"; \
               rs_url="https://github.com/RustScan/RustScan/releases/download/${RUSTSCAN_VERSION}/x86_64-linux-rustscan.tar.gz.zip"; \
               rs_esperado="${RUSTSCAN_SHA256_AMD64}"; rs_anidado=1 ;; \
        arm64) fx_arch="aarch64"; fx_esperado="${FEROXBUSTER_SHA256_ARM64}"; \
               rs_url="https://github.com/RustScan/RustScan/releases/download/${RUSTSCAN_VERSION}/aarch64-linux-rustscan.zip"; \
               rs_esperado="${RUSTSCAN_SHA256_ARM64}"; rs_anidado=0 ;; \
        *) echo "ERROR: arquitectura sin checksum fijado: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    fx_url="https://github.com/epi052/feroxbuster/releases/download/v${FEROXBUSTER_VERSION}/${fx_arch}-linux-feroxbuster.zip"; \
    curl -fsSL --connect-timeout 20 --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/ferox.zip "$fx_url"; \
    real="$(sha256sum /tmp/ferox.zip | cut -d' ' -f1)"; \
    if [ "$real" != "$fx_esperado" ]; then \
        echo "ERROR: checksum incorrecto para ${fx_url}" >&2; exit 1; \
    fi; \
    unzip -oq /tmp/ferox.zip -d /tmp/ferox_extraido; \
    install -m 0755 /tmp/ferox_extraido/feroxbuster /usr/local/bin/feroxbuster; \
    rm -rf /tmp/ferox.zip /tmp/ferox_extraido; \
    curl -fsSL --connect-timeout 20 --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/rustscan.zip "$rs_url"; \
    real="$(sha256sum /tmp/rustscan.zip | cut -d' ' -f1)"; \
    if [ "$real" != "$rs_esperado" ]; then \
        echo "ERROR: checksum incorrecto para ${rs_url}" >&2; exit 1; \
    fi; \
    unzip -oq /tmp/rustscan.zip -d /tmp/rustscan_extraido; \
    if [ "$rs_anidado" = "1" ]; then \
        tar -xzf /tmp/rustscan_extraido/x86_64-linux-rustscan.tar.gz -C /tmp/rustscan_extraido; \
    fi; \
    install -m 0755 /tmp/rustscan_extraido/rustscan /usr/local/bin/rustscan; \
    rm -rf /tmp/rustscan.zip /tmp/rustscan_extraido; \
    feroxbuster --version; rustscan --version

# --- Pivoting: chisel y ligolo-ng ---------------------------------------------
# Binarios Go de GitHub release. chisel publica un .gz de un solo binario;
# ligolo-ng publica un .tar.gz con el binario ya nombrado "proxy" — se
# reinstala como 'ligolo-proxy' para no dejar un comando genérico en el PATH.
# Sólo el lado "proxy" (el que corre en la máquina del alumno): el lado
# "agent" se compila/descarga aparte para cada objetivo, nunca se ejecuta
# aquí.
ARG CHISEL_VERSION=1.12.0
ARG CHISEL_SHA256_AMD64=f3f180f1d93aa72cce4e6386f98cc06569a0146fbd65eb4423cf83e6434bcfe6
ARG CHISEL_SHA256_ARM64=2ec6152cd2c74fe0146d4d79e4e7aa174521368c56e433d55e023a92ea404ec3
ARG LIGOLO_VERSION=0.9.1
ARG LIGOLO_SHA256_AMD64=4e4486a492c24f32ff5f965d230e08388c81b86d07b1af28c5f54df615731503
ARG LIGOLO_SHA256_ARM64=a7bce7ce036decf5375e0c9022ab453614a3f24a94792c12b367f2a6bc4e9560

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) ch_esperado="${CHISEL_SHA256_AMD64}"; li_esperado="${LIGOLO_SHA256_AMD64}" ;; \
        arm64) ch_esperado="${CHISEL_SHA256_ARM64}"; li_esperado="${LIGOLO_SHA256_ARM64}" ;; \
        *) echo "ERROR: arquitectura sin checksum fijado: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    ch_url="https://github.com/jpillora/chisel/releases/download/v${CHISEL_VERSION}/chisel_${CHISEL_VERSION}_linux_${TARGETARCH}.gz"; \
    curl -fsSL --connect-timeout 20 --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/chisel.gz "$ch_url"; \
    real="$(sha256sum /tmp/chisel.gz | cut -d' ' -f1)"; \
    if [ "$real" != "$ch_esperado" ]; then \
        echo "ERROR: checksum incorrecto para ${ch_url}" >&2; exit 1; \
    fi; \
    gunzip -c /tmp/chisel.gz > /usr/local/bin/chisel; \
    chmod 0755 /usr/local/bin/chisel; \
    rm -f /tmp/chisel.gz; \
    li_url="https://github.com/nicocha30/ligolo-ng/releases/download/v${LIGOLO_VERSION}/ligolo-ng_proxy_${LIGOLO_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    curl -fsSL --connect-timeout 20 --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/ligolo.tar.gz "$li_url"; \
    real="$(sha256sum /tmp/ligolo.tar.gz | cut -d' ' -f1)"; \
    if [ "$real" != "$li_esperado" ]; then \
        echo "ERROR: checksum incorrecto para ${li_url}" >&2; exit 1; \
    fi; \
    install -d -m 0755 /tmp/ligolo_extraido; \
    tar -xzf /tmp/ligolo.tar.gz -C /tmp/ligolo_extraido; \
    install -m 0755 /tmp/ligolo_extraido/proxy /usr/local/bin/ligolo-proxy; \
    rm -rf /tmp/ligolo.tar.gz /tmp/ligolo_extraido; \
    chisel --version; ligolo-proxy -h >/dev/null

# --- AD/Windows: enum4linux-ng ------------------------------------------------
# Script Python, no un paquete de Ubuntu. Sus dependencias (impacket, ldap3,
# PyYAML) ya están instaladas más arriba en esta misma etapa (python3-impacket,
# python3-ldap3, python3-yaml). Fijado por tag y checksum, igual que nikto.
ARG ENUM4LINUX_NG_VERSION=1.3.10
ARG ENUM4LINUX_NG_SHA256=563235acd56278dbcc405e436d78cf29eaa55dc83b11b6c38d46077198f6a427

RUN set -eux; \
    seclab-descargar \
        "https://codeload.github.com/cddmp/enum4linux-ng/tar.gz/refs/tags/v${ENUM4LINUX_NG_VERSION}" \
        /tmp/e4lng.tar.gz "${ENUM4LINUX_NG_SHA256}"; \
    install -d -m 0755 /opt/seclab/enum4linux-ng; \
    tar -xzf /tmp/e4lng.tar.gz -C /opt/seclab/enum4linux-ng --strip-components=1; \
    rm -f /tmp/e4lng.tar.gz; \
    chmod 0755 /opt/seclab/enum4linux-ng/enum4linux-ng.py; \
    ln -sf /opt/seclab/enum4linux-ng/enum4linux-ng.py /usr/local/bin/enum4linux-ng; \
    enum4linux-ng -h >/dev/null

# --- Pwn/forense: pwndbg -------------------------------------------------------
# Plugin de gdb. Su propio instalador oficial (./setup.sh dentro del repo) es
# lo que se ejecuta aquí, pero NUNCA a ciegas: el repo entero ya pasó por
# verificación de checksum (es la vía 2 de la política de herramientas), así
# que ejecutar un script QUE YA ESTÁ DENTRO de ese tarball verificado no es
# distinto de ejecutar cualquier otro binario fijado — no hay una segunda
# descarga sin verificar de por medio.
#
# jpype1 (una de sus dependencias Python, para integración con Java) compila
# una extensión en C++: hace falta g++ sólo durante el `setup.sh`. Se instala
# y se quita en el mismo RUN, para no dejar un compilador en la imagen final
# (ver TESTING_GAPS.md, "multi-stage para no enviar el compilador").
ARG PWNDBG_VERSION=2026.07.29
ARG PWNDBG_COMMIT=f4de22244b7e9f0aeda26a92208c42edaca2f8d8
ARG PWNDBG_SHA256=f9f8153feba73e5d4af384c55001cb6759eaca8490f3b869be016b1f0385d7be

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends g++; \
    seclab-descargar \
        "https://codeload.github.com/pwndbg/pwndbg/tar.gz/${PWNDBG_COMMIT}" \
        /tmp/pwndbg.tar.gz "${PWNDBG_SHA256}"; \
    install -d -m 0755 /opt/seclab/pwndbg; \
    tar -xzf /tmp/pwndbg.tar.gz -C /opt/seclab/pwndbg --strip-components=1; \
    rm -f /tmp/pwndbg.tar.gz; \
    (cd /opt/seclab/pwndbg && ./setup.sh); \
    apt-get purge --yes g++; \
    apt-get autoremove --yes; \
    rm -rf /var/log/apt/*

# --- AD/Windows: netexec -------------------------------------------------------
# No está en PyPI (decisión propia del proyecto, según su documentación
# oficial, que recomienda 'pipx install git+...'): el tarball fijado por
# commit y con checksum verificado es el mismo código exacto, sin depender
# de que GitHub esté disponible en cada build.
#
# Dos particularidades reales de esta instalación, encontradas construyendo
# la imagen de verdad (no supuestas):
#   1. netexec usa poetry-dynamic-versioning, que necesita un repositorio git
#      de verdad para saber su propia versión — un tarball sin `.git` no le
#      basta. POETRY_DYNAMIC_VERSIONING_BYPASS se lo da a mano, con la misma
#      versión que ya se fijó arriba.
#   2. Dos dependencias transitivas (arc4, aardwolf) no tienen wheel
#      precompilada para Python 3.14 (muy reciente) y se compilan desde
#      código: hacen falta gcc y, sólo para aardwolf, Rust. Se instalan y se
#      quitan en el mismo RUN, igual que g++ en el bloque de pwndbg de
#      arriba — no quedan en la imagen final.
#   3. Una dependencia de netexec (certipy-ad) apunta a su vez a
#      github.com/Pennyw0rth/Certipy SIN versión fijada — así lo declara el
#      propio netexec, no una decisión de este Dockerfile. Se documenta aquí
#      en vez de ocultarlo: es la única pieza de esta imagen que no se
#      instala por completo con versión inmutable.
#   4. Entre las decenas de dependencias transitivas hay paquetes que
#      apt YA instaló (typing_extensions, entre otros): pip se niega a
#      reinstalarlos por encima sin un registro RECORD que sólo tienen los
#      paquetes que el propio pip instaló. `--ignore-installed` evita el
#      conflicto instalando la versión que netexec necesita en el entorno de
#      pip, sin tocar el paquete de apt.
#   5. `netexec --version` termina con código de salida 1 aunque imprima la
#      versión correctamente (comprobado con `echo $?` fuera de este
#      Dockerfile): es el propio binario, no un fallo de instalación. Bajo
#      `set -e` eso cortaba el RUN justo ahí, antes de purgar gcc/rustc/
#      cargo/python3-dev — se le añade `|| true` porque aquí sólo sirve de
#      humo (confirmar que el binario arranca), no de condición de éxito.
ARG NETEXEC_VERSION=1.5.1
ARG NETEXEC_COMMIT=c7dc286ba65daf10402cdc470e531b84e6d3d911
ARG NETEXEC_SHA256=e6b19598554792dffb32ae9da888439e77d9af7824c3b2bd97f8182cd73b13c7

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends gcc rustc cargo python3-dev; \
    seclab-descargar \
        "https://codeload.github.com/Pennyw0rth/NetExec/tar.gz/${NETEXEC_COMMIT}" \
        /tmp/netexec.tar.gz "${NETEXEC_SHA256}"; \
    install -d -m 0755 /tmp/netexec_src; \
    tar -xzf /tmp/netexec.tar.gz -C /tmp/netexec_src --strip-components=1; \
    rm -f /tmp/netexec.tar.gz; \
    POETRY_DYNAMIC_VERSIONING_BYPASS="${NETEXEC_VERSION}" \
        pip3 install --no-cache-dir --ignore-installed /tmp/netexec_src; \
    rm -rf /tmp/netexec_src; \
    netexec --version || true; \
    apt-get purge --yes gcc rustc cargo python3-dev; \
    apt-get autoremove --yes; \
    rm -rf /var/log/apt/*

# --- Web: OWASP ZAP -------------------------------------------------------------
# Tarball oficial, checksum verificado. Aplicación Java: el mismo archivo
# sirve para amd64 y arm64 (no hay checksum por arquitectura). Requiere
# default-jre-headless (ya en paquetes-full.txt). Se evaluó Burp Suite
# Community como alternativa/complemento, pero PortSwigger no publica ningún
# checksum oficial verificable — se descartó a propósito, no por omisión.
ARG ZAP_VERSION=2.17.0
ARG ZAP_SHA256=efe799aaa3627db683b43f00c9c210aea0b75c00cc8f0a0f0434d12bb3ddde5a

RUN set -eux; \
    seclab-descargar \
        "https://github.com/zaproxy/zaproxy/releases/download/v${ZAP_VERSION}/ZAP_${ZAP_VERSION}_Linux.tar.gz" \
        /tmp/zap.tar.gz "${ZAP_SHA256}"; \
    install -d -m 0755 /opt/zaproxy; \
    tar -xzf /tmp/zap.tar.gz -C /opt/zaproxy --strip-components=1; \
    rm -f /tmp/zap.tar.gz; \
    printf '#!/bin/sh\nexec /opt/zaproxy/zap.sh "$@"\n' > /usr/local/bin/zap; \
    chmod 0755 /usr/local/bin/zap

# --- Shells: pwncat-cs ---------------------------------------------------------
# Paquete de PyPI, versión fijada. La integridad la da el propio índice de
# PyPI (hash por archivo, verificado por pip): no es el mismo mecanismo que un
# checksum calculado a mano, pero es el estándar del ecosistema Python y el
# mismo criterio de "versión fijada, nunca latest".
#
# Su dependencia transitiva 'netifaces' tampoco tiene wheel precompilada para
# Python 3.14 y se compila desde código: mismo patrón que arc4/aardwolf en el
# bloque de netexec de arriba — gcc y python3-dev (Python.h) se instalan y se
# quitan en el mismo RUN.
#
# pwncat-cs 0.5.4 exige 'packaging<21.0', una versión que en Python 3.14
# depende de 'distutils' (retirado del intérprete). apt ya trae 'packaging'
# 26.0 sin registro RECORD, así que ni `--ignore-installed` es seguro aquí:
# forzarlo hace que pip también reinstale 'setuptools' en una versión más
# nueva que ya no trae el módulo 'distutils' de compatibilidad, rompiendo el
# propio 'packaging' viejo en tiempo de ejecución (comprobado). La solución
# real: instalar pwncat-cs con `--no-deps` (pip nunca toca 'packaging', se
# queda con el 26.0 de apt, que es funcionalmente compatible) y declarar a
# mano el resto de sus dependencias exactas (ver requires_dist en PyPI),
# fijando además 'setuptools<81' — a partir de la 81, setuptools deja de
# traer 'pkg_resources', que 'zodburi' (dependencia de pwncat-cs) todavía
# importa.
ARG PWNCAT_CS_VERSION=0.5.4

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends gcc python3-dev; \
    pip3 install --no-cache-dir --no-deps "pwncat-cs==${PWNCAT_CS_VERSION}"; \
    pip3 install --no-cache-dir \
        "setuptools<81" \
        "netifaces>=0.11.0,<0.12.0" \
        "prompt-toolkit>=3.0.19,<4.0.0" \
        "pycryptodome>=3.10.1,<4.0.0" \
        "requests>=2.25.1,<3.0.0" \
        "rich>=10.4.0,<11.0.0" \
        "python-rapidjson>=1.0,<2.0" \
        "ZODB3>=3.11.0,<4.0.0" \
        "zodburi>=2.5.0,<3.0.0" \
        "Jinja2>=3.0.1,<4.0.0" \
        "paramiko-ng>=2.8.8,<3.0.0" \
        "PyNaCl>=1.4.0,<2.0.0"; \
    pwncat-cs --help >/dev/null; \
    apt-get purge --yes gcc python3-dev; \
    apt-get autoremove --yes; \
    rm -rf /var/log/apt/*

# --- Pwn/forense: one_gadget ----------------------------------------------------
# Gem de Ruby, versión fijada (ruby/ruby-dev ya están en paquetes-full.txt).
ARG ONE_GADGET_VERSION=2.1.1

RUN set -eux; \
    gem install --no-document one_gadget -v "${ONE_GADGET_VERSION}"; \
    one_gadget --version

# --- Guardián de capacidades -------------------------------------------------
RUN /usr/local/bin/seclab-capacidades /opt/seclab/capacidades-full.txt

# --- Manifiesto y metadatos --------------------------------------------------
RUN set -eux; \
    { \
      cat /opt/seclab/herramientas-fijadas.txt; \
      echo "nikto|${NIKTO_VERSION}|tarball oficial, checksum verificado"; \
      echo "linpeas|${PEASS_VERSION}|release oficial, checksum verificado"; \
      echo "winPEAS|${PEASS_VERSION}|release oficial, checksum verificado"; \
      if [ "${TARGETARCH}" = "amd64" ]; then \
        echo "pspy|${PSPY_VERSION}|release oficial, checksum verificado"; \
      else \
        echo "pspy|no instalado|sin binario para ${TARGETARCH}"; \
      fi; \
      echo "SecLists (subconjunto)|${SECLISTS_VERSION}|5 listas fijadas por checksum"; \
      echo "subfinder|${SUBFINDER_VERSION}|release oficial, checksum verificado"; \
      echo "nuclei|${NUCLEI_VERSION}|release oficial, checksum verificado"; \
      echo "httpx-toolkit|${HTTPX_VERSION}|release oficial, checksum verificado (nombre 'httpx-toolkit': el paquete de PyPI 'httpx' usa el nombre 'httpx')"; \
      echo "feroxbuster|${FEROXBUSTER_VERSION}|release oficial, checksum verificado"; \
      echo "rustscan|${RUSTSCAN_VERSION}|release oficial, checksum verificado"; \
      echo "chisel|${CHISEL_VERSION}|release oficial, checksum verificado"; \
      echo "ligolo-ng (proxy)|${LIGOLO_VERSION}|release oficial, checksum verificado"; \
      echo "enum4linux-ng|${ENUM4LINUX_NG_VERSION}|tarball oficial, checksum verificado"; \
      echo "pwndbg|${PWNDBG_VERSION}|commit fijado, checksum verificado"; \
      echo "netexec|${NETEXEC_VERSION}|commit fijado, checksum verificado"; \
      echo "OWASP ZAP|${ZAP_VERSION}|tarball oficial, checksum verificado"; \
      echo "pwncat-cs|${PWNCAT_CS_VERSION}|paquete de PyPI, versión fijada"; \
      echo "one_gadget|${ONE_GADGET_VERSION}|gem de RubyGems, versión fijada"; \
    } > /tmp/fijadas.txt; \
    mv /tmp/fijadas.txt /opt/seclab/herramientas-fijadas.txt; \
    chmod 0644 /opt/seclab/herramientas-fijadas.txt; \
    SECLAB_PERFIL=full \
    TARGETARCH="${TARGETARCH}" \
    SECLAB_LISTA_PAQUETES="/opt/seclab/paquetes-lite.txt /opt/seclab/paquetes-full.txt" \
        /usr/local/bin/seclab-manifiesto > /opt/seclab/manifiesto-herramientas.txt; \
    tail -20 /opt/seclab/manifiesto-herramientas.txt

ARG SECLAB_VERSION=0.0.0
ARG SECLAB_COMMIT=desconocido
ARG SECLAB_FECHA=desconocida
ARG UBUNTU_DIGEST

LABEL org.opencontainers.image.title="SecLab full" \
      org.opencontainers.image.description="Laboratorio de ciberseguridad reproducible — perfil full" \
      org.opencontainers.image.version="${SECLAB_VERSION}" \
      org.opencontainers.image.revision="${SECLAB_COMMIT}" \
      org.opencontainers.image.created="${SECLAB_FECHA}" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="ubuntu:26.04" \
      org.opencontainers.image.base.digest="${UBUNTU_DIGEST}" \
      dev.seclab.perfil="full" \
      dev.seclab.arquitectura="${TARGETARCH}" \
      dev.seclab.manifiesto="/opt/seclab/manifiesto-herramientas.txt"

ENV SECLAB_PERFIL=full

# -----------------------------------------------------------------------------
FROM full AS full-msf
# -----------------------------------------------------------------------------
# `full-msf` = `full` + Metasploit. Siempre opt-in: nunca es el perfil
# recomendado y pesa 400 MB más.
#
# Metasploit no está en Ubuntu y su instalador oficial es un script remoto que
# se ejecuta a ciegas, cosa que esta imagen no hace. Se instala el .deb de la
# publicación de Rapid7 fijado por versión, y el checksum es **el que publica
# su propio repositorio** en el índice de paquetes: no uno calculado por
# nosotros. La versión difiere por arquitectura porque el número incluye la
# marca de tiempo del build.

ARG TARGETARCH
ARG MSF_VERSION_AMD64=6.5.3~20260818061200~1rapid7-1
ARG MSF_VERSION_ARM64=6.5.3~20260818060933~1rapid7-1
ARG MSF_SHA256_AMD64=cdf7fc71d5c481d4e374c77d5d7b9ae80de8c646bff547210aed772847bbdba3
ARG MSF_SHA256_ARM64=52421070a71932ec1f06f4dd69d3a692604f3fb09650c4c847eb91f55e4d43e3

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    case "${TARGETARCH}" in \
        amd64) version="${MSF_VERSION_AMD64}"; esperado="${MSF_SHA256_AMD64}" ;; \
        arm64) version="${MSF_VERSION_ARM64}"; esperado="${MSF_SHA256_ARM64}" ;; \
        *) echo "ERROR: arquitectura sin versión fijada de Metasploit: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    seclab-descargar \
        "https://apt.metasploit.com/pool/main/m/metasploit-framework/metasploit-framework_${version}_${TARGETARCH}.deb" \
        /tmp/metasploit.deb "$esperado"; \
    apt-get update; \
    apt-get install --yes --no-install-recommends /tmp/metasploit.deb; \
    rm -f /tmp/metasploit.deb; \
    rm -rf /var/log/apt/*; \
    msfconsole --version

RUN /usr/local/bin/seclab-capacidades /opt/seclab/capacidades-full-msf.txt

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) version="${MSF_VERSION_AMD64}" ;; \
        *) version="${MSF_VERSION_ARM64}" ;; \
    esac; \
    { \
      cat /opt/seclab/herramientas-fijadas.txt; \
      echo "metasploit-framework|${version}|.deb oficial de Rapid7, checksum de su índice"; \
    } > /tmp/fijadas.txt; \
    mv /tmp/fijadas.txt /opt/seclab/herramientas-fijadas.txt; \
    chmod 0644 /opt/seclab/herramientas-fijadas.txt; \
    SECLAB_PERFIL=full-msf \
    TARGETARCH="${TARGETARCH}" \
    SECLAB_LISTA_PAQUETES="/opt/seclab/paquetes-lite.txt /opt/seclab/paquetes-full.txt" \
        /usr/local/bin/seclab-manifiesto > /opt/seclab/manifiesto-herramientas.txt; \
    tail -5 /opt/seclab/manifiesto-herramientas.txt

ARG SECLAB_VERSION=0.0.0
ARG SECLAB_COMMIT=desconocido
ARG SECLAB_FECHA=desconocida
ARG UBUNTU_DIGEST

LABEL org.opencontainers.image.title="SecLab full-msf" \
      org.opencontainers.image.description="Laboratorio de ciberseguridad reproducible — perfil full con Metasploit" \
      org.opencontainers.image.version="${SECLAB_VERSION}" \
      org.opencontainers.image.revision="${SECLAB_COMMIT}" \
      org.opencontainers.image.created="${SECLAB_FECHA}" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="ubuntu:26.04" \
      org.opencontainers.image.base.digest="${UBUNTU_DIGEST}" \
      dev.seclab.perfil="full-msf" \
      dev.seclab.arquitectura="${TARGETARCH}" \
      dev.seclab.manifiesto="/opt/seclab/manifiesto-herramientas.txt"

ENV SECLAB_PERFIL=full-msf
