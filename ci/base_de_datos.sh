#!/bin/sh
# Etapa "Base de datos" del Jenkinsfile: migraciones, linter y supabase/tests/pruebas.sql.
#
#   ci/base_de_datos.sh probar   levanta Postgres de Supabase, aplica todo y prueba
#   ci/base_de_datos.sh limpiar  borra el contenedor y la red (siempre, en post { always })
#
# No usa `supabase db start`: desde el contenedor de build intenta conectarse a 127.0.0.1:54322,
# donde no hay nada (la base queda en el Docker del host). En su lugar levanta la misma imagen de
# Postgres de Supabase en una red propia y conecta este contenedor a esa red.
set -eu

IMAGEN="${BD_IMAGEN:-public.ecr.aws/supabase/postgres:17.11.0.003}"
NOMBRE="${BD_NOMBRE:-monchosos-bd-ci}"
YO="$(hostname)"   # id del contenedor de build
URL="postgresql://postgres:postgres@$NOMBRE:5432/postgres"
# El esquema auth es de supabase_admin (misma contraseña en la imagen).
URL_ADMIN="postgresql://supabase_admin:postgres@$NOMBRE:5432/postgres"

limpiar() {
    docker network disconnect -f "$NOMBRE" "$YO" > /dev/null 2>&1 || true
    docker rm -f "$NOMBRE" > /dev/null 2>&1 || true
    docker network rm "$NOMBRE" > /dev/null 2>&1 || true
}

if [ "${1:-}" = "limpiar" ]; then
    limpiar
    exit 0
fi

limpiar   # por si quedó algo de un build anterior que se canceló
docker network create "$NOMBRE" > /dev/null
docker run -d --name "$NOMBRE" --network "$NOMBRE" -e POSTGRES_PASSWORD=postgres "$IMAGEN" > /dev/null
docker network connect "$NOMBRE" "$YO"

echo "Esperando a Postgres..."
listo=0
for _ in $(seq 1 90); do
    if psql "$URL" -tAc 'select 1' > /dev/null 2>&1; then
        listo=1
        break
    fi
    sleep 2
done
if [ "$listo" != 1 ]; then
    docker logs --tail 50 "$NOMBRE"
    echo "Postgres no arrancó" >&2
    exit 1
fi

echo "Funciones de auth que en Supabase crea el servicio de Auth..."
psql "$URL_ADMIN" -v ON_ERROR_STOP=1 -q -f ci/auth_supabase.sql

echo "Aplicando migraciones..."
for m in supabase/migrations/*.sql; do
    echo "  $m"
    psql "$URL" -v ON_ERROR_STOP=1 -q -f "$m"
done

echo "Linter de la base de datos..."
supabase db lint --db-url "$URL?sslmode=disable" --level warning --fail-on warning

echo "Pruebas (supabase/tests/pruebas.sql)..."
psql "$URL" -v ON_ERROR_STOP=1 -q -f supabase/tests/pruebas.sql
echo "Base de datos: todo bien."
