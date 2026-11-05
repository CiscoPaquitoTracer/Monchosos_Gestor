import 'package:supabase_flutter/supabase_flutter.dart';

import '../datos/formato.dart';
import '../datos/inventario/insumo.dart';
import '../datos/menu/menu.dart';
import '../datos/pedidos/pedido.dart';
import '../datos/pronostico/pronostico.dart';
import '../datos/resumen/resumen.dart';

/// Consultas a Supabase con el contrato exacto de MIGRACION_FLUTTER.md §5.5.
/// Los montos llegan en pesos (numeric) y se convierten a centavos al leerlos.

typedef Fila = Map<String, dynamic>;

/// Precios y disponibilidad del menú. Cada cambio de precio queda en historial_precios
/// (trigger) y los pedidos ya hechos conservan su precio.
class MenuRepositorio {
  const MenuRepositorio(this._db);

  final SupabaseClient _db;

  Future<void> refrescar() async {
    final filas = await _db
        .from('productos')
        .select(
          'id, nombre, precio, activo, categorias_menu(nombre), variantes(id, nombre, precio, activo)',
        );
    Menu.actualizar([
      for (final f in filas)
        PrecioDb(
          id: (f['id'] as num).toInt(),
          categoriaDb: (f['categorias_menu'] as Map)['nombre'] as String,
          nombre: f['nombre'] as String,
          precio: f['precio'] == null ? null : aCentavos(numeroDe(f['precio'])),
          activo: f['activo'] as bool? ?? true,
          variantes: [
            for (final v in (f['variantes'] as List? ?? const []).cast<Map>())
              VarianteDb(
                id: (v['id'] as num).toInt(),
                nombre: v['nombre'] as String,
                precio: aCentavos(numeroDe(v['precio'])),
                activo: v['activo'] as bool? ?? true,
              ),
          ],
        ),
    ]);
  }

  /// Cambia precio y disponibilidad del producto, o de [variante] si se vende por tamaño.
  Future<void> guardar(
    ProductoMenu producto,
    Variante? variante, {
    required int centavos,
    required bool disponible,
  }) async {
    if (centavos <= 0) throw StateError('El precio debe ser mayor a 0.');
    final tabla = variante != null ? 'variantes' : 'productos';
    final id = _idDe(variante?.dbId ?? producto.dbId);
    await _db
        .from(tabla)
        .update({'precio': aPesos(centavos), 'activo': disponible})
        .eq('id', id);
    await refrescar();
  }

  /// dbId = 0: el menú aún no se cargó de Supabase y no se edita a ciegas.
  int _idDe(int dbId) {
    if (dbId == 0) {
      throw StateError(
        'El menú aún no carga. Revisa tu conexión e intenta de nuevo.',
      );
    }
    return dbId;
  }
}

/// Inventario. La existencia nunca se edita directo: cada cambio pasa por
/// movimientos_inventario (guardar_insumo y ajustar_existencia), así la bitácora cuadra.
class InventarioRepositorio {
  const InventarioRepositorio(this._db);

  final SupabaseClient _db;

  Future<List<Insumo>> consultar() async {
    final filas = await _db
        .from('insumos')
        .select()
        .eq('activo', true)
        .order('categoria', ascending: true)
        .order('nombre', ascending: true);
    return [for (final f in filas) Insumo.desdeFila(f)];
  }

  Future<void> guardar(Insumo i) => _db.rpc(
    'guardar_insumo',
    params: {
      'datos': {
        if (i.id != 0) 'id': i.id,
        'nombre': i.nombre,
        'categoria': i.categoria.db,
        'unidad': i.unidad.db,
        'cantidad': i.cantidad,
        'stock_minimo': i.stockMinimo,
        'costo_unitario': i.costoUnitario,
      },
    },
  );

  Future<void> ajustar(Insumo i, double delta) => _db.rpc(
    'ajustar_existencia',
    params: {'p_insumo_id': i.id, 'p_delta': delta},
  );

  /// No se borra (tiene historial y recetas): se desactiva.
  Future<void> eliminar(Insumo i) =>
      _db.from('insumos').update({'activo': false}).eq('id', i.id);
}

/// Lo que regresa la lista de pedidos: los pedidos y los pagos de hoy.
class ListaPedidos {
  const ListaPedidos(this.pedidos, this.pagosHoy);

  final List<PedidoConTotales> pedidos;

  /// Pagos de hoy de pedidos no cancelados (para el resumen del día).
  final List<Pago> pagosHoy;
}

/// Pedidos (ventas, venta_detalle, venta_componentes y pagos).
class PedidosRepositorio {
  const PedidosRepositorio(this._db);

  final SupabaseClient _db;

  static const _producto =
      'productos(nombre, categorias_menu(nombre)), variantes(nombre), sabores(nombre)';
  static const _completo =
      'id, fecha, tipo_entrega, cliente, telefono, direccion, notas, estado, descuento, '
      'venta_detalle(id, cantidad, precio_unitario, notas, $_producto, '
      'venta_componentes(id, cantidad, $_producto)), '
      'pagos(id, venta_id, metodo, monto, creado_en)';

  Future<ListaPedidos> consultar() async {
    final lista = _db
        .from('v_ventas')
        .select()
        .order('fecha', ascending: false)
        .limit(300);
    final pagos = _db
        .from('pagos')
        .select('id, venta_id, metodo, monto, creado_en, ventas!inner(estado)')
        .gte('creado_en', inicioDelDia().toUtc().toIso8601String())
        .neq('ventas.estado', EstadoPedido.cancelado.db);
    final (filas, filasPagos) = await (lista, pagos).wait;
    return ListaPedidos(
      [
        for (final f in filas)
          PedidoConTotales(
            pedido: _pedido(f),
            total: aCentavos(numeroDe(f['total'])),
            pagado: aCentavos(numeroDe(f['pagado'])),
            articulos: numeroDe(f['articulos']).toInt(),
          ),
      ],
      [for (final f in filasPagos) _pago(f)],
    );
  }

  /// El pedido completo, o null si ya no existe.
  Future<PedidoCompleto?> obtener(int id) async {
    final f = await _db
        .from('ventas')
        .select(_completo)
        .eq('id', id)
        .maybeSingle();
    if (f == null) return null;
    final detalles =
        (f['venta_detalle'] as List? ?? const []).cast<Fila>().toList()
          ..sort((a, b) => (a['id'] as num).compareTo(b['id'] as num));
    final pagos = [
      for (final p in (f['pagos'] as List? ?? const []).cast<Fila>()) _pago(p),
    ]..sort((a, b) => a.creadoEn.compareTo(b.creadoEn));
    return PedidoCompleto(
      pedido: _pedido(f),
      renglones: [for (final d in detalles) _renglon(d)],
      pagos: pagos,
    );
  }

  /// Crea o reemplaza el pedido completo en una sola transacción. Devuelve el id.
  Future<int> guardar(Pedido pedido, List<Renglon> renglones) async {
    final id = await _db.rpc(
      'guardar_venta',
      params: {
        'datos': {
          'id': pedido.id == 0 ? null : pedido.id,
          'tipo_entrega': pedido.tipoEntrega.db,
          'cliente': pedido.cliente,
          'telefono': pedido.telefono,
          'direccion': pedido.direccion,
          'notas': pedido.notas,
          'renglones': [
            for (final r in renglones)
              {
                'categoria': r.categoriaDb,
                'producto': r.productoDb,
                'variante': r.variante,
                'sabor': r.sabor,
                'cantidad': r.cantidad,
                'precio_unitario': aPesos(r.precioUnitario),
                'notas': r.notas,
                'componentes': [for (final p in r.partes) p.aJson()],
              },
          ],
        },
      },
    );
    return (id as num).toInt();
  }

  Future<void> cobrar(int pedidoId, MetodoPago metodo, int monto) =>
      _db.from('pagos').insert({
        'venta_id': pedidoId,
        'metodo': metodo.db,
        'monto': aPesos(monto),
      });

  Future<void> borrarPago(Pago pago) =>
      _db.from('pagos').delete().eq('id', pago.id);

  Future<void> cancelar(int id) => _estado(id, EstadoPedido.cancelado);

  /// Al reabrir, la base de datos recalcula si queda pagado o por cobrar.
  Future<void> reabrir(int id) => _estado(id, EstadoPedido.abierto);

  /// El borrado es en cascada y devuelve los insumos.
  Future<void> eliminar(int id) => _db.from('ventas').delete().eq('id', id);

  Future<void> _estado(int id, EstadoPedido e) =>
      _db.from('ventas').update({'estado': e.db}).eq('id', id);

  static Pedido _pedido(Fila f) => Pedido(
    id: (f['id'] as num).toInt(),
    creadoEn: DateTime.parse(f['fecha'] as String).toLocal(),
    tipoEntrega: TipoEntrega.desdeDb(f['tipo_entrega'] as String?),
    cliente: f['cliente'] as String? ?? '',
    telefono: f['telefono'] as String? ?? '',
    direccion: f['direccion'] as String? ?? '',
    notas: f['notas'] as String? ?? '',
    estado: EstadoPedido.desdeDb(f['estado'] as String?),
    descuento: aCentavos(numeroDe(f['descuento'])),
  );

  static Pago _pago(Fila f) => Pago(
    id: (f['id'] as num).toInt(),
    pedidoId: (f['venta_id'] as num).toInt(),
    metodo: MetodoPago.desdeDb(f['metodo'] as String?),
    monto: aCentavos(numeroDe(f['monto'])),
    creadoEn: DateTime.parse(f['creado_en'] as String).toLocal(),
  );

  static String? _nombre(Object? v) => (v as Map?)?['nombre'] as String?;

  static Renglon _renglon(Fila d) {
    final producto = d['productos'] as Map;
    final categoria = _nombre(producto['categorias_menu']) ?? '';
    final nombre = producto['nombre'] as String;
    final enMenu = Menu.porNombreDb(categoria, nombre);
    final componentes =
        (d['venta_componentes'] as List? ?? const []).cast<Fila>().toList()
          ..sort((a, b) => (a['id'] as num).compareTo(b['id'] as num));
    final partes = [
      for (final c in componentes)
        for (var i = 0; i < numeroDe(c['cantidad'], 1).toInt(); i++)
          Parte(
            _nombre((c['productos'] as Map)['categorias_menu']) ?? '',
            (c['productos'] as Map)['nombre'] as String,
            _nombre(c['variantes']),
            _nombre(c['sabores']),
          ),
    ];
    String textoParte(Parte p) {
      final m = Menu.porNombreDb(p.categoriaDb, p.productoDb);
      final base = [
        m == null ? p.productoDb : Menu.nombreCompleto(m),
        ?p.variante,
      ].join(' ');
      return p.sabor == null ? base : '$base (${p.sabor})';
    }

    return Renglon(
      productoId: enMenu?.id ?? '',
      categoriaDb: categoria,
      productoDb: nombre,
      nombre: enMenu == null ? nombre : Menu.nombreCompleto(enMenu),
      variante: _nombre(d['variantes']),
      sabor: _nombre(d['sabores']),
      componentes: partes.isEmpty ? null : partes.map(textoParte).join(', '),
      partes: partes,
      cantidad: numeroDe(d['cantidad'], 1).toInt(),
      precioUnitario: aCentavos(numeroDe(d['precio_unitario'])),
      notas: d['notas'] as String? ?? '',
    );
  }
}

/// Las estimaciones las calcula la base de datos (migración 008) con el historial.
class PronosticoRepositorio {
  const PronosticoRepositorio(this._db);

  final SupabaseClient _db;

  Future<Pronostico> consultar({int dias = 7}) async {
    final filas =
        await _db.rpc('pronostico_dias', params: {'p_dias': dias}) as List;
    final proximos = [
      for (final f in filas.cast<Fila>()) DiaPronostico.desdeFila(f),
    ];
    final evento = proximoEvento(proximos);
    final hasta = hastaCuandoComprar(proximos, evento);
    var porComprar = const <InsumoPorComprar>[];
    if (hasta != null) {
      final insumos = await _db.rpc(
        'pronostico_insumos',
        params: {'p_hasta': hasta},
      ) as List;
      porComprar = [
        for (final f in insumos.cast<Fila>()) InsumoPorComprar.desdeFila(f),
      ].where((i) => i.porComprar > 0).toList();
    }
    return Pronostico(dias: proximos, evento: evento, porComprar: porComprar);
  }
}

class ResumenRepositorio {
  const ResumenRepositorio(this._db);

  final SupabaseClient _db;

  /// [mes] = cualquier día del mes; se manda el día 1.
  Future<Resumen> delMes(DateTime mes) async {
    final j = await _db.rpc(
      'resumen_mes',
      params: {'p_fecha': fechaIso(DateTime(mes.year, mes.month))},
    );
    return Resumen.desdeJson((j as Map).cast<String, dynamic>());
  }
}
