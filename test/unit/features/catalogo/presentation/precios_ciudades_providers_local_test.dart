// El cableado de las ciudades de Precios (#421): con la base local abierta, la ciudad con la que abre
// la vista 26 sale de las réplicas del pull (campañas, ciudades y zonas) y del GPS, de punta a punta
// por los providers; sin base, o sin pull, es la falla de lectura 26·10 y nunca «no tenés campañas».
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/ciudad_consultable.dart';
import 'package:colportores_mobile/features/catalogo/presentation/providers/precios_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/alta_ubicacion_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/replica_de_campanias.dart';

class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase? _db;

  @override
  AppDatabase? build() => _db;
}

const _colportor = 'col-1';

/// Dentro de la zona de Montevideo de la réplica de abajo.
const _enMontevideo = Coordenadas(lat: -34.90, lon: -56.17);

/// Dentro de la zona de Canelones.
const _enCanelones = Coordenadas(lat: -34.52, lon: -56.28);

/// Fuera de toda zona de sus campañas.
const _enSalto = Coordenadas(lat: -31.38, lon: -57.96);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ReplicaDeCampanias replica;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
  });
  tearDown(() => db.close());

  ProviderContainer armar({AppDatabase? base, GpsFalso? gps, bool conBase = true}) {
    final contenedor = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbFija(conBase ? (base ?? db) : null)),
        relojPreciosProvider.overrideWithValue(() => DateTime.utc(2026, 10, 27, 15)),
        esperaDelGpsPreciosProvider.overrideWithValue(const Duration(milliseconds: 200)),
        proveedorGpsProvider.overrideWithValue(gps ?? GpsFalso()),
      ],
    );
    addTearDown(contenedor.dispose);
    // Los providers de la pantalla son autoDispose: sin quien escuche, se descartan mientras cargan.
    contenedor.listen(aperturaDePreciosProvider(_colportor), (_, _) {});
    return contenedor;
  }

  Map<String, Object?> zona(
    String id,
    String campaniaCiudad,
    double sur,
    double norte,
    double o,
    double e,
  ) => filaZona(
    id,
    'Zona $id',
    campaniaCiudad: campaniaCiudad,
    latSur: sur,
    latNorte: norte,
    lonOeste: o,
    lonEste: e,
  );

  Future<void> bajar({String? zonaAsignada, bool pull = true}) async {
    await replica.bajar({
      'ciudad': [
        filaCiudad('ciu-mvd', 'Montevideo', lat: -34.9011, lon: -56.1645),
        filaCiudad('ciu-can', 'Canelones', lat: -34.5228, lon: -56.2778),
      ],
      'campania': [filaCampania('camp-1', 'Verano 2026')],
      'campania_ciudad': [
        filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd'),
        filaCampaniaCiudad('cc-can', campania: 'camp-1', ciudad: 'ciu-can'),
      ],
      'zona': [
        zona('z-mvd', 'cc-mvd', -34.92, -34.88, -56.20, -56.15),
        zona('z-can', 'cc-can', -34.55, -34.50, -56.30, -56.25),
      ],
      'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: zonaAsignada)],
    });
    if (pull) await replica.terminoUnPull();
  }

  Future<AperturaDePrecios> abrir(ProviderContainer c) =>
      c.read(aperturaDePreciosProvider(_colportor).future);

  GpsFalso gpsEn(Coordenadas punto) => GpsFalso(Right(lecturaGps(6, punto: punto)));

  group('con la base local abierta', () {
    test(
      'Precios abre en la ciudad donde está, si es de alguna de sus campañas ("Precios GPS")',
      () async {
        await bajar(zonaAsignada: 'z-mvd');

        final apertura = await abrir(armar(gps: gpsEn(_enCanelones)));

        expect(apertura.inicial.ciudad?.nombre, 'Canelones');
        expect(apertura.inicial.ciudad?.campaniaCiudadId, 'cc-can');
        expect(apertura.inicial.origen, OrigenDeLaCiudad.gps);
        expect(apertura.contexto.ciudades.map((c) => c.nombre), ['Canelones', 'Montevideo']);
      },
    );

    test('sin GPS cae en la ciudad de su zona (26·06)', () async {
      await bajar(zonaAsignada: 'z-mvd');
      final gps = GpsFalso(
        const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.servicioApagado)),
      );

      final apertura = await abrir(armar(gps: gps));

      expect(apertura.inicial.ciudad?.nombre, 'Montevideo');
      expect(apertura.inicial.origen, OrigenDeLaCiudad.zona);
    });

    test('con el GPS fuera de todas sus ciudades también cae en la de su zona', () async {
      await bajar(zonaAsignada: 'z-can');

      final apertura = await abrir(armar(gps: gpsEn(_enSalto)));

      expect(apertura.inicial.ciudad?.nombre, 'Canelones');
      expect(apertura.inicial.origen, OrigenDeLaCiudad.zona);
    });

    test('sin zona ni GPS no se elige por ella: la elige ella', () async {
      await bajar();
      final gps = GpsFalso(
        const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.servicioApagado)),
      );

      final apertura = await abrir(armar(gps: gps));

      expect(apertura.inicial.ciudad, isNull);
      expect(apertura.contexto.ciudades, hasLength(2));
    });

    test(
      'la ciudad del GPS en Montevideo con zona asignada en Canelones: gana donde está',
      () async {
        await bajar(zonaAsignada: 'z-can');

        final apertura = await abrir(armar(gps: gpsEn(_enMontevideo)));

        expect(apertura.inicial.ciudad?.nombre, 'Montevideo');
        expect(apertura.inicial.origen, OrigenDeLaCiudad.gps);
      },
    );

    test('una campaña que terminó: sin ciudades y con el motivo (26·11)', () async {
      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Primavera 2026', fin: '2026-10-15')],
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
      });
      await replica.terminoUnPull();

      final apertura = await abrir(armar());

      expect(apertura.contexto.ciudades, isEmpty);
      expect(apertura.contexto.campaniaTerminada?.nombre, 'Primavera 2026');
      expect(apertura.inicial.ciudad, isNull);
    });
  });

  group('cuando no se sabe, es la falla de lectura 26·10 y no "no tenés campañas"', () {
    test('sin la base abierta', () async {
      final c = armar(conBase: false);

      await expectLater(abrir(c), throwsA(isA<FailurePreciosNoDisponibles>()));
    });

    test('con la base abierta pero ningún pull terminado', () async {
      await bajar(pull: false);

      await expectLater(abrir(armar()), throwsA(isA<FailurePreciosNoDisponibles>()));
    });

    test('el "Reintentar" lee de nuevo y, con el pull ya terminado, abre', () async {
      await bajar(zonaAsignada: 'z-mvd', pull: false);
      final c = armar(
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.servicioApagado))),
      );
      await expectLater(abrir(c), throwsA(isA<FailurePreciosNoDisponibles>()));

      await replica.terminoUnPull();
      c.invalidate(aperturaDePreciosProvider(_colportor));

      expect((await abrir(c)).inicial.ciudad?.nombre, 'Montevideo');
    });
  });
}
