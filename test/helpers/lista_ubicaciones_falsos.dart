import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'alta_ubicacion_falsos.dart';
import 'ubicacion_sin_modificar.dart';

/// Hoy para los tests de la lista: las filas dicen «hace 2 h», «ayer»… respecto de este momento.
final ahoraLista = DateTime.utc(2026, 10, 6, 15);

/// Una fila de la lista de ubicaciones. [hace] es cuánto antes de [ahoraLista] se actualizó.
UbicacionConResumen filaLista(
  String id, {
  TipoUbicacion tipo = TipoUbicacion.casa,
  String? calle,
  String? numero,
  String ciudadId = 'ciu-mvd',
  double metrosAlNorte = 0,
  Duration hace = const Duration(hours: 2),
  int espacios = 1,
  EstadoCasa? estado,
  DateTime? entrevista,
  DateTime? baja,
  String dueno = 'col-1',
}) {
  final actualizada = ahoraLista.subtract(hace);
  return UbicacionConResumen(
    ubicacion: Ubicacion(
      id: id,
      tipo: tipo,
      calle: calle ?? 'Av. Italia',
      numero: numero ?? '1234',
      lat: puntoItalia.lat + metrosAlNorte / 111320,
      lon: puntoItalia.lon,
      ciudadId: ciudadId,
      auditoria: Auditoria(
        createdAt: actualizada.subtract(const Duration(days: 1)),
        updatedAt: actualizada,
        createdBy: dueno,
        deletedAt: baja,
      ),
    ),
    cantidadEspacios: espacios,
    estado: estado,
    proximaEntrevista: entrevista,
  );
}

/// El repositorio de ubicaciones con la lista que el test fije: emite lo que tiene al suscribirse,
/// vuelve a emitir con [emitir], falla con [fallar] y cuenta las suscripciones (nunca debe haber
/// dos vivas de la misma pantalla).
final class RepoListaFalso with UbicacionRepositorySinModificar implements UbicacionRepository {
  RepoListaFalso([List<UbicacionConResumen> filas = const []]) : _filas = filas;

  List<UbicacionConResumen> _filas;
  final _activos = <MultiStreamController<List<UbicacionConResumen>>>[];

  /// Cuántas veces se pidió la lista, con lo que se pidió.
  final pedidos = <({String colportorId, bool incluirBajas})>[];

  /// Cuántas suscripciones se abrieron en total.
  var suscripciones = 0;

  /// Cuántas están abiertas ahora.
  int get activas => _activos.length;

  /// Si no es `null`, pedir la lista lanza esto en el acto (como un repositorio sin base abierta).
  Object? lanzaAlPedir;

  /// Si no es `null`, la suscripción espera a que se complete antes de emitir la primera lista.
  Completer<void>? bloqueo;

  /// Si es `true`, la primera emisión de cada suscripción es un error en vez de la lista.
  bool fallaAlSuscribir = false;

  /// Reemplaza la lista y se la emite a quien esté suscripto (una alta, una baja, una edición).
  void emitir(List<UbicacionConResumen> filas) {
    _filas = filas;
    for (final c in [..._activos]) {
      c.add(filas);
    }
  }

  /// Hace que el stream emita un error a quien esté suscripto.
  void fallar(Object error) {
    for (final c in [..._activos]) {
      c.addError(error);
    }
  }

  @override
  Stream<List<UbicacionConResumen>> observarListaDelColportor({
    required String colportorId,
    bool incluirBajas = false,
  }) {
    pedidos.add((colportorId: colportorId, incluirBajas: incluirBajas));
    final lanza = lanzaAlPedir;
    if (lanza != null) throw lanza;
    return Stream.multi((c) {
      suscripciones++;
      _activos.add(c);
      c.onCancel = () => _activos.remove(c);
      unawaited(
        Future<void>(() async {
          final espera = bloqueo;
          if (espera != null) await espera.future;
          if (!_activos.contains(c)) return;
          if (fallaAlSuscribir) {
            c.addError(StateError('base cerrada'));
          } else {
            c.add(_filas);
          }
        }),
      );
    });
  }

  @override
  Future<Either<Failure, ResultadoAltaUbicacion>> registrar(
    Ubicacion ubicacion, {
    Espacio? espacio,
    required OrigenCoordenadas origen,
    CriterioDuplicadoUbicacion? duplicados,
  }) => throw UnimplementedError();

  @override
  Stream<List<Ubicacion>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) => throw UnimplementedError();

  @override
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  }) => Stream.value(const []);
}

/// Overrides para probar la lista sin plugins ni base de datos.
List<Override> overridesLista({
  required RepoListaFalso repo,
  GpsFalso? gps,
  CiudadesParaAlta? ciudades,
  DateTime? ahora,
}) {
  final gpsFalso = gps ?? GpsFalso();
  return [
    ubicacionRepositoryProvider.overrideWithValue(repo),
    proveedorGpsProvider.overrideWithValue(gpsFalso),
    activadorGpsProvider.overrideWithValue(gpsFalso),
    ciudadesParaAltaProvider.overrideWithValue(ciudades ?? CiudadesFalsas()),
    relojListaUbicacionesProvider.overrideWithValue(() => ahora ?? ahoraLista),
  ];
}
