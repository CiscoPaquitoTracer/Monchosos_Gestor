import 'dart:async';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../datos/errores.dart';

const mensajeSinRed =
    'Sin conexión a internet. Revisa el Wi-Fi o los datos e intenta de nuevo.';
const mensajeSinPermiso = 'Tu cuenta no tiene permiso para hacer esto.';

/// Mensaje entendible para mostrar en pantalla.
String mensajeDeError(Object e) {
  if (e is ErrorValidacion) return e.mensaje;
  // Sin red: http convierte los errores de socket en ClientException (también en web).
  // No se usa dart:io para que compile en la PWA.
  if (e is ClientException ||
      e is TimeoutException ||
      e.runtimeType.toString() == 'SocketException') {
    return mensajeSinRed;
  }
  if (e is AuthRetryableFetchException) return mensajeSinRed;
  if (e is PostgrestException) {
    // Los RAISE EXCEPTION de la base ya vienen en español ("Falta la dirección de entrega").
    final m = e.message;
    if (m.contains('permission denied') ||
        m.contains('row-level security') ||
        e.code == '42501') {
      return mensajeSinPermiso;
    }
    return m.isEmpty ? 'Error del servidor' : m;
  }
  if (e is AuthException) return e.message;
  if (e is StateError) return e.message;
  return 'Ocurrió un error inesperado.';
}
