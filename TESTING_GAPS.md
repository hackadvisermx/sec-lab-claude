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
| **Build multi-arch de `desktop`, `full` y `full-msf`** | Emulación QEMU: el `apt install` de XFCE cruzado tarda más de lo razonable en una sesión de desarrollo | Los checksums están fijados por arquitectura y verificados para las dos. El build real de amd64 es trabajo de la CI (Fase 8), en runner nativo |
| **Linux y Windows/WSL2** | Sólo macOS arm64 | Sigue siendo la brecha más importante del proyecto, y el escritorio la agrava: en WSL2 el navegador está en Windows y `seclab open` usa `wslview`, que **no se ha ejecutado nunca** |
| **Jupyter** | No está en ninguna imagen | La fontanería condicional existe (variable, healthcheck, tarjeta en la página de bienvenida) y activarlo aborta el arranque con un mensaje claro. Llega con los paquetes de la Fase 12 |
| **Paquetes opt-in** (`web`, `ad`, `pwn`, `forensics`, `cloud`, `mobile`) | Son la Fase 12 | `full` trae el núcleo de web, AD, privesc y CTF; el resto no está |
| **ShellCheck y Hadolint** | No instalados en la máquina de desarrollo | `make lint` valida la sintaxis de los quince scripts y los ejecuta si aparecen. Obligatorios en la CI de la Fase 8 |

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

---

## Fases pendientes

Fases 9 a 13: sin ejecutar. Ver [CHANGELOG.md](CHANGELOG.md) para el estado de
lo entregado.
