# Despliegue cloud (opcional, a cargo económico del alumno)

> **Esto es opcional.** El curso se completa entero sin desplegar nada en la
> nube. Si lo haces, lees esto primero: el gasto que genere es **tuyo**, lo
> factura el proveedor que elijas **a ti**, y SecLab no lo gestiona, no lo
> paga y no lo reembolsa. Revisa los términos de servicio y la política de
> precios del proveedor que uses ([DigitalOcean](https://www.digitalocean.com/legal/terms-of-service-agreement) /
> [precios](https://www.digitalocean.com/pricing/droplets),
> [Google Cloud](https://cloud.google.com/terms) /
> [precios](https://cloud.google.com/compute/all-pricing),
> [Oracle Cloud](https://www.oracle.com/legal/terms.html) /
> [precios](https://www.oracle.com/cloud/costestimator.html)) antes de
> escribir `acepto` en `seclab cloud up`.

## Qué es esto y qué no es

Hay un módulo Terraform por proveedor —DigitalOcean (Fase 10, la referencia),
GCP y Oracle Cloud (Fase 11)— y los mismos subcomandos
`seclab cloud <verbo> --provider <digitalocean|gcp|oracle>` para los tres.
Cada uno levanta **una única instancia** con SecLab dentro (la misma imagen
que usas en local, vía Docker), pensada para un laboratorio individual y
temporal: un alumno con una máquina poco potente, o que necesita una IP con
reputación distinta a la de su propia casa para una práctica concreta.

No es: un servicio gestionado por la universidad, una alternativa permanente
al uso local, ni algo que SecLab supervise por ti una vez creado. Tú decides
cuándo se crea, tú decides cuándo se destruye, y tú vigilas mientras tanto.

## Comparación rápida de los tres proveedores

| | DigitalOcean | GCP | Oracle Cloud |
|---|---|---|---|
| Módulo | `terraform/digitalocean/` | `terraform/gcp/` | `terraform/oracle/` |
| Recurso principal | `digitalocean_droplet` | `google_compute_instance` | `oci_core_instance` |
| Red por defecto | Sí (una por Droplet) | Sí (`default` del proyecto) | No: el módulo crea su propia VCN/subred |
| Bootstrap | cloud-init vía `user_data` | cloud-init vía metadata `user-data` (imagen `ubuntu-os-cloud` la soporta) | cloud-init vía metadata `user_data` en base64 (datasource "OracleCloud") |
| Autenticación | Token único (`DIGITALOCEAN_TOKEN`) | Application Default Credentials | Clave de API clásica (tenancy/user/fingerprint/clave privada) |
| Usuario SSH | `root` | El de `ssh_username` (por defecto `seclab`) | `ubuntu` |
| Backend remoto recomendado | Terraform Cloud (Spaces no tiene locking nativo) | GCS (locking nativo) | Terraform Cloud (Object Storage tampoco tiene locking nativo) |
| Autodestrucción opt-in | `at` + token de API dedicado en disco | `at` + identidad de la propia cuenta de servicio (sin token en disco) | `at` + `oci-cli` con instance principal (sin token en disco, pero exige política de identidad fuera de Terraform) |
| Free tier relevante | No | No (créditos de nueva cuenta, no permanentes) | Sí: formas Ampere A1.Flex y E2.1.Micro "Always Free" — límites sujetos a cambio, ver más abajo |
| Coste aproximado del tamaño por defecto | `s-2vcpu-4gb` ≈ \$24/mes | `e2-medium` ≈ \$24/mes | `VM.Standard.A1.Flex` (2 OCPU/12GB) ≈ \$0 dentro del Always Free |

Todos comparten la misma interfaz operativa (`plan|up|wait|status|connect|
destroy`), la misma exigencia de `owner`/`fecha_expiracion`, la misma
confirmación literal de coste, y el mismo bootstrap de fondo (Docker +
systemd) heredado de la Fase 10 — ver `lib/cloud.sh` para la parte común y
cada `terraform/<proveedor>/README.md` para el detalle específico.

## Flujo completo (ejemplo con DigitalOcean; igual para `gcp`/`oracle`, sólo cambia `--provider` y el `.tfvars`)

```
seclab cloud plan    --provider digitalocean   # estimación de coste + terraform plan
seclab cloud up      --provider digitalocean   # exige owner/TTL y escribir 'acepto'; terraform apply
seclab cloud wait    --provider digitalocean   # espera a que el bootstrap termine
seclab cloud connect --provider digitalocean   # SSH a la instancia
seclab cloud status  --provider digitalocean   # qué hay activo, desde cuándo, y el recordatorio de destroy
seclab cloud destroy --provider digitalocean   # exporta workspace (opcional) y borra todo
```

### 1. Prepara las variables

```
cp terraform/digitalocean/terraform.tfvars.example terraform/digitalocean/terraform.tfvars
```

Rellena **todos** los valores del archivo, en particular:

- `do_token` — tu token de API de DigitalOcean (o dejarlo vacío y usar la
  variable de entorno `DIGITALOCEAN_TOKEN`, preferible: un `.tfvars` puede
  acabar copiado o adjuntado a un correo con más facilidad que una variable
  de shell).
- `owner` — tu nombre o usuario del curso. **Obligatorio**: `seclab cloud
  plan/up` se niegan a continuar si falta o si sigue con el valor de
  ejemplo `tu-nombre-aqui`.
- `fecha_expiracion` — cuándo debería dejar de existir esta Droplet
  (`AAAA-MM-DD`). **Obligatorio** por el mismo motivo.
- `ssh_public_key` — la parte pública de una llave dedicada a esto (no la
  personal con acceso a otros sistemas).
- `seclab_registry` / `seclab_imagen_ref` — de dónde viene la imagen. Nunca
  `:latest`: usa un digest (`@sha256:...`) o un tag de versión inmutable (ver
  `seclab image publish`, Fase 8). Una Droplet que se recrea meses después de
  que el TTL original venciera no debe traer una imagen distinta de la que
  probaste.

`terraform.tfvars` está en `.gitignore` (patrón `/terraform/**/*.tfvars`):
nunca lo subas a Git.

### 2. Estimación de coste y plan

```
seclab cloud plan --provider digitalocean
```

Muestra una tabla de precios aproximados (ver más abajo), el tamaño
configurado, y ejecuta `terraform init` + `terraform plan` de verdad. Esto
**sí** contacta la API de DigitalOcean (para leer el catálogo de imágenes,
validar la región, etc.): necesita credenciales válidas.

### 3. Aplicar (esto crea infraestructura real y factura)

```
seclab cloud up --provider digitalocean
```

Antes de tocar Terraform, `seclab cloud up`:

1. Exige que `owner` y `fecha_expiracion` estén rellenos en el `.tfvars`
   (si falta cualquiera de los dos, **aborta sin aplicar nada**).
2. Muestra la tabla de coste aproximado y el tamaño configurado.
3. Repite, de forma prominente, que el gasto es tuyo.
4. Exige que teclees literalmente `acepto` (no `s`, no `sí`: la palabra
   completa). Cualquier otra cosa cancela sin tocar nada. Sin terminal
   interactiva, se niega por sistema — nunca se auto-aprueba.

Sólo entonces ejecuta `terraform apply`.

### 4. Esperar el bootstrap

```
seclab cloud wait --provider digitalocean
```

El `user_data` (cloud-init, ver `terraform/digitalocean/templates/cloud-init.yaml.tftpl`)
instala Docker, trae la imagen configurada y arranca un servicio systemd
llamado `seclab`. `seclab cloud wait` hace SSH periódicamente y comprueba la
marca `/etc/seclab-cloud/bootstrap-completo`, con un timeout configurable
(`--timeout SEGUNDOS`, 600 por defecto). Si se agota, te da el comando SSH
exacto para diagnosticarlo a mano (`cloud-init status`, `journalctl -u
seclab`).

### 5. Conectar

```
seclab cloud connect --provider digitalocean
```

Abre una sesión SSH a la Droplet. **Los servicios web del contenedor
(bienvenida, noVNC, code-server, Jupyter) siguen ligados a `127.0.0.1` DENTRO
de la Droplet** — el mismo valor por defecto que en local (`SECLAB_BIND`).
La única vía de entrada que el firewall de DigitalOcean permite es SSH; para
llegar a un servicio web hace falta un túnel:

```
ssh -i secretos/seclab_ed25519 -p 2222 -L 8080:127.0.0.1:8080 root@TU_IP
```

`seclab cloud connect` imprime el comando exacto con tu IP real.

### 6. Destruir

```
seclab cloud destroy --provider digitalocean
```

Antes de `terraform destroy`, ofrece exportar `/workspace` de la Droplet (vía
SSH, con el mismo formato tar que usa `seclab backup`) a tu directorio local
de copias — **es la única oportunidad**: una vez destruida la Droplet, ese
disco ya no existe en ningún sitio. Pide una segunda confirmación explícita
antes de borrar.

## Estimación de coste (aproximada — LÉELO)

La tabla que muestran `seclab cloud plan` y `seclab cloud up` es **estática**,
no una consulta en vivo a la API de precios de DigitalOcean:

| Tamaño (slug)  | vCPU | RAM  | USD/mes (aprox.) | USD/hora (aprox.) |
|---|---|---|---|---|
| `s-1vcpu-1gb`  | 1 | 1 GB | \$6  | \$0.009 |
| `s-1vcpu-2gb`  | 1 | 2 GB | \$12 | \$0.018 |
| `s-2vcpu-2gb`  | 2 | 2 GB | \$18 | \$0.027 |
| `s-2vcpu-4gb`  | 2 | 4 GB | \$24 | \$0.036 |
| `s-4vcpu-8gb`  | 4 | 8 GB | \$48 | \$0.071 |

Son los precios públicos de Droplets básicos compartidos al escribir esto:
**sujetos a cambio sin aviso**. No incluyen almacenamiento en bloque
adicional, snapshots, IP flotante de repuesto, ni tráfico de salida por
encima de la franquicia incluida. Antes de aplicar, comprueba el precio real
vigente en <https://www.digitalocean.com/pricing/droplets>.

## TTL y autodestrucción

**DigitalOcean no ofrece borrado programado nativo de Droplets** (no hay un
campo "bórrate el día X" en la API de Droplets). Esto no es una limitación de
SecLab que se pueda rodear con más código: es lo que hay. Dos mecanismos,
con expectativas distintas:

1. **Por defecto — recordatorio, no automatismo.** `fecha_expiracion` se
   guarda como etiqueta de la Droplet y como salida de Terraform.
   `seclab cloud status` la lee, calcula si ya venció, y si es así te lo dice
   en rojo con el comando de `destroy` a mano. **No borra nada por ti.**
   Sigue siendo tu responsabilidad destruirla a tiempo.

2. **Opt-in — autodestrucción real desde la propia VM.** El módulo acepta
   `habilitar_autodestruccion = true` (por defecto `false`). Si lo activas,
   el cloud-init programa un `at` en la Droplet que, al llegar la fecha,
   llama a `DELETE /v2/droplets/{id}` de la API de DigitalOcean usando un
   token que tú le das (`do_token_autodestruccion`, un token **distinto** de
   `do_token`, que sólo debería poder borrar, no crear ni listar todo lo
   demás de tu cuenta). Esto SÍ borra la Droplet aunque te olvides.

   **El precio de esa comodidad**: ese token vive en texto plano dentro de
   `/etc/seclab-cloud/autodestruccion.env` en la propia Droplet mientras
   exista. Es una superficie de riesgo real (cualquiera con acceso root a esa
   VM lo lee), y por eso está desactivado por defecto y documentado así de
   explícito en vez de vendido como gratis. Si lo usas: que el token sea de
   un solo propósito (borrar esa Droplet), revócalo en el panel de
   DigitalOcean en cuanto la destruyas por el camino normal, y no reutilices
   el mismo token en dos laboratorios.

   Apagar la Droplet (`shutdown`) **no** detiene el gasto: DigitalOcean
   factura mientras el recurso exista, esté encendido o apagado. Sólo
   destruirla (`terraform destroy` / la llamada `DELETE` de arriba) lo hace.

### TTL y autodestrucción — GCP y Oracle Cloud

Mismo esquema (recordatorio por defecto, autodestrucción opt-in), con una
diferencia real a favor de estos dos proveedores: ninguno necesita depositar
un token estático de API en la VM.

- **GCP**: la instancia usa su propia identidad de cuenta de servicio
  (servida por el servidor de metadata, de corta vida, nunca escrita a
  disco) para llamar a `compute.instances.delete` sobre sí misma. Exige que
  la cuenta de servicio adjunta tenga scope `compute` (el módulo lo añade
  automáticamente sólo si `habilitar_autodestruccion = true`, ver
  `terraform/gcp/main.tf`) **y** un rol IAM de borrado concedido fuera de
  este módulo por un administrador del proyecto.
- **Oracle Cloud**: la instancia se autentica como "instance principal"
  (identidad firmada entregada por el servidor de metadata de OCI) y llama a
  `oci compute instance terminate` sobre sí misma. Exige que la tenancy tenga
  configurado, de antemano y fuera de Terraform, un Dynamic Group que incluya
  la instancia y una Policy que le permita terminarse — algo que una cuenta
  de estudiante normal no siempre puede configurar por sí misma (suele
  requerir privilegios de administrador de tenancy). Si esa política no
  existe, el mecanismo simplemente falla al llegar la fecha: la instancia
  sigue existiendo y facturando, y `seclab cloud status` lo sigue
  recordando en rojo — el mismo resultado que no haberlo activado.

En los tres casos, apagar la instancia **no** detiene el gasto del proveedor
correspondiente; sólo destruirla lo hace.

## Backend remoto por proveedor

Resumen de lo que ya explica cada `versions.tf`/`backend.hcl.example`:

- **DigitalOcean**: Spaces (S3-compatible) **no** tiene locking nativo. Se
  recomienda Terraform Cloud; alternativa, S3 real + DynamoDB o
  `use_lockfile` (Terraform ≥ 1.10).
- **GCP**: el backend `"gcs"` **sí** tiene locking nativo (precondiciones de
  generación de objeto de Google Cloud Storage) — no hace falta ningún
  servicio adicional. Es el único de los tres que resuelve el locking sin
  depender de Terraform Cloud ni de una tabla externa.
- **Oracle Cloud**: **por defecto usa backend local** (decisión explícita
  para uso personal, un solo operador — ver `terraform/oracle/versions.tf`):
  el `.tfstate` vive en `terraform/oracle/terraform.tfstate`, fuera de Git,
  sin locking. Si más adelante hay varias personas aplicando cambios a la
  vez, Object Storage expone una API de compatibilidad S3 pero, igual que
  DigitalOcean, sin locking nativo equivalente a DynamoDB — la alternativa
  documentada sigue siendo Terraform Cloud (ver `backend.hcl.example` para
  migrar).

Detalle completo de cada uno en `terraform/digitalocean/versions.tf`,
`terraform/gcp/versions.tf` y `terraform/oracle/versions.tf`.

## Backend remoto: por qué no DigitalOcean Spaces a secas

El estado de Terraform (`terraform.tfstate`) contiene, en texto plano, cosas
como la IP de la Droplet y puede llegar a incluir valores sensibles según qué
recursos se añadan. Un backend remoto con **locking** evita que dos `apply`
simultáneos (dos terminales tuyas, o dos alumnos con el mismo estado por
error) corrompan ese archivo.

**DigitalOcean Spaces expone una API compatible con S3 para objetos, pero
DigitalOcean no ofrece un servicio de locking equivalente a DynamoDB.**
Guardar el `.tfstate` en Spaces sin más es guardar el archivo, no resolver el
locking. Por eso el backend de este módulo se declara como tipo `s3`
genérico (ver `terraform/digitalocean/versions.tf`) con la configuración real
fuera de Git (`-backend-config`, ver `backend.hcl.example`), y se documentan
dos alternativas reales, no una que aparente funcionar y no lo haga:

1. **Recomendada para este curso: Terraform Cloud / HCP Terraform.** Backend
   `"cloud"`. Locking y cifrado en reposo gestionados por HashiCorp, capa
   gratuita suficiente para un alumno individual. Es la que documentamos
   porque no exige montar ni pagar un segundo servicio (DynamoDB) sólo para
   el locking de un laboratorio de clase.
2. **AWS S3 + DynamoDB** (o cualquier S3 real, no Spaces). El backend `s3`
   soporta locking nativo mediante una tabla DynamoDB dedicada
   (`dynamodb_table`) en versiones de Terraform anteriores a la 1.10, o
   mediante `use_lockfile = true` (locking nativo de S3, sin tabla) en
   Terraform ≥ 1.10.

**Limitación real, no un rodeo**: con backend remoto, `seclab cloud status`
(que hace `terraform output -json`) necesita las mismas credenciales que
`apply` para leer el estado. Sin ellas, `status` no puede decirte nada —
avisa de esto explícitamente en vez de fingir un "no hay nada desplegado".

## Secretos: qué no viaja en el user-data

El `user_data` (cloud-init) que ve la API de DigitalOcean **no contiene
ninguna contraseña permanente**. Las contraseñas de VNC/code-server/Jupyter
de esa instancia concreta las genera el propio contenedor en su primer
arranque — el mismo `docker/entrypoint.sh` que usas en local — y sólo viven
en el volumen de datos de la Droplet, nunca en el estado de Terraform ni en
los logs de cloud-init. Para verlas: `seclab cloud connect`, y desde dentro
lo mismo que harías en local (`seclab status` dentro del contenedor, o
mirando el volumen).

La única credencial que SÍ viaja en el `user_data` es el token de
autodestrucción opcional (ver arriba), y sólo si activas ese mecanismo.

## Snapshot antes de destruir

`seclab cloud destroy` ofrece exportar `/workspace` de la Droplet (recon,
notas, evidencias) a tu directorio de copias local antes de borrar nada,
reutilizando el mismo formato tar que `seclab backup`. No es una copia
completa al estilo `seclab backup` (esa incluye `.env`, `secretos/` y `vpn/`,
que son locales y nunca viven en la Droplet): es sólo el workspace remoto.
Acéptalo salvo que ya tengas ese trabajo replicado en otro sitio: una vez
destruida la Droplet, el disco no existe en ningún backup de DigitalOcean
que SecLab pueda recuperar por ti.

## Qué NO hace este módulo (a propósito)

- No valida ni bloquea contra qué objetivo usas la instancia una vez
  arrancada: el modelo de responsabilidad es el mismo que en local (ver
  [uso-autorizado.md](uso-autorizado.md)).
- No gestiona presupuestos, alertas de gasto ni límites de cuenta: eso lo
  configuras tú en el panel de DigitalOcean (Billing → Alerts) si quieres esa
  red de seguridad adicional.
- No reintenta un `apply` fallido a medias por ti: si `terraform apply` o
  `destroy` fallan, el mensaje te manda a `seclab cloud status` para ver qué
  quedó a medio camino, no finge haberlo arreglado.

## GCP: notas específicas

- **Autenticación**: Application Default Credentials, no un token único. Ver
  `terraform/gcp/README.md`, sección "Credenciales", para las cuatro fuentes
  que `seclab cloud` comprueba (nunca lee su contenido).
- **Imagen de SO**: por familia (`ubuntu-os-cloud/ubuntu-2204-lts`), no por
  digest — a diferencia del Dockerfile de SecLab (que sí ancla por digest),
  GCP no expone un digest estable de imagen de SO de la misma forma que un
  registry OCI. Documentado como asimetría real, no oculta.
- **`seclab cloud status` no muestra "Creado"** para GCP: el recurso
  `google_compute_instance` no expone de forma fiable un atributo de marca de
  creación equivalente al `created_at` de la API de DigitalOcean en todas las
  versiones del provider, y se prefirió omitir la salida a inventar un valor
  aproximado. Ver el comentario en `terraform/gcp/outputs.tf`.
- **Firewall**: `google_compute_firewall` con `target_tags = ["seclab"]`,
  igual de acotado que en DigitalOcean (sólo el puerto SSH configurado).

## Oracle Cloud: notas específicas

- **Autenticación**: clave de API clásica
  (`tenancy_ocid`/`user_ocid`/`fingerprint`/`private_key_path`). SecLab
  **nunca** comprueba `~/.oci/config` por defecto, a propósito — ver
  `terraform/oracle/README.md`, sección "Autenticación".
- **Red propia**: a diferencia de DigitalOcean y GCP, OCI no ofrece una red
  por defecto en un tenancy nuevo. El módulo crea su propia VCN, subred,
  gateway de Internet, tabla de rutas y lista de seguridad (sólo SSH de
  entrada) para seguir siendo autocontenido.
- **`image_ocid` no tiene valor por defecto**: las imágenes de OCI son
  específicas de región y tenancy, no globales. Hay que resolverlo con `oci
  compute image list` antes del primer `plan` — comando exacto en
  `terraform/oracle/README.md`.
- **Always Free tier**: las formas `VM.Standard.A1.Flex` (Ampere ARM, hasta
  4 OCPU/24 GB en total por tenancy al escribir esto) y
  `VM.Standard.E2.1.Micro` pueden desplegarse sin coste dentro de esos
  límites. **No lo des por garantizado**: los límites y la disponibilidad del
  free tier los fija y cambia Oracle, no SecLab — comprueba la página oficial
  vigente antes de asumir gasto cero.
- **"Out of host capacity" no es un problema de tu cuota**: `oci limits
  resource-availability get` puede mostrar cupo de sobra (cuota asignada a tu
  tenancy) mientras el `apply` sigue fallando — son dos cosas distintas. La
  cuota es tuya; la capacidad física del datacenter no la expone ninguna API
  pública, sólo se descubre intentando lanzar de verdad. Si una forma falla,
  antes de darla por perdida prueba otra generación de la misma familia (por
  ejemplo `VM.Standard.E5.Flex` si `E4.Flex` falla) — ver
  `terraform/oracle/README.md`, "Si tu región no tiene capacidad ARM
  disponible".
- **`ssh_user` es el usuario DENTRO del contenedor** (`"seclab"` por
  defecto), no el `"ubuntu"` de la VM anfitriona: `puerto_ssh` (2222 por
  defecto) se publica desde el `docker run` del contenedor, así que
  `seclab cloud connect`/`wait` llegan ahí, no al host. Para entrar al host
  (diagnóstico, sin depender de Docker) usa `ssh -i <llave> ubuntu@<ip>`
  directo al puerto 22 — sólo alcanzable mientras `cerrar_ssh_publico` sea
  `false` (ver más abajo).
- **Escritorio y code-server del contenedor** funcionan igual que en local:
  `seclab init` genera `SECLAB_OCI_VNC_PASSWORD`/`SECLAB_OCI_CODE_PASSWORD`
  en `.env` (mismo mecanismo que sus equivalentes locales, mismas reglas de
  `es_secreto_inseguro`), y `sincronizar_tfvars_oracle_desde_env` los pasa a
  Terraform. `terraform/oracle` ya no genera secretos por su cuenta
  (`random_password`, descartado): `.env` es la fuente real, Terraform sólo
  los lee y los inyecta al contenedor por `--env-file`.
- **Escritorio del HOST (XFCE + xrdp), opt-in y aparte** del escritorio del
  contenedor: `SECLAB_OCI_HABILITAR_ESCRITORIO_HOST=true` instala un
  escritorio real en la VM Ubuntu misma (fuera de Docker), pensado para
  configurar el host directamente, no para el trabajo normal de
  laboratorio — instala paquetes reales y usa RAM/CPU de más. RDP exige una
  contraseña real de sistema para `ubuntu` (`SECLAB_OCI_RDP_PASSWORD`,
  también generada por `seclab init`); el puerto 3389 sigue la misma regla
  de dos pasos que el SSH del host (`cerrar_ssh_publico`) y también se
  publica por Tailscale.

## Habilitar Tailscale sin quedarte fuera

Activar Tailscale y cerrar el SSH público **no es un solo interruptor**: son
dos variables deliberadamente separadas (`habilitar_tailscale` y
`cerrar_ssh_publico`, ver `terraform/oracle/variables.tf`), precisamente
porque si Tailscale no llegara a conectar, cerrar el SSH público en el mismo
`apply` que lo activa dejaría la instancia inalcanzable sin ninguna forma de
diagnosticar por qué.

**Flujo correcto, en dos pasos:**

1. `SECLAB_OCI_HABILITAR_TAILSCALE=true`, `SECLAB_OCI_CERRAR_SSH_PUBLICO=false`
   (o sin declarar, el default). `seclab cloud up --provider oracle`. La
   instancia queda con IP pública, SSH abierto en **dos** puertos — el 22
   del host (vía de rescate, no depende de Docker) y `puerto_ssh`/2222 del
   contenedor — y Tailscale corriendo en paralelo.
2. Verifica que Tailscale conecta de verdad:
   ```
   ssh -i secretos/seclab_ed25519 -p 2222 seclab@<tailscale_hostname>
   ```
   (o el hostname que hayas puesto en `SECLAB_OCI_TAILSCALE_HOSTNAME`, MagicDNS
   de tu tailnet). Si conecta, sólo entonces:
3. `SECLAB_OCI_CERRAR_SSH_PUBLICO=true`, `seclab cloud plan/up --provider
   oracle` de nuevo. Esto **no recrea la instancia**, sólo la red — pierde la
   IP pública, cierra el SSH público, y la salida a Internet la sigue dando
   un NAT Gateway. Si algo falla más adelante, revertir
   (`cerrar_ssh_publico = false` y volver a aplicar) recupera el acceso
   público sin reconstruir nada.

**Configura tu auth key así para no repetir esto cada vez** (una sola vez,
en la consola de Tailscale, no en este repositorio):

1. En https://login.tailscale.com/admin/acls/file, descomenta y define un
   tag:
   ```json
   "tagOwners": {
       "tag:seclab": ["autogroup:admin"]
   },
   ```
   Guarda. Esto es de una sola vez para tu tailnet — no hay que repetirlo por
   despliegue.
2. En https://login.tailscale.com/admin/settings/keys, genera una auth key
   con **Reusable** activado y **Tags** → `tag:seclab` seleccionado. Sin el
   tag, la key sigue siendo válida, pero cada nodo que se una con ella
   heredará el vencimiento de "node key" por defecto de tu tailnet (~180
   días en el plan gratuito) y tendrás que reautenticarlo manualmente pasado
   ese plazo; con el tag, los nodos quedan exentos de ese vencimiento
   automáticamente.
3. Esa key (`Reusable` + `tag:seclab`) sirve para **todas** las próximas
   recreaciones de la instancia sin generar una nueva — hasta que expire (máx.
   90 días, límite del propio Tailscale, no configurable). Una key **sin**
   `Reusable` se consume con el primer nodo que la usa: cualquier recreación
   posterior de la instancia fallará con `invalid key` hasta que generes una
   nueva.

## Referencia rápida de archivos

| Archivo | Qué hace |
|---|---|
| `lib/cloud.sh` | Toda la lógica común de `seclab cloud` para los tres proveedores: validación de owner/TTL, tabla de coste por proveedor, confirmación literal, llamadas a Terraform, comprobación de credenciales (una función `exigir_credenciales_<proveedor>` por proveedor) |
| `terraform/digitalocean/` | Módulo de referencia (Fase 10). Ver su `README.md` |
| `terraform/gcp/` | Módulo GCP (Fase 11). Ver su `README.md` |
| `terraform/oracle/` | Módulo Oracle Cloud (Fase 11). Ver su `README.md` |
| `terraform/<proveedor>/terraform.tfvars.example` | Plantilla con valores evidentemente ficticios, una por proveedor |
| `terraform/<proveedor>/backend.hcl.example` | Configuración parcial de backend remoto, una por proveedor, cada una con la explicación de las diferencias reales de locking |
