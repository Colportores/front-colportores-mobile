// QA de la vista 11 «Espacios» (HU-UBI-007, #211, PR #468): las guías de accesibilidad de Flutter
// (tamaño de toque de Android e iOS, etiqueta en lo tocable y contraste del texto) en cada estado y a
// 360×640 y 412×915. Archivo aparte con la letra de prueba (Ahem): con las fuentes reales el
// `textContrastGuideline` da falsos negativos.
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';
import '../../helpers/qa_vista11_211_arnes.dart';
import 'mapa_ubicaciones_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales211 = false);

  for (final tamano in [telefonoChico211, telefonoGrande211]) {
    for (final estado in EstadoV11.values) {
      final donde = '${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()}';

      testWidgets('tamaño de toque de Android (48 dp) en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, estado, tamano: tamano);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        h.dispose();
      });

      testWidgets('tamaño de toque de iOS (44 dp) en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, estado, tamano: tamano);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        h.dispose();
      });

      testWidgets('toda acción tocable tiene nombre en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, estado, tamano: tamano);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        h.dispose();
      });

      testWidgets('contraste del texto (AA) en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, estado, tamano: tamano);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        h.dispose();
      });

      testWidgets('tamaño de toque con el texto al 200 % en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, estado, tamano: tamano, escala: 2);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        h.dispose();
      });
    }
  }

  // El botón «Detalle» de la vista previa del mapa (06C·04) y la hoja que abre, en el mapa real.
  for (final tamano in [telefonoChico211, telefonoGrande211]) {
    for (final escala in [1.0, 2.0]) {
      testWidgets('«Detalle» de la vista previa y la hoja que abre cumplen las guías a '
          '${tamano.width.toInt()}×${tamano.height.toInt()} con texto ×$escala', (tester) async {
        final h = tester.ensureSemantics();
        final m = await montarMapaUbicaciones(
          tester,
          repo: RepoListaFalso([
            filaLista('a', calle: 'Av. Italia', numero: '1234', metrosAlNorte: 40, espacios: 2),
          ]),
          tamano: tamano,
          escala: escala,
          otrosOverrides: [
            ubicacionDeLaHojaProvider.overrideWith(
              (ref, id) => ubicacionGuardada(
                id: id,
                tipo: TipoUbicacion.edificio,
                calle: 'Av. Italia',
                numero: '1234',
              ),
            ),
            espaciosDeUbicacionProvider.overrideWith(
              (ref, id) => [espacioDe('e-1', '101', piso: '1', ubicacionId: id)],
            ),
          ],
        );
        m.mapa.tocarPunto('a');
        await asentarLista(tester);

        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.ensureVisible(find.byKey(ClavesMapaUbicaciones.detalle));
        await tester.tap(find.byKey(ClavesMapaUbicaciones.detalle));
        await asentarLista(tester);
        expect(find.byKey(ClavesHojaUbicacion.hoja), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        h.dispose();
      });
    }
  }
}
