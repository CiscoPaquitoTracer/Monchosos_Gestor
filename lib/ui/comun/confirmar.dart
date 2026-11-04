import 'package:flutter/material.dart';

/// Diálogo de confirmación (§2.7): toda acción que cambia datos lo usa.
/// [peligro] = el botón de confirmar va en rojo (cancelar, eliminar, quitar pago).
/// Devuelve true si el usuario confirmó.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String confirmar = 'Confirmar',
  String cancelar = 'Cancelar',
  bool peligro = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colores = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(titulo),
        content: Text(
          mensaje,
          style: peligro ? TextStyle(color: colores.error) : null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelar),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: peligro
                ? FilledButton.styleFrom(
                    backgroundColor: colores.error,
                    foregroundColor: colores.onError,
                  )
                : null,
            child: Text(confirmar),
          ),
        ],
      );
    },
  );
  return r ?? false;
}
