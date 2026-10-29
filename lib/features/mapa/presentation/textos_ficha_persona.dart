import '../../agenda/domain/entities/visita.dart' show TipoResultadoVisita;
import '../domain/entities/contexto_notas_persona.dart';
import '../domain/entities/ficha_de_persona.dart';
import '../domain/entities/nota_persona.dart';
import 'textos_baja_persona.dart';
import 'textos_notas.dart';

/// Los textos de la ficha de una persona (vista 32B, HU-UBI-009). Los del canvas van tal cual; los que
/// el canvas no dibuja (marcados «a confirmar») dicen qué pasa y qué hacer, y se listan en el PR para
/// que Cristian los apruebe.
abstract final class TextosFicha {
  // Canvas 32B·01 a 32B·08.
  static const rotulo = 'PERSONA';
  static const ver = 'Ver';
  static const llamar = 'Llamar';
  static const seVuelveAOcultar = 'Se vuelve a ocultar al salir';
  static const sinTelefono = 'Sin teléfono';
  static const agregarTelefono = 'Agregar';
  static const notasRotulo = 'NOTAS · SOLO EN TU TELÉFONO';
  static const masNota = '+ Nota';
  static const historial = 'HISTORIAL';
  static const sinHistorialTitulo = 'Todavía no hay visitas ni ventas';
  static const registrarVisita = 'Registrar visita';
  static const reintentar = 'Reintentar';
  static const reactivar = 'Reactivar';
  static const reactivarDepto = 'Reactivar el depto';
  static const comprado = TextosBajaPersona.comprado;
  static const entregado = TextosBajaPersona.entregado;
  static const pagado = TextosBajaPersona.pagado;
  static const saldo = TextosBajaPersona.saldo;

  /// «Sin movimientos aún» (HU-UBI-009): la cuenta de quien no tiene nada que mostrar.
  static const sinMovimientos = 'Sin movimientos aún';

  // Menú «⋯» (decisiones del 26/10 en #405: la baja sale de acá, y la edición también).
  static const masOpciones = 'Más opciones';
  static const editarPersona = 'Editar persona';
  static const darDeBaja = 'Dar de baja';

  // A confirmar: lo que el canvas no dibuja.
  static const volver = 'Volver';
  static const cerrar = 'Cerrar';
  static const personaNoEncontrada = 'La persona ya no está en tu teléfono. Volvé atrás.';
  static const noPudimosAbrirElTelefono =
      'No pudimos abrir el teléfono de tu celular. Tocá «Ver» para ver el número y llamar a mano.';
  static const noPudimosReactivarElDepto = 'No pudimos reactivar el depto. Probá de nuevo.';
  static const noPudimosAbrir = 'No pudimos abrir esa pantalla. Probá de nuevo.';
  static const sinNotas = TextosNotas.sinNotas;
  static const reactivando = 'Reactivando…';

  static String ayudaSinHistorial(String nombre) => 'Lo que registres con $nombre aparece acá.';

  static String verNotas(int cantidad) => 'Ver ($cantidad)';

  static String verMas(int faltan) => 'Ver más ($faltan)';

  static String cargando(String? nombre) => nombre == null || nombre.trim().isEmpty
      ? 'Cargando la ficha'
      : 'Cargando la ficha de $nombre';

  /// 32B·07: «No pudimos leer los datos de María en tu teléfono.».
  static String noPudimosLeer(String? nombre) => nombre == null || nombre.trim().isEmpty
      ? 'No pudimos leer los datos de la persona en tu teléfono.'
      : 'No pudimos leer los datos de $nombre en tu teléfono.';

  static String noPudimosReactivar(String nombre) => TextosBajaPersona.noPudimosReactivar(nombre);

  /// Los avisos de solo lectura (32B·04 y 32B·08). Los del canvas, con la persona de baja dicha sin
  /// género («de baja», como las notas: mapa §2 de #144) y el aviso del depto como lo decidió Cristian
  /// el 23/10 («Depto baja»: solo lectura, con «Reactivar el depto»).
  static String avisoSoloLectura(ContextoNotasPersona contexto, DateTime ahora) {
    final nombre = contexto.nombre;
    return switch (contexto.causa) {
      CausaSoloLectura.personaDeBaja => () {
        final desde = contexto.bajaDesde;
        final cuando = desde == null ? '' : ' desde el ${FormatoNotas.diaMes(desde, ahora)}';
        return '$nombre está de baja$cuando. Podés ver su historial, pero no registrar nada.';
      }(),
      CausaSoloLectura.espacioDeBaja => () {
        final depto = contexto.numeroDepto;
        final donde = contexto.direccion;
        final lugar = depto != null && donde != null
            ? 'El depto $depto de $donde está dado de baja.'
            : donde != null
            ? 'El espacio de $donde está dado de baja.'
            : depto != null
            ? 'El depto $depto está dado de baja.'
            : 'El espacio de $nombre está dado de baja.';
        return '$lugar La ficha queda en solo lectura.';
      }(),
      CausaSoloLectura.sinEspacioActivo =>
        '$nombre ya no está en ningún depto activo. La ficha queda en solo lectura.',
      null => '',
    };
  }
}

/// Cómo se escriben el teléfono, el historial y las notas de la ficha.
abstract final class FormatoFicha {
  static const _dias = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];

  /// El largo de la vista previa de una nota (HU-UBI-009: «notas muy largas: las primeras 200
  /// caracteres»).
  static const largoDeLaVistaPrevia = 200;

  static String _digitos(String telefono) => telefono.replaceAll(RegExp(r'\D'), '');

  /// Un celular uruguayo de 9 dígitos con el 0 adelante («099 123 456»): se lo escribe como el canvas,
  /// «+598 99 123 456».
  static bool _esCelularUruguayo(String telefono) {
    final valor = telefono.trim();
    final digitos = _digitos(valor);
    return !valor.startsWith('+') && digitos.length == 9 && digitos.startsWith('0');
  }

  /// «+598 99 123 456»; cualquier otro número, como lo escribió la colportora.
  static String telefonoCompleto(String telefono) {
    final valor = telefono.trim();
    if (!_esCelularUruguayo(valor)) return valor;
    final d = _digitos(valor);
    return '+598 ${d.substring(1, 3)} ${d.substring(3, 6)} ${d.substring(6, 9)}';
  }

  /// «+598 99 *** 456»: lo que se ve hasta tocar «Ver» (HU-UBI-009, riesgo R23). Otro número muestra los
  /// dos primeros y los tres últimos dígitos; uno demasiado corto, solo «***».
  static String telefonoEnmascarado(String telefono) {
    final valor = telefono.trim();
    final d = _digitos(valor);
    if (_esCelularUruguayo(valor)) return '+598 ${d.substring(1, 3)} *** ${d.substring(6, 9)}';
    if (d.length <= 5) return '***';
    final mas = valor.startsWith('+') ? '+' : '';
    return '$mas${d.substring(0, 2)} *** ${d.substring(d.length - 3)}';
  }

  /// Lo que dice el lector de pantalla del teléfono: con el número entero solo si se lo mostró.
  static String telefonoParaLector(String telefono, {required bool visible}) {
    if (visible) return 'Teléfono ${telefonoCompleto(telefono)}';
    final d = _digitos(telefono);
    final fin = d.length <= 3 ? d : d.substring(d.length - 3);
    return 'Teléfono terminado en $fin';
  }

  /// Las primeras 200 caracteres de una nota, con «…» si se cortó.
  static String vistaPrevia(String texto) {
    final limpio = texto.trim();
    final runas = limpio.runes.toList();
    if (runas.length <= largoDeLaVistaPrevia) return limpio;
    return '${String.fromCharCodes(runas.take(largoDeLaVistaPrevia)).trimRight()}…';
  }

  /// «HOY 14:20 · 1 DE 2»: cuándo se escribió la última nota y cuántas hay.
  static String rotuloDeLaNota(NotaPersona nota, int total, DateTime ahora) =>
      '${FormatoNotas.fecha(nota, ahora)} · 1 DE $total';

  static String _dia(DateTime fecha, DateTime ahora) => FormatoBajaPersona.fechaCorta(fecha, ahora);

  /// El resultado de una visita: «Entrevista hecha», «No contestó»…
  static String resultadoDeVisita(TipoResultadoVisita resultado) => switch (resultado) {
    TipoResultadoVisita.venta => 'Venta',
    TipoResultadoVisita.entrevista => 'Entrevista hecha',
    TipoResultadoVisita.cobranza => 'Cobranza',
    TipoResultadoVisita.rechazo => 'Rechazó',
    TipoResultadoVisita.noContesto => 'No contestó',
  };

  static String _lineas(List<LineaDeFicha> lineas, {required bool siempreCantidad}) => lineas
      .map((l) => siempreCantidad || l.cantidad > 1 ? '${l.nombre} × ${l.cantidad}' : l.nombre)
      .join(' + ');

  /// La línea chica de arriba de un movimiento: «20/10 · COBRO», «SÁB 26/10 · ENTREGA PENDIENTE».
  static String antetitulo(MovimientoDeFicha m, DateTime ahora) {
    final local = m.fecha.toLocal();
    final dia = _dia(m.fecha, ahora);
    return switch (m) {
      VisitaEnFicha() => '$dia · VISITA',
      VentaEnFicha(:final numeroTalonario) => '$dia · VENTA $numeroTalonario',
      CobroEnFicha() => '$dia · COBRO',
      EntregaEnFicha(pendiente: true) => '${_dias[local.weekday - 1]} $dia · ENTREGA PENDIENTE',
      EntregaEnFicha() => '$dia · ENTREGA',
    };
  }

  /// El título de un movimiento: «Entrevista hecha», «Salud y Hogar + Nuestros Hijos», «$ 600 en
  /// efectivo», «Nuestros Hijos × 1».
  static String titulo(MovimientoDeFicha m) => switch (m) {
    VisitaEnFicha(:final resultado) => resultadoDeVisita(resultado),
    VentaEnFicha(:final lineas) =>
      lineas.isEmpty ? 'Venta' : _lineas(lineas, siempreCantidad: false),
    CobroEnFicha(:final montoCentavos, :final efectivo) =>
      efectivo
          ? '${FormatoBajaPersona.monto(montoCentavos)} en efectivo'
          : FormatoBajaPersona.monto(montoCentavos),
    EntregaEnFicha(:final lineas) =>
      lineas.isEmpty ? 'Entrega' : _lineas(lineas, siempreCantidad: true),
  };

  /// La línea de abajo: el monto de una venta, «Venta 0042» de un cobro. `null` si no hay.
  static String? subtitulo(MovimientoDeFicha m) => switch (m) {
    VentaEnFicha(:final montoCentavos) => FormatoBajaPersona.monto(montoCentavos),
    CobroEnFicha(:final numeroTalonario) =>
      numeroTalonario == null ? null : 'Venta $numeroTalonario',
    _ => null,
  };

  /// Lo que lee el lector de pantalla de un movimiento, de una vez.
  static String paraLector(MovimientoDeFicha m, DateTime ahora) {
    final sub = subtitulo(m);
    return [antetitulo(m, ahora), titulo(m), ?sub].join('. ');
  }
}
