// QA de #155 (HU-NOT-004, vista 24 grupo B): lo que cambió el PR #517 sobre #415.
//
// El PR arregla dos menores de la QA de #415: (1) el aviso «Reprogramamos N recordatorios: te
// avisamos X min antes.» ya no sale si al terminar el guardado los recordatorios quedaron apagados;
// (2) el tramo sin recorrer del control de anticipación pasa a #E3E7EE. Acá se prueba el borde de
// cada arreglo: los demás caminos del aviso (reintentar, encender de nuevo, aviso viejo en
// pantalla), el control con los recordatorios apagados y en los extremos, y que el color del tramo
// recorrido y del botón no cambió.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`
// (ignorado por git). Los tests con `skip` documentan un hallazgo: `--dart-define=QA_HALLAZGOS=true`
// los corre.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
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

const _conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

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
final _apagadosAviso = find.byKey(const Key('pref_apagados_aviso'));
final _errorGuardar = find.byKey(const Key('pref_error_guardar'));
final _reintentarGuardar = find.byKey(const Key('pref_error_reintentar'));
final _toast = find.byKey(const Key('pref_anticipacion_aviso'));
final _subir = find.semantics.byAction(SemanticsAction.increase);

const _tamanos = [('360×640', Size(360, 640)), ('412×915', Size(412, 915))];
const _escalas = [1.0, 2.0];

const _canvasPista = Color(0xFFE3E7EE);

void _visitas(Telefono t, [int cuantas = 4]) {
  for (var n = 1; n <= cuantas; n++) {
    t.agendas.agendas.add(
      RecordatorioDeVisita(
        agendaId: 'ag-$n',
        tipo: TipoAgenda.entrevista,
        direccion: 'Av. Italia ${1000 + n}',
        fechaProgramada: DateTime.now().add(Duration(days: n)),
      ),
    );
  }
}

SemanticsHandle? _handle;

Future<void> _montar(
  WidgetTester tester,
  Telefono t, {
  Size tam = const Size(360, 640),
  double escala = 1,
  Widget? inicio,
}) async {
  fijarTamano(tester, tamano: tam, texto: escala);
  await cargarFuentes(tester);
  _handle?.dispose();
  _handle = tester.ensureSemantics();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [...t.overrides, sesionProvider.overrideWith(_SesionFija.new)],
      child: MaterialApp(theme: temaClaro(), home: inicio ?? const NotificacionesPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa155_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Los colores de los píxeles pedidos, tal como quedaron pintados.
Future<List<Color>> _pixeles(WidgetTester tester, List<Offset> puntos) async {
  final colores = await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData())!;
    return [
      for (final o in puntos)
        Color.fromARGB(
          255,
          bytes.getUint8(((o.dy.round() * img.width) + o.dx.round()) * 4),
          bytes.getUint8(((o.dy.round() * img.width) + o.dx.round()) * 4 + 1),
          bytes.getUint8(((o.dy.round() * img.width) + o.dx.round()) * 4 + 2),
        ),
    ];
  });
  return colores!;
}

double _razon(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

String _textoDe(Finder f) => (f.evaluate().single.widget as Text).data!;

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
  group('El aviso de la anticipación y los recordatorios apagados', () {
    _prueba('solo la anticipación, con los recordatorios encendidos: el aviso sale con el conteo '
        'y los minutos', (tester) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      _visitas(t);
      await _montar(tester, t);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pumpAndSettle();

      expect(_toast, findsOneWidget);
      expect(
        _textoDe(find.descendant(of: _toast, matching: find.byType(Text))),
        'Reprogramamos 4 recordatorios: te avisamos 35 min antes.',
      );
      expect(_apagadosAviso, findsNothing);
    });

    _prueba('anticipación, apagar y volver a encender antes de que termine: quedan encendidos y el '
        'aviso sale con los minutos nuevos', (tester) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      _visitas(t);
      final demora = t.preferencias.guardadoDemorado = Completer<void>();
      await _montar(tester, t);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pump();
      await tester.tap(_interruptor);
      await tester.pump();
      await tester.tap(_interruptor);
      await tester.pump();
      demora.complete();
      await tester.pumpAndSettle();

      expect(t.preferencias.preferencias.activados, isTrue);
      expect(t.preferencias.preferencias.anticipacionMinutos, 35);
      expect(_apagadosAviso, findsNothing);
      expect(_toast, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _prueba('falla el guardado de anticipación + apagar y se reintenta: apagados, sin el aviso de '
        '«te avisamos N min antes» y con el aviso fijo', (tester) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      _visitas(t);
      final demora = t.preferencias.guardadoDemorado = Completer<void>();
      t.preferencias.fallaAlGuardar = true;
      await _montar(tester, t);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pump();
      await tester.tap(_interruptor);
      await tester.pump();
      demora.complete();
      await tester.pumpAndSettle();
      // Falló: todo vuelve a como estaba y hay un «Reintentar» a mano.
      expect(_errorGuardar, findsOneWidget);
      expect(_toast, findsNothing);
      expect(t.preferencias.preferencias.activados, isTrue);

      t.preferencias.fallaAlGuardar = false;
      await tester.tap(_reintentarGuardar);
      await tester.pumpAndSettle();

      expect(t.preferencias.preferencias.activados, isFalse);
      expect(t.preferencias.preferencias.anticipacionMinutos, 35);
      expect(_errorGuardar, findsNothing);
      expect(_apagadosAviso, findsOneWidget);
      expect(_toast, findsNothing);
    });

    _prueba('falla solo la anticipación y se reintenta con los recordatorios encendidos: el aviso '
        'sale al reintentar', (tester) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      _visitas(t);
      t.preferencias.fallaAlGuardar = true;
      await _montar(tester, t);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(_errorGuardar, findsOneWidget);
      expect(_toast, findsNothing);

      t.preferencias.fallaAlGuardar = false;
      await tester.tap(_reintentarGuardar);
      await tester.pumpAndSettle();

      expect(_errorGuardar, findsNothing);
      expect(_toast, findsOneWidget);
      expect(t.preferencias.preferencias.anticipacionMinutos, 35);
    });

    _prueba('dos anticipaciones seguidas y apagar al final: un solo guardado de más, ningún aviso '
        'y nada trabado (el siguiente cambio anda)', (tester) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      _visitas(t);
      final demora = t.preferencias.guardadoDemorado = Completer<void>();
      await _montar(tester, t);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pump();
      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pump();
      await tester.tap(_interruptor);
      await tester.pump();
      demora.complete();
      await tester.pumpAndSettle();

      expect(t.preferencias.preferencias.activados, isFalse);
      expect(t.preferencias.preferencias.anticipacionMinutos, 40);
      expect(_toast, findsNothing);
      expect(_apagadosAviso, findsOneWidget);

      // Nada quedó trabado: se vuelve a encender y el control vuelve a andar.
      await tester.tap(_interruptor);
      await tester.pumpAndSettle();
      expect(t.preferencias.preferencias.activados, isTrue);
      expect(_apagadosAviso, findsNothing);
      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(t.preferencias.preferencias.anticipacionMinutos, 45);
      expect(_toast, findsOneWidget);
    });

    _prueba(
      'salir de la pantalla con el guardado en curso y apagar: se termina de guardar igual y no '
      'revienta; al volver, apagado y sin el aviso',
      (tester) async {
        final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
        _visitas(t);
        final demora = t.preferencias.guardadoDemorado = Completer<void>();
        await _montar(
          tester,
          t,
          inicio: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('qa_entrar'),
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => const NotificacionesPage())),
                child: const Text('Entrar'),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('qa_entrar')));
        await tester.pumpAndSettle();

        tester.semantics.performAction(_subir, SemanticsAction.increase);
        await tester.pump();
        await tester.tap(_interruptor);
        await tester.pump();
        await tester.tap(find.byKey(const Key('notificaciones_atras')));
        await tester.pump(const Duration(milliseconds: 400));
        demora.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(t.preferencias.preferencias.activados, isFalse);
        expect(t.preferencias.preferencias.anticipacionMinutos, 35);
        expect(_toast, findsNothing);

        await tester.tap(find.byKey(const Key('qa_entrar')));
        await tester.pumpAndSettle();
        expect(_apagadosAviso, findsOneWidget);
        expect(_toast, findsNothing);
      },
    );

    // QA #155: con el aviso de la anticipación ya a la vista (4 s), apagar los recordatorios deja
    // los dos juntos: «Reprogramamos 4 recordatorios: te avisamos 35 min antes.» y «Dejamos de
    // programar los recordatorios…». Es la misma contradicción que arregla el PR, pero en secuencia.
    _prueba('apagar con el aviso de la anticipación todavía a la vista: el aviso viejo no queda '
        'junto al fijo de 24B·02', (tester) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      _visitas(t);
      await _montar(tester, t);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(_toast, findsOneWidget);

      await tester.tap(_interruptor);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_apagadosAviso, findsOneWidget);
      expect(_toast, findsNothing, reason: 'sigue «te avisamos 35 min antes» con todo apagado');
    }, skip: !_conHallazgos);
  });

  group('El tramo sin recorrer del control', () {
    Future<(Rect, Color, Color)> medir(WidgetTester tester, double fraccion) async {
      final caja = tester.getRect(_slider);
      final y = caja.center.dy;
      final x = caja.left + caja.width * fraccion;
      final c = await _pixeles(tester, [Offset(x, y), Offset(x, y - 22)]);
      return (caja, c[0], c[1]);
    }

    for (final (nombreTam, tam) in _tamanos) {
      for (final escala in _escalas) {
        _prueba('con los recordatorios encendidos · $nombreTam · texto $escala×: el tramo sin '
            'recorrer es #E3E7EE y el recorrido sigue en el color primario', (tester) async {
          final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
          await _montar(tester, t, tam: tam, escala: escala);

          // 30 min de 5..120: el botón queda al 22 %. A la derecha, sin recorrer; a la izquierda,
          // recorrido.
          final (_, sinRecorrer, tarjeta) = await medir(tester, 0.7);
          expect(sinRecorrer, _canvasPista);
          expect(_razon(sinRecorrer, tarjeta), greaterThan(1.1));

          final caja = tester.getRect(_slider);
          final recorrido = (await _pixeles(tester, [
            Offset(caja.left + caja.width * 0.12, caja.center.dy),
          ])).single;
          expect(recorrido, temaClaro().colorScheme.primary);
          expect(tester.takeException(), isNull);
          await _capturar(tester, 'b01_${nombreTam.substring(0, 3)}_${escala.toInt()}x');
        });
      }
    }

    _prueba('con los recordatorios apagados el control se ve (a la vista y sin tocar): el tramo '
        'se distingue de la tarjeta', (tester) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas)
        ..preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
      await _montar(tester, t);

      final (_, pista, tarjeta) = await medir(tester, 0.7);
      expect(
        _razon(pista, tarjeta),
        greaterThan(1.1),
        reason: 'pista apagada $pista sobre la tarjeta $tarjeta: ${_razon(pista, tarjeta)}',
      );
      await _capturar(tester, 'b02_360_1x');
    });

    _prueba('en los extremos (5 y 120 min) el control se pinta sin romperse', (tester) async {
      for (final (minimo, fraccion) in [(5, 0.7), (120, 0.3)]) {
        final t = Telefono(estado: EstadoSistemaNotificaciones.activadas)
          ..preferencias.preferencias = PreferenciasRecordatorios(anticipacionMinutos: minimo);
        await _montar(tester, t);

        expect(_textoDe(_valor), '$minimo min antes');
        final (_, pista, tarjeta) = await medir(tester, fraccion);
        if (minimo == 5) {
          // Todo el resto sin recorrer.
          expect(pista, _canvasPista);
        } else {
          // Todo recorrido: no queda gris a la vista.
          expect(pista, temaClaro().colorScheme.primary);
        }
        expect(tarjeta, isNot(_canvasPista));
        expect(tester.takeException(), isNull);
        await _capturar(tester, 'extremo_$minimo');
      }
    });

    _prueba('al arrastrar de verdad el tramo sin recorrer cambia de lugar pero no de color', (
      tester,
    ) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      await _montar(tester, t);
      final caja = tester.getRect(_slider);

      await tester.dragFrom(
        Offset(caja.left + caja.width * 0.22, caja.center.dy),
        Offset(caja.width * 0.3, 0),
      );
      await tester.pumpAndSettle();

      final c = await _pixeles(tester, [
        Offset(caja.left + caja.width * 0.9, caja.center.dy),
        Offset(caja.left + caja.width * 0.2, caja.center.dy),
      ]);
      expect(c[0], _canvasPista);
      expect(c[1], temaClaro().colorScheme.primary);
    });
  });
}
