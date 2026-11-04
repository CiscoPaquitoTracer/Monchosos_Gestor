import '../errores.dart';
import '../pedidos/pedido.dart';
import 'menu.dart';

/// Lo que el cliente eligió para un lugar de un combo (ej. "Hamburguesa 1 de 2").
class Eleccion {
  const Eleccion(this.opcion, [this.sabor]);

  final OpcionCombo opcion;
  final String? sabor;

  Eleccion conSabor(String? sabor) => Eleccion(opcion, sabor);
}

/// Los lugares de un combo, uno por cada unidad de cada grupo
/// (Desmadre de Pareja: 2 hamburguesas + 1 papas + 2 refrescos = 5 lugares).
List<GrupoCombo> lugaresDe(ProductoMenu combo) => [
  for (final g in combo.grupos)
    for (var i = 0; i < g.cantidad; i++) g,
];

/// Convierte lo elegido en pantalla en un [Renglon], validando contra el menú.
/// Lanza [ErrorValidacion] con el mensaje para el usuario.
Renglon armarRenglon(
  ProductoMenu producto, {
  String? varianteId,
  String? sabor,
  List<Eleccion?> elecciones = const [],
  int cantidad = 1,
  String notas = '',
}) {
  if (cantidad < 1) {
    throw const ErrorValidacion('La cantidad debe ser al menos 1.');
  }
  final variante = producto.variante(varianteId);
  if (producto.variantes.isNotEmpty && variante == null) {
    throw const ErrorValidacion('Elige el tamaño.');
  }
  if (producto.conSabor && !Menu.sabores.contains(sabor)) {
    throw const ErrorValidacion('Elige el sabor.');
  }

  String? componentes;
  var partes = const <Parte>[];
  if (producto.esCombo) {
    final lugares = lugaresDe(producto);
    if (elecciones.length != lugares.length || elecciones.contains(null)) {
      throw const ErrorValidacion('Completa todas las opciones del combo.');
    }
    final elegidas = elecciones.cast<Eleccion>();
    for (var i = 0; i < lugares.length; i++) {
      final grupo = lugares[i];
      final e = elegidas[i];
      if (!grupo.opciones.contains(e.opcion)) {
        throw ErrorValidacion('Opción no válida en ${grupo.nombre}.');
      }
      if (Menu.producto(e.opcion.productoId).conSabor &&
          !Menu.sabores.contains(e.sabor)) {
        throw ErrorValidacion(
          'Elige el sabor de ${Menu.nombreOpcion(e.opcion)}.',
        );
      }
    }
    partes = [
      for (final e in elegidas)
        () {
          final p = Menu.producto(e.opcion.productoId);
          return Parte(
            p.categoria.db,
            p.nombre,
            p.variante(e.opcion.varianteId)?.nombre,
            e.sabor,
          );
        }(),
    ];
    componentes = elegidas
        .map(
          (e) =>
              Menu.nombreOpcion(e.opcion) +
              (e.sabor == null ? '' : ' (${e.sabor})'),
        )
        .join(', ');
  }

  final precio = variante?.precio ?? producto.precio;
  if (precio == null) {
    throw const ErrorValidacion('El producto no tiene precio.');
  }
  return Renglon(
    productoId: producto.id,
    categoriaDb: producto.categoria.db,
    productoDb: producto.nombre,
    nombre: Menu.nombreCompleto(producto),
    variante: variante?.nombre,
    sabor: producto.conSabor ? sabor : null,
    componentes: componentes,
    partes: partes,
    cantidad: cantidad,
    precioUnitario: precio,
    notas: notas.trim(),
  );
}

/// Agrega [nuevo] a [renglones]: si ya hay uno igual, suma la cantidad.
List<Renglon> agregarRenglon(List<Renglon> renglones, Renglon nuevo) {
  final i = renglones.indexWhere((r) => r.mismoArticuloQue(nuevo));
  if (i < 0) return [...renglones, nuevo];
  return [
    for (var j = 0; j < renglones.length; j++)
      j == i
          ? renglones[j].copyWith(
              cantidad: renglones[j].cantidad + nuevo.cantidad,
            )
          : renglones[j],
  ];
}
