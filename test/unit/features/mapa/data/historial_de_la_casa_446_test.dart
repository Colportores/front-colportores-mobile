// El historial de la casa leído de la base real en memoria (vista 39, C·03, #446): las visitas del
// espacio, las ventas de sus personas y los cobros de esas ventas, de lo más nuevo a lo más viejo, con
// lo pagado, la nota de la visita y sin lo dado de baja.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart'
    show TipoResultadoVisita;
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart'
    show MedioCobranza;
import 'package:colportores_mobile/features/mapa/data/datasources/historial_de_la_casa_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/evento_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart'
    show LineaDeFicha;
import 'package:colportores_mobile/features/mapa/presentation/textos_historial_de_la_casa.dart'
    show FormatoHistorialDeLaCasa;
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late HistorialDeLaCasaLocalDataSourceDrift historial;

  Future<void> persona(String id, String nombre, {String apellido = '', DateTime? baja}) => db
      .into(db.personas)
      .insert(
        PersonasCompanion.insert(
          id: id,
          nombre: nombre,
          apellido: Value(apellido),
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(baja),
        ),
      );

  Future<void> visita(
    String id,
    String resultado,
    DateTime fecha, {
    String espacio = 'esp-1',
    String? vinculo = 'ep-1',
    DateTime? baja,
    DateTime? entrada,
    DateTime? salida,
  }) => db
      .into(db.visitas)
      .insert(
        VisitasCompanion.insert(
          id: id,
          espacioId: espacio,
          espacioPersonaId: Value(vinculo),
          fecha: fecha,
          tipoResultado: resultado,
          colportorId: 'col-1',
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(baja),
          entrevistaEntrada: Value(entrada),
          entrevistaSalida: Value(salida),
        ),
      );

  Future<void> nota(String id, String visitaId, String texto, {DateTime? creada, DateTime? baja}) =>
      db
          .into(db.notas)
          .insert(
            NotasCompanion.insert(
              id: id,
              targetType: 'VISITA',
              targetId: visitaId,
              texto: texto,
              createdAt: creada ?? t0,
              updatedAt: creada ?? t0,
              deletedAt: Value(baja),
            ),
          );

  Future<void> venta(
    String id,
    DateTime fecha, {
    String vinculo = 'ep-1',
    int monto = 480000,
    String talonario = '0038',
    String? visitaId,
    DateTime? baja,
  }) => db
      .into(db.ventas)
      .insert(
        VentasCompanion.insert(
          id: id,
          espacioPersonaId: vinculo,
          numeroTalonario: talonario,
          montoTotal: monto,
          fecha: fecha,
          colportorId: 'col-1',
          visitaId: Value(visitaId),
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(baja),
        ),
      );

  Future<void> renglon(
    String id,
    String ventaId, {
    String? producto,
    String? coleccion,
    int n = 1,
    List<Object?> componentes = const [],
  }) => db
      .into(db.ventaItems)
      .insert(
        VentaItemsCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: Value(producto),
          coleccionId: Value(coleccion),
          componentes: Value(coleccion == null ? null : componentes),
          cantidad: n,
          precioUnitario: 1000,
          subtotal: 1000 * n,
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> cobro(
    String id,
    String ventaId,
    int monto,
    DateTime fecha, {
    String medio = 'EFECTIVO',
    DateTime? baja,
    DateTime? creado,
  }) => db
      .into(db.cobranzas)
      .insert(
        CobranzasCompanion.insert(
          id: id,
          ventaId: ventaId,
          monto: monto,
          medio: medio,
          fecha: fecha,
          createdAt: creado ?? t0,
          updatedAt: creado ?? t0,
          deletedAt: Value(baja),
        ),
      );

  /// Una cuota del plan: una cita de cobranza con monto de la venta (decisión «Plan cuotas»).
  Future<void> cuota(
    String id,
    String ventaId,
    int monto,
    DateTime dia, {
    String estado = 'PROGRAMADA',
    DateTime? creada,
    DateTime? baja,
    bool conMonto = true,
  }) => db
      .into(db.agendas)
      .insert(
        AgendasCompanion.insert(
          id: id,
          espacioId: 'esp-1',
          espacioPersonaId: const Value('ep-1'),
          tipo: 'COBRANZA',
          fechaProgramada: dia,
          estado: Value(estado),
          colportorId: 'col-1',
          ventaId: Value(ventaId),
          montoPrevisto: Value(conMonto ? monto : null),
          createdAt: creada ?? t0,
          updatedAt: creada ?? t0,
          deletedAt: Value(baja),
        ),
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    await sembrarCasa(db);
    await persona('per-1', 'Pedro', apellido: 'Gómez');
    await db
        .into(db.productos)
        .insert(
          ProductosCompanion.insert(
            id: 'pro-1',
            nombre: 'Salud y Hogar',
            tipo: 'LIBRO',
            createdAt: t0,
            updatedAt: t0,
          ),
        );
    historial = HistorialDeLaCasaLocalDataSourceDrift(db);
  });
  tearDown(() => db.close());

  test('una casa sin nada no tiene historial', () async {
    expect(await historial.leer('esp-1'), isEmpty);
  });

  test('mezcla visitas, ventas y cobros de lo más nuevo a lo más viejo', () async {
    await visita('vis-1', 'NO_CONTESTO', DateTime.utc(2026, 10, 3, 15), vinculo: null);
    await visita('vis-2', 'ENTREVISTA', DateTime.utc(2026, 10, 5, 17));
    await venta('ven-1', DateTime.utc(2026, 10, 12, 14));
    await cobro('cob-1', 'ven-1', 60000, DateTime.utc(2026, 10, 12, 14, 20));

    final eventos = await historial.leer('esp-1');

    expect(eventos.map((e) => e.id), ['cob-1', 'ven-1', 'vis-2', 'vis-1']);
    expect(eventos[0], isA<CobroDeLaCasa>());
    expect(eventos[1], isA<VentaDeLaCasa>());
    expect((eventos[2] as VisitaDeLaCasa).resultado, TipoResultadoVisita.entrevista);
    expect((eventos[3] as VisitaDeLaCasa).persona, isNull);
  });

  test('la visita lleva a la persona y la entrevista no inventa una duración', () async {
    await visita('vis-1', 'ENTREVISTA', DateTime.utc(2026, 10, 5, 17));

    final visita1 = (await historial.leer('esp-1')).single as VisitaDeLaCasa;

    expect(visita1.persona?.nombreCompleto, 'Pedro Gómez');
    expect(visita1.persona?.nombreDePila, 'Pedro');
    expect(visita1.duracion, isNull);
  });

  group('la duración de la entrevista (C·03, #466)', () {
    test('con la entrada y la salida guardadas, es la salida menos la entrada', () async {
      await visita(
        'vis-1',
        'ENTREVISTA',
        DateTime.utc(2026, 10, 5, 17, 36),
        entrada: DateTime.utc(2026, 10, 5, 17, 14),
        salida: DateTime.utc(2026, 10, 5, 17, 36),
      );

      final visita1 = (await historial.leer('esp-1')).single as VisitaDeLaCasa;

      expect(visita1.duracion, const Duration(minutes: 22));
    });

    test('sin la salida (o sin la entrada) no se inventa una duración', () async {
      await visita(
        'vis-1',
        'ENTREVISTA',
        DateTime.utc(2026, 10, 5, 17),
        entrada: DateTime.utc(2026, 10, 5, 16, 40),
      );
      await visita(
        'vis-2',
        'ENTREVISTA',
        DateTime.utc(2026, 10, 6, 17),
        salida: DateTime.utc(2026, 10, 6, 17),
      );

      final eventos = await historial.leer('esp-1');

      expect([for (final e in eventos) (e as VisitaDeLaCasa).duracion], [null, null]);
    });

    test('una salida antes de la entrada no da una duración negativa', () async {
      await visita(
        'vis-1',
        'ENTREVISTA',
        DateTime.utc(2026, 10, 5, 17),
        entrada: DateTime.utc(2026, 10, 5, 17, 30),
        salida: DateTime.utc(2026, 10, 5, 17),
      );

      final visita1 = (await historial.leer('esp-1')).single as VisitaDeLaCasa;

      expect(visita1.duracion, isNull);
    });

    test('solo la entrevista lleva duración: otra visita con horas no', () async {
      await visita(
        'vis-1',
        'COBRANZA',
        DateTime.utc(2026, 10, 5, 17),
        entrada: DateTime.utc(2026, 10, 5, 16, 40),
        salida: DateTime.utc(2026, 10, 5, 17),
      );

      final visita1 = (await historial.leer('esp-1')).single as VisitaDeLaCasa;

      expect(visita1.duracion, isNull);
    });
  });

  test('la nota más nueva de la visita se ve; la borrada y la vacía no', () async {
    await visita('vis-1', 'ENTREVISTA', DateTime.utc(2026, 10, 5, 17));
    await nota('n-1', 'vis-1', 'volver con la esposa', creada: DateTime.utc(2026, 10, 5, 18));
    await nota('n-2', 'vis-1', 'la más vieja', creada: DateTime.utc(2026, 10, 5, 17));
    await nota('n-3', 'vis-1', 'borrada', creada: DateTime.utc(2026, 10, 6), baja: t0);
    await visita('vis-2', 'NO_CONTESTO', DateTime.utc(2026, 10, 3), vinculo: null);
    await nota('n-4', 'vis-2', '   ');

    final eventos = await historial.leer('esp-1');

    expect((eventos[0] as VisitaDeLaCasa).nota, 'volver con la esposa');
    expect((eventos[1] as VisitaDeLaCasa).nota, isNull);
  });

  test(
    'la venta lleva lo vendido, lo pagado y el saldo; el cobro dado de baja no cuenta',
    () async {
      await venta('ven-1', DateTime.utc(2026, 10, 12, 14));
      await renglon('it-1', 'ven-1', producto: 'pro-1');
      await renglon('it-2', 'ven-1', producto: 'borrado-del-catalogo', n: 2);
      await cobro('cob-1', 'ven-1', 200000, DateTime.utc(2026, 10, 12, 14, 5));
      await cobro('cob-2', 'ven-1', 160000, DateTime.utc(2026, 10, 14), medio: 'TRANSFERENCIA');
      await cobro('cob-3', 'ven-1', 99900, DateTime.utc(2026, 10, 15), baja: t0);

      final eventos = await historial.leer('esp-1');
      final v = eventos.whereType<VentaDeLaCasa>().single;

      expect(v.numeroTalonario, '0038');
      expect(v.montoCentavos, 480000);
      expect(v.pagadoCentavos, 360000);
      expect(v.saldoCentavos, 120000);
      expect(v.lineas, const [
        LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1),
        LineaDeFicha(nombre: 'Producto', cantidad: 2),
      ]);
      final cobros = eventos.whereType<CobroDeLaCasa>().toList();
      expect(cobros.map((c) => c.id), ['cob-2', 'cob-1']);
      expect(cobros.first.medio, MedioCobranza.transferencia);
      expect(cobros.last.medio, MedioCobranza.efectivo);
      expect(cobros.first.numeroTalonario, '0038');
      expect(cobros.first.persona?.nombreDePila, 'Pedro');
    },
  );

  group('qué cuotas cubrió cada cobro (C·03, decisión del 10/11)', () {
    final armado = DateTime.utc(2026, 10, 24);

    test('con plan: cuota completa, parte, varias y el cobro de antes del plan', () async {
      await venta('ven-1', DateTime.utc(2026, 10, 12, 14), monto: 300000);
      // Se cobró $ 600 al vender y el resto (2.400) quedó en 3 cuotas de 800.
      await cobro('cob-0', 'ven-1', 60000, DateTime.utc(2026, 10, 12, 14, 5));
      await cuota(
        'ag-1',
        'ven-1',
        80000,
        DateTime.utc(2026, 10, 25),
        estado: 'CUMPLIDA',
        creada: armado,
      );
      await cuota('ag-2', 'ven-1', 80000, DateTime.utc(2026, 11, 1), creada: armado);
      await cuota('ag-3', 'ven-1', 80000, DateTime.utc(2026, 11, 8), creada: armado);
      await cobro(
        'cob-1',
        'ven-1',
        80000,
        DateTime.utc(2026, 10, 25),
        creado: DateTime.utc(2026, 10, 25),
      );
      await cobro(
        'cob-2',
        'ven-1',
        40000,
        DateTime.utc(2026, 11, 1),
        creado: DateTime.utc(2026, 11, 1),
      );
      await cobro(
        'cob-3',
        'ven-1',
        120000,
        DateTime.utc(2026, 11, 8),
        creado: DateTime.utc(2026, 11, 8),
      );

      final cobros = {
        for (final c in (await historial.leer('esp-1')).whereType<CobroDeLaCasa>()) c.id: c,
      };

      expect(cobros['cob-0']!.cuotas, isNull);
      expect(FormatoHistorialDeLaCasa.subtitulo(cobros['cob-0']!), 'Venta 0038');
      expect(FormatoHistorialDeLaCasa.subtitulo(cobros['cob-1']!), 'Cuota 1 de 3');
      expect(FormatoHistorialDeLaCasa.subtitulo(cobros['cob-2']!), 'Parte de la cuota 2 de 3');
      expect(FormatoHistorialDeLaCasa.subtitulo(cobros['cob-3']!), 'Cuotas 2 y 3 de 3');
    });

    test('sin plan (sin citas con monto, o borradas), el cobro dice «Venta 0038»', () async {
      await venta('ven-1', DateTime.utc(2026, 10, 12, 14));
      await cuota(
        'ag-1',
        'ven-1',
        80000,
        DateTime.utc(2026, 10, 25),
        conMonto: false,
        creada: armado,
      );
      await cuota('ag-2', 'ven-1', 80000, DateTime.utc(2026, 11, 1), creada: armado, baja: armado);
      await cobro(
        'cob-1',
        'ven-1',
        80000,
        DateTime.utc(2026, 10, 25),
        creado: DateTime.utc(2026, 10, 25),
      );

      final c = (await historial.leer('esp-1')).whereType<CobroDeLaCasa>().single;

      expect(c.cuotas, isNull);
      expect(FormatoHistorialDeLaCasa.subtitulo(c), 'Venta 0038');
    });

    test('al día: una cuota nueva del plan cambia la línea del cobro por el stream', () async {
      await venta('ven-1', DateTime.utc(2026, 10, 12, 14));
      await cobro(
        'cob-1',
        'ven-1',
        80000,
        DateTime.utc(2026, 10, 25),
        creado: DateTime.utc(2026, 10, 25),
      );
      final lineas = historial
          .observar('esp-1')
          .map((e) => FormatoHistorialDeLaCasa.subtitulo(e.whereType<CobroDeLaCasa>().single));
      final vistas = <String?>[];
      final sub = lineas.listen(vistas.add);
      await pumpEventQueue();

      await cuota('ag-1', 'ven-1', 80000, DateTime.utc(2026, 10, 25), creada: armado);
      await cuota('ag-2', 'ven-1', 80000, DateTime.utc(2026, 11, 1), creada: armado);
      await pumpEventQueue();
      await sub.cancel();

      expect(vistas.first, 'Venta 0038');
      expect(vistas.last, 'Cuota 1 de 2');
    });
  });

  test('una venta cobrada de más no debe nada', () async {
    await venta('ven-1', DateTime.utc(2026, 10, 12), monto: 100000);
    await cobro('cob-1', 'ven-1', 150000, DateTime.utc(2026, 10, 13));

    final v = (await historial.leer('esp-1')).whereType<VentaDeLaCasa>().single;

    expect(v.saldoCentavos, 0);
  });

  test('un combo lleva sus libros con nombre: «Colección de 5 libros» (rev 1120)', () async {
    for (final (id, nombre) in [('pro-2', 'Nuestros Hijos'), ('pro-3', 'Vida Feliz')]) {
      await db
          .into(db.productos)
          .insert(
            ProductosCompanion.insert(
              id: id,
              nombre: nombre,
              tipo: 'LIBRO',
              createdAt: t0,
              updatedAt: t0,
            ),
          );
    }
    await venta('ven-1', DateTime.utc(2026, 10, 12));
    await renglon(
      'it-1',
      'ven-1',
      coleccion: 'col-borrada',
      componentes: const [
        {'producto_id': 'pro-1', 'cantidad': 1},
        {'producto_id': 'pro-2', 'cantidad': 1},
        {'producto_id': 'pro-3', 'cantidad': 2},
        {'producto_id': 'fuera-del-catalogo', 'cantidad': 1},
      ],
    );

    final v = (await historial.leer('esp-1')).single as VentaDeLaCasa;

    expect(v.lineas.single.libros, const [
      LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1),
      LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1),
      LineaDeFicha(nombre: 'Vida Feliz', cantidad: 2),
      LineaDeFicha(nombre: '', cantidad: 1),
    ]);
    expect(FormatoHistorialDeLaCasa.titulo(v), 'Colección de 5 libros · Pedro');
    expect(FormatoHistorialDeLaCasa.filasDeLibros(v.lineas), [
      ('Libro', 'Salud y Hogar'),
      ('Libro', 'Nuestros Hijos'),
      ('Libro', 'Vida Feliz × 2'),
      ('Combo', 'Colección'),
    ]);
  });

  test('un producto suelto no es un combo', () async {
    await venta('ven-1', DateTime.utc(2026, 10, 12));
    await renglon('it-1', 'ven-1', producto: 'pro-1', n: 2);

    final linea = ((await historial.leer('esp-1')).single as VentaDeLaCasa).lineas.single;

    expect(linea.esCombo, isFalse);
    expect(linea.cuantosLibros, 2);
  });

  test('una colección sin nombre en el catálogo queda como «Colección»', () async {
    await venta('ven-1', DateTime.utc(2026, 10, 12));
    await renglon('it-1', 'ven-1', coleccion: 'col-borrada');

    final v = (await historial.leer('esp-1')).single as VentaDeLaCasa;

    expect(v.lineas.single.nombre, 'Colección');
  });

  test(
    'la visita de venta que tiene su venta se ve como la venta, con la nota de la visita',
    () async {
      await visita('vis-v', 'VENTA', DateTime.utc(2026, 10, 12, 14));
      await nota('n-1', 'vis-v', 'quiere Nuestros Hijos');
      await venta('ven-1', DateTime.utc(2026, 10, 12, 14), visitaId: 'vis-v');

      final eventos = await historial.leer('esp-1');

      expect(eventos, hasLength(1));
      expect((eventos.single as VentaDeLaCasa).nota, 'quiere Nuestros Hijos');
    },
  );

  test('la visita de venta que se quedó sin su venta sigue a la vista', () async {
    await visita('vis-v', 'VENTA', DateTime.utc(2026, 10, 12, 14));
    await venta('ven-1', DateTime.utc(2026, 10, 12, 14), visitaId: 'vis-v', baja: t0);

    final eventos = await historial.leer('esp-1');

    expect(eventos.single, isA<VisitaDeLaCasa>());
    expect((eventos.single as VisitaDeLaCasa).resultado, TipoResultadoVisita.venta);
  });

  test('la visita de cobranza, el rechazo y el no contestó se ven con su resultado', () async {
    await visita('vis-1', 'COBRANZA', DateTime.utc(2026, 10, 14));
    await visita('vis-2', 'RECHAZO', DateTime.utc(2026, 10, 13), vinculo: null);

    final eventos = (await historial.leer('esp-1')).cast<VisitaDeLaCasa>();

    expect(eventos.map((e) => e.resultado), [
      TipoResultadoVisita.cobranza,
      TipoResultadoVisita.rechazo,
    ]);
  });

  test('lo dado de baja (visita, venta) no se muestra', () async {
    await visita('vis-1', 'ENTREVISTA', DateTime.utc(2026, 10, 5), baja: t0);
    await venta('ven-1', DateTime.utc(2026, 10, 12), baja: t0);
    await cobro('cob-1', 'ven-1', 1000, DateTime.utc(2026, 10, 13));

    expect(await historial.leer('esp-1'), isEmpty);
  });

  test('lo de otra casa no entra', () async {
    await sembrarUbicacion(db, id: 'ub-2');
    await sembrarEspacio(db, id: 'esp-2', ubicacionId: 'ub-2');
    await persona('per-2', 'Ana');
    await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-2', personaId: 'per-2');
    await visita(
      'vis-1',
      'ENTREVISTA',
      DateTime.utc(2026, 10, 5),
      espacio: 'esp-2',
      vinculo: 'ep-2',
    );
    await venta('ven-1', DateTime.utc(2026, 10, 12), vinculo: 'ep-2');
    await cobro('cob-1', 'ven-1', 1000, DateTime.utc(2026, 10, 13));
    await visita('vis-2', 'NO_CONTESTO', DateTime.utc(2026, 10, 1), vinculo: null);

    expect((await historial.leer('esp-1')).map((e) => e.id), ['vis-2']);
    expect((await historial.leer('esp-2')).map((e) => e.id), ['cob-1', 'ven-1', 'vis-1']);
  });

  test('lo que pasó con una persona que ya no está en la casa no se pierde', () async {
    await persona('per-9', 'Marta', apellido: 'Díaz', baja: t0);
    await sembrarVinculo(db, id: 'ep-9', personaId: 'per-9', borrado: t0);
    await venta('ven-9', DateTime.utc(2026, 10, 12), vinculo: 'ep-9', talonario: '0099');
    await visita('vis-9', 'ENTREVISTA', DateTime.utc(2026, 10, 5), vinculo: 'ep-9');

    final eventos = await historial.leer('esp-1');

    expect(eventos.map((e) => e.id), ['ven-9', 'vis-9']);
    expect((eventos.first as VentaDeLaCasa).persona?.nombreCompleto, 'Marta Díaz');
  });

  test('el mismo instante se ordena siempre igual', () async {
    final mismo = DateTime.utc(2026, 10, 5, 17);
    await visita('vis-a', 'NO_CONTESTO', mismo, vinculo: null);
    await visita('vis-b', 'RECHAZO', mismo, vinculo: null);

    expect((await historial.leer('esp-1')).map((e) => e.id), ['vis-b', 'vis-a']);
  });

  test('al día: una visita nueva llega sola por el stream', () async {
    final llegaron = <List<String>>[];
    final suscripcion = historial
        .observar('esp-1')
        .listen((e) => llegaron.add([for (final x in e) x.id]));
    addTearDown(suscripcion.cancel);
    await pumpEventQueue();
    await visita('vis-1', 'ENTREVISTA', DateTime.utc(2026, 10, 5));
    await pumpEventQueue();
    await venta('ven-1', DateTime.utc(2026, 10, 12));
    await pumpEventQueue();
    await cobro('cob-1', 'ven-1', 1000, DateTime.utc(2026, 10, 13));
    await pumpEventQueue();

    expect(llegaron.first, isEmpty);
    expect(llegaron.last, ['cob-1', 'ven-1', 'vis-1']);
  });

  test('una casa con cientos de eventos se lee entera', () async {
    for (var i = 0; i < 300; i++) {
      await visita(
        'v-${i.toString().padLeft(3, '0')}',
        'NO_CONTESTO',
        DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
        vinculo: null,
      );
    }

    final eventos = await historial.leer('esp-1');

    expect(eventos, hasLength(300));
    expect(eventos.first.id, 'v-299');
    expect(eventos.last.id, 'v-000');
  });
}
