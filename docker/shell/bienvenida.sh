#!/usr/bin/env bash
# =============================================================================
# SecLab — página de bienvenida local
# =============================================================================
# Genera la página que abre `seclab open`. Se regenera en cada arranque a partir
# del estado real del contenedor: sólo enseña los accesos de los servicios que
# están de verdad activos, porque una página que anuncia un endpoint apagado
# enseña a desconfiar de la herramienta.
#
# Aquí NO entra ningún secreto. Ni la contraseña de code-server, ni la de VNC,
# ni ningún token: la página se sirve por HTTP y acabaría en el historial del
# navegador, en una captura de pantalla o en el proyector de un aula. Se dice
# dónde está cada secreto, no cuál es.
# =============================================================================

set -uo pipefail

SALIDA="${1:-/run/seclab/web/index.html}"

PERFIL="${SECLAB_PERFIL:-lite}"
VERSION="${SECLAB_VERSION:-desconocida}"
USUARIO="${SECLAB_USUARIO:-seclab}"
ARQ="$(dpkg --print-architecture 2>/dev/null || uname -m)"

# Puertos del HOST: la página se abre en el navegador del alumno, no dentro del
# contenedor, así que los enlaces tienen que llevar los puertos publicados.
P_SSH="${SECLAB_PUERTO_SSH:-2222}"
P_NOVNC="${SECLAB_PUERTO_NOVNC:-6080}"
P_CODE="${SECLAB_PUERTO_CODE:-8443}"

herramientas=0
if [ -r /opt/seclab/manifiesto-herramientas.txt ]; then
    herramientas="$(grep -c '^|' /opt/seclab/manifiesto-herramientas.txt 2>/dev/null || echo 0)"
    # Se descuentan la cabecera de la tabla y su separador.
    herramientas=$(( herramientas > 2 ? herramientas - 2 : 0 ))
fi

servicio() {
    # servicio NOMBRE URL DESCRIPCIÓN
    cat <<TARJETA
      <a class="tarjeta" href="${2}">
        <h2>${1}</h2>
        <p>${3}</p>
        <code>${2}</code>
      </a>
TARJETA
}

install -d -m 0755 "$(dirname "$SALIDA")"

{
cat <<'CABECERA'
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SecLab</title>
<style>
  :root { color-scheme: light dark; --fondo:#1a1b26; --texto:#c0caf5; --tenue:#565f89;
          --borde:#292e42; --acento:#7aa2f7; --tarjeta:#1f2335; }
  * { box-sizing:border-box }
  body { margin:0; padding:2.5rem 1.5rem; background:var(--fondo); color:var(--texto);
         font:16px/1.55 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif }
  main { max-width:52rem; margin:0 auto }
  h1 { margin:0 0 .25rem; font-size:1.75rem; letter-spacing:-.02em }
  .estado { color:var(--tenue); margin:0 0 2rem; font-size:.95rem }
  .rejilla { display:grid; gap:1rem; grid-template-columns:repeat(auto-fit,minmax(15rem,1fr)) }
  .tarjeta { display:block; padding:1.1rem 1.2rem; background:var(--tarjeta);
             border:1px solid var(--borde); border-radius:.6rem; text-decoration:none;
             color:inherit }
  .tarjeta:hover { border-color:var(--acento) }
  .tarjeta h2 { margin:0 0 .35rem; font-size:1.05rem; color:var(--acento) }
  .tarjeta p { margin:0 0 .6rem; font-size:.9rem; color:var(--texto) }
  code { font:0.85rem ui-monospace,SFMono-Regular,Menlo,monospace; color:var(--tenue);
         word-break:break-all }
  section { margin-top:2.25rem }
  h3 { font-size:.85rem; text-transform:uppercase; letter-spacing:.08em;
       color:var(--tenue); margin:0 0 .6rem }
  pre { margin:0; padding:.9rem 1rem; background:var(--tarjeta); border:1px solid var(--borde);
        border-radius:.5rem; overflow-x:auto; font:0.85rem/1.5 ui-monospace,Menlo,monospace }
  .aviso { margin-top:2.5rem; padding:1rem 1.2rem; border-left:3px solid var(--acento);
           background:var(--tarjeta); font-size:.9rem }
  .aviso strong { color:var(--acento) }
  footer { margin-top:2.5rem; color:var(--tenue); font-size:.8rem }
</style>
</head>
<body>
<main>
CABECERA

printf '  <h1>SecLab</h1>\n'
printf '  <p class="estado">versión %s · perfil <strong>%s</strong> · %s · %s herramientas en el manifiesto</p>\n' \
    "$VERSION" "$PERFIL" "$ARQ" "$herramientas"

printf '  <div class="rejilla">\n'

if [ "${SECLAB_HABILITAR_DESKTOP:-false}" = "true" ]; then
    servicio "Escritorio (noVNC)" "http://127.0.0.1:${P_NOVNC}/vnc.html" \
             "XFCE en el navegador. Pide la contraseña de VNC."
fi
if [ "${SECLAB_HABILITAR_CODE:-false}" = "true" ]; then
    servicio "code-server" "http://127.0.0.1:${P_CODE}/" \
             "VS Code sobre /workspace. Pide la contraseña de code-server."
fi
if [ "${SECLAB_HABILITAR_JUPYTER:-false}" = "true" ]; then
    servicio "Jupyter" "http://127.0.0.1:${SECLAB_PUERTO_JUPYTER:-8888}/" \
             "Cuadernos sobre /workspace."
fi

printf '  </div>\n'

cat <<SSH
  <section>
    <h3>Terminal</h3>
    <pre>seclab shell
ssh -i secretos/seclab_ed25519 -p ${P_SSH} ${USUARIO}@127.0.0.1</pre>
  </section>
SSH

cat <<'SECRETOS'
  <section>
    <h3>Contraseñas</h3>
    <pre>grep SECLAB_ .env</pre>
    <p class="estado">Esta página no muestra ninguna: se sirve por HTTP y
    acabaría en el historial del navegador o en el proyector del aula. Están en
    tu <code>.env</code>, con permisos 600.</p>
  </section>

  <div class="aviso">
    <strong>Uso autorizado.</strong> Este laboratorio no comprueba contra qué
    lanzas las herramientas: eso es tu responsabilidad. Úsalo sólo contra
    sistemas propios, contra las plataformas donde tengas cuenta, o dentro del
    alcance por escrito de un encargo. Ver <code>docs/uso-autorizado.md</code>.
  </div>

  <footer>
    Página generada en el arranque del contenedor a partir de su estado real.
    Si un servicio no aparece aquí, no está activo.
  </footer>
</main>
</body>
</html>
SECRETOS
} > "$SALIDA"

chmod 0644 "$SALIDA"
