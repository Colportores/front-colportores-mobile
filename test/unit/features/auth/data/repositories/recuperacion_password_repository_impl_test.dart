// HU-AUTH-005 — repositorio de la confirmación de recuperación, contra el remoto en memoria.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/recuperacion_password_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/repositories/recuperacion_password_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/politica_password.dart';
import 'package:dartz/dartz.dart';
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
        expect(
          const FailureEnlaceRecuperacionVencido().mensaje,
          'El enlace expiró. Solicitá uno nuevo.',
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
      ]) {
        remoto.fallaAlActualizar = e;
        expect(
          (await repo.actualizarPassword('NuevaClave1')).fold((f) => f, (_) => null),
          isA<FailureInesperado>(),
        );
      }
    });
  });

  group('cerrarTodasLasSesiones y abandonar', () {
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
}

final class _RemotoRoto implements RecuperacionPasswordRemoteDataSource {
  @override
  Stream<EnlaceRecuperacion> get enlacesRecuperacion => const Stream.empty();

  @override
  Future<void> actualizarPassword(String nueva) async => throw StateError('boom');

  @override
  Future<void> cerrarTodasLasSesiones() async => throw StateError('boom');

  @override
  Future<void> abandonarRecuperacion() async {}
}
