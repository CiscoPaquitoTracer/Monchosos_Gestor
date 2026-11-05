-- =====================================================================
-- Endurece el control de acceso (hallazgo de GitHub Advanced Security en el PR #14).
--
-- Antes bastaba con que el claim "email" del token estuviera en usuarios_permitidos.
-- Si alguien se registrara con correo/contraseña usando un correo de la lista y el
-- proyecto no exigiera confirmar el correo, obtendría acceso total.
--
-- Ahora además se exige:
--   * app_metadata.provider = 'google'  → solo lo escribe el servidor (no el usuario);
--   * user_metadata.email_verified = true → Google lo confirma (por sí solo no basta:
--     user_metadata lo puede editar el usuario, por eso va junto con el proveedor);
--   * que no sea una sesión anónima.
-- =====================================================================

CREATE OR REPLACE FUNCTION es_usuario_permitido() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT coalesce(auth.jwt() -> 'app_metadata' ->> 'provider', '') = 'google'
       AND lower(coalesce(auth.jwt() -> 'user_metadata' ->> 'email_verified', 'false')) = 'true'
       AND lower(coalesce(auth.jwt() ->> 'is_anonymous', 'false')) <> 'true'
       AND EXISTS (
           SELECT 1 FROM public.usuarios_permitidos
            WHERE correo = lower(coalesce(auth.jwt() ->> 'email', ''))
       )
$$;

-- La app consulta su propio renglón para saber si tiene acceso: con las mismas reglas.
DROP POLICY ver_mi_acceso ON usuarios_permitidos;
CREATE POLICY ver_mi_acceso ON usuarios_permitidos FOR SELECT TO authenticated
    USING (correo = lower(coalesce(auth.jwt() ->> 'email', '')) AND (SELECT es_usuario_permitido()));
