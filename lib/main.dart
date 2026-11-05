import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'avisos/aviso_reabasto.dart';
import 'datos/formato.dart';
import 'estado/proveedores.dart';
import 'remoto/config.dart';
import 'ui/comun/componentes.dart';
import 'ui/login/login.dart';
import 'ui/principal.dart';
import 'ui/tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(localeMx);
  if (Config.completa) {
    // Guarda y renueva la sesión sola (se recuerda entre aperturas).
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabaseLlave,
    );
    try {
      await AvisoReabasto.programar();
    } catch (_) {
      // Si no se puede programar, la app sigue funcionando sin el aviso.
    }
  }
  runApp(
    // Sin reintentos automáticos: los errores se muestran en la franja con "Reintentar".
    ProviderScope(retry: (_, _) => null, child: const MonchososApp()),
  );
}

class MonchososApp extends StatelessWidget {
  const MonchososApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Monchosos',
    debugShowCheckedModeBanner: false,
    theme: temaMonchosos(Brightness.light),
    darkTheme: temaMonchosos(Brightness.dark),
    locale: const Locale('es', 'MX'),
    supportedLocales: const [Locale('es', 'MX')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Config.completa ? const _SegunSesion() : const _SinConfiguracion(),
  );
}

/// Cargando → Login → App principal, según la sesión.
class _SegunSesion extends ConsumerWidget {
  const _SegunSesion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);
    return switch (sesion) {
      AsyncData(value: final u?) => switch (ref.watch(
        accesoProvider(u.correo),
      )) {
        // Sin acceso: ya cerró la sesión; en un momento la sesión cambia y aparece el login.
        AsyncData(value: true) => AppPrincipal(usuario: u),
        _ => const Scaffold(body: Cargando()),
      },
      AsyncData() || AsyncError() => const PantallaLogin(),
      _ => const Scaffold(body: Cargando()),
    };
  }
}

class _SinConfiguracion extends StatelessWidget {
  const _SinConfiguracion();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Mensaje(Config.mensajeFalta, icono: Icons.error_outline),
    ),
  );
}
