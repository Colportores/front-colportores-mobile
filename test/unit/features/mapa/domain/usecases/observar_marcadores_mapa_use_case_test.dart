// Test de dominio: Dart puro (HU-UBI-003).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/observar_marcadores_mapa_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';
import '../../../../../helpers/ubicacion_sin_modificar.dart';

/// Repositorio con un stream de marcadores que el test controla.
final class _RepositorioDeMapa with UbicacionRepositorySinModificar implements UbicacionRepository {
  final fuente = StreamController<List<MarcadorMapa>>();
  ({String colportorId, AreaMapa area})? pedido;

  @override
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  }) {
    pedido = (colportorId: colportorId, area: area);
    return fuente.stream;
  }

  @override
  Stream<List<Ubicacion>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, ResultadoAltaUbicacion>> registrar(
    Ubicacion ubicacion, {
    Espacio? espacio,
    required OrigenCoordenadas origen,
    CriterioDuplicadoUbicacion? duplicados,
  }) => throw UnimplementedError();
}

void main() {
  const area = AreaMapa(sur: -35, oeste: -57, norte: -34, este: -56);

  MarcadorMapa m(String id, double lat, double lon) =>
      MarcadorMapa(ubicacionId: id, tipo: TipoUbicacion.casa, lat: lat, lon: lon);

  test('pide al repositorio el colportor y el área, y agrupa según el zoom', () async {
    final repo = _RepositorioDeMapa();
    final mapas = <MapaUbicaciones>[];
    final sub = ObservarMarcadoresMapaUseCase(repo)(
      const ConsultaMapa(colportorId: 'col-1', area: area, zoom: 10),
    ).listen(mapas.add);
    expect(repo.pedido, (colportorId: 'col-1', area: area));

    repo.fuente.add(const []);
    repo.fuente.add([m('a', -34.9, -56.15), m('b', -34.9001, -56.1501)]);
    await pumpEventQueue();

    expect(mapas.first.estaVacio, isTrue);
    expect(mapas.last.totalMarcadores, 2);
    expect(mapas.last.grupos.single.cantidad, 2);
    await sub.cancel();
  });

  test('un error del repositorio llega al stream', () async {
    final repo = _RepositorioDeMapa();
    final futuro = ObservarMarcadoresMapaUseCase(repo)(
      const ConsultaMapa(colportorId: 'col-1', area: area, zoom: 10),
    ).first;
    final esperado = expectLater(futuro, throwsA(isA<StateError>()));
    repo.fuente.addError(StateError('db cerrada'));
    await esperado;
  });
}
