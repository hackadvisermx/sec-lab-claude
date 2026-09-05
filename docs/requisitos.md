# Requisitos por perfil

> Los cuatro perfiles están construidos y medidos en macOS arm64 con Docker
> 29.7. En amd64 los tamaños varían algo; los tiempos, bastante, según la red.

| Perfil | Contenido | RAM mínima | Imagen (arm64) | Build desde cero |
|---|---|---|---|---|
| `lite` | Shell, red, recon básico, utilidades | 2 GB | 809 MB | ~3 min |
| `desktop` | `lite` + XFCE, noVNC, code-server, Firefox | 4 GB | 2,9 GB | ~7 min |
| `full` | `desktop` + web, AD, privesc, wordlists, CTF | 8 GB | 4,3 GB | ~10 min |
| `full-msf` | `full` + Metasploit | 8 GB | 5,7 GB | ~15 min |

El disco que hay que tener libre es más que el tamaño de la imagen: el build
necesita espacio para las capas intermedias y para la caché. Cuenta el doble
del tamaño final y no te quedarás corto.

La RAM indicada es la que necesita el contenedor, no la de tu máquina. Súmale
lo que consume tu sistema operativo y el navegador. En la práctica: con 8 GB de
RAM total, `desktop` va bien y `full` va justo.

Los tiempos de build son de la primera vez. Reconstruir tras un cambio en la
configuración del curso tarda segundos, porque las capas de paquetes y de
descargas fijadas se reutilizan.

## Qué comprueba SecLab

`seclab init` verifica antes de arrancar:

- Sistema operativo y arquitectura (incluido Windows con WSL2).
- Docker y Docker Compose presentes y en marcha.
- **Memoria disponible para los contenedores**, no la de la máquina. En macOS y
  Windows el contenedor vive en una VM de Docker con su propio límite, casi
  siempre bastante menor que la RAM del portátil: preguntar al sistema daría una
  cifra tranquilizadora y falsa.
- Disco disponible frente al mínimo del perfil elegido.
- Puertos libres.
- Disponibilidad de `/dev/net/tun`, necesario para la VPN.

Si tu máquina no llega al mínimo del perfil, **SecLab no arranca**: te dice
cuánto falta y qué perfil más ligero sí te va a funcionar. Es preferible a un
contenedor que muere a los diez minutos sin explicación.

## Comprobación manual

Si quieres mirarlo antes de instalar nada:

Lo más rápido es preguntárselo a SecLab:

```bash
./bin/seclab doctor
```

Si prefieres mirarlo a mano:

**macOS**

```bash
docker system info --format '{{.MemTotal}}' | awk '{printf "RAM Docker: %.1f GB\n", $1/1024/1024/1024}'
sysctl -n hw.memsize | awk '{printf "RAM máquina: %.1f GB\n", $1/1024/1024/1024}'
df -h / | tail -1 | awk '{print "Disco libre: " $4}'
uname -m
```

**Linux y WSL2**

```bash
free -h | awk '/^Mem:/ {print "RAM: " $2}'
df -h / | tail -1 | awk '{print "Disco libre: " $4}'
uname -m
```

`arm64` o `aarch64` significa ARM (Apple Silicon, Raspberry Pi, portátiles con
Snapdragon). `x86_64` o `amd64` significa Intel o AMD. Algunas herramientas no
tienen binario estable para ARM: el manifiesto de herramientas marcará cuáles
degradan o se omiten en esa arquitectura.
