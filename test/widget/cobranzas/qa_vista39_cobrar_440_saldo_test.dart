// QA de «$ Cobrar» desde la casa (vista 39, C·01 + C·08, #440): lo que ve la hoja de la casa DESPUÉS
// de cobrar, con la base real. El contrato de la 39 dice que al terminar el cobro se «vuelve a la hoja
// de la casa»; la hoja muestra «Debe $ X · $ Cobrar» con el saldo que leyó el caso de uso
// `ObservarContextoDeLaCasaUseCase`, la misma lectura que la hoja real.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/persona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_del_lugar.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/lector_notas_del_lugar.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/observar_contexto_de_la_casa_use_case.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/venta_falsos.dart';

final class _EspaciosDeLaCasa implements EspacioRepository {
  @override
  Future<Either<Failure, List<Espacio>>> listar(
    String ubicacionId, {
    bool incluirBajas = false,
  }) async => Right([Espacio(id: 'esp-1', ubicacionId: ubicacionId, auditoria: auditoriaDe())]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _SinNotas implements LectorNotasDelLugar {
  @override
  Stream<NotaDelLugar?> observarMasReciente(String ubicacionId) => Stream.value(null);
}

Cobranza _cobro(String id, int monto, {String venta = 'v-1'}) => Cobranza(
  id: id,
  ventaId: venta,
  montoCentavos: monto,
  medio: MedioCobranza.efectivo,
  fecha: t0,
  auditoria: auditoriaDe(),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CobranzaLocalDataSourceDrift cobros;
  late ObservarContextoDeLaCasaUseCase caso;
  final emisiones = <ContextoDeLaCasa>[];
  StreamSubscription<ContextoDeLaCasa>? suscripcion;

  Future<void> esperar(bool Function() listo, {int ms = 1500}) async {
    final limite = DateTime.now().add(Duration(milliseconds: ms));
    while (!listo() && DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final estado = HouseStatusUpdaterDrift(db, encolador: encolador);
    cobros = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: estado);
    await sembrarCasa(db);
    await db
        .into(db.personas)
        .insert(
          PersonasCompanion.insert(id: 'per-1', nombre: 'Pedro', createdAt: t0, updatedAt: t0),
        );
    final ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: estado);
    await ventas.registrar(ventaDe('v-1', monto: 120000, talonario: '0038'), [
      itemDe('i-1', 'v-1', cantidad: 1, precio: 120000),
    ]);
    caso = ObservarContextoDeLaCasaUseCase(
      espacios: _EspaciosDeLaCasa(),
      personas: PersonaRepositoryImpl(PersonaLocalDataSourceDrift(db, encolador: encolador)),
      saldos: SaldosDePersonasLocal(cobros),
      notas: _SinNotas(),
    );
    emisiones.clear();
    suscripcion = caso(ubicacionId: 'ub-1', tipo: TipoUbicacion.casa).listen(emisiones.add);
    await esperar(() => emisiones.isNotEmpty);
  });

  tearDown(() async {
    await suscripcion?.cancel();
    await db.close();
  });

  test('la hoja de la casa arranca con la deuda de Pedro: «Debe \$ 1.200»', () {
    expect(emisiones, isNotEmpty);
    expect(emisiones.last.saldosCentavos, {'per-1': 120000});
  });

  test(
    'C·01 tras «\$ Cobrar»: cobrar \$ 500 de \$ 1.200 deja la hoja de la casa diciendo «Debe \$ 700»',
    () async {
      final antes = emisiones.length;

      final r = await cobros.registrar(_cobro('c-1', 50000));
      expect(r.venta.saldoCentavos, 70000, reason: 'la base sí quedó bien');
      await esperar(() => emisiones.length > antes);

      expect(
        emisiones.last.saldosCentavos,
        {'per-1': 70000},
        reason:
            'la hoja sigue diciendo «Debe \$ 1.200» después de cobrar \$ 500: el contexto solo '
            'se vuelve a leer cuando cambian las personas de la casa, no cuando cambia su saldo',
      );
    },
  );

  test(
    'C·01 tras pagar todo: la persona deja de aparecer como deudora (sin «\$ Cobrar»)',
    () async {
      final antes = emisiones.length;

      await cobros.registrar(_cobro('c-1', 120000));
      await esperar(() => emisiones.length > antes);

      expect(
        emisiones.last.saldosCentavos.containsKey('per-1'),
        isFalse,
        reason: 'pagó todo y la hoja sigue ofreciendo «\$ Cobrar» y «Debe \$ 1.200»',
      );
    },
  );

  group('Lo que lista C·08 con la base real', () {
    Future<void> vender(
      String id, {
      required DateTime fecha,
      String vinculo = 'ep-1',
      int monto = 10000,
    }) {
      final ventas = VentaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
      );
      return ventas.registrar(
        ventaDe(id, monto: monto, talonario: 'T-$id', fecha: fecha, vinculo: vinculo),
        [itemDe('i-$id', id, cantidad: 1, precio: monto)],
      );
    }

    test('salen de la más vieja a la más nueva y, con la misma fecha, por id', () async {
      await vender('v-b', fecha: t0.add(const Duration(days: 1)));
      await vender('v-a', fecha: t0.add(const Duration(days: 1)));
      await vender('v-c', fecha: t0.subtract(const Duration(days: 5)));

      final lista = await cobros.ventasConSaldoDe('per-1');

      expect([for (final v in lista) v.ventaId], ['v-c', 'v-1', 'v-a', 'v-b']);
    });

    test('la venta de otra persona de la misma casa no se ofrece ni se cobra a Pedro', () async {
      await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-1', personaId: 'per-2');
      await vender('v-otra', fecha: t0, vinculo: 'ep-2', monto: 99900);

      final deLaOtra = await cobros.ventasConSaldoDe('per-2');
      final dePedro = await cobros.ventasConSaldoDe('per-1');

      expect([for (final v in deLaOtra) v.ventaId], ['v-otra']);
      expect([for (final v in dePedro) v.ventaId], ['v-1']);
      expect(await cobros.saldosPorPersona(['per-1', 'per-2']), {'per-1': 120000, 'per-2': 99900});
    });

    test(
      'una venta saldada deja de aparecer y la que sigue debiendo queda sola (se salta C·08)',
      () async {
        await vender('v-2', fecha: t0.add(const Duration(days: 3)), monto: 24000);

        await cobros.registrar(_cobro('c-1', 120000));
        final lista = await cobros.ventasConSaldoDe('per-1');

        expect([for (final v in lista) v.ventaId], ['v-2']);
      },
    );
  });
}
