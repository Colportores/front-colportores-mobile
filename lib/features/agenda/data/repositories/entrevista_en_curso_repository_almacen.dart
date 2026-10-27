import 'dart:convert';

import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/entities/entrevista_en_curso.dart';
import '../../domain/repositories/entrevista_en_curso_repository.dart';
import '../../domain/usecases/registrar_resultado_visita_use_case.dart' show IdsResultadoVisita;

/// [EntrevistaEnCursoRepository] sobre el almacén seguro ([ClaveSegura.entrevistaEnCurso]): un JSON
/// `{"<colportor>": {...ids y hora de inicio...}}`, una entrada por colportora.
///
/// Serializa las operaciones (cada una espera a la anterior), así dos entrevistas de dos colportoras
/// seguidas no se pisan y una lectura pedida después de un guardado en vuelo ve lo nuevo. Una
/// entrada que no se puede leer cuenta como «sin entrevista»: nunca se inventa una, y no se toca
/// el resto. Sin nombres ni direcciones en lo guardado ni en los logs.
final class EntrevistaEnCursoRepositoryAlmacen implements EntrevistaEnCursoRepository {
  EntrevistaEnCursoRepositoryAlmacen(this._almacen);

  final AlmacenSeguro _almacen;

  Future<void> _cola = Future<void>.value();

  Future<T> _encolar<T>(Future<T> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  /// Lo guardado crudo, sin las entradas que no son un mapa. Un JSON roto es «nada».
  Future<Map<String, Object?>> _leerTodo() async {
    final valor = await _almacen.leer(ClaveSegura.entrevistaEnCurso);
    if (valor == null) return {};
    final Object? json;
    try {
      json = jsonDecode(valor);
    } on FormatException {
      return {};
    }
    if (json is! Map<String, dynamic>) return {};
    return {...json};
  }

  Future<void> _escribirTodo(Map<String, Object?> todo) => todo.isEmpty
      ? _almacen.borrar(ClaveSegura.entrevistaEnCurso)
      : _almacen.escribir(ClaveSegura.entrevistaEnCurso, jsonEncode(todo));

  @override
  Future<EntrevistaEnCurso?> leer(String colportorId) => _encolar(() async {
    final todo = await _leerTodo();
    return _deJson(colportorId, todo[colportorId]);
  });

  @override
  Future<void> guardar(EntrevistaEnCurso entrevista) => _encolar(() async {
    final todo = await _leerTodo();
    todo[entrevista.colportorId] = {
      'espacioId': entrevista.espacioId,
      'espacioPersonaId': entrevista.espacioPersonaId,
      'visitaId': entrevista.ids.visita,
      'notaId': entrevista.ids.nota,
      'inicio': entrevista.inicio.toIso8601String(),
      'agendaId': entrevista.agendaId,
      'jornadaId': entrevista.jornadaId,
    };
    await _escribirTodo(todo);
  });

  @override
  Future<void> borrar(String colportorId, {String? idVisita}) => _encolar(() async {
    final todo = await _leerTodo();
    if (!todo.containsKey(colportorId)) return;
    if (idVisita != null) {
      final actual = _deJson(colportorId, todo[colportorId]);
      // Otra entrevista, o una entrada ilegible: no es la que se cerró, no se toca.
      if (actual != null && actual.ids.visita != idVisita) return;
    }
    todo.remove(colportorId);
    await _escribirTodo(todo);
  });

  static EntrevistaEnCurso? _deJson(String colportorId, Object? crudo) {
    if (crudo is! Map<String, dynamic>) return null;
    String? texto(String clave) {
      final valor = crudo[clave];
      return valor is String && valor.trim().isNotEmpty ? valor : null;
    }

    final espacioId = texto('espacioId');
    final espacioPersonaId = texto('espacioPersonaId');
    final visitaId = texto('visitaId');
    final notaId = texto('notaId');
    final inicio = DateTime.tryParse(texto('inicio') ?? '');
    if (espacioId == null ||
        espacioPersonaId == null ||
        visitaId == null ||
        notaId == null ||
        inicio == null) {
      return null;
    }
    return EntrevistaEnCurso(
      colportorId: colportorId,
      espacioId: espacioId,
      espacioPersonaId: espacioPersonaId,
      ids: IdsResultadoVisita(visita: visitaId, nota: notaId),
      inicio: inicio,
      agendaId: texto('agendaId'),
      jornadaId: texto('jornadaId'),
    );
  }
}
