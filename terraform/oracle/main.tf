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

  # Con Tailscale habilitado, el diseño es en DOS pasos, no uno: primero se
  # verifica que Tailscale funciona (con SSH público seguro por si acaso, ver
  # docs/cloud.md), y sólo entonces se cierra el SSH público — nunca los dos
  # a la vez, porque si Tailscale no llegara a levantar, cerrar el SSH
  # público en el mismo apply que lo activa dejaría la instancia
  # inalcanzable sin ninguna forma de diagnosticar por qué. `privado_final`
  # es la única condición real que cierra el SSH público (sin IP pública, sin
  # regla de entrada, contenedor con el puerto sólo en 127.0.0.1); mientras
  # sea false, la instancia se ve exactamente igual que sin Tailscale, así
  # sea la primera vez o un rollback tras un problema.
  privado_final = var.habilitar_tailscale && var.cerrar_ssh_publico

  # Ambos perfiles full/full-msf traen escritorio y code-server activados
  # por defecto (docker/entrypoint.sh, por_perfil()), y el contenedor exige
  # un secreto no vacío para cada uno o aborta — igual que en local, donde
  # 'seclab init' los genera. Aquí los genera Terraform, se inyectan al
  # contenedor por --env-file (ver templates/cloud-init.yaml.tftpl) y NUNCA
  # se escriben en ningún log ni en el estado en texto plano más de lo que ya
  # implica cualquier atributo 'sensitive' de Terraform. Sólo alfanuméricos:
  # el archivo de entorno es KEY=VALOR simple, sin comillas ni escapes.
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
    ssh_public_key            = var.ssh_public_key
    vnc_password              = var.vnc_password
    code_password             = var.code_password
    habilitar_autodestruccion = var.habilitar_autodestruccion
    habilitar_tailscale       = var.habilitar_tailscale
    privado_final             = local.privado_final
    tailscale_auth_key        = var.tailscale_auth_key
    tailscale_hostname        = var.tailscale_hostname
    habilitar_escritorio_host = var.habilitar_escritorio_host
    rdp_password              = var.rdp_password
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

# Gateway de Internet: sólo hace falta para dar una IP pública a la
# instancia (tráfico ENTRANTE u saliente vía IP pública). Sólo se omite
# cuando privado_final es true (Tailscale confirmado Y cerrar_ssh_publico
# activado) — la salida a Internet la da el NAT Gateway de abajo en su
# lugar. Mientras no se haya cerrado, hay IP pública igual que sin
# Tailscale, para poder verificar que Tailscale funciona antes de perder el
# acceso público (ver docs/cloud.md, "Habilitar Tailscale sin quedarte
# fuera").
resource "oci_core_internet_gateway" "seclab" {
  count          = local.privado_final ? 0 : 1
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.seclab.id
  display_name   = "seclab-igw-${local.saneo_owner}"
  enabled        = true
  freeform_tags  = local.freeform_tags
}

# NAT Gateway: da salida a Internet (docker pull de la imagen desde GHCR,
# actualizaciones de paquetes, servidores de coordinación/DERP de Tailscale)
# a una instancia SIN IP pública. Sin esto, quitar la IP pública dejaría la
# instancia sin salida a Internet en absoluto — un Internet Gateway en OCI
# sólo da tráfico a instancias CON IP pública asignada. Sólo tráfico
# saliente-iniciado-desde-dentro; nada puede entrar por aquí.
resource "oci_core_nat_gateway" "seclab" {
  count          = local.privado_final ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.seclab.id
  display_name   = "seclab-nat-${local.saneo_owner}"
  freeform_tags  = local.freeform_tags
}

resource "oci_core_route_table" "seclab" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.seclab.id
  display_name   = "seclab-rt-${local.saneo_owner}"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = local.privado_final ? oci_core_nat_gateway.seclab[0].id : oci_core_internet_gateway.seclab[0].id
  }
}

# Lista de seguridad explícita: sólo SSH (y, opcionalmente, RDP) de entrada,
# igual que el firewall de DigitalOcean y GCP. Nada más se publica; los
# servicios web quedan en 127.0.0.1 dentro de la instancia.
#
# Mientras no esté cerrado (privado_final = false) se abren dos o tres
# puertos: el 22 (sshd del HOST Ubuntu, arriba desde los primeros segundos de
# arranque, autenticado con la misma ssh_public_key vía el datasource
# OracleCloud de cloud-init), puerto_ssh/2222 (sshd DENTRO del contenedor
# SecLab, que tarda lo que tarde el docker pull de la imagen), y el 3389
# (xrdp del HOST, sólo si habilitar_escritorio_host = true). El del host es
# la vía de rescate real — no depende de Docker ni de la imagen — para
# diagnosticar si el contenedor tarda o falla en arrancar; sin él, la única
# señal disponible mientras el contenedor sube es un silencio total. Todo el
# tráfico público (los tres puertos) sólo deja de abrirse cuando
# privado_final es true: el bloque `ingress_security_rules` es dinámico y no
# genera nada en ese caso. El egress "all" se mantiene siempre — Tailscale
# necesita salida
# UDP hacia sus servidores de coordinación/DERP, e "iniciada desde dentro"
# no necesita ninguna regla de entrada correspondiente en una lista de
# seguridad stateful como la de OCI.
resource "oci_core_security_list" "seclab" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.seclab.id
  display_name   = "seclab-sl-${local.saneo_owner}"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  dynamic "ingress_security_rules" {
    for_each = local.privado_final ? [] : toset(distinct(concat(
      [22, var.puerto_ssh],
      var.habilitar_escritorio_host ? [3389] : []
    )))
    content {
      protocol = "6" # TCP
      source   = "0.0.0.0/0"

      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
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
  prohibit_public_ip_on_vnic = local.privado_final
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
    assign_public_ip = !local.privado_final
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
    precondition {
      condition     = !var.habilitar_escritorio_host || length(var.rdp_password) >= 16
      error_message = "habilitar_escritorio_host = true exige rdp_password de al menos 16 caracteres (SECLAB_OCI_RDP_PASSWORD en .env). Genera uno con 'seclab init --regenerar-secretos'."
    }
  }

  # user_data reescribe /etc/seclab-cloud/entorno con contenido determinista;
  # cambiar la imagen o el owner sí debe recrear la instancia, mismo criterio
  # que en los otros dos módulos.
}
