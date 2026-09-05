# =============================================================================
# SecLab — GCP, variables
# =============================================================================
# Mismo patrón que terraform/digitalocean/variables.tf: `owner` y
# `fecha_expiracion` son obligatorias y sin valor por defecto, con
# `validation` en HCL como última barrera si alguien invoca Terraform sin
# pasar por `seclab cloud` (que las vuelve a exigir antes, en español).
# =============================================================================

variable "project" {
  description = "ID del proyecto de GCP donde se crea la instancia. Obligatorio: a diferencia de DigitalOcean, GCP factura y aísla recursos por proyecto, no por cuenta a secas."
  type        = string

  validation {
    condition     = length(trimspace(var.project)) > 0
    error_message = "project no puede estar vacío. Es el ID del proyecto de GCP (no el nombre visible), ver 'gcloud projects list'."
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
  description = "Fecha (AAAA-MM-DD) a partir de la cual esta instancia ya no debería existir. Obligatoria: sin TTL, un laboratorio temporal se convierte en una VM olvidada facturando indefinidamente."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.fecha_expiracion))
    error_message = "fecha_expiracion debe tener formato AAAA-MM-DD, por ejemplo 2026-12-31."
  }
}

variable "region" {
  description = "Región de GCP. Ver: gcloud compute regions list"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona de GCP dentro de la región."
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "Tipo de máquina de Compute Engine. Ver la tabla de costes aproximados en 'seclab cloud plan' y docs/cloud.md."
  type        = string
  default     = "e2-medium"
}

variable "ssh_public_key" {
  description = "Llave pública SSH que se autoriza en la instancia (contenido de un .pub, no una ruta). Usa una llave dedicada, no la personal del alumno con acceso a otros sistemas."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-)", var.ssh_public_key))
    error_message = "ssh_public_key no parece una llave pública SSH válida (debe empezar por ssh-ed25519, ssh-rsa o ecdsa-sha2-...)."
  }
}

variable "ssh_username" {
  description = "Usuario del sistema al que se asocia la llave SSH (metadata 'ssh-keys' de GCP, formato 'usuario:llave'). Las imágenes oficiales de Ubuntu en GCP no tienen un usuario 'ubuntu' preconfigurado como en otros proveedores: este usuario lo crea el propio arranque de GCP la primera vez que ve esa metadata."
  type        = string
  default     = "seclab"
}

variable "seclab_registry" {
  description = "Registry OCI del que se hace pull de la imagen (ver SECLAB_REGISTRY en .env.example). Nunca Docker Hub a secas por defecto."
  type        = string
}

variable "seclab_imagen_ref" {
  description = "Referencia completa de la imagen a desplegar: por digest (registry/seclab-lite@sha256:...) o por tag inmutable de versión (registry/seclab-lite:0.2.0-abc1234). Nunca 'latest'."
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
  description = "Puerto SSH del contenedor SecLab, publicado en todas las interfaces (es la única vía de entrada remota; el resto de servicios quedan en 127.0.0.1 de la instancia, ver docs/cloud.md)."
  type        = number
  default     = 2222
}

variable "habilitar_autodestruccion" {
  description = <<-EOT
    Activa un temporizador 'at' en la propia instancia que la borra a sí misma
    en fecha_expiracion, llamando a la API de Compute Engine. A diferencia del
    mecanismo de DigitalOcean (que necesita un token de borrado dedicado
    depositado en la VM), aquí la instancia usa su PROPIA identidad de cuenta
    de servicio (metadata de GCP, sin ningún secreto estático en disco) — pero
    eso exige que la cuenta de servicio adjunta tenga permiso IAM de borrado
    sobre sí misma y el scope de acceso 'compute' habilitado (ver
    service_account_scopes y docs/cloud.md, "TTL y autodestrucción"). Es un
    mecanismo de última línea, no el flujo recomendado.
  EOT
  type        = bool
  default     = false
}

variable "service_account_email" {
  description = "Cuenta de servicio que se adjunta a la instancia (vacío = la cuenta de servicio por defecto del proyecto). Sólo importa si habilitar_autodestruccion=true: esa cuenta necesita el rol 'roles/compute.instanceAdmin.v1' (o uno más acotado que sólo permita 'compute.instances.delete') concedido FUERA de este módulo, por un administrador del proyecto — Terraform no lo concede aquí a propósito, para no ampliar sin darse cuenta el alcance de una cuenta de servicio compartida."
  type        = string
  default     = ""
}
