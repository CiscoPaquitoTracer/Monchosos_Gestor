import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/formato.dart';
import '../../datos/menu/menu.dart';
import '../../estado/proveedores.dart';
import '../comun/componentes.dart';
import '../comun/confirmar.dart';
import '../tema.dart';

class PantallaMenu extends ConsumerStatefulWidget {
  const PantallaMenu({super.key});

  @override
  ConsumerState<PantallaMenu> createState() => _PantallaMenuState();
}

class _PantallaMenuState extends ConsumerState<PantallaMenu> {
  CategoriaMenu _categoria = CategoriaMenu.burgers;

  Future<void> _editar(ProductoMenu p, Variante? v) async {
    final nombre = [Menu.nombreCompleto(p), ?v?.nombre].join(' ');
    final antes = v?.precio ?? p.precio ?? 0;
    final activoAntes = v?.activo ?? p.activo;
    final res = await showDialog<(int, bool)>(
      context: context,
      builder: (_) =>
          _DialogoPrecio(nombre: nombre, precio: antes, activo: activoAntes),
    );
    if (res == null || !mounted) return;
    final (precio, activo) = res;
    if (precio == antes && activo == activoAntes) return;
    final detalle = [
      if (precio != antes)
        'Precio: ${formatearCentavos(antes)} → ${formatearCentavos(precio)}',
      if (activo != activoAntes)
        activo ? 'Vuelve a estar disponible' : 'Queda como no disponible',
    ].join('\n');
    final ok = await confirmar(
      context,
      titulo: '¿Guardar cambios en $nombre?',
      mensaje: detalle,
      confirmar: 'Guardar',
    );
    if (!ok) return;
    await ref.ejecutar(
      () => ref
          .read(menuRepoProvider)
          .guardar(p, v, centavos: precio, disponible: activo),
    );
    ref.read(menuProvider.notifier).refrescar();
  }

  @override
  Widget build(BuildContext context) {
    final productos = (ref.watch(menuProvider).valor ?? Menu.productos)
        .where((p) => p.categoria == _categoria)
        .toList();
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
          child: RefreshIndicator(
            onRefresh: () => ref.read(menuProvider.notifier).refrescar(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Centrado(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Toca un precio para cambiarlo. Los pedidos ya hechos conservan su precio.',
                      style: TextStyle(color: context.colores.onSurfaceVariant),
                    ),
                  ),
                ),
                for (final p in productos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Centrado(
                      child: Panel(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (p.variantes.isEmpty)
                              _FilaPrecio(
                                titulo: Menu.nombreCompleto(p),
                                precio: p.precio ?? 0,
                                activo: p.activo,
                                onTap: () => _editar(p, null),
                              )
                            else ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  0,
                                ),
                                child: Text(
                                  Menu.nombreCompleto(p),
                                  style: context.textos.titleMedium,
                                ),
                              ),
                              for (final v in p.variantes)
                                _FilaPrecio(
                                  titulo: v.nombre,
                                  precio: v.precio,
                                  activo: v.activo && p.activo,
                                  onTap: () => _editar(p, v),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FilaPrecio extends StatelessWidget {
  const _FilaPrecio({
    required this.titulo,
    required this.precio,
    required this.activo,
    required this.onTap,
  });

  final String titulo;
  final int precio;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: activo ? 1 : 0.5,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: context.textos.titleSmall),
                  if (!activo)
                    Text(
                      'No disponible',
                      style: context.textos.bodySmall?.copyWith(
                        color: context.colores.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              formatearCentavos(precio),
              style: context.textos.titleMedium?.copyWith(
                color: context.colores.primary,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.edit, size: 18, color: context.colores.onSurfaceVariant),
          ],
        ),
      ),
    ),
  );
}

class _DialogoPrecio extends StatefulWidget {
  const _DialogoPrecio({
    required this.nombre,
    required this.precio,
    required this.activo,
  });

  final String nombre;
  final int precio;
  final bool activo;

  @override
  State<_DialogoPrecio> createState() => _DialogoPrecioState();
}

class _DialogoPrecioState extends State<_DialogoPrecio> {
  late final _precio = TextEditingController(
    text: formatearCentavos(widget.precio)
        .replaceFirst(r'$', '')
        .replaceAll(',', ''),
  );
  late bool _activo = widget.activo;
  String? _error;

  @override
  void dispose() {
    _precio.dispose();
    super.dispose();
  }

  void _aceptar() {
    final c = parsearPesos(_precio.text);
    if (c == null || c <= 0) {
      setState(() => _error = 'Escribe un precio mayor a \$0.');
      return;
    }
    Navigator.pop(context, (c, _activo));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.nombre),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _precio,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Precio',
              prefixText: r'$',
              helperText: 'Antes: ${formatearCentavos(widget.precio)}',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Disponible'),
            subtitle: const Text(
              'Apágalo si se acabó: no aparecerá al tomar pedidos',
            ),
            value: _activo,
            onChanged: (v) => setState(() => _activo = v),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: context.alerta)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _aceptar, child: const Text('Guardar')),
    ],
  );
}
