// QA de #314 / PR #328 (vista 07 «Modificar ubicación», HU-UBI-004): la hoja sigue sola la cuenta de
// espacios mientras está abierta. Lo que agrega a los tests del PR:
//
//   * las cuatro guías de accesibilidad de Flutter y el desborde, en los estados que la cuenta mueve
//     (la línea del 3B, el aviso de bloqueo que aparece solo, «Sin espacios») y en los cuatro artboards
//     del canvas, en 360×640 y 412×915 con el texto al 100 % y al 200 %;
//   * el texto literal de la HU con tres espacios;
//   * que un cambio de la cuenta no cuenta como cambio del colportor (la pregunta de descartar);
//   * el foco y lo tipeado cuando el aviso aparece solo, con el teclado abierto;
//   * el vaivén de la cuenta, el cambio con «Mover el punto» abierto y la reapertura («Abrir de
//     nuevo»), que no dejan la hoja sorda.
//
// Las guías van sin las fuentes reales a propósito (con la letra real `textContrastGuideline` da falsos
// negativos por el antialias). Las capturas (`--dart-define=QA_CAPTURAS=true`) sí las cargan y salen en
// `.dart_tool/qa_capturas/` (gitignored).
import 'dart:io';
import 'dart:math' show min;
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart'
    show AvisoAlta;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';

const _capturas = bool.fromEnvironment('QA_CAPTURAS');

const _telefonoChico = Size(360, 640);
const _telefonoGrande = Size(412, 915);
const _tecladoAbierto = 300.0;

const _avisoDos = 'Esta ubicación tiene 2 espacios. Borralos o reubicalos primero.';
const _avisoTres = 'Esta ubicación tiene 3 espacios. Borralos o reubicalos primero.';
const _lineaCasa = 'El departamento 3B queda como el espacio de la casa, sin número.';
const _lineaNegocio = 'El departamento 3B queda como el espacio del negocio, sin número.';

final _raiz = GlobalKey();

class _Anfitrion extends StatelessWidget {
  const _Anfitrion(this.salidas);

  final List<SalidaModificarUbicacion?> salidas;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async => salidas.add(
          await ModificarUbicacionPage.abrir(context, colportorId: 'col-1', ubicacionId: 'ubi-1'),
        ),
        child: const Text('abrir'),
      ),
    ),
  );
}

final class _Montada {
  _Montada(this.repo, this.mapa, this.salidas);

  final RepoEdicionFalso repo;
  final FabricaMapaFalsa mapa;
  final List<SalidaModificarUbicacion?> salidas;
}

Future<void> _asentar(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Un edificio con un único departamento «3B» (la ubicación de S17 que más se mueve).
RepoEdicionFalso _edificioConUnDepto({TipoUbicacion tipo = TipoUbicacion.edificio}) =>
    RepoEdicionFalso(ubicacionGuardada(tipo: tipo), espacios: 1, numeroDepto: '3B');

Future<_Montada> _abrir(
  WidgetTester tester, {
  RepoEdicionFalso? repo,
  Size tamano = _telefonoChico,
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24);
  addTearDown(tester.view.reset);
  final m = _Montada(repo ?? _edificioConUnDepto(), FabricaMapaFalsa(), []);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesAlta(
        gps: GpsFalso(),
        geocodificador: GeocodificadorFalso(
          (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1250'),
        ),
        ciudades: CiudadesFalsas(),
        repo: m.repo,
        ahora: DateTime.utc(2026, 10, 2, 12),
        mapa: m.mapa,
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => RepaintBoundary(
          key: _raiz,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
        ),
        home: _Anfitrion(m.salidas),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await _asentar(tester);
  return m;
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.pump();
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _asentar(tester);
}

Finder get _guardar => find.widgetWithText(FilledButton, TextosModificar.guardarCambios);
Finder get _campoNumero => find.byType(TextField).at(1);
Finder get _cerrar => find.byTooltip('Cerrar');

/// El campo del número tiene el foco.
bool _foco(WidgetTester tester) => tester
    .widget<EditableText>(find.descendant(of: _campoNumero, matching: find.byType(EditableText)))
    .focusNode
    .hasFocus;

bool _habilitado(WidgetTester tester) => tester.widget<FilledButton>(_guardar).onPressed != null;

/// Teclado de [alto] dp (0 = cerrado), como lo entrega el sistema.
Future<void> _teclado(WidgetTester tester, double alto) async {
  if (alto > 0) {
    tester.view.viewInsets = const FakeViewPadding(bottom: _tecladoAbierto);
  } else {
    tester.view.resetViewInsets();
  }
  await _asentar(tester);
}

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

Future<void> _cargarFuentesEIconos(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final bytes = iconos.readAsBytesSync();
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await cargador.load();
        break;
      }
    }
  });
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_capturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/328_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

String _nombre(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_${e}x';

void main() {
  final matriz = <(Size, double)>[
    (_telefonoChico, 1),
    (_telefonoChico, 2),
    (_telefonoGrande, 1),
    (_telefonoGrande, 2),
  ];

  group('QA #328 · cobertura del canvas 07 y de los estados de la cuenta: guías y desborde', () {
    for (final (tamano, escala) in matriz) {
      final etiqueta = '${tamano.width.toInt()}×${tamano.height.toInt()} · texto ${escala}x';

      testWidgets('07·01 con la línea del depto 3B (Casa elegida, 1 espacio) · $etiqueta', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _abrir(tester, tamano: tamano, escala: escala);
        await _tocar(tester, find.text('Casa'));

        expect(find.text(_lineaCasa), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _guias(tester);
        handle.dispose();
      });

      testWidgets('07·01 con el aviso de bloqueo que aparece solo (2 espacios) · $etiqueta', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final m = await _abrir(tester, tamano: tamano, escala: escala);
        await _tocar(tester, find.text('Casa'));
        m.repo.cambiarEspacios(2);
        await _asentar(tester);

        expect(find.text(_avisoDos), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _guias(tester);
        handle.dispose();
      });

      testWidgets('07·01 «Sin espacios» (el último depto se dio de baja) · $etiqueta', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final m = await _abrir(tester, tamano: tamano, escala: escala);
        await _tocar(tester, find.text('Casa'));
        m.repo.cambiarEspacios(0);
        await _asentar(tester);

        expect(find.textContaining('Sin espacios'), findsOneWidget);
        expect(find.textContaining('Borralos'), findsNothing);
        expect(find.textContaining('queda como el espacio'), findsNothing);
        expect(tester.takeException(), isNull);
        await _guias(tester);
        handle.dispose();
      });

      testWidgets('07·02 «Mover el punto» · $etiqueta', (tester) async {
        final handle = tester.ensureSemantics();
        await _abrir(tester, tamano: tamano, escala: escala);
        await _tocar(tester, find.text('Mover el punto'));

        expect(find.text('Guardar posición'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _guias(tester);
        handle.dispose();
      });

      testWidgets('07·04 «¿Descartar los cambios?» · $etiqueta', (tester) async {
        final handle = tester.ensureSemantics();
        await _abrir(tester, tamano: tamano, escala: escala);
        await _tocar(tester, find.text('Negocio'));
        await _tocar(tester, _cerrar);

        expect(find.text('¿Descartar los cambios?'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _guias(tester);
        handle.dispose();
      });
    }
  });

  group('QA #328 · textos literales de la HU y de la decisión del 07/10', () {
    testWidgets('con tres espacios el aviso es el de la HU con N = 3 y el resumen dice 3', (
      tester,
    ) async {
      final m = await _abrir(tester);
      await _tocar(tester, find.text('Casa'));

      m.repo.cambiarEspacios(3);
      await _asentar(tester);

      expect(find.text(_avisoTres), findsOneWidget);
      expect(find.textContaining('Edificio · 3 espacios'), findsOneWidget);
      expect(_habilitado(tester), isFalse);
    });

    testWidgets('la línea del depto dice «de la casa» con Casa y «del negocio» con Negocio, y '
        'sigue al número que cambia con la hoja abierta', (tester) async {
      final m = await _abrir(tester);
      await _tocar(tester, find.text('Casa'));
      expect(find.text(_lineaCasa), findsOneWidget);

      await _tocar(tester, find.text('Negocio'));
      expect(find.text(_lineaNegocio), findsOneWidget);

      m.repo.cambiarEspacios(1, numeroDepto: '4C');
      await _asentar(tester);
      expect(
        find.text('El departamento 4C queda como el espacio del negocio, sin número.'),
        findsOneWidget,
      );
      expect(find.text(_lineaNegocio), findsNothing);

      m.repo.cambiarEspacios(1);
      await _asentar(tester);
      expect(
        find.textContaining('queda como el espacio'),
        findsNothing,
        reason: 'el depto perdió su número: no hay nada que decir',
      );
      expect(_habilitado(tester), isTrue);
    });

    testWidgets('el resumen cuenta 1 en singular y 0 como «Sin espacios» mientras la hoja sigue la '
        'cuenta', (tester) async {
      final m = await _abrir(tester);
      expect(find.textContaining('Edificio · 1 espacio ·'), findsOneWidget);

      m.repo.cambiarEspacios(0);
      await _asentar(tester);
      expect(find.textContaining('Edificio · Sin espacios ·'), findsOneWidget);

      m.repo.cambiarEspacios(1, numeroDepto: '3B');
      await _asentar(tester);
      expect(find.textContaining('Edificio · 1 espacio ·'), findsOneWidget);
    });
  });

  group('QA #328 · un cambio de la cuenta no es un cambio del colportor', () {
    testWidgets('sin tocar nada, que llegue un depto no hace preguntar al salir', (tester) async {
      final m = await _abrir(tester);
      m.repo.cambiarEspacios(2);
      await _asentar(tester);

      await _tocar(tester, _cerrar);

      expect(find.text('¿Descartar los cambios?'), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
      expect(m.salidas, hasLength(1));
      expect(m.repo.cancelaciones, m.repo.suscripciones);
    });

    testWidgets('con el número cambiado, la pregunta de descartar lista solo lo que cambió el '
        'colportor, no la cuenta', (tester) async {
      final m = await _abrir(tester);
      await tester.enterText(_campoNumero, '1238');
      await tester.pump();
      m.repo.cambiarEspacios(2);
      await _asentar(tester);

      await _tocar(tester, _cerrar);

      expect(find.text('Cambiaste el número. Si salís ahora, se pierden.'), findsOneWidget);
    });
  });

  group('QA #328 · foco y teclado cuando el aviso aparece solo', () {
    testWidgets(
      'escribiendo el número con el teclado abierto llega el 2.º depto: el texto, el foco y '
      'el teclado siguen, y el aviso se anuncia',
      (tester) async {
        final handle = tester.ensureSemantics();
        if (_capturas) await _cargarFuentesEIconos(tester);
        final m = await _abrir(tester);
        await _tocar(tester, find.text('Casa'));
        await _tocar(tester, _campoNumero);
        await tester.enterText(_campoNumero, '1238');
        await _teclado(tester, _tecladoAbierto);
        expect(_foco(tester), isTrue, reason: 'el campo tiene el foco antes del aviso');

        m.repo.cambiarEspacios(2);
        await _asentar(tester);

        expect(tester.takeException(), isNull);
        expect(find.text(_avisoDos), findsOneWidget);
        expect(tester.widget<TextField>(_campoNumero).controller!.text, '1238');
        expect(_foco(tester), isTrue, reason: 'el aviso no le saca el foco al campo');
        expect(tester.testTextInput.isVisible, isTrue, reason: 'el aviso no baja el teclado');
        expect(
          find.ancestor(
            of: find.text(_avisoDos),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.liveRegion == true,
            ),
          ),
          findsWidgets,
        );
        await _capturar(tester, 'teclado_aviso_solo');
        m.repo.cambiarEspacios(1);
        await _asentar(tester);
        await _capturar(tester, 'teclado_aviso_se_va');
        handle.dispose();
      },
    );

    // Con la letra de prueba (cada letra mide un cuadrado) el aviso es más alto que lo que se desplaza
    // con el teclado abierto: se mide la tarjeta entera, y si no entra se la empieza a leer desde arriba.
    testWidgets(
      'con el teclado abierto en 360×640 el aviso que llega solo se ve, no queda arriba de lo que se desplaza',
      (tester) async {
        final m = await _abrir(tester);
        await _tocar(tester, find.text('Casa'));
        await _tocar(tester, _campoNumero);
        await tester.enterText(_campoNumero, '1238');
        await _teclado(tester, _tecladoAbierto);

        m.repo.cambiarEspacios(2);
        await _asentar(tester);

        final aviso = tester.getRect(
          find.ancestor(of: find.text(_avisoDos), matching: find.byType(AvisoAlta)).first,
        );
        final zona = tester.getRect(
          find
              .ancestor(of: find.text(_avisoDos), matching: find.byType(SingleChildScrollView))
              .first,
        );
        final visible =
            aviso.bottom.clamp(zona.top, zona.bottom) - aviso.top.clamp(zona.top, zona.bottom);
        expect(
          visible,
          greaterThanOrEqualTo(min(aviso.height, zona.height) - 1),
          reason: 'aviso $aviso fuera del área que se desplaza $zona',
        );
      },
    );

    testWidgets('con el texto al 200 % y el teclado abierto el aviso que llega solo no desborda', (
      tester,
    ) async {
      final m = await _abrir(tester, escala: 2);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _campoNumero);
      await _teclado(tester, _tecladoAbierto);
      final antes = tester.takeException();

      m.repo.cambiarEspacios(2);
      await _asentar(tester);

      final despues = tester.takeException();
      expect(
        despues?.toString().contains('overflowed') ?? false,
        antes?.toString().contains('overflowed') ?? false,
        reason: 'el aviso que llega solo no agrega un desborde que no estaba: $despues',
      );
    });
  });

  group('QA #328 · casos límite de la cuenta', () {
    testWidgets('vaivén 1→2→1→2→1 sin esperar entre cambios: la hoja queda con la cuenta de ahora, '
        'sin aviso viejo, con el borrador intacto y guarda', (tester) async {
      final m = await _abrir(tester);
      await _tocar(tester, find.text('Casa'));
      await tester.enterText(_campoNumero, '1238');
      await tester.pump();

      m.repo
        ..cambiarEspacios(2)
        ..cambiarEspacios(1, numeroDepto: '3B')
        ..cambiarEspacios(2)
        ..cambiarEspacios(1, numeroDepto: '3B');
      await _asentar(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(_avisoDos), findsNothing);
      expect(find.text(_lineaCasa), findsOneWidget);
      expect(tester.widget<TextField>(_campoNumero).controller!.text, '1238');
      expect(_habilitado(tester), isTrue);
      expect(m.repo.suscripciones - m.repo.cancelaciones, 1, reason: 'una sola vigilancia');

      await _tocar(tester, _guardar);

      expect(m.repo.escrituras, hasLength(1));
      expect(m.repo.escrituras.single.nueva.tipo, TipoUbicacion.casa);
      expect(m.repo.escrituras.single.nueva.numero, '1238');
      expect(m.salidas.single, isNotNull);
    });

    testWidgets('«Mover el punto» abierto cuando llega el 2.º depto: al cancelar vuelve la edición '
        'con el aviso y el botón sin efecto', (tester) async {
      final m = await _abrir(tester);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, find.text('Mover el punto'));

      m.repo.cambiarEspacios(2);
      await _asentar(tester);
      await _tocar(tester, find.text('Cancelar'));

      expect(tester.takeException(), isNull);
      expect(find.text('Guardar cambios'), findsOneWidget);
      expect(find.text(_avisoDos), findsOneWidget);
      expect(_habilitado(tester), isFalse);
    });

    testWidgets(
      '«Abrir de nuevo» tras un cambio concurrente: la hoja nueva sigue la cuenta (una sola '
      'vigilancia, sin dejar la vieja)',
      (tester) async {
        final m = await _abrir(tester);
        await tester.enterText(_campoNumero, '1238');
        await tester.pump();
        m.repo.actual = ubicacionGuardada(
          tipo: TipoUbicacion.edificio,
          actualizada: DateTime.utc(2026, 10, 1, 9),
        );
        await _tocar(tester, _guardar);
        expect(find.textContaining('cambió mientras la editabas'), findsOneWidget);

        await _tocar(tester, find.text('Abrir de nuevo'));
        expect(m.repo.suscripciones - m.repo.cancelaciones, 1, reason: 'no quedan dos vigilancias');

        await _tocar(tester, find.text('Casa'));
        m.repo.cambiarEspacios(2);
        await _asentar(tester);

        expect(tester.takeException(), isNull);
        expect(find.text(_avisoDos), findsOneWidget, reason: 'la hoja reabierta no quedó sorda');
      },
    );

    testWidgets('la cuenta llega a 120 con el texto al 200 % en el teléfono chico: el aviso se ve '
        'entero encima del botón y las guías pasan', (tester) async {
      final handle = tester.ensureSemantics();
      final m = await _abrir(tester, escala: 2);
      await _tocar(tester, find.text('Negocio'));

      m.repo.cambiarEspacios(120);
      await _asentar(tester);

      final aviso = find.text('Esta ubicación tiene 120 espacios. Borralos o reubicalos primero.');
      expect(aviso, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(aviso).bottom, lessThanOrEqualTo(tester.getRect(_guardar).top));
      await _guias(tester);
      handle.dispose();
    });
  });

  group('QA #328 · capturas de cada estado (solo con QA_CAPTURAS=true)', () {
    for (final (tamano, escala) in matriz) {
      testWidgets('capturas ${_nombre(tamano, escala)}', (tester) async {
        if (!_capturas) return;
        await _cargarFuentesEIconos(tester);
        final m = await _abrir(tester, tamano: tamano, escala: escala);
        final n = _nombre(tamano, escala);
        await _capturar(tester, '${n}_01_edificio_un_depto');

        await _tocar(tester, find.text('Casa'));
        await _capturar(tester, '${n}_02_casa_linea_3B');

        m.repo.cambiarEspacios(2);
        await _asentar(tester);
        await _capturar(tester, '${n}_03_aviso_dos_espacios');

        m.repo.cambiarEspacios(0);
        await _asentar(tester);
        await _capturar(tester, '${n}_04_sin_espacios');

        m.repo.cambiarEspacios(120);
        await _asentar(tester);
        await _capturar(tester, '${n}_05_ciento_veinte');

        m.repo.cambiarEspacios(1, numeroDepto: '3B');
        await _asentar(tester);
        await _tocar(tester, find.text('Mover el punto'));
        await _capturar(tester, '${n}_06_mover_el_punto');
        await _tocar(tester, find.text('Cancelar'));

        await _tocar(tester, _cerrar);
        await _capturar(tester, '${n}_07_descartar');
      });
    }
  });
}
