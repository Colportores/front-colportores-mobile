// QA de #542 (PR #556), delta 5abee68..48489c2: la marca en memoria de «reintentar el scope
// `others` al próximo login» queda atada a la cuenta que cambió la contraseña. Prueba dos cambios
// seguidos de cuentas distintas en el mismo teléfono, el reintento solo de la dueña y que la marca
// no se pierda ni se consuma de más.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/recuperacion_password_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

const _ana = 'id-de-ana';
const _beto = 'id-de-beto';
const Right<Failure, Unit> _ok = Right(unit);

void main() {
  late RecuperacionPasswordEnMemoria remoto;
  late RecuperacionPasswordRepositoryImpl repo;

  setUp(() {
    remoto = RecuperacionPasswordEnMemoria();
    repo = RecuperacionPasswordRepositoryImpl(remoto, logger: loggerMudo());
  });

  /// Un cambio de contraseña de [cuenta] en este teléfono: llega el enlace y la revocación global
  /// sale bien o falla.
  Future<void> cambiarContrasena(String cuenta, {required bool revocaBien}) async {
    remoto
      ..usuarioId = cuenta
      ..simularEnlace(EnlaceRecuperacion.valido)
      ..fallaAlCerrarSesiones = revocaBien ? null : const SinConexionException();
    await repo.cerrarTodasLasSesiones();
  }

  group('marca atada a la cuenta', () {
    test('dado que la marca es de ana, cuando entra beto, no revoca nada y la marca sigue; '
        'cuando entra ana, reintenta una sola vez', () async {
      await cambiarContrasena(_ana, revocaBien: false);
      remoto.fallaAlCerrarSesiones = null;

      expect(await repo.cerrarOtrasSesionesPendientes(_beto), _ok);
      expect(await repo.cerrarOtrasSesionesPendientes(_beto), _ok);
      expect(remoto.otrasSesionesCerradas, 0);
      expect(repo.otrasSesionesSinCerrar, isTrue);

      expect(await repo.cerrarOtrasSesionesPendientes(_ana), _ok);
      expect(await repo.cerrarOtrasSesionesPendientes(_ana), _ok);
      expect(remoto.otrasSesionesCerradas, 1, reason: 'se consume una vez');
      expect(repo.otrasSesionesSinCerrar, isFalse);
    });

    test('dado que el reintento de ana falla, cuando entra otra vez ana, la marca sigue y vuelve a '
        'intentar (no se consume por intentar)', () async {
      await cambiarContrasena(_ana, revocaBien: false);
      remoto.fallaAlCerrarLasOtras = const SinConexionException();

      expect(await repo.cerrarOtrasSesionesPendientes(_ana), isA<Left<Failure, Unit>>());
      expect(repo.otrasSesionesSinCerrar, isTrue);

      remoto.fallaAlCerrarLasOtras = null;
      expect(await repo.cerrarOtrasSesionesPendientes(_ana), _ok);
      expect(remoto.otrasSesionesCerradas, 1);
    });

    test('dado que ana quedó pendiente, cuando ana cambia otra vez la contraseña y la revocación '
        'global sale bien, la marca baja y el login ya no reintenta', () async {
      await cambiarContrasena(_ana, revocaBien: false);

      await cambiarContrasena(_ana, revocaBien: true);

      expect(repo.otrasSesionesSinCerrar, isFalse);
      expect(await repo.cerrarOtrasSesionesPendientes(_ana), _ok);
      expect(remoto.otrasSesionesCerradas, 0);
    });

    test('dado que la marca es de ana, cuando beto entra y sale varias veces, no se la lleva ni la '
        'deja colgada: ana la consume al volver', () async {
      await cambiarContrasena(_ana, revocaBien: false);
      remoto.fallaAlCerrarSesiones = null;

      for (var i = 0; i < 3; i++) {
        await repo.cerrarOtrasSesionesPendientes(_beto);
      }

      expect(repo.otrasSesionesSinCerrar, isTrue);
      expect(await repo.cerrarOtrasSesionesPendientes(_ana), _ok);
      expect(remoto.otrasSesionesCerradas, 1);
      expect(repo.otrasSesionesSinCerrar, isFalse);
    });
  });

  group('dos cambios seguidos de cuentas distintas, sin que nadie entre en el medio', () {
    // Hallazgo menor: la marca es una sola. Un segundo cambio (de beto) la pisa: si beto revoca
    // bien la baja a `null` y si falla la reemplaza por la suya. En los dos casos ana pierde el
    // reintento que le prometió su pantalla de éxito.
    test(
      'dado que ana quedó pendiente, cuando beto cambia la suya y la revocación sale bien, la '
      'marca de ana sigue y se reintenta cuando ana entra',
      () async {
        await cambiarContrasena(_ana, revocaBien: false);
        await cambiarContrasena(_beto, revocaBien: true);

        expect(await repo.cerrarOtrasSesionesPendientes(_ana), _ok);

        expect(remoto.otrasSesionesCerradas, 1, reason: 'ana tenía sesiones sin cerrar');
      },
      skip:
          'QA #542: la marca es una sola; un cambio de otra cuenta (que revoca bien) borra la de '
          'ana y ella pierde el reintento que le prometió su pantalla',
    );

    test(
      'dado que ana quedó pendiente, cuando beto cambia la suya y la revocación también falla, '
      'cada cuenta reintenta al entrar',
      () async {
        await cambiarContrasena(_ana, revocaBien: false);
        await cambiarContrasena(_beto, revocaBien: false);
        remoto
          ..fallaAlCerrarSesiones = null
          ..fallaAlCerrarLasOtras = null;

        await repo.cerrarOtrasSesionesPendientes(_ana);
        await repo.cerrarOtrasSesionesPendientes(_beto);

        expect(remoto.otrasSesionesCerradas, 2);
      },
      skip:
          'QA #542: la marca es una sola; la de beto reemplaza a la de ana y ella pierde el '
          'reintento',
    );
  });
}
