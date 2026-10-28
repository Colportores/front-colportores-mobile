// QA de «Entrega diferida» (BACK-HU-VEN-003, #433): lo que una persona puede hacer con la lógica sin
// pantalla, contra la DB real en memoria y los casos de uso de verdad (no los dobles). Cubre los dos
// escenarios literales de la HU, las acciones superpuestas, la falla a mitad, la validación de entradas,
// los datos límite, el cambio de fecha desde la Agenda, la privacidad y lo que baja del servidor.
//
// Los hallazgos van con `skip:` (convención de los issues `[QA-*]`).
import 'dart:async';

import 'package:colportores_mobile/catalogo.dart' show entidadesQueEscribeElMotor;
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source.dart'
    show AgendaRechazadaException;
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/cambios_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/entrega_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/models/entrega_model.dart';
import 'package:colportores_mobile/features/ventas/data/repositories/entrega_repository_impl.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/cumplir_entrega_use_case.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/diferir_entrega_use_case.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:equatable/equatable.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../helpers/campo_falsos.dart';
import '../../../helpers/entrega_falsos.dart';
import '../../../helpers/logger_mudo.dart';
import '../../../helpers/venta_falsos.dart';

/// Un plugin de avisos que lanza en vez de contestar.
final class _AvisosQueRevientan implements Recordatorios {
  @override
  Future<ResultadoRecordatorio> programar(RecordatorioDeVisita visita) async =>
      throw StateError('plugin');

  @override
  Future<bool> cancelar(String agendaId) async => throw StateError('plugin');

  @override
  Future<bool> puedeAvisar() async => throw StateError('plugin');
}

/// Recoge cada línea que el logger del repositorio escribe.
final class _Salida extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late VentaLocalDataSourceDrift ventas;
  late EntregaLocalDataSourceDrift local;
  late EntregaRepositoryImpl repo;
  late RecordatoriosEnMemoria avisos;
  late DiferirEntregaUseCase diferir;
  late CumplirEntregaUseCase cumplir;
  late _Salida salida;
  var ids = 0;
  // Miércoles 20/05/2026, 12:00 en Montevideo.
  var reloj = DateTime.utc(2026, 5, 20, 15);

  setUp(() async {
    reloj = DateTime.utc(2026, 5, 20, 15);
    ids = 0;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final estado = HouseStatusUpdaterDrift(db, encolador: encolador);
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: estado);
    local = EntregaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: estado);
    salida = _Salida();
    repo = EntregaRepositoryImpl(local, logger: AppLogger(output: salida));
    avisos = RecordatoriosEnMemoria();
    diferir = DiferirEntregaUseCase(
      repo,
      avisos,
      generarId: () => 'id-${++ids}',
      ahora: () => reloj,
    );
    cumplir = CumplirEntregaUseCase(
      repo,
      avisos,
      generarId: () => 'id-${++ids}',
      ahora: () => reloj,
    );
    await sembrarCasa(db);
    await (db.update(
      db.ubicaciones,
    )).write(const UbicacionesCompanion(calle: Value('Grecia'), numero: Value('3310')));
  });
  tearDown(() => db.close());

  Future<List<EntregaFila>> filas() =>
      (db.select(db.entregas)..orderBy([(e) => OrderingTerm.asc(e.id)])).get();
  Future<List<AgendaFila>> citas() => db.select(db.agendas).get();

  Future<void> vender({String id = 'v-1', int monto = 150000}) async {
    await ventas.registrar(ventaDe(id, monto: monto, talonario: 'T-$id'), [itemDe('i-$id', id)]);
    encolador.encolados.clear();
  }

  DiferirEntregaParams dejar(
    DateTime fecha, {
    String venta = 'v-1',
    List<ComponenteVendido> productos = const [
      ComponenteVendido(productoId: 'prod-1', cantidad: 2),
      ComponenteVendido(productoId: 'prod-2'),
    ],
  }) => DiferirEntregaParams(
    ventaId: venta,
    colportorId: 'col-1',
    fechaPrevista: fecha,
    productos: productos,
  );

  final primeroDeJunio = DateTime.utc(2026, 6, 1, 12);
  final dosDeJunio = DateTime.utc(2026, 6, 2, 12);

  group('Escenario: Entrega diferida (literal de la HU)', () {
    test('dado que vendí pero no tengo material, cuando elijo «Entrega en otra fecha» y selecciono '
        '2026-06-01, entonces se crea entrega con fecha_prevista=2026-06-01 y estado=PENDIENTE y se '
        'agenda recordatorio para esa fecha', () async {
      await vender();

      final r = await diferir(dejar(primeroDeJunio));

      expect(r.isRight(), isTrue, reason: r.fold((f) => f.mensaje, (_) => ''));
      final guardadas = await filas();
      expect(guardadas, hasLength(2));
      expect(guardadas.every((f) => f.pendiente), isTrue, reason: 'estado = PENDIENTE');
      expect(guardadas.every((f) => f.fechaPrevista == primeroDeJunio), isTrue);
      expect(guardadas.every((f) => f.fechaEntrega == null), isTrue, reason: 'aún sin fecha real');
      final cita = (await citas()).single;
      expect(cita.tipo, 'ENTREGA');
      expect(cita.estado, 'PROGRAMADA');
      expect(cita.fechaProgramada, primeroDeJunio);
      final aviso = avisos.programados[cita.id];
      expect(aviso, isNotNull, reason: 'recordatorio agendado');
      expect(aviso!.fechaProgramada, primeroDeJunio);
      expect(aviso.tipo, TipoAgenda.entrega);
      expect(aviso.direccion, 'Grecia 3310');
    });

    test(
      'dado que tengo entrega pendiente, cuando registro «Entregado hoy», entonces estado pasa a '
      'ENTREGADO con la fecha real (distinta de la prevista) y el recordatorio ya no suena',
      () async {
        await vender();
        await diferir(dejar(primeroDeJunio));
        // Se entrega un día antes de lo previsto.
        reloj = DateTime.utc(2026, 5, 31, 18, 30);

        final r = await cumplir(const CumplirEntregaParams(ventaId: 'v-1'));

        expect(r.isRight(), isTrue, reason: r.fold((f) => f.mensaje, (_) => ''));
        final guardadas = await filas();
        expect(guardadas.every((f) => !f.pendiente), isTrue, reason: 'estado = ENTREGADO');
        expect(guardadas.every((f) => f.fechaEntrega == reloj), isTrue, reason: 'fecha real');
        expect(guardadas.every((f) => f.fechaPrevista == primeroDeJunio), isTrue);
        expect((await citas()).single.estado, 'CUMPLIDA');
        expect(avisos.programados, isEmpty);
        expect(await local.observarPendientes().first, isEmpty);
      },
    );
  });

  group('acciones superpuestas', () {
    test('dos «Entrega en otra fecha» a la vez dejan una sola entrega y una sola cita', () async {
      await vender();

      final r = await Future.wait([diferir(dejar(primeroDeJunio)), diferir(dejar(primeroDeJunio))]);

      expect(r.every((x) => x.isRight()), isTrue);
      expect(await filas(), hasLength(2), reason: 'no se duplican las filas por producto');
      expect(await citas(), hasLength(1));
      expect(avisos.programados.keys, hasLength(1));
    });

    test('dos fechas distintas a la vez: queda una cita y toda la entrega con SU fecha', () async {
      await vender();

      await Future.wait([diferir(dejar(primeroDeJunio)), diferir(dejar(dosDeJunio))]);

      final cita = (await citas()).single;
      expect((await filas()).map((f) => f.fechaPrevista).toSet(), {cita.fechaProgramada});
      expect(avisos.programados.values.single.fechaProgramada, cita.fechaProgramada);
    });

    test(
      'dos «Entregado hoy» a la vez dejan la fecha real del primero y una sola cita cumplida',
      () async {
        await vender();
        await diferir(dejar(primeroDeJunio));
        final ids1 = {'id-1', 'id-2'};

        final r = await Future.wait([
          cumplir(CumplirEntregaParams(ventaId: 'v-1', entregaIds: ids1)),
          cumplir(CumplirEntregaParams(ventaId: 'v-1', entregaIds: ids1)),
        ]);

        expect(r.every((x) => x.isRight()), isTrue);
        expect((await filas()).every((f) => !f.pendiente), isTrue);
        expect((await citas()).single.estado, 'CUMPLIDA');
      },
    );

    // skip: QA #433: el segundo toque a «Entregado hoy» sin ids devuelve una falla y no «ya estaba».
    test(
      'el segundo toque a «Entregado hoy» (todo lo pendiente) no muestra un error: ya estaba entregado',
      () async {
        await vender();
        await diferir(dejar(primeroDeJunio));

        final r = await Future.wait([
          cumplir(const CumplirEntregaParams(ventaId: 'v-1')),
          cumplir(const CumplirEntregaParams(ventaId: 'v-1')),
        ]);

        expect(
          r.every((x) => x.isRight()),
          isTrue,
          reason:
              'el caso de uso se documenta idempotente («marcar de nuevo lo ya entregado no '
              'escribe nada»); con ids lo cumple, sin ids devuelve ${r.map((x) => x.fold((f) => f.mensaje, (_) => 'ok'))}',
        );
      },
      skip: 'QA #433: marcar de nuevo, sin ids, devuelve una validación en vez de «ya estaba»',
    );
  });

  group('falla a mitad de la acción', () {
    test('si el guardado falla, no queda nada y el reintento funciona una sola vez', () async {
      await vender();
      encolador.fallarCon = StateError('motor apagado');
      encolador.fallarDespuesDe = 2;

      final primera = await diferir(dejar(primeroDeJunio));

      expect(primera.isLeft(), isTrue);
      expect(await filas(), isEmpty);
      expect(await citas(), isEmpty);
      expect(avisos.llamadas, isEmpty, reason: 'sin guardar no se avisa nada');

      encolador.fallarCon = null;
      final segunda = await diferir(dejar(primeroDeJunio));

      expect(segunda.isRight(), isTrue);
      expect(await filas(), hasLength(2));
      expect(await citas(), hasLength(1));
      expect(avisos.programados, hasLength(1));
    });

    test(
      'si «Entregado hoy» falla a mitad, lo pendiente sigue pendiente y se puede reintentar',
      () async {
        await vender();
        await diferir(dejar(primeroDeJunio));
        encolador.encolados.clear();
        encolador.fallarCon = StateError('motor apagado');
        encolador.fallarDespuesDe = 1;

        final primera = await cumplir(const CumplirEntregaParams(ventaId: 'v-1'));

        expect(primera.isLeft(), isTrue);
        expect((await filas()).every((f) => f.pendiente && f.fechaEntrega == null), isTrue);
        expect((await citas()).single.estado, 'PROGRAMADA');
        expect(avisos.programados, hasLength(1), reason: 'el aviso sigue');

        encolador.fallarCon = null;
        final segunda = await cumplir(const CumplirEntregaParams(ventaId: 'v-1'));

        expect(segunda.isRight(), isTrue);
        expect((await filas()).every((f) => !f.pendiente), isTrue);
        expect(avisos.programados, isEmpty);
      },
    );

    test(
      'el plugin de avisos que revienta no deshace la entrega ni deja la vista sin respuesta',
      () async {
        await vender();
        final reventado = DiferirEntregaUseCase(
          repo,
          _AvisosQueRevientan(),
          generarId: () => 'id-${++ids}',
          ahora: () => reloj,
        );

        final r = await reventado(dejar(primeroDeJunio));

        expect(r.isRight(), isTrue);
        expect(await filas(), hasLength(2));
      },
    );
  });

  group('validación de entradas', () {
    Future<void> nadaGuardado() async {
      expect(await filas(), isEmpty);
      expect(await citas(), isEmpty);
      expect(avisos.llamadas, isEmpty);
    }

    for (final caso in <(String, DiferirEntregaParams, String)>[
      (
        'cantidad 0',
        dejar(primeroDeJunio, productos: const [ComponenteVendido(productoId: 'p', cantidad: 0)]),
        'productos',
      ),
      (
        'cantidad negativa',
        dejar(primeroDeJunio, productos: const [ComponenteVendido(productoId: 'p', cantidad: -3)]),
        'productos',
      ),
      (
        'cantidad 100000',
        dejar(
          primeroDeJunio,
          productos: const [ComponenteVendido(productoId: 'p', cantidad: 100000)],
        ),
        'productos',
      ),
      (
        'el mismo producto dos veces suma más del tope',
        dejar(
          primeroDeJunio,
          productos: const [
            ComponenteVendido(productoId: 'p', cantidad: 99999),
            ComponenteVendido(productoId: 'p'),
          ],
        ),
        'productos',
      ),
      ('venta en blanco', dejar(primeroDeJunio, venta: '   '), 'venta'),
      ('venta vacía', dejar(primeroDeJunio, venta: ''), 'venta'),
    ]) {
      test('${caso.$1}: es una validación del campo ${caso.$3} y no guarda nada', () async {
        await vender();

        final r = await diferir(caso.$2);

        final f = r.swap().toOption().toNullable();
        expect(f, isA<FailureValidacion>());
        expect((f! as FailureValidacion).campos, contains(caso.$3));
        await nadaGuardado();
      });
    }

    test('el colportor en blanco es una validación y no guarda nada', () async {
      await vender();

      final r = await diferir(
        DiferirEntregaParams(
          ventaId: 'v-1',
          colportorId: '  ',
          fechaPrevista: DateTime.utc(2026, 6, 1, 12),
          productos: const [ComponenteVendido(productoId: 'prod-1')],
        ),
      );

      expect(
        (r.swap().toOption().toNullable()! as FailureValidacion).campos,
        contains('colportorId'),
      );
      await nadaGuardado();
    });

    test(
      'un producto con emoji o texto raro como id se guarda tal cual, sin romper la cola',
      () async {
        await vender();

        final r = await diferir(
          dejar(
            primeroDeJunio,
            productos: const [
              ComponenteVendido(productoId: "prod-ñ-😀-'\"; drop table entrega;--"),
            ],
          ),
        );

        expect(r.isRight(), isTrue);
        expect((await filas()).single.productoId, "prod-ñ-😀-'\"; drop table entrega;--");
        expect(await citas(), hasLength(1));
      },
    );

    test(
      '«ayer a las 23:59» es un día pasado con el texto literal; «hoy a las 00:00» vale',
      () async {
        await vender();
        reloj = DateTime(2026, 5, 20, 15);

        final ayer = await diferir(dejar(DateTime(2026, 5, 19, 23, 59)));

        final falla = ayer.swap().toOption().toNullable()! as FailureValidacion;
        expect(falla.campos['fecha'], 'Esa fecha ya pasó. Elegí hoy o un día más adelante.');
        await nadaGuardado();

        final hoy = await diferir(dejar(DateTime(2026, 5, 20)));

        expect(hoy.isRight(), isTrue, reason: 'hoy vale aunque la hora ya haya pasado');
        expect(
          avisos.programados,
          isEmpty,
          reason: 'la hora ya pasó: se agenda sin aviso y no suena nada',
        );
        expect(await citas(), hasLength(1));
      },
    );

    test('«Entregado hoy» sin ningún producto elegido dice qué hacer y no toca nada', () async {
      await vender();
      await diferir(dejar(primeroDeJunio));

      final r = await cumplir(const CumplirEntregaParams(ventaId: 'v-1', entregaIds: {}));

      final falla = r.swap().toOption().toNullable()! as FailureValidacion;
      expect(falla.campos['productos'], 'Elegí al menos un producto para marcar como entregado.');
      expect((await filas()).every((f) => f.pendiente), isTrue);
    });
  });

  group('reentrada y reintentos', () {
    test('volver a dejar la misma fecha tres veces no duplica filas, citas ni avisos', () async {
      await vender();
      await diferir(dejar(primeroDeJunio));
      final cola = encolador.encolados.length;

      for (var i = 0; i < 2; i++) {
        final r = await diferir(dejar(primeroDeJunio));
        expect(r.getOrElse(() => throw StateError('falló')).entrega.yaEstaba, isTrue);
      }

      expect(await filas(), hasLength(2));
      expect(await citas(), hasLength(1));
      expect(avisos.programados, hasLength(1));
      expect(encolador.encolados, hasLength(cola), reason: 'no se vuelve a encolar nada');
    });

    test(
      'cambiar la fecha mueve la cita, las filas y el aviso (el aviso viejo no queda)',
      () async {
        await vender();
        await diferir(dejar(primeroDeJunio));

        await diferir(dejar(dosDeJunio));

        final cita = (await citas()).single;
        expect(cita.fechaProgramada, dosDeJunio);
        expect((await filas()).map((f) => f.fechaPrevista).toSet(), {dosDeJunio});
        expect(avisos.programados.values.single.fechaProgramada, dosDeJunio);
      },
    );

    test(
      'cancelar la cita a mano no pierde la entrega: sigue en pendientes y «Poner fecha» agenda otra',
      () async {
        await vender();
        await diferir(dejar(primeroDeJunio));
        final agenda = AgendaLocalDataSourceDrift(
          db,
          encolador: encolador,
          estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
        );
        final emisiones = <List<EntregaPendiente>>[];
        final sub = local.observarPendientes().listen(emisiones.add);
        addTearDown(sub.cancel);
        await pumpEventQueue();
        expect(emisiones.last.single.agendaId, isNotNull);

        await agenda.cancelar((await citas()).single.id, ahora: reloj);
        await pumpEventQueue();

        expect(emisiones.last.single.agendaId, isNull);
        expect(emisiones.last.single.fechaPrevista, primeroDeJunio);
        expect(emisiones.last.single.lineas, hasLength(2));

        final r = await diferir(dejar(dosDeJunio));
        await pumpEventQueue();

        expect(r.isRight(), isTrue);
        expect((await citas()).where((c) => c.estado == 'PROGRAMADA'), hasLength(1));
        expect(emisiones.last.single.agendaId, isNotNull);
      },
    );
  });

  group('datos límite', () {
    test('sin entregas pendientes la lista es vacía y no falla', () async {
      expect(await local.observarPendientes().first, isEmpty);
      expect(await local.observarPendientes(espacioPersonaId: 'ep-1').first, isEmpty);
    });

    test('una sola entrega, un solo producto, cantidad máxima', () async {
      await vender();

      final r = await diferir(
        dejar(
          primeroDeJunio,
          productos: const [ComponenteVendido(productoId: 'p', cantidad: 99999)],
        ),
      );

      expect(r.isRight(), isTrue);
      final lista = await local.observarPendientes().first;
      expect(lista.single.lineas.single.cantidad, 99999);
    });

    test(
      'muchas ventas: primero las que tienen fecha, de la más próxima a la más lejana, y después las sin fecha',
      () async {
        for (var i = 0; i < 30; i++) {
          await vender(id: 'v-$i', monto: 0);
        }
        // Las pares con fecha (en desorden); las impares quedaron sin fecha: entrega inmediata parcial.
        for (var i = 0; i < 30; i += 2) {
          final dias = (i * 7) % 13;
          await diferir(dejar(DateTime.utc(2026, 6, 1 + dias, 12), venta: 'v-$i'));
        }
        for (var i = 1; i < 30; i += 2) {
          await repo.entregarAhora('v-$i', [
            entregaDe('s-$i-0', 'p-0', ventaId: 'v-$i'),
            entregaDe('s-$i-1', 'p-1', pendiente: true, ventaId: 'v-$i'),
          ]);
        }

        final lista = await local.observarPendientes().first;

        expect(lista, hasLength(30));
        final conFecha = lista.takeWhile((e) => e.fechaPrevista != null).toList();
        expect(conFecha, hasLength(15));
        final fechas = [for (final e in conFecha) e.fechaPrevista!];
        expect([...fechas]..sort(), fechas);
        expect(lista.skip(15).every((e) => e.sinFecha && e.agendaId == null), isTrue);
      },
    );

    test('lo que queda sin fecha (parcial) figura al final de la lista', () async {
      await vender(id: 'v-a', monto: 0);
      await vender(id: 'v-b', monto: 0);
      await diferir(dejar(dosDeJunio, venta: 'v-a'));
      await diferir(dejar(primeroDeJunio, venta: 'v-b'));
      await cumplir(CumplirEntregaParams(ventaId: 'v-a', entregaIds: {(await filas()).first.id}));

      final lista = await local.observarPendientes().first;

      expect(lista.map((e) => e.ventaId), ['v-b', 'v-a']);
      expect(lista.last.sinFecha, isTrue);
      expect(lista.last.agendaId, isNull);
    });
  });

  group('cambiar la fecha desde la Agenda', () {
    late AgendaLocalDataSourceDrift agenda;
    setUp(() {
      agenda = AgendaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
      );
    });

    test(
      'mover la cita arrastra la fecha prevista de lo pendiente y de lo pendiente solo',
      () async {
        await vender();
        await diferir(dejar(primeroDeJunio));
        final cita = (await citas()).single;
        await cumplir(CumplirEntregaParams(ventaId: 'v-1', entregaIds: {(await filas()).first.id}));
        // El parcial cumplió la cita; se vuelve a fechar lo que quedó.
        await diferir(dejar(primeroDeJunio));
        final viva = (await citas()).firstWhere((c) => c.estado == 'PROGRAMADA');
        expect(viva.id, isNot(cita.id));

        await agenda.modificar(
          CambiosDeAgenda(
            agendaId: viva.id,
            tipo: TipoAgenda.entrega,
            fechaProgramada: dosDeJunio,
            idNota: 'n-1',
          ),
          ahora: reloj,
        );

        final guardadas = await filas();
        final entregada = guardadas.firstWhere((f) => !f.pendiente);
        final pendiente = guardadas.firstWhere((f) => f.pendiente);
        expect(pendiente.fechaPrevista, dosDeJunio);
        expect(
          entregada.fechaPrevista,
          primeroDeJunio,
          reason: 'lo entregado conserva lo acordado',
        );
      },
    );

    // Defensa en profundidad: la pantalla ya no ofrece convertir una cita de entrega, pero el origen de
    // datos acepta el cambio y lo frena un CHECK crudo de SQLite (`entrega_id IS NULL OR tipo =
    // 'ENTREGA'`), que sube como una excepción de SQL en vez del rechazo de la agenda.
    test(
      'una cita de entrega no se convierte en otro tipo: se rechaza con la excepción de la agenda',
      () async {
        await vender();
        await diferir(dejar(primeroDeJunio));
        final cita = (await citas()).single;

        Object? error;
        try {
          await agenda.modificar(
            CambiosDeAgenda(
              agendaId: cita.id,
              tipo: TipoAgenda.entrevista,
              fechaProgramada: dosDeJunio,
              idNota: 'n-1',
            ),
            ahora: reloj,
          );
        } on Object catch (e) {
          error = e;
        }

        expect((await citas()).single.tipo, 'ENTREGA');
        expect((await filas()).map((f) => f.fechaPrevista).toSet(), {primeroDeJunio});
        expect(error, isA<AgendaRechazadaException>(), reason: 'subió: $error');
      },
      skip:
          'QA #433: modificar() acepta cambiar el tipo de una cita ENTREGA y lo frena un CHECK crudo',
    );

    test('esa misma conversión, aunque llegue, deja la entrega y su fecha intactas', () async {
      await vender();
      await diferir(dejar(primeroDeJunio));
      final cita = (await citas()).single;

      await expectLater(
        agenda.modificar(
          CambiosDeAgenda(
            agendaId: cita.id,
            tipo: TipoAgenda.entrevista,
            fechaProgramada: dosDeJunio,
            idNota: 'n-1',
          ),
          ahora: reloj,
        ),
        throwsA(anything),
      );

      expect((await citas()).single.tipo, 'ENTREGA');
      expect((await citas()).single.fechaProgramada, primeroDeJunio);
      expect((await filas()).map((f) => f.fechaPrevista).toSet(), {primeroDeJunio});
    });
  });

  group('privacidad', () {
    // El peor caso: `EquatableConfig.stringify` arranca en `true` en debug (test/README.md,
    // `sin_pii_en_tostring_test.dart`); las entidades con datos sensibles lo apagan una por una.
    late bool? antes;
    setUp(() {
      antes = EquatableConfig.stringify;
      EquatableConfig.stringify = true;
    });
    tearDown(() => EquatableConfig.stringify = antes ?? false);

    test('los logs del repositorio, aun al rechazar una entrega, llevan ids y nada más', () async {
      await vender();
      await diferir(dejar(primeroDeJunio));
      await repo.diferir(
        'v-inexistente',
        fechaPrevista: primeroDeJunio,
        ahora: reloj,
        filasNuevas: const [],
        idDeLaCita: 'x',
      );
      await repo.cumplir('v-inexistente', ahora: reloj, idDeLaCita: 'x');

      final log = salida.lineas.join(' | ');
      expect(log, contains('ENTREGA_DIFERIDA_RECHAZADA'));
      expect(log, isNot(contains('Grecia')));
      expect(log, isNot(contains('3310')));
    });

    test('la entrega pendiente y las excepciones se imprimen sin datos de la persona', () async {
      await vender();
      await diferir(dejar(primeroDeJunio));
      final pendientes = await local.observarPendientes().first;

      final todo = [
        pendientes.toString(),
        const EntregaSinCasaException().toString(),
        const EntregaSinPendientesException().toString(),
        const EntregaAjenaException().toString(),
      ].join(' | ');

      expect(todo, isNot(contains('Grecia')));
      expect(todo, isNot(contains('3310')));
    });

    test(
      'lo que devuelve «Dejar para otro día» no imprime la dirección de la casa',
      () async {
        await vender();
        final d = (await diferir(dejar(primeroDeJunio))).getOrElse(() => throw StateError('falló'));

        expect(d.toString(), isNot(contains('Grecia')));
        expect(d.entrega.toString(), isNot(contains('Grecia')));
      },
      skip: 'QA #433: EntregaDiferida lleva la dirección en props y no apaga stringify',
    );

    test(
      'lo que devuelve «Entregado hoy» no imprime la dirección de la casa',
      () async {
        await vender();
        await diferir(dejar(primeroDeJunio));
        final c = (await cumplir(
          const CumplirEntregaParams(ventaId: 'v-1'),
        )).getOrElse(() => throw StateError('falló'));

        expect(c.entrega.toString(), isNot(contains('Grecia')));
      },
      skip: 'QA #433: EntregaCumplida lleva la dirección en props y no apaga stringify',
    );
  });

  group('lo que baja del servidor', () {
    test(
      'la entrega con fecha_prevista y la cita ENTREGA del servidor entran y se leen igual',
      () async {
        await vender();
        final store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);
        final entrega = {
          'id': 'srv-e-1',
          'venta_id': 'v-1',
          'producto_id': 'prod-1',
          'cantidad': 2,
          'pendiente': true,
          'fecha_prevista': '2026-06-01T12:00:00.000Z',
          'fecha_entrega': null,
          'created_at': '2026-05-20T15:00:00.000Z',
          'updated_at': '2026-05-20T15:00:00.000Z',
          'created_by': 'col-1',
          'deleted_at': null,
          'sync_version': 3,
        };
        final cita = {
          'id': 'srv-c-1',
          'espacio_id': 'esp-1',
          'espacio_persona_id': null,
          'tipo': 'ENTREGA',
          'fecha_programada': '2026-06-01T12:00:00.000Z',
          'slot_codigo': null,
          'es_estricta': false,
          'ubicacion_alt_id': null,
          'estado': 'PROGRAMADA',
          'colportor_id': 'col-1',
          'visita_id': null,
          'venta_id': 'v-1',
          'entrega_id': 'srv-e-1',
          // El servidor manda más columnas de las que la tabla local conoce: se ignoran.
          'monto_previsto': null,
          'created_at': '2026-05-20T15:00:00.000Z',
          'updated_at': '2026-05-20T15:00:00.000Z',
          'created_by': 'col-1',
          'deleted_at': null,
          'sync_version': 2,
        };

        await store.applyDelta(
          {
            'entrega': [entrega],
            'agenda': [cita],
          },
          scope: 'mirror',
          watermark: 'w1',
        );

        final lista = await local.observarPendientes().first;
        expect(lista.single.lineas.single.entregaId, 'srv-e-1');
        expect(lista.single.fechaPrevista, DateTime.utc(2026, 6, 1, 12));
        expect(lista.single.agendaId, 'srv-c-1');
        final volcada = EntregaModel.desdeFila((await filas()).single);
        expect(EntregaModel.toJson(volcada), entrega);
      },
    );
  });
}
