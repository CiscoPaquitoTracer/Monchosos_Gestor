import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'mensaje_error.dart';

/// El usuario con sesión, tal como lo muestra la app.
class Usuario {
  const Usuario({required this.nombre, required this.correo});

  factory Usuario.desde(User u) {
    final meta = u.userMetadata ?? const {};
    final correo = u.email ?? '';
    final nombre = (meta['full_name'] ?? meta['name']) as String?;
    return Usuario(
      nombre: (nombre == null || nombre.isEmpty) ? correo : nombre,
      correo: correo,
    );
  }

  final String nombre;
  final String correo;

  String get inicial => nombre.isEmpty
      ? '?'
      : String.fromCharCode(nombre.runes.first).toUpperCase();
}

/// Resultado de "Iniciar sesión con Google": null = éxito o cancelado; texto = error.
typedef ResultadoLogin = String?;

/// Botón "Iniciar sesión con Google" → Supabase Auth.
///
/// Google entrega un ID token; Supabase lo verifica en el servidor y abre la sesión.
/// El acceso real lo decide la tabla usuarios_permitidos (RLS).
///
/// Nonce (solo Android): Google firma el SHA-256 del nonce dentro del token y Supabase
/// comprueba que corresponde al valor original, así un token interceptado no sirve.
/// `google_sign_in` 7 se inicializa una sola vez, por eso el nonce es uno por apertura
/// de la app. En iOS el SDK de Google maneja el nonce por su cuenta y no se manda.
class Autenticacion {
  Autenticacion(this._db);

  final SupabaseClient _db;
  Future<void>? _inicializado;
  String? _nonce;

  static final Random _aleatorio = Random.secure();

  Future<void> _inicializar() => _inicializado ??= () async {
    final android = Platform.isAndroid;
    _nonce = android ? _nonceAleatorio() : null;
    await GoogleSignIn.instance.initialize(
      clientId: android || Config.googleIosClientId.isEmpty
          ? null
          : Config.googleIosClientId,
      serverClientId: Config.googleWebClientId,
      nonce: _nonce == null ? null : _sha256(_nonce!),
    );
  }();

  Future<ResultadoLogin> iniciarSesion() async {
    if (!Config.completa) return Config.mensajeFalta;
    final String idToken;
    try {
      await _inicializar();
      final cuenta = await GoogleSignIn.instance.authenticate();
      final token = cuenta.authentication.idToken;
      if (token == null) return 'Google no regresó el token de la cuenta.';
      idToken = token;
    } on GoogleSignInException catch (e) {
      return switch (e.code) {
        GoogleSignInExceptionCode.canceled => null,
        GoogleSignInExceptionCode.interrupted => null,
        GoogleSignInExceptionCode.clientConfigurationError =>
          'La configuración de Google no es válida para esta versión de la app '
              '(revisa el SHA-1 en Google Cloud).',
        _ => 'No se pudo iniciar sesión: ${e.description ?? e.code.name}',
      };
    } catch (e) {
      return mensajeDeError(e);
    }

    try {
      await _db.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        nonce: _nonce,
      );
      // RLS solo deja ver tu propio renglón: si no hay, la cuenta no está autorizada.
      final filas = await _db.from('usuarios_permitidos').select('correo');
      if (filas.isNotEmpty) return null;
      final correo = _db.auth.currentUser?.email ?? '';
      await cerrarSesion();
      return 'La cuenta $correo no tiene acceso. Pide que la agreguen en Supabase '
          '(usuarios_permitidos).';
    } catch (e) {
      await cerrarSesion();
      return mensajeDeError(e);
    }
  }

  Future<void> cerrarSesion() async {
    try {
      await _db.auth.signOut();
    } catch (_) {}
    try {
      await _inicializar();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  static String _nonceAleatorio() => List.generate(
    32,
    (_) => _aleatorio.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  static String _sha256(String texto) =>
      sha256.convert(utf8.encode(texto)).toString();
}
