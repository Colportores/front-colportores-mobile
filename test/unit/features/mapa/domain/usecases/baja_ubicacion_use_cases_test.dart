// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests). La baja
// contra las tablas reales está en ubicacion_baja_drift_test.dart.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_baja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/consultor_pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/baja_ubicacion_use_cases.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/ubicacion_sin_modificar.dart';

final _t0 = DateTime.utc(2026, 9, 1, 10);
final _t1 = DateTime.utc(2026, 9, 12, 15);

Ubicacion _ubicacion({String id = 'ub-1', DateTime? deletedAt}) => Ubicacion(
  id: id,
  tipo: TipoUbicacion.casa,
  calle: 'Av. Italia',
  numero: '1240',
  lat: -34.891,
  lon: -56.125,
  ciudadId: 'mvd',
  auditoria: Auditoria(createdAt: _t0, updatedAt: _t0, createdBy: 'col-1', deletedAt: deletedAt),
);

final class _Repositorio with UbicacionRepositorySinModificar implements UbicacionRepository {
  final porId = <String, Ubicacion>{};
  final bajas = <({String id, bool baja, String? motivo, String? conservadaId})>[];

  @override
  Stream<List<Ubicacion>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Ubicacion?>> obtener(String id) async => Right(porId[id]);

  @override
  Future<Either<Failure, CambioDeBaja>> cambiarBaja(
    String id, {
    required bool baja,
    required DateTime baseUpdatedAt,
    required DateTime ahora,
    String? motivo,
    String? conservadaId,
  }) async {
    bajas.add((id: id, baja: baja, motivo: motivo, conservadaId: conservadaId));
    return Right((ubicacion: porId[id]!, escribio: true));
  }

  @override
  Future<Either<Failure, ResultadoAltaUbicacion>> registrar(
    Ubicacion ubicacion, {
    Espacio? espacio,
    required OrigenCoordenadas origen,
    CriterioDuplicadoUbicacion? duplicados,
  }) => throw UnimplementedError();

  @override
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  }) => throw UnimplementedError();
}

final class _Pendientes implements ConsultorPendientesUbicacion {
  PendientesUbicacion pendientes = PendientesUbicacion.ninguno;
  Failure? falla;
  final consultadas = <String>[];

  @override
  Future<Either<Failure, PendientesUbicacion>> de(String ubicacionId) async {
    consultadas.add(ubicacionId);
    return falla != null ? Left(falla!) : Right(pendientes);
  }
}

void main() {
  late _Repositorio repositorio;
  late _Pendientes pendientes;
  late DarDeBajaUbicacionUseCase darDeBaja;

  setUp(() {
    repositorio = _Repositorio()..porId['ub-1'] = _ubicacion();
    pendientes = _Pendientes();
    darDeBaja = DarDeBajaUbicacionUseCase(repositorio, pendientes, ahora: () => _t1);
  });

  DarDeBajaUbicacionParams params({
    String? motivo,
    bool confirma = false,
    String? conservadaId,
    DateTime? base,
  }) => DarDeBajaUbicacionParams(
    id: 'ub-1',
    baseUpdatedAt: base ?? _t0,
    motivo: motivo,
    confirmaPendientes: confirma,
    conservadaId: conservadaId,
  );

  Future<ResultadoBajaUbicacion> ok(DarDeBajaUbicacionParams p) async =>
      (await darDeBaja(p)).getOrElse(() => throw StateError('era un Left'));

  group('DarDeBajaUbicacionUseCase: el motivo', () {
    test(
      'dado un motivo con espacios, cuando da de baja, el repositorio recibe el motivo recortado',
      () async {
        await ok(params(motivo: '  Ya no existe '));

        expect(repositorio.bajas, [
          (id: 'ub-1', baja: true, motivo: 'Ya no existe', conservadaId: null),
        ]);
      },
    );

    test('dado un motivo en blanco, cuando da de baja, el repositorio recibe null (no se guarda '
        'nada)', () async {
      await ok(params(motivo: '   '));

      expect(repositorio.bajas.single.motivo, isNull);
    });

    test(
      'dado el texto libre de «Otro», cuando da de baja, el repositorio lo recibe tal cual',
      () async {
        await ok(params(motivo: 'Se mudó a Rivera'));

        expect(repositorio.bajas.single.motivo, 'Se mudó a Rivera');
      },
    );
  });

  group('DarDeBajaUbicacionUseCase: bloqueos', () {
    const cobranza = CobranzaPendiente(montoCentavos: 145000, numeroCuota: 2);

    test('dado una cobranza pendiente, cuando da de baja, devuelve el bloqueo con la cobranza y no '
        'escribe', () async {
      pendientes.pendientes = const PendientesUbicacion(
        cobranzaPendiente: cobranza,
        tieneVentas: true,
      );

      final r = await ok(params(motivo: 'Ya no existe'));

      expect(r, const BajaBloqueada(bloqueo: BloqueoPorCobranza(cobranza)));
      expect(repositorio.bajas, isEmpty);
    });

    test('dado ventas o una visita de otro colportor, cuando da de baja, devuelve el bloqueo de '
        'ventas o visitas ajenas y no escribe', () async {
      pendientes.pendientes = const PendientesUbicacion(tieneVisitasDeOtros: true);

      final r = await ok(params());

      expect(r, const BajaBloqueada(bloqueo: BloqueoPorVentasOVisitasAjenas()));
      expect(repositorio.bajas, isEmpty);
    });

    test('dado un bloqueo, cuando confirma pendientes igual, sigue bloqueada (la confirmación no '
        'salta un bloqueo)', () async {
      pendientes.pendientes = const PendientesUbicacion(tieneVentas: true);

      final r = await ok(params(confirma: true));

      expect(r, isA<BajaBloqueada>());
      expect(repositorio.bajas, isEmpty);
    });

    test('dado un bloqueo, cuando es la baja de la duplicada de una unión (conservadaId), procede '
        'y pasa la conservada al repositorio', () async {
      pendientes.pendientes = const PendientesUbicacion(tieneVentas: true);

      final r = await ok(params(conservadaId: 'ub-2'));

      expect(r, isA<UbicacionDadaDeBaja>());
      expect(repositorio.bajas.single.conservadaId, 'ub-2');
    });
  });

  group('DarDeBajaUbicacionUseCase: visitas pendientes propias', () {
    test('dado visitas pendientes propias, cuando da de baja sin confirmar, pide la confirmación '
        'con el resumen y no escribe', () async {
      pendientes.pendientes = const PendientesUbicacion(visitasPropiasPendientes: 2);

      final r = await ok(params());

      expect(r, isA<BajaRequiereConfirmacion>());
      expect(
        (r as BajaRequiereConfirmacion).pendientes.resumen.single,
        startsWith('Esta ubicación tiene 2 visitas pendientes.'),
      );
      expect(repositorio.bajas, isEmpty);
    });

    test('dado visitas pendientes propias, cuando confirma, da de baja', () async {
      pendientes.pendientes = const PendientesUbicacion(visitasPropiasPendientes: 2);

      final r = await ok(params(confirma: true));

      expect(r, isA<UbicacionDadaDeBaja>());
      expect(repositorio.bajas, hasLength(1));
    });
  });

  group('DarDeBajaUbicacionUseCase: el resto del flujo', () {
    test('dado que lo pendiente no se puede leer, cuando da de baja, devuelve esa falla', () async {
      pendientes.falla = const FailureInesperado();

      expect((await darDeBaja(params())).swap().toOption().toNullable(), isA<FailureInesperado>());
      expect(repositorio.bajas, isEmpty);
    });

    test('dado una ubicación que ya estaba de baja, cuando da de baja, no consulta lo pendiente ni '
        'escribe', () async {
      repositorio.porId['ub-1'] = _ubicacion(deletedAt: _t1);

      final r = await ok(params());

      expect(r, isA<BajaSinCambios>());
      expect(pendientes.consultadas, isEmpty);
      expect(repositorio.bajas, isEmpty);
    });

    test('dado que la fila cambió desde que se cargó la pantalla, cuando da de baja, falla como '
        'cambio reciente sin consultar lo pendiente', () async {
      final falla = (await darDeBaja(
        params(base: _t0.subtract(const Duration(seconds: 5))),
      )).swap().toOption().toNullable();

      expect(falla, isA<FailureBajaCambioReciente>());
      expect(pendientes.consultadas, isEmpty);
    });
  });

  group('ConsultarPendientesBajaUseCase', () {
    late ConsultarPendientesBajaUseCase consultar;

    setUp(() => consultar = ConsultarPendientesBajaUseCase(pendientes));

    test('dado una ubicación, cuando consulta, devuelve lo que sabe el consultor', () async {
      pendientes.pendientes = const PendientesUbicacion(visitasPropiasPendientes: 1);

      final r = (await consultar('ub-1')).getOrElse(() => throw StateError('era un Left'));

      expect(r.visitasPropiasPendientes, 1);
      expect(pendientes.consultadas, ['ub-1']);
    });

    test(
      'dado un id vacío, cuando consulta, falla de validación sin llamar al consultor',
      () async {
        final r = await consultar('  ');

        expect(r.swap().toOption().toNullable(), isA<FailureValidacion>());
        expect(pendientes.consultadas, isEmpty);
      },
    );

    test('dado que el consultor falla, cuando consulta, devuelve esa falla', () async {
      pendientes.falla = const FailureInesperado();

      expect((await consultar('ub-1')).swap().toOption().toNullable(), isA<FailureInesperado>());
    });
  });
}
