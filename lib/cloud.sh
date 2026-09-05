#!/usr/bin/env bash
# =============================================================================
# SecLab — despliegue cloud (Fase 10: DigitalOcean; Fase 11: GCP y Oracle Cloud)
# =============================================================================
# Se carga con `source` desde bin/seclab. Depende de lib/comun.sh y de las
# variables SECLAB_RAIZ y ARCHIVO_ENV.
#
# La nube es opcional y el gasto es SIEMPRE personal del alumno (ver
# prompt_v3.md, "Contexto y modelo de uso" y "Despliegue cloud"). Este
# archivo es deliberadamente conservador:
#
#   - Nunca ejecuta `terraform apply`/`destroy` sin haber comprobado antes,
#     en shell y en español, que `owner` y la fecha de expiración están
#     definidos y que el alumno ha escrito la confirmación de coste exacta.
#   - Nunca busca ni lee credenciales reales por su cuenta más allá de
#     comprobar que EXISTE una fuente declarada (variable de entorno o un
#     valor no vacío en terraform.tfvars), sin imprimir ni tocar su
#     contenido. Para Oracle Cloud esto es aún más estricto: nunca se
#     comprueba la ruta por defecto '~/.oci/config' (ver
#     exigir_credenciales_oracle más abajo).
#   - `seclab cloud plan|up|destroy` son los únicos subcomandos que invocan
#     Terraform con capacidad de tocar infraestructura real; el resto
#     (status/wait/connect) sólo lee estado o abre una sesión SSH.
#
# Generalización de la Fase 11: toda la lógica común a los tres proveedores
# (validación de owner/TTL, tabla de coste, confirmación literal, snapshot
# antes de destruir, llamadas a Terraform) vive en las funciones sin sufijo
# de proveedor de este archivo. Lo único que varía por proveedor son tres
# puntos, aislados cada uno en su propia función con sufijo _do/_gcp/_oracle:
# la comprobación de credenciales (cada proveedor se autentica distinto), la
# tabla de coste (cada uno publica tamaños y precios distintos) y el usuario
# SSH por defecto (DigitalOcean deja entrar como root; las imágenes Ubuntu de
# GCP y OCI no).
# =============================================================================

readonly SECLAB_CLOUD_PROVEEDORES="digitalocean gcp oracle"

# --- Utilidades básicas -------------------------------------------------------

proveedores_cloud_validos() { printf '%s' "$SECLAB_CLOUD_PROVEEDORES"; }

proveedor_cloud_valido() {
    case " $SECLAB_CLOUD_PROVEEDORES " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# directorio_cloud PROVEEDOR -> módulo Terraform de ese proveedor
directorio_cloud() {
    printf '%s/terraform/%s' "$SECLAB_RAIZ" "$1"
}

# exigir_terraform -> aborta con instrucciones si no hay `terraform` en PATH
exigir_terraform() {
    existe_comando terraform || abortar \
        "No se encuentra 'terraform' en el PATH." \
        "Ningún subcomando de 'seclab cloud' puede continuar sin él." \
        "Instálalo: https://developer.hashicorp.com/terraform/install"
}

# --- Argumentos comunes --------------------------------------------------------

# parsear_proveedor "$@" -> imprime el proveedor y dos ficheros auxiliares;
# uso: leer con `read -r proveedor tfvars <<< "$(parsear_proveedor "$@")"`
# no se usa así en la práctica: cada subcomando llama a cloud_leer_argumentos.
cloud_leer_argumentos() {
    CLOUD_PROVEEDOR=""
    CLOUD_TFVARS=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --provider|--proveedor) CLOUD_PROVEEDOR="${2:-}"; shift 2 ;;
            --tfvars)               CLOUD_TFVARS="${2:-}"; shift 2 ;;
            *) abortar "Opción desconocida: $1" "" \
                       "Uso: seclab cloud <subcomando> --provider digitalocean [--tfvars ARCHIVO]" ;;
        esac
    done
    [ -z "$CLOUD_PROVEEDOR" ] && abortar \
        "Falta --provider." \
        "No se sabe contra qué proveedor operar." \
        "Uso: seclab cloud <subcomando> --provider digitalocean. Proveedores: $(proveedores_cloud_validos)"
    proveedor_cloud_valido "$CLOUD_PROVEEDOR" || abortar \
        "Proveedor desconocido: ${CLOUD_PROVEEDOR}" \
        "SecLab sólo trae Terraform para DigitalOcean, GCP y Oracle Cloud (ver prompt_v3.md)." \
        "Proveedores válidos: $(proveedores_cloud_validos)"

    CLOUD_DIR="$(directorio_cloud "$CLOUD_PROVEEDOR")"
    [ -d "$CLOUD_DIR" ] || abortar \
        "No existe el módulo Terraform de '${CLOUD_PROVEEDOR}' (${CLOUD_DIR})." \
        "" "Revisa terraform/${CLOUD_PROVEEDOR}/README.md."

    local tfvars_por_defecto=false
    if [ -z "$CLOUD_TFVARS" ]; then
        CLOUD_TFVARS="${CLOUD_DIR}/terraform.tfvars"
        tfvars_por_defecto=true
    fi

    # Sólo cuando se usa la ruta por defecto (nadie pasó --tfvars a mano):
    # si el alumno pidió explícitamente otro archivo, es su terraform.tfvars
    # y SecLab no lo toca ni lo regenera.
    if [ "$tfvars_por_defecto" = true ] && [ "$CLOUD_PROVEEDOR" = "oracle" ]; then
        sincronizar_tfvars_oracle_desde_env
    fi

    return 0
}

# sincronizar_tfvars_oracle_desde_env
#
# A petición explícita del dueño del proyecto: en vez de mantener
# terraform/oracle/terraform.tfvars a mano, los datos de la cuenta de Oracle
# y la auth key de Tailscale se declaran en .env (igual que todo lo demás en
# SecLab) y este archivo se REGENERA por completo aquí, cada vez, a partir de
# esas variables — nunca al revés. No es un merge: si algo no está en .env,
# no aparece en terraform.tfvars, y las comprobaciones de más abajo
# (exigir_owner_y_ttl, exigir_credenciales_oracle) siguen siendo la barrera
# real.
#
# Autenticación de OCI: NUNCA se copian a .env ni a terraform.tfvars
# user_ocid/fingerprint/private_key_path. En vez de duplicar esas
# credenciales en un segundo sitio, se usa `config_file_profile = "DEFAULT"`
# — el mismo mecanismo con el que ya se autentica el propio CLI `oci` contra
# ~/.oci/config — así Terraform reutiliza esa configuración tal cual, sin que
# SecLab la lea, la copie ni la imprima en ningún momento.
sincronizar_tfvars_oracle_desde_env() {
    local tfvars="${CLOUD_DIR}/terraform.tfvars"
    local tenancy region compartment imagen owner ttl curso ssh_pub \
          registry imagen_ref hab_ts ts_key ts_host

    tenancy="$(leer_variable "$ARCHIVO_ENV" SECLAB_OCI_TENANCY_OCID)"
    region="$(leer_variable "$ARCHIVO_ENV" SECLAB_OCI_REGION)"
    compartment="$(leer_variable "$ARCHIVO_ENV" SECLAB_OCI_COMPARTMENT_OCID)"
    imagen="$(leer_variable "$ARCHIVO_ENV" SECLAB_OCI_IMAGE_OCID)"
    owner="$(leer_variable "$ARCHIVO_ENV" SECLAB_OCI_OWNER)"
    ttl="$(leer_variable "$ARCHIVO_ENV" SECLAB_OCI_TTL)"
    curso="$(leer_variable "$ARCHIVO_ENV" SECLAB_OCI_CURSO)"
    ssh_pub="$(leer_variable "$ARCHIVO_ENV" SECLAB_SSH_PUBKEY)"
    registry="$(leer_variable "$ARCHIVO_ENV" SECLAB_OCI_REGISTRY)"
    imagen_ref="$(leer_variable "$ARCHIVO_ENV" SECLAB_OCI_IMAGEN_REF)"
    hab_ts="$(leer_variable "$ARCHIVO_ENV" SECLAB_OCI_HABILITAR_TAILSCALE)"
    ts_key="$(leer_variable "$ARCHIVO_ENV" TAILSCALE_AUTH_KEY)"
    ts_host="$(leer_variable "$ARCHIVO_ENV" SECLAB_OCI_TAILSCALE_HOSTNAME)"

    # Si ninguna variable de Oracle está puesta en .env, no se toca
    # terraform.tfvars: puede que el alumno lo esté manteniendo a mano
    # todavía, siguiendo terraform.tfvars.example.
    if [ -z "$tenancy" ] && [ -z "$region" ] && [ -z "$owner" ]; then
        return 0
    fi

    umask 077
    {
        printf '# Generado automáticamente por seclab (sincronizar_tfvars_oracle_desde_env)\n'
        printf '# a partir de .env. NO editar a mano: los cambios se pierden en el próximo\n'
        printf '# "seclab cloud ... --provider oracle". Edita .env, no este archivo.\n\n'
        printf 'tenancy_ocid        = "%s"\n' "$tenancy"
        printf 'config_file_profile = "DEFAULT"\n'
        printf 'region              = "%s"\n' "$region"
        printf 'compartment_ocid    = "%s"\n' "${compartment:-$tenancy}"
        printf 'owner               = "%s"\n' "$owner"
        printf 'curso               = "%s"\n' "${curso:-seclab}"
        printf 'fecha_expiracion    = "%s"\n' "$ttl"
        printf 'image_ocid          = "%s"\n' "$imagen"
        printf 'ssh_public_key      = "%s"\n' "$ssh_pub"
        printf 'seclab_registry     = "%s"\n' "$registry"
        printf 'seclab_imagen_ref   = "%s"\n' "$imagen_ref"
        if [ "$hab_ts" = "true" ]; then
            printf 'habilitar_tailscale = true\n'
            printf 'tailscale_auth_key  = "%s"\n' "$ts_key"
            printf 'tailscale_hostname  = "%s"\n' "${ts_host:-seclab}"
        else
            printf 'habilitar_tailscale = false\n'
        fi
    } > "$tfvars"
    chmod 600 "$tfvars"
}

# valor_tfvars ARCHIVO CLAVE -> el valor de una asignación `clave = "valor"` o
# `clave = true/false` en un .tfvars. No es un parser de HCL completo (no lo
# necesita: sólo lee lo que el propio terraform.tfvars.example genera), pero
# basta para las comprobaciones de owner/TTL/coste que hace este archivo antes
# de invocar a Terraform.
valor_tfvars() {
    local archivo="$1" clave="$2"
    [ -f "$archivo" ] || return 0
    # No encontrar la clave es un resultado válido (el llamador ya trata la
    # cadena vacía como "no está puesta"), no un error: con `pipefail`
    # activo (bin/seclab hace `set -euo pipefail`), un grep sin coincidencias
    # haría fallar toda la tubería, y el fallo de una asignación como
    # `owner="$(valor_tfvars ...)"` mata el script entero en silencio (no es
    # la condición de un if/while, así que `set -e` no lo perdona). El `||
    # true` neutraliza justo eso, sin ocultar un fallo real de lectura del
    # archivo (ya comprobado arriba).
    { grep -E "^[[:space:]]*${clave}[[:space:]]*=" "$archivo" 2>/dev/null || true; } \
        | tail -1 \
        | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*(#.*)?$//; s/^"(.*)"$/\1/'
}

# --- Comprobaciones obligatorias antes de aplicar -----------------------------

# exigir_owner_y_ttl ARCHIVO_TFVARS
# Aplica en shell, con mensaje en español, la regla no negociable de
# prompt_v3.md: "rechazar aplicar si no hay TTL/fecha de expiración
# definida". variables.tf la repite en HCL como última barrera si alguien se
# salta el CLI, pero el mensaje de aquí es el que de verdad va a leer un
# alumno.
exigir_owner_y_ttl() {
    local tfvars="$1" owner fecha

    if [ ! -f "$tfvars" ]; then
        abortar "No existe ${tfvars}." \
                "Sin él no hay owner ni fecha de expiración que comprobar, y SecLab se niega a inventar valores por defecto para eso." \
                "Copia terraform/${CLOUD_PROVEEDOR}/terraform.tfvars.example a ${tfvars} y rellena TODOS los valores."
    fi

    owner="$(valor_tfvars "$tfvars" owner)"
    fecha="$(valor_tfvars "$tfvars" fecha_expiracion)"

    if [ -z "$owner" ] || [ "$owner" = "tu-nombre-aqui" ]; then
        abortar "Falta 'owner' (o sigue con el valor de ejemplo) en ${tfvars}." \
                "Un recurso cloud sin propietario declarado es exactamente lo que hace que una VM se quede encendida facturando sin que nadie se dé por aludido." \
                "Pon tu nombre o usuario del curso en owner dentro de ${tfvars}."
    fi
    if [ -z "$fecha" ]; then
        abortar "Falta 'fecha_expiracion' en ${tfvars}." \
                "Sin una fecha de caducidad, un laboratorio 'temporal' no tiene ningún mecanismo que recuerde destruirlo." \
                "Añade fecha_expiracion = \"AAAA-MM-DD\" en ${tfvars}."
    fi
    if ! printf '%s' "$fecha" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        abortar "'fecha_expiracion' en ${tfvars} no tiene forma AAAA-MM-DD: '${fecha}'." \
                "" "Corrígela, por ejemplo: fecha_expiracion = \"2026-12-31\"."
    fi

    CLOUD_OWNER="$owner"
    CLOUD_TTL="$fecha"
}

# exigir_credenciales_cloud TFVARS PROVEEDOR -> despacha a la comprobación de
# cada proveedor. Ninguna de las tres lee, imprime, ni busca credenciales en
# ningún sitio salvo lo explícitamente documentado.
exigir_credenciales_cloud() {
    local tfvars="$1" proveedor="$2"
    case "$proveedor" in
        digitalocean) exigir_credenciales_do "$tfvars" ;;
        gcp)          exigir_credenciales_gcp "$tfvars" ;;
        oracle)       exigir_credenciales_oracle "$tfvars" ;;
        *)            abortar "Proveedor sin comprobación de credenciales: ${proveedor}" "" \
                               "Esto es un fallo interno de lib/cloud.sh, no algo que puedas corregir tú." ;;
    esac
}

# exigir_credenciales_do
# Sólo COMPRUEBA que hay una fuente de credenciales; nunca la lee, la
# imprime, ni la busca en otro sitio que no sean estas dos rutas explícitas y
# documentadas (variable de entorno estándar del provider, o el propio
# terraform.tfvars que el alumno ha rellenado a mano).
exigir_credenciales_do() {
    local tfvars="$1"
    if [ -n "${DIGITALOCEAN_TOKEN:-}" ]; then
        return 0
    fi
    if [ -f "$tfvars" ] && [ -n "$(valor_tfvars "$tfvars" do_token)" ] \
        && [ "$(valor_tfvars "$tfvars" do_token)" != "REEMPLAZA_CON_TU_TOKEN_DE_DIGITALOCEAN" ]; then
        return 0
    fi
    abortar "No hay token de DigitalOcean configurado." \
            "Sin él, Terraform no puede autenticarse contra la API de DigitalOcean. SecLab no genera ni busca uno por ti." \
            "Define DIGITALOCEAN_TOKEN en tu entorno, o do_token en ${tfvars} (nunca lo subas a Git: ya está en .gitignore)."
}

# exigir_credenciales_gcp
# GCP se autentica con Application Default Credentials (ADC), no con un
# token único como DigitalOcean. Se comprueban, en este orden, las mismas
# rutas que documenta 'gcloud'/el provider "google" de Terraform: variable de
# entorno con la clave, variable con la ruta a un archivo de clave, el
# archivo que deja 'gcloud auth application-default login', o
# 'credentials_file' en el propio .tfvars. Nunca se lee el CONTENIDO de
# ninguna de ellas, sólo se comprueba su existencia.
exigir_credenciales_gcp() {
    local tfvars="$1" credentials_file
    if [ -n "${GOOGLE_CREDENTIALS:-}" ]; then
        return 0
    fi
    if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] && [ -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]; then
        return 0
    fi
    if [ -f "${HOME}/.config/gcloud/application_default_credentials.json" ]; then
        return 0
    fi
    if [ -f "$tfvars" ]; then
        credentials_file="$(valor_tfvars "$tfvars" credentials_file)"
        if [ -n "$credentials_file" ] && [ -f "$credentials_file" ]; then
            return 0
        fi
    fi
    abortar "No hay credenciales de Google Cloud (Application Default Credentials) configuradas." \
            "Sin ellas, Terraform no puede autenticarse contra la API de GCP. SecLab no genera ni busca ninguna por ti." \
            "Define GOOGLE_APPLICATION_CREDENTIALS con la ruta a una clave de cuenta de servicio, ejecuta 'gcloud auth application-default login', o pon credentials_file en ${tfvars}."
}

# exigir_credenciales_oracle
# A propósito, NUNCA comprueba la ruta por defecto '~/.oci/config' (donde el
# CLI oficial de OCI busca credenciales): exige que el propio .tfvars declare
# explícitamente private_key_path (autenticación clásica por clave de API), o
# que se use OCI_CLI_CONFIG_FILE / config_file_profile. Es una decisión
# deliberada (ver terraform/oracle/README.md, "Autenticación"), no un
# descuido: SecLab no debe depender —ni para comprobar su existencia— de un
# archivo de credenciales que pueda existir ya en la máquina por otro motivo.
exigir_credenciales_oracle() {
    local tfvars="$1"
    if [ -n "${OCI_CLI_CONFIG_FILE:-}" ]; then
        return 0
    fi
    if [ -f "$tfvars" ]; then
        if [ -n "$(valor_tfvars "$tfvars" private_key_path)" ]; then
            return 0
        fi
        if [ -n "$(valor_tfvars "$tfvars" config_file_profile)" ]; then
            return 0
        fi
    fi
    abortar "No hay credenciales de Oracle Cloud (OCI) declaradas en ${tfvars}." \
            "SecLab no comprueba '~/.oci/config' por su cuenta (ver terraform/oracle/README.md, 'Autenticación'): exige que tú declares explícitamente la fuente." \
            "Rellena tenancy_ocid/user_ocid/fingerprint/private_key_path en ${tfvars} (ver terraform.tfvars.example), o define OCI_CLI_CONFIG_FILE."
}

# usuario_ssh_cloud -> usuario del sistema para conectar por SSH a la
# instancia ya creada. DigitalOcean deja entrar como root por defecto y no
# declara una salida 'ssh_user' en su módulo (ver
# terraform/digitalocean/outputs.tf); GCP y Oracle sí la declaran porque sus
# imágenes de Ubuntu no permiten login directo de root. Se lee de las
# salidas de Terraform si existe, y se cae a 'root' si no (preserva el
# comportamiento exacto de la Fase 10 para DigitalOcean, sin tocar su
# módulo).
usuario_ssh_cloud() {
    local usuario
    usuario="$(cloud_salida ssh_user)"
    printf '%s' "${usuario:-root}"
}

# --- Tabla de costes (aproximada, estática) ------------------------------------
# Precios de referencia, uno por proveedor. APROXIMADOS y sujetos a cambio:
# son los públicos al escribir esto, no una consulta en vivo a ninguna API de
# precios. 'seclab cloud plan/up' avisan de esto cada vez; consulta la
# página de precios de cada proveedor para el valor real vigente.
tabla_costes_do() {
    cat <<'TABLA'
  SIZE (slug)      vCPU  RAM     USD/mes (aprox.)  USD/hora (aprox.)
  s-1vcpu-1gb      1     1 GB    $6                $0.009
  s-1vcpu-2gb      1     2 GB    $12               $0.018
  s-2vcpu-2gb      2     2 GB    $18               $0.027
  s-2vcpu-4gb      2     4 GB    $24               $0.036
  s-4vcpu-8gb      4     8 GB    $48               $0.071
TABLA
}

# Precios de referencia de Compute Engine (e2, us-central1, bajo demanda),
# públicos al escribir esto. No incluyen disco de arranque adicional al de
# 20 GB por defecto de este módulo, IP pública (efímera, sin coste aparte
# mientras está asignada), ni tráfico de salida por encima de la franquicia.
tabla_costes_gcp() {
    cat <<'TABLA'
  MACHINE_TYPE     vCPU        RAM     USD/mes (aprox.)  USD/hora (aprox.)
  e2-small         2 (compart.) 2 GB   $12               $0.017
  e2-medium        2 (compart.) 4 GB   $24               $0.034
  e2-standard-2    2            8 GB   $49               $0.067
  e2-standard-4    4            16 GB  $98               $0.134
TABLA
}

# Oracle Cloud tiene un "Always Free tier" con formas Ampere ARM
# (VM.Standard.A1.Flex, hasta 4 OCPU/24GB en total por tenancy al escribir
# esto) y una forma x86 micro (VM.Standard.E2.1.Micro). Dentro de esos
# límites el coste es CERO — pero los límites del free tier los fija y
# cambia Oracle, no SecLab: no lo des por garantizado sin comprobar la
# página oficial vigente. Fuera del free tier (formas de pago, o exceder los
# límites anteriores), se factura por OCPU-hora/GB-hora.
tabla_costes_oracle() {
    cat <<'TABLA'
  SHAPE                          OCPU/RAM        USD/mes (aprox.)
  VM.Standard.E2.1.Micro         1/8 OCPU, 1 GB  $0 (Always Free, límite 2 instancias/tenancy)
  VM.Standard.A1.Flex (1/6GB)    1 OCPU, 6 GB    $0 si no excedes el total Always Free del tenancy
  VM.Standard.A1.Flex (2/12GB)   2 OCPU, 12 GB   $0 si no excedes el total Always Free del tenancy
  VM.Standard.A1.Flex (4/24GB)   4 OCPU, 24 GB   Límite superior típico del Always Free
  VM.Standard3.Flex (de pago)    variable        ~$0.03 USD/OCPU-hora aprox. si excedes el free tier
TABLA
}

# tabla_costes_cloud PROVEEDOR -> despacha a la tabla de ese proveedor
tabla_costes_cloud() {
    case "$1" in
        digitalocean) tabla_costes_do ;;
        gcp)          tabla_costes_gcp ;;
        oracle)       tabla_costes_oracle ;;
    esac
}

# coste_aproximado_size SIZE -> "USD/mes USD/hora", o "?" si no está en la tabla
coste_aproximado_size() {
    case "$1" in
        s-1vcpu-1gb) printf '%s %s' 6 0.009 ;;
        s-1vcpu-2gb) printf '%s %s' 12 0.018 ;;
        s-2vcpu-2gb) printf '%s %s' 18 0.027 ;;
        s-2vcpu-4gb) printf '%s %s' 24 0.036 ;;
        s-4vcpu-8gb) printf '%s %s' 48 0.071 ;;
        e2-small)      printf '%s %s' 12 0.017 ;;
        e2-medium)     printf '%s %s' 24 0.034 ;;
        e2-standard-2) printf '%s %s' 49 0.067 ;;
        e2-standard-4) printf '%s %s' 98 0.134 ;;
        VM.Standard.E2.1.Micro) printf '%s %s' 0 0 ;;
        VM.Standard.A1.Flex)    printf '%s %s' '0*' '0*' ;;
        *) printf '%s %s' '?' '?' ;;
    esac
}

# tamano_por_defecto PROVEEDOR -> nombre de tamaño/máquina/forma por defecto,
# usado cuando el .tfvars no fija 'size'/'machine_type'/'shape' (coincide con
# el default de cada variables.tf).
tamano_por_defecto() {
    case "$1" in
        digitalocean) printf 's-2vcpu-4gb' ;;
        gcp)          printf 'e2-medium' ;;
        oracle)       printf 'VM.Standard.A1.Flex' ;;
    esac
}

# clave_tamano_tfvars PROVEEDOR -> nombre de la variable de tamaño en el
# .tfvars de ese proveedor (distinto por proveedor: 'size' en DigitalOcean,
# 'machine_type' en GCP, 'shape' en Oracle).
clave_tamano_tfvars() {
    case "$1" in
        digitalocean) printf 'size' ;;
        gcp)          printf 'machine_type' ;;
        oracle)       printf 'shape' ;;
    esac
}

# --- Confirmación de coste, literal y consciente -------------------------------
# No reutiliza `confirmar` (que acepta s/S/sí para cualquier pregunta): aquí
# se exige la palabra exacta 'acepto', porque es una decisión de gasto
# personal y no una confirmación genérica de "¿seguro?".
confirmar_coste() {
    local respuesta
    if [ ! -t 0 ]; then
        error "Se necesita confirmación interactiva y no hay terminal disponible." \
              "Por seguridad (es dinero real y personal), esto nunca se auto-aprueba." \
              "Ejecuta 'seclab cloud up' desde una terminal interactiva."
        return 1
    fi
    printf '%s' "${C_AMARILLO}?${C_FIN} Escribe exactamente 'acepto' para continuar (cualquier otra cosa cancela): " >&2
    read -r respuesta
    [ "$respuesta" = "acepto" ]
}

# aviso_coste_personal -> el mismo bloque de advertencia en cada punto donde
# se puede generar o mantener gasto (up, plan, status). Repetido a propósito:
# prompt_v3.md pide que el aviso sea "prominente", no una nota a pie de página
# que se lee una vez y se olvida.
aviso_coste_personal() {
    local nombre_proveedor
    case "$CLOUD_PROVEEDOR" in
        digitalocean) nombre_proveedor="DigitalOcean" ;;
        gcp)          nombre_proveedor="Google Cloud" ;;
        oracle)       nombre_proveedor="Oracle Cloud" ;;
        *)            nombre_proveedor="$CLOUD_PROVEEDOR" ;;
    esac
    titulo "Aviso de gasto personal"
    aviso "El coste de esta infraestructura lo factura ${nombre_proveedor} A TI, no a SecLab ni a la universidad."
    detalle "SecLab no gestiona presupuestos ni asume ningún cargo. Revisa la fecha de expiración"
    detalle "que has declarado y destrúyela con 'seclab cloud destroy --provider ${CLOUD_PROVEEDOR}'"
    detalle "en cuanto termines: una instancia olvidada sigue facturando aunque no la uses."
    printf '\n' >&2
}

# =============================================================================
# Subcomandos
# =============================================================================

cloud_plan() {
    cloud_leer_argumentos "$@"
    exigir_terraform
    exigir_owner_y_ttl "$CLOUD_TFVARS"
    exigir_credenciales_cloud "$CLOUD_TFVARS" "$CLOUD_PROVEEDOR"

    local clave_tamano size
    clave_tamano="$(clave_tamano_tfvars "$CLOUD_PROVEEDOR")"
    size="$(valor_tfvars "$CLOUD_TFVARS" "$clave_tamano")"
    size="${size:-$(tamano_por_defecto "$CLOUD_PROVEEDOR")}"

    aviso_coste_personal
    titulo "Estimación de coste (aproximada, ver docs/cloud.md)"
    tabla_costes_cloud "$CLOUD_PROVEEDOR" >&2
    printf '\n' >&2
    detalle "Tamaño configurado en ${CLOUD_TFVARS} (${clave_tamano}): ${size}"
    printf '\n' >&2

    titulo "terraform plan — ${CLOUD_PROVEEDOR}"
    detalle "owner=${CLOUD_OWNER}  fecha_expiracion=${CLOUD_TTL}"
    (
        cd "$CLOUD_DIR" || exit 1
        terraform init -input=false && \
        terraform plan -input=false -var-file="$CLOUD_TFVARS"
    )
}

cloud_up() {
    cloud_leer_argumentos "$@"
    exigir_terraform
    exigir_owner_y_ttl "$CLOUD_TFVARS"
    exigir_credenciales_cloud "$CLOUD_TFVARS" "$CLOUD_PROVEEDOR"

    local clave_tamano size mes hora
    clave_tamano="$(clave_tamano_tfvars "$CLOUD_PROVEEDOR")"
    size="$(valor_tfvars "$CLOUD_TFVARS" "$clave_tamano")"
    size="${size:-$(tamano_por_defecto "$CLOUD_PROVEEDOR")}"
    read -r mes hora <<< "$(coste_aproximado_size "$size")"

    aviso_coste_personal
    titulo "Vas a crear infraestructura real en DigitalOcean"
    detalle "Proveedor:         ${CLOUD_PROVEEDOR}"
    detalle "Propietario:       ${CLOUD_OWNER}"
    detalle "Expira:            ${CLOUD_TTL}  (recuérdalo: no hay autodestrucción por defecto, ver docs/cloud.md)"
    detalle "Tamaño:             ${size} (~\$${mes} USD/mes, ~\$${hora} USD/hora — aproximado, ver docs/cloud.md)"
    printf '\n' >&2
    aviso "Este cargo es personal y tuyo. SecLab no lo paga ni lo reembolsa."
    printf '\n' >&2

    if ! confirmar_coste; then
        abortar "No se ha creado nada." "" \
                "Cuando quieras continuar, repite 'seclab cloud up --provider ${CLOUD_PROVEEDOR}' y escribe 'acepto'."
    fi

    titulo "terraform apply — ${CLOUD_PROVEEDOR}"
    (
        cd "$CLOUD_DIR" || exit 1
        terraform init -input=false && \
        terraform apply -input=false -var-file="$CLOUD_TFVARS"
    ) || abortar "El apply de Terraform ha fallado o se ha cancelado." \
                  "Puede haber quedado infraestructura parcial: revisa con 'seclab cloud status --provider ${CLOUD_PROVEEDOR}'." \
                  "El detalle del error de Terraform está arriba."

    printf '\n' >&2
    ok "Apply completado."
    detalle "Espera a que el bootstrap termine con: seclab cloud wait --provider ${CLOUD_PROVEEDOR}"
    detalle "Destrúyelo en cuanto termines con:      seclab cloud destroy --provider ${CLOUD_PROVEEDOR}"
}

# cloud_salida CLAVE -> lee `terraform output -json` una sola vez por
# invocación y cachea el resultado en CLOUD_OUTPUTS_JSON, para no relanzar
# terraform por cada dato que se necesita.
cloud_cargar_salidas() {
    if [ -z "${CLOUD_OUTPUTS_JSON:-}" ]; then
        CLOUD_OUTPUTS_JSON="$(cd "$CLOUD_DIR" && terraform output -json 2>/dev/null)" || CLOUD_OUTPUTS_JSON=""
    fi
    if [ -z "$CLOUD_OUTPUTS_JSON" ] || [ "$CLOUD_OUTPUTS_JSON" = "{}" ]; then
        abortar "No hay salidas de Terraform para '${CLOUD_PROVEEDOR}' (¿backend remoto sin credenciales, o nada desplegado todavía?)." \
                "Con un backend remoto, leer el estado exige las mismas credenciales que aplicar: es una limitación real, documentada en docs/cloud.md, no un simple 'no hay nada'." \
                "Si ya hiciste 'seclab cloud up', comprueba tus credenciales de backend. Si no, ejecútalo primero."
    fi
}

cloud_salida() {
    printf '%s' "$CLOUD_OUTPUTS_JSON" | python3 -c "
import json,sys
d = json.load(sys.stdin)
v = d.get('$1', {}).get('value', '')
print(v)
" 2>/dev/null
}

cloud_status() {
    cloud_leer_argumentos "$@"
    exigir_terraform

    titulo "Estado — ${CLOUD_PROVEEDOR}"
    cloud_cargar_salidas

    local ip owner fecha creado hoy
    ip="$(cloud_salida ip_publica)"
    owner="$(cloud_salida owner)"
    fecha="$(cloud_salida fecha_expiracion)"
    creado="$(cloud_salida creado_en)"

    printf '  %-20s %s\n' "IP pública" "${ip:-?}" >&2
    printf '  %-20s %s\n' "Propietario" "${owner:-?}" >&2
    printf '  %-20s %s\n' "Creado" "${creado:-?}" >&2
    printf '  %-20s %s\n' "Expira" "${fecha:-?}" >&2

    if [ -n "$fecha" ]; then
        hoy="$(date -u '+%Y-%m-%d')"
        if [[ "$hoy" > "$fecha" ]]; then
            printf '\n' >&2
            error "El TTL declarado (${fecha}) ya ha pasado." \
                  "Esta instancia sigue facturando aunque el plazo que fijaste haya vencido: el proveedor no la apaga ni la borra sola (salvo que hayas activado la autodestrucción opcional; ver docs/cloud.md)." \
                  "Destrúyela ya: seclab cloud destroy --provider ${CLOUD_PROVEEDOR}"
        else
            printf '\n' >&2
            aviso "Recuerda destruirla antes de ${fecha}: seclab cloud destroy --provider ${CLOUD_PROVEEDOR}"
        fi
    fi
    aviso_coste_personal
}

cloud_wait() {
    local timeout=600
    # cloud_leer_argumentos no conoce --timeout; se separa antes.
    local args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --timeout) timeout="${2:-600}"; shift 2 ;;
            *) args+=("$1"); shift ;;
        esac
    done
    cloud_leer_argumentos "${args[@]}"
    exigir_terraform
    cloud_cargar_salidas

    local ip puerto llave usuario transcurrido=0 intervalo=10
    ip="$(cloud_salida ip_publica)"
    puerto="$(cloud_salida puerto_ssh)"
    usuario="$(usuario_ssh_cloud)"
    llave="$(localizar_llave_ssh)"
    [ -z "$ip" ] && abortar "No hay IP pública en las salidas de Terraform." "" \
                            "¿Se completó 'seclab cloud up --provider ${CLOUD_PROVEEDOR}'?"

    titulo "Esperando el bootstrap de ${ip}:${puerto} (timeout ${timeout}s)"
    while [ "$transcurrido" -lt "$timeout" ]; do
        if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
               -i "$llave" -p "$puerto" "${usuario}@${ip}" \
               'test -f /etc/seclab-cloud/bootstrap-completo && grep -q ^listo /etc/seclab-cloud/bootstrap-completo' \
               >/dev/null 2>&1; then
            printf '\n' >&2
            ok "Bootstrap completado."
            detalle "Conéctate con: seclab cloud connect --provider ${CLOUD_PROVEEDOR}"
            return 0
        fi
        printf '.' >&2
        sleep "$intervalo"
        transcurrido=$((transcurrido + intervalo))
    done
    printf '\n' >&2
    abortar "Se ha agotado el timeout (${timeout}s) esperando el bootstrap." \
            "El cloud-init puede seguir en marcha, haber fallado, o el firewall/SSH puede no estar listo todavía." \
            "Revisa manualmente: ssh -i '${llave}' -p ${puerto} ${usuario}@${ip} 'cloud-init status; journalctl -u seclab -n 50'"
}

cloud_connect() {
    cloud_leer_argumentos "$@"
    exigir_terraform
    cloud_cargar_salidas

    local ip puerto llave usuario
    ip="$(cloud_salida ip_publica)"
    puerto="$(cloud_salida puerto_ssh)"
    usuario="$(usuario_ssh_cloud)"
    llave="$(localizar_llave_ssh)"
    [ -z "$ip" ] && abortar "No hay IP pública en las salidas de Terraform." "" \
                            "¿Se completó 'seclab cloud up --provider ${CLOUD_PROVEEDOR}'?"

    titulo "Conectando a ${ip}:${puerto}"
    detalle "Los servicios web (bienvenida/noVNC/code-server/Jupyter) sólo escuchan en 127.0.0.1"
    detalle "DENTRO de la instancia. Para llegar a ellos desde tu máquina, añade -L al ssh, por ejemplo:"
    detalle "  ssh -i '${llave}' -p ${puerto} -L 8080:127.0.0.1:8080 ${usuario}@${ip}"
    exec ssh -i "$llave" -p "$puerto" -o StrictHostKeyChecking=accept-new "${usuario}@${ip}"
}

cloud_destroy() {
    cloud_leer_argumentos "$@"
    exigir_terraform
    exigir_credenciales_cloud "$CLOUD_TFVARS" "$CLOUD_PROVEEDOR"

    titulo "Destrucción — ${CLOUD_PROVEEDOR}"
    aviso "Esto borra la instancia y su red/firewall. El volumen del directorio personal y del"
    detalle "workspace remotos NO se pueden exportar después de destruir: es ahora o nunca."
    printf '\n' >&2

    if confirmar "¿Quieres exportar el workspace de la VM antes de destruirla (recomendado)?"; then
        cloud_exportar_workspace_remoto
    else
        aviso "Continuando SIN exportar. Lo que haya en la VM y no esté ya en tu máquina se pierde."
    fi

    printf '\n' >&2
    if ! confirmar "¿Confirmas destruir la infraestructura de '${CLOUD_PROVEEDOR}' AHORA MISMO?"; then
        abortar "No se ha destruido nada." "" "Repite 'seclab cloud destroy --provider ${CLOUD_PROVEEDOR}' cuando quieras."
    fi

    (
        cd "$CLOUD_DIR" || exit 1
        terraform init -input=false && \
        terraform destroy -input=false -var-file="$CLOUD_TFVARS"
    ) || abortar "El destroy de Terraform ha fallado o se ha cancelado." \
                  "Puede haber quedado infraestructura a medio destruir." \
                  "Revisa 'seclab cloud status --provider ${CLOUD_PROVEEDOR}' y el detalle de arriba."

    ok "Infraestructura de '${CLOUD_PROVEEDOR}' destruida."
}

# cloud_exportar_workspace_remoto
# Reutiliza el formato de 'seclab backup' (tar del workspace remoto vía SSH),
# pero como copia SÓLO del workspace de la VM: el resto de una copia normal
# (secretos/, vpn/, .env) es local y no vive en la Droplet.
cloud_exportar_workspace_remoto() {
    cloud_cargar_salidas
    local ip puerto llave usuario destino archivo
    ip="$(cloud_salida ip_publica)"
    puerto="$(cloud_salida puerto_ssh)"
    usuario="$(usuario_ssh_cloud)"
    llave="$(localizar_llave_ssh)"
    destino="$(directorio_copias)"
    install -d -m 0700 "$destino" 2>/dev/null || true
    archivo="${destino}/seclab-cloud-${CLOUD_PROVEEDOR}-$(date '+%Y%m%d-%H%M%S').tar.gz"

    info "Exportando /workspace de la VM a ${archivo}"
    if ssh -i "$llave" -p "$puerto" -o StrictHostKeyChecking=accept-new "${usuario}@${ip}" \
        "docker exec seclab tar -czf - -C / workspace" > "$archivo" 2>/dev/null \
        && [ -s "$archivo" ]; then
        chmod 600 "$archivo"
        ok "Workspace remoto exportado: ${archivo}"
    else
        rm -f "$archivo"
        aviso "No se ha podido exportar el workspace remoto (¿la VM no responde por SSH?)."
        detalle "Puedes intentarlo a mano: seclab cloud connect --provider ${CLOUD_PROVEEDOR}, y desde dentro 'tar' tu /workspace."
    fi
}
