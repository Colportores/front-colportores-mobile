// El resumen de cada depto de la hoja del edificio (vista 39, C·09, #452) contra las tablas reales:
// AppDatabase en memoria, el mismo esquema que en el dispositivo.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/resumen_de_los_deptos_drift.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/color_house_status.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resumen_del_depto.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ResumenDeLosDeptosDrift lector;
  // «Ahora» del lector: un día antes de la entrevista de `agendaDe` (25/10 14:00 UTC).
  final ahora = DateTime.utc(2026, 10, 24, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    lector = ResumenDeLosDeptosDrift(db, ahora: () => ahora);
    // Edificio `ub-1` con el 1A (`esp-1`, persona en `ep-1`) y el 2B (`esp-2`, persona en `ep-2`).
    await sembrarEdificio(db);
  });
  tearDown(() => db.close());

  Future<Map<String, ResumenDelDepto>> primero({String? colportor = 'col-1'}) =>
      lector.observar('ub-1', colportorId: colportor).first;

  Future<void> sembrarVenta(String id, {required String vinculo, required int monto}) => db
      .into(db.ventas)
      .insert(
        VentasCompanion.insert(
          id: id,
          espacioPersonaId: vinculo,
          numeroTalonario: '0001',
          montoTotal: monto,
          fecha: t0,
          colportorId: 'col-1',
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  group('dado un edificio con dos deptos', () {
    test('sin nada en ninguno: los dos son «Sin visita», sin fechas', () async {
      final resumen = await primero();

      expect(resumen.keys.toSet(), {'esp-1', 'esp-2'});
      expect(resumen['esp-1'], ResumenDelDepto());
      expect(resumen['esp-2'], ResumenDelDepto());
    });

    test('cada depto tiene su estado, y no se mezcla con el del otro', () async {
      await insertarVisita(db, visitaDe('vis-1', resultado: TipoResultadoVisita.noContesto));
      await insertarAgenda(db, agendaDe('age-1', espacio: 'esp-2', vinculo: 'ep-2'));

      final resumen = await primero();

      expect(resumen['esp-1']!.estado, EstadoCasa.noContesto);
      expect(resumen['esp-1']!.ultimaVisita, t0);
      expect(resumen['esp-1']!.proximaEntrevista, isNull);
      expect(resumen['esp-2']!.estado, EstadoCasa.entrevistaAgendada);
      expect(resumen['esp-2']!.proximaEntrevista, DateTime.utc(2026, 10, 25, 14));
      expect(resumen['esp-2']!.ultimaVisita, isNull);
    });

    test('una venta con saldo pinta solo su depto como «Entrega y pago»', () async {
      await sembrarVenta('ven-1', vinculo: 'ep-2', monto: 480000);

      final resumen = await primero();

      expect(resumen['esp-1']!.estado, EstadoCasa.sinVisita);
      expect(resumen['esp-2']!.estado, EstadoCasa.entregaYPago);
    });

    test(
      'el edificio toma el estado más urgente de sus deptos: la misma cuenta que house_status',
      () async {
        await insertarVisita(db, visitaDe('vis-1', resultado: TipoResultadoVisita.rechazo));
        await insertarAgenda(db, agendaDe('age-1', espacio: 'esp-2', vinculo: 'ep-2'));
        final updater = HouseStatusUpdaterDrift(db, encolador: EncoladorSyncEnMemoria());

        final casa = await updater.recalcular('ub-1', ahora: t0, colportorId: 'col-1');
        final resumen = await primero();

        expect(casa!.color, ColorHouseStatus.entrevistaProgramada);
        expect(EstadoCasa.desdeColor(casa.color), resumen['esp-2']!.estado);
        expect(resumen['esp-1']!.estado, EstadoCasa.rechazo);
      },
    );

    test('la próxima entrevista es la más cercana que no pasó y la del colportor', () async {
      await insertarAgenda(db, agendaDe('pasada', fecha: DateTime.utc(2026, 10, 23, 14)));
      await insertarAgenda(db, agendaDe('lejana', fecha: DateTime.utc(2026, 10, 30, 14)));
      await insertarAgenda(db, agendaDe('cercana', fecha: DateTime.utc(2026, 10, 26, 9)));
      await insertarAgenda(
        db,
        agendaDe('cumplida', fecha: DateTime.utc(2026, 10, 24, 15), estado: EstadoAgenda.cumplida),
      );

      expect((await primero())['esp-1']!.proximaEntrevista, DateTime.utc(2026, 10, 26, 9));
      // Sin colportor no se cuenta ninguna (la de otro no es suya).
      expect((await primero(colportor: null))['esp-1']!.proximaEntrevista, isNull);
      expect((await primero(colportor: 'col-9'))['esp-1']!.proximaEntrevista, isNull);
    });

    test('la última visita es la más reciente que no está dada de baja', () async {
      final t1 = t0.add(const Duration(days: 1));
      final t2 = t0.add(const Duration(days: 2));
      await insertarVisita(db, visitaDe('vieja', creada: t0));
      await insertarVisita(db, visitaDe('nueva', creada: t1));
      await insertarVisita(db, visitaDe('borrada', creada: t2, borrada: t2));

      expect((await primero())['esp-1']!.ultimaVisita, t1);
    });

    test('un depto dado de baja no aparece', () async {
      await (db.update(
        db.espacios,
      )..where((e) => e.id.equals('esp-2'))).write(EspaciosCompanion(deletedAt: Value(t0)));

      expect((await primero()).keys, ['esp-1']);
    });
  });

  group('al día', () {
    test(
      'cuando se registra una visita o se suma un depto, vuelve a emitir; sin cambios, no',
      () async {
        final emitidos = <Map<String, ResumenDelDepto>>[];
        final llego = StreamController<void>.broadcast();
        final sub = lector.observar('ub-1', colportorId: 'col-1').listen((r) {
          emitidos.add(r);
          llego.add(null);
        });
        addTearDown(sub.cancel);
        addTearDown(llego.close);
        await llego.stream.first;

        final segunda = llego.stream.first;
        await insertarVisita(db, visitaDe('vis-1', resultado: TipoResultadoVisita.entrevista));
        await segunda;
        expect(emitidos.last['esp-1']!.estado, EstadoCasa.entrevistaHecha);

        final tercera = llego.stream.first;
        await sembrarEspacio(db, id: 'esp-3', numeroDepto: '3C');
        await tercera;
        expect(emitidos.last.keys.toSet(), {'esp-1', 'esp-2', 'esp-3'});

        // Un cambio en una tabla que mira pero que no mueve ningún resumen: no emite de nuevo.
        final cuantos = emitidos.length;
        await sembrarUbicacion(db, id: 'ub-2');
        await sembrarEspacio(db, id: 'esp-9', ubicacionId: 'ub-2');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(emitidos, hasLength(cuantos));
      },
    );
  });
}
