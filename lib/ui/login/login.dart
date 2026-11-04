import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../estado/proveedores.dart';
import '../tema.dart';

/// El logo (la hamburguesa vaquera) en un círculo café.
class Logo extends StatelessWidget {
  const Logo({super.key, this.tamano = 120});

  final double tamano;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: Container(
      width: tamano,
      height: tamano,
      color: Colores.cafe,
      child: Image.asset('assets/logo.png', fit: BoxFit.cover),
    ),
  );
}

class PantallaLogin extends ConsumerStatefulWidget {
  const PantallaLogin({super.key});

  @override
  ConsumerState<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends ConsumerState<PantallaLogin> {
  bool _entrando = false;
  String? _errorLogin;

  Future<void> _entrar() async {
    ref.read(errorAccesoProvider.notifier).poner(null);
    setState(() {
      _entrando = true;
      _errorLogin = null;
    });
    // En la PWA la página se va a Google y regresa ya con la sesión.
    final error = await ref.read(autenticacionProvider).iniciarSesion();
    if (!mounted) return;
    setState(() {
      _entrando = false;
      _errorLogin = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _errorLogin ?? ref.watch(errorAccesoProvider);
    return _contenido(context, error);
  }

  Widget _contenido(BuildContext context, String? error) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                const Logo(),
                const SizedBox(height: 24),
                Text(
                  'Monchosos',
                  style: context.textos.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gestor de la hamburguesería',
                  style: TextStyle(color: context.colores.onSurfaceVariant),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _entrando ? null : _entrar,
                    icon: _entrando
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: const Text('Iniciar sesión con Google'),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: context.alerta),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          style: TextStyle(color: context.alerta),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
