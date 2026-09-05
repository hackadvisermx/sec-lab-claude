# =============================================================================
# SecLab — DigitalOcean, módulo de referencia
# =============================================================================
# Una sola Droplet, con SecLab dentro vía cloud-init/systemd (ver
# templates/cloud-init.yaml.tftpl). Deliberadamente simple: este módulo es la
# base que reutiliza la Fase 11 (GCP, Oracle) y no debe acumular
# funcionalidad que no sea genuinamente necesaria para un laboratorio
# individual de un alumno.
#
# Todos los servicios web del contenedor (página de bienvenida, noVNC,
# code-server, Jupyter) quedan ligados a 127.0.0.1 DENTRO de la Droplet — el
# mismo valor por defecto que en local (ver .env.example, SECLAB_BIND). La
# única vía de entrada remota expuesta en el firewall es SSH. Para llegar a
# los servicios web hace falta un túnel SSH (ver 'seclab cloud connect') o
# Tailscale (Fase 9, si el alumno ya lo tiene desplegado); nunca se exponen
# directamente a Internet.
# =============================================================================

provider "digitalocean" {
  token = var.do_token
}

locals {
  # DigitalOcean no valida el formato de las etiquetas más allá de longitud y
  # caracteres permitidos; se sanean aquí espacios y mayúsculas para evitar un
  # rechazo de la API a mitad de apply.
  etiqueta_owner = "owner:${replace(lower(var.owner), " ", "-")}"
  etiqueta_curso = "curso:${replace(lower(var.curso), " ", "-")}"
  etiqueta_ttl   = "fecha-expiracion:${var.fecha_expiracion}"
}

resource "digitalocean_ssh_key" "seclab" {
  name       = "seclab-${var.owner}"
  public_key = var.ssh_public_key
}

resource "digitalocean_droplet" "seclab" {
  name     = "seclab-${replace(lower(var.owner), " ", "-")}"
  region   = var.region
  size     = var.size
  image    = "ubuntu-22-04-x64"
  ssh_keys = [digitalocean_ssh_key.seclab.fingerprint]

  # Etiquetas obligatorias (ver variables.tf: owner y fecha_expiracion no
  # tienen valor por defecto, así que un apply sin ellas falla en el plan,
  # antes de crear nada).
  tags = [
    "seclab",
    local.etiqueta_owner,
    local.etiqueta_curso,
    local.etiqueta_ttl,
  ]

  user_data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    seclab_registry           = var.seclab_registry
    seclab_imagen_ref         = var.seclab_imagen_ref
    nombre_contenedor         = var.nombre_contenedor
    owner                     = var.owner
    proposito                 = var.curso
    fecha_expiracion          = var.fecha_expiracion
    puerto_ssh                = var.puerto_ssh
    habilitar_autodestruccion = var.habilitar_autodestruccion
    do_token_autodestruccion  = var.do_token_autodestruccion
  })

  # cloud-init reescribe /etc/seclab-cloud/entorno con contenido determinista;
  # cambiar la imagen o el owner sí debe recrear la Droplet (no tiene sentido
  # "actualizar en caliente" un laboratorio docente), así que no se marca
  # ningún campo como ignore_changes.
}

# Firewall explícito: por defecto DigitalOcean no aplica ninguno a una
# Droplet nueva (quedaría con todos los puertos abiertos a quien conozca la
# IP salvo lo que bloquee el propio SO). Aquí se declara la política mínima:
# SSH de entrada, todo lo demás de salida.
resource "digitalocean_firewall" "seclab" {
  name        = "seclab-${replace(lower(var.owner), " ", "-")}"
  droplet_ids = [digitalocean_droplet.seclab.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = tostring(var.puerto_ssh)
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
