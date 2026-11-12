// Personas de un espacio (HU-UBI-008) contra las tablas reales: AppDatabase en memoria, mismo esquema
// y mismas restricciones que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/contador_personas_espacio.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 22, 13, 45, 10, 123);

  Auditoria auditoria({DateTime? creada, DateTime? deletedAt}) => Auditoria(
    createdAt: creada ?? t0,
    updatedAt: creada ?? t0,
    createdBy: 'col-1',
    deletedAt: deletedAt,
  );

  Persona persona(
    String id, {
    String nombre = 'Ana',
    String apellido = 'Martínez',
    String? telefono = '099 123 456',
    DateTime? creada,
  }) => Persona(
    id: id,
    nombre: nombre,
    apellido: apellido,
    telefono: telefono,
    auditoria: auditoria(creada: creada),
  );

  EspacioPersona vinculo(String personaId, {String espacioId = 'esp-1', DateTime? creada}) =>
      EspacioPersona(
        id: 'ep-$personaId',
        espacioId: espacioId,
        personaId: personaId,
        auditoria: auditoria(creada: creada),
      );

  NotaPersona nota(String personaId, {String texto = 'Prefiere de tarde'}) => NotaPersona(
    id: 'nota-$personaId',
    personaId: personaId,
    texto: texto,
    auditoria: auditoria(),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift ubicaciones;
  late PersonaLocalDataSourceDrift local;

  Future<void> sembrarEdificio({DateTime? ubicacionDeBaja, DateTime? espacioDeBaja}) async {
    await ubicaciones.insertar(
      UbicacionModel(
        id: 'ub-1',
        tipo: TipoUbicacion.edificio,
        calle: 'Mataojo',
        numero: '2044',
        lat: -34.89,
        lon: -56.16,
        ciudadId: 'mvd',
        auditoria: auditoria(),
      ),
    );
    await ubicaciones.insertarEspacio(
      EspacioModel(
        id: 'esp-1',
        ubicacionId: 'ub-1',
        numeroDepto: '101',
        auditoria: auditoria(deletedAt: espacioDeBaja),
      ),
    );
    if (ubicacionDeBaja != null) {
      // La baja va después: dar de alta un espacio en una ubicación de baja lo rechaza la propia DB.
      await db.customStatement('UPDATE ubicacion SET deleted_at = ? WHERE id = ?', [
        ubicacionDeBaja.millisecondsSinceEpoch,
        'ub-1',
      ]);
    }
    encolador.encolados.clear();
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    local = PersonaLocalDataSourceDrift(db, encolador: encolador);
  });

  tearDown(() => db.close());

  Future<int> filas(String tabla) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $tabla').getSingle()).read<int>('n');

  Matcher rechaza(MotivoRechazoPersona motivo) =>
      throwsA(isA<PersonaRechazadaException>().having((e) => e.motivo, 'motivo', motivo));

  group('registrar', () {
    test('dado un edificio, cuando registra una persona con nota, guarda las tres filas', () async {
      await sembrarEdificio();

      final r = await local.registrar(
        persona: persona('per-1'),
        vinculo: vinculo('per-1'),
        nota: nota('per-1'),
      );

      expect(r.yaEstaba, isFalse);
      expect(r.persona.nombre, 'Ana');
      expect(await filas('persona'), 1);
      expect(await filas('espacio_persona'), 1);
      expect(await filas('nota'), 1);
      final fila = await db
          .customSelect('SELECT target_type, target_id, texto FROM nota')
          .getSingle();
      expect(fila.read<String>('target_type'), 'PERSONA');
      expect(fila.read<String>('target_id'), 'per-1');
      expect(fila.read<String>('texto'), 'Prefiere de tarde');
    });

    test('dado el alta sin nota, cuando registra, no crea ninguna fila de nota', () async {
      await sembrarEdificio();

      await local.registrar(persona: persona('per-1'), vinculo: vinculo('per-1'));

      expect(await filas('nota'), 0);
    });

    test('dado un alta, cuando registra, encola solo el vínculo con ids opacos: ni la persona ni '
        'la nota (ADR-017)', () async {
      await sembrarEdificio();

      await local.registrar(
        persona: persona('per-1'),
        vinculo: vinculo('per-1'),
        nota: nota('per-1'),
      );

      expect(encolador.encolados, hasLength(1));
      final cambio = encolador.encolados.single;
      expect(cambio.entidad, 'espacio_persona');
      expect(cambio.operacion, OperacionSync.insert);
      expect(cambio.payload['id'], 'ep-per-1');
      expect(cambio.payload['espacio_id'], 'esp-1');
      expect(cambio.payload['persona_id'], 'per-1');
      expect(cambio.payload['created_by'], 'col-1');
      final texto = cambio.payload.toString();
      for (final dato in ['Ana', 'Martínez', '099 123 456', 'Prefiere de tarde']) {
        expect(texto, isNot(contains(dato)));
      }
    });

    test('dado el mismo alta repetida (doble toque o reintento), cuando registra otra vez, no '
        'duplica nada ni vuelve a encolar', () async {
      await sembrarEdificio();
      await local.registrar(
        persona: persona('per-1'),
        vinculo: vinculo('per-1'),
        nota: nota('per-1'),
      );

      final segunda = await local.registrar(
        persona: persona('per-1', nombre: 'Otro'),
        vinculo: vinculo('per-1'),
        nota: nota('per-1'),
      );

      expect(segunda.yaEstaba, isTrue);
      expect(segunda.persona.nombre, 'Ana');
      expect(await filas('persona'), 1);
      expect(await filas('espacio_persona'), 1);
      expect(await filas('nota'), 1);
      expect(encolador.encolados, hasLength(1));
    });

    test('dado el mismo alta lanzada dos veces a la vez, cuando se serializan, queda una sola '
        'persona', () async {
      await sembrarEdificio();

      await Future.wait([
        local.registrar(persona: persona('per-1'), vinculo: vinculo('per-1')),
        local.registrar(persona: persona('per-1'), vinculo: vinculo('per-1')),
      ]);

      expect(await filas('persona'), 1);
      expect(encolador.encolados, hasLength(1));
    });

    test('dado que el espacio no existe, cuando registra, lo rechaza y no escribe nada', () async {
      await expectLater(
        local.registrar(persona: persona('per-1'), vinculo: vinculo('per-1')),
        rechaza(MotivoRechazoPersona.espacioInexistente),
      );

      expect(await filas('persona'), 0);
      expect(await filas('espacio_persona'), 0);
      expect(encolador.encolados, isEmpty);
    });

    test('dado un espacio dado de baja, cuando registra, lo rechaza (solo lectura)', () async {
      await sembrarEdificio(espacioDeBaja: t0.add(const Duration(days: 1)));

      await expectLater(
        local.registrar(persona: persona('per-1'), vinculo: vinculo('per-1')),
        rechaza(MotivoRechazoPersona.espacioDeBaja),
      );
      expect(await filas('persona'), 0);
    });

    test(
      'dado una ubicación dada de baja, cuando registra en uno de sus espacios, lo rechaza',
      () async {
        await sembrarEdificio(ubicacionDeBaja: t0.add(const Duration(days: 1)));

        await expectLater(
          local.registrar(persona: persona('per-1'), vinculo: vinculo('per-1')),
          rechaza(MotivoRechazoPersona.ubicacionDeBaja),
        );
      },
    );

    test('dado que el motor de sync rechaza el encolado, cuando registra, revierte todo', () async {
      await sembrarEdificio();
      encolador.fallarCon = StateError('motor apagado');

      await expectLater(
        local.registrar(persona: persona('per-1'), vinculo: vinculo('per-1'), nota: nota('per-1')),
        throwsStateError,
      );

      expect(await filas('persona'), 0);
      expect(await filas('espacio_persona'), 0);
      expect(await filas('nota'), 0);
    });

    test(
      'dado que la nota no se puede guardar, cuando registra, revierte la persona y el vínculo',
      () async {
        await sembrarEdificio();
        await local.registrar(
          persona: persona('per-1'),
          vinculo: vinculo('per-1'),
          nota: nota('per-1'),
        );
        // Misma nota (mismo id) para otra persona: choca con la clave primaria.
        final choque = NotaPersona(
          id: 'nota-per-1',
          personaId: 'per-2',
          texto: 'x',
          auditoria: auditoria(),
        );

        await expectLater(
          local.registrar(persona: persona('per-2'), vinculo: vinculo('per-2'), nota: choque),
          throwsA(isA<Object>()),
        );

        expect(await filas('persona'), 1);
        expect(await filas('espacio_persona'), 1);
      },
    );
  });

  group('observarDelEspacio y activasEn', () {
    test('dado un espacio sin personas, cuando se observa, emite una lista vacía', () async {
      await sembrarEdificio();

      expect(await local.observarDelEspacio('esp-1').first, isEmpty);
      expect(await local.activasEn('esp-1'), 0);
    });

    test(
      'dado varias personas, cuando se observa, salen en el orden en que se agregaron',
      () async {
        await sembrarEdificio();
        await local.registrar(
          persona: persona('per-b', nombre: 'Bruno', creada: t0.add(const Duration(minutes: 1))),
          vinculo: vinculo('per-b'),
        );
        await local.registrar(
          persona: persona('per-a', nombre: 'Ana', creada: t0),
          vinculo: vinculo('per-a'),
        );

        final lista = await local.observarDelEspacio('esp-1').first;

        expect(lista.map((c) => c.persona.nombre), ['Ana', 'Bruno']);
        expect(lista.first.vinculo.espacioId, 'esp-1');
        expect(await local.activasEn('esp-1'), 2);
      },
    );

    test('dado que se agrega una persona con la lista abierta, cuando se observa, emite la nueva '
        'lista', () async {
      await sembrarEdificio();
      final emisiones = <int>[];
      final suscripcion = local.observarDelEspacio('esp-1').listen((l) => emisiones.add(l.length));

      await pumpEventQueue();
      await local.registrar(persona: persona('per-1'), vinculo: vinculo('per-1'));
      await pumpEventQueue();
      await suscripcion.cancel();

      expect(emisiones, containsAllInOrder([0, 1]));
    });

    test(
      'dado una persona de otro espacio o dada de baja, cuando se observa, no aparece',
      () async {
        await sembrarEdificio();
        await ubicaciones.insertarEspacio(
          EspacioModel(
            id: 'esp-2',
            ubicacionId: 'ub-1',
            numeroDepto: '102',
            auditoria: auditoria(),
          ),
        );
        await local.registrar(persona: persona('per-1'), vinculo: vinculo('per-1'));
        await local.registrar(
          persona: persona('per-2'),
          vinculo: vinculo('per-2', espacioId: 'esp-2'),
        );
        await local.registrar(persona: persona('per-3'), vinculo: vinculo('per-3'));
        await db.customStatement("UPDATE persona SET deleted_at = 1 WHERE id = 'per-3'");

        final lista = await local.observarDelEspacio('esp-1').first;

        expect(lista.map((c) => c.persona.id), ['per-1']);
        expect(await local.activasEn('esp-1'), 1);
        expect(await local.activasEn('esp-2'), 1);
      },
    );

    test('dado que es el adaptador del puerto de la baja de espacios, cuando se lo usa como '
        'ContadorPersonasEspacio, cuenta las personas activas', () async {
      await sembrarEdificio();
      await local.registrar(persona: persona('per-1'), vinculo: vinculo('per-1'));

      final ContadorPersonasEspacio contador = local;

      expect(await contador.activasEn('esp-1'), 1);
    });
  });

  test(
    'dado un listado largo y nombres largos, cuando se guardan y se leen, vuelven enteros',
    () async {
      await sembrarEdificio();
      final largo = 'Ñ' * 60;
      for (var i = 0; i < 120; i++) {
        await local.registrar(
          persona: persona(
            'per-$i',
            nombre: largo,
            creada: t0.add(Duration(seconds: i)),
          ),
          vinculo: vinculo('per-$i'),
        );
      }

      final lista = await local.observarDelEspacio('esp-1').first;

      expect(lista, hasLength(120));
      expect(lista.first.persona.nombre, largo);
      expect(lista.last.persona.id, 'per-119');
    },
  );
}
