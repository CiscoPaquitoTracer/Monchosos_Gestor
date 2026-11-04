-- =====================================================================
-- Monchosos · Seguridad (Row Level Security)
--
-- La app habla directo con Supabase usando la llave pública (publishable),
-- así que la protección real vive AQUÍ, en la base de datos:
--   * anon (sin sesión): no ve ni toca nada.
--   * authenticated (sesión de Google): solo si su correo está en usuarios_permitidos.
--   * Sin roles: los permitidos pueden hacer todo (es una pareja).
-- =====================================================================

-- ¿El usuario de la sesión actual está autorizado?
-- SECURITY DEFINER para poder leer usuarios_permitidos sin depender de sus políticas.
CREATE FUNCTION es_usuario_permitido() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.usuarios_permitidos
         WHERE correo = lower(coalesce(auth.jwt() ->> 'email', ''))
    )
$$;

-- Activa RLS y una política "todo para el equipo" en cada tabla de negocio.
DO $$
DECLARE t text;
BEGIN
    FOR t IN
        SELECT tablename FROM pg_tables
         WHERE schemaname = 'public' AND tablename <> 'usuarios_permitidos'
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format(
            'CREATE POLICY equipo_todo ON public.%I FOR ALL TO authenticated
                 USING ((SELECT es_usuario_permitido())) WITH CHECK ((SELECT es_usuario_permitido()))', t);
    END LOOP;
END $$;

-- usuarios_permitidos: cada quien solo puede ver su propio renglón (para que la app
-- sepa si tiene acceso). Altas y bajas solo desde el panel de Supabase.
ALTER TABLE usuarios_permitidos ENABLE ROW LEVEL SECURITY;
CREATE POLICY ver_mi_acceso ON usuarios_permitidos FOR SELECT TO authenticated
    USING (correo = lower(coalesce(auth.jwt() ->> 'email', '')));

-- Sin sesión no hay nada que ver.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
REVOKE ALL ON usuarios_permitidos FROM authenticated;
GRANT SELECT ON usuarios_permitidos TO authenticated;

-- Las funciones internas (triggers y descuento de inventario) van a un esquema privado
-- que la API de Supabase no expone (/rpc solo publica "public"). Los triggers siguen
-- funcionando porque apuntan a la función, no a su nombre.
CREATE SCHEMA interno;
REVOKE ALL ON SCHEMA interno FROM public;
GRANT USAGE ON SCHEMA interno TO authenticated;

DO $$
DECLARE f record;
BEGIN
    FOR f IN
        SELECT p.oid::regprocedure AS firma
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname LIKE 'fn\_%'
    LOOP
        EXECUTE format('ALTER FUNCTION %s SET SCHEMA interno', f.firma);
    END LOOP;
END $$;

-- Se llaman entre sí por nombre: que se encuentren en su nuevo esquema.
ALTER FUNCTION interno.fn_venta_detalle_inventario() SET search_path = public, interno;
ALTER FUNCTION interno.fn_venta_componente_inventario() SET search_path = public, interno;
ALTER FUNCTION interno.fn_venta_estado_inventario() SET search_path = public, interno;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA interno FROM public, anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA interno TO authenticated;
REVOKE EXECUTE ON FUNCTION es_usuario_permitido() FROM public, anon;
GRANT EXECUTE ON FUNCTION es_usuario_permitido() TO authenticated;

-- Lo que se cree después en public tampoco queda abierto para anon por defecto.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM public, anon;
