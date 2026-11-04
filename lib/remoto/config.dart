/// Configuración de la app. Se compila desde `env.json` (ignorado por git):
///
///     flutter run --dart-define-from-file=env.json
///
/// `env.example.json` muestra los campos. En Jenkins, `env.json` se genera desde las credenciales.
abstract final class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Llave pública (`sb_publishable_…`): la seguridad real la da RLS en la base de datos.
  static const supabaseLlave = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Cliente OAuth de tipo "Aplicación web": es el que pide el login aunque la app sea móvil.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// Cliente OAuth de iOS (bundle com.monchosos.app). Vacío mientras no exista.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  static bool get completa =>
      supabaseUrl.isNotEmpty &&
      supabaseLlave.isNotEmpty &&
      googleWebClientId.isNotEmpty;

  static const mensajeFalta =
      'Falta configurar GOOGLE_WEB_CLIENT_ID, SUPABASE_URL o SUPABASE_PUBLISHABLE_KEY '
      '(compila con --dart-define-from-file=env.json).';
}
