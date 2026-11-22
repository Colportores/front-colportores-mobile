import 'package:equatable/equatable.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/entities/motivo_expiracion.dart';

part 'reingreso_sesion_notifier.g.dart';

/// Quién era el colportor cuando la sesión terminó sin que lo pidiera (HU-AUTH-007, vista 17): el
/// login lo saluda, precarga el correo y dice que lo suyo sigue guardado.
///
/// [email] y [nombre] pueden faltar: si la sesión se descartó al arrancar la app ya no hay de
/// quién, y el nombre de la cuenta todavía no está en la sesión (#243). Sin datos personales en
/// logs: esto vive solo en memoria y en pantalla.
class DatosReingreso extends Equatable {
  const DatosReingreso({required this.motivo, this.email, this.nombre});

  final MotivoExpiracion motivo;
  final String? email;
  final String? nombre;

  // Sin `toString` con el contenido: correo y nombre son datos personales y no deben llegar a logs.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [motivo, email, nombre];
}

/// Dura hasta que el usuario vuelve a entrar. A diferencia del aviso (`AvisoSesion`), que se
/// puede cerrar con la ✕ (17-A04), el saludo y «Recuperar acceso» quedan.
@Riverpod(keepAlive: true)
class ReingresoSesion extends _$ReingresoSesion {
  @override
  DatosReingreso? build() => null;

  void iniciar(DatosReingreso datos) => state = datos;

  void limpiar() => state = null;
}
