// Lo que sube de la agenda, las visitas y la cache de la casa: las claves del JSON son exactamente
// las columnas de la tabla local (ni una más, y menos una nota o un dato de persona).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/data/models/agenda_model.dart';
import 'package:colportores_mobile/features/agenda/data/models/visita_model.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/data/models/house_status_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/color_house_status.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/drift.dart' show Table, TableInfo, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo()));
  tearDown(() => db.close());

  Set<String> columnas(TableInfo<Table, Object?> tabla) => {for (final c in tabla.$columns) c.name};

  group('AgendaModel', () {
    test('toJson trae las columnas de la tabla agenda, ni una más', () {
      final json = AgendaModel.fromEntity(agendaDe('age-1')).toJson();

      expect(json.keys.toSet(), columnas(db.agendas));
    });

    test('toJson usa los códigos del servidor, el booleano y las fechas en ISO UTC', () {
      final agenda = agendaDe(
        'age-1',
        tipo: TipoAgenda.cobranza,
        estado: EstadoAgenda.cumplida,
        esEstricta: true,
        slot: 'afternoon',
        visitaId: 'vis-1',
      );

      final json = AgendaModel.fromEntity(agenda).toJson();

      expect(json['tipo'], 'COBRANZA');
      expect(json['estado'], 'CUMPLIDA');
      expect(json['es_estricta'], true);
      expect(json['slot_codigo'], 'afternoon');
      expect(json['visita_id'], 'vis-1');
      expect(json['fecha_programada'], '2026-10-25T14:00:00.000Z');
      expect(json['created_at'], '2026-10-23T13:45:10.123Z');
      expect(json['deleted_at'], isNull);
    });
  });

  group('VisitaModel', () {
    test('toJson trae las columnas de la tabla visita, ni una más', () {
      final json = VisitaModel.fromEntity(visitaDe('vis-1')).toJson();

      expect(json.keys.toSet(), columnas(db.visitas));
    });

    test('toJson usa el código del resultado y deja la jornada en null si no hay', () {
      final json = VisitaModel.fromEntity(
        visitaDe('vis-1', resultado: TipoResultadoVisita.noContesto),
      ).toJson();

      expect(json['tipo_resultado'], 'NO_CONTESTO');
      expect(json['jornada_id'], isNull);
      expect(json['fecha'], '2026-10-23T13:45:10.123Z');
    });
  });

  group('HouseStatusModel', () {
    test('toJson trae las columnas de la tabla house_status, ni una más', () {
      final json = HouseStatusModel(
        ubicacionId: 'ub-1',
        lat: -34.9,
        lon: -56.16,
        tipoUbicacion: TipoUbicacion.edificio,
        color: ColorHouseStatus.sinContestar,
        auditoria: auditoriaDe(),
      ).toJson();

      expect(json.keys.toSet(), columnas(db.houseStatuses));
      expect(json['tipo_ubicacion'], 'EDIFICIO');
      expect(json['color'], 'SIN_CONTESTAR');
      expect(json['prioridad'], 6);
    });
  });
}
