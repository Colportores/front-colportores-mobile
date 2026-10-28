// HU-SYNC-004 — El estado del respaldo en Drive en la app: una sola operación a la vez, sin trabarse
// si algo falla, y por usuario.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../helpers/respaldo_drive_falsos.dart';

class _SesionFija extends SesionNotifier {
  _SesionFija(this._sesion);

  Sesion? _sesion;

  @override
  Future<Sesion?> build() async => _sesion;

  void cambiar(Sesion? nueva) {
    _sesion = nueva;
    state = AsyncData(nueva);
  }
}

Sesion _sesion(String usuarioId) => Sesion(
  usuarioId: usuarioId,
  email: 'ana@example.com',
  accessToken: 'jwt',
  expiraEn: DateTime.utc(2026, 10, 30),
);

void main() {
  late RespaldoDriveArmado a;
  late _SesionFija sesion;

  ProviderContainer armar({Sesion? con}) {
    a = RespaldoDriveArmado();
    sesion = _SesionFija(con ?? _sesion('u-1'));
    final c = ProviderContainer(
      overrides: [
        sesionProvider.overrideWith(() => sesion),
        respaldoDriveRepositoryProvider.overrideWithValue(a.repo),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<EstadoRespaldoDrive> leer(ProviderContainer c) async {
    await c.read(sesionProvider.future);
    return c.read(estadoRespaldoDriveProvider.future);
  }

  EstadoRespaldoDriveNotifier notifier(ProviderContainer c) =>
      c.read(estadoRespaldoDriveProvider.notifier);

  test('sin sesión, sin conectar', () async {
    final c = armar();
    await c.read(sesionProvider.future);
    sesion.cambiar(null);
    expect(await leer(c), isA<DriveSinConectar>());
    expect(await notifier(c).conectar(), isA<DriveOcupado>(), reason: 'sin usuario no hay a quién');
  });

  test('conectar deja el estado conectado y dice si hubo primer respaldo', () async {
    final c = armar();
    expect(await leer(c), isA<DriveSinConectar>());

    final r = await notifier(c).conectar();

    expect(r, isA<DriveQuedoConectado>());
    expect((r as DriveQuedoConectado).primerRespaldoHecho, isFalse);
    expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveConectada>());
  });

  test('doble toque: la segunda conexión no hace nada mientras la primera sigue', () async {
    final c = armar();
    await leer(c);
    final compuerta = Completer<void>();
    a.google.compuertaConectar = compuerta;

    final primera = notifier(c).conectar();
    await Future<void>.delayed(Duration.zero);
    final segunda = await notifier(c).conectar();
    final desconexion = await notifier(c).desconectar();

    expect(segunda, isA<DriveOcupado>());
    expect(desconexion, isA<DriveOcupado>());
    compuerta.complete();
    expect(await primera, isA<DriveQuedoConectado>());
    expect(a.google.conexiones, 1, reason: 'Google se abrió una sola vez');
  });

  test('Escenario: cancela en Google — no queda conectado y no queda nada trabado', () async {
    final c = armar();
    await leer(c);
    a.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);

    final r = await notifier(c).conectar();

    expect(r, isA<DriveNoQuedoConectado>());
    expect((r as DriveNoQuedoConectado).falla, isA<FailureDriveCancelado>());
    expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveSinConectar>());

    a.google.errorAlConectar = null;
    expect(await notifier(c).conectar(), isA<DriveQuedoConectado>(), reason: 'puede reintentar');
  });

  test('un error inesperado del repositorio no deja la operación trabada ni lanza', () async {
    final c = armar();
    await leer(c);
    a.almacen.alEscribir = true;

    final r = await notifier(c).conectar();

    expect(r, isA<DriveNoQuedoConectado>());
    expect((r as DriveNoQuedoConectado).falla, isA<FailureAlmacenSeguro>());
  });

  test(
    'desconectar vuelve a «sin conectar»; si falla, sigue conectado y se puede reintentar',
    () async {
      final c = armar();
      await leer(c);
      await notifier(c).conectar();

      a.almacen.alBorrar = true;
      final fallo = await notifier(c).desconectar();
      expect(fallo, isA<DriveNoQuedoDesconectado>());
      expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveConectada>());

      a.almacen.alBorrar = false;
      expect(await notifier(c).desconectar(), isA<DriveQuedoDesconectado>());
      expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveSinConectar>());
    },
  );

  test(
    'dos acciones seguidas: conectar y enseguida desconectar, la segunda espera su turno',
    () async {
      final c = armar();
      await leer(c);
      await notifier(c).conectar();
      final desconexion = notifier(c).desconectar();
      final otraConexion = await notifier(c).conectar();
      expect(otraConexion, isA<DriveOcupado>());
      expect(await desconexion, isA<DriveQuedoDesconectado>());
      expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveSinConectar>());
    },
  );

  test('si no se puede leer el estado, es un error en el estado y recargar lo reintenta', () async {
    final c = armar();
    await c.read(sesionProvider.future);
    a.almacen.alLeer = true;
    await expectLater(
      c.read(estadoRespaldoDriveProvider.future),
      throwsA(isA<FailureAlmacenSeguro>()),
    );
    expect(c.read(estadoRespaldoDriveProvider).hasError, isTrue);

    a.almacen.alLeer = false;
    await notifier(c).recargar();
    expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveSinConectar>());
  });

  test(
    'Escenario: acceso revocado desde Google — al abrir, la fila pasa a «Sin permiso»',
    () async {
      final c = armar();
      await a.repo.conectar('u-1');
      a.google.token = null;

      final inicial = await leer(c);
      expect(inicial, isA<DriveConectada>(), reason: 'primero lo guardado, sin esperar a Google');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(c.read(estadoRespaldoDriveProvider).value, isA<DrivePermisoRevocado>());
    },
  );

  test('el motor de respaldo marca permiso revocado, sin espacio y guardado', () async {
    final c = armar();
    await leer(c);
    await notifier(c).conectar();

    await notifier(c).sinEspacio();
    expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveSinEspacio>());
    await notifier(c).respaldoGuardado();
    expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveConectada>());
    await notifier(c).permisoRevocado();
    expect(c.read(estadoRespaldoDriveProvider).value, isA<DrivePermisoRevocado>());
  });

  test('otra persona en el mismo teléfono no hereda el Drive de la anterior', () async {
    final c = armar();
    await leer(c);
    await notifier(c).conectar();
    expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveConectada>());

    sesion.cambiar(_sesion('u-2'));
    expect(await c.read(estadoRespaldoDriveProvider.future), isA<DriveSinConectar>());

    sesion.cambiar(_sesion('u-1'));
    expect(await c.read(estadoRespaldoDriveProvider.future), isA<DriveConectada>());
  });

  test('tokenDriveProvider da el token del usuario con sesión, y null sin sesión', () async {
    final c = armar();
    await c.read(sesionProvider.future);
    await a.repo.conectar('u-1');
    expect(await c.read(tokenDriveProvider)(), 'ya29.token');

    sesion.cambiar(null);
    expect(await c.read(tokenDriveProvider)(), isNull);
  });

  test('el aviso de «cancelaste» se muestra y se oculta', () {
    final c = armar();
    expect(c.read(avisoDriveCanceladoProvider), isFalse);
    c.listen(avisoDriveCanceladoProvider, (_, _) {});
    c.read(avisoDriveCanceladoProvider.notifier).mostrar();
    expect(c.read(avisoDriveCanceladoProvider), isTrue);
    c.read(avisoDriveCanceladoProvider.notifier).ocultar();
    expect(c.read(avisoDriveCanceladoProvider), isFalse);
  });

  test('sin motor de sync (DB cerrada), no hay fecha de último respaldo', () async {
    final c = armar();
    await leer(c);
    c.listen(ultimoRespaldoDriveProvider, (_, _) {});
    expect(await c.read(ultimoRespaldoDriveProvider.future), isNull);
  });
}
