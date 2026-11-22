// QA de #649: capturas PNG de los estados nuevos (hoja a un tercio tras «ir a la casa» y mapa libre
// tras guardar) en `.dart_tool/qa_capturas/` (fuera del repo). Solo corren con
// `--dart-define=QA_CAPTURAS=true`; sin eso no hacen nada.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import 'lista_ubicaciones_arnes.dart' show asentarLista;
import 'navegacion_inicio_649_arnes.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

Future<void> _fuentes(WidgetTester tester) async {
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

Future<void> _capturar(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & tester.view.physicalSize);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/649_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  const tamanos = <(String, Size)>[('360x640', Size(360, 640)), ('412x915', Size(412, 915))];
  for (final (nombre, tamano) in tamanos) {
    for (final escala in [1.0, 2.0]) {
      testWidgets('capturas $nombre x$escala', (tester) async {
        await _fuentes(tester);
        final m = await montar649(
          tester,
          filas: [filaLista('a', calle: 'Avenida Doctor Alejandro Gallinal', numero: '1234')],
          tamano: tamano,
          escala: escala,
        );
        await m.irA('lista');
        await _capturar(tester, '1_lista_${nombre}_x$escala');

        m.notificador.irALaCasa('a');
        await m.asentar();
        await _capturar(tester, '2_ir_a_la_casa_${nombre}_x$escala');

        final registrar = find.byKey(ClavesHojaCasa.registrarVisita);
        await tester.ensureVisible(registrar);
        await tester.tap(registrar);
        await asentarLista(tester);
        await _capturar(tester, '3_tras_guardar_${nombre}_x$escala');
      }, skip: !_conCapturas);
    }
  }
}
