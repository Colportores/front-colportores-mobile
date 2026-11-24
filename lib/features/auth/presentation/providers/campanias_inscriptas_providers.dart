import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../../core/database/database_providers.dart';
import '../../../../core/database/dia_de_calendario.dart';
import '../../../../core/logging/app_logger.dart';
import '../../data/datasources/campanias_inscriptas_data_source.dart';
import '../../data/datasources/campanias_inscriptas_local_data_source.dart';
import '../../domain/entities/campania_inscripta.dart';
import '../../domain/services/situacion_de_campania.dart';

/// El reloj con el que se decide si la campaña ya empezó (HU-AUTH-008). Un test lo reemplaza.
final relojCampaniaProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// De dónde salen las campañas del colportor: las réplicas locales del pull de catálogos
/// ([CampaniasInscriptasLocal]); sin la DB abierta (tests, sin sesión), ninguna. Se reconstruye solo
/// cuando la DB se abre o se cierra.
final campaniasInscriptasDataSourceProvider = Provider<CampaniasInscriptasDataSource>(
  (ref) => CampaniasInscriptasLocal(ref.watch(dbLocalProvider)),
);

/// Las campañas con inscripción viva de [usuarioId], reactivas: cambian cuando un pull escribe.
/// `null` = el teléfono todavía no puede saberlo (ver [CampaniasInscriptasDataSource.observar]).
final campaniasInscriptasProvider = StreamProvider.family<List<CampaniaInscripta>?, String>(
  (ref, usuarioId) => ref.watch(campaniasInscriptasDataSourceProvider).observar(usuarioId),
);

/// Cuánto se espera la lectura de la réplica al frenar una acción: si no contesta, no se frena nada
/// (la app no afirma lo que no sabe; el servidor respalda el freno).
const _esperaDeLaLectura = Duration(seconds: 3);

/// El `read` de un `WidgetRef` o de un `ProviderContainer`: quien frena una acción lo pasa tal cual.
typedef LeerProvider = T Function<T>(ProviderListenable<T> provider);

/// La campaña por empezar que frena la jornada y la venta de [usuarioId] **ahora** (HU-AUTH-008,
/// «Cuenta antes»), o `null` si no frena nada: tiene una campaña en curso, no tiene ninguna por
/// empezar, el teléfono todavía no lo sabe o la lectura falló.
///
/// Se lee fresca en cada toque (el día se mira con [relojCampaniaProvider] en ese momento): el
/// primer día de la campaña el freno se levanta solo, sin esperar a un pull. [leer] es el `read` de
/// quien frena (`ref.read`). Lee del data source con una suscripción propia que se cierra al contestar.
Future<CampaniaPorEmpezar?> campaniaQueFrena(LeerProvider leer, String usuarioId) async {
  try {
    // Una suscripción propia y no el provider: sin nadie escuchándolo (el flujo de venta no es un
    // widget), Riverpod no lo mantiene al día y la lectura nunca contestaría. Se cierra al contestar
    // o al vencer la espera.
    final lectura = Completer<List<CampaniaInscripta>?>();
    final suscripcion = leer(campaniasInscriptasDataSourceProvider)
        .observar(usuarioId)
        .listen(
          (campanias) {
            if (!lectura.isCompleted) lectura.complete(campanias);
          },
          onError: (Object error, StackTrace rastro) {
            if (!lectura.isCompleted) lectura.completeError(error, rastro);
          },
        );
    final List<CampaniaInscripta>? campanias;
    try {
      campanias = await lectura.future.timeout(_esperaDeLaLectura);
    } finally {
      // Sin esperar el cierre: lo que importa es lo que contestó, y cancelar puede tardar.
      unawaited(suscripcion.cancel());
    }
    if (campanias == null) return null;
    return SituacionDeCampania.porEmpezar(
      campanias,
      hoy: diaDeCalendario(leer(relojCampaniaProvider)()),
    );
  } on Object catch (e) {
    // Nunca la excepción al log (una `SqliteException` imprime la sentencia): solo su tipo.
    AppLogger.instance.warn(
      LogModulo.auth,
      'CAMPANIA_POR_EMPEZAR_LEER',
      'no se pudo leer la campaña por empezar: no se frena nada',
      {'tipo': e.runtimeType.toString()},
    );
    return null;
  }
}
