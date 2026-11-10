// QA de #523 (HU-NOT-004, vista 24 · 24B·01): el tramo sin recorrer del control de anticipación pasa
// del `borde` (#E3E7EE, 1,16:1) al `gris` de la paleta (#5B6B82, ~5,2:1 contra la tarjeta).
//
// El PR trae un test por color. Acá se prueba lo que ese cambio puede romper alrededor: que el tramo
// quede PAREJO a lo largo de toda la pista (sin marcas de las 115 divisiones del control), que se
// distinga del tramo recorrido y de la tarjeta en cada valor (5, 30, 60, 90 y 120), que la perilla
// siga a la vista sobre él, que apagado (24B·02 y 24B·04) el control no tome el gris nuevo (sigue
// atenuado: no se confunde con un control activo), que arrastrar no lo cambie y que la pantalla
// entera siga sin overflow ni fallas de tamaño de toque en los 4 tamaños de la matriz.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`
// (ignorado por git). Sin hallazgos: ningún test va con `skip`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/colores_colportaje.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/notificaciones_arnes.dart';
import '../helpers/qa_vista24_153_arnes.dart' show cargarFuentes, conCapturas;

class _SesionFija extends SesionNotifier {
  @override
  Future<Sesion?> build() async => Sesion(
    usuarioId: 'col-1',
    email: 'ana@example.com',
    accessToken: 'jwt',
    expiraEn: DateTime.utc(2030),
  );
}

final _interruptor = find.byKey(const Key('pref_recordatorios_interruptor'));
final _slider = find.byKey(const Key('pref_anticipacion_slider'));
final _valor = find.byKey(const Key('pref_anticipacion_valor'));

const _tamanos = [('360×640', Size(360, 640)), ('412×915', Size(412, 915))];
const _escalas = [1.0, 2.0];

const _gris = Color(0xFF5B6B82);

SemanticsHandle? _handle;

Future<void> _montar(
  WidgetTester tester,
  Telefono t, {
  Size tam = const Size(360, 640),
  double escala = 1,
}) async {
  fijarTamano(tester, tamano: tam, texto: escala);
  await cargarFuentes(tester);
  _handle?.dispose();
  _handle = tester.ensureSemantics();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [...t.overrides, sesionProvider.overrideWith(_SesionFija.new)],
      child: MaterialApp(theme: temaClaro(), home: const NotificacionesPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Telefono _conMinutos(int minutos, {bool activados = true}) =>
    Telefono(estado: EstadoSistemaNotificaciones.activadas)
      ..preferencias.preferencias = PreferenciasRecordatorios(
        activados: activados,
        anticipacionMinutos: minutos,
      );

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa523_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// La fila de píxeles del centro del control, de borde a borde, tal como quedó pintada.
Future<List<Color>> _fila(WidgetTester tester, {double dy = 0}) async {
  await tester.ensureVisible(_slider);
  await tester.pumpAndSettle();
  final caja = tester.getRect(_slider);
  final y = (caja.center.dy + dy).round();
  final fila = await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData())!;
    return [
      for (var x = caja.left.round(); x < caja.right.round(); x++)
        Color.fromARGB(
          255,
          bytes.getUint8(((y * img.width) + x) * 4),
          bytes.getUint8(((y * img.width) + x) * 4 + 1),
          bytes.getUint8(((y * img.width) + x) * 4 + 2),
        ),
    ];
  });
  return fila!;
}

Future<Color> _pixel(WidgetTester tester, Offset o) async {
  final c = await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData())!;
    final i = ((o.dy.round() * img.width) + o.dx.round()) * 4;
    return Color.fromARGB(255, bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
  });
  return c!;
}

double _razon(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void _prueba(String descripcion, Future<void> Function(WidgetTester) cuerpo, {bool? skip}) {
  testWidgets(descripcion, (tester) async {
    try {
      await cuerpo(tester);
    } finally {
      _handle?.dispose();
      _handle = null;
    }
  }, skip: skip);
}

void main() {
  final primario = temaClaro().colorScheme.primary;

  test('el gris de la paleta es #5B6B82 y el del tema es el de la paleta', () {
    expect(ColoresColportaje.unica.gris, _gris);
    expect(temaClaro().extension<ColoresColportaje>()!.gris, _gris);
  });

  group('La pista por valor (24B·01, 24B·03)', () {
    for (final (nombreTam, tam) in _tamanos) {
      for (final escala in _escalas) {
        for (final minutos in [5, 30, 60, 90, 120]) {
          _prueba('$minutos min · $nombreTam · texto $escala×: el tramo sin recorrer es parejo '
              '(#5B6B82 de punta a punta, sin marcas), ≥ 3:1 contra la tarjeta y la perilla a la '
              'vista', (tester) async {
            await _montar(tester, _conMinutos(minutos), tam: tam, escala: escala);
            expect(tester.widget<Text>(_valor).data, '$minutos min antes');

            final fila = await _fila(tester);
            final tarjeta = await _pixel(
              tester,
              tester.getRect(_slider).center - const Offset(0, 22),
            );
            final indices = [
              for (var i = 0; i < fila.length; i++)
                if (fila[i] == _gris) i,
            ];

            if (minutos == 120) {
              expect(
                indices,
                isEmpty,
                reason: 'con 120 min todo está recorrido: sin gris a la vista',
              );
            } else {
              expect(indices, isNotEmpty);
              // Entre el primer y el último píxel gris no hay nada que no sea gris: ni marcas de
              // divisiones ni el tramo recorrido ni otra cosa.
              final primero = indices.first;
              final ultimo = indices.last;
              final intrusos = [
                for (var i = primero; i <= ultimo; i++)
                  if (fila[i] != _gris) i,
              ];
              expect(
                intrusos,
                isEmpty,
                reason: 'el tramo sin recorrer tiene píxeles que no son #5B6B82 en x=$intrusos',
              );
              // Largo mínimo: el tramo sin recorrer se ve (no es una mancha).
              final esperado = 1 - (minutos - 5) / 115;
              expect(
                indices.length,
                greaterThan((tester.getRect(_slider).width - 48) * esperado * 0.8),
                reason: 'el tramo sin recorrer es más corto de lo que marca el valor',
              );
            }

            expect(_razon(_gris, tarjeta), greaterThanOrEqualTo(3.0));
            // La perilla es del color primario y se ve contra la tarjeta.
            final caja = tester.getRect(_slider);
            expect(_razon(primario, tarjeta), greaterThanOrEqualTo(3.0));
            final cuantosPrimarios = fila.where((c) => c == primario).length;
            expect(
              cuantosPrimarios,
              greaterThan(10),
              reason: 'no se ve la perilla ni el recorrido',
            );
            expect(caja.height, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
            await _capturar(tester, '${minutos}_${nombreTam.substring(0, 3)}_${escala.toInt()}x');
          });
        }
      }
    }

    _prueba('medida: el tramo recorrido contra el sin recorrer (#13407A / #5B6B82)', (
      tester,
    ) async {
      await _montar(tester, _conMinutos(60));
      final razon = _razon(primario, _gris);
      // ignore: avoid_print
      print(
        'QA523 razón recorrido/sin recorrer = ${razon.toStringAsFixed(2)} (primario $primario)',
      );
      expect(primario, isNot(_gris));
    });
  });

  group('Apagado (24B·02) y sin permiso del teléfono (24B·04)', () {
    for (final (nombreTam, tam) in _tamanos) {
      for (final escala in _escalas) {
        _prueba('24B·02 · $nombreTam · texto $escala×: apagado el control no toma el gris nuevo y '
            'la perilla no se confunde con la de un control activo', (tester) async {
          await _montar(tester, _conMinutos(30, activados: false), tam: tam, escala: escala);
          final fila = await _fila(tester);
          expect(fila.where((c) => c == _gris), isEmpty, reason: 'apagado se ve como activo');
          expect(fila.where((c) => c == primario), isEmpty, reason: 'apagado pinta el primario');
          expect(tester.widget<Slider>(_slider).onChanged, isNull);
          expect(tester.takeException(), isNull);
          await _capturar(tester, 'apagado_${nombreTam.substring(0, 3)}_${escala.toInt()}x');
        });

        _prueba('24B·04 · $nombreTam · texto $escala×: sin permiso del teléfono el control queda '
            'activo y a todo contraste (sin la opacidad .45 del canvas, decidido el 27/10) con el '
            'gris nuevo', (tester) async {
          await _montar(tester, Telefono(), tam: tam, escala: escala);
          expect(_slider, findsOneWidget);
          expect(tester.widget<Slider>(_slider).onChanged, isNotNull);
          final fila = await _fila(tester);
          expect(fila.where((c) => c == _gris), isNotEmpty);
          expect(fila.where((c) => c == primario), isNotEmpty);
          await _capturar(tester, 'sinpermiso_${nombreTam.substring(0, 3)}_${escala.toInt()}x');
        });
      }
    }

    _prueba('encender los recordatorios: el control pasa a gris y primario; apagarlos, vuelve a '
        'atenuado', (tester) async {
      await _montar(tester, _conMinutos(30, activados: false));
      var fila = await _fila(tester);
      expect(fila.where((c) => c == _gris), isEmpty);

      await tester.tap(_interruptor);
      await tester.pumpAndSettle();
      fila = await _fila(tester);
      expect(fila.where((c) => c == _gris), isNotEmpty);
      expect(fila.where((c) => c == primario), isNotEmpty);

      await tester.tap(_interruptor);
      await tester.pumpAndSettle();
      fila = await _fila(tester);
      expect(fila.where((c) => c == _gris), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('Arrastrar y reentrar', () {
    _prueba('arrastrando el color del tramo no parpadea: en cada cuadro es #5B6B82', (
      tester,
    ) async {
      await _montar(tester, _conMinutos(30));
      final caja = tester.getRect(_slider);
      final gesto = await tester.startGesture(
        Offset(caja.left + caja.width * 0.22, caja.center.dy),
      );
      for (var paso = 1; paso <= 8; paso++) {
        await gesto.moveBy(Offset(caja.width * 0.04, 0));
        await tester.pump(const Duration(milliseconds: 16));
        final fila = await _fila(tester);
        final indices = [
          for (var i = 0; i < fila.length; i++)
            if (fila[i] == _gris) i,
        ];
        expect(indices, isNotEmpty, reason: 'cuadro $paso: no queda tramo sin recorrer');
        for (var i = indices.first; i <= indices.last; i++) {
          expect(fila[i], _gris, reason: 'cuadro $paso: x=$i no es el gris');
        }
      }
      await _capturar(tester, 'arrastrando');
      await gesto.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    _prueba('salir de la pantalla y volver a entrar: el tramo vuelve a ser #5B6B82', (
      tester,
    ) async {
      await _montar(tester, _conMinutos(45));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await _montar(tester, _conMinutos(45));
      final fila = await _fila(tester);
      expect(fila.where((c) => c == _gris), isNotEmpty);
    });
  });

  group('La pantalla entera con el control', () {
    for (final (nombreTam, tam) in _tamanos) {
      for (final escala in _escalas) {
        for (final (estado, activados) in [('encendido', true), ('apagado', false)]) {
          _prueba(
            '$estado · $nombreTam · texto $escala×: tamaño de toque, etiquetas y contraste de '
            'texto',
            (tester) async {
              await _montar(
                tester,
                _conMinutos(30, activados: activados),
                tam: tam,
                escala: escala,
              );
              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    _prueba('el lector sigue viendo un solo control ajustable con su etiqueta y su valor', (
      tester,
    ) async {
      await _montar(tester, _conMinutos(30));
      final nodo = tester.getSemantics(
        find.byWidgetPredicate((w) => w is Semantics && w.properties.slider == true),
      );
      expect(nodo.label, contains('Anticipación'));
      expect(nodo.value, '30 min antes');
      expect(find.semantics.byAction(SemanticsAction.increase), findsOneWidget);
      expect(find.semantics.byAction(SemanticsAction.decrease), findsOneWidget);
    });
  });
}
