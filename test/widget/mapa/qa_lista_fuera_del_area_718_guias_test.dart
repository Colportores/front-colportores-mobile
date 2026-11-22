// QA de #718, guías de accesibilidad de la pestaña «Lista» con casas «fuera del área» (vista 05):
// tamaño de toque, etiqueta de lo tocable y contraste del texto, en los dos teléfonos con el texto a
// 1,0 y a 2,0. Archivo aparte y sin fuentes reales: con la letra real `textContrastGuideline` da
// falsos negativos (ver «Gotchas» del QA de #335).
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/qa_mapa_fuera_del_area_715_arnes.dart';
import 'lista_ubicaciones_arnes.dart';

void main() {
  final casas = [
    filaLista('u1', calle: 'Av. General Fructuoso Rivera', numero: '1234 bis', metrosAlNorte: 10),
    filaLista('u2', numero: '102', metrosAlNorte: 20),
    filaLista('u3', tipo: TipoUbicacion.edificio, numero: '103', metrosAlNorte: 30, espacios: 24),
  ];
  const marcadas = {
    'una marcada': {'u2'},
    'todas marcadas': {'u1', 'u2', 'u3'},
  };

  for (final MapEntry(key: nombreTamano, value: tamano) in tamanos715.entries) {
    for (final escala in [1.0, 2.0]) {
      for (final MapEntry(key: nombre, value: ids) in marcadas.entries) {
        testWidgets(
          'Lista · $nombre · $nombreTamano · texto $escala: tamaños de toque, etiquetas y '
          'contraste',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await montarLista(
              tester,
              repo: RepoListaFalso(casas),
              tamano: tamano,
              escala: escala,
              masOverrides: [FueraDelAreaFalsas715(ids).sobrescribe],
            );

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          },
        );
      }
    }
  }
}
