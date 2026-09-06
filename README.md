# SecLab

Laboratorio de ciberseguridad reproducible para clase, CTFs y práctica en
plataformas como Hack The Box y TryHackMe.

Cada estudiante despliega **su propia instancia**. Funciona en macOS, Linux y
Windows con WSL2, sobre Intel y ARM. La nube es opcional y no hace falta para
completar el curso.

> **Versión 0.2.0 — Fase 2 de 13.**
> El laboratorio arranca y se puede usar: imagen `lite`, acceso por SSH con
> llave y ciclo de vida completo. Los perfiles `full` y `full-msf`,
> la VPN y el resto de módulos llegan en fases posteriores; los comandos que
> aún no existen lo dicen y salen con código 3, en lugar de aparentar que
> funcionan. Ver [CHANGELOG.md](CHANGELOG.md).

## Puesta en marcha

```bash
./bin/seclab init
```

Detecta tu sistema y arquitectura, comprueba que Docker, la memoria y el disco
dan para el perfil elegido, genera los secretos y la llave SSH, crea el
workspace y los directorios de VPN, construye la imagen y arranca el
laboratorio esperando a que esté sano. Si tu máquina no llega al mínimo, se
niega a arrancar y te dice qué perfil sí te va a funcionar.

```bash
./bin/seclab status       # perfil, salud, consumo y accesos
./bin/seclab shell        # entrar al laboratorio
./bin/seclab doctor       # diagnóstico del entorno
./bin/seclab seguridad    # secretos, permisos y exposición
./bin/seclab stop         # detener sin perder datos
make lint                 # validación de shell, Compose, Bake y Python
```

## Qué trae el perfil `lite`

784 MB sobre **Ubuntu 26.04 LTS** anclada por digest: shell y tmux, utilidades
de trabajo, herramientas de red, recon básico (nmap, whatweb, dnsutils), Python
y acceso SSH. El manifiesto de 49 herramientas con sus versiones exactas viaja
dentro de la imagen y se consulta con `seclab image info`.

No se usa Kali. Las herramientas de sistema y red vienen de Ubuntu LTS, que va
al día; las herramientas ofensivas de evolución rápida se traerán de su
publicación oficial con versión fijada y checksum verificado. El razonamiento
completo está en [docs/politica-herramientas.md](docs/politica-herramientas.md).

El acceso es **sólo por llave**: sin contraseñas y sin root. `nmap` funciona con
y sin `sudo`. El contenedor no recibe `NET_ADMIN` en su conjunto de base;
sólo lo gana —junto con `/dev/net/tun`— cuando se aplica
`docker-compose.vpn.yml`, y aun así no hace nada por sí solo hasta que
ejecutas `seclab vpn up`.

## Estructura

```
.
├── bin/seclab              CLI (todos los mensajes en español)
├── lib/                    comun, plataforma, docker, secretos
├── docker/                 Dockerfile, entrypoint, healthcheck, manifiesto
├── scripts/                revisión de seguridad y análisis de Compose
├── templates/
│   ├── lab/                plantillas de scope e informe
│   ├── shell/              configuración de tmux del curso
│   └── vpn/                plantillas de los tres perfiles de VPN
├── docs/                   documentación
├── docker-compose.yml      runtime local
├── docker-bake.hcl         construcción de imágenes y multi-arch
├── .env.example            plantilla de configuración
└── VERSION                 0.2.0
```

Los directorios `vpn/`, `workspace/`, `secretos/` y el archivo `.env` los crea
`seclab init` y **nunca** entran en Git.

## Principios

**Seguro por defecto.** Los servicios escuchan en `127.0.0.1`. No hay
contraseñas por defecto: si falta un secreto, SecLab no arranca. Ningún
secreto, `.ovpn` ni dato de trabajo puede llegar a Git por accidente.

**Sin funcionalidades simuladas.** Un comando no implementado lo dice. Una
prueba que no se pudo ejecutar se anota en [TESTING_GAPS.md](TESTING_GAPS.md)
con el motivo.

**El contenedor es la caja de herramientas, no el árbitro.** SecLab no valida
contra qué objetivos usas las herramientas. Se asume que tienes autorización;
la responsabilidad es tuya. Ver [docs/uso-autorizado.md](docs/uso-autorizado.md).

## VPN

Tres perfiles independientes, porque es como se trabaja de verdad:

| Perfil | Para qué |
|---|---|
| `vpnhtb` | Hack The Box |
| `vpntry` | TryHackMe |
| `vpncli` | VPN de cliente o engagement |

Ninguno acepta la ruta por defecto del túnel, así que la VPN no te secuestra el
resto de la red, y un killswitch bloquea el tráfico hacia los rangos del
perfil si el túnel cae. Detalles y comandos (`seclab vpn ...`) en
[docs/vpn.md](docs/vpn.md).

## Documentación

Índice completo en [docs/README.md](docs/README.md). Lo esencial:

- [Inicio rápido](docs/inicio-rapido.md)
- [Uso autorizado y responsabilidad](docs/uso-autorizado.md)
- [Requisitos por perfil](docs/requisitos.md)
- [Arquitectura](docs/arquitectura.md)

## Licencia

MIT. Ver [LICENSE](LICENSE).
