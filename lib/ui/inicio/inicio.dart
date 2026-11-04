import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/formato.dart';
import '../../datos/inventario/insumo.dart';
import '../../datos/pedidos/pedido.dart';
import '../../datos/pronostico/pronostico.dart';
import '../../estado/proveedores.dart';
import '../comun/componentes.dart';
import '../pedidos/editor.dart';
import '../principal.dart';
import '../tema.dart';

class PantallaInicio extends ConsumerWidget {
  const PantallaInicio({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(pedidosProvider);
    final inventario = ref.watch(inventarioProvider);
    final pronostico = ref.watch(pronosticoProvider);
    final lista = pedidos.valor;
    final dia = lista == null
        ? null
        : resumenDelDia(lista.pedidos, lista.pagosHoy, inicioDelDia());

    return RefreshIndicator(
      onRefresh: () => Future.wait([
        ref.read(pedidosProvider.notifier).refrescar(),
        ref.read(inventarioProvider.notifier).refrescar(),
        ref.read(pronosticoProvider.notifier).refrescar(),
      ]),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Centrado(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  formatearFechaLarga(DateTime.now()),
                  style: context.textos.titleMedium,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: () => abrirPedidoNuevo(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Tomar pedido'),
                    style: FilledButton.styleFrom(
                      textStyle: context.textos.titleMedium,
                    ),
                  ),
                ),
                const EncabezadoSeccion('Hoy'),
                if (dia == null) const Cargando() else _Hoy(dia: dia),
                const EncabezadoSeccion('Próximos días'),
                switch (pronostico.valor) {
                  final Pronostico p => TarjetaPronostico(pronostico: p),
                  null when pronostico.error != null => Mensaje(
                    pronostico.error!,
                  ),
                  null => const Cargando(),
                },
                const EncabezadoSeccion('Inventario'),
                switch (inventario.valor) {
                  final List<Insumo> i => _Inventario(insumos: i),
                  null => const Cargando(),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hoy extends ConsumerWidget {
  const _Hoy({required this.dia});

  final ResumenDia dia;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PanelDestacado(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vendido hoy'),
            Text(
              formatearCentavos(dia.ventas),
              style: context.textos.displaySmall?.copyWith(
                color: Colores.blanco,
              ),
            ),
            Text(dia.pedidos == 1 ? '1 pedido' : '${dia.pedidos} pedidos'),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Panel(
        child: Column(
          children: [
            FilaMonto('Cobrado', formatearCentavos(dia.cobrado), fuerte: true),
            const SizedBox(height: 4),
            for (final m in MetodoPago.values)
              FilaMonto(
                m.etiqueta,
                formatearCentavos(dia.cobradoPorMetodo[m] ?? 0),
                color: context.colores.onSurfaceVariant,
              ),
            if (dia.porCobrar > 0) ...[
              const Divider(height: 16),
              InkWell(
                onTap: () =>
                    ref.read(seccionProvider.notifier).ir(Seccion.pedidos),
                child: FilaMonto(
                  dia.porCobrar == 1
                      ? '1 pedido por cobrar'
                      : '${dia.porCobrar} pedidos por cobrar',
                  formatearCentavos(dia.pendiente),
                  color: context.alerta,
                  icono: Icons.schedule,
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

/// "Se viene el fin de semana" o "Próximos días" (§6.4).
class TarjetaPronostico extends StatelessWidget {
  const TarjetaPronostico({super.key, required this.pronostico});

  final Pronostico pronostico;

  @override
  Widget build(BuildContext context) {
    final evento = pronostico.evento;
    final porComprar = pronostico.porComprar;
    if (pronostico.sinHistorial) {
      return const Panel(
        child: Text(
          'Todavía no hay ventas suficientes para estimar los próximos días. '
          'Conforme registres pedidos aquí verás cuánto sueles vender y qué conviene comprar.',
        ),
      );
    }
    final dias = evento?.dias ?? pronostico.dias.skip(1).take(3).toList();
    final aumento = evento?.aumento;
    return Panel(
      franja: porComprar.isEmpty ? null : Colores.mostaza,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            evento == null ? 'Próximos días' : 'Se viene ${evento.nombre}',
            style: context.textos.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final d in dias) _FilaDia(dia: d),
          if (evento != null && evento.fuerte && aumento != null) ...[
            const SizedBox(height: 6),
            Text(
              'Sueles vender ${(aumento * 100).toInt()} % más que un día normal.',
            ),
          ],
          const Divider(height: 20),
          if (porComprar.isEmpty)
            Row(
              children: [
                Icon(Icons.check_circle, color: context.exito, size: 20),
                const SizedBox(width: 8),
                const Text('Tus insumos alcanzan'),
              ],
            )
          else ...[
            Row(
              children: [
                const Icon(
                  Icons.shopping_cart_outlined,
                  color: Colores.mostaza,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text('Conviene comprar', style: context.textos.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            for (final i in porComprar)
              FilaMonto(
                i.nombre,
                formatearCantidad(i.cantidadAComprar, i.unidad),
              ),
          ],
        ],
      ),
    );
  }
}

class _FilaDia extends StatelessWidget {
  const _FilaDia({required this.dia});

  final DiaPronostico dia;

  @override
  Widget build(BuildContext context) {
    final esperados = dia.productosEsperados;
    final cerrado =
        dia.diasHistorial > 0 && (esperados == null || esperados == 0);
    final suave = TextStyle(color: context.colores.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: capitalizar(nombreDelDia(dia.fecha)),
                children: [
                  if (dia.festivo != null)
                    TextSpan(text: ' · ${dia.festivo}', style: suave),
                ],
              ),
            ),
          ),
          if (dia.fuerte) ...[
            Icon(Icons.trending_up, color: context.exito, size: 18),
            const SizedBox(width: 4),
          ],
          Text(
            cerrado
                ? 'no suele abrir'
                : esperados == null
                ? '—'
                : '~${esperados.round()} productos',
            style: cerrado ? suave : null,
          ),
        ],
      ),
    );
  }
}

class _Inventario extends StatelessWidget {
  const _Inventario({required this.insumos});

  final List<Insumo> insumos;

  @override
  Widget build(BuildContext context) {
    final valor = insumos.fold<double>(0, (s, i) => s + i.valorTotal);
    final bajos = insumos.where((i) => i.bajoStock).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Row(
            children: [
              Expanded(child: Dato('Insumos registrados', '${insumos.length}')),
              Expanded(
                child: Dato(
                  'Valor del inventario',
                  formatearCentavos(aCentavos(valor)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Panel(
          franja: bajos.isEmpty ? null : context.alerta,
          child: bajos.isEmpty
              ? Row(
                  children: [
                    Icon(Icons.check_circle, color: context.exito, size: 20),
                    const SizedBox(width: 8),
                    const Text('Nada por agotarse'),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Por agotarse',
                      style: context.textos.titleSmall?.copyWith(
                        color: context.alerta,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final i in bajos)
                      FilaMonto(
                        i.nombre,
                        formatearCantidad(i.cantidad, i.unidad),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
