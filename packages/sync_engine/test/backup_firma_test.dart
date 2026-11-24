// La firma de las anotaciones de cada archivo del respaldo (HU-SYNC-009, decisión de Cristian del
// 03/11, «Manifiesto»): `parent_id`, `content_hash` y `exported_at` llevan una firma hecha con una llave
// derivada de la llave de la usuaria. Si no coincide —o falta—, la cadena se da por rota y el próximo
// respaldo parte de una base nueva. No hay un índice aparte: la firma viaja en el propio archivo.

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

List<int> _clave(int semilla) => List<int>.generate(32, (i) => (i * 7 + semilla) % 256);

/// La misma entrada con alguna anotación cambiada (como la dejaría alguien con acceso a la carpeta).
BackupEntry _tocada(
  BackupEntry e, {
  String? parentId,
  String? contentHash,
  DateTime? exportedAt,
  String? firma,
  bool sinFirma = false,
}) => BackupEntry(
  id: e.id,
  createdAt: e.createdAt,
  contentHash: contentHash ?? e.contentHash,
  watermark: e.watermark,
  parentId: parentId ?? e.parentId,
  bytes: e.bytes,
  exportedAt: exportedAt ?? e.exportedAt,
  keyId: e.keyId,
  firma: sinFirma ? null : (firma ?? e.firma),
);

void main() {
  late _Reloj reloj;
  late FakeArchive drive;
  late BackupService servicio;

  setUp(() {
    reloj = _Reloj(DateTime.utc(2026, 11, 3, 22));
    drive = FakeArchive(authorized: true, clock: reloj.call);
    servicio = BackupService(
      archive: drive,
      crypto: FakeCrypto(),
      snapshot: FakeSnapshot(),
      clock: reloj.call,
    );
  });

  /// Una base y dos incrementales, todos firmados por el servicio.
  Future<void> cadenaDeTres() async {
    for (var i = 0; i < 3; i++) {
      reloj.pasan(const Duration(minutes: 5));
      await servicio.backupNow(watermark: 'w-$i');
    }
  }

  group('la verificación de la cadena', () {
    test('dada una cadena hecha por el respaldo, cuando se verifica, está íntegra y firmada', () async {
      await cadenaDeTres();

      final cadena = await servicio.verifyChain();

      expect(cadena.ok, isTrue);
      expect(cadena.ordered, hasLength(3));
      expect(drive.entries.every((e) => e.firma != null), isTrue);
      final informe = await servicio.verifyIntegrity();
      expect(informe.ok, isTrue);
      expect(servicio.regenerarBase, isFalse);
    });

    test('dada una base sola, cuando se verifica, está íntegra', () async {
      await servicio.backupNow(watermark: 'w-0');

      expect((await servicio.verifyChain()).ok, isTrue);
    });

    test('dado un incremental reencadenado a otro padre, es una cadena rota por la firma', () async {
      await cadenaDeTres();
      // Se le cambia el padre al último, de modo que la cadena sigue "cerrando" por sus enlaces.
      final base = drive.entries[0];
      final ultimo = drive.entries[2];
      drive.entries[2] = _tocada(ultimo, parentId: base.id);
      drive.entries.removeAt(1);

      final cadena = await servicio.verifyChain();

      expect(cadena.problems, {ChainProblem.badSignature});
      expect(cadena.ordered, isEmpty);
    });

    test('dado un content_hash tocado, es una cadena rota por la firma', () async {
      await cadenaDeTres();
      drive.entries[1] = _tocada(drive.entries[1], contentHash: 'h1');

      expect((await servicio.verifyChain()).problems, {ChainProblem.badSignature});
    });

    test('dado un exported_at tocado, es una cadena rota por la firma', () async {
      await cadenaDeTres();
      drive.entries[1] = _tocada(
        drive.entries[1],
        exportedAt: drive.entries[1].exportedAt!.subtract(const Duration(days: 1)),
      );

      expect((await servicio.verifyChain()).problems, {ChainProblem.badSignature});
    });

    test('dado un exported_at que se perdió, es una cadena rota por la firma', () async {
      await cadenaDeTres();
      final e = drive.entries[1];
      drive.entries[1] = BackupEntry(
        id: e.id,
        createdAt: e.createdAt,
        contentHash: e.contentHash,
        watermark: e.watermark,
        parentId: e.parentId,
        bytes: e.bytes,
        keyId: e.keyId,
        firma: e.firma,
      );

      expect((await servicio.verifyChain()).problems, {ChainProblem.badSignature});
    });

    test('dado un archivo sin firma (de antes de la firma), es una cadena rota', () async {
      await cadenaDeTres();
      drive.entries[0] = _tocada(drive.entries[0], sinFirma: true);

      expect((await servicio.verifyChain()).problems, {ChainProblem.badSignature});
    });

    test('dada una firma de otra llave, es una cadena rota', () async {
      await cadenaDeTres();
      final ajena = await FakeCrypto(llave: 'otra').sign(drive.entries[2].mensajeFirmado);
      drive.entries[2] = _tocada(drive.entries[2], firma: ajena);

      expect((await servicio.verifyChain()).problems, {ChainProblem.badSignature});
    });

    test('dada una firma copiada de otro archivo, es una cadena rota', () async {
      await cadenaDeTres();
      drive.entries[2] = _tocada(drive.entries[2], firma: drive.entries[1].firma);

      expect((await servicio.verifyChain()).problems, {ChainProblem.badSignature});
    });

    test('dada una firma vacía, es una cadena rota', () async {
      await cadenaDeTres();
      drive.entries[2] = _tocada(drive.entries[2], firma: '');

      expect((await servicio.verifyChain()).problems, {ChainProblem.badSignature});
    });

    test('dada la verificación sin bajar contenido, también mira la firma y no baja nada', () async {
      await cadenaDeTres();
      drive.entries[1] = _tocada(drive.entries[1], contentHash: 'h1');

      final cadena = await servicio.verifyChain(checkContent: false);

      expect(cadena.problems, {ChainProblem.badSignature});
      expect(drive.descargas, 0);
    });
  });

  group('la cadena rota por la firma se regenera sola', () {
    test('dada una firma que no coincide, cuando se verifica, el próximo respaldo es una base nueva', () async {
      await cadenaDeTres();
      final viejas = [for (final e in drive.entries) e.id];
      drive.entries[2] = _tocada(drive.entries[2], contentHash: 'otro');

      final informe = await servicio.verifyIntegrity();

      expect(informe.ok, isFalse);
      expect(informe.needsRebase, isTrue);
      expect(informe.problems, {'badSignature'});
      expect(servicio.regenerarBase, isTrue);

      reloj.pasan(const Duration(minutes: 5));
      final nueva = await servicio.backupNow(watermark: 'w-9');

      expect(nueva.isBase, isTrue);
      expect(nueva.firma, isNotNull);
      expect(servicio.regenerarBase, isFalse);
      expect(drive.entries.map((e) => e.id), [nueva.id], reason: 'la cadena rota se poda');
      expect(drive.borrados, containsAll(viejas));
      expect((await servicio.verifyChain()).ok, isTrue);
    });

    test('dados todos los archivos sin firma, la regeneración los reemplaza por una base firmada', () async {
      await cadenaDeTres();
      for (var i = 0; i < drive.entries.length; i++) {
        drive.entries[i] = _tocada(drive.entries[i], sinFirma: true);
      }

      expect((await servicio.verifyIntegrity()).needsRebase, isTrue);
      reloj.pasan(const Duration(minutes: 5));
      final nueva = await servicio.backupNow(watermark: 'w-9');

      expect(drive.entries.single.id, nueva.id);
      expect((await servicio.verifyIntegrity()).ok, isTrue);
    });

    test('dado un archivo de otra llave con anotaciones sin firma, no cuenta para esta cadena', () async {
      await cadenaDeTres();
      final ajeno = BackupService(
        archive: drive,
        crypto: FakeCrypto(llave: 'otra'),
        snapshot: FakeSnapshot(),
        clock: reloj.call,
      );
      reloj.pasan(const Duration(minutes: 5));
      final entradaAjena = await ajeno.backupNow(watermark: 'w-x');
      final i = drive.entries.indexWhere((e) => e.id == entradaAjena.id);
      drive.entries[i] = _tocada(entradaAjena, sinFirma: true);

      expect((await servicio.verifyChain()).ok, isTrue);
    });
  });

  group('restaurar', () {
    test('dado un respaldo hecho antes de la firma, cuando se restaura, se recupera igual', () async {
      final snapshot = FakeSnapshot()..state = {'venta': 'v1'};
      final propio = BackupService(
        archive: drive,
        crypto: FakeCrypto(),
        snapshot: snapshot,
        clock: reloj.call,
      );
      await propio.backupNow(watermark: 'w-0');
      drive.entries[0] = _tocada(drive.entries[0], sinFirma: true);

      final punta = await propio.restore();

      expect(punta, isNotNull);
      expect(snapshot.restored, containsPair('venta', 'v1'));
    });
  });

  group('el mensaje que se firma', () {
    test('dados los mismos datos, es el mismo mensaje', () {
      final a = mensajeDeFirma(parentId: 'p', contentHash: 'h', exportedAt: DateTime.utc(2026, 11, 3));
      final b = mensajeDeFirma(parentId: 'p', contentHash: 'h', exportedAt: DateTime.utc(2026, 11, 3));
      expect(a, b);
    });

    test('dado el límite entre dos campos movido, el mensaje cambia', () {
      final a = mensajeDeFirma(parentId: 'ab', contentHash: 'c', exportedAt: null);
      final b = mensajeDeFirma(parentId: 'a', contentHash: 'bc', exportedAt: null);
      final c = mensajeDeFirma(parentId: 'a", "b', contentHash: 'c', exportedAt: null);
      final d = mensajeDeFirma(parentId: 'a', contentHash: 'b", "c', exportedAt: null);
      expect({a, b, c, d}, hasLength(4));
    });

    test('dados una base (sin padre) y un padre vacío, no hay diferencia: son lo mismo en Drive', () {
      expect(
        mensajeDeFirma(parentId: null, contentHash: 'h', exportedAt: null),
        mensajeDeFirma(parentId: '', contentHash: 'h', exportedAt: null),
      );
    });

    test('dados el mismo instante en otra zona horaria, el mensaje es el mismo', () {
      final utc = DateTime.utc(2026, 11, 3, 22);
      final local = utc.toLocal();
      expect(
        mensajeDeFirma(parentId: null, contentHash: 'h', exportedAt: utc),
        mensajeDeFirma(parentId: null, contentHash: 'h', exportedAt: local),
      );
    });
  });

  group('AesGcmCrypto.sign', () {
    test('dado un mensaje, la firma es HMAC en hexadecimal de 64 caracteres y estable', () async {
      final cripto = AesGcmCrypto(_clave(1));

      final a = await cripto.sign('hola');
      final b = await AesGcmCrypto(_clave(1)).sign('hola');

      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(a, b, reason: 'la misma llave recuperada en otro teléfono firma igual');
    });

    test('dados otra llave u otro mensaje, la firma cambia', () async {
      final base = await AesGcmCrypto(_clave(1)).sign('hola');

      expect(await AesGcmCrypto(_clave(2)).sign('hola'), isNot(base));
      expect(await AesGcmCrypto(_clave(1)).sign('hola!'), isNot(base));
    });

    test('dada la firma, no es la llave ni el identificador de llave', () async {
      final cripto = AesGcmCrypto(_clave(1));

      expect(await cripto.sign(AesGcmCrypto.etiquetaKeyId), isNot(await cripto.keyId()));
      expect(await cripto.sign(''), isNot(contains(_clave(1).join())));
    });

    test('dada su firma, el mensaje se verifica; con cualquier cambio, no', () async {
      final cripto = AesGcmCrypto(_clave(1));
      final firma = await cripto.sign('mensaje');

      expect(await cripto.verifySignature('mensaje', firma), isTrue);
      expect(await cripto.verifySignature('mensaje', firma.toUpperCase()), isFalse);
      expect(await cripto.verifySignature('mensaje ', firma), isFalse);
      expect(await cripto.verifySignature('mensaje', firma.substring(1)), isFalse);
      expect(await cripto.verifySignature('mensaje', '${firma}0'), isFalse);
      expect(await cripto.verifySignature('mensaje', ''), isFalse);
      expect(await cripto.verifySignature('mensaje', null), isFalse);
      expect(await AesGcmCrypto(_clave(2)).verifySignature('mensaje', firma), isFalse);
    });

    test('dada una firma con un solo carácter distinto en cualquier lugar, no se verifica', () async {
      final cripto = AesGcmCrypto(_clave(1));
      final firma = await cripto.sign('mensaje');

      for (var i = 0; i < firma.length; i++) {
        final otro = firma[i] == '0' ? '1' : '0';
        final tocada = firma.replaceRange(i, i + 1, otro);
        expect(await cripto.verifySignature('mensaje', tocada), isFalse, reason: 'posición $i');
      }
    });
  });

  group('con AES-GCM de verdad (sin dobles de cifrado)', () {
    test('dada una cadena cifrada con AES-GCM, la firma se verifica y una anotación tocada la rompe', () async {
      final cripto = AesGcmCrypto(_clave(5));
      // El hash del archivo de mentira tiene que ser el del cifrado en juego.
      final archivo = FakeArchive(authorized: true, clock: reloj.call, digest: cripto.digest);
      final real = BackupService(
        archive: archivo,
        crypto: cripto,
        snapshot: FakeSnapshot()..state = {'venta': 'v1'},
        clock: reloj.call,
      );
      for (var i = 0; i < 2; i++) {
        reloj.pasan(const Duration(minutes: 5));
        await real.backupNow(watermark: 'w-$i');
      }
      expect(archivo.entries.every((e) => e.firma?.length == 64), isTrue);
      expect((await real.verifyIntegrity()).ok, isTrue);

      archivo.entries[1] = _tocada(
        archivo.entries[1],
        exportedAt: archivo.entries[1].exportedAt!.add(const Duration(seconds: 1)),
      );

      expect((await real.verifyChain()).problems, {ChainProblem.badSignature});
    });
  });
}
