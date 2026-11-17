// Arnés del QA de #715 (el mapa marca las casas «fuera del área» y deja verlas u ocultarlas, #713;
// HU-SYNC-011, R-UB12): las escenas del mapa con esas casas, listas para medirlas a 360x640 y 412x915
// con el texto a 1,0 y a 2,0, la carga de las fuentes reales y la captura de cada una (solo con
// `--dart-define=QA_CAPTURAS=true`, en `.dart_tool/qa_capturas`, fuera del repo).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/fuera_del_area_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_fuera_del_area.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/mapa_ubicaciones_arnes.dart';
import 'lista_ubicaciones_falsos.dart';

export '../widget/mapa/mapa_ubicaciones_arnes.dart';

const capturas715 = bool.fromEnvironment('QA_CAPTURAS');

/// Los hallazgos de la QA, con `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
const verHallazgos715 = bool.fromEnvironment('QA_HALLAZGOS');

const tamanos715 = <String, Size>{'360x640': Size(360, 640), '412x915': Size(412, 915)};

/// Lo que el motor marcó fuera del área, como lo da `DriftLocalStore.observarFueraDelArea`: emite lo
/// que hay al suscribirse y cada cambio (un pull).
final class FueraDelAreaFalsas715 {
  FueraDelAreaFalsas715([this._actual = const {}]);

  Set<String> _actual;
  final _cambios = StreamController<Set<String>>.broadcast();

  void emitir(Set<String> ids) {
    _actual = ids;
    _cambios.add(ids);
  }

  Stream<Set<String>> _leer() async* {
    yield _actual;
    yield* _cambios.stream;
  }

  Override get sobrescribe => idsFueraDelAreaProvider.overrideWith((ref) => _leer());
}

/// u1 y u3 fuera del área; u2 y u4 en el área; u5 es una baja que también quedó marcada.
List<UbicacionConResumen> casas715({bool conBaja = false}) => [
  filaLista('u1', calle: 'Av. Italia', numero: '101', metrosAlNorte: 300),
  filaLista('u2', calle: 'Av. Italia', numero: '102', metrosAlNorte: 320),
  filaLista('u3', calle: 'Av. Italia', numero: '103', metrosAlNorte: 340),
  filaLista('u4', calle: 'Av. Italia', numero: '104', metrosAlNorte: 360),
  if (conBaja)
    filaLista(
      'u5',
      calle: 'Av. Italia',
      numero: '105',
      metrosAlNorte: 380,
      baja: DateTime.utc(2026, 10, 1),
      motivoBaja: 'Ya no vive nadie',
    ),
];

final avisoMapa715 = find.byKey(ClavesFueraDelArea.avisoMapa);
final avisoHoja715 = find.byKey(ClavesFueraDelArea.avisoHoja);
final interruptor715 = find.byKey(ClavesFueraDelArea.interruptor);

Set<String> dibujadas715(FabricaMapaFalsa mapa) => {
  for (final p in mapa.config!.puntos)
    if (p.id != 'gps') p.id,
};

Set<String> conAro715(FabricaMapaFalsa mapa) => {
  for (final p in mapa.config!.puntos)
    if (p.fueraDelArea) p.id,
};

Future<MontajeMapaUbicaciones> montar715(
  WidgetTester tester,
  FueraDelAreaFalsas715 fuera, {
  List<UbicacionConResumen>? casas,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) => montarMapaUbicaciones(
  tester,
  repo: RepoListaFalso(casas ?? casas715()),
  otrosOverrides: [fuera.sobrescribe],
  escala: escala,
  tamano: tamano,
);

Future<void> abrirReferencias715(WidgetTester tester) async {
  await tester.tap(chipReferencias);
  await asentarLista(tester, 12);
}

Future<void> cerrarReferencias715(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(ClavesMapaUbicaciones.cerrarReferencias));
  await asentarLista(tester, 4);
  await tester.tap(find.byKey(ClavesMapaUbicaciones.cerrarReferencias));
  await asentarLista(tester, 12);
}

/// Oculta las casas fuera del área desde «Referencias», como lo hace la colportora.
Future<void> ocultar715(WidgetTester tester) async {
  await abrirReferencias715(tester);
  await tester.ensureVisible(interruptor715);
  await tester.tap(interruptor715);
  await asentarLista(tester, 4);
  await cerrarReferencias715(tester);
}

/// Carga Inter, SourceSerif4 y JetBrainsMono de `assets/fonts/` y los íconos de Material.
Future<void> cargarFuentes715(WidgetTester tester) async {
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

/// Una captura PNG de la pantalla entera en `.dart_tool/qa_capturas/715_<nombre>.png`.
Future<void> capturar715(WidgetTester tester, String nombre) async {
  if (!capturas715) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File(
      '${dir.path}/715_${nombre.replaceAll(RegExp(r'[^A-Za-z0-9.-]+'), '_')}.png',
    ).writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

typedef Escena715 =
    Future<MontajeMapaUbicaciones> Function(WidgetTester tester, Size tamano, double escala);

/// Cada estado de lo nuevo, armado como lo vería la colportora.
final escenas715 = <String, Escena715>{
  'A marcas · Cercanía a un tercio': (t, tam, e) async {
    final m = await montar715(t, FueraDelAreaFalsas715({'u1', 'u3'}), escala: e, tamano: tam);
    await tocarAsa(t);
    return m;
  },
  'B marcas · Cercanía a la mitad con una baja fuera del área': (t, tam, e) async {
    final m = await montar715(
      t,
      FueraDelAreaFalsas715({'u1', 'u3', 'u5'}),
      casas: casas715(conBaja: true),
      escala: e,
      tamano: tam,
    );
    await tocarAsa(t, 2);
    return m;
  },
  'C hoja de la casa fuera del área': (t, tam, e) async {
    final m = await montar715(t, FueraDelAreaFalsas715({'u1', 'u3'}), escala: e, tamano: tam);
    m.mapa.tocarPunto('u1');
    await asentarLista(t);
    return m;
  },
  'D Referencias con casas fuera del área': (t, tam, e) async {
    final m = await montar715(t, FueraDelAreaFalsas715({'u1', 'u3'}), escala: e, tamano: tam);
    await abrirReferencias715(t);
    return m;
  },
  'E Referencias con el interruptor apagado': (t, tam, e) async {
    final m = await montar715(t, FueraDelAreaFalsas715({'u1', 'u3'}), escala: e, tamano: tam);
    await ocultar715(t);
    await abrirReferencias715(t);
    return m;
  },
  'F ocultas · mapa con el aviso': (t, tam, e) async {
    final m = await montar715(t, FueraDelAreaFalsas715({'u1', 'u3'}), escala: e, tamano: tam);
    await ocultar715(t);
    return m;
  },
  'G ocultas · Cercanía con el aviso': (t, tam, e) async {
    final m = await montar715(t, FueraDelAreaFalsas715({'u1', 'u3'}), escala: e, tamano: tam);
    await ocultar715(t);
    await tocarAsa(t);
    return m;
  },
  'H todas ocultas · Cercanía': (t, tam, e) async {
    final m = await montar715(
      t,
      FueraDelAreaFalsas715({'u1', 'u2', 'u3', 'u4'}),
      escala: e,
      tamano: tam,
    );
    await ocultar715(t);
    await tocarAsa(t, 2);
    return m;
  },
  'I control · sin casas fuera del área · Referencias': (t, tam, e) async {
    final m = await montar715(t, FueraDelAreaFalsas715(), escala: e, tamano: tam);
    await abrirReferencias715(t);
    return m;
  },
};
