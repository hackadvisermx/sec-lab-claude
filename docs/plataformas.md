# Diferencias por sistema operativo

## macOS (Intel y Apple Silicon)

Necesitas **Docker Desktop** o una alternativa compatible (OrbStack, Colima).

- Docker corre dentro de una máquina virtual Linux. `/dev/net/tun` existe ahí
  dentro, así que la VPN funciona, pero es la VM la que enruta, no macOS.
- En Apple Silicon (`arm64`), algunas herramientas de seguridad no tienen
  binario nativo. El manifiesto de herramientas marcará cuáles degradan o se
  omiten. Emular `amd64` funciona pero es lento: para esas herramientas
  concretas suele salir más a cuenta usar el perfil `lite` y tirar de la
  plataforma remota.
- Ajusta la RAM asignada a Docker Desktop en sus preferencias. Por defecto
  suele ser insuficiente para el perfil `full`.

## Linux

El caso más sencillo: Docker corre nativo y `/dev/net/tun` es el del sistema.

- Instala Docker Engine y el plugin de Compose desde los repositorios
  oficiales, no la versión que traiga tu distribución si está atrasada.
- Añade tu usuario al grupo `docker` para no necesitar `sudo`. Ten presente que
  eso equivale a acceso root en la máquina.
- Si `/dev/net/tun` no existe: `sudo modprobe tun`.

## Windows con WSL2

SecLab se ejecuta **dentro de WSL2**, no en Windows.

- Instala Docker Desktop con la integración de WSL2 activada, o Docker Engine
  directamente dentro de tu distribución de WSL.
- **Guarda el repositorio en el sistema de archivos de Linux**
  (`~/seclab`), no en `/mnt/c/...`. Trabajar sobre el disco de Windows desde
  WSL2 es mucho más lento y da problemas de permisos que rompen el chequeo de
  seguridad.
- El kernel de WSL2 incluye soporte de TUN. Si `/dev/net/tun` no aparece,
  reinicia WSL desde PowerShell con `wsl --shutdown` y vuelve a entrar.
- El cortafuegos de Windows puede interferir con los puertos publicados. Como
  todo escucha en `127.0.0.1`, normalmente no hace falta tocarlo.

## Tabla rápida

| | macOS | Linux | WSL2 |
|---|---|---|---|
| Docker | Desktop / OrbStack / Colima | Engine nativo | Desktop con integración, o Engine en WSL |
| `/dev/net/tun` | Dentro de la VM | Del sistema | Del kernel de WSL2 |
| Rendimiento | Bueno | El mejor | Bueno si el repo está en el FS de Linux |
| Aviso principal | RAM asignada a Docker | Grupo `docker` = root | No usar `/mnt/c` |
