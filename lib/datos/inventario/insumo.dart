import '../errores.dart';

/// Unidad en la que se cuenta un insumo. [db] = valor en Supabase.
enum Unidad {
  kilogramo('Kilogramo', 'kg', 'kg', 0.5),
  pieza('Pieza', 'pz', 'pieza', 1),
  litro('Litro', 'L', 'litro', 0.5);

  const Unidad(this.etiqueta, this.abreviatura, this.db, this.paso);

  final String etiqueta;
  final String abreviatura;
  final String db;

  /// Lo que suma o resta cada toque en el diálogo de ajuste.
  final double paso;

  static Unidad desdeDb(String? valor) =>
      Unidad.values.where((u) => u.db == valor).firstOrNull ?? Unidad.pieza;
}

/// Sección del inventario, en el orden en que se muestra (migración 010).
enum CategoriaInsumo {
  carnes('Carnes', Unidad.kilogramo, 'carnes'),
  lacteos('Lácteos', Unidad.kilogramo, 'lacteos'),
  panes('Panes', Unidad.pieza, 'panes'),
  verduras('Verduras', Unidad.kilogramo, 'verduras'),
  aderezos('Aderezos y salsas', Unidad.litro, 'aderezos'),
  abarrotes('Abarrotes', Unidad.kilogramo, 'abarrotes'),
  bebidas('Bebidas', Unidad.pieza, 'bebidas'),
  desechable('Desechables', Unidad.pieza, 'desechable'),
  otro('Otros', Unidad.pieza, 'otro');

  const CategoriaInsumo(this.etiqueta, this.unidadSugerida, this.db);

  final String etiqueta;
  final Unidad unidadSugerida;
  final String db;

  /// Un valor desconocido se trata como "Otros".
  static CategoriaInsumo desdeDb(String? valor) =>
      CategoriaInsumo.values.where((c) => c.db == valor).firstOrNull ??
      CategoriaInsumo.otro;
}

/// Algo que se compra y se gasta en el negocio (ingredientes o desechables).
class Insumo {
  const Insumo({
    this.id = 0,
    required this.nombre,
    required this.categoria,
    required this.unidad,
    required this.cantidad,
    this.stockMinimo = 0,
    this.costoUnitario = 0,
  });

  final int id;
  final String nombre;
  final CategoriaInsumo categoria;
  final Unidad unidad;
  final double cantidad;

  /// En esta cantidad o abajo se marca "por agotarse". 0 = sin aviso.
  final double stockMinimo;

  /// Costo por kg, pieza o litro, según [unidad].
  final double costoUnitario;

  bool get bajoStock => stockMinimo > 0 && cantidad <= stockMinimo;

  double get valorTotal => cantidad * costoUnitario;

  Insumo copyWith({double? cantidad, double? stockMinimo}) => Insumo(
    id: id,
    nombre: nombre,
    categoria: categoria,
    unidad: unidad,
    cantidad: cantidad ?? this.cantidad,
    stockMinimo: stockMinimo ?? this.stockMinimo,
    costoUnitario: costoUnitario,
  );

  factory Insumo.desdeFila(Map<String, dynamic> f) => Insumo(
    id: (f['id'] as num).toInt(),
    nombre: f['nombre'] as String,
    categoria: CategoriaInsumo.desdeDb(f['categoria'] as String?),
    unidad: Unidad.desdeDb(f['unidad'] as String?),
    cantidad: _num(f['cantidad']),
    stockMinimo: _num(f['stock_minimo']),
    costoUnitario: _num(f['costo_unitario']),
  );

  static double _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? 0}') ?? 0;
}

/// "2.5 kg", "40 pz", "1.5 L". Las piezas se muestran sin decimales.
String formatearCantidad(double cantidad, Unidad unidad) =>
    '${formatearNumero(cantidad, unidad)} ${unidad.abreviatura}';

/// El número solo: piezas enteras; kg y L con hasta 3 decimales sin ceros sobrantes.
String formatearNumero(double cantidad, Unidad unidad) {
  if (unidad == Unidad.pieza) return cantidad.truncate().toString();
  var t = cantidad.toStringAsFixed(3);
  t = t.replaceFirst(RegExp(r'0+$'), '');
  if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  return t == '-0' ? '0' : t;
}

/// Lo que el usuario escribe en el formulario de insumo, todavía como texto.
class FormularioInsumo {
  const FormularioInsumo({
    this.id = 0,
    this.nombre = '',
    this.categoria = CategoriaInsumo.carnes,
    Unidad? unidad,
    this.cantidad = '',
    this.stockMinimo = '',
    this.costoUnitario = '',
  }) : unidad = unidad ?? Unidad.kilogramo;

  factory FormularioInsumo.desde(Insumo i) => FormularioInsumo(
    id: i.id,
    nombre: i.nombre,
    categoria: i.categoria,
    unidad: i.unidad,
    cantidad: _texto(i.cantidad),
    stockMinimo: i.stockMinimo == 0 ? '' : _texto(i.stockMinimo),
    costoUnitario: i.costoUnitario == 0 ? '' : _texto(i.costoUnitario),
  );

  final int id;
  final String nombre;
  final CategoriaInsumo categoria;
  final Unidad unidad;
  final String cantidad;
  final String stockMinimo;
  final String costoUnitario;

  FormularioInsumo copyWith({
    String? nombre,
    CategoriaInsumo? categoria,
    Unidad? unidad,
    String? cantidad,
    String? stockMinimo,
    String? costoUnitario,
  }) => FormularioInsumo(
    id: id,
    nombre: nombre ?? this.nombre,
    categoria: categoria ?? this.categoria,
    unidad: unidad ?? this.unidad,
    cantidad: cantidad ?? this.cantidad,
    stockMinimo: stockMinimo ?? this.stockMinimo,
    costoUnitario: costoUnitario ?? this.costoUnitario,
  );

  /// Convierte a [Insumo] o lanza [ErrorValidacion] con el primer error.
  Insumo validar() {
    final nombreLimpio = nombre.trim();
    if (nombreLimpio.isEmpty) {
      throw const ErrorValidacion('Escribe el nombre del insumo.');
    }
    final cant = _numero(cantidad);
    if (cant == null) {
      throw const ErrorValidacion('La cantidad no es un número válido.');
    }
    final minimo = _numero(stockMinimo, 0);
    if (minimo == null) {
      throw const ErrorValidacion(
        'El aviso en el mínimo no es un número válido.',
      );
    }
    final costo = _numero(costoUnitario, 0);
    if (costo == null) {
      throw const ErrorValidacion('El costo no es un número válido.');
    }
    if (cant < 0 || minimo < 0 || costo < 0) {
      throw const ErrorValidacion('No se permiten números negativos.');
    }
    if (unidad == Unidad.pieza && (cant % 1 != 0 || minimo % 1 != 0)) {
      throw const ErrorValidacion('Las piezas deben ser números enteros.');
    }
    return Insumo(
      id: id,
      nombre: nombreLimpio,
      categoria: categoria,
      unidad: unidad,
      cantidad: cant,
      stockMinimo: minimo,
      costoUnitario: costo,
    );
  }

  static String _texto(double n) =>
      n % 1 == 0 ? n.toInt().toString() : n.toString();

  /// Acepta "1,5" y "1.5". Texto vacío → [vacio] (null = obligatorio).
  static double? _numero(String texto, [double? vacio]) {
    final t = texto.trim().replaceAll(',', '.');
    if (t.isEmpty) return vacio;
    final n = double.tryParse(t);
    return (n != null && n.isFinite) ? n : null;
  }
}
