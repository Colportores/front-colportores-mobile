import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/espacio_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/espacio_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:dartz/dartz.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

/// Data source que responde con [resultado] o lanza [error]; anota cada llamada.
final class _LocalFijo implements EspacioLocalDataSource {
  _LocalFijo(this.modelo, {this.error});

  final EspacioModel modelo;
  final Object? error;
  final llamadas = <String>[];
  bool? incluirBajasRecibido;

  T _o<T>(String nombre, T valor) {
    llamadas.add(nombre);
    final e = error;
    if (e != null) throw e;
    return valor;
  }

  @override
  Future<InsercionEspacio> insertarEspacio(EspacioModel espacio) async =>
      _o('insertar', (espacio: modelo, yaEstaba: false));

  @override
  Future<EspacioModel> actualizarNumeroDepto(
    String id, {
    required String numeroDepto,
    required DateTime ahora,
  }) async => _o('actualizar', modelo);

  @override
  Future<EspacioModel> darDeBajaEspacio(String id, {required DateTime ahora}) async =>
      _o('baja', modelo);

  @override
  Future<EspacioModel> restaurarEspacio(String id, {required DateTime ahora}) async =>
      _o('restaurar', modelo);

  @override
  Future<({EspacioModel espacio, UbicacionModel ubicacion})?> buscarEspacio(String id) async =>
      _o('buscar', id == 'nada' ? null : (espacio: modelo, ubicacion: _ubicacion));

  @override
  Future<List<EspacioModel>> listarEspacios(String ubicacionId, {bool incluirBajas = false}) async {
    incluirBajasRecibido = incluirBajas;
    return _o('listar', [modelo]);
  }

  @override
  Future<int> contarEspaciosActivos(String ubicacionId) async => _o('contar', 3);
}

final _t0 = DateTime.utc(2026, 9, 29, 13, 45);

final _ubicacion = UbicacionModel(
  id: 'ub-1',
  tipo: TipoUbicacion.edificio,
  lat: -34.891,
  lon: -56.125,
  ciudadId: 'mvd',
  auditoria: Auditoria(createdAt: _t0, updatedAt: _t0, createdBy: 'col-1'),
);

Either<Failure, T> _ok<T>(T valor) => Right(valor);

Either<Failure, Never> _ko(Failure fallo) => Left(fallo);

void main() {
  final modelo = EspacioModel(
    id: 'esp-1',
    ubicacionId: 'ub-1',
    numeroDepto: '5B',
    auditoria: Auditoria(createdAt: _t0, updatedAt: _t0, createdBy: 'col-1'),
  );
  final entidad = modelo.toEntity();

  late _SalidaEnMemoria salida;

  setUp(() => salida = _SalidaEnMemoria());

  EspacioRepositoryImpl repo(EspacioLocalDataSource local) =>
      EspacioRepositoryImpl(local, logger: AppLogger(output: salida));

  group('camino feliz', () {
    test('agregar devuelve la entidad guardada', () async {
      expect(await repo(_LocalFijo(modelo)).agregar(entidad), _ok(entidad));
    });

    test('modificar, darDeBaja y restaurar devuelven la entidad', () async {
      final r = repo(_LocalFijo(modelo));

      expect(await r.modificar('esp-1', numeroDepto: '5B', ahora: _t0), _ok(entidad));
      expect(await r.darDeBaja('esp-1', ahora: _t0), _ok(entidad));
      expect(await r.restaurar('esp-1', ahora: _t0), _ok(entidad));
    });

    test('buscar devuelve el espacio con su ubicación, o null', () async {
      final r = repo(_LocalFijo(modelo));

      final encontrado = (await r.buscar('esp-1')).toOption().toNullable()!;
      expect(encontrado.espacio, entidad);
      expect(encontrado.ubicacion, _ubicacion.toEntity());
      expect(await r.buscar('nada'), const Right<Failure, EspacioConUbicacion?>(null));
    });

    test('listar y contarActivos devuelven lo del data source', () async {
      final local = _LocalFijo(modelo);
      final r = repo(local);

      expect(await r.listar('ub-1', incluirBajas: true), _ok([entidad]));
      expect(local.incluirBajasRecibido, isTrue);
      expect(await r.contarActivos('ub-1'), _ok(3));
    });
  });

  group('errores', () {
    test('un rechazo de la persistencia sale como FailureValidacion sin ensuciar el log de '
        'error, con el motivo y sin el número de departamento', () async {
      final r = repo(
        _LocalFijo(
          modelo,
          error: const EspacioRechazadoException(MotivoRechazoEspacio.deptoDuplicado),
        ),
      );

      final resultado = await r.agregar(entidad);

      expect(
        resultado,
        _ko(
          FailureValidacion(
            campos: {
              MotivoRechazoEspacio.deptoDuplicado.campo:
                  MotivoRechazoEspacio.deptoDuplicado.mensaje,
            },
          ),
        ),
      );
      expect(salida.lineas.single, startsWith('[INFO][DB][ESPACIO_ALTA_RECHAZADA]'));
      expect(salida.lineas.single, contains('"motivo":"deptoDuplicado"'));
      expect(salida.lineas.single, isNot(contains('5B')));
    });

    test('cualquier otra excepción sale como FailureInesperado y se loguea', () async {
      final r = repo(_LocalFijo(modelo, error: StateError('disco')));

      expect(
        (await r.darDeBaja('esp-1', ahora: _t0)).swap().toOption().toNullable(),
        isA<FailureInesperado>(),
      );
      expect(salida.lineas.first, startsWith('[ERROR][DB][ESPACIO_BAJA_FAIL]'));
    });
  });
}
