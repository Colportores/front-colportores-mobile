// HU-UBI-007, escenario «Nota por depto, solo en el teléfono»: «del depto solo suben al servidor
// su número y su piso». El backend sacó `espacio.descripcion` (0104, backend-supabase#79): un push
// con esa columna falla. Se prueba contra las tablas reales (AppDatabase en memoria) con una fila
// que todavía trae texto en la columna heredada, la peor situación posible.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 27, 13, 45);
  final t1 = t0.add(const Duration(minutes: 5));
  const textoHeredado = 'timbre roto, la señora Pérez';

  // Las columnas de `public.espacio` después de la migración 0104.
  const columnasDelServidor = {
    'id',
    'ubicacion_id',
    'numero_depto',
    'piso',
    'created_at',
    'updated_at',
    'created_by',
    'deleted_at',
    'sync_version',
  };

  final edificio = UbicacionModel(
    id: 'ub-1',
    tipo: TipoUbicacion.edificio,
    calle: 'Av. Italia',
    numero: '1234',
    lat: -34.891,
    lon: -56.125,
    ciudadId: 'mvd',
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
  );

  EspacioModel depto(String id, String numero, {String? piso}) => EspacioModel(
    id: id,
    ubicacionId: 'ub-1',
    numeroDepto: numero,
    piso: piso,
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift local;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    await local.insertar(edificio);
  });

  tearDown(() => db.close());

  Iterable<CambioEncolado> deptosEncolados() =>
      encolador.encolados.where((c) => c.entidad == 'espacio');

  /// Una fila de una instalación vieja: el texto libre sigue en la columna que ya no sube.
  Future<void> sembrarConTextoHeredado() => db
      .into(db.espacios)
      .insert(
        EspaciosCompanion.insert(
          id: 'e-viejo',
          ubicacionId: 'ub-1',
          numeroDepto: const Value('3B'),
          piso: const Value('3'),
          descripcion: const Value(textoHeredado),
          createdAt: t0,
          updatedAt: t0,
          createdBy: const Value('col-1'),
          syncVersion: const Value(4),
        ),
      );

  void sinNingunTextoLibre() {
    for (final c in deptosEncolados()) {
      expect(c.payload.keys.toSet(), columnasDelServidor, reason: '${c.operacion}');
      expect('${c.payload}', isNot(contains(textoHeredado)));
    }
  }

  test('dado un depto nuevo con número y piso, cuando se agrega, lo que sube es exactamente el '
      'número y el piso más la auditoría', () async {
    await local.insertarEspacio(depto('e-1', '5B', piso: '5'));

    final subido = deptosEncolados().single;
    expect(subido.operacion, OperacionSync.insert);
    expect(subido.payload.keys.toSet(), columnasDelServidor);
    expect((subido.payload['numero_depto'], subido.payload['piso']), ('5B', '5'));
  });

  test('dado un depto de una instalación vieja con texto en la columna heredada, cuando se le '
      'corrige el número, el update sube sin ese texto y la fila local no lo pierde', () async {
    await sembrarConTextoHeredado();

    final editado = await local.actualizarNumeroDepto('e-viejo', numeroDepto: '3C', ahora: t1);

    final subido = deptosEncolados().single;
    expect(subido.operacion, OperacionSync.update);
    expect((subido.payload['numero_depto'], subido.payload['piso']), ('3C', '3'));
    expect(editado.numeroDepto, '3C');
    sinNingunTextoLibre();
    final fila = await (db.select(db.espacios)..where((e) => e.id.equals('e-viejo'))).getSingle();
    expect(fila.descripcion, textoHeredado, reason: 'la columna local no se toca ni se manda');
  });

  test('dado un depto con texto heredado, cuando se da de baja y se restaura, los dos updates '
      'suben solo las columnas del servidor', () async {
    await sembrarConTextoHeredado();

    await local.darDeBajaEspacio('e-viejo', ahora: t1);
    await local.restaurarEspacio('e-viejo', ahora: t1.add(const Duration(minutes: 1)));

    expect(deptosEncolados().map((c) => c.operacion), [OperacionSync.update, OperacionSync.update]);
    sinNingunTextoLibre();
  });

  test('dado un edificio con un solo depto con texto heredado, cuando pasa a casa y su espacio '
      'queda sin número, el update sube sin ese texto', () async {
    await sembrarConTextoHeredado();
    encolador.encolados.clear();

    await local.actualizar(
      UbicacionModel(
        id: edificio.id,
        tipo: TipoUbicacion.casa,
        calle: edificio.calle,
        numero: edificio.numero,
        lat: edificio.lat,
        lon: edificio.lon,
        ciudadId: edificio.ciudadId,
        auditoria: Auditoria(createdAt: t0, updatedAt: t1, createdBy: 'col-1'),
      ),
      baseUpdatedAt: t0,
      reduceAUnEspacio: true,
    );

    final subido = deptosEncolados().single;
    expect(subido.payload['numero_depto'], isNull);
    sinNingunTextoLibre();
  });
}
