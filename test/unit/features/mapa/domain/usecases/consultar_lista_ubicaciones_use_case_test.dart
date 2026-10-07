// Test de dominio: Dart puro (HU-UBI-002).
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/consulta_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/consultar_lista_ubicaciones_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';
import '../../../../../helpers/ubicacion_sin_modificar.dart';

/// Repositorio con un stream que el test controla, y que anota con qué se lo pidió.
final class _RepositorioReactivo
    with UbicacionRepositorySinModificar
    implements UbicacionRepository {
  final fuente = StreamController<List<UbicacionConResumen>>();
  ({String colportorId, bool incluirBajas})? pedido;

  @override
  Stream<List<Ubicacion>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) => throw UnimplementedError();

  @override
  Stream<List<UbicacionConResumen>> observarListaDelColportor({
    required String colportorId,
    bool incluirBajas = false,
  }) {
    pedido = (colportorId: colportorId, incluirBajas: incluirBajas);
    return fuente.stream;
  }

  @override
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  }) => const Stream.empty();

  @override
  Future<Either<Failure, ResultadoAltaUbicacion>> registrar(
    Ubicacion ubicacion, {
    Espacio? espacio,
    required OrigenCoordenadas origen,
    CriterioDuplicadoUbicacion? duplicados,
  }) => throw UnimplementedError();
}

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 12);

  UbicacionConResumen ub(String id, {int minutos = 0, int espacios = 1, bool baja = false}) =>
      UbicacionConResumen(
        cantidadEspacios: espacios,
        ubicacion: Ubicacion(
          id: id,
          tipo: TipoUbicacion.casa,
          calle: 'Rivadavia',
          numero: '1',
          lat: -34.9,
          lon: -56.15,
          ciudadId: 'mvd',
          auditoria: Auditoria(
            createdAt: t0,
            updatedAt: t0.add(Duration(minutes: minutos)),
            createdBy: 'col-1',
            deletedAt: baja ? t0.add(Duration(minutes: minutos)) : null,
          ),
        ),
      );

  test(
    'pide al repositorio lo del colportor y las bajas; la ciudad la filtra el armador',
    () async {
      final repo = _RepositorioReactivo();
      final sub = ConsultarListaUbicacionesUseCase(repo)(
        const ConsultaListaUbicaciones(colportorId: 'col-1', ciudadId: 'mvd', incluirBajas: true),
      ).listen((_) {});
      // Sin ciudad: si no, "sinUbicaciones" no podría contar las de otras ciudades.
      expect(repo.pedido, (colportorId: 'col-1', incluirBajas: true));
      await sub.cancel();
    },
  );

  test('con «Mostrar bajas» apagado pide igual las bajas: no las lista pero las cuenta', () async {
    final repo = _RepositorioReactivo();
    final futuro = ConsultarListaUbicacionesUseCase(repo)(
      const ConsultaListaUbicaciones(colportorId: 'col-1'),
    ).first;
    expect(repo.pedido, (colportorId: 'col-1', incluirBajas: true));

    repo.fuente.add([ub('viva'), ub('baja', baja: true)]);
    final lista = await futuro;

    expect([for (final i in lista.items) i.ubicacion.id], ['viva']);
    expect(lista.bajasOcultas, 1);
  });

  test('solo bajas con «Mostrar bajas» apagado llega como «solo bajas»', () async {
    final repo = _RepositorioReactivo();
    final futuro = ConsultarListaUbicacionesUseCase(repo)(
      const ConsultaListaUbicaciones(colportorId: 'col-1'),
    ).first;
    repo.fuente.add([ub('a', baja: true), ub('b', baja: true)]);
    final lista = await futuro;

    expect(lista.sinUbicaciones, isTrue);
    expect(lista.soloBajas, isTrue);
    expect(lista.items, isEmpty);
  });

  test('cada emisión del repositorio vuelve a emitir la lista armada (stream reactivo)', () async {
    final repo = _RepositorioReactivo();
    final listas = <List<String>>[];
    final sub = ConsultarListaUbicacionesUseCase(repo)(
      const ConsultaListaUbicaciones(colportorId: 'col-1'),
    ).listen((l) => listas.add([for (final i in l.items) i.ubicacion.id]));

    repo.fuente.add(const []);
    repo.fuente.add([ub('a')]);
    repo.fuente.add([ub('a'), ub('b', minutos: 1)]);
    await pumpEventQueue();

    expect(listas, [
      <String>[],
      ['a'],
      ['b', 'a'],
    ]);
    await sub.cancel();
  });

  test('cada fila de la lista lleva los espacios que trajo el repositorio', () async {
    final repo = _RepositorioReactivo();
    final futuro = ConsultarListaUbicacionesUseCase(repo)(
      const ConsultaListaUbicaciones(colportorId: 'col-1'),
    ).first;
    repo.fuente.add([ub('a', espacios: 3)]);
    expect((await futuro).items.single.cantidadEspacios, 3);
  });

  test('un error del repositorio llega al stream', () async {
    final repo = _RepositorioReactivo();
    final futuro = ConsultarListaUbicacionesUseCase(repo)(
      const ConsultaListaUbicaciones(colportorId: 'col-1'),
    ).first;
    final esperado = expectLater(futuro, throwsA(isA<StateError>()));
    repo.fuente.addError(StateError('db cerrada'));
    await esperado;
  });
}
