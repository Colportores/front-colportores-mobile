// QA de #273 / PR #640: el resumen de la candidata (estado de visita y espacios) también sale de los
// otros dos caminos que frenan por duplicado: modificar la ubicación (vista 07) y reactivar una baja.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/color_house_status.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

double _grados(double metros) => metros / 111195.08;

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 13, 45, 10, 123);
  const criterio = CriterioDuplicadoUbicacion();

  UbicacionModel ubicacion({
    required String id,
    String calle = 'Av. Italia',
    String numero = '1234',
    double metrosAlNorte = 0,
    DateTime? deletedAt,
  }) => UbicacionModel(
    id: id,
    tipo: TipoUbicacion.casa,
    calle: calle,
    numero: numero,
    lat: -34.891 + _grados(metrosAlNorte),
    lon: -56.125,
    ciudadId: 'mvd',
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1', deletedAt: deletedAt),
  );

  late AppDatabase db;
  late UbicacionLocalDataSourceDrift local;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    local = UbicacionLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria());
  });
  tearDown(() => db.close());

  Future<void> colorDe(String id, ColorHouseStatus color) => db
      .into(db.houseStatuses)
      .insert(
        HouseStatusesCompanion.insert(
          ubicacionId: id,
          lat: -34.891,
          lon: -56.125,
          tipoUbicacion: 'CASA',
          color: color.codigo,
          prioridad: color.prioridad,
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> espacioEn(String id, String espacioId) => db
      .into(db.espacios)
      .insert(
        EspaciosCompanion.insert(id: espacioId, ubicacionId: id, createdAt: t0, updatedAt: t0),
      );

  test(
    'al modificar una ubicación hacia la dirección de otra, la candidata trae estado y espacios',
    () async {
      await local.insertar(ubicacion(id: 'otra', metrosAlNorte: 300));
      await colorDe('otra', ColorHouseStatus.cobranzaPendiente);
      await espacioEn('otra', 'e1');
      await espacioEn('otra', 'e2');
      await local.insertar(
        ubicacion(id: 'mia', calle: 'Comercio', numero: '10', metrosAlNorte: 900),
      );

      try {
        await local.actualizar(
          ubicacion(id: 'mia'),
          baseUpdatedAt: t0,
          duplicados: criterio,
        );
        fail('debía frenarse por duplicada');
      } on UbicacionDuplicadaException catch (e) {
        final c = e.candidatas.single;
        expect(c.ubicacion.id, 'otra');
        expect(c.estado, EstadoCasa.cobranzaPendiente);
        expect(c.cantidadEspacios, 2);
      }
    },
  );

  test(
    'muchas candidatas a la vez (30): cada una trae lo suyo y el orden por distancia se mantiene',
    () async {
      for (var i = 0; i < 30; i++) {
        await local.insertar(ubicacion(id: 'c$i', calle: 'Comercio', metrosAlNorte: 1.0 + i * 0.1));
        if (i.isEven) await colorDe('c$i', ColorHouseStatus.rechazo);
        for (var k = 0; k < i % 3; k++) {
          await espacioEn('c$i', 'e$i-$k');
        }
      }
      try {
        await local.insertar(
          ubicacion(id: 'nueva', calle: 'Otra', numero: '9'),
          duplicados: criterio,
        );
        fail('debía frenarse por duplicada');
      } on UbicacionDuplicadaException catch (e) {
        expect(e.candidatas, hasLength(30));
        for (final c in e.candidatas) {
          final i = int.parse(c.ubicacion.id.substring(1));
          expect(
            c.estado,
            i.isEven ? EstadoCasa.rechazo : EstadoCasa.sinVisita,
            reason: c.ubicacion.id,
          );
          expect(c.cantidadEspacios, i % 3, reason: c.ubicacion.id);
        }
        final distancias = [for (final c in e.candidatas) c.distanciaMetros];
        expect(distancias, [...distancias]..sort());
      }
    },
  );
}
