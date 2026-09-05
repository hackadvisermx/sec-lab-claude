# Changelog

Todos los cambios relevantes de este proyecto se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/) y el
proyecto usa [versionado semántico](https://semver.org/lang/es/).

## [No publicado]

Fases 3, 4, 5, 6, 7, 8, 9, 10 y 11 entregadas.

### Cambiado — Fase 8, el escaneo de imágenes (Trivy) deja de bloquear la publicación

Decisión explícita del dueño del proyecto, tras publicar `full-msf` de
verdad y encontrar que el kernel (`linux-libc-dev`, necesario en tiempo de
ejecución para `pwntools`/`ropper`) y la librería estándar de Go embebida en
`pspy64` (única versión publicada, sin parche disponible) le iban saliendo
CVEs `CRITICAL` distintas en cada reconstrucción: bloquear la publicación por
ello era perseguir IDs nuevos para siempre sin arreglar nada de fondo, y
además aplicaba a `full`/`full-msf` la misma vara que a una imagen de
aplicación normal, cuando esos perfiles incluyen herramientas ofensivas **a
propósito**.

- `.github/workflows/publicar.yml` y `ci.yml`: Trivy corre siempre
  (`scanners: vuln`, sin el escáner de secretos — ver más abajo por qué) pero
  `exit-code: 0` en todos los casos: nunca bloquea, en ningún perfil.
- El informe se sube como artefacto descargable del workflow
  (`trivy-<perfil>.txt`, incluido `trivy-full-msf.txt`, 90 días de
  retención), para que quien despliegue la imagen lo revise antes de usarla
  — mismo modelo de responsabilidad que el resto del proyecto
  (`docs/uso-autorizado.md`, actualizado con esta decisión).
- **`scanners: vuln`** (sin el escáner de secretos, activo por defecto):
  marcaba como "CRITICAL: Stripe Secret Key" contenido de los propios
  wordlists de Metasploit (pensados para auditar objetivos, no secretos
  reales) y de sus specs de pruebas unitarias. Encontrado en la misma sesión
  de publicación real.
- `.trivyignore` se conserva como documentación histórica de los hallazgos ya
  revisados (`CVE-2026-53398`, `CVE-2026-64535`, `CVE-2026-64564` en
  `linux-libc-dev`; `CVE-2023-24538`, `CVE-2023-24540` en `pspy64`), aunque
  ya no sea necesario para que la publicación pase.

### Añadido — Fase 11, GCP y Oracle Cloud (opcional)

- **`terraform/gcp/`**: módulo Terraform para GCP (Compute Engine), mismo
  patrón que el módulo de referencia de DigitalOcean. `owner` y
  `fecha_expiracion` obligatorias sin valor por defecto (con `validation` en
  HCL); imagen publicada por digest/tag inmutable rechazando `:latest`;
  firewall (`google_compute_firewall`) que sólo abre el puerto SSH
  configurado. Bootstrap: cloud-init completo (no `startup-script` plano) vía
  la metadata `user-data`, que las imágenes oficiales de Ubuntu de
  `ubuntu-os-cloud` ya soportan de fábrica — decisión documentada en
  `terraform/gcp/main.tf` porque permite reutilizar, casi sin tocarla, la
  MISMA plantilla `cloud-init.yaml.tftpl` validada en la Fase 10, en vez de
  reescribir el bootstrap como script de shell plano.
- **`terraform/oracle/`**: módulo Terraform para Oracle Cloud (OCI Compute).
  Mismos requisitos de `owner`/`fecha_expiracion`. A diferencia de
  DigitalOcean y GCP, OCI no ofrece una red por defecto en un tenancy nuevo:
  el módulo crea su propia VCN, subred, gateway de Internet, tabla de rutas y
  lista de seguridad (sólo SSH de entrada), para seguir siendo autocontenido.
  Bootstrap por la misma plantilla de cloud-init (vía metadata `user_data` en
  base64, datasource "OracleCloud"). Documentado con honestidad el Always
  Free tier de las formas Ampere `VM.Standard.A1.Flex` y
  `VM.Standard.E2.1.Micro` como opción de menor riesgo de coste, **sin**
  prometer gasto cero garantizado (los límites del free tier los fija y
  cambia Oracle).
- **Bootstrap reutilizado, no reescrito**: las plantillas
  `terraform/gcp/templates/cloud-init.yaml.tftpl` y
  `terraform/oracle/templates/cloud-init.yaml.tftpl` son, línea a línea, casi
  idénticas a la de `terraform/digitalocean/`: mismo Docker Engine oficial,
  mismos volúmenes nombrados, mismo servicio systemd `seclab.service`, misma
  marca `/etc/seclab-cloud/bootstrap-completo` que sondea `seclab cloud
  wait`. Verificado por render real de ambas plantillas
  (`terraform templatefile()`/`terraform console`, valores ficticios, con
  `habilitar_autodestruccion` en `true` y en `false`), validación YAML
  (`yaml.safe_load`) y `bash -n`/ShellCheck (`--severity=error`) de cada
  bloque `runcmd` renderizado — mismo cuidado que detectó el bug de
  indentación de la Fase 10; esta vez no ha aparecido ninguno nuevo.
- **Autodestrucción opt-in sin token estático en disco (mejora real sobre
  DigitalOcean)**: en GCP, la instancia usa el token de acceso de su propia
  cuenta de servicio (servido por el metadata server, de corta vida, nunca
  escrito a disco) para llamar a `compute.instances.delete` sobre sí misma;
  en Oracle Cloud, se autentica como "instance principal" (identidad firmada
  del servidor de metadata de OCI) para llamar a `oci compute instance
  terminate`. Ambos exigen, a cambio, una concesión de permisos IAM/Policy
  configurada FUERA de este módulo por un administrador (rol de borrado en
  GCP; Dynamic Group + Policy en OCI) — documentado sin adornos como el
  precio de no depositar un secreto estático en la VM.
- **`seclab cloud plan|up|wait|status|connect|destroy --provider
  gcp|oracle`**: `lib/cloud.sh` generalizado para los tres proveedores sin
  duplicar la lógica común (validación de owner/TTL, tabla de coste,
  confirmación literal `acepto`, snapshot del workspace antes de destruir).
  Lo único que varía por proveedor está aislado en tres puntos, cada uno con
  una función `_do`/`_gcp`/`_oracle`: la comprobación de credenciales
  (`exigir_credenciales_cloud`, que despacha a
  `exigir_credenciales_do|_gcp|_oracle` — GCP comprueba Application Default
  Credentials por las mismas rutas que `gcloud`; Oracle Cloud, a propósito,
  **nunca** comprueba `~/.oci/config`, sólo fuentes declaradas
  explícitamente en el `.tfvars` o por variable de entorno, para no depender
  ni siquiera de la existencia de credenciales reales que puedan estar ya en
  una máquina de desarrollo), la tabla de coste (`tabla_costes_cloud`, una
  tabla por proveedor con su propia clave de tamaño — `size` en
  DigitalOcean, `machine_type` en GCP, `shape` en Oracle Cloud —, resuelta
  por `clave_tamano_tfvars`/`tamano_por_defecto`), y el usuario SSH
  (`usuario_ssh_cloud`, que lee la salida `ssh_user` de Terraform si el
  módulo la declara y cae a `root` si no, preservando sin tocarlo el
  comportamiento exacto de DigitalOcean).
- **Backend remoto por proveedor, documentado con sus diferencias reales**:
  GCP usa el backend `"gcs"`, que a diferencia de Spaces (DigitalOcean) y de
  Object Storage (Oracle Cloud) **sí** tiene locking nativo (precondiciones
  de generación de objeto de Google Cloud Storage), sin tabla ni servicio
  adicional. Oracle Cloud, con la misma limitación que DigitalOcean
  (Object Storage S3-compatible sin locking nativo equivalente a DynamoDB),
  recomienda Terraform Cloud por el mismo motivo.
- **`docs/cloud.md`**: extendido con una tabla comparativa de los tres
  proveedores (backend recomendado, autenticación, usuario SSH, coste
  aproximado del tamaño por defecto, autodestrucción), secciones específicas
  de TTL/autodestrucción y notas propias para GCP y Oracle Cloud. Un único
  documento, no divisiones por proveedor: la mayoría del contenido (flujo,
  advertencia de coste, snapshot antes de destruir) es idéntico entre los
  tres y una sola fuente evita que diverjan con el tiempo.
- **`.gitignore`**: sin cambios necesarios. El patrón `/terraform/**/*.tfvars`
  (con `**`, introducido ya en la Fase 10 pensando en esta fase) cubre
  `terraform/gcp/` y `terraform/oracle/` igual que cubre
  `terraform/digitalocean/`. Verificado con `git check-ignore -q` sobre los
  nuevos `.tfvars` (ignorados) y los `.example`/`.terraform.lock.hcl` nuevos
  (versionados).
- **`make lint`**: el bloque de Terraform ahora ejecuta `fmt -check` y
  `init -backend=false && validate` sobre los tres módulos.
  `make cloud-status-gcp` y `make cloud-status-oracle` nuevos, junto al ya
  existente `make cloud-status` (DigitalOcean).

### Añadido — Fase 10, DigitalOcean (proveedor de referencia, opcional)

- **`terraform/digitalocean/`**: módulo Terraform de referencia (una
  Droplet, su llave SSH y un firewall explícito que sólo abre SSH de
  entrada). Un directorio por proveedor a propósito (`terraform/<proveedor>/`,
  no `terraform/` a secas): la Fase 11 (GCP, Oracle Cloud) añadirá
  `terraform/gcp/` y `terraform/oracle/` reutilizando el mismo bootstrap y la
  misma interfaz de CLI, sin mezclar bloques `provider` de proveedores
  distintos. Detalle de cada archivo en `terraform/digitalocean/README.md`.
- **`owner` y `fecha_expiracion` obligatorias, sin valor por defecto**, tanto
  en `variables.tf` (con `validation` en HCL, última barrera si alguien
  invoca Terraform sin pasar por el CLI) como, antes de eso, en
  `lib/cloud.sh` (`exigir_owner_y_ttl`), que da el mensaje en español y
  aborta **antes** de tocar Terraform si faltan. Verificado directamente
  contra el checkout real (son validaciones de argumentos, no operaciones
  destructivas): sin `terraform.tfvars`, sin `owner`, con `owner` igual al
  valor de ejemplo, y sin `fecha_expiracion` — los cuatro casos abortan con
  el mensaje correcto y sin ejecutar Terraform.
- **Bootstrap idempotente por cloud-init**
  (`terraform/digitalocean/templates/cloud-init.yaml.tftpl`): instala Docker
  Engine oficial (si no está ya), crea los volúmenes nombrados si no existen,
  y arranca SecLab como servicio **systemd** (`seclab.service`) que hace
  `docker pull` de `seclab_imagen_ref` (rechazada en `variables.tf` si
  termina en `:latest`: exige digest o tag inmutable) y `docker run` con un
  `docker rm -f` previo tolerante a fallo, para que repetir el bootstrap o
  reiniciar el servicio a mano no falle por "el nombre ya existe". Verificado
  por render real de la plantilla (`terraform templatefile()`, con
  `habilitar_autodestruccion` en `true` y en `false`) más validación YAML
  (`yaml.safe_load`) y ShellCheck de cada bloque `runcmd`; **no probado
  arrancando una Droplet real** (ver `TESTING_GAPS.md`).
- **Estimación de coste y confirmación literal**: `seclab cloud plan|up`
  muestran una tabla de precios aproximados y estáticos de tamaños de
  Droplet (documentada como tal, con enlace al precio real vigente), repiten
  de forma prominente que el gasto es personal del alumno, y `up` exige
  teclear literalmente `acepto` (no una confirmación s/N genérica) antes de
  llamar a `terraform apply`. Sin terminal interactiva, se niega por
  sistema. Verificado contra el checkout real, incluida la ruta sin TTY
  (nunca se auto-aprueba).
- **`seclab cloud plan|up|wait|status|connect|destroy --provider
  digitalocean`**: interfaz nueva en `bin/seclab` (`cmd_cloud`, toda la
  lógica en `lib/cloud.sh` nuevo). `wait` sondea por SSH la marca
  `/etc/seclab-cloud/bootstrap-completo` con timeout configurable y mensaje
  de diagnóstico exacto si se agota. `status` lee `terraform output -json` y
  compara `fecha_expiracion` con la fecha actual, avisando en rojo si ya
  venció. `destroy` ofrece exportar `/workspace` de la Droplet por SSH (mismo
  formato tar que `seclab backup`) antes de `terraform destroy`, con una
  segunda confirmación separada para el borrado.
- **TTL/autodestrucción**: DigitalOcean no ofrece borrado programado nativo
  de Droplets (verificado por lectura de su documentación, no inventado). Por
  defecto, sólo hay recordatorio (`seclab cloud status`), no automatismo. Como
  mecanismo opt-in (`habilitar_autodestruccion`, por defecto `false`), un
  `at` en la propia Droplet puede llamar a `DELETE /v2/droplets/{id}` con un
  token de borrado dedicado — documentado explícitamente como una superficie
  de riesgo (el token vive en la VM mientras ésta exista), no vendido como
  gratis. Detalle completo en `docs/cloud.md`, sección "TTL y
  autodestrucción".
- **Backend remoto**: tipo `s3` declarado sin valores fijos en `versions.tf`
  (config parcial vía `-backend-config`, ver `backend.hcl.example`).
  Documentada la limitación real de DigitalOcean Spaces (sin locking nativo
  equivalente a DynamoDB) y las dos alternativas que sí funcionan: Terraform
  Cloud (recomendada para el curso) o AWS S3 con `dynamodb_table` (Terraform
  < 1.10) o `use_lockfile = true` (Terraform ≥ 1.10). Consecuencia
  documentada: `seclab cloud status` con backend remoto necesita las mismas
  credenciales que `apply` para leer el estado.
- **Secretos fuera del estado**: el `user_data` no lleva ninguna contraseña
  permanente; las credenciales de VNC/code-server/Jupyter de esa instancia
  las genera el propio `docker/entrypoint.sh` en el primer arranque del
  contenedor, igual que en local.
- **`.gitignore`**: patrones de Terraform pasados a `/terraform/**/...` (antes
  sólo cubrían la raíz de `terraform/`, no `terraform/digitalocean/`), con
  negación explícita para los `.example` (`.terraform.lock.hcl` ya se
  versionaba sin necesitar negación: no coincide con ningún patrón de
  exclusión). `scripts/verificar-seguridad.sh` actualizado a juego (su lista
  de patrones exigidos comprobaba el literal antiguo `/terraform/*.tfvars`,
  que dejó de existir). Verificado con `git check-ignore -q` en los cinco
  casos y con `./scripts/verificar-seguridad.sh` sin fallos.
- **`docs/cloud.md`**: flujo completo, advertencia de coste prominente y
  repetida, tabla de precios aproximados, TTL/autodestrucción real, backend
  remoto y su limitación, y qué no hace este módulo a propósito.
- **`make lint`**: nuevo bloque que ejecuta `terraform fmt -check` y
  `terraform init -backend=false && terraform validate` sobre
  `terraform/digitalocean/` (nunca `plan`/`apply`/`destroy`), y limpia el
  `.terraform/` local que genera. Nuevo target `make cloud-status`.

### Añadido — Fase 9, Tailscale

- **`docker-compose.tailscale.yml`**: nodo Tailscale (imagen oficial
  `tailscale/tailscale`, fijada por versión y digest:
  `v1.102.3@sha256:8c42c4574ab066384fcb72f69e086a2ff1dd3652eb6f56856cee34bcf0d2f680`,
  ambos resueltos y confirmados a mano durante esta fase) en su **propio
  contenedor y su propio proyecto de Docker Compose**
  (`${SECLAB_PROJECT}-tailscale`), nunca el de `lab`. Decisión de
  arquitectura (documentada largo en el propio archivo, en
  `docs/tailscale.md` y en `docs/vpn.md`, sección "Convivencia con
  Tailscale"): de las tres rutas que deja abiertas `prompt_v3.md` (nodo en el
  host, `tailscale serve`, o sidecar compartiendo el namespace de red de
  `lab` — esta última explícitamente descartada por el propio prompt), se
  eligió un contenedor dedicado con ciclo de vida **independiente** de
  `lab`: `seclab stop`/`restart`/`update`/`limpiar` nunca lo tocan, sólo
  `seclab tailscale down`. Alcanza los puertos publicados de `lab` por
  `host.docker.internal` (con `extra_hosts: host-gateway` para Linux) en vez
  de compartir la red `seclab`, precisamente para que ninguna operación
  sobre el proyecto de `lab` (que sí borra la red de ese proyecto en cada
  `down`) pueda arrastrar consigo al contenedor de Tailscale.
- **`SECLAB_HABILITAR_TAILSCALE`** (ya existía en `.env.example`, ahora
  con efecto real) gatea la creación del contenedor: en `false` (por
  defecto) no existe en absoluto. **`TAILSCALE_AUTH_KEY`** sigue siendo el
  único punto de entrada real: con la variable vacía, el arranque se niega
  en dos capas — `seclab tailscale up` (CLI, antes de tocar Docker) y el
  propio `command:` del contenedor (red de seguridad para quien invoque
  `docker compose` directamente) — con un mensaje claro en ambos casos,
  nunca "arranca a medias y falla después de forma confusa". Nueva variable
  `SECLAB_TAILSCALE_HOSTNAME` (opcional, por defecto `seclab`).
- **Persistencia de estado**: volumen nombrado dedicado
  `${SECLAB_PROJECT}-tailscale-state` (`/var/lib/tailscale` dentro del
  contenedor, nunca un bind-mount del repositorio). Sobrevive a `seclab
  tailscale down` (que sólo borra el contenedor) y a cualquier recreación:
  verificado escribiendo una marca dentro del volumen y confirmando que
  sigue tras `docker compose down` + `up` (ver "Verificado" en
  `TESTING_GAPS.md`).
- **`lib/docker.sh`**: `compose_tailscale()`, `id_contenedor_tailscale()` y
  `estado_contenedor_tailscale()` — envoltura de Compose independiente de
  `compose_seclab()`, a propósito: nunca comparten función, para que ninguna
  operación sobre `lab` pueda alcanzar por accidente al proyecto de
  Tailscale.
- **`bin/seclab tailscale up|status|down`**, mismo estilo que `seclab vpn`:
  las comprobaciones que no hablan con Docker (flag de habilitación, auth
  key vacía) se hacen primero, con el mensaje exacto de qué falta; el resto
  se delega en Compose. `up` pide confirmación para activar
  `SECLAB_HABILITAR_TAILSCALE` la primera vez, pero a diferencia de `seclab
  vpn up` **no recrea `lab`**: Tailscale vive en un proyecto de Compose
  aparte. `status` nunca imprime la auth key ni ningún secreto, y recuerda
  el comando exacto de `tailscale serve` para publicar un puerto de `lab`
  hacia la tailnet (nunca hacia Internet). Añadidas a `mostrar_ayuda()` (nueva
  sección "ACCESO REMOTO") y al dispatcher de `main()`.
- **`seclab doctor`**: nueva comprobación de convivencia con las VPN de
  plataforma (Fase 7). Con la arquitectura elegida, Tailscale y las VPN de
  `lab` viven en namespaces de red distintos — no hay una tabla de rutas
  compartida que puedan disputarse dentro de Docker —, así que la
  comprobación real no es "¿han chocado?" sino "¿siguen aislados de
  verdad?": confirma que el contenedor `tailscale` no declara
  `network_mode: container:...` ni `service:...`, y si además hay una VPN de
  plataforma activa en `lab` a la vez, lo señala explícitamente como "sin
  conflicto posible" y explica por qué (`--route-nopull` en `lab`,
  `--accept-routes=false` en Tailscale). Documentado también qué caso SÍ
  produciría el conflicto real que describe `prompt_v3.md` (Tailscale y una
  VPN de plataforma, ambos fuera de Docker, en el propio sistema operativo
  del alumno) y por qué queda fuera del alcance de SecLab.
- **`scripts/verificar-seguridad.sh`**: sección 4 ampliada para analizar
  `docker-compose.tailscale.yml` también, por separado (nunca combinado con
  los archivos de `lab`, porque nunca se aplican juntos de verdad):
  configuración válida, sin puertos publicados, sin privilegios ni
  `container_name` fijo.
- **`scripts/ci/probar-tailscale.sh`** y job `tailscale-test` en
  `.github/workflows/ci.yml`: smoke test **sin conexión real** a la red de
  Tailscale (`prompt_v3.md` prohíbe expresamente generar una auth key real).
  Verifica: rechazo sin `TAILSCALE_AUTH_KEY` (por el CLI y, por separado, por
  el propio contenedor sin pasar por el CLI); con una auth key de prueba
  obviamente inválida apuntando a un servidor de control **local e
  inexistente** (`--login-server=http://127.0.0.1:1`, nunca el real
  `controlplane.tailscale.com`) el contenedor sigue vivo reintentando el
  login sin caerse, el rechazo queda en los logs como `connection refused`
  puramente local, y la auth key nunca aparece en ningún log; persistencia
  del volumen de estado tras recrear el contenedor; aislamiento real de red
  y de proyecto de Compose frente a `lab`; y que `lab` arranca con
  normalidad, sin ganar ningún privilegio sólo por tener Tailscale
  habilitado. El detalle de por qué el `--login-server` local (se detectó
  durante el desarrollo de este mismo script que, sin él, una auth key
  inválida igualmente abre una conexión TLS real hacia los servidores de
  Tailscale antes de ser rechazada) está documentado en el propio script y
  en `docs/tailscale.md`.
- **`docs/tailscale.md`** (nuevo): arquitectura elegida y por qué (con las
  dos alternativas descartadas explicadas), flujo paso a paso para crear una
  auth key real (lo hace el profesor/alumno, nunca SecLab), comandos del
  CLI, cómo publicar un servicio de `lab` hacia la tailnet con `tailscale
  serve`, convivencia con VPN de plataforma, y qué verifica el smoke test
  frente a lo que queda sin verificar. `docs/vpn.md`, sección "Convivencia
  con Tailscale", actualizada para enlazarlo y reflejar la implementación
  real en vez del aviso de "todavía no implementado" de la Fase 7.
  `docs/README.md` actualizado (Tailscale pasa de "Pendiente" a la sección
  "Uso").
- **`Makefile`**: nuevos objetivos `tailscale-status`/`tailscale-down`;
  `lint` valida `docker-compose.tailscale.yml` por separado y comprueba la
  sintaxis de `scripts/ci/probar-tailscale.sh`.
- **`.gitignore`**: ya traía `/tailscale-state/` desde la Fase 1 como patrón
  para un eventual bind-mount; revisado y confirmado que no hace falta
  tocarlo — el estado real de esta fase vive en un volumen de Docker
  nombrado, no en un directorio del host, así que ese patrón queda como red
  de seguridad sin uso activo, no como algo que haya que ajustar.

### Añadido — Fase 8, CI/CD y supply chain

- **Dos workflows de GitHub Actions en `.github/workflows/`**: `ci.yml`
  (push a cualquier rama excepto tags, pull requests, y como workflow
  reusable) y `publicar.yml` (sólo con un tag `v*`, o manualmente). Un push
  normal a una rama nunca publica ninguna imagen: eso es literal al
  requisito de `prompt_v3.md` ("Publicación sólo desde tags versionados").
  `publicar.yml` invoca `ci.yml` completo (`uses: ./.github/workflows/ci.yml`)
  como puerta de entrada — si cualquier job de verificación falla, no se
  construye ni se publica nada, igual que ya hace `bin/seclab image publish`
  (`cmd_image_publish`) para una publicación local.
- **Jobs de `ci.yml`**: ShellCheck (`--severity=error`, sobre `bin/seclab`,
  `lib/*.sh`, `scripts/*.sh` incluido `scripts/ci/*.sh`, `docker/*.sh`,
  `docker/shell/*.sh`), Hadolint (`docker/Dockerfile`,
  `--failure-threshold=error`, ignorando `DL3008`/`DL3009` a propósito —
  política de fijado por checksum sólo para herramientas ofensivas, ver
  `docs/politica-herramientas.md`), validación de Compose (los tres overrides
  reales: escritorio, VPN) y de `docker-bake.hcl`, gitleaks (bloqueante),
  terraform fmt/validate (con comportamiento correcto ante la ausencia de
  `terraform/`: no finge validar algo que no existe), `scripts/verificar-
  seguridad.sh`, build + smoke test por perfil (`lite`/`desktop`/`full`, cada
  uno en su propio runner efímero) con escaneo Trivy informativo, y el test
  de VPN automatizado.
- **`scripts/ci/preparar-env.sh`** (ya existente al empezar esta sesión, sólo
  revisado): genera un `.env` de prueba con secretos aleatorios y una llave
  SSH desechable para un checkout efímero de CI. Aborta si ya existe un
  `.env` en el directorio donde corre — ver la nota de seguridad más abajo
  sobre por qué este guardián existe.
- **`scripts/ci/probar-vpn.sh`**: reproduce en CI el procedimiento de la
  Fase 7 contra un servidor OpenVPN de prueba local (arranque de perfil,
  rutas exactas, rechazo por solape, killswitch al caer el túnel). Se
  encontraron y corrigieron tres fallos reales durante la verificación de
  esta fase (no sólo de sintaxis):
  - La red Docker del servidor de prueba usaba el mismo nombre que la red
    que `docker-compose.yml` ya crea para `lab` (`${SECLAB_PROJECT}-net`),
    lo que hacía fallar `docker network create` en silencio (con
    `set -uo pipefail` y sin `-e`). Se documentó que ambos DEBEN compartir
    la misma red (si no, `lab` no podría alcanzar al servidor de prueba por
    su nombre) y se quitó la creación redundante: la red la crea
    `docker compose up`, el script sólo la reutiliza.
  - Varias comprobaciones usaban `comando | grep -q patrón` en vivo: bajo
    `pipefail`, si `grep -q` encuentra la coincidencia y cierra su extremo de
    la tubería antes de que el comando de la izquierda termine de escribir,
    el escritor recibe `SIGPIPE` (código de salida 141) y la comprobación
    daba **FALLO aunque el patrón sí estuviera en la salida** — el mismo
    escollo que ya documentaba `scripts/smoke.sh` con su función
    `contiene()`. Se corrigió capturando la salida primero y aplicando
    `grep` sobre la variable ya capturada, en los tres sitios donde ocurría.
  - La comprobación del killswitch tras detener el servidor de prueba dormía
    un tiempo fijo (22s) y comprobaba una sola vez. Con un servidor OpenVPN
    en modo de clave estática (sin TLS, sin handshake), el cliente no puede
    confirmar que el peer sigue muerto al reconectar: `ping-restart` marca
    el túnel "caído" tras 15s de inactividad, pero se remarca "arriba" un
    par de segundos después con sólo reabrir la interfaz, sin haber
    verificado nada. El túnel queda oscilando entre "arriba" y "caído" cada
    ~15-17s mientras el servidor no vuelva, así que un único punto de
    comprobación a los 22s era una lotería. Se sustituyó por un sondeo
    (hasta 30s, cada 0.5s) que comprueba la ruta en el mismo instante en que
    observa el estado "caído".
- **`bin/seclab image publish`/`image verify`** (`cmd_image_publish`,
  `cmd_image_verify`; ya escritos al empezar esta sesión, revisados y sin
  cambios): publican sólo si pasan el manifiesto de herramientas, la
  revisión de seguridad y los smoke tests; verifican la firma Cosign
  keyless contra `SECLAB_COSIGN_IDENTIDAD_REGEX`/`SECLAB_COSIGN_EMISOR` de
  `.env`, sin fingir una verificación si `cosign` no está instalado.
- **`docs/ci.md`** (nuevo): pipeline completo, qué corre en cada evento,
  política de firma (Cosign keyless con OIDC de GitHub Actions, sin clave
  privada que gestionar), SBOM (Syft, SPDX, adjuntado y firmado con
  `cosign attach sbom`), procedencia (`docker/build-push-action` con
  `provenance: true`), escaneo de imágenes (Trivy: informativo en `ci.yml`,
  bloqueante para `CRITICAL` en `publicar.yml`), y cómo reproducir cada
  verificación en local.
- **`full-msf` nunca se construye ni publica automáticamente**: ni en la
  matriz de `build-test` de `ci.yml` ni en `publicar.yml` con un push de tag
  normal. Se publica sólo con `workflow_dispatch` e `incluir_full_msf: true`
  — la misma filosofía opt-in que ya aplica `docker-bake.hcl` manteniéndolo
  fuera del grupo `todos`.
- **`Makefile`**: `make lint` ahora también ejecuta ShellCheck sobre
  `scripts/ci/*.sh` y, si `hadolint` está instalado, lo ejecuta sobre
  `docker/Dockerfile` (con los mismos umbrales que la CI: `--severity=error`
  y `--failure-threshold=error`, para no bloquear el desarrollo local por
  avisos de estilo preexistentes de fases anteriores — documentado en
  `docs/ci.md`).

### Nota de seguridad: incidente durante el desarrollo de esta fase

Un agente anterior, trabajando en esta misma fase, dañó por accidente el
entorno de desarrollo real (borró el contenedor `seclab-lab-1` y su volumen
`seclab-home` —llaves de host SSH e historial de shell— con un
`docker compose down --volumes`) por un bug de portabilidad
(`sed -i` sin sufijo de backup falla en silencio en macOS/BSD) en un script
de prueba que debía operar sobre una copia aislada del repositorio, pero que
por ese bug no cambió el nombre de proyecto de Docker Compose de esa copia,
que se quedó con el valor por defecto (`seclab`) — el mismo que la instancia
real, que Docker identifica por ese nombre a nivel del propio demonio, no por
directorio. El entorno se recuperó (`seclab start` lo confirmó sano) y el
bug se corrigió: por eso `scripts/ci/preparar-env.sh` usa `escribir_variable`
(basado en `awk`, portátil) en vez de `sed -i`, y por eso aborta
explícitamente si ya existe un `.env` en el directorio donde corre, en vez
de asumir que siempre se invoca sobre un checkout efímero. Esta sesión
verificó todo lo que arranca o detiene contenedores exclusivamente sobre
copias físicas completas en `/tmp`, con nombres de proyecto únicos, y
confirmó antes y después de cada prueba que `seclab-lab-1` no cambiaba de
ID ni de estado (ver `TESTING_GAPS.md`).

### Añadido — Fase 7, VPN autorizada multiperfil

- **La VPN es un atajo dentro del propio contenedor `lab`, no un contenedor
  aparte.** OpenVPN e iptables se instalan en la imagen (todos los perfiles,
  `docker/paquetes-lite.txt`), y un script privilegiado nuevo,
  `/usr/local/bin/seclab-vpn` (`docker/shell/seclab-vpn.sh`), gestiona los
  túneles con root. `docker-compose.vpn.yml` ya no declara servicios propios:
  sólo añade a `lab` `cap_add: NET_ADMIN` y `devices: /dev/net/tun` — nada de
  `network_mode`, nada de namespaces compartidos. `lab` conserva siempre su
  propia red y sus propios puertos, arriba o abajo esté cualquier túnel.
  Decisión del dueño del proyecto: un contenedor de VPN aparte no protegía de
  nada que una interfaz TUN compartida dentro de `lab` no resolviera igual
  —quien comparte la misma VPN de plataforma puede alcanzar por esa interfaz
  a cualquiera que la use, sin que importe en qué contenedor viva—; la
  mitigación real es una regla de firewall sobre la interfaz (ver killswitch
  de entrada, más abajo), no una topología de contenedores distinta.
- **Los tres perfiles pueden estar arriba a la vez de verdad.** Cada uno usa
  su propia interfaz TUN explícita (`tun-htb`, `tun-thm`, `tun-cli`, nunca
  numeradas) y sus propias reglas de iptables. Se eliminó la flag
  `--simultaneo`: el único motivo de rechazo al hacer `seclab vpn up PERFIL`
  es que sus rangos se solapen con los de un perfil ya activo (comprobado con
  el módulo `ipaddress` de Python); si no se solapan, se permite sin más.
  Verificado con los tres perfiles arriba a la vez contra tres servidores
  OpenVPN de prueba locales (ver `TESTING_GAPS.md`).
- **`seclab-vpn up|down|status|routes|logs|activos`** (nuevo,
  `docker/shell/seclab-vpn.sh`, instalado como `/usr/local/bin/seclab-vpn`).
  Lee `vpn/<perfil>/perfil.env` (montado en
  `/etc/seclab/vpn/<perfil>/`, mismo contrato de variables de la Fase 1).
  `up` arranca OpenVPN en segundo plano (PID en `/run/seclab-vpn/<perfil>.pid`,
  log en `/run/seclab-vpn/<perfil>.log`; nunca como PID 1, `lab` tiene muchos
  otros procesos) y espera hasta 60 s a que el gancho `--up`
  (`seclab-vpn-hook`) confirme el túnel arriba. `status` informa, perfil por
  perfil, si está configurado, activo, arriba o caído, con interfaz, IP,
  rangos efectivos y tiempo conectado. Puede invocarse desde el host
  (`seclab vpn ...`, que hace `docker exec -u root lab seclab-vpn ...`) o
  desde dentro de una sesión `seclab shell` con `sudo seclab-vpn ...`.
- **`--route-nopull` real**: el `.ovpn` del alumno se invoca siempre con
  `--route-nopull`, y `seclab-vpn` añade explícitamente sólo las rutas de
  `SECLAB_VPN_RANGOS` (vía `--route`, resolviendo cada CIDR a red+máscara con
  Python). Aceptar la ruta por defecto es un override consciente
  (`SECLAB_VPN_RUTA_DEFECTO=true` en `perfil.env`, hoy sólo en la plantilla de
  `vpncli`), que añade `--redirect-gateway def1`.
- **Killswitch de salida, fail-closed**: por cada perfil activo, `seclab-vpn`
  instala reglas de `iptables` (`DROP` en `OUTPUT`/`FORWARD` hacia sus rangos
  declarados que no salgan por su propia interfaz) **antes** de arrancar
  OpenVPN. Las reglas no dependen del proceso de OpenVPN: si el túnel cae, el
  bloqueo se mantiene. Verificado de verdad contra un servidor OpenVPN de
  prueba, incluida la recuperación tras una caída real (ver `TESTING_GAPS.md`).
- **Killswitch de entrada, nuevo en este diseño**: por cada perfil activo, una
  regla de `INPUT` permite `ESTABLISHED`/`RELATED` en su interfaz y descarta
  cualquier conexión `NEW`. Es la mitigación directa a que "los jugadores en
  la misma VPN de plataforma pueden alcanzar el laboratorio por el túnel":
  nadie puede iniciar una conexión hacia `lab` a través de él, aunque
  comparta la interfaz. Sigue sin ser un filtro de objetivos: es sobre por
  qué interfaz entra una conexión, no sobre a qué IP se conecta el alumno.
  Verificado intentando conectar desde otro contenedor que comparte la
  interfaz del túnel hacia el puerto SSH de `lab`: se bloquea; y que una
  conexión iniciada por `lab` sí recibe respuesta (ver `TESTING_GAPS.md`).
- **`seclab doctor`**: la sección "Red" informa, perfil por perfil, el estado
  real de cada VPN activa (arriba, caído con killswitch activo), consultando
  al contenedor (`docker exec ... seclab-vpn activos`) en vez de leer `.env`.
- **Estado dentro del contenedor, no en `.env`**: con varios perfiles
  pudiendo estar activos a la vez, un único valor como el
  `SECLAB_VPN_PERFIL` de la iteración anterior de esta fase dejó de poder
  representarlo. La fuente de verdad es `/run/seclab-vpn/` dentro de `lab`;
  el host (`seclab vpn list/status`, el banner de bienvenida, `seclab doctor`)
  la consulta con `docker exec`, mismo patrón que ya usaba
  `servicios_activos()` en `lib/docker.sh` para servicios opcionales.
- **Plantillas de la Fase 1** (`templates/vpn/<perfil>/`) sin cambios de
  contrato: `SECLAB_VPN_NOMBRE`, `SECLAB_VPN_CONFIG`, `SECLAB_VPN_RANGOS`,
  `SECLAB_VPN_DNS` (y `SECLAB_VPN_CREDENCIALES`/`SECLAB_VPN_RUTA_DEFECTO` en
  `vpncli`) siguen siendo el contrato que usa `seclab-vpn`.
- **`scripts/verificar-seguridad.sh`**: sigue validando
  `docker-compose.vpn.yml` cuando existe (independientemente de si
  `SECLAB_HABILITAR_VPN` está en `true` o `false` — la revisión analiza lo que
  el archivo *podría* aplicar, no sólo lo que hay activo ahora mismo).
- **`SECLAB_HABILITAR_VPN` (`.env`, por defecto `false`)**: gatea si
  `docker-compose.vpn.yml` se añade a la composición (`compose_seclab`,
  `lib/docker.sh`). En `false`, `lab` no tiene `NET_ADMIN` ni `/dev/net/tun`
  concedidos en absoluto — no hacen falta si no se va a usar ninguna VPN de
  plataforma, y no hay motivo para tenerlas "por si acaso". `seclab vpn up`
  (`bin/seclab`) activa la variable sólo la primera vez que hace falta, con
  confirmación explícita, porque exige recrear `lab` (`compose_seclab up -d
  lab`) para concedérselas — se pierde cualquier shell o proceso abierto
  dentro en ese momento, nunca el directorio personal ni el workspace. Si la
  recreación falla, la variable se revierte a `false` para no dejarla a
  medias. Queda concedida en arranques posteriores hasta que se ponga en
  `false` a mano y se reinicie.
- **Modo auditoría de LAN local, sin conflicto con la VPN**: con el diseño
  actual, `docker-compose.vpn.yml` no toca `network_mode`, así que el bloque
  comentado de `network_mode: host` en `docker-compose.override.yml` y una
  VPN de plataforma activa conviven sin prioridad especial (a diferencia de
  la iteración anterior de esta fase, donde la VPN sí competía por
  `network_mode`). Comprobado con `docker compose config` con ambos overrides
  aplicados a la vez. Documentado en `docs/arquitectura.md`, sección "Modo
  auditoría de LAN local".
- **Integración con `seclab lab create --vpn`**: sin cambios de contrato —
  `avisar_desajuste_vpn` (`lib/labs.sh`) ahora compara contra la lista de
  perfiles activos (`vpn_perfiles_activos()`, `lib/docker.sh`) en vez de un
  único valor de `.env`, para poder decir "ninguno coincide" cuando hay más
  de un perfil arriba a la vez.

### Añadido — Fase 6, workspace de labs y actualización del curso

- **`seclab lab create <nombre>`** crea un directorio bajo el workspace con
  `scope.txt` (el cuaderno de alcance autorizado, no un cortafuegos) y
  `report.md` a partir de plantillas, con las carpetas `recon`, `notes`,
  `loot`, `screenshots` y `exploits` ya creadas. El nombre se valida como slug
  (`^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`, máx. 64) y, si no encaja, se sugiere uno
  quitando acentos y símbolos con normalización NFKD.
- **`seclab lab list`** muestra cada lab con su perfil de VPN declarado en
  `scope.txt`, fecha de creación, número de archivos (sin contar lo archivado)
  y número de rondas de `reset`.
- **`seclab lab reset <nombre>`** archiva el contenido de trabajo en
  `_archivo/<fecha>/` dentro del propio lab, conserva `scope.txt` y regenera
  `report.md` desde cero. Nunca borra nada: todo lo anterior queda accesible
  en el archivo.
- **Aviso de desajuste de VPN**: si el perfil de VPN del lab no coincide con
  ninguno de los conocidos (`vpnhtb`, `vpntry`, `vpncli`), se avisa al crear o
  reiniciar el lab, pero nunca bloquea — la Fase 7 es la que trae las VPN de
  verdad.
- **`seclab shell --lab <nombre>`** entra directamente al directorio del lab
  dentro del contenedor.
- **`seclab update [--stash]`** trae la versión nueva del repositorio del
  curso sin destruir trabajo local. Por defecto se detiene si el árbol está
  sucio y explica cómo seguir; con `--stash` aparta los cambios, hace
  `fetch` + `merge --ff-only` (nunca resuelve una historia divergente por su
  cuenta), muestra el changelog de la versión nueva, reconstruye la imagen del
  perfil activo con la etiqueta correcta y reinicia el laboratorio si estaba
  en marcha. Si el `stash pop` final no puede reaplicarse solo, dice
  exactamente cómo recuperarlo a mano — el stash nunca se pierde.
- **`seclab status`** ahora también lista los labs existentes.

### Añadido — Fase 5, perfiles desktop, full y full-msf

- **Los cuatro perfiles existen y están probados.** `desktop` (2,9 GB) añade
  escritorio XFCE por navegador, code-server y Firefox; `full` (4,3 GB) añade
  web, Active Directory, escalada de privilegios, wordlists y utilidades de
  CTF; `full-msf` (5,7 GB) añade Metasploit y nunca es el perfil por defecto.
  Cada uno parte del anterior, así que la caché se reutiliza y cambiar la
  configuración del curso no obliga a reinstalar XFCE.
- **Escritorio XFCE accesible por navegador.** Xvnc de TigerVNC hace de
  servidor X y de servidor VNC en un solo proceso —la alternativa, Xvfb más
  x11vnc, son dos procesos y dos formas de fallar— y websockify sirve el
  cliente noVNC. El 5901 de VNC **no se publica nunca**: sólo noVNC llega a él,
  desde dentro del contenedor, y Xvnc escucha con `-localhost`.
- **code-server** sobre `/workspace`, con contraseña obligatoria, telemetría
  desactivada y sin comprobación de actualizaciones.
- **Firefox ESR** del tarball oficial de Mozilla. Los paquetes `firefox` y
  `chromium-browser` de Ubuntu son transiciones a snap, y snapd no funciona en
  un contenedor: instalarlos habría dejado un navegador que no arranca.
- **Página de bienvenida local** (`seclab open`), generada en cada arranque a
  partir del estado real: sólo enseña los accesos de los servicios que están
  activos. No contiene ningún secreto —se sirve por HTTP y acabaría en el
  historial del navegador o en el proyector de un aula—, sólo dice dónde
  están.
- **supervisor gestiona los servicios en todos los perfiles**, también en
  `lite` con sólo sshd. Dos caminos de arranque distintos habrían sido dos
  verdades que acabarían discrepando. Dentro del laboratorio, el comando
  `servicios` muestra el estado y permite reiniciar uno solo:
  `servicios restart escritorio-sesion`.
- **Los servicios se activan por perfil.** Una variable `SECLAB_HABILITAR_*`
  vacía significa «lo que traiga el perfil»; con `true` o `false` manda el
  alumno. Elegir `desktop` trae escritorio sin activar tres variables a mano, y
  quien no lo quiera puede apagarlo sin cambiar de perfil.
- **Un servicio activado que el perfil no trae aborta el arranque**, con el
  mensaje de qué perfil usar. Antes se habría quedado `unhealthy` para siempre
  sin explicar por qué. Y **ningún servicio arranca sin su secreto**: no hay
  modo «sin contraseña por esta vez».
- **Los puertos del escritorio se publican en un override aparte**
  (`docker-compose.desktop.yml`), que el CLI aplica sólo cuando el perfil los
  trae. Compose no sabe publicar «si el servicio está activo», y publicarlos
  siempre significaría ocupar tres puertos del portátil del alumno para
  anunciar endpoints que no responden.
- **El healthcheck comprueba endpoints HTTP**, no sólo puertos abiertos: durante
  el arranque de code-server el puerto ya escucha antes de que la aplicación
  responda. Y evalúa exactamente los servicios que el entrypoint declara haber
  levantado, leídos de un archivo que él mismo escribe, en lugar de volver a
  deducirlos de las variables de entorno.
- **`scripts/smoke.sh`: smoke tests por perfil** (`make smoke`). 12
  comprobaciones en `lite`, 28 en `desktop`, 40 en `full` y 43 en `full-msf`:
  salud, login por llave, rechazo del acceso por contraseña, herramientas,
  endpoints, autenticación de code-server con una contraseña incorrecta, tipos
  de seguridad que ofrece Xvnc, que el 5901 no esté publicado, que la sesión
  XFCE tenga gestor de ventanas y panel, y que **ningún secreto de `.env`
  aparezca** en el entorno público ni en la página de bienvenida.
- **Nerd Font (JetBrainsMono) dentro de la imagen** para el perfil `desktop`,
  fijada por versión y checksum. En el escritorio los glifos de la barra de
  tmux se ven siempre; en SSH sigue dependiendo del terminal del alumno, y para
  eso está la variante ASCII de la Fase 3.
- **El manifiesto de herramientas distingue la vía de instalación** con una
  columna nueva: `apt` o `fijada`. Es la información que faltaba para saber de
  un vistazo qué viene del repositorio de Ubuntu y qué de una publicación
  oficial anclada. Se genera de varias listas de paquetes a la vez, porque un
  perfil se construye sobre otro.
- **Herramientas nuevas fijadas por versión y checksum**: code-server 4.135.0,
  Firefox 140.15.0esr, JetBrainsMono Nerd Font v3.5.1, nikto 2.6.1, linPEAS y
  winPEAS 20260901, pspy v1.2.1, cinco listas de SecLists 2026.1 y Metasploit
  6.5.3. El checksum de Metasploit es **el que publica el índice de paquetes de
  Rapid7**, no uno calculado por nosotros.
- **El guardián de capacidades de fichero es ahora un script** que se ejecuta
  en cada etapa que instala paquetes. `desktop`, `full` y `full-msf` añaden
  cientos de binarios, y el invariante —que ninguno reclame una capacidad fuera
  del conjunto del contenedor— hay que comprobarlo donde puede romperse.
- `seclab open` abre la página de bienvenida (con `open`, `xdg-open` o
  `wslview`, y si no hay ninguno imprime la URL). `seclab status` y `start`
  muestran los accesos reales, preguntándoselos al contenedor.
- **`seclab logs [PATRÓN] [--seguir]`** para leer los registros del laboratorio
  y de sus servicios. Los servicios escriben en la salida del contenedor y no
  en archivos dentro de él —así `docker logs` los ve y no crecen en un volumen—,
  de modo que van entremezclados sin prefijo: `seclab logs escritorio` filtra
  los del escritorio. Por el mismo motivo `servicios tail` no sirve, y la
  documentación lo dice en lugar de dejar al alumno delante de un error de
  supervisor.
- Objetivos `desktop`, `full` y `full-msf` en Bake, con sus variantes
  multi-arch, y el grupo `todos` (que **no** incluye `full-msf`).
- Objetivos `make open`, `make smoke` y `make image-todos`.

### Añadido — Fase 5, escritorio usable de verdad

Todo esto salió de usar el escritorio por VNC, que es la única forma de
descubrirlo:

- **La barra superior trae lanzadores de terminal y de Firefox**, que es lo que
  se usa el 90 % del tiempo. Con la configuración por defecto de XFCE había que
  ir al menú de aplicaciones para cada cosa. Un solo panel: XFCE trae además un
  dock inferior con ocultación automática que, en una ventana de navegador,
  aparece cuando no lo esperas.
- **Accesos directos en el escritorio**: terminal, Firefox y un enlace a
  `/workspace`, que es lo primero que busca quien entra por el escritorio. Se
  ocultan los iconos de «Sistema de archivos», papelera y dispositivos
  extraíbles, que en un contenedor no llevan a ninguna parte útil.
- **Firefox tiene entrada de menú.** Venía de un tarball y no traía ninguna, así
  que no aparecía en el menú de aplicaciones de XFCE ni se podía usar como
  lanzador: instalado y con Firefox no era alcanzable sin abrir una terminal.
- **La terminal del escritorio usa la Nerd Font de la imagen.** La fuente por
  defecto (Monospace → DejaVu Sans Mono) no tiene los separadores Powerline, así
  que la barra de estado de tmux salía con cuadros. Se instala la variante
  **Mono** de JetBrainsMono, que es la que dibuja los glifos de icono en una
  celda; la proporcional los pinta a doble ancho y descoloca la barra.
- **Fuente de emoji** (`fonts-noto-color-emoji`): los iconos de la barra de tmux
  son emoji Unicode, que la Nerd Font no cubre. Sin ella salían como cuadros
  aunque los separadores ya se vieran.
- **Escritorio oscuro y coherente** con la terminal y la barra de tmux: tema
  oscuro de GTK y fondo de color plano en lugar del negro por defecto, que
  parecía un fallo.
- **`seclab escritorio restablecer`**: devuelve la barra, la terminal, el tema y
  los accesos directos a la configuración del curso. Hace falta porque XFCE
  reescribe su propia configuración en cuanto arranca —convierte los lanzadores
  en archivos con nombres numéricos—, de modo que un laboratorio ya usado nunca
  vuelve a parecerse a la plantilla y la siembra automática, que respeta lo
  editado, deja de aplicarse. El comando dice qué sobrescribe, pide
  confirmación y reinicia sólo la sesión de escritorio.
- La siembra de configuración del escritorio sigue el criterio de la Fase 3: se
  copia si no existe; se actualiza si el archivo coincide con una versión
  conocida (nadie lo tocó); y se deja como está si el alumno lo ha cambiado.

### Cambiado — Fase 5

- La revisión de seguridad analiza **todos** los archivos de composición que el
  CLI puede aplicar, incluido el override del escritorio. Sin él daba por
  segura una configuración que en el perfil `desktop` publica tres puertos más.
  Verificado en los dos sentidos: con `SECLAB_BIND=0.0.0.0` marca los cuatro.
- `seclab start` detecta un **bucle de reinicios** y muestra la causa en lugar
  de esperar 120 segundos. Con `restart: unless-stopped`, un contenedor cuyo
  entrypoint falla no queda en `exited`: sigue pareciendo `running` mientras se
  reinicia, así que se mira el contador de reinicios. Ahora un error de
  configuración se ve en menos de un segundo, con su mensaje en castellano.
- `.env.example` deja vacías las variables `SECLAB_HABILITAR_*`. **Si vienes de
  una instalación anterior**, tendrán `false` escrito y el perfil `desktop`
  arrancará sin escritorio: vacíalas para que decida el perfil.
- `xz-utils` entra en el perfil `desktop`: la imagen base de Ubuntu no lo trae y
  los tarballs oficiales de Mozilla y de Nerd Fonts vienen en `.tar.xz`. Sin él,
  `tar -xJf` fallaba con un código 2 que no decía nada.

### Corregido — Fase 5

- **La comprobación de nikto en el build era demasiado débil.** nikto imprime
  «Required module not found: XML::Writer» y **sale con código 0**, así que un
  `nikto -Version | head -3` dejaba pasar una instalación que no arrancaba.
  Ahora se exige la cadena de versión y se añade `libxml-writer-perl`, que era
  lo que faltaba. Lo encontraron los smoke tests, no la lectura del código.
- **Dos falsos negativos en los smoke tests, del mismo origen**: con
  `set -o pipefail`, un `comando | grep` da por fallida la comprobación cuando
  el comando termina con código distinto de cero, aunque haya impreso justo lo
  que se buscaba. Le pasaba al rechazo del acceso SSH por contraseña y a
  `msfvenom --help`. Se captura la salida antes de filtrarla, con una función
  (`contiene`) para no repetir el error una tercera vez.
- **GTK 3 no tiene un tema llamado «Adwaita-dark»** —eso es de GTK 4— y al
  ponerlo como nombre de tema, GTK cae al claro sin decir nada: la barra salía
  blanca sobre un escritorio oscuro. El modo oscuro se activa con
  `gtk-application-prefer-dark-theme`, y el «modo oscuro» del panel de XFCE por
  sí solo no basta.
- **msfconsole escribe la versión por stderr**, no por stdout: la comprobación
  la descartaba con `2>/dev/null` y daba por caído un Metasploit que
  funcionaba.
- **`vncpasswd` no está en el servidor de TigerVNC** sino en `tigervnc-tools`.
  Faltaba, y el arranque del escritorio moría con un «command not found» a
  mitad del entrypoint. Ahora el paquete está y el binario se resuelve por sus
  dos nombres posibles, porque Debian y Ubuntu renombran las herramientas de
  TigerVNC y dejan el clásico como alternativa.
- El socket de control de supervisor lleva credenciales aleatorias de cada
  arranque. Sin ellas, supervisor escribía un `CRIT` en cada arranque avisando
  de que no tenía autenticación: un aviso correcto que aparecería siempre y
  acabaría enseñando a ignorar los avisos.

### Añadido — Fase 3, diagnóstico y copias de seguridad

- **`seclab backup`**: copia verificada de `.env`, `secretos/`, `vpn/`, el
  workspace y el volumen del directorio personal. Se puede hacer con el
  laboratorio en marcha. `--sin-workspace` para cuando sólo interesa la
  configuración, `--destino` para escribir fuera de `backups/`.
- El directorio personal viaja como un **tar dentro del tar**, y no como una
  copia de archivos: es lo que conserva propietarios y permisos exactos con
  independencia del sistema de archivos del host, que en macOS y en Windows no
  los representa igual. Ahí viajan también las **llaves de host SSH**, así que
  restaurar una copia no provoca el aviso de cambio de llave.
- **La copia se verifica en cuanto se crea, y si no pasa se borra.** Comprueba
  la suma SHA-256, que el `tar.gz` se puede leer, que dentro están los archivos
  sin los que no se puede restaurar y que el tamaño no delata una copia vacía.
  Una copia que no sirve es peor que no tener copia: se descubre el día que hace
  falta. Verificado en los dos sentidos, incluida una copia incompleta forzada.
- **`seclab backup verify`** repite esa comprobación cuando se quiera —por
  defecto, sobre la más reciente— y **`seclab backup list`** enumera lo que hay.
  SecLab no borra copias antiguas: eso lo decide el alumno.
- **`seclab restore`** con dos modos deliberadamente distintos: `--destino DIR`
  extrae en un directorio nuevo sin tocar la instalación (inspeccionar una
  copia, recuperar un archivo, comprobar que la copia sirve), y sin `--destino`
  restaura sobre esta instalación. El modo en sitio verifica la copia antes de
  nada, exige el laboratorio detenido, pide confirmación y **aparta lo que hay a
  `<nombre>.previo-<fecha>` en lugar de borrarlo**, para que equivocarse de
  copia no sea irreversible. Al terminar asegura los permisos de `.env`,
  `secretos/` y `vpn/`.
- El manifiesto de la copia registra con qué nombre viaja el workspace:
  `SECLAB_WORKSPACE` es configurable y, sin ese dato, restaurar una copia hecha
  cuando el directorio se llamaba de otra forma no encontraría el contenido.
- **`seclab doctor` gana las tres comprobaciones nacidas de fallos reales del
  aula**, todas con la orden correctiva exacta en el mensaje:
  - **Llave de host obsoleta en `known_hosts`.** Compara la huella guardada para
    el puerto configurado con la real del contenedor y, si no coinciden, da el
    `ssh-keygen -R` exacto. Que lo resuelva la herramienta importa: un alumno
    que aprenda a ignorar los avisos de cambio de llave de SSH ha aprendido
    justo lo contrario de lo que se pretende enseñar.
  - **Volumen del directorio personal construido sobre otra imagen base.** El
    entrypoint marca el volumen con el digest de la base la primera vez que lo
    prepara y no vuelve a tocar esa marca —si se actualizara en cada arranque,
    la discrepancia desaparecería justo cuando hay que verla—. `doctor` ofrece
    recrearlo, avisando de que se regeneran las llaves de host y de que el
    workspace no está en ese volumen.
  - **Glifos de la barra de estado.** Imprime una línea con los cuatro
    separadores Powerline y pregunta si se ven; si no, ofrece la variante ASCII,
    la escribe en `.env` y se aplica al reiniciar. No se puede detectar desde
    dentro: depende de la fuente del terminal del alumno.
- **Variante ASCII de la barra de estado** (`SECLAB_GLIFOS=ascii`), generada en
  el build a partir de la configuración del curso para que no puedan divergir.
  El build falla si la sustitución no cambia nada, que sería el aviso de que
  alguna variable de Oh my tmux! ha cambiado de nombre. Cambiar de variante no
  pisa las ediciones del alumno: si su `~/.tmux.conf.local` está modificado, el
  entrypoint no lo toca y le dice qué cuatro líneas cambiar.
- `doctor` acepta `--sin-preguntas` para ser del todo no interactivo, que es
  como lo llama `init` y como lo llamará la CI.
- `seclab init` crea `backups/` con permisos `700`.

### Cambiado — Fase 3

- **El healthcheck habla el protocolo.** Ya no se conforma con que exista el
  proceso y el puerto escuche: abre una conexión al 22 y exige el saludo
  `SSH-2.0-`. Un sshd vivo que no responde es indistinguible de uno sano si sólo
  se mira el pid, y para el alumno la diferencia es total —no puede entrar—. Las
  tres comprobaciones van en cascada para que el motivo del `unhealthy` diga qué
  ha pasado y no sólo que algo va mal.
- La revisión de seguridad comprueba también los permisos de `secretos/` y de
  las copias de `backups/`. Una copia legible por cualquier usuario de la máquina
  entrega el laboratorio completo, y es fácil que pase al moverla.

### Corregido — Fase 3

- **El build fallaba detrás de un proxy.** Las descargas de Oh My Zsh y Oh my
  tmux! usaban las URLs `/archive/` de `github.com`, que responden con un 302
  hacia `codeload.github.com`; a través del proxy de Docker Desktop ese salto se
  quedaba colgado y el build moría a los tres minutos con un «connection timed
  out» que no explicaba nada. Ahora se pide directamente el destino final, con
  reintentos generosos: menos saltos, menos formas de fallar, y el checksum
  sigue garantizando el contenido igual. Un proxy es la norma en la red de una
  universidad, así que esto no era un caso raro.
- **`seclab backup` sin argumentos terminaba en error sin decir nada**: `shift`
  sin argumentos devuelve 1 y, con `set -e`, eso bastaba para abortar. Es el
  tipo de fallo que sólo aparece al ejecutar.
- **`seclab limpiar --con-imagen` moría** si otra instancia de SecLab compartía
  la etiqueta de la imagen, después de haber limpiado todo lo demás. Ahora avisa
  y explica por qué, en lugar de salir con un error de Docker.

### Añadido — Fase 4, experiencia de terminal

- **zsh es el shell por defecto**, con Oh My Zsh y once plugins (`git`, `sudo`,
  `docker`, `tmux`, `extract`, `colored-man-pages`, `command-not-found`,
  `history-substring-search`, `fzf`, `zsh-autosuggestions` y
  `zsh-syntax-highlighting`). Tema `robbyrussell`, sin glifos especiales, para
  que se vea igual de bien en una terminal sin Nerd Font.
- **Oh my tmux!** con la configuración del curso (`templates/shell/tmux.conf.local`),
  tema Tokyo Night y barra de estado con separadores Powerline.
- **Entrada automática en tmux** al abrir sesión interactiva, adjuntando a la
  sesión existente en lugar de crear una nueva, para que un SSH cortado o una
  VPN caída no se lleven el trabajo por delante. Se desactiva con
  `SECLAB_TMUX_AUTO=false`, y si tmux fallara se continúa en un shell normal en
  vez de dejar al alumno fuera.
- **Banner de bienvenida** de cinco líneas, generado del estado real en cada
  arranque y sin ningún secreto.
- **Comando `herramientas`** (alias `tools`): lista las herramientas por
  categoría con su versión, explica una en concreto con su descripción y un
  ejemplo de uso, y busca por nombre o descripción. Se construye a partir del
  manifiesto, así que no puede anunciar algo que no esté instalado.
- Oh My Zsh, sus dos plugins externos y Oh my tmux! se instalan **fijados por
  commit y con checksum verificado**, nunca mediante un instalador remoto sin
  verificar.
- La configuración vive en `/opt/seclab/shell`, dentro de la imagen, y el
  directorio personal sólo guarda punteros. Así una imagen nueva no arranca con
  la configuración de la anterior, que es el problema clásico de los volúmenes
  nombrados.

### Cambiado — Fase 4

- El plan pasa de doce a trece fases. Se inserta la **Fase 4 — Experiencia de
  terminal** (zsh con Oh My Zsh y sus plugins, Oh my tmux! con la configuración
  del curso, entrada automática en tmux, banner de bienvenida y ayuda de las
  herramientas instaladas), y las fases siguientes se desplazan una posición.
- La Fase 3 incorpora tres comprobaciones de `seclab doctor` nacidas de fallos
  reales: llave de host obsoleta en `known_hosts`, volumen de `home` construido
  sobre otra imagen base, y prueba de glifos de la barra de estado. Entregadas
  arriba.

### Corregido — Fase 4

- **sshd no hereda el entorno del contenedor**: el banner mostraba la versión
  como «desconocida» al entrar por SSH, aunque `docker exec` la veía bien. Los
  datos públicos que necesita la sesión se escriben ahora en
  `/etc/seclab/entorno`, que cualquier sesión puede leer.
- **La configuración de tmux no se aplicaba.** Oh my tmux! monta su tema
  ejecutando un script de shell incrustado en sus propios comentarios
  (`cut -c3- "$TMUX_CONF" | sh`), así que `~/.tmux.conf` tiene que ser un enlace
  al archivo real y no un envoltorio que lo cargue con `source-file`: con el
  envoltorio, tmux arrancaba sin errores pero se quedaba con el tema por
  defecto. Fallo silencioso, del peor tipo.
- Se silencia el MOTD de Ubuntu, que competía con el banner y recomendaba
  `unminimize`, cosa que en un contenedor no aplica.
- Se elimina el volumen `seclab-home` heredado de la base anterior, que
  arrastraba `.java`, `.zshrc`, `.zprofile` y un `.bashrc` de Kali al directorio
  personal del usuario de laboratorio.

## [0.2.0] — 2026-09-04

Fase 2: la imagen `lite` y el ciclo de vida local. SecLab ya arranca un
laboratorio utilizable.

### Añadido

- `docker/Dockerfile` multi-etapa (`base` → `lite`) sobre **Ubuntu 26.04 LTS**
  anclada por el digest de su lista de manifiestos, de modo que amd64 y arm64
  resuelven dentro del mismo conjunto verificado.
- Imagen `lite` con shell, tmux, utilidades, red, recon básico (nmap, whatweb,
  dnsutils), Python y acceso SSH. 784 MB en arm64, 49 herramientas en el
  manifiesto.
- `docs/politica-herramientas.md`: por qué Ubuntu LTS y no Kali ni Debian, y el
  reparto en dos vías —apt para sistema y red, publicación oficial con versión
  fijada y checksum para las herramientas de evolución rápida—.
- Manifiesto de herramientas generado durante el build, con la versión real de
  cada paquete y una columna de salvedades por arquitectura. **El build falla si
  un paquete de la lista no figura instalado**: un manifiesto que miente no
  sirve de nada.
- `docker/entrypoint.sh`: valida los secretos y la llave SSH antes de tocar
  nada, prepara el estado persistente, inyecta `authorized_keys` y arranca
  sshd. Aborta con mensaje accionable si falta configuración segura.
- `docker/salud.sh`: healthcheck que evalúa sshd y **sólo** los servicios
  opcionales habilitados, de modo que un servicio apagado nunca puede reportar
  `unhealthy`.
- Llaves de host SSH persistentes en el volumen del laboratorio: reiniciar no
  provoca avisos de cambio de llave.
- `lib/plataforma.sh`: detección de macOS, Linux y Windows/WSL2, arquitectura,
  memoria, disco, `/dev/net/tun` y puertos, con requisitos mínimos por perfil.
- `lib/docker.sh` y `lib/secretos.sh`: envoltura única de Compose, espera de
  healthcheck, generación de secretos y llave SSH dedicada.
- Comandos `seclab init`, `start`, `stop`, `restart`, `status`, `doctor`,
  `shell`, `image build` e `image info`.
- `docker-bake.hcl` con el objetivo `lite` para la arquitectura local y
  `lite-multiarch` para la publicación desde CI.
- Objetivos `image` e `image-info` en el Makefile; `make lint` amplía la
  validación a todos los módulos y a `docker-bake.hcl`.

### Cambiado

- La revisión de seguridad evalúa los secretos **según el servicio al que
  pertenecen**: uno vacío sólo es un fallo si su servicio está habilitado.
  Antes exigía la clave de Tailscale a quien no usa Tailscale, y el ruido acaba
  enseñando a ignorar los avisos.
- SecLab usa una llave SSH dedicada (`secretos/seclab_ed25519`) en lugar de la
  personal del usuario: más predecible en un aula, mantiene el laboratorio
  autocontenido y no mezcla la identidad personal de nadie con un contenedor de
  prácticas.

### Corregido

- **El endurecimiento de la Fase 1 rompía el laboratorio.** `cap_drop: ALL` sin
  añadir nada impedía que el contenedor arrancara siquiera, y
  `no-new-privileges` habría dejado sin efecto tanto `sudo` como nmap. Se
  documenta y se concede el conjunto mínimo verificado de diez capacidades.
- **nmap sin privilegios no podía abrir sockets raw.** El paquete de Ubuntu no
  trae capacidades de fichero, así que fallaba hasta el descubrimiento de hosts.
  La imagen le concede `cap_net_raw` y `cap_net_bind_service`, exactamente las
  dos que el contenedor tiene, y funciona con y sin `sudo` sin necesidad de
  NET_ADMIN.
- **`init` reutilizaba una imagen construida con otra base.** La etiqueta
  (`seclab-lite:0.2.0-local`) no dice nada sobre lo que hay dentro: al cambiar
  la imagen base, una reconstrucción se daba por innecesaria y el alumno habría
  seguido trabajando sobre la base antigua sin enterarse. Ahora `init` y
  `doctor` comparan el digest de la base grabado en la imagen con el que declara
  el Dockerfile, y reconstruyen si difieren.
- El build verifica ahora un invariante que sólo se descubre ejecutando:
  **ningún binario puede reclamar una capacidad fuera del conjunto del
  contenedor**, porque el kernel rechazaría su ejecución por completo. La
  comprobación ya distinguió el caso legítimo (`ping` con `cap_net_raw`) del
  problemático.
- `dnsutils` y `p7zip-full` son paquetes transitorios: el manifiesto no podía
  informar de su versión. Se usan los nombres reales.
- Ubuntu ocupa el UID 1000 con un usuario propio, que impedía crear el del
  laboratorio con ese mismo UID. Se libera durante el build; el UID 1000 importa
  para que los archivos del workspace montado tengan el propietario correcto en
  Linux.

### Cambiado — imagen base

- **Fuera Kali.** La base pasa a Ubuntu 26.04 LTS por decisión del profesorado:
  atarse a Kali significaba depender de sus paquetes para la versión de cada
  herramienta. Se descartó Debian estable, 10 MB más ligera pero un ciclo entero
  por detrás en todo (nmap 7.95 frente a 7.98, y sin `nikto` siquiera). La
  imagen resultante es además 155 MB más pequeña que la anterior.
- `nikto` sale del perfil `lite`: el paquete de Ubuntu es la versión 2.1.5
  frente a la 2.6.1 actual. Llegará en el paquete `web` (Fase 12) desde su
  publicación oficial, que es donde corresponde a un escáner de
  vulnerabilidades web.

### Seguridad

- SSH sólo por llave: sin contraseñas, sin acceso de root, `AuthenticationMethods
  publickey`. Verificado que el acceso por contraseña y el de root se rechazan.
- La cuenta root del contenedor queda bloqueada y las llaves de host de la
  imagen se eliminan en el build, para que ninguna instalación comparta llave.
- `sudo` sin contraseña para el usuario del laboratorio: es deliberado, propio
  de un entorno local de entrenamiento, y está documentado en SECURITY.md.
- `NET_ADMIN` no se concede al contenedor de laboratorio. Pertenece al servicio
  de VPN, en su propio override (Fase 7).

## [0.1.0] — 2026-09-03

Primera fase: estructura base y seguridad. El proyecto todavía no arranca un
laboratorio; establece los cimientos sobre los que se construyen las once fases
restantes.

### Añadido

- Estructura del repositorio: `bin/`, `lib/`, `scripts/`, `docs/`, `templates/`.
- `bin/seclab`, CLI con todos los mensajes en español. Implementa `ayuda`,
  `version` y `seguridad`; el resto de comandos indica en qué fase llega y sale
  con código 3.
- `lib/comun.sh` con utilidades compartidas: mensajería en español, errores con
  causa/impacto/solución, confirmación interactiva que nunca asume que sí, y
  detección de secretos de relleno.
- `scripts/verificar-seguridad.sh` y `scripts/analizar-compose.py`: revisión
  automatizada que comprueba la cobertura de `.gitignore`, archivos sensibles
  versionados, secretos vacíos o de relleno, permisos de `.env` y `vpn/`,
  exposición de puertos fuera de localhost, privilegios elevados,
  `container_name` fijo, montaje del socket de Docker y rastro de claves
  privadas o tokens en los archivos del repositorio.
- `docker-compose.yml` con nombre de proyecto configurable (`SECLAB_PROJECT`),
  `cap_drop: ALL`, `no-new-privileges`, límites de CPU y memoria, y publicación
  de puertos ligada a `127.0.0.1`.
- `docker-compose.override.yml` vacío y comentado para ajustes personales.
- `.env.example` con secretos deliberadamente vacíos y la configuración de los
  tres perfiles de VPN.
- `.gitignore` que cubre secretos, configuraciones de VPN, workspace, estado de
  Terraform y artefactos de lenguajes.
- Plantillas de los perfiles de VPN `vpnhtb`, `vpntry` y `vpncli` en
  `templates/vpn/`, cada una con su procedimiento de descarga del `.ovpn`.
  Las plantillas se versionan; las configuraciones reales, nunca.
- Plantillas de `scope.txt` e informe de laboratorio en `templates/lab/`.
- `Makefile` con atajos que delegan en el CLI, incluido `make lint`.
- Documentación: inicio rápido, requisitos por perfil, diferencias entre macOS,
  Linux y WSL2, uso autorizado y modelo de responsabilidad, VPN multiperfil,
  perfiles y paquetes, resolución de problemas y arquitectura con diagramas
  Mermaid.
- `SECURITY.md`, `TESTING_GAPS.md` y licencia MIT.

### Seguridad

- Ningún servicio se publica fuera de `127.0.0.1` sin un cambio consciente en
  `.env`, y la revisión de seguridad avisa si ocurre.
- Los secretos de `.env.example` se entregan vacíos. Los valores de relleno
  conocidos (`change-this-password`, `changeme`, `admin`…) y los secretos de
  menos de 16 caracteres se rechazan.
- El contenedor de laboratorio arranca con `cap_drop: ALL` y
  `no-new-privileges`. Las capacidades de red las recibirá el servicio de VPN
  en su propio override (Fase 7), nunca el laboratorio.
- Los patrones de directorio de `.gitignore` están anclados a la raíz del
  repositorio. Sin la barra inicial, `vpn/` coincide a cualquier profundidad y
  excluía también `templates/vpn/`, que sí debe versionarse.

[No publicado]: https://example.invalid/seclab/compare/v0.2.0...HEAD
[0.2.0]: https://example.invalid/seclab/compare/v0.1.0...v0.2.0
[0.1.0]: https://example.invalid/seclab/releases/tag/v0.1.0
