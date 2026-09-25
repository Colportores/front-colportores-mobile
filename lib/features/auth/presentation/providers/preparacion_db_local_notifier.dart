import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../../domain/entities/sesion.dart';
import '../../domain/usecases/inicializar_db_local_use_case.dart';
import '../../domain/usecases/recuperar_db_local_con_password_use_case.dart';
import 'db_local_providers.dart';
import 'password_para_db_local.dart';
import 'sesion_notifier.dart';

part 'preparacion_db_local_notifier.g.dart';

/// En qué está la DB local de quien tiene la sesión (HU-AUTH-009, #27).
sealed class EstadoPreparacionDbLocal {
  const EstadoPreparacionDbLocal();
}

/// Nadie tiene la sesión: no hay nada que preparar.
final class SinSesionDbLocal extends EstadoPreparacionDbLocal {
  const SinSesionDbLocal();
}

/// Preparando o abriendo la DB. [paso] es el último que avisó el caso de uso, o `null` mientras
/// todavía verifica el equipo (bloqueo de pantalla, nivel del Keystore).
final class PreparandoDbLocal extends EstadoPreparacionDbLocal {
  const PreparandoDbLocal({this.paso});

  final PasoInicializacionDb? paso;
}

/// Recuperando la DEK con la contraseña (Argon2id, 1 a 2 s).
final class RecuperandoDbLocal extends EstadoPreparacionDbLocal {
  const RecuperandoDbLocal();
}

/// Confirmando la contraseña de la cuenta contra el servidor, para proteger la DB con ella.
final class ConfirmandoPasswordDbLocal extends EstadoPreparacionDbLocal {
  const ConfirmandoPasswordDbLocal();
}

/// La DB está abierta: la app sigue a la pantalla principal (o a HU-AUTH-008).
final class DbLocalLista extends EstadoPreparacionDbLocal {
  const DbLocalLista();
}

/// La preparación no terminó. [falla] dice por qué y la pantalla elige qué ofrecer.
///
/// - [reintentos]: cuántas veces seguidas el usuario tocó "Reintentar" y volvió a fallar **por lo
///   mismo** (si la falla cambia, vuelve a 0). "Empezar de nuevo", que borra, recién se ofrece
///   después de un reintento: una falla del almacén puede ser pasajera, y reintentar no cuesta
///   nada (revisión del PR #81, punto 7).
/// - [errorRecuperacion]: con [FailureAlmacenSeguroRecuperable] o [FailurePasswordParaProteger],
///   por qué no sirvió la contraseña que se probó (va debajo del campo).
final class PreparacionDbLocalFallida extends EstadoPreparacionDbLocal {
  const PreparacionDbLocalFallida(this.falla, {this.reintentos = 0, this.errorRecuperacion});

  final Failure falla;
  final int reintentos;
  final Failure? errorRecuperacion;
}

/// El usuario no aceptó seguir con el Keystore por software (S10): la DB no se preparó y la
/// pantalla le explica cómo usar otro celular.
final class AlmacenSoftwareRechazado extends EstadoPreparacionDbLocal {
  const AlmacenSoftwareRechazado();
}

/// Prepara la DB local cada vez que alguien entra o se restaura la sesión (HU-AUTH-009, #27), y
/// lleva los caminos de la recuperación guiada de ADR-006.
///
/// Se dispara solo: observa el usuario de `sesionProvider`, así que cubre el login con contraseña,
/// el de Google, el registro con sesión y la sesión restaurada al abrir la app. Con la contraseña
/// del login ([PasswordParaDbLocal]) arma el envoltorio. Si la cuenta entra con contraseña y no
/// está (sesión restaurada), la pide antes de crear la DB o de dar por lista una sin envoltorio
/// ([FailurePasswordParaProteger], revisión del PR #130); con Google, abre sin él (ADR-006).
///
/// Cada método guarda `ref` antes de esperar y mira `mounted` en esa copia: si la sesión cambió
/// en el medio, el provider se reconstruyó y lo que termina tarde no pisa el estado nuevo.
///
/// Los flujos corren en `TurnoDbLocal`, así que dos toques seguidos no se pisan: el segundo
/// encuentra la DB abierta y termina en [DbLocalLista].
@Riverpod(keepAlive: true)
class PreparacionDbLocalNotifier extends _$PreparacionDbLocalNotifier {
  @override
  EstadoPreparacionDbLocal build() {
    final usuarioId = ref.watch(
      sesionProvider.select((AsyncValue<Sesion?> s) => s.value?.usuarioId),
    );
    if (usuarioId == null) {
      ref.read(passwordParaDbLocalProvider).olvidar();
      return const SinSesionDbLocal();
    }
    // Después de construir: el caso de uso lee `sesionProvider` y actualiza `state`.
    unawaited(Future.microtask(_preparar));
    return const PreparandoDbLocal();
  }

  /// Vuelve a intentar después de una falla (por ejemplo, un Keystore que no respondió o poco
  /// espacio que el usuario ya liberó).
  Future<void> reintentar() async {
    final (anterior, reintentos) = switch (state) {
      PreparacionDbLocalFallida(:final falla, :final reintentos) => (falla, reintentos + 1),
      _ => (null, 0),
    };
    await _preparar(fallaAnterior: anterior, reintentos: reintentos);
  }

  /// "Entiendo el riesgo y quiero continuar" (S10): sigue con el Keystore por software y registra
  /// la elección.
  Future<void> aceptarAlmacenSoftware() => _preparar(aceptaAlmacenSoftware: true);

  /// "Cancelar" en la advertencia de S10: no se prepara nada.
  void rechazarAlmacenSoftware() => state = const AlmacenSoftwareRechazado();

  /// Vuelve a mostrar la advertencia de S10 después de haberla rechazado.
  void revisarAlmacenSoftware() =>
      state = const PreparacionDbLocalFallida(FailureAlmacenPocoSeguro());

  /// Recuperación guiada (ADR-006): la DEK se desenvuelve con [password]. Si la contraseña no
  /// abre, se queda en el formulario con el error.
  Future<void> recuperarConPassword(String password) async {
    final r = ref;
    state = const RecuperandoDbLocal();
    final resultado = await r.read(recuperarDbLocalConPasswordUseCaseProvider)(
      RecuperarDbLocalParams(password: password),
    );
    if (!r.mounted) return;
    state = resultado.fold(
      (falla) => switch (falla) {
        FailurePasswordNoAbreDatos() || FailureValidacion() => PreparacionDbLocalFallida(
          const FailureAlmacenSeguroRecuperable(),
          errorRecuperacion: falla,
        ),
        _ => _fallida(falla),
      },
      (_) => _lista(),
    );
  }

  /// La contraseña de la cuenta, para proteger la DB con ella ([FailurePasswordParaProteger]). Se
  /// confirma contra el servidor (`SesionNotifier.confirmarPassword`): un envoltorio armado con
  /// una contraseña equivocada no serviría el día que haga falta. Si no se pudo confirmar, se queda
  /// en el formulario con el error.
  Future<void> confirmarPassword(String password) async {
    final r = ref;
    state = const ConfirmandoPasswordDbLocal();
    final falla = await r.read(sesionProvider.notifier).confirmarPassword(password);
    if (!r.mounted) return;
    if (falla != null) {
      state = PreparacionDbLocalFallida(
        const FailurePasswordParaProteger(),
        errorRecuperacion: falla,
      );
      return;
    }
    await _preparar();
  }

  /// "Empezar de nuevo" de ADR-006, **solo después del sí del usuario**: borra la DB que no se
  /// puede abrir y prepara una nueva.
  Future<void> empezarDeNuevo() async {
    final r = ref;
    state = const PreparandoDbLocal();
    final resultado = await r.read(empezarDeNuevoDbLocalUseCaseProvider)(const NoParams());
    if (!r.mounted) return;
    if (resultado case Left(value: final falla)) {
      state = _fallida(falla);
      return;
    }
    await _preparar();
  }

  Future<void> _preparar({
    bool aceptaAlmacenSoftware = false,
    Failure? fallaAnterior,
    int reintentos = 0,
  }) async {
    final r = ref;
    if (!r.mounted) return;
    state = const PreparandoDbLocal();
    final resultado = await r.read(inicializarDbLocalUseCaseProvider)(
      InicializarDbLocalParams(
        password: r.read(passwordParaDbLocalProvider).actual,
        requiereEnvoltorio: r.read(sesionProvider).value?.entraConPassword ?? true,
        aceptaAlmacenSoftware: aceptaAlmacenSoftware,
        alAvanzar: (paso) {
          if (r.mounted) state = PreparandoDbLocal(paso: paso);
        },
      ),
    );
    if (!r.mounted) return;
    state = resultado.fold(
      (falla) => _fallida(
        falla,
        // Otra falla cuenta desde cero: "empezar de nuevo" nunca aparece la primera vez.
        reintentos: falla.runtimeType == fallaAnterior?.runtimeType ? reintentos : 0,
      ),
      (_) => _lista(),
    );
  }

  EstadoPreparacionDbLocal _lista() {
    ref.read(passwordParaDbLocalProvider).olvidar();
    return const DbLocalLista();
  }

  /// El estado para [falla]. Si la sesión se cerró mientras tanto no hay nada que mostrar: la app
  /// vuelve al login sola.
  static EstadoPreparacionDbLocal _fallida(Failure falla, {int reintentos = 0}) => switch (falla) {
    FailureSesionCerrada() => const SinSesionDbLocal(),
    _ => PreparacionDbLocalFallida(falla, reintentos: reintentos),
  };
}
