import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/errores.dart';
import '../../datos/formato.dart';
import '../../datos/inventario/insumo.dart';
import '../../estado/proveedores.dart';
import '../comun/componentes.dart';
import '../comun/confirmar.dart';
import '../tema.dart';

class PantallaInventario extends ConsumerStatefulWidget {
  const PantallaInventario({super.key});

  @override
  ConsumerState<PantallaInventario> createState() => _PantallaInventarioState();
}

class _PantallaInventarioState extends ConsumerState<PantallaInventario> {
  /// null = "Todos".
  CategoriaInsumo? _seccion;

  Future<void> _ajustar(Insumo i, int direccion) async {
    final delta = await _dialogoAjuste(context, i, direccion);
    if (delta == null || delta == 0) return;
    await ref.ejecutar(
      () => ref.read(inventarioRepoProvider).ajustar(i, delta),
    );
    ref.read(inventarioProvider.notifier).refrescar();
  }

  Future<void> _editar([Insumo? i]) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoInsumo(insumo: i),
    );
    if (guardado == true) ref.read(inventarioProvider.notifier).refrescar();
  }

  @override
  Widget build(BuildContext context) {
    final insumos = ref.watch(inventarioProvider).valor;
    final opciones = <CategoriaInsumo?>[null, ...CategoriaInsumo.values];
    final List<Widget> filas;
    if (insumos == null) {
      filas = [const Cargando()];
    } else {
      final grupos = <Widget>[];
      for (final c in CategoriaInsumo.values) {
        if (_seccion != null && _seccion != c) continue;
        final deC = insumos.where((i) => i.categoria == c).toList();
        if (deC.isEmpty) continue;
        if (_seccion == null) {
          grupos.add(EncabezadoSeccion('${c.etiqueta} · ${deC.length}'));
        }
        for (final i in deC) {
          grupos.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FilaInsumo(
                insumo: i,
                onTap: () => _editar(i),
                onMenos: () => _ajustar(i, -1),
                onMas: () => _ajustar(i, 1),
              ),
            ),
          );
        }
      }
      filas = grupos.isEmpty
          ? [
              const Mensaje(
                'No hay insumos en esta sección.',
                icono: Icons.inventory_2_outlined,
              ),
            ]
          : grupos;
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar insumo'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Centrado(
            child: ChipsSeleccion<CategoriaInsumo?>(
              desplazable: true,
              opciones: opciones,
              elegido: _seccion,
              etiqueta: (c) => c?.etiqueta ?? 'Todos',
              onElegir: (c) => setState(() => _seccion = c),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(inventarioProvider.notifier).refrescar(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                children: [for (final f in filas) Centrado(child: f)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaInsumo extends StatelessWidget {
  const _FilaInsumo({
    required this.insumo,
    required this.onTap,
    required this.onMenos,
    required this.onMas,
  });

  final Insumo insumo;
  final VoidCallback onTap;
  final VoidCallback onMenos;
  final VoidCallback onMas;

  @override
  Widget build(BuildContext context) {
    final i = insumo;
    return Panel(
      franja: i.bajoStock ? context.alerta : null,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textos.titleSmall,
                ),
                if (i.costoUnitario > 0)
                  Text(
                    '${formatearCentavos(aCentavos(i.costoUnitario))} / ${i.unidad.abreviatura}',
                    style: context.textos.bodySmall?.copyWith(
                      color: context.colores.onSurfaceVariant,
                    ),
                  ),
                if (i.bajoStock)
                  Text(
                    'Por agotarse',
                    style: context.textos.bodySmall?.copyWith(
                      color: context.alerta,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          SelectorCantidad(
            texto: formatearCantidad(i.cantidad, i.unidad),
            onMenos: i.cantidad > 0 ? onMenos : null,
            onMas: onMas,
          ),
        ],
      ),
    );
  }
}

/// "Hay ahora X", stepper con el delta y "Quedarán Y". No deja quedar en negativo.
Future<double?> _dialogoAjuste(BuildContext context, Insumo i, int direccion) =>
    showDialog<double>(
      context: context,
      builder: (context) {
        var delta = i.unidad.paso * direccion;
        return StatefulBuilder(
          builder: (context, setState) {
            final quedan = i.cantidad + delta;
            final signo = delta > 0 ? '+' : '';
            return AlertDialog(
              title: Text(i.nombre),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Hay ahora ${formatearCantidad(i.cantidad, i.unidad)}'),
                  const SizedBox(height: 16),
                  SelectorCantidad(
                    texto: '$signo${formatearCantidad(delta, i.unidad)}',
                    anchoCantidad: 100,
                    onMenos: i.cantidad + delta - i.unidad.paso < 0
                        ? null
                        : () => setState(() => delta -= i.unidad.paso),
                    onMas: () => setState(() => delta += i.unidad.paso),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Quedarán ${formatearCantidad(quedan, i.unidad)}',
                    style: context.textos.titleMedium,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: delta == 0 || quedan < 0
                      ? null
                      : () => Navigator.pop(context, delta),
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

/// Agregar o editar un insumo. Devuelve true si se guardó o se eliminó.
class _DialogoInsumo extends ConsumerStatefulWidget {
  const _DialogoInsumo({this.insumo});

  final Insumo? insumo;

  @override
  ConsumerState<_DialogoInsumo> createState() => _DialogoInsumoState();
}

class _DialogoInsumoState extends ConsumerState<_DialogoInsumo> {
  late FormularioInsumo _form = widget.insumo == null
      ? const FormularioInsumo()
      : FormularioInsumo.desde(widget.insumo!);
  late final _nombre = TextEditingController(text: _form.nombre);
  late final _cantidad = TextEditingController(text: _form.cantidad);
  late final _minimo = TextEditingController(text: _form.stockMinimo);
  late final _costo = TextEditingController(text: _form.costoUnitario);
  String? _error;
  bool _guardando = false;

  bool get _nuevo => widget.insumo == null;

  @override
  void dispose() {
    for (final c in [_nombre, _cantidad, _minimo, _costo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    final form = _form.copyWith(
      nombre: _nombre.text,
      cantidad: _cantidad.text,
      stockMinimo: _minimo.text,
      costoUnitario: _costo.text,
    );
    final Insumo insumo;
    try {
      insumo = form.validar();
    } on ErrorValidacion catch (e) {
      setState(() => _error = e.mensaje);
      return;
    }
    final ok = await confirmar(
      context,
      titulo: _nuevo ? '¿Agregar ${insumo.nombre}?' : '¿Guardar cambios?',
      mensaje:
          '${insumo.categoria.etiqueta} · ${formatearCantidad(insumo.cantidad, insumo.unidad)}',
      confirmar: _nuevo ? 'Agregar' : 'Guardar',
    );
    if (!ok || !mounted) return;
    setState(() => _guardando = true);
    final listo = await ref.ejecutar(
      () => ref.read(inventarioRepoProvider).guardar(insumo),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (listo) Navigator.pop(context, true);
  }

  Future<void> _eliminar() async {
    final i = widget.insumo!;
    final ok = await confirmar(
      context,
      titulo: '¿Eliminar ${i.nombre}?',
      mensaje:
          'Dejará de aparecer en el inventario y en el pronóstico de compras.',
      confirmar: 'Eliminar',
      peligro: true,
    );
    if (!ok || !mounted) return;
    final listo = await ref.ejecutar(
      () => ref.read(inventarioRepoProvider).eliminar(i),
    );
    if (listo && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final numero = const TextInputType.numberWithOptions(decimal: true);
    return AlertDialog(
      title: Text(_nuevo ? 'Agregar insumo' : 'Editar insumo'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nombre,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const EncabezadoSeccion(
                'Tipo',
                padding: EdgeInsets.fromLTRB(0, 16, 0, 8),
              ),
              ChipsSeleccion<CategoriaInsumo>(
                opciones: CategoriaInsumo.values,
                elegido: _form.categoria,
                etiqueta: (c) => c.etiqueta,
                // El tipo sugiere la unidad.
                onElegir: (c) => setState(
                  () => _form = _form.copyWith(
                    categoria: c,
                    unidad: c.unidadSugerida,
                  ),
                ),
              ),
              const EncabezadoSeccion(
                'Unidad',
                padding: EdgeInsets.fromLTRB(0, 16, 0, 8),
              ),
              ChipsSeleccion<Unidad>(
                opciones: Unidad.values,
                elegido: _form.unidad,
                etiqueta: (u) => u.etiqueta,
                onElegir: (u) =>
                    setState(() => _form = _form.copyWith(unidad: u)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _cantidad,
                keyboardType: numero,
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  suffixText: _form.unidad.abreviatura,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _minimo,
                keyboardType: numero,
                decoration: InputDecoration(
                  labelText: 'Avisar en el mínimo',
                  helperText: 'Vacío = sin aviso',
                  suffixText: _form.unidad.abreviatura,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _costo,
                keyboardType: numero,
                decoration: InputDecoration(
                  labelText: 'Costo por ${_form.unidad.abreviatura}',
                  prefixText: r'$',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: context.alerta)),
                ),
              if (!_nuevo) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: context.alerta),
                  onPressed: _eliminar,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar insumo'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(_nuevo ? 'Agregar' : 'Guardar'),
        ),
      ],
    );
  }
}
