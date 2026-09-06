# Resolución de problemas

> Esta página crece con cada fase.

## Antes que nada

```bash
./bin/seclab doctor       # entorno: Docker, memoria, disco, puertos, TUN
./bin/seclab seguridad    # secretos, permisos y exposición
```

Entre los dos cubren casi todo, y cada fallo trae el comando que lo corrige.

## `seclab: command not found`

Ejecútalo desde la raíz del repositorio con `./bin/seclab`, o añade `bin/` a tu
`PATH`:

```bash
export PATH="$PWD/bin:$PATH"
```

## Un comando dice que no está implementado

Es lo esperado. SecLab se construye por fases y prefiere decírtelo a fingir que
funciona. El mensaje indica en qué fase llega. Sale con código 3 para que se
distinga de un fallo real de tu entorno.

## Pedí el perfil `full` y me dice que no está construido

Hoy sólo existe `lite`. Los demás llegan en la Fase 5. Si lo pediste
explícitamente con `--profile`, SecLab se niega en lugar de cambiártelo por
debajo: acabar trabajando en un perfil distinto del que pediste sin enterarte
sería peor.

## `seclab seguridad` avisa de que no hay repositorio Git

`.gitignore` sólo protege dentro de un repositorio. Si vas a versionar esto:

```bash
git init
```

## `seclab seguridad` se queja de los permisos de `vpn/`

```bash
chmod 700 vpn vpn/*
chmod 600 vpn/*/*
```

Un `.ovpn` contiene tu certificado personal. Merece los mismos permisos que una
clave SSH.

## Docker Compose no valida

```bash
docker compose config
```

muestra el error concreto. La causa más frecuente es un `.env` con una línea
mal formada: cada línea debe ser `CLAVE=valor`, sin espacios alrededor del `=`.

## `seclab init` se niega a arrancar por falta de memoria

Es lo que tiene que pasar: más vale eso que un contenedor que muere a media
práctica. El mensaje te dice cuánta memoria hace falta y qué perfil sí cabe.

Ojo a un detalle que confunde: **la cifra que cuenta no es la RAM de tu
portátil**. En macOS y Windows el contenedor vive dentro de una VM de Docker con
su propio límite de memoria, casi siempre bastante menor. Un equipo con 16 GB
puede tener sólo 7 GB asignados a Docker. Si necesitas más, súbelo en las
preferencias de Docker Desktop (Resources → Memory) y vuelve a ejecutar
`seclab doctor`.

## El contenedor arranca y se muere enseguida

Casi siempre es configuración que falta. `seclab start` te muestra los últimos
20 renglones del log, y el entrypoint aborta con un mensaje explícito:

- *No hay llave pública SSH configurada* → ejecuta `seclab init`.
- *usa un valor de relleno prohibido* → `seclab init --regenerar-secretos`.
- *tiene menos de 16 caracteres* → lo mismo.

No hay contraseñas de emergencia ni degradación silenciosa: si la configuración
no es segura, el contenedor no arranca.

## `nmap` dice «Couldn't open a raw socket»

No debería pasar: la imagen le conserva `cap_net_raw` a nmap precisamente para
esto. Si ocurre, comprueba que el contenedor tiene la capacidad:

```bash
docker inspect --format '{{.HostConfig.CapAdd}}' "$(docker compose ps -q lab)"
```

Debe incluir `NET_RAW`. Si lo has quitado en `docker-compose.override.yml`,
ahí está la causa. `sudo nmap` sigue funcionando en cualquier caso.

## SSH: «Permission denied (publickey)»

El acceso es sólo por llave, así que esto significa que la llave no coincide.
Comprueba cuál está usando SecLab:

```bash
./bin/seclab status
```

Te da el comando `ssh` completo, con la ruta correcta entrecomillada. Si has
regenerado la llave, reinicia el laboratorio para que el contenedor recoja la
nueva:

```bash
./bin/seclab restart
```

## Mi cliente SSH avisa de que cambió la llave del host

Es el aviso en mayúsculas de «REMOTE HOST IDENTIFICATION HAS CHANGED». No
debería salir: las llaves de host viven en un volumen y sobreviven a `stop`,
`start` y `restart`. Si has borrado el volumen (con `seclab limpiar`, o al
recrearlo desde `seclab doctor`), la llave es nueva de verdad y el aviso es
correcto.

Compruébalo antes de hacer nada:

```bash
./bin/seclab doctor
```

Compara la huella guardada con la real y, si la entrada está obsoleta, te da la
orden exacta para borrarla. Es la de siempre, con tu puerto:

```bash
ssh-keygen -R "[127.0.0.1]:2222"
```

Lo que **no** hay que hacer es añadir la llave nueva a mano sin mirar, ni
desactivar `StrictHostKeyChecking`. Ese aviso es una de las pocas defensas
reales que tiene SSH, y acostumbrarse a saltárselo en el laboratorio es
aprender justo lo contrario de lo que se pretende.

## La barra de estado de tmux sale con cuadros o interrogaciones

Los separadores de la barra son glifos Powerline y necesitan una Nerd Font
**en el terminal de tu máquina**, no dentro del contenedor. Sin ella verás
cuadros, interrogaciones o espacios raros.

```bash
./bin/seclab doctor
```

Imprime una línea de prueba y te pregunta si la ves bien. Si respondes que no,
te ofrece la variante ASCII de la barra, que se ve correctamente con cualquier
fuente. Se guarda en `.env` y se aplica al reiniciar:

```
SECLAB_GLIFOS=ascii
```

```bash
./bin/seclab restart
```

La otra opción es instalar una Nerd Font (por ejemplo *MesloLGS NF* o
*JetBrainsMono Nerd Font*) y seleccionarla en las preferencias de tu terminal.

Si habías editado tu `~/.tmux.conf.local`, SecLab no lo sobrescribe: al
arrancar te dice qué cuatro líneas cambiar.

## `seclab doctor` dice que el directorio personal se creó sobre otra imagen base

Los volúmenes de Docker sobreviven a la reconstrucción de la imagen. Si la
imagen base cambia, tu directorio personal conserva restos de la anterior:
archivos de configuración de una distribución que ya no es la que usas.

Recrearlo **no toca tu workspace**, que vive en el host. Lo que sí pasa es que
se regeneran las llaves de host SSH, así que después habrá que retirar la
entrada vieja de `known_hosts` (`doctor` te da la orden). Puedes aceptar la
oferta que hace `doctor` o hacerlo a mano:

```bash
./bin/seclab limpiar
```

Antes de recrear nada, si tienes dudas: `./bin/seclab backup`.

## El build falla al descargar Oh My Zsh o Oh my tmux!

Síntoma: `curl: (28) Connection timed out` en medio de `seclab image build`. Las
descargas van a `codeload.github.com` con reintentos, así que un tropiezo no
suele tumbar el build; si el error persiste, es la red o el proxy de tu máquina.
Comprueba primero si el problema es sólo del build:

```bash
docker run --rm alpine:3 sh -c 'apk add --no-cache curl >/dev/null && curl -sI https://codeload.github.com | head -1'
```

Si eso funciona y el build no, mira si Docker Desktop tiene un proxy
configurado (Settings → Resources → Proxies): las descargas del build pasan por
él y las de `docker run` no.

## El escritorio sale en negro, o noVNC no conecta

Primero, mira qué dice el propio laboratorio:

```bash
./bin/seclab status
./bin/seclab shell
servicios
```

`servicios` lista los procesos que mantiene supervisor. El escritorio son dos:
`escritorio-x` (el servidor X con VNC) y `escritorio-sesion` (XFCE). Si la
sesión está en `FATAL` y el servidor X en `RUNNING`, verás una pantalla gris o
negra al conectar: el escritorio no arrancó, pero el VNC sí. Reinicia sólo esa
parte, sin tocar el servidor X ni tirar la conexión del navegador:

```bash
servicios restart escritorio-sesion
```

Los registros no se leen con `servicios tail`: los servicios escriben en la
salida del contenedor —así `docker logs` los ve y no crecen dentro de un
volumen—, no en archivos. Se miran desde el host:

```bash
./bin/seclab logs escritorio
```

Si noVNC dice «Credentials are required» y la contraseña no la acepta,
recuerda que **VNC sólo usa los ocho primeros caracteres** de la contraseña
(limitación del protocolo, no de SecLab). Está en `.env`:

```bash
grep SECLAB_VNC_PASSWORD .env
```

## En el escritorio, la barra de tmux sale con cuadros

Dentro del escritorio no debería: la imagen trae la Nerd Font y la terminal está
configurada para usarla. Si tu laboratorio viene de una versión anterior, su
configuración ya estaba escrita y no se sobrescribe sola:

```bash
./bin/seclab escritorio restablecer
```

Eso pone la fuente del curso, la barra con los lanzadores y los accesos
directos. Si prefieres hacerlo a mano: Terminal → Preferencias → Apariencia →
Fuente, y elige **JetBrainsMono Nerd Font Mono**.

En una sesión **SSH** es distinto: ahí la fuente la pone el terminal de tu
máquina, y la solución es instalar una Nerd Font o usar `SECLAB_GLIFOS=ascii`.

## Falta el lanzador de Firefox o de la terminal en la barra

Misma causa y misma solución: XFCE reescribe su configuración en cuanto
arranca, así que un laboratorio que ya se usó no recibe la plantilla nueva.

```bash
./bin/seclab escritorio restablecer
```

## code-server pide contraseña y no la acepta

Es la de `SECLAB_CODE_PASSWORD` en `.env`, no la de VNC: son secretos
distintos a propósito.

```bash
grep SECLAB_CODE_PASSWORD .env
```

Si acabas de regenerar los secretos con `seclab init --regenerar-secretos`,
reinicia para que el contenedor recoja los nuevos: `./bin/seclab restart`.

## El terminal web (ttyd) pide usuario y contraseña, y no los acepta

El usuario es `SECLAB_USUARIO` (`seclab` salvo que lo cambiaras) y la
contraseña es `SECLAB_TERMINAL_PASSWORD`, un secreto distinto al de VNC y al
de code-server:

```bash
grep -E "SECLAB_(USUARIO|TERMINAL_PASSWORD)" .env
```

Si acabas de regenerar los secretos con `seclab init --regenerar-secretos`,
reinicia para que el contenedor recoja el nuevo: `./bin/seclab restart`.

## No hay escritorio, o el laboratorio no arranca por un servicio gráfico

Los tres perfiles (`lite`, `full`, `full-msf`) traen el escritorio, code-server
y el terminal por navegador desde `lite`: ya no existe un perfil sin ellos. Si
no ves el escritorio, o el contenedor aborta al arrancar quejándose de alguno
de estos servicios, hay dos causas posibles.

**Una variable `SECLAB_HABILITAR_*` con un valor explícito manda sobre el
perfil.** Si tu `.env` viene de una instalación anterior, puede tener `false`
escrito a mano:

```bash
grep SECLAB_HABILITAR .env
```

Déjalas **vacías** para que decida el perfil, y reinicia:

```
SECLAB_HABILITAR_DESKTOP=
SECLAB_HABILITAR_CODE=
SECLAB_HABILITAR_TERMINAL=
SECLAB_HABILITAR_WEB=
```

**`SECLAB_PERFIL` no es uno de los tres válidos.** El entrypoint comprueba
cada servicio activado contra los binarios que trae la imagen, y si no
coinciden, el laboratorio no arranca con un mensaje como este:

```
el escritorio está activado pero el perfil 'X' no lo trae (falta Xvnc).
Revisa SECLAB_PERFIL (debe ser 'lite', 'full' o 'full-msf'), o pon
SECLAB_HABILITAR_DESKTOP=false en .env.
```

Esto ya no debería pasar por elegir un perfil "equivocado" —los tres traen el
escritorio—, pero sí si `SECLAB_PERFIL` tiene un valor que no es ninguno de
los tres (un resto de una instalación muy anterior, o un typo). Corrige la
variable y reinicia.

## El puerto 2222 ya está ocupado

Suele ser otra instancia de SecLab, o un túnel que dejaste abierto. Cambia el
puerto en `.env`:

```
SECLAB_PUERTO_SSH=2223
```

y reinicia. Si lo que quieres es tener dos instancias a la vez, cambia también
`SECLAB_PROJECT`: es lo que impide que se pisen los contenedores y volúmenes.

## Docker no está corriendo

En macOS y Windows, Docker Desktop tiene que estar abierto. Compruébalo con:

```bash
docker info
```

Si falla, el problema está en Docker, no en SecLab.
