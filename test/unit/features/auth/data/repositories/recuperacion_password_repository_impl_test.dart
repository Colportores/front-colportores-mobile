// HU-AUTH-005 — repositorio de la confirmación de recuperación, contra el remoto en memoria.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/recuperacion_password_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/repositories/recuperacion_password_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/politica_password.dart';
import 'package:dartz/dartz.dart';
import 'package:fake_async/fake_async.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

const _igualALaAnterior = FailureValidacion(
  campos: {'password': 'Tiene que ser distinta de la anterior.'},
);

class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  late RecuperacionPasswordEnMemoria remoto;
  late RecuperacionPasswordRepositoryImpl repo;

  setUp(() {
    remoto = RecuperacionPasswordEnMemoria(passwordActual: 'Vieja1234')
      ..simularEnlace(EnlaceRecuperacion.valido);
    repo = RecuperacionPasswordRepositoryImpl(remoto, logger: loggerMudo());
  });

  test('los enlaces del remoto llegan tal cual', () async {
    final futuro = repo.enlaces.first;

    remoto.simularEnlace(EnlaceRecuperacion.vencido);

    expect(await futuro, EnlaceRecuperacion.vencido);
  });

  test('el usuario es el de la sesión de recuperación; sin sesión, null (#125)', () {
    expect(repo.usuarioId, 'usuario-en-memoria');

    remoto.vencerSesionDeRecuperacion();

    expect(repo.usuarioId, isNull);
  });

  group('actualizarPassword', () {
    test(
      'con la sesión del enlace, fija la contraseña y deja el evento de la HU en el log',
      () async {
        final salida = _SalidaEnMemoria();
        repo = RecuperacionPasswordRepositoryImpl(remoto, logger: AppLogger(output: salida));

        expect(await repo.actualizarPassword('NuevaClave1'), const Right<Failure, Unit>(unit));
        expect(remoto.passwordActual, 'NuevaClave1');
        expect(salida.lineas.join('\n'), contains('password_reset_completed'));
        expect(salida.lineas.join('\n'), isNot(contains('NuevaClave1')));
      },
    );

    test(
      'dada la sesión del enlace vencida, devuelve el enlace vencido (texto de la HU)',
      () async {
        remoto.vencerSesionDeRecuperacion();

        expect(
          await repo.actualizarPassword('NuevaClave1'),
          const Left<Failure, Unit>(FailureEnlaceRecuperacionVencido()),
        );
        // No afirma «expiró»: Supabase no distingue vencido de usado (decisión del 02/10).
        expect(
          const FailureEnlaceRecuperacionVencido().mensaje,
          'Este enlace ya no sirve: venció o ya se usó. Solicitá uno nuevo.',
        );
      },
    );

    test('dada la misma contraseña que antes, lo dice en el campo', () async {
      expect(
        await repo.actualizarPassword('Vieja1234'),
        const Left<Failure, Unit>(_igualALaAnterior),
      );
    });

    group('caso borde: pérdida de conexión durante el cambio', () {
      test('dado que la respuesta se perdió pero Supabase aceptó el cambio, el reintento con la '
          'misma contraseña es un éxito y deja el evento en el log', () async {
        final salida = _SalidaEnMemoria();
        repo = RecuperacionPasswordRepositoryImpl(remoto, logger: AppLogger(output: salida));
        remoto.pierdeLaRespuestaAlActualizar = true;

        expect(
          await repo.actualizarPassword('NuevaClave1'),
          const Left<Failure, Unit>(FailureSinConexion()),
        );
        expect(salida.lineas.join('\n'), isNot(contains('password_reset_completed')));

        expect(await repo.actualizarPassword('NuevaClave1'), const Right<Failure, Unit>(unit));
        expect(remoto.passwordActual, 'NuevaClave1');
        expect(salida.lineas.join('\n'), contains('password_reset_completed'));
      });

      test('dado un corte, la contraseña anterior sigue sin poder repetirse', () async {
        remoto.simularSinConexion = true;
        await repo.actualizarPassword('NuevaClave1');
        remoto.simularSinConexion = false;

        expect(
          await repo.actualizarPassword('Vieja1234'),
          const Left<Failure, Unit>(_igualALaAnterior),
        );
      });

      test('el reintento vale una sola vez: después de una respuesta del servidor, igual a la '
          'anterior vuelve a ser un error', () async {
        remoto.pierdeLaRespuestaAlActualizar = true;
        await repo.actualizarPassword('NuevaClave1');
        await repo.actualizarPassword('NuevaClave1');

        expect(
          await repo.actualizarPassword('NuevaClave1'),
          const Left<Failure, Unit>(_igualALaAnterior),
        );
      });

      test('salir de la pantalla suelta el intento en duda', () async {
        remoto.pierdeLaRespuestaAlActualizar = true;
        await repo.actualizarPassword('NuevaClave1');
        await repo.abandonar();
        remoto.simularEnlace(EnlaceRecuperacion.valido);

        expect(
          await repo.actualizarPassword('NuevaClave1'),
          const Left<Failure, Unit>(_igualALaAnterior),
        );
      });

      test('una respuesta del servidor con otro error también lo suelta', () async {
        remoto.pierdeLaRespuestaAlActualizar = true;
        await repo.actualizarPassword('NuevaClave1');
        remoto.fallaAlActualizar = const ServidorException(status: 500);
        await repo.actualizarPassword('NuevaClave1');
        remoto.fallaAlActualizar = null;

        expect(
          await repo.actualizarPassword('NuevaClave1'),
          const Left<Failure, Unit>(_igualALaAnterior),
        );
      });
    });

    test('dada una contraseña que Supabase rechaza por larga (72 bytes), lo dice (#265; el tope '
        'en el formulario es #296)', () async {
      remoto.fallaAlActualizar = const PasswordDemasiadoLargaException();

      expect(
        await repo.actualizarPassword('NuevaClave1'),
        const Left<Failure, Unit>(
          FailureValidacion(campos: {'password': PoliticaPassword.demasiadoLarga}),
        ),
      );
    });

    test('dada una contraseña que Supabase considera débil, muestra la política', () async {
      remoto.fallaAlActualizar = const PasswordDebilException();

      expect(
        await repo.actualizarPassword('NuevaClave1'),
        const Left<Failure, Unit>(
          FailureValidacion(campos: {'password': PoliticaPassword.requisitos}),
        ),
      );
    });

    test('sin conexión o con el servidor en error, devuelve esa falla', () async {
      remoto.simularSinConexion = true;
      expect(
        await repo.actualizarPassword('NuevaClave1'),
        const Left<Failure, Unit>(FailureSinConexion()),
      );

      remoto
        ..simularSinConexion = false
        ..fallaAlActualizar = const ServidorException(status: 500, mensaje: 'algo');
      expect(
        await repo.actualizarPassword('NuevaClave1'),
        const Left<Failure, Unit>(FailureServidor(status: 500, mensaje: 'algo')),
      );

      remoto.fallaAlActualizar = const ServidorException(status: 502);
      expect(
        await repo.actualizarPassword('NuevaClave1'),
        const Left<Failure, Unit>(FailureServidor(status: 502)),
      );
    });

    test('dada una excepción que no es del remoto, devuelve inesperado', () async {
      final repoRoto = RecuperacionPasswordRepositoryImpl(_RemotoRoto(), logger: loggerMudo());

      expect(
        (await repoRoto.actualizarPassword('NuevaClave1')).fold((f) => f, (_) => null),
        isA<FailureInesperado>(),
      );
      expect(
        (await repoRoto.cerrarTodasLasSesiones()).fold((f) => f, (_) => null),
        isA<FailureInesperado>(),
      );
    });

    test('las excepciones que no son de este flujo salen como inesperado', () async {
      for (final e in const <AuthRemoteException>[
        CredencialesInvalidasException(),
        EmailYaRegistradoException(),
        SesionRevocadaException(),
      ]) {
        remoto.fallaAlActualizar = e;
        expect(
          (await repo.actualizarPassword('NuevaClave1')).fold((f) => f, (_) => null),
          isA<FailureInesperado>(),
        );
      }
    });

    group('sin respuesta del servidor (QA #224)', () {
      const tope = Duration(milliseconds: 20);

      setUp(() {
        remoto.demoraAlActualizar = Completer<void>();
        repo = RecuperacionPasswordRepositoryImpl(remoto, logger: loggerMudo(), tope: tope);
      });

      test('pasado el tope sale como sin conexión y queda en el log', () async {
        final salida = _SalidaEnMemoria();
        repo = RecuperacionPasswordRepositoryImpl(
          remoto,
          logger: AppLogger(output: salida),
          tope: tope,
        );

        expect(
          await repo.actualizarPassword('NuevaClave1'),
          const Left<Failure, Unit>(FailureSinConexion()),
        );
        final log = salida.lineas.join('\n');
        expect(log, contains('RECUPERACION_TIMEOUT'));
        expect(log, isNot(contains('NuevaClave1')));
      });

      test('el cambio pudo haber entrado: reintentar con la misma contraseña es éxito', () async {
        await repo.actualizarPassword('NuevaClave1');
        remoto.demoraAlActualizar!.complete();
        await Future<void>.delayed(Duration.zero);
        expect(remoto.passwordActual, 'NuevaClave1');

        expect(await repo.actualizarPassword('NuevaClave1'), const Right<Failure, Unit>(unit));
      });
    });
  });

  group('cerrarTodasLasSesiones y abandonar', () {
    test('si revocar no contesta, no deja la pantalla esperando: sale como falla', () async {
      remoto.demoraAlCerrarSesiones = Completer<void>();
      repo = RecuperacionPasswordRepositoryImpl(
        remoto,
        logger: loggerMudo(),
        tope: const Duration(milliseconds: 20),
      );

      expect(await repo.cerrarTodasLasSesiones(), isA<Left<Failure, Unit>>());
    });

    test('revocan en el remoto', () async {
      expect(await repo.cerrarTodasLasSesiones(), const Right<Failure, Unit>(unit));
      expect(await repo.abandonar(), const Right<Failure, Unit>(unit));
      expect(remoto.sesionesCerradas, 1);
      expect(remoto.abandonos, 1);
    });

    test('dada una falla al revocar, la deja en el log y la devuelve', () async {
      final salida = _SalidaEnMemoria();
      repo = RecuperacionPasswordRepositoryImpl(remoto, logger: AppLogger(output: salida));
      remoto.fallaAlCerrarSesiones = const SinConexionException();

      expect(await repo.cerrarTodasLasSesiones(), const Left<Failure, Unit>(FailureSinConexion()));
      expect(salida.lineas.join('\n'), contains('RECUPERACION_REVOCAR_FAIL'));
    });
  });

  group('las otras sesiones que no se cerraron (decisión del 29/10 en #542)', () {
    test('dado que revocar sale bien, cuando se pregunta, no queda nada pendiente', () async {
      expect(await repo.cerrarTodasLasSesiones(), const Right<Failure, Unit>(unit));

      expect(repo.otrasSesionesSinCerrar, isFalse);
      expect(await repo.cerrarOtrasSesionesPendientes(), const Right<Failure, Unit>(unit));
      expect(remoto.otrasSesionesCerradas, 0, reason: 'sin pendiente no se llama al servidor');
    });

    test(
      'dado que revocar falla, cuando se reintenta con red, cierra las otras y baja la marca',
      () async {
        remoto.fallaAlCerrarSesiones = const SinConexionException();
        await repo.cerrarTodasLasSesiones();
        expect(repo.otrasSesionesSinCerrar, isTrue);

        remoto.fallaAlCerrarSesiones = null;
        expect(await repo.cerrarOtrasSesionesPendientes(), const Right<Failure, Unit>(unit));

        expect(remoto.otrasSesionesCerradas, 1);
        expect(repo.otrasSesionesSinCerrar, isFalse);
        expect(await repo.cerrarOtrasSesionesPendientes(), const Right<Failure, Unit>(unit));
        expect(remoto.otrasSesionesCerradas, 1, reason: 'no se repite una vez resuelto');
      },
    );

    test('dado que revocar no contesta, cuando pasa el tope, queda pendiente', () async {
      remoto.demoraAlCerrarSesiones = Completer<void>();
      repo = RecuperacionPasswordRepositoryImpl(
        remoto,
        logger: loggerMudo(),
        tope: const Duration(milliseconds: 20),
      );

      expect(await repo.cerrarTodasLasSesiones(), isA<Left<Failure, Unit>>());

      expect(repo.otrasSesionesSinCerrar, isTrue);
    });

    test('dado que el reintento también falla, cuando vuelve a entrar, la marca sigue para el '
        'próximo login', () async {
      remoto.fallaAlCerrarSesiones = const SinConexionException();
      await repo.cerrarTodasLasSesiones();
      remoto.fallaAlCerrarLasOtras = const SinConexionException();

      expect(
        await repo.cerrarOtrasSesionesPendientes(),
        const Left<Failure, Unit>(FailureSinConexion()),
      );
      expect(repo.otrasSesionesSinCerrar, isTrue);

      remoto.fallaAlCerrarLasOtras = null;
      expect(await repo.cerrarOtrasSesionesPendientes(), const Right<Failure, Unit>(unit));
      expect(repo.otrasSesionesSinCerrar, isFalse);
    });
  });

  group('un cambio de contraseña espera al anterior que sigue en el aire (QA de #542)', () {
    const tope = Duration(milliseconds: 100);

    test('dado A varada pasado el tope y B enseguida, cuando A contesta, el servidor las ve en el '
        'orden A y B y queda B', () async {
      final varada = Completer<void>();
      remoto.demoraAlActualizar = varada;
      repo = RecuperacionPasswordRepositoryImpl(remoto, logger: loggerMudo(), tope: tope);

      final a = await repo.actualizarPassword('ClaveAaaa1');
      expect(a, const Left<Failure, Unit>(FailureSinConexion()));

      final b = repo.actualizarPassword('ClaveBbbb1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(remoto.actualizaciones, isEmpty, reason: 'B espera a que A conteste');

      varada.complete();
      expect(await b, const Right<Failure, Unit>(unit));

      expect(remoto.actualizaciones, ['ClaveAaaa1', 'ClaveBbbb1']);
      expect(remoto.passwordActual, 'ClaveBbbb1');
    });

    test('dado A que falla con error, cuando llega B, B sale sin esperar al tope', () async {
      remoto.fallaAlActualizar = const PasswordDebilException();
      repo = RecuperacionPasswordRepositoryImpl(remoto, logger: loggerMudo(), tope: tope);
      await repo.actualizarPassword('flojo');
      remoto.fallaAlActualizar = null;

      final reloj = Stopwatch()..start();
      final b = await repo.actualizarPassword('ClaveBbbb1');

      expect(b, const Right<Failure, Unit>(unit));
      expect(reloj.elapsed, lessThan(tope));
      expect(remoto.actualizaciones, ['ClaveBbbb1']);
    });

    test('dado A que no contesta ni pasado otro tope, cuando llega B, B sale igual', () async {
      remoto.demoraAlActualizar = Completer<void>();
      repo = RecuperacionPasswordRepositoryImpl(remoto, logger: loggerMudo(), tope: tope);
      await repo.actualizarPassword('ClaveAaaa1');
      remoto.demoraAlActualizar = null;

      final b = await repo.actualizarPassword('ClaveBbbb1');

      expect(b, const Right<Failure, Unit>(unit));
      expect(remoto.actualizaciones, ['ClaveBbbb1']);
    });
  });

  group('el tope por defecto es de 15 s (decisión del 29/10 en #542)', () {
    test('cambiar la contraseña sin respuesta sale como sin conexión a los 15 s, no antes', () {
      expect(RecuperacionPasswordRepositoryImpl.topePorDefecto, const Duration(seconds: 15));
      fakeAsync((reloj) {
        remoto.demoraAlActualizar = Completer<void>();
        final porDefecto = RecuperacionPasswordRepositoryImpl(remoto, logger: loggerMudo());
        Either<Failure, Unit>? resultado;
        unawaited(porDefecto.actualizarPassword('NuevaClave1').then((r) => resultado = r));

        reloj.elapse(const Duration(seconds: 14));
        expect(resultado, isNull);
        reloj.elapse(const Duration(seconds: 2));
        expect(resultado, const Left<Failure, Unit>(FailureSinConexion()));
      });
    });

    test('revocar las sesiones sin respuesta también corta a los 15 s', () {
      fakeAsync((reloj) {
        remoto.demoraAlCerrarSesiones = Completer<void>();
        final porDefecto = RecuperacionPasswordRepositoryImpl(remoto, logger: loggerMudo());
        Either<Failure, Unit>? resultado;
        unawaited(porDefecto.cerrarTodasLasSesiones().then((r) => resultado = r));

        reloj.elapse(const Duration(seconds: 14));
        expect(resultado, isNull);
        reloj.elapse(const Duration(seconds: 2));
        expect(resultado, isA<Left<Failure, Unit>>());
      });
    });
  });

  group('enlaces: el vencido y el ya usado son lo mismo (15-A06)', () {
    /// Lo que el repositorio entrega para los próximos [cuantos] enlaces que llegan al remoto.
    Future<List<EnlaceRecuperacion>> llegan(int cuantos, List<EnlaceRecuperacion> enlaces) async {
      final futuro = repo.enlaces.take(cuantos).toList();
      enlaces.forEach(remoto.simularEnlace);
      return futuro;
    }

    test('con un cambio recién completado, el enlace rechazado sigue siendo «vencido»: no se '
        'adivina que ya se usó', () async {
      await repo.actualizarPassword('NuevaClave1');

      expect(await llegan(1, [EnlaceRecuperacion.vencido]), [EnlaceRecuperacion.vencido]);
    });

    test('los enlaces llegan en el mismo orden, sin tocarlos', () async {
      expect(
        await llegan(3, [
          EnlaceRecuperacion.vencido,
          EnlaceRecuperacion.valido,
          EnlaceRecuperacion.sinConexion,
        ]),
        [EnlaceRecuperacion.vencido, EnlaceRecuperacion.valido, EnlaceRecuperacion.sinConexion],
      );
    });
  });
}

final class _RemotoRoto implements RecuperacionPasswordRemoteDataSource {
  @override
  Stream<EnlaceRecuperacion> get enlacesRecuperacion => const Stream.empty();

  @override
  String? get usuarioDeLaRecuperacion => null;

  @override
  Future<void> actualizarPassword(String nueva) async => throw StateError('boom');

  @override
  Future<void> cerrarTodasLasSesiones() async => throw StateError('boom');

  @override
  Future<void> cerrarLasOtrasSesiones() async => throw StateError('boom');

  @override
  Future<void> abandonarRecuperacion() async {}
}
