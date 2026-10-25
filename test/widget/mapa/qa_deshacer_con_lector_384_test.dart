// QA de «Deshacer» con lector de pantalla (HU-UBI-006, vista 10·03; issue #384, PR #470; decisión de
// Cristian 21/10, «Deshacer AA»). Complementa `deshacer_con_lector_384_test.dart` (los escenarios y los
// casos límite del implementador) con lo que ese archivo no mide:
//
// - la matriz 360×640 y 412×915 × texto 1,0 y 2,0 con el lector encendido: aviso con «Deshacer» a la
//   vista, sin overflow, tamaños de toque, etiquetas, contraste del aviso y capturas;
// - la semántica del aviso para el lector (acción `dismiss`, anuncio, «Deshacer» con acción de toque);
// - que un aviso que ya no se va solo no tape lo que la persona tiene que tocar (la última tarjeta);
// - que un aviso que ya no se va solo no deje sin lugar a los avisos de otras pantallas;
// - el lector que se apaga o se enciende con la unión esperando, la cuenta restringida a mitad de la
//   espera, dos descartes seguidos, la reentrada a la pantalla y varios pares;
// - privacidad (`toString()` de la unión pendiente).
//
// Capturas: `flutter test --dart-define=QA_CAPTURAS=true …` las deja en `.dart_tool/qa_capturas/`
// (gitignored: nunca se commitean). Un test que documenta un hallazgo va con `skip` y el comentario
// `// skip: issue #384 — <motivo>`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/uniones_pendientes_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart'
    show ColoresLista;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/duplicados_falsos.dart';
import '../../helpers/qa_vista10_arnes.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Los tests con `skip` documentan un hallazgo: `--dart-define=QA_HALLAZGOS=true` los corre.
const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

const _ocho = Duration(seconds: 8);
const _parItalia = 'ub-a|ub-b';
const _parArtigas = 'ub-c|ub-d';

/// Av. Italia 1234 (A–B, a 12 m) y Bulevar Artigas 880 (C–D, a 150 m), a 1 km uno del otro.
DuplicadosEnMemoria _datos() {
  final vieja = DateTime.utc(2026, 8, 1, 10);
  final nueva = DateTime.utc(2026, 8, 5, 10);
  return DuplicadosEnMemoria()
    ..agregar(ubicacionDuplicable('ub-a', creada: vieja), espacios: 2)
    ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 12, creada: nueva))
    ..agregar(
      ubicacionDuplicable(
        'ub-c',
        metrosAlNorte: 1000,
        calle: 'Bulevar Artigas',
        numero: '880',
        creada: vieja,
      ),
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-d',
        metrosAlNorte: 1150,
        calle: 'Bulevar Artigas',
        numero: '880',
        creada: nueva,
      ),
    );
}

/// [n] pares de ubicaciones (`p0-a|p0-b`, `p1-a|p1-b`…), cada uno en su calle y a 1 km del anterior.
DuplicadosEnMemoria _datosMuchos(int n) {
  final datos = DuplicadosEnMemoria();
  final vieja = DateTime.utc(2026, 8, 1, 10);
  final nueva = DateTime.utc(2026, 8, 5, 10);
  for (var i = 0; i < n; i++) {
    datos
      ..agregar(
        ubicacionDuplicable(
          'p$i-a',
          metrosAlNorte: 1000.0 * i,
          calle: 'Calle $i',
          numero: '${100 + i}',
          creada: vieja,
        ),
      )
      ..agregar(
        ubicacionDuplicable(
          'p$i-b',
          metrosAlNorte: 1000.0 * i + 12,
          calle: 'Calle $i',
          numero: '${100 + i}',
          creada: nueva,
        ),
      );
  }
  return datos;
}

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

class _EstadoControlable extends EstadoCuentaNotifier {
  @override
  Future<EstadoCuenta?> build() async => EstadoCuenta.activa;

  void poner(EstadoCuenta estado) => state = AsyncData(estado);
}

/// Lo que se monta: el lector se enciende y se apaga desde el test.
class _Montaje {
  _Montaje(this.datos, this.lector);

  final DuplicadosEnMemoria datos;
  final ValueNotifier<bool> lector;
}

Future<_Montaje> _montar(
  WidgetTester tester,
  DuplicadosEnMemoria datos, {
  bool lector = true,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool fuentesReales = false,
  bool conCuenta = false,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(datos.cerrar);
  if (fuentesReales) await cargarFuentes208(tester);
  final modoLector = ValueNotifier<bool>(lector);
  addTearDown(modoLector.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesDuplicados(datos, conMapa: true),
        if (conCuenta) estadoCuentaProvider.overrideWith(_EstadoControlable.new),
      ],
      child: RepaintBoundary(
        key: raizCaptura208,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => ValueListenableBuilder<bool>(
            valueListenable: modoLector,
            builder: (context, conLector, _) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(escala), accessibleNavigation: conLector),
              child: child!,
            ),
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
    ),
  );
  if (conCuenta) {
    // Como `_Principal` en la app real: el estado de la cuenta queda escuchado.
    final c = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    final suscripcion = c.listen(estadoCuentaProvider, (_, _) {});
    addTearDown(suscripcion.close);
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('abrir')));
  await _transicion(tester);
  return _Montaje(datos, modoLector);
}

void _prueba(
  String descripcion,
  Future<void> Function(WidgetTester tester) cuerpo, {
  bool skip = false,
}) {
  testWidgets(descripcion, skip: skip, (tester) async {
    final semantica = tester.ensureSemantics();
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    semantica.dispose();
  });
}

final _conservarYUnir = find.byKey(const Key('comparar_conservar_y_unir'));
final _deshacer = find.text('Deshacer');
final _aviso = find.byType(SnackBar);
Finder _revisar(String clave) => find.byKey(Key('revisar_$clave'));

Future<void> _tocar(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _asentar(tester);
}

/// Abre la hoja del par [clave] y toca «Conservar A y unir».
Future<void> _unir(WidgetTester tester, String clave) async {
  await _tocar(tester, _revisar(clave));
  await _tocar(tester, _conservarYUnir);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _descartarElAviso(WidgetTester tester) async {
  tester.semantics.performAction(
    find.semantics.byAction(SemanticsAction.dismiss).first,
    SemanticsAction.dismiss,
  );
  await _transicion(tester);
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raizCaptura208));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/384qa_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<List<String>> _guias(WidgetTester tester) async {
  final fallas = <String>[];
  Future<void> probar(String nombre, AccessibilityGuideline guia) async {
    try {
      await expectLater(tester, meetsGuideline(guia));
    } on TestFailure catch (e) {
      fallas.add('$nombre: ${e.message}');
    }
  }

  await probar('android 48dp', androidTapTargetGuideline);
  await probar('ios 44dp', iOSTapTargetGuideline);
  await probar('etiquetas', labeledTapTargetGuideline);
  return fallas;
}

void main() {
  group('Matriz con lector: el aviso pendiente en cada tamaño', () {
    for (final tamano in [telefonoChico208, telefonoGrande208]) {
      for (final escala in [1.0, 2.0]) {
        final celda = '${tamano.width.toInt()}x${tamano.height.toInt()} · texto $escala';

        _prueba('$celda: con el lector el aviso con "Deshacer" entra, sin overflow, con tamaños de '
            'toque, etiquetas y texto dentro de la pantalla', (tester) async {
          final m = await _montar(
            tester,
            _datos(),
            escala: escala,
            tamano: tamano,
            fuentesReales: true,
          );
          await _unir(tester, _parItalia);
          await _asentar(tester);

          expect(tester.takeException(), isNull);
          expect(_aviso, findsOneWidget);
          expect(_deshacer, findsOneWidget);
          expect(m.datos.uniones, isEmpty);
          final pantalla = Offset.zero & tamano;
          final rect = tester.getRect(_aviso);
          expect(
            pantalla.contains(rect.topLeft) &&
                pantalla.contains(rect.bottomRight - const Offset(1, 1)),
            isTrue,
            reason: 'el aviso se sale de la pantalla: $rect',
          );
          expectSinTextoFueraDeLosCostados208(tester, tamano);
          // "Deshacer" ocupa un toque de 48 dp como mínimo, a la vista.
          final d = tester.getRect(_deshacer);
          expect(
            pantalla.contains(d.topLeft) && pantalla.contains(d.bottomRight - const Offset(1, 1)),
            isTrue,
            reason: '"Deshacer" a la vista: $d',
          );
          expect(await _guias(tester), isEmpty);
          await _capturar(tester, 'aviso_${tamano.width.toInt()}_x$escala');
        });
      }
    }

    _prueba(
      'el aviso de la unión pendiente tiene contraste AA (texto y "Deshacer" sobre la tinta)',
      (tester) async {
        expect(contraste208(Colors.white, ColoresLista.tinta), greaterThanOrEqualTo(4.5));
        expect(
          contraste208(const Color(0xFFC9D6EA), ColoresLista.tinta),
          greaterThanOrEqualTo(4.5),
        );
      },
    );
  });

  group('Sin lector, el aviso de siempre', () {
    _prueba('sin lector el aviso se ve igual que con lector y se va a los 8 s (captura)', (
      tester,
    ) async {
      final m = await _montar(
        tester,
        _datos(),
        lector: false,
        tamano: telefonoChico208,
        fuentesReales: true,
      );
      await _unir(tester, _parItalia);
      await _asentar(tester);
      expect(_deshacer, findsOneWidget);
      await _capturar(tester, 'aviso_sin_lector_360');
      await tester.pump(_ocho);
      await _transicion(tester);
      expect(m.datos.uniones, hasLength(1));
      expect(_aviso, findsNothing);
    });
  });

  group('Semántica para el lector', () {
    _prueba(
      'el aviso se anuncia (liveRegion) y se puede descartar (dismiss); "Deshacer" tiene toque',
      (tester) async {
        await _montar(tester, _datos());
        await _unir(tester, _parItalia);

        final avisoNodo = tester.getSemantics(
          find.descendant(of: _aviso, matching: find.textContaining('quedaron unidas')),
        );
        expect(avisoNodo.label, contains('Las dos Av. Italia 1234 quedaron unidas en una.'));
        // El nodo que acepta `dismiss` es un ancestro del texto.
        expect(find.semantics.byAction(SemanticsAction.dismiss), findsOneWidget);
        expect(find.semantics.byLabel('Deshacer'), findsOneWidget);
        expect(
          find.semantics.byAction(SemanticsAction.tap).evaluate().any((n) => n.label == 'Deshacer'),
          isTrue,
        );
      },
    );

    _prueba('el aviso que se descarta con el lector no deja un nodo "Deshacer" suelto', (
      tester,
    ) async {
      final m = await _montar(tester, _datos());
      await _unir(tester, _parItalia);
      await _descartarElAviso(tester);

      expect(m.datos.uniones, hasLength(1));
      expect(find.semantics.byLabel('Deshacer'), findsNothing);
      expect(find.semantics.byAction(SemanticsAction.dismiss), findsNothing);
    });
  });

  group('Un aviso que no se va solo no tapa lo que hay que tocar', () {
    for (final escala in [1.0, 2.0]) {
      // skip: issue #384 — con lector el aviso queda fijo y tapa el "Revisar" del último par (1,0×: 30 de
      // 52 dp; 2,0×: entero) sin lugar para bajar más: la lista no deja espacio abajo para el aviso.
      _prueba(
        'texto $escala a 360x640: con 5 pares y el aviso pendiente, la última tarjeta y su "Revisar" '
        'se pueden ver y tocar sin descartar el aviso',
        (tester) async {
          final m = await _montar(
            tester,
            _datosMuchos(5),
            escala: escala,
            tamano: telefonoChico208,
            fuentesReales: true,
          );
          await _unir(tester, 'p0-a|p0-b');
          await _asentar(tester);
          expect(m.datos.uniones, isEmpty);
          expect(_aviso, findsOneWidget);

          // Se baja hasta el final de la lista.
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -6000));
          await _asentar(tester);
          await tester.pump(const Duration(seconds: 1));

          final ultimo = _revisar('p4-a|p4-b');
          expect(ultimo, findsOneWidget);
          final boton = tester.getRect(ultimo);
          final aviso = tester.getRect(_aviso);
          await _capturar(tester, 'lista_final_x$escala');
          expect(
            boton.overlaps(aviso) && boton.intersect(aviso).height > 1,
            isFalse,
            reason:
                '"Revisar" del último par $boton queda debajo del aviso $aviso con la lista al final',
          );
        },
        skip: !_verHallazgos,
      );
    }
  });

  group('Un aviso que no se va solo y los avisos de otras pantallas', () {
    // skip: issue #384 — con lector el aviso queda fijo y los avisos de otras pantallas (p. ej. «Guardado
    // sin conexión» de la edición de «Editar uno») esperan en la cola detrás de él, sin verse.
    _prueba('con lector, un aviso que otra pantalla pide mientras la unión espera se ve '
        '(no queda en la cola detrás del aviso que no se va)', (tester) async {
      final m = await _montar(tester, _datos());
      await _unir(tester, _parItalia);
      expect(m.datos.uniones, isEmpty);

      // Una pantalla de arriba (como la edición de «Editar uno») pide su aviso con `showSnackBar`
      // a secas, como `modificar_ubicacion_page.dart` ("Guardado sin conexión…").
      final contexto = tester.element(find.byType(PosiblesDuplicadosPage));
      unawaited(
        Navigator.of(contexto).push<void>(
          MaterialPageRoute(
            builder: (c) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('otra_pide'),
                  onPressed: () => ScaffoldMessenger.of(c).showSnackBar(
                    const SnackBar(content: Text('Guardado sin conexión. Se sube después.')),
                  ),
                  child: const Text('guardar'),
                ),
              ),
            ),
          ),
        ),
      );
      await _transicion(tester);
      await tester.tap(find.byKey(const Key('otra_pide')));
      await _asentar(tester);
      await tester.pump(const Duration(seconds: 6));

      expect(
        find.text('Guardado sin conexión. Se sube después.'),
        findsOneWidget,
        reason: 'el aviso de la otra pantalla espera detrás del "Deshacer" que no se va solo',
      );
    }, skip: !_verHallazgos);
  });

  group('Casos límite', () {
    _prueba('dos descartes seguidos (el mismo cuadro) unen una sola vez', (tester) async {
      final m = await _montar(tester, _datos());
      await _unir(tester, _parItalia);

      final nodo = find.semantics.byAction(SemanticsAction.dismiss).first;
      tester.semantics.performAction(nodo, SemanticsAction.dismiss);
      tester.semantics.performAction(nodo, SemanticsAction.dismiss);
      await _transicion(tester);
      await tester.pump(const Duration(minutes: 1));

      expect(m.datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);
      expect(tester.takeException(), isNull);
    });

    _prueba('"Deshacer" y descartar en el mismo cuadro: gana el primero y no se une dos veces', (
      tester,
    ) async {
      final m = await _montar(tester, _datos());
      await _unir(tester, _parItalia);

      await tester.tap(_deshacer);
      // El nodo de `dismiss` ya no tiene que quedar con una unión que revivir.
      await _transicion(tester);
      await tester.pump(const Duration(minutes: 1));

      expect(m.datos.uniones, isEmpty);
      expect(find.text('2 para revisar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _prueba('unir A, unir B y descartar: A queda definitiva al unir B, B al descartar; en orden y '
        'una vez cada una', (tester) async {
      final m = await _montar(tester, _datos());
      await _unir(tester, _parItalia);
      await _unir(tester, _parArtigas);
      await tester.pump(const Duration(minutes: 1));
      expect(m.datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);

      await _descartarElAviso(tester);
      expect(m.datos.uniones, [
        (conservadaId: 'ub-a', duplicadaId: 'ub-b'),
        (conservadaId: 'ub-c', duplicadaId: 'ub-d'),
      ]);
      await tester.pump(const Duration(minutes: 1));
      expect(m.datos.uniones, hasLength(2));
    });

    _prueba(
      'decidir otro par ("Son distintos") con la unión esperando no la confirma ni la pierde',
      (tester) async {
        final m = await _montar(tester, _datos());
        await _unir(tester, _parItalia);

        await _tocar(tester, _revisar(_parArtigas));
        await _tocar(tester, find.byKey(const Key('comparar_son_distintos')));
        await tester.pump(const Duration(minutes: 1));

        expect(m.datos.decisiones, hasLength(1));
        expect(m.datos.uniones, isEmpty, reason: 'la unión de Italia sigue esperando');
        expect(_deshacer, findsOneWidget);

        await tester.tap(_deshacer);
        await _transicion(tester);
        expect(m.datos.uniones, isEmpty);
        expect(find.text('1 para revisar'), findsOneWidget);
      },
    );

    _prueba('reentrada: unir con lector, descartar, salir y volver a entrar no repite ni resucita '
        'el aviso', (tester) async {
      final m = await _montar(tester, _datos());
      await _unir(tester, _parItalia);
      await _descartarElAviso(tester);
      expect(m.datos.uniones, hasLength(1));

      await tester.tap(find.byKey(const Key('duplicados_volver')));
      await _transicion(tester);
      await tester.tap(find.byKey(const Key('abrir')));
      await _transicion(tester);
      await tester.pump(const Duration(minutes: 1));

      expect(_aviso, findsNothing);
      expect(m.datos.uniones, hasLength(1));
      expect(find.text('1 para revisar'), findsOneWidget);
    });

    _prueba('salir de la pantalla con la unión esperando la hace, y el aviso no se queda en la '
        'pantalla de atrás', (tester) async {
      final m = await _montar(tester, _datos());
      await _unir(tester, _parItalia);

      await tester.tap(find.byKey(const Key('duplicados_volver')));
      await _transicion(tester);

      expect(m.datos.uniones, hasLength(1));
      expect(_aviso, findsNothing);
      expect(_deshacer, findsNothing);
    });

    _prueba('el lector se apaga con la unión esperando: sigue esperando, "Deshacer" anda y '
        'salir la hace', (tester) async {
      final m = await _montar(tester, _datos());
      await _unir(tester, _parItalia);

      m.lector.value = false;
      await _transicion(tester);
      await tester.pump(const Duration(minutes: 1));

      expect(m.datos.uniones, isEmpty, reason: 'no hay reloj: el límite conocido del PR');
      expect(_deshacer, findsOneWidget);
      await tester.tap(_deshacer);
      await _transicion(tester);
      expect(m.datos.uniones, isEmpty);
      expect(find.text('2 para revisar'), findsOneWidget);
    });

    _prueba('el lector se apaga con la unión esperando: la persona tiene una salida y la unión no '
        'se pierde al salir', (tester) async {
      final m = await _montar(tester, _datos());
      await _unir(tester, _parItalia);
      m.lector.value = false;
      await _transicion(tester);

      await tester.tap(find.byKey(const Key('duplicados_volver')));
      await _transicion(tester);

      expect(m.datos.uniones, hasLength(1));
      expect(_aviso, findsNothing);
    });

    _prueba('el lector se enciende después de unir sin él: corren los 8 s y se une una vez', (
      tester,
    ) async {
      final m = await _montar(tester, _datos(), lector: false);
      await _unir(tester, _parItalia);

      m.lector.value = true;
      await _asentar(tester);
      await tester.pump(_ocho);
      await _transicion(tester);
      await tester.pump(const Duration(seconds: 30));

      expect(m.datos.uniones, hasLength(1));
      expect(_aviso, findsNothing);
    });

    _prueba('falla al confirmar al descartar, "Reintentar" corre y no queda nada trabado', (
      tester,
    ) async {
      final m = await _montar(tester, _datos());
      m.datos.falloAlUnir = const FailureInesperado();
      await _unir(tester, _parItalia);
      await _descartarElAviso(tester);

      expect(m.datos.uniones, hasLength(1), reason: 'un intento, que falló');
      expect(find.byKey(const Key('duplicados_falla_union')), findsOneWidget);
      expect(find.text('2 para revisar'), findsOneWidget);

      // Se puede volver a unir el mismo par con el lector: el aviso nuevo espera igual.
      m.datos.falloAlUnir = null;
      await _unir(tester, _parItalia);
      await tester.pump(const Duration(minutes: 1));
      expect(m.datos.uniones, hasLength(1), reason: 'sin reloj no hay otro intento');
      expect(_deshacer, findsOneWidget);
      await _descartarElAviso(tester);
      expect(m.datos.uniones, hasLength(2));
      expect(find.byKey(const Key('duplicados_falla_union')), findsNothing);
    });

    // skip: issue #384 — el aviso del módulo bloqueado (`hideCurrentSnackBar`) cierra el de «Deshacer» y, con
    // lector, eso une la pendiente sin que la persona la haya cerrado.
    _prueba(
      'cuenta restringida a mitad de la espera: tocar "Revisar" no une la pendiente a escondidas',
      (tester) async {
        final m = await _montar(tester, _datos(), conCuenta: true);
        await _unir(tester, _parItalia);
        final c = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
        (c.read(estadoCuentaProvider.notifier) as _EstadoControlable).poner(
          EstadoCuenta.suspendida,
        );
        await tester.pump();

        await _tocar(tester, _revisar(_parArtigas));
        await tester.pump(const Duration(seconds: 1));

        // La pendiente sigue esperando a que la persona la cierre: el aviso del módulo bloqueado no es
        // "cerrar" el aviso de «Deshacer».
        expect(
          m.datos.uniones,
          isEmpty,
          reason: 'el aviso del módulo bloqueado cerró el de "Deshacer"',
        );
      },
      skip: !_verHallazgos,
    );
  });

  group('Privacidad', () {
    // skip: issue #384 — `UnionPendiente` es un `Equatable` sin `stringify => false`: en debug su
    // `toString()` vuelca la dirección y los ids (las demás entidades del mapa lo apagan).
    test(
      skip: !_verHallazgos,
      'el toString de la unión pendiente no vuelca la dirección ni los ids',
      () {
        const union = UnionPendiente(
          clavePar: 'ub-a|ub-b',
          conservarId: 'ub-a',
          duplicadaId: 'ub-b',
          direccion: 'Av. Italia 1234',
          esperaElCierre: true,
        );
        expect(union.toString(), isNot(contains('Italia')));
        expect(union.toString(), isNot(contains('ub-a')));
      },
    );
  });
}
