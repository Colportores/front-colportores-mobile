// Arnés del QA de #62 (HU-AUTH-008, «Cuenta antes», vista 18): «Hoy» con la campaña por empezar y
// la jornada rechazada, «Inicio» con los otros avisos de «Hoy» y 18A·07 «Ya te asignaron» con la
// campaña y la zona reales.
//
// Capturas PNG con `--dart-define=QA_CAPTURAS=true`, en `.dart_tool/qa_capturas/` (fuera del repo).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/campanias_inscriptas_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/asignacion_campania_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/campanias_inscriptas_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/asignacion_campania.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/cuenta_asignada_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/asignacion_campania_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/campanias_inscriptas_providers.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornadas_rechazadas_data_source.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada_rechazada.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornadas_rechazadas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'mapa_base_falso.dart' show overridesPestanaMapa;
import 'notificaciones_arnes.dart';

const conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Los cuatro tamaños de la matriz: (nombre, ancho, alto, escala de texto).
const tamanos = <(String, double, double, double)>[
  ('360x640_1x', 360, 640, 1),
  ('360x640_2x', 360, 640, 2),
  ('412x915_1x', 412, 915, 1),
  ('412x915_2x', 412, 915, 2),
];

/// Viernes 20/11/2026, 12:00 en Montevideo (15:00 UTC).
final ahoraBase = DateTime.utc(2026, 11, 20, 15);

final sesion = Sesion(
  usuarioId: 'u-1',
  email: 'agustin@correo.com',
  accessToken: 'token',
  expiraEn: DateTime.utc(2030),
);

CampaniaInscripta porEmpezar({
  String nombre = 'Verano 2027',
  String inicio = '2026-12-01',
  String? zona,
  String? ciudad,
}) => CampaniaInscripta(
  campaniaId: 'camp-$nombre',
  nombre: nombre,
  fechaInicio: inicio,
  fechaFin: '2027-02-28',
  zona: zona,
  ciudad: ciudad,
);

CampaniaInscripta enCurso() => const CampaniaInscripta(
  campaniaId: 'camp-curso',
  nombre: 'Primavera 2026',
  fechaInicio: '2026-09-01',
  fechaFin: '2026-12-15',
);

JornadaRechazada rechazada(String id, {int visitas = 0, DateTime? inicio}) =>
    JornadaRechazada(id: id, inicio: inicio ?? DateTime.utc(2026, 11, 19, 14), visitas: visitas);

/// Las jornadas rechazadas, con una perilla para publicarlas como lo hace el motor al rechazar.
final class Rechazadas implements JornadasRechazadasDataSource {
  Rechazadas([List<JornadaRechazada> iniciales = const []]) : _actuales = iniciales;

  List<JornadaRechazada> _actuales;
  final _suscriptores = <StreamController<List<JornadaRechazada>>>[];

  @override
  Stream<List<JornadaRechazada>> observar(String colportorId) {
    final c = StreamController<List<JornadaRechazada>>();
    c.onCancel = () => _suscriptores.remove(c);
    _suscriptores.add(c);
    c.add(_actuales);
    return c.stream;
  }

  void publicar(List<JornadaRechazada> jornadas) {
    _actuales = jornadas;
    for (final c in List.of(_suscriptores)) {
      c.add(jornadas);
    }
  }
}

final class BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

final class Mundo {
  Mundo({List<CampaniaInscripta>? campanias, List<JornadaRechazada>? rechazadas})
    : replica = CampaniasInscriptasEnMemoria(campanias),
      rechazadas = Rechazadas(rechazadas ?? const []);

  final CampaniasInscriptasEnMemoria replica;
  final Rechazadas rechazadas;
  final jornadas = JornadaLocalDataSourceEnMemoria();
  final asignacion = AsignacionCampaniaEnMemoria();
  DateTime ahora = ahoraBase;
  final CampaniasInscriptasDataSource? replicaPropia = null;
}

bool _fuentesCargadas = false;

/// Carga las fuentes de `assets/fonts/` y los íconos de Material: sin esto `flutter_test` pinta cajas.
Future<void> cargarFuentesReales(WidgetTester tester) async {
  if (_fuentesCargadas) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'];
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final candidato = raiz != null
          ? File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          : File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (candidato.existsSync()) {
        final bytes = candidato.readAsBytesSync();
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await cargador.load();
        break;
      }
    }
  });
  _fuentesCargadas = true;
}

Future<void> asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

final raiz = GlobalKey();

void _tam(WidgetTester tester, double ancho, double alto) {
  tester.view.physicalSize = Size(ancho, alto);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home, double escala, List<Override> overrides) => ProviderScope(
  key: UniqueKey(),
  overrides: overrides,
  child: RepaintBoundary(
    key: raiz,
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

List<Override> _overridesDe(Mundo m) => [
  jornadaLocalDataSourceProvider.overrideWithValue(m.jornadas),
  disparadorBackupProvider.overrideWithValue(BackupFalso()),
  relojJornadaProvider.overrideWithValue(() => m.ahora),
  relojCampaniaProvider.overrideWithValue(() => m.ahora),
  campaniasInscriptasDataSourceProvider.overrideWithValue(m.replica),
  jornadasRechazadasDataSourceProvider.overrideWithValue(m.rechazadas),
];

/// «Hoy» solo (la `JornadaPage`), con el reloj de [m].
Future<void> montarHoy(
  WidgetTester tester,
  Mundo m, {
  double ancho = 390,
  double alto = 844,
  double escala = 1,
}) async {
  _tam(tester, ancho, alto);
  await tester.pumpWidget(
    _app(Scaffold(body: JornadaPage(sesion: sesion)), escala, _overridesDe(m)),
  );
  await asentar(tester);
}

/// «Inicio» de verdad (con la barra de pestañas y la franja de los otros avisos de «Hoy»).
Future<void> montarInicio(
  WidgetTester tester,
  Mundo m, {
  double ancho = 390,
  double alto = 844,
  double escala = 1,
}) async {
  _tam(tester, ancho, alto);
  final telefono = Telefono();
  await tester.pumpWidget(
    _app(InicioPage(sesion: sesion), escala, [
      ..._overridesDe(m),
      ...overridesPestanaMapa(),
      ...telefono.overrides,
    ]),
  );
  await asentar(tester);
}

/// 18A·07 «Ya te asignaron». [terminadas] cuenta las veces que la pantalla avisó que terminó.
Future<void> montarAsignada(
  WidgetTester tester,
  Mundo m, {
  double ancho = 390,
  double alto = 844,
  double escala = 1,
  void Function()? alTerminar,
}) async {
  _tam(tester, ancho, alto);
  await tester.pumpWidget(
    _app(CuentaAsignadaPage(onTerminar: alTerminar ?? () {}), escala, [
      asignacionCampaniaDataSourceProvider.overrideWithValue(m.asignacion),
    ]),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

AsignacionCampania asignacionDe(String campania, {String? zona, String? ciudad}) =>
    AsignacionCampania(campania: campania, zona: zona, ciudad: ciudad);

Finder get avisoFijo => find.byKey(const Key('jornada_campania_por_empezar'));
Finder get snack => find.byKey(const Key('campania_por_empezar_aviso'));
Finder get iniciar => find.byKey(const Key('jornada_iniciar'));

Future<void> tocarIniciar(WidgetTester tester) async {
  await tester.ensureVisible(iniciar);
  await tester.tap(iniciar);
  await asentar(tester);
  // El aviso entra con una animación de ~250 ms.
  await tester.pump(const Duration(milliseconds: 400));
}

/// Las cuatro guías de accesibilidad de Flutter.
Future<void> cumpleLasGuias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Ningún texto se sale de la pantalla por los costados.
void sinTextoFueraDeLosCostados(WidgetTester tester, double ancho) {
  for (final e in find.byType(RichText).evaluate()) {
    final render = e.renderObject;
    if (render is! RenderBox || !render.attached || !render.hasSize) continue;
    final r = render.localToGlobal(Offset.zero) & render.size;
    expect(r.left, greaterThanOrEqualTo(-0.5), reason: 'texto cortado a la izquierda');
    expect(r.right, lessThanOrEqualTo(ancho + 0.5), reason: 'texto cortado a la derecha');
  }
}

Future<void> capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/62_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
