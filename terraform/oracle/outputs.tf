# =============================================================================
# SecLab — Oracle Cloud (OCI), salidas
# =============================================================================
# `seclab cloud status|connect|wait` leen estas salidas con
# `terraform output -json`, igual que en los otros dos módulos.
# =============================================================================

output "instance_id" {
  description = "OCID de la instancia."
  value       = oci_core_instance.seclab.id
}

output "ip_publica" {
  description = "IPv4 pública de la instancia."
  value       = oci_core_instance.seclab.public_ip
}

output "puerto_ssh" {
  description = "Puerto SSH publicado."
  value       = var.puerto_ssh
}

output "ssh_user" {
  description = "Usuario del sistema autorizado por la llave SSH en las imágenes oficiales de Ubuntu de OCI ('ubuntu', no 'root': igual que en GCP, login directo de root deshabilitado)."
  value       = "ubuntu"
}

output "owner" {
  value = var.owner
}

output "fecha_expiracion" {
  value = var.fecha_expiracion
}

output "creado_en" {
  description = "Marca de creación que reporta la API de OCI (RFC3339)."
  value       = oci_core_instance.seclab.time_created
}

output "shape" {
  value = var.shape
}
