// HU-AUTH-005 — Confirmación de recuperación de contraseña (ADR-006), con el remoto y la DB local
// en memoria. Dart puro. Los casos de #125 siguen con el login y la recuperación guiada que vienen
// después, sobre el mismo dispositivo simulado.
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
import 'package:colportores_mobile/features/auth/domain/usecases/inicializar_db_local_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/observar_enlaces_recuperacion_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/recuperar_db_local_con_password_use_case.dart';
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
  String? usuarioId = 'usuario-a';

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
      expect(dbLocal.llamadas, ['estado', 'marcarDesactualizado', 'leerDek', 'envolver']);
      expect(dbLocal.envoltorio!.password, 'NuevaClave1');
      expect(dbLocal.envoltorio!.dek, List<int>.filled(32, 77));
      expect(dbLocal.envoltorioDesactualizado, isFalse, reason: 'el envoltorio nuevo la baja');
      expect(dbLocal.archivo, isTrue);
      expect(dbLocal.claveDelArchivo, List<int>.filled(32, 77));
      expect(dbLocal.entregadas.single.destruida, isTrue, reason: 'la DEK no queda viva');
      expect(recuperacion.llamadas, ['actualizar', 'cerrarSesiones']);
    });

    test('nunca pide la contraseña vieja: la DEK sale del almacén, no del envoltorio', () async {
      await conPassword('NuevaClave1');

      expect(dbLocal.llamadas, isNot(contains('desenvolver')));
    });

    test('dado que re-envolver falla, la contraseña igual cambió, la DEK no queda viva y la marca '
        'queda para el próximo login', () async {
      dbLocal.fallas['envolver'] = const FailureAlmacenSeguro();

      final r = await conPassword('NuevaClave1');

      expect(r, const Right<Failure, Unit>(unit));
      expect(dbLocal.entregadas.single.destruida, isTrue);
      expect(dbLocal.envoltorioDesactualizado, isTrue);
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

  group('el envoltorio no queda con la contraseña olvidada (#125)', () {
    const abierta = Right<Failure, ResultadoInicializacionDb>(ResultadoInicializacionDb.abierta);
    late VigenciaEnMemoria vigencia;

    setUp(() {
      final dek = Uint8List.fromList(List<int>.filled(32, 77));
      dbLocal
        ..marca = MarcaDbLocal.puesta
        ..archivo = true
        ..claveDelArchivo = dek
        ..dekEnAlmacen = dek
        ..envoltorio = (dek: dek, password: 'Vieja1234');
      vigencia = VigenciaEnMemoria();
    });

    /// El login que sigue a la recuperación, con la DB cerrada por la revocación de las sesiones.
    /// Por defecto, de la cuenta que se recuperó.
    Future<Either<Failure, ResultadoInicializacionDb>> entrarCon(String password, {String? de}) {
      dbLocal.abierta = false;
      final inicializar = InicializarDbLocalUseCase(dbLocal, vigencia, turno);
      final params = InicializarDbLocalParams(
        password: password,
        requiereEnvoltorio: true,
        usuarioId: de ?? 'usuario-a',
      );
      return inicializar(params);
    }

    /// Después falla el Keystore: el próximo inicio pide la contraseña (recuperación guiada de
    /// ADR-006), y se prueba con [password].
    Future<Either<Failure, Unit>> recuperarTrasFallarElKeystore(String password) async {
      dbLocal
        ..abierta = false
        ..fallas['leerDek'] = const FailureAlmacenSeguro();
      final inicializar = InicializarDbLocalUseCase(dbLocal, vigencia, turno);
      expect(
        await inicializar(const InicializarDbLocalParams(requiereEnvoltorio: true)),
        const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguroRecuperable()),
      );
      final recuperar = RecuperarDbLocalConPasswordUseCase(dbLocal, vigencia, turno);
      return recuperar(RecuperarDbLocalParams(password: password));
    }

    test('dado que Supabase aplica el cambio pero la respuesta se pierde y el colportor sale con '
        '"atrás", cuando entra con la contraseña nueva, la DEK queda envuelta con ella: si después '
        'falla el Keystore, esa contraseña recupera los datos', () async {
      recuperacion.fallaAlActualizar = const FailureSinConexion();
      expect(await conPassword('NuevaClave1'), const Left<Failure, Unit>(FailureSinConexion()));
      await AbandonarRecuperacionPasswordUseCase(recuperacion)(const NoParams());

      expect(await entrarCon('NuevaClave1'), abierta);

      expect(dbLocal.envoltorio!.password, 'NuevaClave1');
      expect(dbLocal.envoltorio!.dek, List<int>.filled(32, 77));
      expect(dbLocal.envoltorioDesactualizado, isFalse);
      expect(await recuperarTrasFallarElKeystore('NuevaClave1'), const Right<Failure, Unit>(unit));
      expect(dbLocal.abiertaCon!.bytes, List<int>.filled(32, 77));
    });

    test('dado que la app muere durante el Argon2id del re-envoltorio, el próximo login con la '
        'contraseña nueva la envuelve con ella', () async {
      dbLocal.argon2idPendiente = Completer<void>();
      unawaited(conPassword('NuevaClave1'));
      await dbLocal.pidioArgon2id.future;
      // La app muere: ese Argon2id no termina nunca, y la app que vuelve a abrir tiene otro turno.
      dbLocal.argon2idPendiente = null;
      turno = TurnoDbLocal();

      expect(await entrarCon('NuevaClave1'), abierta);
      expect(dbLocal.envoltorio!.password, 'NuevaClave1');
    });

    test('dado que el Keystore falla justo al re-envolver y después vuelve a responder, el próximo '
        'login con la contraseña nueva la envuelve con ella', () async {
      dbLocal.fallas['leerDek'] = const FailureAlmacenSeguro();
      expect(await conPassword('NuevaClave1'), const Right<Failure, Unit>(unit));
      dbLocal.fallas.remove('leerDek');

      expect(await entrarCon('NuevaClave1'), abierta);
      expect(dbLocal.envoltorio!.password, 'NuevaClave1');
    });

    test('dado que el almacén no deja leer la DEK y sigue sin responder, la contraseña igual '
        'cambió y rige la recuperación guiada en el próximo inicio: la contraseña anterior abre '
        'los datos, no se borra nada y el login siguiente renueva el envoltorio', () async {
      dbLocal.fallas['leerDek'] = const FailureAlmacenSeguro();

      expect(await conPassword('NuevaClave1'), const Right<Failure, Unit>(unit));
      expect(recuperacion.llamadas, ['actualizar', 'cerrarSesiones']);
      expect(dbLocal.envoltorio!.password, 'Vieja1234', reason: 'queda el envoltorio anterior');

      expect(
        await recuperarTrasFallarElKeystore('NuevaClave1'),
        const Left<Failure, Unit>(FailurePasswordNoAbreDatos()),
      );
      final recuperar = RecuperarDbLocalConPasswordUseCase(dbLocal, vigencia, turno);
      expect(
        await recuperar(const RecuperarDbLocalParams(password: 'Vieja1234')),
        const Right<Failure, Unit>(unit),
      );
      expect(dbLocal.abiertaCon!.bytes, List<int>.filled(32, 77));
      expect(dbLocal.archivo, isTrue);
      expect(dbLocal.envoltorioDesactualizado, isTrue);

      dbLocal.fallas.remove('leerDek');
      expect(await entrarCon('NuevaClave1'), abierta);
      expect(dbLocal.envoltorio!.password, 'NuevaClave1');
    });

    test('dado un cambio que el servidor rechaza, la marca queda: un intento anterior pudo haber '
        'entrado sin respuesta', () async {
      recuperacion.fallaAlActualizar = const FailureServidor();

      await conPassword('NuevaClave1');

      expect(dbLocal.envoltorioDesactualizado, isTrue);
      expect(dbLocal.envoltorio!.password, 'Vieja1234');
    });

    test('dado que A cambia su contraseña sin que se renueve el envoltorio y cierra sesión, cuando '
        'entra B con su contraseña, el envoltorio de A no se toca: lo renueva el próximo login de '
        'A', () async {
      recuperacion.fallaAlActualizar = const FailureSinConexion();
      await conPassword('NuevaClave1');

      expect(await entrarCon('ClaveDeB1', de: 'usuario-b'), abierta);

      expect(dbLocal.envoltorio!.password, 'Vieja1234', reason: 'nunca con la contraseña de B');
      expect(dbLocal.envoltorioDesactualizadoPara, 'usuario-a');
      expect(dbLocal.llamadas, contains('avisarOtraCuenta'));

      expect(await entrarCon('NuevaClave1'), abierta);
      expect(dbLocal.envoltorio!.password, 'NuevaClave1');
    });

    test('dado que el Keystore falla en el login con la contraseña nueva y la recuperación guiada '
        'abre con la anterior, el envoltorio se renueva ahí mismo con la del login', () async {
      recuperacion.fallaAlActualizar = const FailureSinConexion();
      await conPassword('NuevaClave1');
      dbLocal.fallas['leerDek'] = const FailureAlmacenSeguro();
      expect(
        await entrarCon('NuevaClave1'),
        const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguroRecuperable()),
      );

      final recuperar = RecuperarDbLocalConPasswordUseCase(dbLocal, vigencia, turno);
      const params = RecuperarDbLocalParams(
        password: 'Vieja1234',
        passwordDelLogin: 'NuevaClave1',
        usuarioId: 'usuario-a',
      );

      expect(await recuperar(params), const Right<Failure, Unit>(unit));
      expect(dbLocal.envoltorio!.password, 'NuevaClave1');
      expect(dbLocal.envoltorio!.dek, List<int>.filled(32, 77));
      expect(dbLocal.envoltorioDesactualizado, isFalse);
    });

    test('dada la recuperación guiada tras el login de otra cuenta, no renueva el envoltorio de '
        'A', () async {
      recuperacion.fallaAlActualizar = const FailureSinConexion();
      await conPassword('NuevaClave1');
      dbLocal.fallas['leerDek'] = const FailureAlmacenSeguro();

      final recuperar = RecuperarDbLocalConPasswordUseCase(dbLocal, vigencia, turno);
      const params = RecuperarDbLocalParams(
        password: 'Vieja1234',
        passwordDelLogin: 'ClaveDeB1',
        usuarioId: 'usuario-b',
      );

      expect(await recuperar(params), const Right<Failure, Unit>(unit));
      expect(dbLocal.envoltorio!.password, 'Vieja1234');
      expect(dbLocal.envoltorioDesactualizadoPara, 'usuario-a');
    });
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
          expect(dbLocal.llamadas, ['estado'], reason: 'sin DB local, solo mira si hay envoltorio');
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

  test('una mayúscula con tilde o Ñ cumple («Ñandú2026», «Élan2026»)', () async {
    for (final nueva in ['Ñandú2026', 'Élan2026']) {
      final r = await conPassword(nueva);

      expect(r, const Right<Failure, Unit>(unit), reason: nueva);
      expect(recuperacion.fijada, nueva);
    }
  });

  test('con 7 caracteres visibles (un emoji cuenta 1) la rechaza sin llamar al servidor', () async {
    final r = await conPassword('Ab1😀😀😀😀');

    expect(campos(r), {'password': PoliticaPassword.requisitos});
    expect(recuperacion.llamadas, isEmpty);
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
