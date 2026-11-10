// QA de «la cuota que toca» de punta a punta (HU-COB-005, #591, PR #634): el caso de uso REAL de la hoja de la
// casa (`ObservarContextoDeLaCasaUseCase`) sobre las tablas reales (AppDatabase en memoria) con los adaptadores
// de producción (`SaldosDePersonasLocal`, `CuotasDePersonasLocal`, `alCambiarLoQueSeDebe`): un cobro, una
// devolución o un plan nuevo se ven en el contexto de la casa sin recargar.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cuotas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/pedido_de_plan.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_del_lugar.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/lector_notas_del_lugar.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/observar_contexto_de_la_casa_use_case.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/devolucion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/persona_falsos.dart';
import '../../../../helpers/venta_falsos.dart';

final class _Espacios implements EspacioRepository {
  _Espacios(this.espacio);
  final Espacio espacio;

  @override
  Future<Either<Failure, List<Espacio>>> listar(
    String ubicacionId, {
    bool incluirBajas = false,
  }) async => Right([espacio]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Personas implements PersonaRepository {
  _Personas(this.lista);
  final List<PersonaDelEspacio> lista;

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) => Stream.value(lista);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Notas implements LectorNotasDelLugar {
  @override
  Stream<NotaDelLugar?> observarMasReciente(String ubicacionId) => Stream.value(null);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CuotasLocalDataSourceDrift cuotas;
  late CobranzaLocalDataSourceDrift cobros;
  late VentaLocalDataSourceDrift ventas;
  late DevolucionLocalDataSourceDrift devoluciones;
  late List<ContextoDeLaCasa> emitidos;

  final armado = DateTime.utc(2026, 10, 10, 14);
  final pedro = clienteDePersonas('per-1', 'Pedro', apellido: 'Gómez');

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    cuotas = CuotasLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    cobros = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    devoluciones = DevolucionLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: casas,
    );
    emitidos = [];
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  /// La venta del canvas de devoluciones: dos renglones, $ 4.500, con plan de dos cuotas de $ 2.250.
  Future<void> venderConPlan({String id = 'v-1'}) async {
    await ventas.registrar(ventaDe(id, monto: 450000, fecha: DateTime.utc(2026, 10, 9, 12)), [
      itemDe('i-salud-$id', id, productoId: 'p-salud', cantidad: 1, precio: 260000),
      itemDe('i-hijos-$id', id, productoId: 'p-hijos', cantidad: 1, precio: 190000),
    ]);
    await cuotas.crearPlan(
      NuevoPlanDeCuotas(
        ventaId: id,
        colportorId: 'col-1',
        ahora: armado,
        cuotas: [
          NuevaCuota(agendaId: '$id-q1', fecha: DateTime(2026, 10, 26, 10), montoCentavos: 225000),
          NuevaCuota(agendaId: '$id-q2', fecha: DateTime(2026, 10, 28, 10), montoCentavos: 225000),
        ],
      ),
    );
  }

  Cobranza cobro(String id, int monto, {String venta = 'v-1'}) => Cobranza(
    id: id,
    ventaId: venta,
    montoCentavos: monto,
    medio: MedioCobranza.efectivo,
    fecha: DateTime.utc(2026, 10, 11, 12),
    auditoria: Auditoria(
      createdAt: DateTime.utc(2026, 10, 11, 12),
      updatedAt: DateTime.utc(2026, 10, 11, 12),
      createdBy: 'col-1',
    ),
  );

  Future<StreamSubscription<ContextoDeLaCasa>> abrir() async {
    final caso = ObservarContextoDeLaCasaUseCase(
      espacios: _Espacios(espacioDePersonas(numeroDepto: null)),
      personas: _Personas([pedro]),
      saldos: SaldosDePersonasLocal(cobros),
      notas: _Notas(),
      cuotas: CuotasDePersonasLocal(cobros),
      cambios: cobros.alCambiarLoQueSeDebe,
    );
    final suscripcion = caso(
      ubicacionId: 'ub-1',
      tipo: TipoUbicacion.casa,
    ).listen(emitidos.add, onError: (Object _) {});
    addTearDown(suscripcion.cancel);
    await _esperarA(() => emitidos.isNotEmpty);
    return suscripcion;
  }

  group('la hoja de la casa con la base real', () {
    test('abre con «Debe» y la cuota; un cobro que cubre la cuota 1 pasa a la cuota 2', () async {
      await venderConPlan();
      await abrir();
      expect(emitidos.last.saldoDe('per-1'), 450000);
      expect(emitidos.last.cuotaQueTocaDe('per-1'), DateTime(2026, 10, 26, 10));

      await cobros.registrar(cobro('c-1', 225000));
      await _esperarA(() => emitidos.last.saldoDe('per-1') == 225000);

      expect(emitidos.last.cuotaQueTocaDe('per-1'), DateTime(2026, 10, 28, 10));
    });

    test('el último cobro: la persona deja de deber y la cuota se va con el saldo', () async {
      await venderConPlan();
      await abrir();

      await cobros.registrar(cobro('c-1', 450000));
      await _esperarA(() => emitidos.last.saldoDe('per-1') == null);

      expect(emitidos.last.cuotaQueTocaDe('per-1'), isNull);
      expect(emitidos.last.proximaCuotaDe, isEmpty);
    });

    test(
      'una devolución total de la venta: sin saldo, sin cuota (la cita pendiente no cuenta)',
      () async {
        await venderConPlan();
        await abrir();

        final r = await devoluciones.registrar(
          PedidoDeDevolucion(
            id: 'd-1',
            ventaId: 'v-1',
            colportorId: 'col-1',
            unidadesPorRenglon: const {'i-salud-v-1': 1, 'i-hijos-v-1': 1},
            motivo: 'no le interesó',
            ahora: DateTime.utc(2026, 10, 10, 15),
          ),
        );
        expect(r, isNotNull);
        await _esperarA(() => emitidos.last.saldoDe('per-1') == null);

        expect(emitidos.last.cuotaQueTocaDe('per-1'), isNull);
        expect(
          emitidos.last.proximaCuotaDe,
          isEmpty,
          reason: 'la cuota de una venta devuelta se muestra',
        );
      },
    );

    test('una devolución parcial: sigue debiendo lo que queda y la cuota sigue', () async {
      await venderConPlan();
      await abrir();

      await devoluciones.registrar(
        PedidoDeDevolucion(
          id: 'd-1',
          ventaId: 'v-1',
          colportorId: 'col-1',
          unidadesPorRenglon: const {'i-hijos-v-1': 1},
          motivo: 'uno solo',
          ahora: DateTime.utc(2026, 10, 10, 15),
        ),
      );
      await _esperarA(() => emitidos.last.saldoDe('per-1') == 260000);

      expect(emitidos.last.cuotaQueTocaDe('per-1'), DateTime(2026, 10, 26, 10));
    });

    test('armar un plan después de abrir la hoja hace aparecer la cuota sin recargar', () async {
      await ventas.registrar(ventaDe('v-1', monto: 450000, fecha: DateTime.utc(2026, 10, 9, 12)), [
        itemDe('i-1', 'v-1', productoId: 'p-salud', cantidad: 1, precio: 450000),
      ]);
      await abrir();
      expect(emitidos.last.saldoDe('per-1'), 450000);
      expect(emitidos.last.cuotaQueTocaDe('per-1'), isNull);

      await cuotas.crearPlan(
        NuevoPlanDeCuotas(
          ventaId: 'v-1',
          colportorId: 'col-1',
          ahora: armado,
          cuotas: [
            NuevaCuota(agendaId: 'q1', fecha: DateTime(2026, 10, 30, 10), montoCentavos: 225000),
            NuevaCuota(agendaId: 'q2', fecha: DateTime(2026, 11, 5, 10), montoCentavos: 225000),
          ],
        ),
      );
      await _esperarA(() => emitidos.last.cuotaQueTocaDe('per-1') != null);

      expect(emitidos.last.cuotaQueTocaDe('per-1'), DateTime(2026, 10, 30, 10));
    });

    test('dos ventas con plan: la cuota que toca es la más temprana de las dos', () async {
      await venderConPlan();
      await ventas.registrar(
        ventaDe('v-2', monto: 100000, talonario: 'T-2', fecha: DateTime.utc(2026, 10, 9, 12)),
        [itemDe('i-2', 'v-2', productoId: 'p-salud', cantidad: 1, precio: 100000)],
      );
      await cuotas.crearPlan(
        NuevoPlanDeCuotas(
          ventaId: 'v-2',
          colportorId: 'col-1',
          ahora: armado,
          cuotas: [
            NuevaCuota(agendaId: 'w1', fecha: DateTime(2026, 10, 20, 10), montoCentavos: 50000),
            NuevaCuota(agendaId: 'w2', fecha: DateTime(2026, 11, 20, 10), montoCentavos: 50000),
          ],
        ),
      );
      await abrir();

      expect(emitidos.last.saldoDe('per-1'), 550000);
      expect(emitidos.last.cuotaQueTocaDe('per-1'), DateTime(2026, 10, 20, 10));

      await cobros.registrar(cobro('c-9', 100000, venta: 'v-2'));
      await _esperarA(() => emitidos.last.saldoDe('per-1') == 450000);
      expect(emitidos.last.cuotaQueTocaDe('per-1'), DateTime(2026, 10, 26, 10));
    });

    test('una cuota a las 23:30 locales no corre de día (el huso del teléfono manda)', () async {
      await ventas.registrar(ventaDe('v-1', monto: 100000, fecha: DateTime.utc(2026, 10, 9, 12)), [
        itemDe('i-1', 'v-1', productoId: 'p-salud', cantidad: 1, precio: 100000),
      ]);
      final tarde = DateTime(2026, 10, 26, 23, 30);
      await cuotas.crearPlan(
        NuevoPlanDeCuotas(
          ventaId: 'v-1',
          colportorId: 'col-1',
          ahora: armado,
          cuotas: [
            NuevaCuota(agendaId: 'q1', fecha: tarde, montoCentavos: 50000),
            NuevaCuota(
              agendaId: 'q2',
              fecha: tarde.add(const Duration(days: 7)),
              montoCentavos: 50000,
            ),
          ],
        ),
      );
      await abrir();

      final dia = emitidos.last.cuotaQueTocaDe('per-1')!.toLocal();
      expect((dia.year, dia.month, dia.day), (2026, 10, 26));
    });
  });
}

/// Espera, sin reloj falso, a que [condicion] valga (la base avisa por un `Stream`).
Future<void> _esperarA(bool Function() condicion) async {
  for (var i = 0; i < 200; i++) {
    if (condicion()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('la condición no se cumplió a tiempo');
}
