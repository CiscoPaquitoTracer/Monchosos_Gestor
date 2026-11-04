import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../datos/inventario/insumo.dart';
import '../datos/menu/menu.dart';
import '../datos/pedidos/pedido.dart';
import '../datos/pronostico/pronostico.dart';
import '../datos/resumen/resumen.dart';
import '../remoto/autenticacion.dart';
import '../remoto/mensaje_error.dart';
import '../remoto/repositorios.dart';

// ---------------------------------------------------------------- Dependencias

final supabaseProvider = Provider<SupabaseClient>(
  (_) => Supabase.instance.client,
);

final autenticacionProvider = Provider(
  (ref) => Autenticacion(ref.watch(supabaseProvider)),
);
final menuRepoProvider = Provider(
  (ref) => MenuRepositorio(ref.watch(supabaseProvider)),
);
final inventarioRepoProvider = Provider(
  (ref) => InventarioRepositorio(ref.watch(supabaseProvider)),
);
final pedidosRepoProvider = Provider(
  (ref) => PedidosRepositorio(ref.watch(supabaseProvider)),
);
final pronosticoRepoProvider = Provider(
  (ref) => PronosticoRepositorio(ref.watch(supabaseProvider)),
);
final resumenRepoProvider = Provider(
  (ref) => ResumenRepositorio(ref.watch(supabaseProvider)),
);

// ---------------------------------------------------------------- Sesión

/// null = sin sesión. La guarda y renueva Supabase Auth.
final sesionProvider = StreamProvider<Usuario?>((ref) async* {
  final auth = ref.watch(supabaseProvider).auth;
  final actual = auth.currentUser;
  yield actual == null ? null : Usuario.desde(actual);
  await for (final cambio in auth.onAuthStateChange) {
    final u = cambio.session?.user;
    yield u == null ? null : Usuario.desde(u);
  }
});

// ---------------------------------------------------------------- Avisos de error

/// La franja roja de arriba (§2.8). [reintentar] repite lo que falló.
class AvisoError {
  const AvisoError(this.mensaje, {this.reintentar, this.origen});

  final String mensaje;
  final Future<void> Function()? reintentar;

  /// Quién lo puso (para quitarlo cuando esa consulta vuelva a funcionar).
  final String? origen;
}

class AvisoErrorNotifier extends Notifier<AvisoError?> {
  @override
  AvisoError? build() => null;

  void mostrar(
    Object error, {
    Future<void> Function()? reintentar,
    String? origen,
  }) => state = AvisoError(
    mensajeDeError(error),
    reintentar: reintentar,
    origen: origen,
  );

  void cerrar() => state = null;

  void limpiar(String origen) {
    if (state?.origen == origen) state = null;
  }
}

final avisoErrorProvider = NotifierProvider<AvisoErrorNotifier, AvisoError?>(
  AvisoErrorNotifier.new,
);

/// Ejecuta una acción que cambia datos. Si falla, muestra el aviso con "Reintentar".
/// Devuelve true si salió bien.
extension EjecutarAccion on WidgetRef {
  Future<bool> ejecutar(Future<void> Function() accion) async {
    final aviso = read(avisoErrorProvider.notifier);
    try {
      await accion();
      aviso.cerrar();
      return true;
    } catch (e) {
      aviso.mostrar(e, reintentar: () => _reintentar(aviso, accion));
      return false;
    }
  }
}

Future<void> _reintentar(
  AvisoErrorNotifier aviso,
  Future<void> Function() accion,
) async {
  try {
    await accion();
    aviso.cerrar();
  } catch (e) {
    aviso.mostrar(e, reintentar: () => _reintentar(aviso, accion));
  }
}

// ---------------------------------------------------------------- Consultas periódicas

/// Lo que se ve en pantalla: el último valor bueno y, si la última consulta falló, el error.
class Datos<T> {
  const Datos({this.valor, this.error});

  final T? valor;
  final String? error;

  bool get cargando => valor == null && error == null;
}

/// Consulta al servidor al abrir y luego cada [cada], para ver lo que hace el otro teléfono.
abstract class Sondeo<T> extends Notifier<Datos<T>> {
  Duration get cada;
  String get origen;
  Future<T> consultar();

  @override
  Datos<T> build() {
    final reloj = Timer.periodic(cada, (_) => refrescar());
    ref.onDispose(reloj.cancel);
    Future.microtask(refrescar);
    return Datos<T>(valor: valorInicial);
  }

  /// Valor mientras llega la primera respuesta (null = "cargando").
  T? get valorInicial => null;

  Future<void> refrescar() async {
    try {
      final v = await consultar();
      if (!ref.mounted) return;
      state = Datos(valor: v);
      ref.read(avisoErrorProvider.notifier).limpiar(origen);
    } catch (e) {
      if (!ref.mounted) return;
      state = Datos(valor: state.valor, error: mensajeDeError(e));
      ref
          .read(avisoErrorProvider.notifier)
          .mostrar(e, reintentar: refrescar, origen: origen);
    }
  }
}

class PedidosNotifier extends Sondeo<ListaPedidos> {
  @override
  Duration get cada => const Duration(seconds: 20);

  @override
  String get origen => 'pedidos';

  @override
  Future<ListaPedidos> consultar() => ref.read(pedidosRepoProvider).consultar();
}

final pedidosProvider =
    NotifierProvider.autoDispose<PedidosNotifier, Datos<ListaPedidos>>(
      PedidosNotifier.new,
    );

class InventarioNotifier extends Sondeo<List<Insumo>> {
  @override
  Duration get cada => const Duration(seconds: 20);

  @override
  String get origen => 'inventario';

  @override
  Future<List<Insumo>> consultar() =>
      ref.read(inventarioRepoProvider).consultar();
}

final inventarioProvider =
    NotifierProvider.autoDispose<InventarioNotifier, Datos<List<Insumo>>>(
      InventarioNotifier.new,
    );

class PronosticoNotifier extends Sondeo<Pronostico> {
  @override
  Duration get cada => const Duration(minutes: 5);

  @override
  String get origen => 'pronostico';

  @override
  Future<Pronostico> consultar() =>
      ref.read(pronosticoRepoProvider).consultar();
}

final pronosticoProvider =
    NotifierProvider.autoDispose<PronosticoNotifier, Datos<Pronostico>>(
      PronosticoNotifier.new,
    );

/// Precios y disponibilidad: se refrescan en toda la app cada 2 min (los cambia el otro
/// teléfono). Mientras no cargan se usa el menú de respaldo.
class MenuNotifier extends Sondeo<List<ProductoMenu>> {
  @override
  Duration get cada => const Duration(minutes: 2);

  @override
  String get origen => 'menu';

  @override
  List<ProductoMenu> get valorInicial => Menu.productos;

  @override
  Future<List<ProductoMenu>> consultar() async {
    await ref.read(menuRepoProvider).refrescar();
    return Menu.productos;
  }
}

final menuProvider =
    NotifierProvider.autoDispose<MenuNotifier, Datos<List<ProductoMenu>>>(
      MenuNotifier.new,
    );

/// El detalle de un pedido; se invalida después de cada cambio.
final pedidoProvider = FutureProvider.autoDispose.family<PedidoCompleto?, int>(
  (ref, id) => ref.read(pedidosRepoProvider).obtener(id),
);

/// Resumen de un mes ((año, mes)).
final resumenProvider = FutureProvider.autoDispose.family<Resumen, (int, int)>(
  (ref, mes) => ref.read(resumenRepoProvider).delMes(DateTime(mes.$1, mes.$2)),
);
