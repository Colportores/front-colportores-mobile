import '../../mapa/domain/services/criterio_duplicado_ubicacion.dart';
import '../../mapa/presentation/textos_personas.dart' show FormatoPersonas;
import '../domain/entities/persona_para_vender.dart';

/// Una fila de la lista «¿A quién le vendés?»: la persona y lo que se escribe de ella.
///
/// **local-only — PII**: ver `PersonaParaVender`.
final class FilaDePersonaParaVender {
  FilaDePersonaParaVender(this.origen)
    : nombre = FormatoPersonas.nombreCompleto(origen.persona),
      direccion = FormatoPersonas.dondeEstaElEspacio(origen.espacio, origen.ubicacion),
      _claveNombre = CriterioDuplicadoUbicacion.normalizar(
        FormatoPersonas.nombreCompleto(origen.persona),
      ),
      _claveApellido = CriterioDuplicadoUbicacion.normalizar(origen.persona.apellido),
      _claveDireccion = CriterioDuplicadoUbicacion.normalizar(
        FormatoPersonas.dondeEstaElEspacio(origen.espacio, origen.ubicacion),
      );

  final PersonaParaVender origen;

  /// «María Fernández».
  final String nombre;

  /// «Mataojo 2044 · Depto 3B».
  final String direccion;

  final String _claveNombre;
  final String _claveApellido;
  final String _claveDireccion;

  String get espacioPersonaId => origen.espacioPersonaId;

  bool _tieneTodo(List<String> terminos) {
    final conjunto = '$_claveNombre $_claveDireccion';
    return terminos.every(conjunto.contains);
  }

  bool _empiezaCon(String consulta) =>
      _claveNombre.startsWith(consulta) ||
      _claveApellido.startsWith(consulta) ||
      _claveDireccion.startsWith(consulta);

  @override
  String toString() => 'FilaDePersonaParaVender(${origen.espacioPersonaId})';
}

/// Arma la lista «¿A quién le vendés?» (la pestaña Ventas, «+ Registrar venta»): busca por nombre o
/// por dirección y ordena.
///
/// - Sin búsqueda: de la A a la Z por nombre.
/// - Con búsqueda: entran las personas cuyo nombre o dirección tienen **todas** las palabras escritas
///   (sin distinguir mayúsculas ni tildes). Primero las que **empiezan** con lo escrito (el nombre, el
///   apellido o la dirección), después las demás; dentro de cada grupo, de la A a la Z.
abstract final class ListadoDePersonasParaVender {
  static List<FilaDePersonaParaVender> armar(
    Iterable<PersonaParaVender> personas, {
    String busqueda = '',
  }) {
    final consulta = CriterioDuplicadoUbicacion.normalizar(busqueda);
    final terminos = consulta.isEmpty ? const <String>[] : consulta.split(' ');
    final todas = [for (final p in personas) FilaDePersonaParaVender(p)];
    final filas = terminos.isEmpty
        ? todas
        : [
            for (final f in todas)
              if (f._tieneTodo(terminos)) f,
          ];

    int porNombre(FilaDePersonaParaVender a, FilaDePersonaParaVender b) {
      final nombre = a._claveNombre.compareTo(b._claveNombre);
      if (nombre != 0) return nombre;
      final direccion = a._claveDireccion.compareTo(b._claveDireccion);
      return direccion != 0 ? direccion : a.espacioPersonaId.compareTo(b.espacioPersonaId);
    }

    if (consulta.isEmpty) return filas..sort(porNombre);
    final primeras = [
      for (final f in filas)
        if (f._empiezaCon(consulta)) f,
    ]..sort(porNombre);
    final otras = [
      for (final f in filas)
        if (!f._empiezaCon(consulta)) f,
    ]..sort(porNombre);
    return [...primeras, ...otras];
  }
}
