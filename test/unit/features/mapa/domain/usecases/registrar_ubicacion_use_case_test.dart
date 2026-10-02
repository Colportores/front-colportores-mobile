// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ubicador_zona.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/registrar_ubicacion_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';
import '../../../../../helpers/ubicacion_sin_modificar.dart';
import '../../../../../helpers/zonas_falsas.dart';

/// Registra lo que recibe y devuelve el alta hecha, salvo que se le fije otra respuesta.
final class _RepositorioQueAnota
    with UbicacionRepositorySinModificar
    implements UbicacionRepository {
  final llamadas =
      <
        ({
          Ubicacion ubicacion,
          Espacio? espacio,
          OrigenCoordenadas origen,
          CriterioDuplicadoUbicacion? duplicados,
        })
      >[];
  Either<Failure, ResultadoAltaUbicacion>? respuesta;

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
  }) async {
    llamadas.add((ubicacion: ubicacion, espacio: espacio, origen: origen, duplicados: duplicados));
    return respuesta ?? Right(AltaRegistrada(ubicacion: ubicacion, espacio: espacio));
  }

  @override
  Stream<List<Ubicacion>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) => const Stream.empty();
}

void main() {
  const italia = Coordenadas(lat: -34.891, lon: -56.125);
  final gpsPreciso = PuntoCapturado.gps(const LecturaGps(coordenadas: italia, precisionMetros: 12));
  final gpsImpreciso = PuntoCapturado.gps(
    const LecturaGps(coordenadas: italia, precisionMetros: 80),
  );
  final ahora = DateTime.utc(2026, 9, 29, 13, 45, 10, 123);

  late _RepositorioQueAnota repositorio;
  late ZonasEnMemoria zonas;
  late InscripcionesEnMemoria inscripciones;
  late RegistrarUbicacionUseCase registrar;
  late int ids;

  setUp(() {
    repositorio = _RepositorioQueAnota();
    zonas = ZonasEnMemoria();
    inscripciones = InscripcionesEnMemoria();
    ids = 0;
    registrar = RegistrarUbicacionUseCase(
      repositorio,
      generarId: () => 'id-${++ids}',
      ubicador: UbicadorZona(zonas, inscripciones),
      ahora: () => ahora,
    );
  });

  RegistrarUbicacionParams params({
    TipoUbicacion tipo = TipoUbicacion.casa,
    PuntoCapturado? punto,
    String? ciudadId = 'mvd',
    String? calle = 'Av. Italia',
    String? numero = '1234',
    String id = 'ub-form',
    bool confirmaBajaPrecision = false,
    String? justificacionDuplicado,
    String colportorId = 'col-1',
  }) => RegistrarUbicacionParams(
    colportorId: colportorId,
    tipo: tipo,
    punto: punto ?? gpsPreciso,
    ciudadId: ciudadId,
    calle: calle,
    numero: numero,
    id: id,
    confirmaBajaPrecision: confirmaBajaPrecision,
    justificacionDuplicado: justificacionDuplicado,
  );

  group('RegistrarUbicacionUseCase', () {
    group('Alta exitosa con GPS preciso', () {
      test('cuando registra una CASA en Av. Italia 1234, crea la ubicación con su id, el '
          'colportor como created_by y zona en null, y un espacio default vinculado', () async {
        final r = await registrar(params());

        expect(repositorio.llamadas, hasLength(1));
        final llamada = repositorio.llamadas.single;
        final u = llamada.ubicacion;
        expect(u.id, 'ub-form');
        expect(u.tipo, TipoUbicacion.casa);
        expect((u.calle, u.numero, u.lat, u.lon), ('Av. Italia', '1234', italia.lat, italia.lon));
        expect(u.ciudadId, 'mvd');
        expect(u.zonaId, isNull);
        expect(u.auditoria.createdBy, 'col-1');
        expect(u.auditoria.createdAt, ahora);
        expect(u.auditoria.updatedAt, ahora);
        expect(u.auditoria.syncVersion, 0);

        final espacio = llamada.espacio!;
        expect(espacio.id, 'id-1');
        expect(espacio.ubicacionId, 'ub-form');
        expect(espacio.numeroDepto, Espacio.deptoPorDefecto);
        expect(espacio.auditoria.createdBy, 'col-1');

        expect(llamada.origen, OrigenCoordenadas.gps);
        expect(llamada.duplicados, isNotNull, reason: 'valida duplicados');
        expect(
          r,
          Right<Failure, ResultadoAltaUbicacion>(AltaRegistrada(ubicacion: u, espacio: espacio)),
        );
      });

      for (final tipo in [TipoUbicacion.negocio, TipoUbicacion.edificio]) {
        test(
          'cuando registra un ${tipo.name}, no crea espacio default (Supuesto S13: solo CASA)',
          () async {
            await registrar(params(tipo: tipo));

            expect(repositorio.llamadas.single.espacio, isNull);
          },
        );
      }

      test('cuando la calle y el número vienen en blanco, se guardan como no cargados', () async {
        await registrar(params(calle: '   ', numero: ''));

        final u = repositorio.llamadas.single.ubicacion;
        expect(u.calle, isNull);
        expect(u.numero, isNull);
      });

      test('cuando calle y número traen espacios en los bordes, se guardan sin ellos pero con '
          'acentos y Ñ', () async {
        await registrar(params(calle: '  Ñandú Á ', numero: ' 12 bis '));

        final u = repositorio.llamadas.single.ubicacion;
        expect(u.calle, 'Ñandú Á');
        expect(u.numero, '12 bis');
      });
    });

    group('Alta sin GPS - colocación manual', () {
      test(
        'cuando el punto es un marcador manual, el alta procede igual y el origen es manual',
        () async {
          final r = await registrar(params(punto: const PuntoCapturado.manual(italia)));

          expect(r.isRight(), isTrue);
          expect(repositorio.llamadas.single.origen, OrigenCoordenadas.manual);
        },
      );
    });

    group('Alta con GPS impreciso - confirmación adicional', () {
      test('cuando la precisión es > 50 m y no confirmó, devuelve AltaConBajaPrecision y no crea '
          'nada', () async {
        final r = await registrar(params(punto: gpsImpreciso));

        expect(
          r,
          const Right<Failure, ResultadoAltaUbicacion>(AltaConBajaPrecision(precisionMetros: 80)),
        );
        expect(repositorio.llamadas, isEmpty);
        expect(
          AltaConBajaPrecision.aviso,
          'Tu ubicación tiene baja precisión. ¿Querés ajustar manualmente o continuar?',
        );
      });

      test('cuando la precisión es > 50 m y confirmó explícitamente, crea la ubicación', () async {
        final r = await registrar(params(punto: gpsImpreciso, confirmaBajaPrecision: true));

        expect(r.isRight(), isTrue);
        expect(repositorio.llamadas, hasLength(1));
      });
    });

    group('Detección de duplicado', () {
      test(
        'cuando el repositorio encuentra candidatas, devuelve AltaConDuplicados tal cual',
        () async {
          final candidata = CandidataDuplicado(
            ubicacion: await _unaUbicacion(registrar, params()),
            motivo: MotivoDuplicado.mismaDireccion,
            distanciaMetros: 40,
            admiteConservarAmbos: true,
          );
          repositorio.respuesta = Right(AltaConDuplicados(candidatas: [candidata]));

          final r = await registrar(params());

          expect(
            r,
            Right<Failure, ResultadoAltaUbicacion>(AltaConDuplicados(candidatas: [candidata])),
          );
        },
      );

      test('con D1, cuando elige "Crear igual" con justificación, pide validar solo las candidatas '
          'que no admiten conservar las dos (la misma dirección a menos de 100 m)', () async {
        await registrar(params(justificacionDuplicado: 'Es la casa del fondo'));

        expect(repositorio.llamadas.single.duplicados?.esSeguirIgual, isTrue);
      });

      test('con la regla anterior a D1 (opción (c)), cuando elige "Crear igual" con justificación, '
          'no pide validar duplicados', () async {
        registrar = RegistrarUbicacionUseCase(
          repositorio,
          generarId: () => 'id-opcion-c',
          ubicador: ubicadorSinZonas(),
          ahora: () => ahora,
          criterio: const CriterioDuplicadoUbicacion(mismaDireccionAdmiteConservarAmbos: true),
        );

        await registrar(params(justificacionDuplicado: 'Es la casa del fondo'));

        expect(repositorio.llamadas.single.duplicados, isNull);
      });

      test('cuando elige "Crear igual" con la justificación en blanco, devuelve FailureValidacion '
          'y no crea nada', () async {
        final r = await registrar(params(justificacionDuplicado: '   '));

        expect(r.fold((f) => f, (_) => null), isA<FailureValidacion>());
        expect(repositorio.llamadas, isEmpty);
      });
    });

    group('Error - ciudad no en catálogo', () {
      for (final ciudad in [null, '', '  ']) {
        test(
          'cuando no hay ciudad ("$ciudad"), devuelve FailureCiudadRequerida y no crea nada',
          () async {
            final r = await registrar(params(ciudadId: ciudad));

            expect(r, const Left<Failure, ResultadoAltaUbicacion>(FailureCiudadRequerida()));
            expect(repositorio.llamadas, isEmpty);
          },
        );
      }
    });

    group('Casos borde', () {
      test(
        'dado coordenadas (0, 0), cuando registra, devuelve FailureValidacion y no crea nada',
        () async {
          final r = await registrar(
            params(punto: const PuntoCapturado.manual(Coordenadas(lat: 0, lon: 0))),
          );

          expect(r.fold((f) => f, (_) => null), isA<FailureValidacion>());
          expect(repositorio.llamadas, isEmpty);
        },
      );

      test(
        'dado coordenadas fuera de rango, cuando registra, devuelve FailureValidacion',
        () async {
          final r = await registrar(
            params(punto: const PuntoCapturado.manual(Coordenadas(lat: -91, lon: 0))),
          );

          expect(r.fold((f) => f, (_) => null), isA<FailureValidacion>());
        },
      );

      test('dado un id de alta en blanco, cuando registra, devuelve FailureValidacion y no crea '
          'nada', () async {
        final r = await registrar(params(id: '  '));

        expect(r.fold((f) => f, (_) => null), isA<FailureValidacion>());
        expect(repositorio.llamadas, isEmpty);
      });

      test('dado un colportor en blanco, cuando registra, devuelve FailureValidacion', () async {
        final r = await registrar(params(colportorId: ' '));

        expect(r.fold((f) => f, (_) => null), isA<FailureValidacion>());
        expect(repositorio.llamadas, isEmpty);
      });

      test('dado el id del formulario, cuando registra dos veces (doble toque), usa el mismo id '
          'las dos veces', () async {
        final id = registrar.nuevoId();

        await registrar(params(id: id));
        await registrar(params(id: id));

        expect(repositorio.llamadas.map((l) => l.ubicacion.id), [id, id]);
      });

      test('dado un repositorio que falla, cuando registra, devuelve su Failure', () async {
        repositorio.respuesta = const Left(FailureInesperado());

        final r = await registrar(params());

        expect(r, const Left<Failure, ResultadoAltaUbicacion>(FailureInesperado()));
      });
    });

    test('dado stringify activado, cuando se imprimen los parámetros, no muestran la '
        'justificación', () {
      final original = EquatableConfig.stringify;
      addTearDown(() => EquatableConfig.stringify = original);
      EquatableConfig.stringify = true;

      final texto = params(justificacionDuplicado: 'La casa de Juan Pérez').toString();

      expect(texto, isNot(contains('Juan')));
    });

    group('Zona por posición', () {
      // Av. Italia 1234 cae en el rectángulo de «z-centro»; la zona «z-este» está al lado.
      setUp(() {
        zonas.zonas.addAll([
          zonaRectangular(
            'z-centro',
            latSur: -34.9,
            latNorte: -34.88,
            lonOeste: -56.13,
            lonEste: -56.12,
          ),
          zonaRectangular(
            'z-este',
            latSur: -34.9,
            latNorte: -34.88,
            lonOeste: -56.12,
            lonEste: -56.11,
          ),
        ]);
        inscripciones.inscripciones.add(inscripcion('col-1', 'camp-1', zonaId: 'z-este'));
      });

      test('dado un alta dentro de una zona, la ubicación queda con la zona que contiene el punto, '
          'aunque no sea la del colportor', () async {
        final r = await registrar(params());

        expect(r.isRight(), isTrue);
        expect(repositorio.llamadas.single.ubicacion.zonaId, 'z-centro');
      });

      test('dado un alta fuera de toda zona, la ubicación queda sin zona', () async {
        final lejos = PuntoCapturado.gps(
          const LecturaGps(coordenadas: Coordenadas(lat: -34.7, lon: -55.9), precisionMetros: 5),
        );

        await registrar(params(punto: lejos));

        expect(repositorio.llamadas.single.ubicacion.zonaId, isNull);
      });

      test('dado que no se pueden leer las zonas, no registra nada y devuelve la falla', () async {
        zonas.falla = const FailureInesperado();

        final r = await registrar(params());

        expect(r, const Left<Failure, ResultadoAltaUbicacion>(FailureInesperado()));
        expect(repositorio.llamadas, isEmpty);
      });

      test('dado un GPS impreciso sin confirmar, no hace falta ubicar el punto', () async {
        zonas.falla = const FailureInesperado();

        final r = await registrar(params(punto: gpsImpreciso));

        expect(r.getOrElse(() => throw StateError('falla')), isA<AltaConBajaPrecision>());
      });
    });
  });
}

/// Una ubicación armada por el caso de uso (para usarla como candidata).
Future<Ubicacion> _unaUbicacion(
  RegistrarUbicacionUseCase registrar,
  RegistrarUbicacionParams params,
) async {
  final r = await registrar(params);
  return r.fold((_) => throw StateError('sin alta'), (a) => (a as AltaRegistrada).ubicacion);
}
