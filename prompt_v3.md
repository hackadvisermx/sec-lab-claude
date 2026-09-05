# Prompt maestro para construir SecLab — v3

Actúa como arquitecto de plataformas, ingeniero DevSecOps, especialista en Docker/Terraform, integrador de agentes de IA (MCP) y formador de ciberseguridad. Construye desde cero un laboratorio de ciberseguridad llamado **SecLab** dentro del directorio de trabajo actual.

El resultado debe ser un producto funcional, seguro por defecto, reproducible, fácil de usar y listo para clases universitarias, CTFs, práctica de bug bounty y pruebas de seguridad únicamente autorizadas.

No te limites a describir una solución: implementa los archivos, scripts, configuración, documentación, pruebas y automatización necesarios. Trabaja por fases, verifica cada fase y no declares terminado algo que no hayas probado. Si una prueba no puede ejecutarse (por ejemplo, por falta de acceso cloud o de un dispositivo físico), documéntalo en `TESTING_GAPS.md` con motivo y alternativa propuesta.

## Contexto y modelo de uso (aula universitaria)

SecLab es una herramienta docente para un curso de ciberseguridad en una universidad pública. El modelo de despliegue es **individual por alumno**:

- Cada alumno despliega y opera **su propia instancia** de SecLab de forma independiente. No hay multiusuario, ni aislamiento entre alumnos, ni estado compartido: cada instancia pertenece al alumno que la ejecuta.
- **La ejecución local es la ruta principal y por defecto.** Debe funcionar en máquinas heterogéneas de estudiantes: macOS, Linux y Windows mediante WSL2; arquitecturas Intel (amd64) y ARM (arm64).
- `seclab init` detecta la plataforma (incluido Windows/WSL2) y **rechaza arrancar con un mensaje claro y amable** si la máquina no cumple los recursos mínimos del perfil elegido, indicando el mínimo requerido y sugiriendo un perfil más ligero.
- **Distribución de imágenes:** la ruta principal es que el alumno haga `pull` de las imágenes `lite` y `desktop` ya publicadas y firmadas desde el registry del curso, para que todos tengan un entorno idéntico sin builds largos. La construcción local es la ruta de respaldo documentada.
- **La nube es totalmente opcional.** Un alumno puede completar el curso íntegro sin usarla. Si la usa, el despliegue cloud corre en la cuenta y **a cargo económico del propio alumno**, bajo su exclusiva responsabilidad. SecLab no gestiona ni asume costos institucionales.
- **La VPN es parte del uso diario, no un extra.** Los alumnos trabajan mayoritariamente contra **TryHackMe** y **Hack The Box** a través de sus VPN, y el profesorado se conecta además a una **VPN de cliente/engagement** distinta. SecLab debe soportar tres perfiles de VPN separados (`vpnhtb`, `vpntry`, `vpncli`), cada uno con su propia configuración, sus rangos autorizados y su propio ciclo de vida. Ver la sección *VPN autorizada (multiperfil)*.
- Antes de aplicar cualquier despliegue cloud, el CLI debe: mostrar la estimación de costo, exigir confirmación explícita del alumno, **rechazar aplicar si no hay TTL/fecha de expiración definida**, advertir de forma prominente que el costo es personal del alumno, y recordar el comando de destrucción. `seclab cloud status` muestra qué recursos siguen activos y desde cuándo, para que nadie olvide una VM encendida facturando.

## Versión del proyecto

Usa semver. La versión inicial es `0.1.0`. El esquema de etiquetado de imágenes será `seclab-<perfil>:<version>-<commit-short>`. El changelog debe seguir el formato [Keep a Changelog](https://keepachangelog.com/es/1.0.0/).

## Reglas no negociables

1. Se da por supuesto que el laboratorio se utiliza contra objetivos propios o autorizados. Es una premisa del proyecto y responsabilidad de quien lo ejecuta, no algo que el software deba comprobar.
2. Los servicios deben quedar ligados a `127.0.0.1` por defecto.
3. Ningún servicio, puerto o laboratorio vulnerable debe quedar expuesto públicamente por defecto.
4. Los objetivos vulnerables se ejecutan sólo mediante perfiles opt-in y redes Docker aisladas.
5. No incluyas credenciales reales, tokens, VPNs, llaves privadas ni datos personales en Git.
6. Nunca uses contraseñas por defecto silenciosamente. El arranque debe fallar si falta una configuración segura.
7. **SecLab no valida ni bloquea objetivos.** Se asume que quien ejecuta el contenedor tiene autorización para usar todas las herramientas que incluye contra los objetivos que elija. No implementes validación de destinos, listas de rangos que bloqueen tráfico, ni rechazos de "objetivo fuera de scope". Ver la sección *Alcance y modelo de responsabilidad*.
8. No borres datos del usuario sin confirmación explícita y una alternativa de recuperación.
9. No ocultes errores con `|| true` en operaciones críticas.
10. Si una dependencia o herramienta es opcional, su fallo debe estar aislado y reportado con claridad.
11. El servidor MCP, si está activo, expone una lista blanca cerrada de operaciones y registra todo lo que hace. La allowlist limita **qué puede hacer el agente**, no contra qué objetivo.
12. Ningún archivo `.ovpn`, credencial de VPN, certificado o clave de plataforma puede entrar en Git, aparecer en logs, en mensajes del CLI, en la página de bienvenida ni en un informe generado.

## Alcance y modelo de responsabilidad

SecLab es una **estación de trabajo**: entrega las herramientas, el entorno reproducible y la organización del trabajo. No es un árbitro de lo que el usuario hace con ellas.

- **Los laboratorios externos quedan fuera del alcance del contenedor.** Hack The Box, TryHackMe y la VPN de cliente del profesorado son plataformas externas con sus propios términos de servicio y su propia autorización. SecLab se conecta a ellas y punto; no valida, no restringe y no supervisa el tráfico que las atraviesa.
- **Se asume autorización plena.** Quien ejecuta el contenedor tiene permiso para usar todas las herramientas incluidas. No añadas gates, campos de autorización obligatorios que impidan usar un lab, ni comprobaciones de "objetivo permitido" en el CLI ni en el servidor MCP.
- **La responsabilidad es del estudiante, bajo la guía del profesor.** La documentación lo recuerda una vez, con claridad y sin paternalismo; el software no lo impone.
- **Scope como documentación, no como cortafuegos.** El `scope.txt` de un lab y los rangos declarados de un perfil VPN sirven para las notas, la organización y el informe del alumno. Nunca para bloquear una operación.
- **Advertencias sí, bloqueos no.** El CLI puede avisar (por ejemplo, que el perfil VPN activo no coincide con el del lab abierto), pero nunca debe impedir continuar.

Lo anterior **no relaja** las medidas que protegen al propio usuario y a su máquina: binding a `127.0.0.1` por defecto, secretos fuera de Git, sin contraseñas por defecto silenciosas, targets vulnerables en redes Docker aisladas y confirmación antes de destruir datos. Esas siguen siendo obligatorias.

## Resultado esperado

Entrega un repositorio completo que permita:

- Instalar y arrancar el laboratorio local con un flujo guiado.
- Elegir perfiles de herramientas sin reconstruir una imagen ambigua.
- Usar una terminal cuidada desde el primer arranque: zsh con Oh My Zsh, tmux con la configuración del curso y sesión persistente, banner de bienvenida y ayuda de las herramientas instaladas.
- Usar escritorio web, code-server y, opcionalmente, Jupyter.
- Conectarse por SSH con llave y con acceso remoto privado mediante Tailscale (opcional).
- Gestionar varias VPN autorizadas con perfiles separados (`vpnhtb`, `vpntry`, `vpncli`), rutas acotadas, killswitch y sin fugas de tráfico.
- Crear workspaces de labs con scope, notas, evidencias y reportes.
- Resetear un lab a su estado limpio reproducible para repetir una práctica.
- Ejecutar objetivos vulnerables de forma aislada.
- Exponer, de forma opcional y acotada, un servidor MCP local consumible por un agente de IA.
- Construir imágenes reproducibles y multi-arquitectura.
- Publicar imágenes firmadas con SBOM y provenance.
- Desplegar en DigitalOcean, GCP y Oracle Cloud mediante Terraform (opcional, a cargo del alumno).
- Esperar a que el despliegue esté sano antes de declararlo terminado.
- Hacer backup, verificarlo y restaurarlo de forma segura.
- Diagnosticar problemas con mensajes accionables.

## Arquitectura requerida

### Imágenes

#### Imagen base y política de versiones de herramientas

La base es **Ubuntu LTS** en su variante más ligera, anclada por el digest de su
lista de manifiestos. **No uses Kali Linux**, ni su imagen ni sus repositorios,
en ningún perfil ni paquete. Tampoco mezcles repositorios de distintas
distribuciones: acaba en conflictos de dependencias difíciles de diagnosticar.

Ubuntu LTS se elige sobre Debian estable porque sus paquetes van al día y su
soporte de años encaja con el ciclo de una asignatura; Debian estable pesa unos
10 MB menos pero va un ciclo entero por detrás en cada herramienta, que es
justo lo que hay que evitar.

Aun así, **ningún repositorio de distribución basta para las herramientas
ofensivas de evolución rápida**. Aplica dos vías distintas y documenta cuál usa
cada herramienta en el manifiesto:

1. **Vía apt**, para el sistema base, utilidades y herramientas de red maduras
   (shell, coreutils, iproute2, tcpdump, nmap, dnsutils, OpenSSH, Python). Aquí
   el repositorio de Ubuntu LTS está al día y da estabilidad y parches de
   seguridad gratis.
2. **Vía publicación oficial con versión fijada y checksum verificado**, para
   las herramientas que se mueven rápido y cuyo paquete de distribución queda
   obsoleto enseguida: escáneres web, utilidades en Go del ecosistema de bug
   bounty, herramientas de Active Directory y similares. Fija la versión
   exacta, verifica el checksum o la firma de lo descargado y registra ambos en
   el manifiesto. Nunca descargues `latest` ni ejecutes un script de
   instalación remoto sin verificar.

Una herramienta cuyo paquete en Ubuntu esté claramente desactualizado **no se
instala vía apt**: o se trae por la segunda vía, o se omite del perfil y se
documenta por qué. Es preferible que falte a que un alumno trabaje con una
versión de hace años creyendo que está al día.

#### Perfiles

Implementa targets de BuildKit o Docker Bake claramente separados:

- `lite`: shell, red, recon básico y utilidades comunes.
- `desktop`: `lite` más XFCE, noVNC y code-server.
- `full`: `desktop` más Web, AD, privesc, wordlists y herramientas de CTF.
- `full-msf`: `full` más Metasploit, siempre opt-in.

Cada imagen debe tener una etiqueta inequívoca y labels con:

- Perfil.
- Versión de SecLab (semver, ej. `0.1.0`).
- Commit de origen.
- Fecha de build.
- Arquitectura.
- Manifiesto de herramientas y versiones, indicando para cada una si vino de
  apt o de una publicación oficial fijada.

Usa etapas compartidas para maximizar cache y evitar que los perfiles se confundan entre sí.

**Ningún binario de la imagen puede reclamar una capacidad que el contenedor no
tenga en su conjunto delimitador.** Si lo hace, el kernel rechaza su ejecución
por completo y la herramienta no arranca ni para imprimir su versión. Comprueba
las capacidades de fichero durante el build y detén la construcción si alguna
queda fuera del conjunto concedido.

**Multi-arquitectura**: Los Dockerfiles deben soportar `linux/amd64` y `linux/arm64`. La construcción cruzada real (`buildx --platform`) es opcional en entornos sin emulación QEMU; si no se puede ejecutar, documéntalo en `TESTING_GAPS.md`. La publicación multi-arch sólo ocurre desde CI. **El manifiesto de herramientas debe marcar explícitamente qué paquetes o herramientas degradan, cambian de versión o se omiten en `arm64`** (por ejemplo, herramientas sin binario ARM estable), para que un alumno con máquina ARM sepa de antemano qué esperar.

### Experiencia de terminal

El laboratorio se usa desde la terminal muchas horas seguidas. La experiencia por defecto debe ser buena desde el primer arranque, sin que cada alumno tenga que montarse el entorno por su cuenta ni copiar configuraciones de un compañero.

#### Shell: zsh con Oh My Zsh

- **zsh es el shell por defecto** del usuario de laboratorio. `bash` sigue instalado y disponible: el material de clase y los scripts que circulan por ahí lo asumen.
- **Oh My Zsh** se instala desde su publicación oficial, fijado por commit y con checksum verificado (vía 2 de la política de herramientas). Nunca mediante el instalador remoto sin verificar.
- **Plugins**, elegidos por utilidad real en un laboratorio de seguridad, no por acumular: `git`, `sudo` (repite el comando con sudo al pulsar `Esc` dos veces), `docker`, `tmux`, `extract` (descomprime cualquier formato con un solo comando, que en CTF se agradece), `colored-man-pages`, `command-not-found`, `history-substring-search`, `fzf`, `zsh-autosuggestions` y `zsh-syntax-highlighting`. Los dos últimos son externos a Oh My Zsh: fíjalos por commit igual que el resto.
- **El tema por defecto no debe depender de glifos especiales.** Ofrece una variante con Nerd Font que se active sola si el entorno los soporta, y documenta cómo cambiarla.
- El historial se conserva entre sesiones, con tamaño amplio y sin duplicados. Es material de trabajo: de ahí sale media metodología cuando toca escribir el informe.

#### tmux: Oh my tmux! con la configuración del curso

- Se usa **Oh my tmux!** (`gpakosz/.tmux`), fijado por commit y con checksum verificado. No lo vendorices: son casi 100 KB de código de terceros que su autor pide expresamente no modificar.
- La personalización del curso vive en `templates/shell/tmux.conf.local`, versionada en el repositorio, y se copia a la imagen como `.tmux.conf.local`. Ese es el único archivo que se toca.
- **Al abrir sesión se entra directamente en tmux.** Usa adjuntar-o-crear (`new-session -A -s seclab`), no una sesión nueva cada vez: la razón de usar tmux en un laboratorio es precisamente que una VPN que se cae o un SSH que se corta no se lleven por delante el trabajo en curso. Crear una sesión nueva en cada conexión anularía esa ventaja y dejaría sesiones huérfanas acumulándose. Debe poder desactivarse con una variable de entorno para quien prefiera entrar a un shell pelado.
- El arranque automático se aplica sólo a sesiones interactivas. Nunca dentro de `seclab shell` si ya se viene de un tmux del host, ni en ejecuciones no interactivas: eso rompe los scripts.

#### Banner de bienvenida

Al abrir sesión, un banner corto —cinco o seis líneas, no una pantalla entera— con: nombre y versión de SecLab, perfil e imagen en uso, arquitectura, número de herramientas del manifiesto, perfil de VPN activo si lo hay, ruta del workspace y el comando para pedir ayuda.

**Nunca imprime secretos**: ni contraseñas, ni tokens, ni la IP pública. Se regenera en cada arranque a partir del estado real, no es un texto fijo que pueda quedar desfasado.

#### Ayuda de herramientas instaladas

Un comando dentro del contenedor que responda a la pregunta más frecuente del alumnado: *¿qué tengo aquí y cómo se usa?*

- Sin argumentos, lista las herramientas del manifiesto **agrupadas por categoría** (red, recon, web, contraseñas, utilidades…) con su versión.
- Con el nombre de una herramienta, muestra para qué sirve, un ejemplo de uso y dónde está su documentación.
- Los ejemplos usan los targets de laboratorio incluidos, que son reproducibles para todo el grupo.
- Se genera a partir del manifiesto, no de una lista escrita a mano: si una herramienta no está instalada, no puede aparecer en la ayuda.
- Encabezado con el recordatorio de uso autorizado, una vez.

#### Glifos e iconos

La configuración de tmux del curso usa separadores Powerline (`U+E0B0`–`U+E0B3`) y emoji. **Que se vean o no lo decide la fuente del emulador de terminal del alumno, no el contenedor**: por SSH o por `seclab shell`, quien dibuja los caracteres es la terminal del host. No prometas en la documentación que se verán.

Lo que sí debe hacer SecLab:

- **Comprobarlo, no suponerlo.** `seclab doctor` imprime una línea de prueba con los glifos y pregunta si se ven correctamente.
- **Degradar bien.** Si no se ven, ofrecer el cambio a separadores ASCII (`tmux_conf_theme_use_nerd_fonts=false`) sin perder el resto del tema.
- **Documentar la solución real**: instalar una Nerd Font en el host y seleccionarla en el emulador de terminal, con las instrucciones concretas para macOS, Linux y Windows/WSL2.
- **En el perfil `desktop` sí se puede garantizar**, porque ahí el contenedor dibuja su propia terminal: incluye una Nerd Font en la imagen y configura la terminal del escritorio para usarla.

### Runtime local

Usa Docker Compose con:

- Un servicio principal del laboratorio.
- Volúmenes nombrados explícitamente y coherentes con los comandos de backup.
- `workspace` montado desde el host.
- `vpn/` montado desde el host en modo sólo lectura, excluido de Git, con un subdirectorio por perfil VPN.
- Persistencia de estado Tailscale cuando se use.
- Límites de CPU, RAM y disco documentados.
- Healthcheck real de procesos, puertos y endpoints HTTP.
- **Healthcheck condicional para servicios opcionales**: un servicio deshabilitado por perfil o por variable de entorno no debe reportarse como `unhealthy` ni mostrar su endpoint. Implementa el healthcheck de modo que sólo evalúe servicios realmente activos.
- Publicación de puertos sólo para servicios activos.
- Overrides separados para TUN/VPN, exposición controlada, objetivos vulnerables y servidor MCP.
- Capabilities y `/dev/net/tun` sólo cuando el perfil los requiera.
- Sin `container_name` fijo para permitir varias instancias. Usa un nombre de proyecto Compose configurable (`SECLAB_PROJECT`, por defecto derivado del directorio) y que **todos** los comandos del CLI lo pasen de forma consistente (`docker compose -p`), para que localizar contenedores nunca dependa de un nombre adivinado.

Mantén el diseño all-in-one si mejora la experiencia, pero separa la red y los privilegios cuando una función no los necesite.

### VPN autorizada (multiperfil)

El uso real del aula pasa por VPN. SecLab debe tratarla como función de primera clase, con **tres perfiles cerrados y declarativos**:

| Perfil  | Uso                                                          | Directorio       |
| ------- | ------------------------------------------------------------ | ---------------- |
| `vpnhtb` | Hack The Box (Starting Point, Machines, Pro Labs)            | `vpn/vpnhtb/`    |
| `vpntry` | TryHackMe (rooms y networks)                                 | `vpn/vpntry/`    |
| `vpncli` | VPN de cliente o engagement autorizado (uso docente/profesional) | `vpn/vpncli/` |

Requisitos:

- **Configuración aportada por el usuario, nunca en Git.** Cada perfil se activa colocando su `.ovpn` (y el fichero de credenciales si aplica) en `vpn/<perfil>/`. Todo `vpn/` está ignorado por Git. Las plantillas versionadas viven en `templates/vpn/<perfil>/` (`README.md` con el flujo de descarga del `.ovpn` en cada plataforma y `perfil.env.example`), y `seclab init` las copia a `vpn/<perfil>/` sin sobrescribir lo existente. **No uses negaciones de `.gitignore` dentro de un directorio ignorado: no funcionan.**
- **Permisos estrictos**: `700` en `vpn/` y sus subdirectorios, `600` en `.ovpn` y credenciales. `seclab doctor` avisa si son más laxos y ofrece el comando corrector.
- **Cada perfil declara su scope.** `vpn/<perfil>/perfil.env` define como mínimo `SECLAB_VPN_NOMBRE`, `SECLAB_VPN_CONFIG` (ruta al `.ovpn`), `SECLAB_VPN_RANGOS` (lista de CIDR autorizados) y `SECLAB_VPN_DNS` (opcional). Los rangos de ejemplo se documentan **como ejemplo verificable, no como verdad fija** —las plataformas los cambian—: el CLI debe mostrar los rangos realmente negociados por el túnel y avisar si no coinciden con los declarados.
- **Nunca aceptes la ruta por defecto del túnel.** Arranca OpenVPN con `--route-nopull` y añade explícitamente sólo las rutas de `SECLAB_VPN_RANGOS`. Esto impide que la VPN secuestre todo el tráfico del alumno, evita romper Docker, Tailscale y la red del campus, y hace posible que dos perfiles convivan. Aceptar `redirect-gateway` sólo mediante override consciente y documentado.
- **Un solo perfil activo por defecto.** `seclab vpn up <perfil>` rechaza levantar un segundo perfil si ya hay uno activo, salvo `--simultaneo`, permitido únicamente si los rangos de los perfiles implicados **no se solapan**; si se solapan, rechaza explicando el conflicto de rutas.
- **Aislamiento del túnel.** Cada VPN es un servicio dedicado (`vpn-htb`, `vpn-thm`, `vpn-cli`) en un override propio (`docker-compose.vpn.yml`), con `NET_ADMIN` y `/dev/net/tun` **sólo en ese servicio**; el contenedor de laboratorio se une al namespace de red del perfil activo y no recibe `NET_ADMIN` por este motivo.
- **Killswitch (fail-closed).** Si el túnel cae, el tráfico hacia los rangos del perfil se bloquea; no debe salir por la conexión doméstica del alumno. El estado degradado tiene que verse en `seclab status` y `seclab vpn status`.
- **Sin fugas de DNS.** El DNS empujado por el túnel se aplica sólo a los dominios/rangos del perfil cuando el sistema lo permita. Documenta el comportamiento **real** y sus límites por plataforma (macOS, Linux, WSL2) en lugar de prometer un aislamiento que no se cumple.
- **Verificación barata.** `seclab vpn status` muestra perfil activo, interfaz, IP asignada, rangos efectivos, tiempo conectado y una comprobación de vida contra la pasarela del propio túnel. Que el diagnóstico sea una comprobación puntual y no un barrido de la red de la plataforma: es más rápido, más fiable y no depende de que haya máquinas encendidas.
- **Sin secretos ni datos personales en salida.** Ni credenciales, ni contenido del `.ovpn`, ni la IP pública del alumno deben aparecer en logs, mensajes del CLI, informes o la página de bienvenida. La IP del túnel sí puede mostrarse.
- **Integración con labs.** `seclab lab create NAME --vpn vpnhtb` rellena `scope.txt` con el perfil, sus rangos y la fecha, como contexto para las notas y el informe del alumno. Es documentación, no un filtro: no bloquea ninguna operación.
- **Diferencias por sistema operativo.** Documenta el acceso a `/dev/net/tun` en macOS (Docker Desktop), Linux y Windows/WSL2, y qué hacer si el dispositivo no existe. `seclab doctor` detecta la ausencia de TUN y da la acción correctiva concreta para cada sistema.
- **Prueba sin plataformas reales.** La verificación automatizada usa un servidor OpenVPN local de prueba levantado por el propio repositorio; **no se prueba contra HTB ni TryHackMe**. Lo que no pueda verificarse va a `TESTING_GAPS.md`.

### Acceso remoto (opcional)

El acceso cloud debe utilizar Tailscale en el host o un sidecar oficialmente soportado. No dependas de una configuración implícita de userspace para exponer servicios.

Implementa y documenta una sola ruta soportada para la primera versión:

- Nodo Tailscale con TUN/kernel, o
- Tailscale Serve para servicios concretos, o
- Sidecar con namespace de red compartido.

El estado Tailscale debe persistir. Las auth keys deben ser efímeras, de mínimo privilegio y no quedar en logs o argumentos persistentes.

**Convivencia con las VPN de plataforma**: Tailscale y OpenVPN compiten por TUN y por la tabla de rutas. La política `--route-nopull` de la sección anterior es lo que permite que coexistan. Documenta el orden de arranque recomendado, cómo detectar un secuestro de la ruta por defecto y cómo recuperarse. `seclab doctor` debe detectar y reportar el conflicto.

**Importante**: No generes auth keys reales de Tailscale. Documenta el flujo de creación y usa la variable de entorno `TAILSCALE_AUTH_KEY` como único punto de entrada. El arranque debe fallar con mensaje claro si la variable no está definida y el perfil VPN está activo.

### Despliegue cloud (opcional, a cargo del alumno)

Terraform debe soportar DigitalOcean, GCP y Oracle Cloud con una interfaz operativa consistente. **Toda esta rama es opcional**: el curso se puede completar sin ella y no debe bloquear el núcleo local.

Requisitos:

- Imagen publicada por digest o tag inmutable.
- Registry OCI configurable, no una dependencia rígida de Docker Hub. El registry por defecto para pruebas locales es un registry local de Docker (`localhost:5000`) o `ttl.sh` (efímero, sin cuenta). Para producción, la variable `SECLAB_REGISTRY` define el registry destino.
- Bootstrap idempotente mediante systemd/cloud-init.
- Ruta de administración del host independiente del contenedor.
- Healthcheck y espera de disponibilidad.
- Logs claros de bootstrap y runtime.
- Etiquetas de propietario, curso, propósito y fecha de expiración.
- **El despliegue debe rechazar aplicar si no están definidos `owner` y `fecha-expiracion`/TTL.**
- **Confirmación de costo explícita**: antes de aplicar, mostrar la estimación de costo y exigir una confirmación consciente (por ejemplo, teclear `acepto` o el monto), con una advertencia prominente de que el gasto es responsabilidad personal del alumno.
- TTL o autodestrucción para laboratorios temporales.
- Estimación de costos antes de aplicar.
- `seclab cloud status` que liste recursos activos y su antigüedad, y recuerde `seclab cloud destroy`.
- Backend Terraform remoto, cifrado y con locking documentado.
- Secretos fuera del estado siempre que el proveedor lo permita.
- Snapshot o exportación de workspace antes de destruir.

No pases contraseñas permanentes directamente en user-data. Genera credenciales en el primer arranque o usa un secret manager y documenta el flujo para recuperarlas.

## Seguridad y autenticación

Implementa estas reglas:

- SSH por llave como mecanismo principal.
- Password login deshabilitado cuando exista una llave.
- Sin acceso SSH directo de root.
- Sudo administrativo sólo en perfiles locales de entrenamiento y documentado.
- Usuario de laboratorio no privilegiado para el uso diario.
- Secretos separados para SSH, VNC, code-server, Jupyter, Tailscale y servidor MCP.
- Prohibición explícita de `change-this-password`.
- No imprimir tokens en URLs, logs ni mensajes de ayuda.
- Jupyter sin `allow_origin="*"` salvo override explícito y temporal.
- Todo endpoint web ligado a localhost salvo un override consciente.
- Archivos de configuración con permisos mínimos.
- Auditoría de capacidades, mounts y dispositivos.
- `NET_ADMIN` y `/dev/net/tun` acotados al servicio VPN correspondiente, nunca concedidos al contenedor de laboratorio "por si acaso".
- Configuraciones y credenciales de VPN con permisos `600`, fuera de Git y fuera de cualquier salida del CLI.

Añade una revisión de seguridad automatizada de Compose y del Dockerfile.

## Servidor MCP para agentes de IA

SecLab debe poder exponer, **de forma opt-in y desactivada por defecto**, un servidor MCP (Model Context Protocol) local que un agente de IA pueda consumir para asistir al alumno durante las prácticas. El objetivo es que el agente pueda consultar el estado del lab, gestionar workspaces y ejecutar las herramientas declaradas en su lista blanca. La allowlist acota **qué operaciones** puede invocar el agente, no contra qué objetivo: el filtrado de destinos no es competencia de SecLab (ver *Alcance y modelo de responsabilidad*).

Requisitos de diseño:

- **Opt-in y aislado**: el servidor MCP se activa sólo mediante un perfil/override dedicado (`mcp`) y una variable de entorno explícita. Nunca arranca por defecto.
- **Ligado a localhost** por defecto, con autenticación obligatoria (token en variable de entorno, nunca hardcodeado ni impreso en logs). El arranque falla si el perfil MCP está activo y falta el token.
- **Lista blanca de capacidades (allowlist)**: define de forma explícita y cerrada qué herramientas/operaciones expone el servidor. El agente no puede ejecutar comandos arbitrarios; sólo las operaciones declaradas. Como mínimo considera capacidades de: consultar estado del lab y de servicios, listar y crear workspaces de labs, leer y escribir notas, y ejecutar las herramientas de recon declaradas. El límite es la lista de operaciones, no el destino.
- **Sin validación de objetivos**: el servidor MCP no comprueba ni restringe contra qué host se lanza una herramienta. Si el agente pide recon contra una IP, se ejecuta y se registra. El contexto del lab (perfil VPN, rangos declarados) se le ofrece al agente como información útil para trabajar, no como un filtro.
- **Sin acciones destructivas sin confirmación**: el agente no puede borrar workspaces, evidencias ni datos del usuario a través del MCP.
- **Auditoría**: toda invocación del agente vía MCP se registra (herramienta, parámetros, objetivo, resultado, marca de tiempo) en un log local del workspace, sin filtrar secretos. La auditoría es trazabilidad para el alumno y material para su informe, no un mecanismo de control.
- **Documentación**: incluye una guía de cómo conectar un cliente/agente de IA al servidor MCP local, la lista de capacidades expuestas, el modelo de permisos y las limitaciones. Deja claro qué operaciones puede invocar el agente y qué queda registrado.
- **Smoke test** del servidor MCP: arranque, autenticación, respuesta de una capacidad de sólo lectura (p. ej. estado del lab), rechazo de una operación **no declarada** en la allowlist y comprobación de que la invocación quedó registrada en el log de auditoría.

## CLI y experiencia de usuario

Proporciona un wrapper `bin/seclab` o una interfaz equivalente con estos comandos:

```text
seclab init
seclab start --profile desktop
seclab stop
seclab restart
seclab open
seclab status
seclab doctor
seclab shell
seclab lab create htb-forest --vpn vpnhtb
seclab lab reset htb-forest
seclab vpn list
seclab vpn up vpnhtb
seclab vpn status
seclab vpn routes
seclab vpn logs vpnhtb
seclab vpn down
seclab backup
seclab backup verify
seclab restore FILE=...
seclab image build --profile full
seclab image publish
seclab image verify
seclab mcp start
seclab mcp status
seclab mcp stop
seclab cloud plan --provider digitalocean
seclab cloud up --provider digitalocean
seclab cloud wait --provider digitalocean
seclab cloud status --provider digitalocean
seclab cloud connect --provider digitalocean
seclab cloud destroy --provider digitalocean
seclab update
```

Todos los mensajes del CLI, errores, advertencias y salidas de diagnóstico deben estar **en español**.

`seclab init` debe:

- Detectar macOS/Linux/**Windows (WSL2)**, Intel/ARM, Docker y Compose.
- Comprobar RAM, disco, puertos y disponibilidad de `/dev/net/tun` (con acción correctiva por sistema operativo si falta).
- Crear `vpn/<perfil>/` para `vpnhtb`, `vpntry` y `vpncli` a partir de `templates/vpn/`, con permisos correctos y sin sobrescribir configuraciones existentes.
- **Rechazar el arranque con un mensaje claro y amable si la máquina no alcanza los recursos mínimos del perfil elegido**, indicando el mínimo y sugiriendo un perfil más ligero.
- Generar secretos seguros.
- Recomendar el perfil adecuado.
- Crear `.env` a partir de una plantilla sin sobrescribirlo.
- Crear la estructura de workspace.
- Construir o descargar la imagen (priorizando `pull` de imagen publicada y firmada).
- Arrancar el servicio.
- Esperar healthcheck.
- Mostrar sólo los accesos realmente disponibles.

`seclab update` debe:

- Comprobar si hay una nueva versión del repositorio (git pull).
- **Abortar de forma limpia o hacer stash automático si el working tree está sucio**, para no destruir cambios locales del alumno o del profesor; informar con claridad qué se hizo.
- Reconstruir o descargar la imagen si cambia la versión.
- Reiniciar el servicio si es necesario.
- Mostrar el changelog de la versión nueva.

Los errores deben indicar causa, impacto y acción correctiva. No muestres URLs de servicios deshabilitados.

Añade una página local de bienvenida con estado de servicios, perfil, versión, recursos, documentación y enlaces rápidos.

## Workspace y laboratorios

`seclab lab create NAME` debe crear:

```text
workspace/NAME/
├── scope.txt          # incluye el perfil VPN vinculado y sus rangos autorizados
├── recon/
├── notes/
├── loot/
├── screenshots/
├── exploits/
└── report.md
```

Valida `NAME` como slug seguro (sólo `a-z`, `0-9` y `-`; longitud máxima 64 caracteres). Incluye plantillas para:

- Objetivo y autorización (ToS de la plataforma para `vpnhtb`/`vpntry`; autorización escrita para `vpncli`).
- Perfil VPN vinculado y rangos autorizados.
- Rango/IPs y dominios.
- Horario.
- Herramientas permitidas.
- Límites de tráfico, fuzzing y fuerza bruta.
- Evidencia.
- Remediación.
- Limpieza.

`seclab lab reset NAME` debe devolver un lab a su estado limpio reproducible (reiniciar targets vulnerables asociados a su estado inicial y opcionalmente archivar evidencias previas), con confirmación explícita y sin borrar datos sin alternativa de recuperación. Esto permite que cada alumno repita una práctica desde cero de forma idéntica.

El diseño debe permitir múltiples labs activos en paralelo. Cada lab es independiente en su directorio; el CLI puede recibir `--lab NAME` para operaciones específicas. Si un lab declara un perfil VPN, el CLI advierte cuando el perfil activo no coincide con el del lab.

## Paquetes de herramientas

No metas todo en la imagen base. Implementa paquetes opt-in:

- `web`: recon, HTTP, fuzzing, DNS, TLS y bug bounty.
- `ad`: SMB, Kerberos, LDAP, BloodHound y lateral movement para redes de laboratorio.
- `privesc`: linPEAS, winPEAS, pspy y utilidades de escalada.
- `pwn`: pwndbg/GEF, checksec, ropper, patchelf y QEMU user-mode.
- `forensics`: Volatility 3, YARA, Sleuth Kit, tshark y esteganografía.
- `cloud`: kubectl, Helm, Trivy, Syft/Grype y herramientas de auditoría cloud.
- `mobile`: apktool, JADX y adb.
- `desktop`: XFCE, navegador, noVNC y code-server.
- `msf`: Metasploit y sus dependencias, nunca por defecto.

Cada cheatsheet de paquete se encabeza con un recordatorio breve de **uso autorizado** —una vez, sin repetirlo en cada sección— y usa como ejemplos los targets de laboratorio incluidos (DVWA, Juice Shop, WebGoat y el target de Active Directory), por ser reproducibles para todos los alumnos. Las cheatsheets son material de referencia completo: no recortes el contenido técnico de los paquetes ofensivos (`ad`, `privesc`, `msf`).

Los objetivos vulnerables como DVWA, Juice Shop y WebGoat deben vivir en Compose separado, con red interna, límites de recursos y sin salida a Internet salvo override explícito. Pina todas las imágenes de targets vulnerables por digest (`image: dvwa@sha256:...`).

**GOAD no es un target de Compose.** Es un despliegue de varias máquinas virtuales Windows con Vagrant/Ansible y requisitos de RAM muy por encima del portátil típico de un alumno; no lo incluyas como servicio Docker. Para las prácticas de Active Directory usa un target dockerizado ligero (por ejemplo, un Samba AD DC con configuración deliberadamente débil) y documenta GOAD aparte, como laboratorio externo opcional con sus propios requisitos, fuera del alcance de SecLab.

## Reproducibilidad y supply chain

- Pinear la imagen base por el digest de su lista de manifiestos, de modo que
  todas las arquitecturas resuelvan dentro del mismo conjunto verificado.
- Pinear paquetes, versiones, tags o commits. Para las herramientas traídas de
  una publicación oficial, fijar la versión exacta y verificar checksum o firma.
- **El build debe fallar si una herramienta declarada no queda instalada.** Un
  manifiesto que no se corresponde con el contenido real de la imagen no sirve
  para nada, y el fallo tiene que verse en el momento, no meses después.
- Sustituir endpoints `latest`, `main` y `master` por referencias verificables.
- Verificar checksums o firmas de binarios descargados.
- Mantener lockfiles de Python, Go y Terraform.
- Generar manifest de herramientas (con marca de compatibilidad por arquitectura).
- Ejecutar escaneo de vulnerabilidades.
- Generar SBOM y provenance.
- Firmar las imágenes publicadas y verificar su firma al desplegar (`seclab image verify`).
- Publicar `amd64` y `arm64` cuando una herramienta lo soporte (ver nota multi-arch en sección de Imágenes).

## CI/CD

Configura CI para:

- ShellCheck.
- Hadolint.
- Validación de Compose (incluidos todos los overrides: VPN, targets, MCP).
- Escaneo de secretos del repositorio (gitleaks o equivalente), como job bloqueante.
- `terraform fmt -check`.
- `terraform validate`.
- Tests de seguridad de configuración.
- Build de todos los perfiles.
- Smoke tests de los endpoints activos.
- Smoke test del servidor MCP (autenticación, capacidad de sólo lectura, rechazo de operación no declarada y registro de auditoría).
- Test de VPN contra un servidor OpenVPN local de prueba: arranque del perfil, rutas exactamente las declaradas, ausencia de ruta por defecto secuestrada, killswitch al caer el túnel y rechazo de `--simultaneo` con rangos solapados.
- Verificación del manifiesto de herramientas.
- Escaneo de imágenes.
- Publicación sólo desde tags versionados.

Un smoke test pasa si el endpoint responde HTTP 200 (o el código esperado documentado) en ≤ 10 s y el healthcheck del contenedor reporta `healthy`. No publiques una imagen si falla una herramienta requerida, un smoke test o una validación de seguridad.

## .gitignore obligatorio

El `.gitignore` debe crearse en la **Fase 1** e incluir al menos:

```
.env
*.pem
*.key
*.p12
*.pfx
vpn/
*.ovpn
*.crt
*.csr
vpn-state/
workspace/
tailscale-state/
mcp-state/
terraform/.terraform/
terraform/*.tfstate
terraform/*.tfstate.backup
terraform/*.tfvars
__pycache__/
*.pyc
node_modules/
.DS_Store
```

Ningún secreto, workspace de usuario, estado de VPN ni estado/token del servidor MCP debe poder llegar a Git accidentalmente.

## Documentación requerida

Escribe documentación clara, coherente y preferentemente en español:

- Inicio rápido de cinco minutos.
- Tabla de perfiles, tamaño, RAM y tiempo aproximado de build.
- Política de herramientas: qué viene de apt, qué se trae de una publicación
  oficial fijada, y cómo actualizar una versión fijada cuando salga una nueva.
- Guía de la terminal: shell y plugins incluidos, atajos de tmux, cómo pedir
  ayuda sobre una herramienta, y cómo instalar una Nerd Font en el host para
  que se vean los iconos de la barra de estado.
- Requisitos mínimos por perfil y cómo verificarlos.
- Uso local.
- Diferencias entre macOS, Linux, **Windows/WSL2** y cloud.
- Guía de VPN multiperfil: cómo obtener y dónde colocar el `.ovpn` de Hack The Box (`vpnhtb`), TryHackMe (`vpntry`) y de un cliente o engagement (`vpncli`); rangos y scope de cada perfil; política de rutas y killswitch; convivencia con Tailscale; problemas de TUN por sistema operativo; y un enlace a los términos de servicio de cada plataforma para que el alumno los consulte.
- Tailscale y arquitectura de acceso (opcional).
- Despliegue por proveedor (opcional, con la advertencia de costo a cargo del alumno).
- Guía del servidor MCP: capacidades expuestas, modelo de permisos, cómo conectar un agente y limitaciones.
- Backup y restore.
- Troubleshooting.
- Uso autorizado y modelo de responsabilidad: una página que deje claro, sin repetirlo por todo el repositorio, que los laboratorios externos quedan fuera del alcance de SecLab, que se asume autorización plena y que el riesgo es del estudiante bajo la guía del profesor.
- Cheatsheets por paquete (encabezadas con el recordatorio de uso autorizado).
- Changelog y política de versiones.
- `TESTING_GAPS.md` — pruebas no ejecutadas, motivo y alternativa.

Incluye diagramas Mermaid para arquitectura local, cloud, redes de objetivos vulnerables, enrutamiento de los perfiles VPN (qué sale por el túnel y qué no) y flujo del servidor MCP con el agente.

## Orden de implementación

Implementa en este orden y deja cada fase comprobada antes de pasar a la siguiente. **El producto mínimo para el aula son las Fases 1–7 y 12** (local completo, labs, VPN multiperfil y targets vulnerables). La Fase 8 (CI) es muy recomendable. Las Fases 9–11 (Tailscale y cloud) y la Fase 13 (MCP) son **módulos opcionales** que no deben bloquear la entrega del núcleo local; márcalos claramente como opcionales en la documentación.

Son trece fases: no intentes completarlas todas en una sola sesión. Al terminar cada fase, deja el repositorio en estado consistente y comprobado, anota en `CHANGELOG.md` lo entregado y en `TESTING_GAPS.md` lo que quedó sin verificar, de forma que el trabajo pueda retomarse desde ahí sin contexto previo.

### Fase 1 — Estructura base y seguridad
Archivos mínimos esperados al terminar esta fase:
`.gitignore`, `.env.example` (incluida `SECLAB_PROJECT` y las variables de VPN), `docker-compose.yml`, `docker-compose.override.yml` (vacío/comentado), `Makefile`, `bin/seclab`, `README.md`, `CHANGELOG.md`, `TESTING_GAPS.md`, `docs/`, `SECURITY.md`, `LICENSE`, `templates/`.

### Fase 2 — Imagen `lite` y runtime local mínimo
Dockerfile multi-stage con target `lite` sobre Ubuntu LTS anclada por digest. Runtime Docker Compose funcional. `seclab init` (con detección de Windows/WSL2 y chequeo de recursos mínimos), `seclab start`, `seclab stop`, `seclab status`, `seclab doctor`, `seclab shell`.

### Fase 3 — Healthchecks, diagnóstico, backup y restore
Healthcheck real y condicional para servicios opcionales. `seclab backup`, `seclab backup verify`, `seclab restore`. Prueba de restore en workspace temporal. Verificación de que backup no crea copia vacía silenciosa.

`seclab doctor` gana además tres comprobaciones que nacen de fallos reales observados en el aula, todas con la orden correctiva exacta en el mensaje:

- **Llave de host obsoleta en `known_hosts`.** Al recrear el laboratorio o borrar su volumen, el cliente SSH del alumno muestra un aviso de suplantación en mayúsculas que asusta y que no explica nada. Detecta la entrada obsoleta para el puerto configurado, compárala con la huella real del contenedor y da el `ssh-keygen -R` exacto. Es importante que esto lo resuelva la herramienta: un alumno que aprenda a ignorar los avisos de cambio de llave de SSH ha aprendido justo lo contrario de lo que se pretende.
- **Volumen de `home` construido sobre otra imagen base.** Los volúmenes nombrados sobreviven a la reconstrucción de la imagen, así que un cambio de base deja restos de la anterior en el directorio personal. Detecta la discrepancia y ofrece recrearlo, avisando de que se regenerarán las llaves de host.
- **Glifos de la barra de estado.** Imprime una línea de prueba con los separadores Powerline y pregunta si se ven; si no, ofrece la variante ASCII.

### Fase 4 — Experiencia de terminal
zsh como shell por defecto con Oh My Zsh y sus plugins, todo fijado por commit y con checksum verificado. Oh my tmux! fijado igual, con `templates/shell/tmux.conf.local` copiado a la imagen. Entrada automática en tmux con adjuntar-o-crear, desactivable por variable de entorno y sin afectar a ejecuciones no interactivas. Banner de bienvenida generado a partir del estado real, sin secretos. Comando de ayuda de herramientas construido desde el manifiesto, por categorías y con ejemplos sobre los targets de laboratorio. Comprobación de glifos con degradación a ASCII. Nerd Font dentro de la imagen para el perfil `desktop`.

Verificación: abrir sesión por SSH y por `seclab shell` y comprobar que en ambos casos se entra en tmux, que reconectar recupera la sesión anterior en lugar de crear otra, que el banner no filtra ningún secreto y que la ayuda de herramientas coincide con el manifiesto.

### Fase 5 — Perfiles `desktop`, `full` y `full-msf`
Targets adicionales en Bake/Dockerfile. Smoke tests por perfil. Página de bienvenida local.

### Fase 6 — CLI guiada, workspace de labs, reset y `seclab update`
`seclab lab create`, plantillas, validación de slug. `seclab lab reset`. `seclab update` con manejo seguro del working tree. Labs paralelos.

### Fase 7 — VPN autorizada multiperfil (`vpnhtb`, `vpntry`, `vpncli`)
Override `docker-compose.vpn.yml` con un servicio dedicado por perfil (`vpn-htb`, `vpn-thm`, `vpn-cli`), con `NET_ADMIN` y `/dev/net/tun` acotados a ese servicio. Plantillas en `templates/vpn/<perfil>/` y creación de `vpn/<perfil>/` desde `seclab init` con permisos correctos. `seclab vpn list|up|status|routes|logs|down`. Política `--route-nopull` con rutas explícitas desde `SECLAB_VPN_RANGOS`, killswitch fail-closed, exclusividad de perfil y validación de solapamiento para `--simultaneo`. Integración con `seclab lab create --vpn` y con el scope del lab. Chequeo de TUN y de conflicto de rutas en `seclab doctor`. Verificación contra un servidor OpenVPN local de prueba, nunca contra HTB o TryHackMe reales; lo no verificable va a `TESTING_GAPS.md`.

### Fase 8 — CI, builds multi-arch, SBOM, provenance y firma
Pipeline completo. ShellCheck, Hadolint, Trivy, Cosign. `seclab image verify`. Publicación desde tags.

### Fase 9 — Tailscale con acceso remoto comprobado (opcional)
Sidecar o TUN/kernel. Persistencia de estado. Variable `TAILSCALE_AUTH_KEY`. Smoke test de conectividad. Verificación de que Tailscale y un perfil VPN activo conviven sin secuestrarse las rutas.

**Decisión ya tomada (ver `docs/vpn.md`, sección "Convivencia con Tailscale"):
Tailscale va en el host/VM, no como sidecar compartiendo el ciclo de vida de
`lab`.** Con el diseño actual de la Fase 7, `lab` ya no cambia de
`network_mode` al activar o desactivar un perfil de VPN de plataforma (la VPN
vive dentro del propio contenedor, gestionada por `seclab-vpn`); la razón para
mantener Tailscale fuera de `lab` es otra: separar ciclos de vida. El acceso
remoto y las VPN de plataforma (HTB, THM, un cliente) tienen motivos muy
distintos para subir o bajar, y un sidecar de Tailscale atado a `lab` seguiría
el ciclo de vida del propio contenedor (se reiniciaría con él, por ejemplo en
un `seclab update`), justo cuando el acceso remoto más importa —por ejemplo,
siendo la única vía de entrada a una VM en la nube. No reabrir esta decisión
sin releer esa sección primero.

### Fase 10 — DigitalOcean (proveedor de referencia, opcional)
Terraform módulo DO. Bootstrap cloud-init. `seclab cloud` comandos. Estimación de costos, confirmación de gasto, `owner`/TTL obligatorios y `seclab cloud status`. TTL/autodestrucción.

### Fase 11 — GCP y Oracle Cloud (opcional)
Reutilizar bootstrap validado de la fase de DigitalOcean. Módulos Terraform separados.

### Fase 12 — Paquetes adicionales y targets vulnerables aislados
Paquetes opt-in. DVWA, Juice Shop, WebGoat y el target AD dockerizado en Compose separado, con imágenes pineadas por digest. GOAD queda documentado como laboratorio externo opcional, no como servicio.

### Fase 13 — Servidor MCP para agentes de IA (opcional)
Perfil/override `mcp` opt-in y desactivado por defecto. Servidor MCP ligado a localhost con autenticación obligatoria por token. Allowlist cerrada de operaciones (no de objetivos). Registro de auditoría en el workspace. `seclab mcp start|status|stop`. Documentación de conexión de un agente y modelo de permisos. Smoke test: arranque, autenticación, capacidad de sólo lectura, rechazo de operación no declarada y comprobación del log de auditoría. Diagrama Mermaid del flujo agente↔MCP↔lab.

Si encuentras un bloqueo, implementa primero una alternativa segura y documenta la decisión. No dejes funcionalidades simuladas que aparenten estar operativas.

## Verificación final obligatoria

Antes de terminar:

- Ejecuta todos los validadores disponibles.
- Construye al menos `lite` y `desktop` si el entorno lo permite. Si `full`/`full-msf` exceden los recursos del entorno, decláralos como no verificados en `TESTING_GAPS.md`; **no simules éxito**.
- Arranca el perfil mínimo y realiza smoke tests.
- Comprueba que los servicios deshabilitados no aparezcan como unhealthy.
- Comprueba que el backup no pueda crear una copia vacía silenciosa.
- Comprueba restore en un workspace temporal.
- Verifica los tres perfiles VPN contra el servidor OpenVPN de prueba: rutas exactamente las declaradas, sin ruta por defecto secuestrada, killswitch efectivo y rechazo de perfiles simultáneos con rangos solapados.
- Comprueba que ningún `.ovpn` ni credencial de VPN está versionado y que sus permisos son `600`.
- Si implementaste la Fase 13, verifica que el servidor MCP rechaza una operación no declarada en la allowlist y que registra correctamente las invocaciones en el log de auditoría.
- Verifica que no se impriman secretos (incluido el token del MCP).
- Revisa el diff completo y no sobrescribas cambios no relacionados.
- Ejecuta un escaneo de secretos sobre el repositorio.
- Documenta qué pruebas no pudieron ejecutarse en `TESTING_GAPS.md`.

## Entregable final

Entrega:

1. Código y configuración funcional.
2. CLI `bin/seclab` con todos los comandos implementados.
3. Dockerfiles/Bake/Compose.
4. Override y scripts de VPN multiperfil, plantillas `templates/vpn/` y su documentación.
5. Terraform y bootstrap cloud (opcional).
6. Servidor MCP y su documentación (opcional).
7. CI/CD.
8. Documentación operativa y de uso autorizado.
9. Tests y smoke tests.
10. Manifiesto de herramientas (con compatibilidad por arquitectura).
11. `CHANGELOG.md` siguiendo Keep a Changelog.
12. `TESTING_GAPS.md` con pruebas no ejecutadas.
13. Un informe final (`docs/informe-final.md`) con arquitectura, decisiones, riesgos restantes, comandos probados y próximos pasos.

Declara el proyecto terminado sólo cuando los criterios anteriores estén satisfechos y los resultados sean reproducibles.
