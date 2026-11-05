import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/formato.dart';
import '../../datos/pedidos/pedido.dart';
import '../../estado/proveedores.dart';
import '../../remoto/mensaje_error.dart';
import '../comun/componentes.dart';
import '../comun/confirmar.dart';
import '../principal.dart';
import '../tema.dart';
import 'editor.dart';

Future<void> abrirDetalle(BuildContext context, int id) => Navigator.push(
  context,
  MaterialPageRoute<void>(builder: (_) => DetallePedido(id: id)),
);

class DetallePedido extends ConsumerWidget {
  const DetallePedido({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedido = ref.watch(pedidoProvider(id));
    return PantallaInterna(
      titulo: 'Pedido #$id',
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(pedidoProvider(id).future),
        child: switch (pedido) {
          AsyncData(value: final p?) => _Contenido(pedido: p),
          AsyncData() => ListView(
            children: const [Mensaje('El pedido ya no existe.')],
          ),
          AsyncError(:final error) => ListView(
            children: [
              Mensaje(mensajeDeError(error), icono: Icons.error_outline),
              Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(pedidoProvider(id)),
                  child: const Text('Reintentar'),
                ),
              ),
            ],
          ),
          _ => ListView(children: const [Cargando()]),
        },
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.pedido});

  final PedidoCompleto pedido;

  Pedido get _p => pedido.pedido;

  /// Ejecuta un cambio y vuelve a consultar el pedido y la lista.
  Future<bool> _cambio(WidgetRef ref, Future<void> Function() accion) async {
    final ok = await ref.ejecutar(accion);
    ref.invalidate(pedidoProvider(_p.id));
    ref.read(pedidosProvider.notifier).refrescar();
    return ok;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(pedidosRepoProvider);
    final cancelado = _p.estado == EstadoPedido.cancelado;
    final (estado, color) = switch (_p.estado) {
      EstadoPedido.abierto => ('Por cobrar', context.alerta),
      EstadoPedido.pagado => ('Pagado', context.exito),
      EstadoPedido.cancelado => ('Cancelado', context.colores.onSurfaceVariant),
    };
    final suave = TextStyle(color: context.colores.onSurfaceVariant);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Centrado(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                franja: _p.estado == EstadoPedido.abierto
                    ? context.alerta
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_p.tipoEntrega.icono),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _p.tipoEntrega.etiqueta,
                            style: context.textos.titleMedium,
                          ),
                        ),
                        Text(
                          estado,
                          style: context.textos.titleSmall?.copyWith(
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(formatearFechaHora(_p.creadoEn), style: suave),
                    if (_p.cliente.isNotEmpty) _Dato(Icons.person, _p.cliente),
                    if (_p.telefono.isNotEmpty) _Dato(Icons.phone, _p.telefono),
                    if (_p.direccion.isNotEmpty)
                      _Dato(Icons.place, _p.direccion),
                    if (_p.notas.isNotEmpty) _Dato(Icons.notes, _p.notas),
                  ],
                ),
              ),
              const EncabezadoSeccion('Productos'),
              Panel(
                child: Column(
                  children: [
                    for (final r in pedido.renglones)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${r.cantidad}× ${r.titulo}',
                                    style: context.textos.titleSmall,
                                  ),
                                  for (final extra in [
                                    ?r.sabor,
                                    ?r.componentes,
                                    if (r.notas.isNotEmpty) r.notas,
                                  ])
                                    Text(
                                      extra,
                                      style: context.textos.bodySmall?.merge(
                                        suave,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(formatearCentavos(r.subtotal)),
                          ],
                        ),
                      ),
                    const Divider(height: 20),
                    if (_p.descuento > 0)
                      FilaMonto(
                        'Descuento',
                        '-${formatearCentavos(_p.descuento)}',
                      ),
                    FilaMonto(
                      'Total',
                      formatearCentavos(pedido.total),
                      fuerte: true,
                    ),
                    FilaMonto(
                      'Pagado',
                      formatearCentavos(pedido.pagado),
                      color: context.exito,
                    ),
                    FilaMonto(
                      'Pendiente',
                      formatearCentavos(pedido.pendiente),
                      color: pedido.pendiente > 0 ? context.alerta : null,
                    ),
                  ],
                ),
              ),
              if (pedido.pagos.isNotEmpty) ...[
                const EncabezadoSeccion('Pagos'),
                Panel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      for (final pago in pedido.pagos)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${pago.metodo.etiqueta} · ${formatearHora(pago.creadoEn)}',
                              ),
                            ),
                            Text(formatearCentavos(pago.monto)),
                            IconButton(
                              tooltip: 'Quitar pago',
                              icon: const Icon(Icons.close),
                              onPressed: () async {
                                final ok = await confirmar(
                                  context,
                                  titulo:
                                      '¿Quitar el pago de ${formatearCentavos(pago.monto)}?',
                                  mensaje:
                                      'El pedido volverá a quedar por cobrar.',
                                  confirmar: 'Quitar pago',
                                  peligro: true,
                                );
                                if (ok) {
                                  await _cambio(
                                    ref,
                                    () => repo.borrarPago(pago),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (!cancelado && pedido.pendiente > 0)
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final pago = await _dialogoCobro(context, pedido);
                      if (pago == null || !context.mounted) return;
                      final ok = await confirmar(
                        context,
                        titulo: '¿Registrar el pago?',
                        mensaje:
                            '${formatearCentavos(pago.$2)} en ${pago.$1.etiqueta.toLowerCase()} '
                            'para el pedido #${_p.id}.',
                        confirmar: 'Registrar',
                      );
                      if (ok) {
                        await _cambio(
                          ref,
                          () => repo.cobrar(_p.id, pago.$1, pago.$2),
                        );
                      }
                    },
                    icon: const Icon(Icons.payments),
                    label: Text(
                      'Cobrar ${formatearCentavos(pedido.pendiente)}',
                    ),
                  ),
                ),
              if (!cancelado) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final guardado = await abrirEdicion(context, pedido);
                    if (guardado == true) ref.invalidate(pedidoProvider(_p.id));
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar pedido'),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: cancelado
                        ? TextButton.icon(
                            onPressed: () async {
                              final ok = await confirmar(
                                context,
                                titulo: '¿Reabrir el pedido #${_p.id}?',
                                mensaje: 'Vuelve a contar en las ventas y se descuentan otra vez sus insumos.',
                                confirmar: 'Reabrir',
                              );
                              if (ok) {
                                await _cambio(ref, () => repo.reabrir(_p.id));
                              }
                            },
                            icon: const Icon(Icons.restore),
                            label: const Text('Reabrir'),
                          )
                        : TextButton.icon(
                            onPressed: () async {
                              final ok = await confirmar(
                                context,
                                titulo: '¿Cancelar el pedido #${_p.id}?',
                                mensaje:
                                    'Deja de contar en las ventas y sus insumos regresan al inventario. '
                                    'Se puede reabrir después.',
                                confirmar: 'Cancelar pedido',
                                cancelar: 'No',
                                peligro: true,
                              );
                              if (ok) {
                                await _cambio(ref, () => repo.cancelar(_p.id));
                              }
                            },
                            icon: const Icon(Icons.block),
                            label: const Text('Cancelar'),
                          ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: context.alerta,
                      ),
                      onPressed: () async {
                        final ok = await confirmar(
                          context,
                          titulo: '¿Eliminar el pedido #${_p.id}?',
                          mensaje:
                              'Se borra con sus productos y pagos, y sus insumos regresan al inventario. '
                              'No se puede deshacer.',
                          confirmar: 'Eliminar',
                          peligro: true,
                        );
                        if (!ok) return;
                        final listo = await ref.ejecutar(
                          () => repo.eliminar(_p.id),
                        );
                        ref.read(pedidosProvider.notifier).refrescar();
                        if (listo && context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.icono, this.texto);

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 18, color: context.colores.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(texto)),
      ],
    ),
  );
}

/// Método y monto (trae el pendiente). En efectivo calcula el cambio.
Future<(MetodoPago, int)?> _dialogoCobro(
  BuildContext context,
  PedidoCompleto pedido,
) => showDialog<(MetodoPago, int)>(
  context: context,
  builder: (_) => _DialogoCobro(pendiente: pedido.pendiente),
);

class _DialogoCobro extends StatefulWidget {
  const _DialogoCobro({required this.pendiente});

  final int pendiente;

  @override
  State<_DialogoCobro> createState() => _DialogoCobroState();
}

class _DialogoCobroState extends State<_DialogoCobro> {
  MetodoPago _metodo = MetodoPago.efectivo;
  late final _monto = TextEditingController(text: _sinSigno(widget.pendiente));
  final _conCuanto = TextEditingController();
  String? _error;

  static String _sinSigno(int centavos) =>
      formatearCentavos(centavos).replaceFirst(r'$', '').replaceAll(',', '');

  @override
  void dispose() {
    _monto.dispose();
    _conCuanto.dispose();
    super.dispose();
  }

  int? get _montoCentavos => parsearPesos(_monto.text);

  int? get _pagaCon => parsearPesos(_conCuanto.text);

  void _aceptar() {
    final monto = _montoCentavos;
    String? error;
    if (monto == null || monto <= 0) {
      error = 'Escribe un monto mayor a \$0.';
    } else if (monto > widget.pendiente) {
      error =
          'El monto no puede pasar de lo pendiente (${formatearCentavos(widget.pendiente)}).';
    } else if (_metodo == MetodoPago.efectivo &&
        _conCuanto.text.trim().isNotEmpty) {
      final paga = _pagaCon;
      if (paga == null || paga < monto) error = 'Con lo que paga no alcanza.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, (_metodo, monto!));
  }

  @override
  Widget build(BuildContext context) {
    final monto = _montoCentavos;
    final paga = _pagaCon;
    final cambio = (monto != null && paga != null && paga >= monto)
        ? paga - monto
        : null;
    return AlertDialog(
      title: const Text('Cobrar'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChipsSeleccion<MetodoPago>(
                opciones: MetodoPago.values,
                elegido: _metodo,
                etiqueta: (m) => m.etiqueta,
                onElegir: (m) => setState(() => _metodo = m),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _monto,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixText: r'$',
                ),
              ),
              if (_metodo == MetodoPago.efectivo) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _conCuanto,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '¿Con cuánto paga?',
                    prefixText: r'$',
                  ),
                ),
                if (cambio != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Cambio: ${formatearCentavos(cambio)}',
                      style: context.textos.titleMedium,
                    ),
                  ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: context.alerta)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _aceptar, child: const Text('Cobrar')),
      ],
    );
  }
}
