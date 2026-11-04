import '../../agenda/presentation/formato_agendar_visita.dart';
import '../../ventas/presentation/formato_venta.dart';
import '../domain/entities/cobranza.dart' show MedioCobranza;
import '../domain/entities/cuota.dart';
import '../domain/services/reparto_de_cuotas.dart';

/// Los textos de la vista 30 grupo A (Plan de cuotas, HU-COB-004): los del canvas tal cual, y los que
/// el canvas no dibuja marcados «A confirmar» (mapa §2: texto).
abstract final class TextosCuotas {
  // --- Del canvas: armar el plan (30A-01 a 30A-03, 30A-08) ---
  static const eyebrowPlan = 'PLAN DE CUOTAS';
  static const tituloPlan = 'Pagar en cuotas';
  static const cantidad = 'Cantidad de cuotas';
  static const cantidadAyuda = 'De 2 a 12';
  static const cadaCuanto = 'CADA CUÁNTO';
  static const semanal = 'Semanal';
  static const mensual = 'Mensual';
  static const primeraCuota = 'PRIMERA CUOTA';
  static const cuotasRotulo = 'CUOTAS · TOCÁ UN MONTO PARA CAMBIARLO';
  static const seAgendan = 'Agendamos una cobranza para cada cuota, con recordatorio.';
  static const crearPlan = 'Crear plan';
  static const reintentar = 'Reintentar';
  static const seAjusto = 'Se ajustó';
  static const primeraEnElPasado = 'La primera cuota tiene que ser hoy o más adelante.';
  static const errorAlCrear = 'No pudimos crear el plan. No se agendó ninguna cobranza.';

  // --- Del canvas: la lista de cuotas (30A-04 a 30A-07) ---
  static const tituloCuotas = 'Cuotas';
  static const agendarCobranza = 'Agendar cobranza';
  static const ventaPagada = 'La venta está pagada';
  static const sinSaldoParaRepartir = 'No hay saldo para repartir en cuotas.';

  // --- Del canvas: modificar (30A-09) ---
  static const tituloModificar = 'Modificar cuotas';
  static const cuotas = 'CUOTAS';
  static const guardarCuotas = 'Guardar cuotas';
  static const yaEstaPagada = 'Ya está pagada: no cambia.';
  static const pagada = 'Pagada';
  static const notaModificar =
      'Solo se ajustan las cuotas que no están cerradas. Al guardar se reprograman sus cobranzas.';

  /// «PLAN DE CUOTAS» del eyebrow de la lista: «VENTA 0042».
  static String eyebrowVenta(String talonario) => 'VENTA $talonario';

  /// «María Fernández · saldo $ 2.500» (30A-01).
  static String subtituloPlan(String? persona, int saldoCentavos) {
    final saldo = 'saldo ${FormatoVenta.monto(saldoCentavos)}';
    return persona == null || persona.isEmpty ? saldo : '$persona · $saldo';
  }

  /// «El saldo es $ 2.500: la cuota no puede ser mayor.» (30A-02C).
  static String superaElSaldo(int saldoCentavos) =>
      'El saldo es ${FormatoVenta.monto(saldoCentavos)}: la cuota no puede ser mayor.';

  /// «1 · sáb 26/10»: el rótulo de una cuota en el plan (30A-01).
  static String rotuloDeCuota(int numero, DateTime fecha) =>
      '$numero · ${FormatoAgendarVisita.diaCortoYMes(fecha).toLowerCase()}';

  /// «Sábado 26/10»: el día de la primera cuota (30A-01).
  static String diaDeLaPrimera(DateTime fecha) => FormatoAgendarVisita.diaLargo(fecha);

  /// «PLAN · 3 CUOTAS SEMANALES» (30A-04); sin frecuencia conocida (el plan de la lista se deduce de
  /// sus fechas), «PLAN · 3 CUOTAS».
  static String rotuloDelPlan(int cantidad, FrecuenciaDeCuotas? frecuencia) {
    final cuotas = cantidad == 1 ? '1 CUOTA' : '$cantidad CUOTAS';
    return frecuencia == null
        ? 'PLAN · $cuotas'
        : 'PLAN · $cuotas ${cantidad == 1 ? frecuencia.adjetivoPlural.replaceAll('ES', 'AL') : frecuencia.adjetivoPlural}';
  }

  /// «Plan creado. Agendamos 3 cobranzas.» (30A-04).
  static String planCreado(int cantidad) =>
      'Plan creado. Agendamos $cantidad ${cantidad == 1 ? 'cobranza' : 'cobranzas'}.';

  /// «CUOTA 1 · 26/10».
  static String antetituloDeCuota(Cuota cuota) =>
      'CUOTA ${cuota.numero} · ${FormatoAgendarVisita.diaYMes(cuota.fecha)}';

  /// «Pagada el 26/10 · efectivo» (30A-04): el día del cobro que completó la cuota y los medios de los
  /// cobros que la cubrieron («efectivo y tarjeta»). Si los cobros no lo dicen, solo «Pagada» (decisión
  /// del 29/10, P5 de #166).
  static String pagadaEl(DateTime? dia, List<MedioCobranza> medios) {
    if (dia == null) return pagada;
    final fecha = 'Pagada el ${FormatoAgendarVisita.diaYMes(dia)}';
    if (medios.isEmpty) return fecha;
    final nombres = [for (final m in medios) _nombreDelMedio(m)];
    final lista = nombres.length == 1
        ? nombres.first
        : '${nombres.sublist(0, nombres.length - 1).join(', ')} y ${nombres.last}';
    return '$fecha · $lista';
  }

  static String _nombreDelMedio(MedioCobranza medio) => switch (medio) {
    MedioCobranza.efectivo => 'efectivo',
    MedioCobranza.tarjeta => 'tarjeta',
    MedioCobranza.transferencia => 'transferencia',
  };

  /// «$ 833».
  static String montoDeCuota(int centavos) => FormatoVenta.monto(centavos);

  /// «$ 400 de $ 833» (30A-04, cuota parcial).
  static String pagadoDe(int pagado, int monto) =>
      '${FormatoVenta.monto(pagado)} de ${FormatoVenta.monto(monto)}';

  /// «Parcial · faltan $ 433» (30A-04).
  static String parcialFaltan(int faltan) => 'Parcial · faltan ${FormatoVenta.monto(faltan)}';

  /// «Agendada · 09/11 10:00» (30A-04).
  static String agendadaPara(DateTime fecha) =>
      'Agendada · ${FormatoAgendarVisita.diaYMes(fecha)} ${FormatoAgendarVisita.hora(fecha)}';

  /// «La cuota 2 venció el 02/11. Te avisamos con una notificación.» (30A-06).
  static String vencio(Cuota cuota) =>
      'La cuota ${cuota.numero} venció el ${FormatoAgendarVisita.diaYMes(cuota.fecha)}. '
      'Te avisamos con una notificación.';

  /// «Completa la cuota 2 ($ 433) y adelanta $ 567 de la cuota 3.» (30A-05). Los casos que el canvas
  /// no dibuja (un pago que no completa ninguna, que completa varias, o que sobra) siguen la misma
  /// frase (A confirmar).
  static String avisoDePago(AplicacionDePago pago) {
    final partes = <String>[];
    final completas = pago.completadas;
    if (completas.length == 1) {
      final c = completas.first;
      partes.add('Completa la cuota ${c.cuota.numero} (${FormatoVenta.monto(c.aplicadoCentavos)})');
    } else if (completas.length > 1) {
      final numeros = completas.map((c) => c.cuota.numero).toList();
      final total = completas.fold<int>(0, (a, c) => a + c.aplicadoCentavos);
      partes.add(
        'Completa las cuotas ${numeros.sublist(0, numeros.length - 1).join(', ')} y '
        '${numeros.last} (${FormatoVenta.monto(total)})',
      );
    }
    final adelanto = pago.adelanto;
    if (adelanto != null) {
      final suma = FormatoVenta.monto(adelanto.aplicadoCentavos);
      partes.add(
        partes.isEmpty
            ? 'Suma $suma a la cuota ${adelanto.cuota.numero}; faltan '
                  '${FormatoVenta.monto(adelanto.faltaDespuesCentavos)}'
            : 'adelanta $suma de la cuota ${adelanto.cuota.numero}',
      );
    }
    final frase = partes.join(' y ');
    final sobra = pago.sobranteCentavos > 0
        ? ' ${FormatoVenta.monto(pago.sobranteCentavos)} quedan como pago libre.'
        : '';
    return '$frase.$sobra';
  }

  // --- A confirmar (mapa §2: texto) ---
  static const creando = 'Creando…';
  static const guardando = 'Guardando…';
  static const cargandoLasCuotas = 'Cargando las cuotas';
  static const errorDeLectura = 'No pudimos leer las cuotas guardadas en tu teléfono.';
  static const ventaAusente = 'Esta venta ya no está en tu teléfono. Volvé atrás y elegí otra.';
  static const sinPlanTitulo = 'Esta venta no tiene plan de cuotas';
  static const sinPlanTexto =
      'Los pagos son libres: cualquier monto baja el saldo. Si querés, repartí lo que falta en '
      'cuotas.';
  static const modificar = 'Modificar cuotas';
  static const pagarEnCuotas = 'Pagar en cuotas';
  static const verLasCuotas = 'Ver las cuotas';
  static const volver = 'Volver';
  static const vencida = 'Vencida';
  static const parcial = 'Parcial';
  static const montoSinValor = 'Ingresá el monto de la cuota.';
  static const noDejaParaLasSiguientes =
      'Dejá algo para las cuotas que siguen: cada una tiene que ser de más de \$ 0.';
  static const menorQueLoPagado = 'No puede ser menos de lo que ya se cobró de esta cuota.';
  static const noHayCuotasAbiertas = 'Todas las cuotas están pagadas.';
  static const sinAvisos =
      'Algunas cobranzas quedaron sin recordatorio: revisá que las notificaciones estén prendidas.';

  /// El texto de un problema de monto de una cuota (30A-02C y los que el canvas no dibuja).
  static String problema(ProblemaDeCuota problema, int saldoCentavos) => switch (problema) {
    ProblemaDeCuota.sinMonto => montoSinValor,
    ProblemaDeCuota.superaElSaldo => superaElSaldo(saldoCentavos),
    ProblemaDeCuota.noDejaParaLasSiguientes => noDejaParaLasSiguientes,
    ProblemaDeCuota.menorQueLoPagado => menorQueLoPagado,
  };
}
