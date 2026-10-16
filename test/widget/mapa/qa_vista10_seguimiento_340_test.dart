// QA del seguimiento de «Posibles duplicados» (HU-UBI-006, vista 10; issue #340, PR #357). Complementa
// `seguimiento_duplicados_340_test.dart` (el flujo de punta a punta de F3, M2, M3 y F4) y
// `qa_vista10_duplicados_208_test.dart` (la matriz 360×640 y 412×915 × 1.0 y 2.0 de #338) con lo que
// ninguno de los dos mide:
//
// - la matriz de la pantalla y de la franja de la Lista en 320×568 (el teléfono más chico que se
//   soporta) con el texto al 100 %, 200 % y 300 %, más 360×640 y 412×915 al 300 %: sin overflow, sin
//   texto fuera de los costados, tamaños de toque y etiquetas, y ningún «5 m» ni «12 m» con espacio común;
// - los estados nuevos de #340 que el canvas no dibuja: la franja «No pudimos unir …» con una falla, con
//   dos y con una dirección larga; el aviso rojo de M2 junto con otra unión esperando; M3 con tres
//   registros del mismo domicilio;
// - el lector de pantalla: la franja de la Lista tiene acción de toque, se anuncia al cambiar y dice lo
//   mismo que ve la persona;
// - casos límite: dos fallas del mismo par, tres fallas, par que ya no existe, reentrada, dos fallas en
//   pantalla.
//
// Capturas: `flutter test --dart-define=QA_CAPTURAS=true …` las deja en `.dart_tool/qa_capturas/`
// (gitignored: nunca se commitean). Un test que documenta un hallazgo va con `skip` y el comentario
// `// skip: QA #340 — <motivo>`; con `--dart-define=QA_VER_HALLAZGOS=true` se corre igual. Los
// hallazgos de la primera vuelta ya están arreglados y sus tests corren sin `skip`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/uniones_pendientes_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart'
    show ColoresLista;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show situacionSinConexion;
import '../../helpers/duplicados_falsos.dart';
import '../../helpers/qa_hojas_teclado_324_arnes.dart' show conCapturas;
import '../../helpers/qa_vista10_arnes.dart';

const _ocho = Duration(seconds: 8);

const _parItalia = 'ub-a|ub-b';
const _parArtigas = 'ub-c|ub-d';
const _parMichigan = 'ub-c|ub-d';
const _parMataojo = 'ub-e|ub-f';

/// El teléfono más chico que se soporta.
const _telefonoMinimo = Size(320, 568);

// ------------------------------------------------------------------------------------------------
// Datos
// ------------------------------------------------------------------------------------------------

/// Los tres pares del canvas 10·01 (Italia, Michigan «bis», Mataojo edificio + casa).
DuplicadosEnMemoria _datosCanvas() {
  final vieja = DateTime.utc(2026, 8, 1, 10);
  final nueva = DateTime.utc(2026, 8, 5, 10);
  return DuplicadosEnMemoria()
    ..agregar(ubicacionDuplicable('ub-a', creada: vieja), espacios: 2)
    ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 12, creada: nueva))
    ..agregar(
      ubicacionDuplicable(
        'ub-c',
        metrosAlNorte: 1000,
        calle: 'Michigan',
        numero: '1540',
        creada: vieja,
      ),
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-d',
        metrosAlNorte: 1003,
        calle: 'Michigan',
        numero: '1540 bis',
        creada: nueva,
      ),
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-e',
        metrosAlNorte: 2000,
        calle: 'Mataojo',
        numero: '2044',
        tipo: TipoUbicacion.edificio,
        creada: vieja,
      ),
      espacios: 6,
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-f',
        metrosAlNorte: 2003,
        calle: 'Mataojo',
        numero: '2044',
        creada: nueva,
      ),
    );
}

/// Av. Italia 1234 (A–B, a 12 m) y otra calle (C–D, a 150 m), a 1 km una de la otra.
DuplicadosEnMemoria _datosDosPares({String calleArtigas = 'Bulevar Artigas'}) {
  final vieja = DateTime.utc(2026, 8, 1, 10);
  final nueva = DateTime.utc(2026, 8, 5, 10);
  return DuplicadosEnMemoria()
    ..agregar(ubicacionDuplicable('ub-a', creada: vieja), espacios: 2)
    ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 12, creada: nueva))
    ..agregar(
      ubicacionDuplicable(
        'ub-c',
        metrosAlNorte: 1000,
        calle: calleArtigas,
        numero: '880',
        creada: vieja,
      ),
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-d',
        metrosAlNorte: 1150,
        calle: calleArtigas,
        numero: '880',
        creada: nueva,
      ),
    );
}

/// Tres registros del mismo domicilio: los pares A–B, A–C y B–C.
DuplicadosEnMemoria _datosTresIguales() => DuplicadosEnMemoria()
  ..agregar(ubicacionDuplicable('ub-a', creada: DateTime.utc(2026, 8, 1)), espacios: 2)
  ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 12, creada: DateTime.utc(2026, 8, 3)))
  ..agregar(ubicacionDuplicable('ub-c', metrosAlNorte: 24, creada: DateTime.utc(2026, 8, 5)));

/// Un par con textos largos y emoji.
DuplicadosEnMemoria _datosExtremos() {
  const calle = 'Avenida Doctor José Gervasio Artigas y Presidente Tomás Berreta 🙂';
  return DuplicadosEnMemoria()
    ..agregar(
      ubicacionDuplicable(
        'ub-a',
        calle: calle,
        numero: '12345 bis apto 1204',
        tipo: TipoUbicacion.edificio,
      ),
      espacios: 128,
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-b',
        metrosAlNorte: 3,
        calle: calle,
        numero: '12345 bis apto 1204',
        creada: DateTime.utc(2026, 9, 2),
      ),
    );
}

/// Una ubicación sin calle ni número: solo participa de un par por distancia (HU-UBI-006).
Ubicacion _sinDireccion(String id, {double metrosAlNorte = 0, DateTime? creada}) {
  final t = creada ?? DateTime.utc(2026, 9, 1, 10);
  return Ubicacion(
    id: id,
    tipo: TipoUbicacion.casa,
    lat: -34.891 + metrosAlNorte / 111195.08,
    lon: -56.125,
    ciudadId: 'mvd',
    zonaId: 'zona-1',
    auditoria: Auditoria(createdAt: t, updatedAt: t, createdBy: 'col-1'),
  );
}

// ------------------------------------------------------------------------------------------------
// Montaje y ayudas
// ------------------------------------------------------------------------------------------------

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

Future<void> _desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

void _prueba(String descripcion, Future<void> Function(WidgetTester tester) cuerpo, {bool? skip}) {
  testWidgets(descripcion, (tester) async {
    final semantica = tester.ensureSemantics();
    await cuerpo(tester);
    await _desmontar(tester);
    semantica.dispose();
  }, skip: skip);
}

FallaUnion _falla(String clavePar, String direccion) {
  final partes = clavePar.split('|');
  return FallaUnion(
    union: UnionPendiente(
      clavePar: clavePar,
      conservarId: partes[0],
      duplicadaId: partes[1],
      direccion: direccion,
    ),
    falla: const FailureInesperado(),
  );
}

Widget _app(
  DuplicadosEnMemoria datos, {
  required double escala,
  required Widget home,
  SituacionMapa? situacion,
  List<FallaUnion> fallas = const [],
}) {
  // Las fallas «fuera de pantalla» que la app ya trae cuando se abre la Lista: se cargan antes de
  // pintar, así la franja nace en su forma de falla (y no se la ve pasar por la de siempre).
  final contenedor = ProviderContainer(
    overrides: overridesDuplicados(datos, conMapa: true, situacion: situacion),
  );
  addTearDown(contenedor.dispose);
  for (final f in fallas) {
    contenedor.read(unionesFallidasFueraDePantallaProvider.notifier).registrar(f);
  }
  return UncontrolledProviderScope(
    container: contenedor,
    child: RepaintBoundary(
      key: raizCaptura208,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
}

void _tamano(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// La Lista de ubicaciones (la pestaña «Lista») con los datos en memoria.
Future<void> _montarLista(
  WidgetTester tester,
  DuplicadosEnMemoria datos, {
  double escala = 1,
  Size tamano = telefonoChico208,
  List<FallaUnion> fallas = const [],
  String? capturaComo,
}) async {
  _tamano(tester, tamano);
  addTearDown(datos.cerrar);
  await cargarFuentes208(tester);
  await tester.pumpWidget(
    _app(
      datos,
      escala: escala,
      fallas: fallas,
      home: const Scaffold(body: ListaUbicacionesPage(colportorId: 'col-1')),
    ),
  );
  await _asentar(tester);
  if (capturaComo != null) await _capturar(tester, capturaComo);
  // En los primeros cuadros la franja ya está y la Lista todavía dice «Buscando tus ubicaciones»: con
  // texto grande ese estado de un cuadro desborda (la app real lee las filas antes que los pares, así
  // que no se ven juntos). Solo se descarta ese desborde; cualquier otra excepción falla el test.
  _descartarDesbordeDelCargando(tester);
  for (var i = 0; i < 20 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  _descartarDesbordeDelCargando(tester);
  expect(
    find.byType(CircularProgressIndicator),
    findsNothing,
    reason: 'la Lista ya cargó sus filas',
  );
}

void _descartarDesbordeDelCargando(WidgetTester tester) {
  Object? e;
  while ((e = tester.takeException()) != null) {
    expect(
      '$e'.contains('RenderFlex overflowed') && '$e'.contains('creator: Column ← Center'),
      isTrue,
      reason: 'excepción inesperada al montar la Lista: $e',
    );
  }
}

/// La pantalla «Posibles duplicados» abierta desde un botón.
Future<void> _montarPantalla(
  WidgetTester tester,
  DuplicadosEnMemoria datos, {
  double escala = 1,
  Size tamano = telefonoChico208,
  SituacionMapa? situacion,
}) async {
  _tamano(tester, tamano);
  addTearDown(datos.cerrar);
  await cargarFuentes208(tester);
  await tester.pumpWidget(
    _app(
      datos,
      escala: escala,
      situacion: situacion,
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
  );
  await tester.tap(find.byKey(const Key('abrir')));
  await _transicion(tester);
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raizCaptura208));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/340qa_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

final _franja = find.byKey(const Key('lista_aviso_duplicados'));
final _franjaFalla = find.byKey(const Key('lista_aviso_union_fallida'));
final _conservarYUnir = find.byKey(const Key('comparar_conservar_y_unir'));
final _avisoRojo = find.byKey(const Key('duplicados_falla_union'));
final _reintentarUnion = find.byKey(const Key('duplicados_reintentar_union'));
final _deshacer = find.text('Deshacer');
final _pagina = find.byType(PosiblesDuplicadosPage);
Finder _revisar(String clave) => find.byKey(Key('revisar_$clave'));
Finder _par(String clave) => find.byKey(Key('par_$clave'));
Finder _texto(String texto) => find.textContaining(texto, findRichText: true);

Future<void> _tocar(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(f);
  await tester.pump();
  // El aviso «quedaron unidas» (SnackBar) tapa el pie de la lista mientras espera: se sube un poco
  // más lo que se quiere tocar, como haría la persona.
  for (var i = 0; i < 4 && f.hitTestable().evaluate().isEmpty; i++) {
    final lista = find.byType(ListView);
    if (lista.evaluate().isEmpty) break;
    // Desde arriba de la lista: el centro puede estar debajo del aviso.
    await tester.dragFrom(
      tester.getTopLeft(lista.first) + const Offset(40, 60),
      const Offset(0, -120),
    );
    await tester.pump();
  }
  if (f.hitTestable().evaluate().isEmpty) {
    // Lo que se ve del botón por encima del aviso: se toca ahí.
    final caja = tester.getRect(f);
    await tester.tapAt(Offset(caja.center.dx, caja.top + 4));
  } else {
    await tester.tap(f);
  }
  await _asentar(tester);
}

/// Si el par [clave] está en la lista (que se arma de a poco: se baja hasta encontrarlo).
Future<bool> _hayPar(WidgetTester tester, String clave) async {
  final f = _par(clave);
  final lista = find.byType(ListView).first;
  await tester.drag(lista, const Offset(0, 5000));
  await tester.pump();
  for (var i = 0; i < 30; i++) {
    if (f.evaluate().isNotEmpty) return true;
    await tester.drag(lista, const Offset(0, -150));
    await tester.pump();
  }
  return false;
}

/// Desde la Lista: toca la franja (la de siempre o la de la falla) y entra a «Posibles duplicados».
Future<void> _entrar(WidgetTester tester) async {
  final franja = _franja.evaluate().isNotEmpty ? _franja : _franjaFalla;
  await tester.tap(franja);
  await _transicion(tester);
  expect(_pagina, findsOneWidget);
}

Future<void> _salir(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('duplicados_volver')));
  await _transicion(tester);
  expect(_pagina, findsNothing);
}

/// Revisa el par [clave] y toca «Conservar A y unir»; la hoja se cierra y el aviso queda a la vista.
Future<void> _unir(WidgetTester tester, String clave) async {
  await _tocar(tester, _revisar(clave));
  await _tocar(tester, _conservarYUnir);
  await tester.pump(const Duration(seconds: 1));
}

/// Registra desde afuera una unión fallida «fuera de pantalla» (lo que hace el notifier al terminar
/// con la pantalla ya cerrada): sirve para armar la franja de la Lista sin recorrer todo el flujo.
void _fallaFuera(WidgetTester tester, String clavePar, String direccion) {
  final partes = clavePar.split('|');
  ProviderScope.containerOf(tester.element(find.byType(ListaUbicacionesPage)))
      .read(unionesFallidasFueraDePantallaProvider.notifier)
      .registrar(
        FallaUnion(
          union: UnionPendiente(
            clavePar: clavePar,
            conservarId: partes[0],
            duplicadaId: partes[1],
            direccion: direccion,
          ),
          falla: const FailureInesperado(),
        ),
      );
}

/// Las tres guías de accesibilidad de Flutter menos el contraste (que con las fuentes reales no es
/// fiable: el contraste se mide aparte).
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

/// Ninguna distancia lleva un espacio común antes de la unidad: «12 m» y «5 m» no se parten.
void _expectUnidadesSinCorte(WidgetTester tester) {
  final patron = RegExp(r'\d (m|km)\b');
  for (final e in find.byType(RichText).evaluate()) {
    final texto = (e.widget as RichText).text.toPlainText();
    expect(patron.hasMatch(texto), isFalse, reason: 'espacio común antes de la unidad: «$texto»');
  }
}

String _tam(Size t) => '${t.width.toInt()}x${t.height.toInt()}';

const _verHallazgos = bool.fromEnvironment('QA_VER_HALLAZGOS');

/// Aviso rojo con [fallas] uniones fallidas y, a la vez, el aviso «quedaron unidas» de otro par
/// esperando sus 8 s (el estado M2 de la HU con una o con dos fallas).
Future<void> _avisoRojoMasSnackbar(
  WidgetTester tester,
  int fallas,
  Size tamano,
  double escala,
) async {
  final datos = _datosCanvas()..falloAlUnir = const FailureInesperado();
  await _montarPantalla(tester, datos, escala: escala, tamano: tamano);
  final pares = [_parItalia, _parMichigan, _parMataojo];
  for (var i = 0; i < fallas; i++) {
    await tester.drag(find.byType(Scrollable).last, const Offset(0, 5000));
    await tester.pump();
    await _unir(tester, pares[i]);
    await tester.pump(_ocho);
    await _asentar(tester);
  }
  datos.falloAlUnir = null;
  await tester.drag(find.byType(Scrollable).last, const Offset(0, 5000));
  await tester.pump();
  await _unir(tester, pares[fallas]);
  await _asentar(tester);
}

/// Dónde el aviso rojo y el SnackBar juntos dejan lista a la vista y los botones del aviso tocables: solo
/// en 412×915 (medido: en 320×568 al 200 % y 300 % y en 360×640 al 300 % no, con una o con dos fallas).
bool _avisoYSnackEntran(Size tamano) => tamano.height >= 915;

// ------------------------------------------------------------------------------------------------
// La matriz
// ------------------------------------------------------------------------------------------------
const _combos = <({Size tamano, double escala})>[
  (tamano: _telefonoMinimo, escala: 1.0),
  (tamano: _telefonoMinimo, escala: 2.0),
  (tamano: _telefonoMinimo, escala: 3.0),
  (tamano: telefonoChico208, escala: 3.0),
  (tamano: telefonoGrande208, escala: 3.0),
];

/// La Lista sola (sin ninguna franja) ya desborda a 300 % en 320×568 y 360×640: su encabezado fijo
/// (título, búsqueda, filtros, contador) mide más que la pantalla. Eso es de la Lista (vista 05), no de
/// este PR: a 300 % la franja solo se mide en el teléfono grande.
const _combosLista = <({Size tamano, double escala})>[
  (tamano: _telefonoMinimo, escala: 1.0),
  (tamano: _telefonoMinimo, escala: 2.0),
  (tamano: telefonoChico208, escala: 1.0),
  (tamano: telefonoChico208, escala: 2.0),
  (tamano: telefonoGrande208, escala: 1.0),
  (tamano: telefonoGrande208, escala: 2.0),
  (tamano: telefonoGrande208, escala: 3.0),
];

/// Donde el encabezado fijo de la Lista (título, búsqueda, filtros, contador) ya ocupa casi toda la
/// pantalla, la franja —que es lo primero de lo que se desplaza, no del encabezado— no entra entera
/// en el pedazo que queda: se ve el comienzo y el resto se alcanza desplazando. Pasa en 320×568 con el
/// texto al 200 % (el encabezado mide ~456 dp) y, con la dirección larga, en 412×915 al 300 %. Es del
/// encabezado de la Lista (vista 05), no de la franja: sin ella la Lista ya desborda a 300 %.
bool _franjaNoEntraSinBajar(String variante, Size tamano, double escala) =>
    (tamano == _telefonoMinimo && escala >= 2.0) ||
    (tamano == telefonoGrande208 && escala >= 3.0 && variante == 'una-falla-direccion-larga');

class _Estado {
  const _Estado(this.nombre, this.datos, this.llegar, {this.situacion});

  final String nombre;
  final DuplicadosEnMemoria Function() datos;
  final Future<void> Function(WidgetTester tester, DuplicadosEnMemoria datos) llegar;
  final SituacionMapa? situacion;
}

Future<void> _nada(WidgetTester tester, DuplicadosEnMemoria datos) async {}

final _estados = <_Estado>[
  const _Estado('lista-3-pares', _datosCanvas, _nada),
  const _Estado('sin-conexion', _datosCanvas, _nada, situacion: situacionSinConexion),
  _Estado('cargando', () => _datosCanvas()..lecturaColgada = true, _nada),
  const _Estado('vacio', DuplicadosEnMemoria.new, _nada),
  _Estado('error-lectura', () => _datosCanvas()..errorDeLectura = StateError('disco'), _nada),
  _Estado('hoja-italia', _datosCanvas, (t, d) => _tocar(t, _revisar(_parItalia))),
  _Estado('hoja-michigan-5m', _datosCanvas, (t, d) => _tocar(t, _revisar(_parMichigan))),
  _Estado('hoja-extremos', _datosExtremos, (t, d) => _tocar(t, _revisar('ub-a|ub-b'))),
  _Estado('par-resuelto-deshacer', _datosCanvas, (t, d) => _unir(t, _parItalia)),
  _Estado('falla-de-union', () => _datosCanvas()..falloAlUnir = const FailureInesperado(), (
    t,
    d,
  ) async {
    await _unir(t, _parItalia);
    await t.pump(_ocho);
    await _asentar(t);
  }),
  // M2: la unión de Italia falla y el aviso rojo se queda mientras la de Michigan espera sus 8 s.
  _Estado('m2-falla-y-otro-par-esperando', _datosCanvas, (t, d) async {
    d.falloAlUnir = const FailureInesperado();
    await _unir(t, _parItalia);
    await t.pump(_ocho);
    await _asentar(t);
    d.falloAlUnir = null;
    await _unir(t, _parMichigan);
    await _asentar(t);
  }),
  // P1 de #357: dos uniones fallan con la pantalla abierta y el aviso rojo (fijo) cuenta los pares.
  _Estado('dos-fallas', _datosCanvas, (t, d) async {
    d.falloAlUnir = const FailureInesperado();
    await _unir(t, _parItalia);
    await t.pump(_ocho);
    await _asentar(t);
    await _unir(t, _parMichigan);
    await t.pump(_ocho);
    await _asentar(t);
  }),
  // El peor caso de altura: dos fallas en el aviso rojo y, a la vez, el aviso «quedaron unidas» de otro.
  _Estado('dos-fallas-y-otro-par-esperando', _datosCanvas, (t, d) async {
    d.falloAlUnir = const FailureInesperado();
    await _unir(t, _parItalia);
    await t.pump(_ocho);
    await _asentar(t);
    await _unir(t, _parMichigan);
    await t.pump(_ocho);
    await _asentar(t);
    d.falloAlUnir = null;
    // La lista quedó bajada por lo anterior: se sube para que el tercer par esté a la vista.
    await t.drag(find.byType(Scrollable).last, const Offset(0, 5000));
    await t.pump();
    await _unir(t, _parMataojo);
    await _asentar(t);
  }),
  _Estado('m3-tres-iguales-A-B-esperando', _datosTresIguales, (t, d) => _unir(t, _parItalia)),
];

class _VarianteLista {
  const _VarianteLista(this.nombre, this.datos, this.fallas);

  final String nombre;
  final DuplicadosEnMemoria Function() datos;

  /// Los pares cuya unión falló fuera de la pantalla (clave del par y quién es A).
  final List<String> fallas;
}

final _variantesLista = <_VarianteLista>[
  const _VarianteLista('sin-falla', _datosDosPares, []),
  const _VarianteLista('una-falla', _datosDosPares, [_parItalia]),
  const _VarianteLista('dos-fallas', _datosDosPares, [_parItalia, _parArtigas]),
  _VarianteLista(
    'una-falla-direccion-larga',
    () => _datosDosPares(
      calleArtigas: 'Avenida Doctor José Gervasio Artigas y Presidente Tomás Berreta',
    ),
    const [_parArtigas],
  ),
];

void main() {
  // ----------------------------------------------------------------------------------------------
  // La franja de la Lista (F3) en la matriz
  // ----------------------------------------------------------------------------------------------
  group('Franja de la Lista (matriz 320×568, 360×640 y 412×915 × texto 100/200/300 %)', () {
    for (final v in _variantesLista) {
      for (final c in _combosLista) {
        _prueba('${v.nombre} · ${_tam(c.tamano)} · x${c.escala}: se ve '
            'entera, sin overflow, con 48 dp y etiqueta', (tester) async {
          final datos = v.datos();
          await _montarLista(
            tester,
            datos,
            escala: c.escala,
            tamano: c.tamano,
            capturaComo: 'lista-${v.nombre}-${_tam(c.tamano)}-x${c.escala}',
            fallas: [
              for (final clave in v.fallas)
                _falla(
                  clave,
                  FormatoUbicaciones.direccion(datos.ubicacion(clave.split('|').first)),
                ),
            ],
          );
          await _asentar(tester);

          expect(tester.takeException(), isNull);
          final conFalla = v.fallas.isNotEmpty;
          final franja = conFalla ? _franjaFalla : _franja;
          expect(franja, findsOneWidget);
          final noEntra = _franjaNoEntraSinBajar(v.nombre, c.tamano, c.escala);
          final caja = tester.getRect(franja);
          expect(caja.left, greaterThanOrEqualTo(0));
          expect(caja.right, lessThanOrEqualTo(c.tamano.width));
          expect(caja.top, greaterThanOrEqualTo(0), reason: 'franja en $caja');
          expect(caja.height, greaterThanOrEqualTo(48));
          expectSinTextoFueraDeLosCostados208(tester, c.tamano);
          if (noEntra) {
            // Se ve el comienzo, arriba de lo que se desplaza, y baja con las filas (no tapa nada).
            expect(caja.top, lessThan(c.tamano.height), reason: 'se ve el comienzo: $caja');
            await tester.dragFrom(Offset(4, caja.top + 8), const Offset(0, -24));
            await _asentar(tester);
            expect(
              tester.getRect(franja).top,
              lessThan(caja.top),
              reason: 'se desplaza con las filas',
            );
            expect(tester.takeException(), isNull);
            return;
          }
          expect(
            caja.bottom,
            lessThanOrEqualTo(c.tamano.height),
            reason: 'la franja está a la vista sin tener que bajar: $caja',
          );
          expect(franja.hitTestable(), findsOneWidget, reason: 'nada la tapa: $caja');
          expect(await _guias(tester), isEmpty);
        });
      }
    }

    test(
      'los colores de la franja llegan a 4.5:1 (texto marrón y «Revisar» azul sobre el ámbar)',
      () {
        const ambar = Color(0xFFFBF1DA);
        expect(contraste208(const Color(0xFF6E5212), ambar), greaterThanOrEqualTo(4.5));
        expect(contraste208(ColoresLista.azul, ambar), greaterThanOrEqualTo(4.5));
      },
    );
  });

  // ----------------------------------------------------------------------------------------------
  // La pantalla en la matriz
  // ----------------------------------------------------------------------------------------------
  group(
    'Pantalla «Posibles duplicados» (matriz 320×568, 360×640 y 412×915 × texto 100/200/300 %)',
    () {
      for (final e in _estados) {
        for (final c in _combos) {
          _prueba(
            '${e.nombre} · ${_tam(c.tamano)} · x${c.escala}: sin overflow, toques de 48/44 dp, '
            'etiquetas y unidades sin corte',
            (tester) async {
              final datos = e.datos();
              await _montarPantalla(
                tester,
                datos,
                escala: c.escala,
                tamano: c.tamano,
                situacion: e.situacion,
              );
              await e.llegar(tester, datos);
              await _asentar(tester);

              expect(tester.takeException(), isNull);
              expectSinTextoFueraDeLosCostados208(tester, c.tamano);
              _expectUnidadesSinCorte(tester);
              expect(await _guias(tester), isEmpty);
              await _capturar(tester, 'pantalla-${e.nombre}-${_tam(c.tamano)}-x${c.escala}');
            },
          );
        }
      }
    },
  );

  // ----------------------------------------------------------------------------------------------
  // Lector de pantalla
  // ----------------------------------------------------------------------------------------------
  group('Lector de pantalla: la franja de la Lista', () {
    _prueba('la franja de siempre y la de la falla son un botón que se anuncia al cambiar', (
      tester,
    ) async {
      final datos = _datosDosPares();
      await _montarLista(tester, datos);
      expect(
        tester.getSemantics(find.bySemanticsLabel('2 posibles duplicados. Revisar')),
        isSemantics(isButton: true, isLiveRegion: true),
      );

      _fallaFuera(tester, _parItalia, 'Av. Italia 1234');
      await _asentar(tester);
      expect(
        tester.getSemantics(find.bySemanticsLabel('No pudimos unir Av. Italia 1234. Revisar')),
        isSemantics(isButton: true, isLiveRegion: true),
      );
    });

    _prueba('la franja de siempre y la de la falla tienen acción de toque para el lector', (
      tester,
    ) async {
      final datos = _datosDosPares();
      await _montarLista(tester, datos);
      expect(
        tester.getSemantics(find.bySemanticsLabel('2 posibles duplicados. Revisar')),
        isSemantics(isButton: true, isLiveRegion: true, hasTapAction: true),
      );

      _fallaFuera(tester, _parItalia, 'Av. Italia 1234');
      await _asentar(tester);
      expect(
        tester.getSemantics(find.bySemanticsLabel('No pudimos unir Av. Italia 1234. Revisar')),
        isSemantics(isButton: true, isLiveRegion: true, hasTapAction: true),
      );
    });

    _prueba(
      'al llegar una falla con la Lista a la vista, el mismo nodo cambia de etiqueta (se anuncia)',
      (tester) async {
        final datos = _datosDosPares();
        await _montarLista(tester, datos);
        expect(find.bySemanticsLabel('2 posibles duplicados. Revisar'), findsOneWidget);

        _fallaFuera(tester, _parItalia, 'Av. Italia 1234');
        await _asentar(tester);
        expect(find.bySemanticsLabel('2 posibles duplicados. Revisar'), findsNothing);
        expect(find.bySemanticsLabel('No pudimos unir Av. Italia 1234. Revisar'), findsOneWidget);

        _fallaFuera(tester, _parArtigas, 'Bulevar Artigas 880');
        await _asentar(tester);
        expect(find.bySemanticsLabel('No pudimos unir 2 pares. Revisar'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel('No pudimos unir 2 pares. Revisar')),
          isSemantics(isLiveRegion: true),
        );
      },
    );

    _prueba('el toque por accesibilidad abre la pantalla igual que el toque con el dedo', (
      tester,
    ) async {
      final datos = _datosDosPares();
      await _montarLista(tester, datos);
      _fallaFuera(tester, _parItalia, 'Av. Italia 1234');
      await _asentar(tester);

      tester.semantics.tap(find.semantics.byLabel('No pudimos unir Av. Italia 1234. Revisar'));
      await _transicion(tester);

      expect(_pagina, findsOneWidget);
      expect(_par(_parItalia), findsOneWidget);
    });
  });

  // ----------------------------------------------------------------------------------------------
  // Casos límite de F3
  // ----------------------------------------------------------------------------------------------
  group('Casos límite de F3 (la franja de la Lista)', () {
    _prueba(
      'dado que el mismo par falla dos veces fuera de la pantalla, la franja dice la dirección '
      '(no "2 pares")',
      (tester) async {
        final datos = _datosDosPares();
        await _montarLista(tester, datos);
        _fallaFuera(tester, _parItalia, 'Av. Italia 1234');
        _fallaFuera(tester, _parItalia, 'Av. Italia 1234');
        await _asentar(tester);

        expect(_texto('No pudimos unir Av. Italia 1234 · Revisar'), findsOneWidget);
        expect(_texto('2 pares'), findsNothing);
      },
    );

    _prueba(
      'dado tres uniones fallidas de un mismo domicilio, la franja dice "No pudimos unir 3 pares"',
      (tester) async {
        final datos = _datosTresIguales();
        await _montarLista(tester, datos);
        for (final clave in ['ub-a|ub-b', 'ub-a|ub-c', 'ub-b|ub-c']) {
          _fallaFuera(tester, clave, 'Av. Italia 1234');
        }
        await _asentar(tester);

        expect(_texto('No pudimos unir 3 pares · Revisar'), findsOneWidget);
        expect(_texto('posibles duplicados'), findsNothing);
      },
    );

    _prueba(
      'dado que A se dio de baja mientras tanto y la unión falla por eso, la Lista no avisa de un '
      'par que ya no existe',
      (tester) async {
        final datos = _datosDosPares();
        await _montarLista(tester, datos);
        await _entrar(tester);
        await _unir(tester, _parItalia);
        datos.darDeBaja('ub-a');
        datos.falloAlUnir = const FailureConservadaDeBaja();
        await _salir(tester);

        expect(_franjaFalla, findsNothing, reason: 'el par Italia ya no existe: nada que revisar');
        expect(_texto('1 posible duplicado · Revisar'), findsOneWidget);
      },
    );

    _prueba(
      'dado el aviso de la Lista, cuando toco "Revisar", vuelvo y una unión nueva falla, el aviso '
      'vuelve a aparecer',
      (tester) async {
        final datos = _datosDosPares();
        await _montarLista(tester, datos);
        await _entrar(tester);
        await _unir(tester, _parItalia);
        datos.falloAlUnir = const FailureInesperado();
        await _salir(tester);
        expect(_franjaFalla, findsOneWidget);

        await _entrar(tester);
        await _salir(tester);
        expect(_franjaFalla, findsNothing, reason: 'tocó "Revisar": lo dio por leído');
        expect(_texto('2 posibles duplicados · Revisar'), findsOneWidget);

        await _entrar(tester);
        await _unir(tester, _parArtigas);
        await _salir(tester);
        expect(_texto('No pudimos unir Bulevar Artigas 880 · Revisar'), findsOneWidget);
        expect(_texto('No pudimos unir 2 pares'), findsNothing, reason: 'la de Italia se leyó');
      },
    );

    _prueba(
      'dado que la unión falla fuera de la pantalla y vuelvo a unir el mismo par con éxito, la '
      'franja deja de avisar',
      (tester) async {
        final datos = _datosDosPares();
        await _montarLista(tester, datos);
        await _entrar(tester);
        await _unir(tester, _parItalia);
        datos.falloAlUnir = const FailureInesperado();
        await _salir(tester);
        datos.falloAlUnir = null;

        await _entrar(tester);
        await _unir(tester, _parItalia);
        await tester.pump(_ocho);
        await _asentar(tester);
        await _salir(tester);

        expect(_franjaFalla, findsNothing);
        expect(_texto('1 posible duplicado · Revisar'), findsOneWidget);
      },
    );

    _prueba('dado un par por distancia sin calle ni número, la franja de la falla no dice '
        '"unir Sin dirección"', (tester) async {
      final datos = DuplicadosEnMemoria()
        ..agregar(_sinDireccion('ub-a', creada: DateTime.utc(2026, 8, 1)))
        ..agregar(_sinDireccion('ub-b', metrosAlNorte: 3, creada: DateTime.utc(2026, 8, 5)));
      await _montarLista(tester, datos);
      await _entrar(tester);
      await _unir(tester, _parItalia);
      datos.falloAlUnir = const FailureInesperado();
      await _salir(tester);

      expect(_franjaFalla, findsOneWidget);
      expect(_texto('unir Sin dirección'), findsNothing);
      expect(_texto('No pudimos unir dos ubicaciones sin dirección · Revisar'), findsOneWidget);
    });
  });

  // ----------------------------------------------------------------------------------------------
  // Casos límite de M2 y M3 en la pantalla
  // ----------------------------------------------------------------------------------------------
  group('Casos límite de M2 y M3 (la pantalla)', () {
    _prueba(
      'dado el aviso rojo de Italia y Michigan esperando, cuando toco "Deshacer", el aviso rojo se '
      'queda y el par de Michigan vuelve',
      (tester) async {
        final datos = _datosCanvas();
        await _montarPantalla(tester, datos);
        await _unir(tester, _parItalia);
        datos.falloAlUnir = const FailureInesperado();
        await _unir(tester, _parMichigan);
        await _asentar(tester);
        expect(_avisoRojo, findsOneWidget);
        expect(find.text('2 para revisar'), findsOneWidget, reason: 'Italia (vuelve) y Mataojo');
        expect(await _hayPar(tester, _parMichigan), isFalse);

        await tester.tap(_deshacer);
        await _asentar(tester);

        await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
        await tester.pump();
        expect(find.text('3 para revisar'), findsOneWidget);
        expect(_avisoRojo, findsOneWidget, reason: 'es de otra unión (M2)');
        expect(await _hayPar(tester, _parMichigan), isTrue);
        expect(await _hayPar(tester, _parItalia), isTrue);
      },
    );

    _prueba(
      'dado el aviso rojo de Italia y Michigan esperando, cuando reintento Italia, las dos uniones '
      'se hacen y no queda ningún aviso',
      (tester) async {
        final datos = _datosCanvas();
        await _montarPantalla(tester, datos);
        await _unir(tester, _parItalia);
        datos.falloAlUnir = const FailureInesperado();
        await _unir(tester, _parMichigan);
        await _asentar(tester);
        expect(_avisoRojo, findsOneWidget);

        datos.falloAlUnir = null;
        await _tocar(tester, _reintentarUnion);
        await tester.pump(_ocho);
        await _asentar(tester);

        expect(datos.uniones, containsAll([(conservadaId: 'ub-a', duplicadaId: 'ub-b')]));
        expect(datos.ubicacion('ub-b').auditoria.estaBorrada, isTrue);
        expect(datos.ubicacion('ub-d').auditoria.estaBorrada, isTrue);
        expect(_avisoRojo, findsNothing);
        expect(find.text('1 para revisar'), findsOneWidget);
      },
    );

    _prueba(
      'dado que dos uniones de pares distintos fallan con la pantalla abierta, nada se pierde: los '
      'dos pares vuelven a la lista y el aviso rojo cuenta los dos (ninguna pisa a la otra)',
      (tester) async {
        final datos = _datosCanvas()..falloAlUnir = const FailureInesperado();
        await _montarPantalla(tester, datos);
        await _unir(tester, _parItalia);
        await _unir(tester, _parMichigan);
        await tester.pump(_ocho);
        await _asentar(tester);

        expect(datos.uniones, hasLength(2));
        expect(find.text('3 para revisar'), findsOneWidget);
        expect(await _hayPar(tester, _parItalia), isTrue);
        expect(await _hayPar(tester, _parMichigan), isTrue);
        expect(_avisoRojo, findsOneWidget);
        expect(
          _texto('No se pudieron marcar 2 pares como duplicados. Probá de nuevo.'),
          findsOneWidget,
        );
      },
    );

    _prueba(
      'dado A←B esperando y A–C a la vista, cuando uno C←A, las dos uniones quedan y los pares con '
      'A y B no reaparecen',
      (tester) async {
        final datos = _datosTresIguales();
        await _montarPantalla(tester, datos);
        await _unir(tester, _parItalia);
        expect(await _hayPar(tester, 'ub-a|ub-c'), isTrue);
        expect(await _hayPar(tester, 'ub-b|ub-c'), isFalse, reason: 'M3: B va a quedar de baja');

        await _tocar(tester, _revisar('ub-a|ub-c'));
        await _tocar(tester, find.byKey(const Key('comparar_opcion_segunda')));
        await _tocar(tester, _conservarYUnir);
        await tester.pump(_ocho);
        await _asentar(tester);

        expect(datos.uniones, [
          (conservadaId: 'ub-a', duplicadaId: 'ub-b'),
          (conservadaId: 'ub-c', duplicadaId: 'ub-a'),
        ]);
        expect(find.text('No hay posibles duplicados'), findsOneWidget);
      },
    );
  });

  // ----------------------------------------------------------------------------------------------
  // Re-QA de #357 (ronda única de fix): P1, P2 y la franja dentro del scroll de la Lista
  // ----------------------------------------------------------------------------------------------
  group('Re-QA de #357 · la franja dentro del scroll de la Lista', () {
    // A 320×568 con el texto al 200 % el encabezado fijo de la Lista mide ~456 dp y la franja (133 dp,
    // o más con una dirección larga) no entra entera en los ~112 dp que quedan: tiene que poder
    // alcanzarse bajando y tocarse (WCAG 1.4.10 y 2.5.8), sin que «+ Nueva» la tape.
    for (final v in _variantesLista.where((v) => v.fallas.isNotEmpty)) {
      _prueba(
        '${v.nombre} · 320x568 · x2.0: bajando un poco la franja queda a la vista y al tocarla se abre '
        '«Posibles duplicados»',
        (tester) async {
          final datos = v.datos();
          await _montarLista(
            tester,
            datos,
            escala: 2,
            tamano: _telefonoMinimo,
            fallas: [
              for (final clave in v.fallas)
                _falla(
                  clave,
                  FormatoUbicaciones.direccion(datos.ubicacion(clave.split('|').first)),
                ),
            ],
          );
          await _asentar(tester);
          final franja = _franjaFalla;
          expect(franja, findsOneWidget);

          final lista = find.byKey(const Key('lista_filas'));
          // Se arrastra desde el borde izquierdo: «+ Nueva» tapa el centro de lo poco que se ve de la lista.
          final arriba = tester.getRect(lista).top;
          for (var i = 0; i < 12 && franja.hitTestable().evaluate().isEmpty; i++) {
            await tester.dragFrom(Offset(6, arriba + 20), const Offset(0, -30));
            await tester.pump();
          }
          expect(
            franja.hitTestable(),
            findsOneWidget,
            reason:
                'bajando se alcanza un punto de la franja que nada tapa: ${tester.getRect(franja)}',
          );
          expect(tester.takeException(), isNull);

          await tester.tap(franja);
          await _transicion(tester);
          expect(_pagina, findsOneWidget);
        },
      );
    }

    _prueba('la franja es lo primero que se ve de la lista, antes de bajar', (tester) async {
      await _montarLista(tester, _datosDosPares(), escala: 2, tamano: _telefonoMinimo);
      await _asentar(tester);
      final franja = tester.getRect(_franja);
      final lista = tester.getRect(find.byKey(const Key('lista_filas')));
      expect(franja.top, closeTo(lista.top + 8, 1), reason: 'franja $franja · lista $lista');
    });

    _prueba('dado que una falla llega con la Lista bajada, la franja de la falla está al subir', (
      tester,
    ) async {
      // Límite conocido: la franja es un ítem más de la lista; con la Lista bajada no se ve ni se
      // anuncia. Al subir está con el texto de la falla (no se pierde).
      final datos = _datosDosPares();
      await _montarLista(tester, datos, escala: 2, tamano: _telefonoMinimo);
      await tester.drag(find.byKey(const Key('lista_filas')), const Offset(0, -300));
      await tester.pump();
      _fallaFuera(tester, _parItalia, 'Av. Italia 1234');
      await _asentar(tester);
      await tester.drag(find.byKey(const Key('lista_filas')), const Offset(0, 800));
      await _asentar(tester);
      expect(_franjaFalla, findsOneWidget);
      expect(_texto('No pudimos unir Av. Italia 1234'), findsOneWidget);
    });
  });

  group('Re-QA de #357 · P1 el aviso rojo fijo de la pantalla', () {
    Future<void> dosFallasEnPantalla(
      WidgetTester tester, {
      double escala = 1,
      Size tamano = telefonoChico208,
    }) async {
      final datos = _datosCanvas()..falloAlUnir = const FailureInesperado();
      await _montarPantalla(tester, datos, escala: escala, tamano: tamano);
      await _unir(tester, _parItalia);
      await tester.pump(_ocho);
      await _asentar(tester);
      await _unir(tester, _parMichigan);
      await tester.pump(_ocho);
      await _asentar(tester);
    }

    _prueba(
      'dado un aviso con una falla, cuando llega otra, el mismo aviso se actualiza con la cuenta '
      '(región viva: el lector lo anuncia)',
      (tester) async {
        final datos = _datosCanvas()..falloAlUnir = const FailureInesperado();
        await _montarPantalla(tester, datos);
        await _unir(tester, _parItalia);
        await tester.pump(_ocho);
        await _asentar(tester);
        expect(
          tester.getSemantics(find.bySemanticsLabel(RegExp('No se pudo marcar como duplicado'))),
          isSemantics(isLiveRegion: true),
        );

        await _unir(tester, _parMichigan);
        await tester.pump(_ocho);
        await _asentar(tester);
        final nodo = tester.getSemantics(
          find.bySemanticsLabel(RegExp('No se pudieron marcar 2 pares como duplicados')),
        );
        expect(nodo, isSemantics(isLiveRegion: true));
        expect(find.bySemanticsLabel(RegExp('No se pudo marcar como duplicado')), findsNothing);
      },
    );

    _prueba(
      'dado dos fallas donde una no se puede reintentar, "Reintentar" prueba solo la otra y el '
      'aviso queda con la que no, sin "Reintentar"',
      (tester) async {
        final datos = _datosCanvas()..falloAlUnir = const FailureInesperado();
        await _montarPantalla(tester, datos);
        await _unir(tester, _parItalia);
        await tester.pump(_ocho);
        await _asentar(tester);
        await _unir(tester, _parMichigan);
        datos.falloAlUnir = const FailureConservadaDeBaja();
        await tester.pump(_ocho);
        await _asentar(tester);
        expect(datos.uniones, hasLength(2));
        expect(_reintentarUnion, findsOneWidget, reason: 'una de las dos se puede reintentar');
        expect(_texto('No se pudieron marcar 2 pares como duplicados'), findsOneWidget);

        datos.falloAlUnir = null;
        await _tocar(tester, _reintentarUnion);
        await _asentar(tester);

        expect(datos.uniones, hasLength(3), reason: 'solo la reintentable corrió de nuevo');
        expect(_avisoRojo, findsOneWidget, reason: 'la que no se puede reintentar sigue avisada');
        expect(_reintentarUnion, findsNothing);
        expect(_texto('No se pudieron marcar'), findsNothing);
        expect(find.byKey(const Key('duplicados_descartar_falla')), findsOneWidget);
      },
    );

    _prueba('dado una falla, dos toques seguidos en "Reintentar" corren la unión una sola vez', (
      tester,
    ) async {
      final datos = _datosCanvas()..falloAlUnir = const FailureInesperado();
      await _montarPantalla(tester, datos);
      await _unir(tester, _parItalia);
      await tester.pump(_ocho);
      await _asentar(tester);
      expect(datos.uniones, hasLength(1));

      datos.falloAlUnir = null;
      await tester.ensureVisible(_reintentarUnion);
      await tester.pump();
      final centro = tester.getCenter(_reintentarUnion);
      await tester.tapAt(centro);
      await tester.tapAt(centro);
      await _asentar(tester);

      expect(datos.uniones, hasLength(2), reason: 'un solo reintento, no dos');
      expect(_avisoRojo, findsNothing);
    });

    _prueba(
      'dado dos fallas, cuando salgo y vuelvo a entrar, el aviso no queda pegado y los dos pares '
      'siguen para revisar',
      (tester) async {
        await dosFallasEnPantalla(tester);
        expect(_avisoRojo, findsOneWidget);

        await tester.tap(find.byKey(const Key('duplicados_volver')));
        await _transicion(tester);
        await tester.tap(find.byKey(const Key('abrir')));
        await _transicion(tester);

        expect(_avisoRojo, findsNothing);
        expect(await _hayPar(tester, _parItalia), isTrue);
        expect(await _hayPar(tester, _parMichigan), isTrue);
      },
    );

    // El aviso rojo (fijo) y el aviso «quedaron unidas» de otro par (8 s) a la vez: la persona tiene que
    // poder tocar «Reintentar» y «Entendido» y ver algo de la lista aunque el SnackBar tape el pie.
    for (final fallas in [1, 2]) {
      for (final c in const [
        (tamano: Size(320, 568), escala: 2.0),
        (tamano: Size(320, 568), escala: 3.0),
        (tamano: Size(360, 640), escala: 3.0),
        (tamano: Size(412, 915), escala: 3.0),
      ]) {
        final alAire = !_avisoYSnackEntran(c.tamano);
        _prueba(
          '${alAire ? 'QA #357 hallazgo · ' : ''}$fallas falla(s) y otro par esperando sus 8 s · '
          '${_tam(c.tamano)} · x${c.escala}: se pueden tocar «Reintentar», «Entendido» y «Deshacer» y '
          'queda lista a la vista',
          (tester) async {
            await _avisoRojoMasSnackbar(tester, fallas, c.tamano, c.escala);

            final lista = tester.getRect(find.byType(ListView).first);
            final snack = tester.getRect(find.byType(SnackBar));
            final visible = (snack.top - lista.top).clamp(0.0, lista.height);
            expect(tester.takeException(), isNull);
            expect(_deshacer.hitTestable(), findsOneWidget);
            expect(
              _reintentarUnion.hitTestable(),
              findsOneWidget,
              reason: 'tapado por el SnackBar',
            );
            expect(
              find.byKey(const Key('duplicados_descartar_falla')).hitTestable(),
              findsOneWidget,
              reason: 'tapado por el SnackBar: snack $snack',
            );
            expect(
              visible,
              greaterThanOrEqualTo(c.tamano.height / 6),
              reason: 'de la lista se ven $visible dp entre el aviso rojo y el SnackBar',
            );
          },
          // skip: QA #357 — con el aviso rojo fijo y el «quedaron unidas» de otro par (8 s) a la vez, en un
          // teléfono chico con texto grande el SnackBar tapa «Entendido» y casi toda la lista.
          skip: alAire && !_verHallazgos,
        );
      }
    }

    for (final c in const [
      (tamano: Size(320, 568), escala: 2.0),
      (tamano: Size(320, 568), escala: 3.0),
      (tamano: Size(360, 640), escala: 3.0),
    ]) {
      _prueba(
        'dos fallas, pasados los 8 s del otro par · ${_tam(c.tamano)} · x${c.escala}: el aviso rojo se '
        'puede tocar y la lista conserva al menos un tercio',
        (tester) async {
          await _avisoRojoMasSnackbar(tester, 2, c.tamano, c.escala);
          await tester.pump(_ocho);
          await _asentar(tester);
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(SnackBar), findsNothing);
          expect(tester.takeException(), isNull);
          expect(_reintentarUnion.hitTestable(), findsOneWidget);
          await tester.ensureVisible(find.byKey(const Key('duplicados_descartar_falla')));
          await tester.pump();
          expect(find.byKey(const Key('duplicados_descartar_falla')).hitTestable(), findsOneWidget);
          expect(
            tester.getRect(find.byType(ListView).first).height,
            greaterThanOrEqualTo(c.tamano.height / 3),
          );
        },
      );
    }
  });
}
