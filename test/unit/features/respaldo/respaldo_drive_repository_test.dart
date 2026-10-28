// HU-SYNC-004 — Autorizar Google Drive: el repositorio que guarda la cuenta conectada y su estado.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart';
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/domain/repositories/respaldo_drive_repository.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../../helpers/respaldo_drive_falsos.dart';

EstadoRespaldoDrive _estado(Either<Failure, EstadoRespaldoDrive> r) =>
    r.fold((f) => throw StateError('falló: $f'), (e) => e);

Failure _falla<T>(Either<Failure, T> r) => r.fold((f) => f, (_) => throw StateError('no falló'));

void main() {
  late RespaldoDriveArmado a;

  setUp(() => a = RespaldoDriveArmado());

  group('estado', () {
    test('sin nada guardado, sin conectar', () async {
      expect(_estado(await a.repo.estado('u-1')), isA<DriveSinConectar>());
    });

    test('un valor ilegible cuenta como sin conectar y no rompe', () async {
      await a.almacen.escribir(ClaveSegura.respaldoDrive, '{esto no es json');
      expect(_estado(await a.repo.estado('u-1')), isA<DriveSinConectar>());
      await a.almacen.escribir(ClaveSegura.respaldoDrive, '[1, 2]');
      expect(_estado(await a.repo.estado('u-1')), isA<DriveSinConectar>());
      await a.almacen.escribir(
        ClaveSegura.respaldoDrive,
        jsonEncode({
          'u-1': {'email': 7},
          'u-2': 'x',
          'u-3': {'email': '', 'id': 'g', 'estado': 'conectada'},
        }),
      );
      for (final u in ['u-1', 'u-2', 'u-3']) {
        expect(_estado(await a.repo.estado(u)), isA<DriveSinConectar>());
      }
    });

    test('si el almacén no se deja leer, es una falla y no «sin conectar»', () async {
      final roto = RespaldoDriveArmado();
      roto.almacen.alLeer = true;
      expect(_falla(await roto.repo.estado('u-1')), isA<FailureAlmacenSeguro>());
    });
  });

  group('conectar', () {
    test('Escenario: Autorización exitosa — guarda la cuenta, sin ningún token', () async {
      final r = await a.repo.conectar('u-1');
      final conexion = r.fold((f) => throw StateError('$f'), (c) => c);

      expect(conexion.estado.email, 'ana.gomez@gmail.com');
      expect(conexion.estado, isA<DriveConectada>());
      expect(_estado(await a.repo.estado('u-1')), isA<DriveConectada>());
      expect(a.google.conexiones, 1);
      expect(a.guardado, isNot(contains('ya29')), reason: 'el token no se guarda');
      final json = jsonDecode(a.guardado!) as Map<String, dynamic>;
      expect((json['u-1'] as Map<String, dynamic>).keys, containsAll(['email', 'id', 'estado']));
    });

    test('el primer respaldo hecho se informa; el que no sale, no rompe la conexión', () async {
      final primero = PrimerRespaldoFalso();
      final con = RespaldoDriveArmado(primerRespaldo: primero);
      var c = (await con.repo.conectar('u-1')).fold((f) => throw StateError('$f'), (c) => c);
      expect(c.primerRespaldoHecho, isTrue);

      primero.resultado = false;
      c = (await con.repo.conectar('u-1')).fold((f) => throw StateError('$f'), (c) => c);
      expect(c.primerRespaldoHecho, isFalse);

      primero.error = StateError('Drive caído');
      c = (await con.repo.conectar('u-1')).fold((f) => throw StateError('$f'), (c) => c);
      expect(
        c.primerRespaldoHecho,
        isFalse,
        reason: 'un error al respaldar no deshace la conexión',
      );
      expect(_estado(await con.repo.estado('u-1')), isA<DriveConectada>());
    });

    test('sin motor de respaldo todavía, el primer respaldo no se dice hecho', () async {
      final c = (await a.repo.conectar('u-1')).fold((f) => throw StateError('$f'), (c) => c);
      expect(c.primerRespaldoHecho, isFalse);
    });

    test('Escenario: la persona cierra la pantalla de Google — cancelado, nada guardado', () async {
      a.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);
      expect(_falla(await a.repo.conectar('u-1')), isA<FailureDriveCancelado>());
      expect(a.guardado, isNull);
      expect(_estado(await a.repo.estado('u-1')), isA<DriveSinConectar>());
    });

    test('la persona no dejó marcado el permiso de Drive: se lo dice y no guarda', () async {
      a.google.errorAlConectar = const PermisoDriveNoConcedido();
      expect(_falla(await a.repo.conectar('u-1')), isA<FailureDrivePermisoIncompleto>());
      expect(a.guardado, isNull);
    });

    test('sin red, sin conexión', () async {
      for (final error in <Object>[
        const SocketException('sin red'),
        http.ClientException('sin red'),
        TimeoutException('lento'),
      ]) {
        a.google.errorAlConectar = error;
        expect(_falla(await a.repo.conectar('u-1')), isA<FailureSinConexion>());
      }
      expect(a.guardado, isNull);
    });

    test('cualquier otra falla de Google: «No pudimos conectar tu Drive»', () async {
      for (final error in <Object>[
        falloDeGoogle(GoogleSignInExceptionCode.clientConfigurationError),
        falloDeGoogle(GoogleSignInExceptionCode.unknownError),
        StateError('rara'),
      ]) {
        a.google.errorAlConectar = error;
        final f = _falla(await a.repo.conectar('u-1'));
        expect(f, isA<FailureDriveNoConectado>());
        expect(f.mensaje, 'No pudimos conectar tu Drive. Probá de nuevo.');
      }
    });

    test('si el almacén no deja guardar, retira el permiso en Google y avisa', () async {
      final roto = RespaldoDriveArmado();
      roto.almacen.alEscribir = true;
      expect(_falla(await roto.repo.conectar('u-1')), isA<FailureDriveNoConectado>());
      expect(roto.google.desconexiones, 1, reason: 'no queda un permiso suelto en Google');
      expect(roto.almacen.contenido[ClaveSegura.respaldoDrive], isNull);
    });

    test('reconectar pisa el estado «Sin permiso» y la cuenta anterior', () async {
      await a.repo.conectar('u-1');
      await a.repo.marcarPermisoRevocado('u-1');
      a.google.cuenta = const CuentaGoogle(id: 'g-200', email: 'otra@gmail.com');

      final c = (await a.repo.conectar('u-1')).fold((f) => throw StateError('$f'), (c) => c);
      expect(c.estado.email, 'otra@gmail.com');
      expect(_estado(await a.repo.estado('u-1')), isA<DriveConectada>());
    });

    test('el valor ilegible se pisa al conectar', () async {
      await a.almacen.escribir(ClaveSegura.respaldoDrive, 'basura');
      await a.repo.conectar('u-1');
      expect(_estado(await a.repo.estado('u-1')), isA<DriveConectada>());
    });

    test('dos conectar seguidos se serializan: cada uno ve el anterior terminado', () async {
      final compuerta = Completer<void>();
      a.google.compuertaConectar = compuerta;
      final primero = a.repo.conectar('u-1');
      final lectura = a.repo.estado('u-1');
      await Future<void>.delayed(Duration.zero);
      expect(a.google.conexiones, 1);
      compuerta.complete();
      await primero;
      expect(_estado(await lectura), isA<DriveConectada>(), reason: 'la lectura espera al cambio');
    });

    test('una falla no traba la cola: la operación siguiente corre', () async {
      a.google.errorAlConectar = StateError('rara');
      expect(_falla(await a.repo.conectar('u-1')), isA<FailureDriveNoConectado>());
      a.google.errorAlConectar = null;
      expect((await a.repo.conectar('u-1')).isRight(), isTrue);
    });
  });

  group('por usuario', () {
    test('Drive de un usuario no es el de otro en el mismo teléfono', () async {
      await a.repo.conectar('u-1');
      expect(_estado(await a.repo.estado('u-2')), isA<DriveSinConectar>());

      a.google.cuenta = const CuentaGoogle(id: 'g-300', email: 'beto@gmail.com');
      await a.repo.conectar('u-2');
      expect((_estado(await a.repo.estado('u-1')) as DriveConectada).email, 'ana.gomez@gmail.com');
      expect((_estado(await a.repo.estado('u-2')) as DriveConectada).email, 'beto@gmail.com');

      await a.repo.desconectar('u-1');
      expect(_estado(await a.repo.estado('u-1')), isA<DriveSinConectar>());
      expect(_estado(await a.repo.estado('u-2')), isA<DriveConectada>(), reason: 'el otro sigue');
    });
  });

  group('desconectar', () {
    test('Escenario: revocar desde Configuración — olvida la cuenta y retira el permiso', () async {
      await a.repo.conectar('u-1');
      final r = await a.repo.desconectar('u-1');

      expect(r.isRight(), isTrue);
      expect(_estado(await a.repo.estado('u-1')), isA<DriveSinConectar>());
      expect(a.google.desconexiones, 1);
      expect(a.guardado, isNull, reason: 'sin cuentas, la clave se borra');
    });

    test('si Google no deja retirar el permiso, igual queda desconectado en la app', () async {
      await a.repo.conectar('u-1');
      a.google.errorAlDesconectar = const SocketException('sin red');
      expect((await a.repo.desconectar('u-1')).isRight(), isTrue);
      expect(_estado(await a.repo.estado('u-1')), isA<DriveSinConectar>());
    });

    test('retirarPermisoGoogle pide el retiro a Google y deja la cuenta guardada', () async {
      await a.repo.conectar('u-1');
      await a.repo.retirarPermisoGoogle();

      expect(a.google.desconexiones, 1);
      expect(_estado(await a.repo.estado('u-1')), isA<DriveConectada>());
    });

    test('retirarPermisoGoogle no lanza si Google falla', () async {
      a.google.errorAlDesconectar = const SocketException('sin red');
      await a.repo.retirarPermisoGoogle();
      expect(a.google.desconexiones, 1, reason: 'lo intentó, falló y no lanzó');
    });

    test('desconectar sin haber conectado no falla', () async {
      expect((await a.repo.desconectar('u-1')).isRight(), isTrue);
    });

    test('si el almacén no deja borrar, falla y la cuenta sigue conectada', () async {
      final roto = RespaldoDriveArmado();
      await roto.repo.conectar('u-1');
      roto.almacen.alEscribir = true;
      roto.almacen.alBorrar = true;
      expect(_falla(await roto.repo.desconectar('u-1')), isA<FailureAlmacenSeguro>());
      expect(
        roto.google.desconexiones,
        0,
        reason: 'primero se olvida acá; si no se pudo, no sigue',
      );
      roto.almacen.alEscribir = false;
      roto.almacen.alBorrar = false;
      expect(_estado(await roto.repo.estado('u-1')), isA<DriveConectada>());
    });
  });

  group('estados que cambian solos', () {
    test('Escenario: acceso revocado desde Google — pasa a «Reconectar» y se queda', () async {
      await a.repo.conectar('u-1');
      final r = _estado(await a.repo.marcarPermisoRevocado('u-1'));
      expect(r, isA<DrivePermisoRevocado>());
      expect((r as DrivePermisoRevocado).email, 'ana.gomez@gmail.com');
      expect(_estado(await a.repo.estado('u-1')), isA<DrivePermisoRevocado>());
      // Dos veces no cambia nada.
      expect(_estado(await a.repo.marcarPermisoRevocado('u-1')), isA<DrivePermisoRevocado>());
    });

    test('sin cuenta, marcar no inventa una', () async {
      expect(_estado(await a.repo.marcarPermisoRevocado('u-1')), isA<DriveSinConectar>());
      expect(_estado(await a.repo.marcarSinEspacio('u-1')), isA<DriveSinConectar>());
      expect(a.guardado, isNull);
    });

    test('sin espacio y de vuelta; «sin espacio» no pisa un permiso revocado', () async {
      await a.repo.conectar('u-1');
      expect(_estado(await a.repo.marcarSinEspacio('u-1')), isA<DriveSinEspacio>());
      expect(_estado(await a.repo.marcarRespaldoGuardado('u-1')), isA<DriveConectada>());

      await a.repo.marcarPermisoRevocado('u-1');
      expect(_estado(await a.repo.marcarSinEspacio('u-1')), isA<DrivePermisoRevocado>());
      expect(_estado(await a.repo.marcarRespaldoGuardado('u-1')), isA<DrivePermisoRevocado>());
    });

    test('un respaldo guardado no cambia una cuenta que ya estaba bien', () async {
      await a.repo.conectar('u-1');
      expect(_estado(await a.repo.marcarRespaldoGuardado('u-1')), isA<DriveConectada>());
    });
  });

  group('verificarPermiso', () {
    test('con el permiso vigente no cambia nada', () async {
      await a.repo.conectar('u-1');
      expect(_estado(await a.repo.verificarPermiso('u-1')), isA<DriveConectada>());
    });

    test('si Google ya no da token, pasa a «Sin permiso»', () async {
      await a.repo.conectar('u-1');
      a.google.token = null;
      expect(_estado(await a.repo.verificarPermiso('u-1')), isA<DrivePermisoRevocado>());
      expect(_estado(await a.repo.estado('u-1')), isA<DrivePermisoRevocado>());
    });

    test('también mira cuando el Drive estaba lleno', () async {
      await a.repo.conectar('u-1');
      await a.repo.marcarSinEspacio('u-1');
      a.google.token = null;
      expect(_estado(await a.repo.verificarPermiso('u-1')), isA<DrivePermisoRevocado>());
    });

    test('sin red no concluye que el permiso se perdió', () async {
      await a.repo.conectar('u-1');
      a.google.errorAlPedirToken = const SocketException('sin red');
      expect(_estado(await a.repo.verificarPermiso('u-1')), isA<DriveConectada>());
    });

    test(
      'si desconectaron mientras Google tardaba, devuelve lo de ahora y no resucita nada',
      () async {
        await a.repo.conectar('u-1');
        final compuerta = Completer<void>();
        a.google.compuertaToken = compuerta;
        final verificacion = a.repo.verificarPermiso('u-1');
        await pumpEventQueue();

        await a.repo.desconectar('u-1');
        compuerta.complete();

        expect(_estado(await verificacion), isA<DriveSinConectar>());
        expect(_estado(await a.repo.estado('u-1')), isA<DriveSinConectar>());
      },
    );

    test('sin token tras una conexión nueva con otra cuenta: no marca la cuenta nueva', () async {
      await a.repo.conectar('u-1');
      final compuerta = Completer<void>();
      a.google.compuertaToken = compuerta;
      a.google.token = null;
      final verificacion = a.repo.verificarPermiso('u-1');
      await pumpEventQueue();

      await a.repo.desconectar('u-1');
      a.google.cuenta = const CuentaGoogle(id: 'g-200', email: 'otra@gmail.com');
      await a.repo.conectar('u-1');
      compuerta.complete();

      final resultado = _estado(await verificacion);
      expect(resultado, isA<DriveConectada>());
      expect((resultado as DriveConectada).cuentaId, 'g-200');
      expect(_estado(await a.repo.estado('u-1')), isA<DriveConectada>());
    });

    test('marcarPermisoRevocado con otra cuenta no toca la guardada', () async {
      await a.repo.conectar('u-1');
      final r = _estado(await a.repo.marcarPermisoRevocado('u-1', cuentaId: 'g-999'));
      expect(r, isA<DriveConectada>());
    });

    test('sin cuenta o ya revocado no le pregunta a Google', () async {
      expect(_estado(await a.repo.verificarPermiso('u-1')), isA<DriveSinConectar>());
      await a.repo.conectar('u-1');
      await a.repo.marcarPermisoRevocado('u-1');
      final antes = a.google.pedidosDeToken;
      expect(_estado(await a.repo.verificarPermiso('u-1')), isA<DrivePermisoRevocado>());
      expect(a.google.pedidosDeToken, antes);
    });
  });

  group('tokenDeAcceso (lo usará el respaldo nocturno)', () {
    test('conectado, da el token pedido en silencio', () async {
      await a.repo.conectar('u-1');
      expect(await a.repo.tokenDeAcceso('u-1'), 'ya29.token');
    });

    test('sin cuenta no hay token ni se le pide a Google', () async {
      expect(await a.repo.tokenDeAcceso('u-1'), isNull);
      expect(a.google.pedidosDeToken, 0);
    });

    test('si Google ya no lo da, queda «Sin permiso» (401 → Reconectar Drive)', () async {
      await a.repo.conectar('u-1');
      a.google.token = null;
      expect(await a.repo.tokenDeAcceso('u-1'), isNull);
      expect(_estado(await a.repo.estado('u-1')), isA<DrivePermisoRevocado>());
    });

    test('un error de red da null sin cambiar el estado', () async {
      await a.repo.conectar('u-1');
      a.google.errorAlPedirToken = const SocketException('sin red');
      expect(await a.repo.tokenDeAcceso('u-1'), isNull);
      expect(_estado(await a.repo.estado('u-1')), isA<DriveConectada>());
    });
  });

  test('PrimerRespaldoSinMotor no hace nada', () async {
    expect(await const PrimerRespaldoSinMotor().hacer(), isFalse);
  });
}
