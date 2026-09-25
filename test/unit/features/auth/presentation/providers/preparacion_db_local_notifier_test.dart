// La preparación de la DB local después del login (HU-AUTH-009, #27): cuándo arranca, con qué
// contraseña, y que la contraseña no quede en memoria más de lo necesario. Los estados de la
// pantalla se prueban en `test/widget/preparacion_db_local_page_test.dart`.
import 'dart:async';

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
      if (estado is! PreparandoDbLocal && estado is! RecuperandoDbLocal && !fin.isCompleted) {
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

  test('la contraseña no aparece al imprimir el contenedor', () {
    final guardada = PasswordParaDbLocal()..recordar(_password);

    expect(guardada.toString(), isNot(contains(_password)));
  });
}
