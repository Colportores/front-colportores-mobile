// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_modificacion_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ubicador_zona.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/modificar_ubicacion_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/zonas_falsas.dart';

typedef _Escritura = ({
  Ubicacion nueva,
  DateTime baseUpdatedAt,
  CriterioDuplicadoUbicacion? duplicados,
});

/// Un repositorio con una ubicación y N espacios, que anota lo que se le manda a escribir.
final class _Repositorio implements UbicacionRepository {
  _Repositorio(this.actual, {this.espacios = 0});

  Ubicacion? actual;
  int espacios;
  Failure? falloAlLeer;
  Either<Failure, ResultadoModificacionUbicacion>? respuesta;
  final escrituras = <_Escritura>[];

  @override
  Future<Either<Failure, Ubicacion?>> obtener(String id) async =>
      falloAlLeer != null ? Left(falloAlLeer!) : Right(actual);

  @override
  Future<Either<Failure, int>> contarEspaciosActivos(String ubicacionId) async => Right(espacios);

  @override
  Future<Either<Failure, ResultadoModificacionUbicacion>> modificar(
    Ubicacion nueva, {
    required DateTime baseUpdatedAt,
    CriterioDuplicadoUbicacion? duplicados,
  }) async {
    escrituras.add((nueva: nueva, baseUpdatedAt: baseUpdatedAt, duplicados: duplicados));
    return respuesta ?? Right(UbicacionModificada(ubicacion: nueva));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 10);
  final t1 = DateTime.utc(2026, 9, 30, 11);
  const italia = Coordenadas(lat: -34.891, lon: -56.125);

  /// Metros al norte de [italia] (mismo radio de la Tierra que `Coordenadas`).
  Coordenadas alNorte(double metros) =>
      Coordenadas(lat: italia.lat + metros / 111195.08, lon: italia.lon);

  Ubicacion ubicacion({
    TipoUbicacion tipo = TipoUbicacion.casa,
    String? calle = 'Av. Italia',
    String? numero = '1234',
    String ciudadId = 'mvd',
    DateTime? deletedAt,
  }) => Ubicacion(
    id: 'ub-1',
    tipo: tipo,
    calle: calle,
    numero: numero,
    lat: italia.lat,
    lon: italia.lon,
    ciudadId: ciudadId,
    zonaId: 'zona-9',
    auditoria: Auditoria(
      createdAt: t0,
      updatedAt: t0,
      createdBy: 'col-1',
      deletedAt: deletedAt,
      syncVersion: 4,
    ),
  );

  ModificarUbicacionParams params({
    String id = 'ub-1',
    TipoUbicacion tipo = TipoUbicacion.casa,
    Coordenadas coordenadas = italia,
    String? ciudadId = 'mvd',
    String? calle = 'Av. Italia',
    String? numero = '1234',
    Set<ConfirmacionModificacion> confirmadas = const {},
    String? justificacion,
    DateTime? base,
    String colportorId = 'col-1',
  }) => ModificarUbicacionParams(
    id: id,
    colportorId: colportorId,
    tipo: tipo,
    coordenadas: coordenadas,
    baseUpdatedAt: base ?? t0,
    ciudadId: ciudadId,
    calle: calle,
    numero: numero,
    confirmadas: confirmadas,
    justificacionDuplicado: justificacion,
  );

  late _Repositorio repo;
  late ZonasEnMemoria zonas;
  late InscripcionesEnMemoria inscripciones;
  late ModificarUbicacionUseCase modificar;

  setUp(() {
    repo = _Repositorio(ubicacion());
    zonas = ZonasEnMemoria();
    inscripciones = InscripcionesEnMemoria();
    modificar = ModificarUbicacionUseCase(
      repo,
      ubicador: UbicadorZona(zonas, inscripciones),
      ahora: () => t1,
    );
  });

  Future<ResultadoModificacionUbicacion> ok(ModificarUbicacionParams p) async =>
      (await modificar(p)).getOrElse(() => throw StateError('era un Left'));

  Future<Failure> falla(ModificarUbicacionParams p) async =>
      (await modificar(p)).swap().getOrElse(() => throw StateError('era un Right'));

  group('Validaciones', () {
    test(
      'dado un colportor en blanco, cuando modifica, falla la validación sin escribir',
      () async {
        final f = await falla(params(colportorId: ' '));

        expect((f as FailureValidacion).campos.keys, ['colportorId']);
        expect(repo.escrituras, isEmpty);
      },
    );

    test(
      'dado un id en blanco, cuando modifica, falla la validación sin leer ni escribir',
      () async {
        expect(await falla(params(id: '  ')), isA<FailureValidacion>());
        expect(repo.escrituras, isEmpty);
      },
    );

    test(
      'dado el punto en (0, 0) o fuera de rango, cuando modifica, falla la validación',
      () async {
        final cero = await falla(params(coordenadas: const Coordenadas(lat: 0, lon: 0)));
        final fuera = await falla(params(coordenadas: const Coordenadas(lat: 95, lon: 0)));

        expect((cero as FailureValidacion).campos.keys, ['coordenadas']);
        expect((fuera as FailureValidacion).campos.keys, ['coordenadas']);
        expect(repo.escrituras, isEmpty);
      },
    );

    test('dado que se saca la ciudad, cuando modifica, falla con la ciudad requerida', () async {
      expect(await falla(params(ciudadId: null)), isA<FailureCiudadRequerida>());
      expect(await falla(params(ciudadId: '  ')), isA<FailureCiudadRequerida>());
    });

    test('dado "seguir igual" con la justificación en blanco, cuando modifica, falla', () async {
      final f = await falla(params(numero: '1236', justificacion: '   '));

      expect((f as FailureValidacion).campos.keys, ['justificacion']);
    });

    test('dado una ubicación que no está, cuando modifica, falla como inexistente', () async {
      repo.actual = null;

      expect(await falla(params(numero: '1236')), isA<FailureUbicacionInexistente>());
    });

    test('dado que la lectura falla, cuando modifica, devuelve esa falla', () async {
      repo.falloAlLeer = const FailureUbicacionCambio();

      expect(await falla(params(numero: '1236')), const FailureUbicacionCambio());
    });
  });

  group('Edición simple de número de calle', () {
    test('dado el número "1234", cuando lo edita a "1236", escribe con updated_at nuevo y sin '
        'tocar sync_version, zona ni creador', () async {
      final r = await ok(params(numero: ' 1236 '));

      expect(r, isA<UbicacionModificada>());
      final w = repo.escrituras.single;
      expect(w.nueva.numero, '1236');
      expect(w.nueva.auditoria.updatedAt, t1);
      expect(w.baseUpdatedAt, t0);
      expect(w.nueva.auditoria.syncVersion, 4, reason: 'la versión base la sube el servidor');
      expect(w.nueva.auditoria.createdAt, t0);
      expect(w.nueva.auditoria.createdBy, 'col-1');
      expect(w.nueva.zonaId, 'zona-9');
      expect(w.nueva.id, 'ub-1');
    });

    test(
      'dado que la calle y el número quedan en blanco, cuando modifica, quedan sin cargar',
      () async {
        await ok(params(calle: '  ', numero: null));

        expect(repo.escrituras.single.nueva.calle, isNull);
        expect(repo.escrituras.single.nueva.numero, isNull);
      },
    );

    test('dado que nada cambia, cuando modifica, no escribe y avisa que no hubo cambios', () async {
      final r = await ok(params(calle: ' Av. Italia ', numero: '1234'));

      expect(r, ModificacionSinCambios(ubicacion: repo.actual!));
      expect(repo.escrituras, isEmpty);
    });
  });

  group('Edición concurrente', () {
    test('dado que la fila cambió desde que la pantalla la cargó, cuando guarda, falla como cambio '
        'concurrente sin escribir', () async {
      repo.actual = ubicacion(calle: 'Av. Italia');
      final cargada = t0.subtract(const Duration(minutes: 5));

      expect(await falla(params(numero: '1236', base: cargada)), const FailureUbicacionCambio());
      expect(repo.escrituras, isEmpty);
    });

    test('dado la base con la que se cargó, cuando guarda, se la pasa al repositorio y no la que '
        'releyó', () async {
      await ok(params(numero: '1236', base: t0));

      expect(repo.escrituras.single.baseUpdatedAt, t0);
    });

    test(
      'dado un doble toque (la fila ya tiene los valores pedidos y otra base), cuando guarda, es '
      'un éxito idempotente sin escribir',
      () async {
        final cargada = t0.subtract(const Duration(minutes: 5));

        final r = await ok(params(base: cargada));

        expect(r, UbicacionModificada(ubicacion: repo.actual!));
        expect(repo.escrituras, isEmpty);
      },
    );
  });

  group('Re-chequeo de duplicados', () {
    test('dado que cambia la calle, el número, el punto o la ciudad, cuando modifica, pide '
        'buscar duplicados en la escritura', () async {
      await ok(params(calle: 'Av. Brasil'));
      await ok(params(numero: '1236'));
      await ok(params(coordenadas: alNorte(20)));
      await ok(params(ciudadId: 'sal', confirmadas: {ConfirmacionModificacion.cambioCiudad}));

      expect(
        repo.escrituras.map((w) => w.duplicados),
        everyElement(isA<CriterioDuplicadoUbicacion>()),
      );
      expect(repo.escrituras, hasLength(4));
    });

    test('dado que solo cambia el tipo, cuando modifica, no busca duplicados', () async {
      await ok(params(tipo: TipoUbicacion.negocio));

      expect(repo.escrituras.single.duplicados, isNull);
    });

    test('dado D1 y "seguir igual" con motivo, cuando modifica, busca solo las candidatas que no '
        'admiten conservar las dos (la misma dirección a menos de 100 m)', () async {
      await ok(params(numero: '1236', justificacion: 'Son dos locales distintos'));

      expect(repo.escrituras.single.duplicados?.esSeguirIgual, isTrue);
    });

    test(
      'dado la regla anterior a D1 (opción (c)) y "seguir igual" con motivo, cuando modifica, no '
      'busca duplicados',
      () async {
        modificar = ModificarUbicacionUseCase(
          repo,
          ubicador: ubicadorSinZonas(),
          ahora: () => t1,
          criterio: const CriterioDuplicadoUbicacion(mismaDireccionAdmiteConservarAmbos: true),
        );

        await ok(params(numero: '1236', justificacion: 'Son dos locales distintos'));

        expect(repo.escrituras.single.duplicados, isNull);
      },
    );

    test(
      'dado que el repositorio encuentra candidatas, cuando modifica, las devuelve tal cual',
      () async {
        final otra = CandidataDuplicado(
          ubicacion: ubicacion(numero: '1236'),
          motivo: MotivoDuplicado.cercania,
          distanciaMetros: 3,
          admiteConservarAmbos: true,
        );
        repo.respuesta = Right(ModificacionConDuplicados(candidatas: [otra]));

        expect(await ok(params(numero: '1236')), ModificacionConDuplicados(candidatas: [otra]));
      },
    );
  });

  group('Cambio de tipo bloqueado', () {
    test(
      'dado un EDIFICIO con 3 espacios activos, cuando lo pasa a CASA o NEGOCIO, se bloquea con el '
      'texto literal y no se escribe',
      () async {
        repo = _Repositorio(ubicacion(tipo: TipoUbicacion.edificio), espacios: 3);
        modificar = ModificarUbicacionUseCase(repo, ubicador: ubicadorSinZonas(), ahora: () => t1);

        for (final tipo in [TipoUbicacion.casa, TipoUbicacion.negocio]) {
          final f = await falla(params(tipo: tipo));

          expect(f, const FailureUbicacionConEspacios(cantidadEspacios: 3));
          expect(f.mensaje, 'Esta ubicación tiene 3 espacios. Borralos o reubicalos primero.');
        }
        expect(repo.escrituras, isEmpty);
      },
    );

    test('dado un EDIFICIO con un solo espacio activo, el texto va en singular', () async {
      repo = _Repositorio(ubicacion(tipo: TipoUbicacion.edificio), espacios: 1);
      modificar = ModificarUbicacionUseCase(repo, ubicador: ubicadorSinZonas(), ahora: () => t1);

      final f = await falla(params(tipo: TipoUbicacion.casa));

      expect(f, const FailureUbicacionConEspacios(cantidadEspacios: 1));
      expect(f.mensaje, 'Esta ubicación tiene 1 espacio. Borralo o reubicalo primero.');
      expect(repo.escrituras, isEmpty);
    });

    test('dado un EDIFICIO sin espacios activos, cuando lo pasa a CASA, se permite', () async {
      repo = _Repositorio(ubicacion(tipo: TipoUbicacion.edificio));
      modificar = ModificarUbicacionUseCase(repo, ubicador: ubicadorSinZonas(), ahora: () => t1);

      expect(await ok(params(tipo: TipoUbicacion.casa)), isA<UbicacionModificada>());
    });

    test('dado una CASA con espacios, cuando pasa a EDIFICIO o NEGOCIO, no se bloquea', () async {
      repo.espacios = 2;

      expect(await ok(params(tipo: TipoUbicacion.edificio)), isA<UbicacionModificada>());
      expect(await ok(params(tipo: TipoUbicacion.negocio)), isA<UbicacionModificada>());
    });

    test('dado un EDIFICIO con espacios, cuando cambia solo el número, no se bloquea', () async {
      repo = _Repositorio(ubicacion(tipo: TipoUbicacion.edificio), espacios: 3);
      modificar = ModificarUbicacionUseCase(repo, ubicador: ubicadorSinZonas(), ahora: () => t1);

      expect(
        await ok(params(tipo: TipoUbicacion.edificio, numero: '1236')),
        isA<UbicacionModificada>(),
      );
    });
  });

  group('Confirmaciones', () {
    test('dado un desplazamiento de más de 100 m, cuando modifica, pide confirmar con la distancia '
        'y no escribe', () async {
      final r = await ok(params(coordenadas: alNorte(150)));

      expect(r, isA<ModificacionRequiereConfirmacion>());
      final pide = r as ModificacionRequiereConfirmacion;
      expect(pide.pendientes, {ConfirmacionModificacion.desplazamiento});
      expect(pide.desplazamientoMetros, closeTo(150, 0.5));
      expect(
        ModificacionRequiereConfirmacion.avisoDesplazamiento(pide.desplazamientoMetros!),
        'Las nuevas coordenadas están a 150m de la ubicación original. ¿Confirmás?',
      );
      expect(repo.escrituras, isEmpty);
    });

    test('dado el desplazamiento confirmado, cuando modifica, escribe', () async {
      final r = await ok(
        params(coordenadas: alNorte(150), confirmadas: {ConfirmacionModificacion.desplazamiento}),
      );

      expect(r, isA<UbicacionModificada>());
      expect(repo.escrituras.single.nueva.lat, alNorte(150).lat);
    });

    test('dado un desplazamiento de 100 m o menos, cuando modifica, no pide confirmar', () async {
      expect(await ok(params(coordenadas: alNorte(90))), isA<UbicacionModificada>());
    });

    test('dado un cambio de ciudad, cuando modifica, pide confirmar', () async {
      final r = await ok(params(ciudadId: 'sal'));

      expect((r as ModificacionRequiereConfirmacion).pendientes, {
        ConfirmacionModificacion.cambioCiudad,
      });
      expect(r.desplazamientoMetros, isNull);
      expect(repo.escrituras, isEmpty);
    });

    test('dado que faltan varias confirmaciones, cuando modifica, las pide todas juntas', () async {
      repo.actual = ubicacion(deletedAt: t0);

      final r = await ok(params(ciudadId: 'sal', coordenadas: alNorte(500)));

      expect((r as ModificacionRequiereConfirmacion).pendientes, {
        ConfirmacionModificacion.reactivar,
        ConfirmacionModificacion.cambioCiudad,
        ConfirmacionModificacion.desplazamiento,
      });
    });

    test('dado que confirma solo una de las que faltan, cuando modifica, pide las otras', () async {
      repo.actual = ubicacion(deletedAt: t0);

      final r = await ok(
        params(numero: '1236', confirmadas: {ConfirmacionModificacion.desplazamiento}),
      );

      expect((r as ModificacionRequiereConfirmacion).pendientes, {
        ConfirmacionModificacion.reactivar,
      });
    });
  });

  group('Ubicación dada de baja', () {
    setUp(() => repo.actual = ubicacion(deletedAt: t0));

    test(
      'dado una baja, cuando la edita sin confirmar, pide "¿Reactivarla al guardar?" y no escribe',
      () async {
        final r = await ok(params(numero: '1236'));

        expect((r as ModificacionRequiereConfirmacion).pendientes, {
          ConfirmacionModificacion.reactivar,
        });
        expect(
          ModificacionRequiereConfirmacion.avisoReactivar,
          'Esta ubicación está en baja. ¿Reactivarla al guardar?',
        );
        expect(repo.escrituras, isEmpty);
      },
    );

    test('dado que confirma reactivar, cuando la edita, se reactiva (deleted_at null) y busca '
        'duplicados aunque solo cambie el tipo', () async {
      final r = await ok(
        params(tipo: TipoUbicacion.negocio, confirmadas: {ConfirmacionModificacion.reactivar}),
      );

      expect((r as UbicacionModificada).reactivada, isTrue);
      final w = repo.escrituras.single;
      expect(w.nueva.auditoria.deletedAt, isNull);
      expect(w.duplicados, isA<CriterioDuplicadoUbicacion>());
    });

    test('dado una baja y ningún cambio, cuando modifica, no la reactiva ni escribe', () async {
      expect(await ok(params()), isA<ModificacionSinCambios>());
      expect(repo.escrituras, isEmpty);
    });

    test('dado una ubicación activa, cuando la edita, no figura como reactivada', () async {
      repo.actual = ubicacion();

      expect((await ok(params(numero: '1236')) as UbicacionModificada).reactivada, isFalse);
    });
  });

  group('Zona por posición', () {
    // Italia cae en «z-centro»; 150 m al norte, en «z-norte»; 2 km al norte, fuera de toda zona.
    setUp(() {
      zonas.zonas.addAll([
        zonaRectangular(
          'z-centro',
          latSur: -34.892,
          latNorte: italia.lat + 100 / 111195.08,
          lonOeste: -56.13,
          lonEste: -56.12,
        ),
        zonaRectangular(
          'z-norte',
          latSur: italia.lat + 100 / 111195.08,
          latNorte: italia.lat + 300 / 111195.08,
          lonOeste: -56.13,
          lonEste: -56.12,
        ),
      ]);
      inscripciones.inscripciones.add(inscripcion('col-1', 'camp-1', zonaId: 'z-centro'));
      inscripciones.inscripciones.add(inscripcion('col-2', 'camp-1', zonaId: 'z-centro'));
    });

    const confirmado = {ConfirmacionModificacion.desplazamiento};

    test('dado que mueve el pin dentro de otra zona, la ubicación queda con esa zona', () async {
      await ok(params(coordenadas: alNorte(150), confirmadas: confirmado));

      expect(repo.escrituras.single.nueva.zonaId, 'z-norte');
    });

    test('dado que mueve el pin fuera de toda zona, la ubicación queda sin zona', () async {
      await ok(params(coordenadas: alNorte(2000), confirmadas: confirmado));

      expect(repo.escrituras.single.nueva.zonaId, isNull);
    });

    test('dado que cambia la ciudad, la zona se calcula en la ciudad nueva', () async {
      await ok(params(ciudadId: 'canelones', confirmadas: {ConfirmacionModificacion.cambioCiudad}));

      expect(repo.escrituras.single.nueva.zonaId, isNull);
    });

    test('dado que no mueve el pin, conserva la zona que tenía', () async {
      await ok(params(numero: '1236'));

      expect(repo.escrituras.single.nueva.zonaId, 'zona-9');
    });

    group('una ubicación que registró otro colportor', () {
      test('movida fuera de las zonas de quien la mueve, se bloquea antes de pedir confirmaciones '
          'y no escribe nada', () async {
        final f = await falla(params(colportorId: 'col-2', coordenadas: alNorte(150)));

        expect(f, const FailureUbicacionAjenaFueraDeZona());
        expect(f.mensaje, contains('pedile a tu coordinador'));
        expect(repo.escrituras, isEmpty);
      });

      test('movida fuera de toda zona, se bloquea', () async {
        final f = await falla(
          params(colportorId: 'col-2', coordenadas: alNorte(2000), confirmadas: confirmado),
        );

        expect(f, isA<FailureUbicacionAjenaFueraDeZona>());
        expect(repo.escrituras, isEmpty);
      });

      test('movida dentro de una zona de quien la mueve, se guarda con esa zona', () async {
        await ok(params(colportorId: 'col-2', coordenadas: alNorte(50)));

        expect(repo.escrituras.single.nueva.zonaId, 'z-centro');
        expect(repo.escrituras.single.nueva.auditoria.createdBy, 'col-1');
      });

      test('sin moverla, se puede corregir aunque su zona no sea de quien la edita', () async {
        await ok(params(colportorId: 'col-3', numero: '1236'));

        expect(repo.escrituras.single.nueva.zonaId, 'zona-9');
      });
    });

    test('dado que la ubicación propia se mueve fuera de sus zonas, se guarda (solo se bloquean '
        'las ajenas)', () async {
      await ok(params(coordenadas: alNorte(150), confirmadas: confirmado));

      expect(repo.escrituras.single.nueva.zonaId, 'z-norte');
    });

    test(
      'dado que no se pueden leer las zonas al moverla, devuelve la falla sin escribir',
      () async {
        zonas.falla = const FailureInesperado();

        expect(await falla(params(coordenadas: alNorte(50))), const FailureInesperado());
        expect(repo.escrituras, isEmpty);
      },
    );
  });
}
