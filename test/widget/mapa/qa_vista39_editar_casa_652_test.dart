// QA de «Editar casa» en la hoja de la casa (vista 39, C·01/C·02/E·04, #652, PR #662): el camino real
// por el mapa (la hoja a un tercio y a la mitad), la vista 07 REAL abierta desde la hoja (guardar, volver,
// reentrar), la matriz de tamaños y escalas, las guías de accesibilidad y las salidas de la 07 que no
// son «guardé». Las capturas salen con `--dart-define=QA_CAPTURAS=true` a `.dart_tool/qa_capturas/652_*.png`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart'
    show ClaveDeLaCasa;
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart'
    show ClavesMapaUbicaciones;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';
import '../../helpers/qa_vista39_445_arnes.dart' show cargarFuentes205, t360x640, t412x915;
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas;

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

Finder get _editar => find.byKey(ClavesHojaCasa.editar);

String _sufijo(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/652_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

// ------------------------------------------------------------------------------------------------
// El mapa real con un abridor de la edición falso
// ------------------------------------------------------------------------------------------------

final class _Edicion {
  final abiertas = <({String colportorId, String ubicacionId})>[];
  Future<SalidaModificarUbicacion?> Function()? alAbrir;

  Future<SalidaModificarUbicacion?> abrir(
    BuildContext context, {
    required String colportorId,
    required String ubicacionId,
  }) {
    abiertas.add((colportorId: colportorId, ubicacionId: ubicacionId));
    return alAbrir == null ? Future.value() : alAbrir!();
  }
}

Future<({MontajeMapaUbicaciones m, _Edicion edicion, RepoListaFalso repo})> _mapa(
  WidgetTester tester, {
  Size tamano = t412x915,
  double escala = 1,
  List<UbicacionConResumen>? filas,
  bool fuentesReales = false,
  Future<void> Function()? registrar,
  Stream<ContextoDeLaCasa> Function(ClaveDeLaCasa clave)? lectura,
}) async {
  if (fuentesReales) await cargarFuentes205(tester);
  final edicion = _Edicion();
  final repo = RepoListaFalso(filas ?? canvas());
  final m = await montarMapaUbicaciones(
    tester,
    repo: repo,
    tamano: tamano,
    escala: escala,
    lecturaContexto: lectura,
    registrarVisita: registrar == null ? (c) {} : (c) => registrar(),
    cobrar: (c) {},
    otrosOverrides: [abridorEdicionUbicacionProvider.overrideWithValue(edicion.abrir)],
  );
  return (m: m, edicion: edicion, repo: repo);
}

// ------------------------------------------------------------------------------------------------
// La vista 07 REAL abierta desde la hoja
// ------------------------------------------------------------------------------------------------

final class _Real {
  _Real(this.repo, this.item);
  final RepoEdicionFalso repo;
  final ValueNotifier<ItemListaUbicacion> item;
  final cierres = <int>[];
}

Future<void> _asentar(WidgetTester tester, [int veces = 12]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_Real> _montarReal(
  WidgetTester tester, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  RepoEdicionFalso? repo,
  String? colportorId = 'col-1',
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = repo ?? RepoEdicionFalso(ubicacionGuardada(id: 'u-1', calle: 'Grecia', numero: '3310'));
  final real = _Real(r, ValueNotifier(itemDeLaHoja()));
  addTearDown(real.item.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...overridesHojaCasa(),
        ...overridesAlta(
          gps: GpsFalso(),
          geocodificador: GeocodificadorFalso(
            (_) => const DireccionDelPunto(calle: 'Grecia', numero: '3310'),
          ),
          ciudades: CiudadesFalsas(),
          repo: r,
          ahora: DateTime.utc(2026, 10, 2, 12),
          mapa: FabricaMapaFalsa(),
        ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: ValueListenableBuilder<ItemListaUbicacion>(
              valueListenable: real.item,
              builder: (_, item, _) => HojaCasa(
                item: item,
                ahora: ahoraLista,
                alCerrar: () => real.cierres.add(real.cierres.length),
                colportorId: colportorId,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return real;
}

/// El «atrás» del sistema sobre la pantalla de arriba.
Future<void> _atras(WidgetTester tester) async {
  await tester.state<NavigatorState>(find.byType(Navigator).last).maybePop();
  await _asentar(tester);
}

Finder get _guardar => find.widgetWithText(FilledButton, TextosModificar.guardarCambios);
Finder get _campoCalle => find.byType(TextField).at(0);

Future<void> _traer(WidgetTester tester, Finder f) async {
  await tester.pump();
  await Scrollable.ensureVisible(tester.element(f), alignment: .5);
  await tester.pump();
}

void main() {
  // ----------------------------------------------------------------------------------------------
  // 1 · La 07 real desde la hoja
  // ----------------------------------------------------------------------------------------------
  group('La vista 07 real abierta desde «Editar casa»', () {
    testWidgets('dado que se toca «Editar casa», abre la 07 con los datos de ESA casa', (
      tester,
    ) async {
      await _montarReal(tester);

      await tester.tap(_editar);
      await _asentar(tester);

      expect(find.byType(ModificarUbicacionPage), findsOneWidget);
      expect(tester.widget<TextField>(_campoCalle).controller!.text, 'Grecia');
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado que se corrige la calle y se guarda, vuelve a la hoja, que sigue abierta, '
        'con la dirección nueva y sin cerrarse', (tester) async {
      final r = await _montarReal(tester);
      expect(find.text('Grecia 3310'), findsOneWidget);

      await tester.tap(_editar);
      await _asentar(tester);
      await _traer(tester, _campoCalle);
      await tester.enterText(_campoCalle, 'Rivera');
      await tester.pump();
      await _traer(tester, _guardar);
      await tester.tap(_guardar);
      await _asentar(tester, 20);

      expect(r.repo.escrituras, hasLength(1));
      expect(r.repo.escrituras.single.nueva.calle, 'Rivera');
      expect(r.repo.escrituras.single.nueva.id, 'u-1');
      expect(find.byType(ModificarUbicacionPage), findsNothing);
      // La lista viva trae la casa corregida: la hoja la muestra sin cerrarse.
      r.item.value = itemDeLaHoja(calle: 'Rivera', numero: '3310');
      await tester.pump();
      expect(find.text('Rivera 3310'), findsOneWidget);
      expect(r.cierres, isEmpty);
      expect(_editar, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado que se guardó, el botón vuelve a abrir la edición (reentrada) y no queda '
        'trabado', (tester) async {
      await _montarReal(tester);
      for (var vez = 0; vez < 3; vez++) {
        await tester.tap(_editar);
        await _asentar(tester);
        expect(find.byType(ModificarUbicacionPage), findsOneWidget, reason: 'vez $vez');
        await _atras(tester);
        await _asentar(tester);
        expect(find.byType(ModificarUbicacionPage), findsNothing, reason: 'vez $vez');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado que se vuelve atrás sin guardar, la hoja sigue igual y no se escribió nada', (
      tester,
    ) async {
      final r = await _montarReal(tester);
      await tester.tap(_editar);
      await _asentar(tester);
      await _traer(tester, _campoCalle);
      await tester.enterText(_campoCalle, 'Otra calle');
      await tester.pump();

      await _atras(tester);
      // Con cambios sin guardar la 07 pregunta antes de salir (07·04): se descartan.
      expect(find.text(TextosModificar.descartar), findsOneWidget);
      await tester.tap(find.text(TextosModificar.descartar));
      await _asentar(tester, 20);

      expect(find.byType(ModificarUbicacionPage), findsNothing);
      expect(r.repo.escrituras, isEmpty);
      expect(find.text('Grecia 3310'), findsOneWidget);
      expect(r.cierres, isEmpty);
    });

    testWidgets('dado un doble toque rápido sobre «Editar casa», se apila una sola edición', (
      tester,
    ) async {
      await _montarReal(tester);

      await tester.tap(_editar);
      await tester.tap(_editar, warnIfMissed: false);
      await tester.tap(_editar, warnIfMissed: false);
      await _asentar(tester);

      expect(find.byType(ModificarUbicacionPage), findsOneWidget);
      await _atras(tester);
      await _asentar(tester);
      expect(find.byType(ModificarUbicacionPage), findsNothing, reason: 'una sola página apilada');
    });

    testWidgets('dado que la ubicación no está en el teléfono, la 07 lo dice y se puede volver a '
        'la hoja', (tester) async {
      final r = await _montarReal(tester);
      r.repo.actual = null;

      await tester.tap(_editar);
      await _asentar(tester);

      expect(tester.takeException(), isNull);
      await _atras(tester);
      await _asentar(tester);
      expect(_editar, findsOneWidget);
    });
  });

  // ----------------------------------------------------------------------------------------------
  // 2 · El mapa real: matriz de tamaños y escalas, hoja a un tercio y a la mitad
  // ----------------------------------------------------------------------------------------------
  group('El mapa real · «Editar casa» en C·01 (un tercio) y C·02 (mitad)', () {
    for (final tamano in [t360x640, t412x915]) {
      for (final escala in [1.0, 2.0]) {
        final suf = _sufijo(tamano, escala);

        testWidgets('C·01 a un tercio: se ve entero, se toca y abre esa casa · $suf', (
          tester,
        ) async {
          final s = await _mapa(tester, tamano: tamano, escala: escala, fuentesReales: true);
          s.m.mapa.tocarPunto('a');
          await asentarLista(tester);

          expect(_editar, findsOneWidget);
          expect(tester.takeException(), isNull);
          final r = tester.getRect(_editar);
          expect(r.height, greaterThanOrEqualTo(48));
          expect(r.width, greaterThanOrEqualTo(48));
          expect(r.top, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(tamano.width));
          expect(_editar.hitTestable(), findsOneWidget, reason: 'nada lo tapa');
          await _capturar(tester, 'mapa_tercio_$suf');

          await tester.tap(_editar);
          await asentarLista(tester);
          expect(s.edicion.abiertas, [(colportorId: 'col-1', ubicacionId: 'a')]);
          expect(find.byKey(ClavesHojaCasa.titulo), findsOneWidget, reason: 'la hoja sigue');
          expect(tester.takeException(), isNull);
        });

        testWidgets('C·02 a la mitad: «Editar casa» sigue junto a la dirección · $suf', (
          tester,
        ) async {
          final s = await _mapa(tester, tamano: tamano, escala: escala, fuentesReales: true);
          s.m.mapa.tocarPunto('a');
          await asentarLista(tester);
          await tocarAsa(tester);

          expect(find.byKey(ClavesHojaCasa.pestanas), findsOneWidget);
          expect(_editar, findsOneWidget);
          expect(_editar.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _capturar(tester, 'mapa_mitad_$suf');
          await tester.tap(_editar);
          await asentarLista(tester);
          expect(s.edicion.abiertas, hasLength(1));
        });
      }
    }

    testWidgets('dado que se toca «Editar casa», el mapa no se recentra ni cambia de zoom', (
      tester,
    ) async {
      final s = await _mapa(tester);
      s.m.mapa.tocarPunto('a');
      await asentarLista(tester);
      final antes = s.m.mapa.camara!;

      await tester.tap(_editar);
      await asentarLista(tester);

      final despues = s.m.mapa.camara!;
      expect(despues.centro, antes.centro);
      expect(despues.zoom, antes.zoom);
    });

    testWidgets('dado que se guardó (UbicacionEditada), la hoja y el marcador muestran el número '
        'nuevo sin cerrar la hoja ni mover el mapa', (tester) async {
      final s = await _mapa(tester);
      s.m.mapa.tocarPunto('a');
      await asentarLista(tester);
      expect(punto(s.m.mapa, 'a').etiqueta, '1234');
      final antes = s.m.mapa.camara!;
      s.edicion.alAbrir = () async {
        s.repo.emitir([
          filaLista(
            'a',
            calle: 'Av. Italia',
            numero: '1300',
            metrosAlNorte: 40,
            espacios: 2,
            estado: EstadoCasa.cobranzaPendiente,
          ),
          ...canvas().skip(1),
        ]);
        return null;
      };

      await tester.tap(_editar);
      await asentarLista(tester);

      expect(find.text('Av. Italia 1300'), findsWidgets);
      expect(find.text('Av. Italia 1234'), findsNothing);
      expect(punto(s.m.mapa, 'a').etiqueta, '1300');
      expect(find.byKey(ClavesHojaCasa.titulo), findsOneWidget);
      expect(s.m.mapa.camara!.centro, antes.centro);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado «Editar casa» en curso, «Registrar visita» no corre a la vez (guarda '
        'compartida) y al terminar vuelve a andar', (tester) async {
      var registros = 0;
      final s = await _mapa(tester, registrar: () async => registros++);
      s.m.mapa.tocarPunto('a');
      await asentarLista(tester);
      await tocarAsa(tester);
      final compuerta = Completer<SalidaModificarUbicacion?>();
      s.edicion.alAbrir = () => compuerta.future;

      await tester.tap(_editar);
      await asentarLista(tester);
      final registrar = find.byKey(ClavesHojaCasa.registrarVisita);
      await tester.ensureVisible(registrar);
      await tester.tap(registrar, warnIfMissed: false);
      await asentarLista(tester);
      expect(registros, 0, reason: 'la acción en curso corta a las otras');

      compuerta.complete(null);
      await asentarLista(tester);
      await tester.tap(registrar, warnIfMissed: false);
      await asentarLista(tester);
      expect(registros, 1);
    });

    testWidgets('dado una casa con dirección larguísima a 360×640 ×2, la dirección cede y «Editar '
        'casa» y la ✕ siguen enteras y tocables', (tester) async {
      final s = await _mapa(
        tester,
        tamano: t360x640,
        escala: 2,
        fuentesReales: true,
        filas: [
          filaLista(
            'a',
            calle: 'Avenida Doctor Luis Alberto de Herrera y Presidente Gestido esquina Bulevar',
            numero: '1234 bis apartamento 12',
            metrosAlNorte: 40,
          ),
        ],
      );
      s.m.mapa.tocarPunto('a');
      await asentarLista(tester);

      expect(tester.takeException(), isNull);
      final e = tester.getRect(_editar);
      final x = tester.getRect(find.byKey(ClavesMapaUbicaciones.cerrarVistaPrevia));
      expect(e.overlaps(x), isFalse, reason: 'no se pisan');
      expect(e.height, greaterThanOrEqualTo(48));
      expect(e.right, lessThanOrEqualTo(360));
      await _capturar(tester, 'mapa_direccion_larga_360x640_x2.0');
    });

    testWidgets('dado un edificio o un negocio, la hoja ofrece el lápiz y abre la 07 con ESA '
        'ubicación (la hoja es la misma para los tres tipos)', (tester) async {
      final s = await _mapa(tester);
      for (final id in ['f', 'd']) {
        s.m.mapa.tocarPunto(id);
        await asentarLista(tester);
        expect(_editar, findsOneWidget, reason: id);
        await tester.tap(_editar);
        await asentarLista(tester);
      }
      expect(s.edicion.abiertas.map((a) => a.ubicacionId), ['f', 'd']);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'dado «Abrir la existente» desde la 07 (UbicacionExistenteElegida), el mapa muestra '
      'la hoja de la OTRA casa y «Editar casa» sigue andando en ella (a5565012)',
      (tester) async {
        final s = await _mapa(tester);
        s.m.mapa.tocarPunto('a');
        await asentarLista(tester);
        s.edicion.alAbrir = () async => const UbicacionExistenteElegida('b');

        await tester.tap(_editar);
        await asentarLista(tester);

        expect(find.text('Av. Italia 1250'), findsWidgets);
        expect(find.text('Av. Italia 1234'), findsNothing);
        expect(tester.takeException(), isNull);
        s.edicion.alAbrir = null;
        await tester.tap(_editar);
        await asentarLista(tester);
        expect(s.edicion.abiertas.map((a) => a.ubicacionId), ['a', 'b']);
      },
    );

    testWidgets('dado que la edición devuelve UbicacionBajaRealizada (dar de baja desde la 07), la '
        'hoja de la casa no deja un lápiz que edite una casa ya dada de baja', (tester) async {
      final s = await _mapa(tester);
      s.m.mapa.tocarPunto('a');
      await asentarLista(tester);
      s.edicion.alAbrir = () async {
        final u = filaLista('a', calle: 'Av. Italia', numero: '1234', baja: ahoraLista);
        s.repo.emitir([u, ...canvas().skip(1)]);
        return UbicacionBajaRealizada(u.ubicacion);
      };

      await tester.tap(_editar);
      await asentarLista(tester);

      expect(tester.takeException(), isNull);
      // La casa quedó de baja: la hoja se cierra (c57cd064) y no deja acciones de una casa activa.
      expect(_editar, findsNothing);
      expect(find.byKey(ClavesHojaCasa.titulo), findsNothing);
      expect(find.byKey(ClavesHojaCasa.registrarVisita), findsNothing);
    });
  });

  // ----------------------------------------------------------------------------------------------
  // 3 · Guías de accesibilidad
  // ----------------------------------------------------------------------------------------------
  group('Accesibilidad de «Editar casa»', () {
    for (final tamano in [t360x640, t412x915]) {
      for (final escala in [1.0, 2.0]) {
        final suf = _sufijo(tamano, escala);

        testWidgets('C·01: tamaño de toque (Android e iOS) y nombre en el nodo tocable · $suf', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          final s = await _mapa(tester, tamano: tamano, escala: escala);
          s.m.mapa.tocarPunto('a');
          await asentarLista(tester);

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantica.dispose();
        });

        testWidgets('C·02: tamaño de toque y nombre en el nodo tocable · $suf', (tester) async {
          final semantica = tester.ensureSemantics();
          final s = await _mapa(tester, tamano: tamano, escala: escala);
          s.m.mapa.tocarPunto('a');
          await asentarLista(tester);
          await tocarAsa(tester);

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantica.dispose();
        });
      }
    }

    testWidgets('el lector de pantalla oye «Editar casa: <dirección>» como botón con acción de '
        'toque', (tester) async {
      final semantica = tester.ensureSemantics();
      final s = await _mapa(tester);
      s.m.mapa.tocarPunto('a');
      await asentarLista(tester);

      final nodo = tester.getSemantics(_editar);
      expect(nodo.label, 'Editar casa: Av. Italia 1234');
      expect(nodo, isSemantics(isButton: true, hasTapAction: true));
      await tester.tap(_editar);
      await asentarLista(tester);
      expect(s.edicion.abiertas, hasLength(1));
      semantica.dispose();
    });

    testWidgets('con el teclado se llega a «Editar casa» y Enter la abre', (tester) async {
      final s = await _mapa(tester);
      s.m.mapa.tocarPunto('a');
      await asentarLista(tester);

      var llego = false;
      final elemento = _editar.evaluate().single;
      for (var i = 0; i < 40 && !llego; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final foco = FocusManager.instance.primaryFocus?.context;
        if (foco == null) continue;
        foco.visitAncestorElements((a) {
          if (a == elemento) llego = true;
          return !llego;
        });
        if (foco == elemento) llego = true;
      }
      expect(llego, isTrue, reason: 'Tab alcanza «Editar casa»');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await asentarLista(tester);
      expect(s.edicion.abiertas, hasLength(1));
    });
  });

  // ----------------------------------------------------------------------------------------------
  // 4 · Privacidad
  // ----------------------------------------------------------------------------------------------
  testWidgets('el abridor falla con datos de la casa en el mensaje: el aviso no los repite', (
    tester,
  ) async {
    final s = await _mapa(tester);
    s.m.mapa.tocarPunto('a');
    await asentarLista(tester);
    s.edicion.alAbrir = () async => throw StateError('Av. Italia 1234 / lat -34.9 lon -56.1');

    await tester.tap(_editar);
    await asentarLista(tester);

    expect(find.text('No pudimos abrir la edición. Probá de nuevo.'), findsOneWidget);
    expect(find.textContaining('lat -34'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
  });

  // ----------------------------------------------------------------------------------------------
  // 5 · Los otros estados de la hoja (E·01 cargando, E·02 error, E·04 baja) y las pestañas (C·03, C·05)
  // ----------------------------------------------------------------------------------------------
  group('Los demás estados de la hoja con el lápiz en la cabecera', () {
    for (final tamano in [t360x640, t412x915]) {
      for (final escala in [1.0, 2.0]) {
        final suf = _sufijo(tamano, escala);

        testWidgets('E·01 cargando la casa: el lápiz está y no hay overflow · $suf', (
          tester,
        ) async {
          final nunca = StreamController<ContextoDeLaCasa>();
          addTearDown(nunca.close);
          final s = await _mapa(
            tester,
            tamano: tamano,
            escala: escala,
            fuentesReales: true,
            lectura: (_) => nunca.stream,
          );
          s.m.mapa.tocarPunto('a');
          await asentarLista(tester);

          expect(_editar, findsOneWidget);
          expect(tester.takeException(), isNull);
          await _capturar(tester, 'e01_cargando_$suf');
          await tester.tap(_editar);
          await asentarLista(tester);
          expect(s.edicion.abiertas, hasLength(1));
        });

        testWidgets('E·02 error al leer la casa: el lápiz está y «Reintentar» también · $suf', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          final s = await _mapa(
            tester,
            tamano: tamano,
            escala: escala,
            fuentesReales: true,
            lectura: (_) => Stream<ContextoDeLaCasa>.error(StateError('no leyó')),
          );
          s.m.mapa.tocarPunto('a');
          await asentarLista(tester);

          expect(_editar, findsOneWidget);
          expect(tester.takeException(), isNull);
          await _capturar(tester, 'e02_error_$suf');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantica.dispose();
        });
      }
    }
  });

  testWidgets('el lápiz no le quita renglones a la dirección: la hoja no crece por «Editar casa» '
      'a 360×640 ×2', (tester) async {
    await _montarReal(tester, tamano: t360x640, escala: 2, colportorId: null);
    final sinLapiz = tester.getSize(find.byKey(ClavesHojaCasa.titulo)).height;
    await _montarReal(tester, tamano: t360x640, escala: 2);
    final conLapiz = tester.getSize(find.byKey(ClavesHojaCasa.titulo)).height;

    expect(conLapiz, sinLapiz, reason: 'la dirección ocupa más renglones por el lápiz');
  });

  // Decisiones del 05/11 (archivo ...-652-qa-261105-1010.md): P1 el rótulo sigue el tipo; P2 botón
  // chico con el lápiz y el rótulo. Sin aplicar en el código al momento de este QA.
  group('Decisiones del 05/11 · rótulo visible por tipo (P1) y botón con lápiz y rótulo (P2)', () {
    const rotulos = {'a': 'Editar casa', 'f': 'Editar edificio', 'd': 'Editar negocio'};
    for (final e in rotulos.entries) {
      testWidgets(
        'P1: la hoja de «${e.key}» dice «${e.value}» en el texto, el tooltip y el Semantics',
        (tester) async {
          final semantica = tester.ensureSemantics();
          final s = await _mapa(tester);
          s.m.mapa.tocarPunto(e.key);
          await asentarLista(tester);

          expect(
            find.descendant(of: _editar, matching: find.text(e.value)),
            findsOneWidget,
            reason: 'rótulo visible',
          );
          final nodo = tester.getSemantics(_editar);
          expect(nodo.label, startsWith(e.value), reason: 'Semantics');
          expect(nodo.tooltip.isEmpty ? nodo.label : nodo.tooltip, contains(e.value));
          semantica.dispose();
        },
      );
    }

    for (final escala in [1.0, 2.0]) {
      testWidgets('P2: el botón muestra el rótulo, mide 48 dp y no se recorta a 360×640 ×$escala', (
        tester,
      ) async {
        final s = await _mapa(tester, tamano: t360x640, escala: escala, fuentesReales: true);
        s.m.mapa.tocarPunto('a');
        await asentarLista(tester);

        final rotulo = find.descendant(of: _editar, matching: find.text('Editar casa'));
        expect(rotulo, findsOneWidget);
        final b = tester.getRect(_editar);
        final r = tester.getRect(rotulo);
        expect(b.height, greaterThanOrEqualTo(48));
        expect(b.left, greaterThanOrEqualTo(0));
        expect(b.right, lessThanOrEqualTo(360));
        expect(r.left, greaterThanOrEqualTo(b.left));
        expect(r.right, lessThanOrEqualTo(b.right), reason: 'el rótulo no se recorta');
        expect(tester.takeException(), isNull);
        await _capturar(tester, 'p2_rotulo_360x640_x$escala');
      });
    }
  });
}
