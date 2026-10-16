import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/secure_storage/clave_db.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/estado_db_local.dart';
import '../entities/politica_password.dart';
import '../repositories/db_local_repository.dart';
import '../repositories/recuperacion_password_repository.dart';
import '../services/turno_db_local.dart';

/// Parámetros de [ConfirmarRecuperacionPasswordUseCase].
final class ConfirmarRecuperacionPasswordParams extends Equatable {
  const ConfirmarRecuperacionPasswordParams({required this.nueva, required this.repetida});

  /// La contraseña nueva.
  final String nueva;

  /// La misma, escrita otra vez ("ingreso una nueva contraseña válida y la confirmo").
  final String repetida;

  /// [props] lleva las contraseñas en texto plano: sin esto, interpolar los params en un log las
  /// filtraría (convenciones-desarrollo.md §7.5).
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [nueva, repetida];
}

/// HU-AUTH-005 — Confirmación de recuperación de contraseña (ADR-006).
///
/// 1. Valida la contraseña nueva con la misma política que el registro, y que las dos coincidan.
/// 2. Si hay envoltorio por contraseña, lo **marca como desactualizado** antes de tocar el
///    servidor (#125).
/// 3. La fija en Supabase Auth con la sesión que abrió el enlace. Si ese paso falla, no se toca
///    nada más: el usuario puede corregir y reintentar.
/// 4. Si hay DB local en este dispositivo, **re-envuelve la DEK** con Argon2id(nueva contraseña):
///    la DEK sale del almacén seguro y el envoltorio anterior se reemplaza (eso baja la marca). La
///    DB no se toca y en ningún momento se pide la contraseña vieja.
/// 5. Revoca todas las sesiones de la cuenta en todos los dispositivos (Supabase `signOut` con
///    scope global), incluida la de este: el usuario vuelve a entrar con la contraseña nueva.
///
/// Los pasos 2 y 4 corren en [TurnoDbLocal], como los otros flujos de la DB local.
///
/// Los pasos 4 y 5 no deshacen el 3: la contraseña ya cambió. Si fallan, el repositorio deja la
/// falla en el log y el resultado es igual un éxito, porque el usuario no puede hacer nada con eso.
///
/// ## Si el re-envoltorio no llega a hacerse (#125)
///
/// Puede pasar que el servidor aplique el cambio y la respuesta se pierda (la pantalla dice "sin
/// conexión" y el usuario sale), que el almacén seguro no deje leer la DEK justo ahora o que la app
/// muera durante el Argon2id. En todos los casos la marca del paso 2 queda puesta, y el próximo
/// login con contraseña **de esa cuenta** re-envuelve la DEK con esa contraseña
/// (`InicializarDbLocalUseCase`, o `RecuperarDbLocalConPasswordUseCase` si el Keystore falla):
/// sin la marca, el envoltorio quedaría con la contraseña olvidada y, si después fallara el
/// Keystore, ninguna contraseña que el usuario conoce abriría sus datos. Si en ese login el almacén
/// no responde, rige la recuperación guiada (ADR-006) con la contraseña anterior (el aviso de
/// "contraseña que no abre" ya sugiere probar con esa), y ahí mismo se renueva el envoltorio.
///
/// Una respuesta del servidor que rechaza el cambio no baja la marca: un intento anterior pudo
/// haber entrado sin respuesta. Una marca de más solo cuesta un Argon2id en el próximo login.
final class ConfirmarRecuperacionPasswordUseCase
    implements UseCase<Unit, ConfirmarRecuperacionPasswordParams> {
  const ConfirmarRecuperacionPasswordUseCase(this._recuperacion, this._dbLocal, this._turno);

  final RecuperacionPasswordRepository _recuperacion;
  final DbLocalRepository _dbLocal;
  final TurnoDbLocal _turno;

  @override
  Future<Either<Failure, Unit>> call(ConfirmarRecuperacionPasswordParams params) async {
    final errores = <String, String>{};
    if (PoliticaPassword.validar(params.nueva, vacia: 'Ingresá la contraseña nueva')
        case final error?) {
      errores['password'] = error;
    }
    if (params.repetida.isEmpty) {
      errores['repetida'] = 'Repetí la contraseña nueva';
    } else if (params.repetida != params.nueva) {
      errores['repetida'] = 'Las contraseñas no coinciden';
    }
    if (errores.isNotEmpty) return Left(FailureValidacion(campos: errores));

    final hayDbLocal = await _turno.enExclusiva(_marcarEnvoltorio);

    final actualizada = await _recuperacion.actualizarPassword(params.nueva);
    if (actualizada case Left(value: final falla)) return Left(falla);

    if (hayDbLocal) await _turno.enExclusiva(() => _reenvolverDek(params.nueva));
    await _recuperacion.cerrarTodasLasSesiones();
    return const Right(unit);
  }

  /// Paso 2: marca el envoltorio como desactualizado, si hay. Devuelve si el dispositivo tiene DB
  /// local, cuya DEK hay que re-envolver en el paso 4; sin DB (dispositivo nuevo) no hay nada que
  /// envolver.
  ///
  /// La marca lleva el `usuario_id` de la cuenta que se recupera: solo un login de esa cuenta la
  /// usa para re-envolver. Sin sesión de recuperación no hay a quién atarla, y tampoco cambio de
  /// contraseña (el servidor lo rechaza).
  ///
  /// Si no se puede marcar, igual se sigue: frenar el cambio de contraseña por eso dejaría al
  /// usuario sin poder entrar a su cuenta. La falla queda en el log.
  Future<bool> _marcarEnvoltorio() async {
    final estado = await _dbLocal.estado();
    if (estado case Right(value: final EstadoDbLocal e)) {
      final usuarioId = _recuperacion.usuarioId;
      if (e.envoltorioExiste && usuarioId != null) {
        await _dbLocal.marcarEnvoltorioDesactualizado(usuarioId);
      }
      return e.archivoExiste && e.marca == MarcaDbLocal.puesta;
    }
    return false;
  }

  /// Paso 4: re-envuelve la DEK del almacén seguro con la contraseña nueva. Si el almacén no la da
  /// o envolver falla, la marca del paso 2 queda puesta para el próximo login.
  Future<void> _reenvolverDek(String nueva) async {
    final leida = await _dbLocal.leerDek();
    if (leida case Right(value: final ClaveDb dek)) {
      try {
        await _dbLocal.envolverConPassword(dek, nueva);
      } finally {
        dek.destruir();
      }
    }
  }
}
