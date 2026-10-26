// Los textos y formatos de la baja de una persona (HU-UBI-011, canvas 32D).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/services/cuenta_de_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_baja_persona.dart';
import 'package:test/test.dart';

import '../../../../helpers/persona_falsos.dart';

ResumenCuentaPersona _cuenta({int saldo = 120000, int hechas = 1, int total = 2}) =>
    ResumenCuentaPersona(
      compradoCentavos: 450000,
      pagadoCentavos: 330000,
      saldoCentavos: saldo,
      entregasHechas: hechas,
      entregasTotales: total,
    );

void main() {
  group('FormatoBajaPersona.monto', () {
    test('escribe pesos con punto de miles y un espacio que no se parte', () {
      expect(FormatoBajaPersona.monto(120000), '\$ 1.200');
      expect(FormatoBajaPersona.monto(450000), '\$ 4.500');
      expect(FormatoBajaPersona.monto(5000), '\$ 50');
      expect(FormatoBajaPersona.monto(0), '\$ 0');
      expect(FormatoBajaPersona.monto(123456789), '\$ 1.234.567,89');
    });

    test('con centavos sueltos usa la coma decimal', () {
      expect(FormatoBajaPersona.monto(120050), '\$ 1.200,50');
      expect(FormatoBajaPersona.monto(5), '\$ 0,05');
    });
  });

  group('FormatoBajaPersona.fechaCorta', () {
    final ahora = DateTime.utc(2026, 10, 26, 12);

    test('este año, día y mes', () {
      expect(FormatoBajaPersona.fechaCorta(DateTime.utc(2026, 10, 22, 12), ahora), '22/10');
      expect(FormatoBajaPersona.fechaCorta(DateTime.utc(2026, 1, 5, 12), ahora), '05/01');
    });

    test('otro año, con el año para no confundirlo', () {
      expect(FormatoBajaPersona.fechaCorta(DateTime.utc(2025, 10, 22, 12), ahora), '22/10/2025');
    });
  });

  group('TextosBajaPersona', () {
    test('el título y los textos del canvas', () {
      expect(TextosBajaPersona.titulo('Jorge'), '¿Dar de baja a Jorge?');
      expect(
        TextosBajaPersona.cuerpoSinSaldo,
        'Deja de aparecer en el depto. No se borra: lo ves en «Ver bajas» y lo podés reactivar.',
      );
      expect(
        TextosBajaPersona.deudaSigue('María', 120000),
        'La deuda de \$ 1.200 sigue en tu cuenta aunque María esté de baja.',
      );
      expect(TextosBajaPersona.activaDeNuevo('María'), 'María está activa de nuevo.');
    });

    test('el resumen dice la deuda y las entregas pendientes en singular y plural', () {
      expect(
        TextosBajaPersona.resumenDeSaldo('María', _cuenta()),
        'María te debe \$ 1.200 y tiene 1 entrega pendiente.',
      );
      expect(
        TextosBajaPersona.resumenDeSaldo('María', _cuenta(hechas: 0, total: 3)),
        'María te debe \$ 1.200 y tiene 3 entregas pendientes.',
      );
      expect(
        TextosBajaPersona.resumenDeSaldo('María', _cuenta(hechas: 2)),
        'María te debe \$ 1.200.',
      );
      expect(TextosBajaPersona.entregas(_cuenta()), '1 de 2');
    });

    test('«Baja el 22/10» con el saldo solo si se conoce y es mayor que cero', () {
      final baja = DateTime.utc(2026, 10, 22, 15);
      final ahora = DateTime.utc(2026, 10, 26);
      expect(TextosBajaPersona.bajaEl(baja, ahora), 'Baja el 22/10');
      expect(TextosBajaPersona.bajaEl(baja, ahora, saldoCentavos: 0), 'Baja el 22/10');
      expect(
        TextosBajaPersona.bajaEl(baja, ahora, saldoCentavos: 120000),
        'Baja el 22/10 · saldo \$ 1.200',
      );
    });

    test('el nombre de pila: el nombre solo, o «La persona» si no tiene', () {
      expect(
        FormatoBajaPersona.nombreDePila(clienteDePersonas('p', 'María', apellido: 'F').persona),
        'María',
      );
      expect(FormatoBajaPersona.nombreDePila(clienteDePersonas('p', ' ').persona), 'La persona');
    });

    test('la falla dice su propio mensaje si es una validación, y el de siempre si no', () {
      const validacion = FailureValidacion(campos: {'persona': 'No está'});
      expect(mensajeDeFallaDePersona(validacion, 'Otro'), 'No está');
      expect(mensajeDeFallaDePersona(const FailureInesperado(), 'Otro'), 'Otro');
      expect(mensajeDeFallaDePersona(const FailureValidacion(campos: {}), 'Otro'), 'Otro');
    });
  });
}
