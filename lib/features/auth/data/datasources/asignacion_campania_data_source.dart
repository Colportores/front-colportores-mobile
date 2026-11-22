import '../../../../core/database/dia_de_calendario.dart';
import '../../domain/entities/asignacion_campania.dart';
import '../../domain/services/situacion_de_campania.dart';
import 'campanias_inscriptas_data_source.dart';

/// De dónde sale la campaña y la zona a las que se asignó al colportor (vista 18, 18-A07 «Ya te
/// asignaron»): decisión de Cristian (02/10), el dato sale del pull de `campania_colportor`, sin
/// endpoint.
abstract interface class AsignacionCampaniaDataSource {
  /// `null` si no se conoce la asignación. Lanza `SinConexionException` o `ServidorException`
  /// (`auth_remote_data_source.dart`) si no se pudo consultar.
  Future<AsignacionCampania?> consultar();
}

/// [AsignacionCampaniaDataSource] sobre las réplicas locales del pull de catálogos
/// ([CampaniasInscriptasDataSource]): lee solo del teléfono, sin red, la campaña en curso o, si no
/// hay, la que empieza primero.
///
/// Nunca inventa: sin sesión, sin inscripciones o sin saber todavía (el pull no trajo la campaña) es
/// `null`, y la pantalla sale sin los renglones de campaña y zona. Con la inscripción pero sin zona
/// (o con la zona todavía sin bajar) devuelve solo la campaña.
final class AsignacionCampaniaLocal implements AsignacionCampaniaDataSource {
  AsignacionCampaniaLocal(this._campanias, {required this.usuarioId, DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final CampaniasInscriptasDataSource _campanias;

  /// El colportor con la sesión abierta, o `null` si no hay.
  final String? Function() usuarioId;
  final DateTime Function() _ahora;

  @override
  Future<AsignacionCampania?> consultar() async {
    final usuario = usuarioId();
    if (usuario == null) return null;
    final inscripciones = await _campanias.observar(usuario).first;
    if (inscripciones == null) return null;
    final campania = SituacionDeCampania.vigenteOProxima(
      inscripciones,
      hoy: diaDeCalendario(_ahora()),
    );
    if (campania == null) return null;
    return AsignacionCampania(
      campania: campania.nombre,
      zona: _sinPrefijo(campania.zona),
      ciudad: campania.ciudad,
    );
  }

  /// El nombre de la zona sin el prefijo «Zona» (la pantalla lo pone): «Zona Centro» → «Centro».
  static String? _sinPrefijo(String? zona) {
    if (zona == null) return null;
    final limpia = zona.replaceFirst(RegExp(r'^zona\s+', caseSensitive: false), '').trim();
    return limpia.isEmpty ? zona : limpia;
  }
}
