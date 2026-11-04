#!/bin/sh
# Etapa "Desplegar web" del Jenkinsfile: sube a Cloudflare Pages
#   /      la página de descarga (pagina/)
#   /app/  la PWA (build/web, compilada con --base-href /app/)
#
#   ci/desplegar_web.sh <rama>
#     main  → producción: https://<proyecto>.pages.dev
#     PR-12 → prueba:     https://pr-12.<proyecto>.pages.dev
#
# Necesita CLOUDFLARE_API_TOKEN (permiso Cloudflare Pages: Edit) y CLOUDFLARE_ACCOUNT_ID.
set -eu

RAMA="${1:?Falta la rama (main o PR-N)}"
PROYECTO="${CF_PROYECTO:-monchosos}"
SITIO=.sitio-web

rm -rf "$SITIO"
cp -r pagina "$SITIO"
cp -r build/web "$SITIO/app"

# La primera vez el proyecto no existe: se crea con main como rama de producción.
if ! wrangler pages project list 2>/dev/null | grep -qw "$PROYECTO"; then
    echo "Creando el proyecto $PROYECTO en Cloudflare Pages..."
    wrangler pages project create "$PROYECTO" --production-branch=main
fi

wrangler pages deploy "$SITIO" \
    --project-name="$PROYECTO" \
    --branch="$RAMA" \
    --commit-hash="${GIT_COMMIT:-desconocido}" \
    --commit-message="Jenkins build ${BUILD_NUMBER:-local} ($RAMA)" \
    --commit-dirty=true

rm -rf "$SITIO"
