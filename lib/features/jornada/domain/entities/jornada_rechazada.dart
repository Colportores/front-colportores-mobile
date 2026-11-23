import 'package:equatable/equatable.dart';

/// Una jornada que el servidor no aceptó porque empezó antes del inicio de la campaña (`42501` en el
/// push, backend-supabase 0115; decisión de Cristian del 27/10 sobre backend-supabase#184), con las
/// visitas que cuelgan de ella y que volvieron con `23503` (la FK a la jornada que no existe).
///
/// Del teléfono no se borra nada: la jornada y sus visitas quedan guardadas, y el aviso lo dice.
class JornadaRechazada extends Equatable {
  const JornadaRechazada({required this.id, required this.inicio, required this.visitas});

  /// `jornada.id`.
  final String id;

  /// Cuándo empezó la jornada, en UTC.
  final DateTime inicio;

  /// Cuántas visitas de la jornada tampoco se enviaron.
  final int visitas;

  @override
  List<Object?> get props => [id, inicio, visitas];
}
