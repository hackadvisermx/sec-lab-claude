# =============================================================================
# SecLab — Oracle Cloud (OCI), módulo (Fase 11)
# =============================================================================
# Reutiliza el bootstrap validado en la Fase 10 (DigitalOcean): la plantilla
# templates/cloud-init.yaml.tftpl instala Docker, trae la imagen de SecLab
# por digest/tag inmutable y la arranca vía systemd — misma lógica, distinta
# vía de entrega.
#
# Decisión de bootstrap — cloud-init vía metadata `user_data`, no un script
# de arranque plano: las imágenes oficiales de Ubuntu publicadas por Oracle
# para OCI incluyen cloud-init con el datasource "OracleCloud", que lee la
# clave de metadata de instancia `user_data` (codificada en base64), igual
# que el resto de datasources de cloud-init. No hace falta ningún mecanismo
# adicional de OCI: es exactamente el mismo patrón que GCP y DigitalOcean.
#
# A diferencia de los otros dos módulos, éste SÍ crea su propia red (VCN,
# subred, tabla de rutas, gateway de Internet y lista de seguridad) en vez de
# asumir una red por defecto preexistente: OCI, a diferencia de DigitalOcean
# y GCP, no ofrece una red "default" lista para usar en un tenancy nuevo. Es
# más código, pero mantiene el módulo autocontenido igual que los otros dos:
# un alumno no necesita crear una VCN a mano antes de poder hacer
# 'seclab cloud up --provider oracle'.
# =============================================================================

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid != "" ? var.user_ocid : null
  fingerprint      = var.fingerprint != "" ? var.fingerprint : null
  private_key_path = var.private_key_path != "" ? var.private_key_path : null
  # Alternativa a las tres de arriba: reutiliza un perfil ya existente de
  # '~/.oci/config' (el mismo que usa el CLI 'oci') sin que este módulo
  # tenga que leer, copiar ni imprimir ninguna credencial. Ver variables.tf.
  config_file_profile = var.config_file_profile != "" ? var.config_file_profile : null
  region              = var.region
}

locals {
  saneo_owner      = replace(replace(lower(var.owner), " ", "-"), "/[^a-z0-9-]/", "-")
  nombre_instancia = "seclab-${local.saneo_owner}"

  freeform_tags = {
    proyecto         = "seclab"
    owner            = var.owner
    curso            = var.curso
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
    habilitar_tailscale       = var.habilitar_tailscale
    tailscale_auth_key        = var.tailscale_auth_key
    tailscale_hostname        = var.tailscale_hostname
  })

  usa_flex = can(regex("Flex$", var.shape))
}

# --- Dominio de disponibilidad ------------------------------------------------
# Data source: no ejecuta llamada real alguna durante `terraform validate`
# (sólo en `plan`/`apply`, que esta sesión no ejecuta). Cómodo para tenancies
# de un solo AD por región, el caso típico de una cuenta de estudiante.
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

locals {
  availability_domain = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.ads.availability_domains[0].name
}

# --- Red mínima autocontenida --------------------------------------------------

resource "oci_core_vcn" "seclab" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.20.0.0/24"]
  display_name   = "seclab-vcn-${local.saneo_owner}"
  dns_label      = "seclabvcn"
  freeform_tags  = local.freeform_tags
}

resource "oci_core_internet_gateway" "seclab" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.seclab.id
  display_name   = "seclab-igw-${local.saneo_owner}"
  enabled        = true
  freeform_tags  = local.freeform_tags
}

resource "oci_core_route_table" "seclab" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.seclab.id
  display_name   = "seclab-rt-${local.saneo_owner}"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.seclab.id
  }
}

# Lista de seguridad explícita: sólo SSH de entrada, igual que el firewall de
# DigitalOcean y GCP. Nada más se publica; los servicios web quedan en
# 127.0.0.1 dentro de la instancia.
#
# Con Tailscale habilitado, el SSH público deja de abrirse por completo: el
# bloque `ingress_security_rules` es dinámico y no genera nada en ese caso.
# El egress "all" se mantiene siempre — Tailscale necesita salida UDP hacia
# sus servidores de coordinación/DERP, e "iniciada desde dentro" no necesita
# ninguna regla de entrada correspondiente en una lista de seguridad
# stateful como la de OCI.
resource "oci_core_security_list" "seclab" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.seclab.id
  display_name   = "seclab-sl-${local.saneo_owner}"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  dynamic "ingress_security_rules" {
    for_each = var.habilitar_tailscale ? [] : [1]
    content {
      protocol = "6" # TCP
      source   = "0.0.0.0/0"

      tcp_options {
        min = var.puerto_ssh
        max = var.puerto_ssh
      }
    }
  }
}

resource "oci_core_subnet" "seclab" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.seclab.id
  cidr_block                 = "10.20.0.0/24"
  display_name               = "seclab-subnet-${local.saneo_owner}"
  dns_label                  = "seclabsub"
  route_table_id             = oci_core_route_table.seclab.id
  security_list_ids          = [oci_core_security_list.seclab.id]
  prohibit_public_ip_on_vnic = false
}

# --- Instancia ------------------------------------------------------------

resource "oci_core_instance" "seclab" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = local.nombre_instancia
  shape               = var.shape
  freeform_tags       = local.freeform_tags

  dynamic "shape_config" {
    # Sólo las formas *.Flex aceptan/necesitan shape_config.
    for_each = local.usa_flex ? [1] : []
    content {
      ocpus         = var.ocpus
      memory_in_gbs = var.memoria_gb
    }
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.seclab.id
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = var.image_ocid
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(local.cloud_init)
  }

  lifecycle {
    precondition {
      condition     = !var.habilitar_tailscale || var.tailscale_auth_key != ""
      error_message = "habilitar_tailscale = true exige tailscale_auth_key (generada por ti en https://login.tailscale.com/admin/settings/keys; SecLab nunca la genera)."
    }
  }

  # user_data reescribe /etc/seclab-cloud/entorno con contenido determinista;
  # cambiar la imagen o el owner sí debe recrear la instancia, mismo criterio
  # que en los otros dos módulos.
}
