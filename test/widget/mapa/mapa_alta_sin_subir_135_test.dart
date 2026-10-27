// HU-UBI-003, último escenario (#135): «Sin modo demo: mi alta sin subir se ve en el mapa». Con la base
// real (Drift en memoria), el alta de verdad (caso de uso → repositorio → DAO) y la pestaña «Mapa»
// real, solo con la vista nativa de MapLibre y los puertos de afuera (GPS, red, tiles) falsos:
//
// - una ubicación recién registrada, que todavía no subió (sigue en la cola del sync), se dibuja con
//   el color de su `house_status` («Sin visita» hasta que tenga uno);
// - no hay casas simuladas: sin altas ni casas bajadas, el mapa no dibuja nada más que el GPS;
// - lo que baja el motor se suma a las altas propias, y lo de otro colportor no se dibuja.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/color_house_status.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/registrar_ubicacion_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/marcador_estado.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/duplicados_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/zonas_falsas.dart';
import 'mapa_ubicaciones_arnes.dart';

final _t0 = DateTime.utc(2026, 10, 27, 12);

/// Grados de latitud que son [metros].
double _grados(double metros) => metros / 111195.08;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late EncoladorSyncEnMemoria cola;
  late RegistrarUbicacionUseCase registrar;
  late int ids;
  StreamSubscription<Object?>? suscripcion;

  /// El teléfono del colportor `col-1`: la base real, la cola del sync (que no sube nada) y el alta
  /// de verdad.
  UbicacionRepositoryImpl armar() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    cola = EncoladorSyncEnMemoria();
    final local = UbicacionLocalDataSourceDrift(
      db,
      encolador: cola,
      marcarDuplicado: EncoladorMarcarDuplicadoFalso(),
    );
    final repositorio = UbicacionRepositoryImpl(local, logger: loggerMudo());
    ids = 0;
    registrar = RegistrarUbicacionUseCase(
      repositorio,
      generarId: () => 'ub-propia-${++ids}',
      ubicador: ubicadorSinZonas(),
      ahora: () => _t0,
    );
    return repositorio;
  }

  /// Registra un alta, como la hace la pantalla «Nueva ubicación», [metrosAlNorte] del GPS.
  Future<String> alta(WidgetTester tester, {required double metrosAlNorte, String? calle}) async {
    final id = registrar.nuevoId();
    final resultado = await tester.runAsync(
      () => registrar(
        RegistrarUbicacionParams(
          id: id,
          colportorId: 'col-1',
          tipo: TipoUbicacion.casa,
          punto: PuntoCapturado.gps(
            LecturaGps(
              coordenadas: Coordenadas(
                lat: puntoItalia.lat + _grados(metrosAlNorte),
                lon: puntoItalia.lon,
              ),
              precisionMetros: 8,
            ),
          ),
          ciudadId: 'mvd',
          calle: calle ?? 'Rivera',
          numero: '${1000 + ids}',
        ),
      ),
    );
    expect(
      resultado!.getOrElse(() => throw StateError('el alta falló')),
      isA<AltaRegistrada>(),
      reason: 'el alta se completa sin red',
    );
    return id;
  }

  /// Una ubicación que ya estaba en la base (la que bajó el motor): [creador] la registró.
  Future<void> bajada(WidgetTester tester, String id, {required String creador}) async {
    await tester.runAsync(
      () => db
          .into(db.ubicaciones)
          .insert(
            UbicacionesCompanion.insert(
              id: id,
              tipo: 'CASA',
              lat: puntoItalia.lat + _grados(300),
              lon: puntoItalia.lon,
              ciudadId: 'mvd',
              createdAt: _t0,
              updatedAt: _t0,
              createdBy: Value(creador),
              syncVersion: const Value(3),
            ),
          ),
    );
  }

  Future<void> conEstado(WidgetTester tester, String id, ColorHouseStatus color) async {
    await tester.runAsync(
      () => db
          .into(db.houseStatuses)
          .insert(
            HouseStatusesCompanion.insert(
              ubicacionId: id,
              lat: puntoItalia.lat + _grados(200),
              lon: puntoItalia.lon,
              tipoUbicacion: 'CASA',
              color: color.codigo,
              prioridad: color.prioridad,
              createdAt: _t0,
              updatedAt: _t0,
            ),
          ),
    );
  }

  /// Abre la pestaña «Mapa». La lista del colportor sale del repositorio real sobre la base real: el
  /// puente la pasa tal cual al repositorio que el arnés le da a la pestaña (cada cambio de la base
  /// llega al mapa por el mismo stream de Drift que usa la app).
  Future<MontajeMapaUbicaciones> abrirMapa(WidgetTester tester) async {
    final repositorio = armar();
    final puente = RepoListaFalso();
    final montaje = await montarMapaUbicaciones(tester, repo: puente, asentar: false);
    suscripcion = repositorio.observarListaDelColportor(colportorId: 'col-1').listen(puente.emitir);
    await _esperarBase(tester);
    return montaje;
  }

  /// Desmonta la pestaña (Drift deja un timer al cancelar el stream) y cierra la base.
  Future<void> cerrar(WidgetTester tester) async {
    await tester.runAsync(() async => suscripcion?.cancel());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(db.close);
  }

  testWidgets('sin altas ni casas bajadas, el mapa no dibuja ninguna casa (no hay modo demo)', (
    tester,
  ) async {
    final m = await abrirMapa(tester);

    expect(m.mapa.config!.puntos.where((p) => p.id != 'gps'), isEmpty);
    expect(tester.takeException(), isNull);
    await cerrar(tester);
  });

  testWidgets('una alta que todavía no subió se ve en el mapa como «Sin visita»', (tester) async {
    final m = await abrirMapa(tester);

    final id = await alta(tester, metrosAlNorte: 200);
    await _esperarBase(tester);

    // La cola del sync tiene el alta y nadie la subió: no hay servidor en este teléfono.
    expect(cola.encolados, isNotEmpty);
    final casas = m.mapa.config!.puntos.where((p) => p.id != 'gps').toList();
    expect(casas.map((p) => p.id), [id]);
    expect(casas.single.variante, VarianteMarcador.de(null));
    expect(casas.single.variante, VarianteMarcador.sinVisita);
    expect(tester.takeException(), isNull);
    await cerrar(tester);
  });

  testWidgets('el alta lleva el color de su house_status cuando la casa lo tiene', (tester) async {
    final m = await abrirMapa(tester);
    final id = await alta(tester, metrosAlNorte: 200);
    await _esperarBase(tester);

    await conEstado(tester, id, ColorHouseStatus.entrevistaProgramada);
    await _esperarBase(tester);

    expect(
      m.mapa.config!.puntos.firstWhere((p) => p.id == id).variante,
      VarianteMarcador.de(EstadoCasa.entrevistaAgendada),
    );
    await cerrar(tester);
  });

  testWidgets('dos altas seguidas con el mapa abierto se dibujan las dos, sin pisarse', (
    tester,
  ) async {
    final m = await abrirMapa(tester);

    final primera = await alta(tester, metrosAlNorte: 150, calle: 'Rivera');
    final segunda = await alta(tester, metrosAlNorte: 250, calle: 'Bulevar Artigas');
    await _esperarBase(tester);

    expect(m.mapa.config!.puntos.where((p) => p.id != 'gps').map((p) => p.id).toSet(), {
      primera,
      segunda,
    });
    await cerrar(tester);
  });

  testWidgets('lo que baja el motor se suma a la alta propia; lo de otro colportor no se dibuja', (
    tester,
  ) async {
    final m = await abrirMapa(tester);
    final propia = await alta(tester, metrosAlNorte: 200);
    await bajada(tester, 'ub-bajada-propia', creador: 'col-1');
    await bajada(tester, 'ub-de-otro', creador: 'col-2');
    await _esperarBase(tester);

    final ids = m.mapa.config!.puntos.where((p) => p.id != 'gps').map((p) => p.id).toSet();
    expect(ids, {propia, 'ub-bajada-propia'});
    expect(hayPunto(m.mapa, 'ub-de-otro'), isFalse);
    await cerrar(tester);
  });
}

/// La base real no avanza con el reloj falso del test: se le da tiempo real y se bombea.
Future<void> _esperarBase(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}
