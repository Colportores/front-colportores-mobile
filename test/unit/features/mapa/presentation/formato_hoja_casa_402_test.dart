// Cómo se escribe lo que debe una persona y la cuota que toca en la hoja de la casa (vista 39, C·01 y
// C·02, #402): «Debe $ 1.200 · cuota sáb 26/10».
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_lista_ubicaciones.dart';
import 'package:test/test.dart';

import '../../../../helpers/persona_falsos.dart';

void main() {
  // Un viernes: 23/10/2026, a media tarde.
  final hoy = DateTime(2026, 10, 23, 14, 20);

  group('«Debe \$ 1.200 · cuota sáb 26/10» (canvas C·01)', () {
    test('la cuota que viene va con el día de la semana y la fecha', () {
      final texto = TextosHojaCasa.debeConCuota(120000, DateTime(2026, 10, 24), hoy);

      expect(texto, 'Debe \$ 1.200 · cuota sáb 24/10');
    });

    test('cada día de la semana tiene su abreviatura', () {
      final dias = [
        for (var i = 0; i < 7; i++)
          FormatoListaUbicaciones.diaSemanaYMes(DateTime(2026, 10, 26 + i)),
      ];

      expect(dias, [
        'lun 26/10',
        'mar 27/10',
        'mié 28/10',
        'jue 29/10',
        'vie 30/10',
        'sáb 31/10',
        'dom 01/11',
      ]);
    });

    test('la cuota de hoy todavía no venció: lleva su día como cualquier otra', () {
      final texto = TextosHojaCasa.debeConCuota(120000, DateTime(2026, 10, 23, 8), hoy);

      expect(TextosHojaCasa.cuotaVencida(DateTime(2026, 10, 23, 8), hoy), isFalse);
      expect(texto, 'Debe \$ 1.200 · cuota vie 23/10');
    });

    test('una cuota de un día que ya pasó está vencida y lo dice con su fecha', () {
      final ayer = DateTime(2026, 10, 22, 23, 59);

      expect(TextosHojaCasa.cuotaVencida(ayer, hoy), isTrue);
      expect(
        TextosHojaCasa.debeConCuota(120000, ayer, hoy),
        'Debe \$ 1.200 · cuota vencida el 22/10',
      );
    });

    test('con centavos y con miles escribe el monto como el resto de la hoja', () {
      expect(
        TextosHojaCasa.debeConCuota(1234567, DateTime(2026, 11, 2), hoy),
        'Debe \$ 12.345,67 · cuota lun 02/11',
      );
    });

    test('sin cuota la línea sigue siendo «Debe \$ 1.200»', () {
      expect(TextosHojaCasa.debe(120000), 'Debe \$ 1.200');
    });
  });

  group('ContextoDeLaCasa.cuotaQueTocaDe', () {
    final pedro = clienteDePersonas('p-1', 'Pedro', apellido: 'Gómez');
    final sabado = DateTime(2026, 10, 26);

    test('solo la tiene quien debe algo', () {
      final contexto = ContextoDeLaCasa(
        personas: [pedro],
        saldosCentavos: const {'p-1': 120000, 'p-2': 0},
        proximaCuotaDe: {'p-1': sabado, 'p-2': sabado, 'p-3': sabado},
      );

      expect(contexto.cuotaQueTocaDe('p-1'), sabado);
      expect(contexto.cuotaQueTocaDe('p-2'), isNull, reason: 'saldo 0');
      expect(contexto.cuotaQueTocaDe('p-3'), isNull, reason: 'sin saldo conocido');
      expect(contexto.cuotaQueTocaDe('p-4'), isNull);
    });

    test('la cuota entra en la comparación: otra cuota es otro contexto', () {
      final base = ContextoDeLaCasa(
        saldosCentavos: const {'p-1': 100},
        proximaCuotaDe: {'p-1': sabado},
      );
      final otra = ContextoDeLaCasa(
        saldosCentavos: const {'p-1': 100},
        proximaCuotaDe: {'p-1': DateTime(2026, 11, 2)},
      );

      expect(base, isNot(otra));
      expect(
        base,
        ContextoDeLaCasa(saldosCentavos: const {'p-1': 100}, proximaCuotaDe: {'p-1': sabado}),
      );
    });
  });
}
