# =============================================================================
# SecLab — Oracle Cloud (OCI), versiones
# =============================================================================
# Terraform no tiene un backend nativo "oci": a diferencia de GCP (backend
# "gcs" con locking nativo), Oracle Cloud sólo ofrece Object Storage con una
# API de compatibilidad S3 — la misma situación que DigitalOcean Spaces (ver
# terraform/digitalocean/versions.tf) y el mismo backend genérico "s3" se usa
# aquí por el mismo motivo: sin servicio de locking equivalente a DynamoDB
# propio de Oracle Cloud, la recomendación por defecto sigue siendo Terraform
# Cloud (ver docs/cloud.md, "Backend remoto por proveedor").
#
# `terraform init -backend=false` (el único modo que se ejecuta desde este
# repositorio sin credenciales de proveedor) ignora este bloque por completo.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }

  backend "s3" {
    # Backend S3-compatible (API de compatibilidad de OCI Object Storage) sin
    # locking nativo — ver docs/cloud.md. Rellena con -backend-config o con
    # un archivo backend.hcl fuera de Git (ver backend.hcl.example).
  }
}
