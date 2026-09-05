# Módulo Terraform — GCP (Fase 11)

Detalle completo del flujo, el coste, el TTL y la responsabilidad económica en
[`docs/cloud.md`](../../docs/cloud.md). Este README es sólo el mapa de archivos.

No ejecutes nada de este directorio a mano salvo que sepas exactamente lo que
implica: `seclab cloud plan|up|destroy --provider gcp` es la interfaz
soportada y la que aplica las comprobaciones de coste, `owner` y TTL.

## Archivos

| Archivo | Qué es |
|---|---|
| `versions.tf` | Versión mínima de Terraform y del provider `google`; declara el tipo de backend (`gcs`, con locking nativo) sin valores fijos |
| `variables.tf` | `owner` y `fecha_expiracion` son obligatorias y sin valor por defecto: un `apply` sin ellas falla en el plan |
| `main.tf` | La instancia, su firewall (sólo SSH de entrada) y el bloque `service_account` condicional para la autodestrucción opcional |
| `outputs.tf` | IP, ID, owner, TTL — lo que lee `seclab cloud status/connect/wait` (sin `creado_en`: ver el comentario en el propio archivo) |
| `templates/cloud-init.yaml.tftpl` | El mismo bootstrap validado en la Fase 10 (DigitalOcean), publicado en la metadata `user-data` en vez de en `user_data` de DigitalOcean |
| `terraform.tfvars.example` | Plantilla con valores evidentemente ficticios. Copia a `terraform.tfvars` (fuera de Git) |
| `backend.hcl.example` | Configuración parcial de backend remoto GCS. Ver docs/cloud.md, "Backend remoto" |

## Por qué reutiliza el bootstrap de DigitalOcean

`templates/cloud-init.yaml.tftpl` es, línea a línea, casi idéntico al de
`terraform/digitalocean/`. La lógica de instalar Docker, traer la imagen por
digest/tag inmutable y arrancarla vía systemd no depende del proveedor cloud:
es la misma lógica de Ubuntu + Docker + systemd en cualquier VM. Lo único que
cambia entre proveedores es CÓMO llega el cloud-init a la máquina (aquí,
metadata `user-data` de GCP, leída por el cloud-init preinstalado en las
imágenes oficiales de Ubuntu de `ubuntu-os-cloud`) y el mecanismo de
autodestrucción opcional (aquí, token de la cuenta de servicio de la propia
instancia; en DigitalOcean, un token de API depositado a propósito).

## Credenciales

GCP no usa un token único como DigitalOcean: el provider `google` se autentica
con **Application Default Credentials** (ADC). `seclab cloud plan/up/destroy
--provider gcp` sólo COMPRUEBA que existe una de estas fuentes (nunca la lee
ni la imprime):

1. Variable de entorno `GOOGLE_APPLICATION_CREDENTIALS` apuntando a un archivo
   existente (clave de cuenta de servicio, JSON).
2. Variable de entorno `GOOGLE_CREDENTIALS` con el contenido de esa clave.
3. El archivo que deja `gcloud auth application-default login`
   (`~/.config/gcloud/application_default_credentials.json`).
4. `credentials_file` en el propio `terraform.tfvars`.
