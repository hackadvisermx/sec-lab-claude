# =============================================================================
# SecLab — GCP, versiones
# =============================================================================
# El backend SÍ se declara con un tipo concreto y estable: "gcs" (Google Cloud
# Storage). A diferencia de DigitalOcean Spaces (ver
# terraform/digitalocean/versions.tf), el backend "gcs" de Terraform tiene
# LOCKING NATIVO desde siempre: usa las precondiciones de generación de objeto
# de GCS (una escritura condicional a nivel de API), sin necesitar una tabla
# tipo DynamoDB ni ningún servicio adicional. Es una diferencia real entre
# proveedores, no un detalle menor (ver docs/cloud.md, "Backend remoto por
# proveedor").
#
# Aun así, los VALORES concretos (bucket, prefix) no se fijan aquí: se pasan
# por configuración parcial (`-backend-config`, ver backend.hcl.example), para
# no acoplar el módulo a un bucket de un alumno concreto ni versionarlo.
#
# `terraform init -backend=false` (el único modo que se ejecuta desde este
# repositorio sin credenciales de proveedor) ignora este bloque por completo.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    # Backend GCS con locking nativo (ver comentario de arriba). Rellena con
    # -backend-config="bucket=..." -backend-config="prefix=..." o con un
    # archivo backend.hcl fuera de Git (ver backend.hcl.example).
  }
}
