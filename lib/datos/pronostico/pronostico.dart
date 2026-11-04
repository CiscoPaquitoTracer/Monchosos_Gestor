import 'package:intl/intl.dart';

import '../formato.dart';
import '../inventario/insumo.dart';

/// Un día del pronóstico (pronostico_dias en Supabase). [fecha] = "yyyy-MM-dd".
class DiaPronostico {
  const DiaPronostico({
    required this.fecha,
    required this.diaSemana,
    this.festivo,
    this.productosEsperados,
    this.productosPromedio,
    this.diasHistorial = 0,
  });

  factory DiaPronostico.desdeFila(Map<String, dynamic> f) => DiaPronostico(
    fecha: f['fecha'] as String,
    diaSemana: (f['dia_semana'] as num).toInt(),
    festivo: f['festivo'] as String?,
    productosEsperados: (f['productos_esperados'] as num?)?.toDouble(),
    productosPromedio: (f['productos_promedio'] as num?)?.toDouble(),
    diasHistorial: (f['dias_historial'] as num?)?.toInt() ?? 0,
  );

  static const double umbralFuerte = 1.15;

  final String fecha;

  /// 1 = lunes … 7 = domingo.
  final int diaSemana;
  final String? festivo;

  /// null = sin historial para estimar.
  final double? productosEsperados;

  /// Promedio de un día cualquiera, para comparar.
  final double? productosPromedio;
  final int diasHistorial;

  bool get finDeSemana => diaSemana >= 6;

  bool get especial => festivo != null || finDeSemana;

  /// Se espera vender claramente más que un día normal (15 % o más).
  bool get fuerte {
    final e = productosEsperados, p = productosPromedio;
    return e != null && p != null && p > 0 && e >= p * umbralFuerte;
  }

  DiaPronostico copyWith({
    double? Function()? productosEsperados,
    double? Function()? productosPromedio,
    int? diasHistorial,
  }) => DiaPronostico(
    fecha: fecha,
    diaSemana: diaSemana,
    festivo: festivo,
    productosEsperados: productosEsperados != null
        ? productosEsperados()
        : this.productosEsperados,
    productosPromedio: productosPromedio != null
        ? productosPromedio()
        : this.productosPromedio,
    diasHistorial: diasHistorial ?? this.diasHistorial,
  );
}

/// Lo que conviene comprar para cubrir los próximos días (pronostico_insumos).
class InsumoPorComprar {
  const InsumoPorComprar({
    required this.nombre,
    required this.unidad,
    required this.existencia,
    required this.consumoEsperado,
    required this.porComprar,
  });

  factory InsumoPorComprar.desdeFila(Map<String, dynamic> f) =>
      InsumoPorComprar(
        nombre: f['nombre'] as String,
        unidad: Unidad.desdeDb(f['unidad'] as String?),
        existencia: numeroDe(f['existencia']),
        consumoEsperado: numeroDe(f['consumo_esperado']),
        porComprar: numeroDe(f['por_comprar']),
      );

  final String nombre;
  final Unidad unidad;
  final double existencia;
  final double consumoEsperado;
  final double porComprar;

  /// Las piezas se redondean hacia arriba (2.3 panes → comprar 3).
  double get cantidadAComprar =>
      unidad == Unidad.pieza ? porComprar.ceilToDouble() : porComprar;

  String get texto => '$nombre: ${formatearCantidad(cantidadAComprar, unidad)}';
}

/// Fin de semana y/o festivo(s) que se acercan: días consecutivos "especiales".
class Evento {
  const Evento(this.dias);

  final List<DiaPronostico> dias;

  String get hasta => dias.last.fecha;

  bool get fuerte => dias.any((d) => d.fuerte);

  bool get conHistorial => dias.any((d) => d.diasHistorial > 0);

  /// "el fin de semana", "Día de Muertos", "Día de Muertos y el fin de semana"…
  String get nombre {
    final festivos = <String>[];
    for (final d in dias) {
      if (d.festivo != null && !festivos.contains(d.festivo)) {
        festivos.add(d.festivo!);
      }
    }
    final conFinde = dias.any((d) => d.finDeSemana && d.festivo == null);
    if (festivos.isEmpty) return 'el fin de semana';
    if (conFinde) return '${festivos.join(', ')} y el fin de semana';
    return festivos.join(', ');
  }

  double get productosEsperados =>
      dias.fold(0, (s, d) => s + (d.productosEsperados ?? 0));

  /// Cuánto más que días normales (0.25 = 25 % más), si hay datos.
  double? get aumento {
    final conDatos = dias.where(
      (d) => d.productosEsperados != null && (d.productosPromedio ?? 0) > 0,
    );
    if (conDatos.isEmpty) return null;
    final esperados = conDatos.fold<double>(
      0,
      (s, d) => s + d.productosEsperados!,
    );
    final promedio = conDatos.fold<double>(
      0,
      (s, d) => s + d.productosPromedio!,
    );
    return esperados / promedio - 1;
  }
}

/// Busca un fin de semana o festivo que empiece mañana o pasado mañana, y lo extiende a
/// los días especiales seguidos (festivo en lunes + sábado y domingo = un solo "puente").
/// [dias] empieza hoy. Hoy no cuenta: el aviso es para comprar con tiempo.
Evento? proximoEvento(List<DiaPronostico> dias) {
  int? inicio;
  for (final i in [1, 2]) {
    if (i < dias.length && dias[i].especial) {
      inicio = i;
      break;
    }
  }
  if (inicio == null) return null;
  var fin = inicio;
  while (fin + 1 < dias.length && dias[fin + 1].especial) {
    fin++;
  }
  return Evento(dias.sublist(inicio, fin + 1));
}

/// Hasta qué día comprar: el final del evento, o mañana si no hay evento.
String? hastaCuandoComprar(List<DiaPronostico> dias, Evento? evento) {
  if (evento != null) return evento.hasta;
  if (dias.length > 1) return dias[1].fecha;
  return dias.firstOrNull?.fecha;
}

/// Texto de la notificación (título, cuerpo), o null si no vale la pena avisar.
(String, String)? mensajeDeAviso(
  Evento evento,
  List<InsumoPorComprar> porComprar,
) {
  if (porComprar.isEmpty && !evento.fuerte) return null;
  final titulo = 'Se viene ${evento.nombre}';
  final cuerpo = StringBuffer();
  final aumento = evento.aumento;
  if (aumento != null && evento.fuerte) {
    cuerpo.write('Sueles vender ${(aumento * 100).toInt()} % más. ');
  }
  if (evento.conHistorial) {
    cuerpo.write(
      'Esperamos vender ~${evento.productosEsperados.toInt()} productos. ',
    );
  }
  if (porComprar.isEmpty) {
    cuerpo.write('Tus insumos alcanzan.');
  } else {
    cuerpo.write('Te falta: ');
    cuerpo.write(porComprar.take(4).map((i) => i.texto).join(', '));
    if (porComprar.length > 4) cuerpo.write(' y ${porComprar.length - 4} más');
    cuerpo.write('.');
  }
  return (titulo, cuerpo.toString().trim());
}

/// "2026-10-31" → "sábado 31". Si no es fecha, regresa el texto tal cual.
String nombreDelDia(String fecha) {
  final d = DateTime.tryParse(fecha);
  if (d == null) return fecha;
  return DateFormat('EEEE d', localeMx).format(d);
}

/// Pronóstico de la semana y, si se acerca un evento, qué comprar para cubrirlo.
class Pronostico {
  const Pronostico({
    required this.dias,
    required this.evento,
    required this.porComprar,
  });

  final List<DiaPronostico> dias;
  final Evento? evento;

  /// Para cubrir hasta el final del evento (o hasta mañana si no hay evento).
  final List<InsumoPorComprar> porComprar;

  bool get sinHistorial => dias.every((d) => d.diasHistorial == 0);
}
