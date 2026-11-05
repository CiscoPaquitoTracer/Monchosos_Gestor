import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:monchosos_gestor/datos/formato.dart';
import 'package:monchosos_gestor/datos/inventario/insumo.dart';
import 'package:monchosos_gestor/datos/pronostico/pronostico.dart';

/// Semana de 7 días empezando en [diaSemanaHoy]; [festivos] = índice → nombre.
List<DiaPronostico> semana(
  int diaSemanaHoy, {
  Map<int, String> festivos = const {},
  double? Function(DiaPronostico)? productos,
}) {
  double? porDefecto(DiaPronostico d) => d.especial ? 30.0 : 20.0;
  final f = productos ?? porDefecto;
  return [
    for (var i = 0; i < 7; i++)
      () {
        final base = DiaPronostico(
          fecha: '2026-11-${(i + 1).toString().padLeft(2, '0')}',
          diaSemana: (diaSemanaHoy - 1 + i) % 7 + 1,
          festivo: festivos[i],
        );
        return base.copyWith(
          productosEsperados: () => f(base),
          productosPromedio: () => 22.0,
          diasHistorial: 4,
        );
      }(),
  ];
}

const pan = InsumoPorComprar(
  nombre: 'Pan para hamburguesa',
  unidad: Unidad.pieza,
  existencia: 10,
  consumoEsperado: 32.3,
  porComprar: 22.3,
);

void main() {
  setUpAll(() => initializeDateFormatting(localeMx));

  test('el jueves avisa del fin de semana', () {
    final e = proximoEvento(semana(4))!;
    expect(e.dias.map((d) => d.diaSemana), [6, 7]);
    expect(e.nombre, 'el fin de semana');
    expect(e.fuerte, isTrue);
  });

  test('un lunes sin festivo no tiene evento', () {
    expect(proximoEvento(semana(1)), isNull);
  });

  test('un festivo en lunes hace puente con el fin de semana', () {
    final e = proximoEvento(semana(5, festivos: {3: 'Revolución Mexicana'}))!;
    expect(e.dias.length, 3);
    expect(e.nombre, 'Revolución Mexicana y el fin de semana');
    expect(e.hasta, '2026-11-04');
  });

  test('festivo entre semana', () {
    final e = proximoEvento(semana(1, festivos: {2: 'Día de Muertos'}))!;
    expect(e.nombre, 'Día de Muertos');
    expect(e.dias.length, 1);
  });

  test('mensaje con faltantes y aumento', () {
    final e = proximoEvento(semana(4))!;
    final (titulo, cuerpo) = mensajeDeAviso(e, [pan])!;
    expect(titulo, 'Se viene el fin de semana');
    expect(cuerpo, contains('36 % más')); // 60 esperados / 44 normales
    expect(cuerpo, contains('~60 productos'));
    expect(cuerpo, contains('Pan para hamburguesa: 23 pz')); // 22.3 piezas → 23
  });

  test('sin faltantes y día normal no avisa', () {
    final e = proximoEvento(semana(4, productos: (_) => 20.0))!;
    expect(mensajeDeAviso(e, const []), isNull);
    // Pero si faltan insumos, sí avisa aunque se venda lo normal.
    expect(mensajeDeAviso(e, [pan])!.$2, contains('Te falta'));
  });

  test('más de 4 faltantes se resumen', () {
    final e = proximoEvento(semana(4))!;
    final (_, cuerpo) = mensajeDeAviso(e, List.filled(6, pan))!;
    expect(cuerpo, endsWith(' y 2 más.'));
  });

  test('sin historial no inventa números', () {
    final vacio = semana(4, productos: (_) => null)
        .map((d) => d.copyWith(productosPromedio: () => null, diasHistorial: 0))
        .toList();
    final e = proximoEvento(vacio)!;
    expect(e.aumento, isNull);
    final (_, cuerpo) = mensajeDeAviso(e, [pan])!;
    expect(cuerpo, isNot(contains('productos')));
  });

  test('hasta cuándo comprar: fin del evento o mañana', () {
    final dias = semana(4);
    expect(hastaCuandoComprar(dias, proximoEvento(dias)), '2026-11-04');
    expect(hastaCuandoComprar(semana(1), null), '2026-11-02');
  });

  test('nombre del día en español', () {
    expect(nombreDelDia('2026-10-31'), 'sábado 31');
    expect(nombreDelDia('no-es-fecha'), 'no-es-fecha');
  });
}
