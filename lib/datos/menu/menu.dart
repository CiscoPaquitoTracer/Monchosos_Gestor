import 'package:flutter/foundation.dart';

/// Menú de Monchosos. Aquí vive la ESTRUCTURA (combos, descripciones, categorías); los
/// PRECIOS y la disponibilidad mandan desde Supabase (ver [Menu.actualizar] y
/// MenuRepositorio). Los precios de este archivo solo se usan mientras carga o sin internet.
/// Los precios van en CENTAVOS.

/// [db] = nombre de la categoría en Supabase (tabla categorias_menu).
enum CategoriaMenu {
  burgers('Burgers', 'Burger', 'Burgers'),
  doggos('Doggos', 'Doggo', 'Doggos Jumbo'),
  alitas('Alitas', 'Alitas', 'Alitas'),
  boneless('Boneless', 'Boneless', 'Boneless'),
  papas('Papas', 'Papas', 'Papas'),
  combos('Combos', 'Combo', 'Combos'),
  aderezos('Aderezos', 'Aderezo', 'Aderezos Extra'),
  refrescos('Refrescos', 'Refresco', 'Refrescos');

  const CategoriaMenu(this.etiqueta, this.singular, this.db);

  final String etiqueta;
  final String singular;
  final String db;
}

/// Precio y disponibilidad de un producto según Supabase (precios en centavos).
class PrecioDb {
  const PrecioDb({
    required this.id,
    required this.categoriaDb,
    required this.nombre,
    required this.precio,
    required this.activo,
    this.variantes = const [],
  });

  final int id;
  final String categoriaDb;
  final String nombre;
  final int? precio;
  final bool activo;
  final List<VarianteDb> variantes;
}

class VarianteDb {
  const VarianteDb({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.activo,
  });

  final int id;
  final String nombre;
  final int precio;
  final bool activo;
}

/// Un tamaño de un producto ("5 piezas"). [dbId] = 0 mientras no carga de Supabase.
class Variante {
  const Variante(
    this.id,
    this.nombre,
    this.precio, {
    this.activo = true,
    this.dbId = 0,
  });

  final String id;
  final String nombre;
  final int precio;
  final bool activo;
  final int dbId;

  Variante conDb(VarianteDb v) =>
      Variante(id, nombre, v.precio, activo: v.activo, dbId: v.id);
}

/// Una opción permitida dentro de un grupo de combo (ej. "Boneless 5 piezas").
@immutable
class OpcionCombo {
  const OpcionCombo(this.productoId, [this.varianteId]);

  final String productoId;
  final String? varianteId;

  @override
  bool operator ==(Object other) =>
      other is OpcionCombo &&
      other.productoId == productoId &&
      other.varianteId == varianteId;

  @override
  int get hashCode => Object.hash(productoId, varianteId);
}

/// "2 hamburguesas a elegir entre…".
class GrupoCombo {
  const GrupoCombo(this.nombre, this.cantidad, this.opciones);

  final String nombre;
  final int cantidad;
  final List<OpcionCombo> opciones;
}

class ProductoMenu {
  const ProductoMenu(
    this.id,
    this.categoria,
    this.nombre, {
    this.precio,
    this.descripcion = '',
    this.variantes = const [],
    this.conSabor = false,
    this.incluyePapas = false,
    this.grupos = const [],
    this.activo = true,
    this.dbId = 0,
  });

  final String id;
  final CategoriaMenu categoria;
  final String nombre;

  /// null cuando el precio depende de la variante.
  final int? precio;
  final String descripcion;
  final List<Variante> variantes;
  final bool conSabor;
  final bool incluyePapas;
  final List<GrupoCombo> grupos;

  /// false = "no disponible hoy": no aparece al tomar pedidos.
  final bool activo;
  final int dbId;

  bool get esCombo => grupos.isNotEmpty;

  bool get necesitaConfigurar => variantes.isNotEmpty || conSabor || esCombo;

  List<Variante> get variantesActivas =>
      variantes.where((v) => v.activo).toList();

  /// Precio fijo, o el mínimo entre las variantes activas ("desde $X").
  int get precioDesde {
    if (precio != null) return precio!;
    final lista = variantesActivas.isEmpty ? variantes : variantesActivas;
    return lista.map((v) => v.precio).reduce((a, b) => a < b ? a : b);
  }

  Variante? variante(String? id) =>
      variantes.where((v) => v.id == id).firstOrNull;

  ProductoMenu conDb(PrecioDb fila) => ProductoMenu(
    id,
    categoria,
    nombre,
    precio: precio != null ? (fila.precio ?? precio) : null,
    descripcion: descripcion,
    variantes: [
      for (final v in variantes)
        switch (fila.variantes.where((x) => x.nombre == v.nombre).firstOrNull) {
          final VarianteDb x => v.conDb(x),
          null => v,
        },
    ],
    conSabor: conSabor,
    incluyePapas: incluyePapas,
    grupos: grupos,
    activo: fila.activo,
    dbId: fila.id,
  );
}

int _p(int pesos) => pesos * 100;

abstract final class Menu {
  static const String nota =
      'Todas las hamburguesas y hot dogs incluyen una porción de papas.';

  static const List<String> sabores = [
    'Mango-Habanero',
    'Venenosas',
    'BBQ',
    'Parmesano',
    'Lemon Pepper Crispy',
  ];

  static const _burgers = [
    ProductoMenu(
      'burger-junior',
      CategoriaMenu.burgers,
      'Junior',
      precio: 7500,
      descripcion: 'Carne de la casa, costra de queso, queso americano, jamón y salsa comeback.',
      incluyePapas: true,
    ),
    ProductoMenu(
      'burger-glotona',
      CategoriaMenu.burgers,
      'Glotona',
      precio: 12000,
      descripcion: 'Carne de la casa rellena de queso, boneless, tocino, costra de queso, piña y aderezo de la casa.',
      incluyePapas: true,
    ),
    ProductoMenu(
      'burger-guacamole',
      CategoriaMenu.burgers,
      'La Guacamole',
      precio: 10000,
      descripcion: 'Carne de la casa, costra de queso, chiles jalapeños, tocino, pico de gallo, guacamole y aderezo venenoso.',
      incluyePapas: true,
    ),
    ProductoMenu(
      'burger-sweet-bacon',
      CategoriaMenu.burgers,
      'Sweet Bacon',
      precio: 9000,
      descripcion: 'Doble carne, tocino, queso americano, costra de queso y aderezo de la casa.',
      incluyePapas: true,
    ),
    ProductoMenu(
      'burger-toxica',
      CategoriaMenu.burgers,
      'La Tóxica',
      precio: 14000,
      descripcion: 'Carne rellena de queso, salchicha parrillera, costra de queso, chile morrón, piña, cebolla caramelizada y aderezo a elección.',
      incluyePapas: true,
    ),
    ProductoMenu(
      'burger-hula-hula',
      CategoriaMenu.burgers,
      'Hula Hula',
      precio: 9500,
      descripcion: 'Carne de la casa, queso manchego, jamón, piña-canela, cebolla caramelizada y aderezo hula hula.',
      incluyePapas: true,
    ),
    ProductoMenu(
      'burger-bonchosa',
      CategoriaMenu.burgers,
      'Bonchosa',
      precio: 9000,
      descripcion: 'Boneless bañados en BBQ, tocino y aderezo cheddar.',
      incluyePapas: true,
    ),
  ];

  static const _doggos = [
    ProductoMenu(
      'doggo-callejero',
      CategoriaMenu.doggos,
      'El Perro Callejero',
      precio: 5000,
      descripcion: 'Salchicha jumbo para asar envuelta en tocino, cebolla caramelizada y chiles en vinagre picados.',
      incluyePapas: true,
    ),
    ProductoMenu(
      'doggo-atascado',
      CategoriaMenu.doggos,
      'Atascado',
      precio: 7000,
      descripcion: 'Salchicha jumbo envuelta en tocino rellena de queso, cubierta con lluvia de papas fritas trituradas y queso cheddar.',
      incluyePapas: true,
    ),
    ProductoMenu(
      'doggo-junior',
      CategoriaMenu.doggos,
      'Junior',
      precio: 3500,
      descripcion:
          'El clásico con jitomate, cebolla y aderezos (ideal para niños).',
      incluyePapas: true,
    ),
    ProductoMenu(
      'doggo-pica-pica',
      CategoriaMenu.doggos,
      'Pica Pica',
      precio: 6000,
      descripcion: 'Salchicha jumbo, costra de queso, jalapeño, cebolla morada curtida con limón y aderezo venenoso.',
      incluyePapas: true,
    ),
    ProductoMenu(
      'doggo-mexicanisimo',
      CategoriaMenu.doggos,
      'Mexicanísimo',
      precio: 8000,
      descripcion: 'Salchicha jumbo cubierta con costra de queso manchego, pico de gallo, guacamole y un toque de aderezo In & Out.',
      incluyePapas: true,
    ),
    ProductoMenu(
      'doggo-toxico-guac',
      CategoriaMenu.doggos,
      'Tóxico Guac',
      precio: 7000,
      descripcion: 'Salchicha jumbo rellena de queso, guacamole, pico de gallo y cebolla caramelizada.',
      incluyePapas: true,
    ),
  ];

  static const _alitas = ProductoMenu(
    'alitas',
    CategoriaMenu.alitas,
    'Alitas',
    variantes: [
      Variante('alitas-5', '5 piezas', 7500),
      Variante('alitas-10', '10 piezas', 14000),
    ],
    conSabor: true,
  );

  static const _boneless = ProductoMenu(
    'boneless',
    CategoriaMenu.boneless,
    'Boneless',
    variantes: [
      Variante('boneless-5', '5 piezas', 7000),
      Variante('boneless-10', '10 piezas', 13000),
    ],
    conSabor: true,
  );

  static const _papas = [
    ProductoMenu(
      'papas-normalitas',
      CategoriaMenu.papas,
      'Normalitas',
      precio: 6000,
      descripcion: 'Orden clásica.',
    ),
    ProductoMenu(
      'papas-monchosas',
      CategoriaMenu.papas,
      'Monchosas',
      precio: 11000,
      descripcion: 'Cama de papas a la francesa sazonadas, trozos de boneless, mucho queso cheddar derretido, tocino picado y aderezo ranch.',
    ),
    ProductoMenu(
      'papas-junior',
      CategoriaMenu.papas,
      'Junior',
      precio: 8000,
      descripcion: 'Papas a la francesa con tocino y trozos de salchicha frita, acompañadas de aderezo cheddar.',
    ),
    ProductoMenu(
      'papas-criminales',
      CategoriaMenu.papas,
      'Criminales',
      precio: 10000,
      descripcion: "Papas fritas, trozos de boneless bañados en salsa búfalo, jalapeños en rodajas, aderezo ranch y un toque de Flamin' Hot.",
    ),
    ProductoMenu(
      'papas-bbq-bacon',
      CategoriaMenu.papas,
      'BBQ Bacon',
      precio: 8500,
      descripcion: 'Papas fritas, trozos de salchicha jumbo, salsa BBQ ahumada, queso fundido y una capa extra de cebolla caramelizada.',
    ),
  ];

  static final List<ProductoMenu> _aderezos = [
    for (final (i, nombre) in const [
      'De la casa',
      'Hula Hula',
      'Cheddar',
      'Venenoso',
      'In & Out',
      'Comeback',
    ].indexed)
      ProductoMenu(
        'aderezo-${i + 1}',
        CategoriaMenu.aderezos,
        nombre,
        precio: _p(15),
      ),
  ];

  static const _refrescos = [
    ProductoMenu(
      'refresco-boing',
      CategoriaMenu.refrescos,
      'Boing 500 ml',
      precio: 2000,
    ),
    ProductoMenu(
      'refresco-coca',
      CategoriaMenu.refrescos,
      'Coca Cola 600 ml',
      precio: 2500,
    ),
    ProductoMenu(
      'refresco-sprite',
      CategoriaMenu.refrescos,
      'Sprite 600 ml',
      precio: 2300,
    ),
    ProductoMenu(
      'refresco-jarritos',
      CategoriaMenu.refrescos,
      'Jarritos 600 ml',
      precio: 2300,
    ),
    ProductoMenu(
      'refresco-fresca',
      CategoriaMenu.refrescos,
      'Fresca 600 ml',
      precio: 2300,
    ),
  ];

  static List<OpcionCombo> _opciones(List<String> ids) => [
    for (final id in ids) OpcionCombo(id),
  ];

  static final List<ProductoMenu> _combos = [
    ProductoMenu(
      'combo-solitario',
      CategoriaMenu.combos,
      'Solitario',
      precio: _p(160),
      descripcion: '1 hamburguesa Sweet Bacon + 1 porción papas normalitas + 1 refresco.',
      grupos: [
        GrupoCombo('Hamburguesa', 1, _opciones(['burger-sweet-bacon'])),
        GrupoCombo('Papas', 1, _opciones(['papas-normalitas'])),
        GrupoCombo(
          'Refresco',
          1,
          _opciones([for (final r in _refrescos) r.id]),
        ),
      ],
    ),
    ProductoMenu(
      'combo-desmadre',
      CategoriaMenu.combos,
      'Desmadre de Pareja',
      precio: _p(325),
      descripcion: '2 hamburguesas (Hula Hula, Sweet Bacon o Bonchosa) + 1 orden papas Criminales + 2 refrescos.',
      grupos: [
        GrupoCombo(
          'Hamburguesa',
          2,
          _opciones([
            'burger-hula-hula',
            'burger-sweet-bacon',
            'burger-bonchosa',
          ]),
        ),
        GrupoCombo('Papas', 1, _opciones(['papas-criminales'])),
        GrupoCombo(
          'Refresco',
          2,
          _opciones([for (final r in _refrescos) r.id]),
        ),
      ],
    ),
    ProductoMenu(
      'combo-pandora',
      CategoriaMenu.combos,
      'Caja de Pandora',
      precio: _p(500),
      descripcion: '2 hamburguesas (Tóxica, Junior o La Guacamole) + 2 doggos (El Perro Callejero, Pica Pica o Tóxico Guac) + 5 alitas + 5 boneless (cualquier sabor).',
      grupos: [
        GrupoCombo(
          'Hamburguesa',
          2,
          _opciones(['burger-toxica', 'burger-junior', 'burger-guacamole']),
        ),
        GrupoCombo(
          'Doggo',
          2,
          _opciones([
            'doggo-callejero',
            'doggo-pica-pica',
            'doggo-toxico-guac',
          ]),
        ),
        const GrupoCombo('Alitas', 1, [OpcionCombo('alitas', 'alitas-5')]),
        const GrupoCombo('Boneless', 1, [
          OpcionCombo('boneless', 'boneless-5'),
        ]),
      ],
    ),
    ProductoMenu(
      'combo-bajon',
      CategoriaMenu.combos,
      'Kit Para El Bajón',
      precio: _p(230),
      descripcion: '10 boneless a elegir + papas junior + 2 aderezos a elegir.',
      grupos: [
        const GrupoCombo('Boneless', 1, [
          OpcionCombo('boneless', 'boneless-10'),
        ]),
        GrupoCombo('Papas', 1, _opciones(['papas-junior'])),
        GrupoCombo('Aderezo', 2, _opciones([for (final a in _aderezos) a.id])),
      ],
    ),
  ];

  /// Menú tal como está escrito arriba (precios de respaldo).
  static final List<ProductoMenu> _base = [
    ..._burgers,
    ..._doggos,
    _alitas,
    _boneless,
    ..._papas,
    ..._combos,
    ..._aderezos,
    ..._refrescos,
  ];

  /// Menú vigente, con precios y disponibilidad de Supabase. Las pantallas lo escuchan.
  static final ValueNotifier<List<ProductoMenu>> catalogo = ValueNotifier(
    List.unmodifiable(_base),
  );

  static List<ProductoMenu> get productos => catalogo.value;

  static final Set<String> _nombresRepetidos = () {
    final cuenta = <String, int>{};
    for (final p in _base.where((p) => p.categoria != CategoriaMenu.aderezos)) {
      cuenta[p.nombre] = (cuenta[p.nombre] ?? 0) + 1;
    }
    return {
      for (final e in cuenta.entries)
        if (e.value > 1) e.key,
    };
  }();

  /// Aplica lo que hay en Supabase sobre el menú base. Se empata por categoría + nombre
  /// (y la variante por nombre); lo que no esté en [filas] se queda con su respaldo.
  static void actualizar(List<PrecioDb> filas) {
    final porNombre = {for (final f in filas) (f.categoriaDb, f.nombre): f};
    catalogo.value = List.unmodifiable([
      for (final p in _base)
        switch (porNombre[(p.categoria.db, p.nombre)]) {
          final PrecioDb f => p.conDb(f),
          null => p,
        },
    ]);
  }

  static ProductoMenu producto(String id) =>
      productoONull(id) ?? (throw StateError('No existe el producto $id'));

  static ProductoMenu? productoONull(String id) =>
      productos.where((p) => p.id == id).firstOrNull;

  /// Busca por los nombres con que el producto está en Supabase.
  static ProductoMenu? porNombreDb(String categoriaDb, String nombre) =>
      productos
          .where((p) => p.categoria.db == categoriaDb && p.nombre == nombre)
          .firstOrNull;

  static List<ProductoMenu> deCategoria(CategoriaMenu categoria) =>
      productos.where((p) => p.categoria == categoria).toList();

  /// "Junior" existe en Burgers, Doggos y Papas: en esos casos se antepone la categoría.
  static String nombreCompleto(ProductoMenu producto) {
    if (producto.categoria == CategoriaMenu.aderezos) {
      return 'Aderezo ${producto.nombre}';
    }
    if (producto.categoria == CategoriaMenu.papas) {
      return 'Papas ${producto.nombre}';
    }
    if (_nombresRepetidos.contains(producto.nombre)) {
      return '${producto.categoria.singular} ${producto.nombre}';
    }
    return producto.nombre;
  }

  /// "Boneless 5 piezas".
  static String nombreOpcion(OpcionCombo opcion) {
    final p = producto(opcion.productoId);
    final v = p.variante(opcion.varianteId);
    return [nombreCompleto(p), ?v?.nombre].join(' ');
  }

  /// Solo se ofrecen opciones cuyo producto (y variante) estén disponibles.
  static bool opcionDisponible(OpcionCombo opcion) {
    final p = productoONull(opcion.productoId);
    if (p == null || !p.activo) return false;
    if (opcion.varianteId == null) return true;
    return p.variante(opcion.varianteId)?.activo ?? false;
  }
}
