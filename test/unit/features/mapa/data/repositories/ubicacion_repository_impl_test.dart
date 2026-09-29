import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

/// Data source que responde lo que se le fije (o lanza [error]).
final class _LocalFijo implements UbicacionLocalDataSource {
  _LocalFijo({this.respuesta, this.error});

  final InsercionUbicacion? respuesta;
  final Object? error;
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
  Stream<List<UbicacionModel>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) => const Stream.empty();
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

    test('dado candidatas a duplicado, devuelve AltaConDuplicados con entidades y loguea sus ids '
        'sin la dirección', () async {
      final candidata = UbicacionModel.fromEntity(ubicacion);
      final local = _LocalFijo(error: UbicacionDuplicadaException([candidata]));

      final r = await repositorio(
        local,
      ).registrar(ubicacion, origen: OrigenCoordenadas.gps, duplicados: criterio);

      final resultado = r.getOrElse(() => throw StateError('falló'));
      expect(resultado, AltaConDuplicados(candidatas: [ubicacion]));
      expect((resultado as AltaConDuplicados).candidatas.single.runtimeType, Ubicacion);
      expect(salida.lineas.single, contains('"candidatas":["ub-1"]'));
      expect(salida.lineas.single, isNot(contains('Italia')));
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
      final e = UbicacionDuplicadaException([UbicacionModel.fromEntity(ubicacion)]);

      expect(e.toString(), 'UbicacionDuplicadaException(1)');
    });
  });
}
