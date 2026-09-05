# Módulo Terraform — DigitalOcean (referencia)

Detalle completo del flujo, el coste, el TTL y la responsabilidad económica en
[`docs/cloud.md`](../../docs/cloud.md). Este README es sólo el mapa de archivos.

No ejecutes nada de este directorio a mano salvo que sepas exactamente lo que
implica: `seclab cloud plan|up|destroy --provider digitalocean` es la interfaz
soportada y la que aplica las comprobaciones de coste, `owner` y TTL.

## Archivos

| Archivo | Qué es |
|---|---|
| `versions.tf` | Versión mínima de Terraform y del provider; declara el tipo de backend (`s3`) sin valores fijos |
| `variables.tf` | `owner` y `fecha_expiracion` son obligatorias y sin valor por defecto: un `apply` sin ellas falla en el plan |
| `main.tf` | La Droplet, su llave SSH y un firewall explícito (sólo SSH de entrada) |
| `outputs.tf` | IP, ID, fechas — lo que lee `seclab cloud status/connect/wait` |
| `templates/cloud-init.yaml.tftpl` | Bootstrap idempotente: Docker, pull de la imagen por digest/tag, systemd |
| `terraform.tfvars.example` | Plantilla con valores evidentemente ficticios. Copia a `terraform.tfvars` (fuera de Git) |
| `backend.hcl.example` | Configuración parcial de backend remoto. Ver docs/cloud.md, "Backend remoto" |

## Por qué esta estructura y no `terraform/` a secas

La Fase 11 (GCP, Oracle Cloud) reutiliza el mismo bootstrap cloud-init y la
misma interfaz `seclab cloud`, pero necesita su propio proveedor de Terraform
y sus propios recursos (`terraform/gcp/`, `terraform/oracle/`). Un módulo por
proveedor bajo `terraform/<proveedor>/` evita mezclar bloques `provider` y dos
juegos de variables en un mismo archivo, y permite que `seclab cloud` elija el
directorio de trabajo con `--provider` sin más lógica que un `cd`.
