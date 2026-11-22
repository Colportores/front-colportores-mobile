// Dobles de la última visita de un espacio (vista 11·04, HU-VIS-005, #151) para los tests de widget.
import 'dart:async';

import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ultima_visita_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/services/lector_ultima_visita_del_espacio.dart';

/// La visita del canvas de 11·04: «Entrevista hecha · 20/09» (a mediodía UTC: el día no cambia en
/// ningún huso razonable).
UltimaVisitaDelEspacio visitaDel20deSeptiembre([
  TipoResultadoVisita resultado = TipoResultadoVisita.entrevista,
]) => UltimaVisitaDelEspacio(resultado: resultado, fecha: DateTime.utc(2026, 9, 20, 12));

/// [LectorUltimaVisitaDelEspacio] que dice lo que se le programa y puede cambiar después, como lo haría
/// la tabla `visita` al registrar o deshacer una visita.
final class LectorUltimaVisitaFalso implements LectorUltimaVisitaDelEspacio {
  LectorUltimaVisitaFalso([this._actual]);

  UltimaVisitaDelEspacio? _actual;
  final _cambios = StreamController<UltimaVisitaDelEspacio?>.broadcast();

  /// Cuántas veces la pantalla pidió leer.
  var lecturas = 0;

  /// Registra una visita nueva (o `null`: la deshacen): la pantalla se entera.
  void cambiarA(UltimaVisitaDelEspacio? nueva) {
    _actual = nueva;
    _cambios.add(nueva);
  }

  @override
  Stream<UltimaVisitaDelEspacio?> observar(String espacioId) async* {
    lecturas++;
    yield _actual;
    yield* _cambios.stream;
  }
}

/// [LectorUltimaVisitaDelEspacio] que nunca contesta (la lectura sigue en curso).
final class LectorUltimaVisitaCargando implements LectorUltimaVisitaDelEspacio {
  @override
  Stream<UltimaVisitaDelEspacio?> observar(String espacioId) =>
      StreamController<UltimaVisitaDelEspacio?>().stream;
}

/// [LectorUltimaVisitaDelEspacio] cuya lectura falla.
final class LectorUltimaVisitaQueFalla implements LectorUltimaVisitaDelEspacio {
  @override
  Stream<UltimaVisitaDelEspacio?> observar(String espacioId) =>
      Stream.error(StateError('no se pudo leer'));
}
