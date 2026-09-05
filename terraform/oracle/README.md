# Módulo Terraform — Oracle Cloud / OCI (Fase 11)

Detalle completo del flujo, el coste, el TTL y la responsabilidad económica en
[`docs/cloud.md`](../../docs/cloud.md). Este README es sólo el mapa de archivos.

No ejecutes nada de este directorio a mano salvo que sepas exactamente lo que
implica: `seclab cloud plan|up|destroy --provider oracle` es la interfaz
soportada y la que aplica las comprobaciones de coste, `owner` y TTL.

## Archivos

| Archivo | Qué es |
|---|---|
| `versions.tf` | Versión mínima de Terraform y del provider `oci`; declara el tipo de backend (`s3`, compatible con OCI Object Storage, sin locking nativo) |
| `variables.tf` | `owner` y `fecha_expiracion` obligatorias; autenticación por clave de API clásica, nunca `~/.oci/config` implícito |
| `main.tf` | VCN + subred + lista de seguridad (sólo SSH de entrada) + la instancia — este módulo, a diferencia de DigitalOcean y GCP, crea su propia red mínima porque OCI no ofrece una red "default" |
| `outputs.tf` | IP, OCID, owner, TTL, `time_created` — lo que lee `seclab cloud status/connect/wait` |
| `templates/cloud-init.yaml.tftpl` | El mismo bootstrap validado en la Fase 10, publicado en la metadata `user_data` (base64, datasource "OracleCloud" de cloud-init) |
| `terraform.tfvars.example` | Plantilla con valores evidentemente ficticios. Copia a `terraform.tfvars` (fuera de Git) |
| `backend.hcl.example` | Configuración parcial de backend remoto S3-compatible. Ver docs/cloud.md, "Backend remoto" |

## Resolver `image_ocid` para tu región

Las imágenes de OCI no son globales (a diferencia de las de GCP): hay que
resolver el OCID exacto para la región donde despliegues. Con el CLI de OCI
ya autenticado:

```
oci compute image list \
  --compartment-id <tu-tenancy-ocid> \
  --operating-system "Canonical Ubuntu" \
  --operating-system-version "22.04" \
  --shape "VM.Standard.A1.Flex" \
  --query "data[0].id" --raw-output
```

O desde la consola web: Compute → Images, filtrando por Ubuntu 22.04 y la
arquitectura de tu `shape` (ARM para `VM.Standard.A1.Flex`, x86 para el resto).

## Por qué este módulo crea su propia VCN

DigitalOcean asigna una red por defecto a cada Droplet y GCP trae una red
"default" en todo proyecto nuevo; OCI no ofrece equivalente. Sin una VCN,
subred, gateway de Internet y tabla de rutas propias, la instancia no tendría
por dónde salir ni por dónde entrar el SSH. Se declaran aquí, acotadas a lo
mínimo (una lista de seguridad que sólo abre el puerto SSH configurado), para
mantener el módulo autocontenido igual que los otros dos.

## Autenticación (nunca `~/.oci/config` implícito)

A propósito, `seclab cloud plan/up/destroy --provider oracle` (ver
`lib/cloud.sh`) **no** comprueba la ruta por defecto `~/.oci/config`, aunque
es donde el CLI oficial de OCI busca credenciales por defecto. Exige que
`tenancy_ocid`/`user_ocid`/`fingerprint`/`private_key_path` estén declarados
explícitamente en el `.tfvars`, o que se use `OCI_CLI_CONFIG_FILE` /
`config_file_profile`. Es una decisión deliberada de esta fase, no un
descuido: evita que el CLI de SecLab dependa —ni siquiera para comprobar su
existencia— de un archivo de credenciales que pueda existir ya en la máquina
de un desarrollador o profesor por otro motivo.
