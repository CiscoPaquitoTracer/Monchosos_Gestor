import 'package:flutter_test/flutter_test.dart';
import 'package:monchosos_gestor/datos/resumen/resumen.dart';

Resumen resumen({
  int ventas = 40500,
  int estimadas = 15000,
  int anterior = 30000,
  int pedidos = 2,
  int gastos = 20000,
}) => Resumen(
  ventas: ventas,
  ventasEstimadas: estimadas,
  ventasMesAnterior: anterior,
  pedidos: pedidos,
  productos: 5,
  diasAbiertos: 3,
  descuentos: 2000,
  porCobrar: 9500,
  cobrado: const {},
  costoInsumos: 2100,
  insumosSinCosto: 0,
  gastos: gastos,
  compras: 0,
  topProductos: const [],
  porDiaSemana: const [],
);

void main() {
  test('ganancia y promedios', () {
    final r = resumen();
    expect(r.ganancia, 18400); // 405 − 21 − 200
    expect(r.ticketPromedio, 12750); // (405 − 150 del Excel) / 2 pedidos
    expect(r.cambioVsAnterior, closeTo(0.35, 0.0001)); // 405 / 300 − 1
  });

  test('sin mes anterior ni pedidos', () {
    final r = resumen(anterior: 0, pedidos: 0);
    expect(r.cambioVsAnterior, isNull);
    expect(r.ticketPromedio, isNull);
  });

  test('mes vacío', () {
    expect(
      resumen(ventas: 0, estimadas: 0, pedidos: 0, gastos: 0).sinDatos,
      isTrue,
    );
  });

  test('promedio por día', () {
    expect(const VentaDiaSemana(5, 2, 31000).promedio, 15500);
    expect(const VentaDiaSemana(1, 0, 0).promedio, 0);
  });

  test('lee el jsonb de resumen_mes', () {
    final r = Resumen.desdeJson({
      'ventas': 405,
      'ventas_estimadas': 150,
      'ventas_mes_anterior': '300.00',
      'pedidos': 2,
      'productos': 5,
      'dias_abiertos': 3,
      'descuentos': 20,
      'por_cobrar': 95,
      'cobrado': {'efectivo': 100.5, 'transferencia': 0, 'tarjeta': 50},
      'costo_insumos': 21,
      'insumos_sin_costo': 1,
      'gastos': 200,
      'compras': 0,
      'top_productos': [
        {'nombre': 'Burger Junior', 'cantidad': 3, 'total': 225},
      ],
      'por_dia_semana': [
        {'dia_semana': 5, 'dias': 2, 'total': 310},
      ],
    });
    expect(r.ventasMesAnterior, 30000);
    expect(r.cobrado.values.fold(0, (a, b) => a + b), 15050);
    expect(r.topProductos.single.total, 22500);
    expect(r.porDiaSemana.single.promedio, 15500);
  });
}
