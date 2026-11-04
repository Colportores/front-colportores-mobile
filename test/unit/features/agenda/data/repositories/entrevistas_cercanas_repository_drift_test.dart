// Vista 39, R·02: la lectura de las entrevistas cercanas contra las tablas reales (AppDatabase en
// memoria): la distancia de 300 m, el tipo, el estado, las bajas y el colportor.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/entrevistas_cercanas_repository_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EntrevistasCercanasRepositoryDrift repo;

  // La casa de la agenda: lat -34.9, lon -56.16 (la de `sembrarUbicacion`).
  const centro = Coordenadas(lat: -34.9, lon: -56.16);
  final desde = DateTime.utc(2026, 10, 23, 17);

  /// Una latitud a [metros] al norte del centro (un grado de latitud son unos 111 km).
  double alNorte(double metros) => centro.lat + metros / 111195;

  Future<void> casaA(String id, double metros) async {
    await sembrarUbicacion(db, id: 'ub-$id', lat: alNorte(metros), lon: centro.lon);
    await sembrarEspacio(db, id: 'esp-$id', ubicacionId: 'ub-$id');
  }

  Future<void> entrevista(
    String id,
    String casa, {
    DateTime? cuando,
    TipoAgenda tipo = TipoAgenda.entrevista,
    EstadoAgenda estado = EstadoAgenda.programada,
    String colportor = 'col-1',
    String? slot,
    DateTime? borrada,
  }) => insertarAgenda(
    db,
    Agenda(
      id: id,
      espacioId: 'esp-$casa',
      tipo: tipo,
      fechaProgramada: cuando ?? DateTime.utc(2026, 10, 26, 19),
      slotCodigo: slot,
      estado: estado,
      colportorId: colportor,
      auditoria: auditoriaDe(borrada: borrada),
    ),
  );

  Future<List<String?>> leer({
    String espacio = 'esp-1',
    String colportor = 'col-1',
    DateTime? desdeEsto,
    double radio = 300,
  }) async => [
    for (final e in await repo.leer(
      colportorId: colportor,
      espacioId: espacio,
      desde: desdeEsto ?? desde,
      radioMetros: radio,
    ))
      e.slotCodigo ?? e.fecha.toIso8601String(),
  ];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    repo = EntrevistasCercanasRepositoryDrift(db);
    await sembrarUbicacion(db);
    await sembrarEspacio(db);
  });

  tearDown(() => db.close());

  group('dado que la casa tiene entrevistas agendadas alrededor', () {
    test('cuando una está a 299 m, entonces cuenta; a 301 m, no', () async {
      await casaA('cerca', 299);
      await casaA('lejos', 301);
      await entrevista('a-cerca', 'cerca', slot: 'cerca');
      await entrevista('a-lejos', 'lejos', slot: 'lejos');
      expect(await leer(), ['cerca']);
    });

    test('cuando la entrevista es de la misma casa (0 m), entonces cuenta', () async {
      await entrevista('a-1', '1', slot: 'misma');
      expect(await leer(), ['misma']);
    });

    test('cuando son varias, entonces vienen de la más temprana a la más tardía', () async {
      await casaA('b', 50);
      await entrevista('a-2', 'b', cuando: DateTime.utc(2026, 10, 27, 15), slot: 'tarde');
      await entrevista('a-1', 'b', cuando: DateTime.utc(2026, 10, 26, 13), slot: 'temprano');
      expect(await leer(), ['temprano', 'tarde']);
    });

    test('cuando se pide un radio más chico, entonces se usa ese', () async {
      await casaA('b', 150);
      await entrevista('a-1', 'b', slot: 'b');
      expect(await leer(radio: 100), isEmpty);
      expect(await leer(radio: 200), ['b']);
    });
  });

  group('dado lo que no cuenta', () {
    setUp(() => casaA('b', 50));

    test('cuando es una cobranza, entonces no cuenta', () async {
      await entrevista('a-1', 'b', tipo: TipoAgenda.cobranza, slot: 'x');
      expect(await leer(), isEmpty);
    });

    for (final estado in [EstadoAgenda.cumplida, EstadoAgenda.noCumplida, EstadoAgenda.cancelada]) {
      test('cuando está ${estado.codigo}, entonces no cuenta', () async {
        await entrevista('a-1', 'b', estado: estado, slot: 'x');
        expect(await leer(), isEmpty);
      });
    }

    test('cuando es de otro colportor, entonces no cuenta', () async {
      await entrevista('a-1', 'b', colportor: 'col-2', slot: 'x');
      expect(await leer(), isEmpty);
    });

    test('cuando la agenda tiene baja, entonces no cuenta', () async {
      await entrevista('a-1', 'b', borrada: DateTime.utc(2026, 10, 23), slot: 'x');
      expect(await leer(), isEmpty);
    });

    test('cuando es anterior a «desde», entonces no cuenta; justo en «desde», sí', () async {
      await entrevista('a-1', 'b', cuando: DateTime.utc(2026, 10, 23, 16, 59), slot: 'antes');
      await entrevista('a-2', 'b', cuando: DateTime.utc(2026, 10, 23, 17), slot: 'justo');
      expect(await leer(), ['justo']);
    });

    test('cuando su casa o su depto están dados de baja, entonces no cuenta', () async {
      await sembrarUbicacion(
        db,
        id: 'ub-baja',
        lat: alNorte(60),
        lon: centro.lon,
        borrada: DateTime.utc(2026, 10, 1),
      );
      await sembrarEspacio(db, id: 'esp-baja', ubicacionId: 'ub-baja');
      await sembrarEspacio(
        db,
        id: 'esp-depto',
        ubicacionId: 'ub-1',
        borrado: DateTime.utc(2026, 10, 1),
      );
      await entrevista('a-1', 'baja', slot: 'casa-baja');
      await entrevista('a-2', 'depto', slot: 'depto-baja');
      expect(await leer(), isEmpty);
    });

    test('cuando la casa de la entrevista no llegó al teléfono, entonces no cuenta', () async {
      await insertarAgenda(
        db,
        Agenda(
          id: 'a-1',
          espacioId: 'esp-fantasma',
          tipo: TipoAgenda.entrevista,
          fechaProgramada: DateTime.utc(2026, 10, 26, 19),
          colportorId: 'col-1',
          auditoria: auditoriaDe(),
        ),
      );
      expect(await leer(), isEmpty);
    });
  });

  group('dado que la casa de referencia no sirve', () {
    test('cuando el espacio no existe, entonces no hay entrevistas cercanas', () async {
      await entrevista('a-1', '1', slot: 'x');
      expect(await leer(espacio: 'esp-no-existe'), isEmpty);
    });

    test('cuando la casa de referencia tiene baja, entonces no hay entrevistas cercanas', () async {
      await entrevista('a-1', '1', slot: 'x');
      await (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-1'))).write(
        UbicacionesCompanion(deletedAt: Value(DateTime.utc(2026, 10, 1))),
      );
      expect(await leer(), isEmpty);
    });

    test('cuando está en (0, 0), entonces no hay entrevistas cercanas', () async {
      await sembrarUbicacion(db, id: 'ub-cero', lat: 0, lon: 0);
      await sembrarEspacio(db, id: 'esp-cero', ubicacionId: 'ub-cero');
      await entrevista('a-1', 'cero', slot: 'x');
      expect(await leer(espacio: 'esp-cero'), isEmpty);
    });
  });
}
