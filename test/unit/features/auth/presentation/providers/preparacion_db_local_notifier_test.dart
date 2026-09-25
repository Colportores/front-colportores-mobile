// La preparación de la DB local después del login (HU-AUTH-009, #27): cuándo arranca, con qué
// contraseña, y que la contraseña no quede en memoria más de lo necesario. Los estados de la
// pantalla se prueban en `test/widget/preparacion_db_local_page_test.dart`.
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/password_para_db_local.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/preparacion_db_local_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/db_local_repository_en_memoria.dart';

const _email = 'ana@example.com';
const _password = 'Secreto123';

void main() {
  late DbLocalRepositoryEnMemoria db;
  late ProviderContainer container;

  setUp(() {
    db = DbLocalRepositoryEnMemoria();
    container = ProviderContainer(
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {_email: _password}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        dbLocalRepositoryProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
  });

  /// Espera a que la preparación termine (lista, fallida o rechazada).
  Future<EstadoPreparacionDbLocal> terminada() async {
    final fin = Completer<EstadoPreparacionDbLocal>();
    final sub = container.listen(preparacionDbLocalProvider, (_, estado) {
      final enCurso =
          estado is PreparandoDbLocal ||
          estado is RecuperandoDbLocal ||
          estado is ConfirmandoPasswordDbLocal;
      if (!enCurso && !fin.isCompleted) {
        fin.complete(estado);
      }
    }, fireImmediately: true);
    addTearDown(sub.close);
    return fin.future;
  }

  Future<void> entrar() async {
    await container.read(sesionProvider.future);
    await container.read(sesionProvider.notifier).iniciarSesion(email: _email, password: _password);
  }

  test('sin sesión no prepara nada', () async {
    await container.read(sesionProvider.future);

    expect(container.read(preparacionDbLocalProvider), isA<SinSesionDbLocal>());
    expect(db.llamadas, isEmpty);
  });

  test('al entrar con contraseña, prepara la DB con ella y después la olvida', () async {
    await entrar();
    expect(container.read(passwordParaDbLocalProvider).actual, _password);

    expect(await terminada(), isA<DbLocalLista>());
    expect(db.envoltorio!.password, _password);
    expect(container.read(passwordParaDbLocalProvider).actual, isNull);
  });

  test('si la preparación falla, la contraseña queda para el reintento', () async {
    db.bloqueoPantalla = false;
    await entrar();

    expect(await terminada(), isA<PreparacionDbLocalFallida>());
    expect(container.read(passwordParaDbLocalProvider).actual, _password);
  });

  test('al cerrar la sesión, vuelve a "sin sesión" y olvida la contraseña', () async {
    db.bloqueoPantalla = false;
    await entrar();
    await terminada();

    await container.read(sesionProvider.notifier).cerrarSesion();

    expect(container.read(preparacionDbLocalProvider), isA<SinSesionDbLocal>());
    expect(container.read(passwordParaDbLocalProvider).actual, isNull);
  });

  test('cada reintento fallido suma uno: "empezar de nuevo" se ofrece desde el primero', () async {
    db
      ..marca = MarcaDbLocal.puesta
      ..archivo = true;
    await entrar();
    final primera = await terminada() as PreparacionDbLocalFallida;
    expect(primera.reintentos, 0);

    await container.read(preparacionDbLocalProvider.notifier).reintentar();

    final segunda = container.read(preparacionDbLocalProvider) as PreparacionDbLocalFallida;
    expect(segunda.reintentos, 1);
  });

  group('cuenta con contraseña sin envoltorio (revisión del PR #130)', () {
    /// Una sesión restaurada: entró antes, así que no hay contraseña del login en memoria.
    Future<void> restaurada() async {
      await entrar();
      container.read(passwordParaDbLocalProvider).olvidar();
    }

    test('dada una sesión restaurada sin DB, pide la contraseña antes de crear nada; confirmada '
        'contra el servidor, crea la DB con envoltorio', () async {
      await restaurada();

      final pedido = await terminada() as PreparacionDbLocalFallida;
      expect(pedido.falla, const FailurePasswordParaProteger());
      expect(db.llamadas, isNot(contains('crearDek')));
      expect(db.llamadas, isNot(contains('descartar')));

      final notifier = container.read(preparacionDbLocalProvider.notifier);
      await notifier.confirmarPassword('equivocada');
      final error = container.read(preparacionDbLocalProvider) as PreparacionDbLocalFallida;
      expect(error.errorRecuperacion, const FailureCredencialesInvalidas());
      expect(db.envoltorio, isNull);

      await notifier.confirmarPassword(_password);

      expect(container.read(preparacionDbLocalProvider), isA<DbLocalLista>());
      expect(db.envoltorio!.password, _password);
      expect(container.read(passwordParaDbLocalProvider).actual, isNull);
    });

    test(
      'dada una DB existente sin envoltorio, no la da por lista hasta tener la contraseña',
      () async {
        final dek = Uint8List.fromList(List<int>.filled(32, 5));
        db
          ..marca = MarcaDbLocal.puesta
          ..archivo = true
          ..claveDelArchivo = dek
          ..dekEnAlmacen = dek;
        await restaurada();

        final pedido = await terminada() as PreparacionDbLocalFallida;
        expect(pedido.falla, const FailurePasswordParaProteger());
        expect(db.abierta, isFalse);

        await container.read(preparacionDbLocalProvider.notifier).confirmarPassword(_password);

        expect(container.read(preparacionDbLocalProvider), isA<DbLocalLista>());
        expect(db.envoltorio!.password, _password);
        expect(db.claveDelArchivo, dek, reason: 'la misma DB, nunca una nueva');
      },
    );

    test('con Google no pide contraseña: abre sin envoltorio (ADR-006)', () async {
      await container.read(sesionProvider.future);
      await container.read(sesionProvider.notifier).iniciarSesionConGoogle();

      expect(await terminada(), isA<DbLocalLista>());
      expect(db.envoltorio, isNull);
    });
  });

  group('la contraseña se olvida en SesionNotifier (revisión del PR #130)', () {
    test('sin nadie escuchando la preparación, cerrar la sesión la olvida', () async {
      await entrar();
      expect(container.read(passwordParaDbLocalProvider).actual, _password);

      await container.read(sesionProvider.notifier).cerrarSesion();

      expect(container.read(passwordParaDbLocalProvider).actual, isNull);
    });

    test('empezar un login con Google olvida la de un ingreso anterior', () async {
      await entrar();

      await container.read(sesionProvider.notifier).iniciarSesionConGoogle();

      expect(container.read(passwordParaDbLocalProvider).actual, isNull);
    });
  });

  test('si la falla cambia de tipo, los reintentos vuelven a 0: "empezar de nuevo" nunca aparece '
      'la primera vez que se ve (revisión del PR #130)', () async {
    db.fallas['nivel'] = const FailureAlmacenSeguro();
    await entrar();
    expect(await terminada(), isA<PreparacionDbLocalFallida>());

    // Ahora el almacén perdió la DEK con la DB en disco: otra falla.
    db
      ..fallas.remove('nivel')
      ..marca = MarcaDbLocal.puesta
      ..archivo = true;
    await container.read(preparacionDbLocalProvider.notifier).reintentar();

    final otra = container.read(preparacionDbLocalProvider) as PreparacionDbLocalFallida;
    expect(otra.falla, const FailureAlmacenSeguroSinRecuperacion());
    expect(otra.reintentos, 0);
  });

  test('una preparación que termina después de que la sesión cambió no pisa el estado nuevo '
      '(revisión del PR #130)', () async {
    db.argon2idPendiente = Completer<void>();
    final estados = <EstadoPreparacionDbLocal>[];
    final sub = container.listen(preparacionDbLocalProvider, (_, e) => estados.add(e));
    addTearDown(sub.close);
    await entrar();
    await db.pidioArgon2id.future;

    await container.read(sesionProvider.notifier).cerrarSesion();
    await entrar();
    estados.clear();
    db.argon2idPendiente!.complete();

    expect(await terminada(), isA<DbLocalLista>());
    expect(estados, isNot(contains(isA<SinSesionDbLocal>())));
  });

  test('la contraseña no aparece al imprimir el contenedor', () {
    final guardada = PasswordParaDbLocal()..recordar(_password);

    expect(guardada.toString(), isNot(contains(_password)));
  });
}
