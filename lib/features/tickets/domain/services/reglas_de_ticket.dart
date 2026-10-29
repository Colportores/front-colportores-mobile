import '../../../cobranzas/domain/entities/cobranza.dart' show TipoTarjeta;
import '../../../ventas/domain/services/reglas_de_venta.dart';

/// Los datos del ticket de un cobro con tarjeta que el servidor exige (backend 0113, HU-COB-007).
enum DatoDelTicket {
  monto('monto'),
  fecha('fecha'),
  numeroAutorizacion('numero_autorizacion'),
  tipoDeTarjeta('tipo_de_tarjeta');

  const DatoDelTicket(this.nombre);

  final String nombre;
}

/// Las reglas de los datos del ticket, las mismas que aplica el servidor al subirlo: así lo que está
/// mal se corrige antes de salir, sin esperar a un `invalid` del push.
abstract final class ReglasDeTicket {
  /// El largo máximo del número de autorización y de la marca (`ticket_*_check` del servidor).
  static const largoMaximo = 40;

  /// Los datos con problema, o vacío si el ticket de tarjeta está completo.
  ///
  /// - **monto**: mayor que cero;
  /// - **fecha**: obligatoria y no futura (el día de Montevideo);
  /// - **número de autorización**: obligatorio, no en blanco, hasta 40 caracteres;
  /// - **tarjeta**: crédito o débito.
  static Set<DatoDelTicket> validar({
    required int? montoCentavos,
    required DateTime? fecha,
    required String? numeroAutorizacion,
    required TipoTarjeta? tarjetaTipo,
    required DateTime ahora,
  }) {
    final mal = <DatoDelTicket>{};
    if (montoCentavos == null || montoCentavos <= 0) mal.add(DatoDelTicket.monto);
    if (fecha == null ||
        ReglasDeVenta.diaDeMontevideo(fecha).isAfter(ReglasDeVenta.diaDeMontevideo(ahora))) {
      mal.add(DatoDelTicket.fecha);
    }
    final aut = numeroAutorizacion?.trim() ?? '';
    if (aut.isEmpty || aut.length > largoMaximo) mal.add(DatoDelTicket.numeroAutorizacion);
    if (tarjetaTipo == null) mal.add(DatoDelTicket.tipoDeTarjeta);
    return mal;
  }

  /// El monto del ticket no es el del cobro: se avisa antes de subir, **no se bloquea** (HU-COB-007).
  static bool montoDifiere({required int montoDelTicket, required int montoDelCobro}) =>
      montoDelTicket != montoDelCobro;
}
