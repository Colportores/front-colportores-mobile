// HU-AUTH-009 — orquestación de la inicialización de la DB local con la DEK envuelta (ADR-006), con
// el repositorio y la vigencia de sesión en memoria. El Argon2id es un Completer que el test
// controla: así se puede cerrar la sesión justo mientras "se envuelve la DEK".
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/core/dispositivo/seguridad_dispositivo.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/domain/services/turno_db_local.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/empezar_de_nuevo_db_local_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/inicializar_db_local_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/recuperar_db_local_con_password_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

import '../../../../../helpers/db_local_repository_en_memoria.dart';

void main() {
  late DbLocalRepositoryEnMemoria repo;
  late VigenciaEnMemoria vigencia;
  late TurnoDbLocal turno;
  late InicializarDbLocalUseCase useCase;
  late List<PasoInicializacionDb> pasos;

  setUp(() {
    repo = DbLocalRepositoryEnMemoria();
    vigencia = VigenciaEnMemoria();
    turno = TurnoDbLocal();
    useCase = InicializarDbLocalUseCase(repo, vigencia, turno);
    pasos = [];
  });

  Future<Either<Failure, ResultadoInicializacionDb>> inicializar({
    String? password = 'secreto123',
    bool aceptaAlmacenSoftware = false,
  }) => useCase(
    InicializarDbLocalParams(
      password: password,
      aceptaAlmacenSoftware: aceptaAlmacenSoftware,
      alAvanzar: pasos.add,
    ),
  );

  /// Dispositivo ya inicializado en un login anterior.
  void dispositivoInicializado({bool conEnvoltorio = true}) {
    final dek = Uint8List.fromList(List<int>.filled(32, 77));
    repo
      ..marca = MarcaDbLocal.puesta
      ..archivo = true
      ..dekEnAlmacen = dek
      ..envoltorio = conEnvoltorio ? (dek: dek, password: 'secreto123') : null;
  }

  const creada = Right<Failure, ResultadoInicializacionDb>(ResultadoInicializacionDb.creada);
  const abierta = Right<Failure, ResultadoInicializacionDb>(ResultadoInicializacionDb.abierta);

  group('Escenario: Inicialización exitosa', () {
    test(
      'dado mi primer login, verifica el bloqueo de pantalla, genera y guarda la DEK, la envuelve '
      'con Argon2id(mi contraseña), crea la DB con ella y recién al final marca el dispositivo',
      () async {
        final r = await inicializar();

        expect(r, creada);
        expect(repo.llamadas, [
          'estado',
          'bloqueo',
          'nivel',
          'descartar',
          'crearDek',
          'envolver',
          'abrir',
          'marcar',
        ]);
        final dek = repo.entregadas.single;
        expect(repo.abiertaCon, same(dek), reason: 'la DB se crea con la DEK generada');
        expect(repo.envoltorio!.dek, repo.dekEnAlmacen, reason: 'envuelve la misma DEK');
        expect(repo.envoltorio!.password, 'secreto123');
        expect(repo.marca, MarcaDbLocal.puesta);
      },
    );

    test('la UI recibe el progreso en tres pasos: 1/3, 2/3, 3/3', () async {
      await inicializar();

      expect(pasos, [
        PasoInicializacionDb.generandoClave,
        PasoInicializacionDb.protegiendoClave,
        PasoInicializacionDb.abriendoDb,
      ]);
    });

    test(
      'dado un login con Google (sin contraseña), crea la DB sin envoltorio por contraseña',
      () async {
        final r = await inicializar(password: null);

        expect(r, creada);
        expect(repo.llamadas, isNot(contains('envolver')));
        expect(repo.envoltorio, isNull);
        expect(pasos, [PasoInicializacionDb.generandoClave, PasoInicializacionDb.abriendoDb]);
      },
    );
  });

  group('Escenario: Error - equipo sin bloqueo de pantalla', () {
    test(
      'dado un equipo sin PIN, patrón ni biometría, no inicializa la DB y explica por qué y cómo '
      'configurarlo',
      () async {
        repo.bloqueoPantalla = false;

        final r = await inicializar();

        expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSinBloqueoPantalla()));
        expect(repo.llamadas, ['estado', 'bloqueo'], reason: 'no toca nada');
        expect(pasos, isEmpty);
        final mensaje = const FailureSinBloqueoPantalla().mensaje;
        expect(mensaje, contains('bloqueo de pantalla'));
        expect(mensaje, contains('ajustes de seguridad'));
      },
    );
  });

  group('Escenario: Keystore por software - consentimiento explícito', () {
    setUp(() => repo.nivel = NivelAlmacenSeguro.software);

    test('dado un Keystore por software, sin consentimiento, muestra la advertencia de la HU y no '
        'toca nada', () async {
      final r = await inicializar();

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenPocoSeguro()));
      expect(
        const FailureAlmacenPocoSeguro().mensaje,
        'Tu dispositivo tiene almacenamiento menos seguro. Los datos siguen cifrados pero el '
        'nivel de protección es menor.',
      );
      expect(repo.llamadas, ['estado', 'bloqueo', 'nivel']);
    });

    test('si acepta, sigue con el mismo almacén y registra la elección', () async {
      final r = await inicializar(aceptaAlmacenSoftware: true);

      expect(r, creada);
      expect(repo.consentimiento, isTrue);
      expect(
        repo.llamadas.sublist(3, 6),
        ['descartar', 'consentimiento', 'crearDek'],
        reason: 'se registra después de limpiar, para que la limpieza no se lo lleve',
      );
    });

    test('dado un Keystore por hardware, no pregunta ni registra nada', () async {
      repo.nivel = NivelAlmacenSeguro.hardware;

      expect(await inicializar(), creada);
      expect(repo.llamadas, isNot(contains('consentimiento')));
    });
  });

  group('Escenario: Error - falla al escribir en secure_storage', () {
    test(
      'dado que el almacén falla al guardar la DEK, limpia el estado parcial, devuelve el mensaje '
      'de la HU y no marca el dispositivo',
      () async {
        repo.fallas['crearDek'] = const FailureAlmacenSeguro();

        final r = await inicializar();

        expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguro()));
        expect(
          const FailureAlmacenSeguro().mensaje,
          'No pudimos preparar el almacenamiento seguro. Probá reinstalar el app o consultá a '
          'soporte.',
        );
        expect(repo.llamadas.last, 'descartar');
        expect(repo.llamadas, isNot(contains('marcar')));
        expect(repo.marca, MarcaDbLocal.ausente);
      },
    );
  });

  group('Escenario: Error - sin espacio en disco', () {
    test('dado que no hay espacio para crear el archivo, aborta, devuelve el mensaje de la HU y '
        'borra el archivo parcial', () async {
      repo.fallas['abrir'] = const FailureSinEspacio();

      final r = await inicializar();

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSinEspacio()));
      expect(const FailureSinEspacio().mensaje, 'No hay espacio suficiente para preparar el app');
      expect(repo.llamadas.last, 'descartar');
      expect(repo.archivo, isFalse);
      expect(repo.dekEnAlmacen, isNull);
      expect(repo.envoltorio, isNull);
    });
  });

  group('Escenario: Edge - inicialización interrumpida', () {
    test('dado un archivo sin marca y con la DEK en el almacén (la app murió a mitad), elimina la '
        'DEK envuelta y el archivo parcial y parte de cero', () async {
      repo
        ..archivo = true
        ..dekEnAlmacen = Uint8List.fromList(List<int>.filled(32, 5))
        ..envoltorio = (dek: Uint8List(32), password: 'secreto123');

      final r = await inicializar();

      expect(r, creada);
      expect(repo.llamadas.take(5), ['estado', 'leerDek', 'bloqueo', 'nivel', 'descartar']);
      expect(repo.entregadas.first.destruida, isTrue, reason: 'la DEK vieja no queda viva');
      expect(repo.dekEnAlmacen, isNot(List<int>.filled(32, 5)));
    });

    test(
      'dado un archivo sin marca y sin DEK (un iPhone restaurado trae los archivos pero no el '
      'Keychain), no es una inicialización cortada: pide la contraseña y no borra nada',
      () async {
        repo
          ..archivo = true
          ..envoltorio = (dek: Uint8List(32), password: 'secreto123');

        final r = await inicializar();

        expect(
          r,
          const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguroRecuperable()),
        );
        expect(repo.llamadas, ['estado', 'leerDek']);
        expect(repo.archivo, isTrue);
        expect(repo.envoltorio, isNotNull);
      },
    );

    test(
      'dado un archivo sin marca, sin DEK y sin envoltorio, ofrece empezar de nuevo sin borrar',
      () async {
        repo.archivo = true;

        expect(
          await inicializar(),
          const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguroSinRecuperacion()),
        );
        expect(repo.llamadas, isNot(contains('descartar')));
      },
    );

    test(
      'dado un archivo sin marca y un almacén que falla al leer la DEK, tampoco borra',
      () async {
        repo
          ..archivo = true
          ..fallas['leerDek'] = const FailureAlmacenSeguro();

        expect(
          await inicializar(),
          const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguroSinRecuperacion()),
        );
        expect(repo.llamadas, ['estado', 'leerDek']);
      },
    );

    test('dado un archivo sin marca y otra falla al leer la DEK, la devuelve tal cual', () async {
      repo
        ..archivo = true
        ..fallas['leerDek'] = const FailureInesperado();

      expect(
        await inicializar(),
        const Left<Failure, ResultadoInicializacionDb>(FailureInesperado()),
      );
      expect(repo.llamadas, ['estado', 'leerDek']);
    });
  });

  group('Escenario: Edge - segundo intento tras error transitorio', () {
    test('dado que el primer intento falló, el segundo parte desde cero con otra DEK', () async {
      repo.fallas['abrir'] = const FailureSinEspacio();
      await inicializar();
      final primera = Uint8List.fromList(repo.envoltorio?.dek ?? List<int>.filled(32, 1));
      repo.fallas.clear();

      final r = await inicializar();

      expect(r, creada);
      expect(repo.dekEnAlmacen, isNot(primera));
      expect(repo.entregadas, hasLength(2));
      expect(repo.entregadas.first.destruida, isTrue, reason: 'la DEK del intento fallido no vive');
    });
  });

  group('primer login — limpieza ante cada falla', () {
    for (final (paso, falla) in [
      ('crearDek', const FailureAlmacenSeguro()),
      ('envolver', const FailureAlmacenSeguro()),
      ('abrir', const FailureInesperado()),
      ('marcar', const FailureAlmacenSeguro()),
    ]) {
      test('dado que falla "$paso", devuelve la falla, deja el dispositivo limpio y no queda una '
          'DEK viva', () async {
        repo.fallas[paso] = falla;

        final r = await inicializar();

        expect(r, Left<Failure, ResultadoInicializacionDb>(falla));
        expect(repo.llamadas.last, 'descartar');
        expect(repo.marca, MarcaDbLocal.ausente);
        expect(repo.dekEnAlmacen, isNull);
        expect(repo.envoltorio, isNull);
        if (paso != 'crearDek' && paso != 'marcar') {
          expect(repo.entregadas.single.destruida, isTrue);
        }
      });
    }

    test('dado que el registro del consentimiento falla, limpia y devuelve la falla', () async {
      repo
        ..nivel = NivelAlmacenSeguro.software
        ..fallas['consentimiento'] = const FailureAlmacenSeguro();

      final r = await inicializar(aceptaAlmacenSoftware: true);

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguro()));
      expect(repo.llamadas.last, 'descartar');
      expect(repo.llamadas, isNot(contains('crearDek')));
    });

    test(
      'dado que la limpieza inicial falla, no sigue: una DEK nueva no abriría el archivo viejo',
      () async {
        repo.fallas['descartar'] = const FailureInesperado();

        final r = await inicializar();

        expect(r.isLeft(), isTrue);
        expect(repo.llamadas, ['estado', 'bloqueo', 'nivel', 'descartar']);
      },
    );

    test('dado que la verificación del equipo falla, devuelve esa falla sin tocar nada', () async {
      repo.fallas['bloqueo'] = const FailureAlmacenSeguro();
      expect(
        await inicializar(),
        const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguro()),
      );

      repo
        ..fallas.clear()
        ..llamadas.clear()
        ..fallas['nivel'] = const FailureAlmacenSeguro();
      expect(
        await inicializar(),
        const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguro()),
      );
      expect(repo.llamadas, ['estado', 'bloqueo', 'nivel']);
    });

    test('dado que la limpieza posterior también falla, devuelve la falla original', () async {
      repo.fallas['abrir'] = const FailureSinEspacio();

      // La limpieza inicial anda; la del aborto (después de este paso) falla.
      final r = await useCase(
        InicializarDbLocalParams(
          password: 'secreto123',
          alAvanzar: (paso) {
            if (paso == PasoInicializacionDb.abriendoDb) {
              repo.fallas['descartar'] = const FailureInesperado();
            }
          },
        ),
      );

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSinEspacio()));
      expect(repo.llamadas.last, 'descartar');
    });
  });

  group('dispositivo que hay que tratar como nuevo', () {
    test('dado marca sin archivo (iOS tras reinstalar), crea de cero', () async {
      repo
        ..marca = MarcaDbLocal.puesta
        ..dekEnAlmacen = Uint8List(32);

      expect(await inicializar(), creada);
      expect(repo.llamadas, isNot(contains('leerDek')));
      expect(repo.llamadas, contains('descartar'));
    });

    test(
      'dado un almacén ilegible sin archivo, intenta crear de cero (no hay datos que perder)',
      () async {
        repo.marca = MarcaDbLocal.ilegible;

        expect(await inicializar(), creada);
      },
    );
  });

  group('login posterior (DB existente)', () {
    setUp(dispositivoInicializado);

    test('dado un dispositivo inicializado, abre la DB con la DEK del almacén seguro, sin Argon2id '
        'y sin borrar nada', () async {
      final r = await inicializar();

      expect(r, abierta);
      expect(repo.llamadas, ['estado', 'leerDek', 'abrir']);
      expect(pasos, [PasoInicializacionDb.abriendoDb]);
      expect(repo.abiertaCon!.bytes, List<int>.filled(32, 77));
    });

    test('dada una sesión restaurada o un login con Google (sin contraseña), abre igual', () async {
      expect(await inicializar(password: null), abierta);
    });

    test(
      'dado un login con contraseña en un equipo sin envoltorio, lo arma antes de abrir (#81)',
      () async {
        dispositivoInicializado(conEnvoltorio: false);

        final r = await inicializar();

        expect(r, abierta);
        expect(repo.llamadas, ['estado', 'leerDek', 'envolver', 'abrir']);
        expect(repo.envoltorio!.dek, List<int>.filled(32, 77), reason: 'envuelve la DEK de la DB');
        expect(repo.envoltorio!.password, 'secreto123');
        expect(pasos, [PasoInicializacionDb.protegiendoClave, PasoInicializacionDb.abriendoDb]);
      },
    );

    test('dado que armar ese envoltorio falla, abre igual: la DB está bien (#81)', () async {
      dispositivoInicializado(conEnvoltorio: false);
      repo.fallas['envolver'] = const FailureAlmacenSeguro();

      expect(await inicializar(), abierta);
      expect(repo.abierta, isTrue);
    });

    test('dado un envoltorio que ya existe, no lo toca', () async {
      final r = await inicializar();

      expect(r, abierta);
      expect(repo.llamadas, isNot(contains('envolver')));
    });

    test(
      'no verifica el bloqueo de pantalla ni el Keystore: al abrir, la app no pide nada propio',
      () async {
        repo
          ..bloqueoPantalla = false
          ..nivel = NivelAlmacenSeguro.software;

        expect(await inicializar(), abierta);
      },
    );

    for (final falla in [
      const FailureClaveDbIncorrecta(),
      const FailureEsquemaPosterior(),
      const FailureSinEspacio(),
    ]) {
      test('dado que abrir falla con ${falla.codigo}, devuelve la falla y no borra nada', () async {
        repo.fallas['abrir'] = falla;

        final r = await inicializar();

        expect(r, Left<Failure, ResultadoInicializacionDb>(falla));
        expect(repo.llamadas, isNot(contains('descartar')));
        expect(repo.archivo, isTrue);
        expect(repo.dekEnAlmacen, isNotNull);
        expect(repo.marca, MarcaDbLocal.puesta);
      });
    }

    test('Escenario: Edge - DB con un esquema posterior: FailureEsquemaPosterior con el texto de '
        'la HU, sin migrar ni borrar', () async {
      repo.fallas['abrir'] = const FailureEsquemaPosterior();

      final r = await inicializar();

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureEsquemaPosterior()));
      expect(
        const FailureEsquemaPosterior().mensaje,
        'Tus datos son de una versión más nueva de la app. Actualizala para seguir usando tus '
        'datos.',
      );
      expect(repo.llamadas, isNot(contains('descartar')));
    });

    test('dada otra falla al leer la DEK, la devuelve tal cual', () async {
      repo.fallas['leerDek'] = const FailureInesperado();

      expect(
        await inicializar(),
        const Left<Failure, ResultadoInicializacionDb>(FailureInesperado()),
      );
    });
  });

  group('recuperación guiada (ADR-006): el almacén falla con la DB en disco', () {
    for (final (descripcion, preparar) in [
      ('el almacén no responde', (DbLocalRepositoryEnMemoria r) => r.marca = MarcaDbLocal.ilegible),
      (
        'leer la DEK falla',
        (DbLocalRepositoryEnMemoria r) => r.fallas['leerDek'] = const FailureAlmacenSeguro(),
      ),
      ('el almacén perdió la DEK', (DbLocalRepositoryEnMemoria r) => r.dekEnAlmacen = null),
    ]) {
      test('dado que $descripcion y hay envoltorio por contraseña, pide la contraseña para '
          'recuperar y no borra nada', () async {
        dispositivoInicializado();
        preparar(repo);

        final r = await inicializar();

        expect(
          r,
          const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguroRecuperable()),
        );
        expect(
          const FailureAlmacenSeguroRecuperable().mensaje,
          'Tu almacenamiento seguro falló. Ingresá tu contraseña para recuperar tus datos',
        );
        expect(repo.llamadas, isNot(contains('descartar')));
        expect(repo.llamadas, isNot(contains('abrir')));
        expect(repo.archivo, isTrue);
      });

      test('dado que $descripcion y no hay envoltorio (Google sin backup), devuelve el mensaje de '
          'la HU para ofrecer "empezar de nuevo", sin borrar', () async {
        dispositivoInicializado(conEnvoltorio: false);
        preparar(repo);

        final r = await inicializar();

        expect(
          r,
          const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguroSinRecuperacion()),
        );
        expect(
          const FailureAlmacenSeguroSinRecuperacion().mensaje,
          const FailureAlmacenSeguro().mensaje,
        );
        expect(repo.llamadas, isNot(contains('descartar')));
      });
    }
  });

  group('cierre de sesión durante la inicialización (revisión del PR #44)', () {
    test('dado que no hay sesión, no hace nada', () async {
      vigencia.haySesion = false;

      final r = await inicializar();

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSesionCerrada()));
      expect(repo.llamadas, isEmpty);
    });

    test('dado un logout mientras se envuelve la DEK, no abre, la destruye y deja el dispositivo '
        'limpio', () async {
      repo.argon2idPendiente = Completer<void>();

      final enCurso = inicializar();
      await repo.pidioArgon2id.future;
      vigencia.cerrarSesion();
      repo.argon2idPendiente!.complete();
      final r = await enCurso;

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSesionCerrada()));
      expect(repo.llamadas, isNot(contains('abrir')));
      expect(repo.abierta, isFalse);
      expect(repo.entregadas.single.destruida, isTrue);
      expect(repo.llamadas.last, 'descartar');
      expect(repo.marca, MarcaDbLocal.ausente);
    });

    test('dado un logout mientras lee la DEK de una DB existente, no abre, la destruye y no borra '
        'nada', () async {
      dispositivoInicializado();
      repo.lecturaPendiente = Completer<void>();

      final enCurso = inicializar();
      await Future<void>.delayed(Duration.zero);
      vigencia.cerrarSesion();
      repo.lecturaPendiente!.complete();
      final r = await enCurso;

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSesionCerrada()));
      expect(repo.llamadas, ['estado', 'leerDek']);
      expect(repo.entregadas.single.destruida, isTrue);
      expect(repo.archivo, isTrue);
      expect(repo.marca, MarcaDbLocal.puesta);
    });
  });

  group('validación', () {
    test('dada una contraseña vacía, devuelve FailureValidacion sin tocar nada', () async {
      final r = await inicializar(password: '');

      expect(r.isLeft(), isTrue);
      expect(r.fold((f) => f, (_) => null), isA<FailureValidacion>());
      expect(repo.llamadas, isEmpty);
    });

    test('los params no imprimen la contraseña', () {
      final previo = EquatableConfig.stringify;
      addTearDown(() => EquatableConfig.stringify = previo);
      EquatableConfig.stringify = true;

      expect(
        '${const InicializarDbLocalParams(password: 'secreto123')}',
        isNot(contains('secreto')),
      );
    });
  });

  group('un flujo a la vez (revisión del PR #81)', () {
    test('dadas dos inicializaciones en paralelo, la segunda espera y encuentra la DB abierta: la '
        'DEK de la DB, la del almacén y la del envoltorio son la misma', () async {
      repo.argon2idPendiente = Completer<void>();

      final primera = inicializar();
      await repo.pidioArgon2id.future;
      final segunda = inicializar();
      await Future<void>.delayed(Duration.zero);
      expect(
        repo.llamadas.where((l) => l == 'estado'),
        hasLength(1),
        reason: 'la segunda no empezó: espera el turno',
      );

      repo.argon2idPendiente!.complete();
      expect(await primera, creada);
      expect(await segunda, abierta);

      expect(repo.llamadas.where((l) => l == 'descartar'), hasLength(1));
      expect(repo.claveDelArchivo, repo.dekEnAlmacen);
      expect(repo.envoltorio!.dek, repo.dekEnAlmacen);
    });

    test('"empezar de nuevo" espera a que termine una inicialización en curso', () async {
      repo.argon2idPendiente = Completer<void>();
      final empezarDeNuevo = EmpezarDeNuevoDbLocalUseCase(repo, turno);

      final inicializacion = inicializar();
      await repo.pidioArgon2id.future;
      final borrado = empezarDeNuevo(const NoParams());
      await Future<void>.delayed(Duration.zero);
      expect(repo.llamadas.where((l) => l == 'descartar'), hasLength(1), reason: 'solo el inicial');

      repo.argon2idPendiente!.complete();
      expect(await inicializacion, creada);
      await borrado;
      expect(repo.llamadas.last, 'descartar', reason: 'recién después de que terminó');
    });

    test('dada la DB ya abierta en esta sesión, inicializar no toca nada', () async {
      dispositivoInicializado();
      repo.abierta = true;

      expect(await inicializar(), abierta);
      expect(repo.llamadas, ['estado']);
    });
  });

  group('almacén que se corta a mitad de la recuperación (revisión del PR #81)', () {
    for (final (escritura, descripcion) in [(1, 'la marca'), (2, 'la DEK')]) {
      test(
        'dado que el Keystore falla al escribir $descripcion, el próximo arranque vuelve a pedir '
        'la contraseña y no borra la DB',
        () async {
          final dek = Uint8List.fromList(List<int>.filled(32, 77));
          repo
            ..archivo = true
            ..claveDelArchivo = dek
            ..envoltorio = (dek: dek, password: 'secreto123')
            ..reconstruccionSeCortaEn = escritura;
          final recuperar = RecuperarDbLocalConPasswordUseCase(repo, vigencia, turno);

          expect(
            await inicializar(password: null),
            const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguroRecuperable()),
          );
          await recuperar(const RecuperarDbLocalParams(password: 'secreto123'));

          // Reinicio de la app con el Keystore otra vez sano.
          repo
            ..abierta = false
            ..reconstruccionSeCortaEn = null
            ..llamadas.clear();
          final r = await inicializar(password: null);

          expect(
            r,
            const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguroRecuperable()),
          );
          expect(repo.llamadas, isNot(contains('descartar')));
          expect(repo.archivo, isTrue);
          expect(repo.claveDelArchivo, dek, reason: 'la DB del colportor sigue ahí');
        },
      );
    }
  });
}
