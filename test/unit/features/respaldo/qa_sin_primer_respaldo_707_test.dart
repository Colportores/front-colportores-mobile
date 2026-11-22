// QA de #707: conectar Drive para «Recuperar mi respaldo» sin el primer respaldo del teléfono vacío
// (decisión de Cristian, 11/11, «Resp. vacío»). Casos del repositorio que el implementador no
// probó: falla de Google o del almacén con la bandera en `false`, llamadas superpuestas con las dos
// banderas, y un primer respaldo que revienta.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart'
    show CuentaGoogle;
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInExceptionCode;

import '../../../helpers/respaldo_drive_falsos.dart';

void main() {
  late PrimerRespaldoFalso primero;
  late RespaldoDriveArmado con;

  setUp(() {
    primero = PrimerRespaldoFalso();
    con = RespaldoDriveArmado(primerRespaldo: primero);
  });

  group('conectar(conPrimerRespaldo: false)', () {
    test('dado un primer respaldo que reventaría, cuando se conecta para recuperar, ni se '
        'toca y la conexión sale bien', () async {
      primero.error = StateError('no debería llamarse');

      final r = await con.repo.conectar('u-1', conPrimerRespaldo: false);

      expect(primero.llamadas, 0);
      final c = r.fold((f) => throw StateError('$f'), (c) => c);
      expect(c.primerRespaldoHecho, isFalse);
      expect(c.estado, isA<DriveConectada>());
    });

    test('dado que la persona cancela en Google, cuando conecta para recuperar, vuelve '
        '«cancelado», no queda nada guardado y no sube nada', () async {
      con.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);

      final r = await con.repo.conectar('u-1', conPrimerRespaldo: false);

      expect(r.fold((f) => f, (_) => null), isA<FailureDriveCancelado>());
      expect(primero.llamadas, 0);
      expect(con.guardado, isNull);
    });

    test('dado que el almacén no puede anotar la cuenta, cuando conecta para recuperar, da '
        'el aviso de «no conectamos» y retira el permiso de Google', () async {
      con.almacen.alEscribir = true;

      final r = await con.repo.conectar('u-1', conPrimerRespaldo: false);

      expect(r.fold((f) => f, (_) => null), isA<FailureDriveNoConectado>());
      expect(con.google.desconexiones, 1, reason: 'no queda un permiso suelto');
      expect(primero.llamadas, 0);
      expect(con.guardado, isNull);
    });

    test('dado que se pide recuperar y la fila «Cuenta Drive» a la vez, cuando se superponen, '
        'cada una respeta su bandera y el primer respaldo se hace una sola vez', () async {
      primero.resultado = true;
      final compuerta = Completer<void>();
      con.google.compuertaConectar = compuerta;

      // La primera espera en la pantalla de Google; la segunda queda en la cola del repositorio.
      final paraRecuperar = con.repo.conectar('u-1', conPrimerRespaldo: false);
      final deLaFila = con.repo.conectar('u-1');
      await Future<void>.delayed(Duration.zero);
      compuerta.complete();
      final a = (await paraRecuperar).fold((f) => throw StateError('$f'), (c) => c);
      final b = (await deLaFila).fold((f) => throw StateError('$f'), (c) => c);

      expect(a.primerRespaldoHecho, isFalse);
      expect(b.primerRespaldoHecho, isTrue);
      expect(primero.llamadas, 1, reason: 'solo la que no era para recuperar');
    });

    test('dado que ya había una cuenta conectada, cuando se reconecta para recuperar, queda '
        'la nueva sin primer respaldo', () async {
      primero.resultado = true;
      await con.repo.conectar('u-1');
      expect(primero.llamadas, 1);
      con.google.cuenta = const CuentaGoogle(id: 'g-200', email: 'otra@gmail.com');

      final r = await con.repo.conectar('u-1', conPrimerRespaldo: false);

      expect(primero.llamadas, 1, reason: 'la reconexión para recuperar no suma otro');
      final c = r.fold((f) => throw StateError('$f'), (c) => c);
      expect(c.estado, isA<DriveConectada>().having((e) => e.email, 'email', 'otra@gmail.com'));
    });

    test('privacidad: ni el texto de la conexión ni el del resultado llevan el correo', () async {
      final c = (await con.repo.conectar(
        'u-1',
        conPrimerRespaldo: false,
      )).fold((f) => throw StateError('$f'), (c) => c);

      expect('$c', isNot(contains('ana.gomez')));
      expect('${c.estado}', isNot(contains('ana.gomez')));
    });
  });
}
