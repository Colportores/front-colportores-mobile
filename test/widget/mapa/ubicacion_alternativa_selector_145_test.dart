// HU-UBI-013 (#145), vista 22 grupo A: el selector «¿Dónde le cobrás?» (22A·02 a 22A·05): elegir entre
// las ubicaciones propias, buscar, cargando, vacío, sin resultados y error al leer.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/elegir_ubicacion_alternativa_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_state.dart'
    show EstadoGpsLista;
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_alternativa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ubicacion_alternativa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ubicacion_alternativa_falsos.dart';
import '../../helpers/ubicacion_colportor_falsos.dart';

void main() {
  // Av. Italia queda a ~2 km, Mataojo a ~40 m y la Rambla a ~2,5 km de «aquí».
  const aqui = Coordenadas(lat: -34.89, lon: -56.16);
  final italia = ubicacionParaAlternativa('ub-2', lat: -34.872, lon: -56.16);
  final mataojo = ubicacionParaAlternativa(
    'ub-3',
    calle: 'Mataojo',
    numero: '2051',
    tipo: TipoUbicacion.casa,
    lat: -34.8904,
    lon: -56.16,
  );
  final rambla = ubicacionParaAlternativa(
    'ub-4',
    calle: 'Rambla Gandhi',
    numero: '470',
    tipo: TipoUbicacion.edificio,
    lat: -34.9125,
    lon: -56.16,
  );

  Ubicacion? elegida;
  var cerro = false;
  var registros = 0;

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Monta una pantalla de arranque con «abrir selector» y la abre.
  Future<void> montar(
    WidgetTester tester,
    UbicacionAlternativaRepositorioFalso repo, {
    double escala = 1,
    Size tamano = const Size(390, 844),
    bool conGps = true,
    bool sinGps = false,
    Future<void> Function()? alRegistrar,
  }) async {
    elegida = null;
    cerro = false;
    registros = 0;
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ubicacionAlternativaRepositoryProvider.overrideWithValue(repo),
          ubicacionColportorProvider.overrideWith(
            () => UbicacionColportorFija(
              conGps && !sinGps
                  ? const UbicacionColportorState(
                      gps: EstadoGpsLista.conLectura,
                      lectura: LecturaGps(coordenadas: aqui, precisionMetros: 8),
                    )
                  : const UbicacionColportorState(),
            ),
          ),
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
                    final u = await Navigator.of(context).push<Ubicacion>(
                      MaterialPageRoute(
                        builder: (_) => ElegirUbicacionAlternativaPage(
                          colportorId: 'col-1',
                          espacioId: 'esp-1',
                          alRegistrar:
                              alRegistrar ??
                              () async {
                                registros += 1;
                              },
                        ),
                      ),
                    );
                    elegida = u;
                    cerro = true;
                  },
                  child: const Text('abrir selector'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir selector'));
    await asentar(tester);
  }

  UbicacionAlternativaRepositorioFalso repoCon(List<Ubicacion> candidatas) =>
      UbicacionAlternativaRepositorioFalso(candidatas: candidatas);

  final buscar = find.byKey(ClavesAlternativa.selectorBuscar);

  group('22A·02 · elegir una ubicación registrada', () {
    testWidgets('dice qué hacer, lista las ubicaciones con dirección, tipo y distancia', (
      tester,
    ) async {
      await montar(tester, repoCon([italia, mataojo, rambla]));

      expect(find.text('COBRAR EN OTRO LUGAR'), findsOneWidget);
      expect(find.text('¿Dónde le cobrás?'), findsOneWidget);
      expect(
        find.text('Elegí una de tus ubicaciones. Si no está, registrala primero.'),
        findsOneWidget,
      );
      expect(find.text('Buscar por dirección o nombre'), findsOneWidget);
      expect(find.text('TUS UBICACIONES · POR CERCANÍA'), findsOneWidget);
      for (final id in ['ub-2', 'ub-3', 'ub-4']) {
        expect(find.byKey(ClavesAlternativa.fila(id)), findsOneWidget);
      }
      final mataojoFila = find.byKey(ClavesAlternativa.fila('ub-3'));
      expect(find.descendant(of: mataojoFila, matching: find.text('Mataojo 2051')), findsOneWidget);
      expect(find.descendant(of: mataojoFila, matching: find.text('Casa')), findsOneWidget);
      expect(
        find.descendant(of: mataojoFila, matching: find.textContaining('a 44')),
        findsOneWidget,
      );
      expect(find.text('+ Registrar una ubicación'), findsOneWidget);
    });

    testWidgets('van por cercanía: la más cerca arriba', (tester) async {
      await montar(tester, repoCon([rambla, italia, mataojo]));

      double arriba(String id) => tester.getTopLeft(find.byKey(ClavesAlternativa.fila(id))).dy;
      expect(arriba('ub-3'), lessThan(arriba('ub-2')));
      expect(arriba('ub-2'), lessThan(arriba('ub-4')));
    });

    testWidgets('sin GPS van por dirección, sin distancia y el rótulo no promete cercanía', (
      tester,
    ) async {
      await montar(tester, repoCon([rambla, mataojo, italia]), sinGps: true);

      expect(find.text('TUS UBICACIONES'), findsOneWidget);
      expect(find.text('TUS UBICACIONES · POR CERCANÍA'), findsNothing);
      expect(find.textContaining('a 4'), findsNothing);
      double arriba(String id) => tester.getTopLeft(find.byKey(ClavesAlternativa.fila(id))).dy;
      // Av. Italia, Mataojo, Rambla Gandhi.
      expect(arriba('ub-2'), lessThan(arriba('ub-3')));
      expect(arriba('ub-3'), lessThan(arriba('ub-4')));
    });

    testWidgets('pide solo las ubicaciones de quien cobra para el espacio de la persona', (
      tester,
    ) async {
      final repo = repoCon([italia]);
      await montar(tester, repo);

      expect(repo.pedidasCandidatas, [(colportorId: 'col-1', espacioId: 'esp-1')]);
    });

    testWidgets('tocar una fila devuelve esa ubicación y cierra', (tester) async {
      await montar(tester, repoCon([italia, mataojo]));

      await tester.tap(find.byKey(ClavesAlternativa.fila('ub-2')));
      await asentar(tester);

      expect(cerro, isTrue);
      expect(elegida?.id, 'ub-2');
      expect(find.byKey(ClavesAlternativa.selector), findsNothing);
    });

    testWidgets('dos toques seguidos sobre filas distintas eligen solo la primera', (tester) async {
      await montar(tester, repoCon([italia, mataojo]));

      await tester.tap(find.byKey(ClavesAlternativa.fila('ub-3')));
      await tester.tap(find.byKey(ClavesAlternativa.fila('ub-2')));
      await asentar(tester);

      expect(elegida?.id, 'ub-3');
      expect(find.text('abrir selector'), findsOneWidget);
    });

    testWidgets('la ✕ cierra sin elegir y un segundo toque no cierra dos veces', (tester) async {
      await montar(tester, repoCon([italia]));

      final cerrar = find.byKey(ClavesAlternativa.selectorCerrar);
      await tester.tap(cerrar);
      await tester.tap(cerrar);
      await asentar(tester);

      expect(cerro, isTrue);
      expect(elegida, isNull);
      expect(find.text('abrir selector'), findsOneWidget);
    });

    testWidgets(
      'las filas y la ✕ miden al menos 48 dp y se anuncian como botones con dirección y tipo',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await montar(tester, repoCon([italia, mataojo]));

        final fila = find.byKey(ClavesAlternativa.fila('ub-3'));
        expect(tester.getSize(fila).height, greaterThanOrEqualTo(48));
        expect(
          tester.getSize(find.byKey(ClavesAlternativa.selectorCerrar)).height,
          greaterThanOrEqualTo(48),
        );
        final nodo = tester.getSemantics(fila);
        expect(nodo.flagsCollection.isButton, isTrue);
        expect(nodo.label, startsWith('Mataojo 2051, Casa, a '));
        semantica.dispose();
      },
    );
  });

  group('búsqueda', () {
    testWidgets('filtra por dirección mientras se escribe', (tester) async {
      await montar(tester, repoCon([italia, mataojo, rambla]));

      await tester.enterText(buscar, 'italia');
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.fila('ub-3')), findsNothing);
      expect(find.byKey(ClavesAlternativa.fila('ub-4')), findsNothing);
    });

    testWidgets('la ✕ del campo borra la búsqueda y vuelve la lista entera', (tester) async {
      await montar(tester, repoCon([italia, mataojo]));
      await tester.enterText(buscar, 'mataojo');
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsNothing);

      await tester.tap(find.byKey(ClavesAlternativa.selectorBorrarBusqueda));
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.fila('ub-3')), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.selectorBorrarBusqueda), findsNothing);
    });
  });

  group('22A·05 · búsqueda sin resultados', () {
    testWidgets('dice que ninguna coincide, ofrece registrarla y conserva el texto buscado', (
      tester,
    ) async {
      await montar(tester, repoCon([italia, mataojo]));

      await tester.enterText(buscar, 'Bulevar Artigas');
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.selectorSinResultados), findsOneWidget);
      expect(find.text('Ninguna ubicación coincide'), findsOneWidget);
      expect(find.text('Probá con otra parte de la dirección o registrala.'), findsOneWidget);
      expect(find.text('Bulevar Artigas'), findsOneWidget);
      expect(find.text('+ Registrar una ubicación'), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.selectorVacio), findsNothing);
    });

    testWidgets('«+ Registrar una ubicación» abre el alta, una sola vez aunque se toque dos', (
      tester,
    ) async {
      final compuerta = Completer<void>();
      await montar(
        tester,
        repoCon([italia]),
        alRegistrar: () {
          registros += 1;
          return compuerta.future;
        },
      );

      final registrar = find.byKey(ClavesAlternativa.selectorRegistrarMas);
      await tester.tap(registrar);
      await tester.tap(registrar);
      await asentar(tester);

      expect(registros, 1);
      compuerta.complete();
      await asentar(tester);
      // Con el alta cerrada se puede volver a tocar.
      await tester.tap(registrar);
      await asentar(tester);
      expect(registros, 2);
    });

    testWidgets('al volver del alta la lista, que lee en vivo, ya trae la ubicación nueva', (
      tester,
    ) async {
      final repo = repoCon([italia]);
      await montar(
        tester,
        repo,
        alRegistrar: () async {
          repo.ponerCandidatas([italia, mataojo]);
        },
      );
      expect(find.byKey(ClavesAlternativa.fila('ub-3')), findsNothing);

      await tester.tap(find.byKey(ClavesAlternativa.selectorRegistrarMas));
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.fila('ub-3')), findsOneWidget);
    });

    testWidgets('si el alta falla, el selector sigue y el botón vuelve a quedar tocable', (
      tester,
    ) async {
      var intentos = 0;
      await montar(
        tester,
        repoCon([italia]),
        alRegistrar: () async {
          intentos += 1;
          if (intentos == 1) throw StateError('se cortó');
        },
      );

      await tester.tap(find.byKey(ClavesAlternativa.selectorRegistrarMas));
      await asentar(tester);
      // El error del alta lo maneja el alta; acá no queda trabado nada.
      tester.takeException();
      await tester.tap(find.byKey(ClavesAlternativa.selectorRegistrarMas));
      await asentar(tester);

      expect(intentos, 2);
    });
  });

  group('22A·03 · cargando', () {
    testWidgets('el campo apagado y tres filas de relleno, y al llegar los datos se reemplazan', (
      tester,
    ) async {
      final repo = repoCon([italia])..sinLecturaDeCandidatas();
      await montar(tester, repo);

      expect(find.byKey(ClavesAlternativa.selectorCargando), findsOneWidget);
      expect(tester.widget<TextField>(buscar).enabled, isFalse);
      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsNothing);
      // Sin lista todavía no se ofrece registrar: no se sabe si hacía falta.
      expect(find.byKey(ClavesAlternativa.selectorRegistrarMas), findsNothing);

      repo.ponerCandidatas([italia, mataojo]);
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.selectorCargando), findsNothing);
      expect(tester.widget<TextField>(buscar).enabled, isTrue);
      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsOneWidget);
    });

    testWidgets('el lector de pantalla oye una sola frase', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar(tester, repoCon([italia])..sinLecturaDeCandidatas());

      expect(
        tester.getSemantics(find.byKey(ClavesAlternativa.selectorCargando)).label,
        'Cargando tus ubicaciones',
      );
      semantica.dispose();
    });
  });

  group('22A·04 · sin otras ubicaciones', () {
    testWidgets('dice qué pasa y qué hacer, con «Registrar una ubicación» y sin campo de búsqueda', (
      tester,
    ) async {
      await montar(tester, repoCon(const []));

      expect(find.byKey(ClavesAlternativa.selectorVacio), findsOneWidget);
      expect(find.text('No tenés otra ubicación para elegir'), findsOneWidget);
      expect(
        find.text(
          'Registrá primero el lugar donde le vas a cobrar (por ejemplo, su trabajo) y volvé a esta ficha.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(ClavesAlternativa.selectorRegistrar), findsOneWidget);
      expect(find.text('Registrar una ubicación'), findsOneWidget);
      expect(buscar, findsNothing);
      expect(find.byKey(ClavesAlternativa.selectorRegistrarMas), findsNothing);
    });

    testWidgets('«Registrar una ubicación» abre el alta y, al volver, aparece la nueva', (
      tester,
    ) async {
      final repo = repoCon(const []);
      await montar(
        tester,
        repo,
        alRegistrar: () async {
          registros += 1;
          repo.ponerCandidatas([italia]);
        },
      );

      await tester.tap(find.byKey(ClavesAlternativa.selectorRegistrar));
      await asentar(tester);

      expect(registros, 1);
      expect(find.byKey(ClavesAlternativa.selectorVacio), findsNothing);
      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsOneWidget);
    });
  });

  group('error al leer', () {
    testWidgets('avisa con «Reintentar» y, al reintentar, trae la lista', (tester) async {
      final repo = repoCon([italia])..errorAlObservarCandidatas = StateError('sin db');
      await montar(tester, repo);

      expect(find.byKey(ClavesAlternativa.selectorError), findsOneWidget);
      expect(
        find.text('No pudimos leer tus ubicaciones en tu teléfono. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.byKey(ClavesAlternativa.selectorRegistrarMas), findsNothing);

      repo.errorAlObservarCandidatas = null;
      await tester.tap(find.byKey(ClavesAlternativa.selectorReintentar));
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.selectorError), findsNothing);
      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsOneWidget);
    });

    testWidgets('si el reintento vuelve a fallar, el aviso sigue y «Reintentar» sigue tocable', (
      tester,
    ) async {
      final repo = repoCon([italia])..errorAlObservarCandidatas = StateError('sin db');
      await montar(tester, repo);

      await tester.tap(find.byKey(ClavesAlternativa.selectorReintentar));
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.selectorError), findsOneWidget);
      expect(repo.observacionesDeCandidatas, greaterThanOrEqualTo(2));
      await tester.tap(find.byKey(ClavesAlternativa.selectorReintentar));
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.selectorError), findsOneWidget);
    });
  });

  group('datos límite', () {
    testWidgets('con 150 ubicaciones se puede llegar a la última y elegirla', (tester) async {
      final muchas = [
        for (var i = 0; i < 150; i++)
          ubicacionParaAlternativa(
            'ub-m$i',
            calle: 'Calle $i',
            numero: '${100 + i}',
            lat: -34.89 + i * .001,
          ),
      ];
      await montar(tester, repoCon(muchas));

      final ultima = find.byKey(ClavesAlternativa.fila('ub-m149'));
      await tester.scrollUntilVisible(ultima, 600, scrollable: find.byType(Scrollable).first);
      await tester.tap(ultima);
      await asentar(tester);

      expect(elegida?.id, 'ub-m149');
    });

    final larga = ubicacionParaAlternativa(
      'ub-largo',
      calle: 'Avenida Doctor Luis Alberto de Herrera y Sarmiento de Gamboa',
      numero: '12345 bis apto 1204',
    );
    const chico = Size(320, 640);

    testWidgets('con el texto al 200 % la lista, con una dirección larguísima, entra', (
      tester,
    ) async {
      await montar(tester, repoCon([larga, mataojo]), escala: 2, tamano: chico);

      final fila = find.byKey(ClavesAlternativa.fila('ub-largo'));
      await tester.scrollUntilVisible(fila, 200, scrollable: find.byType(Scrollable).first);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(fila, findsOneWidget);
      await tester.tap(fila);
      await asentar(tester);
      expect(elegida?.id, 'ub-largo');
    });

    testWidgets('con el texto al 200 % «sin resultados» y registrar siguen a la vista', (
      tester,
    ) async {
      await montar(tester, repoCon([larga, mataojo]), escala: 2, tamano: chico);

      // Con el texto grande el campo queda más abajo: se llega desplazando.
      await tester.scrollUntilVisible(buscar, 100, scrollable: find.byType(Scrollable).first);
      await tester.enterText(buscar, 'zzz');
      await asentar(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesAlternativa.selectorSinResultados), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.selectorRegistrarMas), findsOneWidget);
    });

    testWidgets('con el texto al 200 % el vacío entra y «Registrar una ubicación» se ve', (
      tester,
    ) async {
      await montar(tester, repoCon(const []), escala: 2, tamano: chico);

      // El botón va fijo abajo; el mensaje está en la lista, que se desplaza.
      expect(find.byKey(ClavesAlternativa.selectorRegistrar), findsOneWidget);
      final vacio = find.byKey(ClavesAlternativa.selectorVacio);
      await tester.scrollUntilVisible(vacio, 100, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      expect(vacio, findsOneWidget);
    });

    testWidgets('con el texto al 200 % el error al leer entra con su «Reintentar»', (tester) async {
      final conError = repoCon([larga])..errorAlObservarCandidatas = StateError('x');
      await montar(tester, conError, escala: 2, tamano: chico);

      final reintentar = find.byKey(ClavesAlternativa.selectorReintentar);
      await tester.scrollUntilVisible(reintentar, 100, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      expect(reintentar, findsOneWidget);
    });

    testWidgets('con el teclado abierto el botón de registrar sigue a la vista', (tester) async {
      await montar(tester, repoCon([italia]), tamano: const Size(390, 500));

      await tester.showKeyboard(buscar);
      await tester.pump();

      expect(find.byKey(ClavesAlternativa.selectorRegistrarMas), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
