-- =====================================================================
-- Pruebas automáticas de la base de datos.
-- Se ejecutan dentro de una transacción que se deshace al final (no deja rastro).
--
--   Local:  npx supabase@2.118.0 db start   y luego
--           docker exec -i supabase_db_Gestor_Hamburgueseria psql -U postgres -v ON_ERROR_STOP=1 -f - < supabase/tests/pruebas.sql
--
-- Requiere las migraciones de supabase/migrations. Crea sus propios datos de prueba.
-- =====================================================================
\set QUIET on
BEGIN;

CREATE FUNCTION pg_temp.prod(p_categoria text, p_nombre text) RETURNS bigint LANGUAGE sql AS
$$ SELECT p.id FROM productos p JOIN categorias_menu c ON c.id = p.categoria_id
    WHERE c.nombre = p_categoria AND p.nombre = p_nombre $$;
CREATE FUNCTION pg_temp.stock(p_nombre text) RETURNS numeric LANGUAGE sql AS
$$ SELECT cantidad FROM insumos WHERE nombre = p_nombre $$;

-- 1. Menú completo -------------------------------------------------------
DO $$ BEGIN
    ASSERT (SELECT count(*) FROM categorias_menu) = 9, 'Deben existir 9 categorías (8 del menú + Extras)';
    ASSERT (SELECT count(*) FROM productos) = 36, 'Deben existir 36 productos (35 del menú + Extra)';
    ASSERT (SELECT count(*) FROM variantes) = 4, 'Alitas y boneless tienen 2 variantes cada uno';
    ASSERT (SELECT precio FROM v_menu WHERE categoria = 'Boneless' AND variante = '10 piezas') = 130,
        'Boneless 10 piezas cuesta $130';
    ASSERT (SELECT count(*) FROM combo_opciones o JOIN combo_grupos g ON g.id = o.grupo_id
             WHERE g.combo_id = pg_temp.prod('Combos', 'Solitario') AND g.nombre = 'Refresco') = 5,
        'El Solitario permite cualquiera de los 5 refrescos';
    RAISE NOTICE '✔ 1. Menú';
END $$;

-- 2. Corte de caja ----------------------------------------------------------
DO $$
DECLARE t bigint; v bigint; d bigint; c record;
BEGIN
    INSERT INTO turnos (abierto_en, cerrado_en, fondo_inicial, efectivo_contado)
    VALUES (now() - interval '9 hours', now(), 500, 100) RETURNING id INTO t;

    -- 2 Sweet Bacon + 2 Coca = $230 → efectivo
    INSERT INTO ventas (turno_id, estado) VALUES (t, 'pagada') RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id, cantidad) VALUES
        (v, pg_temp.prod('Burgers', 'Sweet Bacon'), 2), (v, pg_temp.prod('Refrescos', 'Coca Cola 600 ml'), 2);
    INSERT INTO pagos (venta_id, metodo, monto) VALUES (v, 'efectivo', 230);

    -- Solitario + Perro Callejero = $210 → $110 efectivo + $100 transferencia
    INSERT INTO ventas (turno_id, estado) VALUES (t, 'pagada') RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id) VALUES
        (v, pg_temp.prod('Combos', 'Solitario')), (v, pg_temp.prod('Doggos Jumbo', 'El Perro Callejero'));
    INSERT INTO pagos (venta_id, metodo, monto) VALUES (v, 'efectivo', 110), (v, 'transferencia', 100);

    -- Alitas 10 piezas + aderezo = $155 → tarjeta
    INSERT INTO ventas (turno_id, estado) VALUES (t, 'pagada') RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id, variante_id) VALUES
        (v, pg_temp.prod('Alitas', 'Alitas'),
            (SELECT id FROM variantes WHERE producto_id = pg_temp.prod('Alitas', 'Alitas') AND nombre = '10 piezas'));
    INSERT INTO venta_detalle (venta_id, producto_id) VALUES (v, pg_temp.prod('Aderezos Extra', 'Cheddar'));
    INSERT INTO pagos (venta_id, metodo, monto) VALUES (v, 'tarjeta', 155);

    -- Cancelada: no cuenta
    INSERT INTO ventas (turno_id, estado) VALUES (t, 'cancelada') RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id) VALUES (v, pg_temp.prod('Burgers', 'Glotona'));

    -- Abierta con pago parcial: Bonchosa + Boing = $110, abonó $50
    INSERT INTO ventas (turno_id) VALUES (t) RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id) VALUES
        (v, pg_temp.prod('Burgers', 'Bonchosa')), (v, pg_temp.prod('Refrescos', 'Boing 500 ml'));
    INSERT INTO pagos (venta_id, metodo, monto) VALUES (v, 'efectivo', 50);
    ASSERT (SELECT pendiente FROM v_ventas WHERE id = v) = 60, 'La venta abierta debe $60';

    -- Gasto y compra en efectivo durante el turno
    INSERT INTO gastos (turno_id, categoria, monto) VALUES (t, 'gas', 550);
    INSERT INTO compras (turno_id, metodo_pago) VALUES (t, 'efectivo') RETURNING id INTO d;
    INSERT INTO compra_detalle (compra_id, insumo_id, cantidad, costo_total)
    VALUES (d, (SELECT id FROM insumos WHERE nombre = 'Jitomate'), 2, 184);

    SELECT * INTO c FROM v_corte_turno WHERE turno_id = t;
    ASSERT c.pedidos = 4,                      format('4 pedidos (sin la cancelada), hay %s', c.pedidos);
    ASSERT c.total_ventas = 705,               format('Ventas $705, hay %s', c.total_ventas);
    ASSERT c.cobrado_efectivo = 390,           format('Efectivo $390, hay %s', c.cobrado_efectivo);
    ASSERT c.cobrado_transferencia = 100,      format('Transferencia $100, hay %s', c.cobrado_transferencia);
    ASSERT c.cobrado_tarjeta = 155,            format('Tarjeta $155, hay %s', c.cobrado_tarjeta);
    ASSERT c.gastos = 550 AND c.compras = 184, 'Gastos $550 y compras $184';
    ASSERT c.balance = -29,                    format('Balance $705 - 550 - 184 = -29, hay %s', c.balance);
    ASSERT c.efectivo_esperado = 156,          format('Efectivo esperado 500+390-550-184 = 156, hay %s', c.efectivo_esperado);
    ASSERT c.diferencia_caja = -56,            format('Faltan $56 en caja, hay %s', c.diferencia_caja);
    RAISE NOTICE '✔ 2. Corte de caja';
END $$;

-- 3. Precio por defecto, congelado e historial ----------------------------
DO $$
DECLARE v bigint; d bigint;
BEGIN
    INSERT INTO ventas DEFAULT VALUES RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id) VALUES (v, pg_temp.prod('Burgers', 'Junior'))
    RETURNING id INTO d;
    ASSERT (SELECT precio_unitario FROM venta_detalle WHERE id = d) = 75, 'Toma el precio actual ($75)';

    UPDATE productos SET precio = 80 WHERE id = pg_temp.prod('Burgers', 'Junior');
    ASSERT (SELECT precio_unitario FROM venta_detalle WHERE id = d) = 75,
        'Cambiar el menú no altera ventas ya hechas';
    ASSERT EXISTS (SELECT 1 FROM historial_precios
                    WHERE producto_id = pg_temp.prod('Burgers', 'Junior')
                      AND precio_anterior = 75 AND precio_nuevo = 80), 'Se registra el cambio de precio';
    RAISE NOTICE '✔ 3. Precios';
END $$;

-- 4. Validaciones -----------------------------------------------------------
DO $$
DECLARE v bigint;
BEGIN
    INSERT INTO ventas DEFAULT VALUES RETURNING id INTO v;
    BEGIN
        INSERT INTO venta_detalle (venta_id, producto_id) VALUES (v, pg_temp.prod('Alitas', 'Alitas'));
        RAISE EXCEPTION 'Debió fallar: alitas sin variante';
    EXCEPTION WHEN raise_exception THEN
        ASSERT SQLERRM LIKE '%se vende por variante%', SQLERRM;
    END;
    BEGIN
        INSERT INTO venta_detalle (venta_id, producto_id, sabor_id)
        VALUES (v, pg_temp.prod('Burgers', 'Glotona'), (SELECT id FROM sabores WHERE nombre = 'BBQ'));
        RAISE EXCEPTION 'Debió fallar: sabor en una hamburguesa';
    EXCEPTION WHEN raise_exception THEN
        ASSERT SQLERRM LIKE '%no está disponible%', SQLERRM;
    END;
    BEGIN
        INSERT INTO turnos (fondo_inicial) VALUES (100);   -- primer turno abierto: OK
        INSERT INTO turnos (fondo_inicial) VALUES (100);   -- segundo: debe fallar
        RAISE EXCEPTION 'Debió fallar: dos turnos abiertos';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    RAISE NOTICE '✔ 4. Validaciones';
END $$;

-- 5. Inventario: compras, ventas, combos y cancelaciones --------------------
DO $$
DECLARE v bigint; d bigint; pan0 numeric; carne0 numeric; coca0 numeric; c bigint;
BEGIN
    pan0   := pg_temp.stock('Pan para hamburguesa');
    carne0 := pg_temp.stock('Carne molida');
    coca0  := pg_temp.stock('Refresco Coca Cola 600 ml');

    -- Venta: 2 Sweet Bacon (0.300 kg c/u) + combo con 1 Coca
    INSERT INTO ventas DEFAULT VALUES RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id, cantidad) VALUES (v, pg_temp.prod('Burgers', 'Sweet Bacon'), 2);
    INSERT INTO venta_detalle (venta_id, producto_id) VALUES (v, pg_temp.prod('Combos', 'Solitario')) RETURNING id INTO d;
    INSERT INTO venta_componentes (detalle_id, producto_id) VALUES
        (d, pg_temp.prod('Burgers', 'Sweet Bacon')),
        (d, pg_temp.prod('Refrescos', 'Coca Cola 600 ml'));
    ASSERT pg_temp.stock('Pan para hamburguesa') = pan0 - 3, 'Descuenta 3 panes (2 + 1 del combo)';
    ASSERT pg_temp.stock('Carne molida') = carne0 - 0.900, 'Descuenta 0.9 kg de carne';
    ASSERT pg_temp.stock('Refresco Coca Cola 600 ml') = coca0 - 1, 'El combo descuenta su refresco';

    -- Cambiar cantidad del combo a 2 → duplica componentes
    UPDATE venta_detalle SET cantidad = 2 WHERE id = d;
    ASSERT pg_temp.stock('Refresco Coca Cola 600 ml') = coca0 - 2, 'Combo x2 descuenta 2 refrescos';

    -- Cancelar devuelve todo; reabrir vuelve a descontar
    UPDATE ventas SET estado = 'cancelada' WHERE id = v;
    ASSERT pg_temp.stock('Pan para hamburguesa') = pan0, 'Cancelar devuelve los panes';
    ASSERT pg_temp.stock('Refresco Coca Cola 600 ml') = coca0, 'Cancelar devuelve los refrescos';
    UPDATE ventas SET estado = 'abierta' WHERE id = v;
    ASSERT pg_temp.stock('Pan para hamburguesa') = pan0 - 4, 'Reabrir vuelve a descontar (2 + 2 del combo)';

    -- Borrar la venta devuelve todo
    DELETE FROM ventas WHERE id = v;
    ASSERT pg_temp.stock('Pan para hamburguesa') = pan0, 'Borrar la venta devuelve los panes';

    -- Compra suma, actualiza costo; editarla y borrarla se refleja
    INSERT INTO compras DEFAULT VALUES RETURNING id INTO c;
    INSERT INTO compra_detalle (compra_id, insumo_id, cantidad, costo_total)
    VALUES (c, (SELECT id FROM insumos WHERE nombre = 'Pan para hamburguesa'), 10, 70) RETURNING id INTO d;
    ASSERT pg_temp.stock('Pan para hamburguesa') = pan0 + 10, 'La compra suma 10 panes';
    ASSERT (SELECT costo_unitario FROM insumos WHERE nombre = 'Pan para hamburguesa') = 7, 'Costo unitario $7';
    UPDATE compra_detalle SET cantidad = 12 WHERE id = d;
    ASSERT pg_temp.stock('Pan para hamburguesa') = pan0 + 12, 'Editar la compra corrige la existencia';
    DELETE FROM compras WHERE id = c;
    ASSERT pg_temp.stock('Pan para hamburguesa') = pan0, 'Borrar la compra resta lo que había sumado';
    RAISE NOTICE '✔ 5. Inventario';
END $$;

-- 6. La existencia coincide con la bitácora ----------------------------------
DO $$ BEGIN
    ASSERT NOT EXISTS (
        SELECT 1 FROM insumos i
          LEFT JOIN (SELECT insumo_id, sum(cantidad) AS s FROM movimientos_inventario GROUP BY 1) m
                 ON m.insumo_id = i.id
         WHERE i.cantidad <> coalesce(m.s, 0)
    ), 'insumos.cantidad debe ser igual a la suma de sus movimientos';
    RAISE NOTICE '✔ 6. Bitácora de inventario consistente';
END $$;

-- 7. Lo que salió de Comandas.xlsx: descuentos, extras, "Mercado" y pagos de deuda ----
DO $$
DECLARE t bigint; v bigint; pr bigint; c record;
BEGIN
    ASSERT (SELECT saldo FROM v_prestamos WHERE acreedor = 'Mamá') = 0, 'El préstamo de Mamá está saldado';
    ASSERT EXISTS (SELECT 1 FROM proveedores WHERE nombre = 'Sheila'), 'El proveedor es Sheila';

    INSERT INTO turnos (abierto_en, cerrado_en) VALUES (now() - interval '3 days', now()) RETURNING id INTO t;

    -- 2 Glotonas con 10 % de descuento → $216 en efectivo
    INSERT INTO ventas (turno_id, descuento, motivo_descuento) VALUES (t, 24, '10 % inauguración') RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id, cantidad) VALUES (v, pg_temp.prod('Burgers', 'Glotona'), 2);
    INSERT INTO pagos (venta_id, metodo, monto) VALUES (v, 'efectivo', 216);
    ASSERT (SELECT total FROM v_ventas WHERE id = v) = 216, 'Total con descuento $216';
    ASSERT (SELECT pendiente FROM v_ventas WHERE id = v) = 0, 'Pagada completa';
    BEGIN
        UPDATE ventas SET motivo_descuento = NULL WHERE id = v;
        RAISE EXCEPTION 'Debió fallar: descuento sin motivo';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- Bonchosa + Extra de $45 (aderezos) → $135 por Mercado Pago
    INSERT INTO ventas (turno_id) VALUES (t) RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id) VALUES (v, pg_temp.prod('Burgers', 'Bonchosa'));
    BEGIN
        INSERT INTO venta_detalle (venta_id, producto_id) VALUES (v, pg_temp.prod('Extras', 'Extra'));
        RAISE EXCEPTION 'Debió fallar: extra sin precio';
    EXCEPTION WHEN raise_exception THEN
        ASSERT SQLERRM LIKE '%precio libre%', SQLERRM;
    END;
    INSERT INTO venta_detalle (venta_id, producto_id, precio_unitario, notas)
    VALUES (v, pg_temp.prod('Extras', 'Extra'), 45, '3 aderezos extra');
    INSERT INTO pagos (venta_id, metodo, monto) VALUES (v, 'transferencia', 100), (v, 'tarjeta', 35);

    -- Gasto de limpieza y abono a deuda pagados de la caja del turno
    INSERT INTO gastos (turno_id, categoria, descripcion, monto) VALUES (t, 'limpieza', 'Cloro', 19);
    INSERT INTO prestamos (acreedor, monto) VALUES ('Prueba', 1000) RETURNING id INTO pr;
    INSERT INTO abonos (prestamo_id, turno_id, monto) VALUES (pr, t, 300);

    SELECT * INTO c FROM v_corte_turno WHERE turno_id = t;
    ASSERT c.total_ventas = 351,      format('Ventas $216 + $135 = 351, hay %s', c.total_ventas);
    ASSERT c.descuentos = 24,         format('Descuentos $24, hay %s', c.descuentos);
    ASSERT c.cobrado_mercado = 135,   format('Mercado (transf. + tarjeta) $135, hay %s', c.cobrado_mercado);
    ASSERT c.pagos_deuda = 300,       format('Pagos de deuda $300, hay %s', c.pagos_deuda);
    ASSERT c.balance = 32,            format('Balance 351 - 19 - 300 = 32, hay %s', c.balance);
    ASSERT c.efectivo_esperado = -103, format('Efectivo 216 - 19 - 300 = -103, hay %s', c.efectivo_esperado);
    ASSERT (SELECT saldo FROM v_prestamos WHERE id = pr) = 700, 'El abono reduce el saldo';
    RAISE NOTICE '✔ 7. Descuentos, extras, Mercado y pagos de deuda';
END $$;

-- 9. Estado calculado por la base de datos -------------------------------------
DO $$
DECLARE v bigint; pg bigint;
BEGIN
    INSERT INTO ventas DEFAULT VALUES RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id) VALUES (v, pg_temp.prod('Burgers', 'Bonchosa'));
    ASSERT (SELECT estado FROM ventas WHERE id = v) = 'abierta', 'Recién creada está abierta';
    INSERT INTO pagos (venta_id, metodo, monto) VALUES (v, 'efectivo', 50);
    ASSERT (SELECT estado FROM ventas WHERE id = v) = 'abierta', 'Pago parcial: sigue abierta';
    INSERT INTO pagos (venta_id, metodo, monto) VALUES (v, 'transferencia', 40) RETURNING id INTO pg;
    ASSERT (SELECT estado FROM ventas WHERE id = v) = 'pagada', 'Con $90 cobrados queda pagada';
    INSERT INTO venta_detalle (venta_id, producto_id) VALUES (v, pg_temp.prod('Refrescos', 'Boing 500 ml'));
    ASSERT (SELECT estado FROM ventas WHERE id = v) = 'abierta', 'Agregar un refresco la vuelve a abrir';
    UPDATE ventas SET descuento = 20, motivo_descuento = 'Cortesía' WHERE id = v;
    ASSERT (SELECT estado FROM ventas WHERE id = v) = 'pagada', 'El descuento cubre la diferencia';
    UPDATE ventas SET estado = 'cancelada' WHERE id = v;
    DELETE FROM pagos WHERE id = pg;
    ASSERT (SELECT estado FROM ventas WHERE id = v) = 'cancelada', 'Cancelada se respeta';
    UPDATE ventas SET estado = 'abierta' WHERE id = v;
    ASSERT (SELECT estado FROM ventas WHERE id = v) = 'abierta', 'Al reabrir se recalcula (falta cobrar)';
    RAISE NOTICE '✔ 9. Estado por pagos';
END $$;

-- 10. Funciones de la app (guardar_venta, guardar_insumo, ajustar_existencia) ---
DO $$
DECLARE v bigint; i bigint; coca0 numeric;
BEGIN
    coca0 := (SELECT cantidad FROM insumos WHERE nombre = 'Refresco Coca Cola 600 ml');
    v := guardar_venta('{
        "tipo_entrega": "domicilio", "cliente": " Ana ", "direccion": "Centro",
        "renglones": [
          {"categoria": "Alitas", "producto": "Alitas", "variante": "10 piezas", "sabor": "BBQ",
           "cantidad": 1, "precio_unitario": 140},
          {"categoria": "Combos", "producto": "Solitario", "cantidad": 2, "precio_unitario": 160, "notas": "sin cebolla",
           "componentes": [
             {"categoria": "Burgers", "producto": "Sweet Bacon"},
             {"categoria": "Papas", "producto": "Normalitas"},
             {"categoria": "Refrescos", "producto": "Coca Cola 600 ml"}]}
        ]}'::jsonb);
    ASSERT (SELECT total FROM v_ventas WHERE id = v) = 460, 'Alitas $140 + 2 Solitarios $320';
    ASSERT (SELECT articulos FROM v_ventas WHERE id = v) = 3, '3 artículos';
    ASSERT (SELECT cliente FROM ventas WHERE id = v) = 'Ana', 'Limpia espacios';
    ASSERT (SELECT cantidad FROM insumos WHERE nombre = 'Refresco Coca Cola 600 ml') = coca0 - 2,
        'Los 2 combos descuentan 2 Cocas';

    -- Editar: reemplaza los renglones y devuelve lo que ya no está
    PERFORM guardar_venta(jsonb_build_object('id', v, 'tipo_entrega', 'local', 'renglones',
        '[{"categoria": "Burgers", "producto": "Junior", "cantidad": 1, "precio_unitario": 75}]'::jsonb));
    ASSERT (SELECT articulos FROM v_ventas WHERE id = v) = 1, 'Quedó solo la Junior';
    ASSERT (SELECT cantidad FROM insumos WHERE nombre = 'Refresco Coca Cola 600 ml') = coca0,
        'Las Cocas regresaron al inventario';

    BEGIN
        PERFORM guardar_venta('{"renglones": [{"categoria": "Burgers", "producto": "Big Mac"}]}'::jsonb);
        RAISE EXCEPTION 'Debió fallar: producto inexistente';
    EXCEPTION WHEN raise_exception THEN
        ASSERT SQLERRM LIKE 'No existe en el menú%', SQLERRM;
    END;
    BEGIN
        PERFORM guardar_venta('{"tipo_entrega": "domicilio", "renglones": [{"categoria": "Burgers", "producto": "Junior"}]}'::jsonb);
        RAISE EXCEPTION 'Debió fallar: domicilio sin dirección';
    EXCEPTION WHEN raise_exception THEN
        ASSERT SQLERRM LIKE 'Falta la dirección%', SQLERRM;
    END;

    -- Insumo nuevo con existencia inicial → movimiento de ajuste
    i := guardar_insumo('{"nombre": "Servilletas", "categoria": "desechable", "unidad": "pieza", "cantidad": 100}'::jsonb);
    ASSERT (SELECT cantidad FROM insumos WHERE id = i) = 100, 'Nace con 100';
    PERFORM guardar_insumo(jsonb_build_object('id', i, 'nombre', 'Servilletas', 'categoria', 'desechable',
        'unidad', 'pieza', 'cantidad', 80));
    ASSERT (SELECT cantidad FROM insumos WHERE id = i) = 80, 'Editar a 80 registra −20';
    ASSERT ajustar_existencia(i, -500) = 0, 'No baja de 0';
    ASSERT ajustar_existencia(i, 5) = 5, 'Suma 5';
    RAISE NOTICE '✔ 10. Funciones de la app';
END $$;

-- 11. Pronóstico de ventas e insumos -----------------------------------------
-- Mañana (T) se estima con el mismo día de la semana; un festivo, con festivos anteriores.
DO $$
DECLARE
    hoy date := (now() AT TIME ZONE 'America/Mexico_City')::date;
    t   date := (now() AT TIME ZONE 'America/Mexico_City')::date + 1;
    sb  bigint := pg_temp.prod('Burgers', 'Sweet Bacon');
    dia date; n int; v bigint; r record; pan_hoy numeric; pan_hasta numeric; f record;
BEGIN
    ASSERT (SELECT count(*) FROM dias_festivos WHERE fecha = '2026-04-03' AND nombre = 'Viernes Santo') = 1,
        'Calcula Semana Santa (Pascua 2026 = 5 de abril)';
    ASSERT (SELECT fecha FROM dias_festivos WHERE nombre = 'Revolución Mexicana' AND extract(year FROM fecha) = 2026)
        = '2026-11-16', 'Revolución: tercer lunes de noviembre';
    ASSERT (SELECT fecha FROM dias_festivos WHERE nombre = 'Día del Padre' AND extract(year FROM fecha) = 2027)
        = '2027-06-20', 'Día del Padre: tercer domingo de junio';

    -- Calendario controlado: solo un festivo pasado (T-30) y uno próximo (T+1).
    DELETE FROM dias_festivos;
    INSERT INTO dias_festivos (fecha, nombre) VALUES (t - 30, 'Festivo pasado'), (t + 1, 'Festivo de prueba');

    -- Historial: 2 pedidos en cada uno de los 3 días previos con el mismo día de la semana que T,
    -- 1 pedido el día anterior a hoy hace una semana, y 5 en el festivo pasado. 1 Sweet Bacon por pedido.
    FOR dia, n IN SELECT * FROM (VALUES (t - 7, 2), (t - 14, 2), (t - 21, 2), (t - 8, 1), (t - 30, 5)) AS x LOOP
        FOR i IN 1..n LOOP
            INSERT INTO ventas (fecha) VALUES ((dia + time '14:00') AT TIME ZONE 'America/Mexico_City') RETURNING id INTO v;
            INSERT INTO venta_detalle (venta_id, producto_id) VALUES (v, sb);
        END LOOP;
    END LOOP;
    -- Una cancelada no cuenta.
    INSERT INTO ventas (fecha, estado) VALUES ((t - 7 + time '15:00') AT TIME ZONE 'America/Mexico_City', 'cancelada');

    SELECT * INTO r FROM pronostico_dias(3) WHERE fecha = t;
    ASSERT r.festivo IS NULL AND r.dias_historial = 3, format('T usa 3 días de referencia, usa %s', r.dias_historial);
    ASSERT r.productos_esperados = 2, format('T: 2 productos esperados, hay %s', r.productos_esperados);
    ASSERT r.productos_promedio > 0, 'Promedio general calculado';

    SELECT * INTO f FROM pronostico_dias(3) WHERE fecha = t + 1;
    ASSERT f.festivo = 'Festivo de prueba' AND f.dias_historial = 1, 'El festivo se estima con festivos anteriores';
    ASSERT f.productos_esperados = 5, format('Festivo: 5 productos esperados, hay %s', f.productos_esperados);
    ASSERT (SELECT count(*) FROM pronostico_dias(3)) = 3, 'Un renglón por día';

    -- Insumos de T y T+1 (sin contar hoy): 2 + 5 panes; 0.3 kg de carne por burger.
    pan_hoy   := coalesce((SELECT consumo_esperado FROM pronostico_insumos(hoy) WHERE nombre = 'Pan para hamburguesa'), 0);
    pan_hasta := (SELECT consumo_esperado FROM pronostico_insumos(t + 1) WHERE nombre = 'Pan para hamburguesa');
    ASSERT pan_hasta - pan_hoy = 7, format('Pan para T y T+1 = 7, da %s', pan_hasta - pan_hoy);

    -- Con 3 panes en existencia hay que comprar lo que falte (stock mínimo 0).
    UPDATE insumos SET stock_minimo = 0 WHERE nombre = 'Pan para hamburguesa';
    INSERT INTO movimientos_inventario (insumo_id, tipo, cantidad)
    SELECT id, 'ajuste', 3 - cantidad FROM insumos WHERE nombre = 'Pan para hamburguesa' AND cantidad <> 3;
    ASSERT (SELECT por_comprar FROM pronostico_insumos(t + 1) WHERE nombre = 'Pan para hamburguesa') = pan_hasta - 3,
        'por_comprar = consumo esperado − existencia';
    ASSERT NOT EXISTS (SELECT 1 FROM pronostico_insumos(t + 1) WHERE nombre = 'Refresco Boing 500 ml'),
        'Lo que no se ha vendido no aparece';

    -- Historial importado (Comandas.xlsx): un día viejo con el mismo día de la semana que T.
    -- 10 Sweet Bacon + 1 Solitario (cuyo Sweet Bacon va como componente). En T-7 también se
    -- "importan" 100, pero ese día ya está en la app: se ignoran.
    INSERT INTO historial_ventas (dia, producto_id, cantidad, componente, fuente) VALUES
        (t - 35, sb, 10, false, 'prueba'),
        (t - 35, pg_temp.prod('Combos', 'Solitario'), 1, false, 'prueba'),
        (t - 35, sb, 1, true, 'prueba'),
        (t - 7, sb, 100, false, 'prueba');
    ASSERT (SELECT x.productos FROM v_ventas_por_dia x WHERE x.dia = t - 35) = 11, 'El combo cuenta 1 vez, su componente no';
    ASSERT (SELECT x.productos FROM v_ventas_por_dia x WHERE x.dia = t - 7) = 2, 'Si el día está en la app, manda la app';
    SELECT * INTO r FROM pronostico_dias(2) WHERE fecha = t;
    ASSERT r.dias_historial = 4 AND r.productos_esperados = 4.3,
        format('T con historial importado: (2+2+2+11)/4 ≈ 4.3, da %s con %s días', r.productos_esperados, r.dias_historial);
    pan_hasta := (SELECT consumo_esperado FROM pronostico_insumos(t) WHERE nombre = 'Pan para hamburguesa');
    ASSERT pan_hasta - pan_hoy = 4.25, format('Pan para T = (2+2+2+11)/4 = 4.25, da %s', pan_hasta - pan_hoy);
    RAISE NOTICE '✔ 11. Pronóstico';
END $$;

-- 12. Resumen del mes ----------------------------------------------------------
-- Marzo 2020 (vacío salvo lo que se crea aquí): 2 ventas de la app, una cancelada,
-- historial importado y un gasto. Febrero: historial para comparar.
DO $$
DECLARE
    v bigint; j jsonb;
    sb bigint := pg_temp.prod('Burgers', 'Sweet Bacon');
    mx text := 'America/Mexico_City';
BEGIN
    UPDATE insumos SET costo_unitario = 0;
    UPDATE insumos SET costo_unitario = 7 WHERE nombre = 'Pan para hamburguesa';

    -- Vie 6: 2 Sweet Bacon ($180) − $20 de descuento = $160, pagado $100 efectivo + $60 transferencia.
    INSERT INTO ventas (fecha) VALUES ('2020-03-06 14:00' AT TIME ZONE mx) RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id, cantidad, precio_unitario) VALUES (v, sb, 2, 90);
    UPDATE ventas SET descuento = 20, motivo_descuento = 'prueba' WHERE id = v;
    INSERT INTO pagos (venta_id, metodo, monto) VALUES (v, 'efectivo', 100), (v, 'transferencia', 60);
    -- Sáb 7: 1 Hula Hula $95 sin cobrar; y una cancelada que no cuenta.
    INSERT INTO ventas (fecha) VALUES ('2020-03-07 15:00' AT TIME ZONE mx) RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id, precio_unitario) VALUES (v, pg_temp.prod('Burgers', 'Hula Hula'), 95);
    INSERT INTO ventas (fecha, estado) VALUES ('2020-03-07 16:00' AT TIME ZONE mx, 'cancelada');
    -- Historial: vie 13, 2 alitas de 5 ($75 c/u, estimado $150). El vie 6 ya está en la app: se ignora.
    INSERT INTO historial_ventas (dia, producto_id, variante_id, cantidad, fuente) VALUES
        ('2020-03-13', pg_temp.prod('Alitas', 'Alitas'),
         (SELECT id FROM variantes WHERE producto_id = pg_temp.prod('Alitas', 'Alitas') AND nombre = '5 piezas'), 2, 'prueba'),
        ('2020-03-06', sb, NULL, 50, 'prueba'),
        ('2020-02-14', pg_temp.prod('Refrescos', 'Boing 500 ml'), NULL, 1, 'prueba');
    INSERT INTO gastos (fecha, categoria, monto) VALUES ('2020-03-10 12:00' AT TIME ZONE mx, 'otro', 200);

    j := resumen_mes('2020-03-20');
    ASSERT (j ->> 'ventas')::numeric = 405, format('Ventas 160 + 95 + 150 = 405, da %s', j ->> 'ventas');
    ASSERT (j ->> 'ventas_estimadas')::numeric = 150, 'Lo del historial va como estimado';
    ASSERT (j ->> 'ventas_mes_anterior')::numeric = 20, 'Febrero: un Boing';
    ASSERT (j ->> 'pedidos')::int = 2, 'La cancelada no cuenta';
    ASSERT (j ->> 'productos')::numeric = 5, format('2 SB + 1 Hula + 2 alitas = 5, da %s', j ->> 'productos');
    ASSERT (j ->> 'dias_abiertos')::int = 3, 'Abrió el 6, 7 y 13';
    ASSERT (j ->> 'descuentos')::numeric = 20 AND (j ->> 'por_cobrar')::numeric = 95, 'Descuentos y por cobrar';
    ASSERT (j -> 'cobrado' ->> 'efectivo')::numeric = 100 AND (j -> 'cobrado' ->> 'transferencia')::numeric = 60,
        'Cobrado por método';
    ASSERT (j ->> 'costo_insumos')::numeric = 21, format('3 panes x $7 = 21, da %s', j ->> 'costo_insumos');
    ASSERT (j ->> 'gastos')::numeric = 200, 'Gastos del mes';
    ASSERT j -> 'top_productos' -> 0 ->> 'nombre' = 'Sweet Bacon', 'El más vendido (empata con alitas, gana por dinero)';
    ASSERT j -> 'top_productos' -> 1 ->> 'nombre' = 'Alitas 5 piezas', 'Nombre con tamaño';
    ASSERT (SELECT (x ->> 'total')::numeric FROM jsonb_array_elements(j -> 'por_dia_semana') x
             WHERE (x ->> 'dia_semana')::int = 5) = 310, 'Viernes: 160 + 150';
    ASSERT (resumen_mes('2019-01-01') ->> 'ventas')::numeric = 0, 'Mes sin datos = 0';
    RAISE NOTICE '✔ 12. Resumen del mes';
END $$;

-- 8. Seguridad (RLS) -----------------------------------------------------------
DO $$ BEGIN
    ASSERT NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname LIKE 'fn\_%'),
        'Las funciones internas no deben estar en public (se expondrían en /rpc)';
    ASSERT NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND NOT rowsecurity),
        'Todas las tablas de public deben tener RLS';
END $$;

-- Sin sesión (anon): ni siquiera puede leer el menú.
SET LOCAL ROLE anon;
DO $$ BEGIN
    BEGIN
        PERFORM 1 FROM productos;
        RAISE EXCEPTION 'anon no debería poder leer productos';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM pronostico_dias(7);
        RAISE EXCEPTION 'anon no debería poder ver el pronóstico';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM resumen_mes('2020-03-01');
        RAISE EXCEPTION 'anon no debería poder ver el resumen';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END $$;
RESET ROLE;

-- Sesión de Google con un correo NO autorizado: no ve nada y no puede escribir.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"email":"intruso@gmail.com","role":"authenticated","app_metadata":{"provider":"google"},"user_metadata":{"email_verified":true}}', true);
DO $$ BEGIN
    ASSERT (SELECT count(*) FROM productos) = 0, 'Un correo no autorizado no debe ver el menú';
    ASSERT (SELECT count(*) FROM usuarios_permitidos) = 0, 'Ni la lista de autorizados';
    ASSERT (SELECT sum(dias_historial) FROM pronostico_dias(7)) = 0, 'Ni el historial de ventas en el pronóstico';
    ASSERT NOT EXISTS (SELECT 1 FROM pronostico_insumos(current_date + 7)), 'Ni el consumo de insumos';
    ASSERT (resumen_mes('2020-03-01') ->> 'ventas')::numeric = 0, 'Ni las ventas del mes';
    BEGIN
        INSERT INTO gastos (categoria, monto) VALUES ('otro', 1);
        RAISE EXCEPTION 'Un correo no autorizado no debería poder registrar gastos';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM guardar_venta('{"renglones": [{"categoria": "Refrescos", "producto": "Boing 500 ml"}]}'::jsonb);
        RAISE EXCEPTION 'Un correo no autorizado no debería poder guardar pedidos';
    EXCEPTION WHEN raise_exception OR insufficient_privilege THEN
        ASSERT SQLERRM NOT LIKE '%no debería%', SQLERRM;
    END;
END $$;
RESET ROLE;

INSERT INTO usuarios_permitidos (correo, nombre) VALUES ('equipo@prueba.com', 'Prueba');

-- Suplantación (hallazgo del PR #14): correo autorizado pero NO vía Google, o sin verificar.
-- Incluye user_metadata.email_verified falsificado (el usuario puede editar user_metadata).
SET LOCAL ROLE authenticated;
DO $$
DECLARE
    claims text;
BEGIN
    FOREACH claims IN ARRAY ARRAY[
        '{"email":"equipo@prueba.com","role":"authenticated","app_metadata":{"provider":"email"},"user_metadata":{"email_verified":true}}',
        '{"email":"equipo@prueba.com","role":"authenticated","app_metadata":{"provider":"google"},"user_metadata":{"email_verified":false}}',
        '{"email":"equipo@prueba.com","role":"authenticated","user_metadata":{"email_verified":true}}',
        '{"email":"equipo@prueba.com","role":"authenticated","is_anonymous":true,"app_metadata":{"provider":"google"},"user_metadata":{"email_verified":true}}'
    ] LOOP
        PERFORM set_config('request.jwt.claims', claims, true);
        ASSERT (SELECT count(*) FROM productos) = 0, 'Sin Google verificado no debe ver el menú: ' || claims;
        ASSERT (SELECT count(*) FROM usuarios_permitidos) = 0, 'Ni saber si está en la lista: ' || claims;
        BEGIN
            INSERT INTO gastos (categoria, monto) VALUES ('otro', 1);
            RAISE EXCEPTION 'Suplantación pudo escribir: %', claims;
        EXCEPTION WHEN insufficient_privilege THEN NULL;
        END;
    END LOOP;
END $$;
RESET ROLE;

-- Correo autorizado con Google verificado: ve el menú y puede vender (los triggers internos funcionan con su rol).
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"email":"Equipo@Prueba.com","role":"authenticated","app_metadata":{"provider":"google"},"user_metadata":{"email_verified":true}}', true);
DO $$
DECLARE v bigint; pan0 numeric;
BEGIN
    ASSERT (SELECT count(*) FROM productos) = 36, 'El equipo ve el menú completo';
    ASSERT (SELECT count(*) FROM usuarios_permitidos) = 1, 'Ve solo su propio acceso';
    pan0 := (SELECT cantidad FROM insumos WHERE nombre = 'Pan para hamburguesa');
    INSERT INTO ventas DEFAULT VALUES RETURNING id INTO v;
    INSERT INTO venta_detalle (venta_id, producto_id)
    VALUES (v, (SELECT p.id FROM productos p JOIN categorias_menu c ON c.id = p.categoria_id
                 WHERE c.nombre = 'Burgers' AND p.nombre = 'Hula Hula'));
    ASSERT (SELECT total FROM v_ventas WHERE id = v) = 95, 'La venta se registra con su precio';
    ASSERT (SELECT cantidad FROM insumos WHERE nombre = 'Pan para hamburguesa') = pan0 - 1,
        'El trigger descuenta inventario aunque la función esté en el esquema interno';
    BEGIN
        INSERT INTO usuarios_permitidos (correo, nombre) VALUES ('colado@gmail.com', 'Colado');
        RAISE EXCEPTION 'Nadie debería poder darse de alta desde la app';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    ASSERT guardar_venta('{"renglones": [{"categoria": "Refrescos", "producto": "Boing 500 ml", "precio_unitario": 20}]}'::jsonb) > 0,
        'El equipo puede guardar pedidos por la función';
    RAISE NOTICE '✔ 8. Seguridad (RLS)';
END $$;
RESET ROLE;

ROLLBACK;
\echo 'Todas las pruebas pasaron ✅'
