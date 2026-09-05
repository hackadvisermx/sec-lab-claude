# =============================================================================
# SecLab — DigitalOcean, versiones
# =============================================================================
# El backend NO se declara aquí con valores fijos: DigitalOcean Spaces no
# soporta locking nativo de Terraform (ver docs/cloud.md, sección "Backend
# remoto"), así que el backend real se resuelve por configuración parcial
# (`terraform init -backend-config=...`), nunca hardcodeado en el repositorio.
# El bloque `backend "s3"` de abajo declara SÓLO el tipo; los valores
# concretos (bucket/organización, credenciales) viven fuera de Git.
#
# `terraform init -backend=false` (el único modo que se ejecuta desde este
# repositorio sin credenciales de proveedor) ignora este bloque por completo:
# es justo lo que permite validar sintaxis sin backend remoto real.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.41"
    }
  }

  backend "s3" {
    # Backend S3-compatible con locking (ver docs/cloud.md). Rellena con
    # -backend-config="bucket=..." -backend-config="key=..." etc., o con un
    # archivo backend.hcl fuera de Git (ver backend.hcl.example).
  }
}
