import 'dart:convert';

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

BackupEntry _e(String id, {String? parent, String hash = 'h1'}) => BackupEntry(
      id: id,
      createdAt: DateTime.utc(2026, 8, int.parse(id.split('-').last)),
      contentHash: hash,
      watermark: 'w-0',
      parentId: parent,
    );

void main() {
  group('cadena (ADR-003)', () {
    test('base sola es una cadena válida', () {
      final c = buildChain([_e('b-1')]);
      expect(c.ok, isTrue);
      expect(c.ordered.single.id, 'b-1');
    });

    test('ordena de la base a la punta, no por fecha de archivo', () {
      // A propósito desordenadas: en Drive no vienen en ningún orden útil.
      final c = buildChain([
        _e('b-3', parent: 'b-2'),
        _e('b-1'),
        _e('b-2', parent: 'b-1'),
      ]);
      expect(c.ordered.map((e) => e.id), ['b-1', 'b-2', 'b-3']);
      expect(c.tip!.id, 'b-3');
    });

    test('sin base no se puede reconstruir nada', () {
      expect(buildChain([]).problems, {ChainProblem.missingBase});
      expect(buildChain([_e('b-2', parent: 'b-1')]).problems,
          contains(ChainProblem.missingBase));
    });

    test('un eslabón faltante se detecta antes de bajar nada', () {
      final c = buildChain([_e('b-1'), _e('b-3', parent: 'b-2')]);
      expect(c.problems, contains(ChainProblem.brokenLink));
      expect(c.ordered, isEmpty, reason: 'no se ofrece una cadena a medias');
    });

    test('dos dispositivos escribiendo la misma cadena es un fork', () {
      final c = buildChain([
        _e('b-1'),
        _e('b-2', parent: 'b-1'),
        _e('b-3', parent: 'b-1'),
      ]);
      expect(c.problems, contains(ChainProblem.fork));
    });
  });

  group('BackupService', () {
    ({
      BackupService service,
      FakeArchive drive,
      FakeSnapshot snap,
      FakeCrypto crypto
    }) armar() {
      final drive = FakeArchive(authorized: true);
      final snap = FakeSnapshot();
      final crypto = FakeCrypto();
      return (
        service: BackupService(archive: drive, crypto: crypto, snapshot: snap),
        drive: drive,
        snap: snap,
        crypto: crypto,
      );
    }

    test('el primero es completo; los siguientes, incrementales', () async {
      final (:service, :drive, :snap, crypto: _) = armar();

      final base = await service.backupNow(watermark: 'w-1');
      expect(base.isBase, isTrue);
      expect(snap.exports.single, isNull, reason: 'export completo');

      final inc = await service.backupNow(watermark: 'w-2');
      expect(inc.parentId, base.id);
      expect(snap.exports.last, base.createdAt,
          reason: 'solo lo posterior a la base');
      expect(drive.entries, hasLength(2));
    });

    test('lo que sale al Drive va cifrado, nunca en claro', () async {
      final (:service, :drive, :snap, crypto: _) = armar();
      snap.state = {'persona': 'Ana Gómez'};

      await service.backupNow(watermark: 'w-1');

      final subido = await drive.download('backup-1');
      // Ni siquiera es UTF-8 válido, así que hay que mirarlo permisivamente.
      expect(utf8.decode(subido, allowMalformed: true),
          isNot(contains('Ana Gómez')));
      expect(subido, isNot(equals(utf8.encode(jsonEncode(snap.state)))));
    });

    test('el watermark queda en la entrada, para la fase 3 de §7', () async {
      final (:service, drive: _, snap: _, crypto: _) = armar();
      final e = await service.backupNow(watermark: 'w-42');
      expect(e.watermark, 'w-42');
    });

    test('verifyChain detecta un payload corrupto, no solo uno faltante',
        () async {
      final (:service, :drive, snap: _, crypto: _) = armar();
      await service.backupNow(watermark: 'w-1');
      await service.backupNow(watermark: 'w-2');
      expect((await service.verifyChain()).ok, isTrue);

      drive.corrupt('backup-2');
      expect((await service.verifyChain()).ok, isFalse,
          reason: 'existe pero rompe el restore igual que si faltara');
    });

    test('restore aplica la cadena entera, en orden', () async {
      final (:service, drive: _, :snap, crypto: _) = armar();
      snap.state = {'a': 1};
      await service.backupNow(watermark: 'w-1');
      snap.state = {'b': 2};
      await service.backupNow(watermark: 'w-2');

      final punta = await service.restore();
      expect(punta!.id, 'backup-2');
      expect(snap.restored!.keys, containsAll(['a', 'b']));
    });

    test('sobre una cadena rota, restore no devuelve nada a medias', () async {
      final (:service, :drive, :snap, crypto: _) = armar();
      await service.backupNow(watermark: 'w-1');
      await service.backupNow(watermark: 'w-2');
      drive.deleteEntry('backup-1');

      expect(await service.restore(), isNull);
      expect(snap.restored, isNull);
    });

    test('una cadena rota no se extiende: el backup nuevo arranca de cero',
        () async {
      final (:service, :drive, :snap, crypto: _) = armar();
      await service.backupNow(watermark: 'w-1');
      await service.backupNow(watermark: 'w-2');
      drive.deleteEntry('backup-1');

      final nuevo = await service.backupNow(watermark: 'w-3');
      expect(nuevo.isBase, isTrue);
      expect(snap.exports.last, isNull, reason: 'export completo otra vez');
    });
  });
}
