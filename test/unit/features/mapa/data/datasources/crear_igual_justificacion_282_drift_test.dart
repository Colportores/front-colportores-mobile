// La justificación de «Crear igual» (HU-UBI-001, #282; decisión de Cristian, 06/10, «Justificar»)
// contra las tablas reales: AppDatabase en memoria. Queda en el `audit_log` local con el uuid de la
// ubicación, en la misma transacción que el alta, y nunca en la cola de sync ni en una columna.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

final class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  final t0 = DateTime.utc(2026, 10, 6, 9, 30, 15, 250);
  final t1 = DateTime.utc(2026, 10, 6, 10, 0, 0, 500);
  const texto = 'Es la puerta de al lado, tiene otro timbre';

  UbicacionModel ubicacion({
    String id = 'ub-nueva',
    String calle = 'Av. Italia',
    String numero = '1234',
    double metrosAlNorte = 0,
    DateTime? actualizada,
  }) => UbicacionModel(
    id: id,
    tipo: TipoUbicacion.casa,
    calle: calle,
    numero: numero,
    lat: -34.891 + metrosAlNorte / 111195.08,
    lon: -56.125,
    ciudadId: 'mvd',
    auditoria: Auditoria(createdAt: t0, updatedAt: actualizada ?? t0, createdBy: 'col-1'),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift local;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador);
  });

  tearDown(() => db.close());

  Future<List<AuditLogFila>> auditoria() =>
      (db.select(db.auditLogLocal)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  group('Alta con «Crear igual»', () {
    test('dado un alta con justificación, queda en la auditoría local con el uuid de la ubicación '
        'nueva, el texto sin espacios en los bordes y la marca de su updated_at', () async {
      await local.insertar(ubicacion(), justificacion: '  $texto  ');

      final filas = await auditoria();
      expect(filas, hasLength(1));
      expect(filas.single.evento, EventoAuditoriaLocal.ubicacionCrearIgual);
      expect(filas.single.uuid, 'ub-nueva');
      expect(filas.single.motivo, texto);
      expect(filas.single.creadoEn, t0);
    });

    test('no va a la cola de sync ni a ninguna columna de la ubicación', () async {
      await local.insertar(ubicacion(), justificacion: texto);

      expect(encolador.encolados.map((c) => c.entidad), ['ubicacion']);
      expect('${encolador.encolados.map((c) => c.payload)}', isNot(contains(texto)));
      final guardada = await local.obtener('ub-nueva');
      expect('${guardada!.toJson()}', isNot(contains(texto)));
    });

    for (final vacia in <String?>[null, '', '   ']) {
      test('dado un alta con justificación ${vacia == null ? 'nula' : "'$vacia'"}, no escribe '
          'ninguna fila de auditoría', () async {
        await local.insertar(ubicacion(), justificacion: vacia);

        expect(await auditoria(), isEmpty);
        expect(await local.obtener('ub-nueva'), isNotNull);
      });
    }

    test('dado un doble envío del mismo alta (mismo id), la justificación se guarda una sola vez '
        'y la segunda llamada no escribe nada', () async {
      await local.insertar(ubicacion(), justificacion: texto);
      final segunda = await local.insertar(ubicacion(), justificacion: 'Otro texto distinto');

      expect(segunda.yaEstaba, isTrue);
      final filas = await auditoria();
      expect(filas, hasLength(1));
      expect(filas.single.motivo, texto);
    });

    test('dado que el alta frena por duplicados, no queda ninguna justificación', () async {
      await local.insertar(ubicacion(id: 'ub-vieja'));

      await expectLater(
        local.insertar(
          ubicacion(calle: 'Otra calle', numero: '9', metrosAlNorte: 3),
          justificacion: texto,
          duplicados: const CriterioDuplicadoUbicacion(),
        ),
        throwsA(isA<UbicacionDuplicadaException>()),
      );

      expect(await auditoria(), isEmpty);
      expect(await local.obtener('ub-nueva'), isNull);
    });

    test('dado «Crear igual» sobre un duplicado que admite conservar las dos, se crea y queda la '
        'justificación', () async {
      await local.insertar(ubicacion(id: 'ub-vieja'));

      await local.insertar(
        ubicacion(calle: 'Otra calle', numero: '9', metrosAlNorte: 3),
        justificacion: texto,
        duplicados: const CriterioDuplicadoUbicacion().alSeguirIgual,
      );

      final filas = await auditoria();
      expect(filas.single.uuid, 'ub-nueva');
      expect(filas.single.motivo, texto);
    });

    test('dado que el encolado falla, la transacción se revierte y no queda ni la ubicación ni la '
        'justificación', () async {
      encolador.fallarCon = StateError('motor apagado');

      await expectLater(
        local.insertar(ubicacion(), justificacion: texto),
        throwsA(isA<StateError>()),
      );

      expect(await auditoria(), isEmpty);
      expect(await local.obtener('ub-nueva'), isNull);
    });

    test('dos altas «Crear igual» seguidas guardan cada una su justificación '
        'con su uuid', () async {
      await local.insertar(ubicacion(id: 'ub-a'), justificacion: 'Primera casa del fondo');
      await local.insertar(
        ubicacion(id: 'ub-b', calle: 'Otra', numero: '2'),
        justificacion: 'Segunda casa del fondo',
      );

      final filas = await auditoria();
      expect(filas.map((f) => (f.uuid, f.motivo)), [
        ('ub-a', 'Primera casa del fondo'),
        ('ub-b', 'Segunda casa del fondo'),
      ]);
    });

    test('la justificación no se confunde con el motivo de una baja: la lista de bajas no la '
        'toma', () async {
      await local.insertar(ubicacion(), justificacion: texto);

      final lista = await local.observarListaDelColportor(colportorId: 'col-1').first;
      expect(lista.single.motivoBaja, isNull);
    });
  });

  group('Edición con «Crear igual» (la hoja es la misma)', () {
    test('dado una edición con justificación, queda con el id de la ubicación y su updated_at '
        'nuevo, y el update encolado no la lleva', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();

      await local.actualizar(
        ubicacion(numero: '1236', actualizada: t1),
        baseUpdatedAt: t0,
        justificacion: texto,
      );

      final filas = await auditoria();
      expect(filas, hasLength(1));
      expect(filas.single.evento, EventoAuditoriaLocal.ubicacionCrearIgual);
      expect(filas.single.uuid, 'ub-nueva');
      expect(filas.single.motivo, texto);
      expect(filas.single.creadoEn, t1);
      expect('${encolador.encolados.map((c) => c.payload)}', isNot(contains(texto)));
    });

    test('la fila de auditoría no viaja por el sync: solo se encola el update de la ubicación, '
        'sin la justificación ni el motivo', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();

      await local.actualizar(
        ubicacion(numero: '1236', actualizada: t1),
        baseUpdatedAt: t0,
        justificacion: texto,
      );

      expect(encolador.encolados.map((c) => (c.entidad, c.operacion)), [
        ('ubicacion', OperacionSync.update),
      ]);
      expect(encolador.encolados.single.payload.keys, isNot(contains('motivo')));
    });

    test('dado que la ubicación cambió desde que se leyó, no escribe ni la '
        'justificación', () async {
      await local.insertar(ubicacion(actualizada: t1));

      await expectLater(
        local.actualizar(
          ubicacion(numero: '1236', actualizada: t1),
          baseUpdatedAt: t0,
          justificacion: texto,
        ),
        throwsA(isA<UbicacionCambioException>()),
      );

      expect(await auditoria(), isEmpty);
    });

    test('dado una edición sin justificación, no escribe auditoría', () async {
      await local.insertar(ubicacion());

      await local.actualizar(
        ubicacion(numero: '1236', actualizada: t1),
        baseUpdatedAt: t0,
      );

      expect(await auditoria(), isEmpty);
    });
  });

  group('Falla al guardar la justificación: el texto no sale en el log', () {
    const privado = 'La familia García de la casa azul';
    late _SalidaEnMemoria salida;
    late UbicacionRepositoryImpl repositorio;

    setUp(() {
      salida = _SalidaEnMemoria();
      repositorio = UbicacionRepositoryImpl(local, logger: AppLogger(output: salida));
    });

    Future<void> fallarElInsertEnAudit() => db.customStatement(
      'CREATE TRIGGER falla_audit BEFORE INSERT ON audit_log '
      "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END",
    );

    void sinElTexto() {
      final log = salida.lineas.join(' ');
      expect(log, contains('SqliteException'), reason: 'el tipo sí');
      expect(log, contains('result_code'), reason: 'el código sí');
      expect(log, isNot(contains('García')));
      expect(log, isNot(contains('INSERT INTO "audit_log"')), reason: 'ni la sentencia');
    }

    test('dado que falla el INSERT en audit_log en el alta, devuelve FailureInesperado, no queda '
        'nada a medias y el log no lleva la justificación', () async {
      await fallarElInsertEnAudit();

      final r = await repositorio.registrar(
        ubicacion().toEntity(),
        origen: OrigenCoordenadas.gps,
        justificacion: privado,
      );

      expect(r.fold((f) => f, (_) => null), isA<FailureInesperado>());
      expect(salida.lineas.join(' '), contains('UBICACION_ALTA_FAIL'));
      sinElTexto();
      expect(await local.obtener('ub-nueva'), isNull, reason: 'la transacción se revirtió');
    });

    test('dado que falla el INSERT en audit_log en la edición, devuelve FailureInesperado, no '
        'cambia la ubicación y el log no lleva la justificación', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();
      await fallarElInsertEnAudit();

      final r = await repositorio.modificar(
        ubicacion(numero: '1236', actualizada: t1).toEntity(),
        baseUpdatedAt: t0,
        justificacion: privado,
      );

      expect(r.fold((f) => f, (_) => null), isA<FailureInesperado>());
      expect(salida.lineas.join(' '), contains('UBICACION_MODIFICAR_FAIL'));
      sinElTexto();
      expect((await local.obtener('ub-nueva'))!.numero, '1234');
    });
  });
}
