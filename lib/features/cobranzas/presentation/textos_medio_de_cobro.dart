/// Los textos de la vista 29 (Cobro con tarjeta y por transferencia, HU-COB-002 y HU-COB-003): los
/// del canvas tal cual, y los que el canvas no dibuja (decididos como están, PR #572, P5).
abstract final class TextosMedioDeCobro {
  // --- Del canvas (29A y 29B) ---
  static const eyebrow = 'COBRO';
  static const medio = 'MEDIO';
  static const efectivo = 'Efectivo';
  static const tarjeta = 'Tarjeta';
  static const transferencia = 'Transferencia';
  static const debito = 'Débito';
  static const credito = 'Crédito';
  static const marca = 'MARCA (OPCIONAL)';
  static const marcas = ['Visa', 'Mastercard', 'OCA'];
  static const marcaOtra = 'Otra';
  static const aprobacion = 'Nº DE APROBACIÓN (OPCIONAL)';
  static const aprobacionHint = 'Lo dice el ticket';
  static const referencia = 'REFERENCIA (OPCIONAL)';
  static const referenciaHint = 'Nº de operación';
  static const banco = 'BANCO DE ORIGEN (OPCIONAL)';
  static const bancoHint = 'Elegir banco';
  static const hojaBancoTitulo = 'Banco de origen';
  static const bancos = ['BROU', 'Itaú', 'Santander', 'Scotiabank', 'BBVA'];
  static const bancoOtro = 'Otro';
  static const listo = 'Listo';

  /// 29A·02: el segundo aviso de la tarjeta registrada (decisión del 23/10: gana el canvas sobre el
  /// texto de la HU, «En V2 podrás cargarlo desde aquí.»).
  static const guardaElTicket = 'Guardá el ticket de la tarjeta: tu coordinador te lo va a pedir.';

  /// «Sumamos $ 1.200 a tu dinero depositado.» (29A·02) y, con la referencia, «… Referencia 88213.»
  /// (29B·03). Tarjeta y transferencia suman al dinero depositado, no al dinero en mano.
  static String sumamosDepositado(String monto, {String? referencia}) =>
      'Sumamos $monto a tu dinero depositado.${referencia == null ? '' : ' Referencia $referencia.'}';

  // --- Sin dibujo en el canvas (texto y accesibilidad; decididos como están) ---

  /// Lo que oye el lector de pantalla en el control de débito o crédito, que el canvas dibuja sin
  /// rótulo.
  static const tipoDeTarjeta = 'Tipo de tarjeta';

  /// Los campos de «Otra» marca y «Otro» banco, que el canvas no dibuja.
  static const marcaOtraRotulo = 'OTRA MARCA';
  static const marcaOtraHint = 'Escribí la marca';
  static const bancoOtroRotulo = 'OTRO BANCO';
  static const bancoOtroHint = 'Escribí el banco';

  /// Lo que oye el lector de pantalla al llegar a las opciones de la hoja del banco.
  static const elegirUnBanco = 'Elegí un banco';
}
