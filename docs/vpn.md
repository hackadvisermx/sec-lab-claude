# VPN multiperfil

SecLab maneja tres perfiles de VPN independientes, pensados para el uso real
del curso:

| Perfil | Para qué | Configuración | Interfaz |
|---|---|---|---|
| `vpnhtb` | Hack The Box | `vpn/vpnhtb/` | `tun-htb` |
| `vpntry` | TryHackMe | `vpn/vpntry/` | `tun-thm` |
| `vpncli` | VPN de cliente o engagement (uso docente y profesional) | `vpn/vpncli/` | `tun-cli` |

Cada directorio tiene su propio `README.md` con el procedimiento exacto de
descarga del `.ovpn` en esa plataforma.

## Cómo funciona

La VPN es un atajo dentro del propio contenedor de laboratorio (`lab`), no un
contenedor aparte. OpenVPN e iptables se instalan en la imagen (todos los
perfiles, `docker/paquetes-lite.txt`), y un script interno,
`/usr/local/bin/seclab-vpn` (instalado desde `docker/shell/seclab-vpn.sh`),
gestiona los túneles con privilegios de root. `docker-compose.vpn.yml`
concede a `lab` sólo lo mínimo que ese script necesita:

- `cap_add: NET_ADMIN` — manipular interfaces y rutas.
- `devices: /dev/net/tun` — crear las interfaces TUN.

Nada más. `lab` no cambia de `network_mode`, no pierde sus `ports` ni sus
`networks`: sigue siendo el mismo contenedor, en el mismo bridge, con el
mismo SSH publicado, arriba o abajo esté cualquier túnel.

**`docker-compose.vpn.yml` sólo se aplica si `SECLAB_HABILITAR_VPN=true` en
`.env`** (por defecto, `false`). Con la variable en `false`, `lab` ni siquiera
tiene `NET_ADMIN` ni `/dev/net/tun` concedidos — no hacen falta si no vas a
usar ninguna VPN de plataforma, y no hay motivo para tenerlas ahí "por si
acaso". No hace falta activarla a mano: la primera vez que ejecutas
`seclab vpn up <perfil>`, si la variable sigue en `false`, el CLI te pide
confirmación, la activa y **recrea `lab`** para concedérselas — se pierde
cualquier shell o proceso que tuvieras abierto dentro en ese momento (tu
directorio personal y tu `workspace/` no se tocan). A partir de ahí queda
concedida en arranques posteriores, hasta que la pongas en `false` tú mismo y
reinicies.

**Por qué este diseño y no un contenedor de VPN dedicado por perfil** (que es
como se implementó esta fase originalmente): aislar la VPN en su propio
contenedor no protegía de nada que una interfaz TUN compartida dentro de
`lab` no resolviera igual. Quien más comparte la misma VPN de plataforma
(otro alumno en HTB o THM, u otra persona en la VPN de un cliente) puede
alcanzar por esa interfaz a cualquiera que la use — eso no depende de en qué
contenedor viva la interfaz, sino de que la interfaz exista y de qué reglas
de firewall tenga puestas. La mitigación real es el killswitch de entrada
(más abajo), no una topología de contenedores distinta. Con este diseño,
además, **los tres perfiles pueden estar arriba a la vez de verdad**: la
arquitectura anterior sólo podía unir `lab` al espacio de red de uno de
ellos.

Las decisiones de diseño que más notarás en el día a día:

**No se acepta la ruta por defecto del túnel.** OpenVPN arranca con
`--route-nopull` y SecLab añade explícitamente sólo las rutas que declaras en
`SECLAB_VPN_RANGOS`, vía `--route`. Sin esto, la VPN de HTB o de un cliente se
llevaría todo tu tráfico y te rompería Docker, Tailscale y la red del campus.
Aceptar la ruta por defecto es un override consciente
(`SECLAB_VPN_RUTA_DEFECTO=true` en `perfil.env`, hoy sólo en la plantilla de
`vpncli`, donde algunos engagements lo exigen): con él, OpenVPN arranca además
con `--redirect-gateway def1` y **todo** tu tráfico sale por el túnel.

**Los tres perfiles pueden convivir arriba a la vez.** Cada uno usa su propia
interfaz TUN, explícita y no numerada (`tun-htb`, `tun-thm`, `tun-cli`), y sus
propias reglas de iptables. El único motivo real de rechazo al hacer
`seclab vpn up <perfil>` es que sus rangos declarados se solapen con los de
un perfil que YA está activo: con rangos solapados no hay forma de decidir
por qué túnel debe salir un paquete, y se rechaza explicando el conflicto en
vez de dejarte con un enrutamiento impredecible. Si no se solapan, se permite
sin más — no hace falta ninguna opción para forzarlo.

**Killswitch de salida, fail-closed.** `seclab-vpn` instala reglas de
`iptables` (`OUTPUT`/`FORWARD`, `DROP` hacia cada rango declarado de ese
perfil que no salga por su propia interfaz) **antes** de arrancar OpenVPN, y
esas reglas no dependen de que el túnel esté arriba: si cae, el tráfico hacia
los rangos del perfil se sigue bloqueando, en vez de escapar por la interfaz
normal del contenedor. Lo verás reflejado en `seclab status`, `seclab doctor`
y `seclab vpn status`.

**Killswitch de entrada, nuevo en este diseño.** Por cada perfil activo, hay
además una regla sobre tráfico ENTRANTE por su interfaz: se permite
`ESTABLISHED`/`RELATED` (las respuestas a algo que `lab` inició) y se
descarta cualquier conexión `NEW`. Esto es la mitigación directa a que
"los jugadores en la misma VPN de plataforma pueden alcanzarte por el
túnel": nadie que comparta esa red puede iniciar una conexión hacia un
servicio de `lab` a través del túnel, aunque comparta la interfaz contigo.

Esto **no es un filtro de objetivos**: ni el killswitch de salida ni el de
entrada miran contra qué IP dentro del rango se conecta el alumno o quién es
quien intenta entrar — sólo por qué interfaz sale o entra el tráfico. SecLab
no valida ni bloquea objetivos — ver
[uso-autorizado.md](uso-autorizado.md).

## Puesta en marcha

```bash
# 1. Descarga el .ovpn de la plataforma (ver el README de cada perfil)
# 2. Colócalo en su directorio
cp ~/Downloads/tu-usuario.ovpn vpn/vpnhtb/vpnhtb.ovpn

# 3. Ajusta el perfil
cp vpn/vpnhtb/perfil.env.example vpn/vpnhtb/perfil.env
$EDITOR vpn/vpnhtb/perfil.env

# 4. Permisos estrictos
chmod 700 vpn/vpnhtb && chmod 600 vpn/vpnhtb/*

# 5. Conecta
seclab vpn up vpnhtb
seclab vpn status
```

## Comandos

```
seclab vpn list             Perfiles conocidos: .ovpn, perfil.env, cuáles están activos
seclab vpn up PERFIL        Levanta un perfil; pueden estar los tres a la vez
seclab vpn status [PERFIL]  Estado de uno o de todos los perfiles conocidos
seclab vpn routes           Rutas activas hacia los túneles ahora mismo
seclab vpn logs PERFIL      Registro de OpenVPN de ese perfil (sin secretos)
seclab vpn down [PERFIL]    Baja ese perfil, o todos los activos si se omite
```

Todos, salvo `list`, son en realidad `docker exec -u root lab seclab-vpn
<subcomando>`: el CLI del host no reimplementa la lógica de túneles, sólo
valida lo que puede comprobar sin hablar con el contenedor (que el `.ovpn` y
`perfil.env` existan, permisos) y delega. Puedes hacer exactamente lo mismo
desde dentro de una sesión `seclab shell`, con `sudo seclab-vpn <subcomando>`
(el usuario de laboratorio tiene sudo sin contraseña).

`seclab vpn up` valida que el `.ovpn` y `perfil.env` existen y tienen permisos
correctos (avisa con la orden `chmod` exacta si no) antes de delegar. Dentro,
`seclab-vpn up` comprueba que los rangos no se solapen con los de un perfil ya
activo, instala el killswitch, arranca OpenVPN en segundo plano (nunca como
PID 1: `lab` tiene muchos otros procesos) y espera hasta 60 s a que el túnel
esté arriba. Si el proceso de OpenVPN de un perfil muere por su cuenta,
`seclab vpn up <mismo perfil>` lo detecta (no hay PID vivo) y lo vuelve a
levantar en vez de negarse a repetir la operación.

## Los rangos cambian

Los `SECLAB_VPN_RANGOS` de las plantillas son **ejemplos orientativos**. Las
plataformas cambian sus rangos, y varían según el producto, la región y la
sala. La fuente de verdad es lo que negocie el túnel: conecta y mira
`seclab vpn status`, que te muestra los rangos efectivos (los que de verdad
tiene activos ese túnel) y te avisa si no coinciden con los que declaraste en
`perfil.env`.

Si has hecho todo bien y aun así no llegas a la máquina objetivo, lo primero
que hay que mirar es esto.

## Convivencia con Tailscale

Tailscale ya está implementado (Fase 9, opcional): ver
[tailscale.md](tailscale.md) para la guía completa, el flujo de creación de
una auth key y los comandos del CLI. Esta sección se queda como la versión
docente del razonamiento, porque nace de la misma pregunta que motiva la
sección anterior: dos mecanismos de red que podrían pelearse por la tabla de
rutas y por `/dev/net/tun`.

**Decisión de diseño: Tailscale va en un contenedor propio, con su propio
proyecto de Compose — nunca como sidecar de `lab`.** `prompt_v3.md` deja
abiertas tres formas de integrar Tailscale (nodo en el host, Tailscale Serve,
o sidecar compartiendo el namespace de red de `lab`) y descarta
explícitamente la tercera. Con el diseño actual de la Fase 7, `lab` ya no
cambia de `network_mode` al activar o desactivar un perfil de VPN —eso era
cierto en la arquitectura anterior, con un contenedor de VPN dedicado, y dejó
de serlo—, así que la razón para mantener esta decisión ya no es esa. Sigue
siendo la correcta por otro motivo: separar ciclos de vida. El acceso remoto
(Tailscale) y las VPN de plataforma (HTB, THM, un cliente) tienen razones muy
distintas para subir o bajar, y con el diseño actual las segundas se activan
y desactivan sin recrear `lab` en absoluto (`seclab vpn up`/`down` no tocan el
contenedor, sólo procesos y reglas de iptables dentro de él). Un sidecar de
Tailscale pegado a `lab` seguiría atado al ciclo de vida del propio
contenedor —se reiniciaría con él, por ejemplo en un `seclab update`—, justo
cuando más importa no perder el acceso remoto: en un despliegue cloud donde
Tailscale es la única vía de entrada a la máquina.

La implementación real (`docker-compose.tailscale.yml`) va un paso más allá
de "no sidecar": el contenedor `tailscale` vive en su **propio proyecto** de
Docker Compose (`${SECLAB_PROJECT}-tailscale`, distinto del de `lab`), en su
propio namespace de red, alcanzando los puertos de `lab` por
`host.docker.internal` en vez de compartir la red `seclab`. La consecuencia
práctica para la convivencia con la VPN: `tailscale` y las VPN de plataforma
de `lab` no comparten tabla de rutas en absoluto — cada una vive en el
namespace de red de su propio contenedor. `seclab doctor` verifica esto de
verdad (que `tailscale` no declara `network_mode: container:...` ni
`service:...`), no lo da por supuesto. Detalle completo, incluida la
excepción real (Tailscale instalado fuera de Docker, en el propio sistema
operativo del alumno, a la vez que una VPN de plataforma también fuera de
Docker — fuera del alcance de SecLab), en
[tailscale.md](tailscale.md#convivencia-con-vpn-de-plataforma).

## TUN por sistema operativo

- **Linux y WSL2**: `/dev/net/tun` es un dispositivo del kernel del host.
  `seclab doctor` comprueba que exista; si no, sugiere `sudo modprobe tun`
  (Linux) o `wsl --shutdown` desde PowerShell y volver a entrar (WSL2).
- **macOS**: `/dev/net/tun` vive dentro de la VM de Docker Desktop, no en
  macOS. No se puede comprobar desde el host sin arrancar un contenedor;
  `seclab doctor` lo marca como "vive dentro de la VM" y la comprobación real
  ocurre al hacer `seclab vpn up`, que sí necesita el dispositivo dentro de
  `lab` para poder crear la interfaz TUN.

## Seguridad

- Todo `vpn/` está en `.gitignore`. Un `.ovpn` contiene tu certificado
  personal: es una credencial, trátala como tal.
- Permisos `700` en los directorios y `600` en los archivos.
  `seclab seguridad` y `seclab vpn up` avisan si se quedan más laxos, con la
  orden `chmod` exacta.
- Ni las credenciales, ni el contenido del `.ovpn`, ni tu IP pública aparecen
  en logs de `seclab-vpn`, en mensajes del CLI ni en la página de bienvenida.
  La IP del túnel sí se muestra: hace falta para trabajar.
- Las plantillas versionadas viven en `templates/vpn/`; `seclab init` las
  copia a `vpn/`. En Git nunca hay nada real.
- `NET_ADMIN` y `/dev/net/tun` sólo llegan a `lab` cuando
  `docker-compose.vpn.yml` está aplicado, y no permiten nada por sí solos:
  sin ejecutar `seclab-vpn up`, nada escucha ni enruta con esas dos
  concesiones de más.

## Integración con labs

`seclab lab create NOMBRE --vpn vpnhtb` anota en `scope.txt` el perfil y sus
rangos declarados (los reales de `vpn/vpnhtb/perfil.env` si ya existen; si no,
los de la plantilla, marcados explícitamente como ejemplo). Es documentación
para tus notas y tu informe, nunca un filtro: `seclab shell --lab` y
`seclab lab create/reset` avisan —sin bloquear— cuando ninguno de los
perfiles de VPN activos coincide con el que declara el lab.

## Uso

Lo que hagas a través del túnel es cosa tuya y de los términos de servicio de
cada plataforma. SecLab no supervisa el tráfico. Ver
[uso-autorizado.md](uso-autorizado.md).
