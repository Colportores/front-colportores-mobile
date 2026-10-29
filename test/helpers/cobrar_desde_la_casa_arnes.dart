// Arnés de los tests de «$ Cobrar» de la vista 39 (C·08 «¿Qué venta?», #440): un repositorio de cobros
// cuya lectura de ventas con saldo el test controla (compuerta, fallas, lista fija), y dos pantallas de
// arranque, una que abre solo la hoja `mostrarHojaQueVenta` y otra que abre el flujo entero
// `FlujoCobrarDesdeLaCasa.abrir` (hoja + cobro en efectivo).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/domain/repositories/cobranza_repository.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/flujo_cobrar_desde_la_casa.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/hoja_que_venta.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/hoja_con_quien_arnes.dart' show ObservadorDeRutas;
import 'agendar_visita_arnes.dart';
import 'cobro_arnes.dart';
import 'notificaciones_arnes.dart' show Telefono;
import 'persona_falsos.dart';

/// La venta 0038 del canvas de C·08: «Venta 0038 · 12/10», «Colección de 1 libro», saldo $ 1.200.
VentaConSaldo ventaDelCanvas38({int saldo = 120000}) => VentaConSaldo(
  ventaId: 'v-38',
  numeroTalonario: '0038',
  fecha: DateTime.utc(2026, 10, 12, 15),
  montoTotalCentavos: saldo,
  cobradoCentavos: 0,
  descripcion: 'Colección de 1 libro',
);

/// La venta 0045 del canvas de C·08: «Venta 0045 · 20/10», «Vida Feliz × 2», saldo $ 240.
VentaConSaldo ventaDelCanvas45({int saldo = 24000}) => VentaConSaldo(
  ventaId: 'v-45',
  numeroTalonario: '0045',
  fecha: DateTime.utc(2026, 10, 20, 15),
  montoTotalCentavos: saldo,
  cobradoCentavos: 0,
  descripcion: 'Vida Feliz × 2',
);

/// [CobranzaRepository] que delega en [base] (los cobros y el saldo reales de la memoria) y deja al test
/// mandar sobre la lectura de `ventasConSaldoDe`: la cuenta, una compuerta que la demora, las fallas
/// que devuelve o lanza, y una lista fija que pisa a la de [base].
final class CobranzasQueLeen implements CobranzaRepository {
  CobranzasQueLeen(this.base);

  final CobranzasEnMemoria base;

  /// Cuántas veces se leyeron las ventas con saldo.
  var lecturas = 0;

  /// Si no es `null`, cada lectura espera a que se complete.
  Completer<void>? compuerta;

  /// Cada lectura toma la siguiente: una [Failure] la devuelve como `Left`, otro objeto se lanza, `null`
  /// o sin más es una lectura buena.
  final fallas = <Object?>[];

  /// Si no es `null`, es lo que devuelve la lectura (en vez de lo que dice [base]).
  List<VentaConSaldo>? fija;

  @override
  Future<Either<Failure, CobroRegistrado>> registrar(Cobranza cobro) => base.registrar(cobro);

  @override
  Future<Either<Failure, VentaConSaldo?>> ventaConSaldo(String ventaId) =>
      base.ventaConSaldo(ventaId);

  @override
  Future<Either<Failure, List<VentaConSaldo>>> ventasConSaldoDe(String personaId) async {
    lecturas++;
    await compuerta?.future;
    final falla = fallas.isEmpty ? null : fallas.removeAt(0);
    if (falla is Failure) return Left(falla);
    if (falla != null) throw falla;
    final fijas = fija;
    if (fijas != null) return Right(fijas.where((v) => v.tieneSaldo).toList());
    return base.ventasConSaldoDe(personaId);
  }
}

/// Un repositorio de cobros con las ventas dadas, sin nada cobrado antes.
CobranzasQueLeen cobranzasConVentas(List<VentaConSaldo> ventas) =>
    CobranzasQueLeen(CobranzasEnMemoria(ventas: ventas, cobradoAntes: 0));

// ---------------------------------------------------------------------------------------------------
// La hoja sola
// ---------------------------------------------------------------------------------------------------

/// Lo que la pantalla de arranque recibió de la hoja.
final class ResultadoQueVenta {
  VentaConSaldo? elegida;

  /// Cuántas veces terminó la hoja (con o sin venta).
  var cierres = 0;

  final rutas = ObservadorDeRutas();

  /// Las rutas abiertas encima de la pantalla de arranque.
  int get abiertas => rutas.aperturas - 1 - rutas.cierres;
}

/// Monta una pantalla con un botón «abrir venta» que abre `mostrarHojaQueVenta` y, si [abrir], lo toca.
Future<ResultadoQueVenta> montarQueVenta(
  WidgetTester tester, {
  required CobranzaRepository repo,
  String? nombre = 'Pedro',
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool lector = false,
  bool abrir = true,
}) async {
  final resultado = ResultadoQueVenta();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [cobranzaRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: temaClaro(),
        navigatorObservers: [resultado.rutas],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala), accessibleNavigation: lector),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final v = await mostrarHojaQueVenta(context, personaId: 'p1', nombre: nombre);
                  resultado
                    ..elegida = v
                    ..cierres += 1;
                },
                child: const Text('abrir venta'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirQueVenta(tester);
  return resultado;
}

/// Toca el botón de arranque y deja correr la apertura de la hoja.
Future<void> abrirQueVenta(WidgetTester tester) async {
  await tester.tap(find.text('abrir venta'));
  await asentarAgendar(tester);
}

Finder get filaDeVenta => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('que_venta_fila_'),
);

Future<void> tocarQueVenta(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await asentarAgendar(tester);
}

// ---------------------------------------------------------------------------------------------------
// El flujo entero
// ---------------------------------------------------------------------------------------------------

final class ArnesCobrarDesdeLaCasa {
  ArnesCobrarDesdeLaCasa({required this.repo, required this.telefono, required this.rutas});

  final CobranzasQueLeen repo;
  final Telefono telefono;
  final ObservadorDeRutas rutas;

  /// Los ids de cobro que se generaron, en orden.
  final idsGenerados = <String>[];

  /// Cada vez que el flujo terminó: lo que devolvió.
  final resultados = <bool>[];

  /// Lo que lanzó el flujo, si lanzó.
  final lanzados = <Object>[];
}

/// Monta una pantalla con el botón «cobrar» que abre `FlujoCobrarDesdeLaCasa.abrir` y, si [abrir], lo
/// toca. [personas] es quien vive en la casa (por defecto Pedro Gómez, `p1`).
Future<ArnesCobrarDesdeLaCasa> montarCobrarDesdeLaCasa(
  WidgetTester tester, {
  required CobranzasQueLeen repo,
  List<PersonaDelEspacio>? personas,
  String? espacioId = 'esp-1',
  String? colportorId = 'col-1',
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final arnes = ArnesCobrarDesdeLaCasa(
    repo: repo,
    telefono: Telefono(),
    rutas: ObservadorDeRutas(),
  );
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final personasRepo = PersonaRepositorioFalso()
    ..sembrar(personas ?? [clienteDePersonas('p1', 'Pedro', apellido: 'Gómez')]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cobranzaRepositoryProvider.overrideWithValue(repo),
        generadorIdCobroProvider.overrideWithValue(() {
          final id = 'cobro-${arnes.idsGenerados.length + 1}';
          arnes.idsGenerados.add(id);
          return id;
        }),
        relojCobroProvider.overrideWithValue(() => hoyDelCobro),
        agendaRepositoryProvider.overrideWithValue(AgendaRepositorioQueAgenda()),
        ...arnes.telefono.overrides,
        personaRepositoryProvider.overrideWithValue(personasRepo),
        espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(casaMataojo())),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        navigatorObservers: [arnes.rutas],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  try {
                    final ContextoDeCobro datos = (
                      ubicacionId: 'ub-1',
                      espacioId: espacioId,
                      personaId: 'p1',
                    );
                    arnes.resultados.add(
                      await FlujoCobrarDesdeLaCasa.abrir(context, datos, colportorId: colportorId),
                    );
                  } on Object catch (e) {
                    arnes.lanzados.add(e);
                  }
                },
                child: const Text('cobrar'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirCobrarDesdeLaCasa(tester);
  return arnes;
}

/// Toca el botón de arranque y deja correr la apertura.
Future<void> abrirCobrarDesdeLaCasa(WidgetTester tester) async {
  await tester.tap(find.text('cobrar'));
  await asentarAgendar(tester);
}
