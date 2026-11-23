// #550 (HU-SYNC-004) — El repositorio del respaldo en Drive con otra cuenta de Google (vista 16,
// 16E·01 a 16E·04) y con la franja del Drive de Hoy oculta hasta mañana (16F·04).
import 'dart:convert';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart';
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../helpers/respaldo_drive_falsos.dart';

const _otra = CuentaGoogle(id: 'g-200', email: 'ana.casa@gmail.com');
const _tercera = CuentaGoogle(id: 'g-300', email: 'ana.trabajo@gmail.com');

T _derecha<T>(Either<Failure, T> r) => r.fold((f) => throw StateError('falló: $f'), (v) => v);

Failure _falla<T>(Either<Failure, T> r) => r.fold((f) => f, (_) => throw StateError('no falló'));

Future<EstadoRespaldoDrive> _estado(RespaldoDriveArmado a) async =>
    _derecha(await a.repo.estado('u-1'));

void main() {
  late PrimerRespaldoFalso primero;
  late RespaldoDriveArmado a;
  var ahora = DateTime(2026, 11, 20, 22, 30);

  setUp(() {
    primero = PrimerRespaldoFalso();
    ahora = DateTime(2026, 11, 20, 22, 30);
    a = RespaldoDriveArmado(primerRespaldo: primero, ahora: () => ahora);
  });

  /// El respaldo de Ana ya estaba en `cuentaDeAna`: se le perdió el permiso y vuelve a conectar.
  Future<void> conRespaldoEnLaCuentaDeAna() async {
    _derecha(await a.repo.conectar('u-1'));
    primero.llamadas = 0;
  }

  group('16E·01 Otra cuenta: la conexión', () {
    test(
      'con una cuenta distinta de la del respaldo, queda por confirmar y sin primer respaldo',
      () async {
        await conRespaldoEnLaCuentaDeAna();
        a.google.cuenta = _otra;

        final conexion = _derecha(await a.repo.conectar('u-1'));

        expect(
          conexion.estado,
          const DriveCuentaPorConfirmar(
            email: 'ana.casa@gmail.com',
            cuentaId: 'g-200',
            anteriorEmail: 'ana.gomez@gmail.com',
            anteriorCuentaId: 'g-100',
          ),
        );
        expect(conexion.primerRespaldoHecho, isFalse);
        expect(primero.llamadas, 0, reason: 'el primer respaldo espera a que elija');
        expect(await _estado(a), conexion.estado);
        expect((await _estado(a)).respaldaAhora, isFalse);
      },
    );

    test('Reconectar con la MISMA cuenta tras perder el permiso sigue como siempre', () async {
      await conRespaldoEnLaCuentaDeAna();
      await a.repo.marcarPermisoRevocado('u-1');

      final conexion = _derecha(await a.repo.conectar('u-1'));

      expect(conexion.estado, isA<DriveConectada>());
      expect(conexion.primerRespaldoHecho, isTrue);
      expect(primero.llamadas, 1);
    });

    test(
      'para recuperar (sin primer respaldo, #707) la cuenta elegida no se compara: es la que busca',
      () async {
        await conRespaldoEnLaCuentaDeAna();
        a.google.cuenta = _otra;

        final conexion = _derecha(await a.repo.conectar('u-1', conPrimerRespaldo: false));

        expect(conexion.estado, isA<DriveConectada>());
        expect((conexion.estado as DriveConectada).email, 'ana.casa@gmail.com');
        expect(primero.llamadas, 0);
      },
    );

    test('sin cuenta guardada no hay con qué comparar: es una conexión común', () async {
      a.google.cuenta = _otra;
      final conexion = _derecha(await a.repo.conectar('u-1'));
      expect(conexion.estado, isA<DriveConectada>());
      expect(primero.llamadas, 1);
    });

    test(
      'el respaldo anterior no se toca: la cuenta anterior queda guardada y nada se borra',
      () async {
        await conRespaldoEnLaCuentaDeAna();
        a.google.cuenta = _otra;
        await a.repo.conectar('u-1');

        final guardado = jsonDecode(a.guardado!) as Map<String, dynamic>;
        final fila = guardado['u-1'] as Map<String, dynamic>;
        expect(fila['anterior_email'], 'ana.gomez@gmail.com');
        expect(fila['anterior_id'], 'g-100');
        expect(a.google.desconexiones, 0, reason: 'no se retira ningún permiso por esto');
      },
    );

    test('con otra cuenta por confirmar, perder el permiso o llenarse no la pisa', () async {
      await conRespaldoEnLaCuentaDeAna();
      a.google.cuenta = _otra;
      await a.repo.conectar('u-1');

      await a.repo.marcarPermisoRevocado('u-1');
      await a.repo.marcarSinEspacio('u-1');
      await a.repo.marcarRespaldoGuardado('u-1');

      expect(await _estado(a), isA<DriveCuentaPorConfirmar>());
    });

    test('«verificarPermiso» y «tokenDeAcceso» no se mueven mientras está por confirmar', () async {
      await conRespaldoEnLaCuentaDeAna();
      a.google.cuenta = _otra;
      await a.repo.conectar('u-1');
      final pedidos = a.google.pedidosDeToken;

      expect(await a.repo.tokenDeAcceso('u-1'), isNull);
      expect(_derecha(await a.repo.verificarPermiso('u-1')), isA<DriveCuentaPorConfirmar>());
      expect(a.google.pedidosDeToken, pedidos);
    });

    test(
      'si no se pudo anotar la cuenta nueva, falla, retira el permiso y deja lo anterior',
      () async {
        await conRespaldoEnLaCuentaDeAna();
        a.google.cuenta = _otra;
        a.almacen.alEscribir = true;

        final falla = _falla(await a.repo.conectar('u-1'));

        expect(falla, isA<FailureDriveNoConectado>());
        expect(a.google.desconexiones, 1);
        a.almacen.alEscribir = false;
        expect(await _estado(a), isA<DriveConectada>());
        expect((await _estado(a) as DriveConectada).cuentaId, 'g-100');
      },
    );
  });

  group('16E·03 Volver a la cuenta anterior', () {
    test(
      'Google devuelve la anterior: queda conectada, sin primer respaldo, y sin cuenta por confirmar',
      () async {
        await conRespaldoEnLaCuentaDeAna();
        a.google.cuenta = _otra;
        await a.repo.conectar('u-1');

        a.google.cuenta = cuentaDeAna;
        final conexion = _derecha(await a.repo.conectar('u-1'));

        expect(conexion.estado, isA<DriveConectada>());
        expect((conexion.estado as DriveConectada).email, 'ana.gomez@gmail.com');
        expect(conexion.primerRespaldoHecho, isFalse, reason: 'su respaldo sigue ahí');
        expect(primero.llamadas, 0);
        final fila =
            (jsonDecode(a.guardado!) as Map<String, dynamic>)['u-1'] as Map<String, dynamic>;
        expect(fila.containsKey('anterior_id'), isFalse);
        expect(fila['estado'], 'conectada');
      },
    );

    test(
      'si elige una tercera cuenta, la de referencia sigue siendo la del respaldo anterior',
      () async {
        await conRespaldoEnLaCuentaDeAna();
        a.google.cuenta = _otra;
        await a.repo.conectar('u-1');

        a.google.cuenta = _tercera;
        final conexion = _derecha(await a.repo.conectar('u-1'));

        expect(
          conexion.estado,
          const DriveCuentaPorConfirmar(
            email: 'ana.trabajo@gmail.com',
            cuentaId: 'g-300',
            anteriorEmail: 'ana.gomez@gmail.com',
            anteriorCuentaId: 'g-100',
          ),
        );
      },
    );

    test('si cancela en Google, sigue por confirmar y nada cambia', () async {
      await conRespaldoEnLaCuentaDeAna();
      a.google.cuenta = _otra;
      await a.repo.conectar('u-1');
      final antes = a.guardado;

      a.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);
      expect(_falla(await a.repo.conectar('u-1')), isA<FailureDriveCancelado>());

      expect(a.guardado, antes);
    });
  });

  group('16E·02 Seguir con la cuenta nueva', () {
    test(
      'la nueva pasa a ser la del respaldo, se hace el primer respaldo y no queda anterior',
      () async {
        await conRespaldoEnLaCuentaDeAna();
        a.google.cuenta = _otra;
        await a.repo.conectar('u-1');

        final conexion = _derecha(await a.repo.confirmarCuentaNueva('u-1'));

        expect(conexion.estado, isA<DriveConectada>());
        expect((conexion.estado as DriveConectada).email, 'ana.casa@gmail.com');
        expect(conexion.primerRespaldoHecho, isTrue);
        expect(primero.llamadas, 1);
        expect(await _estado(a), conexion.estado);
        final fila =
            (jsonDecode(a.guardado!) as Map<String, dynamic>)['u-1'] as Map<String, dynamic>;
        expect(fila.containsKey('anterior_id'), isFalse);
        expect((await _estado(a)).respaldaAhora, isTrue);
      },
    );

    test('si el primer respaldo falla, igual sigue con la nueva y lo dice con la verdad', () async {
      await conRespaldoEnLaCuentaDeAna();
      a.google.cuenta = _otra;
      await a.repo.conectar('u-1');
      primero.resultado = false;

      final conexion = _derecha(await a.repo.confirmarCuentaNueva('u-1'));

      expect(conexion.estado, isA<DriveConectada>());
      expect(conexion.primerRespaldoHecho, isFalse);
    });

    test('si el primer respaldo lanza, nada se desconecta', () async {
      await conRespaldoEnLaCuentaDeAna();
      a.google.cuenta = _otra;
      await a.repo.conectar('u-1');
      primero.error = StateError('sin red');

      final conexion = _derecha(await a.repo.confirmarCuentaNueva('u-1'));

      expect(conexion.estado, isA<DriveConectada>());
      expect(conexion.primerRespaldoHecho, isFalse);
    });

    test('sin cuenta por confirmar no hace nada: devuelve lo que hay y no respalda', () async {
      await conRespaldoEnLaCuentaDeAna();

      final conexion = _derecha(await a.repo.confirmarCuentaNueva('u-1'));

      expect(conexion.estado, isA<DriveConectada>());
      expect(conexion.primerRespaldoHecho, isFalse);
      expect(primero.llamadas, 0);
    });

    test('sin cuenta guardada es una falla, no una conexión inventada', () async {
      expect(_falla(await a.repo.confirmarCuentaNueva('u-1')), isA<FailureDriveNoConectado>());
    });

    test('dos veces seguidas: la segunda no repite el primer respaldo', () async {
      await conRespaldoEnLaCuentaDeAna();
      a.google.cuenta = _otra;
      await a.repo.conectar('u-1');

      final dos = await Future.wait([
        a.repo.confirmarCuentaNueva('u-1'),
        a.repo.confirmarCuentaNueva('u-1'),
      ]);

      expect(dos.map(_derecha).map((c) => c.estado), everyElement(isA<DriveConectada>()));
      expect(primero.llamadas, 1);
    });

    test(
      'si el almacén no deja anotarlo, falla y sigue por confirmar (no se pierde la elección)',
      () async {
        await conRespaldoEnLaCuentaDeAna();
        a.google.cuenta = _otra;
        await a.repo.conectar('u-1');
        a.almacen.alEscribir = true;

        expect(_falla(await a.repo.confirmarCuentaNueva('u-1')), isA<FailureDriveNoConectado>());

        a.almacen.alEscribir = false;
        expect(await _estado(a), isA<DriveCuentaPorConfirmar>());
        expect(primero.llamadas, 0);
      },
    );
  });

  group('16F·04 La franja del Drive oculta hasta mañana', () {
    test('sin ocultar, no hay día', () async {
      await conRespaldoEnLaCuentaDeAna();
      expect(await a.repo.franjaOcultaEl('u-1'), isNull);
    });

    test('al ocultarla queda el día de hoy (hora del teléfono, a las 00:00)', () async {
      await conRespaldoEnLaCuentaDeAna();
      await a.repo.marcarPermisoRevocado('u-1');

      _derecha(await a.repo.ocultarFranja('u-1'));

      expect(await a.repo.franjaOcultaEl('u-1'), DateTime(2026, 11, 20));
    });

    test('sobrevive a leer de nuevo y es por usuario', () async {
      await conRespaldoEnLaCuentaDeAna();
      _derecha(await a.repo.ocultarFranja('u-1'));

      expect(await a.repo.franjaOcultaEl('u-1'), isNotNull);
      expect(await a.repo.franjaOcultaEl('u-2'), isNull);
    });

    test('cambiar de estado la vuelve a mostrar', () async {
      await conRespaldoEnLaCuentaDeAna();
      await a.repo.marcarSinEspacio('u-1');
      _derecha(await a.repo.ocultarFranja('u-1'));

      await a.repo.marcarPermisoRevocado('u-1');

      expect(await a.repo.franjaOcultaEl('u-1'), isNull);
    });

    test('guardar un respaldo (sale de «sin espacio») también la vuelve a mostrar', () async {
      await conRespaldoEnLaCuentaDeAna();
      await a.repo.marcarSinEspacio('u-1');
      _derecha(await a.repo.ocultarFranja('u-1'));

      await a.repo.marcarRespaldoGuardado('u-1');

      expect(await a.repo.franjaOcultaEl('u-1'), isNull);
    });

    test('volver a conectar la vuelve a mostrar', () async {
      await conRespaldoEnLaCuentaDeAna();
      await a.repo.marcarPermisoRevocado('u-1');
      _derecha(await a.repo.ocultarFranja('u-1'));

      await a.repo.conectar('u-1');

      expect(await a.repo.franjaOcultaEl('u-1'), isNull);
    });

    test('sin cuenta conectada, ocultar no inventa nada', () async {
      _derecha(await a.repo.ocultarFranja('u-1'));
      expect(await a.repo.franjaOcultaEl('u-1'), isNull);
      expect(a.guardado, isNull);
    });

    test('si el almacén no deja anotarlo, es una falla y la franja sigue a la vista', () async {
      await conRespaldoEnLaCuentaDeAna();
      a.almacen.alEscribir = true;

      expect(_falla(await a.repo.ocultarFranja('u-1')), isA<FailureAlmacenSeguro>());

      a.almacen.alEscribir = false;
      expect(await a.repo.franjaOcultaEl('u-1'), isNull);
    });

    test('si el almacén no se deja leer, ante la duda la franja se ve (null)', () async {
      await conRespaldoEnLaCuentaDeAna();
      _derecha(await a.repo.ocultarFranja('u-1'));
      a.almacen.alLeer = true;

      expect(await a.repo.franjaOcultaEl('u-1'), isNull);
    });

    test('un día guardado ilegible cuenta como no oculta', () async {
      await a.almacen.escribir(
        ClaveSegura.respaldoDrive,
        jsonEncode({
          'u-1': {
            'email': 'ana@x.com',
            'id': 'g-1',
            'estado': 'revocada',
            'franja_oculta': 'ayer a la tarde',
          },
        }),
      );
      expect(await a.repo.franjaOcultaEl('u-1'), isNull);
    });
  });
}
