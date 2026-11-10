// QA de «Ver la venta» del Historial de la casa (vista 39, C·04 → vista 30 A, #446, PR #677, tras el fix
// de la decisión del 10/11): el enganche abre LA venta tocada (con SUS datos, no solo con su id), cada
// estado de las cuotas tiene salida (cargando, venta que no está, error de lectura, sin saldo), «atrás»
// (el botón y el del sistema) devuelve al historial como estaba, y el detalle cerrado sin tocar «Ver la
// venta» no abre nada. Todo con el enganche real de `main.dart`, sin conexión.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart'
    show TipoResultadoVisita;
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cuota.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/pedido_de_plan.dart';
import 'package:colportores_mobile/features/cobranzas/domain/repositories/plan_de_cuotas_repository.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/textos_cuotas.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/piezas_cuotas.dart'
    show EsqueletoDeCuotas, MarcaDeSinSaldo;
import 'package:colportores_mobile/features/mapa/domain/entities/evento_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart'
    show LineaDeFicha;
import 'package:colportores_mobile/features/mapa/domain/services/historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_ver_venta_desde_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/historial_de_la_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_detalle_de_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_historial_de_la_casa.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuotas_arnes.dart' show hoyDeLasCuotas, paginaLista, volverDeCuotas;
import '../../helpers/persona_falsos.dart';
import '../../helpers/plan_de_cuotas_arnes.dart';

final _ahora = DateTime(2026, 10, 25, 16);

DateTime _local(int mes, int dia, [int hora = 12]) => DateTime(2026, mes, dia, hora).toUtc();

VentaDeLaCasa _venta(
  String id,
  String talonario,
  int monto,
  int pagado, {
  int dia = 12,
  String? vinculo = 'ep-1',
  String nombre = 'Pedro',
}) => VentaDeLaCasa(
  id: id,
  fecha: _local(10, dia, 14),
  numeroTalonario: talonario,
  montoCentavos: monto,
  pagadoCentavos: pagado,
  lineas: const [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)],
  persona: PersonaDelEvento(nombre: nombre),
  espacioPersonaId: vinculo,
);

/// Una casa con cuatro ventas de distinto estado y una visita.
final _eventos = <EventoDeLaCasa>[
  _venta('ven-ana', '0041', 200000, 50000, dia: 20, vinculo: 'ep-ana', nombre: 'Ana'),
  _venta('ven-pedro', '0038', 480000, 360000),
  _venta('ven-pagada', '0030', 100000, 100000, dia: 8),
  _venta('ven-suelta', '0029', 90000, 0, dia: 6, vinculo: null, nombre: 'Luis'),
  VisitaDeLaCasa(id: 'vis-1', fecha: _local(10, 3, 15), resultado: TipoResultadoVisita.noContesto),
];

final class _Historial implements HistorialDeLaCasa {
  @override
  Stream<List<EventoDeLaCasa>> observar(String espacioId) => Stream.value(_eventos);
}

/// Un plan distinto por venta: lo que se ve en cuotas dice de QUÉ venta es.
final class _PlanesPorVenta implements PlanDeCuotasRepository {
  _PlanesPorVenta(this.planes);

  final Map<String, PlanDeCuotasEnMemoria> planes;
  final consultadas = <String>[];

  @override
  Stream<PlanDeCuotas?> observar(String ventaId) {
    consultadas.add(ventaId);
    final plan = planes[ventaId];
    return plan == null ? Stream.value(null) : plan.observar(ventaId);
  }

  @override
  Future<Either<Failure, PlanDeCuotas?>> leer(String ventaId) async =>
      planes[ventaId]?.leer(ventaId) ?? const Right(null);

  @override
  Future<Either<Failure, PlanDeCuotas>> crear(NuevoPlanDeCuotas plan) => throw UnimplementedError();

  @override
  Future<Either<Failure, PlanDeCuotas>> modificar(ModificacionDeCuotas cambios) =>
      throw UnimplementedError();
}

class _SesionFija extends SesionNotifier {
  @override
  Future<Sesion?> build() async => Sesion(
    usuarioId: 'col-1',
    email: 'ana@example.com',
    accessToken: 'jwt',
    expiraEn: DateTime.utc(2030),
  );
}

void main() {
  late _PlanesPorVenta planes;

  Future<void> asentar(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> salir(WidgetTester tester) async {
    // La ruta se anima al salir: fotogramas de a poco, como en las pruebas de cuotas (#580).
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> montar(
    WidgetTester tester, {
    double escala = 1,
    Size tamano = const Size(412, 915),
    Map<String, PlanDeCuotasEnMemoria>? planesPorVenta,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final todos =
        planesPorVenta ??
        {
          'ven-ana': PlanDeCuotasEnMemoria(
            montoCentavos: 200000,
            cobradoCentavos: 50000,
            talonario: '0041',
            cuotas: [cuotaDe(1, dia: 2, monto: 75000), cuotaDe(2, dia: 9, monto: 75000)],
          ),
          'ven-pedro': PlanDeCuotasEnMemoria(
            montoCentavos: 480000,
            cobradoCentavos: 360000,
            talonario: '0038',
          ),
          'ven-pagada': PlanDeCuotasEnMemoria(
            montoCentavos: 100000,
            cobradoCentavos: 100000,
            talonario: '0030',
          ),
          'ven-suelta': PlanDeCuotasEnMemoria(
            montoCentavos: 90000,
            cobradoCentavos: 0,
            talonario: '0029',
          ),
        };
    for (final p in todos.values) {
      addTearDown(p.cerrar);
    }
    planes = _PlanesPorVenta(todos);
    final navegador = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historialDeLaCasaFuenteProvider.overrideWithValue(_Historial()),
          relojPersonaProvider.overrideWithValue(() => _ahora),
          sesionProvider.overrideWith(_SesionFija.new),
          personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
          planDeCuotasRepositoryProvider.overrideWithValue(planes),
          relojCobroProvider.overrideWithValue(() => hoyDeLasCuotas),
          FlujoVerVentaDesdeLaCasa.enganche(navegador),
        ],
        child: MaterialApp(
          navigatorKey: navegador,
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Consumer(
            builder: (context, ref, child) {
              ref.watch(sesionProvider);
              return child!;
            },
            child: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: PestanaHistorialDeLaCasa(espacioId: 'esp-1', direccion: 'Grecia 3310'),
              ),
            ),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  Finder fila(String id) => find.byKey(ClavesHistorialDeLaCasa.fila(id));

  Future<void> tocarVerLaVenta(WidgetTester tester, String id) async {
    await tester.ensureVisible(fila(id));
    await tester.tap(fila(id));
    await asentar(tester);
    final boton = find.byKey(ClavesDetalleDeVisita.verLaVenta);
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await asentar(tester);
  }

  group('abre LA venta tocada, con sus datos', () {
    testWidgets(
      'dado dos ventas con saldo, cada «Ver la venta» muestra el talonario y el plan de la suya',
      (tester) async {
        await montar(tester);

        await tocarVerLaVenta(tester, 'ven-ana');
        expect(find.text(TextosCuotas.eyebrowVenta('0041')), findsOneWidget);
        expect(find.text(TextosCuotas.eyebrowVenta('0038')), findsNothing);
        expect(planes.consultadas, ['ven-ana']);
        await tester.tap(volverDeCuotas);
        await salir(tester);

        await tocarVerLaVenta(tester, 'ven-pedro');
        expect(find.text(TextosCuotas.eyebrowVenta('0038')), findsOneWidget);
        expect(find.text(TextosCuotas.eyebrowVenta('0041')), findsNothing);
        expect(planes.consultadas.last, 'ven-pedro');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('dado una venta pagada del todo, abre las cuotas y dice que no tiene saldo', (
      tester,
    ) async {
      await montar(tester);

      await tocarVerLaVenta(tester, 'ven-pagada');

      expect(paginaLista, findsOneWidget);
      expect(find.byType(MarcaDeSinSaldo), findsOneWidget);
      expect(find.text(TextosCuotas.eyebrowVenta('0030')), findsOneWidget);
    });

    testWidgets('dado una venta sin cliente vinculado, abre las cuotas sin romper', (tester) async {
      await montar(tester);

      await tocarVerLaVenta(tester, 'ven-suelta');

      expect(paginaLista, findsOneWidget);
      expect(find.text(TextosCuotas.eyebrowVenta('0029')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('cada estado de las cuotas tiene salida', () {
    testWidgets('dado que la venta ya no está en el teléfono, lo dice y «Volver» sale', (
      tester,
    ) async {
      await montar(tester, planesPorVenta: const {});

      await tocarVerLaVenta(tester, 'ven-pedro');

      expect(find.byKey(const Key('cuotas_sin_venta')), findsOneWidget);
      expect(find.text(TextosCuotas.ventaAusente), findsOneWidget);
      await tester.tap(volverDeCuotas);
      await salir(tester);
      expect(paginaLista, findsNothing);
      expect(fila('ven-pedro'), findsOneWidget);
      expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsNothing);
    });

    testWidgets('dado que leer las cuotas falla, ofrece «Reintentar» y se puede volver', (
      tester,
    ) async {
      final falla = PlanDeCuotasEnMemoria(talonario: '0038')..fallaAlLeer = true;
      await montar(tester, planesPorVenta: {'ven-pedro': falla});

      await tocarVerLaVenta(tester, 'ven-pedro');

      expect(find.byKey(const Key('cuotas_error_lectura')), findsOneWidget);
      expect(find.text(TextosCuotas.reintentar), findsOneWidget);

      // Se arregla la lectura y «Reintentar» muestra la venta.
      falla.fallaAlLeer = false;
      await tester.tap(find.text(TextosCuotas.reintentar));
      await asentar(tester);
      expect(find.text(TextosCuotas.eyebrowVenta('0038')), findsOneWidget);

      await tester.tap(volverDeCuotas);
      await salir(tester);
      expect(paginaLista, findsNothing);
    });

    testWidgets('dado que las cuotas tardan en leerse, se ve el esqueleto con «Volver» a mano', (
      tester,
    ) async {
      final espera = Completer<void>();
      final lenta = PlanDeCuotasEnMemoria(talonario: '0038')..retenerLaLectura = espera;
      await montar(tester, planesPorVenta: {'ven-pedro': lenta});

      await tocarVerLaVenta(tester, 'ven-pedro');

      expect(find.byType(EsqueletoDeCuotas), findsOneWidget);
      expect(volverDeCuotas, findsOneWidget);
      await tester.tap(volverDeCuotas);
      await salir(tester);
      expect(paginaLista, findsNothing);
      expect(fila('ven-pedro'), findsOneWidget);
      espera.complete();
      await asentar(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('volver y reentrar', () {
    testWidgets(
      'dado el filtro «Ventas», volver de las cuotas con «atrás» del sistema deja el filtro',
      (tester) async {
        await montar(tester);
        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.ventas)));
        await asentar(tester);
        expect(fila('vis-1'), findsNothing);

        await tocarVerLaVenta(tester, 'ven-pedro');
        expect(paginaLista, findsOneWidget);
        await tester.binding.handlePopRoute();
        await salir(tester);

        expect(paginaLista, findsNothing);
        expect(fila('ven-pedro'), findsOneWidget);
        expect(fila('vis-1'), findsNothing, reason: 'el filtro Ventas sigue puesto');
        expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsNothing);
      },
    );

    testWidgets('dado que cierro el detalle con «atrás» del sistema, no abre las cuotas', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(fila('ven-pedro'));
      await asentar(tester);
      expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);

      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(find.byKey(ClavesDetalleDeVisita.hoja), findsNothing);
      expect(paginaLista, findsNothing);
      expect(planes.consultadas, isEmpty);
      // y la fila sigue tocable
      await tester.tap(fila('ven-pedro'));
      await asentar(tester);
      expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);
    });

    testWidgets('dado que abro la venta cinco veces seguidas, cada vez abre una sola pantalla', (
      tester,
    ) async {
      await montar(tester);

      for (var i = 0; i < 5; i++) {
        await tocarVerLaVenta(tester, 'ven-pedro');
        expect(paginaLista, findsOneWidget, reason: 'vuelta $i');
        await tester.tap(volverDeCuotas);
        await salir(tester);
        expect(paginaLista, findsNothing, reason: 'vuelta $i');
      }
      expect(planes.consultadas, hasLength(5));
    });
  });

  group('letra grande', () {
    testWidgets('dado la letra al 200 % en 360×640, el camino completo no desborda', (
      tester,
    ) async {
      await montar(tester, escala: 2, tamano: const Size(360, 640));

      await tocarVerLaVenta(tester, 'ven-ana');

      expect(paginaLista, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
