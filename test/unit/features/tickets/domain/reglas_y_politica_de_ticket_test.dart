// Las reglas del ticket y la política de compresión de la foto (HU-COB-007, #426).
import 'dart:typed_data';

import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/services/politica_de_compresion.dart';
import 'package:colportores_mobile/features/tickets/domain/services/reglas_de_ticket.dart';
import 'package:test/test.dart';

import '../../../../helpers/tickets_falsos.dart';

void main() {
  group('ReglasDeTicket', () {
    test('el monto es mayor que cero y entra en el entero de la app', () {
      expect(ReglasDeTicket.montoValido(1), isTrue);
      expect(ReglasDeTicket.montoValido(ReglasDeTicket.maximoCentavos), isTrue);
      expect(ReglasDeTicket.montoValido(0), isFalse);
      expect(ReglasDeTicket.montoValido(-5), isFalse);
      expect(ReglasDeTicket.montoValido(ReglasDeTicket.maximoCentavos + 1), isFalse);
    });

    test('la fecha se mide en días de Montevideo: hoy a la noche no es futuro, mañana sí', () {
      // 23:30 en Montevideo (UTC-3) del 30/10 es 02:30 UTC del 31/10.
      final ahora = DateTime.utc(2026, 10, 31, 2, 30);
      expect(ReglasDeTicket.fechaValida(DateTime.utc(2026, 10, 31, 2, 0), ahora), isTrue);
      expect(ReglasDeTicket.fechaValida(DateTime.utc(2026, 10, 29), ahora), isTrue);
      // Mañana en Montevideo (31/10 a las 04:00 UTC = 01:00 del 31/10 allá; ya es otro día).
      expect(ReglasDeTicket.fechaValida(DateTime.utc(2026, 10, 31, 3, 30), ahora), isFalse);
      expect(ReglasDeTicket.fechaValida(DateTime.utc(2026, 11, 5), ahora), isFalse);
    });

    test('el ticket de tarjeta pide autorización y tarjeta; el de un depósito, no', () {
      expect(ReglasDeTicket.pideAutorizacion(TipoDeTicket.cobroTarjeta), isTrue);
      expect(ReglasDeTicket.pideTarjeta(TipoDeTicket.cobroTarjeta), isTrue);
      expect(ReglasDeTicket.pideAutorizacion(TipoDeTicket.deposito), isFalse);
      expect(ReglasDeTicket.pideTarjeta(TipoDeTicket.deposito), isFalse);
      expect(ReglasDeTicket.pideAutorizacion(TipoDeTicket.otro), isFalse);
    });

    test('limpio recorta y deja null lo que queda en blanco; los textos tienen hasta 40', () {
      expect(ReglasDeTicket.limpio('  123 '), '123');
      expect(ReglasDeTicket.limpio('   '), isNull);
      expect(ReglasDeTicket.limpio(null), isNull);
      expect(ReglasDeTicket.textoValido('a' * 40), isTrue);
      expect(ReglasDeTicket.textoValido('a' * 41), isFalse);
      expect(ReglasDeTicket.textoValido(null), isTrue);
    });

    test('avisa si el monto del ticket no coincide con el del cobro (no bloquea)', () {
      expect(
        ReglasDeTicket.montoDistintoDelCobro(montoDelTicket: 1500, montoDelCobro: 1500),
        isFalse,
      );
      expect(
        ReglasDeTicket.montoDistintoDelCobro(montoDelTicket: 1500, montoDelCobro: 1000),
        isTrue,
      );
    });

    test('la foto pesa algo y no pasa de 2 MiB', () {
      expect(ReglasDeTicket.fotoValida(0), isFalse);
      expect(ReglasDeTicket.fotoValida(1), isTrue);
      expect(ReglasDeTicket.fotoValida(2 * 1024 * 1024), isTrue);
      expect(ReglasDeTicket.fotoValida(2 * 1024 * 1024 + 1), isFalse);
    });
  });

  group('PoliticaDeCompresion', () {
    final original = Uint8List.fromList([1, 2, 3]);
    const objetivo = ReglasDeTicket.objetivoBytesDeLaFoto;

    test('se queda con el primer paso que entra en 200 KB', () async {
      final compresor = CompresorDePrueba([objetivo + 1, objetivo, 10]);

      final foto = (await PoliticaDeCompresion(compresor).comprimir(original))!;

      expect(foto.indiceDelPaso, 1);
      expect(foto.cabeEnElObjetivo, isTrue);
      expect(compresor.llamadas, hasLength(2));
      expect(compresor.llamadas.first.calidad, PoliticaDeCompresion.escalera.first.calidad);
    });

    test('si la primera ya entra, no baja la calidad de más', () async {
      final compresor = CompresorDePrueba([1000]);

      final foto = (await PoliticaDeCompresion(compresor).comprimir(original))!;

      expect(foto.indiceDelPaso, 0);
      expect(compresor.llamadas, hasLength(1));
    });

    test('la legibilidad gana: si ningún paso llega a 200 KB, queda con el de más calidad que '
        'el servidor acepta', () async {
      final compresor = CompresorDePrueba([900 * 1024, 800 * 1024, 700 * 1024, 600 * 1024]);

      final foto = (await PoliticaDeCompresion(compresor).comprimir(original))!;

      expect(foto.indiceDelPaso, 0);
      expect(foto.bytes.length, 900 * 1024);
      expect(foto.cabeEnElObjetivo, isFalse);
      expect(compresor.llamadas, hasLength(PoliticaDeCompresion.escalera.length));
    });

    test('un paso que pasa de 2 MiB no sirve; el primero que lo cumple sí', () async {
      final compresor = CompresorDePrueba([3 * 1024 * 1024, 1500 * 1024, 1400 * 1024, 1300 * 1024]);

      final foto = (await PoliticaDeCompresion(compresor).comprimir(original))!;

      expect(foto.indiceDelPaso, 1);
    });

    test('si ni el último paso entra en 2 MiB, devuelve null', () async {
      final compresor = CompresorDePrueba([5 * 1024 * 1024]);

      expect(await PoliticaDeCompresion(compresor).comprimir(original), isNull);
    });

    test('una imagen que no se puede leer devuelve null', () async {
      expect(
        await PoliticaDeCompresion(CompresorDePrueba([10], legible: false)).comprimir(original),
        isNull,
      );
    });

    test('«No se lee bien»: se vuelve a comprimir desde un paso de más calidad', () async {
      final compresor = CompresorDePrueba([objetivo + 1, objetivo + 1, 5000]);
      final politica = PoliticaDeCompresion(compresor);

      final primera = (await politica.comprimir(original))!;
      expect(primera.indiceDelPaso, 2);

      compresor.llamadas.clear();
      final mejor = (await politica.comprimir(original, desdeElPaso: 0))!;
      expect(compresor.llamadas.first.calidad, PoliticaDeCompresion.escalera.first.calidad);
      expect(mejor, isNotNull);
    });

    test('desdeElPaso fuera de la escalera se acota', () async {
      final compresor = CompresorDePrueba([10]);

      final foto = (await PoliticaDeCompresion(compresor).comprimir(original, desdeElPaso: 99))!;

      expect(foto.indiceDelPaso, PoliticaDeCompresion.escalera.length - 1);
    });
  });
}
