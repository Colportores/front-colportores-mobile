// Ayudas del QA de «Transferencia de materiales» (HU-STK-005, vista 40, #512): fuentes reales para ver y
// medir el texto, capturas PNG (solo con `--dart-define=QA_CAPTURAS=true`, fuera del repo) y los 20
// estados del canvas (40A·01 a 40A·09 y 40B·01 a 40B·11) para recorrerlos en cada tamaño.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/companiero_de_campania.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/transferencia.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'transferencias_arnes.dart';
import 'transferencias_en_memoria.dart';

const conCapturas512 = bool.fromEnvironment('QA_CAPTURAS');

/// Los hallazgos de QA que siguen sin arreglar corren solo con `--dart-define=QA_HALLAZGOS=true`.
const conHallazgos512 = bool.fromEnvironment('QA_HALLAZGOS');

bool _fuentesCargadas = false;

/// Carga las fuentes de `assets/fonts/`: sin ellas `flutter_test` pinta cajas de ancho fijo.
Future<void> cargarFuentes512(WidgetTester tester) async {
  if (_fuentesCargadas) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'];
    final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (raiz != null && iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
  });
  _fuentesCargadas = true;
}

/// La pantalla entera como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar512(WidgetTester tester, String nombre) async {
  if (!conCapturas512) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/512_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado512(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Ninguna palabra se parte en dos renglones: cada palabra, sola, cabe en el ancho que tiene su texto.
/// Devuelve las palabras partidas.
List<String> palabrasPartidas512(WidgetTester tester) {
  final partidas = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    final span = p.text;
    final plano = span.toPlainText();
    if (plano.trim().isEmpty) continue;
    final estilo = (span is TextSpan ? span.style : null) ?? const TextStyle();
    for (final palabra in plano.split(RegExp(r'\s+')).where((w) => w.length > 3)) {
      final medida = TextPainter(
        text: TextSpan(text: palabra, style: estilo),
        textDirection: TextDirection.ltr,
        textScaler: p.textScaler,
      )..layout();
      if (medida.width > p.size.width + 0.5) partidas.add(palabra);
    }
  }
  return partidas;
}

const chico512 = Size(360, 640);
const grande512 = Size(412, 915);

String _t(Size t) => '${t.width.toInt()}x${t.height.toInt()}';

String rotuloDeTamano512(Size t) => _t(t);

/// Las cinco filas de 40B·01 (las mismas del canvas).
TransferenciasEnMemoria repoDelCanvas512() => TransferenciasEnMemoria()
  ..sembrar(transferenciaDeEjemplo(id: 't-1', creada: DateTime.utc(2026, 10, 23, 17, 35)))
  ..sembrar(
    transferenciaDeEjemplo(
      id: 't-2',
      origen: 'juan',
      destino: 'bruno',
      solicitante: 'bruno',
      creada: DateTime.utc(2026, 10, 22, 15),
      lineas: const [LineaDeTransferencia(id: 'l-2', productoId: 'p-3', cantidad: 10)],
    ),
  )
  ..sembrar(
    transferenciaDeEjemplo(
      id: 't-3',
      estado: EstadoDeTransferencia.autorizada,
      creada: DateTime.utc(2026, 10, 15, 12),
      lineas: const [LineaDeTransferencia(id: 'l-3', productoId: 'p-2', cantidad: 1)],
    ),
  )
  ..sembrar(
    transferenciaDeEjemplo(
      id: 't-4',
      origen: 'bruno',
      estado: EstadoDeTransferencia.rechazada,
      creada: DateTime.utc(2026, 10, 9, 12),
      lineas: const [LineaDeTransferencia(id: 'l-4', productoId: 'p-1', cantidad: 4)],
      motivoRechazo: 'Ana los necesita esta semana',
    ),
  )
  ..sembrar(
    transferenciaDeEjemplo(
      id: 't-5',
      origen: 'juan',
      destino: 'vale',
      solicitante: 'vale',
      estado: EstadoDeTransferencia.cancelada,
      creada: DateTime.utc(2026, 10, 2, 12),
      lineas: const [LineaDeTransferencia(id: 'l-5', productoId: 'p-3', cantidad: 6)],
    ),
  );

/// Un estado del canvas y cómo llegar a él.
class Estado512 {
  const Estado512(this.id, this.rotulo, this.armar);

  final String id;
  final String rotulo;
  final Future<void> Function(WidgetTester tester, Size tamano, double escala) armar;

  @override
  String toString() => '$id $rotulo';
}

Future<void> _pedirListo(WidgetTester tester, ArnesTransferencias a) async {
  await sumar(tester, 'p-1', 2);
  await elegirColportor(tester, 'Ana Pereira');
}

DateTime _hoy() => DateTime.utc(2026, 10, 23, 17, 35);

TransferenciasEnMemoria _unaDecidida(EstadoDeTransferencia e, {String? motivo}) =>
    TransferenciasEnMemoria()..sembrar(
      transferenciaDeEjemplo(
        estado: e,
        creada: _hoy(),
        decididoEn: DateTime.utc(2026, 10, 23, 12, 12),
        motivoRechazo: motivo,
      ),
    );

final estados512 = <Estado512>[
  Estado512('40A·01', 'Qué pedís', (t, s, e) async {
    await montarTransferencias(t, tamano: s, escala: e, abrir: 'pedir');
  }),
  Estado512('40A·02', 'Elegir colportor', (t, s, e) async {
    await montarTransferencias(t, tamano: s, escala: e, abrir: 'pedir');
    await tocar(t, tarjetaDeColportor);
  }),
  Estado512('40A·03', 'Lista para enviar', (t, s, e) async {
    final a = await montarTransferencias(t, tamano: s, escala: e, abrir: 'pedir');
    await _pedirListo(t, a);
  }),
  Estado512('40A·04', 'Sin materiales', (t, s, e) async {
    await montarTransferencias(t, tamano: s, escala: e, abrir: 'pedir');
    await elegirColportor(t, 'Ana Pereira');
  }),
  Estado512('40A·05', 'Enviando', (t, s, e) async {
    final repo = TransferenciasEnMemoria()..compuerta = Completer<void>();
    final a = await montarTransferencias(t, repo: repo, tamano: s, escala: e, abrir: 'pedir');
    await _pedirListo(t, a);
    await tocar(t, botonPrincipal);
    addTearDown(() {
      if (!repo.compuerta!.isCompleted) repo.compuerta!.complete();
    });
  }),
  Estado512('40A·06', 'Enviada', (t, s, e) async {
    final a = await montarTransferencias(t, tamano: s, escala: e, abrir: 'pedir');
    await _pedirListo(t, a);
    await tocar(t, botonPrincipal);
  }),
  Estado512('40A·07', 'Sin conexión', (t, s, e) async {
    final a = await montarTransferencias(
      t,
      tamano: s,
      escala: e,
      sinConexion: true,
      abrir: 'pedir',
    );
    await _pedirListo(t, a);
  }),
  Estado512('40A·08', 'Error al enviar', (t, s, e) async {
    final repo = TransferenciasEnMemoria()..fallas.add(const FailureTransferenciaNoGuardada());
    final a = await montarTransferencias(t, repo: repo, tamano: s, escala: e, abrir: 'pedir');
    await _pedirListo(t, a);
    await tocar(t, botonPrincipal);
  }),
  Estado512('40A·09', 'Sin compañeros', (t, s, e) async {
    await montarTransferencias(
      t,
      tamano: s,
      escala: e,
      companieros: CompanierosFalsos(
        resultado: const CompanierosDeCampania(campania: 'Primavera 2026', companieros: []),
      ),
      conHacerUnPedido: true,
      abrir: 'pedir',
    );
  }),
  Estado512('40B·01', 'Lista', (t, s, e) async {
    await montarTransferencias(t, repo: repoDelCanvas512(), tamano: s, escala: e, abrir: 'lista');
  }),
  Estado512('40B·02', 'Detalle por autorizar', (t, s, e) async {
    await montarTransferencias(t, repo: repoDelCanvas512(), tamano: s, escala: e, abrir: 'detalle');
  }),
  Estado512('40B·03', 'Cancelar', (t, s, e) async {
    await montarTransferencias(t, repo: repoDelCanvas512(), tamano: s, escala: e, abrir: 'detalle');
    await tocar(t, botonCancelar);
  }),
  Estado512('40B·04', 'Cancelada', (t, s, e) async {
    await montarTransferencias(t, repo: repoDelCanvas512(), tamano: s, escala: e, abrir: 'lista');
    await tocar(t, find.byKey(const Key('transferencia_t-1')));
    await tocar(t, botonCancelar);
    await tocar(t, cancelarSi);
  }),
  Estado512('40B·05', 'Autorizada', (t, s, e) async {
    await montarTransferencias(
      t,
      repo: _unaDecidida(EstadoDeTransferencia.autorizada),
      tamano: s,
      escala: e,
      abrir: 'detalle',
    );
  }),
  Estado512('40B·06', 'Rechazada', (t, s, e) async {
    await montarTransferencias(
      t,
      repo: _unaDecidida(EstadoDeTransferencia.rechazada, motivo: 'Ana los necesita esta semana'),
      tamano: s,
      escala: e,
      abrir: 'detalle',
    );
  }),
  Estado512('40B·07', 'Me piden a mí', (t, s, e) async {
    final repo = TransferenciasEnMemoria()
      ..sembrar(
        transferenciaDeEjemplo(origen: 'juan', destino: 'ana', solicitante: 'ana', creada: _hoy()),
      );
    await montarTransferencias(t, repo: repo, tamano: s, escala: e, abrir: 'detalle');
  }),
  Estado512('40B·08', 'Vacío', (t, s, e) async {
    await montarTransferencias(t, tamano: s, escala: e, abrir: 'lista');
  }),
  Estado512('40B·09', 'Cargando', (t, s, e) async {
    final repo = TransferenciasEnMemoria()..compuertaDeLectura = Completer<void>();
    await montarTransferencias(t, repo: repo, tamano: s, escala: e, abrir: 'lista');
    addTearDown(() {
      if (!repo.compuertaDeLectura!.isCompleted) repo.compuertaDeLectura!.complete();
    });
  }),
  Estado512('40B·10', 'Error', (t, s, e) async {
    final repo = TransferenciasEnMemoria()
      ..errorDeLectura = const FailureTransferenciasNoDisponibles();
    await montarTransferencias(t, repo: repo, tamano: s, escala: e, abrir: 'lista');
  }),
  Estado512('40B·11', 'Sin conexión', (t, s, e) async {
    await montarTransferencias(
      t,
      repo: repoDelCanvas512(),
      tamano: s,
      escala: e,
      sinConexion: true,
      ultimaBajada: DateTime.utc(2026, 10, 23),
      abrir: 'lista',
    );
  }),
];
