import 'package:intl/intl.dart';

/// Formato de dinero, cantidades y fechas en español de México.
///
/// El dinero SIEMPRE va en centavos (`int`): nunca se suman pesos con `double`.

const String localeMx = 'es_MX';

final NumberFormat _miles = NumberFormat('#,##0', 'en_US');

/// 16000 → "$160", 15050 → "$150.50", 149000 → "$1,490".
String formatearCentavos(int centavos) {
  final signo = centavos < 0 ? '-' : '';
  final absoluto = centavos.abs();
  final entero = _miles.format(absoluto ~/ 100);
  final resto = absoluto % 100;
  return resto == 0
      ? '$signo\$$entero'
      : '$signo\$$entero.${resto.toString().padLeft(2, '0')}';
}

final RegExp _monto = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$');

/// "160", "160.5", "$1,490" → centavos (la coma es separador de miles).
/// `null` si no es un monto válido (vacío, negativo o con más de 2 decimales).
int? parsearPesos(String texto) {
  var limpio = texto.trim();
  if (limpio.startsWith(r'$')) limpio = limpio.substring(1);
  limpio = limpio.replaceAll(',', '').trim();
  final m = _monto.firstMatch(limpio);
  if (m == null) return null;
  final pesos = int.parse(m.group(1)!);
  final decimales = (m.group(2) ?? '').padRight(2, '0');
  return pesos * 100 + int.parse(decimales);
}

/// numeric de Postgres (pesos) → centavos, sin errores de redondeo.
int aCentavos(num pesos) => (pesos * 100).round();

/// Centavos → pesos para mandar a Supabase.
double aPesos(int centavos) => centavos / 100;

/// Lee un número que puede venir como int, double o texto (numeric de Postgres).
double numeroDe(Object? valor, [double siNulo = 0]) {
  if (valor == null) return siNulo;
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor.toString()) ?? siNulo;
}

/// "HH:mm".
String formatearHora(DateTime fecha) =>
    DateFormat('HH:mm', localeMx).format(fecha.toLocal());

/// "vie 30 de oct · 19:45".
String formatearFechaHora(DateTime fecha) =>
    DateFormat("EEE d 'de' MMM · HH:mm", localeMx).format(fecha.toLocal());

/// "Viernes 30 de octubre" (con mayúscula inicial).
String formatearFechaLarga(DateTime fecha) =>
    capitalizar(DateFormat("EEEE d 'de' MMMM", localeMx).format(fecha));

/// "octubre de 2026" → "Octubre 2026".
String formatearMes(DateTime mes) =>
    capitalizar(DateFormat('MMMM yyyy', localeMx).format(mes));

String capitalizar(String texto) =>
    texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);

/// Medianoche de hoy en la hora del teléfono.
DateTime inicioDelDia([DateTime? ahora]) {
  final a = ahora ?? DateTime.now();
  return DateTime(a.year, a.month, a.day);
}

/// "yyyy-MM-dd" (para los parámetros de las funciones de Supabase).
String fechaIso(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';
