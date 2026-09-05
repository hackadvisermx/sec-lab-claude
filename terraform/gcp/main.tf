# =============================================================================
# SecLab — GCP, módulo (Fase 11)
# =============================================================================
# Reutiliza el mismo bootstrap validado en la Fase 10 (DigitalOcean):
# instalar Docker, traer la imagen de SecLab por digest/tag inmutable, y
# arrancarla mediante un servicio systemd. La plantilla
# (templates/cloud-init.yaml.tftpl) es prácticamente idéntica a la de
# DigitalOcean; la diferencia real está en CÓMO llega a la instancia y en el
# mecanismo opcional de autodestrucción (ver esa plantilla y variables.tf).
#
# Decisión de bootstrap — cloud-init completo, no "startup-script" a secas:
# las imágenes oficiales de Ubuntu en GCP (proyecto ubuntu-os-cloud) traen
# cloud-init preinstalado y configurado con el datasource "GCE", que lee
# system metadata la clave `user-data` exactamente igual que otros
# proveedores (no hace falta activar nada adicional). La alternativa nativa
# de GCP, la clave de metadata `startup-script`, es un simple script de shell
# sin las fases idempotentes (`write_files`, `runcmd` con las garantías de
# "una sola vez por instancia") que sí da cloud-init. Usar `user-data` permite
# reutilizar la MISMA plantilla que DigitalOcean casi sin tocarla — que es
# exactamente lo que pide la Fase 11 — en vez de reescribir el bootstrap como
# un script de shell plano.
#
# Todos los servicios web del contenedor quedan ligados a 127.0.0.1 DENTRO de
# la instancia, igual que en DigitalOcean y en local. La única vía de entrada
# remota que abre el firewall es SSH.
# =============================================================================

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

locals {
  # Las labels de GCP son más restrictivas que las tags de DigitalOcean:
  # sólo minúsculas, dígitos, guiones y guiones bajos, y el valor no puede
  # empezar por un dígito según la clave. Se sanea aquí para no depender de
  # que el alumno rellene el .tfvars ya en ese formato.
  saneo_owner = replace(replace(lower(var.owner), " ", "-"), "/[^a-z0-9_-]/", "-")
  saneo_curso = replace(replace(lower(var.curso), " ", "-"), "/[^a-z0-9_-]/", "-")

  nombre_instancia = "seclab-${local.saneo_owner}"

  labels = {
    proyecto         = "seclab"
    owner            = local.saneo_owner
    curso            = local.saneo_curso
    fecha-expiracion = var.fecha_expiracion
  }

  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    seclab_registro           = var.seclab_registry
    seclab_imagen_ref         = var.seclab_imagen_ref
    nombre_contenedor         = var.nombre_contenedor
    owner                     = var.owner
    proposito                 = var.curso
    fecha_expiracion          = var.fecha_expiracion
    puerto_ssh                = var.puerto_ssh
    habilitar_autodestruccion = var.habilitar_autodestruccion
  })
}

resource "google_compute_firewall" "seclab_ssh" {
  name    = "seclab-ssh-${local.saneo_owner}"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = [tostring(var.puerto_ssh)]
  }

  # Sólo SSH de entrada, igual que el firewall de DigitalOcean. Nada más se
  # publica: los servicios web quedan en 127.0.0.1 dentro de la instancia.
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["seclab"]
}

resource "google_compute_instance" "seclab" {
  name         = local.nombre_instancia
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["seclab"]
  labels       = local.labels

  boot_disk {
    initialize_params {
      # Misma familia de SO que DigitalOcean (Ubuntu 22.04 LTS), por la misma
      # imagen pública mantenida por Canonical/GCP, no un digest fijo: GCP
      # versiona sus imágenes por familia (`-lts`) y resuelve la última
      # revisión parcheada de esa familia en el momento del apply. Es una
      # asimetría real frente al Dockerfile de SecLab (que sí ancla por
      # digest): el proveedor no expone un digest estable de imagen de SO de
      # la misma forma que un registry OCI.
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
    }
  }

  network_interface {
    network = "default"
    access_config {
      # Bloque vacío = IP pública efímera asignada por GCP.
    }
  }

  metadata = {
    user-data = local.cloud_init
    ssh-keys  = "${var.ssh_username}:${var.ssh_public_key}"
  }

  dynamic "service_account" {
    # Sólo se adjunta un bloque service_account explícito si hace falta el
    # scope 'compute' para la autodestrucción (ver variables.tf). Sin esto,
    # la instancia usa igualmente la cuenta de servicio por defecto del
    # proyecto, pero SIN el scope de Compute Engine necesario para borrarse a
    # sí misma — que es precisamente el comportamiento por defecto que se
    # quiere (menor privilegio salvo opt-in explícito).
    for_each = var.habilitar_autodestruccion ? [1] : []
    content {
      email  = var.service_account_email != "" ? var.service_account_email : null
      scopes = ["https://www.googleapis.com/auth/compute"]
    }
  }

  # user-data reescribe /etc/seclab-cloud/entorno con contenido determinista;
  # cambiar la imagen o el owner sí debe recrear la instancia, así que no se
  # marca ningún campo como ignore_changes (mismo criterio que en
  # terraform/digitalocean/main.tf).
}
