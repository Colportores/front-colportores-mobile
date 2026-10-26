import '../../../core/error/failure.dart';
import '../domain/entities/persona.dart';
import '../domain/services/cuenta_de_persona.dart';

/// Los textos de la baja de una persona y de «Ver bajas» (vista 32D, HU-UBI-011). Los del canvas van
/// tal cual; los que el canvas no dibuja (marcados «a confirmar») dicen qué pasa y qué hacer.
abstract final class TextosBajaPersona {
  // Canvas 32D·01 a 32D·03.
  static const cuerpoSinSaldo =
      'Deja de aparecer en el depto. No se borra: queda en «Ver bajas» y se puede reactivar.';
  static const darDeBaja = 'Dar de baja';
  static const darDeBajaIgual = 'Dar de baja igual';
  static const cancelar = 'Cancelar';
  static const seguro = '¿Seguro?';
  static const siDarDeBaja = 'Sí, dar de baja';
  static const noVolver = 'No, volver';
  static const comprado = 'Comprado';
  static const entregado = 'Entregado';
  static const pagado = 'Pagado';
  static const saldo = 'Saldo';

  static String titulo(String nombre) => '¿Dar de baja a $nombre?';

  /// «María te debe $ 1.200 y tiene 1 entrega pendiente.» Sin entregas pendientes, solo la deuda.
  static String resumenDeSaldo(String nombre, ResumenCuentaPersona cuenta) {
    final deuda = '$nombre te debe ${FormatoBajaPersona.monto(cuenta.saldoCentavos)}';
    final pendientes = cuenta.entregasPendientes;
    if (pendientes == 0) return '$deuda.';
    final entregas = pendientes == 1 ? '1 entrega pendiente' : '$pendientes entregas pendientes';
    return '$deuda y tiene $entregas.';
  }

  /// «La deuda de $ 1.200 sigue en tu cuenta aunque María esté de baja.»
  static String deudaSigue(String nombre, int saldoCentavos) =>
      'La deuda de ${FormatoBajaPersona.monto(saldoCentavos)} sigue en tu cuenta aunque $nombre esté '
      'de baja.';

  /// «1 de 2»: las entregas hechas sobre el total.
  static String entregas(ResumenCuentaPersona cuenta) =>
      '${cuenta.entregasHechas} de ${cuenta.entregasTotales}';

  // A confirmar: estados que el canvas no dibuja.
  static const entendido = 'Entendido';
  static const reintentar = 'Reintentar';
  static const dandoDeBaja = 'Dando de baja…';
  static String revisando(String nombre) => 'Revisando la cuenta de $nombre…';
  static String noPudimosRevisar(String nombre) =>
      'No pudimos revisar si $nombre tiene saldo. Probá de nuevo.';
  static String noPudimosDarDeBaja(String nombre) =>
      'No pudimos dar de baja a $nombre. Probá de nuevo.';

  // Canvas 32D·04 y 32D·05.
  static const mostrarBajas = 'Mostrar bajas';
  static const reactivar = 'Reactivar';
  static const reactivando = 'Reactivando…';

  static String activaDeNuevo(String nombre) => 'Reactivamos a $nombre.';

  /// «Baja el 22/10», o «Baja el 22/10/2025» si no fue este año; con saldo conocido, «· saldo $ 1.200».
  static String bajaEl(DateTime baja, DateTime ahora, {int? saldoCentavos}) {
    final fecha = FormatoBajaPersona.fechaCorta(baja, ahora);
    final desde = 'Baja el $fecha';
    return saldoCentavos == null || saldoCentavos <= 0
        ? desde
        : '$desde · saldo ${FormatoBajaPersona.monto(saldoCentavos)}';
  }

  // A confirmar: lo que el canvas no dibuja de «Ver bajas».
  static String noPudimosReactivar(String nombre) =>
      'No pudimos reactivar a $nombre. Probá de nuevo.';
  static const noPudimosLeerBajas = 'No pudimos leer las bajas en tu teléfono.';
  static const cargandoBajas = 'Cargando las bajas';
}

/// Cómo se escriben los montos y las fechas de la baja de una persona.
abstract final class FormatoBajaPersona {
  /// «$ 1.200» (canvas 32D): pesos con punto de miles y coma decimal si no son pesos justos; entre el
  /// signo y el número va un espacio que no se parte.
  static String monto(int centavos) {
    final signo = centavos < 0 ? '-' : '';
    final absoluto = centavos.abs();
    final pesos = (absoluto ~/ 100).toString();
    final sueltos = absoluto % 100;
    final conMiles = StringBuffer();
    for (var i = 0; i < pesos.length; i++) {
      if (i > 0 && (pesos.length - i) % 3 == 0) conMiles.write('.');
      conMiles.write(pesos[i]);
    }
    final decimales = sueltos == 0 ? '' : ',${sueltos.toString().padLeft(2, '0')}';
    return '$signo\$ $conMiles$decimales';
  }

  /// «22/10», en hora local; con el año («22/10/2025») si [momento] no es de este año.
  static String fechaCorta(DateTime momento, DateTime ahora) {
    final m = momento.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    final dia = '${dos(m.day)}/${dos(m.month)}';
    return m.year == ahora.toLocal().year ? dia : '$dia/${m.year}';
  }

  /// El nombre con el que se le habla de la persona: solo el nombre de pila (canvas 32D).
  static String nombreDePila(Persona persona) {
    final nombre = persona.nombre.trim();
    return nombre.isEmpty ? 'La persona' : nombre;
  }
}

/// El texto de una falla al escribir sobre una persona: una validación del repositorio dice ella misma
/// qué pasó (la persona ya no está, su espacio está dado de baja); cualquier otra, [porDefecto].
String mensajeDeFallaDePersona(Failure falla, String porDefecto) => switch (falla) {
  FailureValidacion(:final campos) when campos.isNotEmpty => campos.values.first,
  _ => porDefecto,
};
