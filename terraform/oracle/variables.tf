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


# Los tres siguientes NO los genera este módulo (a diferencia de un primer
# diseño con random_password, descartado): el mismo generador que los
# secretos del contenedor local ('seclab init'/'seclab init
# --regenerar-secretos', ver bin/seclab) los deja en .env
# (SECLAB_OCI_VNC_PASSWORD/CODE_PASSWORD/RDP_PASSWORD), y
# sincronizar_tfvars_oracle_desde_env (lib/cloud.sh) los copia aquí. Un solo
# mecanismo de generación para local y remoto, en vez de dos.
variable "vnc_password" {
  description = "Contraseña del escritorio del contenedor (noVNC). La genera 'seclab init', no este módulo. Sólo los primeros 8 caracteres son significativos de todos modos (VncAuth clásico, cifrado DES de 8 bytes) — el resto se acepta pero se ignora al autenticar."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.vnc_password) >= 16
    error_message = "vnc_password debe tener al menos 16 caracteres (misma exigencia que docker/entrypoint.sh). Genera uno con 'seclab init --regenerar-secretos'."
  }
}

variable "code_password" {
  description = "Contraseña de code-server del contenedor. La genera 'seclab init', no este módulo."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.code_password) >= 16
    error_message = "code_password debe tener al menos 16 caracteres (misma exigencia que docker/entrypoint.sh). Genera uno con 'seclab init --regenerar-secretos'."
  }
}

variable "rdp_password" {
  description = "Contraseña real del usuario 'ubuntu' del HOST (RDP, puerto 3389). Sólo se usa si habilitar_escritorio_host = true; la genera 'seclab init', no este módulo. La condición real (>= 16 caracteres cuando habilitar_escritorio_host = true) se comprueba en el lifecycle.precondition de oci_core_instance.seclab: una validación de variable no puede referenciar otra variable de forma fiable en este proyecto (mismo criterio ya usado para tailscale_auth_key)."
  type        = string
  sensitive   = true
  default     = ""
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

variable "ssh_username" {
  description = "Usuario del sistema DENTRO del contenedor SecLab (imagen publicada con ARG SECLAB_USUARIO=seclab en docker/Dockerfile), NO el usuario 'ubuntu' de la VM anfitriona. El puerto_ssh se publica desde el contenedor (docker run -p puerto_ssh:22), así que quien conecta ahí siempre llega a este usuario, nunca a 'ubuntu' — mismo criterio que 'ssh_username' en terraform/gcp/variables.tf."
  type        = string
  default     = "seclab"
}

variable "habilitar_escritorio_host" {
  description = <<-EOT
    Instala un escritorio XFCE + xrdp en el HOST Ubuntu (fuera del
    contenedor SecLab, que ya trae su propio escritorio por noVNC — ver
    docker/entrypoint.sh). Opt-in explícito: añade paquetes reales
    (xfce4, xrdp), un servicio más que mantener y RAM/CPU de más en la VM.
    Pensado para configurar el HOST directamente (drivers, red, lo que sea
    que no tenga sentido hacer dentro de un contenedor), no para el trabajo
    normal de laboratorio — para eso ya está el escritorio del contenedor.
    Requiere autenticación por contraseña real (RDP no soporta llave SSH):
    la genera Terraform (random_password.rdp_host), nunca un valor por
    defecto. El puerto 3389 sigue exactamente la misma regla de dos pasos
    que el SSH del host (ver cerrar_ssh_publico): abierto públicamente
    mientras no se cierre, y siempre servido también por Tailscale.
  EOT
  type        = bool
  default     = false
}

variable "habilitar_tailscale" {
  description = <<-EOT
    Instala y arranca Tailscale en la instancia durante el bootstrap
    (paquete oficial, fijado por versión, vía el repositorio apt de
    Tailscale — nunca el instalador remoto 'curl | sh' sin verificar). Con
    esto en true, Tailscale corre desde el primer arranque, pero el SSH
    público SIGUE abierto hasta que además pongas cerrar_ssh_publico = true
    (ver esa variable): son dos pasos deliberadamente separados, para poder
    comprobar que Tailscale funciona antes de perder el único otro camino de
    entrada. Requiere 'tailscale_auth_key'. Ver docs/cloud.md, "Habilitar
    Tailscale sin quedarte fuera".
  EOT
  type        = bool
  default     = false
}

variable "cerrar_ssh_publico" {
  description = <<-EOT
    Segundo paso, deliberadamente separado de habilitar_tailscale: sólo con
    ESTO en true (y habilitar_tailscale también en true) la instancia pierde
    la IP pública, el puerto SSH deja de publicarse en la lista de
    seguridad de OCI (0.0.0.0/0) y el contenedor deja de publicarlo en todas
    las interfaces (pasa a 127.0.0.1, igual que el resto de servicios web);
    la salida a Internet la sigue dando un NAT Gateway. Ver docs/cloud.md,
    "Habilitar Tailscale sin quedarte fuera": no actives esto en el mismo
    apply que activa Tailscale por primera vez — primero confirma con
    'ssh -p puerto_ssh usuario@tailscale_hostname' que Tailscale sí conecta,
    y sólo entonces pon esto en true y vuelve a aplicar (no recrea la
    instancia, sólo la red).
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
