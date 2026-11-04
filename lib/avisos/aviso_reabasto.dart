import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../datos/formato.dart';
import '../datos/pronostico/pronostico.dart';
import '../remoto/config.dart';
import '../remoto/repositorios.dart';

/// Una vez al día (10:00) revisa si se acerca un fin de semana o festivo y, si se suele vender
/// más o no alcanzan los insumos, manda una notificación con lo que conviene comprar.
///
/// Solo Android (workmanager). En iOS no hay tareas periódicas a hora fija: la estrategia
/// (BGAppRefreshTask o aviso desde el servidor) está pendiente de decidir (§9).
abstract final class AvisoReabasto {
  static const _trabajo = 'aviso-reabasto';
  static const _ultimoAviso = 'ultimo_aviso_reabasto';
  static const _hora = 10; // antes de ir a comprar
  static const _canal = 'reabasto';
  static const _idNotificacion = 1001;

  static final _notificaciones = FlutterLocalNotificationsPlugin();

  /// Programa la revisión diaria. KEEP: no se reinicia el reloj cada vez que abre la app.
  static Future<void> programar() async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(despacharAvisoReabasto);
    await Workmanager().registerPeriodicTask(
      _trabajo,
      _trabajo,
      frequency: const Duration(days: 1),
      initialDelay: _hastaLaProxima(_hora),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// Pide el permiso de notificaciones (Android 13+), una vez al entrar.
  static Future<void> pedirPermiso() async {
    if (!Platform.isAndroid) return;
    await _inicializarNotificaciones();
    await _notificaciones
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  static Duration _hastaLaProxima(int hora) {
    final ahora = DateTime.now();
    var siguiente = DateTime(ahora.year, ahora.month, ahora.day, hora);
    if (!siguiente.isAfter(ahora)) {
      siguiente = siguiente.add(const Duration(days: 1));
    }
    return siguiente.difference(ahora);
  }

  static Future<void> _inicializarNotificaciones() =>
      _notificaciones.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notificacion'),
        ),
      );

  /// La tarea en segundo plano. true = terminó; false = reintentar más tarde.
  static Future<bool> revisar() async {
    if (!Config.completa) return true;
    await initializeDateFormatting(localeMx);
    try {
      await Supabase.initialize(
        url: Config.supabaseUrl,
        publishableKey: Config.supabaseLlave,
      );
    } catch (_) {
      // Ya estaba inicializado en este proceso.
    }
    final db = Supabase.instance.client;
    // Sin sesión de Google no hay datos que consultar (RLS); se intenta mañana.
    if (db.auth.currentSession == null) return true;

    final Pronostico pronostico;
    try {
      pronostico = await PronosticoRepositorio(db).consultar();
    } catch (_) {
      return false;
    }
    final evento = pronostico.evento;
    if (evento == null) return true;
    final mensaje = mensajeDeAviso(evento, pronostico.porComprar);
    if (mensaje == null) return true;

    // Un aviso por evento; se repite solo si cambia la lista de faltantes.
    final clave = '${evento.hasta}:${pronostico.porComprar.length}';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_ultimoAviso) == clave) return true;

    await _inicializarNotificaciones();
    final (titulo, cuerpo) = mensaje;
    await _notificaciones.show(
      id: _idNotificacion,
      title: titulo,
      body: cuerpo,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _canal,
          'Reabasto de insumos',
          channelDescription: 'Avisos antes de fines de semana y festivos',
          styleInformation: BigTextStyleInformation(cuerpo),
          autoCancel: true,
        ),
      ),
    );
    await prefs.setString(_ultimoAviso, clave);
    return true;
  }
}

/// Punto de entrada de workmanager (corre en otro isolate).
@pragma('vm:entry-point')
void despacharAvisoReabasto() {
  Workmanager().executeTask((tarea, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    return AvisoReabasto.revisar();
  });
}
