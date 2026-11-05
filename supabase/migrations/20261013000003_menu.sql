-- =====================================================================
-- Monchosos · Menú actual (datos REALES, tomados de men_monchosos.md)
-- Las imágenes (productos.imagen_url) se agregan después.
-- =====================================================================

-- Ayudantes solo para este script (pg_temp desaparece al terminar la sesión).
CREATE FUNCTION pg_temp.cat(p_nombre text) RETURNS smallint LANGUAGE sql AS
$$ SELECT id FROM categorias_menu WHERE nombre = p_nombre $$;

CREATE FUNCTION pg_temp.prod(p_categoria text, p_nombre text) RETURNS bigint LANGUAGE sql AS
$$ SELECT p.id FROM productos p JOIN categorias_menu c ON c.id = p.categoria_id
    WHERE c.nombre = p_categoria AND p.nombre = p_nombre $$;

CREATE FUNCTION pg_temp.var(p_categoria text, p_producto text, p_variante text) RETURNS bigint LANGUAGE sql AS
$$ SELECT v.id FROM variantes v WHERE v.producto_id = pg_temp.prod(p_categoria, p_producto) AND v.nombre = p_variante $$;

-- Categorías ------------------------------------------------------------
INSERT INTO categorias_menu (nombre, emoji, orden) VALUES
    ('Burgers',         '🍔', 1),
    ('Doggos Jumbo',    '🌭', 2),
    ('Alitas',          '🍗', 3),
    ('Boneless',        '🍗', 4),
    ('Papas',           '🍟', 5),
    ('Combos',          '📦', 6),
    ('Aderezos Extra',  '🥫', 7),
    ('Refrescos',       '🥤', 8),
    ('Extras',          '➕', 9);

-- Burgers (incluyen papas) -----------------------------------------------
INSERT INTO productos (categoria_id, nombre, precio, incluye_papas, orden, descripcion) VALUES
    (pg_temp.cat('Burgers'), 'Junior',       75, true, 1, 'Carne de la casa, costra de queso, queso americano, jamón y salsa comeback.'),
    (pg_temp.cat('Burgers'), 'Glotona',     120, true, 2, 'Carne de la casa rellena de queso, boneless, tocino, costra de queso, piña y aderezo de la casa.'),
    (pg_temp.cat('Burgers'), 'La Guacamole',100, true, 3, 'Carne de la casa, costra de queso, chiles jalapeños, tocino, pico de gallo, guacamole y aderezo venenoso.'),
    (pg_temp.cat('Burgers'), 'Sweet Bacon',  90, true, 4, 'Doble carne, tocino, queso americano, costra de queso y aderezo de la casa.'),
    (pg_temp.cat('Burgers'), 'La Tóxica',   140, true, 5, 'Carne rellena de queso, salchicha parrillera, costra de queso, chile morrón, piña, cebolla caramelizada y aderezo a elección.'),
    (pg_temp.cat('Burgers'), 'Hula Hula',    95, true, 6, 'Carne de la casa, queso manchego, jamón, piña-canela, cebolla caramelizada y aderezo hula hula.'),
    (pg_temp.cat('Burgers'), 'Bonchosa',     90, true, 7, 'Boneless bañados en BBQ, tocino y aderezo cheddar.');

-- Doggos Jumbo (incluyen papas) ------------------------------------------
INSERT INTO productos (categoria_id, nombre, precio, incluye_papas, orden, descripcion) VALUES
    (pg_temp.cat('Doggos Jumbo'), 'El Perro Callejero', 50, true, 1, 'Salchicha jumbo para asar envuelta en tocino, cebolla caramelizada y chiles en vinagre picados.'),
    (pg_temp.cat('Doggos Jumbo'), 'Atascado',           70, true, 2, 'Salchicha jumbo envuelta en tocino rellena de queso, cubierta con lluvia de papas fritas trituradas y queso cheddar.'),
    (pg_temp.cat('Doggos Jumbo'), 'Junior',             35, true, 3, 'El clásico con jitomate, cebolla y aderezos (ideal para niños).'),
    (pg_temp.cat('Doggos Jumbo'), 'Pica Pica',          60, true, 4, 'Salchicha jumbo, costra de queso, jalapeño, cebolla morada curtida con limón y aderezo venenoso.'),
    (pg_temp.cat('Doggos Jumbo'), 'Mexicanísimo',       80, true, 5, 'Salchicha jumbo cubierta con costra de queso manchego, pico de gallo, guacamole y un toque de aderezo In & Out.'),
    (pg_temp.cat('Doggos Jumbo'), 'Tóxico Guac',        70, true, 6, 'Salchicha jumbo rellena de queso, guacamole, pico de gallo y cebolla caramelizada.');

-- Alitas y Boneless (precio por variante + sabor) -------------------------
INSERT INTO productos (categoria_id, nombre, precio, orden) VALUES
    (pg_temp.cat('Alitas'),   'Alitas',   NULL, 1),
    (pg_temp.cat('Boneless'), 'Boneless', NULL, 1);

INSERT INTO variantes (producto_id, nombre, piezas, precio, orden) VALUES
    (pg_temp.prod('Alitas', 'Alitas'),     '5 piezas',   5,  75, 1),
    (pg_temp.prod('Alitas', 'Alitas'),     '10 piezas', 10, 140, 2),
    (pg_temp.prod('Boneless', 'Boneless'), '5 piezas',   5,  70, 1),
    (pg_temp.prod('Boneless', 'Boneless'), '10 piezas', 10, 130, 2);

INSERT INTO sabores (nombre) VALUES
    ('Mango-Habanero'), ('Venenosas'), ('BBQ'), ('Parmesano'), ('Lemon Pepper Crispy');

INSERT INTO producto_sabores (producto_id, sabor_id)
SELECT p.id, s.id
  FROM sabores s
 CROSS JOIN (VALUES (pg_temp.prod('Alitas', 'Alitas')), (pg_temp.prod('Boneless', 'Boneless'))) AS p (id);

-- Papas -------------------------------------------------------------------
INSERT INTO productos (categoria_id, nombre, precio, orden, descripcion) VALUES
    (pg_temp.cat('Papas'), 'Normalitas',  60, 1, 'Orden clásica.'),
    (pg_temp.cat('Papas'), 'Monchosas',  110, 2, 'Cama de papas a la francesa sazonadas, trozos de boneless, mucho queso cheddar derretido, tocino picado y aderezo ranch.'),
    (pg_temp.cat('Papas'), 'Junior',      80, 3, 'Papas a la francesa con tocino y trozos de salchicha frita, acompañadas de aderezo cheddar.'),
    (pg_temp.cat('Papas'), 'Criminales', 100, 4, 'Papas fritas, trozos de boneless bañados en salsa búfalo, jalapeños en rodajas, aderezo ranch y un toque de Flamin'' Hot.'),
    (pg_temp.cat('Papas'), 'BBQ Bacon',   85, 5, 'Papas fritas, trozos de salchicha jumbo, salsa BBQ ahumada, queso fundido y una capa extra de cebolla caramelizada.');

-- Aderezos extra ($15 c/u) ------------------------------------------------
INSERT INTO productos (categoria_id, nombre, precio, orden) VALUES
    (pg_temp.cat('Aderezos Extra'), 'De la casa', 15, 1),
    (pg_temp.cat('Aderezos Extra'), 'Hula Hula',  15, 2),
    (pg_temp.cat('Aderezos Extra'), 'Cheddar',    15, 3),
    (pg_temp.cat('Aderezos Extra'), 'Venenoso',   15, 4),
    (pg_temp.cat('Aderezos Extra'), 'In & Out',   15, 5),
    (pg_temp.cat('Aderezos Extra'), 'Comeback',   15, 6);

-- Refrescos ---------------------------------------------------------------
INSERT INTO productos (categoria_id, nombre, precio, orden) VALUES
    (pg_temp.cat('Refrescos'), 'Boing 500 ml',     20, 1),
    (pg_temp.cat('Refrescos'), 'Coca Cola 600 ml', 25, 2),
    (pg_temp.cat('Refrescos'), 'Sprite 600 ml',    23, 3),
    (pg_temp.cat('Refrescos'), 'Jarritos 600 ml',  23, 4),
    (pg_temp.cat('Refrescos'), 'Fresca 600 ml',    23, 5);

-- Extras (precio a mano en cada venta) -------------------------------------
-- Para cargos que no están en el menú y en las comandas se sumaban a mano
-- (ej. "=C150*2+45", "TOTAL VENTAS +20+20").
INSERT INTO productos (categoria_id, nombre, precio, precio_libre, orden, descripcion) VALUES
    (pg_temp.cat('Extras'), 'Extra', NULL, true, 1, 'Cargo libre: escribe qué es en notas y el precio a mano.');

-- Combos ------------------------------------------------------------------
INSERT INTO productos (categoria_id, nombre, precio, es_combo, orden, descripcion) VALUES
    (pg_temp.cat('Combos'), 'Solitario',          160, true, 1, '1 hamburguesa Sweet Bacon + 1 porción papas normalitas + 1 refresco.'),
    (pg_temp.cat('Combos'), 'Desmadre de Pareja', 325, true, 2, '2 hamburguesas (Hula Hula, Sweet Bacon o Bonchosa) + 1 orden papas Criminales + 2 refrescos.'),
    (pg_temp.cat('Combos'), 'Caja de Pandora',    500, true, 3, '2 hamburguesas (Tóxica, Junior o La Guacamole) + 2 doggos (El Perro Callejero, Pica Pica o Tóxico Guac) + 5 alitas + 5 boneless (cualquier sabor).'),
    (pg_temp.cat('Combos'), 'Kit Para El Bajón',  230, true, 4, '10 boneless a elegir + papas junior + 2 aderezos a elegir.');

INSERT INTO combo_grupos (combo_id, nombre, cantidad, orden) VALUES
    (pg_temp.prod('Combos', 'Solitario'),          'Hamburguesa',  1, 1),
    (pg_temp.prod('Combos', 'Solitario'),          'Papas',        1, 2),
    (pg_temp.prod('Combos', 'Solitario'),          'Refresco',     1, 3),
    (pg_temp.prod('Combos', 'Desmadre de Pareja'), 'Hamburguesas', 2, 1),
    (pg_temp.prod('Combos', 'Desmadre de Pareja'), 'Papas',        1, 2),
    (pg_temp.prod('Combos', 'Desmadre de Pareja'), 'Refrescos',    2, 3),
    (pg_temp.prod('Combos', 'Caja de Pandora'),    'Hamburguesas', 2, 1),
    (pg_temp.prod('Combos', 'Caja de Pandora'),    'Doggos',       2, 2),
    (pg_temp.prod('Combos', 'Caja de Pandora'),    'Alitas',       1, 3),
    (pg_temp.prod('Combos', 'Caja de Pandora'),    'Boneless',     1, 4),
    (pg_temp.prod('Combos', 'Kit Para El Bajón'),  'Boneless',     1, 1),
    (pg_temp.prod('Combos', 'Kit Para El Bajón'),  'Papas',        1, 2),
    (pg_temp.prod('Combos', 'Kit Para El Bajón'),  'Aderezos',     2, 3);

CREATE FUNCTION pg_temp.grupo(p_combo text, p_grupo text) RETURNS bigint LANGUAGE sql AS
$$ SELECT id FROM combo_grupos WHERE combo_id = pg_temp.prod('Combos', p_combo) AND nombre = p_grupo $$;

INSERT INTO combo_opciones (grupo_id, producto_id, variante_id) VALUES
    (pg_temp.grupo('Solitario', 'Hamburguesa'),          pg_temp.prod('Burgers', 'Sweet Bacon'), NULL),
    (pg_temp.grupo('Solitario', 'Papas'),                pg_temp.prod('Papas', 'Normalitas'), NULL),
    (pg_temp.grupo('Desmadre de Pareja', 'Hamburguesas'), pg_temp.prod('Burgers', 'Hula Hula'), NULL),
    (pg_temp.grupo('Desmadre de Pareja', 'Hamburguesas'), pg_temp.prod('Burgers', 'Sweet Bacon'), NULL),
    (pg_temp.grupo('Desmadre de Pareja', 'Hamburguesas'), pg_temp.prod('Burgers', 'Bonchosa'), NULL),
    (pg_temp.grupo('Desmadre de Pareja', 'Papas'),        pg_temp.prod('Papas', 'Criminales'), NULL),
    (pg_temp.grupo('Caja de Pandora', 'Hamburguesas'),    pg_temp.prod('Burgers', 'La Tóxica'), NULL),
    (pg_temp.grupo('Caja de Pandora', 'Hamburguesas'),    pg_temp.prod('Burgers', 'Junior'), NULL),
    (pg_temp.grupo('Caja de Pandora', 'Hamburguesas'),    pg_temp.prod('Burgers', 'La Guacamole'), NULL),
    (pg_temp.grupo('Caja de Pandora', 'Doggos'),          pg_temp.prod('Doggos Jumbo', 'El Perro Callejero'), NULL),
    (pg_temp.grupo('Caja de Pandora', 'Doggos'),          pg_temp.prod('Doggos Jumbo', 'Pica Pica'), NULL),
    (pg_temp.grupo('Caja de Pandora', 'Doggos'),          pg_temp.prod('Doggos Jumbo', 'Tóxico Guac'), NULL),
    (pg_temp.grupo('Caja de Pandora', 'Alitas'),          pg_temp.prod('Alitas', 'Alitas'), pg_temp.var('Alitas', 'Alitas', '5 piezas')),
    (pg_temp.grupo('Caja de Pandora', 'Boneless'),        pg_temp.prod('Boneless', 'Boneless'), pg_temp.var('Boneless', 'Boneless', '5 piezas')),
    (pg_temp.grupo('Kit Para El Bajón', 'Boneless'),      pg_temp.prod('Boneless', 'Boneless'), pg_temp.var('Boneless', 'Boneless', '10 piezas')),
    (pg_temp.grupo('Kit Para El Bajón', 'Papas'),         pg_temp.prod('Papas', 'Junior'), NULL);

-- "Cualquier refresco" y "cualquier aderezo": todas las opciones de esa categoría.
INSERT INTO combo_opciones (grupo_id, producto_id)
SELECT g.id, p.id
  FROM (VALUES (pg_temp.grupo('Solitario', 'Refresco')),
               (pg_temp.grupo('Desmadre de Pareja', 'Refrescos'))) AS g (id)
 CROSS JOIN productos p
 WHERE p.categoria_id = pg_temp.cat('Refrescos');

INSERT INTO combo_opciones (grupo_id, producto_id)
SELECT pg_temp.grupo('Kit Para El Bajón', 'Aderezos'), p.id
  FROM productos p
 WHERE p.categoria_id = pg_temp.cat('Aderezos Extra');

