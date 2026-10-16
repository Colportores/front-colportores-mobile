import '../domain/entities/pendientes_ubicacion.dart';

/// Los textos con números de la baja de una ubicación (vista 09, HU-UBI-005).
abstract final class FormatoBaja {
  /// «$U 1.450», o «$U 1.450,50» si no son pesos justos: pesos uruguayos, con punto de miles y coma
  /// decimal.
  static String monto(int centavos) {
    final signo = centavos < 0 ? '-' : '';
    final absoluto = centavos.abs();
    final pesos = (absoluto ~/ 100).toString();
    final centavosSueltos = absoluto % 100;
    final conMiles = StringBuffer();
    for (var i = 0; i < pesos.length; i++) {
      if (i > 0 && (pesos.length - i) % 3 == 0) conMiles.write('.');
      conMiles.write(pesos[i]);
    }
    final decimales = centavosSueltos == 0 ? '' : ',${centavosSueltos.toString().padLeft(2, '0')}';
    return '$signo\$U $conMiles$decimales';
  }

  /// «2.ª cuota».
  static String cuota(int numero) => '$numero.ª cuota';

  /// «$U 1.450 (2.ª cuota)».
  static String cobranza(CobranzaPendiente cobranza) =>
      '${monto(cobranza.montoCentavos)} (${cuota(cobranza.numeroCuota)})';

  /// «12/09/2026», en hora local.
  static String fecha(DateTime momento) {
    final m = momento.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(m.day)}/${dos(m.month)}/${m.year}';
  }
}
