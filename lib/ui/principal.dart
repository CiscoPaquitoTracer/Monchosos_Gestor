import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../avisos/aviso_reabasto.dart';
import '../estado/proveedores.dart';
import '../remoto/autenticacion.dart';
import 'comun/componentes.dart';
import 'comun/confirmar.dart';
import 'inicio/inicio.dart';
import 'inventario/inventario.dart';
import 'menu/menu_precios.dart';
import 'pedidos/pedidos.dart';
import 'resumen/resumen.dart';
import 'tema.dart';

/// Las secciones de la barra inferior, en orden (solo íconos; el nombre va arriba).
enum Seccion {
  inicio('Inicio', Icons.home_outlined, Icons.home),
  pedidos('Pedidos', Icons.receipt_long_outlined, Icons.receipt_long),
  resumen('Resumen', Icons.bar_chart_outlined, Icons.bar_chart),
  inventario('Inventario', Icons.inventory_2_outlined, Icons.inventory_2),
  menu('Menú', Icons.restaurant_menu_outlined, Icons.restaurant_menu);

  const Seccion(this.titulo, this.icono, this.iconoActivo);

  final String titulo;
  final IconData icono;
  final IconData iconoActivo;
}

/// Para que Inicio pueda cambiar de sección (por ejemplo, al tocar "por cobrar").
final seccionProvider = NotifierProvider<SeccionNotifier, Seccion>(
  SeccionNotifier.new,
);

class SeccionNotifier extends Notifier<Seccion> {
  @override
  Seccion build() => Seccion.inicio;

  void ir(Seccion s) => state = s;
}

class AppPrincipal extends ConsumerStatefulWidget {
  const AppPrincipal({super.key, required this.usuario});

  final Usuario usuario;

  @override
  ConsumerState<AppPrincipal> createState() => _AppPrincipalState();
}

class _AppPrincipalState extends ConsumerState<AppPrincipal> {
  @override
  void initState() {
    super.initState();
    // Android 13+: se pide una vez al entrar.
    AvisoReabasto.pedirPermiso().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final seccion = ref.watch(seccionProvider);
    // Precios y disponibilidad en toda la app (cada 2 min).
    ref.watch(menuProvider);
    void ir(int i) => ref.read(seccionProvider.notifier).ir(Seccion.values[i]);
    // iPad horizontal, Chromebook o laptop: barra lateral en lugar de la inferior.
    final ancha = MediaQuery.sizeOf(context).width >= anchoBarraLateral;
    final contenido = ConFranjaError(
      child: IndexedStack(
        index: seccion.index,
        children: const [
          PantallaInicio(),
          PantallaPedidos(),
          PantallaResumen(),
          PantallaInventario(),
          PantallaMenu(),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(seccion.titulo),
        actions: [
          BotonPerfil(usuario: widget.usuario),
          const SizedBox(width: 8),
        ],
      ),
      body: ancha
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: seccion.index,
                  onDestinationSelected: ir,
                  labelType: NavigationRailLabelType.none,
                  backgroundColor: context.colores.surfaceContainer,
                  indicatorColor: context.colores.secondaryContainer,
                  destinations: [
                    for (final s in Seccion.values)
                      NavigationRailDestination(
                        icon: Tooltip(message: s.titulo, child: Icon(s.icono)),
                        selectedIcon: Icon(s.iconoActivo),
                        label: Text(s.titulo),
                      ),
                  ],
                ),
                VerticalDivider(width: 1, color: context.colores.outline),
                Expanded(child: contenido),
              ],
            )
          : contenido,
      bottomNavigationBar: ancha
          ? null
          : NavigationBar(
              selectedIndex: seccion.index,
              onDestinationSelected: ir,
              destinations: [
                for (final s in Seccion.values)
                  NavigationDestination(
                    icon: Icon(s.icono),
                    selectedIcon: Icon(s.iconoActivo),
                    label: s.titulo,
                    tooltip: s.titulo,
                  ),
              ],
            ),
    );
  }
}

/// Círculo café con la inicial. Abre nombre, correo y "Cerrar sesión".
class BotonPerfil extends ConsumerWidget {
  const BotonPerfil({super.key, required this.usuario});

  final Usuario usuario;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: 'Perfil',
    offset: const Offset(0, 48),
    onSelected: (_) async {
      final ok = await confirmar(
        context,
        titulo: '¿Cerrar sesión?',
        mensaje: 'Tendrás que volver a entrar con tu cuenta de Google.',
        confirmar: 'Cerrar sesión',
      );
      if (!ok) return;
      ref.read(avisoErrorProvider.notifier).cerrar();
      ref.read(seccionProvider.notifier).ir(Seccion.inicio);
      await ref.read(autenticacionProvider).cerrarSesion();
    },
    itemBuilder: (context) => [
      PopupMenuItem(
        enabled: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(usuario.nombre, style: context.textos.titleMedium),
            Text(
              usuario.correo,
              style: context.textos.bodySmall?.copyWith(
                color: context.colores.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'salir',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.logout),
          title: Text('Cerrar sesión'),
        ),
      ),
    ],
    child: CircleAvatar(
      radius: 18,
      backgroundColor: Colores.cafe,
      foregroundColor: Colores.blanco,
      child: Text(
        usuario.inicial,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
  );
}

/// Pantalla interna (pedido nuevo, detalle, editar): flecha de regreso y franja de error.
class PantallaInterna extends StatelessWidget {
  const PantallaInterna({
    super.key,
    required this.titulo,
    required this.child,
    this.abajo,
    this.acciones = const [],
  });

  final String titulo;
  final Widget child;
  final Widget? abajo;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(titulo),
      actions: acciones,
      // La flecha pasa por el "back" del sistema para que la pantalla lo pueda interceptar.
      leading: BackButton(onPressed: () => Navigator.maybePop(context)),
    ),
    body: ConFranjaError(child: child),
    bottomNavigationBar: abajo,
  );
}
