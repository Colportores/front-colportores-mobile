// QA de #642: la clave `deuda_hace_7_dias` del RPC `mi_deuda_con_la_casa_editora` (backend-supabase
// 0168) y la variación semanal con datos límite; privacidad de `toString` de la jornada sin el tipo de
// acompañamiento.
import 'package:colportores_mobile/features/cuenta/data/models/deuda_con_la_casa_model.dart';
import 'package:colportores_mobile/features/cuenta/presentation/textos_deuda.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _base([Map<String, Object?> extra = const {}]) => {
  'deuda_total': 1840000,
  'suma_de_saldos': 1840000,
  'depositos_validados': 0,
  'pedidos': <Object?>[],
  ...extra,
};

void main() {
  group('deuda_hace_7_dias del servidor', () {
    test('dado que la clave falta (respuesta guardada antes de 0168), no hay con qué comparar', () {
      final d = DeudaConLaCasaModel.desdeJson(_base());
      expect(d.deudaHace7DiasCentavos, isNull);
      expect(d.variacionCentavos, isNull);
      expect(FormatoDeuda.lineaDeVariacion(d), 'Sin datos de la semana anterior');
    });

    test('dado null explícito, es lo mismo que la clave ausente', () {
      final d = DeudaConLaCasaModel.desdeJson(_base({'deuda_hace_7_dias': null}));
      expect(d.variacionCentavos, isNull);
    });

    test(
      'dado 0 (el servidor registró que no debía nada), es «igual» o «subió», no «sin datos»',
      () {
        final cero = DeudaConLaCasaModel.desdeJson(
          _base({'deuda_total': 0, 'deuda_hace_7_dias': 0}),
        );
        expect(cero.variacionCentavos, 0);
        expect(FormatoDeuda.lineaDeVariacion(cero), 'Igual que la semana pasada');
        final subio = DeudaConLaCasaModel.desdeJson(_base({'deuda_hace_7_dias': 0}));
        expect(FormatoDeuda.lineaDeVariacion(subio), r'▲ $ 18.400 contra la semana pasada');
      },
    );

    test('dado un valor negativo (estaba a favor), la variación es contra ese negativo', () {
      final d = DeudaConLaCasaModel.desdeJson(_base({'deuda_hace_7_dias': -50000}));
      expect(d.variacionCentavos, 1840000 + 50000);
      expect(FormatoDeuda.lineaDeVariacion(d), r'▲ $ 18.900 contra la semana pasada');
    });

    test('dado un entero que viene como double sin decimales (JSON de Postgres), se acepta', () {
      final d = DeudaConLaCasaModel.desdeJson(_base({'deuda_hace_7_dias': 2050000.0}));
      expect(d.deudaHace7DiasCentavos, 2050000);
    });

    for (final raro in <Object>[
      '2050000',
      'abc',
      20500.5,
      true,
      <Object?>[],
      <String, Object?>{},
    ]) {
      test('dado ${raro.runtimeType} «$raro», la lectura se rechaza entera (no se adivina)', () {
        expect(
          () => DeudaConLaCasaModel.desdeJson(_base({'deuda_hace_7_dias': raro})),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('dado un entero enorme, la cuenta no se desborda ni da negativo', () {
      final d = DeudaConLaCasaModel.desdeJson(
        _base({'deuda_total': 9000000000000000, 'deuda_hace_7_dias': 1}),
      );
      expect(d.variacionCentavos, 9000000000000000 - 1);
    });
  });

  group('privacidad', () {
    test('toString de la deuda no vuelca montos ni pedidos', () {
      final d = DeudaConLaCasaModel.desdeJson(_base({'deuda_hace_7_dias': 2050000}));
      expect(d.toString(), isNot(contains('1840000')));
      expect(d.toString(), isNot(contains('2050000')));
    });
  });
}
