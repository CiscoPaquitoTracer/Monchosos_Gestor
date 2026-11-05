-- =====================================================================
-- Monchosos · Catálogos: proveedores, insumos, recetas, préstamos y activos
-- Fuentes: contexto_de_gestion_y_comandas.md y Comandas.xlsx (hojas Gastos y Hoja 9)
--
-- ⚠️ Las RECETAS son cantidades de EJEMPLO (no vienen en los documentos).
--    Hay que ajustarlas con la pareja: de ellas depende el descuento de inventario.
-- =====================================================================

-- Proveedores -------------------------------------------------------------
INSERT INTO proveedores (nombre, notas) VALUES
    ('Sams',              'Pan Wonder, salchicha, jamón, papa corte recto, catsup en sobres, harina'),
    ('Carnemart',         'Carne molida, tocino, queso chihuahua, salchicha, papa delgada'),
    ('Carnicería local',  'Carne molida'),
    ('Omar',              'Carne molida'),
    ('Chedraui',          'Pan Bimbollo y Wonder, salchicha parrillera, refrescos, utensilios'),
    ('Bodega Aurrera',    'Pan, lechuga, refrescos'),
    ('Alpe',              'Pan Bimbollo, salchicha parrillera'),
    ('Tienda 3B',         'Carne molida, tocino, aceite, pan molido, limpieza'),
    ('Sheila',            'Fruta y verdura'),
    ('Mercado Libre',     'Unicel 7x7, comandas, porta comandas, calculadora'),
    ('Dulcería',          'Vasos y tapas soufflé'),
    ('Tienda casa',       'Harina, botanas, limpieza'),
    ('Oxxo',              NULL);

-- Insumos -----------------------------------------------------------------
-- Existencias en 0: entran con las compras.
INSERT INTO insumos (nombre, categoria, unidad, stock_minimo) VALUES
    -- Carnes y embutidos
    ('Carne molida',               'ingrediente', 'kg',     3),
    ('Tocino',                     'ingrediente', 'kg',     1),
    ('Alitas de pollo',            'ingrediente', 'kg',     2),
    ('Pechuga para boneless',      'ingrediente', 'kg',     2),
    ('Jamón',                      'ingrediente', 'kg',     0.5),
    ('Salchicha jumbo',            'ingrediente', 'pieza', 10),
    ('Salchicha parrillera',       'ingrediente', 'pieza',  5),
    -- Panadería
    ('Pan para hamburguesa',       'ingrediente', 'pieza', 16),
    ('Pan para hot dog',           'ingrediente', 'pieza', 10),
    -- Lácteos
    ('Queso manchego',             'ingrediente', 'kg',     1),
    ('Queso cheddar',              'ingrediente', 'kg',     1),
    ('Queso americano',            'ingrediente', 'pieza', 20),
    ('Queso chihuahua',            'ingrediente', 'kg',     0.5),
    -- Abarrotes y verduras
    ('Papa a la francesa',         'ingrediente', 'kg',     5),
    ('Aceite',                     'ingrediente', 'litro',  5),
    ('Lechuga',                    'ingrediente', 'pieza',  2),
    ('Jitomate',                   'ingrediente', 'kg',     1),
    ('Cebolla',                    'ingrediente', 'kg',     1),
    ('Cebolla morada',             'ingrediente', 'kg',     0.5),
    ('Chile jalapeño',             'ingrediente', 'kg',     0.5),
    ('Chile morrón',               'ingrediente', 'kg',     0.5),
    ('Piña',                       'ingrediente', 'kg',     0.5),
    ('Aguacate',                   'ingrediente', 'kg',     1),
    ('Salsa BBQ',                  'ingrediente', 'litro',  1),
    ('Salsa búfalo',               'ingrediente', 'litro',  0.5),
    -- Empanizado (boneless) y condimentos
    ('Harina',                     'ingrediente', 'kg',     1),
    ('Pan molido',                 'ingrediente', 'kg',     0.5),
    ('Huevo',                      'ingrediente', 'pieza', 12),
    ('Leche',                      'ingrediente', 'litro',  1),
    ('Paprika',                    'ingrediente', 'kg',     0),
    ('Catsup en sobres',           'ingrediente', 'pieza', 50),
    -- Botanas que se usan como ingrediente (Flamin' Hot de las Criminales, lluvia de papas del Atascado)
    ('Cheetos Flamin'' Hot',       'ingrediente', 'pieza',  2),
    ('Papas Sabritas',             'ingrediente', 'pieza',  2),
    -- Empaque
    ('Contenedor unicel 7x7',      'desechable',  'pieza', 50),
    ('Vaso soufflé 2 oz',          'desechable',  'pieza', 50),
    ('Tapa soufflé 2 oz',          'desechable',  'pieza', 50),
    ('Bolsa para entrega',         'desechable',  'pieza', 30),
    ('Papel grado alimenticio',    'desechable',  'pieza', 50),
    -- Bebidas (se revenden tal cual)
    ('Refresco Boing 500 ml',      'otro',        'pieza',  6),
    ('Refresco Coca Cola 600 ml',  'otro',        'pieza',  6),
    ('Refresco Sprite 600 ml',     'otro',        'pieza',  6),
    ('Refresco Jarritos 600 ml',   'otro',        'pieza',  6),
    ('Refresco Fresca 600 ml',     'otro',        'pieza',  6);

-- Recetas (EJEMPLO) --------------------------------------------------------
CREATE FUNCTION pg_temp.receta(p_cat text, p_prod text, p_var text, p_insumo text, p_cant numeric)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO recetas (producto_id, variante_id, insumo_id, cantidad)
    SELECT p.id, v.id, i.id, p_cant
      FROM productos p
      JOIN categorias_menu c ON c.id = p.categoria_id AND c.nombre = p_cat
      JOIN insumos i         ON i.nombre = p_insumo
      LEFT JOIN variantes v  ON v.producto_id = p.id AND v.nombre = p_var
     WHERE p.nombre = p_prod
$$;

-- Todo lo que "incluye papas" lleva porción de papa y contenedor.
INSERT INTO recetas (producto_id, insumo_id, cantidad)
SELECT p.id, i.id, x.cantidad
  FROM productos p
 CROSS JOIN (VALUES ('Papa a la francesa', 0.150), ('Contenedor unicel 7x7', 1)) AS x (insumo, cantidad)
  JOIN insumos i ON i.nombre = x.insumo
 WHERE p.incluye_papas;

-- Burgers: pan + carne (+ extras principales)
SELECT pg_temp.receta('Burgers', b.nombre, NULL, 'Pan para hamburguesa', 1)
  FROM (VALUES ('Junior'), ('Glotona'), ('La Guacamole'), ('Sweet Bacon'),
               ('La Tóxica'), ('Hula Hula'), ('Bonchosa')) AS b (nombre);
SELECT pg_temp.receta('Burgers', b.nombre, NULL, 'Carne molida', b.carne)
  FROM (VALUES ('Junior', 0.150), ('Glotona', 0.180), ('La Guacamole', 0.150),
               ('Sweet Bacon', 0.300), ('La Tóxica', 0.180), ('Hula Hula', 0.150)) AS b (nombre, carne);
SELECT pg_temp.receta('Burgers', b.nombre, NULL, 'Tocino', 0.030)
  FROM (VALUES ('Glotona'), ('La Guacamole'), ('Sweet Bacon'), ('Bonchosa')) AS b (nombre);
SELECT pg_temp.receta('Burgers', 'Glotona',    NULL, 'Pechuga para boneless', 0.080);
SELECT pg_temp.receta('Burgers', 'Bonchosa',   NULL, 'Pechuga para boneless', 0.150);
SELECT pg_temp.receta('Burgers', 'La Tóxica',  NULL, 'Salchicha parrillera', 1);
SELECT pg_temp.receta('Burgers', 'Hula Hula',  NULL, 'Queso manchego', 0.030);
SELECT pg_temp.receta('Burgers', 'Junior',     NULL, 'Queso americano', 1);
SELECT pg_temp.receta('Burgers', 'Sweet Bacon', NULL, 'Queso americano', 1);

-- Doggos: pan + salchicha (+ tocino si va envuelto)
SELECT pg_temp.receta('Doggos Jumbo', d.nombre, NULL, 'Pan para hot dog', 1)
  FROM (VALUES ('El Perro Callejero'), ('Atascado'), ('Junior'), ('Pica Pica'),
               ('Mexicanísimo'), ('Tóxico Guac')) AS d (nombre);
SELECT pg_temp.receta('Doggos Jumbo', d.nombre, NULL, 'Salchicha jumbo', 1)
  FROM (VALUES ('El Perro Callejero'), ('Atascado'), ('Junior'), ('Pica Pica'),
               ('Mexicanísimo'), ('Tóxico Guac')) AS d (nombre);
SELECT pg_temp.receta('Doggos Jumbo', d.nombre, NULL, 'Tocino', 0.025)
  FROM (VALUES ('El Perro Callejero'), ('Atascado')) AS d (nombre);

-- Alitas y boneless: dependen de la variante
SELECT pg_temp.receta('Alitas',   'Alitas',   '5 piezas',  'Alitas de pollo', 0.350);
SELECT pg_temp.receta('Alitas',   'Alitas',   '10 piezas', 'Alitas de pollo', 0.700);
SELECT pg_temp.receta('Boneless', 'Boneless', '5 piezas',  'Pechuga para boneless', 0.200);
SELECT pg_temp.receta('Boneless', 'Boneless', '10 piezas', 'Pechuga para boneless', 0.400);
SELECT pg_temp.receta('Alitas',   'Alitas',   NULL, 'Contenedor unicel 7x7', 1);
SELECT pg_temp.receta('Boneless', 'Boneless', NULL, 'Contenedor unicel 7x7', 1);

-- Papas
SELECT pg_temp.receta('Papas', p.nombre, NULL, 'Papa a la francesa', 0.250)
  FROM (VALUES ('Normalitas'), ('Monchosas'), ('Junior'), ('Criminales'), ('BBQ Bacon')) AS p (nombre);
SELECT pg_temp.receta('Papas', p.nombre, NULL, 'Contenedor unicel 7x7', 1)
  FROM (VALUES ('Normalitas'), ('Monchosas'), ('Junior'), ('Criminales'), ('BBQ Bacon')) AS p (nombre);

-- Aderezos: vaso + tapa
SELECT pg_temp.receta('Aderezos Extra', a.nombre, NULL, x.insumo, 1)
  FROM (VALUES ('De la casa'), ('Hula Hula'), ('Cheddar'), ('Venenoso'), ('In & Out'), ('Comeback')) AS a (nombre)
 CROSS JOIN (VALUES ('Vaso soufflé 2 oz'), ('Tapa soufflé 2 oz')) AS x (insumo);

-- Refrescos: 1 a 1
SELECT pg_temp.receta('Refrescos', r.producto, NULL, r.insumo, 1)
  FROM (VALUES ('Boing 500 ml',     'Refresco Boing 500 ml'),
               ('Coca Cola 600 ml', 'Refresco Coca Cola 600 ml'),
               ('Sprite 600 ml',    'Refresco Sprite 600 ml'),
               ('Jarritos 600 ml',  'Refresco Jarritos 600 ml'),
               ('Fresca 600 ml',    'Refresco Fresca 600 ml')) AS r (producto, insumo);

-- Préstamos y activos (Hoja 9 de Comandas.xlsx) ----------------------------
-- Mamá: 2,185 + 620 + 164 = 2,969, saldada con 5 abonos que suman lo mismo.
-- Los abonos son anteriores al sistema, por eso no van ligados a ningún turno.
INSERT INTO prestamos (acreedor, monto, notas) VALUES
    ('Mamá', 2969, 'Capital de trabajo: 2,185 + 620 + 164. Saldada.'),
    ('Dani', 2150, NULL),
    ('Ike',   800, NULL);

INSERT INTO abonos (prestamo_id, monto, notas)
SELECT p.id, a.monto, a.notas
  FROM prestamos p
 CROSS JOIN (VALUES (620, NULL), (360, '100 + 40 + 220'), (1000, NULL), (600, '400 + 200'), (389, NULL)) AS a (monto, notas)
 WHERE p.acreedor = 'Mamá';

INSERT INTO activos (nombre, monto, notas) VALUES
    ('Moto de reparto', 5000, 'Vehículo para envíos a domicilio');

