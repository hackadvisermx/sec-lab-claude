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
  description = "IPv4 pública de la instancia. Vacía con Tailscale habilitado: la instancia no tiene IP pública en ese caso (ver 'tailscale_hostname')."
  value       = oci_core_instance.seclab.public_ip
}

output "tailscale_hostname" {
  description = "Nombre Tailscale de la instancia (MagicDNS), para conectarse cuando no hay IP pública. Vacío si Tailscale no está habilitado."
  value       = var.habilitar_tailscale ? var.tailscale_hostname : ""
}

output "puerto_ssh" {
  description = "Puerto SSH publicado."
  value       = var.puerto_ssh
}

output "ssh_user" {
  description = "Usuario DENTRO del contenedor SecLab (no el 'ubuntu' de la VM anfitriona): puerto_ssh se publica desde el contenedor, así que es a este usuario al que se llega por ahí."
  value       = var.ssh_username
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

output "vnc_password" {
  description = "Contraseña del escritorio del contenedor (noVNC). La genera 'seclab init', no Terraform — este output sólo refleja SECLAB_OCI_VNC_PASSWORD de .env, que es la fuente real."
  value       = var.vnc_password
  sensitive   = true
}

output "code_password" {
  description = "Contraseña de code-server del contenedor. La genera 'seclab init', no Terraform — este output sólo refleja SECLAB_OCI_CODE_PASSWORD de .env, que es la fuente real."
  value       = var.code_password
  sensitive   = true
}

output "rdp_password" {
  description = "Contraseña real del usuario 'ubuntu' del HOST (RDP, puerto 3389). Vacía si habilitar_escritorio_host = false. La genera 'seclab init', no Terraform — este output sólo refleja SECLAB_OCI_RDP_PASSWORD de .env, que es la fuente real."
  value       = var.rdp_password
  sensitive   = true
}
