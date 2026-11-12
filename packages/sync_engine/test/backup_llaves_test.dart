// Dos instalaciones, una misma carpeta de Drive (HU-SYNC-005; #185, decisión del 29/10).
//
// Ana cambia de teléfono, entra con la misma cuenta y el teléfono nuevo respalda con su propia DEK.
// El `appDataFolder` es uno solo: lo que dejó el teléfono viejo, cifrado con otra llave, no se
// puede abrir con esta. Por eso el respaldo solo extiende y solo poda lo que tiene su llave; lo
// ajeno queda entero (nunca se pierde una persona).

import 'package:crypto/crypto.dart' as hash;
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

class _Reloj {
  _Reloj(this.ahora);
  DateTime ahora;
  DateTime call() => ahora;
  void pasan(Duration d) => ahora = ahora.add(d);
}

BackupService _servicio(FakeArchive drive, _Reloj reloj, String llave) =>
    BackupService(
      archive: drive,
      crypto: FakeCrypto(llave: llave),
      snapshot: FakeSnapshot(),
      clock: reloj.call,
    );

void main() {
  late _Reloj reloj;
  late FakeArchive drive;

  setUp(() {
    reloj = _Reloj(DateTime.utc(2026, 11, 2, 22));
    drive = FakeArchive(authorized: true, clock: reloj.call);
  });

  group('el teléfono nuevo, con otra llave', () {
    test(
      'con una cadena ajena de 40 días no la borra: arranca la suya al lado',
      () async {
        final viejo = _servicio(drive, reloj, 'viejo');
        final baseVieja = await viejo.backupNow(watermark: 'w-0');
        reloj.pasan(const Duration(days: 40));

        final nuevo = _servicio(drive, reloj, 'nuevo');
        final propia = await nuevo.backupNow(watermark: 'w-1');

        expect(propia.isBase, isTrue);
        expect(propia.keyId, isNot(baseVieja.keyId));
        expect(
          drive.borrados,
          isEmpty,
          reason: 'la única copia del teléfono viejo sigue en Drive',
        );
        expect(
          drive.entries.map((e) => e.id),
          containsAll([baseVieja.id, propia.id]),
        );
      },
    );

    test(
      'con una cadena ajena de 2 días no le cuelga un incremental',
      () async {
        final viejo = _servicio(drive, reloj, 'viejo');
        final baseVieja = await viejo.backupNow(watermark: 'w-0');
        reloj.pasan(const Duration(days: 2));
        final incVieja = await viejo.backupNow(watermark: 'w-1');
        reloj.pasan(const Duration(hours: 1));

        final propia = await _servicio(
          drive,
          reloj,
          'nuevo',
        ).backupNow(watermark: 'w-2');

        expect(
          propia.isBase,
          isTrue,
          reason: 'no hay cadena propia que extender',
        );
        expect(propia.parentId, isNull);
        expect(drive.borrados, isEmpty);
        expect(
          drive.entries.map((e) => e.id),
          containsAll([baseVieja.id, incVieja.id, propia.id]),
        );
      },
    );

    test(
      'después sigue su propia cadena y la ajena no se toca ni al rotar',
      () async {
        final viejo = _servicio(drive, reloj, 'viejo');
        final baseVieja = await viejo.backupNow(watermark: 'w-0');
        final nuevo = _servicio(drive, reloj, 'nuevo');
        final base = await nuevo.backupNow(watermark: 'w-1');

        reloj.pasan(const Duration(hours: 1));
        final inc = await nuevo.backupNow(watermark: 'w-2');
        expect(inc.parentId, base.id);

        // 31 días: le toca rotar la base propia; la ajena sigue sin tocarse.
        reloj.pasan(const Duration(days: 31));
        final rotada = await nuevo.backupNow(watermark: 'w-3');

        expect(rotada.isBase, isTrue);
        expect(drive.borrados, unorderedEquals([base.id, inc.id]));
        expect(
          drive.entries.map((e) => e.id),
          containsAll([baseVieja.id, rotada.id]),
        );
      },
    );

    test('lo que no trae identificador de llave tampoco se toca', () async {
      final suelta = await drive.upload(
        payload: const [1, 2, 3],
        parentId: null,
        watermark: 'w-viejo',
        exportedAt: reloj.ahora,
      );
      expect(suelta.keyId, isNull);
      reloj.pasan(const Duration(days: 40));

      final propia = await _servicio(
        drive,
        reloj,
        'nuevo',
      ).backupNow(watermark: 'w-1');

      expect(propia.isBase, isTrue);
      expect(drive.borrados, isEmpty);
      expect(drive.entries.map((e) => e.id), contains(suelta.id));
    });

    test(
      'la verificación mira solo su cadena: una ajena no la da por rota',
      () async {
        await _servicio(drive, reloj, 'viejo').backupNow(watermark: 'w-0');
        final nuevo = _servicio(drive, reloj, 'nuevo');

        // Sin cadena propia todavía: no es un problema, es «todavía no hubo respaldo».
        final sinPropia = await nuevo.verifyIntegrity();
        expect(sinPropia.hasBackup, isFalse);
        expect(sinPropia.ok, isTrue);

        await nuevo.backupNow(watermark: 'w-1');
        final informe = await nuevo.verifyIntegrity();
        expect(informe.ok, isTrue);
        expect(informe.entries, 1);
        expect(nuevo.regenerarBase, isFalse);
      },
    );

    test(
      'un eslabón corrupto de la cadena ajena no hace regenerar la base propia',
      () async {
        drive = FakeArchive(
          authorized: true,
          clock: reloj.call,
          informaHashRemoto: true,
        );
        final baseVieja = await _servicio(
          drive,
          reloj,
          'viejo',
        ).backupNow(watermark: 'w-0');
        final nuevo = _servicio(drive, reloj, 'nuevo');
        await nuevo.backupNow(watermark: 'w-1');
        drive.corrupt(baseVieja.id);

        expect((await nuevo.verifyIntegrity()).ok, isTrue);
        expect(nuevo.regenerarBase, isFalse);
      },
    );
  });

  group('la misma llave en otra instalación', () {
    test(
      'la DEK recuperada con la contraseña sigue la cadena, sin base nueva',
      () async {
        final base = await _servicio(
          drive,
          reloj,
          'ana',
        ).backupNow(watermark: 'w-0');
        reloj.pasan(const Duration(hours: 5));

        // Otra instalación (teléfono nuevo, DEK recuperada): mismo identificador de llave.
        final otra = _servicio(drive, reloj, 'ana');
        final inc = await otra.backupNow(watermark: 'w-1');

        expect(inc.isBase, isFalse);
        expect(inc.parentId, base.id);
        expect(drive.borrados, isEmpty);
        expect((await otra.verifyIntegrity()).ok, isTrue);
      },
    );
  });

  group('AesGcmCrypto.keyId', () {
    List<int> clave(int semilla) =>
        List<int>.generate(32, (i) => (i * 7 + semilla) % 256);

    test(
      'es estable: la misma llave da siempre el mismo identificador',
      () async {
        expect(
          await AesGcmCrypto(clave(1)).keyId(),
          await AesGcmCrypto(clave(1)).keyId(),
        );
      },
    );

    test('llaves distintas dan identificadores distintos', () async {
      expect(
        await AesGcmCrypto(clave(1)).keyId(),
        isNot(await AesGcmCrypto(clave(2)).keyId()),
      );
    });

    test(
      'no deja la llave a la vista: ni la contiene ni es su hash directo',
      () async {
        final bytes = clave(3);
        final id = await AesGcmCrypto(bytes).keyId();
        final hex = bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

        expect(
          id,
          matches(RegExp(r'^[0-9a-f]{32}$')),
          reason: '16 bytes en hexadecimal',
        );
        expect(hex, isNot(contains(id)));
        final directo = hash.sha256.convert(bytes).toString();
        expect(
          directo.startsWith(id),
          isFalse,
          reason: 'no es el SHA-256 de la llave recortado',
        );
      },
    );
  });
}
