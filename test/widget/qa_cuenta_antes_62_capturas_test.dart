// QA de #62 (PR #729): capturas de cada estado con la fuente real (Inter + MaterialIcons), a
// `.dart_tool/qa_capturas/` (fuera del repo) con `--dart-define=QA_CAPTURAS=true`. Sin la bandera los
// casos igual corren: miran que con la fuente real no haya texto cortado ni desborde.
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_cuenta_antes_62_arnes.dart';

void main() {
  for (final (nombre, ancho, alto, escala) in tamanos) {
    group('capturas · $nombre', () {
      testWidgets('hoy_por_empezar', (tester) async {
        await cargarFuentesReales(tester);
        final m = Mundo(campanias: [porEmpezar()]);
        await montarHoy(tester, m, ancho: ancho, alto: alto, escala: escala);
        sinTextoFueraDeLosCostados(tester, ancho);
        await capturar(tester, 'hoy_por_empezar_$nombre');
      });

      testWidgets('hoy_por_empezar_tocar_iniciar', (tester) async {
        await cargarFuentesReales(tester);
        final m = Mundo(campanias: [porEmpezar()]);
        await montarHoy(tester, m, ancho: ancho, alto: alto, escala: escala);
        await tocarIniciar(tester);
        sinTextoFueraDeLosCostados(tester, ancho);
        await capturar(tester, 'hoy_tocar_iniciar_$nombre');
      });

      testWidgets('hoy_rechazadas', (tester) async {
        await cargarFuentesReales(tester);
        final m = Mundo(
          campanias: [porEmpezar(nombre: 'Campaña Verano 2026-27 (demo)', inicio: '2026-12-01')],
          rechazadas: [rechazada('j1', visitas: 12), rechazada('j2', visitas: 1)],
        );
        await montarHoy(tester, m, ancho: ancho, alto: alto, escala: escala);
        sinTextoFueraDeLosCostados(tester, ancho);
        await capturar(tester, 'hoy_rechazadas_$nombre');
      });

      testWidgets('hoy_en_curso_sin_aviso', (tester) async {
        await cargarFuentesReales(tester);
        final m = Mundo(
          campanias: [
            const CampaniaInscripta(
              campaniaId: 'c',
              nombre: 'Primavera 2026',
              fechaInicio: '2026-09-01',
            ),
          ],
        );
        await montarHoy(tester, m, ancho: ancho, alto: alto, escala: escala);
        await capturar(tester, 'hoy_en_curso_$nombre');
      });

      testWidgets('inicio_por_empezar', (tester) async {
        await cargarFuentesReales(tester);
        final m = Mundo(campanias: [porEmpezar()]);
        await montarInicio(tester, m, ancho: ancho, alto: alto, escala: escala);
        sinTextoFueraDeLosCostados(tester, ancho);
        await capturar(tester, 'inicio_por_empezar_$nombre');
        await tocarIniciar(tester);
        await capturar(tester, 'inicio_tocar_iniciar_$nombre');
      });

      testWidgets('asignada_con_zona', (tester) async {
        await cargarFuentesReales(tester);
        final m = Mundo()
          ..asignacion.asignacion = asignacionDe(
            'Campaña Verano 2026-27 (demo)',
            zona: 'Centro',
            ciudad: 'Montevideo',
          );
        await montarAsignada(tester, m, ancho: ancho, alto: alto, escala: escala);
        sinTextoFueraDeLosCostados(tester, ancho);
        await capturar(tester, 'asignada_zona_$nombre');
      });

      testWidgets('asignada_sin_zona', (tester) async {
        await cargarFuentesReales(tester);
        final m = Mundo()..asignacion.asignacion = asignacionDe('Verano 2027');
        await montarAsignada(tester, m, ancho: ancho, alto: alto, escala: escala);
        await capturar(tester, 'asignada_sin_zona_$nombre');
      });
    });
  }
}
