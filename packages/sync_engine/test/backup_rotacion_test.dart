// HU-SYNC-005 (rotación de la base, subida que se corta, filas que no se pierden)
// y HU-SYNC-009 (verificación de la cadena) sobre los fakes.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

/// Un reloj que el test mueve a mano.
class _Reloj {
  _Reloj(this.ahora);
  DateTime ahora;
  DateTime call() => ahora;
  void pasan(Duration d) => ahora = ahora.add(d);
}

({
  BackupService service,
  FakeArchive drive,
  FakeSnapshot snap,
  _Reloj reloj,
}) _armar({
  bool informaHashRemoto = false,
  BackupPolicy policy = const BackupPolicy(),
}) {
  final reloj = _Reloj(DateTime.utc(2026, 11, 2, 22));
  final drive = FakeArchive(
    authorized: true,
    clock: reloj.call,
    informaHashRemoto: informaHashRemoto,
  );
  final snap = FakeSnapshot();
  return (
    service: BackupService(
      archive: drive,
      crypto: FakeCrypto(),
      snapshot: snap,
      clock: reloj.call,
      policy: policy,
    ),
    drive: drive,
    snap: snap,
    reloj: reloj,
  );
}

void main() {
  group('rotación de la base (HU-SYNC-005)', () {
    test('a los 30 incrementales, el siguiente backup es una base nueva', () async {
      final (:service, :drive, :snap, :reloj) = _armar();

      final primera = await service.backupNow(watermark: 'w-0');
      for (var i = 1; i <= 30; i++) {
        reloj.pasan(const Duration(hours: 1));
        final inc = await service.backupNow(watermark: 'w-$i');
        expect(inc.isBase, isFalse, reason: 'incremental $i');
      }
      expect(drive.entries, hasLength(31));

      reloj.pasan(const Duration(hours: 1));
      final nueva = await service.backupNow(watermark: 'w-31');

      expect(nueva.isBase, isTrue);
      expect(snap.exports.last, isNull, reason: 'la base nueva es completa');
      expect(drive.entries.map((e) => e.id), [nueva.id],
          reason: 'la cadena vieja se poda, la nueva ya está confirmada');
      expect(drive.borrados, hasLength(31));
      expect(drive.borrados, contains(primera.id));
    });

    test('a los 30 días, aunque haya un solo incremental', () async {
      final (:service, :drive, :snap, :reloj) = _armar();
      await service.backupNow(watermark: 'w-0');
      reloj.pasan(const Duration(days: 29, hours: 23));
      expect((await service.backupNow(watermark: 'w-1')).isBase, isFalse);

      reloj.pasan(const Duration(hours: 2));
      final nueva = await service.backupNow(watermark: 'w-2');

      expect(nueva.isBase, isTrue);
      expect(drive.entries, hasLength(1));
    });

    test('mientras la base nueva no está confirmada, la vieja sigue entera', () async {
      final (:service, :drive, snap: _, :reloj) = _armar();
      await service.backupNow(watermark: 'w-0');
      for (var i = 1; i <= 30; i++) {
        reloj.pasan(const Duration(hours: 1));
        await service.backupNow(watermark: 'w-$i');
      }
      final antes = drive.entries.map((e) => e.id).toList();

      // Se corta la subida de la base nueva.
      drive.subidasQueFallan = 1;
      reloj.pasan(const Duration(hours: 1));
      await expectLater(service.backupNow(watermark: 'w-31'), throwsStateError);

      expect(drive.entries.map((e) => e.id), antes,
          reason: 'no se borró nada: la cadena vieja sigue siendo la vigente');
      expect(drive.borrados, isEmpty);
      expect((await service.verifyChain()).ok, isTrue);
    });

    test('una subida que se corta no cambia la cadena y el reintento la extiende', () async {
      final (:service, :drive, :snap, :reloj) = _armar();
      final base = await service.backupNow(watermark: 'w-1');

      drive.subidasQueFallan = 1;
      reloj.pasan(const Duration(hours: 1));
      await expectLater(service.backupNow(watermark: 'w-2'), throwsStateError);
      expect(drive.entries.map((e) => e.id), [base.id],
          reason: 'sin entrada, el backup no cuenta (manifest intacto)');

      reloj.pasan(const Duration(hours: 1));
      final inc = await service.backupNow(watermark: 'w-3');
      expect(inc.parentId, base.id);
      expect(snap.exports.last, base.exportedAt,
          reason: 'el reintento parte de lo último que sí se subió');
    });

    test('si la poda de la cadena vieja se corta, queda basura y se limpia después', () async {
      final (:service, :drive, snap: _, :reloj) = _armar(
          policy: const BackupPolicy(maxPatches: 1));
      await service.backupNow(watermark: 'w-0');
      reloj.pasan(const Duration(hours: 1));
      await service.backupNow(watermark: 'w-1');

      drive.failOnDelete = true;
      reloj.pasan(const Duration(hours: 1));
      final nueva = await service.backupNow(watermark: 'w-2');
      expect(nueva.isBase, isTrue, reason: 'el backup salió aunque no pudo podar');
      expect(drive.entries, hasLength(3));

      // La cadena con dos bases no es un problema: la vigente es la más nueva.
      final estado = await service.verifyChain();
      expect(estado.ok, isTrue);
      expect(estado.tip!.id, nueva.id);
      expect(estado.superseded, hasLength(2));

      drive.failOnDelete = false;
      reloj.pasan(const Duration(hours: 1));
      final inc = await service.backupNow(watermark: 'w-3');
      expect(inc.parentId, nueva.id);
      expect(drive.entries.map((e) => e.id).toSet(), {nueva.id, inc.id},
          reason: 'los restos de la cadena anterior se podaron');
    });
  });

  group('lo escrito mientras se subía no se pierde (HU-SYNC-005)', () {
    test('el incremental parte de cuándo se leyó la DB', () async {
      final (:service, drive: _, :snap, :reloj) = _armar();

      final base = await service.backupNow(watermark: 'w-1');
      expect(base.exportedAt, DateTime.utc(2026, 11, 2, 22));

      reloj.pasan(const Duration(minutes: 3));
      await service.backupNow(watermark: 'w-2');

      expect(snap.exports.last, base.exportedAt);
    });

    test('con una subida lenta, lo que se escribió durante la subida entra en el siguiente',
        () async {
      final reloj = _Reloj(DateTime.utc(2026, 11, 2, 22));
      // Un archivo cuyo reloj corre 5 segundos más que el del teléfono mientras
      // sube: `createdAt` queda 5 s después de `exportedAt`.
      final drive = FakeArchive(
        authorized: true,
        clock: () => reloj.ahora.add(const Duration(seconds: 5)),
      );
      final snap = FakeSnapshot();
      final service = BackupService(
        archive: drive,
        crypto: FakeCrypto(),
        snapshot: snap,
        clock: reloj.call,
      );

      final base = await service.backupNow(watermark: 'w-1');
      expect(base.createdAt.difference(base.exportedAt!),
          const Duration(seconds: 5));

      // Una venta que se escribió a los 3 s de empezar la lectura: antes de que
      // termine la subida (`createdAt`) y después de leer la DB (`exportedAt`).
      final escritaDurante = base.exportedAt!.add(const Duration(seconds: 3));

      reloj.pasan(const Duration(hours: 1));
      await service.backupNow(watermark: 'w-2');

      expect(snap.exports.last!.isBefore(escritaDurante), isTrue,
          reason: 'el incremental parte antes de esa venta, así que la incluye; '
              'partir de createdAt la hubiera salteado');
    });
  });

  group('verificación de la cadena (HU-SYNC-009)', () {
    test('con el hash que informa el archivo, no se baja ningún blob', () async {
      final (:service, :drive, snap: _, :reloj) = _armar(informaHashRemoto: true);
      await service.backupNow(watermark: 'w-1');
      reloj.pasan(const Duration(hours: 1));
      await service.backupNow(watermark: 'w-2');
      drive.descargas = 0;

      final informe = await service.verifyIntegrity();

      expect(informe.ok, isTrue);
      expect(informe.hasBackup, isTrue);
      expect(informe.entries, 2);
      expect(drive.descargas, 0,
          reason: 'solo metadatos y checksums (no descarga los blobs)');
    });

    test('un patch corrupto se detecta por los metadatos, sin bajar nada', () async {
      final (:service, :drive, snap: _, :reloj) = _armar(informaHashRemoto: true);
      await service.backupNow(watermark: 'w-1');
      reloj.pasan(const Duration(hours: 1));
      await service.backupNow(watermark: 'w-2');
      drive.corrupt('backup-2');
      drive.descargas = 0;

      final informe = await service.verifyIntegrity();

      expect(informe.ok, isFalse);
      expect(informe.needsRebase, isTrue);
      expect(informe.problems, {'corrupt'});
      expect(informe.status.corruptIds, {'backup-2'});
      expect(drive.descargas, 0);
    });

    test('sin hash remoto, se baja el blob y se compara', () async {
      final (:service, :drive, snap: _, :reloj) = _armar();
      await service.backupNow(watermark: 'w-1');
      reloj.pasan(const Duration(hours: 1));
      await service.backupNow(watermark: 'w-2');
      drive.corrupt('backup-2');

      final informe = await service.verifyIntegrity();

      expect(informe.ok, isFalse);
      expect(informe.problems, {'corrupt'});
      expect(drive.descargas, greaterThan(0));
    });

    test('sin backups no hay nada que verificar: no es un problema', () async {
      final (:service, drive: _, snap: _, reloj: _) = _armar();

      final informe = await service.verifyIntegrity();

      expect(informe.hasBackup, isFalse);
      expect(informe.ok, isTrue);
      expect(informe.needsRebase, isFalse);
      expect(service.regenerarBase, isFalse);
    });

    test('el resultado llega a quien lo registra', () async {
      final (:service, drive: _, snap: _, reloj: _) = _armar(informaHashRemoto: true);
      await service.backupNow(watermark: 'w-1');
      final recibidos = <IntegrityReport>[];
      service.alVerificarIntegridad = (i) async => recibidos.add(i);

      final informe = await service.verifyIntegrity();

      expect(recibidos, [same(informe)]);
      expect(informe.checkedAt, service.now);
    });

    test('si quien registra el resultado falla, la verificación no falla', () async {
      final (:service, drive: _, snap: _, reloj: _) = _armar(informaHashRemoto: true);
      await service.backupNow(watermark: 'w-1');
      service.alVerificarIntegridad = (_) async => throw StateError('audit_log');

      expect((await service.verifyIntegrity()).ok, isTrue);
    });

    test('con un problema, el próximo backup es una base completa nueva y la cadena rota se poda',
        () async {
      final (:service, :drive, :snap, :reloj) = _armar(informaHashRemoto: true);
      await service.backupNow(watermark: 'w-1');
      reloj.pasan(const Duration(hours: 1));
      await service.backupNow(watermark: 'w-2');
      drive.corrupt('backup-2');
      expect((await service.verifyIntegrity()).needsRebase, isTrue);
      expect(service.regenerarBase, isTrue);

      reloj.pasan(const Duration(hours: 1));
      final nueva = await service.backupNow(watermark: 'w-3');

      expect(nueva.isBase, isTrue);
      expect(snap.exports.last, isNull);
      expect(service.regenerarBase, isFalse);
      expect(drive.entries.map((e) => e.id), [nueva.id]);
      expect((await service.verifyIntegrity()).ok, isTrue);
    });

    test('un blob corrupto sin que nadie haya verificado igual regenera la base', () async {
      // El archivo informa su hash: el backup mismo ve que la cadena no sirve.
      final (:service, :drive, :snap, :reloj) = _armar(informaHashRemoto: true);
      await service.backupNow(watermark: 'w-1');
      drive.corrupt('backup-1');

      reloj.pasan(const Duration(hours: 1));
      final nueva = await service.backupNow(watermark: 'w-2');

      expect(nueva.isBase, isTrue);
      expect(snap.exports.last, isNull);
    });

    test('una falla de red al verificar no es un hallazgo y no regenera nada', () async {
      final (:service, :drive, snap: _, reloj: _) = _armar();
      await service.backupNow(watermark: 'w-1');
      drive.revoke();
      final roto = _ArchivoSinRed(drive);
      final service2 = BackupService(
        archive: roto,
        crypto: FakeCrypto(),
        snapshot: FakeSnapshot(),
      );

      await expectLater(service2.verifyIntegrity(), throwsStateError);
      expect(service2.regenerarBase, isFalse);
    });

    test('verificar no se pisa con un backup en curso', () async {
      final (:service, :drive, snap: _, :reloj) = _armar(informaHashRemoto: true);
      await service.backupNow(watermark: 'w-1');
      reloj.pasan(const Duration(hours: 1));

      final resultados = await Future.wait<Object>([
        service.backupNow(watermark: 'w-2'),
        service.verifyIntegrity(),
      ]);

      expect((resultados[1] as IntegrityReport).ok, isTrue);
      expect((resultados[1] as IntegrityReport).entries, 2,
          reason: 'vio la cadena con el backup ya terminado');
      expect(drive.entries, hasLength(2));
    });
  });

  group('cadena con varias bases', () {
    BackupEntry e(String id, int dia, {String? padre, String? stored}) =>
        BackupEntry(
          id: id,
          createdAt: DateTime.utc(2026, 11, dia),
          contentHash: 'h',
          watermark: 'w',
          parentId: padre,
          storedHash: stored,
        );

    test('la base más nueva manda y lo anterior es de una cadena vieja', () {
      final c = buildChain([
        e('a', 1),
        e('a2', 2, padre: 'a'),
        e('b', 10),
        e('b2', 11, padre: 'b'),
      ]);

      expect(c.ok, isTrue);
      expect(c.ordered.map((x) => x.id), ['b', 'b2']);
      expect(c.superseded.map((x) => x.id).toSet(), {'a', 'a2'});
    });

    test('un incremental más nuevo que la base y sin padre es un eslabón perdido', () {
      final c = buildChain([e('a', 1), e('x', 5, padre: 'no-esta')]);
      expect(c.problems, contains(ChainProblem.brokenLink));
    });

    test('un hash remoto que no coincide marca la entrada como corrupta', () {
      final c = buildChain([e('a', 1), e('a2', 2, padre: 'a', stored: 'otro')]);
      expect(c.problems, {ChainProblem.corrupt});
      expect(c.corruptIds, {'a2'});
      expect(c.ordered, isEmpty);
    });
  });
}

/// Un archivo al que se le fue la red.
class _ArchivoSinRed implements ArchivePort {
  _ArchivoSinRed(this._real);
  final FakeArchive _real;

  @override
  Future<bool> authorize() => _real.authorize();
  @override
  Future<bool> get isAuthorized => _real.isAuthorized;
  @override
  Future<List<BackupEntry>> list() async => throw StateError('sin red');
  @override
  Future<BackupEntry> upload({
    required List<int> payload,
    required String? parentId,
    required String watermark,
    DateTime? exportedAt,
    String? keyId,
  }) async =>
      throw StateError('sin red');
  @override
  Future<List<int>> download(String id) async => throw StateError('sin red');
  @override
  Future<void> delete(String id) async => throw StateError('sin red');
}
