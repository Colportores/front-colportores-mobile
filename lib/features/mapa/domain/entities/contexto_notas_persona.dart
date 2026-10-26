import 'package:equatable/equatable.dart';

/// De quién son las notas que se están viendo y si se pueden cambiar (HU-UBI-012, vista 32E).
///
/// **PII**: lleva el nombre de la persona; no se imprime ni va a los logs (`stringify` apagado).
class ContextoNotasPersona extends Equatable {
  const ContextoNotasPersona({required this.nombre, required this.soloLectura});

  /// El nombre de pila («Notas de María»).
  final String nombre;

  /// La persona está dada de baja, o ningún espacio suyo sigue activo (32B·04 y 32B·08): las notas se
  /// ven, pero no se agrega, edita, borra ni restaura ninguna.
  final bool soloLectura;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [nombre, soloLectura];
}
