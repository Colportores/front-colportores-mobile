// La lectura de la ficha de una persona (HU-UBI-009, #403) contra las tablas reales en memoria: sus
// visitas y ventas por todos sus vínculos, ordenadas, sin lo borrado, reactiva, y el evento
// `click_to_call` sin el número.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ficha_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FichaPersonaLocalDataSourceDrift fuente;

  Future<void> sembrarPersona({
    String id = 'per-1',
    String? telefono = '099123456',
    DateTime? borrada,
  }) => db
      .into(db.personas)
      .insert(
        PersonasCompanion.insert(
          id: id,
          nombre: 'María',
          apellido: const Value('Pérez'),
          telefono: Value(telefono),
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrada),
        ),
      );

  Future<void> sembrarProducto(String id, String nombre) => db
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

  Future<void> sembrarVenta(
    String id, {
    String vinculo = 'ep-1',
    String talonario = '0042',
    int monto = 60000,
    DateTime? fecha,
    DateTime? borrada,
  }) => db
      .into(db.ventas)
      .insert(
        VentasCompanion.insert(
          id: id,
          espacioPersonaId: vinculo,
          numeroTalonario: talonario,
          montoTotal: monto,
          fecha: fecha ?? t0,
          colportorId: 'col-1',
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrada),
        ),
      );

  Future<void> sembrarRenglon(
    String id,
    String ventaId, {
    String? producto,
    String? coleccion,
    int cantidad = 1,
    DateTime? borrada,
  }) => db
      .into(db.ventaItems)
      .insert(
        VentaItemsCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: Value(producto),
          coleccionId: Value(coleccion),
          cantidad: cantidad,
          precioUnitario: 1000,
          subtotal: 1000 * cantidad,
          componentes: Value(coleccion == null ? null : const <Object?>[]),
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrada),
        ),
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    fuente = FichaPersonaLocalDataSourceDrift(db);
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  test('sin la persona en el teléfono, la lectura es null', () async {
    expect(await fuente.observar('per-1').first, isNull);
  });

  test('la persona sin nada que mostrar: sus datos y el historial vacío', () async {
    await sembrarPersona();

    final lectura = (await fuente.observar('per-1').first)!;

    expect(lectura.persona.nombre, 'María');
    expect(lectura.persona.telefono, '099123456');
    expect(lectura.historial, isEmpty);
  });

  test('una persona dada de baja también se lee (la ficha es de solo lectura)', () async {
    await sembrarPersona(borrada: t0);

    final lectura = (await fuente.observar('per-1').first)!;

    expect(lectura.persona.estaBorrada, isTrue);
  });

  test('junta visitas y ventas, la más nueva primero, con los nombres de lo vendido', () async {
    await sembrarPersona();
    await sembrarProducto('pro-1', 'Salud y Hogar');
    await db
        .into(db.colecciones)
        .insert(
          ColeccionesCompanion.insert(
            id: 'col-1',
            nombre: 'Nuestros Hijos',
            createdAt: t0,
            updatedAt: t0,
          ),
        );
    await insertarVisita(db, visitaDe('vis-vieja', creada: DateTime.utc(2026, 10, 5, 14)));
    await sembrarVenta('ven-1', fecha: DateTime.utc(2026, 10, 12, 14));
    await sembrarRenglon('it-1', 'ven-1', producto: 'pro-1', cantidad: 2);
    await sembrarRenglon('it-2', 'ven-1', coleccion: 'col-1');

    final lectura = (await fuente.observar('per-1').first)!;

    expect(lectura.historial.map((m) => m.id), ['ven-1', 'vis-vieja']);
    final venta = lectura.historial.first as VentaEnFicha;
    expect(venta.numeroTalonario, '0042');
    expect(venta.montoCentavos, 60000);
    expect(venta.lineas, const [
      LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 2),
      LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1),
    ]);
    final visita = lectura.historial.last as VisitaEnFicha;
    expect(visita.resultado, TipoResultadoVisita.entrevista);
  });

  test('un producto que el catálogo ya no trae no se inventa: queda como «Producto»', () async {
    await sembrarPersona();
    await sembrarVenta('ven-1');
    await sembrarRenglon('it-1', 'ven-1', producto: 'pro-que-no-esta');

    final venta = (await fuente.observar('per-1').first)!.historial.single as VentaEnFicha;

    expect(venta.lineas.single.nombre, 'Producto');
  });

  test('lo borrado (visitas, ventas y renglones) no aparece', () async {
    await sembrarPersona();
    await sembrarProducto('pro-1', 'Salud y Hogar');
    await insertarVisita(db, visitaDe('vis-borrada', borrada: t0));
    await sembrarVenta('ven-borrada', borrada: t0);
    await sembrarVenta('ven-1');
    await sembrarRenglon('it-1', 'ven-1', producto: 'pro-1');
    await sembrarRenglon('it-borrado', 'ven-1', producto: 'pro-1', borrada: t0);

    final lectura = (await fuente.observar('per-1').first)!;

    expect(lectura.historial.map((m) => m.id), ['ven-1']);
    expect((lectura.historial.single as VentaEnFicha).lineas, hasLength(1));
  });

  test('lo de otra persona no se mezcla', () async {
    await sembrarPersona();
    await sembrarPersona(id: 'per-2');
    await sembrarVinculo(db, id: 'ep-9', personaId: 'per-2');
    await insertarVisita(db, visitaDe('vis-de-otra', vinculo: 'ep-9'));
    await sembrarVenta('ven-de-otra', vinculo: 'ep-9');

    expect((await fuente.observar('per-1').first)!.historial, isEmpty);
  });

  test(
    'la persona en dos deptos (uno dado de baja) junta el historial de los dos vínculos',
    () async {
      await sembrarPersona();
      await sembrarEspacio(db, id: 'esp-3', numeroDepto: '3B');
      await sembrarVinculo(db, id: 'ep-3', espacioId: 'esp-3', borrado: t0);
      await insertarVisita(db, visitaDe('vis-1', creada: DateTime.utc(2026, 10, 6)));
      await insertarVisita(
        db,
        visitaDe('vis-2', espacio: 'esp-3', vinculo: 'ep-3', creada: DateTime.utc(2026, 10, 7)),
      );

      final lectura = (await fuente.observar('per-1').first)!;

      expect(lectura.historial.map((m) => m.id), ['vis-2', 'vis-1']);
    },
  );

  test('a igual fecha desempata por id, siempre en el mismo orden', () async {
    await sembrarPersona();
    await insertarVisita(db, visitaDe('a'));
    await insertarVisita(db, visitaDe('b'));

    final lectura = (await fuente.observar('per-1').first)!;

    expect(lectura.historial.map((m) => m.id), ['b', 'a']);
  });

  test('más de 500 movimientos se leen enteros (la pantalla es la que pagina)', () async {
    await sembrarPersona();
    for (var i = 0; i < 620; i++) {
      await insertarVisita(
        db,
        visitaDe('vis-${i.toString().padLeft(4, '0')}', creada: t0.add(Duration(minutes: i))),
      );
    }

    final lectura = (await fuente.observar('per-1').first)!;

    expect(lectura.historial, hasLength(620));
    expect(lectura.historial.first.id, 'vis-0619');
  });

  test('es reactivo: una visita nueva sale en una lectura nueva', () async {
    await sembrarPersona();
    final lecturas = <int>[];
    final sub = fuente.observar('per-1').listen((l) => lecturas.add(l!.historial.length));
    addTearDown(sub.cancel);
    await pumpEventQueue();

    await insertarVisita(db, visitaDe('vis-1'));
    await pumpEventQueue();

    expect(lecturas.first, 0);
    expect(lecturas.last, 1);
  });

  group('registrarLlamada', () {
    test('deja click_to_call con el id de la persona y sin el número', () async {
      await sembrarPersona();

      await fuente.registrarLlamada(personaId: 'per-1', ahora: t0);

      final filas = await db.select(db.auditLogLocal).get();
      expect(filas, hasLength(1));
      expect(filas.single.evento, EventoAuditoriaLocal.clickToCall);
      expect(filas.single.uuid, 'per-1');
      expect(filas.single.toString().contains('099123456'), isFalse);
      expect(filas.single.toString().contains('99123456'), isFalse);
    });
  });
}
