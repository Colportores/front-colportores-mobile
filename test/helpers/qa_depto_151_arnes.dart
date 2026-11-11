// Arnés de los tests de QA de «Registrar visita» y el estado de la última visita en la ficha del depto
// (vista 11·04, HU-VIS-005, #151, PR #574): lleva la pantalla real, a los tamaños de la matriz de QA,
// a cada uno de sus estados, y saca capturas a `.dart_tool/qa_capturas/151_*.png` (gitignored: nunca se
// commitean; solo con `--dart-define=QA_CAPTURAS=true`).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ultima_visita_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/services/lector_ultima_visita_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_visita_del_depto.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/personas_arnes.dart';
import 'persona_falsos.dart';
import 'ultima_visita_del_espacio_falsos.dart';

export '../widget/mapa/personas_arnes.dart' show asentar, contextoActivo;
export 'persona_falsos.dart';
export 'ultima_visita_del_espacio_falsos.dart';

const telefonoChico151 = Size(360, 640);
const telefonoGrande151 = Size(412, 915);

/// ¿Se cargan las fuentes reales? Las guías de contraste las apagan (con letra real el
/// `textContrastGuideline` da falsos negativos).
bool usarFuentesReales151 = true;
var _fuentesCargadas = false;

Future<void> cargarFuentes151(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales151) return;
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
        final roboto = FontLoader('Roboto');
        for (final peso in ['Regular', 'Medium', 'Bold']) {
          final f = File('${dir.path}/artifacts/material_fonts/Roboto-$peso.ttf');
          if (f.existsSync()) {
            roboto.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
          }
        }
        await roboto.load();
        break;
      }
    }
  });
  _fuentesCargadas = true;
}

/// Una captura PNG de todo lo que se ve en `.dart_tool/qa_capturas/151_<nombre>.png`.
Future<void> capturar151(WidgetTester tester, String nombre) async {
  if (!const bool.fromEnvironment('QA_CAPTURAS')) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & (vista.size));
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/151_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

final botonRegistrar151 = find.byKey(ClavesVisitaDelDepto.registrar);
final pildoraEstado151 = find.byKey(ClavesVisitaDelDepto.estado);

/// Lo que recibió el destino de «Registrar visita» y cómo contesta.
final class Destino151 {
  final contextos = <ContextoDeVisita>[];

  /// Si no es `null`, el destino espera a que se complete (la hoja «¿Qué pasó?» abierta).
  Completer<Object?>? compuerta;
  Object? contesta = true;
  Object? lanza;

  Future<Object?> llamar(ContextoDeVisita datos) async {
    contextos.add(datos);
    final espera = compuerta;
    if (espera != null) await espera.future;
    final falla = lanza;
    if (falla != null) throw falla;
    return contesta;
  }
}

/// Un lector controlable: emite lo que se le manda, valores o errores, cuando se quiere.
final class LectorControlable151 implements LectorUltimaVisitaDelEspacio {
  final _ctl = StreamController<UltimaVisitaDelEspacio?>.broadcast();
  var lecturas = 0;

  void valor(UltimaVisitaDelEspacio? v) => _ctl.add(v);
  void error(Object e) => _ctl.addError(e);

  @override
  Stream<UltimaVisitaDelEspacio?> observar(String espacioId) {
    lecturas++;
    return _ctl.stream;
  }
}

/// Cada estado de la ficha del depto.
enum Estado151 {
  entrevista('11·04 entrevista hecha (canvas)'),
  noContesto('no contestó'),
  rechazo('rechazó'),
  venta('venta'),
  cobranza('cobranza'),
  sinVisitas('sin visitas todavía'),
  leyendo('leyendo el estado'),
  errorDeLectura('error al leer el estado'),
  deptoDeBaja('depto dado de baja'),
  sinDestino('sin destino enganchado'),
  sinClientes('sin clientes'),
  muchosClientes('40 clientes'),
  textosLargos('nombres de clientes larguísimos'),
  conEntrevistasYBajas('con bajas'),
  avisoDeFalla('aviso de falla al abrir');

  const Estado151(this.rotulo);

  final String rotulo;
}

PersonaRepositorioFalso _clientes(Estado151 e) {
  final repo = PersonaRepositorioFalso();
  switch (e) {
    case Estado151.sinClientes:
      break;
    case Estado151.muchosClientes:
      repo.sembrar([
        for (var i = 0; i < 40; i++)
          clienteDePersonas(
            'p$i',
            'Cliente$i',
            apellido: 'Apellido$i',
            telefono: '099 123 4${i.toString().padLeft(2, '0')}',
            minutos: i,
          ),
      ]);
    case Estado151.textosLargos:
      repo.sembrar([
        clienteDePersonas(
          'p1',
          'Maria de los Angeles Fernandez',
          apellido: 'Rodriguez de Santa Cruz y Barrios',
          telefono: '099 123 412',
          minutos: 0,
        ),
        clienteDePersonas('p2', 'Pedro', apellido: 'Rodríguez', minutos: 1),
      ]);
    case Estado151.conEntrevistasYBajas:
      repo.sembrar([
        clienteDePersonas('p1', 'Ana', apellido: 'Martínez', telefono: '099 123 412', minutos: 0),
        clienteDeBajaDePersonas('p3', 'Luis', apellido: 'Pérez', minutos: 2),
      ]);
    default:
      repo.sembrar([
        clienteDePersonas('p1', 'Ana', apellido: 'Martínez', telefono: '099 123 412', minutos: 0),
        clienteDePersonas('p2', 'Pedro', apellido: 'Rodríguez', minutos: 1),
      ]);
  }
  return repo;
}

LectorUltimaVisitaDelEspacio _lector(Estado151 e) => switch (e) {
  Estado151.noContesto => LectorUltimaVisitaFalso(
    visitaDel20deSeptiembre(TipoResultadoVisita.noContesto),
  ),
  Estado151.rechazo => LectorUltimaVisitaFalso(
    visitaDel20deSeptiembre(TipoResultadoVisita.rechazo),
  ),
  Estado151.venta => LectorUltimaVisitaFalso(visitaDel20deSeptiembre(TipoResultadoVisita.venta)),
  Estado151.cobranza => LectorUltimaVisitaFalso(
    visitaDel20deSeptiembre(TipoResultadoVisita.cobranza),
  ),
  Estado151.sinVisitas => LectorUltimaVisitaFalso(),
  Estado151.leyendo => LectorUltimaVisitaCargando(),
  Estado151.errorDeLectura => LectorUltimaVisitaQueFalla(),
  _ => LectorUltimaVisitaFalso(visitaDel20deSeptiembre()),
};

/// El texto que debe decir la píldora en cada estado (`null`: no hay píldora).
String? textoDePildora151(Estado151 e) => switch (e) {
  Estado151.noContesto => 'No contestó · 20/09',
  Estado151.rechazo => 'Rechazó · 20/09',
  Estado151.venta => 'Venta · 20/09',
  Estado151.cobranza => 'Cobranza · 20/09',
  Estado151.sinVisitas => 'Sin visitas todavía',
  Estado151.leyendo || Estado151.errorDeLectura => null,
  _ => 'Entrevista hecha · 20/09',
};

/// Lleva la pantalla real al estado [e] a [tamano] y [escala].
Future<Destino151> llegar151(
  WidgetTester tester,
  Estado151 e, {
  Size tamano = telefonoChico151,
  double escala = 1,
}) async {
  await cargarFuentes151(tester);
  final destino = Destino151();
  if (e == Estado151.avisoDeFalla) destino.lanza = StateError('boom');
  await montarClientes(
    tester,
    repo: _clientes(e),
    escala: escala,
    tamano: tamano,
    contexto: e == Estado151.deptoDeBaja
        ? contextoActivo(espacioDeBaja: DateTime.utc(2026, 10, 24))
        : null,
    otrosOverrides: [
      lectorUltimaVisitaDelEspacioProvider.overrideWithValue(_lector(e)),
      if (e != Estado151.sinDestino)
        registrarVisitaDesdeLaCasaProvider.overrideWithValue(destino.llamar),
    ],
  );
  if (e == Estado151.avisoDeFalla) {
    await tester.tap(botonRegistrar151);
    await asentar(tester);
  }
  return destino;
}
