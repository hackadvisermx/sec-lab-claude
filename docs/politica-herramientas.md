# Política de herramientas y versiones

SecLab se construye sobre **Ubuntu 26.04 LTS**, no sobre Kali. Esta página
explica esa decisión y, sobre todo, cómo se resuelve el problema que la motivó:
tener las versiones actuales de las herramientas.

## Por qué Ubuntu y no Kali

Kali es la distribución habitual en formación, pero atarse a ella significa
depender de sus paquetes para todo. La base de SecLab necesita otra cosa:
soporte de años que acompañe el ciclo de una asignatura, reproducibilidad, y
que la elección de la base no condicione la versión de cada herramienta.

Ubuntu LTS da lo primero. Lo segundo lo resuelve el anclaje por digest. Lo
tercero es el reparto en dos vías que viene a continuación.

Se descartó Debian estable, que pesa unos 10 MB menos, porque sus paquetes van
un ciclo entero por detrás:

| | Debian 13 | Ubuntu 26.04 | Kali |
|---|---|---|---|
| nmap | 7.95 | 7.98 | 7.99 |
| python3 | 3.13.5 | 3.14.3 | 3.14.6 |
| openssh | 10.0 | 10.2 | 10.4 |
| ripgrep | 14.1.1 | 15.1.0 | 15.2.0 |
| nikto | no existe | 2.1.5 | 2.6.1 |

Sobre una imagen de ~800 MB, esos 10 MB no compran nada. El ciclo de retraso, en
cambio, se nota todos los días.

## Las dos vías

Ningún repositorio de distribución basta para las herramientas ofensivas que se
mueven rápido. Por eso SecLab usa dos caminos distintos, y el manifiesto dice
cuál usó cada herramienta.

### Vía apt — sistema, utilidades y red

Para lo que Ubuntu mantiene al día y parchea por su cuenta: shell y coreutils,
`iproute2`, `tcpdump`, `nmap`, `bind9-dnsutils`, OpenSSH, Python, `git`, `curl`.

Aquí el repositorio es una ventaja: parches de seguridad automáticos, sin
mantenimiento por nuestra parte y versiones al día. Los paquetes se declaran en
`docker/paquetes-<perfil>.txt`.

### Vía publicación oficial — herramientas de evolución rápida

Para lo que el repositorio deja obsoleto enseguida: escáneres web, utilidades en
Go del ecosistema de bug bounty (`ffuf`, `nuclei`, `httpx`, `subfinder`),
herramientas de Active Directory, y en general cualquier proyecto que publique
varias versiones al año.

Estas se traen del repositorio oficial del proyecto con **tres condiciones
innegociables**:

1. **Versión exacta fijada**, nunca `latest` ni la rama principal.
2. **Checksum o firma verificados** antes de instalar nada.
3. **Registro en el manifiesto**, con la versión y el origen.

Nunca se ejecuta un script de instalación remoto (`curl ... | sh`) sin
verificar lo descargado: eso es entregar la imagen a quien controle ese
servidor.

### La regla que zanja las dudas

**Una herramienta cuyo paquete en Ubuntu esté claramente desactualizado no se
instala vía apt.** O se trae por la segunda vía, o se omite del perfil y se
documenta por qué. Es preferible que falte a que alguien trabaje con una
versión de hace años creyendo que está al día.

El primer caso concreto es `nikto`: Ubuntu ofrece la 2.1.5 frente a la 2.6.1
actual. No está en `lite`; llegará en el paquete `web` (Fase 12) desde su
publicación oficial.

## Cómo actualizar una versión fijada

1. Mira la última versión publicada en el repositorio oficial del proyecto.
2. Descarga el archivo de checksums que publica junto a los binarios.
3. Actualiza la versión y el checksum en la definición de la herramienta.
4. Reconstruye y comprueba que el manifiesto refleja la versión nueva.
5. Anótalo en `CHANGELOG.md`.

Conviene hacer esta revisión **al comenzar cada curso**, no en mitad de él: así
todo el grupo trabaja con lo mismo de principio a fin.

## Reproducibilidad

- La imagen base está anclada por el **digest de su lista de manifiestos**, de
  forma que `amd64` y `arm64` resuelven dentro del mismo conjunto verificado.
- El **manifiesto de herramientas** se genera durante el build y registra la
  versión realmente instalada de cada paquete.
- **El build falla si una herramienta declarada no queda instalada.** Ya evitó
  un error real: `dnsutils` y `p7zip-full` eran paquetes transitorios y el
  manifiesto no podía informar de su versión.
- La ruta principal para el alumnado es **descargar la imagen ya publicada y
  firmada** (Fase 8), con lo que todo el grupo obtiene bit a bit lo mismo sin
  depender de cuándo construyó cada uno.

## Capacidades de fichero

Hay un detalle que sólo se descubre ejecutando: si un binario reclama una
capacidad de fichero que el contenedor no tiene en su conjunto delimitador, el
kernel **rechaza su ejecución por completo**. No es que la herramienta funcione
con menos permisos: no arranca ni para imprimir su versión.

Le pasó a nmap sobre la base anterior, que lo marcaba con `cap_net_admin` — una
capacidad que SecLab reserva deliberadamente para el servicio de VPN. Por eso el
build comprueba las capacidades de fichero de toda la imagen y se detiene si
alguna queda fuera del conjunto concedido. Ver [SECURITY.md](../SECURITY.md).

## Qué se instala fijado, y por qué cada cosa

Esta es la lista completa de lo que **no** viene de apt, con el motivo. Todo
ello se descarga de la publicación oficial del proyecto, con la versión escrita
en el Dockerfile y el checksum comprobado antes de instalar nada; el build se
detiene si no coincide.

| Herramienta | Perfil | Por qué no apt |
|---|---|---|
| Oh My Zsh y sus dos plugins | `lite` | No están empaquetados; se fijan por commit |
| Oh my tmux! | `lite` | Igual: configuración, no paquete |
| code-server | `desktop` | No está en el repositorio de Ubuntu |
| Firefox ESR | `desktop` | Los paquetes `firefox` y `chromium-browser` de Ubuntu son transiciones a **snap**, y snapd no funciona dentro de un contenedor: instalarlos deja un navegador que no arranca |
| JetBrainsMono Nerd Font | `desktop` | Las fuentes con glifos Powerline no están en el repositorio |
| nikto | `full` | Ubuntu trae la 2.1.5; la actual es la 2.6.1 |
| linPEAS y winPEAS | `full` | No están empaquetados en ninguna distribución |
| pspy | `full` | No empaquetado. **Sólo x86**: en arm64 no se instala y el manifiesto lo dice |
| SecLists (subconjunto) | `full` | No está en Ubuntu, y del repositorio completo (1,5 GB) se usan siempre las mismas cinco listas |
| Metasploit | `full-msf` | No está en Ubuntu. Su instalador oficial es un script remoto que se ejecuta a ciegas, cosa que esta imagen no hace: se usa el `.deb` de Rapid7 con el checksum que publica su propio índice de paquetes |

El manifiesto de herramientas tiene una columna `vía` que distingue las dos
rutas, para que dentro del laboratorio se pueda ver de un vistazo de dónde
salió cada cosa:

```bash
grep fijada /opt/seclab/manifiesto-herramientas.txt
```

Dos consecuencias de fijar la versión que conviene tener claras:

- **Metasploit avisará de que está desactualizado** en cuanto pasen dos
  semanas. Es correcto y es el precio de la reproducibilidad: todo el aula
  trabaja sobre la misma versión. Lo que se actualiza es el número del
  Dockerfile, no el contenedor de cada alumno.
- **Ninguna descarga usa `latest`.** Si mañana el proyecto publica una versión
  nueva, esta imagen sigue construyendo lo mismo hasta que alguien cambie a la
  vez la versión y el checksum.
