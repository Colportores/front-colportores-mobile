// QA de «Edificio y sus deptos» (vista 39, #452, PR #705): las guías de accesibilidad de Flutter (zona de
// toque de Android y de iOS, nombre en todo lo tocable) en cada estado, en 360×640 y 412×915 con texto
// 1,0× y 2,0×. El contraste va en `qa_vista39_deptos_452_contraste_test.dart` (con la letra de prueba).
import 'package:colportores_mobile/features/mapa/presentation/widgets/deptos_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart'
    show AlturaHoja;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_452_arnes.dart';

const _tamanos = [(chico452, '360x640'), (grande452, '412x915')];
const _escalas = [1.0, 2.0];

/// Los hallazgos del QA corren con `--dart-define=QA_HALLAZGOS=true`; sin eso quedan con `skip`.
const _conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  // skip: QA #705 — la «‹» de C·10 mide 40×48 dp (`SizedBox(width: 40)` en `_Cabecera`), menos que los
  // 48×48 dp de la zona de toque; la guía de Flutter no lo detecta por el nodo de semántica.
  testWidgets('QA #705: la «‹» de C·10 mide 48×48 dp o más', (tester) async {
    final semantica = tester.ensureSemantics();
    await llegarA452(tester, Estado452.c10);
    final tamano = tester.getSize(find.byKey(ClavesDeptosDeLaCasa.volver));
    expect(tamano.width, greaterThanOrEqualTo(48), reason: 'ancho: ${tamano.width}');
    expect(tamano.height, greaterThanOrEqualTo(48));
    semantica.dispose();
  }, skip: !_conHallazgos);

  // skip: QA #705 — con el error de lectura a un tercio, «Reintentar» queda a medias (1,0×) o fuera de
  // vista (2,0×); se llega desplazando la hoja.
  testWidgets(
    'QA #705: a un tercio, con el error de lectura de los deptos, «Reintentar» queda a la vista',
    (tester) async {
      for (final escala in [1.0, 2.0]) {
        await llegarA452(tester, Estado452.c09Error, escala: escala, altura: AlturaHoja.tercio);
        final boton = tester.getRect(find.byKey(ClavesDeptosDeLaCasa.reintentar));
        expect(boton.bottom, lessThanOrEqualTo(640), reason: 'escala $escala: $boton');
      }
    },
    skip: !_conHallazgos,
  );

  for (final estado in Estado452.values) {
    for (final (tamano, nombreTamano) in _tamanos) {
      for (final escala in _escalas) {
        testWidgets('guías · ${estado.id} · $nombreTamano · ${escala}x', (tester) async {
          final semantica = tester.ensureSemantics();
          await llegarA452(tester, estado, tamano: tamano, escala: escala);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantica.dispose();
        });
      }
    }
  }
}
