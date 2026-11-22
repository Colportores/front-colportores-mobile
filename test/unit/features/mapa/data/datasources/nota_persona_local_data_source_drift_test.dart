// Las notas de una persona (HU-UBI-012) contra las tablas reales: AppDatabase en memoria, mismo esquema
// y mismas restricciones que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_persona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_nota.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
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

  NotaPersona nota(
    String id, {
    String personaId = 'per-1',
    String texto = 'Prefiere de tarde',
    DateTime? creada,
  }) => NotaPersona(
    id: id,
    personaId: personaId,
    texto: texto,
    auditoria: auditoria(creada: creada),
  );

  late AppDatabase db;
  late NotaPersonaLocalDataSourceDrift local;

  Future<void> sembrar({
    DateTime? espacioDeBaja,
    DateTime? ubicacionDeBaja,
    String nombre = 'María',
  }) async {
    final encolador = EncoladorSyncEnMemoria();
    final ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
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
      EspacioModel(id: 'esp-1', ubicacionId: 'ub-1', numeroDepto: '3B', auditoria: auditoria()),
    );
    await PersonaLocalDataSourceDrift(db, encolador: encolador).registrar(
      persona: Persona(id: 'per-1', nombre: nombre, apellido: 'Fernández', auditoria: auditoria()),
      vinculo: EspacioPersona(
        id: 'ep-1',
        espacioId: 'esp-1',
        personaId: 'per-1',
        auditoria: auditoria(),
      ),
    );
    // Las bajas llegan después de registrar a la persona (el registro las rechaza).
    if (espacioDeBaja != null) {
      await db.customStatement('UPDATE espacio SET deleted_at = ? WHERE id = ?', [
        espacioDeBaja.millisecondsSinceEpoch,
        'esp-1',
      ]);
    }
    if (ubicacionDeBaja != null) {
      await db.customStatement('UPDATE ubicacion SET deleted_at = ? WHERE id = ?', [
        ubicacionDeBaja.millisecondsSinceEpoch,
        'ub-1',
      ]);
    }
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    local = NotaPersonaLocalDataSourceDrift(db);
  });

  tearDown(() => db.close());

  Future<int> filas([String donde = '1 = 1']) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM nota WHERE $donde').getSingle()).read<int>(
        'n',
      );

  Matcher rechaza(MotivoRechazoNota motivo) =>
      throwsA(isA<NotaRechazadaException>().having((e) => e.motivo, 'motivo', motivo));

  group('agregar', () {
    test(
      'dado una persona, cuando agrego su primera nota, guarda la fila PERSONA con mi autor',
      () async {
        await sembrar();

        final guardada = await local.agregar(
          nota('nota-1', texto: 'Le interesa Caminos de la Vida'),
        );

        expect(guardada.texto, 'Le interesa Caminos de la Vida');
        final fila = await db
            .customSelect('SELECT target_type, target_id, texto, created_by, deleted_at FROM nota')
            .getSingle();
        expect(fila.read<String>('target_type'), 'PERSONA');
        expect(fila.read<String>('target_id'), 'per-1');
        expect(fila.read<String>('texto'), 'Le interesa Caminos de la Vida');
        expect(fila.read<String>('created_by'), 'col-1');
        expect(fila.read<int?>('deleted_at'), isNull);
      },
    );

    test(
      'dado la misma nota repetida (doble toque o reintento), cuando agrego otra vez, no duplica',
      () async {
        await sembrar();

        await local.agregar(nota('nota-1', texto: 'Primera'));
        final otra = await local.agregar(nota('nota-1', texto: 'Distinta'));

        expect(await filas(), 1);
        expect(otra.texto, 'Primera');
      },
    );

    test(
      'dado dos altas casi simultáneas con el mismo id, cuando se serializan, queda una fila',
      () async {
        await sembrar();

        await Future.wait([local.agregar(nota('nota-1')), local.agregar(nota('nota-1'))]);

        expect(await filas(), 1);
      },
    );

    test('dado varias notas, cuando agrego, caben más de una por persona', () async {
      await sembrar();

      await local.agregar(nota('nota-1'));
      await local.agregar(nota('nota-2'));

      expect(await filas("target_id = 'per-1'"), 2);
    });

    test(
      'dado un texto de 6000 caracteres con emojis, cuando agrego, se guarda entero (límite blando)',
      () async {
        await sembrar();
        final largo = '👍ñ${'a' * 6000}';

        await local.agregar(nota('nota-1', texto: largo));

        final fila = await db.customSelect('SELECT texto FROM nota').getSingle();
        expect(fila.read<String>('texto'), largo);
      },
    );

    test(
      'dado una persona que no existe, cuando agrego, rechaza por persona inexistente y no escribe',
      () async {
        await sembrar();

        await expectLater(
          local.agregar(nota('nota-1', personaId: 'fantasma')),
          rechaza(MotivoRechazoNota.personaInexistente),
        );
        expect(await filas(), 0);
      },
    );

    test(
      'dado una persona dada de baja, cuando agrego, rechaza por solo lectura y no escribe',
      () async {
        await sembrar();
        await db.customStatement('UPDATE persona SET deleted_at = ? WHERE id = ?', [
          t0.millisecondsSinceEpoch,
          'per-1',
        ]);

        await expectLater(local.agregar(nota('nota-1')), rechaza(MotivoRechazoNota.soloLectura));
        expect(await filas(), 0);
      },
    );

    test(
      'dado que su espacio está dado de baja, cuando agrego, rechaza por solo lectura',
      () async {
        await sembrar(espacioDeBaja: t0);

        await expectLater(local.agregar(nota('nota-1')), rechaza(MotivoRechazoNota.soloLectura));
      },
    );

    test(
      'dado que su ubicación está dada de baja, cuando agrego, rechaza por solo lectura',
      () async {
        await sembrar(ubicacionDeBaja: t0);

        await expectLater(local.agregar(nota('nota-1')), rechaza(MotivoRechazoNota.soloLectura));
      },
    );

    test(
      'dado que su vínculo con el espacio está dado de baja, cuando agrego, rechaza por solo lectura',
      () async {
        await sembrar();
        await db.customStatement('UPDATE espacio_persona SET deleted_at = ? WHERE id = ?', [
          t0.millisecondsSinceEpoch,
          'ep-1',
        ]);

        await expectLater(local.agregar(nota('nota-1')), rechaza(MotivoRechazoNota.soloLectura));
      },
    );
  });

  group('observar', () {
    test(
      'dado varias notas, cuando observo, salen de la más nueva a la más vieja, con las borradas',
      () async {
        await sembrar();
        await local.agregar(nota('a', creada: t0));
        await local.agregar(nota('b', creada: t0.add(const Duration(hours: 2))));
        await local.agregar(nota('c', creada: t0.add(const Duration(hours: 1))));
        await local.borrar(id: 'c', ahora: t0.add(const Duration(hours: 3)));

        final notas = await local.observar('per-1').first;

        expect([for (final n in notas) n.id], ['b', 'c', 'a']);
        expect(notas[1].estaBorrada, isTrue);
      },
    );

    test(
      'dado dos notas del mismo instante, cuando observo, desempata por id (siempre el mismo orden)',
      () async {
        await sembrar();
        await local.agregar(nota('a'));
        await local.agregar(nota('b'));

        final notas = await local.observar('per-1').first;

        expect([for (final n in notas) n.id], ['b', 'a']);
      },
    );

    test('dado notas de otra persona o de otro objeto, cuando observo, no aparecen', () async {
      await sembrar();
      await local.agregar(nota('mia'));
      await db.customStatement(
        'INSERT INTO nota (id, target_type, target_id, texto, created_at, updated_at, sync_version) '
        'VALUES (\'de-visita\', \'VISITA\', \'per-1\', \'otra cosa\', 1, 1, 0)',
      );
      await db.customStatement(
        'INSERT INTO nota (id, target_type, target_id, texto, created_at, updated_at, sync_version) '
        'VALUES (\'de-otra\', \'PERSONA\', \'per-2\', \'otra persona\', 1, 1, 0)',
      );

      final notas = await local.observar('per-1').first;

      expect([for (final n in notas) n.id], ['mia']);
    });

    test(
      'dado que se agrega y se borra una nota, cuando observo, el flujo se actualiza solo',
      () async {
        await sembrar();
        final emisiones = <List<String>>[];
        final suscripcion = local
            .observar('per-1')
            .listen((l) => emisiones.add([for (final n in l) n.estaBorrada ? '${n.id}!' : n.id]));

        await pumpEventQueue();
        await local.agregar(nota('a'));
        await pumpEventQueue();
        await local.borrar(id: 'a', ahora: t0);
        await pumpEventQueue();
        await local.restaurar(id: 'a', ahora: t0);
        await pumpEventQueue();
        await suscripcion.cancel();

        expect(emisiones, [
          <String>[],
          ['a'],
          ['a!'],
          ['a'],
        ]);
      },
    );
  });

  group('editar', () {
    test(
      'dado una nota, cuando la edito, cambia el texto y updated_at y conserva created_at y created_by',
      () async {
        await sembrar();
        await local.agregar(nota('nota-1', texto: 'Vieja'));
        final despues = t0.add(const Duration(days: 2));

        final editada = await local.editar(id: 'nota-1', texto: 'Nueva', ahora: despues);

        expect(editada.texto, 'Nueva');
        expect(editada.auditoria.updatedAt, despues.toUtc());
        expect(editada.auditoria.createdAt, t0);
        expect(editada.auditoria.createdBy, 'col-1');
        expect(editada.estaBorrada, isFalse);
      },
    );

    test('dado el mismo texto, cuando la edito, no escribe nada: updated_at queda', () async {
      await sembrar();
      await local.agregar(nota('nota-1', texto: 'Igual'));

      final r = await local.editar(
        id: 'nota-1',
        texto: 'Igual',
        ahora: t0.add(const Duration(days: 2)),
      );

      expect(r.auditoria.updatedAt, t0);
    });

    test('dado un reloj atrasado, cuando edito, updated_at no retrocede', () async {
      await sembrar();
      await local.agregar(nota('nota-1', texto: 'Vieja'));

      final r = await local.editar(
        id: 'nota-1',
        texto: 'Nueva',
        ahora: t0.subtract(const Duration(days: 1)),
      );

      expect(r.auditoria.updatedAt, t0);
      expect(r.texto, 'Nueva');
    });

    test('dado una nota borrada, cuando la edito, rechaza por nota borrada', () async {
      await sembrar();
      await local.agregar(nota('nota-1'));
      await local.borrar(id: 'nota-1', ahora: t0);

      await expectLater(
        local.editar(id: 'nota-1', texto: 'x', ahora: t0),
        rechaza(MotivoRechazoNota.notaBorrada),
      );
    });

    test(
      'dado una nota que no existe, o que es de otro objeto, cuando la edito, rechaza por nota inexistente',
      () async {
        await sembrar();
        await db.customStatement(
          'INSERT INTO nota (id, target_type, target_id, texto, created_at, updated_at, sync_version) '
          'VALUES (\'de-visita\', \'VISITA\', \'per-1\', \'otra cosa\', 1, 1, 0)',
        );

        await expectLater(
          local.editar(id: 'fantasma', texto: 'x', ahora: t0),
          rechaza(MotivoRechazoNota.notaInexistente),
        );
        await expectLater(
          local.editar(id: 'de-visita', texto: 'x', ahora: t0),
          rechaza(MotivoRechazoNota.notaInexistente),
        );
      },
    );

    test(
      'dado que la persona quedó en solo lectura, cuando edito, rechaza y el texto queda',
      () async {
        await sembrar();
        await local.agregar(nota('nota-1', texto: 'Vieja'));
        await db.customStatement('UPDATE persona SET deleted_at = ? WHERE id = ?', [
          t0.millisecondsSinceEpoch,
          'per-1',
        ]);

        await expectLater(
          local.editar(id: 'nota-1', texto: 'Nueva', ahora: t0),
          rechaza(MotivoRechazoNota.soloLectura),
        );
        final fila = await db.customSelect('SELECT texto FROM nota').getSingle();
        expect(fila.read<String>('texto'), 'Vieja');
      },
    );
  });

  group('borrar y restaurar', () {
    test('dado una nota, cuando la borro, setea deleted_at y la fila sigue en la tabla', () async {
      await sembrar();
      await local.agregar(nota('nota-1'));
      final cuando = t0.add(const Duration(hours: 1));

      final borrada = await local.borrar(id: 'nota-1', ahora: cuando);

      expect(borrada.estaBorrada, isTrue);
      expect(borrada.auditoria.deletedAt, cuando.toUtc());
      expect(borrada.auditoria.updatedAt, cuando.toUtc());
      expect(await filas(), 1);
    });

    test('dado una nota ya borrada, cuando la borro otra vez, no cambia deleted_at', () async {
      await sembrar();
      await local.agregar(nota('nota-1'));
      final primera = t0.add(const Duration(hours: 1));
      await local.borrar(id: 'nota-1', ahora: primera);

      final segunda = await local.borrar(id: 'nota-1', ahora: primera.add(const Duration(days: 1)));

      expect(segunda.auditoria.deletedAt, primera.toUtc());
    });

    test(
      'dado una nota borrada, cuando la restauro, vuelve a estar activa con su texto y su fecha',
      () async {
        await sembrar();
        await local.agregar(nota('nota-1', texto: 'Importante'));
        await local.borrar(id: 'nota-1', ahora: t0.add(const Duration(hours: 1)));

        final vuelta = await local.restaurar(id: 'nota-1', ahora: t0.add(const Duration(hours: 2)));

        expect(vuelta.estaBorrada, isFalse);
        expect(vuelta.texto, 'Importante');
        expect(vuelta.auditoria.createdAt, t0);
        expect(vuelta.auditoria.updatedAt, t0.add(const Duration(hours: 2)).toUtc());
      },
    );

    test('dado una nota activa, cuando la restauro, no cambia nada', () async {
      await sembrar();
      await local.agregar(nota('nota-1'));

      final r = await local.restaurar(id: 'nota-1', ahora: t0.add(const Duration(days: 1)));

      expect(r.auditoria.updatedAt, t0);
    });

    test(
      'dado dos borrados seguidos de notas distintas, cuando se serializan, las dos quedan borradas',
      () async {
        await sembrar();
        await local.agregar(nota('a'));
        await local.agregar(nota('b'));

        await Future.wait([local.borrar(id: 'a', ahora: t0), local.borrar(id: 'b', ahora: t0)]);

        expect(await filas('deleted_at IS NOT NULL'), 2);
      },
    );

    test(
      'dado una nota que no existe, cuando la borro o la restauro, rechaza por nota inexistente',
      () async {
        await sembrar();

        await expectLater(
          local.borrar(id: 'fantasma', ahora: t0),
          rechaza(MotivoRechazoNota.notaInexistente),
        );
        await expectLater(
          local.restaurar(id: 'fantasma', ahora: t0),
          rechaza(MotivoRechazoNota.notaInexistente),
        );
      },
    );

    test(
      'dado que la persona quedó en solo lectura, cuando borro o restauro, rechaza y nada cambia',
      () async {
        await sembrar();
        await local.agregar(nota('a'));
        await local.agregar(nota('b'));
        await local.borrar(id: 'b', ahora: t0);
        await db.customStatement('UPDATE persona SET deleted_at = ? WHERE id = ?', [
          t0.millisecondsSinceEpoch,
          'per-1',
        ]);

        await expectLater(local.borrar(id: 'a', ahora: t0), rechaza(MotivoRechazoNota.soloLectura));
        await expectLater(
          local.restaurar(id: 'b', ahora: t0),
          rechaza(MotivoRechazoNota.soloLectura),
        );
        expect(await filas('deleted_at IS NOT NULL'), 1);
      },
    );

    test('dado el soft delete, cuando borro, ninguna otra nota se toca', () async {
      await sembrar();
      await local.agregar(nota('a'));
      await local.agregar(nota('b'));

      await local.borrar(id: 'a', ahora: t0);

      expect(await filas("id = 'b' AND deleted_at IS NULL"), 1);
    });
  });

  group('leerContexto', () {
    test(
      'dado una persona activa, cuando leo el contexto, no trae causa de solo lectura',
      () async {
        await sembrar();

        final c = await local.leerContexto('per-1');

        expect(c?.causa, isNull);
        expect(c?.soloLectura, isFalse);
      },
    );

    test(
      'dado una persona de baja, cuando leo el contexto, la causa es la baja y trae desde cuándo (32B·04)',
      () async {
        await sembrar();
        await db.customStatement('UPDATE persona SET deleted_at = ? WHERE id = ?', [
          t0.millisecondsSinceEpoch,
          'per-1',
        ]);

        final c = await local.leerContexto('per-1');

        expect(c?.causa, CausaSoloLectura.personaDeBaja);
        expect(c?.bajaDesde, t0);
      },
    );

    test(
      'dado que su depto está de baja, cuando leo el contexto, la causa trae el número y la dirección (32B·08)',
      () async {
        await sembrar(espacioDeBaja: t0);

        final c = await local.leerContexto('per-1');

        expect(c?.causa, CausaSoloLectura.espacioDeBaja);
        expect(c?.numeroDepto, '3B');
        expect(c?.direccion, 'Mataojo 2044');
      },
    );

    test(
      'dado que su vínculo está de baja y no tiene otro, cuando leo el contexto, la causa es que no tiene espacio activo',
      () async {
        await sembrar();
        await db.customStatement('UPDATE espacio_persona SET deleted_at = ? WHERE id = ?', [
          t0.millisecondsSinceEpoch,
          'ep-1',
        ]);

        final c = await local.leerContexto('per-1');

        expect(c?.causa, CausaSoloLectura.sinEspacioActivo);
      },
    );

    test(
      'dado una persona activa, cuando leo el contexto, trae su nombre y se puede escribir',
      () async {
        await sembrar();

        final c = await local.leerContexto('per-1');

        expect(c?.nombre, 'María');
        expect(c?.soloLectura, isFalse);
      },
    );

    test('dado una persona que no existe, cuando leo el contexto, es nulo', () async {
      await sembrar();

      expect(await local.leerContexto('fantasma'), isNull);
    });

    test('dado una persona de baja, cuando leo el contexto, es solo lectura', () async {
      await sembrar();
      await db.customStatement('UPDATE persona SET deleted_at = ? WHERE id = ?', [
        t0.millisecondsSinceEpoch,
        'per-1',
      ]);

      expect((await local.leerContexto('per-1'))?.soloLectura, isTrue);
    });

    test(
      'dado que su único espacio está de baja (32B·08), cuando leo el contexto, es solo lectura',
      () async {
        await sembrar(espacioDeBaja: t0);

        expect((await local.leerContexto('per-1'))?.soloLectura, isTrue);
      },
    );

    test('dado que su ubicación está de baja, cuando leo el contexto, es solo lectura', () async {
      await sembrar(ubicacionDeBaja: t0);

      expect((await local.leerContexto('per-1'))?.soloLectura, isTrue);
    });

    test(
      'dado una persona con dos espacios y uno de baja, cuando leo el contexto, se puede escribir',
      () async {
        await sembrar();
        final ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria());
        await ubicaciones.insertarEspacio(
          EspacioModel(id: 'esp-2', ubicacionId: 'ub-1', numeroDepto: '4A', auditoria: auditoria()),
        );
        await db.customStatement(
          'INSERT INTO espacio_persona (id, espacio_id, persona_id, created_at, updated_at, sync_version) '
          'VALUES (\'ep-2\', \'esp-2\', \'per-1\', 1, 1, 0)',
        );
        await db.customStatement('UPDATE espacio SET deleted_at = ? WHERE id = ?', [
          t0.millisecondsSinceEpoch,
          'esp-1',
        ]);

        expect((await local.leerContexto('per-1'))?.soloLectura, isFalse);
      },
    );
  });
}
