# Perfiles y paquetes de herramientas

> Estado: los tres perfiles están construidos y con smoke tests que pasan.
> Los paquetes opt-in (`web`, `ad`, `pwn`, `forensics`, `cloud`, `mobile`)
> llegan en la Fase 12: son conjuntos instalables sobre cualquier perfil.

## Perfiles de imagen

Un perfil es una imagen completa. Eliges uno al arrancar. Los tres incluyen
desde `lite` el escritorio XFCE por navegador (noVNC), Firefox, code-server y
un terminal por navegador (ttyd): no hay perfil "sin escritorio".

| Perfil | Qué añade | Cuándo usarlo |
|---|---|---|
| `lite` ✅ | Shell, red, recon básico, XFCE por navegador (noVNC), Firefox, code-server, terminal por navegador (ttyd) | Trabajo diario contra HTB o TryHackMe, con o sin interfaz gráfica |
| `full` ✅ | `lite` más web, AD, privesc, wordlists, CTF y recon/pivoting adicional | Máquinas complejas y CTFs largos |
| `full-msf` ✅ | `full` más Metasploit | Sólo si vas a usar Metasploit; pesa más |

`full-msf` nunca es el predeterminado ni entra en la publicación por defecto:
es opt-in explícito. Ver [requisitos.md](requisitos.md) para RAM y disco de
cada uno.

Cambiar de perfil no toca tu workspace ni tus secretos: son la misma
instalación con otra imagen.

```bash
./bin/seclab start --profile full
```

## Los servicios de escritorio y acceso web

| Servicio | Dónde | Autenticación |
|---|---|---|
| Página de bienvenida | `http://127.0.0.1:8080` (`seclab open`) | ninguna: no muestra nada privado |
| Escritorio XFCE | `http://127.0.0.1:6080/vnc.html` | contraseña de VNC (`SECLAB_VNC_PASSWORD`) |
| code-server | `http://127.0.0.1:8443` | contraseña (`SECLAB_CODE_PASSWORD`) |
| Terminal (ttyd) | `http://127.0.0.1:7681` | usuario/contraseña (`SECLAB_TERMINAL_PASSWORD`) |

Los cuatro se publican **sólo en 127.0.0.1**, en los tres perfiles por igual:
ya no hay un perfil donde estos puertos no existan. El servidor VNC en sí
(puerto 5901) no se publica nunca: sólo noVNC llega a él, desde dentro del
contenedor.

Los servicios se activan por defecto en los tres perfiles. Si quieres
prescindir de alguno —por ejemplo, sólo code-server sin escritorio gráfico—
pon `SECLAB_HABILITAR_DESKTOP=false` en `.env`. Y si activas un servicio en un
perfil que no lo trae (por ejemplo, a mano con un `SECLAB_PERFIL` mal escrito),
el laboratorio **no arranca** y te dice qué perfil usar, en lugar de quedarse
a medias.

### Qué te encuentras al entrar por el escritorio

La barra superior trae, de izquierda a derecha: menú de aplicaciones, **lanzador
de terminal**, **lanzador de Firefox**, la lista de ventanas, el reloj y el botón
de salir. En el escritorio hay accesos directos a la terminal, a Firefox y a
`/workspace`.

La terminal usa la Nerd Font de la imagen, así que los separadores de la barra
de tmux se ven bien sin instalar nada en tu máquina. Eso vale **dentro** del
escritorio; en una sesión SSH la fuente la pone tu terminal, y para eso está
`SECLAB_GLIFOS=ascii` (ver [troubleshooting](troubleshooting.md)).

Si tu escritorio no se parece a esto —porque venías de una versión anterior o
porque lo has cambiado y quieres volver atrás:

```bash
./bin/seclab escritorio restablecer
```

Dice qué va a sobrescribir, pide confirmación y reinicia sólo la sesión de
escritorio. No toca tu workspace ni el resto del laboratorio.

Dentro del laboratorio, `servicios` muestra el estado de todos ellos:

```bash
./bin/seclab shell
servicios
servicios restart escritorio-sesion
```

## Paquetes opt-in

Los paquetes son conjuntos de herramientas que se instalan sobre un perfil sin
tener que reconstruir una imagen distinta.

| Paquete | Contenido |
|---|---|
| `web` | Recon HTTP, fuzzing, DNS, TLS, bug bounty |
| `ad` | SMB, Kerberos, LDAP, BloodHound, movimiento lateral |
| `privesc` | linPEAS, winPEAS, pspy, utilidades de escalada |
| `pwn` | pwndbg/GEF, checksec, ropper, patchelf, QEMU user-mode |
| `forensics` | Volatility 3, YARA, Sleuth Kit, tshark, esteganografía |
| `cloud` | kubectl, Helm, Trivy, Syft/Grype, auditoría cloud |
| `mobile` | apktool, JADX, adb |
| `msf` | Metasploit y dependencias |

No hay paquete `desktop`: XFCE, noVNC, code-server y ttyd ya vienen en los
tres perfiles desde `lite`, así que no hace falta instalarlos aparte.

Cada paquete trae su cheatsheet en `docs/cheatsheets/`. Los ejemplos usan los
targets de laboratorio incluidos, porque son reproducibles para toda la clase.

## Qué hay dentro de `lite`

Para ver el contenido exacto de tu imagen, con la versión de cada herramienta:

```bash
./bin/seclab image info
./bin/seclab shell
cat /opt/seclab/manifiesto-herramientas.txt
```

El manifiesto se genera durante el build, no se escribe a mano: dice lo que
realmente quedó instalado. Si un paquete de la lista no aparece instalado, el
build se detiene, porque un manifiesto que miente no sirve de nada.

`lite` añade además `eza` y `bat` (reemplazos modernos de `ls` y `cat`, ambos
paquetes de apt).

`nikto` no está en `lite`, y en `full` no es el de Ubuntu: el paquete de la
distribución es la versión 2.1.5 y la actual es la 2.6.1 —cinco años de firmas
de diferencia en un escáner de vulnerabilidades web—. En `full` se instala de
su publicación oficial, con versión fijada y checksum verificado. El criterio
general está en [politica-herramientas.md](politica-herramientas.md).

## Nota sobre `full`: qué trae y qué no

`full` incluye lo que se usa en casi todas las prácticas: web (sqlmap, ffuf,
gobuster, nikto, wfuzz, hydra), Active Directory (impacket, smbclient, smbmap,
krb5, ldap-utils), escalada (linPEAS, winPEAS, pspy), análisis (radare2, gdb,
pwntools, binwalk, exiftool) y un subconjunto de SecLists.

A eso se suman 13 herramientas nuevas, todas de su publicación oficial con
versión fijada y checksum verificado (ver
[politica-herramientas.md](politica-herramientas.md)):

- Recon HTTP: `subfinder` (2.16.0), `nuclei` (3.11.1), `httpx-toolkit`
  (1.11.0) — el trío de ProjectDiscovery. Se instala como `httpx-toolkit`, no
  como `httpx`: el cliente HTTP de Python del mismo nombre (dependencia
  transitiva de `netexec` y `pwncat-cs`) instala un script llamado `httpx` en
  la misma ruta y se comería el binario de Go sin avisar. Kali empaqueta el
  mismo binario con el mismo nombre por el mismo motivo.
- Enumeración y fuzzing: `feroxbuster` (2.13.1), `rustscan` (2.4.1).
- Pivoting: `chisel` (1.12.0), `ligolo-ng` (0.9.1, sólo el componente proxy).
- Active Directory: `enum4linux-ng` (1.3.10), `netexec` (1.5.1).
- Pwn/forense: `pwndbg` (2026.07.29 — plugin de gdb, no un binario suelto: se
  carga solo al ejecutar `gdb`, que fuente `/opt/seclab/pwndbg/gdbinit.py`),
  `one_gadget` (2.1.1, gem de RubyGems).
- Web: OWASP ZAP (2.17.0).
- Shells: `pwncat-cs` (0.5.4, paquete de PyPI).

Dos candidatas se evaluaron y se descartaron a propósito:

- **exploitdb/searchsploit**: su repositorio oficial
  (`offensive-security/exploitdb`) está archivado en GitHub desde el
  10-11-2022 —congelado, justo lo contrario de lo que necesita una base de
  exploits para servir de algo—. Descartada.
- **Burp Suite Community**: PortSwigger no publica checksum oficial de su
  descarga. OWASP ZAP, que sí lo tiene, cubre el mismo caso de uso de proxy
  web.

Las wordlists son un **subconjunto** deliberado —`common.txt`,
`raft-medium-directories.txt`, subdominios, usuarios y rockyou—, no SecLists
completo: son 1,5 GB de los que en una asignatura se usan siempre los mismos
cinco archivos. Están en `/opt/seclab/wordlists`.

`pspy` sólo se publica para x86: en `arm64` no se instala y el manifiesto lo
dice, en lugar de dejar un binario que no ejecuta.

## Nota sobre ARM

Algunas herramientas no tienen binario estable para `arm64`. El manifiesto de herramientas
marca explícitamente cuáles cambian de versión, degradan o se omiten, para que
sepas de antemano qué esperar si trabajas en un Mac con Apple Silicon. En `lite`
es `whatweb`: funciona, pero sobre el intérprete de Ruby y con menos
rendimiento.
