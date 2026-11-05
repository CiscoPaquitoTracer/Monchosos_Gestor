import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/formato.dart';
import '../../datos/pedidos/pedido.dart';
import '../../datos/resumen/resumen.dart';
import '../../estado/proveedores.dart';
import '../../remoto/mensaje_error.dart';
import '../comun/componentes.dart';
import '../tema.dart';

const _dias = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

class PantallaResumen extends ConsumerStatefulWidget {
  const PantallaResumen({super.key});

  @override
  ConsumerState<PantallaResumen> createState() => _PantallaResumenState();
}

class _PantallaResumenState extends ConsumerState<PantallaResumen> {
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _esMesActual {
    final hoy = DateTime.now();
    return _mes.year == hoy.year && _mes.month == hoy.month;
  }

  void _mover(int delta) =>
      setState(() => _mes = DateTime(_mes.year, _mes.month + delta));

  @override
  Widget build(BuildContext context) {
    final clave = (_mes.year, _mes.month);
    final resumen = ref.watch(resumenProvider(clave));
    return RefreshIndicator(
      onRefresh: () => ref.refresh(resumenProvider(clave).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Centrado(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Mes anterior',
                      onPressed: () => _mover(-1),
                      icon: const Icon(Icons.keyboard_arrow_left),
                    ),
                    Expanded(
                      child: Text(
                        formatearMes(_mes),
                        textAlign: TextAlign.center,
                        style: context.textos.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mes siguiente',
                      onPressed: _esMesActual ? null : () => _mover(1),
                      icon: const Icon(Icons.keyboard_arrow_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                switch (resumen) {
                  AsyncData(:final value) =>
                    value.sinDatos
                        ? const Mensaje(
                            'No hay ventas ni gastos registrados en este mes.',
                            icono: Icons.bar_chart,
                          )
                        : _Contenido(r: value),
                  AsyncError(:final error) => Column(
                    children: [
                      Mensaje(
                        mensajeDeError(error),
                        icono: Icons.error_outline,
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(resumenProvider(clave)),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                  _ => const Cargando(),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.r});

  final Resumen r;

  @override
  Widget build(BuildContext context) {
    final cambio = r.cambioVsAnterior;
    final ticket = r.ticketPromedio;
    final maximo = r.porDiaSemana.fold(
      0,
      (m, d) => d.promedio > m ? d.promedio : m,
    );
    final porDia = {for (final d in r.porDiaSemana) d.diaSemana: d};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelDestacado(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vendido en el mes'),
              Text(
                formatearCentavos(r.ventas),
                style: context.textos.displaySmall?.copyWith(
                  color: Colores.blanco,
                ),
              ),
              if (cambio != null)
                Row(
                  children: [
                    Icon(
                      cambio >= 0 ? Icons.trending_up : Icons.trending_down,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${cambio >= 0 ? '+' : ''}${(cambio * 100).toStringAsFixed(0)} % contra el mes anterior',
                    ),
                  ],
                ),
              if (r.ventasEstimadas > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Incluye ${formatearCentavos(r.ventasEstimadas)} estimados del Excel (con los precios de hoy)',
                    style: context.textos.bodySmall?.copyWith(
                      color: Colores.blanco,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Panel(
          child: Row(
            children: [
              Expanded(child: Dato('Pedidos', '${r.pedidos}')),
              Expanded(
                child: Dato(
                  'Por pedido',
                  ticket == null ? '—' : formatearCentavos(ticket),
                ),
              ),
              Expanded(child: Dato('Días abiertos', '${r.diasAbiertos}')),
            ],
          ),
        ),
        const EncabezadoSeccion('Cobrado'),
        Panel(
          child: Column(
            children: [
              for (final m in MetodoPago.values)
                FilaMonto(m.etiqueta, formatearCentavos(r.cobrado[m] ?? 0)),
              const Divider(height: 16),
              FilaMonto(
                'Falta por cobrar',
                formatearCentavos(r.porCobrar),
                color: r.porCobrar > 0 ? context.alerta : null,
              ),
              FilaMonto('Descuentos dados', formatearCentavos(r.descuentos)),
            ],
          ),
        ),
        const EncabezadoSeccion('Ganancia estimada'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilaMonto('Ventas', formatearCentavos(r.ventas)),
              FilaMonto(
                'Costo de lo vendido',
                '-${formatearCentavos(r.costoInsumos)}',
              ),
              FilaMonto('Gastos', '-${formatearCentavos(r.gastos)}'),
              const Divider(height: 16),
              FilaMonto(
                'Ganancia',
                formatearCentavos(r.ganancia),
                fuerte: true,
                color: r.ganancia >= 0 ? context.exito : context.alerta,
              ),
              const SizedBox(height: 4),
              FilaMonto(
                'Compras de insumos del mes',
                formatearCentavos(r.compras),
                color: context.colores.onSurfaceVariant,
              ),
              if (r.insumosSinCosto > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    r.insumosSinCosto == 1
                        ? '1 insumo no tiene costo registrado: la ganancia es aproximada.'
                        : '${r.insumosSinCosto} insumos no tienen costo registrado: la ganancia es aproximada.',
                    style: context.textos.bodySmall?.copyWith(
                      color: context.alerta,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (r.topProductos.isNotEmpty) ...[
          const EncabezadoSeccion('Lo más vendido'),
          Panel(
            child: Column(
              children: [
                for (final (i, t) in r.topProductos.take(5).indexed)
                  FilaMonto(
                    '${i + 1}. ${t.nombre} ×${t.cantidad % 1 == 0 ? t.cantidad.toInt() : t.cantidad}',
                    formatearCentavos(t.total),
                  ),
              ],
            ),
          ),
        ],
        if (r.porDiaSemana.isNotEmpty) ...[
          const EncabezadoSeccion('Promedio por día de la semana'),
          Panel(
            child: Column(
              children: [
                for (var d = 1; d <= 7; d++)
                  if (porDia[d] case final v?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(width: 88, child: Text(_dias[d - 1])),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: maximo == 0 ? 0 : v.promedio / maximo,
                                minHeight: 10,
                                backgroundColor:
                                    context.colores.secondaryContainer,
                                color: context.colores.primary,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              formatearCentavos(v.promedio),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
