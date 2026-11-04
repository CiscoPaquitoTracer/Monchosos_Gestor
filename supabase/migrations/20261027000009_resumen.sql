-- =====================================================================
-- Resumen del mes (lo que antes sacaban del Excel): cuánto se vendió y se cobró,
-- cuánto costó lo vendido, gastos, productos más vendidos y mejores días.
--
-- Incluye el historial importado (historial_ventas, ej. Comandas.xlsx). Como ese
-- historial solo tiene cantidades, su dinero se calcula con los precios ACTUALES y se
-- marca como estimado.
-- =====================================================================

-- Productos vendidos por día: de la app (precio con que se vendió) y del historial
-- (precio actual). Si un día está en los dos, manda la app.
CREATE VIEW v_productos_por_dia WITH (security_invoker = true) AS
WITH app AS (
    SELECT (v.fecha AT TIME ZONE 'America/Mexico_City')::date AS dia, d.producto_id, d.variante_id,
           sum(d.cantidad) AS cantidad, sum(d.subtotal) AS total
      FROM ventas v
      JOIN venta_detalle d ON d.venta_id = v.id
     WHERE v.estado <> 'cancelada'
     GROUP BY 1, 2, 3
)
SELECT dia, producto_id, variante_id, cantidad, total, false AS estimado FROM app
UNION ALL
SELECT h.dia, h.producto_id, h.variante_id, h.cantidad, h.cantidad * coalesce(va.precio, p.precio, 0), true
  FROM historial_ventas h
  JOIN productos p       ON p.id = h.producto_id
  LEFT JOIN variantes va ON va.id = h.variante_id
 WHERE NOT h.componente AND h.dia NOT IN (SELECT dia FROM app);

-- Total vendido entre dos fechas [desde, hasta): ventas de la app (ya con descuentos)
-- más lo estimado del historial.
CREATE FUNCTION interno.total_vendido(p_desde date, p_hasta date) RETURNS numeric
LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT coalesce((SELECT sum(v.total) FROM v_ventas v
                      WHERE v.estado <> 'cancelada'
                        AND (v.fecha AT TIME ZONE 'America/Mexico_City')::date >= p_desde
                        AND (v.fecha AT TIME ZONE 'America/Mexico_City')::date <  p_hasta), 0)
         + coalesce((SELECT sum(p.total) FROM v_productos_por_dia p
                      WHERE p.estimado AND p.dia >= p_desde AND p.dia < p_hasta), 0)
$$;

-- Resumen del mes que contiene p_fecha. Montos en pesos. Ver ResumenRepository en la app.
CREATE FUNCTION resumen_mes(p_fecha date) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = public, interno AS $$
    WITH r AS (
        SELECT date_trunc('month', p_fecha)::date AS desde,
               (date_trunc('month', p_fecha) + interval '1 month')::date AS hasta,
               (date_trunc('month', p_fecha) - interval '1 month')::date AS anterior
    ),
    ventas_mes AS (
        SELECT v.* FROM v_ventas v, r
         WHERE v.estado <> 'cancelada'
           AND (v.fecha AT TIME ZONE 'America/Mexico_City')::date >= r.desde
           AND (v.fecha AT TIME ZONE 'America/Mexico_City')::date <  r.hasta
    ),
    prod AS (SELECT p.* FROM v_productos_por_dia p, r WHERE p.dia >= r.desde AND p.dia < r.hasta),
    -- Dinero por día: app (total real) + historial (estimado).
    por_dia AS (
        SELECT (fecha AT TIME ZONE 'America/Mexico_City')::date AS dia, sum(total) AS total FROM ventas_mes GROUP BY 1
        UNION ALL
        SELECT dia, sum(total) FROM prod WHERE estimado GROUP BY 1
    ),
    consumo AS (
        SELECT c.cantidad, i.costo_unitario FROM v_consumo_por_dia c, r, insumos i
         WHERE i.id = c.insumo_id AND c.dia >= r.desde AND c.dia < r.hasta
    )
    SELECT jsonb_build_object(
        'desde',             r.desde,
        'ventas',            total_vendido(r.desde, r.hasta),
        'ventas_estimadas',  coalesce((SELECT sum(total) FROM prod WHERE estimado), 0),
        'ventas_mes_anterior', total_vendido(r.anterior, r.desde),
        'pedidos',           (SELECT count(*) FROM ventas_mes),
        'productos',         coalesce((SELECT sum(cantidad) FROM prod), 0),
        'dias_abiertos',     (SELECT count(DISTINCT dia) FROM por_dia),
        'descuentos',        coalesce((SELECT sum(descuento) FROM ventas_mes), 0),
        'por_cobrar',        coalesce((SELECT sum(pendiente) FROM ventas_mes WHERE pendiente > 0), 0),
        'cobrado', (SELECT coalesce(jsonb_object_agg(metodo, monto), '{}'::jsonb)
                      FROM (SELECT pg.metodo, sum(pg.monto) AS monto
                              FROM pagos pg JOIN ventas_mes vm ON vm.id = pg.venta_id
                             GROUP BY pg.metodo) x),
        -- Costo de lo vendido según recetas y costo de cada insumo (0 si el insumo no tiene costo).
        'costo_insumos',     coalesce((SELECT round(sum(cantidad * costo_unitario), 2) FROM consumo), 0),
        'insumos_sin_costo', (SELECT count(*) FROM consumo WHERE costo_unitario = 0),
        'gastos', coalesce((SELECT sum(g.monto) FROM gastos g, r
                             WHERE (g.fecha AT TIME ZONE 'America/Mexico_City')::date >= r.desde
                               AND (g.fecha AT TIME ZONE 'America/Mexico_City')::date <  r.hasta), 0),
        'compras', coalesce((SELECT sum(cd.costo_total) FROM compras c JOIN compra_detalle cd ON cd.compra_id = c.id, r
                              WHERE (c.fecha AT TIME ZONE 'America/Mexico_City')::date >= r.desde
                                AND (c.fecha AT TIME ZONE 'America/Mexico_City')::date <  r.hasta), 0),
        'top_productos', coalesce((
            SELECT jsonb_agg(t ORDER BY t.cantidad DESC, t.total DESC)
              -- Mismos nombres que la app: "Papas Junior", "Burger Junior", "Doggo Junior", "Alitas 5 piezas".
              FROM (SELECT concat_ws(' ', CASE c.nombre
                                              WHEN 'Papas' THEN 'Papas'
                                              WHEN 'Aderezos Extra' THEN 'Aderezo'
                                              WHEN 'Burgers' THEN CASE WHEN pr.nombre = 'Junior' THEN 'Burger' END
                                              WHEN 'Doggos Jumbo' THEN CASE WHEN pr.nombre = 'Junior' THEN 'Doggo' END
                                          END,
                                          pr.nombre, va.nombre) AS nombre,
                           sum(p.cantidad) AS cantidad, sum(p.total) AS total
                      FROM prod p
                      JOIN productos pr      ON pr.id = p.producto_id
                      JOIN categorias_menu c ON c.id = pr.categoria_id
                      LEFT JOIN variantes va ON va.id = p.variante_id
                     GROUP BY 1
                     ORDER BY 2 DESC, 3 DESC
                     LIMIT 5) t), '[]'::jsonb),
        -- 1 = lunes … 7 = domingo; promedio vendido por día abierto.
        'por_dia_semana', coalesce((
            SELECT jsonb_agg(jsonb_build_object('dia_semana', dow, 'dias', dias, 'total', total) ORDER BY dow)
              FROM (SELECT extract(isodow FROM dia)::int AS dow, count(DISTINCT dia) AS dias, sum(total) AS total
                      FROM por_dia GROUP BY 1) s), '[]'::jsonb)
    )
    FROM r
$$;

REVOKE EXECUTE ON FUNCTION resumen_mes(date), interno.total_vendido(date, date) FROM public, anon;
GRANT EXECUTE ON FUNCTION resumen_mes(date), interno.total_vendido(date, date) TO authenticated;
