// HU-AUTH-005 — Confirmación de recuperación de contraseña (ADR-006), con el remoto y la DB local
// en memoria. Dart puro.
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/domain/entities/politica_password.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/recuperacion_password_repository.dart';
import 'package:colportores_mobile/features/auth/domain/services/turno_db_local.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/abandonar_recuperacion_password_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/confirmar_recuperacion_password_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/observar_enlaces_recuperacion_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

import '../../../../../helpers/db_local_repository_en_memoria.dart';

final class _RecuperacionFalsa implements RecuperacionPasswordRepository {
  final llamadas = <String>[];
  final enlacesController = StreamController<EnlaceRecuperacion>.broadcast();
  Failure? fallaAlActualizar;
  Failure? fallaAlCerrarSesiones;
  String? fijada;

  @override
  Stream<EnlaceRecuperacion> get enlaces => enlacesController.stream;

  @override
  Future<Either<Failure, Unit>> actualizarPassword(String nueva) async {
    llamadas.add('actualizar');
    if (fallaAlActualizar case final falla?) return Left(falla);
    fijada = nueva;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> cerrarTodasLasSesiones() async {
    llamadas.add('cerrarSesiones');
    if (fallaAlCerrarSesiones case final falla?) return Left(falla);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> abandonar() async {
    llamadas.add('abandonar');
    return const Right(unit);
  }
}

void main() {
  late _RecuperacionFalsa recuperacion;
  late DbLocalRepositoryEnMemoria dbLocal;
  late TurnoDbLocal turno;
  late ConfirmarRecuperacionPasswordUseCase confirmar;

  setUp(() {
    recuperacion = _RecuperacionFalsa();
    dbLocal = DbLocalRepositoryEnMemoria();
    turno = TurnoDbLocal();
    confirmar = ConfirmarRecuperacionPasswordUseCase(recuperacion, dbLocal, turno);
  });

  Future<Either<Failure, Unit>> conPassword(String nueva, {String? repetida}) =>
      confirmar(ConfirmarRecuperacionPasswordParams(nueva: nueva, repetida: repetida ?? nueva));

  Map<String, String> campos(Either<Failure, Unit> r) =>
      (r.fold((f) => f, (_) => fail('se esperaba Left')) as FailureValidacion).campos;

  group('Escenario: Cambio exitoso en dispositivo sin DB local previa', () {
    test('dado un dispositivo sin DB local, actualiza la contraseña y revoca todas las sesiones, '
        'sin tocar la DB', () async {
      final r = await conPassword('NuevaClave1');

      expect(r, const Right<Failure, Unit>(unit));
      expect(recuperacion.fijada, 'NuevaClave1');
      expect(recuperacion.llamadas, ['actualizar', 'cerrarSesiones']);
      expect(dbLocal.llamadas, ['estado'], reason: 'no hay DEK que re-envolver');
    });
  });

  group('Escenario: Cambio en dispositivo CON DB local - se re-envuelve la DEK', () {
    setUp(() {
      final dek = Uint8List.fromList(List<int>.filled(32, 77));
      dbLocal
        ..marca = MarcaDbLocal.puesta
        ..archivo = true
        ..claveDelArchivo = dek
        ..dekEnAlmacen = dek
        ..envoltorio = (dek: dek, password: 'Vieja1234');
    });

    test('dado una DB local, desenvuelve la DEK con el almacén seguro y la re-envuelve con la '
        'contraseña nueva; la DB queda intacta', () async {
      final r = await conPassword('NuevaClave1');

      expect(r, const Right<Failure, Unit>(unit));
      expect(dbLocal.llamadas, ['estado', 'leerDek', 'envolver']);
      expect(dbLocal.envoltorio!.password, 'NuevaClave1');
      expect(dbLocal.envoltorio!.dek, List<int>.filled(32, 77));
      expect(dbLocal.archivo, isTrue);
      expect(dbLocal.claveDelArchivo, List<int>.filled(32, 77));
      expect(dbLocal.entregadas.single.destruida, isTrue, reason: 'la DEK no queda viva');
      expect(recuperacion.llamadas, ['actualizar', 'cerrarSesiones']);
    });

    test('nunca pide la contraseña vieja: la DEK sale del almacén, no del envoltorio', () async {
      await conPassword('NuevaClave1');

      expect(dbLocal.llamadas, isNot(contains('desenvolver')));
    });

    test('dado que el almacén no deja leer la DEK, la contraseña igual cambió: no se borra nada y '
        'rige la recuperación guiada en el próximo inicio', () async {
      dbLocal.fallas['leerDek'] = const FailureAlmacenSeguro();

      final r = await conPassword('NuevaClave1');

      expect(r, const Right<Failure, Unit>(unit));
      expect(dbLocal.llamadas, isNot(contains('envolver')));
      expect(dbLocal.envoltorio!.password, 'Vieja1234', reason: 'queda el envoltorio anterior');
      expect(dbLocal.archivo, isTrue);
      expect(recuperacion.llamadas, ['actualizar', 'cerrarSesiones']);
    });

    test('dado que re-envolver falla, la contraseña igual cambió y la DEK no queda viva', () async {
      dbLocal.fallas['envolver'] = const FailureAlmacenSeguro();

      final r = await conPassword('NuevaClave1');

      expect(r, const Right<Failure, Unit>(unit));
      expect(dbLocal.entregadas.single.destruida, isTrue);
    });

    test(
      're-envuelve dentro del turno de la DB local: espera a una inicialización en curso',
      () async {
        final ocupado = Completer<void>();
        final enCurso = turno.enExclusiva(() => ocupado.future);

        final r = conPassword('NuevaClave1');
        await Future<void>.delayed(Duration.zero);
        expect(dbLocal.llamadas, isEmpty, reason: 'espera el turno');

        ocupado.complete();
        await enCurso;
        expect(await r, const Right<Failure, Unit>(unit));
        expect(dbLocal.llamadas, contains('envolver'));
      },
    );
  });

  group('validación de la contraseña nueva (misma política que el registro)', () {
    test('dada una contraseña vacía o que no cumple la política, lo dice en el campo y no llama al '
        'remoto', () async {
      expect(campos(await conPassword('')), {
        'password': 'Ingresá la contraseña nueva',
        'repetida': 'Repetí la contraseña nueva',
      });
      expect(campos(await conPassword('corta1A')), {'password': PoliticaPassword.requisitos});
      expect(campos(await conPassword('sinmayuscula1')), {'password': PoliticaPassword.requisitos});
      expect(campos(await conPassword('SinNumero')), {'password': PoliticaPassword.requisitos});
      expect(recuperacion.llamadas, isEmpty);
    });

    test('dado que la repetida no coincide, lo dice en ese campo', () async {
      expect(campos(await conPassword('NuevaClave1', repetida: 'NuevaClave2')), {
        'repetida': 'Las contraseñas no coinciden',
      });
      expect(recuperacion.llamadas, isEmpty);
    });
  });

  group('cuando el remoto falla', () {
    for (final falla in <Failure>[
      const FailureEnlaceRecuperacionVencido(),
      const FailureSinConexion(),
      const FailureValidacion(campos: {'password': 'Tiene que ser distinta de la anterior.'}),
      const FailureServidor(),
    ]) {
      test(
        'dado ${falla.codigo} al actualizar, lo devuelve y no toca la DB ni las sesiones',
        () async {
          recuperacion.fallaAlActualizar = falla;

          expect(await conPassword('NuevaClave1'), Left<Failure, Unit>(falla));
          expect(recuperacion.llamadas, ['actualizar']);
          expect(dbLocal.llamadas, isEmpty);
        },
      );
    }

    test('dado que revocar las sesiones falla, la contraseña igual cambió: éxito', () async {
      recuperacion.fallaAlCerrarSesiones = const FailureSinConexion();

      expect(await conPassword('NuevaClave1'), const Right<Failure, Unit>(unit));
    });
  });

  test('los params no imprimen las contraseñas', () {
    final previo = EquatableConfig.stringify;
    addTearDown(() => EquatableConfig.stringify = previo);
    EquatableConfig.stringify = true;

    expect(
      '${const ConfirmarRecuperacionPasswordParams(nueva: 'NuevaClave1', repetida: 'x')}',
      isNot(contains('NuevaClave1')),
    );
  });

  test('ObservarEnlacesRecuperacion y AbandonarRecuperacion delegan en el repositorio', () async {
    final eventos = <EnlaceRecuperacion>[];
    final suscripcion = ObservarEnlacesRecuperacionUseCase(recuperacion)(
      const NoParams(),
    ).listen(eventos.add);
    addTearDown(suscripcion.cancel);

    recuperacion.enlacesController.add(EnlaceRecuperacion.valido);
    await Future<void>.delayed(Duration.zero);
    final r = await AbandonarRecuperacionPasswordUseCase(recuperacion)(const NoParams());

    expect(eventos, [EnlaceRecuperacion.valido]);
    expect(r, const Right<Failure, Unit>(unit));
    expect(recuperacion.llamadas, ['abandonar']);
  });

  test(
    'PoliticaPassword acepta una contraseña que cumple y usa el texto de vacía que se le pase',
    () {
      expect(PoliticaPassword.validar('NuevaClave1'), isNull);
      expect(PoliticaPassword.validar(''), 'Ingresá tu contraseña');
      expect(PoliticaPassword.validar('', vacia: 'x'), 'x');
    },
  );
}
