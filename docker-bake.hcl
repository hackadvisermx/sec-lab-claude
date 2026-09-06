// =============================================================================
// SecLab — construcción de imágenes con Docker Bake
// =============================================================================
// Uso local (una sola arquitectura, la tuya):
//     docker buildx bake lite
//
// Publicación multi-arquitectura: sólo desde CI (Fase 8), donde hay emulación
// y credenciales de registry.
//     docker buildx bake lite-multiarch --push
//
// El esquema de etiquetado es seclab-<perfil>:<version>-<commit>, como manda
// la política de versiones.
// =============================================================================

variable "SECLAB_VERSION" { default = "0.1.0" }
variable "SECLAB_COMMIT"  { default = "local" }
variable "SECLAB_FECHA"   { default = "desconocida" }
variable "SECLAB_REGISTRY" { default = "" }

// Prefijo del registry, con la barra sólo si hay registry.
function "prefijo" {
  params = []
  result = SECLAB_REGISTRY == "" ? "" : "${SECLAB_REGISTRY}/"
}

function "etiquetas" {
  params = [perfil]
  result = [
    "${prefijo()}seclab-${perfil}:${SECLAB_VERSION}-${SECLAB_COMMIT}",
    "${prefijo()}seclab-${perfil}:${SECLAB_VERSION}",
  ]
}

target "_comun" {
  context    = "."
  dockerfile = "docker/Dockerfile"
  args = {
    SECLAB_VERSION = SECLAB_VERSION
    SECLAB_COMMIT  = SECLAB_COMMIT
    SECLAB_FECHA   = SECLAB_FECHA
  }
}

// --- Perfiles implementados -------------------------------------------------

// Sin `platforms`: se construye para la arquitectura de quien lo ejecuta.
// Fijar una aquí rompería el build de cualquier alumno con la otra.
target "lite" {
  inherits = ["_comun"]
  target   = "lite"
  tags     = etiquetas("lite")
}

target "lite-multiarch" {
  inherits  = ["lite"]
  platforms = ["linux/amd64", "linux/arm64"]
}

target "full" {
  inherits = ["_comun"]
  target   = "full"
  tags     = etiquetas("full")
}

target "full-multiarch" {
  inherits  = ["full"]
  platforms = ["linux/amd64", "linux/arm64"]
}

// full-msf nunca entra en el grupo por defecto: es opt-in explícito.
target "full-msf" {
  inherits = ["_comun"]
  target   = "full-msf"
  tags     = etiquetas("full-msf")
}

target "full-msf-multiarch" {
  inherits  = ["full-msf"]
  platforms = ["linux/amd64", "linux/arm64"]
}

group "default" {
  targets = ["lite"]
}

// Los perfiles que se publican en cada versión. `full-msf` va aparte.
group "todos" {
  targets = ["lite", "full"]
}
