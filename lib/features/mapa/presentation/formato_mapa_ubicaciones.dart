import '../domain/entities/estado_casa.dart';
import '../domain/entities/ubicacion.dart';
import 'formato_lista_ubicaciones.dart';

/// Los textos del mapa de ubicaciones (vista 06, HU-UBI-003). Los del canvas están letra por letra;
/// los que el canvas no dibuja (el vacío, el error, «Sin GPS») son propuestas marcadas en el
/// pendiente del issue.
abstract final class TextosMapaUbicaciones {
  // Del canvas (06C·01 a 06C·07).
  static const cercania = 'Cercanía';
  static const cambiarAltura = 'Cambiar altura de la hoja';
  static const referencias = 'Referencias';
  static const miUbicacion = 'Mi ubicación';
  static const nueva = 'Nueva';

  // Seguimiento de la ubicación (#670, decisión de Cristian del 05/11, «GPS viejo»): lo que dice el
  // botón de ubicación según su modo. Son los tres textos del issue; los lee el lector de pantalla
  // y se anuncian al cambiar de modo.
  static const seguimientoLibre = 'Mapa libre';
  static const seguimientoSeguir = 'Seguir mi ubicación';
  static const seguimientoSeguirYGirar = 'Seguir y girar con el teléfono';

  // Vista 41, 41E·03, 03B y 03C (#692): el nombre accesible del botón («Ubicación: Mapa libre»), la
  // brújula que aparece arriba con el mapa girado y el cono que sale del punto del GPS.
  static const ubicacion = 'Ubicación';
  static const brujula = 'Brújula: volver al norte';
  static const brujulaNorte = 'N';
  static const conoOrientacion = 'Hacia dónde apunta el teléfono';

  /// El aviso cuando se corta el seguimiento solo (propuesta: pendiente «mapa §2: texto/aviso»).
  static const seguimientoCortado =
      'Dejamos de seguir tu ubicación: el GPS se apagó o dejó de responder. '
      'Activalo y tocá el botón para volver a seguirte.';
  static const cerrarVistaPrevia = 'Cerrar vista previa';
  static const leyendaSinVisita = 'Sin visita';
  static const leyendaAgrupadas = 'Agrupadas';
  static const leyendaCerca = 'Cerca tuyo: crece y muestra el número';
  static const leyendaTuUbicacion = 'Tu ubicación';

  // Vista 39 (decisión del 23/10, #467): lo que el mapa dibuja y la leyenda no explicaba.
  static const leyendaEdificio = 'Edificio';
  static const leyendaAcercar = 'Al acercar: cada casa muestra su número';
  static const muestraCuadrado = 'Casa con su número de puerta';

  // Lo que dice el lector de pantalla donde el canvas dibuja solo un ícono o un número.
  static const mapa = 'Mapa de ubicaciones';
  static const nuevaUbicacion = 'Nueva ubicación';

  /// El pin para sumar una casa (vista 39, M·01; vista 41): se arrastra al lugar o se toca para
  /// dejarlo en la ubicación de la colportora.
  static const pinCasaNueva = 'Arrastrá para sumar una casa';
  static const pinCasaNuevaPista = 'Tocalo para ponerlo en tu ubicación';
  static const miUbicacionSinGps = 'No disponible: no hay GPS.';
  static const miUbicacionBuscandoGps = 'No disponible: buscando GPS…';
  static const alturaMinimizada = 'Minimizada';
  static const alturaTercio = 'A un tercio de la pantalla';
  static const alturaMitad = 'A la mitad de la pantalla';
  static const vistaPrevia = 'Vista previa';

  // Lo que el canvas no dibuja (propuestas: están en el pendiente del issue).
  static const cerrar = 'Cerrar';
  static const cargando = 'Cargando ubicaciones';
  static const vacioTitulo = 'Todavía no registraste ubicaciones';
  static const vacioCuerpo =
      'Tocá «Nueva» o mantené el dedo sobre el mapa para registrar la primera.';
  static const registrarPrimera = 'Registrar tu primera ubicación';
  static const soloBajasTitulo = 'No tenés ubicaciones activas';
  static const soloBajasCuerpo =
      'Las que están dadas de baja no se muestran en el mapa. Las ves en «Lista».';
  static const registrarUna = 'Registrar una ubicación';
  static const errorLectura = 'No pudimos leer tus ubicaciones.';
  static const reintentar = 'Reintentar';
  static const sinGps = 'Sin GPS no podemos ordenarlas por cercanía.';
  static const buscandoGps = 'Buscando GPS…';
  static const activarGps = 'Activar GPS';
  static const noPudimosAbrirAlta = 'No pudimos abrir «Nueva ubicación». Probá de nuevo.';

  /// Al elegir «usar esa» en el alta con una ubicación que ya registró otro colportor: no es una de
  /// las del colportor, así que el mapa no la muestra ni la elige (decisión del 07/10 en el #294).
  static const ubicacionDeOtroColportor =
      'Esa ubicación ya la registró otro colportor. No hace falta registrarla de nuevo.';
}

/// Lo que el mapa de ubicaciones escribe a partir de las ubicaciones.
abstract final class FormatoMapaUbicaciones {
  /// El número de puerta que va en el marcador de «cerca tuyo»: el de la ubicación, o «s/n» si no
  /// lo tiene (el alta no lo exige).
  static String etiquetaPuerta(Ubicacion ubicacion) {
    final numero = ubicacion.numero?.trim();
    return numero == null || numero.isEmpty ? 's/n' : numero;
  }

  /// El estado de la casa en la vista previa (canvas: «Cobranza pendiente · hoy 15:00»): el rótulo
  /// del estado y, si es una entrevista agendada con hora, cuándo. El detalle de la cobranza (la
  /// cuota y el monto) llega con las ventas y cobros (HU-COB-005).
  static String estadoVistaPrevia(EstadoCasa estado, DateTime? cuando, DateTime ahora) {
    final rotulo = FormatoListaUbicaciones.estado(estado);
    if (estado == EstadoCasa.entrevistaAgendada && cuando != null) {
      return '$rotulo · ${FormatoListaUbicaciones.entrevista(cuando, ahora)}';
    }
    return rotulo;
  }

  /// El lector de pantalla de «Cercanía 12»: «Cercanía, 12 ubicaciones».
  static String cuentaCercania(int? total) => total == null
      ? TextosMapaUbicaciones.cercania
      : '${TextosMapaUbicaciones.cercania}, $total ${total == 1 ? 'ubicación' : 'ubicaciones'}';
}
