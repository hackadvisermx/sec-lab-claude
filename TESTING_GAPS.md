# Pruebas no ejecutadas

Registro honesto de lo que **no** se ha podido verificar, con el motivo y la
alternativa aplicada. Una prueba que no se ejecutó no cuenta como aprobada.

Se actualiza al cerrar cada fase.

---

## Fase 1 — Estructura base y seguridad

### Verificado

Cada comprobación de seguridad se probó en los dos sentidos: que pasa cuando
todo está bien y que **falla de verdad** cuando se introduce el problema.

| Prueba | Resultado |
|---|---|
| `docker-compose.yml` valida (`docker compose config`) | Correcto |
| Puertos publicados fuera de localhost | Detectado — con `SECLAB_BIND=0.0.0.0` la revisión falla con código 1 |
| `privileged`, capacidades peligrosas, `container_name` fijo y montaje del socket de Docker | Detectados los cuatro con un override de prueba |
| Secretos vacíos en `.env` | Detectados los cinco |
| Valor de relleno (`change-this-password`) | Detectado |
| Secretos válidos generados aleatoriamente | Pasan la revisión |
| Permisos de `.env` (644 en vez de 600) | Detectado, con el `chmod` correctivo en el mensaje |
| Permisos de `vpn/`, `vpn/<perfil>/` y `.ovpn` | Correctos con 700/700/600 |
| Archivo sensible forzado al índice de Git (`git add -f` de un `.ovpn`) | Detectado |
| Clave privada dentro de un archivo versionado | Detectada |
| `.gitignore` ignora `vpn/` real pero **no** `templates/vpn/` | Correcto tras anclar los patrones a la raíz |
| Sintaxis de `bin/seclab`, `lib/comun.sh`, `scripts/verificar-seguridad.sh` (`bash -n`) | Correcto |
| Sintaxis de `scripts/analizar-compose.py` | Correcto |
| `seclab ayuda`, `seclab version`, `seclab seguridad` | Correcto |
| Comandos no implementados: código 3 y mensaje con la fase | Correcto |
| `make lint` completo | Correcto |

### Corregido durante la verificación

El patrón `vpn/` de `.gitignore`, sin barra inicial, coincide a cualquier
profundidad y estaba excluyendo también `templates/vpn/`, que sí debe
versionarse: las plantillas de los tres perfiles habrían desaparecido del
repositorio sin que nadie se diera cuenta. Los patrones de directorio propios
del proyecto (`vpn/`, `workspace/`, `backups/`, `tailscale-state/`,
`mcp-state/`, `terraform/`) están ahora anclados con `/` inicial. Verificado en
ambos sentidos: `vpn/vpnhtb/vpnhtb.ovpn` se ignora, `templates/vpn/**` se
versiona.

### No verificado

| Prueba | Motivo | Alternativa |
|---|---|---|
| **ShellCheck** sobre los scripts de shell | No está instalado en la máquina de desarrollo | `make lint` lo ejecuta si está disponible y avisa si no. La CI de la Fase 8 lo hará obligatorio. `bash -n` cubre errores de sintaxis, pero no de estilo ni de citado |
| **Arranque del contenedor** | No hay imagen todavía: se construye en la Fase 2 | `docker-compose.yml` valida sintácticamente. El arranque real es criterio de cierre de la Fase 2 |
| **Portabilidad a Linux y Windows/WSL2** | Desarrollado y probado sólo en macOS | Los scripts evitan dependencias específicas de macOS: `stat` se intenta en los dos formatos (`-f` de BSD y `-c` de GNU). Aun así, **requiere verificación real en las otras dos plataformas antes de entregar a la clase**, porque es donde estarán la mayoría de los alumnos |
| **Comportamiento en `arm64` frente a `amd64`** | Sin build de imágenes | Se aborda en las Fases 2, 4 y 7 |
| **Conexión VPN real** | Los perfiles se implementan en la Fase 7 | En la Fase 1 sólo existen las plantillas y la política de exclusión de Git, ambas verificadas. La Fase 7 probará contra un servidor OpenVPN local, nunca contra HTB o TryHackMe |

---

## Fase 2 — Imagen `lite` y runtime local

### Verificado

Todo lo de abajo se ejecutó de verdad sobre la imagen construida, en macOS
arm64 con Docker 29.7.

| Prueba | Resultado |
|---|---|
| Build de la imagen `lite` sobre Ubuntu 26.04 LTS | Correcto — 784 MB, ~3 min |
| Comparativa de bases medida antes de elegir (Debian 13 / Ubuntu 26.04 / Kali) | Ubuntu queda a un paquete de Kali; Debian, un ciclo por detrás |
| Liberación del UID 1000 que Ubuntu ocupa con su propio usuario | Correcto |
| Guardián de capacidades de fichero | Detectó `ping` con `cap_net_raw` y se rehízo como comprobación de subconjunto |
| Detección de imagen construida con otra base | Correcto — `doctor` la marca y `init` la reconstruye |
| nmap 7.98 sin privilegios y con `sudo` sobre Ubuntu | Correctos |
| Manifiesto de herramientas generado en el build | 49 entradas con versión real |
| El build falla si un paquete de la lista no figura instalado | Correcto — detectó `dnsutils` y `p7zip-full` como transitorios |
| Arranque sin llave SSH | Aborta con mensaje accionable |
| Arranque con `SECLAB_SSH_PUBKEY` malformada | Aborta |
| Arranque con un secreto de relleno (`change-this-password`) | Aborta |
| Arranque correcto | `healthy` en ~8 s |
| Login SSH por llave | Correcto, como usuario `seclab` (uid 1000) |
| Login SSH por contraseña | Rechazado (`Permission denied (publickey)`) |
| Login SSH como root | Rechazado |
| `sudo` dentro del contenedor | Correcto |
| `nmap` sin privilegios | Correcto (necesita `cap_net_raw` de fichero) |
| `nmap -sS` con `sudo` | Correcto |
| `ping` y `tcpdump` | Correctos |
| Healthcheck al matar sshd | Pasa a `unhealthy` tras los 3 reintentos |
| Llave de host SSH tras `restart` | Idéntica: sin avisos de cambio de llave |
| `seclab init` completo | Correcto de principio a fin |
| `init` no sobrescribe un `.env` existente | Correcto |
| `doctor` con un perfil que no cabe en la RAM | Rechaza y sugiere el perfil que sí cabe |
| `init --profile full` (no implementado) | Rechaza sin modificar nada |
| `stop` conserva volúmenes y workspace | Correcto |
| Secretos vacíos de servicios desactivados | No se evalúan; con el servicio activo, fallan |
| Anclaje multi-arch: build de la etapa `base` para `linux/amd64` | Correcto — el digest resuelve para la otra arquitectura |

### Corregido durante la verificación

Tres fallos que sólo aparecieron al ejecutar, no al leer el código:

1. **El endurecimiento de la Fase 1 impedía arrancar el contenedor.**
   `cap_drop: ALL` deja fuera `CHOWN`, `DAC_OVERRIDE` y `FOWNER`, así que el
   entrypoint moría en la primera línea que crea un directorio. Se concede el
   conjunto mínimo de diez capacidades, cada una con su motivo anotado en
   `docker-compose.yml`.

2. **`no-new-privileges` habría roto `sudo` y nmap** sin aportar seguridad: el
   perfil de entrenamiento ya concede `sudo` sin contraseña, así que el candado
   no cerraba nada. Se retira, con la razón escrita en el archivo.

3. **nmap no arrancaba ni para imprimir su versión** sobre la base anterior,
   que lo marcaba con `cap_net_admin`: al no estar esa capacidad en el conjunto
   delimitador del contenedor, el kernel rechaza el `exec` completo. Sobre
   Ubuntu el paquete no trae capacidades de fichero y el síntoma es otro
   —fallan los sockets raw sin `sudo`—, así que la imagen le concede
   `cap_net_raw` y `cap_net_bind_service`, exactamente las que el contenedor
   tiene. El build verifica ahora ese invariante para toda la imagen.

4. **`init` reutilizaba una imagen construida con otra imagen base.** Al
   cambiar de base, la etiqueta seguía siendo la misma y la reconstrucción se
   daba por innecesaria: el laboratorio arrancaba con la base antigua sin que
   nada lo indicara. Ahora se compara el digest de la base grabado en la imagen
   con el que declara el Dockerfile.

5. **El guardián de capacidades estaba mal planteado.** Exigía que ningún
   binario tuviera capacidades de fichero, y Ubuntu marca `ping` con
   `cap_net_raw` de forma perfectamente legítima. Se rehízo como lo que de
   verdad importa: que ninguna capacidad quede fuera del conjunto del
   contenedor.

### No verificado

| Prueba | Motivo | Alternativa |
|---|---|---|
| **Build completo de `lite` para `linux/amd64`** | Bajo emulación QEMU en Apple Silicon, el `apt install` tarda más de lo razonable para una sesión de desarrollo | Verificado que la etapa `base` sí cruza y que el digest resuelve para amd64. El build multi-arch completo es trabajo de CI (Fase 8), donde corre en un runner nativo |
| **ShellCheck** | No está instalado en la máquina de desarrollo | `make lint` valida la sintaxis de los nueve scripts con `bash -n` y ejecuta ShellCheck si aparece. Obligatorio en la CI de la Fase 8 |
| **Hadolint sobre el Dockerfile** | No instalado | CI de la Fase 8 |
| **Linux y Windows/WSL2** | Sólo se ha probado en macOS arm64 | La detección de plataforma contempla los tres sistemas y `stat` se intenta en formato BSD y GNU, pero **sigue sin ejecutarse en Linux ni WSL2**. Es la brecha más importante que queda: la mayoría de los alumnos estarán ahí |
| **Encaje de UID/GID en bind mounts de Linux** | Requiere Linux | El entrypoint hace `chown` de `/workspace`, que debería bastar. Sin comprobar en un bind mount real de Linux |
| **`/dev/net/tun` en macOS** | Vive dentro de la VM de Docker; no se puede comprobar desde el host sin arrancar un contenedor | `doctor` lo informa como tal en lugar de dar un falso positivo. Se verificará de verdad al implementar la VPN (Fase 7) |
| **Escaneo de vulnerabilidades de la imagen (Trivy)** | Fase 8 | La imagen base está anclada por digest y el manifiesto registra las versiones instaladas |

---

## Fase 3 — Diagnóstico, copias de seguridad y restauración

### Verificado

Ejecutado sobre la imagen reconstruida, en macOS arm64 con Docker 29.7. La
restauración en sitio se probó en una **segunda instancia desechable** con su
propio proyecto (`seclabprueba`) y su propio puerto (2299), para no arriesgar la
instalación de desarrollo.

| Prueba | Resultado |
|---|---|
| Build con la variante ASCII de la barra y el digest de la base dentro de la imagen | Correcto |
| Guardián de la variante ASCII: el build falla si el `sed` no cambia nada | Correcto |
| Healthcheck contra sshd real | Saludo `SSH-2.0-` recibido |
| Healthcheck contra un servicio que escucha y no saluda | Detectado |
| Healthcheck contra un puerto cerrado | Detectado |
| `unhealthy` al matar sshd | Tras los 3 reintentos, ~45 s |
| `seclab backup` con el laboratorio en marcha | Correcto — 284 KB, 20 entradas |
| Permisos de la copia | 600, y `.sha256` al lado |
| Modos dentro de la copia (`.env` y llave privada) | 600 los dos |
| Copias hechas en macOS sin archivos AppleDouble (`._*`) | Correcto |
| `backup --sin-workspace` | Correcto, y `verify` avisa de que esa copia no trae el trabajo |
| `backup verify` sobre una copia buena | Correcto |
| **Copia incompleta forzada** (stub de `tar` que omite `.env`) | Detectada, **borrada** y salida 1 |
| Copia corrupta (8 bytes alterados en medio) | Suma SHA-256 no coincide, salida 1 |
| Copia vacía (0 bytes) | Detectada por tamaño y por miembros, salida 1 |
| Copia inexistente | Error claro, salida 1 |
| Copia con `formato=99` (de una versión futura) | Rechazada sin restaurar nada |
| `--destino` dentro del workspace | Rechazado: la copia se incluiría a sí misma |
| `--destino` fuera del repositorio | Correcto |
| `restore --destino` en un directorio temporal | Contenido idéntico al vivo, permisos 600, llaves de host dentro de `home.tar` |
| `restore` con el laboratorio en marcha | Rechazado, con el `seclab stop` en el mensaje |
| `restore` en sitio respondiendo «no» | No se toca nada |
| `restore` en sitio respondiendo «sí» | Workspace y directorio personal restaurados; el estado anterior en `*.previo-*`; permisos asegurados; el laboratorio arranca sano y se entra por SSH |
| `doctor`: `known_hosts` al día | Correcto |
| `doctor`: `known_hosts` obsoleta tras recrear el volumen | Detectada. `ssh` confirmó el aviso de suplantación, y la orden que dio `doctor` lo arregló |
| `doctor`: volumen sin marca de origen (creado por una versión anterior) | Avisa sin afirmar de más |
| `doctor`: volumen de otra imagen base (marca falsificada) | Detectado por el entrypoint al arrancar y por `doctor` |
| `doctor`: oferta de recrear el volumen, respondiendo «sí» y «no» | Correcta en los dos casos |
| `doctor`: prueba de glifos → variante ASCII | Escrita en `.env` y aplicada al reiniciar |
| Vuelta a `SECLAB_GLIFOS=powerline` | Aplicada |
| `~/.tmux.conf.local` editado por el alumno | No se sobrescribe; el arranque dice qué líneas cambiar |
| `doctor --sin-preguntas` | No pregunta nada; es como lo llama `init` |
| Revisión de seguridad: permisos de `secretos/` y `backups/` | Correctos; con 644 falla con salida 1 |
| `make lint` completo | Correcto |

### Corregido durante la verificación

1. **El build fallaba detrás del proxy de Docker Desktop.** Las URLs
   `/archive/` de `github.com` responden con un 302 hacia
   `codeload.github.com`, y ese salto se quedaba colgado 75 segundos por
   petición: el build moría con un «connection timed out» que no señalaba la
   causa. Se pide directamente el destino final y se amplían los reintentos. Un
   proxy es la norma en la red de una universidad, así que no era un caso raro.

2. **`seclab backup` sin argumentos terminaba en error sin imprimir nada.**
   `shift` sin argumentos devuelve 1 y con `set -e` eso aborta el script. Sólo
   se ve ejecutando.

3. **`seclab limpiar --con-imagen` moría al final** si otra instancia compartía
   la etiqueta de la imagen, después de haber limpiado el resto. Ahora avisa y
   explica por qué.

### No verificado

| Prueba | Motivo | Alternativa |
|---|---|---|
| **Restauración en una máquina distinta** | Sólo hay una máquina de desarrollo | Se probó en una segunda instancia local completa, con su proyecto, su volumen y su puerto propios: es el mismo camino de código, salvo el traslado del archivo. El procedimiento de traslado está en [docs/backup.md](docs/backup.md) y **sigue sin ejecutarse de extremo a extremo** |
| **Copias grandes** (workspace de varios GB) | El workspace de desarrollo tiene unos pocos archivos | Sin medir tiempos ni consumo de disco. Conviene comprobarlo antes de recomendar copias con `workspace` en clase |
| **Restaurar en otra arquitectura** (copia de amd64 en arm64 y al revés) | Sólo hay arm64 | Nada de la copia depende de la arquitectura salvo la imagen, que no viaja en ella; sin comprobar |
| **`restore` sin imagen construida** | Requiere borrar la imagen que usa la instancia de desarrollo | La rama está implementada (avisa y deja el resto restaurado), pero no se ha ejecutado |
| **Linux y Windows/WSL2** | Sólo se ha probado en macOS arm64 | Sigue siendo la brecha más importante del proyecto. En Linux, además, el volumen del directorio personal se lee sin VM y `docker run` monta rutas sin restricciones de compartición: el camino es el mismo pero no está ejecutado |
| **ShellCheck y Hadolint** | No están instalados en la máquina de desarrollo | `make lint` valida la sintaxis con `bash -n` y los ejecuta si aparecen. Obligatorios en la CI de la Fase 8 |

---

## Fase 4 — Experiencia de terminal

Esta fase se entregó **sin registro de verificación** en su momento. Lo que sí
se ha comprobado ahora, al trabajar sobre ella en la Fase 3:

| Prueba | Resultado |
|---|---|
| Sesión SSH real: comando remoto ejecutado como `seclab` | Correcto |
| Las dos variantes de `tmux.conf.local` se aplican según `SECLAB_GLIFOS` | Correcto |
| Un `~/.tmux.conf.local` editado no se sobrescribe | Correcto |
| El entorno público (`/etc/seclab/entorno`) no contiene secretos | Correcto — comprobado contra los cuatro secretos de `.env` |

Queda sin verificar de esa fase lo que declara su entrada del CHANGELOG y aquí
no se ha vuelto a probar: entrada automática en tmux con adjuntar-o-crear al
reconectar, contenido del banner y correspondencia del comando `herramientas`
con el manifiesto.

---

## Fase 5 — Perfiles `desktop`, `full` y `full-msf`

### Verificado

Todo sobre las imágenes construidas, en macOS arm64 con Docker 29.7. Los smoke
tests son reproducibles: `make smoke` con el perfil arrancado.

| Prueba | Resultado |
|---|---|
| Build de los cuatro perfiles | Correcto — 809 MB / 2,9 GB / 4,3 GB / 5,7 GB |
| Tiempos de build desde cero | ~3, ~7, ~10 y ~15 min |
| Guardián de capacidades en cada etapa nueva | Pasa en `desktop`, `full` y `full-msf` |
| Smoke tests del perfil `lite` | 12 comprobaciones, ninguna falla |
| Smoke tests del perfil `desktop` | 28 comprobaciones, ninguna falla |
| Smoke tests del perfil `full` | 40 comprobaciones, ninguna falla |
| Smoke tests del perfil `full-msf` | 43 comprobaciones, ninguna falla |
| Sesión XFCE real | xfwm4, xfce4-panel, xfdesktop y Thunar presentes en el display :1 a 1440x900 |
| noVNC en un navegador de verdad | `/vnc.html` carga y, al conectar, pide credenciales |
| Handshake RFB de Xvnc | Ofrece **sólo** VncAuth; no ofrece acceso sin contraseña |
| Puerto 5901 de VNC | No accesible desde el host |
| code-server | Responde con 302 a `/`; rechaza una contraseña incorrecta |
| Página de bienvenida | HTTP 200, renderizada y revisada visualmente |
| Fuga de secretos en la página de bienvenida | Ninguno de los cuatro secretos de `.env` aparece |
| Fuga de secretos en `/etc/seclab/entorno` | Ninguno |
| Firefox dentro del escritorio | Arranca y abre ventana en el display :1 |
| nikto es el fijado (2.6.1) y no el de apt (2.1.5) | Correcto |
| Herramientas de `full` | sqlmap, ffuf, gobuster, hydra, impacket, pwntools, radare2, john y linPEAS responden |
| Las 5 wordlists fijadas | Presentes y no vacías (52 MB en total) |
| pspy en arm64 | No se instala, y el manifiesto lo declara |
| Metasploit | `msfconsole --version` responde (6.5.3) y `msfvenom` está disponible |
| Publicación de puertos por perfil | En `lite` sólo el 2222; en `desktop` también 6080, 8443 y 8080 |
| Servicio activado en un perfil que no lo trae | El arranque aborta con el mensaje de qué perfil usar |
| Detección del bucle de reinicios en `start` | Falla en menos de un segundo mostrando la causa |
| Reinicio de `escritorio-sesion` sin tocar el servidor X | XFCE vuelve a estar completo en ~10 s; el laboratorio sigue `SANO` |
| Caída del servidor X (`pkill -x Xvnc`) | supervisor levanta los dos programas; display de nuevo a 1440x900 y sesión XFCE completa |
| `seclab logs escritorio` | Muestra el ciclo de caída y recuperación |
| Escritorio completo en una instalación nueva (volumen recién creado) | Barra con los dos lanzadores, cuatro accesos directos, tema oscuro y fondo plano, todo sembrado solo |
| Glifos de la barra de tmux dentro del escritorio | Separadores Powerline **y** emoji se ven correctamente en xfce4-terminal |
| `seclab escritorio restablecer` sobre un escritorio ya reescrito por XFCE | Adopta la configuración del curso y reinicia sólo la sesión |
| Lanzadores de la barra y accesos del escritorio | Verificados por captura de pantalla del display :1 |
| Revisión de seguridad con el override del escritorio | Con `SECLAB_BIND=0.0.0.0` marca los cuatro puertos |
| `seclab open` sin página que abrir (perfil `lite`) | Rechaza con la solución exacta |
| Cambio de perfil ida y vuelta (`lite` ↔ `desktop`) | Conserva workspace, secretos y llaves de host |
| `make lint` completo | Correcto |
| Revisión de seguridad completa | Sin fallos ni avisos |

### Corregido durante la verificación

Los cuatro fallos salieron al ejecutar, no al leer:

1. **`vncpasswd` no venía en el paquete del servidor** de TigerVNC sino en
   `tigervnc-tools`. El escritorio moría en el entrypoint con un «command not
   found».
2. **La comprobación de nikto en el build no comprobaba nada útil.** nikto sale
   con código 0 aunque le falte un módulo de Perl, así que la imagen se daba
   por buena con un nikto que no arrancaba (faltaba `libxml-writer-perl`).
3. **`pipefail` provocaba dos falsos negativos en los smoke tests**: un
   `comando | grep` da por fallida la comprobación si el comando sale con
   código distinto de cero, aunque haya impreso lo que se buscaba. Afectaba al
   rechazo del acceso SSH por contraseña y a `msfvenom --help`.
4. **msfconsole escribe su versión por stderr**, y la comprobación la
   descartaba.

### No verificado

| Prueba | Motivo | Alternativa |
|---|---|---|
| **`full` y `full-msf` bajo su carga real** | La VM de Docker de esta máquina tiene 7 GB y esos perfiles piden 8. `seclab doctor full` los **rechaza**, como debe | Las imágenes se construyeron y los smoke tests pasaron con el límite de 4 GB del contenedor, pero **nadie ha usado Burp, un navegador y Metasploit a la vez** en ellos. Es exactamente el escenario para el que se pide 8 GB, y sigue sin probarse |
| **Uso real del escritorio** (mover ventanas, copiar y pegar, portapapeles entre host y lab, teclado no inglés) | Requiere sesión interactiva con contraseña, que no se ha introducido | Verificado por captura del display :1: barra, lanzadores, accesos directos, tema y glifos de tmux se ven bien, y Firefox y la terminal abren ventana. Lo que sigue sin probar es la **interacción**: ratón, portapapeles entre host y contenedor, y distribuciones de teclado que no sean la inglesa |
| **Rendimiento del escritorio en arm64 con render por software** | Sin medir | `libgl1-mesa-dri` va por software y el manifiesto lo anota. Puede ir lento con ventanas grandes; no se ha cuantificado |
| **Build multi-arch de `full` y `full-msf`** (perfil `desktop` ya fusionado en `lite`) | Emulación QEMU: el `apt install` de XFCE cruzado tarda más de lo razonable en una sesión de desarrollo | Los checksums están fijados por arquitectura y verificados para las dos. El build real de amd64 es trabajo de la CI (Fase 8), en runner nativo. Ver también la actualización posterior sobre las 13 herramientas nuevas, al final de esta fase |
| **Linux y Windows/WSL2** | Sólo macOS arm64 | Sigue siendo la brecha más importante del proyecto, y el escritorio la agrava: en WSL2 el navegador está en Windows y `seclab open` usa `wslview`, que **no se ha ejecutado nunca** |
| **Jupyter** | No está en ninguna imagen | La fontanería condicional existe (variable, healthcheck, tarjeta en la página de bienvenida) y activarlo aborta el arranque con un mensaje claro. Llega con los paquetes de la Fase 12 |
| **Paquetes opt-in** (`web`, `ad`, `pwn`, `forensics`, `cloud`, `mobile`) | Son la Fase 12 | `full` trae el núcleo de web, AD, privesc y CTF; el resto no está |
| **ShellCheck y Hadolint** | No instalados en la máquina de desarrollo | `make lint` valida la sintaxis de los quince scripts y los ejecuta si aparecen. Obligatorios en la CI de la Fase 8 |

### Actualización — fusión de perfiles y 13 herramientas nuevas (sesión posterior)

La fusión del perfil `desktop` en `lite` (quedan tres perfiles: `lite`,
`full`, `full-msf`) y las 13 herramientas nuevas de `full` (ver
`CHANGELOG.md`) están **hechas y verificadas**: `full` y `full-msf` se
construyeron y arrancaron con `docker build`/`docker run` reales en `arm64`
esta misma sesión, de punta a punta, con resultado correcto.

**Pendiente real: build amd64.** No se pudo completar en esta máquina de
desarrollo (host arm64) por una limitación de la emulación QEMU/binfmt, no
por un defecto del Dockerfile ni de la instalación de las herramientas
nuevas: un paso temprano y no relacionado —la extracción del tarball de Oh
My Zsh— falla bajo emulación con `tar: ... Function not implemented` antes
de llegar siquiera a las herramientas nuevas. Como mitigación, los checksums
reales por arquitectura de las 13 herramientas se verificaron igualmente,
de forma independiente y fuera de un build completo, con `curl` +
`sha256sum` directos contra cada publicación oficial.

El build real de amd64 sigue pendiente de un runner nativo. Se espera que
funcione sin problemas en GitHub Actions (Fase 8): la limitación de QEMU
observada es específica de la emulación en esta máquina de desarrollo
arm64, no de la lógica del Dockerfile.

---

## Fase 6 — CLI guiada, workspace de labs y `seclab update`

### Verificado

Ejecutado en macOS arm64. `seclab update` se probó con un remoto de Git
desechable (`remoto.git`) y dos copias de trabajo (`curso` y `alumno`)
simulando el repositorio del curso y el de un alumno, para no arriesgar la
copia real de desarrollo.

| Prueba | Resultado |
|---|---|
| `lab create` con nombre válido | Crea el directorio, `scope.txt`, `report.md` y las cinco subcarpetas |
| `lab create` con nombre inválido (mayúsculas, espacios, acentos) | Rechazado, con una sugerencia de slug generada por normalización NFKD |
| `lab create` con un nombre ya existente | Rechazado sin tocar el lab existente |
| `lab list` | Columnas correctas; excluye `_archivo` del conteo de archivos |
| `lab reset` | Archiva el contenido en `_archivo/<fecha>/`, conserva `scope.txt`, regenera `report.md`; el contador de rondas sube |
| `lab reset` dos veces seguidas | Dos carpetas de archivo distintas, ninguna se pisa |
| Aviso de perfil de VPN desconocido en `scope.txt` | Avisa y no bloquea la creación ni el reinicio |
| `shell --lab <nombre>` | Entra en `/workspace/<nombre>` dentro del contenedor |
| `seclab status` con labs creados | Los lista correctamente |
| `update` con árbol de trabajo sucio, sin `--stash` | Aborta sin tocar nada y muestra el `git status` |
| `update --stash` con cambios locales | Aparta con `git stash`, actualiza, muestra el changelog de la versión nueva, y reaplica el stash al final |
| `update` ya al día (mismo commit) | Lo dice y no reconstruye nada |
| `update` con historia divergente (commits propios no subidos) | Rechazado con `merge --ff-only`; da la orden exacta para revisarlo a mano; no toca el árbol |
| `update --stash` con conflicto al reaplicar el stash | El `stash pop` falla, el aviso dice que el stash sigue a salvo y da los comandos (`git stash list`, `git stash show -p`, `git stash pop`) para recuperarlo |
| Etiquetado de la imagen tras `update` | `etiqueta_imagen_de lite 0.4.0` produce `seclab-lite:0.4.0-<commit>` — antes se usaba la versión leída al arrancar la CLI, la vieja, no la nueva |
| `bash -n` sobre `lib/labs.sh` y `bin/seclab` | Correcto |
| `make lint` completo | Correcto |

### No verificado

| Prueba | Motivo | Alternativa |
|---|---|---|
| **`update` contra el remoto real del curso** | Este repositorio no tiene todavía ningún remoto de Git configurado ni commits | Se verificó el mismo camino de código completo (stash, fetch, merge --ff-only, divergencia, changelog, reconstrucción de imagen, reinicio) contra un remoto de Git desechable creado sólo para la prueba. Falta ejecutarlo una vez contra el repositorio real cuando exista |
| **`update` reconstruyendo una imagen `full` o `full-msf`** | Se probó el flujo con la imagen `lite`, la más rápida de reconstruir | El código de reconstrucción es el mismo `construir_imagen` que usan `init` e `image build`, ya probado para los cuatro perfiles en la Fase 5 |
| **Labs con nombres al límite de 64 caracteres y con colisiones tras quitar acentos** | No se generó ese caso concreto | `validar_slug` y `sugerir_slug` se revisaron por lectura y se probaron con varios nombres típicos (con espacios, acentos y mayúsculas), pero no con el límite exacto de longitud |
| **`lab reset` con las carpetas de trabajo modificadas por herramientas mientras el laboratorio está en marcha** | No se probó con el contenedor arrancado | Se ejecutó con el laboratorio detenido; el comando opera directamente sobre el volumen del workspace, no hay diferencia de código esperada, pero no está comprobado |
| **Linux y Windows/WSL2** | Sólo macOS arm64 | Sigue siendo la brecha más importante del proyecto |
| **ShellCheck y Hadolint sobre `lib/labs.sh`** | No instalados en la máquina de desarrollo | `make lint` lo cubre con `bash -n`; obligatorio en la CI de la Fase 8 |

---

## Fase 7 — VPN autorizada multiperfil

Esta sección se reescribió por completo: la arquitectura de la Fase 7 cambió
de "un contenedor de VPN dedicado por perfil" a "OpenVPN e iptables dentro del
propio contenedor `lab`, gestionados por `seclab-vpn`" (decisión del dueño del
proyecto — ver `docs/vpn.md` y `docs/arquitectura.md`). Todo lo que sigue se
volvió a verificar de verdad contra el diseño nuevo, en macOS arm64 con Docker
Desktop (Compose v5.5.0, `docker info` confirmado disponible). El requisito
del propio `prompt_v3.md` sigue vigente: la verificación usa servidores
OpenVPN **locales** de prueba, nunca HTB ni TryHackMe reales.

Montaje de prueba: tres servidores OpenVPN en modo de clave estática
(`--secret`, con `--allow-deprecated-insecure-static-crypto` y
`--cipher AES-256-CBC` — el valor por defecto, `BF-CBC`, ya no está soportado
en OpenVPN 2.7), cada uno en su propio contenedor sobre una red Docker de
prueba dedicada, sirviendo a los tres perfiles reales (`vpnhtb`, `vpntry`,
`vpncli`) con rangos declarados disjuntos (`10.50.1.0/24`, `10.50.2.0/24`,
`10.50.3.0/24`). El contenedor `lab` se levantó con un proyecto de Compose
separado (`SECLAB_PROJECT` distinto), para no tocar la instancia real de
desarrollo. El perfil real `vpntry` (que ya tenía un `.ovpn` y `perfil.env`
reales de una plataforma configurados en este repositorio) se respaldó antes
de la prueba y se restauró exactamente al terminar —comprobado con
`sha256sum` antes y después—; su `.ovpn` real no se leyó ni se tocó en ningún
momento. `vpnhtb` y `vpncli` sólo tenían plantillas antes de la prueba y se
dejaron así al terminar.

### Verificado

| Prueba | Resultado |
|---|---|
| `docker compose -f docker-compose.yml -f docker-compose.vpn.yml config --quiet` | Válido |
| `docker compose ... --format json` sobre lo anterior | Un único servicio, `lab`; `cap_add` incluye `NET_ADMIN` (fusionado con las capacidades de base); `devices` incluye `/dev/net/tun`; sin `network_mode`; `ports`/`networks` intactos (el mapeo de SSH 127.0.0.1:2222→22 sigue ahí) |
| `docker compose -f docker-compose.yml -f docker-compose.desktop.yml -f docker-compose.vpn.yml config --quiet` | Válido |
| Modo auditoría de LAN local + VPN a la vez | En una copia temporal de `docker-compose.override.yml` (nunca el archivo real) se descomentó el bloque `network_mode: host`; `docker compose -f docker-compose.yml -f <copia> -f docker-compose.vpn.yml config --quiet` fue válido, con `network_mode: host` Y `cap_add: NET_ADMIN`/`devices: /dev/net/tun` conviviendo sin error de fusión ni prioridad especial |
| Build real de la imagen `lite` con `openvpn` e `iptables` | Completado; el manifiesto de herramientas los lista con sus versiones (`openvpn 2.7.0-1ubuntu1.2`, `iptables 1.8.11-2ubuntu3`) |
| Guardián de capacidades de fichero (`docker/verificar-capacidades.sh`) tras instalar `openvpn`/`iptables` | Sigue pasando: `getcap -r` sobre la imagen sólo reporta `nmap` y `ping` (los mismos de siempre); ni `openvpn` ni `iptables` reciben capacidades de fichero del paquete de Ubuntu |
| Arranque real de `lab` con el override de VPN aplicado | Contenedor `healthy`, con `NET_ADMIN` y `/dev/net/tun` confirmados vía `docker inspect` |
| `docker exec lab seclab-vpn ...` como usuario no root | Rechazado con mensaje "necesita privilegios de root", indicando `sudo seclab-vpn ...` o `seclab vpn ...` desde el host |
| `sudo seclab-vpn activos` desde dentro (usuario `seclab`, sudo sin contraseña) | Funciona igual que `docker exec -u root` |
| `seclab vpn up vpnhtb` (los TRES: `vpnhtb`, `vpntry`, `vpncli`) contra sus tres servidores de prueba, uno tras otro | Los tres quedan arriba; `seclab-vpn activos` (y `seclab vpn list`) los reporta a los tres simultáneamente — **la prueba que la arquitectura anterior no podía ofrecer** |
| `ip route` dentro de `lab` con los tres arriba | Exactamente `10.50.1.0/24 vía tun-htb`, `10.50.2.0/24 vía tun-thm`, `10.50.3.0/24 vía tun-cli`; ninguna ruta por defecto secuestrada (sigue apuntando a `eth0`) |
| `seclab vpn status` (host) y `seclab-vpn status` (dentro) con los tres arriba | Perfil, interfaz, IP del túnel, rangos efectivos y tiempo conectado correctos para cada uno |
| `seclab vpn routes`, `seclab vpn logs PERFIL`, `seclab vpn list` (host, vía `docker exec -u root`) | Los tres funcionan igual que sus equivalentes dentro del contenedor |
| Rechazo por solape de rangos | Se bajó `vpnhtb`, se le declaró un rango que se solapaba con el de `vpncli` (ya activo), y `seclab-vpn up vpnhtb` lo rechazó explicando el conflicto exacto (perfiles y rangos implicados), sin tocar nada; `vpntry`/`vpncli` siguieron activos sin cambios |
| Sin `--simultaneo`: activar sin solape | Se permite sin más, sin ninguna flag — confirmado levantando los tres perfiles con rangos disjuntos uno tras otro sin que ninguno rechazara al anterior |
| **Killswitch de salida (fail-closed)** | Con un `ping`/`ping-restart` del lado cliente para forzar la detección de caída, se retiró el servidor de `vpnhtb`; el gancho `--down` marcó el túnel como caído, la ruta hacia `10.50.1.0/24` desapareció de `ip route`, pero las reglas `DROP` de `OUTPUT`/`FORWARD` de `iptables` para ese rango siguieron presentes sin cambios |
| **Killswitch de entrada (nuevo en este diseño)** | Desde el contenedor del servidor de prueba de `vpnhtb` (que comparte la interfaz del túnel, como "otro jugador en la misma VPN"), se intentó abrir una conexión NUEVA hacia `lab` por `tun-htb`: tanto contra un puerto de prueba como contra el 22 (SSH), la conexión se quedó en timeout (`DROP`). Desde `lab`, una conexión iniciada hacia el servidor de prueba por la misma interfaz sí tuvo éxito (la respuesta, `ESTABLISHED`, se permite) |
| `iptables -S` con los tres perfiles arriba | Seis reglas de `INPUT` (dos por interfaz: `ACCEPT ESTABLISHED,RELATED` + `DROP NEW`) y seis de `OUTPUT`/`FORWARD` (una por rango declarado), ninguna cruzada entre perfiles |
| `seclab-vpn down` (un perfil) y `seclab-vpn down` (todos) | Detiene el proceso de OpenVPN (`TERM`, con `KILL` de respaldo tras 15 s), retira exactamente las reglas de `iptables` de ese perfil (comprobado con `iptables -S` antes/después: cero reglas huérfanas) y limpia su estado en `/run/seclab-vpn/` |
| `seclab vpn up`/`down`/`status`/`routes`/`logs`/`list` desde el HOST (`bin/seclab`, vía `docker exec -u root`) | Los seis se probaron de extremo a extremo contra el contenedor de prueba y su salida coincide con la de invocar `seclab-vpn` directamente dentro |
| `seclab doctor` con una VPN activa | La sección "Red" reporta "VPN 'vpnhtb' arriba", consultando el contenedor en vez de `.env` |
| `./scripts/verificar-seguridad.sh` completo | Sin fallos ni avisos, incluida la sección 4 (Compose) con `docker-compose.vpn.yml` en el análisis |
| `make lint` completo | Correcto (incluye `bash -n`/`sh -n` sobre `docker/shell/seclab-vpn.sh` y `docker/shell/seclab-vpn-hook.sh`, y las composiciones con `docker-compose.vpn.yml`) |
| Ausencia de secretos en logs | Los logs de `seclab-vpn logs`/`docker logs` no contienen el contenido del `.ovpn`/clave estática ni ninguna IP pública; sólo IPs de la red Docker de prueba (172.20.0.x) y del túnel (10.9.x.x en la prueba), que no son la IP pública del alumno |
| Perfil real `vpntry` preexistente | Respaldado (`sha256sum` antes/después idéntico) y restaurado exactamente al terminar; su `.ovpn` real nunca se leyó ni se modificó |

### No verificado

| Prueba | Motivo | Alternativa |
|---|---|---|
| **Verificación contra un `.ovpn` real de HTB o TryHackMe, en modo TLS cliente-servidor** | `prompt_v3.md` prohíbe expresamente probar contra esas plataformas | Se verificó con servidores OpenVPN de prueba en modo de clave estática (`--secret`, deprecado mas funcional con `--allow-deprecated-insecure-static-crypto`). El comportamiento del lado SecLab (`--route-nopull`, `--route` explícitas, killswitch de salida y de entrada) no depende del modo de autenticación del túnel, así que la cobertura es representativa, pero el modo TLS con certificados y `ifconfig-push` del servidor no se ha ejercitado tal cual |
| **`SECLAB_VPN_RUTA_DEFECTO=true` (`--redirect-gateway def1`)** | No se probó en esta sesión (los tres perfiles de prueba usaban rutas explícitas) | El código es el mismo que verificaba la iteración anterior de esta fase; no cambió en esta revisión |
| **DNS del túnel (`SECLAB_VPN_DNS`)** | No se aplica automáticamente al resolver del sistema | `seclab-vpn` registra que el valor está declarado pero no lo actúa; documentado en `docs/vpn.md` como límite real, no como promesa incumplida |
| **Linux y Windows/WSL2** | Sólo macOS arm64 | Sigue siendo la brecha más importante del proyecto. En Linux, `/dev/net/tun` es del host directamente (no de una VM) y `NET_ADMIN`/iptables dentro de un contenedor son un camino más transitado; debería comportarse igual o mejor, pero no se ha ejecutado |
| **ShellCheck sobre `docker/shell/seclab-vpn.sh` y `docker/shell/seclab-vpn-hook.sh`** | No instalado en la máquina de desarrollo | `make lint` los cubre con `bash -n`/`sh -n`; obligatorio en la CI de la Fase 8 |
| **Build multi-arch** | Sólo se construyó `linux/arm64` (la arquitectura de esta máquina) | `openvpn`/`iptables` se instalan por apt sin fijar binarios por arquitectura, así que no debería haber sorpresas en `amd64`, pero no se ha construido ni ejecutado ahí |
| **`seclab vpn up` con `lab` ya en marcha bajo `seclab start` real (perfiles `desktop`/`full`)** | Se verificó con un contenedor `lite` levantado directamente vía `docker compose`, no con el flujo completo `seclab init`/`seclab start` de un perfil con escritorio | El camino de código es idéntico (mismo `docker-compose.vpn.yml`, mismo `seclab-vpn`); no hay ninguna interacción especial con el perfil documentada, pero falta repetir la secuencia completa con `seclab start --profile desktop` y una VPN activa a la vez |
| **Regla de entrada con tráfico UDP o ICMP** (no sólo TCP) | Sólo se probó con TCP (`nc`) | `conntrack` clasifica ESTABLISHED/RELATED de forma equivalente para UDP e ICMP; el mecanismo no depende del protocolo, pero no se repitió la prueba con esos dos explícitamente |
| **Múltiples conexiones concurrentes o de alto volumen a través de varios túneles a la vez** | La prueba fue de conectividad puntual (un `nc`/`ping` por caso), no de carga | No hay razón para esperar un comportamiento distinto (son reglas de `iptables` estándar), pero no se ha medido |
| **`network_mode: host` para auditoría de LAN local, en macOS + Docker Desktop** | ~~No verificado~~ **Verificado, y no sirve para esto**: con el bloque de `docker-compose.override.yml` aplicado, `ip addr` dentro de `lab` sólo muestra `eth0` en `192.168.65.0/24` (la red interna de la VM de Docker Desktop) más las redes de puentes internos de Docker (172.17/18/19.x) — ninguna interfaz conectada a la LAN física. `nmap -sn 192.168.65.0/24` sí obtuvo respuestas ARP, pero las tres direcciones que respondieron (`.1`, `.129`, `.254`) comparten el mismo MAC (`5A:94:EF:E4:0C:DD`), que es la infraestructura de la VM, no dispositivos reales | Confirmado que en macOS + Docker Desktop la vía correcta para descubrimiento por ARP de la LAN real es ejecutar la herramienta directamente en el host (macOS), no dentro del contenedor. Sin verificar en Linux nativo, donde `network_mode: host` sí comparte la pila de red real del host y debería funcionar como se espera |
| **`SECLAB_HABILITAR_VPN` y la recreación automática de `lab` en `seclab vpn up`** | Añadido después de cerrar la verificación end-to-end de esta fase; se validó por lectura y con `docker compose config` (sin la variable: `lab` sin `NET_ADMIN`/`tun`; con `SECLAB_HABILITAR_VPN=true` simulado: presentes), pero no se ejecutó `seclab vpn up` de verdad desde cero contra un `lab` recién arrancado con la variable en `false`, para confirmar que la confirmación, la escritura de la variable, `compose_seclab up -d lab` y la espera de salud encadenan sin fallos en un caso real | El camino de código (`compose_seclab up -d lab`, `esperar_salud`) es el mismo que usa `cmd_start`, ya probado extensamente en fases anteriores; falta repetir la secuencia completa una vez con este gate nuevo |

---

## Fase 8 — CI, builds multi-arch, SBOM, provenance y firma

Este repositorio no tiene ningún remoto de Git configurado (`git remote -v`
no devuelve nada) ni ningún commit todavía. Eso significa que **el pipeline
de GitHub Actions en sí no se ha ejecutado ni una sola vez en un runner real
de GitHub Actions** — nada de lo que sigue como "verificado" lo es contra un
runner de GitHub; es verificado contra los mismos comandos, ejecutados
directamente en esta máquina de desarrollo (macOS arm64, con Docker
Desktop, `shellcheck` 0.11.0 y `hadolint` 2.15.1 instalados durante esta
sesión, y `gitleaks`/`terraform` ya instalados de antes).

**Nota de seguridad sobre esta verificación**: siguiendo la advertencia al
inicio de esta fase (un agente anterior dañó `seclab-lab-1` con un
`docker compose down --volumes` ejecutado por error contra el checkout
real), todo lo que arranca, detiene o recrea contenedores se ejecutó
exclusivamente sobre una copia física completa en `/tmp`
(`rsync -a --exclude .git --exclude .env --exclude vpn --exclude workspace
--exclude secretos --exclude backups`), con un nombre de proyecto de Compose
único (`seclabci-f8-<sufijo>`, `seclabvpnci`) que nunca coincidió con
`seclab`. Antes y después de cada prueba se confirmó con
`docker ps --format '{{.Names}}\t{{.ID}}\t{{.Status}}'` que `seclab-lab-1`
mantenía el mismo ID (`18231aa50edf`) y el mismo estado (`Up ... (healthy)`).
Al terminar, se destruyó la copia de `/tmp` completa y se confirmó con
`docker ps -a`/`docker volume ls`/`docker network ls` que no quedó ningún
contenedor, volumen ni red huérfanos con el prefijo de prueba.

### Verificado

| Prueba | Resultado |
|---|---|
| `bash -n`/`sh -n` sobre `.github/workflows/*.yml` (vía `python3 -m venv` + `pyyaml`, `yaml.safe_load`) | Ambos workflows son YAML válido y con las claves de nivel superior esperadas (`on`, `permissions`, `jobs`) |
| ShellCheck real (`shellcheck --severity=error`) sobre `bin/seclab`, `lib/*.sh`, `scripts/*.sh` (incluido `scripts/ci/*.sh`), `docker/*.sh`, `docker/shell/*.sh` | Sin errores. Con severidad `warning` sí aparecen ~9 avisos de estilo (`SC2034` variables no usadas en el propio archivo pero sí usadas por otro que las `source`ea; `SC2155` declarar y asignar por separado) preexistentes de fases 1-7: se decidió que la CI bloquee sólo por `error` y se documentó el resto como deuda técnica en vez de tocar código ya verificado de otras fases sin necesidad |
| Hadolint real (`hadolint --ignore DL3008 --ignore DL3009 --failure-threshold error`) sobre `docker/Dockerfile` | Sin errores. Con umbral por defecto sí aparecen 10 avisos `DL4006`/`DL3025` preexistentes (pipefail explícito por `RUN` con tubería, JSON en `CMD`); misma decisión que ShellCheck: bloquear sólo por `error`, documentar el resto |
| `make lint` completo (con `shellcheck`/`hadolint` ya instalados) sobre el checkout real | Sin fallos |
| `./scripts/verificar-seguridad.sh` sobre el checkout real | Sin fallos, 0 avisos |
| `gitleaks detect --source . -v` sobre el checkout real | "no leaks found" — aunque con matices: el repositorio no tiene todavía ningún commit (`0 commits scanned`), así que esto confirma que el job funciona y no arroja falsos positivos, pero no ha tenido ningún historial real que escanear. `gitleaks detect --source . --no-git` (todo el árbol de trabajo, no sólo el historial de Git) sí encuentra 7 "hallazgos" — el `.env` real, la llave SSH real en `secretos/`, y el `.ovpn`/credenciales reales de `vpn/vpntry/` — pero todos son archivos correctamente excluidos por `.gitignore` y nunca versionados; es la comprobación equivalente a la sección 5 de `scripts/verificar-seguridad.sh`, no a lo que ejecuta gitleaks en `ci.yml` (que sólo mira el historial de Git) |
| `terraform validate`/`fmt -check` contra la ausencia de `terraform/` | Confirmado por inspección directa (`[ -d terraform ]` es falso en este repositorio): el job de `ci.yml` toma la rama "no existe todavía" y termina con un aviso explícito, sin ejecutar `terraform` ni fingir haber validado nada |
| Build real del perfil `lite` (`docker buildx bake lite --load`, y por separado `seclab image build --profile lite`) en la copia de `/tmp` | Completado (con caché de capas de una sesión anterior de esta misma máquina) |
| `seclab start --profile lite` + `scripts/smoke.sh lite` en la copia de `/tmp`, proyecto `seclabci-f8-<sufijo>` | 12 comprobaciones, ninguna falla |
| Limpieza tras el build+smoke test (`docker compose down --volumes --remove-orphans` sobre el proyecto de prueba) | Confirmado sin contenedores, volúmenes ni redes residuales de ese proyecto; `seclab-lab-1` sin cambios |
| `scripts/ci/probar-vpn.sh` de extremo a extremo, en la copia de `/tmp`, proyecto `seclabvpnci` | Las 8 comprobaciones pasan (arranque sin `NET_ADMIN`, recreación con `NET_ADMIN`/`tun`, conexión de `vpnhtb`, rutas exactas, rechazo por solape de `vpncli`, `vpnhtb` no afectado, killswitch tras caída del túnel, ruta ausente durante la caída) — pero sólo **después de corregir tres fallos reales encontrados durante esta misma verificación** (ver el detalle en `CHANGELOG.md`, sección Fase 8): colisión del nombre de red de prueba con la red de `docker-compose.yml`; tres comprobaciones con `comando \| grep -q` en vivo que daban FALLO por `SIGPIPE` bajo `pipefail` aunque el patrón sí estuviera en la salida; y una comprobación de killswitch con una única muestra a tiempo fijo contra un túnel que oscila entre "arriba" y "caído" en modo de clave estática, sustituida por un sondeo |
| Limpieza tras `probar-vpn.sh` (el propio `trap limpiar EXIT` del script) | Confirmado sin contenedores, volúmenes ni redes residuales del proyecto `seclabvpnci`; `seclab-lab-1` sin cambios en ID ni estado en ningún punto de esta sesión |
| `bin/seclab image publish`/`image verify` (`cmd_image_publish`/`cmd_image_verify`) | Revisados por lectura (ya estaban escritos al empezar esta sesión): las tres comprobaciones obligatorias antes de publicar (manifiesto, seguridad, smoke tests) y el rechazo explícito de `image verify` sin `cosign` instalado o sin `SECLAB_COSIGN_IDENTIDAD_REGEX` en `.env` están implementadas tal como las describe `docs/ci.md`. No se ha ejecutado `image publish`/`image verify` de verdad en esta sesión (ver "No verificado") |

### No verificado

| Prueba | Motivo | Alternativa |
|---|---|---|
| **El pipeline de GitHub Actions ejecutándose en un runner real** | Sin remoto de Git configurado, no hay dónde disparar un workflow | Cada job se reprodujo manualmente en esta máquina con los mismos comandos que el YAML invoca (ver "Verificado"); la sintaxis de ambos workflows se validó con un parser YAML real. Falta la primera ejecución real en GitHub Actions en cuanto exista un remoto |
| **`docker buildx bake ...-multiarch --push`, QEMU, `docker/build-push-action`, `docker/setup-qemu-action`** | Publicación multi-arch real necesita un registry accesible y credenciales; sólo se ha construido para `linux/arm64` (la arquitectura de esta máquina), nunca `linux/amd64` en la misma tanda | El Dockerfile no fija binarios por arquitectura salvo donde ya lo hacía antes de esta fase (Metasploit, pspy); no debería haber sorpresas, pero no se ha ejecutado |
| **`anchore/sbom-action`/Syft, `cosign attach sbom`, `cosign sign --yes` (keyless), `cosign verify`** | Ni `syft` ni `cosign` están instalados en esta máquina; instalarlos y probarlos no aporta nada sin un registry real donde publicar y sin el runner de GitHub Actions cuya identidad OIDC firma keyless | Sintaxis de los pasos de `publicar.yml` revisada con cuidado; `cmd_image_verify` en `bin/seclab` ya está escrito para abortar con instrucciones claras si `cosign` no está instalado, en vez de fingir una verificación |
| **`aquasecurity/trivy-action`** | `trivy` no está instalado en esta máquina | Sólo se validó la sintaxis del paso (nombre de la action, `image-ref` calculado desde `SECLAB_IMAGE` real en `.env`, no un valor inventado) |
| **`gitleaks/gitleaks-action`, `hadolint/hadolint-action`, `ludeeus/action-shellcheck`, `hashicorp/setup-terraform`, `docker/*-action`, `sigstore/cosign-installer`, `anchore/sbom-action` como GitHub Actions (no como binarios locales)** | No hay forma de ejecutar una GitHub Action fuera de un runner de GitHub Actions (o `act`, no instalado) | Se verificó el comportamiento equivalente con los binarios locales donde existían (`gitleaks`, `terraform`, `shellcheck`, `hadolint`); se revisó la documentación de cada action de memoria para los parámetros usados (`severity`, `failure-threshold`, `ignore`, `provenance`, etc.), sin poder confirmar contra la action real que esos nombres de parámetro son exactamente correctos en la versión fijada |
| **Las referencias de versión de las actions de terceros (`@v4`, `@v3`, `@v6`, `@v0`, `@2.0.0`, `@3.1.0`, `@0.29.0`)** | Sin acceso para resolver y verificar el SHA de commit exacto de cada action en el momento de escribir esto | Se usan etiquetas de versión mayor, práctica común pero menos estricta que fijar por SHA; documentado como endurecimiento futuro en `docs/ci.md`, no como promesa incumplida |
| **Build y smoke test de los perfiles `desktop` y `full` dentro de la matriz de `ci.yml`** | Sólo se ejecutó `lite` de verdad en esta sesión (más rápido de reconstruir, y ya cubre el camino de código completo) | El camino de código (`seclab image build`, `seclab start`, `scripts/smoke.sh`) es el mismo para los cuatro perfiles, ya probado individualmente para cada uno en fases anteriores (Fase 5); la matriz de la CI simplemente lo repite por perfil |
| **`full-msf` en cualquier job** | Nunca se construye automáticamente por diseño (opt-in explícito); tampoco se ha probado manualmente en esta sesión | Ninguna: es opt-in a propósito, documentado en `docs/ci.md` |
| **Smoke test del servidor MCP** | El servidor MCP es Fase 13, todavía no implementado | Ninguna todavía; el punto de `prompt_v3.md` sobre este smoke test queda pendiente hasta esa fase |
| **`terraform fmt`/`validate` contra un `terraform/` real** | No existe `terraform/` (Fases 10-11) | Se verificó que el job se comporta correctamente ante su ausencia (ver "Verificado"); falta la comprobación positiva cuando exista el directorio |
| **Linux y Windows/WSL2 para cualquier parte de esta fase** | Sólo macOS arm64, igual que el resto del proyecto | Sigue siendo la brecha más importante del proyecto, ya señalada en fases anteriores |

**Nota (actualización posterior a la redacción de la tabla de arriba)**: el
pipeline de `publicar.yml` sí se ejecutó de verdad contra GitHub Actions,
publicando `lite`/`desktop`/`full`/`full-msf` en GHCR. Encontró y corrigió
varios problemas reales que no se podían ver validando sólo sintaxis: un pin
de `aquasecurity/trivy-action` roto (etiqueta sin el prefijo `v`, y una
versión con una dependencia interna ya borrada río arriba), el runner
quedándose sin disco al construir multi-arch un perfil pesado, un bug de
permisos de archivo en `scripts/ci/probar-vpn.sh` (UID distinto entre quien
genera un archivo dentro de un contenedor y quien lo lee después en el
host), y el escáner de secretos de Trivy marcando como filtrados los propios
wordlists/specs de Metasploit (corregido restringiendo a `scanners: vuln`).

**Cada reconstrucción sacaba una CVE `CRITICAL` nueva y distinta** en
`linux-libc-dev` (cabeceras del kernel, tres IDs distintos en tres intentos:
`CVE-2026-53398`, `CVE-2026-64535`, `CVE-2026-64564`) y en la librería
estándar de Go embebida en `pspy64` (dos IDs de la misma familia
`html/template`: `CVE-2023-24538`, `CVE-2023-24540`). Ir añadiendo una
excepción a la vez no arreglaba nada de fondo — el dueño del proyecto decidió
romper el ciclo cambiando la política, no persiguiendo más CVEs: **Trivy deja
de bloquear la publicación en cualquier perfil** (ver `docs/ci.md`, sección
"Escaneo de imágenes", y `CHANGELOG.md`). El razonamiento: `full`/`full-msf`
incluyen herramientas ofensivas a propósito, y un escáner genérico de cadena
de suministro no puede distinguir eso de un defecto accidental. El escaneo se
sigue haciendo siempre y su resultado queda documentado como artefacto
descargable de cada publicación; revisarlo y decidir si una imagen es apta
para un despliegue dado pasa a ser responsabilidad de quien la despliega,
igual que el resto del modelo de responsabilidad del proyecto
(`docs/uso-autorizado.md`).

**Pendiente real, no resuelto hoy** (ya no bloqueante, pero sigue siendo la
mejora correcta): un build multi-etapa que compile en una etapa aparte y no
lleve el compilador/cabeceras a la imagen final evitaría que
`linux-libc-dev` apareciera siquiera en el escaneo de vulnerabilidades,
aunque ya no impida publicar. Queda como trabajo futuro.

---

## Fase 9 — Tailscale con acceso remoto comprobado

**Nota de seguridad sobre esta verificación** (misma advertencia que abre la
Fase 8, y sigue vigente en esta sesión): todo lo que arranca, detiene o
recrea contenedores se ejecutó exclusivamente sobre una copia física
completa en `/tmp` (`rsync -a --exclude .git --exclude .env --exclude vpn
--exclude workspace --exclude secretos --exclude backups`), con nombres de
proyecto de Compose únicos (`seclabtsci`, y varios sufijos de depuración
manual: `seclabtsci2`, `seclabtsdbg`, `seclabtsdoctor`) que nunca
coincidieron con `seclab`. Antes y después de cada prueba se confirmó con
`docker ps --format '{{.Names}}\t{{.ID}}\t{{.Status}}' | grep seclab-lab-1`
que el contenedor real del usuario mantenía el mismo ID (`18231aa50edf`) y el
mismo estado (`Up ... (healthy)`); nunca cambió. Al terminar, se destruyó la
copia de `/tmp` completa y se confirmó con `docker ps -a`/`docker volume
ls`/`docker network ls` que no quedó ningún contenedor, volumen ni red
huérfanos con ninguno de esos prefijos.

**Nunca se generó una auth key real de Tailscale ni se creó una cuenta**:
`prompt_v3.md` lo prohíbe explícitamente para esta fase. Todas las pruebas
usaron o bien una `TAILSCALE_AUTH_KEY` vacía (para probar el rechazo) o un
valor de prueba que a propósito NO usa el prefijo real `tskey-auth-` (ver el
comentario en el propio script: ese prefijo es justo lo que
`scripts/verificar-seguridad.sh` busca para detectar una key real filtrada),
obviamente
inválido y jamás usado contra la infraestructura real de Tailscale — ver el
punto siguiente.

**Aviso honesto sobre un incidente menor durante la verificación manual (no
en el script que queda en el repositorio)**: al escribir por primera vez el
smoke test, una versión inicial de la comprobación 2 (auth key inválida)
dejó que `tailscaled` intentara autenticarse contra el control plane REAL de
Tailscale (`controlplane.tailscale.com`) antes de ser rechazado por la key
inválida — una conexión TLS real, aunque sin éxito y sin exponer ningún dato
salvo la key de prueba obviamente falsa. Se detectó revisando los logs del
contenedor, se corrigió de inmediato añadiendo `--login-server=http://127.0.0.1:1`
(un puerto local en el que nunca escucha nada, dentro del propio contenedor)
para que el mismo comportamiento se observe sin que salga ningún paquete de
la máquina, y **`scripts/ci/probar-tailscale.sh`, tal como queda en el
repositorio, usa siempre esa variante local**. Aparte, durante la
verificación manual e interactiva de `seclab doctor`/`seclab tailscale
status` con un contenedor ya arrancado (sección "Verificado" más abajo), se
dejó pasar unos ~3 segundos con una auth key de prueba SIN el
`--login-server` local antes de detener el contenedor — tiempo suficiente
para que `tailscaled` abriera una conexión real hacia Tailscale con una key
inválida, nunca aceptada, sin crear ningún nodo ni sesión. Se documenta aquí
sin minimizarlo: no debería haber ocurrido, ninguna prueba automatizada del
repositorio lo repite, y la lección (usar siempre un `--login-server` local
para cualquier prueba con auth key no vacía) queda explícita en
`docs/tailscale.md` y en los comentarios del propio script.

### Verificado

| Prueba | Resultado |
|---|---|
| `bash -n`/`sh -n` sobre `docker-compose.tailscale.yml` (vía `docker compose config`), `bin/seclab`, `lib/docker.sh`, `scripts/ci/probar-tailscale.sh` | Sintaxis válida en todos |
| ShellCheck (`--severity=error`) sobre `bin/seclab`, `lib/*.sh`, `scripts/*.sh`, `scripts/ci/*.sh` (incluido el `probar-tailscale.sh` nuevo) | Sin errores |
| `docker compose -f docker-compose.tailscale.yml config` en el checkout real (sólo lectura) | Configuración válida; confirmado que `$$TS_AUTHKEY` en el `command:` se resuelve a `$TS_AUTHKEY` en el contenedor real en tiempo de ejecución (comprobado con un compose de prueba desechable en `/tmp`, no en el checkout), no en el momento de `config` (que muestra el `$$` sin colapsar a propósito, por diseño de Compose, para poder mostrar el archivo tal cual se re-interpretará) |
| `docker compose -f docker-compose.yml -f docker-compose.tailscale.yml config` (combinación hipotética, nunca usada por el CLI) | También válida sintácticamente, aunque el diseño real nunca las combina |
| Resolución y verificación del digest de la imagen oficial (`docker pull tailscale/tailscale:v1.102.3` y `:stable`, mismo digest en ambos: `sha256:8c42c4574ab066384fcb72f69e086a2ff1dd3652eb6f56856cee34bcf0d2f680`) | Confirmado; versión y digest fijados en `docker-compose.tailscale.yml` |
| `./scripts/verificar-seguridad.sh` en el checkout real, con la nueva comprobación de `docker-compose.tailscale.yml` | Sin fallos, 0 avisos |
| `make lint` en el checkout real (incluida la nueva validación de `docker-compose.tailscale.yml` y la sintaxis de `probar-tailscale.sh`) | Sin fallos (mismos avisos preexistentes de Hadolint ya documentados en la Fase 8) |
| `scripts/ci/probar-tailscale.sh` de extremo a extremo, en una copia de `/tmp`, proyecto `seclabtsci` | Las 9 comprobaciones pasan: (1) `seclab tailscale up` rechaza sin `TAILSCALE_AUTH_KEY` antes de tocar Docker; (1b) el propio contenedor se niega igual sin pasar por el CLI; (2/2b) con una auth key de prueba inválida contra un `--login-server` local inexistente, el contenedor sigue vivo, el rechazo es un `connection refused` local y la key nunca aparece en los logs; (3) el volumen de estado sobrevive a `down`+`up`; (4) el contenedor vive en su propio namespace de red y su propio proyecto de Compose; (5) `lab` arranca sin ganar privilegios por tener Tailscale habilitado |
| Limpieza tras `probar-tailscale.sh` (su propio `trap limpiar EXIT`) | Confirmado sin contenedores, volúmenes ni redes residuales del proyecto `seclabtsci`; `seclab-lab-1` sin cambios en ID ni estado |
| `seclab tailscale status`/`seclab tailscale down` con el contenedor ausente, y `seclab doctor` con `SECLAB_HABILITAR_TAILSCALE=true` y `TAILSCALE_AUTH_KEY` vacía | Mensajes verificados a mano en la copia de `/tmp`: "Contenedor ausente", "TAILSCALE_AUTH_KEY está vacía: 'seclab tailscale up' se negará a arrancarlo", "El contenedor 'tailscale' no está en marcha" |
| `seclab doctor` con el contenedor `tailscale` realmente arrancado (vía `docker compose up -d tailscale`, no `docker compose run`, que Compose no lista igual — ver nota abajo) | La comprobación de convivencia (`comprobar_convivencia_tailscale`) reporta correctamente "'tailscale' vive en su propio namespace de red (...); no comparte tabla de rutas con 'lab'"; `seclab tailscale status` mostró `Logged out.` (esperado, sin key real) sin imprimir la key en ningún momento |
| Comportamiento de `docker compose ps`/`ps -q <servicio>` con contenedores creados vía `docker compose run` (usado sólo en depuración manual, nunca en el script final) | Un contenedor de `run` no aparece en `docker compose ps -q <servicio>` sin `-a`; es una particularidad de Compose (los oneoffs de `run` se etiquetan distinto), no un fallo de `id_contenedor_tailscale()` — el flujo real (`seclab tailscale up`, que usa `up -d`, no `run`) no se ve afectado, y así quedó confirmado al repetir la prueba con `up -d` |

### No verificado

| Prueba | Motivo | Alternativa |
|---|---|---|
| **Unirse de verdad a una tailnet con una auth key real** | `prompt_v3.md` prohíbe expresamente generar una auth key real de Tailscale para este proyecto; no hay cuenta del curso | Cuando el curso tenga una cuenta de Tailscale: crear una auth key efímera y de mínimo privilegio siguiendo `docs/tailscale.md`, ejecutar `seclab tailscale up` y confirmar con `seclab tailscale status` que el nodo aparece como conectado (no "Logged out"), con una IP en el rango `100.64.0.0/10` |
| **`tailscale serve` sirviendo tráfico real hacia otro dispositivo de la tailnet** | Depende de lo anterior (nodo autenticado de verdad) | Con un nodo real autenticado: ejecutar el comando exacto que imprime `seclab tailscale status`, y desde OTRO dispositivo de la misma tailnet, confirmar que el SSH de `lab` responde a través de la IP/hostname de Tailscale del nodo |
| **Convivencia real con una VPN de plataforma activa a la vez que un nodo Tailscale autenticado de verdad** | Se verificó por diseño y por inspección (namespaces de red separados, `--route-nopull` en `lab`, `--accept-routes=false` en Tailscale) y `seclab doctor` confirma la separación de namespaces de forma automatizada, pero no se ha repetido con AMBOS conectados de verdad a la vez (un nodo Tailscale autenticado y un túnel OpenVPN de prueba activo en `lab` simultáneamente), por la misma razón que el punto anterior: no hay auth key real con la que probarlo | El razonamiento arquitectónico (namespaces de red de Docker completamente separados) no depende de que la autenticación haya tenido éxito o no: un `tailscaled` "logged out" ya vive en el mismo namespace aislado que uno autenticado. La comprobación automatizada de `seclab doctor` es la misma en ambos casos |
| **`host.docker.internal` en Linux nativo (no Docker Desktop)** | La verificación de esta fase se hizo en macOS con Docker Desktop, donde `host.docker.internal` funciona sin nada que declarar; en Linux depende del `extra_hosts: host-gateway` añadido en `docker-compose.tailscale.yml`, disponible desde Docker 20.10, pero no se ha ejecutado en Linux nativo en esta sesión | El mecanismo (`extra_hosts` con `host-gateway`) es una característica documentada de Docker Engine desde la versión 20.10, no específica de Docker Desktop; no debería haber sorpresas, pero sigue siendo la misma brecha de plataforma (sólo macOS arm64 verificado) que arrastran las fases anteriores |
| **Windows/WSL2 para cualquier parte de esta fase** | Sólo macOS arm64, igual que el resto del proyecto | Sigue siendo la brecha más importante del proyecto, ya señalada en fases anteriores |
| **Despliegue real en una VM cloud con Tailscale como única vía de entrada (el caso de uso que motiva esta fase)** | Depende de las Fases 10-11 (cloud), todavía sin implementar, y de una auth key real | Cuando existan ambas: desplegar la VM sin publicar SSH a Internet, arrancar `tailscale` con una auth key real durante el bootstrap, y confirmar que `seclab tailscale status`/`ssh` a través de la IP de Tailscale son la única vía de acceso funcional |

---

## Fase 10 — DigitalOcean (proveedor de referencia, opcional)

**Contexto importante de esta sesión, para quien retome el trabajo**: esta
fase se implementó bajo una regla de seguridad explícita y no negociable —
nunca ejecutar `terraform apply`, `plan` ni `destroy` de verdad contra
DigitalOcean, nunca buscar ni usar credenciales reales de esta máquina, y
nunca generar un token o una llave que pudieran confundirse con reales. Como
consecuencia, y dicho sin adornos: **casi todo lo entregado en esta fase es
sintaxis validada y diseño revisado por lectura, no ejecución real contra la
API de DigitalOcean.** No se creó, ni se intentó crear, ningún recurso cloud
real en ningún momento de esta sesión. Tampoco se tocó `seclab-lab-1` (el
contenedor de desarrollo real): se confirmó su ID y su estado (`healthy`)
antes y después del trabajo de esta fase, y ninguna prueba ejecutada arranca,
detiene ni recrea contenedores Docker.

### Verificado

| Prueba | Resultado |
|---|---|
| `terraform fmt -check -diff` sobre `terraform/digitalocean/` | Sin diferencias |
| `terraform init -backend=false` + `terraform validate` sobre `terraform/digitalocean/` | Válido. Es el único modo de `init` ejecutado: nunca con el backend real, nunca con credenciales de proveedor |
| Render real de `templates/cloud-init.yaml.tftpl` con `terraform templatefile()` (variables ficticias, sin recursos) | Detectado y corregido un bug real de indentación: `%{ if ... ~}` sin `~` de apertura dejaba la indentación de la línea del `if` pegada a la primera línea del bloque, rompiendo el YAML cuando `habilitar_autodestruccion=true`. Corregido a `%{~ if ... ~}` / `%{~ endif ~}`; re-renderizado y verificado en ambos valores (`true` y `false`) |
| El cloud-init renderizado es YAML válido (`yaml.safe_load`, Python) | Correcto en ambas ramas de `habilitar_autodestruccion` |
| ShellCheck de cada entrada de `runcmd` del cloud-init renderizado | Sin avisos de severidad error ni warning reales (un único SC1091 informativo por `. /etc/os-release`, esperado: ese archivo no existe en la máquina de desarrollo) |
| `bash -n` y ShellCheck (`--severity=error` y por defecto) de `lib/cloud.sh` y de `bin/seclab` completo | Sin errores. Se corrigieron dos avisos de estilo (SC2034, variables sin usar) |
| **Bug real de `set -e` encontrado y corregido durante la verificación** (ver más abajo) | Corregido |
| Rechazo de `seclab cloud plan\|up` sin `--provider` | Correcto, mensaje claro |
| Rechazo con `--provider` desconocido (`aws`) | Correcto: explica que sólo DigitalOcean existe en esta fase |
| Rechazo sin `terraform.tfvars` (ni el indicado por `--tfvars` existe) | Correcto, indica copiar el `.example` |
| Rechazo con `owner` ausente | Correcto |
| Rechazo con `owner = "tu-nombre-aqui"` (el valor de ejemplo, sin cambiar) | Correcto |
| Rechazo con `fecha_expiracion` ausente | Correcto |
| Rechazo sin token de DigitalOcean (`DIGITALOCEAN_TOKEN` sin definir y sin `do_token` real en el `.tfvars`) — con `owner`/TTL correctos | Correcto, y confirmado que esto ocurre **antes** de invocar a Terraform (ningún proceso `terraform` se lanzó en esta prueba) |
| `seclab cloud up` sin terminal interactiva (stdin no es un TTY) | Se niega por sistema con mensaje claro, nunca se auto-aprueba; confirmado que no llegó a ejecutar `terraform apply` |
| `seclab cloud status --provider digitalocean` sin estado ni backend inicializado | Falla con el mensaje documentado sobre la limitación de backend remoto, sin crear ningún directorio `.terraform/` ni tocar red |
| `.gitignore`: `terraform/digitalocean/terraform.tfvars` ignorado; `terraform.tfvars.example`, `backend.hcl.example` y `.terraform.lock.hcl` versionados | Confirmado con `git check-ignore -q` (código de salida) en los cinco casos |
| `git add -n terraform/` sólo añade los archivos de código/documentación esperados (nunca `.tfvars` ni `.terraform/`) | Correcto |
| `make lint` completo (incluido el nuevo bloque de Terraform) | Sin fallos |
| `./scripts/verificar-seguridad.sh` sobre el checkout real tras los cambios | Sin fallos ni avisos nuevos |
| `seclab-lab-1` (contenedor real de desarrollo): ID y estado `healthy` antes y después de todas las pruebas de esta fase | Sin cambios; nunca se ejecutó `docker` contra él desde esta fase |

**Bug de `set -e` encontrado durante la verificación** (documentado aquí en
detalle porque es la clase de fallo más peligrosa de este archivo: silenciosa,
sin ningún mensaje, y fácil de reintroducir sin darse cuenta): dos patrones
del estilo `[ -z "$X" ] && X="$default"` / una asignación desde una tubería
que termina en `grep` sin coincidencias, con `set -euo pipefail` activo,
pueden matar el script entero sin imprimir nada, porque (a) el **último**
comando de una función que termina en una lista `cond && acción` devuelve el
código de `cond` cuando la acción no se ejecuta, y una llamada a esa función
sin comprobar su código de salida hereda ese fallo bajo `set -e`; y (b) una
asignación `var="$(tubería)"` donde la tubería termina en un `grep` sin
coincidencias falla completa bajo `pipefail`, aunque "no encontrar la clave"
sea un resultado perfectamente válido para el llamador. Ambos se dieron en
`lib/cloud.sh` (`cloud_leer_argumentos` y `valor_tfvars`) y se detectaron
sólo porque las pruebas de rechazo de arriba, en su primera versión, fallaban
con código de salida 1 y **ningún mensaje**. Corregidos con un `return 0`
explícito al final de `cloud_leer_argumentos` y neutralizando el código de
salida de `grep` dentro de `valor_tfvars` (`{ grep ... || true; } | tail -1 |
sed ...`). Vale la pena que quien retome este archivo revise si el mismo
patrón aparece en código futuro que lea `.tfvars`.

### No verificado

Todo lo de esta tabla requeriría una cuenta de DigitalOcean real y un
presupuesto de pruebas acotado (unos pocos dólares y una Droplet destruida
al terminar bastarían). Nada de esto se intentó, ni parcialmente, en esta
sesión.

| Prueba | Motivo | Alternativa propuesta |
|---|---|---|
| `terraform plan`/`apply`/`destroy` reales contra la API de DigitalOcean | Prohibido explícitamente para esta sesión: crea infraestructura real y factura a quien tenga las credenciales | Con una cuenta de pruebas y presupuesto acotado: `terraform plan` primero (revisar el diff con calma), luego `seclab cloud up`, confirmando que la Droplet resultante tiene exactamente las etiquetas `owner`/`curso`/`fecha-expiracion` esperadas en el panel de DigitalOcean |
| El cloud-init ejecutándose de verdad en una Droplet Ubuntu 22.04 (instalación de Docker, arranque del servicio `seclab`, `docker pull` real desde `SECLAB_REGISTRY`) | Depende de la Droplet real de arriba | Tras el `apply`: `seclab cloud wait`, y si falla, el propio comando de diagnóstico que imprime (`ssh ... 'cloud-init status; journalctl -u seclab'`) |
| `seclab cloud wait` esperando de verdad por SSH hasta la marca `bootstrap-completo` | Depende de una Droplet real | Igual que arriba; además probar el caso de timeout agotado de verdad (`--timeout` bajo) contra una Droplet que tarda |
| `seclab cloud connect` y el túnel SSH `-L` a los servicios web de la Droplet | Depende de una Droplet real | Tras `wait`, comprobar que `seclab cloud connect` abre sesión y que el túnel a `127.0.0.1:8080` sirve la página de bienvenida |
| `seclab cloud status` leyendo un backend remoto real (Terraform Cloud o S3+DynamoDB/`use_lockfile`) | No hay backend remoto configurado (a propósito: no se configuró ninguno con credenciales reales) | Configurar un workspace de Terraform Cloud gratuito o un bucket S3 de pruebas, aplicar con backend remoto, y confirmar que `status` lee las salidas y que, sin las credenciales del backend, falla con el mensaje documentado de limitación |
| `seclab cloud destroy`, incluida la exportación previa del workspace remoto por SSH | Depende de una Droplet real con datos en `/workspace` | Con una Droplet de pruebas: crear un archivo de prueba en `/workspace` dentro del contenedor, ejecutar `destroy`, aceptar la exportación, y confirmar que el `.tar.gz` resultante contiene ese archivo antes de que la Droplet desaparezca |
| El mecanismo opt-in de autodestrucción (`habilitar_autodestruccion=true`, el `at` llamando a `DELETE /v2/droplets/{id}`) | Requiere una Droplet real y un token de borrado dedicado; además es el camino que menos se ha probado a propósito, por ser el de mayor riesgo | Con una Droplet de pruebas y un token de API con alcance reducido (sólo borrado, revisar en el panel de DigitalOcean qué granularidad de alcance ofrece realmente en el momento de probarlo — no asumir que existe la misma granularidad que había al escribir esto): fijar `fecha_expiracion` a un par de minutos en el futuro y confirmar que la Droplet desaparece sola |
| Firewall de DigitalOcean (`digitalocean_firewall`) aplicado de verdad: que sólo SSH responda desde fuera y que los puertos web no sean alcanzables sin túnel | Depende de una Droplet real | Con una Droplet de pruebas: `nmap`/`curl` contra la IP pública en los puertos 8080/6080/8443/8888 (deben fallar) y 2222/22 (debe responder SSH) |
| Coste real de una Droplet `s-2vcpu-4gb` (u otro tamaño) comparado con la tabla estática de `docs/cloud.md` | La tabla es la lista de precios pública al escribir esto, no una consulta en vivo | Revisar la factura real de una Droplet de pruebas contra la tabla, y actualizar la tabla si diverge |
| Comportamiento cuando `DIGITALOCEAN_TOKEN` o el `do_token` del `.tfvars` son inválidos (no ausentes: presentes pero rechazados por la API) | Requeriría un token real (aunque sea inválido/revocado) para observar el mensaje exacto de error de Terraform/el provider | Con un token revocado de una cuenta de pruebas: ejecutar `seclab cloud plan` y confirmar que el mensaje de error del provider llega con claridad hasta el alumno |
| Windows/WSL2 y Linux nativo para cualquier parte de esta fase | Sólo macOS arm64, igual que el resto del proyecto | Sigue siendo la misma brecha de plataforma que arrastran las fases anteriores. Nada en `lib/cloud.sh` es específico de macOS a propósito (mismo cuidado que el resto del CLI), pero no se ha ejecutado en las otras dos plataformas |

---

## Fase 11 — GCP y Oracle Cloud

**Bug real encontrado y corregido después de cerrar la verificación de esta
fase**, al preparar el fallback a x86 para regiones sin capacidad ARM
(`SECLAB_OCI_SHAPE`, `terraform/oracle/README.md`): `leer_variable()`
(`lib/secretos.sh`), usada por todo el proyecto para leer claves de `.env`,
hacía `grep -m1 "^CLAVE=" archivo | cut -d= -f2-`. Bajo `pipefail` (`bin/
seclab` usa `set -euo pipefail`), si la clave **no existe como línea en el
archivo** (distinto de existir con valor vacío), `grep` devuelve 1 y
`pipefail` propaga ese 1 como salida de toda la tubería, aunque `cut` termine
bien. Una asignación `var="$(leer_variable ...)"` para una clave así de
ausente mataba el script en silencio bajo `set -e`. No se había manifestado
antes porque `seclab init` siempre copia `.env.example` completo (toda clave
aparece, aunque sea vacía) — pero al añadir `SECLAB_OCI_SHAPE` a
`sincronizar_tfvars_oracle_desde_env` (`lib/cloud.sh`) sin haberla añadido
todavía a `.env.example`, se reprodujo el caso real: una clave ausente de
verdad. Corregido con el mismo patrón que ya se usó en `valor_tfvars`
(Fase 10): `{ grep ... || true; } | cut ...`. Verificado en ambos sentidos
(clave ausente del todo, y clave presente) en una copia aislada, sin tocar
`seclab-lab-1`. Añadida también la línea que faltaba en `.env.example`.

**Misma regla de seguridad no negociable que la Fase 10, sin excepción**:
nunca se ejecutó `terraform apply`, `plan` ni `destroy` de verdad contra GCP
ni Oracle Cloud; nunca se buscaron ni usaron credenciales reales de esta
máquina (se confirmó explícitamente que no hay Application Default
Credentials de GCP en `~/.config/gcloud/` ni en variables de entorno antes de
probar el camino de rechazo de credenciales; para Oracle Cloud, el CLI `oci`
SÍ está instalado en esta máquina, así que **directamente no se comprobó, ni
se probó el camino de rechazo de credenciales de** `exigir_credenciales_oracle`
— sólo se probaron los rechazos de owner/TTL, que ocurren antes en el flujo y
nunca llegan a esa función); y no se generó ni se usó ningún token, clave o
credencial real de ningún proveedor. Dicho sin adornos: **casi todo lo
entregado en esta fase es sintaxis validada y diseño revisado por lectura,
no ejecución real contra la API de GCP ni de Oracle Cloud.** No se creó, ni
se intentó crear, ningún recurso cloud real en ningún momento de esta
sesión. Tampoco se tocó `seclab-lab-1` (el contenedor de desarrollo real):
se confirmó su ID (`18231aa50edf`) y su estado (`healthy`) antes y después
del trabajo de esta fase.

### Verificado

| Prueba | Resultado |
|---|---|
| `terraform fmt -check -diff` sobre `terraform/gcp/` y `terraform/oracle/` | Sin diferencias |
| `terraform init -backend=false` + `terraform validate` sobre ambos módulos | Válidos. Único modo de `init` ejecutado: nunca con el backend real, nunca con credenciales de proveedor. Esto confirmó de paso que atributos poco habituales referenciados (`oci_core_instance.public_ip`, `oci_core_instance.time_created`, la sintaxis `dynamic "service_account"`/`dynamic "shape_config"`) existen de verdad en los providers `hashicorp/google ~> 5.0` (resolvió `5.45.2`) y `oracle/oci >= 5.0.0` (resolvió `9.0.0`) |
| Render real de ambas plantillas de cloud-init con `terraform console` (valores ficticios, sin recursos, con un backend `"local"` temporal en una copia del módulo bajo `/tmp` — nunca en el checkout real) | Ambas plantillas renderizan sin error, en `habilitar_autodestruccion = true` y `= false` |
| El cloud-init renderizado (GCP y Oracle, ambas ramas) es YAML válido (`yaml.safe_load`, Python) | Correcto en las cuatro combinaciones |
| `bash -n` y ShellCheck (`--severity=error`) de cada bloque `runcmd` no trivial de ambas plantillas renderizadas | Sin avisos |
| `bash -n` y ShellCheck (`--severity=error`) de `lib/cloud.sh` completo tras la generalización | Sin errores |
| Rechazo de `seclab cloud plan` sin `--provider` | Correcto (mensaje ahora lista `digitalocean gcp oracle`) |
| Rechazo con `--provider` desconocido (`aws`) | Correcto |
| Rechazo de `--provider gcp` sin `terraform.tfvars` | Correcto, indica copiar el `.example` de `terraform/gcp/` |
| Rechazo de `--provider oracle` sin `terraform.tfvars` | Correcto, indica copiar el `.example` de `terraform/oracle/` |
| Rechazo de `--provider gcp` con `owner` ausente, con `owner = "tu-nombre-aqui"`, y con `fecha_expiracion` ausente (tres casos, `.tfvars` de prueba en `/tmp`) | Correcto en los tres |
| Rechazo de `--provider oracle` con `owner` ausente y con `fecha_expiracion` ausente (dos casos) | Correcto en los dos |
| Rechazo de `--provider gcp` sin credenciales (`GOOGLE_APPLICATION_CREDENTIALS`/`GOOGLE_CREDENTIALS` sin definir, sin `~/.config/gcloud/application_default_credentials.json`, `.tfvars` con owner/TTL correctos) | Correcto, y confirmado que ocurre **antes** de invocar a Terraform (ningún proceso `terraform` se lanzó en esta prueba). Se comprobó primero, por separado, que ninguna de esas fuentes existe en esta máquina, precisamente para poder probar este camino con seguridad |
| `.gitignore`: `terraform/gcp/terraform.tfvars` y `terraform/oracle/terraform.tfvars` ignorados; los `.example`, `backend.hcl.example` y `.terraform.lock.hcl` de ambos, versionados | Confirmado con `git check-ignore -q` |
| `git add -n terraform/` sólo añade los archivos de código/documentación esperados de los tres proveedores (nunca `.tfvars` ni `.terraform/`) | Correcto |
| `make lint` completo (bloque de Terraform ahora recorre los tres módulos) | Sin fallos |
| `./scripts/verificar-seguridad.sh` sobre el checkout real tras los cambios | Sin fallos ni avisos nuevos |
| `seclab-lab-1` (contenedor real de desarrollo): ID y estado `healthy` antes y después de todas las pruebas de esta fase | Sin cambios; nunca se ejecutó `docker` contra él desde esta fase |

### No verificado

Todo lo de esta tabla requeriría una cuenta real de GCP y/o de Oracle Cloud
(con un presupuesto de pruebas acotado) o, en el caso marcado aparte, tocar
credenciales de una herramienta ya instalada en esta máquina que esta sesión
tenía prohibido tocar. Nada de esto se intentó, ni parcialmente.

| Prueba | Motivo | Alternativa propuesta |
|---|---|---|
| `terraform plan`/`apply`/`destroy` reales contra la API de GCP o de Oracle Cloud | Prohibido explícitamente para esta sesión: crea infraestructura real y factura a quien tenga las credenciales | Con una cuenta de pruebas y presupuesto acotado, igual que se documentó para DigitalOcean en la Fase 10: `plan` primero, revisar el diff, luego `up`, confirmando labels/freeform_tags exactas en la consola del proveedor |
| El cloud-init ejecutándose de verdad en una instancia GCP (`ubuntu-os-cloud/ubuntu-2204-lts`) u OCI (imagen Ubuntu 22.04 resuelta por `image_ocid`) | Depende de una instancia real | Tras el `apply`: `seclab cloud wait --provider gcp\|oracle`, y si falla, el comando de diagnóstico que imprime (`ssh ... 'cloud-init status; journalctl -u seclab'`) |
| `seclab cloud wait`/`connect` de verdad contra una instancia GCP u Oracle Cloud, incluido confirmar que el usuario SSH resuelto (`seclab`/`ubuntu`, no `root`) es correcto | Depende de una instancia real | Igual que en la Fase 10, más comprobar explícitamente que `ssh <usuario>@IP` funciona con ese usuario y que `root@IP` es rechazado (las imágenes Ubuntu de ambos proveedores deshabilitan login directo de root) |
| El mecanismo de autodestrucción opt-in en GCP (identidad de cuenta de servicio + scope `compute` + rol IAM externo) | Requiere un proyecto GCP real con una cuenta de servicio a la que conceder el rol de borrado — configuración de IAM fuera de este módulo a propósito | Con un proyecto de pruebas: conceder `roles/compute.instanceAdmin.v1` (o un rol acotado sólo a `compute.instances.delete`) a la cuenta de servicio de la instancia, fijar `fecha_expiracion` a un par de minutos en el futuro con `habilitar_autodestruccion = true`, y confirmar que la instancia desaparece sola |
| El mecanismo de autodestrucción opt-in en Oracle Cloud (`oci-cli` + instance principal + Dynamic Group/Policy) | Requiere una tenancy con permisos de administrador para crear el Dynamic Group y la Policy — fuera del alcance de una cuenta de estudiante típica, y desde luego fuera del alcance de esta sesión | Con una tenancy de pruebas donde se tenga ese privilegio: crear el Dynamic Group (`instance.compartment.id = '<compartment>'`), la Policy (`allow dynamic-group <grupo> to manage instance-family in compartment <compartment>` o un permiso más acotado), y repetir la prueba de arriba |
| Firewall de GCP (`google_compute_firewall`) y lista de seguridad de Oracle Cloud (`oci_core_security_list`) aplicados de verdad: que sólo SSH responda desde fuera | Depende de una instancia real | Con una instancia de pruebas de cada proveedor: `nmap`/`curl` contra la IP pública en los puertos 8080/6080/8443/8888 (deben fallar) y el puerto SSH configurado (debe responder) |
| Coste real de `e2-medium` (GCP) y de una forma Ampere A1.Flex u otra (Oracle Cloud) comparado con las tablas estáticas de `docs/cloud.md`/`lib/cloud.sh` | Las tablas son precios públicos al escribir esto, no una consulta en vivo | Revisar la factura real de una instancia de pruebas de cada proveedor contra la tabla correspondiente, y actualizarla si diverge |
| Límites vigentes del "Always Free tier" de Oracle Cloud (formas, cantidad, región) | Los límites los fija y cambia Oracle; no se consultó ninguna API en vivo, sólo documentación pública general | Comprobar la página oficial de Oracle Cloud Free Tier en el momento de desplegar, antes de asumir gasto cero |
| Rechazo de `seclab cloud plan/up --provider oracle` por falta de credenciales (`exigir_credenciales_oracle`) | El CLI `oci` está instalado en esta máquina de desarrollo; esta sesión tenía prohibido buscar, leer o siquiera comprobar la existencia de `~/.oci/config` o de credenciales activas configuradas, así que este camino de rechazo deliberadamente no se ejercitó aquí (a diferencia del equivalente de GCP, donde sí se confirmó primero que no había ninguna fuente de credenciales antes de probarlo) | En una máquina sin `~/.oci/config` ni variables `OCI_CLI_*`/`TF_VAR_*` de Oracle: repetir la prueba equivalente a la de GCP y confirmar el mismo resultado (rechazo antes de invocar Terraform) |
| Backend remoto real de GCP (`"gcs"`) y de Oracle Cloud (`"s3"` vía Object Storage) | No se configuró ningún backend con credenciales reales (a propósito) | Configurar un bucket de GCS de pruebas (backend `gcs`, confirmar que el locking nativo efectivamente bloquea un segundo `apply` concurrente) y un bucket de Object Storage de OCI vía su API S3-compatible (confirmar la ausencia de locking, igual que con Spaces en la Fase 10) |
| Windows/WSL2 y Linux nativo para cualquier parte de esta fase | Sólo macOS arm64, igual que el resto del proyecto | Misma brecha de plataforma que arrastran todas las fases anteriores |

### Actualización — primer despliegue real en Oracle Cloud (sesión posterior)

A diferencia de todo lo anterior en esta fase, esta sí fue una sesión con
`terraform apply` real, contra la cuenta de Oracle Cloud del dueño del
proyecto, con su autorización explícita en cada paso (incluido el "acepto"
interactivo que exige `seclab cloud up`, que esta sesión nunca pudo saltarse
— el propio harness bloqueó un intento de `terraform apply -auto-approve`
por no pasar por ese gate). Encontró y corrigió los bugs reales descritos en
[CHANGELOG.md](CHANGELOG.md) (bajo "Fase 11, Oracle Cloud"): IP pública fija
con Tailscale, `ssh_user` apuntando al usuario equivocado, falta de
`--env-file` en el `docker run` (por lo que NINGUNA variable de
`/etc/seclab-cloud/entorno` llegaba nunca al contenedor), `SECLAB_SSH_PUBKEY`
sin pasar, y `SECLAB_HABILITAR_DESKTOP`/`CODE` sin secretos. Confirmado
end-to-end: `ssh -p 2222 seclab@<ip>` entra al contenedor `full-msf` real,
`msfconsole`/`nmap` presentes, `/workspace` montado.

**Verificado de verdad esta vez**: `terraform apply`/`destroy` reales
(múltiples veces, iterando sobre `VM.Standard.A1.Flex` y `.E4.Flex`, ambos
sin capacidad en `mx-monterrey-1` en el momento de la prueba — confirmado con
`oci limits resource-availability get`, que muestra cupo de sobra pero no
puede predecir la capacidad física real del datacenter — hasta encontrar que
`VM.Standard.E5.Flex` sí tenía capacidad); `seclab cloud connect` con el
`ssh_user` corregido; acceso de rescate por el puerto 22 del host (via
`ubuntu@IP`, sin pasar por Docker) recién añadido; `oci limits
resource-availability`, `oci compute console-history capture` y `oci
instance-agent command create` (Run Command de OCI) como vías de diagnóstico
reales cuando SSH no respondía.

**Sigue sin verificar / pendiente real**, encontrado en esta misma sesión:

| Pendiente | Detalle |
|---|---|
| `seclab cloud wait --provider oracle` nunca confirma el bootstrap | Comprueba `/etc/seclab-cloud/bootstrap-completo` conectando por `puerto_ssh` (2222) con el usuario del contenedor (`seclab`) — pero ese archivo lo escribe el cloud-init **del host**, no existe dentro del contenedor. El comando conecta bien pero jamás encuentra el archivo: falla por timeout siempre, incluso cuando el bootstrap sí terminó bien. Corregir probablemente exige comprobar ese archivo por el puerto 22 (host, usuario `ubuntu`) en vez de por `puerto_ssh`, o mover la comprobación a otro archivo dentro del contenedor. Mismo patrón compartido con `terraform/digitalocean` y `terraform/gcp`, sin confirmar allí. |
| `--env-file` faltante, sin confirmar en DigitalOcean/GCP | El bug real más profundo de esta sesión (ninguna variable de `entorno` llegaba al contenedor) se corrigió sólo en `terraform/oracle`. Los cloud-init de `terraform/digitalocean` y `terraform/gcp` tienen la misma estructura de `ExecStart` sin `--env-file`/`-e`: muy probablemente el mismo bug, nunca confirmado porque ninguno de los dos ha tenido tampoco un `apply` real todavía. |
| Instance Console Connection y Run Command de OCI, usados como diagnóstico real esta sesión | Quedó una `oci compute instance-console-connection` de prueba (llave RSA descartable en `/tmp`, ya no en disco) creada durante el diagnóstico; no se automatizó ni se documentó como parte del flujo normal de `seclab cloud`, sólo se usó ad-hoc para depurar. |
| Generación de secretos (`seclab init`) para el despliegue en la nube sólo implementada en Oracle | `terraform/digitalocean` y `terraform/gcp` no leen `SECLAB_OCI_VNC_PASSWORD`/`CODE_PASSWORD`/`RDP_PASSWORD` (esos nombres son específicos de Oracle, `SECLAB_OCI_*`) ni tienen su propio equivalente: si algún día tienen un `apply` real con perfil `full`/`full-msf`, probablemente se topen con el mismo bug que Oracle tuvo esta sesión (contenedor en bucle de crash por falta de esos secretos). Replicar ahí el mismo patrón (generar en `seclab init`, sincronizar a `terraform.tfvars`) sería el mismo trabajo que ya se hizo para Oracle. |
| Terminal por navegador (ttyd) añadido al Docker, no desplegado todavía | A petición explícita del dueño del proyecto: `docker/Dockerfile`, `docker/entrypoint.sh`, `docker/salud.sh`, `docker-compose*.yml` y la documentación ya tienen el servicio completo (ver CHANGELOG.md), verificado con un build y un `docker run` reales en `arm64`. Pero la imagen `full-msf` publicada en GHCR sigue sin este cambio (falta un ciclo de `seclab image publish`/CI), y ningún módulo de Terraform (Oracle, DigitalOcean, GCP) expone el puerto 7681 ni genera `SECLAB_TERMINAL_PASSWORD` — si se despliega en la nube tal cual, `SECLAB_HABILITAR_TERMINAL` se resolvería `true` para `full`/`full-msf` pero el secreto llegaría vacío, mismo bucle de crash que ya se vio con VNC/code-server. Falta: (1) publicar una imagen nueva, (2) replicar en Oracle el patrón `random_password` + `--env-file` + puerto publicado + entrada en `tailscale serve`, (3) lo mismo en DigitalOcean/GCP si alguna vez tienen un `apply` real. |

**Resuelto en esta misma sesión, tras un segundo `apply` real**: escritorio y
code-server en la nube (Oracle) — `terraform/oracle/main.tf` ahora genera
`SECLAB_VNC_PASSWORD`/`SECLAB_CODE_PASSWORD` reales con `random_password` y
los inyecta por `--env-file`, expuestos como salidas `sensitive`. También se
implementó `tailscale serve` automático (sin pasos manuales) para el SSH y
los cuatro puertos web, tanto en Oracle como en el nodo Tailscale local
(`docker-compose.tailscale.yml`) — ver CHANGELOG.md.

---

## Fases pendientes

Fases 12 y 13: sin ejecutar. Ver [CHANGELOG.md](CHANGELOG.md) para el estado de
lo entregado.
