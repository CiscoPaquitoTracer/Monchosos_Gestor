import 'package:flutter_test/flutter_test.dart';
import 'package:monchosos_gestor/datos/formato.dart';
import 'package:monchosos_gestor/datos/pedidos/pedido.dart';

void main() {
  test('formato y lectura de pesos', () {
    expect(formatearCentavos(16000), r'$160');
    expect(formatearCentavos(149000), r'$1,490');
    expect(formatearCentavos(15050), r'$150.50');
    expect(formatearCentavos(-2500), r'-$25');
    expect(parsearPesos('160'), 16000);
    expect(parsearPesos('150.5'), 15050);
    expect(parsearPesos(r'$1,490'), 149000);
    expect(parsearPesos('abc'), isNull);
    expect(parsearPesos('-5'), isNull);
    expect(parsearPesos('1.234'), isNull);
    expect(parsearPesos(''), isNull);
  });

  test('conversión de pesos a centavos sin errores de redondeo', () {
    expect(aCentavos(0.1 + 0.2), 30);
    expect(aCentavos(149.99), 14999);
    expect(aPesos(15050), 150.5);
  });

  test('resumen del día como cierre de turno', () {
    final hoy = DateTime(2026, 11, 3);
    DateTime h(int horas) => hoy.add(Duration(hours: horas));
    PedidoConTotales p(
      int id,
      DateTime creado,
      int total,
      int pagado,
      EstadoPedido e,
    ) => PedidoConTotales(
      pedido: Pedido(id: id, creadoEn: creado, estado: e),
      total: total,
      pagado: pagado,
      articulos: 1,
    );
    final pedidos = [
      p(1, h(1), 23000, 23000, EstadoPedido.pagado),
      p(2, h(2), 21000, 10000, EstadoPedido.abierto),
      p(3, h(3), 12000, 0, EstadoPedido.cancelado),
      p(4, h(-5), 5000, 0, EstadoPedido.abierto), // de ayer, sigue por cobrar
    ];
    final pagos = [
      Pago(
        pedidoId: 1,
        metodo: MetodoPago.efectivo,
        monto: 23000,
        creadoEn: h(1),
      ),
      Pago(
        pedidoId: 2,
        metodo: MetodoPago.transferencia,
        monto: 10000,
        creadoEn: h(2),
      ),
    ];
    final r = resumenDelDia(pedidos, pagos, hoy);
    expect(r.pedidos, 2);
    expect(r.ventas, 44000);
    expect(r.porCobrar, 2);
    expect(r.pendiente, 11000 + 5000);
    expect(r.cobradoPorMetodo[MetodoPago.efectivo], 23000);
    expect(r.cobrado, 33000);
  });
}
