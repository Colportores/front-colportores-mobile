import '../../agenda/domain/entities/visita.dart';
import '../domain/entities/espacio.dart';
import '../domain/entities/estado_casa.dart';
import '../domain/entities/persona.dart';
import '../domain/entities/ubicacion.dart';
import '../domain/entities/ultima_visita_del_espacio.dart';
import 'formato_lista_ubicaciones.dart';
import 'formato_ubicaciones.dart';

/// Los textos de las vistas de personas (32A, alta de persona, y 11·04, los clientes del depto). Los
/// del canvas van tal cual; los que el canvas no dibuja (marcados «a confirmar») dicen qué pasa y qué
/// hacer, y se listan en el PR para que Cristian los apruebe.
abstract final class TextosPersonas {
  // Alta de persona (32A).
  static const altaRotulo = 'NUEVA PERSONA';
  static const altaTitulo = 'Nueva persona';
  static const privacidad = 'Estos datos solo viven en tu celular. Nunca se suben a la nube.';

  /// «No volver a mostrar» del aviso de privacidad (canvas, `Bloques` · banner «lock»; decisión de
  /// Cristian, 23/10, «Aviso privado»). Los dos textos de abajo no están en el canvas (mapa §2: texto):
  /// lo que queda donde estaba el aviso, que dice cómo volver a verlo, y la falla al guardar la
  /// preferencia.
  static const noVolverAMostrar = 'No volver a mostrar';
  static const avisoEscondido =
      'Listo, no vas a ver más este aviso. Para volver a verlo, andá a Configuración y activá '
      '«Mostrar el aviso de privacidad».';
  static const noPudimosGuardarElAviso = 'No pudimos guardar tu elección. Probá de nuevo.';
  static const etiquetaNombre = 'NOMBRE';
  static const etiquetaApellido = 'APELLIDO (OPCIONAL)';
  static const etiquetaTelefono = 'TELÉFONO (OPCIONAL)';
  static const etiquetaNota = 'PRIMERA NOTA (OPCIONAL)';
  static const sugerenciaNombre = 'Obligatorio';
  static const sugerenciaApellido = 'Apellido';
  static const sugerenciaTelefono = '09X XXX XXX';
  static const sugerenciaNota = 'Lo que te sirva para la próxima visita';
  static const guardar = 'Guardar persona';
  static const guardando = 'Guardando…';
  static const reintentar = 'Reintentar';
  static const noPudimosGuardar = 'No pudimos guardar a la persona. Probá de nuevo.';
  static const cerrar = 'Cerrar';
  static const volver = 'Volver';

  /// El aviso que sigue a un alta (canvas 32A·05).
  static String guardada(String nombre) => 'Guardamos a $nombre en este teléfono.';

  // Los clientes del depto (11·04).
  static const agregarCliente = '+ Agregar cliente';
  static const sinTelefono = 'Sin teléfono';
  static const notaDePrivacidad =
      'Los datos de los clientes quedan solo en tu celular. Al coordinador le llega el estado de las '
      'visitas.';

  /// A confirmar: el canvas no dibuja el depto sin clientes, ni el espacio dado de baja, ni la falla
  /// de lectura de esta lista (el de la ficha, 32B·07, dice «No pudimos leer los datos de María en tu
  /// teléfono.»).
  static const sinClientes = 'Todavía no hay clientes';
  static const sinClientesAyuda = 'Los clientes que agregues van a aparecer acá.';
  static const noPudimosLeer = 'No pudimos leer los clientes en tu teléfono.';
  static const espacioNoEncontrado = 'El espacio ya no está en tu teléfono. Volvé a la lista.';
  static const espacioDeBaja =
      'Espacio dado de baja: solo lectura. Podés ver a sus clientes, pero no agregar más.';
  static const cargando = 'Cargando los clientes';

  static String clientes(int cantidad) => 'CLIENTES · $cantidad';

  // El estado de la última visita y «Registrar visita» (11·04, HU-VIS-005, #151).
  static const registrarVisita = 'Registrar visita';

  /// A confirmar (mapa §2: texto): lo que dice el encabezado del depto que todavía no tiene ninguna
  /// visita. El canvas solo dibuja el depto con una entrevista hecha.
  static const sinVisitas = 'Sin visitas todavía';
}

/// Cómo se escribe una persona y su espacio en las vistas de personas.
abstract final class FormatoPersonas {
  /// «Ana Martínez»; solo el nombre si no tiene apellido.
  static String nombreCompleto(Persona persona) {
    final partes = [persona.nombre, persona.apellido].where((p) => p.trim().isNotEmpty);
    return partes.join(' ');
  }

  /// Las iniciales del círculo: la primera letra del nombre y la del apellido, en mayúscula.
  static String iniciales(Persona persona) {
    String primera(String texto) {
      final limpio = texto.trim();
      return limpio.isEmpty ? '' : String.fromCharCode(limpio.runes.first).toUpperCase();
    }

    return '${primera(persona.nombre)}${primera(persona.apellido)}';
  }

  /// «Tel. 099 ••• 412»: el teléfono sin el medio, hasta que se lo toque en la ficha (HU-UBI-009).
  /// «Sin teléfono» si no tiene.
  static String telefonoOculto(String? telefono) {
    final valor = telefono?.trim() ?? '';
    if (valor.isEmpty) return TextosPersonas.sinTelefono;
    final compacto = valor.replaceAll(RegExp(r'[\s().\-]'), '');
    final prefijo = compacto.startsWith('+') ? '+' : '';
    final digitos = compacto.replaceAll(RegExp(r'\D'), '');
    if (digitos.length < 7) {
      final fin = digitos.length <= 2 ? digitos : digitos.substring(digitos.length - 2);
      return 'Tel. ••• $fin';
    }
    final inicio = digitos.substring(0, 3);
    final fin = digitos.substring(digitos.length - 3);
    return 'Tel. $prefijo$inicio ••• $fin';
  }

  /// Lo que dice el lector de pantalla del teléfono de [telefono]: los puntos no se leen bien.
  static String telefonoParaLector(String? telefono) {
    final valor = telefono?.trim() ?? '';
    if (valor.isEmpty) return TextosPersonas.sinTelefono;
    final digitos = valor.replaceAll(RegExp(r'\D'), '');
    final fin = digitos.length <= 3 ? digitos : digitos.substring(digitos.length - 3);
    return 'Teléfono terminado en $fin';
  }

  /// El título del espacio: «Depto 101», «Sin número» (un depto sin número, decisión del 06/10 en
  /// #211: solo en pantalla, el dato sigue nulo), o «Casa» / «Negocio» para su espacio único.
  static String tituloEspacio(Espacio espacio, Ubicacion ubicacion) {
    if (ubicacion.tipo != TipoUbicacion.edificio) return FormatoUbicaciones.tipo(ubicacion.tipo);
    final numero = espacio.numeroDepto?.trim() ?? '';
    return numero.isEmpty ? 'Sin número' : 'Depto $numero';
  }

  /// «Piso 1», o `null` si el espacio no tiene piso.
  static String? pisoDelEspacio(Espacio espacio) {
    final piso = espacio.piso?.trim() ?? '';
    return piso.isEmpty ? null : 'Piso $piso';
  }

  /// «Entrevista hecha · 20/09»: el resultado de la última visita del depto y el día (canvas 11·04). Los
  /// rótulos de «Entrevista hecha», «No contestó» y «Rechazó» son los de la lista (vista 05); «Venta» y
  /// «Cobranza» son los resultados de la HU-VIS-005 (mapa §2: texto: el canvas no los dibuja).
  static String ultimaVisita(UltimaVisitaDelEspacio ultima) {
    final rotulo = switch (ultima.resultado) {
      TipoResultadoVisita.entrevista => FormatoListaUbicaciones.estado(EstadoCasa.entrevistaHecha),
      TipoResultadoVisita.noContesto => FormatoListaUbicaciones.estado(EstadoCasa.noContesto),
      TipoResultadoVisita.rechazo => FormatoListaUbicaciones.estado(EstadoCasa.rechazo),
      TipoResultadoVisita.venta => 'Venta',
      TipoResultadoVisita.cobranza => 'Cobranza',
    };
    return '$rotulo · ${FormatoListaUbicaciones.diaMes(ultima.fecha)}';
  }

  /// «Mataojo 2044 · Depto 3B»: dónde está la persona que se da de alta.
  static String dondeEstaElEspacio(Espacio espacio, Ubicacion ubicacion) {
    final direccion = FormatoUbicaciones.direccion(ubicacion);
    if (ubicacion.tipo != TipoUbicacion.edificio) return direccion;
    return '$direccion · ${tituloEspacio(espacio, ubicacion)}';
  }
}
