import '../domain/entities/espacio.dart';
import '../domain/entities/estado_casa.dart';
import '../domain/entities/lista_ubicaciones.dart';
import '../domain/entities/resumen_del_depto.dart';
import '../domain/entities/ubicacion.dart' show TipoUbicacion;
import '../domain/services/cercania_de_la_casa.dart';
import 'formato_baja.dart';
import 'formato_espacios.dart' show TextosEspacios;
import 'formato_lista_ubicaciones.dart';
import 'formato_mapa_ubicaciones.dart';
import 'formato_ubicaciones.dart';
import 'widgets/estados_hoja_casa.dart';

/// Los textos de la hoja de la casa (vista 39, C·01 «Tocar una casa: resumen»). Los del canvas van
/// letra por letra; los que el canvas no dibuja están marcados «a confirmar» y se listan en el PR.
abstract final class TextosHojaCasa {
  // Del canvas (C·01).
  static const notaDelLugar = 'NOTA DEL LUGAR';
  static const registrarVisita = 'Registrar visita';
  static const cobrar = r'$ Cobrar';

  /// El tilde del botón, que el canvas escribe delante del rótulo con dos espacios: «✓  Registrar
  /// visita». Es decoración: el lector de pantalla solo dice [registrarVisita].
  static const tildeDelBoton = '✓';

  /// El rótulo del botón junto a la dirección (decisión de Cristian, 04/11, «Editar casa», #652; el
  /// rótulo sigue el tipo, decisión del 05/11): «Editar casa», «Editar edificio» o «Editar negocio»,
  /// como en la hoja de la Lista. Abre la edición de la ubicación (vista 07). El canvas de la 39 no lo
  /// dibuja; manda la decisión.
  static String editar(TipoUbicacion tipo) => TextosEspacios.editarUbicacion(tipo);

  /// Lo que lee el lector de pantalla del botón: lleva la dirección, porque la hoja puede estar
  /// debajo de otras acciones y el rótulo solo no dice cuál.
  static String editarDe(TipoUbicacion tipo, String direccion) =>
      direccion.trim().isEmpty ? editar(tipo) : '${editar(tipo)}: $direccion';

  /// A confirmar (mapa §2: texto): lo que dice la hoja si el destino de «Registrar visita» o de
  /// «$ Cobrar» no se pudo abrir. El canvas no dibuja el error.
  static const noPudimosAbrirVisita = 'No pudimos abrir «Registrar visita». Probá de nuevo.';
  static const noPudimosAbrirCobro = 'No pudimos abrir «\$ Cobrar». Probá de nuevo.';

  /// Lo que lee el lector de pantalla del botón de cobrar de [nombre]: lleva el rótulo visible
  /// «$ Cobrar» y a quién (hay una fila por persona).
  static String cobrarA(String nombre) => '$cobrar a $nombre';

  /// «Debe $ 1.200» (el canvas no usa «$U» en la 39).
  static String debe(int centavos) => 'Debe ${monto(centavos)}';

  /// «Debe $ 1.200 · cuota sáb 26/10» (canvas C·01): lo que debe y el día de la cuota que toca. Si la
  /// cuota ya venció (su día quedó atrás) dice «Debe $ 1.200 · cuota vencida el 02/11».
  ///
  /// A confirmar (mapa §2: texto): el canvas dibuja solo la cuota que viene; la vencida la dice con las
  /// palabras del aviso de 30A-06 («La cuota 2 venció el 02/11»), sin el número porque la persona
  /// puede tener cuotas de varias ventas.
  static String debeConCuota(int centavos, DateTime cuota, DateTime ahora) =>
      cuotaVencida(cuota, ahora)
      ? '${debe(centavos)} · cuota vencida el ${FormatoListaUbicaciones.diaMes(cuota)}'
      : '${debe(centavos)} · cuota ${FormatoListaUbicaciones.diaSemanaYMes(cuota)}';

  /// La cuota venció: su día ya pasó («venció» se mide por día: la cuota de hoy todavía no venció).
  static bool cuotaVencida(DateTime cuota, DateTime ahora) =>
      FormatoListaUbicaciones.diasDeCalendario(cuota, ahora) > 0;

  /// «$ 1.200»: pesos con punto de miles y, si no son pesos justos, coma decimal.
  static String monto(int centavos) => FormatoBaja.monto(centavos).replaceFirst(r'$U', r'$');
}

/// Los textos de la hoja de la casa arriba (vista 39, C·02 «Hoja arriba · Personas»). Los del canvas van
/// letra por letra; los que el canvas no dibuja están marcados «a confirmar» (mapa §2: texto) y se
/// listan en el PR.
abstract final class TextosPestanasHojaCasa {
  // Del canvas (C·02).
  static const personas = 'Personas';
  static const historial = 'Historial';
  static const notas = 'Notas';
  static const agregarPersona = '+ Agregar persona';

  /// A confirmar: el canvas no dibuja la pestaña sin personas. Con «+ Agregar persona» abajo, el
  /// texto solo dice que no hay.
  static const sinPersonas = 'Todavía no hay personas acá.';

  /// Debajo de [sinPersonas] cuando se puede agregar: anotar a la persona no es un paso obligatorio
  /// (decisión de Cristian, 04/11: el nombre es opcional). Texto propuesto (mapa §2: texto/aviso).
  static const sinPersonasParaDespues = 'Podés sumar a alguien ahora o dejarlo para después.';

  /// A confirmar: lo que dice la hoja si no se pudo abrir el alta de persona o la ficha. El canvas no
  /// dibuja el error.
  static const noPudimosAbrirAlta = 'No pudimos abrir «Agregar persona». Probá de nuevo.';
  static const noPudimosAbrirFicha = 'No pudimos abrir la ficha. Probá de nuevo.';

  /// «Entrevista dada el 05/10» (canvas): la línea de la persona que no debe nada y tuvo una
  /// entrevista.
  static String entrevistaDada(DateTime fecha) =>
      'Entrevista dada el ${FormatoListaUbicaciones.diaMes(fecha)}';
}

/// Cómo se escribe la hoja de la casa a partir de la ubicación y su contexto.
abstract final class FormatoHojaCasa {
  /// El nombre de la casa con el marcador ⇢ cuando ya no hay nada que cobrar (P1 de #687).
  static const entregaPendiente = 'Entrega pendiente';

  /// La línea chica debajo de la dirección (canvas: «Casa · Cobranza pendiente · a 20 m de vos»): el
  /// tipo, el estado si se sabe (nunca uno que no se sabe) y la distancia si hay GPS. Una casa dada de
  /// baja dice «Casa · dada de baja el 18/10» y no su estado (E·04).
  ///
  /// [sinSaldo]: ninguna persona de la casa debe nada. Con el marcador ⇢ («Entrega y pago») y sin
  /// saldo, lo único pendiente es entregar: el nombre dice «Entrega pendiente» (decisión del 10/11, P1
  /// de #687; el marcador y la leyenda no cambian).
  static String subtitulo(ItemListaUbicacion item, DateTime ahora, {bool sinSaldo = false}) {
    final ubicacion = item.ubicacion;
    final baja = ubicacion.auditoria.deletedAt;
    if (item.esBaja && baja != null) {
      return TextosEstadosHojaCasa.subtituloDeBaja(ubicacion.tipo, baja);
    }
    final estado = item.estado;
    final distancia = item.distanciaMetros;
    // Con el aviso «Estás a 650 m de esta casa.» (E·05) el subtítulo no repite la distancia: el canvas lo
    // deja en «Casa · Cobranza pendiente» (decisión del 29/10, #541 P2). Sin aviso, «a 20 m de vos».
    final lejos = CercaniaDeLaCasa.estaLejos(distancia);
    final partes = [
      FormatoUbicaciones.tipo(ubicacion.tipo),
      if (estado == EstadoCasa.entregaYPago && sinSaldo)
        entregaPendiente
      else if (estado != null)
        FormatoMapaUbicaciones.estadoVistaPrevia(estado, item.proximaEntrevista, ahora),
      if (!lejos && distancia != null && FormatoUbicaciones.distancia(distancia).isNotEmpty)
        'a ${FormatoUbicaciones.distancia(distancia)} de vos',
    ];
    return partes.join(' · ');
  }
}

/// Los textos de los deptos en la hoja de la casa (vista 39, N·04, N·06, C·09 y C·10). Los del canvas
/// van letra por letra; los que el canvas no dibuja (vacío, error, volver) están marcados «a confirmar»
/// (mapa §2: texto) y se listan en el PR.
abstract final class TextosDeptosDeLaCasa {
  // Del canvas (N·04, N·06 y C·09).
  static const deptos = 'DEPTOS';
  static const agregarDepto = '+ Agregar depto';
  static const agregarDeptoTarjeta = 'Agregar depto';
  static const numeroYPiso = 'Número y piso';
  static const sumaLosDeptos = 'Sumá los deptos que vas a visitar. El resto, cuando llegues.';
  static const seguir = 'Seguir';
  static const recienRegistrado = 'recién registrado';
  static const personas = 'PERSONAS';
  static const agregarPersona = '+ Agregar';

  /// «Edificio en Grecia 3307» (N·04).
  static String edificioEn(String direccion) => 'Edificio en $direccion';

  /// «6 DEPTOS» (C·09); «1 DEPTO» con uno.
  static String cantidad(int total) => total == 1 ? '1 DEPTO' : '$total DEPTOS';

  /// A confirmar: el canvas no dibuja el edificio sin deptos (C·09 vacío).
  static const sinDeptos = 'Todavía no hay deptos.';
  static const sinDeptosQueHacer = 'Tocá «+ Agregar depto» para sumar los que vas a visitar.';

  /// A confirmar: lo que dice la hoja si no puede leer los deptos (como la vista 11).
  static const errorLectura = 'No pudimos leer los deptos de tu teléfono. Probá de nuevo.';
  static const reintentar = 'Reintentar';

  /// A confirmar: lo que dice la hoja si no se pudo abrir el alta del depto (N·05).
  static const noPudimosAbrirAlta = 'No pudimos abrir «Agregar depto». Probá de nuevo.';

  /// Lo que lee el lector de pantalla de la flecha «‹» de C·10, que vuelve a la lista de deptos.
  static const volverALosDeptos = 'Volver a los deptos';
}

/// Cómo se escriben los deptos en la hoja de la casa (vista 39, C·09 y C·10).
abstract final class FormatoDeptosDeLaCasa {
  /// La línea debajo de la dirección de un edificio (C·09: «Edificio · 6 deptos · a 35 m de vos»; N·06:
  /// «Edificio · 3 deptos · recién registrado»). Sin la cuenta (todavía se lee) va solo el tipo. Un
  /// edificio dado de baja dice lo mismo que la casa (E·04).
  static String subtitulo(
    ItemListaUbicacion item, {
    required int? cantidad,
    required bool recienRegistrado,
  }) {
    final ubicacion = item.ubicacion;
    final baja = ubicacion.auditoria.deletedAt;
    if (item.esBaja && baja != null) {
      return TextosEstadosHojaCasa.subtituloDeBaja(ubicacion.tipo, baja);
    }
    final distancia = item.distanciaMetros;
    final lejos = CercaniaDeLaCasa.estaLejos(distancia);
    return [
      FormatoUbicaciones.tipo(ubicacion.tipo),
      if (cantidad != null) TextosEspacios.cantidad(cantidad),
      if (recienRegistrado)
        TextosDeptosDeLaCasa.recienRegistrado
      else if (!lejos && distancia != null && FormatoUbicaciones.distancia(distancia).isNotEmpty)
        'a ${FormatoUbicaciones.distancia(distancia)} de vos',
    ].join(' · ');
  }

  /// La línea de abajo de la fila de un depto.
  ///
  /// - Recién registrado (N·04): el piso, «Piso 1»; eligiendo el depto (N·06), el piso y el estado,
  ///   «Piso 1 · Sin visita».
  /// - En un edificio que ya estaba (C·09), el estado y cuándo: «No contestó · ayer», «Entrevista
  ///   agendada · jue 24/10 10:00» (la misma forma que la hoja de la casa), «Cobranza pendiente». A
  ///   confirmar: el canvas escribe «Entrevista jue 24/10 10:00»; va el rótulo del estado, como en la
  ///   hoja de la casa y la Lista.
  ///
  /// Sin [resumen] (no se pudo leer) no dice estado: no se afirma lo que no se sabe.
  static String detalle(
    Espacio espacio,
    ResumenDelDepto? resumen,
    DateTime ahora, {
    required bool recienRegistrado,
    bool conEstado = true,
  }) {
    final piso = _piso(espacio, mayuscula: true);
    if (recienRegistrado) {
      return [
        ?piso,
        if (conEstado && resumen != null) FormatoListaUbicaciones.estado(resumen.estado),
      ].join(' · ');
    }
    if (resumen == null) return piso ?? '';
    return estadoDelDepto(resumen, ahora);
  }

  /// El estado del depto y cuándo, como la línea de la hoja de la casa: con una entrevista agendada,
  /// cuándo es; con un resultado de visita (no contestó, rechazo, entrevista hecha), cuándo fue.
  static String estadoDelDepto(ResumenDelDepto resumen, DateTime ahora) {
    final estado = resumen.estado;
    final rotulo = FormatoMapaUbicaciones.estadoVistaPrevia(
      estado,
      resumen.proximaEntrevista,
      ahora,
    );
    final ultima = resumen.ultimaVisita;
    final deVisita = switch (estado) {
      EstadoCasa.noContesto || EstadoCasa.rechazo || EstadoCasa.entrevistaHecha => true,
      _ => false,
    };
    return deVisita && ultima != null
        ? '$rotulo · ${FormatoListaUbicaciones.hace(ultima, ahora)}'
        : rotulo;
  }

  /// El título de la hoja con el depto elegido (C·10): «Grecia 3313 · Depto 3B».
  static String tituloDelDepto(String direccion, Espacio espacio) => direccion.trim().isEmpty
      ? TextosEspacios.depto(espacio)
      : '$direccion · ${TextosEspacios.depto(espacio)}';

  /// La línea de abajo con el depto elegido (C·10): «Cobranza pendiente · piso 3». Sin el resumen,
  /// solo el piso.
  static String subtituloDelDepto(Espacio espacio, ResumenDelDepto? resumen, DateTime ahora) => [
    if (resumen != null) estadoDelDepto(resumen, ahora),
    ?_piso(espacio, mayuscula: false),
  ].join(' · ');

  static String? _piso(Espacio espacio, {required bool mayuscula}) {
    final piso = espacio.piso?.trim() ?? '';
    if (piso.isEmpty) return null;
    return '${mayuscula ? 'Piso' : 'piso'} $piso';
  }
}
