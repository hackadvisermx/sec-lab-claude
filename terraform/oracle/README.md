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

## Si tu región no tiene capacidad ARM disponible (fallback a x86)

`VM.Standard.A1.Flex` (Ampere ARM, Always Free dentro de los límites del
tenancy) no está disponible en todas las regiones ni en todo momento — OCI
puede rechazar el `apply` con un error de capacidad ("Out of host capacity",
o la forma simplemente no aparece listada para tu región). Cuando pase, la
imagen de SecLab **no es el problema**: se publica multi-arquitectura
(`linux/amd64` + `linux/arm64` en el mismo manifest de GHCR), así que
`docker pull` en la VM trae automáticamente la variante correcta sin que
tengas que tocar `seclab_imagen_ref` para nada — sólo hace falta cambiar la
**forma de la instancia** y su **imagen de sistema operativo**, que si tienen
que ir emparejadas (una imagen aarch64 no arranca en una forma x86 y
viceversa).

Cambia estas dos variables en `terraform.tfvars` (o en `.env` si usas
`SECLAB_OCI_*`, ver `sincronizar_tfvars_oracle_desde_env` en `lib/cloud.sh`)
y repite `seclab cloud plan`/`up`:

| | ARM (por defecto) | x86 (fallback, E4) | x86 (fallback, E5) |
|---|---|---|---|
| `shape` | `VM.Standard.A1.Flex` | `VM.Standard.E4.Flex` | `VM.Standard.E5.Flex` |
| `image_ocid` (región `mx-monterrey-1`, resuelto el 2026-09-05 — vuelve a resolverlo para tu región/fecha con el comando de arriba) | `ocid1.image.oc1.mx-monterrey-1.aaaaaaaa33gwf2bybgepuwu4zzg45ony3etaj5oaxixfpaf4vwhzgpmwyqxq` | `ocid1.image.oc1.mx-monterrey-1.aaaaaaaapsyapvnmysguthfj3rtypwipp7rx3eudhihanwdtnvk635fal4ja` | mismo OCID que E4 (ambos x86_64) |

**"Out of host capacity" no siempre se resuelve cambiando de forma una sola
vez.** Es un problema de capacidad física del datacenter, no de tu cuota
(`oci limits resource-availability get` puede mostrar cupo de sobra y el
`apply` seguir fallando igual) — y varía por generación de CPU, no sólo por
arquitectura. En una prueba real contra `mx-monterrey-1`, tanto
`VM.Standard.A1.Flex` (ARM) como `VM.Standard.E4.Flex` (AMD EPYC, generación
anterior) fallaron por falta de capacidad, mientras que
`VM.Standard.E5.Flex` (AMD EPYC Genoa, más nueva) sí tenía capacidad libre en
ese momento. Si una forma falla, vale la pena probar otra generación de la
misma familia antes de darla por perdida o cambiar de proveedor. También
puedes probar un tamaño más chico dentro de la misma forma con
`SECLAB_OCI_OCPUS`/`SECLAB_OCI_MEMORIA_GB` (ver `.env.example`) — a veces
falta capacidad sólo para el tamaño pedido, no para toda la forma.

**Aviso de coste**: ni `VM.Standard.E4.Flex` ni `VM.Standard.E5.Flex` (AMD
EPYC) forman parte del Always Free tier — a diferencia de
`VM.Standard.A1.Flex`, facturan desde el primer minuto (~$45-50 USD/mes con
2 OCPU/8-12GB, ver la tabla de costes que muestra `seclab cloud up`).
Recuerda que el gasto es siempre personal (`docs/cloud.md`). El único x86 del
Always Free (`VM.Standard.E2.1.Micro`) tiene 1 GB de RAM, muy por debajo de
lo que necesita el perfil `full`/`full-msf` (ver `docs/requisitos.md`), así
que no es una alternativa realista aquí.

## Tailscale, sin quedarte fuera

Ver `docs/cloud.md`, sección "Habilitar Tailscale sin quedarte fuera": el
flujo correcto es en dos pasos (`habilitar_tailscale` primero, verificar,
`cerrar_ssh_publico` después), nunca los dos a la vez, y cómo configurar la
auth key (`Reusable` + un tag que desactive el vencimiento de node key) para
no tener que regenerarla en cada recreación de la instancia.

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
