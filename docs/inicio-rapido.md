# Inicio rápido

## Requisitos

- Docker y Docker Compose. Ver [plataformas.md](plataformas.md) para las
  particularidades de macOS, Linux y Windows/WSL2.
- Bash y Python 3, presentes en cualquiera de los tres sistemas.
- Para el perfil `lite`: 2 GB de memoria disponibles para el contenedor y 5 GB
  de disco. Ver [requisitos.md](requisitos.md).

## Cinco minutos

```bash
./bin/seclab init
```

Eso es todo. `init` hace, en este orden:

1. Detecta sistema, arquitectura, Docker, memoria, disco, puertos y TUN.
2. **Se niega a seguir** si tu máquina no llega al mínimo del perfil, y te dice
   cuál sí te va a funcionar.
3. Crea `.env` desde la plantilla, sin sobrescribir el tuyo si ya existe.
4. Genera los secretos y una llave SSH dedicada.
5. Crea `workspace/` y los tres directorios de VPN desde las plantillas.
6. Construye la imagen (la primera vez tarda unos minutos).
7. Arranca y espera a que el laboratorio esté sano.
8. Muestra sólo los accesos que existen de verdad.

Si prefieres elegir el perfil tú:

```bash
./bin/seclab init --profile lite
```

## El día a día

```bash
./bin/seclab shell        # entrar al laboratorio
./bin/seclab status       # perfil, salud, consumo y accesos
./bin/seclab stop         # detener; los datos se conservan
./bin/seclab start        # volver a levantarlo
```

Tu trabajo vive en `workspace/`, que está montado dentro del contenedor en
`/workspace`. Es lo que sobrevive a cualquier reconstrucción de la imagen.

## Con interfaz gráfica: el perfil `desktop`

```bash
./bin/seclab start --profile desktop
./bin/seclab open
```

Eso abre la página de bienvenida, con los accesos al escritorio XFCE (en el
navegador, por noVNC) y a code-server. Las contraseñas están en tu `.env`:

```bash
grep -E "SECLAB_(VNC|CODE)_PASSWORD" .env
```

La página no las muestra a propósito: se sirve por HTTP y acabaría en el
historial del navegador o en el proyector del aula.

## Entrar por SSH

`seclab status` te da el comando exacto, con la ruta de tu llave:

```bash
ssh -i "secretos/seclab_ed25519" -p 2222 seclab@127.0.0.1
```

Sólo por llave: no hay contraseña que probar, ni acceso de root. La llave de
host se conserva entre reinicios, así que tu cliente no te avisará de cambios.

## Comprobar que todo está en orden

```bash
./bin/seclab doctor       # entorno, llave de host, volumen y glifos de la barra
./bin/seclab seguridad    # secretos, permisos y exposición de servicios
./bin/seclab image info   # qué hay dentro de la imagen
```

`doctor` es interactivo: te pregunta si ves bien los separadores de la barra de
estado y te ofrece arreglarlo. Con `--sin-preguntas` no pregunta nada, para
cuando lo llames desde un script.

## Guardar tu trabajo

```bash
./bin/seclab backup          # copia verificada de .env, llaves, vpn y workspace
./bin/seclab backup verify   # comprobar la última
```

La copia queda en `backups/` y **contiene secretos en claro**: trátala como una
contraseña. Los detalles, en [backup.md](backup.md).

## Qué falta todavía

Los cuatro perfiles están construidos, los workspaces de laboratorio
(`seclab lab`), `seclab update` y la VPN multiperfil (`seclab vpn`) ya
funcionan. Lo que falta: los paquetes opt-in y los targets vulnerables, en la
Fase 12, y el servidor MCP y el despliegue en la nube, ambos opcionales. Un
comando que aún no exista te lo dirá.

## Antes de conectarte a una plataforma

Lee [uso-autorizado.md](uso-autorizado.md). Son cinco minutos y evita la clase
de problema que no se arregla con un comando.

Para HTB, TryHackMe o la VPN de un cliente, ver [vpn.md](vpn.md).
