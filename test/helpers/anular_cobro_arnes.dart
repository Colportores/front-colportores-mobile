// Arnés de los tests de «Detalle del cobro» y «Anular cobro» (vista 30 B, HU-COB-006, #424): un
// repositorio de anulaciones en memoria que respeta las reglas del real (idempotente, ventana de 72 h,
// saldo que vuelve), con compuertas y fallas que el test dispara, y la pantalla montada con un botón que
// abre `DetalleDelCobroPage.abrir`.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/detalle_del_cobro.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/domain/repositories/anulacion_de_cobro_repository.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/pages/detalle_del_cobro_page.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart' show asentarAgendar;

/// El «ahora» del canvas: viernes 23/10/2026, 15:00 en Montevideo (18:00 UTC).
final ahoraDeLaAnulacion = DateTime.utc(2026, 10, 23, 18);

/// El cobro del canvas: $ 600 en efectivo, «Hoy 14:10» (17:10 UTC) de la venta 0042 de María Fernández,
/// que va por $ 4.500 con $ 3.900 pagados contando este cobro (saldo $ 600; sin él, $ 1.200).
DetalleDelCobro detalleDeEjemplo({
  String id = 'c-1',
  int monto = 60000,
  DateTime? fecha,
  MedioCobranza medio = MedioCobranza.efectivo,
  int cobrado = 390000,
  String? cliente = 'María Fernández',
  DateTime? anuladoAt,
  MotivoDeAnulacion? motivo,
}) {
  final f = fecha ?? DateTime.utc(2026, 10, 23, 17, 10);
  return DetalleDelCobro(
    cobranza: Cobranza(
      id: id,
      ventaId: 'v-42',
      montoCentavos: monto,
      medio: medio,
      fecha: f,
      anuladoAt: anuladoAt,
      motivoAnulacion: motivo,
      auditoria: Auditoria(createdAt: f, updatedAt: f, createdBy: 'col-1'),
    ),
    venta: VentaConSaldo(
      ventaId: 'v-42',
      numeroTalonario: '0042',
      fecha: DateTime.utc(2026, 10, 12, 15),
      montoTotalCentavos: 450000,
      cobradoCentavos: cobrado,
    ),
    cliente: cliente,
  );
}

/// [AnulacionDeCobroRepository] en memoria con las reglas del real. Cada [anular] toma la siguiente de
/// [fallas]; si hay [compuerta], espera a que se complete (una anulación «en curso»).
final class AnulacionesEnMemoria implements AnulacionDeCobroRepository {
  AnulacionesEnMemoria({List<DetalleDelCobro>? cobros}) {
    for (final d in cobros ?? [detalleDeEjemplo()]) {
      detalles[d.cobranza.id] = d;
    }
  }

  final detalles = <String, DetalleDelCobro>{};

  /// Cada pedido que le llegó a [anular], también los que fallaron.
  final recibidos =
      <({String id, MotivoDeAnulacion motivo, String? justificacion, DateTime ahora})>[];

  /// Cada [anular] toma la siguiente (`null` o sin más: éxito).
  final fallas = <Failure?>[];

  /// Si no es `null`, [anular] espera a que se complete.
  Completer<void>? compuerta;

  /// Si no es `null`, el próximo [anular] lanza esto en vez de devolver un `Either`.
  Object? lanzar;

  /// Si no es `null`, [detalle] responde con esta falla (una sola vez si [fallaDeLecturaUnaVez]).
  Failure? fallaDeLectura;
  var fallaDeLecturaUnaVez = false;

  /// Si no es `null`, [detalle] espera a que se complete.
  Completer<void>? compuertaDeLectura;

  var lecturas = 0;

  @override
  Future<Either<Failure, DetalleDelCobro?>> detalle(String cobranzaId) async {
    lecturas++;
    await compuertaDeLectura?.future;
    final falla = fallaDeLectura;
    if (falla != null) {
      if (fallaDeLecturaUnaVez) fallaDeLectura = null;
      return Left(falla);
    }
    return Right(detalles[cobranzaId]);
  }

  @override
  Future<Either<Failure, AnulacionHecha>> anular({
    required String cobranzaId,
    required MotivoDeAnulacion motivo,
    required String colportorId,
    required DateTime ahora,
    String? justificacion,
  }) async {
    recibidos.add((id: cobranzaId, motivo: motivo, justificacion: justificacion, ahora: ahora));
    await compuerta?.future;
    final error = lanzar;
    if (error != null) {
      lanzar = null;
      throw error;
    }
    final falla = fallas.isEmpty ? null : fallas.removeAt(0);
    if (falla != null) return Left(falla);
    final actual = detalles[cobranzaId];
    if (actual == null) return const Left(FailureCobroAusente());
    if (actual.cobranza.estaAnulado) return Right(AnulacionHecha(detalle: actual, yaEstaba: true));
    if (!actual.dentroDelPlazo(ahora)) return const Left(FailureAnulacionFueraDePlazo());
    final c = actual.cobranza;
    final nuevo = DetalleDelCobro(
      cobranza: Cobranza(
        id: c.id,
        ventaId: c.ventaId,
        montoCentavos: c.montoCentavos,
        medio: c.medio,
        fecha: c.fecha,
        anuladoAt: ahora,
        motivoAnulacion: motivo,
        auditoria: c.auditoria,
      ),
      venta: VentaConSaldo(
        ventaId: actual.venta.ventaId,
        numeroTalonario: actual.venta.numeroTalonario,
        fecha: actual.venta.fecha,
        montoTotalCentavos: actual.venta.montoTotalCentavos,
        cobradoCentavos: actual.venta.cobradoCentavos - c.montoCentavos,
      ),
      cliente: actual.cliente,
    );
    detalles[cobranzaId] = nuevo;
    return Right(AnulacionHecha(detalle: nuevo));
  }
}

class ArnesAnular {
  ArnesAnular({required this.repo, required this.ahora});

  final AnulacionesEnMemoria repo;

  /// El reloj de la pantalla; se mueve cambiando este campo.
  DateTime ahora;

  /// Cada vez que `DetalleDelCobroPage.abrir` terminó: lo que devolvió.
  final resultados = <bool>[];
}

/// Monta una pantalla con el botón «abrir cobro» y, si [abrir], lo toca.
Future<ArnesAnular> montarDetalleDelCobro(
  WidgetTester tester, {
  AnulacionesEnMemoria? repo,
  String cobranzaId = 'c-1',
  DateTime? ahora,
  bool ticketValidado = false,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final arnes = ArnesAnular(
    repo: repo ?? AnulacionesEnMemoria(),
    ahora: ahora ?? ahoraDeLaAnulacion,
  );
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        anulacionDeCobroRepositoryProvider.overrideWithValue(arnes.repo),
        relojCobroProvider.overrideWithValue(() => arnes.ahora),
        ticketValidadoDelCobroProvider.overrideWith((ref, id) async => ticketValidado),
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
                  final r = await DetalleDelCobroPage.abrir(
                    context,
                    cobranzaId: cobranzaId,
                    colportorId: 'col-1',
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
  if (abrir) await abrirDetalle(tester);
  return arnes;
}

/// Toca el botón de arranque y deja correr la apertura de la pantalla.
Future<void> abrirDetalle(WidgetTester tester) async {
  await tester.tap(find.text('abrir cobro'));
  await asentarAgendar(tester);
}

final paginaDetalle = find.byKey(const Key('detalle_cobro_pagina'));
final paginaAnular = find.byKey(const Key('anular_cobro_pagina'));
final botonAnularDelDetalle = find.byKey(const Key('detalle_cobro_anular'));
final botonPrincipal = find.byKey(const Key('venta_cta'));
final campoOtro = find.descendant(
  of: find.byKey(const Key('anular_cobro_otro')),
  matching: find.byType(TextField),
);
final siAnular = find.byKey(const Key('anular_cobro_si'));
final noVolver = find.byKey(const Key('anular_cobro_no'));

Finder motivo(MotivoDeAnulacion m) => find.byKey(Key('anular_cobro_motivo_${m.name}'));

/// El texto del `Text` con la [clave].
String textoDe(String clave) => (find.byKey(Key(clave)).evaluate().single.widget as Text).data!;

/// Trae [f] a la vista: la lista es perezosa y con letra grande el widget puede no estar armado.
Future<void> traerAlAlcance(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    final listas = find.byType(Scrollable);
    await tester.scrollUntilVisible(f, 100, scrollable: listas.first);
  }
  await tester.ensureVisible(f.first);
  await tester.pump();
}

Future<void> tocar(WidgetTester tester, Finder f) async {
  await traerAlAlcance(tester, f);
  await tester.tap(f.first);
  await asentarAgendar(tester);
}

/// Detalle → «Anular cobro» → elegido el [m] (y el [texto] si es «Otro»).
Future<void> irAAnular(WidgetTester tester, {MotivoDeAnulacion? m, String? texto}) async {
  await tocar(tester, botonAnularDelDetalle);
  if (m != null) await tocar(tester, motivo(m));
  if (texto != null) {
    await traerAlAlcance(tester, campoOtro);
    await tester.enterText(campoOtro, texto);
    await asentarAgendar(tester, 3);
  }
}

FilledButton elBoton(WidgetTester tester) => tester.widget<FilledButton>(botonPrincipal);
