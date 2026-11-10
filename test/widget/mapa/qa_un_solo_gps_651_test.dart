// QA #651 (PR #660): un solo GPS del colportor. Se prueba de punta a punta por la pantalla
// principal (Hoy · Mapa · Lista) y el alta, con un único `GpsFalso` que cuenta cuántas veces se le
// pidió una lectura (= cuántas veces el sistema habría mostrado el diálogo del permiso).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart'
    show LecturaGps;
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_state.dart'
    show EstadoGpsLista;
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
import 'lista_ubicaciones_arnes.dart' show asentarLista;

final _sesion = Sesion(
  usuarioId: 'col-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

/// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas/`,
/// fuera del commit).
const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');
final _raiz = GlobalKey();

Future<void> _cargarFuentes(WidgetTester tester) async {
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
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(iconos.readAsBytesSync().buffer)));
        await cargador.load();
        break;
      }
    }
  });
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/651_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

Either<Failure, LecturaGps> _sin(MotivoSinGps motivo) =>
    Left(FailureGpsNoDisponible(motivo: motivo));

Future<void> _montar(
  WidgetTester tester, {
  required GpsFalso gps,
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  _hojaAbierta = false;
  if (_conCapturas) await _cargarFuentes(tester);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => DateTime(2026, 10, 6, 15)),
        ...overridesLista(
          repo: RepoListaFalso([filaLista('a', calle: 'Rivadavia', numero: '100')]),
          gps: gps,
        ),
        ...overridesPestanaMapa(),
      ],
      child: RepaintBoundary(
        key: _raiz,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: InicioPage(sesion: _sesion),
        ),
      ),
    ),
  );
  await asentarLista(tester);
}

var _hojaAbierta = false;

/// Va a la pestaña; la primera vez en «Mapa» sube la hoja (arranca minimizada) para ver sus avisos.
Future<void> _irA(WidgetTester tester, String pestana) async {
  await tester.tap(find.byKey(Key('inicio_pestana_$pestana')));
  await asentarLista(tester);
  if (pestana == 'mapa' && !_hojaAbierta) {
    _hojaAbierta = true;
    await tester.tap(find.byKey(ClavesMapaUbicaciones.asa));
    await asentarLista(tester);
  }
}

ProviderContainer _contenedor(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

Future<void> _alVolverALaApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await asentarLista(tester);
}

final _activarEnElMapa = find.byKey(ClavesMapaUbicaciones.activarGps);
final _chipDeLaLista = find.text('◎ Sin GPS');
final _chipSinPedir = find.text('◎ Sin GPS · Activar GPS');

void main() {
  group('Criterio: primera vez en el Mapa, un solo diálogo; las demás vistas nunca lo piden', () {
    testWidgets(
      'dado permiso denegado, cuando recorre Hoy → Lista → Mapa → Lista → Hoy → Mapa, entonces '
      'el sistema se consulta una sola vez y nada se abre solo',
      (tester) async {
        final gps = GpsFalso(_sin(MotivoSinGps.permisoDenegado));
        await _montar(tester, gps: gps);
        expect(gps.lecturas, 0, reason: 'arrancar la app no lee el GPS');

        await _irA(tester, 'lista');
        expect(gps.lecturas, 0, reason: 'la Lista no pide el permiso');
        expect(_chipSinPedir, findsOneWidget, reason: 'sin pasar por el mapa se ofrece activarlo');

        await _irA(tester, 'mapa');
        expect(gps.lecturas, 1, reason: 'el mapa pide el permiso, una vez');
        expect(_activarEnElMapa, findsOneWidget);
        expect(find.text('Sin GPS no podemos ordenarlas por cercanía.'), findsOneWidget);

        await _irA(tester, 'lista');
        expect(_chipDeLaLista, findsOneWidget);
        await _irA(tester, 'hoy');
        await _irA(tester, 'mapa');

        expect(gps.lecturas, 1, reason: 'denegado no se vuelve a pedir solo al reentrar');
        expect(gps.activaciones, isEmpty, reason: 'no se abrió ningún permiso ni ajuste');
      },
    );

    testWidgets(
      'dado permiso otorgado, cuando abre la Lista y el alta después del Mapa, entonces la Lista no '
      'lee y el alta lee una vez (#670: nunca parte de una lectura vieja) sin pedir el permiso',
      (tester) async {
        final gps = GpsFalso(Right(lecturaGps(6)));
        await _montar(tester, gps: gps);
        await _irA(tester, 'mapa');
        expect(gps.lecturas, 1);

        await _irA(tester, 'lista');
        await tester.tap(find.byKey(const Key('lista_nueva')));
        await asentarLista(tester);

        expect(find.byType(AltaUbicacionPage), findsOneWidget);
        expect(gps.lecturas, 2, reason: 'solo el alta lee, una vez; la Lista no');
        expect(gps.activaciones, isEmpty, reason: 'sin diálogo: el permiso ya estaba dado');
        expect(find.textContaining('±6'), findsWidgets, reason: 'el alta usa la lectura nueva');
        expect(find.text('Activar GPS'), findsNothing);
      },
    );

    testWidgets(
      'dado que nunca pasó por el Mapa, cuando abre el alta desde la Lista, entonces dice qué hacer '
      '(«Activar GPS») sin mostrar el diálogo, y al tocarlo lee una vez',
      (tester) async {
        final gps = GpsFalso(Right(lecturaGps(6)));
        await _montar(tester, gps: gps);
        await _irA(tester, 'lista');

        await tester.tap(find.byKey(const Key('lista_nueva')));
        await asentarLista(tester);

        expect(gps.lecturas, 0, reason: 'el alta no pide el permiso');
        expect(find.text('Activar GPS'), findsOneWidget);
        await tester.tap(find.text('Activar GPS'));
        await asentarLista(tester);
        expect(gps.lecturas, 1);
        expect(find.text('Activar GPS'), findsNothing);
      },
    );
  });

  group('«Activar GPS»: una acción del GPS único', () {
    testWidgets(
      'dado permiso denegado, cuando toca «Activar GPS» en el mapa y lo da, entonces la Lista y el '
      'mapa se enteran sin salir de la pestaña',
      (tester) async {
        final gps = GpsFalso(_sin(MotivoSinGps.permisoDenegado))..alActivar = () {};
        await _montar(tester, gps: gps);
        await _irA(tester, 'mapa');
        gps.alActivar = () => gps.respuesta = Right(lecturaGps(9));

        await tester.tap(_activarEnElMapa);
        await asentarLista(tester);

        expect(gps.activaciones, [MotivoSinGps.permisoDenegado]);
        expect(_activarEnElMapa, findsNothing);
        await _irA(tester, 'lista');
        expect(_chipDeLaLista, findsNothing);
        expect(find.textContaining('GPS ±9'), findsOneWidget);
      },
    );

    testWidgets(
      'dado el chip de la Lista, cuando lo toca con el diálogo abierto, entonces la lleva al mapa '
      '(un solo diálogo, ya no sobre la Lista) y al cerrarlo puede volver a tocarlo',
      (tester) async {
        final gps = GpsFalso(_sin(MotivoSinGps.permisoDenegado));
        await _montar(tester, gps: gps);
        await _irA(tester, 'mapa');
        await _irA(tester, 'lista');
        gps.bloqueoActivacion = Completer<void>();

        await tester.tap(_chipDeLaLista);
        await tester.pump();
        // La Lista pasó a segundo plano: no hay segundo chip que tocar sobre el diálogo abierto.
        expect(_chipDeLaLista, findsNothing);
        expect(gps.activaciones, hasLength(1), reason: 'un solo diálogo, el del mapa');

        gps.bloqueoActivacion!.complete();
        await asentarLista(tester);
        gps.bloqueoActivacion = null;
        await _irA(tester, 'lista');
        await tester.tap(_chipDeLaLista);
        await asentarLista(tester);
        expect(gps.activaciones, hasLength(2), reason: 'no quedó nada trabado');
      },
    );

    testWidgets(
      'dado que el sistema falla al abrir el permiso, cuando toca «Activar GPS», entonces no queda '
      'trabado: lee igual y el botón sigue disponible',
      (tester) async {
        final gps = GpsFalso(_sin(MotivoSinGps.servicioApagado));
        await _montar(tester, gps: gps);
        await _irA(tester, 'mapa');
        gps.alActivar = () => throw PlatformException(code: 'sin_ajustes');

        await tester.tap(_activarEnElMapa);
        await asentarLista(tester);

        expect(tester.takeException(), isNull);
        expect(gps.lecturas, 2, reason: 'lee igual por si lo activó por su cuenta');
        expect(_activarEnElMapa, findsOneWidget);
        await tester.tap(_activarEnElMapa);
        await asentarLista(tester);
        expect(gps.activaciones, hasLength(2));
      },
    );

    testWidgets(
      'dado que volvió de otra app (WhatsApp) sin tocar «Activar GPS», cuando regresa, entonces no '
      'se vuelve a leer; si lo tocó, se reintenta una sola vez',
      (tester) async {
        final gps = GpsFalso(_sin(MotivoSinGps.permisoDenegado));
        await _montar(tester, gps: gps);
        await _irA(tester, 'mapa');
        expect(gps.lecturas, 1);

        await _alVolverALaApp(tester);
        expect(gps.lecturas, 1, reason: 'volver de WhatsApp no muestra el diálogo');

        await tester.tap(_activarEnElMapa);
        await asentarLista(tester);
        expect(gps.lecturas, 2);
        gps.respuesta = Right(lecturaGps(7));
        await _alVolverALaApp(tester);
        expect(gps.lecturas, 3, reason: 'volvió de los ajustes: se reintenta');
        expect(_activarEnElMapa, findsNothing);
        await _alVolverALaApp(tester);
        expect(gps.lecturas, 3, reason: 'una sola vez');
      },
    );
  });

  group('Reentrada y lecturas superpuestas', () {
    testWidgets(
      'dado que la primera lectura tarda, cuando cambia de pestaña y vuelve al Mapa, entonces no se '
      'pide una segunda lectura encima y el estado «Buscando GPS…» termina en el resultado',
      (tester) async {
        final gps = GpsFalso(Right(lecturaGps(5)))..bloqueo = Completer<void>();
        await _montar(tester, gps: gps);
        await _irA(tester, 'mapa');
        expect(find.text('Buscando GPS…'), findsOneWidget);

        await _irA(tester, 'lista');
        expect(find.text('◎ Buscando GPS…'), findsOneWidget);
        await _irA(tester, 'mapa');
        expect(gps.lecturas, 1, reason: 'una lectura en curso no se duplica');

        gps.bloqueo!.complete();
        await asentarLista(tester);
        expect(find.text('Buscando GPS…'), findsNothing);
        await _irA(tester, 'lista');
        expect(find.textContaining('GPS ±5'), findsOneWidget);
      },
    );

    testWidgets(
      'dado una lectura buena, cuando el refresco siguiente falla (sin señal), entonces la Lista y '
      'el mapa conservan la última posición y no aparece «Activar GPS»',
      (tester) async {
        final gps = GpsFalso(Right(lecturaGps(5)));
        await _montar(tester, gps: gps);
        await _irA(tester, 'mapa');
        gps.respuesta = _sin(MotivoSinGps.sinSenal);

        await _irA(tester, 'hoy');
        await _irA(tester, 'mapa');

        expect(gps.lecturas, 2);
        expect(_activarEnElMapa, findsNothing);
        await _irA(tester, 'lista');
        expect(_chipDeLaLista, findsNothing);
        expect(find.textContaining('GPS ±5'), findsOneWidget);
      },
    );

    testWidgets(
      'dado sin señal al entrar, cuando reentra al Mapa y ahora hay señal, entonces se recupera '
      'solo (sin señal no es un permiso: no hay diálogo que repetir)',
      (tester) async {
        final gps = GpsFalso(_sin(MotivoSinGps.sinSenal));
        await _montar(tester, gps: gps);
        await _irA(tester, 'mapa');
        expect(_activarEnElMapa, findsOneWidget);
        gps.respuesta = Right(lecturaGps(8));

        await _irA(tester, 'hoy');
        await _irA(tester, 'mapa');

        expect(gps.lecturas, 2);
        expect(_activarEnElMapa, findsNothing);
      },
    );
  });

  group('Privacidad', () {
    testWidgets('el estado del GPS único no vuelca la posición en toString()', (tester) async {
      final gps = GpsFalso(Right(lecturaGps(5)));
      await _montar(tester, gps: gps);
      await _irA(tester, 'mapa');

      final estado = _contenedor(tester).read(ubicacionColportorProvider);

      expect(estado.gps, EstadoGpsLista.conLectura);
      expect(estado.toString(), isNot(contains('-34')));
      expect(estado.toString(), isNot(contains('-58')));
      expect(estado.lectura.toString(), isNot(contains('-34')));
    });
  });

  group(
    'Accesibilidad y tamaños (360×640 y 412×915, texto 1.0 y 2.0; la app no tiene tema oscuro)',
    () {
      final estados = <String, Either<Failure, LecturaGps> Function()>{
        'con lectura': () => Right(lecturaGps(6)),
        'permiso denegado': () => _sin(MotivoSinGps.permisoDenegado),
        'ubicación apagada': () => _sin(MotivoSinGps.servicioApagado),
        'sin señal': () => _sin(MotivoSinGps.sinSenal),
        'buscando': () => Right(lecturaGps(6)),
      };
      for (final tamano in const [Size(360, 640), Size(412, 915)]) {
        for (final escala in const [1.0, 2.0]) {
          {
            for (final entrada in estados.entries) {
              for (final pestana in const ['mapa', 'lista']) {
                testWidgets(
                  '$pestana · ${entrada.key} · ${tamano.width.toInt()}×${tamano.height.toInt()} · '
                  'texto $escala: sin overflow y con las guías de accesibilidad',
                  (tester) async {
                    final handle = tester.ensureSemantics();
                    final gps = GpsFalso(entrada.value());
                    if (entrada.key == 'buscando') gps.bloqueo = Completer<void>();
                    await _montar(tester, gps: gps, tamano: tamano, escala: escala);
                    await _irA(tester, 'mapa');
                    if (pestana == 'lista') await _irA(tester, 'lista');

                    expect(tester.takeException(), isNull);
                    await _capturar(
                      tester,
                      '${pestana}_${entrada.key.replaceAll(' ', '_')}_${tamano.width.toInt()}_x$escala',
                    );
                    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
                    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
                    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
                    // Con las fuentes reales (capturas) la guía da falsos negativos: se mide sin ellas.
                    if (!_conCapturas) {
                      await expectLater(tester, meetsGuideline(textContrastGuideline));
                    }
                    handle.dispose();
                  },
                );
              }
            }
          }
        }
      }
    },
  );

  group('Alta de ubicación con el GPS único (360×640 y 412×915, texto 1.0 y 2.0)', () {
    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final escala in const [1.0, 2.0]) {
        for (final caso in const ['sin pasar por el mapa', 'permiso denegado', 'con lectura']) {
          testWidgets(
            '$caso · ${tamano.width.toInt()}×${tamano.height.toInt()} · texto $escala: sin '
            'overflow, con «Activar GPS» alcanzable y las guías de accesibilidad',
            (tester) async {
              final handle = tester.ensureSemantics();
              final gps = GpsFalso(
                caso == 'con lectura' ? Right(lecturaGps(6)) : _sin(MotivoSinGps.permisoDenegado),
              );
              await _montar(tester, gps: gps, tamano: tamano, escala: escala);
              if (caso != 'sin pasar por el mapa') await _irA(tester, 'mapa');
              await _irA(tester, 'lista');
              await tester.tap(find.byKey(const Key('lista_nueva')));
              await asentarLista(tester);

              expect(find.byType(AltaUbicacionPage), findsOneWidget);
              expect(tester.takeException(), isNull);
              if (caso != 'con lectura') {
                expect(find.text('Activar GPS'), findsOneWidget);
                expect(
                  find.textContaining('No tenemos tu ubicación. Tocá el mapa donde está el lugar'),
                  findsOneWidget,
                );
              }
              await _capturar(
                tester,
                'alta_${caso.replaceAll(' ', '_')}_${tamano.width.toInt()}_x$escala',
              );
              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
              // Con las fuentes reales (capturas) la guía da falsos negativos: se mide sin ellas.
              if (!_conCapturas) {
                await expectLater(tester, meetsGuideline(textContrastGuideline));
              }
              handle.dispose();
            },
          );
        }
      }
    }

    testWidgets(
      'dado que el colportor se movió desde la última lectura del mapa, cuando abre el alta, '
      'entonces el pin arranca en la posición de ahora (decisión #670: nunca una lectura vieja)',
      (tester) async {
        final gps = GpsFalso(Right(lecturaGps(6)));
        await _montar(tester, gps: gps);
        await _irA(tester, 'mapa');
        gps.respuesta = Right(lecturaGps(6, punto: const Coordenadas(lat: -34.88, lon: -56.1302)));
        final antes = gps.lecturas;

        await _irA(tester, 'lista');
        await tester.tap(find.byKey(const Key('lista_nueva')));
        await asentarLista(tester);

        expect(gps.lecturas, antes + 1, reason: 'el alta lee una vez al abrirse');
        expect(find.text('-34.88000, -56.13020'), findsOneWidget, reason: 'el pin sale de ahora');
      },
    );
  });

  group('Delta: «Activar GPS» de la Lista lleva al Mapa (commit 6378f78c)', () {
    testWidgets(
      'dado que nunca pasó por el Mapa, cuando toca el chip de la Lista, entonces va al Mapa, que '
      'lee una sola vez (un solo diálogo) y la Lista se actualiza',
      (tester) async {
        final gps = GpsFalso(Right(lecturaGps(7)));
        await _montar(tester, gps: gps);
        await _irA(tester, 'lista');
        expect(gps.lecturas, 0);

        await tester.tap(_chipSinPedir);
        await asentarLista(tester);

        expect(find.byKey(const Key('pestana_mapa')), findsOneWidget);
        expect(gps.lecturas, 1, reason: 'solo el mapa lee');
        expect(gps.activaciones, isEmpty, reason: 'sin motivo previo no hay ajuste que abrir');
        await _irA(tester, 'lista');
        expect(_chipSinPedir, findsNothing);
        expect(find.textContaining('GPS ±7'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que nunca pasó por el Mapa y el permiso se niega, cuando toca el chip, entonces queda '
      'en el Mapa con «Activar GPS» a mano y la Lista pasa a «Sin GPS» sin repetir el diálogo',
      (tester) async {
        final gps = GpsFalso(_sin(MotivoSinGps.permisoDenegado));
        await _montar(tester, gps: gps);
        await _irA(tester, 'lista');

        await tester.tap(_chipSinPedir);
        await asentarLista(tester);

        expect(gps.lecturas, 1);
        // La hoja del mapa arranca minimizada: se sube para ver el aviso.
        await tester.tap(find.byKey(ClavesMapaUbicaciones.asa));
        await asentarLista(tester);
        expect(_activarEnElMapa, findsOneWidget);
        await _irA(tester, 'lista');
        expect(_chipDeLaLista, findsOneWidget);
        expect(_chipSinPedir, findsNothing);
      },
    );

    testWidgets(
      'dado sin señal, cuando toca el chip de la Lista, entonces no se superponen dos lecturas '
      'que muestren dos diálogos (activar + abrir la pestaña)',
      (tester) async {
        final gps = GpsFalso(_sin(MotivoSinGps.sinSenal));
        await _montar(tester, gps: gps);
        await _irA(tester, 'mapa');
        await _irA(tester, 'lista');
        final antes = gps.lecturas;

        await tester.tap(_chipDeLaLista);
        await asentarLista(tester);

        expect(gps.lecturas - antes, lessThanOrEqualTo(2));
        expect(gps.activaciones, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );

    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final escala in const [1.0, 2.0]) {
        testWidgets('chip «◎ Sin GPS · Activar GPS» de la Lista · ${tamano.width.toInt()}×'
            '${tamano.height.toInt()} · texto $escala: sin overflow, dentro de la pantalla y con las '
            'guías de accesibilidad', (tester) async {
          final handle = tester.ensureSemantics();
          await _montar(tester, gps: GpsFalso(), tamano: tamano, escala: escala);
          await _irA(tester, 'lista');

          expect(tester.takeException(), isNull);
          final caja = tester.getRect(_chipSinPedir);
          expect(caja.left, greaterThanOrEqualTo(0));
          expect(caja.right, lessThanOrEqualTo(tamano.width));
          await _capturar(tester, 'lista_sin_pedir_${tamano.width.toInt()}_x$escala');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          if (!_conCapturas) {
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          }
          handle.dispose();
        });
      }
    }
  });
}
