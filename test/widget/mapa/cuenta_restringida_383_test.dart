// #383 (decisión del agente de decisiones, P2): con la cuenta restringida las pantallas que ya estaban
// abiertas («Posibles duplicados» y su hoja) no dejan empezar nada nuevo —otra revisión, otra
// edición—, y avisan con el texto de esa cuenta. Lo que ya estaba abierto se puede terminar.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/duplicados_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_comparar_duplicado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/duplicados_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'mapa_ubicaciones_arnes.dart' as mapa;
import 'personas_arnes.dart' as personas;

/// Un estado de cuenta que el test cambia cuando quiere.
class _EstadoControlable extends EstadoCuentaNotifier {
  _EstadoControlable(this._inicial);

  final EstadoCuenta _inicial;

  @override
  Future<EstadoCuenta?> build() async => _inicial;

  void poner(EstadoCuenta estado) => state = AsyncData(estado);
}

const _par = 'ub-a|ub-b';
final _hoja = find.byType(HojaCompararDuplicado);
final _aviso = find.byKey(const Key('modulo_bloqueado_aviso'));
final _editarUno = find.byKey(const Key('comparar_editar_uno'));
final _sonDistintos = find.byKey(const Key('comparar_son_distintos'));

late ProviderContainer _container;

/// Toma el contenedor de la app y deja el estado de la cuenta escuchado, como lo hace `_Principal`
/// en la app real (un `read` solo lo deja cargando la primera vez).
void _escucharCuenta(WidgetTester tester) {
  _container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  final suscripcion = _container.listen(estadoCuentaProvider, (_, _) {});
  addTearDown(suscripcion.close);
}

late DuplicadosEnMemoria _datos;

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _transicion(WidgetTester tester) async {
  await _asentar(tester);
  await tester.pump(const Duration(seconds: 1));
  await _asentar(tester);
}

/// «Posibles duplicados» abierto, con un par de ubicaciones a 150 m (admite «Son distintos»).
Future<void> _montar(
  WidgetTester tester, {
  required EstadoCuenta cuenta,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _datos = DuplicadosEnMemoria()
    ..agregar(ubicacionDuplicable('ub-a'))
    ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 150));
  addTearDown(_datos.cerrar);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesDuplicados(_datos, conMapa: true),
        estadoCuentaProvider.overrideWith(() => _EstadoControlable(cuenta)),
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
              child: ElevatedButton(
                key: const Key('abrir'),
                onPressed: () =>
                    unawaited(PosiblesDuplicadosPage.abrir(context, colportorId: 'col-1')),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  _escucharCuenta(tester);
  await _asentar(tester);
  await tester.tap(find.byKey(const Key('abrir')));
  await _transicion(tester);
  expect(find.byKey(const Key('duplicados_titulo')), findsOneWidget);
}

void _restringir(EstadoCuenta estado) =>
    (_container.read(estadoCuentaProvider.notifier) as _EstadoControlable).poner(estado);

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _asentar(tester);
}

Finder _textoDelAviso(String texto) => find.descendant(of: _aviso, matching: find.text(texto));

Future<void> _desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  setUpAll(cargarFuentesReales);

  group('«Posibles duplicados» abierto cuando la cuenta se restringe', () {
    testWidgets('con la cuenta activa, «Revisar» abre la hoja (control)', (tester) async {
      await _montar(tester, cuenta: EstadoCuenta.activa);

      await _tocar(tester, find.byKey(const Key('revisar_$_par')));

      expect(_hoja, findsOneWidget);
      expect(_aviso, findsNothing);
      await _desmontar(tester);
    });

    testWidgets('con la cuenta suspendida, «Revisar» no abre otra revisión y avisa por qué', (
      tester,
    ) async {
      await _montar(tester, cuenta: EstadoCuenta.activa);
      _restringir(EstadoCuenta.suspendida);
      await _asentar(tester);

      await _tocar(tester, find.byKey(const Key('revisar_$_par')));

      expect(_hoja, findsNothing);
      expect(_textoDelAviso(TextosModuloBloqueado.suspendida), findsOneWidget);
      expect(_datos.uniones, isEmpty);
      expect(tester.takeException(), isNull);
      await _desmontar(tester);
    });

    testWidgets('con la cuenta pendiente, el aviso es el de esa cuenta', (tester) async {
      await _montar(tester, cuenta: EstadoCuenta.activa);
      _restringir(EstadoCuenta.pendienteAsignacion);
      await _asentar(tester);

      await _tocar(tester, find.byKey(const Key('revisar_$_par')));

      expect(_hoja, findsNothing);
      expect(_textoDelAviso(TextosModuloBloqueado.pendiente), findsOneWidget);
      await _desmontar(tester);
    });

    testWidgets('dos toques seguidos en «Revisar»: un solo aviso y ninguna hoja', (tester) async {
      await _montar(tester, cuenta: EstadoCuenta.suspendida);

      final lugar = tester.getCenter(find.byKey(const Key('revisar_$_par')));
      await tester.tapAt(lugar);
      await tester.pump();
      await tester.tapAt(lugar);
      await _asentar(tester);

      expect(_hoja, findsNothing);
      expect(_aviso, findsOneWidget);
      await _desmontar(tester);
    });

    testWidgets('a 320×568 y con el texto al 200 %, el aviso se lee entero', (tester) async {
      await _montar(
        tester,
        cuenta: EstadoCuenta.suspendida,
        escala: 2,
        tamano: const Size(320, 568),
      );

      await _tocar(tester, find.byKey(const Key('revisar_$_par')));

      expect(_textoDelAviso(TextosModuloBloqueado.suspendida), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _desmontar(tester);
    });
  });

  group('la hoja de un par ya abierta cuando la cuenta se restringe', () {
    testWidgets('«Editar uno» no abre otra edición y avisa; la hoja sigue', (tester) async {
      await _montar(tester, cuenta: EstadoCuenta.activa);
      await _tocar(tester, find.byKey(const Key('revisar_$_par')));
      expect(_hoja, findsOneWidget);
      _restringir(EstadoCuenta.suspendida);
      await _asentar(tester);

      await _tocar(tester, _editarUno);

      expect(find.text('¿Cuál querés editar?'), findsNothing);
      expect(find.byType(ModificarUbicacionPage), findsNothing);
      expect(_textoDelAviso(TextosModuloBloqueado.suspendida), findsOneWidget);
      expect(_hoja, findsOneWidget, reason: 'lo abierto sigue abierto');
      await _desmontar(tester);
    });

    testWidgets('lo que ya estaba abierto se puede terminar: «Son distintos» se guarda', (
      tester,
    ) async {
      await _montar(tester, cuenta: EstadoCuenta.activa);
      await _tocar(tester, find.byKey(const Key('revisar_$_par')));
      _restringir(EstadoCuenta.suspendida);
      await _asentar(tester);

      await _tocar(tester, _sonDistintos);
      await _transicion(tester);

      expect(_datos.decisiones, isNotEmpty, reason: 'se guardó la decisión');
      expect(_hoja, findsNothing);
      expect(tester.takeException(), isNull);
      await _desmontar(tester);
    });

    testWidgets('con la cuenta activa «Editar uno» sigue abriendo el selector (control)', (
      tester,
    ) async {
      await _montar(tester, cuenta: EstadoCuenta.activa);
      await _tocar(tester, find.byKey(const Key('revisar_$_par')));

      await _tocar(tester, _editarUno);

      expect(find.text('¿Cuál querés editar?'), findsOneWidget);
      expect(_aviso, findsNothing);
      await _desmontar(tester);
    });
  });

  group('la Lista y el Mapa ya abiertos cuando la cuenta se restringe', () {
    Future<void> montarLista(
      WidgetTester tester, {
      required EstadoCuenta cuenta,
      required Future<void> Function() alRegistrar,
      required Future<void> Function() alRevisar,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overridesLista(repo: RepoListaFalso([filaLista('u1')])),
            cantidadParesParaRevisarProvider.overrideWith((ref, colportorId) => 2),
            estadoCuentaProvider.overrideWith(() => _EstadoControlable(cuenta)),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: Scaffold(
              body: ListaUbicacionesPage(
                colportorId: 'col-1',
                alRegistrar: alRegistrar,
                alRevisarDuplicados: alRevisar,
              ),
            ),
          ),
        ),
      );
      _escucharCuenta(tester);
      await _asentar(tester);
    }

    testWidgets('con la cuenta suspendida, «Nueva» y «Revisar» no abren nada y avisan', (
      tester,
    ) async {
      var altas = 0;
      var revisiones = 0;
      await montarLista(
        tester,
        cuenta: EstadoCuenta.activa,
        alRegistrar: () async => altas++,
        alRevisar: () async => revisiones++,
      );
      _restringir(EstadoCuenta.suspendida);
      await _asentar(tester);

      await tester.tap(find.byKey(const Key('lista_nueva')));
      await _asentar(tester);
      expect(altas, 0);
      expect(_textoDelAviso(TextosModuloBloqueado.suspendida), findsOneWidget);

      await tester.tap(find.byKey(const Key('lista_aviso_duplicados')));
      await _asentar(tester);
      expect(revisiones, 0);
      expect(tester.takeException(), isNull);
      await _desmontar(tester);
    });

    testWidgets('con la cuenta activa, «Nueva» y «Revisar» abren (control)', (tester) async {
      var altas = 0;
      var revisiones = 0;
      await montarLista(
        tester,
        cuenta: EstadoCuenta.activa,
        alRegistrar: () async => altas++,
        alRevisar: () async => revisiones++,
      );

      await tester.tap(find.byKey(const Key('lista_nueva')));
      await _asentar(tester);
      await tester.tap(find.byKey(const Key('lista_aviso_duplicados')));
      await _asentar(tester);

      expect(altas, 1);
      expect(revisiones, 1);
      expect(_aviso, findsNothing);
      await _desmontar(tester);
    });

    testWidgets('en el Mapa, con la cuenta pendiente, «Nueva» no abre el alta y avisa', (
      tester,
    ) async {
      final montaje = await mapa.montarMapaUbicaciones(
        tester,
        otrosOverrides: [
          estadoCuentaProvider.overrideWith(
            () => _EstadoControlable(EstadoCuenta.pendienteAsignacion),
          ),
        ],
      );
      _escucharCuenta(tester);
      await _asentar(tester);

      await tester.tap(mapa.botonNueva);
      await _asentar(tester);

      expect(montaje.altas, isEmpty);
      expect(_textoDelAviso(TextosModuloBloqueado.pendiente), findsOneWidget);
      await _desmontar(tester);
    });

    testWidgets('en el Mapa, con la cuenta activa, «Nueva» abre el alta (control)', (tester) async {
      final montaje = await mapa.montarMapaUbicaciones(
        tester,
        otrosOverrides: [
          estadoCuentaProvider.overrideWith(() => _EstadoControlable(EstadoCuenta.activa)),
        ],
      );

      await tester.tap(mapa.botonNueva);
      await _asentar(tester);

      expect(montaje.altas, hasLength(1));
      expect(_aviso, findsNothing);
      await _desmontar(tester);
    });
  });

  group('los clientes de un depto ya abiertos cuando la cuenta se restringe', () {
    testWidgets('con la cuenta suspendida, «+ Agregar cliente» no abre el alta y avisa', (
      tester,
    ) async {
      await personas.montarClientes(
        tester,
        otrosOverrides: [
          estadoCuentaProvider.overrideWith(() => _EstadoControlable(EstadoCuenta.suspendida)),
        ],
      );
      _escucharCuenta(tester);
      await _asentar(tester);

      await tester.tap(find.text('+ Agregar cliente'));
      await _asentar(tester);

      expect(find.text('Nueva persona'), findsNothing);
      expect(_textoDelAviso(TextosModuloBloqueado.suspendida), findsOneWidget);
      await _desmontar(tester);
    });

    testWidgets('con la cuenta activa, «+ Agregar cliente» abre el alta (control)', (tester) async {
      await personas.montarClientes(
        tester,
        otrosOverrides: [
          estadoCuentaProvider.overrideWith(() => _EstadoControlable(EstadoCuenta.activa)),
        ],
      );
      _escucharCuenta(tester);
      await _asentar(tester);

      await tester.tap(find.text('+ Agregar cliente'));
      await _asentar(tester);

      expect(find.text('Nueva persona'), findsOneWidget);
      await _desmontar(tester);
    });
  });
}
