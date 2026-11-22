// QA de #539 / PR #623 (tanda 2 de tests saltados: notificaciones y recordatorios). Lo que los tests
// del implementador no recorren del centro de notificaciones (vista 24, grupo C) y de la campana:
// el aviso (SnackBar) que cede su altura a la lista (a 1,0× y 2,0×, con 5 y con 300 avisos, dos
// avisos seguidos, descartado con el dedo), «Borrar todas» por ids (llega uno con hora anterior con la
// confirmación abierta, falla y reintento, doble toque, 300 avisos) y la campana con el globo «99+»
// en un barrido de escalas.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/textos_centro_notificaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/historial_notificaciones_falsos.dart';
import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;
import '../helpers/qa_centro_notificaciones_156_arnes.dart';

final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

/// El aviso entra y se asienta (animación de 250 ms y el cuadro que mide su alto).
Future<void> _asentarAviso(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// El aviso se va solo (8 s) y la lista recupera su alto.
Future<void> _esperarQueSeVaya(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 12));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

/// Cuánto del aviso entra en la parte visible de la lista (lo que asoma de la fila por encima del
/// borde de la lista no cuenta: el scroll la recorta).
double _tapado(WidgetTester tester, Finder fila) {
  final aviso = find.byType(SnackBar);
  if (aviso.evaluate().isEmpty) return 0;
  final visible = tester.getRect(fila).intersect(tester.getRect(centroLista));
  final t = tester.getRect(aviso).intersect(visible);
  return t.width > 0 && t.height > 0 ? t.height : 0;
}

void main() {
  group('el aviso cede su altura a la lista', () {
    for (final tam in tamanos) {
      for (final escala in escalas) {
        testWidgets(
          '5 avisos · ${tam.nombre} · texto ${escala}x: el aviso no tapa la fila tocada y al irse '
          'la lista recupera su alto',
          (tester) async {
            final arnes = CentroArnes(avisos: cincoDelCanvas())..destinos.todosExisten = false;
            await abrirCentro(tester, arnes, tamano: Size(tam.ancho, tam.alto), texto: escala);
            final altoInicial = tester.getRect(centroLista).height;
            await tester.drag(centroLista, const Offset(0, -4000));
            await tester.pumpAndSettle();
            await tester.tap(filaDe('e'));
            await _asentarAviso(tester);

            // ignore: avoid_print
            print(
              'DBG ${tam.nombre} $escala lista=${tester.getRect(centroLista)} fila=${tester.getRect(filaDe("e"))} aviso=${tester.getRect(find.byType(SnackBar))} alto0=$altoInicial',
            );
            expect(find.byType(SnackBar), findsOneWidget);
            expect(find.text(TextosCentroNotificaciones.errorAlAbrir), findsNothing);
            expect(_tapado(tester, filaDe('e')), 0, reason: 'el aviso tapa la fila');
            expect(tester.takeException(), isNull);
            // Con el aviso a la vista se puede llegar a la última fila entera, por encima del aviso.
            await tester.drag(centroLista, const Offset(0, -4000));
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              tester.getRect(filaDe('e')).bottom,
              lessThanOrEqualTo(tester.getRect(find.byType(SnackBar)).top + 0.5),
              reason: 'la última fila queda detrás del aviso aun con la lista al final',
            );

            await _esperarQueSeVaya(tester);
            expect(find.byType(SnackBar), findsNothing);
            expect(
              tester.getRect(centroLista).height,
              altoInicial,
              reason: 'la reserva del aviso quedó puesta después de irse',
            );
          },
        );

        testWidgets(
          '300 avisos, al final de la lista · ${tam.nombre} · texto ${escala}x: el aviso no tapa '
          'la última fila',
          (tester) async {
            final arnes = CentroArnes(avisos: trescientos())..destinos.todosExisten = false;
            await abrirCentro(tester, arnes, tamano: Size(tam.ancho, tam.alto), texto: escala);
            for (var i = 0; i < 40; i++) {
              await tester.drag(centroLista, const Offset(0, -6000));
              await tester.pump();
            }
            await tester.pumpAndSettle();
            await tester.tap(filaDe('m-299'));
            await _asentarAviso(tester);

            expect(find.byType(SnackBar), findsOneWidget);
            expect(filaDe('m-299'), findsOneWidget);
            expect(_tapado(tester, filaDe('m-299')), 0);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('dos avisos seguidos (dos filas sin destino): queda uno solo y, al irse, ninguna '
        'reserva', (tester) async {
      final arnes = CentroArnes(avisos: cincoDelCanvas())..destinos.todosExisten = false;
      await abrirCentro(tester, arnes, tamano: const Size(360, 640), texto: 2);
      final altoInicial = tester.getRect(centroLista).height;

      await tester.tap(filaDe('a'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(filaDe('b'));
      await _asentarAviso(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _esperarQueSeVaya(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.getRect(centroLista).height, altoInicial);
    });

    testWidgets('el aviso descartado con el dedo también devuelve su altura a la lista', (
      tester,
    ) async {
      final arnes = CentroArnes(avisos: cincoDelCanvas())..destinos.todosExisten = false;
      await abrirCentro(tester, arnes, tamano: const Size(360, 640), texto: 2);
      final altoInicial = tester.getRect(centroLista).height;
      await tester.tap(filaDe('a'));
      await _asentarAviso(tester);
      expect(tester.getRect(centroLista).height, lessThan(altoInicial));

      await tester.drag(find.byType(SnackBar), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(tester.getRect(centroLista).height, altoInicial);
    });

    testWidgets('la falla de «Marcar todas» avisa y no tapa la última fila a 360×640 ×2,0', (
      tester,
    ) async {
      final arnes = CentroArnes(avisos: cincoDelCanvas());
      arnes.historial.fallaAlMarcarTodas = true;
      await abrirCentro(tester, arnes, tamano: const Size(360, 640), texto: 2);
      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
      await tester.ensureVisible(menuMarcarTodas);
      await tester.tap(menuMarcarTodas);
      await tester.pumpAndSettle();
      await _asentarAviso(tester);

      expect(find.text(TextosCentroNotificaciones.errorAlMarcar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.drag(centroLista, const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(_tapado(tester, filaDe('e')), 0);
    });
  });

  group('«Borrar todas» borra los avisos de la cuenta que se mostró', () {
    Future<void> hastaConfirmar(WidgetTester tester) async {
      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
      await tester.ensureVisible(menuBorrarTodas);
      await tester.tap(menuBorrarTodas);
      await tester.pumpAndSettle();
    }

    testWidgets('llega un aviso con hora de hace 3 días con la confirmación abierta: sobrevive, y '
        'el pedido lleva exactamente los 5 ids contados', (tester) async {
      final arnes = CentroArnes(avisos: cincoDelCanvas());
      await abrirCentro(tester, arnes, tamano: const Size(412, 915));
      await hastaConfirmar(tester);
      expect(find.text('¿Borrar las 5 notificaciones?'), findsOneWidget);
      arnes.historial.llegaUno(aviso('tardio', hace: const Duration(days: 3)));
      await tester.pump();
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();

      expect(arnes.historial.borrados.single, {'a', 'b', 'c', 'd', 'e'});
      expect(arnes.historial.filas.map((f) => f.id), ['tardio']);
      expect(filaDe('tardio'), findsOneWidget, reason: 'el que llegó después se sigue viendo');
    });

    testWidgets('falla al borrar, llega un aviso y se reintenta: el reintento lleva los mismos '
        '5 ids y el que llegó después sobrevive', (tester) async {
      final arnes = CentroArnes(avisos: cincoDelCanvas());
      arnes.historial.fallaAlBorrar = true;
      await abrirCentro(tester, arnes, tamano: const Size(360, 640), texto: 2);
      await hastaConfirmar(tester);
      await tester.ensureVisible(borrarConfirmar);
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();
      expect(borrarError, findsOneWidget);

      arnes.historial
        ..llegaUno(aviso('despues', hace: const Duration(days: 9)))
        ..fallaAlBorrar = false;
      await tester.pump();
      await tester.ensureVisible(borrarConfirmar);
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();

      expect(arnes.historial.borrados, hasLength(2));
      expect(arnes.historial.borrados.last, {'a', 'b', 'c', 'd', 'e'});
      expect(arnes.historial.filas.map((f) => f.id), ['despues']);
    });

    testWidgets('doble toque en «Borrar»: un solo pedido', (tester) async {
      final arnes = CentroArnes(avisos: cincoDelCanvas());
      arnes.historial.puertaAlBorrar = Completer<void>();
      await abrirCentro(tester, arnes, tamano: const Size(390, 844));
      await hastaConfirmar(tester);
      await tester.tap(borrarConfirmar);
      await tester.pump();
      await tester.tap(borrarConfirmar, warnIfMissed: false);
      await tester.pump();
      await tester.tap(borrarConfirmar, warnIfMissed: false);
      await tester.pump();

      expect(arnes.historial.borrados, hasLength(1));
      arnes.historial.puertaAlBorrar!.complete();
      await tester.pumpAndSettle();
      expect(arnes.historial.filas, isEmpty);
      expect(centroVacio, findsOneWidget);
    });

    testWidgets('300 avisos: el pedido lleva los 300 ids y el centro queda vacío', (tester) async {
      final arnes = CentroArnes(avisos: trescientos());
      await abrirCentro(tester, arnes, tamano: const Size(412, 915));
      await hastaConfirmar(tester);
      expect(find.text('¿Borrar las 300 notificaciones?'), findsOneWidget);
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();

      expect(arnes.historial.borrados.single, hasLength(300));
      expect(centroVacio, findsOneWidget);
      expect(centroMenu, findsNothing);
    });
  });

  group('la campana con el globo «99+» en un barrido de escalas', () {
    Future<void> montar(
      WidgetTester tester, {
      required int sinLeer,
      required double ancho,
      required double alto,
      required double escala,
    }) async {
      final avisos = [
        for (var i = 0; i < sinLeer; i++) aviso('n-$i', hace: Duration(minutes: i + 1)),
      ];
      final arnes = CentroArnes(avisos: avisos);
      tester.view
        ..physicalSize = Size(ancho, alto)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
            disparadorBackupProvider.overrideWithValue(_BackupFalso()),
            relojJornadaProvider.overrideWithValue(() => ahoraDelCentro),
            ...overridesPestanaMapa(),
            ...arnes.overrides,
          ],
          child: MaterialApp(
            theme: temaClaro(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
              child: child!,
            ),
            home: InicioPage(sesion: _sesion),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final tam in tamanos) {
      for (final escala in const [1.0, 1.3, 1.6, 2.0]) {
        testWidgets(
          '120 sin leer · ${tam.nombre} · texto ${escala}x: campana y engranaje a la vista, sin '
          'pisarse y con el globo fuera del ícono del engranaje',
          (tester) async {
            await montar(tester, sinLeer: 120, ancho: tam.ancho, alto: tam.alto, escala: escala);

            expect(tester.takeException(), isNull, reason: 'sin RenderFlex overflowed');
            final campana = tester.getRect(find.byKey(const Key('inicio_notificaciones')));
            final engranaje = tester.getRect(find.byKey(const Key('inicio_configuracion')));
            final icono = tester.getRect(
              find.descendant(
                of: find.byKey(const Key('inicio_configuracion')),
                matching: find.byType(Icon),
              ),
            );
            final globo = tester.getRect(find.byKey(const Key('inicio_notificaciones_numero')));
            expect(campana.width, greaterThanOrEqualTo(48));
            expect(campana.height, greaterThanOrEqualTo(48));
            expect(campana.overlaps(engranaje), isFalse);
            expect(engranaje.right, lessThanOrEqualTo(tam.ancho));
            expect(campana.left, greaterThanOrEqualTo(0));
            // A 1,0× el globo ya rozaba la esquina del ícono (4 dp, antes del PR); el lugar que deja
            // la campana es lo que se prueba desde 1,6×.
            expect(
              (escala < 1.5 ? globo.deflate(4.1) : globo).overlaps(icono),
              isFalse,
              reason: 'globo $globo, ícono del engranaje $icono, campana $campana',
            );
          },
        );
      }
    }

    // Más allá de lo que pide el proyecto (2,0× a 360×640 y 412×915): el desborde del encabezado
    // con el globo, comparado con el mismo tamaño sin globo, dice si lo causa el lugar que se le deja.
    for (final c in const [
      (nombre: '320x568', ancho: 320.0, alto: 568.0, escala: 2.0),
      (nombre: '360x640', ancho: 360.0, alto: 640.0, escala: 2.5),
      (nombre: '360x640', ancho: 360.0, alto: 640.0, escala: 3.0),
      (nombre: '412x915', ancho: 412.0, alto: 915.0, escala: 3.0),
    ]) {
      testWidgets(
        'el globo no agrega desborde al encabezado de Hoy · ${c.nombre} · texto ${c.escala}x',
        (tester) async {
          await montar(tester, sinLeer: 0, ancho: c.ancho, alto: c.alto, escala: c.escala);
          final sinGlobo = tester.takeException() == null;
          await montar(tester, sinLeer: 120, ancho: c.ancho, alto: c.alto, escala: c.escala);
          final conGlobo = tester.takeException() == null;

          expect(
            conGlobo,
            sinGlobo,
            reason:
                'sin globo ${sinGlobo ? "no desborda" : "desborda"}; con globo '
                '${conGlobo ? "no desborda" : "desborda"}',
          );
        },
      );
    }
  });
}
