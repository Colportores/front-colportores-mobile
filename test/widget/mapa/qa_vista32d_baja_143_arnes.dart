// Arnés de la QA de #143 (vista 32D, baja de persona y «Ver bajas», PR #485): los estados de la hoja
// «¿Dar de baja a …?» (D·01 a D·03 y los que el canvas no dibuja) y de «Mostrar bajas» (D·04, D·05),
// con las fuentes reales del proyecto y la matriz de tamaños y escalas de texto de la QA.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`
// (ignorado por git: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'baja_persona_arnes.dart';
import 'hoja_con_quien_arnes.dart' show SaldosFalsos;
import 'personas_arnes.dart';

const conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Los dos teléfonos de la matriz de la QA y las dos escalas de texto.
const tamanos = [Size(360, 640), Size(412, 915)];
const escalas = [1.0, 2.0];

bool _fuentesCargadas = false;

/// `false` solo para la guía de contraste de Flutter: con las fuentes reales (trazos de 1 px,
/// suavizados) da falsos negativos; con las cajas de Ahem lee el color de verdad.
bool usarFuentesReales = true;

/// Sin las fuentes del proyecto `flutter_test` pinta cajas (Ahem) y las medidas no son las reales.
Future<void> cargarFuentes(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'] ?? _raizDeFlutter();
    final roboto = File('$raiz/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
    if (roboto.existsSync()) {
      final bytes = roboto.readAsBytesSync();
      final cargador = FontLoader('Roboto')..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
  });
  _fuentesCargadas = true;
}

String _raizDeFlutter() {
  // .../bin/cache/dart-sdk/bin/dart  ->  .../
  var d = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    if (Directory('${d.path}/bin/cache/artifacts/material_fonts').existsSync()) return d.path;
    d = d.parent;
  }
  return '';
}

/// La pantalla completa (con la hoja modal) como PNG, solo con `--dart-define=QA_CAPTURAS=true`.
Future<void> capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final tam = tester.view.physicalSize;
    final img = await capa.toImage(Offset.zero & tam);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa143_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// El [finder] cabe entero en la pantalla (no queda tapado por el borde ni fuera del viewport).
void dentroDeLaPantalla(WidgetTester tester, Finder finder, {String? rotulo}) {
  final r = tester.getRect(finder.first);
  final v = tester.view.physicalSize;
  expect(r.left, greaterThanOrEqualTo(-0.5), reason: '${rotulo ?? finder} sale por la izquierda');
  expect(r.top, greaterThanOrEqualTo(-0.5), reason: '${rotulo ?? finder} sale por arriba');
  expect(
    r.right,
    lessThanOrEqualTo(v.width + 0.5),
    reason: '${rotulo ?? finder} sale por la derecha',
  );
  expect(r.bottom, lessThanOrEqualTo(v.height + 0.5), reason: '${rotulo ?? finder} sale por abajo');
}

/// Desplaza la lista hasta que [finder] quede a la vista (`ensureVisible` sin un cuadro después no mueve
/// nada que se pueda medir).
Future<void> verEnPantalla(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    // Lista perezosa: lo que está más abajo todavía no se construyó.
    await tester.scrollUntilVisible(
      finder,
      150,
      maxScrolls: 80,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
}

/// Los estados de la hoja de baja: cada artboard del canvas (D·01 a D·03) y los que no dibuja.
enum EstadoHoja {
  d01('D01 sin saldo'),
  d02('D02 con saldo resumen'),
  d03('D03 segunda confirmacion'),
  revisando('revisando la cuenta'),
  errorRevision('error al revisar la cuenta'),
  dandoDeBaja('dando de baja'),
  fallaSinSaldo('falla al dar de baja sin saldo'),
  fallaConfirmar('falla al dar de baja en la segunda confirmacion');

  const EstadoHoja(this.rotulo);

  final String rotulo;
}

/// Escenario de la hoja ya montado.
final class EscenarioHoja {
  EscenarioHoja({required this.repo, required this.cuentas, required this.resultado});

  final PersonaRepositorioFalso repo;
  final CuentasFalsas cuentas;
  final ResultadoBaja resultado;
}

/// Monta la hoja de [nombre] y la lleva al [estado].
Future<EscenarioHoja> hojaEn(
  WidgetTester tester,
  EstadoHoja estado, {
  Size tamano = const Size(360, 640),
  double escala = 1,
  String nombre = 'Jorge',
  String apellido = 'Fernández',
}) async {
  await cargarFuentes(tester);
  final conSaldo = switch (estado) {
    EstadoHoja.d02 || EstadoHoja.d03 || EstadoHoja.fallaConfirmar => true,
    _ => false,
  };
  final cuentas = CuentasFalsas(
    cuenta: conSaldo ? cuentaConSaldo : null,
    lanza: estado == EstadoHoja.errorRevision ? StateError('no se pudo leer') : null,
    compuerta: estado == EstadoHoja.revisando ? Completer<void>() : null,
  );
  final repo = PersonaRepositorioFalso()
    ..sembrar([clienteDePersonas('p1', nombre, apellido: apellido)]);
  if (estado == EstadoHoja.dandoDeBaja) repo.compuertaBaja = Completer<void>();
  if (estado == EstadoHoja.fallaSinSaldo || estado == EstadoHoja.fallaConfirmar) {
    repo.resultadosBaja.add(const FailureInesperado());
  }
  final resultado = await montarHojaBaja(
    tester,
    repo: repo,
    cuentas: cuentas,
    persona: personaParaBaja(nombre: nombre, apellido: apellido),
    tamano: tamano,
    escala: escala,
  );
  switch (estado) {
    case EstadoHoja.d03 || EstadoHoja.fallaConfirmar:
      await tester.tap(find.text('Dar de baja igual'));
      await asentar(tester);
      if (estado == EstadoHoja.fallaConfirmar) {
        await tester.tap(find.text('Sí, dar de baja'));
        await asentar(tester);
      }
    case EstadoHoja.dandoDeBaja || EstadoHoja.fallaSinSaldo:
      await tester.tap(find.text('Dar de baja'));
      await asentar(tester);
    default:
  }
  return EscenarioHoja(repo: repo, cuentas: cuentas, resultado: resultado);
}

/// Los estados de «Mostrar bajas» (D·04, D·05) y los que el canvas no dibuja.
enum EstadoBajas {
  d04('D04 ver bajas con saldo'),
  d04SinSaldo('D04 ver bajas sin saldo conocido'),
  d05('D05 reactivada'),
  reactivando('reactivando'),
  fallaReactivar('falla al reactivar'),
  errorBajas('error al leer las bajas'),
  espacioDeBaja('espacio de baja: bajas sin reactivar'),
  soloBajas('todas de baja'),
  listaLarga('40 bajas');

  const EstadoBajas(this.rotulo);

  final String rotulo;
}

/// Overrides de reloj y saldos de «Mostrar bajas».
List<Override> extrasBajas({Map<String, int>? saldos}) => [
  relojPersonaProvider.overrideWithValue(() => ahoraBaja),
  if (saldos != null) saldosDePersonasProvider.overrideWithValue(SaldosFalsos(saldos)),
];

/// Monta los clientes del depto en el [estado] y devuelve el repositorio.
Future<PersonaRepositorioFalso> bajasEn(
  WidgetTester tester,
  EstadoBajas estado, {
  Size tamano = const Size(360, 640),
  double escala = 1,
}) async {
  await cargarFuentes(tester);
  final repo = PersonaRepositorioFalso();
  switch (estado) {
    case EstadoBajas.soloBajas:
      repo.sembrar([clienteDeBajaDePersonas('p2', 'María', apellido: 'Fernández')]);
    case EstadoBajas.listaLarga:
      repo.sembrar([
        clienteDePersonas('p1', 'Jorge', apellido: 'Fernández'),
        for (var i = 0; i < 40; i++)
          clienteDeBajaDePersonas('b$i', 'Persona$i', apellido: 'Apellido', minutos: i),
      ]);
    default:
      repo.sembrar([
        clienteDePersonas('p1', 'Jorge', apellido: 'Fernández'),
        clienteDeBajaDePersonas('p2', 'María', apellido: 'Fernández', minutos: 1),
      ]);
  }
  if (estado == EstadoBajas.reactivando) repo.compuertaReactivar = Completer<void>();
  if (estado == EstadoBajas.fallaReactivar) repo.resultadosReactivar.add(const FailureInesperado());
  await montarClientes(
    tester,
    repo: estado == EstadoBajas.errorBajas ? _RepoQueNoLeeBajas() : repo,
    contexto: estado == EstadoBajas.espacioDeBaja
        ? contextoActivo(espacioDeBaja: DateTime.utc(2026, 10, 20))
        : null,
    tamano: tamano,
    escala: escala,
    otrosOverrides: extrasBajas(
      saldos: estado == EstadoBajas.d04 || estado == EstadoBajas.listaLarga ? {'p2': 120000} : null,
    ),
  );
  if (estado != EstadoBajas.errorBajas) {
    final interruptor = find.widgetWithText(SwitchListTile, 'Mostrar bajas');
    await verEnPantalla(tester, interruptor);
    await tester.tap(interruptor);
    await asentar(tester);
  }
  switch (estado) {
    case EstadoBajas.d05 || EstadoBajas.fallaReactivar || EstadoBajas.reactivando:
      final boton = find.widgetWithText(TextButton, 'Reactivar').first;
      await verEnPantalla(tester, boton);
      await tester.tap(boton);
      await asentar(tester);
    default:
  }
  return repo;
}

/// Repositorio cuya lectura de bajas falla y el resto sale del repositorio real.
final class _RepoQueNoLeeBajas extends PersonaRepositorioFalso {
  _RepoQueNoLeeBajas() {
    sembrar([clienteDePersonas('p1', 'Jorge', apellido: 'Fernández')]);
  }

  @override
  Stream<List<PersonaDelEspacio>> observarBajasDelEspacio(String espacioId) =>
      Stream<List<PersonaDelEspacio>>.error(StateError('no se pudo leer'));
}
