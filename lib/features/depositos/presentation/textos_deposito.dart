import '../../catalogo/presentation/formato_precios.dart' show FormatoPrecios;
import '../../cuenta/presentation/textos_cuenta.dart' show FormatoCuenta;

/// Los textos de «Registrar depósito» (vista 33 D, HU-CTA-004). Los del canvas van tal cual; los que el
/// canvas no dibuja los decidió el agente de decisiones el 10/11 (P2 de #443).
abstract final class TextosDeposito {
  // --- 33D-01 -------------------------------------------------------------------------------
  static const eyebrow = 'REGISTRAR DEPÓSITO';
  static const titulo = 'Depositar efectivo';
  static const monto = 'MONTO';
  static const montoHint = r'$ 0';
  static const paraQue = 'PARA QUÉ';
  static const casaEditora = 'Casa editora';
  static const alquiler = 'Alquiler';
  static const donde = 'DÓNDE';
  static const banco = 'Banco';
  static const oficina = 'Oficina';
  static const retiro = 'Retiro';
  static const registrar = 'Registrar depósito';

  /// Lo que oye el lector de pantalla al llegar a cada grupo de opciones.
  static const paraQueEtiqueta = 'Para qué es el depósito';
  static const dondeEtiqueta = 'Dónde depositaste';

  /// «En mano: $ 2.400» (la línea de abajo del título).
  static String enMano(int centavos) => 'En mano: ${FormatoPrecios.monto(centavos)}';

  // --- La foto del ticket (vista 38 A, decisión «Paso ticket») ------------------------------
  static const sacarFotoDelTicket = 'Sacar foto del ticket';
  static const fotoCargada = 'Foto del ticket · tocá para cambiarla';
  static const fotoCargadaEtiqueta = 'Foto del ticket cargada. Tocá para cambiarla.';

  /// Mientras se achica la foto.
  static const preparandoFoto = 'Preparando la foto…';

  /// La hoja para elegir de dónde sale la foto.
  static const deDondeLaFoto = 'La foto del ticket';
  static const sacarFoto = 'Sacar foto';
  static const elegirDeLaGaleria = 'Elegir de la galería';

  /// Las fallas de la cámara y de la foto.
  static const sinPermisoDeCamara =
      'No tenemos permiso para usar la cámara. Activalo en los ajustes del teléfono o elegí la foto '
      'de la galería.';
  static const capturaFallida = 'No pudimos usar esa foto. Probá de nuevo.';
  static const fotoIlegible = 'No pudimos leer esa foto. Sacala de nuevo.';
  static const sinCamara = 'Este teléfono no tiene cámara: elegí la foto del ticket de la galería.';

  /// El número de operación del banco (la «referencia» de HU-CTA-004): opcional.
  static const referencia = 'Nº DE OPERACIÓN';
  static const referenciaHint = 'Opcional';

  /// El retiro no lleva foto (HU-CTA-004, «Retiro coord»).
  static const retiroSinFoto =
      'El retiro no lleva foto: tu coordinador confirma que recibió el efectivo.';

  /// El alquiler se paga a la campaña en curso y no hay ninguna.
  static const sinCampaniaParaElAlquiler =
      'No estás inscripto en una campaña en curso, y el alquiler se paga a tu campaña. Si es de una '
      'campaña que ya terminó, avisale a tu coordinador.';

  /// El título del calendario de la fecha.
  static const cuandoDepositaste = '¿Cuándo depositaste?';

  // --- Lo que falta (38A-04) ----------------------------------------------------------------
  static const faltaElMonto = 'Ingresá el monto que depositaste.';
  static const faltaLaFoto = 'Falta la foto del ticket.';
  static const faltanFotoYMonto = 'Falta la foto y el monto.';
  static const montoInvalido = 'Escribí un monto válido, por ejemplo 1.800.';

  // --- 33D-02 -------------------------------------------------------------------------------
  /// «Tenés $ 2.400 en mano.»
  static String tenesEnMano(int centavos) => 'Tenés ${FormatoPrecios.monto(centavos)} en mano.';

  // --- 33D-03, 33D-05 y 33D-06 --------------------------------------------------------------
  static const registrando = 'Registrando…';
  static const reintentar = 'Reintentar';
  static const sinConexion =
      'Sin conexión. Se registra en el teléfono y se envía cuando vuelve la conexión.';

  // --- 33D-04 -------------------------------------------------------------------------------
  static const tituloRegistrado = 'Depósito registrado';
  static const listo = 'Listo';
  static const filaEnMano = 'En mano';

  /// Con «Acredita V1» el depósito no pasa a «Depositado» al registrarlo, sino a lo
  /// «por validar» (el rótulo de Mi plata).
  static const filaPorValidar = 'Por validar';

  /// El aviso de 33D-04 con el texto de la decisión «Acredita V1» (23/10).
  static const quedaPorValidarTicket =
      'Queda por validar: suma a tu dinero depositado cuando tu coordinador valide el ticket.';

  /// El mismo aviso para el retiro, que no tiene ticket.
  static const quedaPorValidarRetiro =
      'Queda por validar: suma a tu dinero depositado cuando tu coordinador confirme el retiro.';

  /// El éxito sin conexión.
  static const seEnviaAlVolver = 'Se envía cuando vuelva la conexión.';

  // --- 38A-08, la foto del ticket no subió -------------------------------------------------

  /// 38A-08 tal cual con un ticket; con más, lo mismo en plural (pendiente de textos, P2 de la
  /// entrega de 38A-08).
  static String ticketsSinSubir(int cuantos) => cuantos == 1
      ? 'No pudimos enviar el ticket. Quedó guardado en el teléfono y lo reintentamos solo.'
      : 'No pudimos enviar $cuantos tickets. Quedaron guardados en el teléfono y los reintentamos '
            'solos.';
  static const reintentarAhora = 'Reintentar ahora';

  /// La foto que el servidor rechazó para siempre: no hay reintento, lo revisa el coordinador
  /// (decisión P1 del 10/11). [fechas] son las de los depósitos, la más vieja primero.
  static String ticketsRechazados(List<DateTime> fechas) => fechas.length == 1
      ? 'No pudimos enviar la foto del ticket del depósito del ${FormatoCuenta.fecha(fechas.first)} '
            'y ya no se puede reintentar. Avisale a tu coordinador para que lo revise.'
      : 'No pudimos enviar las fotos de ${fechas.length} tickets de depósito y ya no se pueden '
            'reintentar. Avisale a tu coordinador para que los revise.';

  /// «$ 2.400 → $ 600».
  static String antesYDespues(int antes, int despues) =>
      '${FormatoPrecios.monto(antes)} → ${FormatoPrecios.monto(despues)}';

  /// Lo que dice el lector de pantalla de una fila de 33D-04: «En mano: de $ 2.400 a $ 600».
  static String antesYDespuesEtiqueta(String fila, int antes, int despues) =>
      '$fila: de ${FormatoPrecios.monto(antes)} a ${FormatoPrecios.monto(despues)}';
}
