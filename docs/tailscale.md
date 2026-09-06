# Tailscale — acceso remoto privado (Fase 9, opcional)

Todo lo de esta página es **opcional**: el curso se completa entero sin
Tailscale. Sirve para un caso concreto, que aparece sobre todo cuando se
combina con el despliegue cloud (Fases 10-11): acceder de forma privada a tu
instancia de SecLab sin publicar ningún puerto a Internet, ni siquiera el SSH.

Antes de seguir: lee [uso-autorizado.md](uso-autorizado.md). Nada de lo que
sigue cambia el modelo de responsabilidad del proyecto.

## Qué NO hace SecLab

**SecLab nunca genera una auth key de Tailscale, ni crea una cuenta por ti.**
`prompt_v3.md` lo prohíbe explícitamente para esta fase. Toda auth key es cosa
tuya: la creas en tu propia cuenta de Tailscale, la pegas en `.env`, y SecLab
la usa exactamente una vez, para unir un nodo. SecLab tampoco intenta nunca
conectarse a la red real de Tailscale durante sus propias pruebas
automatizadas (ver "Qué verifica el smoke test", más abajo): sin auth key
real, no hay nada contra lo que conectar, y así se queda a propósito.

## Arquitectura elegida

`prompt_v3.md` deja abiertas tres formas de integrar Tailscale (nodo en el
host, `tailscale serve` para servicios concretos, o un sidecar con namespace
de red compartido) pero ya fija una decisión de diseño que esta fase no
reabre: **Tailscale va en el host o VM, nunca como sidecar que comparta el
ciclo de vida de `lab`** (ver también [vpn.md](vpn.md), sección "Convivencia
con Tailscale").

De las rutas compatibles con esa decisión, SecLab implementa: **un
contenedor `tailscale` dedicado, en su PROPIO proyecto de Docker Compose**
(`docker-compose.tailscale.yml`, proyecto `${SECLAB_PROJECT}-tailscale`,
nunca el proyecto `${SECLAB_PROJECT}` de `lab`). No es un sidecar de `lab`
mismo, ni ata su `network_mode`: es un servicio completamente independiente.

### Por qué esta ruta y no las otras dos

- **Nodo Tailscale en el portátil del alumno, fuera de Docker por completo.**
  Es la más simple y no necesita contenedor ni `NET_ADMIN`, pero no resuelve
  el caso de uso real: acceder a una VM en la nube (Fase 10/11) donde corre
  SecLab. Ahí el "host" que necesita Tailscale es la VM, no el portátil.
  Sigue siendo una opción legítima y más simple para quien sólo usa SecLab en
  local y quiere Tailscale para otra cosa — pero entonces no hace falta nada
  de este documento: se instala Tailscale normal en el sistema operativo del
  alumno, sin tocar SecLab en absoluto.
- **Sidecar con `network_mode: service:lab`.** Es la ruta que `prompt_v3.md`
  descarta explícitamente. Un sidecar así ata el ciclo de vida de Tailscale al
  de `lab`: cada `seclab restart` o `seclab update` recrearía también el nodo
  Tailscale, justo cuando el acceso remoto más importa (siendo la única vía
  de entrada a una VM en la nube, perder la sesión de Tailscale a mitad de un
  `seclab update` dejaría la VM inalcanzable hasta volver a entrar por otra
  vía).
- **Contenedor propio, proyecto de Compose propio (elegido).** Ni comparte
  namespace de red con `lab` ni su ciclo de vida. `seclab stop`, `restart`,
  `update` y `limpiar` hablan sólo con el proyecto de `lab`
  (`docker-compose.yml` + sus overrides) y **nunca** tocan
  `docker-compose.tailscale.yml`; sólo `seclab tailscale down` lo hace. El
  nodo Tailscale puede seguir arriba con `lab` parado, reiniciándose o
  recreándose sin perder su sesión ni su identidad.

### Cómo alcanza `tailscale` los servicios de `lab` sin compartir red

Sin namespace de red compartido, `tailscale` llega a `lab` por
`host.docker.internal`, que apunta a la máquina donde corre el propio
demonio Docker (el host real en Linux; la VM ligera de Docker Desktop en
macOS/Windows, que también expone ahí los puertos que `lab` publica). Es
decir: `tailscale` alcanza a `lab` exactamente por donde tu propio equipo lo
alcanzaría — los puertos que `lab` ya publica en `127.0.0.1`
(`SECLAB_PUERTO_SSH`, etc.), ni uno más.

En Docker Desktop (macOS/Windows) `host.docker.internal` funciona sin nada
que declarar. En Linux, `docker-compose.tailscale.yml` lo añade con
`extra_hosts: host-gateway` (disponible desde Docker 20.10).

## Requisitos

- **Opt-in y desactivado por defecto**: `SECLAB_HABILITAR_TAILSCALE=false` en
  `.env.example`. El contenedor `tailscale` ni siquiera se crea con ese valor.
- **`TAILSCALE_AUTH_KEY` como único punto de entrada.** Con
  `SECLAB_HABILITAR_TAILSCALE=true` y la variable vacía, `seclab tailscale
  up` se niega a arrancar el contenedor — nunca lo deja a medias para que
  falle después de forma confusa. La misma comprobación se repite dentro del
  propio contenedor (`command:` de `docker-compose.tailscale.yml`), por si
  alguien invoca `docker compose` directamente sin pasar por el CLI.
- **Persistencia de estado**: la identidad del nodo y sus claves viven en un
  volumen de Docker nombrado y dedicado (`${SECLAB_PROJECT}-tailscale-state`,
  montado en `/var/lib/tailscale`), no en un bind-mount del repositorio.
  Sobrevive a `seclab tailscale down` (que sólo borra el contenedor, nunca el
  volumen) y a cualquier recreación del contenedor: la sesión no se pide dos
  veces por reiniciarlo.
- **Nunca se imprime la auth key.** Ni en los mensajes del CLI, ni en los
  logs del contenedor (`TS_AUTHKEY` no aparece en la salida de
  `tailscaled`/`containerboot` salvo que algo vaya realmente mal en la propia
  imagen oficial de Tailscale — no es algo que controle este proyecto, pero
  `scripts/ci/probar-tailscale.sh` lo comprueba en cada ejecución), ni en la
  página de bienvenida (que no menciona Tailscale en absoluto).

## Flujo de creación de una auth key real (lo haces tú, nunca SecLab)

1. Entra en <https://login.tailscale.com/admin/settings/keys> con tu propia
   cuenta de Tailscale (o crea una gratuita si no tienes: no la crea SecLab
   por ti, ni falta que hace: es tu propia identidad en la tailnet).
2. "Generate auth key". Recomendado para un nodo de laboratorio:
   - **Reusable**: no, salvo que sepas que vas a recrear el contenedor muchas
     veces sin conservar el volumen de estado (con el volumen persistente de
     SecLab casi nunca hace falta).
   - **Ephemeral**: sí, si el nodo es temporal (por ejemplo, una VM de Fase
     10/11 con TTL). No, si quieres que el nodo conserve su lugar en la
     tailnet aunque lo apagues varios días.
   - **Expiry**: el más corto que te sirva. Una key con expiración larga que
     se filtrara sería un acceso persistente y silencioso a tu tailnet.
   - **Tags**: si tu tailnet usa ACLs por tag (recomendado en cuanto haya más
     de un nodo), asígnale uno aquí en vez de dejarlo para luego.
3. Copia la key (empieza por `tskey-auth-`). Se muestra una única vez.
4. Pégala en `.env`, en `TAILSCALE_AUTH_KEY`. `.env` está en `.gitignore` y
   tiene permisos `600`: no la pegues en ningún otro sitio (chat, ticket,
   commit).
5. `seclab tailscale up`.

## Comandos del CLI

```text
seclab tailscale up       Arranca el contenedor (falla sin TAILSCALE_AUTH_KEY)
seclab tailscale status   Estado del contenedor y de la sesión Tailscale
seclab tailscale down     Detiene el contenedor (conserva su identidad y claves)
```

Mismo estilo que `seclab vpn`: las comprobaciones que no necesitan hablar con
Docker (auth key vacía, flag de habilitación) se hacen primero, con el
mensaje exacto de qué falta; el resto se delega en Compose.

`seclab tailscale up` la primera vez pide confirmación para activar
`SECLAB_HABILITAR_TAILSCALE=true` en `.env` — a diferencia de `seclab vpn
up`, esto **no recrea `lab`**: Tailscale vive en un contenedor y un proyecto
de Compose completamente aparte, así que activarlo nunca te hace perder una
shell abierta dentro de `lab`.

## Publicar los servicios de `lab` hacia tu tailnet (automático)

En cuanto el nodo autentica, el propio contenedor `tailscale` corre
`tailscale serve --bg --tcp <puerto>` por cada puerto de `lab` que
corresponda a tu `.env` (`SECLAB_PUERTO_SSH`, `SECLAB_PUERTO_WEB`,
`SECLAB_PUERTO_NOVNC`, `SECLAB_PUERTO_CODE`, `SECLAB_PUERTO_JUPYTER`) —
apuntando siempre a `host.docker.internal:<PUERTO>`, nunca hacia Internet
(`tailscale serve` sólo es alcanzable por los dispositivos de tu propia
tailnet). No hace falta ningún paso manual ni redirigir puertos por SSH
(`-L`): desde cualquier dispositivo de tu tailnet, con el nodo arriba, entras
directo a `http://<hostname>:<puerto>` (por ejemplo,
`http://seclab:8080` para code-server) exactamente igual que si fuera local.

`seclab tailscale status` muestra qué nodo y qué IP tiene el contenedor; para
ver qué puertos quedaron publicados de verdad:

```bash
docker exec $(docker compose -f docker-compose.tailscale.yml ps -q tailscale) tailscale serve status
```

Si cambiaste alguno de esos puertos en `.env` después de que el nodo ya
estuviera arriba, un `seclab tailscale down` + `up` vuelve a aplicar la
publicación con los puertos nuevos (el `command` del contenedor los relee de
su propio entorno en cada arranque).

## Convivencia con VPN de plataforma

Ver [vpn.md](vpn.md#convivencia-con-tailscale) para el razonamiento completo.
En corto: con esta arquitectura, `tailscale` y las VPN de plataforma que
`lab` pueda tener activas (`vpnhtb`, `vpntry`, `vpncli`, Fase 7) viven en
**namespaces de red distintos** — cada contenedor tiene su propia tabla de
rutas, así que no hay una tabla compartida que uno pueda secuestrarle al
otro. Además:

- `lab` sigue arrancando cualquier VPN de plataforma con `--route-nopull` y
  sólo las rutas de `SECLAB_VPN_RANGOS` (Fase 7): nunca toma la ruta por
  defecto.
- `tailscale` arranca con `TS_EXTRA_ARGS=--accept-routes=false
  --accept-dns=false`: no acepta rutas ni DNS anunciados por otros nodos de
  tu tailnet, así que tampoco puede tomar la ruta por defecto del contenedor
  por una decisión tomada en otra parte de la tailnet.

`seclab doctor` verifica que esto es cierto, no que "podría serlo": comprueba
que el contenedor `tailscale` no declara `network_mode: container:...` ni
`service:...` (lo que indicaría que comparte namespace con otro contenedor,
rompiendo el aislamiento anterior), y si además hay una VPN de plataforma
activa en `lab` a la vez, lo señala explícitamente como "sin conflicto
posible" y explica por qué.

**Dónde SÍ puede darse el conflicto real que describe `prompt_v3.md`** (dos
procesos disputándose la misma tabla de rutas del sistema): si, aparte de
este contenedor, el propio alumno instala Tailscale directamente en su
sistema operativo (fuera de Docker) y a la vez usa ahí una VPN de
plataforma también fuera de Docker. Eso queda fuera del alcance de SecLab —
no gestiona nada que corra fuera de sus propios contenedores — y se
menciona aquí sólo para que quede claro que no es una laguna del diseño,
sino un caso de uso distinto que este documento no cubre.

## Qué verifica el smoke test (sin conexión real)

`scripts/ci/probar-tailscale.sh` (también en la CI, job `tailscale-test`)
verifica, sin generar nunca una auth key real ni contactar la red real de
Tailscale:

1. `SECLAB_HABILITAR_TAILSCALE=true` + `TAILSCALE_AUTH_KEY` vacía →
   `seclab tailscale up` se niega **antes** de tocar Docker.
2. La misma comprobación, pero invocando `docker compose` directamente sin
   pasar por el CLI: el propio `command:` del contenedor también se niega.
3. Con una auth key de prueba obviamente inválida (que a propósito NO usa el
   prefijo real `tskey-auth-`, para no disparar el propio escáner de
   secretos del proyecto por una key de mentira) apuntando a un servidor de
   control **local e inexistente** (`--login-server=http://127.0.0.1:1`, nunca al
   real `controlplane.tailscale.com`): el contenedor sigue vivo reintentando
   el login, el rechazo queda en los logs como "connection refused" **local**
   (nunca sale tráfico real de la máquina) y la auth key nunca aparece en los
   logs.
4. El volumen de estado (`${PROYECTO}-tailscale-state`) sobrevive a
   `docker compose down` + `up`: una marca escrita a mano en él sigue
   presente tras recrear el contenedor.
5. El contenedor `tailscale` vive en su propio namespace de red y su propio
   proyecto de Compose, nunca compartido con `lab`.
6. `lab` arranca con normalidad, sin ganar `NET_ADMIN` ni ningún privilegio
   extra sólo porque Tailscale esté habilitado (son proyectos de Compose
   independientes: activar uno no toca al otro).

### Por qué el `--login-server` local en el paso 3

Se probó primero sin él, apuntando (sin querer) al control plane real de
Tailscale: incluso con una key obviamente inválida, `tailscaled` abre una
conexión TLS real hacia `controlplane.tailscale.com` antes de que el
servidor la rechace. Eso **sí** sería "conectar de verdad a la red de
Tailscale de alguien", que `prompt_v3.md` prohíbe para esta fase — así que el
smoke test apunta siempre a un puerto local en el que nunca escucha nada
(`127.0.0.1:1`, dentro del propio contenedor), y el rechazo que se observa es
un `connection refused` completamente local, sin salir de la máquina.

### Lo que queda sin verificar

Unirse de verdad a una tailnet, con una auth key real, y servir tráfico real
con `tailscale serve` hacia otro dispositivo de esa tailnet. Sin cuenta de
Tailscale del curso, no hay forma honesta de probarlo sin usar una cuenta
personal de alguien, que tampoco sería representativa. Ver
[TESTING_GAPS.md](../TESTING_GAPS.md), sección "Fase 9", para el detalle y el
procedimiento propuesto para cuando el curso tenga una cuenta.
