import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';
import '../../../../../helpers/ubicacion_sin_modificar.dart';

class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

/// Data source que responde lo que se le fije (o lanza [error]).
final class _LocalFijo with UbicacionLocalSinModificar implements UbicacionLocalDataSource {
  _LocalFijo({this.respuesta, this.error, this.lista = const Stream.empty()});

  final InsercionUbicacion? respuesta;
  final Object? error;
  final Stream<List<UbicacionConEspacios>> lista;
  ({String colportorId, bool incluirBajas})? listaPedida;
  CriterioDuplicadoUbicacion? duplicadosRecibido;
  EspacioModel? espacioRecibido;

  @override
  Future<InsercionUbicacion> insertar(
    UbicacionModel ubicacion, {
    EspacioModel? espacio,
    CriterioDuplicadoUbicacion? duplicados,
  }) async {
    duplicadosRecibido = duplicados;
    espacioRecibido = espacio;
    final e = error;
    if (e != null) throw e;
    return respuesta ?? (ubicacion: ubicacion, yaEstaba: false);
  }

  @override
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  }) => const Stream.empty();

  @override
  Stream<List<UbicacionModel>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) => const Stream.empty();

  @override
  Stream<List<UbicacionConEspacios>> observarListaDelColportor({
    required String colportorId,
    bool incluirBajas = false,
  }) {
    listaPedida = (colportorId: colportorId, incluirBajas: incluirBajas);
    return lista;
  }
}

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 13, 45);
  final ubicacion = Ubicacion(
    id: 'ub-1',
    tipo: TipoUbicacion.casa,
    calle: 'Av. Italia',
    numero: '1234',
    lat: -34.891,
    lon: -56.125,
    ciudadId: 'mvd',
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
  );
  final espacio = Espacio(
    id: 'esp-1',
    ubicacionId: 'ub-1',
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
  );
  const criterio = CriterioDuplicadoUbicacion();

  late _SalidaEnMemoria salida;

  setUp(() => salida = _SalidaEnMemoria());

  UbicacionRepositoryImpl repositorio(_LocalFijo local) =>
      UbicacionRepositoryImpl(local, logger: AppLogger(output: salida));

  group('UbicacionRepositoryImpl.registrar', () {
    test('dado un alta nueva, devuelve AltaRegistrada con la entidad y el espacio, y loguea solo '
        'ids y el coords_source', () async {
      final local = _LocalFijo();

      final r = await repositorio(local).registrar(
        ubicacion,
        espacio: espacio,
        origen: OrigenCoordenadas.manual,
        duplicados: criterio,
      );

      expect(
        r,
        Right<Failure, ResultadoAltaUbicacion>(
          AltaRegistrada(ubicacion: ubicacion, espacio: espacio),
        ),
      );
      expect(local.espacioRecibido, EspacioModel.fromEntity(espacio));
      expect(local.duplicadosRecibido, same(criterio));
      expect(salida.lineas.single, startsWith('[INFO][DB][UBICACION_CREADA]'));
      expect(salida.lineas.single, contains('"coords_source":"manual"'));
      expect(salida.lineas.single, contains('"crear_igual":false'));
      expect(salida.lineas.single, isNot(contains('Italia')));
    });

    test('dado que el alta ya estaba (mismo id), devuelve AltaRegistrada con la guardada y sin '
        'espacio', () async {
      final guardada = UbicacionModel.fromEntity(ubicacion);
      final local = _LocalFijo(respuesta: (ubicacion: guardada, yaEstaba: true));

      final r = await repositorio(
        local,
      ).registrar(ubicacion, espacio: espacio, origen: OrigenCoordenadas.gps);

      expect(r, Right<Failure, ResultadoAltaUbicacion>(AltaRegistrada(ubicacion: ubicacion)));
      expect(salida.lineas.single, startsWith('[INFO][DB][UBICACION_YA_REGISTRADA]'));
    });

    test('dado candidatas a duplicado, devuelve AltaConDuplicados con ellas y loguea sus ids y '
        'motivos sin la dirección', () async {
      final candidata = CandidataDuplicado(
        ubicacion: ubicacion,
        motivo: MotivoDuplicado.mismaDireccion,
        distanciaMetros: 120,
        admiteConservarAmbos: true,
      );
      final local = _LocalFijo(error: UbicacionDuplicadaException([candidata]));

      final r = await repositorio(
        local,
      ).registrar(ubicacion, origen: OrigenCoordenadas.gps, duplicados: criterio);

      expect(
        r.getOrElse(() => throw StateError('falló')),
        AltaConDuplicados(candidatas: [candidata]),
      );
      expect(salida.lineas.single, contains('"candidatas":["ub-1"]'));
      expect(salida.lineas.single, contains('"motivos":["mismaDireccion"]'));
      expect(salida.lineas.single, isNot(contains('Italia')));
    });

    test('dado "Crear igual" con D1 (criterio que solo frena la misma dirección a menos de 100 m), '
        'cuando guarda, el log lo marca como crear igual', () async {
      final alSeguirIgual = criterio.alSeguirIgual;

      await repositorio(
        _LocalFijo(),
      ).registrar(ubicacion, origen: OrigenCoordenadas.gps, duplicados: alSeguirIgual);

      expect(salida.lineas.single, contains('"crear_igual":true'));
    });

    test(
      'dado que el almacenamiento falla, devuelve FailureInesperado y loguea el error',
      () async {
        final local = _LocalFijo(error: StateError('disco lleno'));

        final r = await repositorio(local).registrar(ubicacion, origen: OrigenCoordenadas.gps);

        expect(r.fold((f) => f, (_) => null), isA<FailureInesperado>());
        expect(salida.lineas.first, startsWith('[ERROR][DB][UBICACION_ALTA_FAIL]'));
      },
    );

    test('la excepción de duplicado no imprime la dirección de las candidatas', () {
      final e = UbicacionDuplicadaException([
        CandidataDuplicado(
          ubicacion: ubicacion,
          motivo: MotivoDuplicado.cercania,
          distanciaMetros: 3,
          admiteConservarAmbos: true,
        ),
      ]);

      expect(e.toString(), 'UbicacionDuplicadaException(1)');
    });
  });
  group('UbicacionRepositoryImpl.observarListaDelColportor', () {
    test('devuelve entidades con sus espacios y sin estado (aún no hay house_status)', () async {
      final modelo = UbicacionModel.fromEntity(ubicacion);
      final local = _LocalFijo(
        lista: Stream.value([(ubicacion: modelo, cantidadEspacios: 3, motivoBaja: 'Ya no existe')]),
      );

      final lista = await UbicacionRepositoryImpl(
        local,
      ).observarListaDelColportor(colportorId: 'col-1', incluirBajas: true).first;

      expect(local.listaPedida, (colportorId: 'col-1', incluirBajas: true));
      expect(lista.single.ubicacion, ubicacion);
      expect(lista.single.cantidadEspacios, 3);
      expect(lista.single.motivoBaja, 'Ya no existe');
      expect(lista.single.estado, isNull);
      expect(lista.single.proximaEntrevista, isNull);
    });

    test('un error de lectura llega al stream', () async {
      final local = _LocalFijo(lista: Stream.error(StateError('db cerrada')));
      final repo = UbicacionRepositoryImpl(local);

      await expectLater(
        repo.observarListaDelColportor(colportorId: 'col-1'),
        emitsError(isA<StateError>()),
      );
    });
  });
}
