// QA de #679 (errores hallados al recorrer la app): lo que una persona ve y toca.
//   · «Nueva persona» (32A) pregunta «¿Descartar lo que escribiste?» antes de perder lo escrito
//     (HU-UBI-011, mismo aviso que las notas): matriz de tamaños y casos límite del flujo.
//   · Hoja «¿Cerrar sesión?» (vista 16, HU-AUTH-006): singular/plural y matriz de tamaños.
// Con las fuentes reales del proyecto (sin ellas `flutter_test` pinta cajas Ahem y las medidas de
// layout mienten). Las guías de accesibilidad van en `qa_errores_manual_679_guias_test.dart`.
// Capturas: `--dart-define=QA_CAPTURAS=true` → `.dart_tool/qa_capturas/` (nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/configuracion/presentation/widgets/hoja_cerrar_sesion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

const _chico = Size(360, 640);
const _grande = Size(412, 915);
const _tamanos = [_chico, _grande];
const _escalas = [1.0, 2.0];

const _titulo = '¿Descartar lo que escribiste?';
const _cuerpo = 'Si salís ahora, lo que escribiste no se guarda.';
const _nombre = 'Obligatorio';
const _apellido = 'Apellido';
const _telefono = '09X XXX XXX';
const _nota = 'Lo que te sirva para la próxima visita';
const _fallaAlGuardar = 'No pudimos guardar a la persona. Probá de nuevo.';

var _fuentesCargadas = false;

Future<void> _cargarFuentes(WidgetTester tester) async {
  if (_fuentesCargadas) return;
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
  _fuentesCargadas = true;
}

Future<void> _escribir(WidgetTester tester, String sugerencia, String texto) async {
  await tester.enterText(
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == sugerencia),
    texto,
  );
  await tester.pump();
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final imagen = await capa.toImage(
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('.dart_tool/qa_capturas/679_$nombre.png');
    archivo.parent.createSync(recursive: true);
    archivo.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<ResultadoAlta> _alta(
  WidgetTester tester, {
  PersonaRepositorioFalso? repo,
  Size tamano = _chico,
  double escala = 1,
}) async {
  await _cargarFuentes(tester);
  return montarAlta(tester, repo: repo, tamano: tamano, escala: escala);
}

Finder get _cerrar => find.byTooltip('Cerrar');

Finder get _guardar => find.widgetWithText(FilledButton, 'Guardar persona');

Finder get _reintentar => find.widgetWithText(FilledButton, 'Reintentar');

String _medida(Size t) => '${t.width.toInt()}×${t.height.toInt()}';

void main() {
  group('«Nueva persona» · descartar lo escrito (32A, HU-UBI-011)', () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        testWidgets(
          'dado un nombre escrito a ${_medida(tamano)} con texto ×$escala, cuando toca la ✕, el '
          'aviso se ve entero, sin desborde, con sus dos salidas',
          (tester) async {
            await _alta(tester, tamano: tamano, escala: escala);
            await _escribir(tester, _nombre, 'Ana');

            await tester.tap(_cerrar);
            await asentar(tester);

            expect(tester.takeException(), isNull);
            expect(find.text(_titulo), findsOneWidget);
            expect(find.text(_cuerpo), findsOneWidget);
            expect(find.text('Seguir escribiendo'), findsOneWidget);
            expect(find.text('Descartar'), findsOneWidget);
            await _capturar(tester, 'descartar_${_medida(tamano)}_x$escala');
          },
        );
      }
    }

    testWidgets('dado el aviso abierto con el teclado a medio subir (280 dp) a 360×640 ×2, no '
        'desborda y las dos salidas quedan sobre el teclado', (tester) async {
      await _alta(tester, escala: 2);
      await _escribir(tester, _nombre, 'Ana');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);

      await tester.tap(_cerrar);
      await asentar(tester);

      expect(tester.takeException(), isNull);
      for (final salida in ['Seguir escribiendo', 'Descartar']) {
        final f = find.text(salida);
        expect(f, findsOneWidget);
        expect(tester.getRect(f).bottom, lessThanOrEqualTo(640 - 280 + 0.5));
      }
    });

    testWidgets(
      'dado un guardado que falla, cuando sale con la ✕, lo escrito sigue ahí, pregunta y '
      '«Seguir escribiendo» deja reintentar sin perder nada',
      (tester) async {
        final repo = PersonaRepositorioFalso(
          resultados: [
            const FailureInesperado(causa: 'x'),
            null,
          ],
        );
        final resultado = await _alta(tester, repo: repo);
        await _escribir(tester, _nombre, 'Ana');
        await _escribir(tester, _telefono, '099 123 456');

        await tester.tap(_guardar);
        await asentar(tester);
        expect(find.text(_fallaAlGuardar), findsOneWidget);
        expect(find.text('Ana'), findsOneWidget, reason: 'tras el error lo tipeado no se pierde');
        expect(
          tester.widget<FilledButton>(_reintentar).onPressed,
          isNotNull,
          reason: 'el botón vuelve a habilitarse (A·06 «Reintentar»)',
        );

        await tester.tap(_cerrar);
        await asentar(tester);
        expect(find.text(_titulo), findsOneWidget);
        await tester.tap(find.text('Seguir escribiendo'));
        await asentar(tester);
        expect(find.text('Ana'), findsOneWidget);
        expect(find.text('099 123 456'), findsOneWidget);
        expect(resultado.cierres, 0);

        // El reintento sale bien y vuelve sin volver a preguntar.
        await tester.tap(_reintentar);
        await asentar(tester);
        expect(find.text(_titulo), findsNothing);
        expect(resultado.persona?.nombre, 'Ana');
        expect(repo.recibidas, hasLength(2));
        expect(
          repo.recibidas.first.persona.id,
          repo.recibidas.last.persona.id,
          reason: 'el reintento repite los ids (no duplica a la persona)',
        );
      },
    );

    testWidgets('dado un guardado en curso, cuando toca la ✕ o usa el atrás, no pasa nada: ni '
        'pregunta ni cierra; al terminar vuelve con la persona', (tester) async {
      final compuerta = Completer<void>();
      final repo = PersonaRepositorioFalso(compuerta: compuerta);
      final resultado = await _alta(tester, repo: repo);
      await _escribir(tester, _nombre, 'Ana');

      await tester.tap(_guardar);
      await tester.pump();
      await tester.tap(_cerrar, warnIfMissed: false);
      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(find.text(_titulo), findsNothing);
      expect(resultado.cierres, 0, reason: 'mientras guarda no se sale: el resultado se perdería');
      expect(repo.recibidas, hasLength(1));

      compuerta.complete();
      await asentar(tester);
      expect(resultado.persona?.nombre, 'Ana');
      expect(resultado.cierres, 1);
      expect(find.text(_titulo), findsNothing);
    });

    testWidgets('dado un nombre con emoji y una nota pegada de 20 000 caracteres, cuando sale, '
        'pregunta y «Descartar» cierra sin guardar nada', (tester) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await _alta(tester, repo: repo, escala: 2);
      await _escribir(tester, _nombre, 'Ñandú 🙂 «Ana»');
      await _escribir(tester, _nota, List.filled(20000, 'ñ').join());

      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(_titulo), findsOneWidget);

      await tester.tap(find.text('Descartar'));
      await asentar(tester);

      expect(resultado.cierres, 1);
      expect(resultado.persona, isNull);
      expect(repo.recibidas, isEmpty);
    });

    testWidgets('dado el aviso abierto, cuando toca fuera de él, se cierra el aviso y el '
        'formulario sigue con lo escrito', (tester) async {
      final resultado = await _alta(tester);
      await _escribir(tester, _apellido, 'Pérez');

      await tester.tap(_cerrar);
      await asentar(tester);
      expect(find.text(_titulo), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await asentar(tester);

      expect(find.text(_titulo), findsNothing);
      expect(find.text('Pérez'), findsOneWidget);
      expect(resultado.cierres, 0);
    });

    testWidgets('dado el aviso abierto, cuando usa el atrás del sistema, cierra solo el aviso '
        '(no el formulario)', (tester) async {
      final resultado = await _alta(tester);
      await _escribir(tester, _nombre, 'Ana');

      await tester.tap(_cerrar);
      await asentar(tester);
      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(find.text(_titulo), findsNothing);
      expect(find.text('Ana'), findsOneWidget);
      expect(resultado.cierres, 0);
    });

    testWidgets('dado que descartó, cuando vuelve a abrir «Nueva persona», el formulario está '
        'vacío y la ✕ cierra directo', (tester) async {
      final resultado = await _alta(tester);
      await _escribir(tester, _nombre, 'Ana');
      await tester.tap(_cerrar);
      await asentar(tester);
      await tester.tap(find.text('Descartar'));
      await asentar(tester);
      expect(resultado.cierres, 1);

      await tester.tap(find.text('abrir alta'));
      await asentar(tester);
      expect(find.text('Ana'), findsNothing);
      await tester.tap(_cerrar);
      await asentar(tester);

      expect(find.text(_titulo), findsNothing);
      expect(resultado.cierres, 2);
    });

    testWidgets('dado que escribió, borró y escribió en otro campo, cuando toca la ✕, pregunta (el '
        'estado de «hay cambios» sigue lo que hay en pantalla)', (tester) async {
      await _alta(tester);
      await _escribir(tester, _nombre, 'Ana');
      await _escribir(tester, _nombre, '');
      await _escribir(tester, _telefono, '099');

      await tester.tap(_cerrar);
      await asentar(tester);

      expect(find.text(_titulo), findsOneWidget);
    });

    testWidgets(
      'dado solo espacios y saltos de línea en la nota, cuando toca la ✕, cierra directo',
      (tester) async {
        final resultado = await _alta(tester);
        await _escribir(tester, _nota, '  \n \t  ');

        await tester.tap(_cerrar);
        await asentar(tester);

        expect(find.text(_titulo), findsNothing);
        expect(resultado.cierres, 1);
      },
    );
  });

  group('Hoja «¿Cerrar sesión?» · aviso de pendientes (vista 16, HU-AUTH-006)', () {
    Future<void> abrir(
      WidgetTester tester, {
      required int pendientes,
      Future<bool> Function()? cerrar,
      Size tamano = _chico,
      double escala = 1,
    }) async {
      await _cargarFuentes(tester);
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => mostrarHojaCerrarSesion(
                  context,
                  pendientes: pendientes,
                  cerrar: cerrar ?? () async => true,
                ),
                child: const Text('abrir hoja'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir hoja'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    const una =
        'Tenés 1 operación sin sincronizar. Si cerrás sesión ahora, se subirá cuando vuelvas a '
        'iniciar sesión.';

    testWidgets('dado 1 pendiente, el texto es el literal de la HU en singular', (tester) async {
      await abrir(tester, pendientes: 1);
      expect(find.text(una), findsOneWidget);
      expect(find.text('Cerrar sesión igual'), findsOneWidget);
      expect(find.text('Todo sincronizado'), findsNothing);
    });

    for (final n in [2, 3, 10, 1000]) {
      testWidgets('dado $n pendientes, el texto es el literal de la HU en plural', (tester) async {
        await abrir(tester, pendientes: n);
        expect(
          find.text(
            'Tenés $n operaciones sin sincronizar. Si cerrás sesión ahora, se subirán cuando '
            'vuelvas a iniciar sesión.',
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('dado 0 pendientes, dice «Todo sincronizado» y no avisa de operaciones', (
      tester,
    ) async {
      await abrir(tester, pendientes: 0);
      expect(find.text('Todo sincronizado'), findsOneWidget);
      expect(find.textContaining('Tenés'), findsNothing);
    });

    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        for (final n in [1, 1000]) {
          testWidgets(
            'dado $n pendiente(s) a ${_medida(tamano)} con texto ×$escala, la hoja no desborda '
            'y «Cancelar» y «Cerrar sesión igual» existen',
            (tester) async {
              await abrir(tester, pendientes: n, tamano: tamano, escala: escala);
              expect(tester.takeException(), isNull);
              expect(find.text('Cancelar'), findsOneWidget);
              expect(find.text('Cerrar sesión igual'), findsOneWidget);
              await _capturar(tester, 'cerrar_sesion_${n}_${_medida(tamano)}_x$escala');
            },
          );
        }
      }
    }

    testWidgets('dado un cierre que lanza una excepción, cuando toca «Cerrar sesión igual», '
        'muestra el error con «Reintentar» y el reintento funciona', (tester) async {
      var llamadas = 0;
      await abrir(
        tester,
        pendientes: 1,
        cerrar: () async {
          llamadas++;
          if (llamadas == 1) throw StateError('cierre roto');
          return true;
        },
      );

      await tester.tap(find.text('Cerrar sesión igual'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No pudimos cerrar la sesión. Probá de nuevo.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget, reason: 'el error deja una salida');

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(llamadas, 2);
    });

    testWidgets('dado un cierre lento, cuando toca dos veces «Cerrar sesión igual», cierra una '
        'sola vez y «Cancelar» queda apagado', (tester) async {
      final lento = Completer<bool>();
      var llamadas = 0;
      await abrir(
        tester,
        pendientes: 2,
        cerrar: () {
          llamadas++;
          return lento.future;
        },
      );

      await tester.tap(find.text('Cerrar sesión igual'));
      await tester.pump();
      await tester.tap(find.text('Cerrando sesión'), warnIfMissed: false);
      await tester.pump();

      expect(llamadas, 1);
      final cancelar = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Cancelar'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(cancelar.onPressed, isNull);
      lento.complete(true);
      await tester.pump();
    });
  });
}
