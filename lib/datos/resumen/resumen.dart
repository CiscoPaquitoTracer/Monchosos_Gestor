import '../formato.dart';
import '../pedidos/pedido.dart';

class ProductoTop {
  const ProductoTop(this.nombre, this.cantidad, this.total);

  final String nombre;
  final double cantidad;
  final int total;
}

/// [diaSemana]: 1 = lunes … 7 = domingo. [total] = todo lo vendido esos días.
class VentaDiaSemana {
  const VentaDiaSemana(this.diaSemana, this.dias, this.total);

  final int diaSemana;
  final int dias;
  final int total;

  int get promedio => dias == 0 ? 0 : total ~/ dias;
}

/// Resumen de un mes (función resumen_mes en Supabase). Importes en centavos.
class Resumen {
  const Resumen({
    required this.ventas,
    required this.ventasEstimadas,
    required this.ventasMesAnterior,
    required this.pedidos,
    required this.productos,
    required this.diasAbiertos,
    required this.descuentos,
    required this.porCobrar,
    required this.cobrado,
    required this.costoInsumos,
    required this.insumosSinCosto,
    required this.gastos,
    required this.compras,
    required this.topProductos,
    required this.porDiaSemana,
  });

  factory Resumen.desdeJson(Map<String, dynamic> j) {
    final cobrado = (j['cobrado'] as Map?)?.cast<String, dynamic>() ?? {};
    return Resumen(
      ventas: aCentavos(numeroDe(j['ventas'])),
      ventasEstimadas: aCentavos(numeroDe(j['ventas_estimadas'])),
      ventasMesAnterior: aCentavos(numeroDe(j['ventas_mes_anterior'])),
      pedidos: numeroDe(j['pedidos']).toInt(),
      productos: numeroDe(j['productos']),
      diasAbiertos: numeroDe(j['dias_abiertos']).toInt(),
      descuentos: aCentavos(numeroDe(j['descuentos'])),
      porCobrar: aCentavos(numeroDe(j['por_cobrar'])),
      cobrado: {
        for (final m in MetodoPago.values)
          m: aCentavos(numeroDe(cobrado[m.db])),
      },
      costoInsumos: aCentavos(numeroDe(j['costo_insumos'])),
      insumosSinCosto: numeroDe(j['insumos_sin_costo']).toInt(),
      gastos: aCentavos(numeroDe(j['gastos'])),
      compras: aCentavos(numeroDe(j['compras'])),
      topProductos: [
        for (final t in (j['top_productos'] as List? ?? const []).cast<Map>())
          ProductoTop(
            t['nombre'] as String,
            numeroDe(t['cantidad']),
            aCentavos(numeroDe(t['total'])),
          ),
      ],
      porDiaSemana: [
        for (final d in (j['por_dia_semana'] as List? ?? const []).cast<Map>())
          VentaDiaSemana(
            numeroDe(d['dia_semana']).toInt(),
            numeroDe(d['dias']).toInt(),
            aCentavos(numeroDe(d['total'])),
          ),
      ],
    );
  }

  final int ventas;

  /// Parte de [ventas] que viene del historial importado (Excel), con precios actuales.
  final int ventasEstimadas;
  final int ventasMesAnterior;
  final int pedidos;
  final double productos;
  final int diasAbiertos;
  final int descuentos;
  final int porCobrar;
  final Map<MetodoPago, int> cobrado;
  final int costoInsumos;
  final int insumosSinCosto;
  final int gastos;
  final int compras;
  final List<ProductoTop> topProductos;
  final List<VentaDiaSemana> porDiaSemana;

  /// Ventas − costo de lo vendido (según recetas) − gastos.
  int get ganancia => ventas - costoInsumos - gastos;

  /// Promedio por pedido de la app (el historial no tiene pedidos).
  int? get ticketPromedio =>
      pedidos == 0 ? null : (ventas - ventasEstimadas) ~/ pedidos;

  /// 0.12 = 12 % más que el mes anterior; null si el mes anterior no tiene ventas.
  double? get cambioVsAnterior =>
      ventasMesAnterior <= 0 ? null : ventas / ventasMesAnterior - 1;

  bool get sinDatos =>
      ventas == 0 && pedidos == 0 && gastos == 0 && compras == 0;
}
