import 'package:flutter/material.dart';

/// Colores de la marca, tomados del ícono. Diseño provisional: otro equipo hará el final.
abstract final class Colores {
  static const cafe = Color(0xFF571401);
  static const cafeClaro = Color(0xFFFFB59C);
  static const cafeFondo = Color(0xFFF6E7E0);
  static const mostaza = Color(0xFFE0A100);
  static const mostazaFondo = Color(0xFFFFF1CC);
  static const ketchup = Color(0xFFB3261E);
  static const papel = Color(0xFFF7F4EF);
  static const blanco = Color(0xFFFFFFFF);
  static const linea = Color(0xFFE2DAD0);
  static const textoSuave = Color(0xFF6B5F57);
  static const tinta = Color(0xFF231A15);
  static const carbon = Color(0xFF181311);
  static const carbonPanel = Color(0xFF221B18);
  static const carbonLinea = Color(0xFF3B322D);
  static const exito = Color(0xFF2E7D32);
  static const exitoOscuro = Color(0xFF81C784);
}

const _claro = ColorScheme(
  brightness: Brightness.light,
  primary: Colores.cafe,
  onPrimary: Colores.blanco,
  primaryContainer: Colores.cafeFondo,
  onPrimaryContainer: Colores.cafe,
  secondary: Colores.mostaza,
  onSecondary: Colores.tinta,
  secondaryContainer: Colores.mostazaFondo,
  onSecondaryContainer: Colores.tinta,
  tertiary: Colores.ketchup,
  onTertiary: Colores.blanco,
  error: Colores.ketchup,
  onError: Colores.blanco,
  surface: Colores.papel,
  onSurface: Colores.tinta,
  onSurfaceVariant: Colores.textoSuave,
  // Paneles y barras blancos sobre el fondo papel.
  surfaceContainerLowest: Colores.blanco,
  surfaceContainerLow: Colores.blanco,
  surfaceContainer: Colores.blanco,
  surfaceContainerHigh: Colores.blanco,
  surfaceContainerHighest: Colores.blanco,
  outline: Colores.linea,
  outlineVariant: Colores.linea,
);

const _oscuro = ColorScheme(
  brightness: Brightness.dark,
  primary: Colores.cafeClaro,
  onPrimary: Colores.cafe,
  primaryContainer: Color(0xFF3D1205),
  onPrimaryContainer: Colores.cafeClaro,
  secondary: Colores.mostaza,
  onSecondary: Colores.tinta,
  // Chips elegidos y botones − / + (sin esto Material usa un gris morado).
  secondaryContainer: Color(0xFF4A3426),
  onSecondaryContainer: Color(0xFFFFDCC4),
  tertiary: Color(0xFFFFB4AB),
  onTertiary: Color(0xFF690005),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  surface: Colores.carbon,
  onSurface: Color(0xFFEDE0DA),
  onSurfaceVariant: Color(0xFFBFB0A8),
  surfaceContainerLowest: Colores.carbonPanel,
  surfaceContainerLow: Colores.carbonPanel,
  surfaceContainer: Colores.carbonPanel,
  surfaceContainerHigh: Colores.carbonPanel,
  surfaceContainerHighest: Colores.carbonPanel,
  outline: Colores.carbonLinea,
  outlineVariant: Colores.carbonLinea,
);

/// Dígitos de ancho fijo para que los montos queden alineados.
const cifras = [FontFeature.tabularFigures()];

ThemeData temaMonchosos(Brightness brillo) {
  final esquema = brillo == Brightness.dark ? _oscuro : _claro;
  final base = ThemeData(colorScheme: esquema, useMaterial3: true);
  final t = base.textTheme;
  TextStyle? c(TextStyle? s, [FontWeight? peso]) =>
      s?.copyWith(fontFeatures: cifras, fontWeight: peso);

  // Esquinas cortas: más punto de venta que burbuja de chat.
  RoundedRectangleBorder radio(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

  return base.copyWith(
    scaffoldBackgroundColor: esquema.surface,
    textTheme: t.copyWith(
      displaySmall: c(t.displaySmall, FontWeight.bold)?.copyWith(fontSize: 34),
      headlineSmall: c(t.headlineSmall, FontWeight.bold),
      titleLarge: c(t.titleLarge, FontWeight.bold),
      titleMedium: c(t.titleMedium, FontWeight.w600),
      titleSmall: c(t.titleSmall),
      bodyLarge: c(t.bodyLarge),
      bodyMedium: c(t.bodyMedium),
      labelMedium: t.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: esquema.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: esquema.outline)),
      titleTextStyle: t.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: esquema.onSurface,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: esquema.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: esquema.secondaryContainer,
      indicatorShape: radio(8),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      height: 64,
    ),
    cardTheme: CardThemeData(
      color: esquema.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: radio(8).copyWith(side: BorderSide(color: esquema.outline)),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: radio(6),
      side: BorderSide(color: esquema.outline),
      selectedColor: esquema.secondaryContainer,
      showCheckmark: false,
    ),
    dialogTheme: DialogThemeData(
      shape: radio(14),
      backgroundColor: esquema.surfaceContainer,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: radio(8)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: radio(8),
        side: BorderSide(color: esquema.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: radio(8)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: radio(10),
      backgroundColor: esquema.primary,
      foregroundColor: esquema.onPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    ),
    dividerTheme: DividerThemeData(
      color: esquema.outline,
      space: 1,
      thickness: 1,
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: radio(8),
      color: esquema.surfaceContainer,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

extension ColoresDelTema on BuildContext {
  ColorScheme get colores => Theme.of(this).colorScheme;

  TextTheme get textos => Theme.of(this).textTheme;

  bool get oscuro => Theme.of(this).brightness == Brightness.dark;

  /// Verde de "pagado", "ganancia" y "alcanza".
  Color get exito => oscuro ? Colores.exitoOscuro : Colores.exito;

  /// Rojo de "por cobrar" y "por agotarse".
  Color get alerta => colores.error;
}
