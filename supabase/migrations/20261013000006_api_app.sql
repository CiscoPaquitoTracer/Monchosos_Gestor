-- =====================================================================
-- Funciones que usa la app (se llaman por /rpc). Corren con los permisos del
-- usuario (SECURITY INVOKER), así que RLS sigue aplicando.
-- =====================================================================

-- Artículos por venta, para la lista de pedidos (columna nueva al final de la vista).
CREATE OR REPLACE VIEW v_ventas WITH (security_invoker = true) AS
SELECT x.*, x.total - x.pagado AS pendiente, coalesce(a.articulos, 0) AS articulos
  FROM (
    SELECT v.*,
           coalesce(d.subtotal, 0)                              AS subtotal,
           greatest(coalesce(d.subtotal, 0) - v.descuento, 0)   AS total,
           coalesce(p.pagado, 0)                                AS pagado
      FROM ventas v
      LEFT JOIN (SELECT venta_id, sum(subtotal) AS subtotal FROM venta_detalle GROUP BY venta_id) d
             ON d.venta_id = v.id
      LEFT JOIN (SELECT venta_id, sum(monto) AS pagado FROM pagos GROUP BY venta_id) p ON p.venta_id = v.id
  ) x
  LEFT JOIN (SELECT venta_id, sum(cantidad)::int AS articulos FROM venta_detalle GROUP BY venta_id) a
         ON a.venta_id = x.id;

-- Búsquedas por nombre (la app conoce el menú por nombre, la BD valida que exista) --
CREATE FUNCTION interno.producto_por_nombre(p_categoria text, p_nombre text) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE r bigint;
BEGIN
    SELECT p.id INTO r FROM productos p JOIN categorias_menu c ON c.id = p.categoria_id
     WHERE c.nombre = p_categoria AND p.nombre = p_nombre;
    IF r IS NULL THEN
        RAISE EXCEPTION 'No existe en el menú: % / %', p_categoria, p_nombre;
    END IF;
    RETURN r;
END $$;

CREATE FUNCTION interno.variante_por_nombre(p_producto_id bigint, p_nombre text) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE r bigint;
BEGIN
    IF p_nombre IS NULL THEN RETURN NULL; END IF;
    SELECT id INTO r FROM variantes WHERE producto_id = p_producto_id AND nombre = p_nombre;
    IF r IS NULL THEN
        RAISE EXCEPTION 'No existe la variante "%"', p_nombre;
    END IF;
    RETURN r;
END $$;

CREATE FUNCTION interno.sabor_por_nombre(p_nombre text) RETURNS smallint
LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE r smallint;
BEGIN
    IF p_nombre IS NULL THEN RETURN NULL; END IF;
    SELECT id INTO r FROM sabores WHERE nombre = p_nombre;
    IF r IS NULL THEN
        RAISE EXCEPTION 'No existe el sabor "%"', p_nombre;
    END IF;
    RETURN r;
END $$;

-- guardar_venta ---------------------------------------------------------------
-- Crea (sin "id") o reemplaza (con "id") un pedido completo en UNA transacción:
-- {
--   "id": null, "tipo_entrega": "local|para_llevar|domicilio",
--   "cliente": "", "telefono": "", "direccion": "", "notas": "",
--   "renglones": [{
--       "categoria": "Burgers", "producto": "Junior", "variante": null, "sabor": null,
--       "cantidad": 1, "precio_unitario": 75, "notas": "",
--       "componentes": [{"categoria": "...", "producto": "...", "variante": null, "sabor": null, "cantidad": 1}]
--   }]
-- }
CREATE FUNCTION guardar_venta(datos jsonb) RETURNS bigint
LANGUAGE plpgsql SET search_path = public, interno AS $$
DECLARE
    v_id   bigint := nullif(datos ->> 'id', '')::bigint;
    r      jsonb;
    c      jsonb;
    p_id   bigint;
    d_id   bigint;
    cp_id  bigint;
BEGIN
    IF jsonb_array_length(coalesce(datos -> 'renglones', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'El pedido no tiene productos';
    END IF;
    IF datos ->> 'tipo_entrega' = 'domicilio' AND coalesce(trim(datos ->> 'direccion'), '') = '' THEN
        RAISE EXCEPTION 'Falta la dirección de entrega';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO ventas (tipo_entrega, cliente, telefono, direccion, notas)
        VALUES (coalesce(datos ->> 'tipo_entrega', 'local'),
                nullif(trim(datos ->> 'cliente'), ''), nullif(trim(datos ->> 'telefono'), ''),
                nullif(trim(datos ->> 'direccion'), ''), nullif(trim(datos ->> 'notas'), ''))
        RETURNING id INTO v_id;
    ELSE
        UPDATE ventas
           SET tipo_entrega = coalesce(datos ->> 'tipo_entrega', 'local'),
               cliente   = nullif(trim(datos ->> 'cliente'), ''),
               telefono  = nullif(trim(datos ->> 'telefono'), ''),
               direccion = nullif(trim(datos ->> 'direccion'), ''),
               notas     = nullif(trim(datos ->> 'notas'), '')
         WHERE id = v_id AND estado <> 'cancelada';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El pedido % no existe o está cancelado', v_id;
        END IF;
        DELETE FROM venta_detalle WHERE venta_id = v_id;   -- devuelve sus insumos (trigger)
    END IF;

    FOR r IN SELECT value FROM jsonb_array_elements(datos -> 'renglones') LOOP
        p_id := producto_por_nombre(r ->> 'categoria', r ->> 'producto');
        INSERT INTO venta_detalle (venta_id, producto_id, variante_id, sabor_id, cantidad, precio_unitario, notas)
        VALUES (v_id, p_id, variante_por_nombre(p_id, r ->> 'variante'), sabor_por_nombre(r ->> 'sabor'),
                coalesce((r ->> 'cantidad')::smallint, 1), (r ->> 'precio_unitario')::numeric,
                nullif(trim(r ->> 'notas'), ''))
        RETURNING id INTO d_id;

        FOR c IN SELECT value FROM jsonb_array_elements(coalesce(r -> 'componentes', '[]'::jsonb)) LOOP
            cp_id := producto_por_nombre(c ->> 'categoria', c ->> 'producto');
            INSERT INTO venta_componentes (detalle_id, producto_id, variante_id, sabor_id, cantidad)
            VALUES (d_id, cp_id, variante_por_nombre(cp_id, c ->> 'variante'), sabor_por_nombre(c ->> 'sabor'),
                    coalesce((c ->> 'cantidad')::smallint, 1));
        END LOOP;
    END LOOP;

    RETURN v_id;
END $$;

-- Inventario ----------------------------------------------------------------------
-- Crea o edita un insumo. Si "cantidad" cambia, registra un movimiento "ajuste"
-- (la existencia nunca se edita a mano: así la bitácora siempre cuadra).
CREATE FUNCTION guardar_insumo(datos jsonb) RETURNS bigint
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    i_id     bigint  := nullif(datos ->> 'id', '')::bigint;
    deseada  numeric := (datos ->> 'cantidad')::numeric;
    actual   numeric;
BEGIN
    IF i_id IS NULL THEN
        INSERT INTO insumos (nombre, categoria, unidad, stock_minimo, costo_unitario)
        VALUES (trim(datos ->> 'nombre'), datos ->> 'categoria', datos ->> 'unidad',
                coalesce((datos ->> 'stock_minimo')::numeric, 0), coalesce((datos ->> 'costo_unitario')::numeric, 0))
        RETURNING id, cantidad INTO i_id, actual;
    ELSE
        UPDATE insumos
           SET nombre = trim(datos ->> 'nombre'), categoria = datos ->> 'categoria', unidad = datos ->> 'unidad',
               stock_minimo = coalesce((datos ->> 'stock_minimo')::numeric, 0),
               costo_unitario = coalesce((datos ->> 'costo_unitario')::numeric, 0),
               activo = true
         WHERE id = i_id
        RETURNING cantidad INTO actual;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El insumo % no existe', i_id;
        END IF;
    END IF;

    IF deseada IS NOT NULL AND deseada <> actual THEN
        INSERT INTO movimientos_inventario (insumo_id, tipo, cantidad, notas)
        VALUES (i_id, 'ajuste', deseada - actual, 'Ajuste desde la app');
    END IF;
    RETURN i_id;
END $$;

-- Botones − / + de la app. No deja la existencia por debajo de 0. Devuelve la nueva cantidad.
CREATE FUNCTION ajustar_existencia(p_insumo_id bigint, p_delta numeric) RETURNS numeric
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    actual numeric;
    delta  numeric;
BEGIN
    SELECT cantidad INTO actual FROM insumos WHERE id = p_insumo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El insumo % no existe', p_insumo_id;
    END IF;
    delta := greatest(p_delta, -greatest(actual, 0));
    IF delta <> 0 THEN
        INSERT INTO movimientos_inventario (insumo_id, tipo, cantidad, notas)
        VALUES (p_insumo_id, 'ajuste', delta, 'Ajuste rápido desde la app');
    END IF;
    RETURN actual + delta;
END $$;

REVOKE EXECUTE ON FUNCTION guardar_venta(jsonb), guardar_insumo(jsonb), ajustar_existencia(bigint, numeric)
    FROM public, anon;
GRANT EXECUTE ON FUNCTION guardar_venta(jsonb), guardar_insumo(jsonb), ajustar_existencia(bigint, numeric)
    TO authenticated;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA interno FROM public, anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA interno TO authenticated;
