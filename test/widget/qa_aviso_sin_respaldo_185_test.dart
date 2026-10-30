// QA de #185 (PR #577) — HU-SYNC-005, «Aviso por > 7 días sin backup». El PR no trae artboard de este
// aviso: se compara con el literal de la HU, con `AvisoDrive` de la vista 16 y con las convenciones §10.
//
// Matriz: 360×640 y 412×915 × texto 1,0 y 2,0 × aviso con días / reintentando / muchos días, con las
// guías de accesibilidad de Flutter, letra real (Inter + MaterialIcons) y el aviso dentro de Inicio
// junto a los otros avisos. Los hallazgos que quedaron con `skip` van en otro issue (#550). Capturas: `--dart-define=QA_CAPTURAS=true` (a `.dart_tool/qa_capturas/`,
// fuera del repo).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_respaldo.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_automatico_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/widgets/aviso_sin_respaldo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;
import '../helpers/notificaciones_arnes.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

// El reloj real: Inicio usa `DateTime.now()` y el aviso solo se puede probar contra él.
final _ahora = DateTime.now().toUtc();
final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

const _chico = Size(360, 640);
const _grande = Size(412, 915);
const _conectada = DriveConectada(email: 'ana@example.com', cuentaId: 'g-1');

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

class _EstadoFijo extends EstadoRespaldoDriveNotifier {
  _EstadoFijo(this._estado);
  final EstadoRespaldoDrive _estado;

  @override
  Future<EstadoRespaldoDrive> build() async => _estado;
}

final class _Servicio implements ServicioRespaldo {
  _Servicio([this.resultado]);

  /// Lo que contesta `respaldar`; sin esto, un respaldo hecho.
  ResultadoRespaldo? resultado;
  Completer<ResultadoRespaldo>? espera;
  int pedidos = 0;

  @override
  Future<ResultadoRespaldo> respaldar(OrigenRespaldo origen) async {
    pedidos++;
    if (espera case final e?) return e.future;
    return resultado ?? RespaldoHecho(fecha: _ahora, esBase: false);
  }

  @override
  Future<ResultadoVerificacion> verificarIntegridad() async =>
      const VerificacionOmitida(MotivoOmision.sinWifi);
}

DateTime _haceDias(int dias, {int horas = 0}) =>
    _ahora.subtract(Duration(days: dias, hours: horas));

final _raiz = GlobalKey();
Finder get _aviso => find.byKey(const Key('aviso_sin_respaldo'));
Finder get _reintentar => find.byKey(const Key('aviso_drive_accion'));

Future<void> _tam(WidgetTester tester, Size tam, double escala) async {
  await _cargarFuentes(tester);
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.view.resetViewInsets());
}

List<Override> _overrides({
  required _Servicio servicio,
  EstadoRespaldoDrive estado = _conectada,
  DateTime? ultimo,
}) => [
  estadoRespaldoDriveProvider.overrideWith(() => _EstadoFijo(estado)),
  ultimoRespaldoDriveProvider.overrideWith((ref) => Stream.value(ultimo)),
  servicioRespaldoProvider.overrideWithValue(servicio),
];

Widget _app({required double escala, required Widget home, required List<Override> overrides}) =>
    ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: RepaintBoundary(
        key: _raiz,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
            child: child!,
          ),
          home: home,
        ),
      ),
    );

/// El aviso solo, arriba de un cuerpo de Inicio de mentira.
Future<void> _montarAviso(
  WidgetTester tester, {
  required Size tam,
  required double escala,
  required _Servicio servicio,
  DateTime? ultimo,
  EstadoRespaldoDrive estado = _conectada,
}) async {
  await _tam(tester, tam, escala);
  await tester.pumpWidget(
    _app(
      escala: escala,
      overrides: _overrides(servicio: servicio, estado: estado, ultimo: ultimo),
      home: Scaffold(
        body: Column(
          children: [
            AvisoSinRespaldo(ahora: () => _ahora),
            const Expanded(child: Center(child: Text('Hoy'))),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

/// Inicio de verdad, con el aviso de «notificaciones apagadas» (el otro aviso de Hoy) si [apagadas].
Future<void> _montarInicio(
  WidgetTester tester, {
  required Size tam,
  required double escala,
  required _Servicio servicio,
  DateTime? ultimo,
  EstadoRespaldoDrive estado = _conectada,
  bool apagadas = false,
}) async {
  await _tam(tester, tam, escala);
  final telefono = Telefono();
  if (apagadas) telefono.recuerdo.pedido = PedidoNotificaciones.ahoraNo;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    _app(
      escala: escala,
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => DateTime(2026, 11, 10, 9, 30)),
        ...overridesPestanaMapa(),
        ...telefono.overrides,
        ..._overrides(servicio: servicio, estado: estado, ultimo: ultimo),
      ],
      home: InicioPage(sesion: _sesion),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/185_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto se sale de la pantalla por los costados.
void _sinTextoFueraDeLosCostados(WidgetTester tester, Size tam) {
  for (final e in find.byType(RichText).evaluate()) {
    final render = e.renderObject;
    if (render is! RenderBox || !render.attached || !render.hasSize) continue;
    final r = render.localToGlobal(Offset.zero) & render.size;
    expect(r.left, greaterThanOrEqualTo(-0.5), reason: 'texto cortado a la izquierda');
    expect(r.right, lessThanOrEqualTo(tam.width + 0.5), reason: 'texto cortado a la derecha');
  }
}

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final oscuro = la > lb ? lb : la;
  return (claro + 0.05) / (oscuro + 0.05);
}

void main() {
  const estados = ['con_dias', 'reintentando', 'muchos_dias'];

  Future<void> armarEstado(
    WidgetTester tester,
    String estado,
    Size tam,
    double escala, {
    required _Servicio servicio,
  }) async {
    await _montarAviso(
      tester,
      tam: tam,
      escala: escala,
      servicio: servicio,
      ultimo: estado == 'muchos_dias' ? _haceDias(400, horas: 5) : _haceDias(8, horas: 3),
    );
    if (estado == 'reintentando') {
      servicio.espera = Completer<ResultadoRespaldo>();
      await tester.tap(_reintentar);
      await tester.pump();
    }
  }

  group('matriz: 3 estados × 360×640 / 412×915 × texto 1,0 / 2,0', () {
    for (final tam in [_chico, _grande]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in estados) {
          final id = '${estado}_${tam.width.toInt()}x${tam.height.toInt()}_x${escala.toInt()}';

          testWidgets('$id: sin overflow, texto entero, aviso ≤ 40 % del alto', (tester) async {
            final servicio = _Servicio();
            await armarEstado(tester, estado, tam, escala, servicio: servicio);

            expect(tester.takeException(), isNull, reason: 'overflow o error de render');
            _sinTextoFueraDeLosCostados(tester, tam);
            expect(
              tester.getSize(find.byType(AvisoSinRespaldo)).height,
              lessThanOrEqualTo(tam.height * 0.4 + 0.5),
            );
            await _capturar(tester, id);
          });

          testWidgets('$id: guías de toque y etiquetas', (tester) async {
            final servicio = _Servicio();
            await armarEstado(tester, estado, tam, escala, servicio: servicio);

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          });
        }
      }
    }
  });

  group('la acción a la vista', () {
    for (final tam in [_chico, _grande]) {
      testWidgets(
        '«Reintentar» se ve sin desplazar el aviso (${tam.width.toInt()}×${tam.height.toInt()}, texto 2,0)',
        (tester) async {
          await _montarAviso(
            tester,
            tam: tam,
            escala: 2,
            servicio: _Servicio(),
            ultimo: _haceDias(8, horas: 3),
          );

          final caja = tester.getRect(find.byType(AvisoSinRespaldo));
          final boton = tester.getRect(_reintentar);
          expect(
            boton.bottom,
            lessThanOrEqualTo(caja.bottom + 0.5),
            reason:
                'el botón queda bajo el borde del aviso (${boton.bottom} > ${caja.bottom}): hay que desplazar el aviso para ver la acción',
          );
          expect(boton.top, greaterThanOrEqualTo(caja.top - 0.5));
        },
      );
    }
  });

  group('contraste (letra real, tema claro)', () {
    testWidgets('texto, acción y marca del aviso', (tester) async {
      await _montarAviso(
        tester,
        tam: _grande,
        escala: 1,
        servicio: _Servicio(),
        ultimo: _haceDias(9),
      );
      final tema = Theme.of(tester.element(_aviso));
      final fondo = tema.scaffoldBackgroundColor;

      final texto = tester.widget<Text>(find.textContaining('Llevás 9 días'));
      final colorTexto =
          texto.style?.color ?? tema.textTheme.bodyMedium?.color ?? tema.colorScheme.onSurface;
      expect(_contraste(colorTexto, fondo), greaterThanOrEqualTo(4.5), reason: 'texto del aviso');
      expect(
        _contraste(tema.colorScheme.primary, fondo),
        greaterThanOrEqualTo(4.5),
        reason: '«Reintentar»',
      );
      expect(
        _contraste(tema.colorScheme.error, fondo),
        greaterThanOrEqualTo(3.0),
        reason: 'borde del aviso (no textual)',
      );
      expect(
        _contraste(Colors.white, tema.colorScheme.error),
        greaterThanOrEqualTo(4.5),
        reason: 'el «!» blanco sobre el rojo',
      );
    });
  });

  group('semántica', () {
    testWidgets('región viva, botón con nombre y apagado se anuncia como apagado', (tester) async {
      final semantica = tester.ensureSemantics();
      final servicio = _Servicio();
      await _montarAviso(tester, tam: _grande, escala: 1, servicio: servicio, ultimo: _haceDias(9));

      expect(
        tester.getSemantics(_reintentar),
        isSemantics(
          label: 'Reintentar',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      servicio.espera = Completer<ResultadoRespaldo>();
      await tester.tap(_reintentar);
      await tester.pump();
      expect(
        tester.getSemantics(_reintentar),
        isSemantics(
          label: 'Reintentando…',
          isButton: true,
          isEnabled: false,
          hasEnabledState: true,
        ),
      );
      semantica.dispose();
    });
  });

  group('casos límite del flujo', () {
    testWidgets(
      'dos toques seguidos + completar: un pedido, el botón vuelve, el aviso se va solo al ponerse al día',
      (tester) async {
        final servicio = _Servicio()..espera = Completer<ResultadoRespaldo>();
        await _montarAviso(
          tester,
          tam: _chico,
          escala: 1,
          servicio: servicio,
          ultimo: _haceDias(9),
        );

        await tester.tap(_reintentar);
        await tester.tap(_reintentar, warnIfMissed: false);
        await tester.pump();
        expect(servicio.pedidos, 1);

        servicio.espera!.complete(const RespaldoFallido(CausaFalloRespaldo.otra));
        await tester.pumpAndSettle();
        expect(tester.widget<TextButton>(_reintentar).onPressed, isNotNull);

        // Reintento posterior: se puede pedir otra vez.
        servicio.espera = null;
        await tester.tap(_reintentar);
        await tester.pumpAndSettle();
        expect(servicio.pedidos, 2);
      },
    );

    testWidgets(
      '«Reintentar» con el respaldo ya corriendo por otro lado (enCurso): el botón se libera',
      (tester) async {
        final servicio = _Servicio(const RespaldoOmitido(MotivoOmision.enCurso));
        await _montarAviso(
          tester,
          tam: _chico,
          escala: 1,
          servicio: servicio,
          ultimo: _haceDias(9),
        );

        await tester.tap(_reintentar);
        await tester.pumpAndSettle();

        expect(tester.widget<TextButton>(_reintentar).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'el último respaldo cambia a «hace 2 días» con el aviso abierto: se va sin dejar rastro',
      (tester) async {
        final control = StreamController<DateTime?>();
        addTearDown(control.close);
        await _tam(tester, _chico, 1);
        await tester.pumpWidget(
          _app(
            escala: 1,
            overrides: [
              estadoRespaldoDriveProvider.overrideWith(() => _EstadoFijo(_conectada)),
              ultimoRespaldoDriveProvider.overrideWith((ref) => control.stream),
              servicioRespaldoProvider.overrideWithValue(_Servicio()),
            ],
            home: Scaffold(
              body: Column(
                children: [
                  AvisoSinRespaldo(ahora: () => _ahora),
                  const Expanded(child: Text('Hoy')),
                ],
              ),
            ),
          ),
        );
        control.add(_haceDias(12));
        await tester.pumpAndSettle();
        expect(_aviso, findsOneWidget);
        control.add(_haceDias(2));
        await tester.pumpAndSettle();
        expect(_aviso, findsNothing);
        expect(find.text('Hoy'), findsOneWidget);
      },
    );

    testWidgets('datos extremos: 36 500 días no desborda ni se corta', (tester) async {
      await _montarAviso(
        tester,
        tam: _chico,
        escala: 2,
        servicio: _Servicio(),
        ultimo: _haceDias(36500),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text('Llevás 36500 días sin respaldo. Revisá tu conexión y reintentá.'),
        findsOneWidget,
      );
    });

    testWidgets('último respaldo en el futuro (reloj atrasado): no avisa ni rompe', (tester) async {
      await _montarAviso(
        tester,
        tam: _chico,
        escala: 1,
        servicio: _Servicio(),
        ultimo: _ahora.add(const Duration(days: 3)),
      );
      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('en Inicio, con los otros avisos', () {
    testWidgets('aparece solo en Hoy (decisión del 29/10) y «Reintentar» funciona desde Inicio', (
      tester,
    ) async {
      final servicio = _Servicio();
      await _montarInicio(
        tester,
        tam: _grande,
        escala: 1,
        servicio: servicio,
        ultimo: _haceDias(9),
      );
      expect(_aviso, findsOneWidget);
      await tester.tap(find.text('Agenda'));
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing, reason: 'fuera de Hoy no hay aviso');
      await tester.tap(find.text('Hoy'));
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget, reason: 'vuelve en Hoy');
      await tester.tap(_reintentar);
      await tester.pumpAndSettle();
      expect(servicio.pedidos, 1);
      expect(tester.takeException(), isNull);
    });

    for (final tam in [_chico, _grande]) {
      testWidgets(
        'aviso + notificaciones apagadas a texto 2,0 (${tam.width.toInt()}×${tam.height.toInt()}): sin overflow y Hoy sigue usable',
        (tester) async {
          await _montarInicio(
            tester,
            tam: tam,
            escala: 2,
            servicio: _Servicio(),
            ultimo: _haceDias(9),
            apagadas: true,
          );

          expect(tester.takeException(), isNull);
          expect(_aviso, findsOneWidget);
          expect(avisoApagadas, findsOneWidget);
          expect(principal, findsOneWidget);
          await _capturar(
            tester,
            'inicio_dos_avisos_${tam.width.toInt()}x${tam.height.toInt()}_x2',
          );
          // Lo que queda para el contenido de Hoy bajo los avisos.
          final avisos = tester.getRect(_aviso).bottom;
          final alto = tester.getSize(principal).height;
          expect(
            alto,
            greaterThan(tam.height * 0.2),
            reason: 'tras los avisos quedan $alto dp de $avisos',
          );
        },
      );
    }

    testWidgets('con el teclado abierto el aviso cede el lugar y vuelve al cerrarlo', (
      tester,
    ) async {
      await _montarInicio(
        tester,
        tam: _chico,
        escala: 1,
        servicio: _Servicio(),
        ultimo: _haceDias(9),
      );
      expect(_aviso, findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget);
    });

    testWidgets('Drive conectado, con respaldo hace 3 días: Inicio sin aviso', (tester) async {
      await _montarInicio(
        tester,
        tam: _chico,
        escala: 1,
        servicio: _Servicio(),
        ultimo: _haceDias(3),
      );
      expect(_aviso, findsNothing);
    });
  });

  group('Hoy sigue usable bajo los avisos (texto 2,0, 360×640)', () {
    // La acción principal de Hoy («Iniciar jornada») tiene que poder tocarse, desplazando Hoy si hace
    // falta, con los avisos puestos.
    Future<double> altoDeHoy(WidgetTester tester) async =>
        tester.getSize(find.byType(IndexedStack).first).height;

    for (final (nombre, dias, apagadas) in [
      ('sin aviso de respaldo ni de notificaciones (línea base)', 3, false),
      ('con el aviso de respaldo', 9, false),
      ('con el aviso de respaldo y el de notificaciones apagadas', 9, true),
    ]) {
      // La franja de avisos tiene un tope conjunto (40 % del alto) y se desplaza sola: Hoy conserva su
      // lugar aunque haya dos avisos a texto 2,0 en 360×640.
      testWidgets('$nombre: «Iniciar jornada» se puede tocar', (tester) async {
        await _montarInicio(
          tester,
          tam: _chico,
          escala: 2,
          servicio: _Servicio(),
          ultimo: _haceDias(dias),
          apagadas: apagadas,
        );
        final alto = await altoDeHoy(tester);
        expect(alto, greaterThan(_chico.height * 0.2), reason: 'a Hoy le quedan $alto dp');
        final franja = find.byKey(const Key('inicio_franja_avisos'));
        expect(
          tester.getSize(franja).height,
          lessThanOrEqualTo(_chico.height * 0.4 + 0.01),
          reason: 'la franja de avisos pasó su tope',
        );
        final boton = find.byKey(const Key('jornada_iniciar'));
        expect(boton, findsOneWidget);
        await tester.ensureVisible(boton);
        await tester.pump();
        final centro = tester.getCenter(boton);
        final area = tester.getRect(find.byType(IndexedStack).first);
        expect(
          area.contains(centro),
          isTrue,
          reason: 'el botón queda fuera del área de Hoy ($centro vs $area)',
        );
        expect(boton.hitTestable(), findsOneWidget);
      });
    }
  });

  group('con el motivo del último reintento (decisión del 29/10)', () {
    for (final tam in [_chico, _grande]) {
      for (final escala in [1.0, 2.0]) {
        for (final (id, resultado, texto) in [
          (
            'sin_conexion',
            const RespaldoOmitido(MotivoOmision.sinConexion),
            'Necesitás conexión para hacer el respaldo.',
          ),
          (
            'fallido',
            const RespaldoFallido(CausaFalloRespaldo.otra),
            'No pudimos hacer el respaldo. Probá de nuevo en un rato.',
          ),
        ]) {
          final celda = '${id}_${tam.width.toInt()}x${tam.height.toInt()}_x${escala.toInt()}';
          testWidgets('$celda: se lee entero, sin overflow, con guías y botón a la vista', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            await _montarAviso(
              tester,
              tam: tam,
              escala: escala,
              servicio: _Servicio(resultado),
              ultimo: _haceDias(9),
            );
            await tester.tap(_reintentar);
            await tester.pumpAndSettle();

            expect(find.text(texto), findsOneWidget);
            expect(tester.takeException(), isNull);
            _sinTextoFueraDeLosCostados(tester, tam);
            final caja = tester.getRect(find.byType(AvisoSinRespaldo));
            expect(caja.height, lessThanOrEqualTo(tam.height * 0.4 + 0.5));
            // Con el motivo agregado el botón sigue pudiéndose tocar sin desplazar el aviso... o,
            // si el aviso se desplaza, queda alcanzable.
            await tester.ensureVisible(_reintentar);
            await tester.pump();
            expect(_reintentar.hitTestable(), findsOneWidget);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await _capturar(tester, celda);
            semantica.dispose();
          });
        }
      }
    }

    testWidgets('reintentar otra vez borra el motivo, y si sale bien el aviso se va', (
      tester,
    ) async {
      final servicio = _Servicio(const RespaldoFallido(CausaFalloRespaldo.otra));
      await _montarAviso(tester, tam: _chico, escala: 1, servicio: servicio, ultimo: _haceDias(9));
      await tester.tap(_reintentar);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aviso_drive_detalle')), findsOneWidget);

      servicio
        ..resultado = null
        ..espera = Completer<ResultadoRespaldo>();
      await tester.tap(_reintentar);
      await tester.pump();
      expect(
        find.byKey(const Key('aviso_drive_detalle')),
        findsNothing,
        reason: 'durante el reintento',
      );
      servicio.espera!.complete(RespaldoHecho(fecha: _ahora, esBase: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aviso_drive_detalle')), findsNothing);
    });

    testWidgets('límites del número: 7 días justos no avisa; 7 d 3 h dice 8; 8 d justos dice 8', (
      tester,
    ) async {
      await _montarAviso(
        tester,
        tam: _chico,
        escala: 1,
        servicio: _Servicio(),
        ultimo: _haceDias(7),
      );
      expect(_aviso, findsNothing);
      await _montarAviso(
        tester,
        tam: _chico,
        escala: 1,
        servicio: _Servicio(),
        ultimo: _haceDias(7, horas: 3),
      );
      expect(find.textContaining('Llevás 8 días'), findsOneWidget);
      await _montarAviso(
        tester,
        tam: _chico,
        escala: 1,
        servicio: _Servicio(),
        ultimo: _haceDias(8),
      );
      expect(find.textContaining('Llevás 8 días'), findsOneWidget);
    });
  });

  group('el motivo del reintento a la vista, sin desplazar', () {
    // Ronda 2: a 360×640 con texto 2,0× el motivo y «Reintentar» quedaban bajo el borde del aviso
    // (tope de 40 %). Al aparecer el motivo, el aviso se desplaza hasta mostrarlo.
    for (final tam in [_chico, _grande]) {
      testWidgets(
        'tras un fallo, el motivo se ve sin desplazar el aviso (${tam.width.toInt()}×${tam.height.toInt()}, 2,0×)',
        (tester) async {
          await _montarAviso(
            tester,
            tam: tam,
            escala: 2,
            servicio: _Servicio(const RespaldoFallido(CausaFalloRespaldo.otra)),
            ultimo: _haceDias(9),
          );
          await tester.tap(_reintentar);
          await tester.pumpAndSettle();

          final aviso = tester.getRect(find.byType(AvisoSinRespaldo));
          final detalle = tester.getRect(find.byKey(const Key('aviso_drive_detalle')));
          expect(
            detalle.bottom,
            lessThanOrEqualTo(aviso.bottom + 0.5),
            reason: 'el motivo queda ${detalle.bottom - aviso.bottom} dp bajo el borde del aviso',
          );
          expect(tester.getRect(_reintentar).bottom, lessThanOrEqualTo(aviso.bottom + 0.5));
        },
      );
    }
  });

  testWidgets(
    'en Inicio con dos avisos (360×640, 2,0×), tras un fallo el motivo queda dentro de la franja',
    (tester) async {
      await _montarInicio(
        tester,
        tam: _chico,
        escala: 2,
        servicio: _Servicio(const RespaldoFallido(CausaFalloRespaldo.otra)),
        ultimo: _haceDias(9),
        apagadas: true,
      );
      await tester.ensureVisible(_reintentar);
      await tester.pump();
      await tester.tap(_reintentar);
      await tester.pumpAndSettle();

      final franja = tester.getRect(find.byKey(const Key('inicio_franja_avisos')));
      final detalle = tester.getRect(find.byKey(const Key('aviso_drive_detalle')));
      expect(detalle.top, greaterThanOrEqualTo(franja.top - 0.5));
      expect(detalle.bottom, lessThanOrEqualTo(franja.bottom + 0.5));
      expect(tester.getRect(_reintentar).bottom, lessThanOrEqualTo(franja.bottom + 0.5));
    },
  );

  group('hallazgos', () {
    // Decisión del 29/10 (P1): tras «Reintentar» sin conexión o con un fallo, el aviso lo dice, dentro
    // del mismo aviso (convenciones §10).
    testWidgets('tras «Reintentar» sin conexión, el aviso dice qué pasó', (tester) async {
      final servicio = _Servicio(const RespaldoOmitido(MotivoOmision.sinConexion));
      await _montarAviso(tester, tam: _chico, escala: 1, servicio: servicio, ultimo: _haceDias(9));
      await tester.tap(_reintentar);
      await tester.pumpAndSettle();

      expect(find.text('Necesitás conexión para hacer el respaldo.'), findsOneWidget);
    });

    testWidgets('tras «Reintentar» que falla, el aviso dice qué pasó', (tester) async {
      final servicio = _Servicio(const RespaldoFallido(CausaFalloRespaldo.otra));
      await _montarAviso(tester, tam: _chico, escala: 1, servicio: servicio, ultimo: _haceDias(9));
      await tester.tap(_reintentar);
      await tester.pumpAndSettle();

      expect(find.text('No pudimos hacer el respaldo. Probá de nuevo en un rato.'), findsOneWidget);
    });

    // skip: va en #550 (Drive en Hoy, con diseño; decisión del 29/10, P2) — HU-SYNC-005: «Notificación al usuario si > 7 días sin backup exitoso». Con el
    // permiso de Drive revocado o sin espacio (justo cuando los respaldos no salen) Inicio no avisa
    // nada: el único aviso está en Configuración → Cuenta Drive.
    for (final estado in <EstadoRespaldoDrive>[
      const DrivePermisoRevocado(email: 'ana@example.com', cuentaId: 'g-1'),
      const DriveSinEspacio(email: 'ana@example.com', cuentaId: 'g-1'),
    ]) {
      testWidgets(
        '${estado.runtimeType} y 9 días sin respaldo: Inicio avisa que hay que hacer algo',
        (tester) async {
          await _montarInicio(
            tester,
            tam: _chico,
            escala: 1,
            servicio: _Servicio(),
            ultimo: _haceDias(9),
            estado: estado,
          );

          expect(find.textContaining('respaldo'), findsAtLeastNWidgets(1));
        },
        skip: true,
      );
    }
  });
}
