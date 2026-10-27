// La ubicación alternativa de cobranza (HU-UBI-013) contra las tablas reales: AppDatabase en memoria,
// mismo esquema y mismas restricciones que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_alternativa_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_alternativa_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 22, 13, 45, 10, 123);
  final t1 = DateTime.utc(2026, 10, 26, 9, 30);
  final t2 = DateTime.utc(2026, 10, 26, 9, 31);

  Auditoria auditoria({String? por = 'col-1'}) =>
      Auditoria(createdAt: t0, updatedAt: t0, createdBy: por);

  UbicacionModel ubicacion(
    String id, {
    TipoUbicacion tipo = TipoUbicacion.negocio,
    String? calle,
    String? numero,
    String creadaPor = 'col-1',
  }) => UbicacionModel(
    id: id,
    tipo: tipo,
    calle: calle,
    numero: numero,
    lat: -34.89,
    lon: -56.16,
    ciudadId: 'mvd',
    auditoria: auditoria(por: creadaPor),
  );

  Persona persona(String id) => Persona(
    id: id,
    nombre: 'Ana',
    apellido: 'Martínez',
    telefono: '099 123 456',
    auditoria: auditoria(),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift ubicaciones;
  late PersonaLocalDataSourceDrift personas;
  late UbicacionAlternativaLocalDataSourceDrift local;

  Future<void> registrarPersona(String id, {String espacioId = 'esp-1'}) async {
    await personas.registrar(
      persona: persona(id),
      vinculo: EspacioPersona(
        id: 'ep-$id',
        espacioId: espacioId,
        personaId: id,
        auditoria: auditoria(),
      ),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    personas = PersonaLocalDataSourceDrift(db, encolador: encolador);
    local = UbicacionAlternativaLocalDataSourceDrift(db, encolador: encolador);
    // Donde viven: un edificio con dos deptos. Donde podría cobrar: tres ubicaciones más (una de
    // otro colportor).
    await ubicaciones.insertar(
      ubicacion('ub-1', tipo: TipoUbicacion.edificio, calle: 'Mataojo', numero: '2044'),
    );
    for (final (id, depto) in [('esp-1', '101'), ('esp-2', '102')]) {
      await ubicaciones.insertarEspacio(
        EspacioModel(id: id, ubicacionId: 'ub-1', numeroDepto: depto, auditoria: auditoria()),
      );
    }
    await ubicaciones.insertar(ubicacion('ub-2', calle: 'Av. Italia', numero: '2810'));
    await ubicaciones.insertar(
      ubicacion('ub-3', tipo: TipoUbicacion.casa, calle: 'Gral. Flores', numero: '100'),
    );
    await ubicaciones.insertar(ubicacion('ub-ajena', calle: 'Rivera', creadaPor: 'col-9'));
    await registrarPersona('per-1');
    encolador.encolados.clear();
  });

  tearDown(() => db.close());

  Future<EspacioPersonaFila> fila([String personaId = 'per-1']) =>
      (db.select(db.espacioPersonas)..where((v) => v.personaId.equals(personaId))).getSingle();

  Future<EspacioPersona> establecer(
    String ubicacionId, {
    String personaId = 'per-1',
    String espacioId = 'esp-1',
    String colportorId = 'col-1',
    DateTime? ahora,
  }) => local.establecer(
    personaId: personaId,
    espacioId: espacioId,
    ubicacionId: ubicacionId,
    colportorId: colportorId,
    ahora: ahora ?? t1,
  );

  Future<EspacioPersona> quitar({
    String personaId = 'per-1',
    String espacioId = 'esp-1',
    DateTime? ahora,
  }) => local.quitar(personaId: personaId, espacioId: espacioId, ahora: ahora ?? t1);

  Future<void> darDeBajaUbicacion(String id, DateTime cuando) =>
      (db.update(db.ubicaciones)..where((u) => u.id.equals(id))).write(
        UbicacionesCompanion(deletedAt: Value(cuando), updatedAt: Value(cuando)),
      );

  Matcher rechaza(MotivoRechazoUbicacionAlternativa motivo) => throwsA(
    isA<UbicacionAlternativaRechazadaException>().having((e) => e.motivo, 'motivo', motivo),
  );

  /// Que la escritura no dejó rastro: ni en la fila ni en la cola del sync.
  Future<void> sinRastro() async {
    expect((await fila()).ubicacionCobranzaAltId, isNull);
    expect((await fila()).updatedAt, t0);
    expect(encolador.encolados, isEmpty);
  }

  group('establecer', () {
    test('dada una persona y una ubicación propia activa, cuando se establece, queda guardada con '
        'su updated_at y se encola el update del vínculo solo con ids', () async {
      final r = await establecer('ub-2');

      expect(r.ubicacionCobranzaAltId, 'ub-2');
      final guardada = await fila();
      expect(guardada.ubicacionCobranzaAltId, 'ub-2');
      expect(guardada.updatedAt, t1);
      expect(guardada.createdAt, t0);
      expect(guardada.deletedAt, isNull);
      expect(encolador.encolados, hasLength(1));
      final cambio = encolador.encolados.single;
      expect(cambio.entidad, 'espacio_persona');
      expect(cambio.operacion, OperacionSync.update);
      expect(cambio.payload['id'], 'ep-per-1');
      expect(cambio.payload['espacio_id'], 'esp-1');
      expect(cambio.payload['persona_id'], 'per-1');
      expect(cambio.payload['ubicacion_cobranza_alt_id'], 'ub-2');
      expect(cambio.payload['updated_at'], t1.toIso8601String());
      final texto = cambio.payload.toString();
      expect(texto, isNot(contains('Ana')));
      expect(texto, isNot(contains('099')));
    });

    test(
      'dada una alternativa, cuando se cambia por otra, queda la nueva y cada cambio se encola',
      () async {
        await establecer('ub-2');

        await establecer('ub-3', ahora: t2);

        expect((await fila()).ubicacionCobranzaAltId, 'ub-3');
        expect(encolador.encolados.map((c) => c.payload['ubicacion_cobranza_alt_id']), [
          'ub-2',
          'ub-3',
        ]);
      },
    );

    test(
      'dado un doble toque (dos pedidos a la vez con la misma), cuando se serializan, el segundo no '
      'escribe ni encola de nuevo',
      () async {
        final dos = await Future.wait([establecer('ub-2'), establecer('ub-2', ahora: t2)]);

        expect(dos.map((v) => v.ubicacionCobranzaAltId), ['ub-2', 'ub-2']);
        expect(encolador.encolados, hasLength(1));
        expect((await fila()).updatedAt, t1);
      },
    );

    test(
      'dadas dos acciones seguidas sin esperar la primera (A y después B), cuando terminan, queda B '
      'y la cola termina en B: ninguna se pisa ni se pierde',
      () async {
        await Future.wait([establecer('ub-2'), establecer('ub-3', ahora: t2)]);

        expect((await fila()).ubicacionCobranzaAltId, 'ub-3');
        expect(encolador.encolados.map((c) => c.payload['ubicacion_cobranza_alt_id']), [
          'ub-2',
          'ub-3',
        ]);
      },
    );

    test(
      'dadas dos acciones seguidas (establecer y quitar), cuando terminan, queda sin alternativa y la '
      'cola termina en null',
      () async {
        await Future.wait([establecer('ub-2'), quitar(ahora: t2)]);

        expect((await fila()).ubicacionCobranzaAltId, isNull);
        expect(encolador.encolados.map((c) => c.payload['ubicacion_cobranza_alt_id']), [
          'ub-2',
          null,
        ]);
      },
    );

    test(
      'dada una falla al encolar, cuando se establece, no queda nada y al reintentar sale bien',
      () async {
        encolador.fallarCon = StateError('sin cola');

        await expectLater(establecer('ub-2'), throwsStateError);
        await sinRastro();

        encolador.fallarCon = null;
        final r = await establecer('ub-2');
        expect(r.ubicacionCobranzaAltId, 'ub-2');
        expect(encolador.encolados, hasLength(1));
      },
    );

    test('dado un reloj atrasado, cuando se establece, el updated_at no retrocede', () async {
      await establecer('ub-2', ahora: t1);

      await establecer('ub-3', ahora: DateTime.utc(2026, 10, 20));

      expect((await fila()).updatedAt, t1);
      expect((await fila()).ubicacionCobranzaAltId, 'ub-3');
    });

    test(
      'dado que varias personas apuntan a la misma alternativa, cuando se establece, está permitido '
      '(también en otro depto del mismo edificio)',
      () async {
        await registrarPersona('per-2');
        await registrarPersona('per-3', espacioId: 'esp-2');

        await establecer('ub-2');
        await establecer('ub-2', personaId: 'per-2');
        await establecer('ub-2', personaId: 'per-3', espacioId: 'esp-2');

        for (final id in ['per-1', 'per-2', 'per-3']) {
          expect((await fila(id)).ubicacionCobranzaAltId, 'ub-2');
        }
      },
    );

    test('dada la propia ubicación del espacio (o de otro depto del mismo edificio), cuando se '
        'establece, se bloquea', () async {
      await expectLater(
        establecer('ub-1'),
        rechaza(MotivoRechazoUbicacionAlternativa.esLaDelEspacio),
      );
      await sinRastro();
    });

    test('dada una ubicación de otro colportor, cuando se establece, se bloquea', () async {
      await expectLater(
        establecer('ub-ajena'),
        rechaza(MotivoRechazoUbicacionAlternativa.ubicacionAjena),
      );
      await sinRastro();
    });

    test('dada una ubicación que no existe, cuando se establece, se bloquea', () async {
      await expectLater(
        establecer('ub-fantasma'),
        rechaza(MotivoRechazoUbicacionAlternativa.ubicacionInexistente),
      );
      await sinRastro();
    });

    test('dada una ubicación dada de baja, cuando se establece, se bloquea', () async {
      await darDeBajaUbicacion('ub-2', t1);

      await expectLater(
        establecer('ub-2'),
        rechaza(MotivoRechazoUbicacionAlternativa.ubicacionDeBaja),
      );
      await sinRastro();
    });

    test('dada una persona de baja, cuando se establece, se bloquea: es de solo lectura', () async {
      await personas.darDeBaja(personaId: 'per-1', ahora: t1);
      encolador.encolados.clear();

      await expectLater(
        establecer('ub-2'),
        rechaza(MotivoRechazoUbicacionAlternativa.personaDeBaja),
      );
      expect((await fila()).ubicacionCobranzaAltId, isNull);
      expect(encolador.encolados, isEmpty);
    });

    test('dado un espacio de baja, cuando se establece, se bloquea', () async {
      await (db.update(db.espacios)..where((e) => e.id.equals('esp-1'))).write(
        EspaciosCompanion(deletedAt: Value(t1), updatedAt: Value(t1)),
      );

      await expectLater(
        establecer('ub-2'),
        rechaza(MotivoRechazoUbicacionAlternativa.espacioDeBaja),
      );
      expect((await fila()).ubicacionCobranzaAltId, isNull);
    });

    test('dada la ubicación del espacio de baja, cuando se establece, se bloquea', () async {
      await darDeBajaUbicacion('ub-1', t1);

      await expectLater(
        establecer('ub-2'),
        rechaza(MotivoRechazoUbicacionAlternativa.ubicacionDelEspacioDeBaja),
      );
      expect((await fila()).ubicacionCobranzaAltId, isNull);
    });

    test('dado un vínculo que no existe (otro espacio), cuando se establece, se bloquea', () async {
      await expectLater(
        establecer('ub-2', espacioId: 'esp-2'),
        rechaza(MotivoRechazoUbicacionAlternativa.vinculoInexistente),
      );
      await expectLater(
        establecer('ub-2', personaId: 'per-fantasma'),
        rechaza(MotivoRechazoUbicacionAlternativa.vinculoInexistente),
      );
      await sinRastro();
    });

    test('dada una alternativa guardada que se da de baja después, cuando se vuelve a mirar, la '
        'referencia sigue: nada se borra del teléfono', () async {
      await establecer('ub-2');

      await darDeBajaUbicacion('ub-2', t2);

      expect((await fila()).ubicacionCobranzaAltId, 'ub-2');
    });
  });

  group('quitar', () {
    test(
      'dada una alternativa, cuando se quita, el vínculo queda sin ella y se encola el update con '
      'null',
      () async {
        await establecer('ub-2');
        encolador.encolados.clear();

        final r = await quitar(ahora: t2);

        expect(r.ubicacionCobranzaAltId, isNull);
        expect((await fila()).ubicacionCobranzaAltId, isNull);
        expect((await fila()).updatedAt, t2);
        expect(encolador.encolados, hasLength(1));
        expect(encolador.encolados.single.operacion, OperacionSync.update);
        expect(encolador.encolados.single.payload['ubicacion_cobranza_alt_id'], isNull);
      },
    );

    test('dada una persona sin alternativa, cuando se quita, no escribe ni encola', () async {
      final r = await quitar();

      expect(r.ubicacionCobranzaAltId, isNull);
      await sinRastro();
    });

    test('dado un doble toque, cuando se quita dos veces, la segunda no escribe', () async {
      await establecer('ub-2');
      encolador.encolados.clear();

      await Future.wait([quitar(), quitar(ahora: t2)]);

      expect(encolador.encolados, hasLength(1));
      expect((await fila()).updatedAt, t1);
    });

    test(
      'dada una alternativa dada de baja, cuando se quita, se puede: es lo que hay que hacer',
      () async {
        await establecer('ub-2');
        await darDeBajaUbicacion('ub-2', t2);

        await quitar(ahora: t2);

        expect((await fila()).ubicacionCobranzaAltId, isNull);
      },
    );

    test(
      'dada una falla al encolar, cuando se quita, la alternativa sigue y al reintentar se quita',
      () async {
        await establecer('ub-2');
        encolador
          ..encolados.clear()
          ..fallarCon = StateError('sin cola');

        await expectLater(quitar(ahora: t2), throwsStateError);
        expect((await fila()).ubicacionCobranzaAltId, 'ub-2');
        expect((await fila()).updatedAt, t1);

        encolador.fallarCon = null;
        await quitar(ahora: t2);
        expect((await fila()).ubicacionCobranzaAltId, isNull);
      },
    );

    test(
      'dada una persona de baja o un vínculo que no existe, cuando se quita, se bloquea',
      () async {
        await personas.darDeBaja(personaId: 'per-1', ahora: t1);

        await expectLater(quitar(), rechaza(MotivoRechazoUbicacionAlternativa.personaDeBaja));
        await expectLater(
          quitar(espacioId: 'esp-2'),
          rechaza(MotivoRechazoUbicacionAlternativa.vinculoInexistente),
        );
      },
    );
  });

  group('observar', () {
    /// Lo que va emitiendo [stream] hasta que se cancela.
    ({List<EstadoUbicacionAlternativa> emitidos, Future<void> Function() cerrar}) mirar() {
      final emitidos = <EstadoUbicacionAlternativa>[];
      final sub = local.observar(personaId: 'per-1', espacioId: 'esp-1').listen(emitidos.add);
      return (emitidos: emitidos, cerrar: sub.cancel);
    }

    Future<void> hasta(List<Object?> emitidos, int n) async {
      for (var i = 0; i < 200 && emitidos.length < n; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(emitidos.length, greaterThanOrEqualTo(n), reason: 'emisiones: $emitidos');
    }

    test(
      'dada una persona sin alternativa, cuando se observa, emite «sin alternativa» y no sugiere '
      'nada',
      () async {
        final m = mirar();
        await hasta(m.emitidos, 1);

        expect(m.emitidos.last, const SinUbicacionAlternativa());
        expect(m.emitidos.last.sugerida, isNull);
        expect(m.emitidos.last.requiereActualizar, isFalse);
        await m.cerrar();
      },
    );

    test('dada una alternativa, cuando se establece, se baja y se reactiva, el estado la sigue: '
        'vigente, de baja (no se sugiere) y vigente otra vez', () async {
      final m = mirar();
      await hasta(m.emitidos, 1);

      await establecer('ub-2');
      await hasta(m.emitidos, 2);
      final vigente = m.emitidos.last as UbicacionAlternativaVigente;
      expect(vigente.ubicacion.id, 'ub-2');
      expect(vigente.ubicacion.calle, 'Av. Italia');
      expect(vigente.ubicacion.tipo, TipoUbicacion.negocio);
      expect(vigente.sugerida.id, 'ub-2');

      await darDeBajaUbicacion('ub-2', t2);
      await hasta(m.emitidos, 3);
      expect(m.emitidos.last, const UbicacionAlternativaDeBaja('ub-2'));
      expect(m.emitidos.last.sugerida, isNull);
      expect(m.emitidos.last.requiereActualizar, isTrue);

      await (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-2'))).write(
        const UbicacionesCompanion(deletedAt: Value(null)),
      );
      await hasta(m.emitidos, 4);
      expect(m.emitidos.last, isA<UbicacionAlternativaVigente>());

      await quitar(ahora: t2);
      await hasta(m.emitidos, 5);
      expect(m.emitidos.last, const SinUbicacionAlternativa());
      await m.cerrar();
    });

    test(
      'dada una alternativa que no está en el teléfono, cuando se observa, emite «faltante» y no '
      'afirma que esté de baja',
      () async {
        await establecer('ub-2');
        await (db.delete(db.ubicaciones)..where((u) => u.id.equals('ub-2'))).go();

        final m = mirar();
        await hasta(m.emitidos, 1);

        expect(m.emitidos.last, const UbicacionAlternativaFaltante('ub-2'));
        expect(m.emitidos.last.sugerida, isNull);
        expect(m.emitidos.last.requiereActualizar, isTrue);
        await m.cerrar();
      },
    );

    test('dado un vínculo que no existe, cuando se observa, emite «sin alternativa»', () async {
      final emitidos = <EstadoUbicacionAlternativa>[];
      final sub = local
          .observar(personaId: 'per-fantasma', espacioId: 'esp-1')
          .listen(emitidos.add);
      await hasta(emitidos, 1);

      expect(emitidos.last, const SinUbicacionAlternativa());
      await sub.cancel();
    });

    test('dada la alternativa de otra persona, cuando cambia, esta persona no se entera', () async {
      await registrarPersona('per-2');
      final m = mirar();
      await hasta(m.emitidos, 1);

      await establecer('ub-3', personaId: 'per-2');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(m.emitidos.last, const SinUbicacionAlternativa());
      await m.cerrar();
    });
  });

  group('observarCandidatas', () {
    Future<List<String>> ids({String colportorId = 'col-1', String espacioId = 'esp-1'}) async => [
      for (final u
          in await local.observarCandidatas(colportorId: colportorId, espacioId: espacioId).first)
        u.id,
    ];

    test(
      'dado un colportor con otras ubicaciones, cuando elige, ve las propias activas menos la del '
      'espacio, ordenadas por dirección',
      () async {
        expect(await ids(), ['ub-2', 'ub-3']);
      },
    );

    test('dadas ubicaciones de baja o de otro colportor, cuando elige, no aparecen', () async {
      await darDeBajaUbicacion('ub-3', t1);

      expect(await ids(), ['ub-2']);
      expect(await ids(colportorId: 'col-9'), ['ub-ajena']);
    });

    test(
      'dado que solo tiene la ubicación de la persona, cuando abre el selector, la lista está vacía '
      '(estado vacío)',
      () async {
        await darDeBajaUbicacion('ub-2', t1);
        await darDeBajaUbicacion('ub-3', t1);

        expect(await ids(), isEmpty);
      },
    );

    test(
      'dado otro espacio con otra ubicación, cuando elige, la propia de ese espacio queda afuera '
      'y la anterior aparece',
      () async {
        await ubicaciones.insertarEspacio(
          EspacioModel(id: 'esp-3', ubicacionId: 'ub-2', auditoria: auditoria()),
        );

        expect(await ids(espacioId: 'esp-3'), ['ub-3', 'ub-1']);
      },
    );

    test(
      'dada una ubicación nueva registrada con la selección abierta, cuando se alta, la lista se '
      'actualiza sola',
      () async {
        final listas = <List<String>>[];
        final sub = local
            .observarCandidatas(colportorId: 'col-1', espacioId: 'esp-1')
            .listen((l) => listas.add([for (final u in l) u.id]));
        for (var i = 0; i < 200 && listas.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }

        await ubicaciones.insertar(ubicacion('ub-4', calle: 'Zabala'));
        for (var i = 0; i < 200 && listas.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }

        expect(listas.last, ['ub-2', 'ub-3', 'ub-4']);
        await sub.cancel();
      },
    );
  });
}
