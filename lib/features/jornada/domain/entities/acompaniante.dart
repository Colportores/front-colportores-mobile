import 'package:equatable/equatable.dart';

/// Un coordinador de la campaña de la colportora, de los que ofrece «¿Quién te acompaña?» (vista 20,
/// HU-JOR-003): de él se guarda solo el nombre y el apellido (nunca el correo ni el teléfono).
class CoordinadorDeCampania extends Equatable {
  const CoordinadorDeCampania({
    required this.usuarioId,
    required this.nombre,
    required this.apellido,
  });

  /// La cuenta del coordinador: es lo que sube como `jornada_acompaniante.acompaniante_id`.
  final String usuarioId;

  final String nombre;

  final String apellido;

  /// «Marta Pérez»: nombre y apellido sin espacios de más, o `null` si el perfil no trajo ninguno.
  String? get nombreCompleto => _nombreCompleto(nombre, apellido);

  @override
  List<Object?> get props => [usuarioId, nombre, apellido];
}

/// Quien acompañó una jornada: una fila de `jornada_acompaniante` (varios por jornada, decisión de
/// Cristian, 05/11, «Dos acomp.»).
class Acompaniante extends Equatable {
  const Acompaniante({required this.usuarioId, this.nombre, this.apellido});

  final String usuarioId;

  /// `null` si el teléfono no tiene a esa persona en la lista de coordinadores (no se inventa un nombre).
  final String? nombre;

  final String? apellido;

  /// El nombre para mostrar, o `null` si no se sabe.
  String? get nombreCompleto => _nombreCompleto(nombre ?? '', apellido ?? '');

  @override
  List<Object?> get props => [usuarioId, nombre, apellido];
}

String? _nombreCompleto(String nombre, String apellido) {
  final junto = '${nombre.trim()} ${apellido.trim()}'.trim();
  return junto.isEmpty ? null : junto;
}
