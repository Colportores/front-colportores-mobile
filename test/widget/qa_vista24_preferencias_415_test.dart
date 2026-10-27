// QA de #415 (HU-NOT-004, vista 24 grupo B): preferencias de los recordatorios de agenda.
//
// Cada artboard 24B·01 a 24B·06 (más «error al leer», que el canvas no dibuja) en 360×640 y 412×915,
// con el texto a 1,0× y a 2,0× y con las fuentes reales; la HU literal; los casos límite que los
// tests del PR no miran (acciones superpuestas con el aviso, falla con un cambio pendiente, extremos
// arrastrando el control de verdad) y las capturas de cada estado.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`
// (ignorado por git: nunca se commitean). Los dos hallazgos menores de la QA (el aviso de la
// anticipación con los recordatorios apagados y el tramo sin recorrer del control) se arreglaron en
// #155 y sus tests ya no llevan `skip`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/notificaciones/notificaciones_providers.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/motor_de_avisos_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/recordatorios_locales.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/recordatorios_providers.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/notificaciones_providers.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/preferencias_recordatorios_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/notificaciones_arnes.dart';
import '../helpers/qa_vista24_153_arnes.dart' show cargarFuentes, conCapturas;

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

final _interruptor = find.byKey(const Key('pref_recordatorios_interruptor'));
final _slider = find.byKey(const Key('pref_anticipacion_slider'));
final _valor = find.byKey(const Key('pref_anticipacion_valor'));
final _apagadosAviso = find.byKey(const Key('pref_apagados_aviso'));
final _errorGuardar = find.byKey(const Key('pref_error_guardar'));
final _reintentarGuardar = find.byKey(const Key('pref_error_reintentar'));
final _errorLeer = find.byKey(const Key('pref_error_leer'));
final _reintentarLeer = find.byKey(const Key('pref_reintentar_leer'));
final _toast = find.byKey(const Key('pref_anticipacion_aviso'));
final _cargando = find.byKey(const Key('notificaciones_cargando'));
final _atras = find.byKey(const Key('notificaciones_atras'));
final _subir = find.semantics.byAction(SemanticsAction.increase);

const _tamanos = [('360×640', Size(360, 640)), ('412×915', Size(412, 915))];
const _escalas = [1.0, 2.0];

/// Cada artboard del grupo B del canvas y los estados que el canvas no dibuja.
enum E24B {
  b01('24B·01 preferencias'),
  b02('24B·02 recordatorios apagados'),
  b03('24B·03 anticipación cambiada (toast)'),
  b04('24B·04 permiso del teléfono apagado'),
  b05('24B·05 cargando'),
  b06('24B·06 error al guardar'),
  leer('error al leer las preferencias'),
  bloqueado('permiso bloqueado en el teléfono');

  const E24B(this.rotulo);

  final String rotulo;
}

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

Future<void> _montar(
  WidgetTester tester,
  Telefono t, {
  Size tam = const Size(360, 640),
  double escala = 1,
  Sesion? sesion,
  bool esperar = true,
  Widget? pantalla,
  Recordatorios? recordatorios,
}) async {
  fijarTamano(tester, tamano: tam, texto: escala);
  await cargarFuentes(tester);
  _handle?.dispose();
  _handle = tester.ensureSemantics();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        if (recordatorios == null)
          ...t.overrides
        else ...[
          preferenciasRecordatoriosRepositoryProvider.overrideWithValue(t.preferencias),
          recordatoriosProvider.overrideWithValue(recordatorios),
          agendasParaRecordarProvider.overrideWithValue(t.agendas),
          permisoNotificacionesSistemaProvider.overrideWithValue(t.sistema),
          permisoNotificacionesRepositoryProvider.overrideWithValue(t.recuerdo),
          monitorConectividadProvider.overrideWithValue(t.conexion),
        ],
        sesionProvider.overrideWith(() => _SesionFija(sesion ?? _sesion)),
      ],
      child: MaterialApp(theme: temaClaro(), home: pantalla ?? const NotificacionesPage()),
    ),
  );
  if (esperar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Lleva la pantalla al estado [e].
Future<Telefono> _llegarA(
  WidgetTester tester,
  E24B e, {
  Size tam = const Size(360, 640),
  double escala = 1,
}) async {
  final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
  switch (e) {
    case E24B.b01:
      await _montar(tester, t, tam: tam, escala: escala);
    case E24B.b02:
      t.preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
      await _montar(tester, t, tam: tam, escala: escala);
    case E24B.b03:
      _visitas(t);
      await _montar(tester, t, tam: tam, escala: escala);
      // Arrastra hasta cerca de los 60 minutos (el valor exacto no importa para la vista).
      final caja = tester.getRect(_slider);
      await tester.drag(_slider, Offset(caja.width * 0.26, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    case E24B.b04:
      final sin = Telefono();
      await _montar(tester, sin, tam: tam, escala: escala);
      return sin;
    case E24B.b05:
      t.preferencias.lecturaDemorada = Completer<void>();
      await _montar(tester, t, tam: tam, escala: escala, esperar: false);
    case E24B.b06:
      t.preferencias.fallaAlGuardar = true;
      await _montar(tester, t, tam: tam, escala: escala);
      await tester.tap(_interruptor);
      await tester.pumpAndSettle();
    case E24B.leer:
      t.preferencias.fallaAlLeer = true;
      await _montar(tester, t, tam: tam, escala: escala);
    case E24B.bloqueado:
      final b = Telefono()..recuerdo.pedido = PedidoNotificaciones.sistema;
      await _montar(tester, b, tam: tam, escala: escala);
      return b;
  }
  return t;
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa415_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

bool _encendido(WidgetTester tester) => tester.widget<SwitchListTile>(_interruptor).value;

double _valorSlider(WidgetTester tester) => tester.widget<Slider>(_slider).value;

String _textoDe(Finder f) => (f.evaluate().single.widget as Text).data!;

void main() {
  group('Criterio de la HU (literal)', () {
    _prueba('Escenario: Toggle recordatorios locales apagado — '
        'dado que apago «Recordatorios de agenda», cuando tengo visitas agendadas, '
        'entonces no se programan notificaciones locales (se cancelan las ya programadas)', (
      tester,
    ) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      _visitas(t, 3);
      // Los recordatorios de verdad (`RecordatoriosLocales`) sobre un motor de avisos en memoria.
      final motor = MotorDeAvisosEnMemoria();
      final locales = RecordatoriosLocales(
        motor: motor,
        permiso: t.sistema,
        anticipacion: t.preferencias,
        activados: t.preferencias,
      );
      for (final v in t.agendas.agendas) {
        await locales.programar(v);
      }
      expect(motor.pendientes.length, 3);
      await _montar(tester, t, recordatorios: locales);

      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      expect(_encendido(tester), isFalse);
      expect(t.preferencias.preferencias.activados, isFalse);
      expect(motor.pendientes, isEmpty);
      // Y una visita que se agenda ahora tampoco programa nada.
      final nueva = t.agendas.agendas.first;
      expect(await locales.programar(nueva), ResultadoRecordatorio.apagados);
      expect(motor.pendientes, isEmpty);
    });

    _prueba('«Recordatorios de agenda» y «Anticipación»: textos literales del canvas', (
      tester,
    ) async {
      await _llegarA(tester, E24B.b01);

      expect(find.text('RECORDATORIOS'), findsOneWidget);
      expect(find.text('Recordatorios de agenda'), findsOneWidget);
      expect(find.text('Antes de cada visita agendada'), findsOneWidget);
      expect(find.text('Anticipación'), findsOneWidget);
      expect(find.text('30 min antes'), findsOneWidget);
      expect(find.text('5 min'), findsOneWidget);
      expect(find.text('120 min'), findsOneWidget);
    });

    _prueba('regla: default 30 y rango 5..120 en el control', (tester) async {
      await _llegarA(tester, E24B.b01);

      final s = tester.widget<Slider>(_slider);
      expect(s.value, 30);
      expect(s.min, 5);
      expect(s.max, 120);
    });

    _prueba('regla: «los ya programados se reprograman al guardar» (4 visitas, 60 min)', (
      tester,
    ) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      _visitas(t);
      await _montar(tester, t);
      final caja = tester.getRect(_slider);

      await tester.drag(_slider, Offset(caja.width * 0.26, 0));
      await tester.pumpAndSettle();

      final minutos = t.preferencias.preferencias.anticipacionMinutos;
      expect(minutos, greaterThan(30));
      expect(t.recordatorios.programados.keys, unorderedEquals(['ag-1', 'ag-2', 'ag-3', 'ag-4']));
      expect(
        _textoDe(find.descendant(of: _toast, matching: find.byType(Text))),
        'Reprogramamos 4 recordatorios: te avisamos $minutos min antes.',
      );
    });
  });

  group('Extremos arrastrando de verdad', () {
    _prueba('arrastrar hasta el final guarda 120 y hasta el principio guarda 5', (tester) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      await _montar(tester, t);
      final caja = tester.getRect(_slider);

      await tester.drag(_slider, Offset(caja.width * 2, 0));
      await tester.pumpAndSettle();
      expect(t.preferencias.preferencias.anticipacionMinutos, 120);
      expect(_valorSlider(tester), 120);
      expect(_textoDe(_valor), '120 min antes');

      await tester.drag(_slider, Offset(-caja.width * 2, 0));
      await tester.pumpAndSettle();
      expect(t.preferencias.preferencias.anticipacionMinutos, 5);
      expect(_valorSlider(tester), 5);
      expect(_textoDe(_valor), '5 min antes');
    });

    // QA #415 (arreglado en #155): el tramo sin recorrer del control de anticipación era blanco sobre
    // la tarjeta (1,05:1); el canvas lo dibuja a 4 px en #E3E7EE (Bloques.dc.html), 1,16:1.
    _prueba(
      'el tramo sin recorrer del control se distingue de la tarjeta (canvas: #E3E7EE, 4 px)',
      (tester) async {
        await _llegarA(tester, E24B.b01);

        // Se mide el píxel del tramo sin recorrer (a la derecha del botón) contra el de la tarjeta.
        final caja = tester.getRect(_slider);
        final pista = Offset(caja.left + caja.width * 0.85, caja.center.dy);
        final tarjeta = Offset(pista.dx, caja.center.dy - 22);
        final colores = await tester.runAsync(() async {
          final vista = tester.binding.renderViews.first;
          final capa = vista.debugLayer! as OffsetLayer;
          final img = await capa.toImage(Offset.zero & vista.size);
          final bytes = (await img.toByteData())!;
          Color en(Offset o) {
            final i = ((o.dy.round() * img.width) + o.dx.round()) * 4;
            return Color.fromARGB(
              255,
              bytes.getUint8(i),
              bytes.getUint8(i + 1),
              bytes.getUint8(i + 2),
            );
          }

          return (en(pista), en(tarjeta));
        });
        final (colorPista, colorTarjeta) = colores!;
        final lp = colorPista.computeLuminance();
        final lt = colorTarjeta.computeLuminance();
        final razon = (lp > lt ? lp + 0.05 : lt + 0.05) / (lp > lt ? lt + 0.05 : lp + 0.05);
        expect(
          razon,
          greaterThanOrEqualTo(1.1),
          reason: 'pista $colorPista sobre tarjeta $colorTarjeta: $razon',
        );
        expect(colorPista, const Color(0xFFE3E7EE));
      },
    );

    _prueba('el control tiene al menos 48 dp de alto para el dedo', (tester) async {
      await _llegarA(tester, E24B.b01);

      expect(tester.getSize(_slider).height, greaterThanOrEqualTo(48));
    });
  });

  group('Acciones superpuestas y fallas', () {
    // QA #415 (arreglado en #155): con «anticipación» y «apagar» superpuestos, el toast prometía
    // «te avisamos N min antes» (con N recordatorios reprogramados) aunque quedaron apagados.
    _prueba('anticipación y, antes de que termine, apagar: el aviso no promete reprogramaciones '
        'ni «te avisamos N min antes» con los recordatorios apagados', (tester) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      _visitas(t);
      final demora = t.preferencias.guardadoDemorado = Completer<void>();
      await _montar(tester, t);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pump();
      await tester.tap(_interruptor);
      await tester.pump();
      demora.complete();
      await tester.pumpAndSettle();

      expect(t.preferencias.preferencias.activados, isFalse);
      expect(_apagadosAviso, findsOneWidget);
      // Con los recordatorios apagados no se reprogramó ninguno: el toast de la anticipación
      // («Guardado: te avisamos 35 min antes.») contradice el aviso fijo de 24B·02.
      expect(_toast, findsNothing);
    });

    _prueba('falla el guardado con un segundo cambio ya pedido: la pantalla vuelve a lo guardado '
        'y dice el error (nada trabado, el siguiente cambio anda)', (tester) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      final demora = t.preferencias.guardadoDemorado = Completer<void>();
      await _montar(tester, t);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pump();
      await tester.tap(_interruptor);
      await tester.pump();
      t.preferencias.fallaAlGuardar = true;
      demora.complete();
      await tester.pumpAndSettle();

      expect(_errorGuardar, findsOneWidget);
      expect(_reintentarGuardar, findsOneWidget);
      // Decisión del 27/10 (mapa §2): el aviso dice lo que volvió (dos cambios) y «Reintentar» los
      // repite a los dos.
      expect(
        find.text('No pudimos guardar los cambios. Volvieron a como estaban.'),
        findsOneWidget,
      );
      expect(_encendido(tester), t.preferencias.preferencias.activados);
      expect(_valorSlider(tester), t.preferencias.preferencias.anticipacionMinutos.toDouble());

      t.preferencias
        ..fallaAlGuardar = false
        ..guardadoDemorado = null;
      await tester.tap(_reintentarGuardar);
      await tester.pumpAndSettle();
      expect(_errorGuardar, findsNothing);
      expect(_encendido(tester), isFalse);
      expect(t.preferencias.preferencias.activados, isFalse);
      expect(t.preferencias.preferencias.anticipacionMinutos, 35);
      expect(_valorSlider(tester), 35);

      // Y el siguiente cambio sigue andando.
      await tester.tap(_interruptor);
      await tester.pumpAndSettle();
      expect(_encendido(tester), isTrue);
      expect(t.preferencias.preferencias.activados, isTrue);
    });

    _prueba('10 toques seguidos al interruptor: lo que se ve es lo que quedó guardado', (
      tester,
    ) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      _visitas(t);
      t.preferencias.guardadoDemorado = Completer<void>();
      await _montar(tester, t);

      for (var i = 0; i < 10; i++) {
        await tester.tap(_interruptor);
        await tester.pump();
      }
      t.preferencias.guardadoDemorado!.complete();
      await tester.pumpAndSettle();

      expect(_encendido(tester), t.preferencias.preferencias.activados);
      expect(_errorGuardar, findsNothing);
      // 10 toques = vuelve a estar prendido: los recordatorios están programados.
      expect(t.recordatorios.programados.length, 4);
    });

    _prueba('«Reintentar» del error al guardar deja de mostrarse si llega un cambio nuevo', (
      tester,
    ) async {
      final t = await _llegarA(tester, E24B.b06);
      expect(_errorGuardar, findsOneWidget);

      t.preferencias.fallaAlGuardar = false;
      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      expect(_errorGuardar, findsNothing);
      expect(_reintentarGuardar, findsNothing);
    });

    _prueba('sin sesión (no hay a quién reprogramar): guarda y avisa sin inventar números', (
      tester,
    ) async {
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      await _montar(tester, t, sesion: null);
      final caja = tester.getRect(_slider);

      await tester.drag(_slider, Offset(caja.width * 0.2, 0));
      await tester.pumpAndSettle();

      expect(t.preferencias.preferencias.anticipacionMinutos, greaterThan(30));
      expect(_errorGuardar, findsNothing);
      expect(
        _textoDe(find.descendant(of: _toast, matching: find.byType(Text))),
        startsWith('Guardado: te avisamos '),
      );
    });

    _prueba('error al leer: «Reintentar» lee de nuevo y entrega la pantalla completa', (
      tester,
    ) async {
      final t = await _llegarA(tester, E24B.leer);
      expect(_errorLeer, findsOneWidget);
      expect(_interruptor, findsNothing);

      t.preferencias.fallaAlLeer = false;
      await tester.tap(_reintentarLeer);
      await tester.pumpAndSettle();

      expect(_errorLeer, findsNothing);
      expect(_interruptor, findsOneWidget);
      expect(_slider, findsOneWidget);
    });

    _prueba('con los recordatorios apagados el control de anticipación no se mueve y el lector '
        'no ofrece subir ni bajar', (tester) async {
      await _llegarA(tester, E24B.b02);

      expect(tester.widget<Slider>(_slider).onChanged, isNull);
      expect(_subir, findsNothing);
      expect(_apagadosAviso, findsOneWidget);
    });
  });

  group('Navegación', () {
    for (final e in [E24B.b01, E24B.b02, E24B.b05, E24B.b06, E24B.leer, E24B.bloqueado]) {
      _prueba('${e.rotulo}: «Volver» está a mano y sale de la pantalla', (tester) async {
        // Se abre sobre otra ruta para poder volver.
        final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
        switch (e) {
          case E24B.b02:
            t.preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
          case E24B.b05:
            t.preferencias.lecturaDemorada = Completer<void>();
          case E24B.b06:
            t.preferencias.fallaAlGuardar = true;
          case E24B.leer:
            t.preferencias.fallaAlLeer = true;
          case E24B.bloqueado:
            t.recuerdo.pedido = PedidoNotificaciones.sistema;
            t.sistema.estado = EstadoSistemaNotificaciones.apagadas;
          case E24B.b01 || E24B.b03 || E24B.b04:
            break;
        }
        await _montar(
          tester,
          t,
          esperar: false,
          pantalla: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(NotificacionesPage.ruta()),
                child: const Text('Ir'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Ir'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        if (e == E24B.b06) {
          await tester.tap(_interruptor);
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(_atras, findsOneWidget);
        await tester.tap(_atras);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('notificaciones_pagina')), findsNothing);
        expect(find.text('Ir'), findsOneWidget);
      });
    }

    _prueba('salir y volver a entrar con el error al guardar: la pantalla arranca limpia', (
      tester,
    ) async {
      final t = await _llegarA(tester, E24B.b06);
      expect(_errorGuardar, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await _montar(tester, t);

      expect(_errorGuardar, findsNothing);
      expect(_encendido(tester), isTrue);
    });
  });

  group('Estados: matriz de tamaños y escalas (fuentes reales)', () {
    for (final (nombreTam, tam) in _tamanos) {
      for (final escala in _escalas) {
        for (final e in E24B.values) {
          _prueba('${e.rotulo} · $nombreTam · texto $escala×: sin overflow, con contenido y '
              'con la acción a mano', (tester) async {
            await _llegarA(tester, e, tam: tam, escala: escala);

            expect(tester.takeException(), isNull);
            expect(find.text('Notificaciones'), findsOneWidget);

            switch (e) {
              case E24B.b01 || E24B.b03:
                expect(_interruptor, findsOneWidget);
                expect(_slider, findsOneWidget);
              case E24B.b02:
                expect(_apagadosAviso, findsOneWidget);
              case E24B.b04:
                expect(find.byKey(const Key('notificaciones_activar')), findsOneWidget);
                expect(_interruptor, findsOneWidget);
              case E24B.b05:
                expect(_cargando, findsOneWidget);
                expect(_interruptor, findsNothing);
              case E24B.b06:
                expect(_errorGuardar, findsOneWidget);
                expect(_reintentarGuardar, findsOneWidget);
              case E24B.leer:
                expect(_errorLeer, findsOneWidget);
                expect(_reintentarLeer, findsOneWidget);
              case E24B.bloqueado:
                expect(find.byKey(const Key('notificaciones_abrir_ajustes')), findsOneWidget);
            }

            // Ningún texto queda cortado con puntos suspensivos ni se desborda de la pantalla.
            for (final p in find.byType(RichText).evaluate()) {
              final r = p.renderObject! as RenderParagraph;
              expect(r.didExceedMaxLines, isFalse, reason: r.text.toPlainText());
              final rect = MatrixUtils.transformRect(r.getTransformTo(null), Offset.zero & r.size);
              expect(rect.right, lessThanOrEqualTo(tam.width + 0.5), reason: r.text.toPlainText());
            }

            await _capturar(
              tester,
              '${e.name}_${nombreTam.replaceAll('×', 'x')}_${escala.toStringAsFixed(0)}x',
            );
          });
        }
      }
    }
  });

  group('Guías de accesibilidad de Flutter (toque y etiqueta)', () {
    for (final (nombreTam, tam) in _tamanos) {
      for (final escala in _escalas) {
        for (final e in E24B.values) {
          _prueba('${e.rotulo} · $nombreTam · texto $escala×', (tester) async {
            await _llegarA(tester, e, tam: tam, escala: escala);

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          });
        }
      }
    }
  });

  group('Lectores de pantalla', () {
    _prueba('el interruptor se anuncia con su nombre y su estado', (tester) async {
      await _llegarA(tester, E24B.b01);

      expect(
        tester.getSemantics(_interruptor),
        isSemantics(
          label: 'Recordatorios de agenda\nAntes de cada visita agendada',
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
        ),
      );
    });

    _prueba('el error al guardar y el de lectura son regiones vivas (se anuncian solos)', (
      tester,
    ) async {
      await _llegarA(tester, E24B.b06);
      var nodo = tester.getSemantics(_errorGuardar);
      expect(_vivo(nodo), isTrue);

      await _llegarA(tester, E24B.leer);
      nodo = tester.getSemantics(_errorLeer);
      expect(_vivo(nodo), isTrue);
    });

    _prueba('el aviso de 24B·02 es una región viva', (tester) async {
      await _llegarA(tester, E24B.b02);

      expect(_vivo(tester.getSemantics(_apagadosAviso)), isTrue);
    });
  });
}

bool _vivo(SemanticsNode nodo) {
  SemanticsNode? n = nodo;
  while (n != null) {
    if (n.flagsCollection.isLiveRegion) return true;
    n = n.parent;
  }
  return false;
}

SemanticsHandle? _handle;

/// `testWidgets` que suelta la semántica antes del chequeo final del test (un `addTearDown` llega tarde).
void _prueba(String descripcion, Future<void> Function(WidgetTester) cuerpo) {
  testWidgets(descripcion, (tester) async {
    try {
      await cuerpo(tester);
    } finally {
      _handle?.dispose();
      _handle = null;
    }
  });
}
