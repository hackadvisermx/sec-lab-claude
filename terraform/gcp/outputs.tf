# =============================================================================
# SecLab — GCP, salidas
# =============================================================================
# `seclab cloud status|connect|wait` leen estas salidas con
# `terraform output -json`, igual que en DigitalOcean.
#
# Nota honesta: NO se declara una salida `creado_en` como en
# terraform/digitalocean/outputs.tf (que usa `digitalocean_droplet.created_at`
# de la API real). El recurso `google_compute_instance` de este provider no
# expone de forma fiable un atributo de marca de creación equivalente en
# todas las versiones del provider; en vez de inventar un valor aproximado
# (por ejemplo `timestamp()` evaluado en el momento del apply, que NO es la
# hora de creación real de la instancia sino la del propio `apply`), se omite
# la salida. `seclab cloud status` no puede mostrar antigüedad para GCP por
# este motivo — documentado también en TESTING_GAPS.md.
# =============================================================================

output "instance_id" {
  description = "ID numérico de la instancia en GCP."
  value       = google_compute_instance.seclab.instance_id
}

output "ip_publica" {
  description = "IPv4 pública (efímera) de la instancia."
  value       = google_compute_instance.seclab.network_interface[0].access_config[0].nat_ip
}

output "puerto_ssh" {
  description = "Puerto SSH publicado."
  value       = var.puerto_ssh
}

output "ssh_user" {
  description = "Usuario del sistema autorizado por la llave SSH (no 'root': las imágenes de Ubuntu en GCP no habilitan login directo de root)."
  value       = var.ssh_username
}

output "owner" {
  value = var.owner
}

output "fecha_expiracion" {
  value = var.fecha_expiracion
}

output "zone" {
  value = var.zone
}

output "machine_type" {
  value = var.machine_type
}
