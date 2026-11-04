// El restore de la cadena (HU-SYNC-006, ADR-006 §Restore): parcial ante un
// eslabón dañado, la cadena de cada llave, la pausa por red, la cancelación y la
// base nueva que sigue a una recuperación.

import 'dart:async';

import 'package:sync_engine/adapters.dart' show BackupIlegible;
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

/// Un Drive al que se le puede caer la red al bajar un eslabón.
class _ArchivoQueSeCae extends FakeArchive {
  _ArchivoQueSeCae() : super(authorized: true);

  /// Cuántas descargas fallan antes de volver a andar.
  int fallas = 0;

  /// Qué id falla (null: cualquiera).
  String? soloEn;

  final intentos = <String>[];

  @override
  Future<List<int>> download(String id) async {
    intentos.add(id);
    if (fallas > 0 && (soloEn == null || soloEn == id)) {
      fallas--;
      throw TimeoutException('se cortó la red');
    }
    return super.download(id);
  }
}

/// Un cifrado cuya llave no abre lo que hay en Drive: el descifrado falla (un archivo roto o una
/// llave que no es la de esa cadena) a partir de la llamada [desde] (1 = la base).
class _CryptoQueNoAbre extends FakeCrypto {
  _CryptoQueNoAbre({
    super.llave,
    this.desde = 1,
    this.error = const FormatException('no se descifra'),
  });

  final int desde;

  /// Qué lanza: el `FormatException` del gzip o el `BackupIlegible` de AES-GCM.
  final Exception error;
  int _llamadas = 0;

  @override
  Future<List<int>> decrypt(List<int> ciphertext) async {
    if (++_llamadas >= desde) throw error;
    return super.decrypt(ciphertext);
  }
}

/// Un cifrado con un bug de programa (no un archivo roto): lanza un `Error`, como el
/// `StateError` de una clave que ya no está.
class _CryptoConUnBug extends FakeCrypto {
  _CryptoConUnBug({super.llave});

  @override
  Future<List<int>> decrypt(List<int> ciphertext) async =>
      throw StateError('la clave de la cadena ya no está');
}

/// Una cadena de [partes] eslabones de la llave [llave] en [drive].
Future<BackupService> _cadena(
  FakeArchive drive,
  FakeSnapshot snap, {
  int partes = 4,
  String llave = 'a',
  String prefijo = '',
  String marca = 'w-',
}) async {
  final service = BackupService(
    archive: drive,
    crypto: FakeCrypto(llave: llave),
    snapshot: snap,
  );
  for (var i = 1; i <= partes; i++) {
    snap.state = {'$prefijo$i': i};
    await service.backupNow(watermark: '$marca$i');
  }
  return service;
}

void main() {
  late _ArchivoQueSeCae drive;
  late FakeSnapshot origen;
  late FakeSnapshot nuevo;
  late BackupService restaurador;

  setUp(() {
    drive = _ArchivoQueSeCae();
    origen = FakeSnapshot();
    nuevo = FakeSnapshot();
    // El teléfono nuevo: otra llave, su propia DB vacía.
    restaurador = BackupService(
      archive: drive,
      crypto: FakeCrypto(llave: 'nuevo'),
      snapshot: nuevo,
    );
  });

  group('restore parcial (HU-SYNC-006, «Patch corrupto en medio»)', () {
    test('una parte dañada corta la cadena: se aplica hasta la última buena',
        () async {
      await _cadena(drive, origen);
      drive.corrupt('backup-3');

      final r = await restaurador.restoreDetailed();

      expect(r!.partial, isTrue);
      expect(r.tip.id, 'backup-2', reason: 'hasta cuándo llega lo restaurado');
      expect([r.applied, r.total], [2, 4]);
      expect(r.problem, 'corrupt');
      expect(nuevo.restored!.keys, containsAll(['1', '2']));
      expect(nuevo.restored!.keys, isNot(contains('3')));
      expect(nuevo.restored!.keys, isNot(contains('4')),
          reason: 'lo que cuelga de la parte dañada tampoco entra');
    });

    test('el hash que informa Drive también delata la parte dañada antes de bajarla',
        () async {
      final conHash = FakeArchive(authorized: true, informaHashRemoto: true);
      await _cadena(conHash, origen);
      conHash.corrupt('backup-4');

      final r = await BackupService(
        archive: conHash,
        crypto: FakeCrypto(llave: 'nuevo'),
        snapshot: nuevo,
      ).restoreDetailed();

      expect([r!.applied, r.total, r.problem], [3, 3, 'corrupt']);
      expect(r.tip.id, 'backup-3');
      expect(conHash.descargas, 3, reason: 'la dañada no se baja');
    });

    test('la base dañada no deja nada que restaurar y la DB no se toca', () async {
      await _cadena(drive, origen);
      drive.corrupt('backup-1');

      expect(await restaurador.restoreDetailed(), isNull);
      expect(nuevo.restored, isNull);
    });

    test('una cadena entera no es parcial', () async {
      await _cadena(drive, origen);

      final r = await restaurador.restoreDetailed();

      expect(r!.partial, isFalse);
      expect([r.applied, r.total, r.problem], [4, 4, '']);
      expect(nuevo.restored!.keys, containsAll(['1', '2', '3', '4']));
    });

    test('un eslabón que falta corta ahí; lo que cuelga de él queda afuera',
        () async {
      await _cadena(drive, origen);
      drive.deleteEntry('backup-3');

      final r = await restaurador.restoreDetailed();

      expect([r!.applied, r.partial], [2, true]);
      expect(r.tip.id, 'backup-2');
    });

    test('una base que no se descifra: no hay nada que restaurar y la DB no se toca',
        () async {
      await _cadena(drive, origen);
      final conOtraLlave = BackupService(
        archive: drive,
        crypto: _CryptoQueNoAbre(llave: 'a'),
        snapshot: nuevo,
      );

      expect(await conOtraLlave.restoreDetailed(), isNull);
      expect(nuevo.restored, isNull);
    });

    test('un Error al descifrar (un bug, no un archivo roto) no se disfraza de base ilegible',
        () async {
      await _cadena(drive, origen);
      final conUnBug = BackupService(
        archive: drive,
        crypto: _CryptoConUnBug(llave: 'a'),
        snapshot: nuevo,
      );

      await expectLater(conUnBug.restoreDetailed(), throwsStateError);
      expect(nuevo.restored, isNull);
    });

    test('un BackupIlegible al descifrar sí es un archivo roto: la cadena se salta',
        () async {
      await _cadena(drive, origen);
      final roto = BackupService(
        archive: drive,
        crypto: _CryptoQueNoAbre(llave: 'a', error: const BackupIlegible('roto')),
        snapshot: nuevo,
      );

      expect(await roto.restoreDetailed(), isNull);
    });

    test('un incremental que no se descifra corta la cadena ahí, con la base aplicada',
        () async {
      await _cadena(drive, origen);
      final conOtraLlave = BackupService(
        archive: drive,
        crypto: _CryptoQueNoAbre(llave: 'a', desde: 3),
        snapshot: nuevo,
      );

      final r = await conOtraLlave.restoreDetailed();

      expect([r!.applied, r.total, r.partial, r.problem], [2, 4, true, 'unreadable']);
      expect(nuevo.restored!.keys, containsAll(['1', '2']));
      expect(nuevo.restored!.keys, isNot(contains('3')));
    });

    test('si aplicar la copia falla, no queda registrado nada restaurado', () async {
      await _cadena(drive, origen);
      nuevo.failOnRestore = true;

      await expectLater(restaurador.restoreDetailed(), throwsStateError);
      expect(nuevo.restored, isNull);
    });
  });

  group('la cadena de cada llave', () {
    test('con la llave pedida restaura solo esa cadena', () async {
      await _cadena(drive, origen, llave: 'viejo', prefijo: 'v');
      await _cadena(drive, FakeSnapshot(), llave: 'otro', prefijo: 'o', partes: 2);

      final r = await restaurador.restoreDetailed(keyId: 'id-viejo');

      expect(r!.applied, 4);
      expect(nuevo.restored!.keys, containsAll(['v1', 'v2', 'v3', 'v4']));
      expect(nuevo.restored!.keys, isNot(contains('o1')));
    });

    test('candidateChains lista una cadena por llave, sin bajar nada', () async {
      await _cadena(drive, origen, llave: 'viejo', prefijo: 'v');
      await _cadena(drive, FakeSnapshot(), llave: 'otro', prefijo: 'o', partes: 2);

      final candidatas = await restaurador.candidateChains();

      expect(candidatas.map((c) => c.keyId).toSet(), {'id-viejo', 'id-otro'});
      expect(candidatas.map((c) => c.parts).toSet(), {4, 2});
      expect(candidatas.every((c) => c.intact), isTrue);
      expect(drive.intentos, isEmpty);
    });

    test('una cadena rota a medias se ofrece, pero no como entera', () async {
      await _cadena(drive, origen, llave: 'viejo');
      drive.deleteEntry('backup-3');

      final c = (await restaurador.candidateChains()).single;

      expect([c.parts, c.intact], [2, false]);
    });
  });

  group('pausa por red (HU-SYNC-006, «Fallo de red durante restore»)', () {
    test('se cae la red en la parte 2: espera, vuelve y sigue desde ahí', () async {
      await _cadena(drive, origen);
      drive
        ..fallas = 2
        ..soloEn = 'backup-2'
        ..intentos.clear();
      final avances = <RecoveryProgress>[];
      var esperas = 0;

      final r = await restaurador.restoreDetailed(
        onProgress: avances.add,
        waitForNetwork: () async {
          esperas++;
          return true;
        },
      );

      expect(r!.partial, isFalse);
      expect(esperas, 2);
      expect(avances.where((a) => a.waitingForNetwork).map((a) => a.done),
          [1, 1], reason: 'la pausa dice en qué parte quedó');
      expect(drive.intentos.where((i) => i == 'backup-1'), hasLength(1),
          reason: 'lo ya bajado no se baja de nuevo');
    });

    test('si la red no vuelve a tiempo falla, y el reintento no repite lo bajado',
        () async {
      await _cadena(drive, origen);
      drive
        ..fallas = 100
        ..soloEn = 'backup-3'
        ..intentos.clear();

      await expectLater(
        restaurador.restoreDetailed(waitForNetwork: () async => false),
        throwsA(isA<TimeoutException>()),
      );
      expect(nuevo.restored, isNull, reason: 'la DB no se tocó');

      drive
        ..fallas = 0
        ..intentos.clear();
      final r = await restaurador.restoreDetailed();

      expect(r!.applied, 4);
      expect(drive.intentos, ['backup-3', 'backup-4'],
          reason: 'sigue desde la parte donde quedó');
    });

    test('tras tres intentos sin red se rinde en vez de esperar para siempre',
        () async {
      await _cadena(drive, origen);
      drive.fallas = 100;

      await expectLater(
        restaurador.restoreDetailed(waitForNetwork: () async => true),
        throwsA(isA<TimeoutException>()),
      );
      expect(drive.intentos.where((i) => i == 'backup-1'), hasLength(3));
    });

    test('un error de programa no se toma por un corte de red', () async {
      await _cadena(drive, origen);
      var esperas = 0;
      drive.deleteEntry('backup-2'); // la lista lo sigue viendo? no: se va

      // Una entrada que está en la lista pero no en el archivo: StateError.
      final fantasma = FakeArchive(authorized: true);
      await _cadena(fantasma, FakeSnapshot(), partes: 2);
      fantasma.entries.add(BackupEntry(
        id: 'backup-9',
        createdAt: DateTime.utc(2099),
        contentHash: 'x',
        watermark: 'w',
        parentId: 'backup-2',
        keyId: 'id-a',
      ));

      await expectLater(
        BackupService(
          archive: fantasma,
          crypto: FakeCrypto(llave: 'nuevo'),
          snapshot: nuevo,
        ).restoreDetailed(waitForNetwork: () async {
          esperas++;
          return true;
        }),
        throwsStateError,
      );
      expect(esperas, 0);
    });
  });

  group('cancelar (HU-SYNC-006, «Cancelación por el usuario»)', () {
    test('cancelar a mitad de la descarga descarta todo y no toca la DB', () async {
      await _cadena(drive, origen);
      final cancelar = RecoveryCancelToken();

      await expectLater(
        restaurador.restoreDetailed(
          cancel: cancelar,
          onProgress: (p) {
            if (p.phase == RecoveryPhase.downloading && p.done == 2) {
              cancelar.cancel();
            }
          },
        ),
        throwsA(isA<RecoveryCancelled>()),
      );
      expect(nuevo.restored, isNull);

      // Y un restore nuevo parte limpio: lo cancelado no queda en memoria.
      drive.intentos.clear();
      await restaurador.restoreDetailed();
      expect(drive.intentos, hasLength(4));
    });

    test('desde que empieza a aplicarse, el avance dice que ya no se cancela',
        () async {
      await _cadena(drive, origen);
      final avances = <RecoveryProgress>[];

      await restaurador.restoreDetailed(onProgress: avances.add);

      expect(avances.first.canCancel, isTrue);
      expect(avances.firstWhere((a) => a.phase == RecoveryPhase.applying).canCancel,
          isFalse);
      expect(
        avances
            .where((a) => a.phase == RecoveryPhase.downloading)
            .map((a) => '${a.done}/${a.total}'),
        ['0/4', '1/4', '2/4', '3/4'],
      );
    });
  });

  group('esquema más nuevo (HU-SYNC-006, «Edge»)', () {
    test('el aviso sale tal cual y la DB queda intacta', () async {
      await _cadena(drive, origen);
      final conEsquemaNuevo = _SnapshotDeEsquemaNuevo();
      final service = BackupService(
        archive: drive,
        crypto: FakeCrypto(llave: 'nuevo'),
        snapshot: conEsquemaNuevo,
      );

      await expectLater(
        service.restoreDetailed(),
        throwsA(isA<SnapshotNewerSchemaException>()
            .having((e) => e.backupSchema, 'respaldo', 30)
            .having((e) => e.appSchema, 'app', 22)),
      );
      expect(conEsquemaNuevo.tocada, isFalse);
    });
  });

  group('varias cadenas juntas (HU-SYNC-006, «Varios resp.»)', () {
    late FakeSnapshot origenB;
    late FakeSyncTransport transporte;
    late SyncEngine motor;

    SyncEngine armar() => SyncEngine(
          specs: SpecRegistry([
            SyncSpec.push('venta', critical: true),
            SyncSpec.pull('producto'),
            SyncSpec.local('persona'),
          ], allEntities: {'venta', 'producto', 'persona'}),
          transport: transporte,
          jobs: InMemoryJobStore(),
          store: InMemoryLocalStore(),
          backup: BackupService(
            archive: FakeArchive(authorized: true),
            crypto: FakeCrypto(llave: 'nuevo'),
            snapshot: FakeSnapshot(),
          ),
        );

    /// El servicio que baja la cadena de [llave] (cada teléfono viejo tiene la suya).
    BackupService servicioDe(String llave) => BackupService(
          archive: drive,
          crypto: FakeCrypto(llave: llave),
          snapshot: nuevo,
        );

    setUp(() async {
      origenB = FakeSnapshot();
      transporte = FakeSyncTransport();
      // El teléfono más viejo hizo 2 respaldos; el que lo reemplazó, 3 (después).
      await _cadena(drive, origen,
          partes: 2, llave: 'a', prefijo: 'a', marca: 'a-');
      await _cadena(drive, origenB,
          partes: 3, llave: 'b', prefijo: 'b', marca: 'b-');
      motor = armar();
    });

    tearDown(() => motor.dispose());

    test('baja las dos cadenas y las aplica juntas, en una sola operación',
        () async {
      final informe = await motor.recover(sources: [
        RecoverySource(backup: servicioDe('a'), keyId: 'id-a'),
        RecoverySource(backup: servicioDe('b'), keyId: 'id-b'),
      ]);

      expect(nuevo.chainsRestored, hasLength(2));
      expect(nuevo.chainsRestored.map((c) => c.length), [2, 3]);
      expect(nuevo.restored!.keys, containsAll(['a1', 'a2', 'b1', 'b2', 'b3']));
      expect([informe.partial, informe.partsRestored, informe.partsTotal],
          [false, 5, 5]);
      expect(informe.backupDates, hasLength(2));
      expect(informe.backupDate, informe.backupDates.last,
          reason: 'la fecha del informe es la del respaldo más nuevo');
    });

    test('el avance suma las partes de todas las cadenas: «3/5»', () async {
      final avances = <(int, int)>[];

      await motor.recover(
        sources: [
          RecoverySource(backup: servicioDe('a'), keyId: 'id-a'),
          RecoverySource(backup: servicioDe('b'), keyId: 'id-b'),
        ],
        onProgress: (p) {
          if (p.phase == RecoveryPhase.downloading) {
            avances.add((p.done, p.total));
          }
        },
      );

      expect(avances, [(0, 5), (1, 5), (2, 5), (3, 5), (4, 5)]);
    });

    test('el pull parte del watermark de la cadena más vieja, no de la más nueva',
        () async {
      await motor.recover(sources: [
        // Al revés a propósito: el orden en que se pasan no cambia cuál es la más vieja.
        RecoverySource(backup: servicioDe('b'), keyId: 'id-b'),
        RecoverySource(backup: servicioDe('a'), keyId: 'id-a'),
      ]);

      expect(transporte.pulls.first.watermark, 'a-2',
          reason: 'lo que solo tenía la cadena vieja tiene que bajar también');
    });

    test('una cadena sin base usable se salta y la otra entra', () async {
      drive.corrupt('backup-1');

      final informe = await motor.recover(sources: [
        RecoverySource(backup: servicioDe('a'), keyId: 'id-a'),
        RecoverySource(backup: servicioDe('b'), keyId: 'id-b'),
      ]);

      expect(nuevo.chainsRestored, hasLength(1));
      expect(nuevo.restored!.keys, containsAll(['b1', 'b2', 'b3']));
      expect(nuevo.restored!.keys, isNot(contains('a1')));
      expect([informe.partsRestored, informe.backupDates.length], [3, 1]);
    });

    test('una cadena cuya base no se descifra se salta y la otra entra', () async {
      final informe = await motor.recover(sources: [
        RecoverySource(
          backup: BackupService(
            archive: drive,
            crypto: _CryptoQueNoAbre(llave: 'a'),
            snapshot: nuevo,
          ),
          keyId: 'id-a',
        ),
        RecoverySource(backup: servicioDe('b'), keyId: 'id-b'),
      ]);

      expect(nuevo.chainsRestored, hasLength(1));
      expect(nuevo.restored!.keys, containsAll(['b1', 'b2', 'b3']));
      expect(nuevo.restored!.keys, isNot(contains('a1')));
      expect([informe.partsRestored, informe.backupDates.length], [3, 1],
          reason: 'la que no abrió queda fuera de las fechas: la app la cuenta en «sin abrir»');
    });

    test('si ninguna base se descifra, no hay respaldo y la DB no se toca', () async {
      final informe = await motor.recover(sources: [
        for (final k in ['a', 'b'])
          RecoverySource(
            backup: BackupService(
              archive: drive,
              crypto: _CryptoQueNoAbre(llave: k),
              snapshot: nuevo,
            ),
            keyId: 'id-$k',
          ),
      ]);

      expect(informe.hadBackup, isFalse);
      expect(nuevo.restored, isNull);
    });

    test('si ninguna tiene base usable, no hay respaldo y la DB no se toca',
        () async {
      drive
        ..corrupt('backup-1')
        ..corrupt('backup-3');

      final informe = await motor.recover(sources: [
        RecoverySource(backup: servicioDe('a'), keyId: 'id-a'),
        RecoverySource(backup: servicioDe('b'), keyId: 'id-b'),
      ]);

      expect(informe.hadBackup, isFalse);
      expect(nuevo.restored, isNull);
    });

    test('un eslabón dañado de una cadena la deja parcial; la otra entra entera',
        () async {
      drive.corrupt('backup-5'); // el último de la cadena b

      final informe = await motor.recover(sources: [
        RecoverySource(backup: servicioDe('a'), keyId: 'id-a'),
        RecoverySource(backup: servicioDe('b'), keyId: 'id-b'),
      ]);

      expect(informe.partial, isTrue);
      expect([informe.partsRestored, informe.partsTotal], [4, 5]);
      expect(nuevo.restored!.keys, isNot(contains('b3')));
    });

    test('si aplicar falla, no queda registrado nada restaurado y el error sube',
        () async {
      nuevo.failOnRestore = true;

      await expectLater(
        motor.recover(sources: [
          RecoverySource(backup: servicioDe('a'), keyId: 'id-a'),
          RecoverySource(backup: servicioDe('b'), keyId: 'id-b'),
        ]),
        throwsStateError,
      );
      expect(nuevo.restored, isNull);
    });

    test('cancelar entre una cadena y la otra no toca la DB', () async {
      final cancelar = RecoveryCancelToken();

      await expectLater(
        motor.recover(
          cancel: cancelar,
          sources: [
            RecoverySource(backup: servicioDe('a'), keyId: 'id-a'),
            RecoverySource(backup: servicioDe('b'), keyId: 'id-b'),
          ],
          onProgress: (p) {
            if (p.phase == RecoveryPhase.downloading && p.done == 2) {
              cancelar.cancel();
            }
          },
        ),
        throwsA(isA<RecoveryCancelled>()),
      );
      expect(nuevo.restored, isNull);
    });

    test('con una sola fuente es la recuperación de siempre', () async {
      final informe = await motor.recover(sources: [
        RecoverySource(backup: servicioDe('a'), keyId: 'id-a'),
      ]);

      expect(nuevo.chainsRestored, hasLength(1));
      expect(informe.backupDates, hasLength(1));
      expect(nuevo.restored!.keys, containsAll(['a1', 'a2']));
    });

    test('sin fuentes no hay respaldo: solo reconcilia', () async {
      final informe = await motor.recover(sources: const []);

      expect(informe.hadBackup, isFalse);
      expect(informe.backupDates, isEmpty);
    });

    test('reintentar después de restaurar no vuelve a aplicar las cadenas',
        () async {
      final fuentes = [
        RecoverySource(backup: servicioDe('a'), keyId: 'id-a'),
        RecoverySource(backup: servicioDe('b'), keyId: 'id-b'),
      ];
      await motor.recover(sources: fuentes);
      nuevo.chainsRestored = [];

      final segundo = await motor.recover(sources: fuentes);

      expect(nuevo.chainsRestored, isEmpty,
          reason: 'volver a restaurar pisaría lo reconciliado');
      expect(segundo.backupDate, isNotNull);
    });
  });

  group('recover() con un servicio de restauración propio', () {
    SyncEngine armar(BackupService viva, FakeSyncTransport transport) =>
        SyncEngine(
          specs: SpecRegistry([
            SyncSpec.push('venta', critical: true),
            SyncSpec.pull('producto'),
            SyncSpec.local('persona'),
          ], allEntities: {'venta', 'producto', 'persona'}),
          transport: transport,
          jobs: InMemoryJobStore(),
          store: InMemoryLocalStore(),
          backup: viva,
        );

    test('restaura con el servicio pasado y reporta el avance por paso', () async {
      await _cadena(drive, origen);
      final viva = BackupService(
        archive: FakeArchive(authorized: true),
        crypto: FakeCrypto(llave: 'nuevo'),
        snapshot: FakeSnapshot(),
      );
      final motor = armar(viva, FakeSyncTransport());
      final fases = <RecoveryPhase>[];

      final informe = await motor.recover(
        backup: restaurador,
        keyId: 'id-a',
        onProgress: (p) {
          if (fases.isEmpty || fases.last != p.phase) fases.add(p.phase);
        },
      );

      expect(informe.hadBackup, isTrue);
      expect([informe.partial, informe.partsRestored, informe.partsTotal],
          [false, 4, 4]);
      expect(nuevo.restored, isNotNull);
      expect(fases, [
        RecoveryPhase.searching,
        RecoveryPhase.downloading,
        RecoveryPhase.applying,
        RecoveryPhase.replaying,
        RecoveryPhase.reconciling,
        RecoveryPhase.done,
      ]);
      await motor.dispose();
    });

    test('un restore parcial queda dicho en el reporte', () async {
      await _cadena(drive, origen);
      drive.corrupt('backup-4');
      final motor = armar(
        BackupService(
          archive: FakeArchive(authorized: true),
          crypto: FakeCrypto(llave: 'nuevo'),
          snapshot: FakeSnapshot(),
        ),
        FakeSyncTransport(),
      );

      final informe = await motor.recover(backup: restaurador);

      expect(informe.partial, isTrue);
      expect([informe.partsRestored, informe.partsTotal], [3, 4]);
      expect(informe.backupDate, isNotNull,
          reason: 'la fecha es la de la última parte buena');
      await motor.dispose();
    });

    test('lo restaurado entra en el próximo respaldo: arranca de una base nueva',
        () async {
      await _cadena(drive, origen);
      final propio = FakeArchive(authorized: true);
      final snapPropio = FakeSnapshot();
      final viva = BackupService(
        archive: propio,
        crypto: FakeCrypto(llave: 'nuevo'),
        snapshot: snapPropio,
      );
      // El teléfono nuevo ya había hecho su primer respaldo (al conectar Drive).
      await viva.backupNow(watermark: 'w-0');
      final motor = armar(viva, FakeSyncTransport());

      await motor.recover(backup: restaurador, keyId: 'id-a');
      final siguiente = await viva.backupNow(watermark: 'w-1');

      expect(siguiente.isBase, isTrue,
          reason: 'un incremental no vería lo restaurado: conserva su fecha vieja');
      await motor.dispose();
    });

    test('cancelar en la descarga no toca la DB ni llega a la reconciliación',
        () async {
      await _cadena(drive, origen);
      final transport = FakeSyncTransport();
      final motor = armar(
        BackupService(
          archive: FakeArchive(authorized: true),
          crypto: FakeCrypto(llave: 'nuevo'),
          snapshot: FakeSnapshot(),
        ),
        transport,
      );
      final cancelar = RecoveryCancelToken()..cancel();

      await expectLater(
        motor.recover(backup: restaurador, cancel: cancelar),
        throwsA(isA<RecoveryCancelled>()),
      );
      expect(nuevo.restored, isNull);
      await motor.dispose();
    });

    test('sin red por un rato, el restore espera la conexión del motor y sigue',
        () async {
      await _cadena(drive, origen);
      drive
        ..fallas = 1
        ..soloEn = 'backup-2';
      final conexion = FakeConnectivityPort();
      final motor = SyncEngine(
        specs: SpecRegistry([
          SyncSpec.push('venta', critical: true),
          SyncSpec.local('persona'),
        ], allEntities: {'venta', 'persona'}),
        transport: FakeSyncTransport(),
        jobs: InMemoryJobStore(),
        store: InMemoryLocalStore(),
        connectivity: conexion,
      );

      final informe = await motor.recover(backup: restaurador);

      expect(informe.partsRestored, 4);
      await motor.dispose();
    });
  });
}

/// Un [SnapshotPort] que rechaza el respaldo por ser de un esquema más nuevo, como hace
/// la app antes de abrir nada.
class _SnapshotDeEsquemaNuevo implements SnapshotPort {
  bool tocada = false;

  @override
  Future<List<int>> export({DateTime? since}) async => const [];

  @override
  Future<void> restore(List<List<int>> payloadsInOrder) async {
    throw const SnapshotNewerSchemaException(backupSchema: 30, appSchema: 22);
  }

  @override
  Future<void> restoreChains(List<List<List<int>>> chains) => restore(const []);
}
