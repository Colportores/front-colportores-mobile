import '../../catalogo/presentation/formato_precios.dart' show FormatoPrecios;
import '../domain/entities/resumen_de_cuenta.dart';

/// Los textos de Mi Cuenta (vista 33A, HU-CTA-001). Los del canvas van tal cual; los que el canvas no
/// dibuja dicen «para confirmar».
abstract final class TextosCuenta {
  /// El rótulo chico sobre el título («CUENTA», 33A·01).
  static const eyebrow = 'CUENTA';
  static const titulo = 'Mi Cuenta';

  static const enMano = 'EN MANO';
  static const porCobrar = 'POR COBRAR';

  /// 33A·04, la cuenta nueva: no hay con qué comparar.
  static const sinDatosSemanaAnterior = 'Sin datos de la semana anterior';

  /// Para confirmar: el canvas no dibuja la cifra que no se movió.
  static const igualQueLaSemanaPasada = 'Igual que la semana pasada';

  /// El consejo de «En mano» cuando el efectivo creció (33A·01).
  static const depositaloPronto = 'depositalo pronto';

  /// 33A·03: lo que lee el lector de pantalla mientras se calcula.
  static const cargando = 'Calculando tu cuenta';

  /// 33A·05.
  static const errorCalculo = 'No pudimos calcular tu cuenta.';
  static const reintentar = 'Reintentar';

  /// «contra la semana pasada», sin la flecha ni el monto.
  static const contraLaSemanaPasada = 'contra la semana pasada';
}

/// Cómo se escriben las cifras de Mi Cuenta.
abstract final class FormatoCuenta {
  /// «$ 18.400», o «$ 1.450,50» si no son pesos justos.
  static String monto(int centavos) => FormatoPrecios.monto(centavos);

  /// La línea de abajo de una tarjeta, tal como se ve: «▲ $ 1.800 contra la semana pasada»,
  /// «▼ $ 1.300 contra la semana pasada», «Igual que la semana pasada» o «Sin datos de la semana
  /// anterior».
  ///
  /// [aconsejaDepositar]: «En mano» que creció y todavía tiene efectivo cierra con
  /// «· depositalo pronto» en lugar de «contra la semana pasada» (33A·01).
  static String lineaDeVariacion(CifraDeCuenta cifra, {bool aconsejaDepositar = false}) {
    final variacion = cifra.variacionCentavos;
    if (variacion == null) return TextosCuenta.sinDatosSemanaAnterior;
    if (variacion == 0) return TextosCuenta.igualQueLaSemanaPasada;
    final flecha = variacion > 0 ? '▲' : '▼';
    final monto = FormatoPrecios.monto(variacion.abs());
    return _aconseja(cifra, aconsejaDepositar)
        ? '$flecha $monto · ${TextosCuenta.depositaloPronto}'
        : '$flecha $monto ${TextosCuenta.contraLaSemanaPasada}';
  }

  static bool _aconseja(CifraDeCuenta cifra, bool aconsejaDepositar) =>
      aconsejaDepositar && (cifra.variacionCentavos ?? 0) > 0 && cifra.totalCentavos > 0;

  /// Lo mismo para el lector de pantalla, que lee mal las flechas: «Subió $ 1.800 contra la semana
  /// pasada».
  static String variacionHablada(CifraDeCuenta cifra, {bool aconsejaDepositar = false}) {
    final variacion = cifra.variacionCentavos;
    if (variacion == null) return TextosCuenta.sinDatosSemanaAnterior;
    if (variacion == 0) return TextosCuenta.igualQueLaSemanaPasada;
    final verbo = variacion > 0 ? 'Subió' : 'Bajó';
    final consejo = _aconseja(cifra, aconsejaDepositar)
        ? '. ${_capitalizar(TextosCuenta.depositaloPronto)}'
        : '';
    final monto = FormatoPrecios.monto(variacion.abs());
    return '$verbo $monto ${TextosCuenta.contraLaSemanaPasada}$consejo';
  }

  static String _capitalizar(String texto) => texto[0].toUpperCase() + texto.substring(1);
}
