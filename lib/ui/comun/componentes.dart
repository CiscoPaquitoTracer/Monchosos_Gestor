import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../estado/proveedores.dart';
import '../tema.dart';

/// Ancho máximo del contenido: en tableta no se estira a toda la pantalla.
const double anchoMaximo = 760;

/// Desde este ancho (iPad horizontal, Chromebook) la navegación va en una barra lateral.
const double anchoBarraLateral = 840;

/// Centra el contenido y limita su ancho (teléfono y tableta).
class Centrado extends StatelessWidget {
  const Centrado({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: anchoMaximo),
      child: child,
    ),
  );
}

/// Panel blanco con borde de 1 px. Con [franja], una línea de 4 dp a la izquierda marca
/// el estado (rojo = por cobrar o por agotarse, mostaza = conviene comprar).
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.franja,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.atenuado = false,
  });

  final Widget child;
  final Color? franja;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool atenuado;

  @override
  Widget build(BuildContext context) {
    Widget contenido = Padding(padding: padding, child: child);
    if (franja != null) {
      contenido = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: franja),
            Expanded(child: contenido),
          ],
        ),
      );
    }
    return Opacity(
      opacity: atenuado ? 0.55 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? contenido
            : InkWell(onTap: onTap, child: contenido),
      ),
    );
  }
}

/// Fondo café con texto blanco, para la cifra principal de Inicio y Resumen.
class PanelDestacado extends StatelessWidget {
  const PanelDestacado({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fondo = context.oscuro ? const Color(0xFF3D1205) : Colores.cafe;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colores.blanco),
        child: IconTheme.merge(
          data: const IconThemeData(color: Colores.blanco),
          child: child,
        ),
      ),
    );
  }
}

/// Etiqueta pequeña arriba y la cifra en titleLarge.
class Dato extends StatelessWidget {
  const Dato(this.etiqueta, this.valor, {super.key, this.color});

  final String etiqueta;
  final String valor;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        etiqueta,
        style: context.textos.bodySmall?.copyWith(
          color: context.colores.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 2),
      Text(valor, style: context.textos.titleLarge?.copyWith(color: color)),
    ],
  );
}

/// "HOY", "INVENTARIO", "CARNES · 7": pequeño, en mayúsculas y con espaciado.
class EncabezadoSeccion extends StatelessWidget {
  const EncabezadoSeccion(
    this.texto, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 8),
  });

  final String texto;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(
      texto.toUpperCase(),
      style: context.textos.labelMedium?.copyWith(
        color: context.colores.onSurfaceVariant,
      ),
    ),
  );
}

/// Fila "etiqueta ........ monto".
class FilaMonto extends StatelessWidget {
  const FilaMonto(
    this.etiqueta,
    this.monto, {
    super.key,
    this.color,
    this.fuerte = false,
    this.icono,
  });

  final String etiqueta;
  final String monto;
  final Color? color;
  final bool fuerte;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final estilo =
        (fuerte ? context.textos.titleMedium : context.textos.bodyMedium)
            ?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (icono != null) ...[
            Icon(icono, size: 18, color: color),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(etiqueta, style: estilo)),
          Text(monto, style: estilo),
        ],
      ),
    );
  }
}

/// Botones − / + con la cantidad en medio, de ancho fijo (76 dp) para que queden alineados
/// en todas las filas.
class SelectorCantidad extends StatelessWidget {
  const SelectorCantidad({
    super.key,
    required this.texto,
    required this.onMenos,
    required this.onMas,
    this.iconoMenos = Icons.remove,
    this.anchoCantidad = 76,
  });

  final String texto;
  final VoidCallback? onMenos;
  final VoidCallback? onMas;
  final IconData iconoMenos;
  final double anchoCantidad;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.filledTonal(
        onPressed: onMenos,
        icon: Icon(iconoMenos),
        tooltip: 'Menos',
      ),
      SizedBox(
        width: anchoCantidad,
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: context.textos.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      IconButton.filledTonal(
        onPressed: onMas,
        icon: const Icon(Icons.add),
        tooltip: 'Más',
      ),
    ],
  );
}

/// Texto centrado para "cargando" o listas vacías.
class Mensaje extends StatelessWidget {
  const Mensaje(this.texto, {super.key, this.icono});

  final String texto;
  final IconData? icono;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icono != null)
          Icon(icono, size: 40, color: context.colores.onSurfaceVariant),
        if (icono != null) const SizedBox(height: 12),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colores.onSurfaceVariant),
        ),
      ],
    ),
  );
}

class Cargando extends StatelessWidget {
  const Cargando({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(48),
    child: Center(child: CircularProgressIndicator()),
  );
}

/// Franja roja arriba de la pantalla con "Reintentar" y "OK" (§2.8).
class FranjaError extends ConsumerWidget {
  const FranjaError({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aviso = ref.watch(avisoErrorProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: aviso == null
          ? const SizedBox(width: double.infinity)
          : Material(
              color: context.colores.error,
              child: SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: context.colores.onError),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          aviso.mensaje,
                          style: TextStyle(color: context.colores.onError),
                        ),
                      ),
                      if (aviso.reintentar != null)
                        TextButton(
                          onPressed: () {
                            ref.read(avisoErrorProvider.notifier).cerrar();
                            aviso.reintentar!();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: context.colores.onError,
                          ),
                          child: const Text('Reintentar'),
                        ),
                      TextButton(
                        onPressed: () =>
                            ref.read(avisoErrorProvider.notifier).cerrar(),
                        style: TextButton.styleFrom(
                          foregroundColor: context.colores.onError,
                        ),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Pone la [FranjaError] encima del contenido de una pantalla.
class ConFranjaError extends StatelessWidget {
  const ConFranjaError({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const FranjaError(),
      Expanded(child: child),
    ],
  );
}

/// Chips de selección única con ícono opcional.
class ChipsSeleccion<T> extends StatelessWidget {
  const ChipsSeleccion({
    super.key,
    required this.opciones,
    required this.elegido,
    required this.etiqueta,
    required this.onElegir,
    this.icono,
    this.desplazable = false,
  });

  final List<T> opciones;
  final T? elegido;
  final String Function(T) etiqueta;
  final IconData Function(T)? icono;
  final ValueChanged<T> onElegir;

  /// true = una sola fila que se desliza (filtros); false = varias filas.
  final bool desplazable;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final o in opciones)
        ChoiceChip(
          label: Text(etiqueta(o)),
          avatar: icono == null ? null : Icon(icono!(o), size: 18),
          selected: o == elegido,
          onSelected: (_) => onElegir(o),
        ),
    ];
    if (!desplazable) return Wrap(spacing: 8, runSpacing: 8, children: chips);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final c in chips)
            Padding(padding: const EdgeInsets.only(right: 8), child: c),
        ],
      ),
    );
  }
}
