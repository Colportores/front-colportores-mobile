// Arnés de la QA de «Venta crece» (vista 42, 42B·09A a 09D; HU-VEN-001, #693): ventas abiertas que
// cambian en vivo y por persona, la hoja de la casa real y la ficha real con «Sumar un libro»
// enchufado, fuentes reales y capturas (`--dart-define=QA_CAPTURAS=true` → `.dart_tool/qa_capturas/`,
// gitignored).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/restaurar_espacio_use_case.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/ficha_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ficha_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/notas_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_abierta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_item.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/ficha_persona_arnes.dart'
    show MundoFicha, ahoraFicha, cuentaConSaldo, historialDelCanvas;
import 'agendar_visita_arnes.dart' show AgendaRepositorioQueAgenda;
import 'hoja_casa_falsos.dart';
import 'lista_ubicaciones_falsos.dart' show ahoraLista;
import 'venta_falsos.dart';

export 'venta_falsos.dart';

/// Tamaños lógicos de la matriz de QA: el chico y el grande.
const telefonoChico693 = Size(360, 640);
const telefonoGrande693 = Size(412, 915);

/// La raíz de las capturas.
final raiz693 = GlobalKey();

const conCapturas693 = bool.fromEnvironment('QA_CAPTURAS');

/// Carga Inter, SourceSerif4 y JetBrainsMono de `assets/fonts/` y los íconos de Material: sin eso
/// `flutter_test` dibuja cajas y mide el texto con Ahem.
Future<void> cargarFuentes693(WidgetTester tester) async {
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
}

/// Una captura PNG de [raiz693] en `.dart_tool/qa_capturas/693_<nombre>.png` (solo con `QA_CAPTURAS`).
Future<void> capturar693(WidgetTester tester, String nombre) async {
  if (!conCapturas693) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz693));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/693_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Una venta abierta como la 0039 de Pedro: $ 1.200, $ 400 pagos, entregada.
VentaAbierta ventaAbierta693(
  String id, {
  String numero = '0039',
  DateTime? fecha,
  int total = 120000,
  int cobrado = 40000,
  bool entregada = true,
  String descripcion = 'Colección de 1 libro',
  String personaVinculo = 'ep-p-pedro',
  String? motivo,
  List<RenglonYaVendido> renglones = const [],
}) => VentaAbierta(
  ventaId: id,
  espacioPersonaId: personaVinculo,
  numeroTalonario: numero,
  fecha: fecha ?? DateTime.utc(2026, 10, 23, 15),
  montoTotalCentavos: total,
  cobradoCentavos: cobrado,
  entregada: entregada,
  entregadaEl: entregada ? DateTime.utc(2026, 10, 23, 15) : null,
  descripcion: descripcion,
  motivoMontoManual: motivo,
  renglones: renglones,
);

/// El repositorio de «Venta crece» de la QA: ventas abiertas **por persona** y en vivo ([cambiar]),
/// una lectura que se puede demorar o fallar y un guardado que puede fallar con una excepción.
final class VentasAbiertasQA extends VentaQueCreceEnMemoria {
  VentasAbiertasQA({this.porPersona = const {}, super.abiertas, super.citas});

  /// Las ventas abiertas de cada persona; las que no están, [abiertas].
  Map<String, List<VentaAbierta>> porPersona;

  /// Las personas por las que se pidió leer, en orden.
  final lecturas = <String>[];

  /// Si no es `null`, la lectura espera a que se complete (antes del primer dato).
  Completer<void>? compuertaLectura;

  /// Si no es `null`, [sumar] lanza esto (una excepción, no una falla).
  Object? lanzarAlSumar;

  final _vivos = <({String persona, StreamController<List<VentaAbierta>> c})>[];

  List<VentaAbierta> _de(String personaId) => porPersona[personaId] ?? abiertas;

  @override
  Stream<List<VentaAbierta>> observarAbiertasDe(String personaId) {
    lecturas.add(personaId);
    final error = errorAlLeer;
    if (error != null) return Stream.error(error);
    late final StreamController<List<VentaAbierta>> c;
    c = StreamController<List<VentaAbierta>>(onCancel: () => _vivos.removeWhere((v) => v.c == c));
    _vivos.add((persona: personaId, c: c));
    unawaited(() async {
      await compuertaLectura?.future;
      if (!c.isClosed) c.add(_de(personaId));
    }());
    return c.stream;
  }

  /// Cambia las ventas abiertas de [personaId] y avisa a quien las mira (se pagó, se anuló…).
  void cambiar(String personaId, List<VentaAbierta> nuevas) {
    porPersona = {...porPersona, personaId: nuevas};
    for (final v in _vivos.where((v) => v.persona == personaId)) {
      if (!v.c.isClosed) v.c.add(nuevas);
    }
  }

  @override
  Future<Either<Failure, VentaQueCrecio>> sumar(
    String ventaId,
    List<VentaItem> itemsNuevos, {
    required String numeroTalonario,
    required int sumadoCentavos,
    required DateTime ahora,
    String? motivoMontoManual,
    int? diferenciaCentavos,
  }) {
    final error = lanzarAlSumar;
    if (error != null) {
      sumas.add((
        ventaId: ventaId,
        items: itemsNuevos,
        sumado: sumadoCentavos,
        motivo: motivoMontoManual,
        diferencia: diferenciaCentavos,
      ));
      throw error;
    }
    return super.sumar(
      ventaId,
      itemsNuevos,
      numeroTalonario: numeroTalonario,
      sumadoCentavos: sumadoCentavos,
      ahora: ahora,
      motivoMontoManual: motivoMontoManual,
      diferenciaCentavos: diferenciaCentavos,
    );
  }
}

/// Lo que recibió «Sumar un libro» (la casa y la persona) cada vez que se tocó.
typedef Destino693 = ({String ubicacionId, String espacioId, String personaId});

/// Un destino de «Sumar un libro» que anota lo que recibe y devuelve lo que se le pida.
final class DestinoQA {
  DestinoQA([this.respuesta = const VentaRegistradaEnLaCasa()]);

  Object? respuesta;
  Object? lanzar;
  Completer<void>? compuerta;
  final recibidos = <Destino693>[];

  Future<Object?> llamar(ContextoDeCobro datos) async {
    recibidos.add((
      ubicacionId: datos.ubicacionId,
      espacioId: datos.espacioId ?? '',
      personaId: datos.personaId,
    ));
    await compuerta?.future;
    final error = lanzar;
    if (error != null) throw error;
    return respuesta;
  }
}

/// Monta la hoja de la casa REAL (C·01) con «Sumar un libro» enchufado a [destino] (o sin destino).
Future<List<int>> montarHoja693(
  WidgetTester tester, {
  required VentasAbiertasQA repo,
  DestinoQA? destino,
  bool sinDestino = false,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool lector = false,
  ItemListaUbicacion? item,
  ContextoDeLaCasa? contexto,
  Stream<ContextoDeLaCasa> Function(ClaveDeLaCasa clave)? lectura,
  FutureOr<void> Function(ContextoDeCobro)? cobrar,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cierres = <int>[];
  final d = destino ?? DestinoQA();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...overridesHojaCasa(
          cobrar: cobrar ?? (_) {},
          lectura: lectura ?? (contexto == null ? null : (_) => Stream.value(contexto)),
        ),
        ventaQueCreceRepositoryProvider.overrideWithValue(repo),
        sumarUnLibroDesdeLaCasaProvider.overrideWithValue(sinDestino ? null : d.llamar),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala), accessibleNavigation: lector),
          child: child!,
        ),
        home: RepaintBoundary(
          key: raiz693,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: HojaCasa(
                item: item ?? itemDeLaHoja(),
                ahora: ahoraLista,
                alCerrar: () => cierres.add(cierres.length),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  return cierres;
}

/// Monta la ficha REAL de María (32B) con «Sumar un libro» enchufado.
Future<MundoFicha> montarFicha693(
  WidgetTester tester, {
  required VentasAbiertasQA repo,
  DestinoQA? destino,
  bool sinDestino = false,
  double escala = 1,
  Size tamano = const Size(390, 844),
  MundoFicha? mundo,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final m = mundo ?? MundoFicha(historial: historialDelCanvas());
  m.cuentas.cuenta ??= cuentaConSaldo;
  final d = destino ?? DestinoQA();
  var contador = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fichaPersonaRepositoryProvider.overrideWithValue(m.fichas),
        notaPersonaRepositoryProvider.overrideWithValue(m.notas),
        espacioRepositoryProvider.overrideWithValue(m.espacios),
        cuentasDePersonasProvider.overrideWithValue(m.cuentas),
        movimientosDeCuentaProvider.overrideWithValue(m.movimientos),
        marcadorDeTelefonoProvider.overrideWithValue(m.marcador),
        personaRepositoryProvider.overrideWithValue(m.personas),
        restaurarEspacioUseCaseProvider.overrideWithValue(RestaurarEspacioUseCase(m.espacios)),
        relojPersonaProvider.overrideWithValue(() => ahoraFicha),
        generadorIdPersonaProvider.overrideWithValue(() => 'nota-nueva-${++contador}'),
        agendaRepositoryProvider.overrideWithValue(AgendaRepositorioQueAgenda()),
        ventaQueCreceRepositoryProvider.overrideWithValue(repo),
        sumarUnLibroDesdeLaCasaProvider.overrideWithValue(sinDestino ? null : d.llamar),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: RepaintBoundary(key: raiz693, child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => FichaPersonaPage.abrir(
                  context,
                  personaId: 'per-1',
                  espacioId: 'esp-1',
                  colportorId: 'col-1',
                ),
                child: const Text('abrir ficha'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir ficha'));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return m;
}

/// Asienta: unos cuadros para que corran las animaciones y los `Stream` en memoria.
Future<void> asentar693(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Ningún texto visible se sale de la pantalla por los costados ni por abajo del alto de la vista.
List<String> textosFueraDeLaPantalla693(WidgetTester tester, Size pantalla) {
  final fuera = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final texto = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (texto.trim().isEmpty) continue;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
    final caja = ro.localToGlobal(Offset.zero) & ro.size;
    if (caja.left < -0.5 || caja.right > pantalla.width + 0.5) fuera.add(texto);
  }
  return fuera;
}

/// Una captura PNG de toda la pantalla (incluye hojas modales) en `.dart_tool/qa_capturas/693_<nombre>.png`.
Future<void> capturarPantalla693(WidgetTester tester, String nombre) async {
  if (!conCapturas693) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(vista.paintBounds);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/693_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
