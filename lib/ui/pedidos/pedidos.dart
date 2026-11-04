import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/formato.dart';
import '../../datos/pedidos/pedido.dart';
import '../../estado/proveedores.dart';
import '../comun/componentes.dart';
import '../tema.dart';
import 'detalle.dart';
import 'editor.dart';

enum FiltroPedidos { porCobrar, hoy, todos }

class PantallaPedidos extends ConsumerStatefulWidget {
  const PantallaPedidos({super.key});

  @override
  ConsumerState<PantallaPedidos> createState() => _PantallaPedidosState();
}

class _PantallaPedidosState extends ConsumerState<PantallaPedidos> {
  FiltroPedidos _filtro = FiltroPedidos.porCobrar;

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(pedidosProvider);
    final todos = datos.valor?.pedidos;
    final hoy = inicioDelDia();
    final porCobrar =
        todos?.where((p) => p.pedido.estado == EstadoPedido.abierto).toList() ??
        [];
    final visibles = switch (_filtro) {
      FiltroPedidos.porCobrar => porCobrar,
      FiltroPedidos.hoy =>
        todos?.where((p) => !p.pedido.creadoEn.isBefore(hoy)).toList() ?? [],
      FiltroPedidos.todos => todos ?? [],
    };

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => abrirPedidoNuevo(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo pedido'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Centrado(
            child: ChipsSeleccion<FiltroPedidos>(
              desplazable: true,
              opciones: FiltroPedidos.values,
              elegido: _filtro,
              etiqueta: (f) => switch (f) {
                FiltroPedidos.porCobrar =>
                  porCobrar.isEmpty
                      ? 'Por cobrar'
                      : 'Por cobrar (${porCobrar.length})',
                FiltroPedidos.hoy => 'Hoy',
                FiltroPedidos.todos => 'Todos',
              },
              onElegir: (f) => setState(() => _filtro = f),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(pedidosProvider.notifier).refrescar(),
              child: todos == null
                  ? ListView(children: const [Cargando()])
                  : visibles.isEmpty
                  ? ListView(
                      children: [
                        Mensaje(switch (_filtro) {
                          FiltroPedidos.porCobrar =>
                            'No hay pedidos por cobrar.',
                          FiltroPedidos.hoy => 'Todavía no hay pedidos hoy.',
                          FiltroPedidos.todos => 'No hay pedidos registrados.',
                        }, icono: Icons.receipt_long_outlined),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      itemCount: visibles.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => Centrado(
                        child: FilaPedido(pedido: visibles[i], hoy: hoy),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class FilaPedido extends StatelessWidget {
  const FilaPedido({super.key, required this.pedido, required this.hoy});

  final PedidoConTotales pedido;
  final DateTime hoy;

  @override
  Widget build(BuildContext context) {
    final p = pedido.pedido;
    final esDeHoy = !p.creadoEn.isBefore(hoy);
    final cuando = esDeHoy
        ? formatearHora(p.creadoEn)
        : formatearFechaHora(p.creadoEn);
    final porCobrar = p.estado == EstadoPedido.abierto;
    final (estado, color) = switch (p.estado) {
      EstadoPedido.abierto when pedido.pagado > 0 => (
        'Debe ${formatearCentavos(pedido.pendiente)}',
        context.alerta,
      ),
      EstadoPedido.abierto => ('Por cobrar', context.alerta),
      EstadoPedido.pagado => ('Pagado', context.exito),
      EstadoPedido.cancelado => ('Cancelado', context.colores.onSurfaceVariant),
    };
    final articulos = pedido.articulos == 1
        ? '1 artículo'
        : '${pedido.articulos} artículos';
    return Panel(
      franja: porCobrar ? context.alerta : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: () => abrirDetalle(context, p.id),
      child: Row(
        children: [
          Icon(p.tipoEntrega.icono, color: context.colores.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('#${p.id} · $cuando', style: context.textos.titleSmall),
                Text(
                  '${p.cliente.isEmpty ? p.tipoEntrega.etiqueta : p.cliente} · $articulos',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colores.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatearCentavos(pedido.total),
                style: context.textos.titleMedium,
              ),
              Text(
                estado,
                style: context.textos.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
