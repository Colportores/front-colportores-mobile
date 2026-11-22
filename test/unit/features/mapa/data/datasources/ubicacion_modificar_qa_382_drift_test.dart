// QA del PR #456 (issue #382, HU-UBI-004 / S13): al pasar a Casa sin espacios, la casa recibe su
// espacio default. Complementa a `ubicacion_modificar_drift_test.dart` con los cruces que el PR no
// prueba: el espacio solo se crea cuando la edición se guarda de verdad (no con un aviso de
// duplicado, una confirmación pendiente ni una reactivación sin confirmar), una casa que va y viene
// nunca suma un segundo espacio, y dos guardados superpuestos dejan uno solo. Base real (Drift en
// memoria), caso de uso y repositorio reales.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_modificacion_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/modificar_ubicacion_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/zonas_falsas.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 21, 13, 45, 10, 123);
  final t1 = DateTime.utc(2026, 10, 22, 8, 0, 0, 500);
  const italia = Coordenadas(lat: -34.891, lon: -56.125);

  Coordenadas alNorte(double metros) =>
      Coordenadas(lat: italia.lat + metros / 111195.08, lon: italia.lon);

  UbicacionModel ubicacion({
    String id = 'ub-1',
    TipoUbicacion tipo = TipoUbicacion.edificio,
    String? numero = '1234',
    Coordenadas punto = italia,
    String creadaPor = 'col-1',
    DateTime? deletedAt,
  }) => UbicacionModel(
    id: id,
    tipo: tipo,
    calle: 'Av. Italia',
    numero: numero,
    lat: punto.lat,
    lon: punto.lon,
    ciudadId: 'mvd',
    zonaId: 'zona-9',
    auditoria: Auditoria(
      createdAt: t0,
      updatedAt: t0,
      createdBy: creadaPor,
      deletedAt: deletedAt,
      syncVersion: 4,
    ),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift local;
  late ModificarUbicacionUseCase modificar;
  late int ids;
  late DateTime reloj;

  setUp(() {
    ids = 0;
    reloj = t1;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    modificar = ModificarUbicacionUseCase(
      UbicacionRepositoryImpl(local, logger: loggerMudo()),
      generarId: () => 'esp-${++ids}',
      ubicador: ubicadorSinZonas(),
      ahora: () => reloj,
    );
  });

  tearDown(() => db.close());

  ModificarUbicacionParams params({
    TipoUbicacion tipo = TipoUbicacion.casa,
    Coordenadas coordenadas = italia,
    String? numero = '1234',
    Set<ConfirmacionModificacion> confirmadas = const {},
    String? justificacion,
    DateTime? base,
  }) => ModificarUbicacionParams(
    id: 'ub-1',
    colportorId: 'col-1',
    tipo: tipo,
    coordenadas: coordenadas,
    baseUpdatedAt: base ?? t0,
    ciudadId: 'mvd',
    calle: 'Av. Italia',
    numero: numero,
    confirmadas: confirmadas,
    justificacionDuplicado: justificacion,
  );

  Future<ResultadoModificacionUbicacion> ok(ModificarUbicacionParams p) async =>
      (await modificar(p)).getOrElse(() => throw StateError('era un Left'));

  Future<List<EspacioFila>> espacios() => db.select(db.espacios).get();

  Future<List<EspacioFila>> activos() async =>
      (await espacios()).where((e) => e.deletedAt == null).toList();

  List<String> entidades() => [for (final c in encolador.encolados) c.entidad];

  group('QA #382 · el espacio nace solo cuando la edición se guarda', () {
    test('dado un aviso de posible duplicado, cuando el colportor todavía no confirmó, la casa no '
        'recibe espacio ni se encola nada; con «seguir igual» recibe uno solo', () async {
      await local.insertar(ubicacion());
      await local.insertar(ubicacion(id: 'ub-2', numero: '1237', punto: alNorte(150)));
      encolador.encolados.clear();

      final aviso = await ok(params(numero: '1237'));

      expect(aviso, isA<ModificacionConDuplicados>());
      expect(await espacios(), isEmpty);
      expect(encolador.encolados, isEmpty);
      expect((await local.obtener('ub-1'))!.tipo, TipoUbicacion.edificio);

      final r = await ok(params(numero: '1237', justificacion: 'Son dos casas del mismo número'));

      expect(r, isA<UbicacionModificada>());
      expect(await activos(), hasLength(1));
      expect(entidades(), ['ubicacion', 'espacio']);
    });

    test('dado un desplazamiento de más de 100 m sin confirmar, cuando pasa a Casa, no se crea el '
        'espacio; confirmado, se crea uno', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();

      final pide = await ok(params(coordenadas: alNorte(150)));

      expect(pide, isA<ModificacionRequiereConfirmacion>());
      expect(await espacios(), isEmpty);
      expect(encolador.encolados, isEmpty);

      await ok(
        params(coordenadas: alNorte(150), confirmadas: {ConfirmacionModificacion.desplazamiento}),
      );

      expect(await activos(), hasLength(1));
      expect(entidades(), ['ubicacion', 'espacio']);
    });

    test(
      'dado un edificio vacío dado de baja, cuando pasa a Casa, sin confirmar la reactivación no '
      'se crea nada; confirmada, la ubicación se reactiva y la casa recibe su espacio',
      () async {
        await local.insertar(ubicacion(deletedAt: t0));
        encolador.encolados.clear();

        final pide = await ok(params());

        expect(pide, isA<ModificacionRequiereConfirmacion>());
        expect(await espacios(), isEmpty);
        expect(encolador.encolados, isEmpty);

        await ok(params(confirmadas: {ConfirmacionModificacion.reactivar}));

        final u = (await local.obtener('ub-1'))!;
        expect(u.tipo, TipoUbicacion.casa);
        expect(u.auditoria.deletedAt, isNull);
        final e = await activos();
        expect(e, hasLength(1));
        expect(e.single.numeroDepto, isNull);
        expect(e.single.deletedAt, isNull);
        expect(entidades(), ['ubicacion', 'espacio']);
      },
    );
  });

  group('QA #382 · una casa que va y viene nunca suma un segundo espacio', () {
    test('dado Edificio → Casa → Edificio → Negocio → Casa, cuando se guarda cada paso, queda un '
        'solo espacio activo y se encoló un solo insert de espacio', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();
      var base = t0;
      for (final tipo in [
        TipoUbicacion.casa,
        TipoUbicacion.edificio,
        TipoUbicacion.negocio,
        TipoUbicacion.casa,
      ]) {
        reloj = reloj.add(const Duration(minutes: 1));
        final r = await ok(params(tipo: tipo, base: base));
        expect(r, isA<UbicacionModificada>(), reason: tipo.name);
        base = (await local.obtener('ub-1'))!.auditoria.updatedAt;
        expect(await activos(), hasLength(1), reason: 'después de pasar a ${tipo.name}');
      }

      final inserts = encolador.encolados.where((c) => c.entidad == 'espacio').toList();
      expect(inserts, hasLength(1), reason: 'el segundo paso a Casa ya encuentra su espacio');
      expect(ids, 2, reason: 'un id por cada paso que reduce a un espacio (E→Casa y Neg→Casa)');
    });
  });

  group('QA #382 · acciones superpuestas', () {
    test('dado dos guardados a la vez de la misma edición, cuando terminan, hay un solo espacio '
        'activo y ninguno rompe', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();

      final rs = await Future.wait([modificar(params()), modificar(params())]);

      // Los dos leen antes de que escriba el primero: el segundo puede salir como «la ubicación
      // cambió» (es el control de edición concurrente de siempre), pero nunca como un error
      // inesperado ni dejando un segundo espacio.
      expect(rs.where((r) => r.isRight()), isNotEmpty);
      for (final r in rs.where((r) => r.isLeft())) {
        expect(r.swap().getOrElse(() => throw StateError('x')), isA<FailureUbicacionCambio>());
      }
      expect(await activos(), hasLength(1));
      expect(entidades().where((e) => e == 'espacio'), hasLength(1));
    });
  });

  group('QA #382 · quién lo crea', () {
    test('dado una ubicación de otro colportor, cuando la pasa a Casa quien edita, el espacio nace '
        'con quien edita en created_by y la ubicación conserva a su dueño', () async {
      await local.insertar(ubicacion(creadaPor: 'col-9'));

      await ok(params());

      expect((await local.obtener('ub-1'))!.auditoria.createdBy, 'col-9');
      final e = (await activos()).single;
      expect(e.createdBy, 'col-1');
    });
  });
}
