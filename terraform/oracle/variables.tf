# =============================================================================
# SecLab — Oracle Cloud (OCI), variables
# =============================================================================
# Mismo patrón que los otros dos módulos: `owner` y `fecha_expiracion` son
# obligatorias y sin valor por defecto.
#
# Autenticación: las cuatro variables de abajo (tenancy_ocid, user_ocid,
# fingerprint, private_key_path) son las de autenticación clásica por clave
# de API de OCI. NINGUNA tiene valor por defecto ni se lee de
# '~/.oci/config': `seclab cloud` (lib/cloud.sh) exige que se declaren
# explícitamente aquí o por las variables de entorno estándar del provider —
# a propósito, esta sesión de trabajo tiene prohibido buscar o tocar
# credenciales reales de OCI en esta máquina (donde el CLI 'oci' SÍ está
# instalado), así que el módulo nunca asume un '~/.oci/config' implícito.
# =============================================================================

variable "tenancy_ocid" {
  description = "OCID del tenancy de OCI. Ver 'oci iam compartment list' o la consola, menú de perfil."
  type        = string

  validation {
    condition     = length(trimspace(var.tenancy_ocid)) > 0
    error_message = "tenancy_ocid no puede estar vacío."
  }
}

variable "user_ocid" {
  description = "OCID del usuario de OCI que autentica la API."
  type        = string
  sensitive   = true
  default     = ""
}

variable "fingerprint" {
  description = "Huella de la clave de API subida a ese usuario en la consola de OCI."
  type        = string
  sensitive   = true
  default     = ""
}

variable "private_key_path" {
  description = "Ruta a la clave privada de API (PEM), FUERA de este repositorio. Nunca la copies dentro del proyecto: no hay patrón de .gitignore que la proteja si la pegas dentro de terraform/oracle/."
  type        = string
  sensitive   = true
  default     = ""
}

variable "config_file_profile" {
  description = "Perfil de '~/.oci/config' a usar cuando user_ocid/fingerprint/private_key_path se dejan vacíos (autenticación por archivo, el mismo mecanismo que ya usa el CLI 'oci' — ver lib/cloud.sh, sincronizar_tfvars_oracle_desde_env). Vacío = no se usa este mecanismo, hay que rellenar los cuatro campos clásicos."
  type        = string
  default     = ""
}

variable "region" {
  description = "Región de OCI, ej. 'us-ashburn-1'. Ver 'oci iam region list'."
  type        = string
}

variable "compartment_ocid" {
  description = "OCID del compartimento donde se crean los recursos. En cuentas de estudiante suele ser el compartimento raíz del tenancy o uno dedicado creado por el profesor."
  type        = string

  validation {
    condition     = length(trimspace(var.compartment_ocid)) > 0
    error_message = "compartment_ocid no puede estar vacío."
  }
}

variable "owner" {
  description = "Alumno responsable del gasto de esta instancia. Obligatorio: sin owner, nadie sabe a quién pertenece un recurso encendido facturando."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner no puede estar vacío. Pon tu nombre o usuario del curso."
  }
}

variable "curso" {
  description = "Curso o propósito de la instancia, para la etiqueta 'curso'."
  type        = string
  default     = "seclab"
}

variable "fecha_expiracion" {
  description = "Fecha (AAAA-MM-DD) a partir de la cual esta instancia ya no debería existir. Obligatoria."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.fecha_expiracion))
    error_message = "fecha_expiracion debe tener formato AAAA-MM-DD, por ejemplo 2026-12-31."
  }
}

variable "availability_domain" {
  description = "Dominio de disponibilidad exacto (ej. 'Uocm:US-ASHBURN-AD-1'). Vacío = se usa el primero que devuelva la API para el tenancy (data source), cómodo para un tenancy de un solo AD por región."
  type        = string
  default     = ""
}

variable "shape" {
  description = "Forma de la instancia. Por defecto una forma Ampere ARM (A1.Flex) que entra, dentro de los límites de shape_config, en el 'Always Free' de OCI (ver docs/cloud.md: los límites del free tier cambian, no está garantizado)."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "ocpus" {
  description = "OCPUs para formas *.Flex (ignorado en formas fijas). El Always Free de A1.Flex cubre, a fecha de escribir esto, hasta 4 OCPU/24GB en total entre todas las instancias A1 del tenancy — verifica el límite vigente antes de asumir coste cero."
  type        = number
  default     = 2
}

variable "memoria_gb" {
  description = "Memoria en GB para formas *.Flex."
  type        = number
  default     = 12
}

variable "image_ocid" {
  description = "OCID de la imagen Ubuntu 22.04 a usar, específico de tu región y tenancy (las imágenes de OCI no son globales como en GCP: hay que resolver el OCID por región). Consulta 'oci compute image list --compartment-id <tenancy> --operating-system Ubuntu --operating-system-version 22.04' o la consola. Sin valor por defecto a propósito: un OCID de otra región falla el apply."
  type        = string

  validation {
    condition     = length(trimspace(var.image_ocid)) > 0
    error_message = "image_ocid no puede estar vacío. Resuélvelo para tu región con 'oci compute image list' (ver README.md)."
  }
}

variable "ssh_public_key" {
  description = "Llave pública SSH que se autoriza en la instancia (contenido de un .pub, no una ruta)."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-)", var.ssh_public_key))
    error_message = "ssh_public_key no parece una llave pública SSH válida (debe empezar por ssh-ed25519, ssh-rsa o ecdsa-sha2-...)."
  }
}

variable "seclab_registry" {
  description = "Registry OCI del que se hace pull de la imagen (ver SECLAB_REGISTRY en .env.example). Nunca Docker Hub a secas por defecto."
  type        = string
}

variable "seclab_imagen_ref" {
  description = "Referencia completa de la imagen a desplegar: por digest o por tag inmutable de versión. Nunca 'latest'."
  type        = string

  validation {
    condition     = !endswith(var.seclab_imagen_ref, ":latest")
    error_message = "seclab_imagen_ref no puede usar el tag 'latest'. Usa un digest (@sha256:...) o un tag de versión inmutable."
  }
}

variable "nombre_contenedor" {
  description = "Nombre del contenedor systemd en la instancia."
  type        = string
  default     = "seclab"
}

variable "puerto_ssh" {
  description = "Puerto SSH del contenedor SecLab, publicado en todas las interfaces."
  type        = number
  default     = 2222
}

variable "habilitar_tailscale" {
  description = <<-EOT
    Instala y arranca Tailscale en la instancia durante el bootstrap
    (paquete oficial, fijado por versión, vía el repositorio apt de
    Tailscale — nunca el instalador remoto 'curl | sh' sin verificar). Con
    esto en true:
      - El puerto SSH deja de publicarse en la lista de seguridad de OCI
        (0.0.0.0/0) y el contenedor deja de publicarlo en todas las
        interfaces: pasa a 127.0.0.1, igual que el resto de servicios web.
      - 'tailscale up --ssh' te deja entrar por la tailnet sin exponer nada
        a Internet.
    Requiere 'tailscale_auth_key'. Ver docs/cloud.md, "Tailscale en un
    despliegue cloud".
  EOT
  type        = bool
  default     = false
}

variable "tailscale_auth_key" {
  description = "Auth key de Tailscale, efímera y de mínimo privilegio, generada por TI en https://login.tailscale.com/admin/settings/keys — SecLab nunca la genera. Obligatoria si habilitar_tailscale = true (comprobado en main.tf, no aquí: este bloque no puede ver otras variables sin exigir Terraform >= 1.9, y el módulo declara >= 1.5.0)."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = var.tailscale_auth_key == "" || can(regex("^tskey-auth-", var.tailscale_auth_key))
    error_message = "tailscale_auth_key no tiene la forma de una auth key de Tailscale (debe empezar por 'tskey-auth-')."
  }
}

variable "tailscale_hostname" {
  description = "Nombre con el que el nodo aparece en tu tailnet."
  type        = string
  default     = "seclab"
}

variable "habilitar_autodestruccion" {
  description = <<-EOT
    Activa un temporizador 'at' en la propia instancia que la termina a sí
    misma en fecha_expiracion. Usa 'oci-cli' con autenticación por
    'instance principal' (identidad propia de la instancia entregada por el
    servidor de metadata de OCI, sin ningún token estático en disco), pero
    eso EXIGE que la tenancy tenga configurado, de antemano y fuera de este
    módulo, un Dynamic Group que incluya esta instancia y una Policy que le
    permita 'manage instance-family' (o un permiso más acotado sólo de
    terminación) sobre el compartimento. Este módulo NO crea esas políticas
    de identidad: suelen requerir privilegios de administrador de tenancy
    que una cuenta de estudiante normalmente no tiene. Ver docs/cloud.md,
    "TTL y autodestrucción".
  EOT
  type        = bool
  default     = false
}
