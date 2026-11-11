// Arnés del QA de #704 (vista 06, 06C·03 «Hoja a 1/2 · Agendados»): las escenas de la hoja del mapa
// con «Agendados» (y las pestañas vecinas), listas para medirlas en los tamaños y escalas del QA, la
// carga de las fuentes reales y la captura de cada una (solo con `--dart-define=QA_CAPTURAS=true`).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_agendados.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'lista_ubicaciones_arnes.dart' show asentarLista;
import 'mapa_agendados_407_arnes.dart';
import 'mapa_ubicaciones_arnes.dart' show hoja, tocarAsa;

export 'lista_ubicaciones_arnes.dart' show asentarLista;
export 'mapa_agendados_407_arnes.dart';
export 'mapa_ubicaciones_arnes.dart' show hoja, tocarAsa;

const capturas704 = bool.fromEnvironment('QA_CAPTURAS');

const tamanos704 = <String, Size>{'360x640': Size(360, 640), '412x915': Size(412, 915)};

/// Carga Inter, SourceSerif4 y JetBrainsMono de `assets/fonts/` y los íconos de Material (sin las
/// fuentes reales `flutter_test` pinta cajas y el ancho de los textos es falso).
Future<void> cargarFuentes704(WidgetTester tester) async {
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

/// Una captura PNG de la pantalla entera en `.dart_tool/qa_capturas/704_<nombre>.png`.
Future<void> capturar704(WidgetTester tester, String nombre) async {
  if (!capturas704) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File(
      '${dir.path}/704_${nombre.replaceAll(RegExp(r'[^A-Za-z0-9.-]+'), '_')}.png',
    ).writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

typedef Escena704 =
    Future<MontajeAgendados> Function(WidgetTester tester, Size tamano, double escala);

/// Cada estado de la hoja con «Agendados», armado como lo vería la colportora (el teléfono real:
/// 360x640 o 412x915, no la pantalla alta de los tests del implementador).
final escenas704 = <String, Escena704>{
  '06C·01 minimizada': (t, tam, e) => montarAgendados(t, tamano: tam, escala: e),
  '06C·02 Cercania a un tercio': (t, tam, e) async {
    final m = await montarAgendados(t, tamano: tam, escala: e);
    await tocarAsa(t);
    return m;
  },
  '06C·03 Agendados a un tercio': (t, tam, e) async {
    final m = await montarAgendados(t, tamano: tam, escala: e);
    await abrirAgendados(t);
    return m;
  },
  '06C·03 Agendados a la mitad': (t, tam, e) async {
    final m = await montarAgendados(t, tamano: tam, escala: e);
    await abrirAgendados(t);
    await tocarAsa(t);
    return m;
  },
  'Agendados a la mitad con el chip Entrevistas': (t, tam, e) async {
    final m = await montarAgendados(t, tamano: tam, escala: e);
    await abrirAgendados(t);
    await tocarAsa(t);
    await t.tap(chip407(TipoAgenda.entrevista));
    await asentarLista(t);
    return m;
  },
  'Agendados vacia a un tercio': (t, tam, e) async {
    final m = await montarAgendados(t, tamano: tam, escala: e, items: [], conAgendar: true);
    await abrirAgendados(t);
    return m;
  },
  'Agendados filtro sin resultados a la mitad': (t, tam, e) async {
    final m = await montarAgendados(
      t,
      tamano: tam,
      escala: e,
      items: [agendado('e1', dia407(10), ubicacionId: 'u-italia')],
    );
    await abrirAgendados(t);
    await tocarAsa(t);
    await t.tap(chip407(TipoAgenda.entrega));
    await asentarLista(t);
    return m;
  },
  'Agendados error al leer a un tercio': (t, tam, e) async {
    final consulta = ConsultaAgendaFalsa(agendaDelCanvas())..error = Exception('db');
    final m = await montarAgendados(t, tamano: tam, escala: e, consulta: consulta);
    await abrirAgendados(t);
    return m;
  },
  'Agendados cargando a un tercio': (t, tam, e) async {
    final consulta = ConsultaAgendaFalsa(agendaDelCanvas())..congelada = true;
    final m = await montarAgendados(t, tamano: tam, escala: e, consulta: consulta);
    await abrirAgendados(t);
    return m;
  },
};

/// Las palabras de [texto] (un `Text` ya pintado) más anchas que el lugar donde se dibuja, y que por
/// eso se parten a mitad de palabra («Ital/ia»).
List<String> palabrasPartidas(WidgetTester tester, Finder texto) {
  final p = tester.renderObject<RenderParagraph>(texto);
  final span = p.text as TextSpan;
  final ancho = p.size.width;
  final partidas = <String>[];
  for (final palabra in span.toPlainText().split(RegExp(r'\s+'))) {
    if (palabra.isEmpty) continue;
    final medida = TextPainter(
      text: TextSpan(text: palabra, style: span.style),
      textScaler: p.textScaler,
      textDirection: TextDirection.ltr,
    )..layout();
    if (medida.width > ancho + 0.5) partidas.add(palabra);
  }
  return partidas;
}

/// Los `Text` dentro de [raiz] que parten una palabra, con las palabras: «Entrevista → Entrevista».
List<String> textosPartidos(WidgetTester tester, Finder raiz) {
  final partidos = <String>[];
  for (final e in find.descendant(of: raiz, matching: find.byType(Text)).evaluate()) {
    final palabras = palabrasPartidas(tester, find.byWidget(e.widget));
    if (palabras.isNotEmpty) partidos.add('«${(e.widget as Text).data}»: ${palabras.join(', ')}');
  }
  return partidos;
}

/// ¿Está [f] entero dentro de la hoja del mapa y de la pantalla (sin tener que desplazar nada)?
bool enLaHoja(WidgetTester tester, Finder f, Size pantalla) {
  final r = tester.getRect(f);
  final h = tester.getRect(hoja);
  return r.top >= h.top - 0.5 &&
      r.bottom <= h.bottom + 0.5 &&
      r.left >= -0.5 &&
      r.right <= pantalla.width + 0.5 &&
      r.bottom <= pantalla.height + 0.5;
}

final filasDeAgendados = find.byWidgetPredicate((w) => w is FilaAgendado);
