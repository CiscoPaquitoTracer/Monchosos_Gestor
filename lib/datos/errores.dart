/// Error de validación con un mensaje listo para mostrar al usuario.
class ErrorValidacion implements Exception {
  const ErrorValidacion(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}
