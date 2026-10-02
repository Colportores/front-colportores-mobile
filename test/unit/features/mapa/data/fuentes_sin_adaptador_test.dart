// HU-UBI-001: lo que hace el alta mientras no existen el catálogo de ciudades, las inscripciones ni el
// motor de sync. Ninguno inventa datos.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/features/mapa/data/services/fuentes_sin_adaptador_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

const _punto = Coordenadas(lat: -34.9, lon: -56.1);

void main() {
  test(
    'sin catálogo: ninguna ciudad se detecta, no hay lista y no hay ciudad de la zona',
    () async {
      final c = CiudadesParaAltaSinFuente();

      expect(await c.detectar(_punto), const Right<Failure, DeteccionCiudad>(CiudadNoEncontrada()));
      expect(await c.todas(), const Right<Failure, List<CiudadCatalogo>>([]));
      expect(await c.deMiZona('col-1'), const Right<Failure, CiudadCatalogo?>(null));
    },
  );

  test('sin dónde mandar el pedido de alta de ciudad: dice que todavía no se puede', () async {
    final r = await const SolicitadorAltaCiudadSinFuente().solicitar(
      colportorId: 'col-1',
      punto: _punto,
    );

    expect(r, const Left<Failure, Unit>(FailureSolicitudCiudadNoDisponible()));
    expect(
      const FailureSolicitudCiudadNoDisponible().mensaje,
      contains('Avisale a tu coordinador'),
    );
  });

  test(
    'sin inscripciones: lista vacía, el alta queda sin zona local y el servidor la calcula',
    () async {
      final r = await InscripcionesColportorSinFuente().vigentesDe('col-1');

      expect(r.getOrElse(() => throw StateError('falló')), isEmpty);
    },
  );

  test('sin motor de sync encolar falla: un alta que no sube no se guarda', () async {
    await expectLater(
      const EncoladorSyncSinMotor().encolar('ubicacion', OperacionSync.insert, const {}),
      throwsStateError,
    );
  });

  test('sin la base local abierta no hay repositorio de ubicaciones ni de zonas', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(() => c.read(ubicacionRepositoryProvider), throwsA(isA<ProviderException>()));
    expect(() => c.read(zonaRepositoryProvider), throwsA(isA<ProviderException>()));
  });

  test('sin la base abierta, el contexto del mapa no tiene ubicaciones', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    const consulta = (
      colportorId: 'col-1',
      area: AreaMapa(sur: -35, oeste: -57, norte: -34, este: -56),
    );
    c.listen(marcadoresCercanosProvider(consulta), (_, _) {});
    final lista = await c.read(marcadoresCercanosProvider(consulta).future);

    expect(lista, isEmpty);
  });
}
