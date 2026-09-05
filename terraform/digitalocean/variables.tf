# =============================================================================
# SecLab — DigitalOcean, variables
# =============================================================================
# `owner` y `fecha_expiracion` son obligatorias sin valor por defecto a
# propósito: es la aplicación en Terraform de la regla de prompt_v3.md
# ("rechazar aplicar si no hay TTL/fecha de expiración definida"). `seclab
# cloud up` las vuelve a exigir ANTES de llamar a Terraform (para dar un
# mensaje en español y no un error crudo de HCL), pero si alguien invoca
# terraform directamente sin pasar por el CLI, esto es la última barrera.
# =============================================================================

variable "do_token" {
  description = "Token de API de DigitalOcean. NUNCA lo pongas en un .tfvars versionado; usa una variable de entorno DIGITALOCEAN_TOKEN o un .tfvars fuera de Git (ver terraform.tfvars.example)."
  type        = string
  sensitive   = true
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
  description = "Fecha (AAAA-MM-DD) a partir de la cual esta instancia ya no debería existir. Obligatoria: sin TTL, un laboratorio temporal se convierte en una VM olvidada facturando indefinidamente."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.fecha_expiracion))
    error_message = "fecha_expiracion debe tener formato AAAA-MM-DD, por ejemplo 2026-12-31."
  }
}

variable "region" {
  description = "Región de DigitalOcean. Ver: doctl compute region list"
  type        = string
  default     = "nyc3"
}

variable "size" {
  description = "Tamaño de la Droplet (slug de DigitalOcean). Ver la tabla de costes aproximados en 'seclab cloud plan' y docs/cloud.md."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "ssh_public_key" {
  description = "Llave pública SSH que se autoriza en la Droplet (contenido de un .pub, no una ruta). Usa una llave dedicada, no la personal del alumno con acceso a otros sistemas."
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
  description = "Referencia completa de la imagen a desplegar: por digest (registry/seclab-lite@sha256:...) o por tag inmutable de versión (registry/seclab-lite:0.2.0-abc1234). Nunca 'latest': una Droplet que se recrea meses después de un TTL vencido no debe traer una imagen distinta a la que el alumno probó."
  type        = string

  validation {
    condition     = !endswith(var.seclab_imagen_ref, ":latest")
    error_message = "seclab_imagen_ref no puede usar el tag 'latest'. Usa un digest (@sha256:...) o un tag de versión inmutable."
  }
}

variable "nombre_contenedor" {
  description = "Nombre del contenedor systemd en la Droplet."
  type        = string
  default     = "seclab"
}

variable "puerto_ssh" {
  description = "Puerto SSH del contenedor SecLab, publicado en todas las interfaces (es la única vía de entrada remota; el resto de servicios quedan en 127.0.0.1 de la Droplet, ver docs/cloud.md)."
  type        = number
  default     = 2222
}

variable "habilitar_autodestruccion" {
  description = "Activa un temporizador 'at' en la propia Droplet que llama a la API de DigitalOcean para autoborrarse en fecha_expiracion. Requiere depositar do_token_autodestruccion en la VM: es un mecanismo de última línea, no el flujo recomendado. Ver docs/cloud.md, 'TTL y autodestrucción'."
  type        = bool
  default     = false
}

variable "do_token_autodestruccion" {
  description = "Token de API de DigitalOcean con alcance de borrado, usado SÓLO por el temporizador de autodestrucción dentro de la propia Droplet. Debe ser un token distinto de do_token, de un solo propósito, y revocado tras destruir. Vacío si habilitar_autodestruccion es false."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = var.habilitar_autodestruccion == false || length(trimspace(var.do_token_autodestruccion)) > 0
    error_message = "habilitar_autodestruccion=true exige do_token_autodestruccion (un token de borrado dedicado)."
  }
}
