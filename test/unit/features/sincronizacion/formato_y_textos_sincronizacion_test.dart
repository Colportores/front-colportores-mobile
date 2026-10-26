// Cómo se dicen las fechas y los números de la vista 25.
import 'package:colportores_mobile/features/sincronizacion/domain/entities/estado_sincronizacion.dart';
import 'package:colportores_mobile/features/sincronizacion/presentation/formato_sincronizacion.dart';
import 'package:colportores_mobile/features/sincronizacion/presentation/textos_sincronizacion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ahora = DateTime(2026, 10, 26, 14, 35);

  group('FormatoSincronizacion.hace', () {
    test('should say "recién" under a minute and for a date in the future', () {
      expect(FormatoSincronizacion.hace(DateTime(2026, 10, 26, 14, 34, 30), ahora), 'recién');
      expect(FormatoSincronizacion.hace(DateTime(2026, 10, 26, 14, 40), ahora), 'recién');
    });

    test('should say the minutes under an hour', () {
      expect(FormatoSincronizacion.hace(DateTime(2026, 10, 26, 14, 32), ahora), 'hace 3 min');
      expect(FormatoSincronizacion.hace(DateTime(2026, 10, 26, 13, 36), ahora), 'hace 59 min');
    });

    test('should say the hours on the same day', () {
      expect(FormatoSincronizacion.hace(DateTime(2026, 10, 26, 9, 10), ahora), 'hace 5 h');
    });

    test('should say yesterday with the hour and then the date', () {
      expect(FormatoSincronizacion.hace(DateTime(2026, 10, 25, 21), ahora), 'ayer 21:00');
      expect(FormatoSincronizacion.hace(DateTime(2026, 10, 22, 14, 20), ahora), '22/10 14:20');
    });

    test('should say "ayer" when it was less than a day ago but before midnight', () {
      expect(
        FormatoSincronizacion.hace(DateTime(2026, 10, 25, 23, 50), DateTime(2026, 10, 26, 0, 20)),
        'hace 30 min',
      );
      expect(
        FormatoSincronizacion.hace(DateTime(2026, 10, 25, 20), DateTime(2026, 10, 26, 0, 20)),
        'ayer 20:00',
      );
    });
  });

  group('FormatoSincronizacion.reloj', () {
    test('should say today, yesterday or the date with the hour', () {
      expect(FormatoSincronizacion.reloj(DateTime(2026, 10, 26, 3, 10), ahora), 'hoy 03:10');
      expect(FormatoSincronizacion.reloj(DateTime(2026, 10, 25, 3, 10), ahora), 'ayer 03:10');
      expect(FormatoSincronizacion.reloj(DateTime(2026, 10, 20, 3, 10), ahora), '20/10 03:10');
      expect(FormatoSincronizacion.reloj(DateTime(2026, 10, 26, 14, 35), ahora), 'recién');
    });
  });

  group('FormatoSincronizacion.dia y diaYHora', () {
    test('should pad the day, the month and the hour', () {
      expect(FormatoSincronizacion.dia(DateTime(2026, 3, 5)), '05/03');
      expect(FormatoSincronizacion.diaYHora(DateTime(2026, 3, 5, 7, 4)), '05/03 07:04');
    });
  });

  group('TextosSincronizacion.listo', () {
    test('should follow the canvas when something was sent and received', () {
      expect(
        TextosSincronizacion.listo(const ActualizacionCompleta(enviadas: 3, recibidas: 12)),
        'Listo: enviamos 3 operaciones y recibimos 12 cambios.',
      );
    });

    test('should use the singular', () {
      expect(
        TextosSincronizacion.listo(const ActualizacionCompleta(enviadas: 1, recibidas: 1)),
        'Listo: enviamos 1 operación y recibimos 1 cambio.',
      );
    });

    test('should say only what moved', () {
      expect(
        TextosSincronizacion.listo(const ActualizacionCompleta(enviadas: 2)),
        'Listo: enviamos 2 operaciones.',
      );
      expect(
        TextosSincronizacion.listo(const ActualizacionCompleta(recibidas: 4)),
        'Listo: recibimos 4 cambios.',
      );
    });

    test('should say everything was up to date when nothing moved', () {
      expect(
        TextosSincronizacion.listo(const ActualizacionCompleta()),
        'Listo: todo estaba al día.',
      );
    });

    test('should not hide the rejected ones', () {
      expect(
        TextosSincronizacion.listo(const ActualizacionCompleta(enviadas: 2, rechazadas: 1)),
        'Listo: enviamos 2 operaciones, pero 1 operación no se pudo enviar.',
      );
      expect(
        TextosSincronizacion.listo(const ActualizacionCompleta(rechazadas: 3)),
        'Listo: todo estaba al día, pero 3 operaciones no se pudieron enviar.',
      );
    });
  });

  group('TextosSincronizacion nombres', () {
    test('should name the known tables and humanize the unknown ones', () {
      expect(TextosSincronizacion.nombreDeLaTabla('venta'), 'Venta');
      expect(TextosSincronizacion.nombreDeLaTabla('cobranza'), 'Cobro');
      expect(
        TextosSincronizacion.nombreDeLaTabla('ubicacion_par_decidido'),
        'Decisión de posibles duplicados',
      );
      expect(TextosSincronizacion.nombreDeLaTabla('pedido_stock'), 'Pedido stock');
      expect(TextosSincronizacion.nombreDeLaTabla(''), 'Operación');
      expect(TextosSincronizacion.nombreDeLaTabla('_'), 'Operación');
    });

    test('should close the reason with a period only when it lacks one', () {
      const esperado =
          'El servidor la rechazó: sin precio. Si el dato ya se corrigió, tocá «Reintentar».';
      expect(TextosSincronizacion.detalleTexto('sin precio'), esperado);
      expect(TextosSincronizacion.detalleTexto('sin precio.'), esperado);
    });
  });
}
