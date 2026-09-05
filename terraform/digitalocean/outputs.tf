# =============================================================================
# SecLab — DigitalOcean, salidas
# =============================================================================
# `seclab cloud status|connect|wait` leen estas salidas con
# `terraform output -json`, en lugar de volver a calcular nada por su cuenta:
# una sola fuente de verdad para lo que existe de verdad en DigitalOcean.
# =============================================================================

output "droplet_id" {
  description = "ID de la Droplet en DigitalOcean."
  value       = digitalocean_droplet.seclab.id
}

output "ip_publica" {
  description = "IPv4 pública de la Droplet."
  value       = digitalocean_droplet.seclab.ipv4_address
}

output "puerto_ssh" {
  description = "Puerto SSH publicado."
  value       = var.puerto_ssh
}

output "owner" {
  value = var.owner
}

output "fecha_expiracion" {
  value = var.fecha_expiracion
}

output "creado_en" {
  description = "Marca de creación que reporta la API de DigitalOcean (RFC3339)."
  value       = digitalocean_droplet.seclab.created_at
}

output "region" {
  value = digitalocean_droplet.seclab.region
}

output "size" {
  value = digitalocean_droplet.seclab.size
}
