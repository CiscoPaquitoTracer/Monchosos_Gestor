-- =====================================================================
-- Monchosos · Esquema de base de datos (Supabase · PostgreSQL 17)
--
-- Convenciones:
--   * Dinero: numeric(10,2). Nunca float/double.
--   * Cantidades de inventario: numeric(12,3) (kg con gramos, piezas, litros).
--   * Fechas con zona horaria (timestamptz); los reportes usan America/Mexico_City.
--   * No se borran productos ni insumos con historial: se marcan activo = false.
--   * La seguridad (RLS) está en la migración 20261013000002_seguridad.sql.
-- =====================================================================

-- Métodos de pago (ventas, compras y gastos). "tarjeta" = terminal Mercado Pago.
CREATE DOMAIN metodo_pago AS text
    CHECK (VALUE IN ('efectivo', 'transferencia', 'tarjeta'));

CREATE FUNCTION fn_actualizado_en() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    NEW.actualizado_en := now();
    RETURN NEW;
END $$;

-- ---------------------------------------------------------------------
-- Correos con acceso (la pareja). Sin roles: quien esté aquí puede hacer todo.
-- Se administra desde el panel de Supabase (Table Editor), no desde la app.
CREATE TABLE usuarios_permitidos (
    correo     text        PRIMARY KEY CHECK (correo = lower(correo)),
    nombre     text        NOT NULL,
    creado_en  timestamptz NOT NULL DEFAULT now()
);

-- =====================================================================
-- MENÚ
-- =====================================================================
CREATE TABLE categorias_menu (
    id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre  text     NOT NULL UNIQUE,
    emoji   text,
    orden   smallint NOT NULL DEFAULT 0
);

CREATE TABLE productos (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    categoria_id    smallint      NOT NULL REFERENCES categorias_menu (id),
    nombre          text          NOT NULL,
    descripcion     text,
    -- NULL cuando el precio depende de la variante (ej. alitas 5 / 10 piezas).
    precio          numeric(10,2) CHECK (precio >= 0),
    incluye_papas   boolean       NOT NULL DEFAULT false,
    es_combo        boolean       NOT NULL DEFAULT false,
    -- Precio a mano en cada venta (ej. "Extra": queso, aderezo de más). Obliga a indicar precio_unitario.
    precio_libre    boolean       NOT NULL DEFAULT false,
    imagen_url      text,
    activo          boolean       NOT NULL DEFAULT true,
    orden           smallint      NOT NULL DEFAULT 0,
    creado_en       timestamptz   NOT NULL DEFAULT now(),
    actualizado_en  timestamptz   NOT NULL DEFAULT now(),
    UNIQUE (categoria_id, nombre)   -- "Junior" existe en Papas, Burgers y Doggos
);
COMMENT ON COLUMN productos.precio IS 'NULL si el producto se vende por variante (ver tabla variantes).';

CREATE TABLE variantes (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    producto_id     bigint        NOT NULL REFERENCES productos (id) ON DELETE CASCADE,
    nombre          text          NOT NULL,            -- "5 piezas"
    piezas          smallint      CHECK (piezas > 0),
    precio          numeric(10,2) NOT NULL CHECK (precio >= 0),
    activo          boolean       NOT NULL DEFAULT true,
    orden           smallint      NOT NULL DEFAULT 0,
    actualizado_en  timestamptz   NOT NULL DEFAULT now(),
    UNIQUE (producto_id, nombre)
);

CREATE TABLE sabores (
    id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre  text     NOT NULL UNIQUE,
    activo  boolean  NOT NULL DEFAULT true
);

CREATE TABLE producto_sabores (
    producto_id  bigint   NOT NULL REFERENCES productos (id) ON DELETE CASCADE,
    sabor_id     smallint NOT NULL REFERENCES sabores (id) ON DELETE CASCADE,
    PRIMARY KEY (producto_id, sabor_id)
);

-- Un combo (producto con es_combo = true) se arma con grupos:
--   "2 hamburguesas a elegir entre Hula Hula, Sweet Bacon o Bonchosa".
CREATE TABLE combo_grupos (
    id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    combo_id  bigint   NOT NULL REFERENCES productos (id) ON DELETE CASCADE,
    nombre    text     NOT NULL,
    cantidad  smallint NOT NULL DEFAULT 1 CHECK (cantidad > 0),
    orden     smallint NOT NULL DEFAULT 0,
    UNIQUE (combo_id, nombre)
);

CREATE TABLE combo_opciones (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    grupo_id     bigint NOT NULL REFERENCES combo_grupos (id) ON DELETE CASCADE,
    producto_id  bigint NOT NULL REFERENCES productos (id),
    variante_id  bigint REFERENCES variantes (id),
    UNIQUE NULLS NOT DISTINCT (grupo_id, producto_id, variante_id)
);

-- Se llena solo (trigger) cada vez que cambia un precio.
CREATE TABLE historial_precios (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    producto_id      bigint REFERENCES productos (id) ON DELETE CASCADE,
    variante_id      bigint REFERENCES variantes (id) ON DELETE CASCADE,
    precio_anterior  numeric(10,2),
    precio_nuevo     numeric(10,2),
    cambiado_en      timestamptz NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(producto_id, variante_id) = 1)
);

-- =====================================================================
-- INVENTARIO Y COMPRAS
-- =====================================================================
CREATE TABLE insumos (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          text          NOT NULL UNIQUE,
    categoria       text          NOT NULL CHECK (categoria IN ('ingrediente', 'desechable', 'otro')),
    unidad          text          NOT NULL CHECK (unidad IN ('kg', 'pieza', 'litro')),
    -- La mantiene movimientos_inventario. Puede quedar negativa si se vende sin
    -- haber registrado la compra: así se nota que falta un registro.
    cantidad        numeric(12,3) NOT NULL DEFAULT 0,
    stock_minimo    numeric(12,3) NOT NULL DEFAULT 0 CHECK (stock_minimo >= 0),
    costo_unitario  numeric(10,2) NOT NULL DEFAULT 0 CHECK (costo_unitario >= 0),
    activo          boolean       NOT NULL DEFAULT true,
    creado_en       timestamptz   NOT NULL DEFAULT now(),
    actualizado_en  timestamptz   NOT NULL DEFAULT now()
);
COMMENT ON COLUMN insumos.cantidad IS 'No editar a mano: registrar un movimiento tipo "ajuste" o "merma".';
COMMENT ON COLUMN insumos.costo_unitario IS 'Último costo por kg/pieza/litro; se actualiza con cada compra.';

-- Qué insumos gasta cada producto. variante_id NULL = aplica a todas las variantes.
CREATE TABLE recetas (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    producto_id  bigint        NOT NULL REFERENCES productos (id) ON DELETE CASCADE,
    variante_id  bigint        REFERENCES variantes (id) ON DELETE CASCADE,
    insumo_id    bigint        NOT NULL REFERENCES insumos (id),
    cantidad     numeric(12,3) NOT NULL CHECK (cantidad > 0),
    UNIQUE NULLS NOT DISTINCT (producto_id, variante_id, insumo_id)
);

CREATE TABLE proveedores (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre     text        NOT NULL UNIQUE,
    telefono   text,
    notas      text,
    activo     boolean     NOT NULL DEFAULT true,
    creado_en  timestamptz NOT NULL DEFAULT now()
);

-- =====================================================================
-- TURNOS (corte de caja)
-- =====================================================================
CREATE TABLE turnos (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    abierto_en        timestamptz   NOT NULL DEFAULT now(),
    cerrado_en        timestamptz,
    abierto_por       uuid        DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE SET NULL,
    cerrado_por       uuid        REFERENCES auth.users (id) ON DELETE SET NULL,
    fondo_inicial     numeric(10,2) NOT NULL DEFAULT 0 CHECK (fondo_inicial >= 0),
    efectivo_contado  numeric(10,2) CHECK (efectivo_contado >= 0),  -- lo que había en caja al cerrar
    notas             text,
    CHECK (cerrado_en IS NULL OR cerrado_en >= abierto_en)
);
-- Solo puede haber un turno abierto a la vez.
CREATE UNIQUE INDEX turnos_un_solo_abierto ON turnos ((true)) WHERE cerrado_en IS NULL;

CREATE TABLE compras (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    proveedor_id    bigint      REFERENCES proveedores (id),
    turno_id        bigint      REFERENCES turnos (id),
    fecha           timestamptz NOT NULL DEFAULT now(),
    metodo_pago     metodo_pago NOT NULL DEFAULT 'efectivo',
    notas           text,
    registrado_por  uuid      DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE SET NULL,
    creado_en       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE compra_detalle (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    compra_id    bigint        NOT NULL REFERENCES compras (id) ON DELETE CASCADE,
    insumo_id    bigint        NOT NULL REFERENCES insumos (id),
    cantidad     numeric(12,3) NOT NULL CHECK (cantidad > 0),
    costo_total  numeric(10,2) NOT NULL CHECK (costo_total >= 0)
);

-- =====================================================================
-- VENTAS (comandas)
-- =====================================================================
CREATE TABLE ventas (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    turno_id        bigint      REFERENCES turnos (id),
    fecha           timestamptz NOT NULL DEFAULT now(),
    tipo_entrega    text        NOT NULL DEFAULT 'local'
                                CHECK (tipo_entrega IN ('local', 'para_llevar', 'domicilio')),
    cliente         text,
    telefono        text,
    direccion       text,
    estado          text        NOT NULL DEFAULT 'abierta'
                                CHECK (estado IN ('abierta', 'pagada', 'cancelada')),
    -- Descuento en pesos sobre el subtotal (ej. 10 % de inauguración). El total nunca baja de 0.
    descuento         numeric(10,2) NOT NULL DEFAULT 0 CHECK (descuento >= 0),
    motivo_descuento  text,
    registrado_por  uuid      DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE SET NULL,
    notas           text,
    creado_en       timestamptz NOT NULL DEFAULT now(),
    actualizado_en  timestamptz NOT NULL DEFAULT now(),
    CHECK (descuento = 0 OR motivo_descuento IS NOT NULL)
);

CREATE TABLE venta_detalle (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    venta_id         bigint        NOT NULL REFERENCES ventas (id) ON DELETE CASCADE,
    producto_id      bigint        NOT NULL REFERENCES productos (id),
    variante_id      bigint        REFERENCES variantes (id),
    sabor_id         smallint      REFERENCES sabores (id),
    cantidad         smallint      NOT NULL DEFAULT 1 CHECK (cantidad > 0),
    -- Precio CONGELADO al momento de la venta. Si se omite, se toma el precio actual.
    precio_unitario  numeric(10,2) NOT NULL CHECK (precio_unitario >= 0),
    subtotal         numeric(10,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
    notas            text
);
COMMENT ON COLUMN venta_detalle.precio_unitario IS
    'Se guarda el precio con el que se vendió: si el menú cambia, los cortes viejos no se alteran.';

-- Lo que el cliente eligió dentro de un combo (no suma al total; el combo ya tiene precio).
CREATE TABLE venta_componentes (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    detalle_id   bigint   NOT NULL REFERENCES venta_detalle (id) ON DELETE CASCADE,
    producto_id  bigint   NOT NULL REFERENCES productos (id),
    variante_id  bigint   REFERENCES variantes (id),
    sabor_id     smallint REFERENCES sabores (id),
    cantidad     smallint NOT NULL DEFAULT 1 CHECK (cantidad > 0)
);

-- Una venta puede pagarse en partes (ej. $100 efectivo + $60 transferencia).
CREATE TABLE pagos (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    venta_id    bigint        NOT NULL REFERENCES ventas (id) ON DELETE CASCADE,
    metodo      metodo_pago   NOT NULL,
    monto       numeric(10,2) NOT NULL CHECK (monto > 0),
    referencia  text,
    creado_en   timestamptz   NOT NULL DEFAULT now()
);

-- =====================================================================
-- MOVIMIENTOS DE INVENTARIO (bitácora; mantiene insumos.cantidad)
-- =====================================================================
CREATE TABLE movimientos_inventario (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    insumo_id            bigint        NOT NULL REFERENCES insumos (id),
    tipo                 text          NOT NULL CHECK (tipo IN ('compra', 'venta', 'ajuste', 'merma')),
    cantidad             numeric(12,3) NOT NULL CHECK (cantidad <> 0),   -- + entra, − sale
    compra_detalle_id    bigint        REFERENCES compra_detalle (id) ON DELETE CASCADE,
    venta_detalle_id     bigint        REFERENCES venta_detalle (id) ON DELETE CASCADE,
    venta_componente_id  bigint        REFERENCES venta_componentes (id) ON DELETE CASCADE,
    notas                text,
    creado_en            timestamptz   NOT NULL DEFAULT now()
);

-- =====================================================================
-- GASTOS, PRÉSTAMOS Y ACTIVOS
-- =====================================================================
CREATE TABLE gastos (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    turno_id        bigint        REFERENCES turnos (id),
    fecha           timestamptz   NOT NULL DEFAULT now(),
    -- limpieza: cloro, Raid, fibras, papel · publicidad: stickers, estampas · transporte: casetas, envíos
    categoria       text          NOT NULL CHECK (categoria IN
                        ('gas', 'gasolina', 'transporte', 'sueldos', 'renta', 'servicios',
                         'mantenimiento', 'limpieza', 'equipo', 'publicidad', 'otro')),
    descripcion     text,
    beneficiario    text,
    monto           numeric(10,2) NOT NULL CHECK (monto > 0),
    metodo_pago     metodo_pago   NOT NULL DEFAULT 'efectivo',
    registrado_por  uuid        DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE SET NULL,
    creado_en       timestamptz   NOT NULL DEFAULT now()
);

CREATE TABLE prestamos (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    acreedor   text          NOT NULL,                 -- a quién se le debe
    monto      numeric(10,2) NOT NULL CHECK (monto > 0),
    fecha      date          NOT NULL DEFAULT current_date,
    notas      text,
    creado_en  timestamptz   NOT NULL DEFAULT now()
);

-- Si el abono sale de la caja de un turno, entra en su corte como "pagos de deuda"
-- (en las comandas el "Pago Mamá" se restaba junto con los gastos).
CREATE TABLE abonos (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    prestamo_id  bigint        NOT NULL REFERENCES prestamos (id) ON DELETE CASCADE,
    turno_id     bigint        REFERENCES turnos (id),
    fecha        date          NOT NULL DEFAULT current_date,
    monto        numeric(10,2) NOT NULL CHECK (monto > 0),
    metodo_pago  metodo_pago   NOT NULL DEFAULT 'efectivo',
    notas        text
);

CREATE TABLE activos (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre        text          NOT NULL,
    monto         numeric(10,2) NOT NULL CHECK (monto >= 0),
    fecha_compra  date,
    notas         text,
    creado_en     timestamptz   NOT NULL DEFAULT now()
);

-- =====================================================================
-- ÍNDICES (llaves foráneas y fechas de consulta frecuente)
-- =====================================================================
CREATE INDEX ON productos (categoria_id);
CREATE INDEX ON variantes (producto_id);
CREATE INDEX ON combo_opciones (grupo_id);
CREATE INDEX ON recetas (producto_id);
CREATE INDEX ON compras (turno_id);
CREATE INDEX ON compra_detalle (compra_id);
CREATE INDEX ON ventas (turno_id);
CREATE INDEX ON ventas (fecha);
CREATE INDEX ON venta_detalle (venta_id);
CREATE INDEX ON venta_componentes (detalle_id);
CREATE INDEX ON pagos (venta_id);
CREATE INDEX ON movimientos_inventario (insumo_id);
CREATE INDEX ON movimientos_inventario (compra_detalle_id);
CREATE INDEX ON movimientos_inventario (venta_detalle_id);
CREATE INDEX ON movimientos_inventario (venta_componente_id);
CREATE INDEX ON gastos (turno_id);
CREATE INDEX ON abonos (prestamo_id);
CREATE INDEX ON abonos (turno_id);

-- =====================================================================
-- TRIGGERS
-- =====================================================================
CREATE TRIGGER productos_actualizado_en BEFORE UPDATE ON productos
    FOR EACH ROW EXECUTE FUNCTION fn_actualizado_en();
CREATE TRIGGER variantes_actualizado_en BEFORE UPDATE ON variantes
    FOR EACH ROW EXECUTE FUNCTION fn_actualizado_en();
CREATE TRIGGER insumos_actualizado_en BEFORE UPDATE ON insumos
    FOR EACH ROW EXECUTE FUNCTION fn_actualizado_en();
CREATE TRIGGER ventas_actualizado_en BEFORE UPDATE ON ventas
    FOR EACH ROW EXECUTE FUNCTION fn_actualizado_en();

-- Historial de precios ------------------------------------------------
CREATE FUNCTION fn_historial_precio() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    IF TG_TABLE_NAME = 'productos' THEN
        INSERT INTO historial_precios (producto_id, precio_anterior, precio_nuevo)
        VALUES (NEW.id, OLD.precio, NEW.precio);
    ELSE
        INSERT INTO historial_precios (variante_id, precio_anterior, precio_nuevo)
        VALUES (NEW.id, OLD.precio, NEW.precio);
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER productos_historial_precio AFTER UPDATE OF precio ON productos
    FOR EACH ROW WHEN (OLD.precio IS DISTINCT FROM NEW.precio) EXECUTE FUNCTION fn_historial_precio();
CREATE TRIGGER variantes_historial_precio AFTER UPDATE OF precio ON variantes
    FOR EACH ROW WHEN (OLD.precio IS DISTINCT FROM NEW.precio) EXECUTE FUNCTION fn_historial_precio();

-- Validación de lo vendido + precio por defecto -----------------------
CREATE FUNCTION fn_validar_vendido() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    v_precio numeric(10,2);
    v_libre  boolean;
BEGIN
    SELECT precio_libre INTO v_libre FROM productos WHERE id = NEW.producto_id;
    IF NEW.variante_id IS NOT NULL THEN
        SELECT precio INTO v_precio FROM variantes
         WHERE id = NEW.variante_id AND producto_id = NEW.producto_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'La variante % no pertenece al producto %', NEW.variante_id, NEW.producto_id;
        END IF;
    ELSE
        SELECT precio INTO v_precio FROM productos WHERE id = NEW.producto_id;
    END IF;

    IF NEW.sabor_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM producto_sabores WHERE producto_id = NEW.producto_id AND sabor_id = NEW.sabor_id
    ) THEN
        RAISE EXCEPTION 'El sabor % no está disponible para el producto %', NEW.sabor_id, NEW.producto_id;
    END IF;

    -- Solo venta_detalle lleva precio; en componentes de combo no aplica.
    IF TG_TABLE_NAME = 'venta_detalle' THEN
        IF v_libre AND (NEW.precio_unitario IS NULL OR coalesce(trim(NEW.notas), '') = '') THEN
            RAISE EXCEPTION 'El producto % es de precio libre: indica precio_unitario y en notas qué es', NEW.producto_id;
        END IF;
        IF NEW.precio_unitario IS NULL THEN
            IF v_precio IS NULL THEN
                RAISE EXCEPTION 'El producto % se vende por variante (ej. 5 o 10 piezas): indica variante_id',
                    NEW.producto_id;
            END IF;
            NEW.precio_unitario := v_precio;
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER venta_detalle_validar BEFORE INSERT OR UPDATE ON venta_detalle
    FOR EACH ROW EXECUTE FUNCTION fn_validar_vendido();
CREATE TRIGGER venta_componentes_validar BEFORE INSERT OR UPDATE ON venta_componentes
    FOR EACH ROW EXECUTE FUNCTION fn_validar_vendido();

-- Movimientos → existencias -------------------------------------------
CREATE FUNCTION fn_movimiento_aplicar() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        UPDATE insumos SET cantidad = cantidad - OLD.cantidad WHERE id = OLD.insumo_id;
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        UPDATE insumos SET cantidad = cantidad + NEW.cantidad WHERE id = NEW.insumo_id;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER movimientos_aplicar AFTER INSERT OR UPDATE OR DELETE ON movimientos_inventario
    FOR EACH ROW EXECUTE FUNCTION fn_movimiento_aplicar();

-- Compras → entrada de inventario y último costo -----------------------
CREATE FUNCTION fn_compra_detalle_inventario() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO movimientos_inventario (insumo_id, tipo, cantidad, compra_detalle_id)
        VALUES (NEW.insumo_id, 'compra', NEW.cantidad, NEW.id);
    ELSE
        UPDATE movimientos_inventario
           SET insumo_id = NEW.insumo_id, cantidad = NEW.cantidad
         WHERE compra_detalle_id = NEW.id;
    END IF;
    UPDATE insumos SET costo_unitario = round(NEW.costo_total / NEW.cantidad, 2) WHERE id = NEW.insumo_id;
    RETURN NULL;
END $$;

CREATE TRIGGER compra_detalle_inventario AFTER INSERT OR UPDATE ON compra_detalle
    FOR EACH ROW EXECUTE FUNCTION fn_compra_detalle_inventario();

-- Ventas → salida de inventario según recetas --------------------------
-- Recalcula (borra y vuelve a insertar) los movimientos de un renglón. Si la venta
-- está cancelada no inserta nada, así que cancelar = devolver los insumos.
CREATE FUNCTION fn_descontar_detalle(p_detalle_id bigint) RETURNS void LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    DELETE FROM movimientos_inventario WHERE venta_detalle_id = p_detalle_id;
    INSERT INTO movimientos_inventario (insumo_id, tipo, cantidad, venta_detalle_id)
    SELECT r.insumo_id, 'venta', -(r.cantidad * d.cantidad), d.id
      FROM venta_detalle d
      JOIN ventas v  ON v.id = d.venta_id AND v.estado <> 'cancelada'
      JOIN recetas r ON r.producto_id = d.producto_id
                    AND (r.variante_id IS NULL OR r.variante_id = d.variante_id)
     WHERE d.id = p_detalle_id;
END $$;

CREATE FUNCTION fn_descontar_componente(p_componente_id bigint) RETURNS void LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    DELETE FROM movimientos_inventario WHERE venta_componente_id = p_componente_id;
    INSERT INTO movimientos_inventario (insumo_id, tipo, cantidad, venta_componente_id)
    SELECT r.insumo_id, 'venta', -(r.cantidad * c.cantidad * d.cantidad), c.id
      FROM venta_componentes c
      JOIN venta_detalle d ON d.id = c.detalle_id
      JOIN ventas v        ON v.id = d.venta_id AND v.estado <> 'cancelada'
      JOIN recetas r       ON r.producto_id = c.producto_id
                          AND (r.variante_id IS NULL OR r.variante_id = c.variante_id)
     WHERE c.id = p_componente_id;
END $$;

CREATE FUNCTION fn_venta_detalle_inventario() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    PERFORM fn_descontar_detalle(NEW.id);
    -- La cantidad del renglón multiplica a los componentes del combo.
    PERFORM fn_descontar_componente(c.id) FROM venta_componentes c WHERE c.detalle_id = NEW.id;
    RETURN NULL;
END $$;

CREATE TRIGGER venta_detalle_inventario
    AFTER INSERT OR UPDATE OF producto_id, variante_id, cantidad ON venta_detalle
    FOR EACH ROW EXECUTE FUNCTION fn_venta_detalle_inventario();

CREATE FUNCTION fn_venta_componente_inventario() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    PERFORM fn_descontar_componente(NEW.id);
    RETURN NULL;
END $$;

CREATE TRIGGER venta_componentes_inventario
    AFTER INSERT OR UPDATE OF producto_id, variante_id, cantidad ON venta_componentes
    FOR EACH ROW EXECUTE FUNCTION fn_venta_componente_inventario();

-- Cancelar una venta devuelve sus insumos; "descancelarla" los vuelve a descontar.
CREATE FUNCTION fn_venta_estado_inventario() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    PERFORM fn_descontar_detalle(d.id) FROM venta_detalle d WHERE d.venta_id = NEW.id;
    PERFORM fn_descontar_componente(c.id)
       FROM venta_componentes c JOIN venta_detalle d ON d.id = c.detalle_id
      WHERE d.venta_id = NEW.id;
    RETURN NULL;
END $$;

CREATE TRIGGER ventas_estado_inventario AFTER UPDATE OF estado ON ventas
    FOR EACH ROW
    WHEN ((OLD.estado = 'cancelada') IS DISTINCT FROM (NEW.estado = 'cancelada'))
    EXECUTE FUNCTION fn_venta_estado_inventario();

-- =====================================================================
-- VISTAS (reportes listos para consultar)
-- =====================================================================
CREATE VIEW v_menu WITH (security_invoker = true) AS
SELECT c.orden AS orden_categoria, c.nombre AS categoria, p.id AS producto_id, p.nombre AS producto,
       v.id AS variante_id, v.nombre AS variante, coalesce(v.precio, p.precio) AS precio,
       p.incluye_papas, p.es_combo, p.activo AND coalesce(v.activo, true) AS activo
  FROM productos p
  JOIN categorias_menu c ON c.id = p.categoria_id
  LEFT JOIN variantes v  ON v.producto_id = p.id
 ORDER BY c.orden, p.orden, p.nombre, v.orden;

CREATE VIEW v_ventas WITH (security_invoker = true) AS
SELECT x.*, x.total - x.pagado AS pendiente
  FROM (
    SELECT v.*,
           coalesce(d.subtotal, 0)                              AS subtotal,
           greatest(coalesce(d.subtotal, 0) - v.descuento, 0)   AS total,
           coalesce(p.pagado, 0)                                AS pagado
      FROM ventas v
      LEFT JOIN (SELECT venta_id, sum(subtotal) AS subtotal FROM venta_detalle GROUP BY venta_id) d
             ON d.venta_id = v.id
      LEFT JOIN (SELECT venta_id, sum(monto) AS pagado FROM pagos GROUP BY venta_id) p ON p.venta_id = v.id
  ) x;

-- Corte de caja por turno, como en las comandas: pedidos, ventas, desglose por método y balance.
-- Un turno puede durar varios días (en las comandas cada corte junta 3 o 4 días de venta).
-- "Mercado" = transferencia + tarjeta (lo que entra por Mercado Pago).
CREATE VIEW v_corte_turno WITH (security_invoker = true) AS
WITH vt AS (
    SELECT turno_id, count(*) AS pedidos, sum(total) AS total_ventas, sum(descuento) AS descuentos
      FROM v_ventas WHERE estado <> 'cancelada' GROUP BY turno_id
), ab AS (
    SELECT turno_id, sum(monto) AS pagos_deuda,
           sum(monto) FILTER (WHERE metodo_pago = 'efectivo') AS pagos_deuda_efectivo
      FROM abonos WHERE turno_id IS NOT NULL GROUP BY turno_id
), pg AS (
    SELECT v.turno_id,
           sum(p.monto) FILTER (WHERE p.metodo = 'efectivo')      AS efectivo,
           sum(p.monto) FILTER (WHERE p.metodo = 'transferencia') AS transferencia,
           sum(p.monto) FILTER (WHERE p.metodo = 'tarjeta')       AS tarjeta
      FROM pagos p JOIN ventas v ON v.id = p.venta_id
     WHERE v.estado <> 'cancelada'
     GROUP BY v.turno_id
), ga AS (
    SELECT turno_id, sum(monto) AS gastos,
           sum(monto) FILTER (WHERE metodo_pago = 'efectivo') AS gastos_efectivo
      FROM gastos GROUP BY turno_id
), co AS (
    SELECT c.turno_id, sum(d.costo_total) AS compras,
           sum(d.costo_total) FILTER (WHERE c.metodo_pago = 'efectivo') AS compras_efectivo
      FROM compras c JOIN compra_detalle d ON d.compra_id = c.id GROUP BY c.turno_id
), corte AS (
    SELECT t.id AS turno_id, t.abierto_en, t.cerrado_en, t.fondo_inicial, t.efectivo_contado,
           coalesce(vt.pedidos, 0)        AS pedidos,
           coalesce(vt.total_ventas, 0)   AS total_ventas,
           coalesce(vt.descuentos, 0)     AS descuentos,
           coalesce(pg.efectivo, 0)       AS cobrado_efectivo,
           coalesce(pg.transferencia, 0)  AS cobrado_transferencia,
           coalesce(pg.tarjeta, 0)        AS cobrado_tarjeta,
           coalesce(pg.transferencia, 0) + coalesce(pg.tarjeta, 0) AS cobrado_mercado,
           coalesce(ga.gastos, 0)         AS gastos,
           coalesce(co.compras, 0)        AS compras,
           coalesce(ab.pagos_deuda, 0)    AS pagos_deuda,
           t.fondo_inicial + coalesce(pg.efectivo, 0)
             - coalesce(ga.gastos_efectivo, 0) - coalesce(co.compras_efectivo, 0)
             - coalesce(ab.pagos_deuda_efectivo, 0) AS efectivo_esperado
      FROM turnos t
      LEFT JOIN vt ON vt.turno_id = t.id
      LEFT JOIN pg ON pg.turno_id = t.id
      LEFT JOIN ga ON ga.turno_id = t.id
      LEFT JOIN co ON co.turno_id = t.id
      LEFT JOIN ab ON ab.turno_id = t.id
)
SELECT *,
       total_ventas - gastos - compras - pagos_deuda AS balance,   -- "TOTAL" de la hoja Gastos
       efectivo_contado - efectivo_esperado          AS diferencia_caja   -- negativo = falta dinero
  FROM corte;

CREATE VIEW v_ventas_por_categoria WITH (security_invoker = true) AS
SELECT (v.fecha AT TIME ZONE 'America/Mexico_City')::date AS dia,
       c.nombre AS categoria, sum(d.cantidad) AS unidades, sum(d.subtotal) AS total
  FROM venta_detalle d
  JOIN ventas v          ON v.id = d.venta_id AND v.estado <> 'cancelada'
  JOIN productos p       ON p.id = d.producto_id
  JOIN categorias_menu c ON c.id = p.categoria_id
 GROUP BY 1, 2;

CREATE VIEW v_insumos_por_agotarse WITH (security_invoker = true) AS
SELECT id, nombre, categoria, unidad, cantidad, stock_minimo
  FROM insumos
 WHERE activo AND stock_minimo > 0 AND cantidad <= stock_minimo;

CREATE VIEW v_prestamos WITH (security_invoker = true) AS
SELECT p.*, coalesce(a.abonado, 0) AS abonado, p.monto - coalesce(a.abonado, 0) AS saldo
  FROM prestamos p
  LEFT JOIN (SELECT prestamo_id, sum(monto) AS abonado FROM abonos GROUP BY prestamo_id) a
         ON a.prestamo_id = p.id;

