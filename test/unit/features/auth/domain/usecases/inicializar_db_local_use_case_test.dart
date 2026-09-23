// HU-AUTH-009 — orquestación de la inicialización de la DB local, con el repositorio y la vigencia
// de sesión en memoria. La derivación es un Completer que el test controla: así se puede cerrar la
// sesión justo mientras "se deriva".
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/db_local_repository.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/vigencia_sesion.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/inicializar_db_local_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

/// Dispositivo simulado: marca, sal y archivo, más el registro de qué se pidió y en qué orden.
final class _RepoEnMemoria implements DbLocalRepository {
  bool marca = false;
  bool archivo = false;
  bool abierta = false;
  Uint8List? sal;

  final llamadas = <String>[];
  final claves = <ClaveDb>[];
  final salesDerivadas = <Uint8List>[];

  /// Falla a devolver por operación (`estado`, `leerSal`, `generarSal`, `derivar`, `abrir`,
  /// `marcar`, `descartar`).
  final fallas = <String, Failure>{};

  /// Si está, la derivación espera a que el test lo complete.
  Completer<void>? derivacionPendiente;

  /// Se completa cuando alguien pide derivar.
  final pidioDerivar = Completer<void>();

  int _generadas = 0;

  Either<Failure, T> _o<T>(String op, T Function() valor) {
    llamadas.add(op);
    final falla = fallas[op];
    return falla != null ? Left(falla) : Right(valor());
  }

  @override
  Future<Either<Failure, EstadoDbLocal>> estado() async =>
      _o('estado', () => EstadoDbLocal(inicializada: marca, archivoExiste: archivo));

  @override
  Future<Either<Failure, Uint8List?>> leerSal() async => _o('leerSal', () => sal);

  @override
  Future<Either<Failure, Uint8List>> generarSal() async => _o('generarSal', () {
    final nueva = Uint8List.fromList(List<int>.filled(32, ++_generadas));
    sal = nueva;
    return nueva;
  });

  @override
  Future<Either<Failure, ClaveDb>> derivarClave({
    required String password,
    required Uint8List sal,
  }) async {
    salesDerivadas.add(sal);
    if (!pidioDerivar.isCompleted) pidioDerivar.complete();
    await derivacionPendiente?.future;
    return _o('derivar', () {
      final clave = ClaveDb(Uint8List.fromList(List<int>.filled(32, sal.first)));
      claves.add(clave);
      return clave;
    });
  }

  @override
  Future<Either<Failure, Unit>> abrir(ClaveDb clave) async {
    final r = _o('abrir', () => unit);
    if (r.isLeft()) {
      clave.destruir();
    } else {
      abierta = true;
      archivo = true;
    }
    return r;
  }

  @override
  Future<Either<Failure, Unit>> marcarInicializada() async {
    final r = _o('marcar', () => unit);
    if (r.isRight()) marca = true;
    return r;
  }

  @override
  Future<Either<Failure, Unit>> descartar() async {
    final r = _o('descartar', () => unit);
    if (r.isRight()) {
      abierta = false;
      archivo = false;
      marca = false;
      sal = null;
    }
    return r;
  }
}

final class _Testigo implements TestigoSesion {
  bool vigente = true;

  @override
  bool get sigueVigente => vigente;
}

final class _Vigencia implements VigenciaSesion {
  bool haySesion = true;
  final testigo = _Testigo();

  /// Simula el cierre de sesión: el testigo que ya se entregó deja de valer.
  void cerrarSesion() {
    haySesion = false;
    testigo.vigente = false;
  }

  @override
  TestigoSesion? tomarTestigo() => haySesion ? testigo : null;
}

void main() {
  late _RepoEnMemoria repo;
  late _Vigencia vigencia;
  late InicializarDbLocalUseCase useCase;
  late List<PasoInicializacionDb> pasos;

  setUp(() {
    repo = _RepoEnMemoria();
    vigencia = _Vigencia();
    useCase = InicializarDbLocalUseCase(repo, vigencia);
    pasos = [];
  });

  Future<Either<Failure, ResultadoInicializacionDb>> inicializar([
    String password = 'secreto123',
  ]) => useCase(InicializarDbLocalParams(password: password, alAvanzar: pasos.add));

  /// Dispositivo ya inicializado en un login anterior.
  void dispositivoInicializado() {
    repo
      ..marca = true
      ..archivo = true
      ..sal = Uint8List.fromList(List<int>.filled(32, 77));
  }

  group('primer login', () {
    test('dado un dispositivo nuevo, limpia, genera la sal, deriva con ella, crea la DB y recién '
        'al final marca el dispositivo', () async {
      final r = await inicializar();

      expect(r, const Right<Failure, ResultadoInicializacionDb>(ResultadoInicializacionDb.creada));
      expect(repo.llamadas, ['estado', 'descartar', 'generarSal', 'derivar', 'abrir', 'marcar']);
      expect(repo.salesDerivadas.single, same(repo.sal), reason: 'deriva con la sal que guardó');
      expect(repo.abierta, isTrue);
      expect(repo.marca, isTrue);
      expect(pasos, [
        PasoInicializacionDb.generandoSal,
        PasoInicializacionDb.derivandoClave,
        PasoInicializacionDb.abriendoDb,
      ]);
    });

    test('dado marca sin archivo (iOS tras reinstalar), lo trata como dispositivo nuevo', () async {
      repo
        ..marca = true
        ..sal = Uint8List.fromList(List<int>.filled(32, 77));

      final r = await inicializar();

      expect(r.isRight(), isTrue);
      expect(repo.llamadas, isNot(contains('leerSal')));
      expect(repo.llamadas.take(3), ['estado', 'descartar', 'generarSal']);
    });

    test(
      'dado el archivo sin sal, lo trata como dispositivo nuevo y descarta el archivo',
      () async {
        repo
          ..marca = true
          ..archivo = true;

        final r = await inicializar();

        expect(
          r,
          const Right<Failure, ResultadoInicializacionDb>(ResultadoInicializacionDb.creada),
        );
        expect(repo.llamadas.take(4), ['estado', 'leerSal', 'descartar', 'generarSal']);
      },
    );

    test('dado una inicialización interrumpida (sal y archivo sin marca), parte desde cero con '
        'otra sal', () async {
      final vieja = Uint8List.fromList(List<int>.filled(32, 99));
      repo
        ..archivo = true
        ..sal = vieja;

      final r = await inicializar();

      expect(r.isRight(), isTrue);
      expect(repo.llamadas.take(3), ['estado', 'descartar', 'generarSal']);
      expect(repo.salesDerivadas.single, isNot(equals(vieja)));
    });

    test(
      'dado un segundo intento tras un error, no reutiliza la sal del intento anterior',
      () async {
        repo.fallas['abrir'] = const FailureSinEspacio();
        await inicializar();
        final primera = repo.salesDerivadas.single;
        repo.fallas.clear();

        final r = await inicializar();

        expect(r.isRight(), isTrue);
        expect(repo.salesDerivadas.last, isNot(equals(primera)));
      },
    );

    for (final (paso, falla) in [
      ('generarSal', const FailureAlmacenSeguro()),
      ('derivar', const FailureInesperado()),
      ('abrir', const FailureSinEspacio()),
      ('marcar', const FailureAlmacenSeguro()),
    ]) {
      test('dado que falla $paso, deja el dispositivo limpio y devuelve esa falla', () async {
        repo.fallas[paso] = falla;

        final r = await inicializar();

        expect(r, Left<Failure, ResultadoInicializacionDb>(falla));
        expect(repo.llamadas.last, 'descartar', reason: 'limpia lo que haya quedado a medias');
        expect(repo.marca, isFalse);
        expect(repo.sal, isNull);
        expect(repo.archivo, isFalse);
        expect(repo.abierta, isFalse);
      });
    }

    test('dado que no puede limpiar al empezar, no genera una sal nueva', () async {
      repo.fallas['descartar'] = const FailureInesperado();

      final r = await inicializar();

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureInesperado()));
      expect(repo.llamadas, ['estado', 'descartar']);
    });

    test('dado que también falla la limpieza posterior, devuelve la falla original', () async {
      // La primera limpieza (al empezar) anda; la del aborto falla.
      final conLimpiezaRota = _RepoQueFallaAlSegundoDescarte();
      conLimpiezaRota.fallas['abrir'] = const FailureSinEspacio();
      repo = conLimpiezaRota;
      useCase = InicializarDbLocalUseCase(repo, vigencia);

      final r = await inicializar();

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSinEspacio()));
      expect(conLimpiezaRota.descartes, 2);
    });
  });

  group('login posterior', () {
    setUp(dispositivoInicializado);

    test('dado un dispositivo inicializado, deriva con la sal guardada y abre sin tocar nada '
        'más', () async {
      final guardada = repo.sal;

      final r = await inicializar();

      expect(r, const Right<Failure, ResultadoInicializacionDb>(ResultadoInicializacionDb.abierta));
      expect(repo.llamadas, ['estado', 'leerSal', 'derivar', 'abrir']);
      expect(repo.salesDerivadas.single, same(guardada));
      expect(pasos, [PasoInicializacionDb.derivandoClave, PasoInicializacionDb.abriendoDb]);
    });

    for (final (paso, falla) in [
      ('leerSal', const FailureAlmacenSeguro()),
      ('derivar', const FailureInesperado()),
      ('abrir', const FailureClaveDbIncorrecta()),
    ]) {
      test('dado que falla $paso, devuelve la falla y no borra la DB existente', () async {
        repo.fallas[paso] = falla;

        final r = await inicializar();

        expect(r, Left<Failure, ResultadoInicializacionDb>(falla));
        expect(repo.llamadas, isNot(contains('descartar')));
        expect(repo.marca, isTrue);
        expect(repo.sal, isNotNull);
        expect(repo.archivo, isTrue);
      });
    }
  });

  group('cierre de sesión durante la derivación (revisión del PR #44)', () {
    Future<Either<Failure, ResultadoInicializacionDb>> cerrarSesionMientrasDeriva() async {
      repo.derivacionPendiente = Completer<void>();
      final enCurso = inicializar();
      await repo.pidioDerivar.future;

      vigencia.cerrarSesion();
      repo.derivacionPendiente!.complete();
      return enCurso;
    }

    test('dado un primer login, destruye la clave, no abre y deja el dispositivo limpio', () async {
      final r = await cerrarSesionMientrasDeriva();

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSesionCerrada()));
      expect(repo.llamadas, isNot(contains('abrir')));
      expect(repo.claves.single.destruida, isTrue);
      expect(repo.abierta, isFalse);
      expect(repo.marca, isFalse);
      expect(repo.sal, isNull, reason: 'no queda una sal suelta');
    });

    test('dado un login posterior, destruye la clave y no abre, sin borrar la DB', () async {
      dispositivoInicializado();

      final r = await cerrarSesionMientrasDeriva();

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSesionCerrada()));
      expect(repo.llamadas, isNot(contains('abrir')));
      expect(repo.llamadas, isNot(contains('descartar')));
      expect(repo.claves.single.destruida, isTrue);
      expect(repo.archivo, isTrue);
      expect(repo.marca, isTrue);
    });

    test('dado que la sesión sigue, abre con la clave viva', () async {
      final r = await inicializar();

      expect(r.isRight(), isTrue);
      expect(repo.claves.single.destruida, isFalse);
    });
  });

  group('entrada', () {
    test('dado que no hay sesión, no toca nada', () async {
      vigencia.haySesion = false;

      final r = await inicializar();

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSesionCerrada()));
      expect(repo.llamadas, isEmpty);
    });

    test('dado una contraseña vacía, devuelve validación sin tocar nada', () async {
      final r = await inicializar('');

      expect(r.isLeft(), isTrue);
      r.fold((f) => expect(f, isA<FailureValidacion>()), (_) => fail('esperaba Left'));
      expect(repo.llamadas, isEmpty);
    });

    test('dado que falla leer el estado, devuelve esa falla', () async {
      repo.fallas['estado'] = const FailureAlmacenSeguro();

      final r = await inicializar();

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguro()));
      expect(repo.llamadas, ['estado']);
    });

    test('dado los params interpolados, no aparece la contraseña', () {
      final stringify = EquatableConfig.stringify;
      addTearDown(() => EquatableConfig.stringify = stringify);
      EquatableConfig.stringify = true;

      const params = InicializarDbLocalParams(password: 'secreto123');

      expect(params.toString(), isNot(contains('secreto123')));
      expect(params, const InicializarDbLocalParams(password: 'secreto123'));
    });
  });
}

/// La primera limpieza anda y las siguientes fallan: el aborto no puede tapar la falla original.
final class _RepoQueFallaAlSegundoDescarte extends _RepoEnMemoria {
  int descartes = 0;

  @override
  Future<Either<Failure, Unit>> descartar() async {
    if (++descartes > 1) {
      llamadas.add('descartar');
      return const Left(FailureInesperado());
    }
    return super.descartar();
  }
}
