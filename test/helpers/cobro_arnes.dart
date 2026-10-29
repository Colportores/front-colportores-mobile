// Arnés de los tests de «Cobro en efectivo» (vista 28, HU-COB-001, #439): un repositorio de cobros en
// memoria que respeta las reglas del real (idempotente por id, tope del saldo), con compuertas y
// fallas que el test dispara, y la pantalla montada con un botón que abre `CobroEfectivoPage.abrir`.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/domain/repositories/cobranza_repository.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/pages/cobro_efectivo_page.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart';
import 'notificaciones_arnes.dart' show Telefono;
import 'persona_falsos.dart';

/// El hoy del canvas: viernes 23/10/2026, mediodía en Montevideo.
final hoyDelCobro = DateTime.utc(2026, 10, 23, 15);

/// La venta del canvas de la vista 28: «Venta 0042 · 12/10» por $ 4.500, con $ 3.300 pagados (saldo
/// $ 1.200).
VentaConSaldo ventaDelCobro({
  String id = 'v-42',
  String talonario = '0042',
  int total = 450000,
  DateTime? fecha,
}) => VentaConSaldo(
  ventaId: id,
  numeroTalonario: talonario,
  fecha: fecha ?? DateTime.utc(2026, 10, 12, 15),
  montoTotalCentavos: total,
  cobradoCentavos: 0,
  descripcion: 'Colección de 1 libro',
);

Cobranza cobroDeEjemplo(String id, int monto, {String venta = 'v-42'}) => Cobranza(
  id: id,
  ventaId: venta,
  montoCentavos: monto,
  medio: MedioCobranza.efectivo,
  fecha: DateTime.utc(2026, 10, 14, 15),
  auditoria: Auditoria(
    createdAt: DateTime.utc(2026, 10, 14, 15),
    updatedAt: DateTime.utc(2026, 10, 14, 15),
    createdBy: 'col-1',
  ),
);

/// [CobranzaRepository] en memoria con las reglas del real: idempotente por `id`, rechaza un monto
/// mayor al saldo y una venta que no está. Cada [registrar] toma la siguiente de [fallas]; si hay
/// [compuerta], espera a que se complete (un guardado «en curso»).
final class CobranzasEnMemoria implements CobranzaRepository {
  CobranzasEnMemoria({List<VentaConSaldo>? ventas, int cobradoAntes = 330000}) {
    for (final v in ventas ?? [ventaDelCobro()]) {
      this.ventas[v.ventaId] = v;
      if (cobradoAntes > 0) {
        final id = 'previo-${v.ventaId}';
        cobros[id] = cobroDeEjemplo(id, cobradoAntes, venta: v.ventaId);
      }
    }
  }

  final ventas = <String, VentaConSaldo>{};

  /// Los cobros guardados, por id (incluidos los que ya tenía la venta).
  final cobros = <String, Cobranza>{};

  /// Cada cobro que le llegó a [registrar], también los que fallaron.
  final recibidos = <Cobranza>[];

  /// Cada [registrar] toma el siguiente (`null` o sin más: éxito).
  final fallas = <Failure?>[];

  /// Si no es `null`, [registrar] espera a que se complete.
  Completer<void>? compuerta;

  /// Si no es `null`, el próximo [registrar] lanza esto en vez de devolver un `Either`.
  Object? lanzar;

  /// Si no es `null`, [ventaConSaldo] responde con esta falla (una sola vez si [fallaDeLecturaUnaVez]).
  Failure? fallaDeLectura;
  var fallaDeLecturaUnaVez = false;

  /// Si no es `null`, [ventaConSaldo] espera a que se complete.
  Completer<void>? compuertaDeLectura;

  var lecturas = 0;

  VentaConSaldo _con(VentaConSaldo v) {
    final cobrado = cobros.values
        .where((c) => c.ventaId == v.ventaId)
        .fold<int>(0, (a, c) => a + c.montoCentavos);
    return VentaConSaldo(
      ventaId: v.ventaId,
      numeroTalonario: v.numeroTalonario,
      fecha: v.fecha,
      montoTotalCentavos: v.montoTotalCentavos,
      cobradoCentavos: cobrado,
      descripcion: v.descripcion,
    );
  }

  @override
  Future<Either<Failure, CobroRegistrado>> registrar(Cobranza cobro) async {
    recibidos.add(cobro);
    await compuerta?.future;
    final error = lanzar;
    if (error != null) {
      lanzar = null;
      throw error;
    }
    final falla = fallas.isEmpty ? null : fallas.removeAt(0);
    if (falla != null) return Left(falla);
    final venta = ventas[cobro.ventaId];
    if (venta == null) return const Left(FailureCobroSinVenta());
    final previo = cobros[cobro.id];
    if (previo != null) {
      return Right(CobroRegistrado(cobranza: previo, venta: _con(venta), yaEstaba: true));
    }
    final saldo = _con(venta).saldoCentavos;
    if (cobro.montoCentavos > saldo) return Left(FailureCobroMayorAlSaldo(saldoCentavos: saldo));
    cobros[cobro.id] = cobro;
    return Right(CobroRegistrado(cobranza: cobro, venta: _con(venta)));
  }

  @override
  Future<Either<Failure, VentaConSaldo?>> ventaConSaldo(String ventaId) async {
    lecturas++;
    await compuertaDeLectura?.future;
    final falla = fallaDeLectura;
    if (falla != null) {
      if (fallaDeLecturaUnaVez) fallaDeLectura = null;
      return Left(falla);
    }
    final venta = ventas[ventaId];
    return Right(venta == null ? null : _con(venta));
  }

  @override
  Future<Either<Failure, List<VentaConSaldo>>> ventasConSaldoDe(String personaId) async =>
      Right([for (final v in ventas.values) _con(v)].where((v) => v.tieneSaldo).toList());
}

class ArnesCobro {
  ArnesCobro({
    required this.repo,
    required this.agendas,
    required this.telefono,
    required this.ahora,
  });

  final CobranzasEnMemoria repo;
  final AgendaRepositorioQueAgenda agendas;
  final Telefono telefono;

  /// El reloj de la pantalla; se mueve cambiando este campo.
  DateTime ahora;

  /// Los ids de cobro que se generaron, en orden.
  final idsGenerados = <String>[];

  /// Cada vez que `CobroEfectivoPage.abrir` terminó: lo que devolvió.
  final resultados = <bool>[];
}

/// Monta una pantalla con el botón «abrir cobro» y, si [abrir], lo toca.
Future<ArnesCobro> montarCobro(
  WidgetTester tester, {
  CobranzasEnMemoria? repo,
  String ventaId = 'v-42',
  String? espacioPersonaId = 'ep-p1',
  List<PersonaDelEspacio>? personas,
  EspacioConUbicacion? casa,
  bool sinCasa = false,
  DateTime? ahora,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final arnes = ArnesCobro(
    repo: repo ?? CobranzasEnMemoria(),
    agendas: AgendaRepositorioQueAgenda(),
    telefono: Telefono(),
    ahora: ahora ?? hoyDelCobro,
  );
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final personasRepo = PersonaRepositorioFalso()..sembrar(personas ?? [mariaFernandez]);
  final lugar = sinCasa ? null : (casa ?? casaMataojo());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cobranzaRepositoryProvider.overrideWithValue(arnes.repo),
        generadorIdCobroProvider.overrideWithValue(() {
          final id = 'cobro-${arnes.idsGenerados.length + 1}';
          arnes.idsGenerados.add(id);
          return id;
        }),
        relojCobroProvider.overrideWithValue(() => arnes.ahora),
        agendaRepositoryProvider.overrideWithValue(arnes.agendas),
        ...arnes.telefono.overrides,
        personaRepositoryProvider.overrideWithValue(personasRepo),
        espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(lugar)),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final r = await CobroEfectivoPage.abrir(
                    context,
                    ventaId: ventaId,
                    colportorId: 'col-1',
                    espacioId: 'esp-1',
                    espacioPersonaId: espacioPersonaId,
                  );
                  arnes.resultados.add(r);
                },
                child: const Text('abrir cobro'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirCobro(tester);
  return arnes;
}

/// Toca el botón de arranque y deja correr la apertura de la pantalla.
Future<void> abrirCobro(WidgetTester tester) async {
  await tester.tap(find.text('abrir cobro'));
  await asentarAgendar(tester);
}

final pagina = find.byKey(const Key('cobro_pagina'));
final campoMonto = find.descendant(
  of: find.byKey(const Key('cobro_monto')),
  matching: find.byType(TextField),
);
final botonRegistrar = find.byKey(const Key('venta_cta'));
final campoFecha = find.byKey(const Key('cobro_fecha'));
final cerrarCobro = find.byKey(const Key('venta_atras'));

/// El botón principal de abajo, como `FilledButton`.
FilledButton elBoton(WidgetTester tester) => tester.widget<FilledButton>(botonRegistrar);

/// Trae [f] a la vista: la lista es perezosa y con letra grande el widget puede no estar armado.
Future<void> traerAlAlcance(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    final lista = find.descendant(of: pagina, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(f, 100, scrollable: lista.first);
  }
  await tester.ensureVisible(f.first);
  await tester.pump();
}

Future<void> escribirMonto(WidgetTester tester, String texto) async {
  await traerAlAlcance(tester, campoMonto);
  await tester.enterText(campoMonto, texto);
  await asentarAgendar(tester, 3);
}

Future<void> tocarCobro(WidgetTester tester, Finder f) async {
  await traerAlAlcance(tester, f);
  await tester.tap(f.first);
  await asentarAgendar(tester);
}
