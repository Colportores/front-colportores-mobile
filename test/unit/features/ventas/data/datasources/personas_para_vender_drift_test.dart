// Las personas a las que se les puede vender desde la pestaña Ventas (#546) contra las tablas reales:
// AppDatabase en memoria, mismo esquema y mismas restricciones que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/personas_para_vender_drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 22, 13, 45, 10, 123);
  final baja = DateTime.utc(2026, 10, 25, 9, 30);

  Auditoria auditoria({String creador = 'col-1'}) =>
      Auditoria(createdAt: t0, updatedAt: t0, createdBy: creador);

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift ubicaciones;
  late PersonaLocalDataSourceDrift personas;
  late PersonasParaVenderDrift lector;

  Future<void> sembrarEdificio({String ubicacionId = 'ub-1', String calle = 'Mataojo'}) async {
    await ubicaciones.insertar(
      UbicacionModel(
        id: ubicacionId,
        tipo: TipoUbicacion.edificio,
        calle: calle,
        numero: '2044',
        lat: -34.89,
        lon: -56.16,
        ciudadId: 'mvd',
        auditoria: auditoria(),
      ),
    );
  }

  Future<void> sembrarDepto(String espacioId, {String ubicacionId = 'ub-1', String? depto}) =>
      ubicaciones.insertarEspacio(
        EspacioModel(
          id: espacioId,
          ubicacionId: ubicacionId,
          numeroDepto: depto ?? espacioId.toUpperCase(),
          auditoria: auditoria(),
        ),
      );

  Future<void> sembrarPersona(
    String id, {
    String espacioId = 'esp-1',
    String nombre = 'Ana',
    String creador = 'col-1',
  }) async {
    await personas.registrar(
      persona: Persona(
        id: id,
        nombre: nombre,
        apellido: 'Martínez',
        telefono: '099 123 456',
        auditoria: auditoria(creador: creador),
      ),
      vinculo: EspacioPersona(
        id: 'ep-$id',
        espacioId: espacioId,
        personaId: id,
        auditoria: auditoria(creador: creador),
      ),
    );
  }

  Future<void> marcarBaja(String tabla, String id) => db.customStatement(
    'UPDATE $tabla SET deleted_at = ? WHERE id = ?',
    [baja.millisecondsSinceEpoch, id],
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    personas = PersonaLocalDataSourceDrift(db, encolador: encolador);
    lector = PersonasParaVenderDrift(db);
    await sembrarEdificio();
    await sembrarDepto('esp-1', depto: '3B');
  });

  tearDown(() => db.close());

  Future<List<String>> ids() async =>
      [for (final p in await lector.observar('col-1').first) p.espacioPersonaId]..sort();

  test('dada una persona activa en un depto activo, cuando se lee, trae la persona, el vínculo y '
      'dónde está', () async {
    await sembrarPersona('per-1');

    final lista = await lector.observar('col-1').first;

    expect(lista, hasLength(1));
    final p = lista.single;
    expect(p.persona.id, 'per-1');
    expect(p.persona.nombre, 'Ana');
    expect(p.persona.apellido, 'Martínez');
    expect(p.espacioPersonaId, 'ep-per-1');
    expect(p.espacioId, 'esp-1');
    expect(p.espacio.numeroDepto, '3B');
    expect(p.ubicacion.id, 'ub-1');
    expect(p.ubicacion.calle, 'Mataojo');
    expect(p.ubicacion.ciudadId, 'mvd');
  });

  test('dada la base sin personas, cuando se lee, la lista queda vacía', () async {
    expect(await ids(), isEmpty);
  });

  test('dada una persona dada de baja, cuando se lee, no entra (es de solo lectura)', () async {
    await sembrarPersona('per-1');
    await sembrarPersona('per-2', nombre: 'Berta');
    await marcarBaja('persona', 'per-1');

    expect(await ids(), ['ep-per-2']);
  });

  test('dado un vínculo dado de baja, cuando se lee, esa persona no entra', () async {
    await sembrarPersona('per-1');
    await marcarBaja('espacio_persona', 'ep-per-1');

    expect(await ids(), isEmpty);
  });

  test('dado un depto dado de baja, cuando se lee, sus personas no entran', () async {
    await sembrarDepto('esp-2', depto: '4C');
    await sembrarPersona('per-1');
    await sembrarPersona('per-2', espacioId: 'esp-2');
    await marcarBaja('espacio', 'esp-2');

    expect(await ids(), ['ep-per-1']);
  });

  test('dada una ubicación dada de baja, cuando se lee, sus personas no entran', () async {
    await sembrarEdificio(ubicacionId: 'ub-2', calle: 'Rivera');
    await sembrarDepto('esp-2', ubicacionId: 'ub-2', depto: '1A');
    await sembrarPersona('per-1');
    await sembrarPersona('per-2', espacioId: 'esp-2');
    await marcarBaja('ubicacion', 'ub-2');

    expect(await ids(), ['ep-per-1']);
  });

  test('dada la persona de otro colportor, cuando se lee, no entra', () async {
    await sembrarPersona('per-1');
    await sembrarPersona('per-2', creador: 'col-2');

    expect(await ids(), ['ep-per-1']);
  });

  test('dada una persona en dos deptos, cuando se lee, hay una fila por vínculo', () async {
    await sembrarDepto('esp-2', depto: '4C');
    await sembrarPersona('per-1');
    await personas.registrar(
      persona: Persona(id: 'per-3', nombre: 'Otra', apellido: '', auditoria: auditoria()),
      vinculo: EspacioPersona(
        id: 'ep-per-3',
        espacioId: 'esp-2',
        personaId: 'per-3',
        auditoria: auditoria(),
      ),
    );

    final lista = await lector.observar('col-1').first;

    expect({for (final p in lista) p.espacioId}, {'esp-1', 'esp-2'});
  });

  test(
    'dada una lista abierta, cuando se da de alta o de baja a alguien, se actualiza sola',
    () async {
      await sembrarPersona('per-1');
      final vistas = <List<String>>[];
      final suscripcion = lector
          .observar('col-1')
          .listen((lista) => vistas.add([for (final p in lista) p.espacioPersonaId]..sort()));
      addTearDown(suscripcion.cancel);
      await pumpEventQueue();

      await sembrarPersona('per-2', nombre: 'Berta');
      await pumpEventQueue();
      await personas.darDeBaja(personaId: 'per-1', ahora: baja);
      await pumpEventQueue();

      expect(vistas.first, ['ep-per-1']);
      expect(vistas.any((v) => v.length == 2), isTrue);
      expect(vistas.last, ['ep-per-2']);
    },
  );

  test('dado un listado largo, cuando se lee, trae todos sin perder a nadie', () async {
    for (var i = 0; i < 300; i++) {
      await sembrarPersona('per-$i', nombre: 'Persona $i');
    }

    expect((await lector.observar('col-1').first), hasLength(300));
  });
}
