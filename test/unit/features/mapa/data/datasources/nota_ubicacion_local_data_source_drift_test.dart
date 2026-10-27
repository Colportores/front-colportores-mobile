// Las notas de un lugar (vista 39, C·05) contra las tablas reales: AppDatabase en memoria, mismo esquema
// y mismas restricciones que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_persona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_nota.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 22, 13, 45, 10, 123);

  Auditoria auditoria({DateTime? creada}) =>
      Auditoria(createdAt: creada ?? t0, updatedAt: creada ?? t0, createdBy: 'col-1');

  NotaUbicacion nota(
    String id, {
    String ubicacionId = 'ub-1',
    String texto = 'El portón no cierra',
    DateTime? creada,
  }) => NotaUbicacion(
    id: id,
    ubicacionId: ubicacionId,
    texto: texto,
    auditoria: auditoria(creada: creada),
  );

  late AppDatabase db;
  late NotaUbicacionLocalDataSourceDrift local;

  Future<void> sembrar({String id = 'ub-1', DateTime? deBaja}) async {
    final ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria());
    await ubicaciones.insertar(
      UbicacionModel(
        id: id,
        tipo: TipoUbicacion.casa,
        calle: 'Mataojo',
        numero: '2044',
        lat: -34.89,
        lon: -56.16,
        ciudadId: 'mvd',
        auditoria: auditoria(),
      ),
    );
    if (deBaja != null) {
      await db.customStatement('UPDATE ubicacion SET deleted_at = ? WHERE id = ?', [
        deBaja.millisecondsSinceEpoch,
        id,
      ]);
    }
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    local = NotaUbicacionLocalDataSourceDrift(db);
  });

  tearDown(() => db.close());

  Future<int> filas([String donde = '1 = 1']) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM nota WHERE $donde').getSingle()).read<int>(
        'n',
      );

  Matcher rechaza(MotivoRechazoNota motivo) =>
      throwsA(isA<NotaRechazadaException>().having((e) => e.motivo, 'motivo', motivo));

  group('agregar', () {
    test('dado un lugar, cuando agrego una nota, guarda la fila UBICACION con mi autor', () async {
      await sembrar();

      final guardada = await local.agregar(nota('nota-1', texto: 'Perro en el patio'));

      expect(guardada.texto, 'Perro en el patio');
      final fila = await db
          .customSelect('SELECT target_type, target_id, texto, created_by, deleted_at FROM nota')
          .getSingle();
      expect(fila.read<String>('target_type'), 'UBICACION');
      expect(fila.read<String>('target_id'), 'ub-1');
      expect(fila.read<String>('texto'), 'Perro en el patio');
      expect(fila.read<String>('created_by'), 'col-1');
      expect(fila.read<int?>('deleted_at'), isNull);
    });

    test('dado la misma nota repetida (doble toque), cuando agrego otra vez, no duplica', () async {
      await sembrar();

      await local.agregar(nota('nota-1', texto: 'Primera'));
      final otra = await local.agregar(nota('nota-1', texto: 'Distinta'));

      expect(await filas(), 1);
      expect(otra.texto, 'Primera');
    });

    test('dado dos altas casi simultáneas con el mismo id, queda una fila', () async {
      await sembrar();

      await Future.wait([local.agregar(nota('nota-1')), local.agregar(nota('nota-1'))]);

      expect(await filas(), 1);
    });

    test('dado varias notas, caben más de una por lugar', () async {
      await sembrar();

      await local.agregar(nota('nota-1'));
      await local.agregar(nota('nota-2'));

      expect(await filas("target_id = 'ub-1'"), 2);
    });

    test('dado un texto de 6000 caracteres con emojis, se guarda entero', () async {
      await sembrar();
      final largo = '👍ñ${'a' * 6000}';

      await local.agregar(nota('nota-1', texto: largo));

      expect(
        (await db.customSelect('SELECT texto FROM nota').getSingle()).read<String>('texto'),
        largo,
      );
    });

    test('dado un lugar que no está en el teléfono, rechaza y no escribe', () async {
      await expectLater(
        local.agregar(nota('nota-1')),
        rechaza(MotivoRechazoNota.ubicacionInexistente),
      );

      expect(await filas(), 0);
    });

    test('dado un lugar dado de baja, rechaza y no escribe', () async {
      await sembrar(deBaja: t0);

      await expectLater(local.agregar(nota('nota-1')), rechaza(MotivoRechazoNota.ubicacionDeBaja));

      expect(await filas(), 0);
    });
  });

  group('observar', () {
    test(
      'dado notas de dos lugares y de una persona, solo llegan las del lugar, de la más nueva a la más vieja',
      () async {
        await sembrar();
        await sembrar(id: 'ub-2');
        await local.agregar(nota('a', texto: 'Vieja', creada: DateTime.utc(2026, 10, 5)));
        await local.agregar(nota('b', texto: 'Nueva', creada: DateTime.utc(2026, 10, 22)));
        await local.agregar(nota('c', ubicacionId: 'ub-2', texto: 'De otro'));
        await db.customStatement(
          'INSERT INTO nota (id, target_type, target_id, texto, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          ['p', 'PERSONA', 'ub-1', 'De persona', 1, 1],
        );

        final notas = await local.observar('ub-1').first;

        expect([for (final n in notas) n.texto], ['Nueva', 'Vieja']);
      },
    );

    test(
      'dado una nota borrada, llega marcada como borrada (la pantalla decide qué mostrar)',
      () async {
        await sembrar();
        await local.agregar(nota('a'));
        await local.borrar(id: 'a', ahora: t0.add(const Duration(minutes: 1)));

        final notas = await local.observar('ub-1').first;

        expect(notas.single.estaBorrada, isTrue);
      },
    );

    test('dado que agrego una nota con la lista abierta, la lista se actualiza sola', () async {
      await sembrar();
      final emisiones = <int>[];
      final sub = local.observar('ub-1').listen((l) => emisiones.add(l.length));

      await pumpEventQueue();
      await local.agregar(nota('a'));
      await pumpEventQueue();
      await sub.cancel();

      expect(emisiones, [0, 1]);
    });
  });

  group('editar', () {
    test(
      'dado una nota, cuando edito, cambia el texto y updated_at pero no created_at ni el autor',
      () async {
        await sembrar();
        await local.agregar(nota('a', texto: 'Antes'));
        final despues = t0.add(const Duration(hours: 1));

        final editada = await local.editar(id: 'a', texto: 'Después', ahora: despues);

        expect(editada.texto, 'Después');
        expect(editada.auditoria.updatedAt, despues);
        expect(editada.auditoria.createdAt, t0);
        expect(editada.auditoria.createdBy, 'col-1');
      },
    );

    test('dado el mismo texto, no toca updated_at', () async {
      await sembrar();
      await local.agregar(nota('a', texto: 'Igual'));

      final editada = await local.editar(
        id: 'a',
        texto: 'Igual',
        ahora: t0.add(const Duration(hours: 1)),
      );

      expect(editada.auditoria.updatedAt, t0);
    });

    test('dado un reloj que retrocede, updated_at no queda antes del que tenía', () async {
      await sembrar();
      await local.agregar(nota('a'));

      final editada = await local.editar(
        id: 'a',
        texto: 'Otro',
        ahora: t0.subtract(const Duration(days: 1)),
      );

      expect(editada.auditoria.updatedAt, t0);
    });

    test('dado una nota inexistente, una borrada o un lugar dado de baja, rechaza', () async {
      await sembrar();
      await local.agregar(nota('a'));
      await local.borrar(id: 'a', ahora: t0);

      await expectLater(
        local.editar(id: 'zzz', texto: 'x', ahora: t0),
        rechaza(MotivoRechazoNota.notaInexistente),
      );
      await expectLater(
        local.editar(id: 'a', texto: 'x', ahora: t0),
        rechaza(MotivoRechazoNota.notaBorrada),
      );

      await db.customStatement('UPDATE ubicacion SET deleted_at = ?', [t0.millisecondsSinceEpoch]);
      await local
          .restaurar(id: 'a', ahora: t0)
          .then<void>(
            (_) => fail('un lugar de baja no restaura'),
            onError: (Object e) =>
                expect((e as NotaRechazadaException).motivo, MotivoRechazoNota.ubicacionDeBaja),
          );
    });
  });

  group('borrar y restaurar', () {
    test('dado una nota, cuando la borro, queda la fila con deleted_at (no se pierde)', () async {
      await sembrar();
      await local.agregar(nota('a'));

      final borrada = await local.borrar(id: 'a', ahora: t0.add(const Duration(minutes: 5)));

      expect(borrada.estaBorrada, isTrue);
      expect(await filas(), 1);
    });

    test(
      'dado una nota borrada, cuando la borro de nuevo o la restauro dos veces, no cambia nada más',
      () async {
        await sembrar();
        await local.agregar(nota('a'));
        final primera = await local.borrar(id: 'a', ahora: t0.add(const Duration(minutes: 5)));
        final segunda = await local.borrar(id: 'a', ahora: t0.add(const Duration(minutes: 9)));
        expect(segunda, primera);

        final r1 = await local.restaurar(id: 'a', ahora: t0.add(const Duration(minutes: 10)));
        final r2 = await local.restaurar(id: 'a', ahora: t0.add(const Duration(minutes: 11)));

        expect(r1.estaBorrada, isFalse);
        expect(r2, r1);
      },
    );

    test(
      'dado dos borrados casi simultáneos de notas distintas, quedan las dos borradas',
      () async {
        await sembrar();
        await local.agregar(nota('a'));
        await local.agregar(nota('b'));

        await Future.wait([local.borrar(id: 'a', ahora: t0), local.borrar(id: 'b', ahora: t0)]);

        expect(await filas('deleted_at IS NOT NULL'), 2);
      },
    );

    test('dado un lugar dado de baja, no se borra ni se restaura una nota', () async {
      await sembrar();
      await local.agregar(nota('a'));
      await local.agregar(nota('b'));
      await local.borrar(id: 'b', ahora: t0);
      await db.customStatement('UPDATE ubicacion SET deleted_at = ?', [t0.millisecondsSinceEpoch]);

      await expectLater(
        local.borrar(id: 'a', ahora: t0),
        rechaza(MotivoRechazoNota.ubicacionDeBaja),
      );
      await expectLater(
        local.restaurar(id: 'b', ahora: t0),
        rechaza(MotivoRechazoNota.ubicacionDeBaja),
      );
      expect(await filas('deleted_at IS NOT NULL'), 1);
    });

    test('dado una nota de una persona con el mismo id, el lugar no la ve ni la toca', () async {
      await sembrar();
      await db.customStatement(
        'INSERT INTO nota (id, target_type, target_id, texto, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['p', 'PERSONA', 'ub-1', 'De persona', 1, 1],
      );

      await expectLater(
        local.borrar(id: 'p', ahora: t0),
        rechaza(MotivoRechazoNota.notaInexistente),
      );
    });
  });
}
