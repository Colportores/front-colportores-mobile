import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/aviso_zona.dart';
import '../../domain/entities/inscripcion_con_zona.dart';
import '../../domain/services/detector_avisos_zona.dart';
import 'avisos_zona_providers.dart';

part 'avisos_zona_notifier.g.dart';

/// Los avisos de zona pendientes del colportor [usuarioId] (HU-CAM-006, #251): «Te asignaron la
/// zona `zona` en `campaña`.» y «Ya no tenés zona en `campaña`.». Se arman al abrirse la pantalla
/// principal y cada vez que un pull termina de escribir las inscripciones, comparando lo que hay en
/// el teléfono contra lo que ya se avisó ([DetectorAvisosZona]). No hay push.
///
/// Un aviso se queda hasta que la persona lo cierra ([cerrar]); recién ahí se anota como avisado.
/// Si la app se cierra antes, el aviso vuelve a salir al abrirla. Todo falla hacia «avisar de más»:
/// si el almacén no deja anotar, el aviso puede repetirse en otra sesión, nunca perderse.
@riverpod
class AvisosZona extends _$AvisosZona {
  Future<void> _cola = Future<void>.value();

  /// Lo que la persona cerró en esta sesión, anotado o no: aunque el almacén falle, un aviso
  /// cerrado no vuelve a salir hasta que la zona cambie de nuevo.
  final _cerradas = <String, String?>{};

  @override
  List<AvisoZona> build(String usuarioId) {
    final fuente = ref.watch(inscripcionesConZonaDataSourceProvider);
    final suscripcion = fuente
        .observar(usuarioId)
        .listen(
          (inscripciones) => unawaited(_encolar(() => _procesar(inscripciones))),
          onError: (Object error) => AppLogger.instance.warn(
            LogModulo.auth,
            'ZONA_AVISO_LEER',
            'no se pudieron leer las inscripciones para el aviso de zona',
            {'error': error.runtimeType.toString()},
          ),
        );
    ref.onDispose(() => unawaited(suscripcion.cancel()));
    return const [];
  }

  /// Ejecuta las operaciones **en el orden en que llegan**: dos pulls seguidos, o un cierre en
  /// medio de un pull, no se pisan.
  Future<void> _encolar(Future<void> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  Future<void> _procesar(List<InscripcionConZona> inscripciones) async {
    try {
      final repositorio = ref.read(zonasAvisadasRepositoryProvider);
      final avisadas = {...await repositorio.leer(), ..._cerradas};
      final resultado = DetectorAvisosZona.detectar(avisadas: avisadas, actuales: inscripciones);
      await repositorio.anotar(resultado.silenciosas);
      if (ref.mounted && !listEquals(state, resultado.avisos)) state = resultado.avisos;
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.auth,
        'ZONA_AVISO_PROCESAR',
        'no se pudo armar el aviso de zona',
        {'error': e.runtimeType.toString()},
      );
    }
  }

  /// La persona cerró [aviso]: desaparece enseguida y se anota como avisado. Si entre tanto la zona
  /// volvió a cambiar y [aviso] ya no es el vigente, no se hace nada (el nuevo sigue visible).
  Future<void> cerrar(AvisoZona aviso) {
    if (!state.contains(aviso)) return Future<void>.value();
    _cerradas[aviso.inscripcionId] = aviso.zonaId;
    state = [
      for (final pendiente in state)
        if (pendiente != aviso) pendiente,
    ];
    return _encolar(
      () => ref.read(zonasAvisadasRepositoryProvider).anotar({aviso.inscripcionId: aviso.zonaId}),
    );
  }
}
