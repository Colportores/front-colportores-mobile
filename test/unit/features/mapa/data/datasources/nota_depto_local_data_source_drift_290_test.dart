// Las notas de un depto (vista 11, «Nota depto», #290) contra las tablas reales: AppDatabase en memoria,
// mismo esquema y mismas restricciones que en el dispositivo. Son las mismas piezas que las notas de un
// lugar con `target_type = ESPACIO`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_persona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_borradas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_nota.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 20, 13, 45, 10, 123);
  final t1 = t0.add(const Duration(minutes: 5));

  Auditoria auditoria({DateTime? creada}) =>
      Auditoria(createdAt: creada ?? t0, updatedAt: creada ?? t0, createdBy: 'col-1');

  NotaUbicacion nota(
    String id, {
    String espacioId = 'e-3b',
    String texto = 'timbre roto, tocar fuerte',
    DateTime? creada,
  }) => NotaUbicacion(
    id: id,
    ubicacionId: espacioId,
    texto: texto,
    auditoria: auditoria(creada: creada),
  );

  late AppDatabase db;
  late NotaUbicacionLocalDataSourceDrift deptos;
  late NotaUbicacionLocalDataSourceDrift lugares;

  Future<void> sembrar({DateTime? lugarDeBaja, DateTime? deptoDeBaja}) async {
    final ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria());
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
        id: 'e-3b',
        ubicacionId: 'ub-1',
        numeroDepto: '3B',
        piso: '3',
        auditoria: auditoria(),
      ),
    );
    if (lugarDeBaja != null) {
      await db.customStatement('UPDATE ubicacion SET deleted_at = ? WHERE id = ?', [
        lugarDeBaja.millisecondsSinceEpoch,
        'ub-1',
      ]);
    }
    if (deptoDeBaja != null) {
      await db.customStatement('UPDATE espacio SET deleted_at = ? WHERE id = ?', [
        deptoDeBaja.millisecondsSinceEpoch,
        'e-3b',
      ]);
    }
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    deptos = NotaUbicacionLocalDataSourceDrift(db, objetivo: TipoObjetivoNota.espacio);
    lugares = NotaUbicacionLocalDataSourceDrift(db);
  });

  tearDown(() => db.close());

  Future<int> filas([String donde = '1 = 1']) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM nota WHERE $donde').getSingle()).read<int>(
        'n',
      );

  Matcher rechaza(MotivoRechazoNota motivo) =>
      throwsA(isA<NotaRechazadaException>().having((e) => e.motivo, 'motivo', motivo));

  group('agregar', () {
    test('dado un depto, cuando agrego una nota, guarda la fila ESPACIO con mi autor', () async {
      await sembrar();

      final guardada = await deptos.agregar(nota('nota-1'));

      expect(guardada.texto, 'timbre roto, tocar fuerte');
      final fila = await db
          .customSelect('SELECT target_type, target_id, texto, created_by, deleted_at FROM nota')
          .getSingle();
      expect(fila.read<String>('target_type'), 'ESPACIO');
      expect(fila.read<String>('target_id'), 'e-3b');
      expect(fila.read<String>('created_by'), 'col-1');
      expect(fila.read<int?>('deleted_at'), isNull);
    });

    test(
      'dado el mismo envío repetido (doble toque), cuando agrego otra vez, no duplica',
      () async {
        await sembrar();

        await deptos.agregar(nota('nota-1', texto: 'Primera'));
        final otra = await deptos.agregar(nota('nota-1', texto: 'Distinta'));
        await Future.wait([deptos.agregar(nota('nota-2')), deptos.agregar(nota('nota-2'))]);

        expect(otra.texto, 'Primera');
        expect(await filas(), 2);
      },
    );

    test('dado un depto con varias notas, cuando agrego otra, no pisa a las anteriores', () async {
      await sembrar();

      await deptos.agregar(nota('nota-1', texto: 'Primera'));
      await deptos.agregar(nota('nota-2', texto: 'Segunda', creada: t1));

      final lista = await deptos.observar('e-3b').first;
      expect(lista.map((n) => n.texto), ['Segunda', 'Primera'], reason: 'la más nueva primero');
    });

    test('dado un depto que no está en el teléfono, cuando agrego, rechaza sin escribir', () async {
      await sembrar();

      await expectLater(
        deptos.agregar(nota('nota-1', espacioId: 'e-fantasma')),
        rechaza(MotivoRechazoNota.espacioInexistente),
      );
      expect(await filas(), 0);
    });

    test('dado un depto dado de baja, cuando agrego, rechaza: se ve, no se toca', () async {
      await sembrar(deptoDeBaja: t1);

      await expectLater(deptos.agregar(nota('nota-1')), rechaza(MotivoRechazoNota.espacioDeBaja));
      expect(await filas(), 0);
    });

    test('dado un lugar dado de baja, cuando agrego a su depto, rechaza', () async {
      await sembrar(lugarDeBaja: t1);

      await expectLater(deptos.agregar(nota('nota-1')), rechaza(MotivoRechazoNota.ubicacionDeBaja));
      expect(await filas(), 0);
    });
  });

  group('editar, borrar y restaurar', () {
    test('dado una nota, cuando la edito, cambia el texto y updated_at, no created_at', () async {
      await sembrar();
      await deptos.agregar(nota('nota-1'));

      final editada = await deptos.editar(id: 'nota-1', texto: 'timbre arreglado', ahora: t1);

      expect(editada.texto, 'timbre arreglado');
      expect(editada.auditoria.createdAt, t0);
      expect(editada.auditoria.updatedAt, t1);
    });

    test('dado una nota, cuando la borro y la restauro, vuelve con su texto y su fecha', () async {
      await sembrar();
      await deptos.agregar(nota('nota-1'));

      final borrada = await deptos.borrar(id: 'nota-1', ahora: t1);
      expect(borrada.estaBorrada, isTrue);
      expect(await filas('deleted_at IS NOT NULL'), 1, reason: 'soft delete: la fila sigue');

      final vuelta = await deptos.restaurar(id: 'nota-1', ahora: t1.add(const Duration(hours: 1)));
      expect(vuelta.estaBorrada, isFalse);
      expect((vuelta.texto, vuelta.auditoria.createdAt), ('timbre roto, tocar fuerte', t0));
    });

    test('dado un borrado repetido (doble toque), cuando borro otra vez, no cambia nada', () async {
      await sembrar();
      await deptos.agregar(nota('nota-1'));
      final primera = await deptos.borrar(id: 'nota-1', ahora: t1);

      final segunda = await deptos.borrar(id: 'nota-1', ahora: t1.add(const Duration(hours: 2)));

      expect(segunda.auditoria.deletedAt, primera.auditoria.deletedAt);
    });

    test('dado una nota borrada, cuando la edito, rechaza: primero se restaura', () async {
      await sembrar();
      await deptos.agregar(nota('nota-1'));
      await deptos.borrar(id: 'nota-1', ahora: t1);

      await expectLater(
        deptos.editar(id: 'nota-1', texto: 'otra cosa', ahora: t1),
        rechaza(MotivoRechazoNota.notaBorrada),
      );
    });

    test('dado el depto dado de baja después de la nota, cuando la borro, rechaza', () async {
      await sembrar();
      await deptos.agregar(nota('nota-1'));
      await db.customStatement('UPDATE espacio SET deleted_at = ? WHERE id = ?', [
        t1.millisecondsSinceEpoch,
        'e-3b',
      ]);

      await expectLater(
        deptos.borrar(id: 'nota-1', ahora: t1),
        rechaza(MotivoRechazoNota.espacioDeBaja),
      );
      // La baja del depto no borra la nota: sigue en el teléfono.
      expect(await filas('deleted_at IS NULL'), 1);
    });
  });

  group('cada dueño ve solo lo suyo', () {
    test('dado una nota del depto y otra del lugar, cuando leo, no se mezclan', () async {
      await sembrar();
      await deptos.agregar(nota('nota-depto', texto: 'del depto'));
      await lugares.agregar(nota('nota-lugar', espacioId: 'ub-1', texto: 'del lugar'));

      expect((await deptos.observar('e-3b').first).map((n) => n.texto), ['del depto']);
      expect((await lugares.observar('ub-1').first).map((n) => n.texto), ['del lugar']);
      // Un id del otro dueño no existe para este: no se edita ni se borra desde el equivocado.
      await expectLater(
        deptos.borrar(id: 'nota-lugar', ahora: t1),
        rechaza(MotivoRechazoNota.notaInexistente),
      );
      await expectLater(
        lugares.borrar(id: 'nota-depto', ahora: t1),
        rechaza(MotivoRechazoNota.notaInexistente),
      );
    });

    test(
      'dado el texto de la nota, cuando se lee la lista, no se imprime en el toString',
      () async {
        await sembrar();
        final guardada = await deptos.agregar(nota('nota-1', texto: 'secreto del timbre'));

        expect('$guardada', isNot(contains('secreto del timbre')));
      },
    );
  });

  group('límites del texto', () {
    test(
      'dado un texto de 5000 caracteres, cuando lo guardo, se guarda entero (límite blando)',
      () async {
        await sembrar();
        final largo = List.filled(5000, 'a').join();

        final guardada = await deptos.agregar(nota('nota-1', texto: largo));

        expect(guardada.texto.length, 5000);
      },
    );
  });

  group('limpieza de los 90 días', () {
    test(
      'dado una nota del depto borrada hace más de 90 días, cuando limpia, se va; la de 89 se queda',
      () async {
        await sembrar();
        final ahora = DateTime.utc(2027, 2, 20);
        await deptos.agregar(nota('vieja'));
        await deptos.agregar(nota('reciente', creada: t1));
        await deptos.agregar(nota('activa', creada: t1));
        await deptos.borrar(id: 'vieja', ahora: ahora.subtract(const Duration(days: 91)));
        await deptos.borrar(id: 'reciente', ahora: ahora.subtract(const Duration(days: 89)));

        final borradas = await NotasBorradasLocalDataSourceDrift(db).purgarVencidas(ahora: ahora);

        expect(borradas, 1);
        final ids = (await db.customSelect('SELECT id FROM nota').get()).map(
          (f) => f.read<String>('id'),
        );
        expect(ids, unorderedEquals(['reciente', 'activa']));
      },
    );
  });
}
