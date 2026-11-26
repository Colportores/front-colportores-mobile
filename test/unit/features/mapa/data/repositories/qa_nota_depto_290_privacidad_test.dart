// QA de la nota del depto (#290, PR #776), privacidad: el texto de una nota del depto vive solo en el
// teléfono. Con la base real en memoria: ni los logs de agregar, editar, borrar y restaurar, ni los
// `toString()` de la nota, de su resumen y del depto fundido lo dicen, y ninguna operación encola nada
// para subir (`sync_queue` vacía).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/movimientos_de_union.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/nota_ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resumen_del_depto.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

final class _Salida extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

/// Un texto que no se parece a nada de lo que la app escribe: si aparece en un log o en un `toString`,
/// es que se filtró.
const _secreto = 'ZXQ-clave del portón 4471 😀';

void main() {
  final t0 = DateTime.utc(2026, 11, 20, 13, 45);
  late AppDatabase db;
  late _Salida salida;
  late NotaUbicacionRepositoryImpl repo;

  Auditoria auditoria() => Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1');

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
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
    salida = _Salida();
    repo = NotaUbicacionRepositoryImpl(
      NotaUbicacionLocalDataSourceDrift(db, objetivo: TipoObjetivoNota.espacio),
      logger: AppLogger(
        logger: Logger(level: Level.trace, output: salida),
      ),
      delDepto: true,
    );
  });

  tearDown(() => db.close());

  test(
    'dado agregar, editar, borrar y restaurar una nota de un depto, cuando miro los logs, el texto '
    'no está y el prefijo es NOTA_DEPTO',
    () async {
      final nota = NotaUbicacion(
        id: 'n-1',
        ubicacionId: 'e-3b',
        texto: _secreto,
        auditoria: auditoria(),
      );
      expect((await repo.agregar(nota)).isRight(), isTrue);
      expect(
        (await repo.editar(id: 'n-1', texto: '$_secreto editada', ahora: t0)).isRight(),
        isTrue,
      );
      expect((await repo.borrar(id: 'n-1', ahora: t0)).isRight(), isTrue);
      expect((await repo.restaurar(id: 'n-1', ahora: t0)).isRight(), isTrue);
      // Un rechazo (depto que no existe) también se loguea.
      final rechazo = await repo.agregar(
        NotaUbicacion(id: 'n-2', ubicacionId: 'no-existe', texto: _secreto, auditoria: auditoria()),
      );
      expect(rechazo.isLeft(), isTrue);

      final log = salida.lineas.join('\n');
      expect(log, isNotEmpty, reason: 'el repositorio sí deja rastro de lo que hizo');
      expect(log, contains('NOTA_DEPTO_'));
      expect(log, isNot(contains('NOTA_LUGAR_')));
      expect(log, isNot(contains('ZXQ')));
      expect(log, isNot(contains('4471')));
      expect(log, isNot(contains('portón')));
    },
  );

  test(
    'dado una nota del depto, cuando hago toString de la nota y de su resumen, no dicen el texto',
    () {
      final nota = NotaUbicacion(
        id: 'n-1',
        ubicacionId: 'e-3b',
        texto: _secreto,
        auditoria: auditoria(),
      );
      final resumen = ResumenDelDepto(notaMasNueva: _secreto);

      expect('$nota', isNot(contains('ZXQ')));
      expect('$resumen', isNot(contains('ZXQ')));
      expect('$nota $resumen', isNot(contains('4471')));
    },
  );

  test(
    'dado que el depto se funde en otro, cuando miro el movimiento, lleva solo los id de las notas',
    () {
      const movimiento = EspacioFundido(espacioId: 'e-3b', unicoDeA: 'e-1a', notas: ['n-1', 'n-2']);

      expect(movimiento.toJson()['notas'], ['n-1', 'n-2']);
      expect('${movimiento.toJson()}', isNot(contains('ZXQ')));
    },
  );

  test(
    'dado una nota del depto, cuando la agrego, la edito y la borro, no se encola nada para subir (las '
    'notas son solo del teléfono)',
    () async {
      final nota = NotaUbicacion(
        id: 'n-1',
        ubicacionId: 'e-3b',
        texto: _secreto,
        auditoria: auditoria(),
      );
      await repo.agregar(nota);
      await repo.editar(id: 'n-1', texto: 'otra', ahora: t0);
      await repo.borrar(id: 'n-1', ahora: t0);

      expect(await db.select(db.syncQueue).get(), isEmpty);
    },
  );
}
