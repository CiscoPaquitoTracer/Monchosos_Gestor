import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/formato.dart';
import '../../datos/menu/armar_renglon.dart';
import '../../datos/menu/menu.dart';
import '../../datos/pedidos/pedido.dart';
import '../../estado/proveedores.dart';
import '../comun/componentes.dart';
import '../comun/confirmar.dart';
import '../principal.dart';
import '../tema.dart';
import 'configurar_producto.dart';
import 'detalle.dart';

/// Abre el editor vacío. Al guardar, se abre el detalle para cobrar.
Future<void> abrirPedidoNuevo(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute<void>(builder: (_) => const EditorPedido()),
);

/// Abre el editor con un pedido existente. Devuelve true si se guardó.
Future<bool?> abrirEdicion(BuildContext context, PedidoCompleto pedido) =>
    Navigator.push(
      context,
      MaterialPageRoute<bool>(builder: (_) => EditorPedido(existente: pedido)),
    );

class EditorPedido extends ConsumerStatefulWidget {
  const EditorPedido({super.key, this.existente});

  final PedidoCompleto? existente;

  @override
  ConsumerState<EditorPedido> createState() => _EditorPedidoState();
}

class _EditorPedidoState extends ConsumerState<EditorPedido> {
  late Pedido _pedido = widget.existente?.pedido ?? Pedido();
  late List<Renglon> _renglones = [...?widget.existente?.renglones];
  bool _revision = false;
  bool _cambios = false;
  bool _guardando = false;
  CategoriaMenu _categoria = CategoriaMenu.burgers;

  late final _cliente = TextEditingController(text: _pedido.cliente);
  late final _telefono = TextEditingController(text: _pedido.telefono);
  late final _direccion = TextEditingController(text: _pedido.direccion);
  late final _notas = TextEditingController(text: _pedido.notas);

  bool get _editando => widget.existente != null;

  int get _total => _renglones.fold(0, (s, r) => s + r.subtotal);

  int get _articulos => _renglones.fold(0, (s, r) => s + r.cantidad);

  @override
  void dispose() {
    for (final c in [_cliente, _telefono, _direccion, _notas]) {
      c.dispose();
    }
    super.dispose();
  }

  void _cambiar(VoidCallback f) => setState(() {
    f();
    _cambios = true;
  });

  Future<void> _tocarProducto(ProductoMenu p) async {
    if (!p.necesitaConfigurar) {
      _cambiar(() => _renglones = agregarRenglon(_renglones, armarRenglon(p)));
      _avisarAgregado(Menu.nombreCompleto(p));
      return;
    }
    final r = await configurarProducto(context, p);
    if (r == null || !mounted) return;
    _cambiar(() => _renglones = agregarRenglon(_renglones, r));
    _avisarAgregado(r.titulo);
  }

  void _avisarAgregado(String nombre) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Agregado: $nombre'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  Future<void> _quitar(int i) async {
    final ok = await confirmar(
      context,
      titulo: '¿Quitar del pedido?',
      mensaje: _renglones[i].titulo,
      confirmar: 'Quitar',
    );
    if (ok) _cambiar(() => _renglones = [..._renglones]..removeAt(i));
  }

  Future<void> _notasDe(int i) async {
    final notas = await editarNotas(context, _renglones[i]);
    if (notas == null || notas == _renglones[i].notas) return;
    _cambiar(
      () =>
          _renglones = [..._renglones]
            ..[i] = _renglones[i].copyWith(notas: notas),
    );
  }

  Future<void> _guardar() async {
    final tipo = _pedido.tipoEntrega;
    final pedido = _pedido.copyWith(
      cliente: _cliente.text.trim(),
      telefono: tipo == TipoEntrega.local ? '' : _telefono.text.trim(),
      direccion: tipo == TipoEntrega.domicilio ? _direccion.text.trim() : '',
      notas: _notas.text.trim(),
    );
    setState(() => _guardando = true);
    var id = 0;
    final ok = await ref.ejecutar(() async {
      id = await ref.read(pedidosRepoProvider).guardar(pedido, _renglones);
    });
    if (!mounted) return;
    setState(() => _guardando = false);
    if (!ok) return;
    ref.read(pedidosProvider.notifier).refrescar();
    ref.invalidate(pedidoProvider(id));
    _cambios = false;
    if (_editando) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => DetallePedido(id: id)),
      );
    }
  }

  /// Back: de la revisión regresa al menú; si hay cambios pide confirmar.
  Future<void> _regresar() async {
    if (_revision) {
      setState(() => _revision = false);
      return;
    }
    if (_cambios) {
      final ok = await confirmar(
        context,
        titulo: _editando ? '¿Descartar los cambios?' : '¿Descartar el pedido?',
        mensaje: _editando
            ? 'Los cambios que hiciste no se guardarán.'
            : 'Se perderán los productos que agregaste.',
        confirmar: 'Descartar',
        cancelar: 'Seguir editando',
        peligro: true,
      );
      if (!ok || !mounted) return;
    }
    _cambios = false;
    _revision = false;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(menuProvider); // precios y disponibilidad al día
    return PopScope(
      canPop: !_cambios && !_revision,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _regresar();
      },
      child: PantallaInterna(
        titulo: _editando ? 'Editar pedido #${_pedido.id}' : 'Pedido nuevo',
        abajo: _barraInferior(),
        child: _revision ? _pasoRevision() : _pasoMenu(),
      ),
    );
  }

  Widget _barraInferior() {
    final listo = _renglones.isNotEmpty && !_guardando;
    return Material(
      color: context.colores.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.colores.outline)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Centrado(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_articulos == 1 ? '1 artículo' : '$_articulos artículos'} · ${formatearCentavos(_total)}',
                    style: context.textos.titleMedium,
                  ),
                ),
                if (_revision)
                  FilledButton.icon(
                    onPressed: listo ? _guardar : null,
                    icon: _guardando
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _editando ? 'Guardar cambios' : 'Guardar pedido',
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: listo
                        ? () => setState(() => _revision = true)
                        : null,
                    icon: const Icon(Icons.arrow_forward),
                    iconAlignment: IconAlignment.end,
                    label: const Text('Revisar pedido'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Paso 1: menú

  Widget _pasoMenu() {
    final productos = Menu.deCategoria(_categoria).where((p) {
      if (!p.activo) return false;
      return p.variantes.isEmpty || p.variantesActivas.isNotEmpty;
    }).toList();
    final conNota =
        _categoria == CategoriaMenu.burgers ||
        _categoria == CategoriaMenu.doggos;
    return Column(
      children: [
        const SizedBox(height: 12),
        Centrado(
          child: ChipsSeleccion<CategoriaMenu>(
            desplazable: true,
            opciones: CategoriaMenu.values,
            elegido: _categoria,
            etiqueta: (c) => c.etiqueta,
            onElegir: (c) => setState(() => _categoria = c),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (conNota)
                Centrado(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      Menu.nota,
                      style: TextStyle(color: context.colores.onSurfaceVariant),
                    ),
                  ),
                ),
              if (productos.isEmpty)
                const Mensaje(
                  'No hay productos disponibles en esta categoría.',
                ),
              for (final p in productos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Centrado(
                    child: _FilaProducto(
                      producto: p,
                      onTap: () => _tocarProducto(p),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- Paso 2: revisión

  Widget _pasoRevision() {
    final tipo = _pedido.tipoEntrega;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Centrado(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EncabezadoSeccion('Productos'),
              for (var i = 0; i < _renglones.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _FilaRenglon(
                    renglon: _renglones[i],
                    onTap: () => _notasDe(i),
                    onMenos: _renglones[i].cantidad == 1
                        ? () => _quitar(i)
                        : () => _cambiar(
                            () => _renglones = [..._renglones]
                              ..[i] = _renglones[i].copyWith(
                                cantidad: _renglones[i].cantidad - 1,
                              ),
                          ),
                    onMas: () => _cambiar(
                      () => _renglones = [..._renglones]
                        ..[i] = _renglones[i].copyWith(
                          cantidad: _renglones[i].cantidad + 1,
                        ),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _revision = false),
                icon: const Icon(Icons.add),
                label: const Text('Agregar más productos'),
              ),
              const EncabezadoSeccion('Entrega'),
              ChipsSeleccion<TipoEntrega>(
                opciones: TipoEntrega.values,
                elegido: tipo,
                etiqueta: (t) => t.etiqueta,
                icono: (t) => t.icono,
                onElegir: (t) =>
                    _cambiar(() => _pedido = _pedido.copyWith(tipoEntrega: t)),
              ),
              const SizedBox(height: 16),
              _Campo(
                _cliente,
                'Cliente (opcional)',
                onChanged: () => _cambios = true,
              ),
              if (tipo != TipoEntrega.local)
                _Campo(
                  _telefono,
                  'Teléfono',
                  teclado: TextInputType.phone,
                  onChanged: () => _cambios = true,
                ),
              if (tipo == TipoEntrega.domicilio)
                _Campo(
                  _direccion,
                  'Dirección (obligatoria)',
                  ayuda: 'Xochitepec, envío gratis',
                  onChanged: () => _cambios = true,
                ),
              _Campo(
                _notas,
                'Notas del pedido',
                onChanged: () => _cambios = true,
              ),
              const SizedBox(height: 8),
              FilaMonto('Total', formatearCentavos(_total), fuerte: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilaProducto extends StatelessWidget {
  const _FilaProducto({required this.producto, required this.onTap});

  final ProductoMenu producto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    final precio = p.precio == null
        ? 'desde ${formatearCentavos(p.precioDesde)}'
        : formatearCentavos(p.precioDesde);
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Menu.nombreCompleto(p), style: context.textos.titleMedium),
                if (p.descripcion.isNotEmpty)
                  Text(
                    p.descripcion,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textos.bodySmall?.copyWith(
                      color: context.colores.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            precio,
            style: context.textos.titleMedium?.copyWith(
              color: context.colores.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaRenglon extends StatelessWidget {
  const _FilaRenglon({
    required this.renglon,
    required this.onTap,
    required this.onMenos,
    required this.onMas,
  });

  final Renglon renglon;
  final VoidCallback onTap;
  final VoidCallback onMenos;
  final VoidCallback onMas;

  @override
  Widget build(BuildContext context) {
    final r = renglon;
    final detalle = [
      ?r.sabor,
      ?r.componentes,
      if (r.notas.isNotEmpty) r.notas,
    ].join(' · ');
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.titulo, style: context.textos.titleSmall),
                if (detalle.isNotEmpty)
                  Text(
                    detalle,
                    style: context.textos.bodySmall?.copyWith(
                      color: context.colores.onSurfaceVariant,
                    ),
                  ),
                Text(
                  formatearCentavos(r.subtotal),
                  style: context.textos.bodyMedium,
                ),
              ],
            ),
          ),
          SelectorCantidad(
            texto: '${r.cantidad}',
            anchoCantidad: 36,
            iconoMenos: r.cantidad == 1 ? Icons.delete_outline : Icons.remove,
            onMenos: onMenos,
            onMas: onMas,
          ),
        ],
      ),
    );
  }
}

class _Campo extends StatelessWidget {
  const _Campo(
    this.control,
    this.etiqueta, {
    this.teclado,
    this.ayuda,
    required this.onChanged,
  });

  final TextEditingController control;
  final String etiqueta;
  final TextInputType? teclado;
  final String? ayuda;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: control,
      keyboardType: teclado,
      textCapitalization: TextCapitalization.sentences,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(labelText: etiqueta, helperText: ayuda),
    ),
  );
}
