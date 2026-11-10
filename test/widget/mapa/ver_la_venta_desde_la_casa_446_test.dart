// Vista 39 C·04 «Detalle de una venta» → vista 30 A «Cuotas de la venta» (decisión del 10/11, P2 de
// #446): «Ver la venta» del Historial de la casa abre, por el enganche REAL que arma `main.dart`
// (`FlujoVerVentaDesdeLaCasa.enganche`), las cuotas de LA venta tocada, con el espacio de la hoja, su
// cliente y el colportor de la sesión. Casos límite: dos ventas con saldo en la casa, doble toque, falla
// a mitad (sin sesión), volver y reentrar, y letra al 200 %.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/pages/cuotas_de_la_venta_page.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/evento_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart'
    show LineaDeFicha;
import 'package:colportores_mobile/features/mapa/domain/services/historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_ver_venta_desde_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/historial_de_la_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_detalle_de_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_historial_de_la_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuotas_arnes.dart' show paginaLista, volverDeCuotas;
import '../../helpers/cuotas_desde_agenda_arnes.dart' show overridesDeLasCuotas, planDeLaVenta;
import '../../helpers/persona_falsos.dart';

/// El «hoy» de los tests: domingo 25/10/2026 a las 16:00, hora local.
final _ahora = DateTime(2026, 10, 25, 16);

DateTime _local(int mes, int dia, [int hora = 12]) => DateTime(2026, mes, dia, hora).toUtc();

/// El historial de la casa en memoria.
final class _Historial implements HistorialDeLaCasa {
  _Historial(this._eventos);

  final List<EventoDeLaCasa> _eventos;

  @override
  Stream<List<EventoDeLaCasa>> observar(String espacioId) => Stream.value(_eventos);
}

class _SesionFija extends SesionNotifier {
  _SesionFija(this._sesion);

  final Sesion? _sesion;

  @override
  Future<Sesion?> build() async => _sesion;
}

final _sesion = Sesion(
  usuarioId: 'col-1',
  email: 'ana@example.com',
  accessToken: 'jwt',
  expiraEn: DateTime.utc(2030),
);

/// Cuenta las pantallas que se empujan (no las hojas modales).
final class _Pantallas extends NavigatorObserver {
  var empujadas = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && route.settings.name != '/') empujadas++;
  }
}

/// La venta 0038 de Pedro: $ 4800, pagó $ 3600.
final _dePedro = VentaDeLaCasa(
  id: 'ven-1',
  fecha: _local(10, 12, 14),
  numeroTalonario: '0038',
  montoCentavos: 480000,
  pagadoCentavos: 360000,
  lineas: const [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)],
  persona: const PersonaDelEvento(nombre: 'Pedro', apellido: 'Gómez'),
  espacioPersonaId: 'ep-pedro',
);

/// La venta 0041 de Ana, más nueva y también con saldo.
final _deAna = VentaDeLaCasa(
  id: 'ven-2',
  fecha: _local(10, 20, 11),
  numeroTalonario: '0041',
  montoCentavos: 200000,
  pagadoCentavos: 50000,
  lineas: const [LineaDeFicha(nombre: 'El Deseado', cantidad: 1)],
  persona: const PersonaDelEvento(nombre: 'Ana'),
  espacioPersonaId: 'ep-ana',
);

void main() {
  late _Pantallas pantallas;

  Future<void> asentar(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> montar(
    WidgetTester tester, {
    Sesion? sesion,
    bool conSesion = true,
    double escala = 1,
    Size tamano = const Size(412, 915),
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final plan = planDeLaVenta();
    addTearDown(plan.cerrar);
    final navegador = GlobalKey<NavigatorState>();
    pantallas = _Pantallas();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historialDeLaCasaFuenteProvider.overrideWithValue(_Historial([_deAna, _dePedro])),
          relojPersonaProvider.overrideWithValue(() => _ahora),
          sesionProvider.overrideWith(() => _SesionFija(conSesion ? (sesion ?? _sesion) : null)),
          personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
          ...overridesDeLasCuotas(plan),
          // El enganche de verdad, el mismo que arma `main.dart`.
          FlujoVerVentaDesdeLaCasa.enganche(navegador),
        ],
        child: MaterialApp(
          navigatorKey: navegador,
          navigatorObservers: [pantallas],
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          // Como en la app (`app.dart` mira la sesión desde el arranque): la sesión ya está leída
          // cuando se toca «Ver la venta».
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
    // La sesión se resuelve en un futuro: que esté antes del primer toque.
    await asentar(tester);
    final contenedor = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(contenedor.read(sesionProvider).hasValue, isTrue);
  }

  Finder fila(String id) => find.byKey(ClavesHistorialDeLaCasa.fila(id));

  Future<void> verLaVentaDe(WidgetTester tester, String id) async {
    await tester.ensureVisible(fila(id));
    await tester.tap(fila(id));
    await asentar(tester);
    final boton = find.byKey(ClavesDetalleDeVisita.verLaVenta);
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await asentar(tester);
  }

  CuotasDeLaVentaPage laPantalla(WidgetTester tester) =>
      tester.widget<CuotasDeLaVentaPage>(find.byType(CuotasDeLaVentaPage));

  testWidgets(
    'dado el enganche de la app, «Ver la venta» abre las cuotas de esa venta con el espacio, el '
    'cliente y el colportor de la sesión',
    (tester) async {
      await montar(tester);

      await verLaVentaDe(tester, 'ven-1');

      expect(paginaLista, findsOneWidget);
      final p = laPantalla(tester);
      expect(p.ventaId, 'ven-1');
      expect(p.espacioId, 'esp-1');
      expect(p.espacioPersonaId, 'ep-pedro');
      expect(p.colportorId, 'col-1');
      expect(find.byKey(ClavesDetalleDeVisita.hoja), findsNothing);
      expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsNothing);
    },
  );

  testWidgets(
    'dado dos ventas con saldo en la casa, cada «Ver la venta» abre la suya; al volver, el '
    'historial sigue como estaba',
    (tester) async {
      await montar(tester);

      await verLaVentaDe(tester, 'ven-2');
      expect(laPantalla(tester).ventaId, 'ven-2');
      expect(laPantalla(tester).espacioPersonaId, 'ep-ana');

      await tester.tap(volverDeCuotas);
      await asentar(tester);
      expect(paginaLista, findsNothing);
      expect(fila('ven-1'), findsOneWidget);
      expect(fila('ven-2'), findsOneWidget);

      await verLaVentaDe(tester, 'ven-1');
      expect(laPantalla(tester).ventaId, 'ven-1');
      expect(laPantalla(tester).espacioPersonaId, 'ep-pedro');
      expect(pantallas.empujadas, 2);
    },
  );

  testWidgets('dado un doble toque en «Ver la venta», se abre una sola pantalla de cuotas', (
    tester,
  ) async {
    await montar(tester);
    await tester.tap(fila('ven-1'));
    await asentar(tester);

    final handle = tester.ensureSemantics();
    final boton = find.semantics.byLabel(TextosHistorialDeLaCasa.verLaVenta);
    tester.semantics.performAction(boton, SemanticsAction.tap);
    tester.semantics.performAction(boton, SemanticsAction.tap);
    await asentar(tester);
    handle.dispose();

    expect(find.byType(CuotasDeLaVentaPage), findsOneWidget);
    expect(pantallas.empujadas, 1);
  });

  testWidgets(
    'dado que no hay sesión, no abre nada, avisa que no pudo abrir la venta y la fila no queda '
    'trabada',
    (tester) async {
      await montar(tester, conSesion: false);

      await verLaVentaDe(tester, 'ven-1');

      expect(find.byType(CuotasDeLaVentaPage), findsNothing);
      expect(find.text(TextosHistorialDeLaCasa.noPudimosAbrirLaVenta), findsOneWidget);
      expect(tester.takeException(), isNull);

      // La fila se vuelve a tocar: el detalle abre y el aviso se va.
      await tester.tap(fila('ven-1'));
      await asentar(tester);
      expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);
      expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsNothing);
    },
  );

  testWidgets('dado la letra al 200 % en un teléfono chico, abre las cuotas sin desbordes', (
    tester,
  ) async {
    await montar(tester, escala: 2, tamano: const Size(320, 568));

    await verLaVentaDe(tester, 'ven-2');

    expect(laPantalla(tester).ventaId, 'ven-2');
    expect(tester.takeException(), isNull);
  });
}
