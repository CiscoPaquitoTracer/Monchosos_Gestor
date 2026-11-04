import 'package:flutter/material.dart';

import '../../datos/errores.dart';
import '../../datos/formato.dart';
import '../../datos/menu/armar_renglon.dart';
import '../../datos/menu/menu.dart';
import '../../datos/pedidos/pedido.dart';
import '../comun/componentes.dart';
import '../tema.dart';

/// Elegir tamaño, sabor y, en combos, cada lugar ("Hamburguesa 1 de 2"), más la cantidad y
/// las notas. Devuelve el renglón armado o null si se canceló.
Future<Renglon?> configurarProducto(
  BuildContext context,
  ProductoMenu producto,
) => showDialog<Renglon>(
  context: context,
  builder: (_) => _ConfigurarProducto(producto: producto),
);

class _ConfigurarProducto extends StatefulWidget {
  const _ConfigurarProducto({required this.producto});

  final ProductoMenu producto;

  @override
  State<_ConfigurarProducto> createState() => _ConfigurarProductoState();
}

class _ConfigurarProductoState extends State<_ConfigurarProducto> {
  late final List<GrupoCombo> _lugares = lugaresDe(widget.producto);
  late final List<Eleccion?> _elecciones;
  String? _varianteId;
  String? _sabor;
  int _cantidad = 1;
  final _notas = TextEditingController();
  String? _error;

  ProductoMenu get _p => widget.producto;

  @override
  void initState() {
    super.initState();
    final activas = _p.variantesActivas;
    if (activas.length == 1) _varianteId = activas.single.id;
    // Un lugar con una sola opción disponible ya queda elegido.
    _elecciones = [
      for (final g in _lugares)
        switch (g.opciones.where(Menu.opcionDisponible).toList()) {
          [final unica] => Eleccion(unica),
          _ => null,
        },
    ];
  }

  @override
  void dispose() {
    _notas.dispose();
    super.dispose();
  }

  int get _precio =>
      (_p.variante(_varianteId)?.precio ?? _p.precio ?? _p.precioDesde) *
      _cantidad;

  void _agregar() {
    try {
      final r = armarRenglon(
        _p,
        varianteId: _varianteId,
        sabor: _sabor,
        elecciones: _elecciones,
        cantidad: _cantidad,
        notas: _notas.text,
      );
      Navigator.pop(context, r);
    } on ErrorValidacion catch (e) {
      setState(() => _error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contenido = <Widget>[
      if (_p.descripcion.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _p.descripcion,
            style: TextStyle(color: context.colores.onSurfaceVariant),
          ),
        ),
      if (_p.variantes.isNotEmpty) ...[
        const EncabezadoSeccion(
          'Tamaño',
          padding: EdgeInsets.fromLTRB(0, 12, 0, 8),
        ),
        ChipsSeleccion<Variante>(
          opciones: _p.variantesActivas,
          elegido: _p.variante(_varianteId),
          etiqueta: (v) => '${v.nombre} · ${formatearCentavos(v.precio)}',
          onElegir: (v) => setState(() => _varianteId = v.id),
        ),
      ],
      if (_p.conSabor) ...[
        const EncabezadoSeccion(
          'Sabor',
          padding: EdgeInsets.fromLTRB(0, 12, 0, 8),
        ),
        _Sabores(elegido: _sabor, onElegir: (s) => setState(() => _sabor = s)),
      ],
      for (var i = 0; i < _lugares.length; i++) ..._lugar(i),
      const EncabezadoSeccion(
        'Cantidad',
        padding: EdgeInsets.fromLTRB(0, 12, 0, 8),
      ),
      SelectorCantidad(
        texto: '$_cantidad',
        anchoCantidad: 56,
        onMenos: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
        onMas: () => setState(() => _cantidad++),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _notas,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Notas',
          hintText: 'sin cebolla',
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: TextStyle(color: context.alerta)),
        ),
    ];

    return AlertDialog(
      title: Text(Menu.nombreCompleto(_p)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: contenido,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _agregar,
          child: Text('Agregar ${formatearCentavos(_precio)}'),
        ),
      ],
    );
  }

  /// "Hamburguesa 1 de 2" con sus opciones disponibles y, si lleva, el sabor.
  List<Widget> _lugar(int i) {
    final grupo = _lugares[i];
    final numero = _lugares
        .take(i + 1)
        .where((g) => identical(g, grupo))
        .length;
    final titulo = grupo.cantidad > 1
        ? '${grupo.nombre} $numero de ${grupo.cantidad}'
        : grupo.nombre;
    final eleccion = _elecciones[i];
    final opciones = grupo.opciones.where(Menu.opcionDisponible).toList();
    final llevaSabor =
        eleccion != null && Menu.producto(eleccion.opcion.productoId).conSabor;
    return [
      EncabezadoSeccion(
        titulo,
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
      ),
      if (opciones.isEmpty)
        Text(
          'No hay opciones disponibles.',
          style: TextStyle(color: context.alerta),
        )
      else
        ChipsSeleccion<OpcionCombo>(
          opciones: opciones,
          elegido: eleccion?.opcion,
          etiqueta: Menu.nombreOpcion,
          onElegir: (o) => setState(() => _elecciones[i] = Eleccion(o)),
        ),
      if (llevaSabor) ...[
        const SizedBox(height: 8),
        _Sabores(
          elegido: eleccion.sabor,
          onElegir: (s) =>
              setState(() => _elecciones[i] = eleccion.conSabor(s)),
        ),
      ],
    ];
  }
}

class _Sabores extends StatelessWidget {
  const _Sabores({required this.elegido, required this.onElegir});

  final String? elegido;
  final ValueChanged<String> onElegir;

  @override
  Widget build(BuildContext context) => ChipsSeleccion<String>(
    opciones: Menu.sabores,
    elegido: elegido,
    etiqueta: (s) => s,
    onElegir: onElegir,
  );
}

/// Editar las notas de un renglón ya agregado.
Future<String?> editarNotas(BuildContext context, Renglon r) async {
  // No se hace dispose aquí: el diálogo todavía lo usa durante la animación de cierre.
  final control = TextEditingController(text: r.notas);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(r.titulo),
      content: TextField(
        controller: control,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Notas',
          hintText: 'sin cebolla',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, control.text.trim()),
          child: const Text('Listo'),
        ),
      ],
    ),
  );
}
