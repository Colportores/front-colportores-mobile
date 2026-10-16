// Casos de uso de la gestión de espacios (HU-UBI-007) contra un repositorio falso.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_baja_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/contador_personas_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/agregar_espacio_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/dar_de_baja_espacio_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/listar_espacios_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/modificar_espacio_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/restaurar_espacio_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

/// Repositorio que responde lo que se le fije y anota lo que recibe.
final class _RepoFalso implements EspacioRepository {
  Either<Failure, Espacio>? respuestaEscritura;
  Either<Failure, EspacioConUbicacion?> respuestaBuscar = _ok(null);
  Either<Failure, int> respuestaConteo = _ok(2);
  Either<Failure, List<Espacio>> respuestaListado = _ok([]);

  final llamadas = <String>[];
  Espacio? agregado;
  String? idRecibido;
  String? numeroRecibido;
  DateTime? ahoraRecibido;
  bool? incluirBajasRecibido;

  @override
  Future<Either<Failure, Espacio>> agregar(Espacio espacio) async {
    llamadas.add('agregar');
    agregado = espacio;
    return respuestaEscritura ?? _ok(espacio);
  }

  @override
  Future<Either<Failure, Espacio>> modificar(
    String id, {
    required String numeroDepto,
    required DateTime ahora,
  }) async {
    llamadas.add('modificar');
    idRecibido = id;
    numeroRecibido = numeroDepto;
    ahoraRecibido = ahora;
    return respuestaEscritura!;
  }

  @override
  Future<Either<Failure, Espacio>> darDeBaja(String id, {required DateTime ahora}) async {
    llamadas.add('darDeBaja');
    idRecibido = id;
    ahoraRecibido = ahora;
    return respuestaEscritura!;
  }

  @override
  Future<Either<Failure, Espacio>> restaurar(String id, {required DateTime ahora}) async {
    llamadas.add('restaurar');
    idRecibido = id;
    ahoraRecibido = ahora;
    return respuestaEscritura!;
  }

  @override
  Future<Either<Failure, EspacioConUbicacion?>> buscar(String id) async => respuestaBuscar;

  @override
  Future<Either<Failure, List<Espacio>>> listar(
    String ubicacionId, {
    bool incluirBajas = false,
  }) async {
    llamadas.add('listar');
    idRecibido = ubicacionId;
    incluirBajasRecibido = incluirBajas;
    return respuestaListado;
  }

  @override
  Future<Either<Failure, int>> contarActivos(String ubicacionId) async => respuestaConteo;
}

final class _PersonasFalsas implements ContadorPersonasEspacio {
  _PersonasFalsas(this.cantidad, {this.error});

  final int cantidad;
  final Object? error;

  @override
  Future<int> activasEn(String espacioId) async {
    final e = error;
    if (e != null) throw e;
    return cantidad;
  }
}

Either<Failure, T> _ok<T>(T valor) => Right(valor);

Either<Failure, Never> _ko(Failure fallo) => Left(fallo);

void main() {
  final t0 = DateTime.utc(2026, 9, 1, 13, 45);
  DateTime ahora() => t0;

  Ubicacion ubicacion({TipoUbicacion tipo = TipoUbicacion.edificio}) => Ubicacion(
    id: 'ub-1',
    tipo: tipo,
    lat: -34.891,
    lon: -56.125,
    ciudadId: 'mvd',
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
  );

  Espacio espacio({DateTime? deletedAt, String? numeroDepto = '5B'}) => Espacio(
    id: 'esp-1',
    ubicacionId: 'ub-1',
    numeroDepto: numeroDepto,
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1', deletedAt: deletedAt),
  );

  late _RepoFalso repo;

  setUp(() => repo = _RepoFalso());

  group('AgregarEspacioUseCase', () {
    late AgregarEspacioUseCase useCase;

    setUp(() => useCase = AgregarEspacioUseCase(repo, generarId: () => 'id-nuevo', ahora: ahora));

    test('dado los datos completos, cuando agrega, arma el espacio con el número sin espacios '
        'en los bordes y la auditoría del colportor', () async {
      final r = await useCase(
        const AgregarEspacioParams(
          id: 'esp-1',
          ubicacionId: 'ub-1',
          colportorId: 'col-1',
          numeroDepto: '  Apto 5B ',
        ),
      );

      expect(
        repo.agregado,
        Espacio(
          id: 'esp-1',
          ubicacionId: 'ub-1',
          numeroDepto: 'Apto 5B',
          auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
        ),
      );
      expect(r, _ok(repo.agregado));
    });

    test('dado el número en blanco y sin id, ubicación ni colportor, cuando agrega, devuelve '
        'la validación de cada campo y no llama al repositorio', () async {
      final r = await useCase(
        const AgregarEspacioParams(id: ' ', ubicacionId: '', colportorId: ' ', numeroDepto: ' '),
      );

      expect(
        r,
        _ko(
          const FailureValidacion(
            campos: {
              'id': 'Falta el identificador del alta del espacio',
              'ubicacionId': 'Falta la ubicación del espacio',
              'colportorId': 'No hay un colportor para registrar el espacio',
              'numeroDepto': 'Ingresá el número o nombre del espacio.',
            },
          ),
        ),
      );
      expect(repo.llamadas, isEmpty);
    });

    test('dado que el repositorio rechaza, cuando agrega, devuelve ese fallo', () async {
      const fallo = FailureValidacion(campos: {'numeroDepto': 'repetido'});
      repo.respuestaEscritura = _ko(fallo);

      final r = await useCase(
        const AgregarEspacioParams(
          id: 'esp-1',
          ubicacionId: 'ub-1',
          colportorId: 'col-1',
          numeroDepto: '5B',
        ),
      );

      expect(r, _ko(fallo));
    });

    test('nuevoId devuelve un id del generador', () {
      expect(useCase.nuevoId(), 'id-nuevo');
    });

    test('sin ahora, usa el reloj del sistema', () async {
      final sinReloj = AgregarEspacioUseCase(repo, generarId: () => 'x');

      await sinReloj(
        const AgregarEspacioParams(
          id: 'esp-1',
          ubicacionId: 'ub-1',
          colportorId: 'col-1',
          numeroDepto: '5B',
        ),
      );

      expect(repo.agregado!.auditoria.createdAt.isAfter(t0), isTrue);
    });
  });

  group('ModificarEspacioUseCase', () {
    late ModificarEspacioUseCase useCase;

    setUp(() => useCase = ModificarEspacioUseCase(repo, ahora: ahora));

    test('dado un número con espacios, cuando modifica, lo pasa limpio con la hora', () async {
      repo.respuestaEscritura = _ok(espacio(numeroDepto: '5C'));

      final r = await useCase(const ModificarEspacioParams(id: ' esp-1 ', numeroDepto: ' 5C '));

      expect(repo.idRecibido, 'esp-1');
      expect(repo.numeroRecibido, '5C');
      expect(repo.ahoraRecibido, t0);
      expect(r, _ok(espacio(numeroDepto: '5C')));
    });

    test(
      'dado el número o el id en blanco, devuelve la validación sin llamar al repositorio',
      () async {
        final r = await useCase(const ModificarEspacioParams(id: '', numeroDepto: ' '));

        expect(
          r,
          _ko(
            const FailureValidacion(
              campos: {
                'id': 'Falta el espacio a modificar',
                'numeroDepto': 'Ingresá el número o nombre del espacio.',
              },
            ),
          ),
        );
        expect(repo.llamadas, isEmpty);
      },
    );

    test('sin ahora, usa el reloj del sistema', () async {
      repo.respuestaEscritura = _ok(espacio());

      await ModificarEspacioUseCase(repo)(
        const ModificarEspacioParams(id: 'esp-1', numeroDepto: '5B'),
      );

      expect(repo.ahoraRecibido!.isAfter(t0), isTrue);
    });
  });

  group('DarDeBajaEspacioUseCase', () {
    DarDeBajaEspacioUseCase useCase(int personas, {Object? error}) =>
        DarDeBajaEspacioUseCase(repo, _PersonasFalsas(personas, error: error), ahora: ahora);

    void hayEspacio({TipoUbicacion tipo = TipoUbicacion.edificio, DateTime? deletedAt}) {
      repo.respuestaBuscar = _ok((
        espacio: espacio(deletedAt: deletedAt),
        ubicacion: ubicacion(tipo: tipo),
      ));
      repo.respuestaEscritura = _ok(espacio(deletedAt: t0));
    }

    test('dado un espacio sin personas, cuando lo da de baja, lo baja', () async {
      hayEspacio();

      final r = await useCase(0)(const DarDeBajaEspacioParams(id: 'esp-1'));

      expect(repo.llamadas, ['darDeBaja']);
      expect(repo.ahoraRecibido, t0);
      expect(r, _ok(BajaRealizada(espacio(deletedAt: t0))));
    });

    test('dado el último espacio activo sin personas, cuando lo da de baja, lo baja: el mínimo '
        'de 1 solo protege a las personas', () async {
      hayEspacio();
      repo.respuestaConteo = _ok(1);

      final r = await useCase(0)(const DarDeBajaEspacioParams(id: 'esp-1'));

      expect(r.isRight(), isTrue);
      expect(repo.llamadas, ['darDeBaja']);
    });

    test('dado un espacio con 2 personas, cuando lo da de baja sin confirmar, pide '
        'confirmación con el aviso de la HU y no escribe', () async {
      hayEspacio();

      final r = await useCase(2)(const DarDeBajaEspacioParams(id: 'esp-1'));

      expect(r, _ok(const BajaRequiereConfirmacion(personas: 2)));
      expect(
        (r.toOption().toNullable()! as BajaRequiereConfirmacion).aviso,
        'Este espacio tiene 2 personas. Sus datos se conservarán pero el espacio quedará '
        'marcado como baja.',
      );
      expect(repo.llamadas, isEmpty);
    });

    test('dado un espacio con personas, cuando confirma, lo baja', () async {
      hayEspacio();

      final r = await useCase(2)(
        const DarDeBajaEspacioParams(id: 'esp-1', confirmaConPersonas: true),
      );

      expect(r, _ok(BajaRealizada(espacio(deletedAt: t0))));
      expect(repo.llamadas, ['darDeBaja']);
    });

    test('dado el único espacio activo con personas, cuando lo da de baja (aun confirmando), lo '
        'bloquea con el mensaje de la HU', () async {
      hayEspacio();
      repo.respuestaConteo = _ok(1);

      final r = await useCase(1)(
        const DarDeBajaEspacioParams(id: 'esp-1', confirmaConPersonas: true),
      );

      expect(r, _ko(const FailureUltimoEspacioConPersonas()));
      expect(
        const FailureUltimoEspacioConPersonas().mensaje,
        'No podés borrar el último espacio activo con personas. Agregá otro o reubicá las '
        'personas primero.',
      );
      expect(repo.llamadas, isEmpty);
    });

    test('dado un espacio ya dado de baja, cuando lo da de baja, devuelve lo que estaba sin '
        'escribir', () async {
      hayEspacio(deletedAt: t0);

      final r = await useCase(3)(const DarDeBajaEspacioParams(id: 'esp-1'));

      expect(r, _ok(BajaRealizada(espacio(deletedAt: t0))));
      expect(repo.llamadas, isEmpty);
    });

    test('dado el espacio de una casa, lo rechaza', () async {
      hayEspacio(tipo: TipoUbicacion.casa);

      final r = await useCase(0)(const DarDeBajaEspacioParams(id: 'esp-1'));

      expect(
        r,
        _ko(
          FailureValidacion(
            campos: {
              MotivoRechazoEspacio.ubicacionCasa.campo: MotivoRechazoEspacio.ubicacionCasa.mensaje,
            },
          ),
        ),
      );
    });

    test('dado un espacio que no existe, lo rechaza', () async {
      final r = await useCase(0)(const DarDeBajaEspacioParams(id: 'nada'));

      expect(
        r,
        _ko(
          FailureValidacion(
            campos: {
              MotivoRechazoEspacio.espacioInexistente.campo:
                  MotivoRechazoEspacio.espacioInexistente.mensaje,
            },
          ),
        ),
      );
    });

    test('dado un id en blanco, devuelve la validación', () async {
      final r = await useCase(0)(const DarDeBajaEspacioParams(id: ' '));

      expect(r, _ko(const FailureValidacion(campos: {'id': 'Falta el espacio a dar de baja'})));
    });

    test('dado que falla la búsqueda o el conteo, devuelve ese fallo', () async {
      const fallo = FailureInesperado();
      repo.respuestaBuscar = _ko(fallo);
      expect(await useCase(0)(const DarDeBajaEspacioParams(id: 'esp-1')), _ko(fallo));

      hayEspacio();
      repo.respuestaConteo = _ko(fallo);
      expect(await useCase(1)(const DarDeBajaEspacioParams(id: 'esp-1')), _ko(fallo));
    });

    test('dado que el contador de personas falla, devuelve FailureInesperado', () async {
      hayEspacio();

      final r = await useCase(0, error: StateError('x'))(const DarDeBajaEspacioParams(id: 'esp-1'));

      expect(r.swap().toOption().toNullable(), isA<FailureInesperado>());
      expect(repo.llamadas, isEmpty);
    });

    test('dado que el repositorio falla al escribir, devuelve ese fallo', () async {
      hayEspacio();
      repo.respuestaEscritura = _ko(const FailureInesperado());

      expect(
        await useCase(0)(const DarDeBajaEspacioParams(id: 'esp-1')),
        _ko(const FailureInesperado()),
      );
    });

    test('sin ahora, usa el reloj del sistema', () async {
      hayEspacio();

      await DarDeBajaEspacioUseCase(repo, _PersonasFalsas(0))(
        const DarDeBajaEspacioParams(id: 'esp-1'),
      );

      expect(repo.ahoraRecibido!.isAfter(t0), isTrue);
    });
  });

  group('RestaurarEspacioUseCase', () {
    test('dado un id, cuando restaura, lo pasa con la hora', () async {
      repo.respuestaEscritura = _ok(espacio());

      final r = await RestaurarEspacioUseCase(repo, ahora: ahora)(
        const RestaurarEspacioParams(id: ' esp-1 '),
      );

      expect(repo.idRecibido, 'esp-1');
      expect(repo.ahoraRecibido, t0);
      expect(r, _ok(espacio()));
    });

    test('dado un id en blanco, devuelve la validación sin llamar al repositorio', () async {
      final r = await RestaurarEspacioUseCase(repo)(const RestaurarEspacioParams(id: ''));

      expect(r, _ko(const FailureValidacion(campos: {'id': 'Falta el espacio a restaurar'})));
      expect(repo.llamadas, isEmpty);
    });

    test('sin ahora, usa el reloj del sistema', () async {
      repo.respuestaEscritura = _ok(espacio());

      await RestaurarEspacioUseCase(repo)(const RestaurarEspacioParams(id: 'esp-1'));

      expect(repo.ahoraRecibido!.isAfter(t0), isTrue);
    });
  });

  group('ListarEspaciosUseCase', () {
    test('dado una ubicación, cuando lista, pide los activos por defecto', () async {
      repo.respuestaListado = _ok([espacio()]);

      final r = await ListarEspaciosUseCase(repo)(
        const ListarEspaciosParams(ubicacionId: ' ub-1 '),
      );

      expect(repo.idRecibido, 'ub-1');
      expect(repo.incluirBajasRecibido, isFalse);
      expect(r.toOption().toNullable(), [espacio()]);
    });

    test('dado incluirBajas, lo pasa al repositorio', () async {
      await ListarEspaciosUseCase(repo)(
        const ListarEspaciosParams(ubicacionId: 'ub-1', incluirBajas: true),
      );

      expect(repo.incluirBajasRecibido, isTrue);
    });

    test('dado una ubicación en blanco, devuelve la validación', () async {
      final r = await ListarEspaciosUseCase(repo)(const ListarEspaciosParams(ubicacionId: ' '));

      expect(r, _ko(const FailureValidacion(campos: {'ubicacionId': 'Falta la ubicación'})));
      expect(repo.llamadas, isEmpty);
    });
  });
}
