import 'package:equatable/equatable.dart';

/// Por qué las notas de una persona están en solo lectura (32B·04 y 32B·08).
enum CausaSoloLectura {
  /// La persona está dada de baja ([ContextoNotasPersona.bajaDesde]).
  personaDeBaja,

  /// Su espacio (o la ubicación del espacio) está dado de baja.
  espacioDeBaja,

  /// Ninguno de sus vínculos con un espacio sigue activo.
  sinEspacioActivo,
}

/// De quién son las notas que se están viendo y si se pueden cambiar (HU-UBI-012, vista 32E).
///
/// **PII**: lleva el nombre de la persona y la dirección de su espacio; no se imprime ni va a los logs
/// (`stringify` apagado).
class ContextoNotasPersona extends Equatable {
  const ContextoNotasPersona({
    required this.nombre,
    this.causa,
    this.bajaDesde,
    this.numeroDepto,
    this.direccion,
  });

  /// El nombre de pila («Notas de María»).
  final String nombre;

  /// Por qué solo se pueden ver; `null` si se pueden agregar, editar, borrar y restaurar.
  final CausaSoloLectura? causa;

  /// Cuándo se dio de baja a la persona (con [CausaSoloLectura.personaDeBaja]).
  final DateTime? bajaDesde;

  /// El número del depto dado de baja (con [CausaSoloLectura.espacioDeBaja]), si tiene.
  final String? numeroDepto;

  /// «Mataojo 2044»: dónde está el espacio dado de baja, si se conoce.
  final String? direccion;

  /// La persona está dada de baja, o ningún espacio suyo sigue activo (32B·04 y 32B·08): las notas se
  /// ven, pero no se agrega, edita, borra ni restaura ninguna.
  bool get soloLectura => causa != null;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [nombre, causa, bajaDesde, numeroDepto, direccion];
}
