// Accesibilidad de los avisos del mapa (#190): tamaño de toque, nombres, anuncio al aparecer y
// contraste, en cada artboard (06C·05, 06C·06, 06C·07) y en «No pudimos cargar el mapa».
//
// Con la fuente de prueba (Ahem) el contraste se mide bien; las medidas finas con las fuentes reales
// están en `aviso_mapa_test.dart`.
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/mapa_descargas_arnes.dart';

/// Cada aviso con lo que hace falta para que aparezca, y el finder de su tarjeta.
final _avisos = <String, ({TipoConexion conexion, bool catalogo, bool minimizar, Key clave})>{
  '06C·05 sin conexión': (
    conexion: TipoConexion.sinConexion,
    catalogo: true,
    minimizar: false,
    clave: ClavesAvisoMapa.sinConexion,
  ),
  '06C·06 aviso minimizado': (
    conexion: TipoConexion.sinConexion,
    catalogo: true,
    minimizar: true,
    clave: ClavesAvisoMapa.pildora,
  ),
  '06C·07 con datos móviles': (
    conexion: TipoConexion.datosMoviles,
    catalogo: true,
    minimizar: false,
    clave: ClavesAvisoMapa.datosMoviles,
  ),
  'no pudimos cargar el mapa': (
    conexion: TipoConexion.wifi,
    catalogo: false,
    minimizar: false,
    clave: ClavesAvisoMapa.noCarga,
  ),
};

Future<void> _montarAviso(
  WidgetTester tester,
  ({TipoConexion conexion, bool catalogo, bool minimizar, Key clave}) aviso, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  await montarAviso(
    tester,
    conexion: aviso.conexion,
    // «No pudimos cargar» es un catálogo que no trae la ciudad.
    catalogo: aviso.catalogo ? [paqueteMontevideo] : [paqueteCanelones],
    tamano: tamano,
    escala: escala,
  );
  if (aviso.minimizar) {
    await tester.tap(find.byTooltip('Minimizar aviso'));
    await asentarAviso(tester);
  }
  expect(find.byKey(aviso.clave), findsOneWidget);
}

void main() {
  for (final MapEntry(key: nombre, value: aviso) in _avisos.entries) {
    group(nombre, () {
      for (final (tamano, escala) in [(const Size(390, 844), 1.0), (const Size(360, 640), 2.0)]) {
        testWidgets(
          'toques de 48, nombres y contraste a ${tamano.width.toInt()}×${tamano.height.toInt()} con texto ${escala}x',
          (tester) async {
            final semantica = tester.ensureSemantics();
            try {
              await _montarAviso(tester, aviso, tamano: tamano, escala: escala);

              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
              await expectLater(tester, meetsGuideline(textContrastGuideline));
            } finally {
              semantica.dispose();
            }
          },
        );
      }

      testWidgets('se anuncia al aparecer (liveRegion)', (tester) async {
        final semantica = tester.ensureSemantics();
        try {
          await _montarAviso(tester, aviso);

          expect(tester.getSemantics(find.byKey(aviso.clave)), isSemantics(isLiveRegion: true));
        } finally {
          semantica.dispose();
        }
      });
    });
  }

  group('nombres', () {
    testWidgets('la ✕ se llama «Minimizar aviso» y la insignia «!» no se lee', (tester) async {
      final semantica = tester.ensureSemantics();
      try {
        await _montarAviso(tester, _avisos['06C·05 sin conexión']!);

        expect(find.bySemanticsLabel('Minimizar aviso'), findsOneWidget);
        expect(find.bySemanticsLabel('!'), findsNothing);
        expect(find.bySemanticsLabel('✕'), findsNothing);
        expect(find.bySemanticsLabel('Descargar mapa'), findsOneWidget);
        expect(find.bySemanticsLabel('Activar datos'), findsOneWidget);
      } finally {
        semantica.dispose();
      }
    });

    testWidgets('la píldora es un solo botón con el texto del canvas', (tester) async {
      final semantica = tester.ensureSemantics();
      try {
        await _montarAviso(tester, _avisos['06C·06 aviso minimizado']!);

        expect(find.bySemanticsLabel('Sin conexión · Descargar mapa'), findsOneWidget);
        expect(
          tester.getSemantics(find.byKey(ClavesAvisoMapa.pildora)),
          isSemantics(isButton: true, hasTapAction: true, isEnabled: true),
        );
      } finally {
        semantica.dispose();
      }
    });

    testWidgets('el aviso de datos móviles no tiene ✕: solo «Descargar mapa · N MB» y «Ahora no»', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      try {
        await _montarAviso(tester, _avisos['06C·07 con datos móviles']!);

        expect(find.bySemanticsLabel('Minimizar aviso'), findsNothing);
        expect(find.bySemanticsLabel('Descargar mapa · 1 MB'), findsOneWidget);
        expect(find.bySemanticsLabel('Ahora no'), findsOneWidget);
      } finally {
        semantica.dispose();
      }
    });
  });
}
