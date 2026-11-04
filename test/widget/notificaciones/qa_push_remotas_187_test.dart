// QA de HU-NOT-003 (#187, PR #615): recibir las push remotas, guardarlas y avisarlas con la app
// abierta (vista 24, 24C·08). Contra la HU, el canvas y las decisiones del 03/11 del issue (P2 tipos
// de push, P3 «sin destino abre el centro»). Los hallazgos van con `skip` salvo
// `--dart-define=QA_HALLAZGOS=true`.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/push_remotas_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/notificaciones_providers.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/notificaciones/domain/services/interpretador_push_remota.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/enganches_push_remotas.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/centro_notificaciones_page.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/push_remotas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auditoria_push_en_memoria.dart';
import '../../helpers/datos_locales_de_push_en_memoria.dart';
import '../../helpers/historial_notificaciones_falsos.dart';
import '../../helpers/notificaciones_arnes.dart';

/// Los hallazgos de la QA, con `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
const verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

const _pedido = '3f2b8c1e-9a4d-4e7b-8c1a-5d6e7f8a9b0c';
const _ticket = '7c1d2e3f-4a5b-4c6d-8e7f-0a1b2c3d4e5f';
const _campania = '11111111-2222-4333-8444-555555555555';
const _zona = '66666666-7777-4888-8999-aaaaaaaaaaaa';
const _agenda = 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff';
const _evento = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';

String _evento_(int n) => 'e0000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

final _banner = find.byKey(const Key('aviso_push_en_app_abrir'));
final _cerrar = find.byKey(const Key('aviso_push_en_app_cerrar'));
final _centro = find.byKey(const Key('centro_notificaciones_pagina'));

Telefono _telefono() => Telefono(estado: EstadoSistemaNotificaciones.activadas);

void main() {
  late PushRemotasEnMemoria push;
  late CentroArnes centro;
  late AuditoriaPushEnMemoria auditoria;

  setUp(() {
    push = PushRemotasEnMemoria();
    centro = CentroArnes();
    auditoria = AuditoriaPushEnMemoria();
  });

  List<Override> extra() => [
    pushRemotasProvider.overrideWithValue(push),
    ...EnganchesPushRemotas.enganches(navigatorKeyColportores),
    ...centro.overrides,
    auditoriaPushRepositoryProvider.overrideWithValue(auditoria),
    datosLocalesDePushRepositoryProvider.overrideWithValue(DatosLocalesDePushEnMemoria()),
  ];

  Future<void> abrir(WidgetTester tester) async {
    await abrirApp(tester, _telefono(), extra: extra());
    expect(principal, findsOneWidget);
  }

  Future<void> llega(WidgetTester tester, Map<String, Object?> datos) async {
    push.llegaConLaAppAbierta(datos);
    await tester.pump(const Duration(milliseconds: 50));
  }

  int sinLeer() => centro.historial.filas.where((n) => !n.leida).length;

  group('HU-NOT-003 · escenarios literales', () {
    testWidgets('Dado el payload literal de la HU (sin event_id), cuando llega con la app abierta, '
        'entonces el texto es «Tu pedido fue autorizado» y repetirlo no duplica nada', (
      tester,
    ) async {
      await abrir(tester);

      await llega(tester, {'type': 'pedido_autorizado', 'pedido_id': _pedido});
      expect(_banner, findsOneWidget);
      expect(find.text('Tu pedido fue autorizado'), findsOneWidget);
      expect(find.text('AHORA'), findsOneWidget);
      expect(centro.historial.filas, hasLength(1));

      // El mismo evento (y el pedido en mayúsculas) no genera dos avisos.
      await tester.tap(_cerrar);
      await tester.pump();
      await llega(tester, {'type': 'pedido_autorizado', 'pedido_id': _pedido});
      await llega(tester, {'type': 'pedido_autorizado', 'pedido_id': _pedido.toUpperCase()});
      expect(_banner, findsNothing);
      expect(centro.historial.filas, hasLength(1));
    });

    testWidgets('Escenario «Foreground»: el aviso es un banner arriba, liviano, no una pantalla '
        'entera (no tapa más de la quinta parte de 390×844)', (tester) async {
      await abrir(tester);
      await llega(tester, {'type': 'pedido_autorizado', 'pedido_id': _pedido});

      final caja = tester.getRect(find.byKey(const Key('aviso_push_en_app_abrir')));
      expect(caja.top, lessThan(120));
      expect(caja.height, lessThan(844 / 5));
      // El resto de la app sigue ahí, sin bloquearse.
      expect(principal, findsOneWidget);
    });

    testWidgets(
      'Escenario «Edge: payload con PII»: el campo prohibido se descarta, no se muestra nada y '
      'queda el NOMBRE del campo en la auditoría (nunca el valor)',
      (tester) async {
        final salida = <String>[];
        await runZoned(
          () async {
            await abrir(tester);
            await llega(tester, {
              'type': 'pedido_autorizado',
              'pedido_id': _pedido,
              'cliente_nombre': 'María Fernández',
              'telefono': '+54 9 11 5555-1234',
            });
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, linea) => salida.add(linea),
          ),
        );

        expect(_banner, findsNothing);
        expect(centro.historial.filas, isEmpty);
        expect(auditoria.descartadas, [
          ['cliente_nombre', 'telefono'],
        ]);
        final todo = salida.join('\n');
        expect(todo, contains('PUSH_PII_DETECTED'));
        expect(todo, isNot(contains('María')));
        expect(todo, isNot(contains('5555')));
      },
    );
  });

  group('HU-NOT-003 · decisiones del 03/11 sin aplicar (P2 tipos, P3 sin destino)', () {
    // P2: «sumá en #187 los tipos de arriba a TipoPushRemota, con sus textos».
    for (final caso in <(String, Map<String, Object?>, String?)>[
      (
        'ticket_validado',
        {'type': 'ticket_validado', 'ticket_id': _ticket},
        'Tu ticket fue validado',
      ),
      (
        'ticket_rechazado',
        {'type': 'ticket_rechazado', 'ticket_id': _ticket},
        'Tu ticket fue rechazado',
      ),
      (
        'asignacion_campania',
        {'type': 'asignacion_campania', 'campania_id': _campania, 'zona_id': _zona},
        null,
      ),
      ('cuota_pendiente', {'type': 'cuota_pendiente', 'agenda_id': _agenda}, null),
      ('agenda_manana', {'type': 'agenda_manana'}, null),
    ]) {
      testWidgets(
        'P2: el tipo «${caso.$1}» se guarda y se avisa${caso.$3 == null ? '' : ' con «${caso.$3}»'}',
        (tester) async {
          await abrir(tester);

          await llega(tester, {...caso.$2, 'event_id': _evento});

          expect(centro.historial.filas, hasLength(1));
          if (caso.$3 != null) {
            expect(find.text(caso.$3!), findsOneWidget);
          }
        },
      );
    }
    testWidgets('P3: tocar el banner del pedido autorizado abre el centro con el aviso ya leído', (
      tester,
    ) async {
      await abrir(tester);
      await llega(tester, {'type': 'pedido_autorizado', 'pedido_id': _pedido, 'event_id': _evento});

      await tester.tap(_banner);
      await tester.pumpAndSettle();

      expect(_centro, findsOneWidget);
      expect(centro.historial.filas.single.leida, isTrue);
    });
    testWidgets(
      'P3: tocar la notificación del sistema (app en segundo plano) abre el centro con el aviso leído',
      (tester) async {
        await abrir(tester);

        push.seTocaConLaAppEnSegundoPlano({
          'type': 'pedido_autorizado',
          'pedido_id': _pedido,
          'event_id': _evento,
        });
        await tester.pumpAndSettle();

        expect(_centro, findsOneWidget);
        expect(centro.historial.filas.single.leida, isTrue);
      },
    );
    testWidgets('P3: la fila del centro de un aviso sin destino no lleva «›»', (tester) async {
      await abrir(tester);
      await llega(tester, {'type': 'pedido_autorizado', 'pedido_id': _pedido, 'event_id': _evento});
      unawaited(
        navigatorKeyColportores.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const CentroNotificacionesPage()),
        ),
      );
      await tester.pumpAndSettle();

      final fila = find.byKey(const Key('centro_aviso_push-$_evento'));
      expect(fila, findsOneWidget);
      expect(find.descendant(of: fila, matching: find.byIcon(Icons.chevron_right)), findsNothing);
    });

    testWidgets('P3 (parte que sí está): el banner del pedido autorizado no promete «Tocá para ver '
        'el detalle»', (tester) async {
      await abrir(tester);
      await llega(tester, {'type': 'pedido_autorizado', 'pedido_id': _pedido, 'event_id': _evento});

      expect(_banner, findsOneWidget);
      expect(find.text('Tocá para ver el detalle'), findsNothing);
    });
  });

  group('Casos límite del flujo', () {
    testWidgets('ráfaga: 5 copias del mismo evento y 3 distintos → 4 filas, un solo banner (el '
        'último) y sin excepciones', (tester) async {
      await abrir(tester);

      for (var i = 0; i < 5; i++) {
        push.llegaConLaAppAbierta({
          'type': 'pedido_autorizado',
          'pedido_id': _pedido,
          'event_id': _evento,
        });
      }
      for (var i = 1; i <= 3; i++) {
        push.llegaConLaAppAbierta({
          'type': 'pedido_autorizado',
          'pedido_id': _pedido,
          'event_id': _evento_(i),
        });
      }
      await tester.pump(const Duration(milliseconds: 200));

      expect(centro.historial.filas, hasLength(4));
      expect(_banner, findsOneWidget);
      expect(sinLeer(), 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('muchos: 60 push distintas seguidas se guardan todas y no tiran la app', (
      tester,
    ) async {
      await abrir(tester);

      for (var i = 1; i <= 60; i++) {
        push.llegaConLaAppAbierta({
          'type': 'pedido_autorizado',
          'pedido_id': _pedido,
          'event_id': _evento_(i),
        });
      }
      await tester.pump(const Duration(milliseconds: 500));

      expect(centro.historial.filas, hasLength(60));
      expect(_banner, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dos push distintas: la segunda reemplaza al banner de la primera, que queda sin '
        'leer en el centro, y cuenta sus propios 8 s', (tester) async {
      await abrir(tester);
      await llega(tester, {
        'type': 'pedido_autorizado',
        'pedido_id': _pedido,
        'event_id': _evento_(1),
      });
      await tester.pump(const Duration(seconds: 6));
      await llega(tester, {
        'type': 'pedido_autorizado',
        'pedido_id': _pedido,
        'event_id': _evento_(2),
      });

      // 6 s + 5 s: el primero ya habría vencido; el segundo sigue.
      await tester.pump(const Duration(seconds: 5));
      expect(_banner, findsOneWidget);
      expect(sinLeer(), 2);

      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      expect(_banner, findsNothing);
      expect(sinLeer(), 2, reason: 'irse solo no lo marca leído');
    });

    testWidgets('el aviso se queda 8 s (no menos) y después se va, sin perderse del centro', (
      tester,
    ) async {
      await abrir(tester);
      await llega(tester, {'type': 'pedido_autorizado', 'pedido_id': _pedido, 'event_id': _evento});

      await tester.pump(const Duration(seconds: 7));
      expect(_banner, findsOneWidget);
      await tester.pump(const Duration(seconds: 1, milliseconds: 100));
      expect(_banner, findsNothing);
      expect(centro.historial.filas, hasLength(1));
    });

    testWidgets('con un diálogo abierto, el banner sigue a la vista y su ✕ responde', (
      tester,
    ) async {
      await abrir(tester);
      unawaited(
        showDialog<void>(
          context: navigatorKeyColportores.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Un diálogo'), content: Text('Cuerpo')),
        ),
      );
      await tester.pumpAndSettle();

      await llega(tester, {'type': 'pedido_autorizado', 'pedido_id': _pedido, 'event_id': _evento});
      expect(_banner, findsOneWidget);

      await tester.tap(_cerrar);
      await tester.pump();
      expect(_banner, findsNothing);
      expect(
        find.text('Un diálogo'),
        findsOneWidget,
        reason: 'cerrar el aviso no cierra el diálogo',
      );
    });

    testWidgets(
      'con el centro abierto, la push llega a la lista en vivo y también sale el banner',
      (tester) async {
        await abrir(tester);
        unawaited(
          navigatorKeyColportores.currentState!.push(
            MaterialPageRoute<void>(builder: (_) => const CentroNotificacionesPage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('centro_vacio')), findsOneWidget);

        await llega(tester, {
          'type': 'pedido_autorizado',
          'pedido_id': _pedido,
          'event_id': _evento,
        });
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byKey(const Key('centro_vacio')), findsNothing);
        expect(find.byKey(const Key('centro_aviso_push-$_evento')), findsOneWidget);
        expect(_banner, findsOneWidget);
      },
    );

    testWidgets('con la barra de estado / notch de 48 dp el banner arranca debajo, no tapado', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 48);
      addTearDown(tester.view.resetPadding);
      await abrir(tester);

      await llega(tester, {'type': 'pedido_autorizado', 'pedido_id': _pedido, 'event_id': _evento});

      expect(tester.getRect(_banner).top, greaterThanOrEqualTo(48));
    });
    for (final (nombre, tam, escala) in [
      ('390x844 ×1,0', const Size(390, 844), 1.0),
      ('360x640 ×2,0', const Size(360, 640), 2.0),
    ]) {
      testWidgets(
        'P1 del QA: con el aviso a la vista, la campana y el engranaje de Hoy siguen tocables ($nombre)',
        (tester) async {
          tester.view
            ..physicalSize = tam
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = escala;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await abrir(tester);
          await llega(tester, {
            'type': 'pedido_autorizado',
            'pedido_id': _pedido,
            'event_id': _evento,
          });
          expect(_banner, findsOneWidget);

          final aviso = tester.getRect(_banner);
          for (final clave in ['inicio_notificaciones', 'inicio_configuracion']) {
            final boton = tester.getRect(find.byKey(Key(clave)));
            expect(boton.overlaps(aviso), isFalse, reason: '$clave queda tapado por el aviso');
          }
        },
      );
    }

    // skip: QA #187 r4 — decisión P1 del QA (03/11): el aviso «nunca tapa la fecha»; en Hoy la fecha
    // (`jornada_fecha`) queda bajo el aviso (top = barra de estado + 56 + 8, y la fecha va justo abajo).
    for (final (nombre, tam, escala) in [
      ('390x844 ×1,0', const Size(390, 844), 1.0),
      ('360x640 ×2,0', const Size(360, 640), 2.0),
    ]) {
      testWidgets(
        'P1 del QA: con el aviso a la vista, la fecha de Hoy no queda tapada ($nombre)',
        (tester) async {
          tester.view
            ..physicalSize = tam
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = escala;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await abrir(tester);
          await llega(tester, {
            'type': 'pedido_autorizado',
            'pedido_id': _pedido,
            'event_id': _evento,
          });
          expect(_banner, findsOneWidget);

          final fecha = tester.getRect(find.byKey(const Key('jornada_fecha')));
          expect(
            fecha.overlaps(tester.getRect(_banner)),
            isFalse,
            reason: 'la fecha de Hoy queda tapada por el aviso',
          );
        },
        skip: !verHallazgos,
      );
    }

    testWidgets('el toque de la notificación del sistema de un evento nuevo lo guarda ya leído', (
      tester,
    ) async {
      await abrir(tester);

      push.seTocaConLaAppEnSegundoPlano({
        'type': 'pedido_autorizado',
        'pedido_id': _pedido,
        'event_id': _evento,
      });
      await tester.pumpAndSettle();

      expect(centro.historial.filas.map((n) => n.id), ['push-$_evento']);
      expect(sinLeer(), 0);
      expect(_banner, findsNothing, reason: 'con el toque no se avisa dos veces');
    });
  });

  group('Teclado y lector', () {
    testWidgets('el aviso se anuncia: un solo botón con región viva y la ✕ con nombre', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await abrir(tester);
      await llega(tester, {'type': 'pedido_autorizado', 'pedido_id': _pedido, 'event_id': _evento});

      expect(
        tester.getSemantics(_banner),
        isSemantics(label: 'AHORA. Tu pedido fue autorizado', isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(_cerrar),
        isSemantics(label: 'Cerrar aviso', isButton: true, hasTapAction: true),
      );
      expect(find.bySemanticsLabel(RegExp('AHORA')), findsOneWidget);
      semantica.dispose();
    });
  });

  group('Validación del payload (R-NO02) · el mensaje llega de afuera y no es confiable', () {
    // Valores que no son string, claves raras, mensajes enormes: nada tira la app ni se muestra.
    final hostiles = <String, Map<String, Object?>>{
      'vacío': {},
      'solo type': {'type': 'pedido_autorizado'},
      'type nulo': {'type': null, 'pedido_id': _pedido},
      'type numérico': {'type': 7, 'pedido_id': _pedido},
      'type con mayúsculas': {'type': 'PEDIDO_AUTORIZADO', 'pedido_id': _pedido},
      'type con emoji': {'type': 'pedido_autorizado 🎉', 'pedido_id': _pedido},
      'type larguísimo': {'type': 'a' * 5000, 'pedido_id': _pedido},
      'pedido_id con nombre': {'type': 'pedido_autorizado', 'pedido_id': 'María Fernández'},
      'pedido_id con emoji': {'type': 'pedido_autorizado', 'pedido_id': '👤👤👤'},
      'pedido_id vacío': {'type': 'pedido_autorizado', 'pedido_id': ''},
      'pedido_id mapa': {
        'type': 'pedido_autorizado',
        'pedido_id': {'x': 1},
      },
      'pedido_id lista': {
        'type': 'pedido_autorizado',
        'pedido_id': [_pedido],
      },
      'pedido_id con espacios': {'type': 'pedido_autorizado', 'pedido_id': ' $_pedido '},
      'event_id no UUID': {
        'type': 'pedido_autorizado',
        'pedido_id': _pedido,
        'event_id': 'evento-1',
      },
      'campo extra': {'type': 'pedido_autorizado', 'pedido_id': _pedido, 'body': 'Tu pedido'},
      'clave con emoji': {'type': 'pedido_autorizado', 'pedido_id': _pedido, '👤': 'x'},
      'clave enorme': {'type': 'pedido_autorizado', 'pedido_id': _pedido, 'k' * 5000: 'x'},
      '500 campos': {
        'type': 'pedido_autorizado',
        'pedido_id': _pedido,
        for (var i = 0; i < 500; i++) 'campo_$i': 'dato $i',
      },
    };

    for (final MapEntry(key: nombre, value: datos) in hostiles.entries) {
      testWidgets('«$nombre» no muestra ni guarda nada, y no tira la app', (tester) async {
        await abrir(tester);

        await llega(tester, datos);

        expect(_banner, findsNothing);
        expect(centro.historial.filas, isEmpty);
        expect(tester.takeException(), isNull);
        // Lo auditado son nombres de campo, de a lo sumo 10, nunca valores.
        for (final campos in auditoria.descartadas) {
          expect(campos.length, lessThanOrEqualTo(InterpretadorPushRemota.maximoDeCamposAuditados));
          for (final c in campos) {
            expect(c.length, lessThanOrEqualTo(40));
            expect(c, isNot(contains('María')));
            expect(c, isNot(contains(_pedido)));
          }
        }
      });
    }

    testWidgets(
      'un type que la app no conoce (servidor adelantado) se ignora sin auditar como PII',
      (tester) async {
        await abrir(tester);

        await llega(tester, {'type': 'tipo_del_futuro', 'foo_id': _pedido});

        expect(_banner, findsNothing);
        expect(centro.historial.filas, isEmpty);
        expect(auditoria.descartadas, isEmpty);
      },
    );

    test('InterpretadorPushRemota: la lectura de una clave con un valor personal no lo repite', () {
      final lectura = InterpretadorPushRemota.leer({
        'type': 'pedido_autorizado',
        'pedido_id': _pedido,
        'cliente_nombre': 'María Fernández',
      });
      expect(lectura, isA<PushConDatosPersonales>());
      expect((lectura as PushConDatosPersonales).campos, ['cliente_nombre']);
    });

    testWidgets('con la base cerrada / sin sesión no se escucha: la push se pierde sin romper', (
      tester,
    ) async {
      await abrirApp(tester, _telefono(), iniciarSesion: false, extra: extra());

      await llega(tester, {'type': 'pedido_autorizado', 'pedido_id': _pedido, 'event_id': _evento});

      expect(_banner, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
