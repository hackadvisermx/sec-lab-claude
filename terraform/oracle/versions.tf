# =============================================================================
# SecLab — Oracle Cloud (OCI), versiones
# =============================================================================
# Backend: local por defecto (decisión explícita del usuario para uso
# personal, un solo operador, una sola máquina — sin locking, sin cuenta
# externa que crear). El .tfstate vive en terraform/oracle/terraform.tfstate,
# fuera de Git (ver .gitignore).
#
# Si más adelante hay varias personas aplicando cambios a la vez, hace falta
# un backend remoto con locking. Oracle Object Storage tiene API de
# compatibilidad S3 (igual que DigitalOcean Spaces, ver
# terraform/digitalocean/versions.tf) pero SIN locking nativo — la
# recomendación para ese caso es Terraform Cloud (HCP Terraform, con
# locking real) o AWS S3 + DynamoDB. Ver backend.hcl.example y docs/cloud.md,
# "Backend remoto por proveedor", para cómo migrar: añadir aquí un bloque
# `backend "s3" { }` y ejecutar `terraform init -backend-config=backend.hcl
# -migrate-state`.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}
