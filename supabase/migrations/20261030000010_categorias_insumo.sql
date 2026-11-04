-- =====================================================================
-- Categorías de insumo más finas, como se acomodan en el negocio:
-- carnes, lácteos, panes, verduras, aderezos y salsas, abarrotes, bebidas,
-- desechables y otros. Sustituyen a 'ingrediente', que agrupaba casi todo.
-- =====================================================================

ALTER TABLE insumos DROP CONSTRAINT insumos_categoria_check;

-- Reacomodo de lo que ya existe (catálogo de 004 y lo dado de alta en la app).
-- Lo que no encaje en ninguna regla y era 'ingrediente' queda en 'abarrotes'.
UPDATE insumos SET categoria = CASE
    WHEN nombre IN ('Carne molida', 'Tocino', 'Alitas de pollo', 'Pechuga para boneless', 'Jamón')
      OR nombre ILIKE 'salchicha%'                                         THEN 'carnes'
    WHEN nombre ILIKE 'queso%' OR nombre IN ('Leche', 'Huevo')             THEN 'lacteos'
    WHEN nombre ILIKE 'pan para%'                                          THEN 'panes'
    WHEN nombre IN ('Aguacate', 'Cebolla', 'Cebolla morada', 'Jitomate', 'Lechuga', 'Piña',
                    'Papa a la francesa')
      OR nombre ILIKE 'chile%'                                             THEN 'verduras'
    WHEN nombre ILIKE 'aderezo%' OR nombre ILIKE 'salsa%' OR nombre ILIKE 'catsup%'
      OR nombre ILIKE 'mayonesa%'                                          THEN 'aderezos'
    WHEN nombre ILIKE 'refresco%'                                          THEN 'bebidas'
    WHEN categoria = 'ingrediente'                                         THEN 'abarrotes'
    ELSE categoria
END;

ALTER TABLE insumos ADD CONSTRAINT insumos_categoria_check CHECK (categoria IN
    ('carnes', 'lacteos', 'panes', 'verduras', 'aderezos', 'abarrotes', 'bebidas', 'desechable', 'otro'));
