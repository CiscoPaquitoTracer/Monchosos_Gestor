import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

/// [db] = valor en Supabase (ventas.tipo_entrega).
enum TipoEntrega {
  local('Comer aquí', 'local', Icons.restaurant),
  paraLlevar('Para llevar', 'para_llevar', Icons.takeout_dining),
  domicilio('Domicilio', 'domicilio', Icons.delivery_dining);

  const TipoEntrega(this.etiqueta, this.db, this.icono);

  final String etiqueta;
  final String db;
  final IconData icono;

  static TipoEntrega desdeDb(String? v) =>
      values.where((t) => t.db == v).firstOrNull ?? TipoEntrega.local;
}

/// [db] = valor en Supabase (ventas.estado). El estado lo calcula la base de datos.
enum EstadoPedido {
  abierto('Por cobrar', 'abierta'),
  pagado('Pagado', 'pagada'),
  cancelado('Cancelado', 'cancelada');

  const EstadoPedido(this.etiqueta, this.db);

  final String etiqueta;
  final String db;

  static EstadoPedido desdeDb(String? v) =>
      values.where((e) => e.db == v).firstOrNull ?? EstadoPedido.abierto;
}

/// [db] = valor en Supabase (dominio metodo_pago).
enum MetodoPago {
  efectivo('Efectivo', 'efectivo'),
  transferencia('Transferencia', 'transferencia'),
  tarjeta('Tarjeta / Mercado Pago', 'tarjeta');

  const MetodoPago(this.etiqueta, this.db);

  final String etiqueta;
  final String db;

  static MetodoPago desdeDb(String? v) =>
      values.where((m) => m.db == v).firstOrNull ?? MetodoPago.efectivo;
}

/// Una comanda. Los importes van en centavos.
class Pedido {
  Pedido({
    this.id = 0,
    DateTime? creadoEn,
    this.tipoEntrega = TipoEntrega.local,
    this.cliente = '',
    this.telefono = '',
    this.direccion = '',
    this.notas = '',
    this.estado = EstadoPedido.abierto,
    this.descuento = 0,
  }) : creadoEn = creadoEn ?? DateTime.now();

  final int id;
  final DateTime creadoEn;
  final TipoEntrega tipoEntrega;
  final String cliente;
  final String telefono;
  final String direccion;
  final String notas;
  final EstadoPedido estado;
  final int descuento;

  Pedido copyWith({
    TipoEntrega? tipoEntrega,
    String? cliente,
    String? telefono,
    String? direccion,
    String? notas,
  }) => Pedido(
    id: id,
    creadoEn: creadoEn,
    tipoEntrega: tipoEntrega ?? this.tipoEntrega,
    cliente: cliente ?? this.cliente,
    telefono: telefono ?? this.telefono,
    direccion: direccion ?? this.direccion,
    notas: notas ?? this.notas,
    estado: estado,
    descuento: descuento,
  );
}

/// Algo elegido dentro de un combo, con los nombres que usa la base de datos.
@immutable
class Parte {
  const Parte(this.categoriaDb, this.productoDb, [this.variante, this.sabor]);

  final String categoriaDb;
  final String productoDb;
  final String? variante;
  final String? sabor;

  Map<String, dynamic> aJson() => {
    'categoria': categoriaDb,
    'producto': productoDb,
    'variante': variante,
    'sabor': sabor,
    'cantidad': 1,
  };

  @override
  bool operator ==(Object other) =>
      other is Parte &&
      other.categoriaDb == categoriaDb &&
      other.productoDb == productoDb &&
      other.variante == variante &&
      other.sabor == sabor;

  @override
  int get hashCode => Object.hash(categoriaDb, productoDb, variante, sabor);

  @override
  String toString() => 'Parte($categoriaDb, $productoDb, $variante, $sabor)';
}

/// Un renglón del pedido. Guarda nombre y precio CONGELADOS al momento de la venta.
class Renglon {
  const Renglon({
    required this.productoId,
    required this.categoriaDb,
    required this.productoDb,
    required this.nombre,
    this.variante,
    this.sabor,
    this.componentes,
    this.partes = const [],
    required this.cantidad,
    required this.precioUnitario,
    this.notas = '',
  });

  final String productoId;

  /// Nombre de la categoría y del producto en Supabase (para guardar).
  final String categoriaDb;
  final String productoDb;

  /// Nombre para mostrar ("Burger Junior").
  final String nombre;
  final String? variante;
  final String? sabor;

  /// Lo elegido dentro de un combo, en texto: "Hula Hula, Bonchosa, Papas Criminales…".
  final String? componentes;
  final List<Parte> partes;
  final int cantidad;
  final int precioUnitario;
  final String notas;

  int get subtotal => cantidad * precioUnitario;

  /// "Burger Junior", "Alitas 10 piezas".
  String get titulo => [nombre, ?variante].join(' ');

  /// Mismo producto con las mismas elecciones → se suma la cantidad en vez de duplicar.
  bool mismoArticuloQue(Renglon o) =>
      categoriaDb == o.categoriaDb &&
      productoDb == o.productoDb &&
      variante == o.variante &&
      sabor == o.sabor &&
      listEquals(partes, o.partes) &&
      notas == o.notas &&
      precioUnitario == o.precioUnitario;

  Renglon copyWith({int? cantidad, String? notas}) => Renglon(
    productoId: productoId,
    categoriaDb: categoriaDb,
    productoDb: productoDb,
    nombre: nombre,
    variante: variante,
    sabor: sabor,
    componentes: componentes,
    partes: partes,
    cantidad: cantidad ?? this.cantidad,
    precioUnitario: precioUnitario,
    notas: notas ?? this.notas,
  );
}

class Pago {
  Pago({
    this.id = 0,
    required this.pedidoId,
    required this.metodo,
    required this.monto,
    DateTime? creadoEn,
  }) : creadoEn = creadoEn ?? DateTime.now();

  final int id;
  final int pedidoId;
  final MetodoPago metodo;
  final int monto;
  final DateTime creadoEn;
}

/// Para la lista: el pedido con sus totales (calculados por la base de datos).
class PedidoConTotales {
  const PedidoConTotales({
    required this.pedido,
    required this.total,
    required this.pagado,
    required this.articulos,
  });

  final Pedido pedido;
  final int total;
  final int pagado;
  final int articulos;

  int get pendiente => total - pagado < 0 ? 0 : total - pagado;
}

/// Para el detalle: el pedido con renglones y pagos.
class PedidoCompleto {
  const PedidoCompleto({
    required this.pedido,
    required this.renglones,
    required this.pagos,
  });

  final Pedido pedido;
  final List<Renglon> renglones;
  final List<Pago> pagos;

  int get subtotal => renglones.fold(0, (s, r) => s + r.subtotal);

  int get total {
    final t = subtotal - pedido.descuento;
    return t < 0 ? 0 : t;
  }

  int get pagado => pagos.fold(0, (s, p) => s + p.monto);

  int get pendiente => total - pagado < 0 ? 0 : total - pagado;
}

/// Resumen tipo "cierre de turno" de las comandas.
class ResumenDia {
  const ResumenDia({
    this.pedidos = 0,
    this.ventas = 0,
    this.porCobrar = 0,
    this.pendiente = 0,
    this.cobradoPorMetodo = const {},
  });

  final int pedidos;
  final int ventas;
  final int porCobrar;
  final int pendiente;
  final Map<MetodoPago, int> cobradoPorMetodo;

  int get cobrado => cobradoPorMetodo.values.fold(0, (s, v) => s + v);
}

/// [pagos] deben ser solo de pedidos no cancelados. [desde] = inicio del día.
/// Los pedidos por cobrar se cuentan aunque sean de días anteriores (siguen pendientes).
ResumenDia resumenDelDia(
  List<PedidoConTotales> pedidos,
  List<Pago> pagos,
  DateTime desde,
) {
  final vigentes = pedidos.where(
    (p) => p.pedido.estado != EstadoPedido.cancelado,
  );
  final deHoy = vigentes.where((p) => !p.pedido.creadoEn.isBefore(desde));
  final abiertos = vigentes.where(
    (p) => p.pedido.estado == EstadoPedido.abierto,
  );
  final porMetodo = <MetodoPago, int>{};
  for (final p in pagos.where((p) => !p.creadoEn.isBefore(desde))) {
    porMetodo[p.metodo] = (porMetodo[p.metodo] ?? 0) + p.monto;
  }
  return ResumenDia(
    pedidos: deHoy.length,
    ventas: deHoy.fold(0, (s, p) => s + p.total),
    porCobrar: abiertos.length,
    pendiente: abiertos.fold(0, (s, p) => s + p.pendiente),
    cobradoPorMetodo: porMetodo,
  );
}
