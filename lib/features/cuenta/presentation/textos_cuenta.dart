import '../../catalogo/presentation/formato_precios.dart' show FormatoPrecios;
import '../domain/entities/resumen_de_cuenta.dart';

/// Los textos de Mi Cuenta (vista 33A, HU-CTA-001). Los del canvas van tal cual; los que el canvas no
/// dibuja dicen «para confirmar».
abstract final class TextosCuenta {
  /// El rótulo chico sobre el título («CUENTA», 33A·01).
  static const eyebrow = 'CUENTA';
  static const titulo = 'Mi Cuenta';

  static const depositado = 'DEPOSITADO';
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

  /// 33A·02: cómo empieza el aviso de sin conexión.
  static const avisoSinConexion = 'Sin conexión';
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

  /// 33A·02, el aviso de sin conexión: «Sin conexión. Lo depositado es de ayer a las 21:00; en mano y
  /// por cobrar están al día.» El canvas nombra también la deuda con la casa editora; sin ella (V2)
  /// queda lo depositado. [bajadoEn] es la última bajada del servidor; [ahora], el reloj de la
  /// pantalla. Para confirmar (mapa §2: texto): el canvas solo dibuja «ayer»; «hoy» y la fecha son
  /// los otros dos días posibles.
  ///
  /// Decisión del 04/11 (mapa §2, coherencia): si la deuda con la casa editora que se guardó
  /// ([deudaLeidaEn]) es de otro momento que lo depositado, el aviso suma «La deuda con la casa
  /// editora es de ayer a las 21:00.»; si coinciden, queda el aviso del canvas.
  static String sinConexion(DateTime bajadoEn, DateTime ahora, {DateTime? deudaLeidaEn}) {
    final depositado = _cuandoYHora(bajadoEn, ahora);
    final aviso =
        '${TextosCuenta.avisoSinConexion}. Lo depositado es $depositado; en mano y por cobrar '
        'están al día.';
    if (deudaLeidaEn == null) return aviso;
    final deuda = _cuandoYHora(deudaLeidaEn, ahora);
    return deuda == depositado ? aviso : '$aviso La deuda con la casa editora es $deuda.';
  }

  /// «de ayer a las 21:00», «de hoy a las 07:05» o «del 28/10 a las 09:00».
  static String _cuandoYHora(DateTime instante, DateTime ahora) {
    final momento = instante.toLocal();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(momento.year, momento.month, momento.day);
    String dos(int n) => n.toString().padLeft(2, '0');
    final cuando = switch (hoy.difference(dia).inDays) {
      0 => 'de hoy',
      1 => 'de ayer',
      _ => 'del ${dos(dia.day)}/${dos(dia.month)}',
    };
    return '$cuando a las ${dos(momento.hour)}:${dos(momento.minute)}';
  }

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
