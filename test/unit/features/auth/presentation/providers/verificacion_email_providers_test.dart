// #126: los `StreamProvider` de la verificación de email (HU-AUTH-002) avisan cada evento, no solo
// el primero. Con `Stream<void>` todos los eventos valían `AsyncData(null)`, y `listen` (que solo
// avisa si el valor cambió) se perdía el segundo error o la segunda verificación exitosa.
import 'dart:async';

import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/observar_errores_verificacion_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/observar_verificaciones_exitosas_use_case.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late StreamController<void> errores;
  late StreamController<void> exitosas;
  late ProviderContainer container;

  setUp(() {
    errores = StreamController<void>();
    exitosas = StreamController<void>();
    final repository = _MockAuthRepository();
    when(() => repository.erroresVerificacionEmail).thenAnswer((_) => errores.stream);
    when(() => repository.verificacionesExitosas).thenAnswer((_) => exitosas.stream);
    final observarErrores = ObservarErroresVerificacionUseCase(repository);
    final observarExitosas = ObservarVerificacionesExitosasUseCase(repository);
    container = ProviderContainer(
      overrides: [
        observarErroresVerificacionUseCaseProvider.overrideWithValue(observarErrores),
        observarVerificacionesExitosasUseCaseProvider.overrideWithValue(observarExitosas),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await errores.close();
    await exitosas.close();
  });

  test('dados dos errores de verificación seguidos, el listener se entera de los dos', () async {
    var avisos = 0;
    container.listen(erroresVerificacionEmailProvider, (_, next) {
      if (next is AsyncData<EventoVerificacionEmail>) avisos++;
    });

    errores.add(null);
    await pumpEventQueue();
    errores.add(null);
    await pumpEventQueue();

    expect(avisos, 2);
  });

  test('dadas dos verificaciones exitosas en la misma sesión de la app, el listener se entera de '
      'las dos', () async {
    var avisos = 0;
    container.listen(verificacionesExitosasProvider, (_, next) {
      if (next is AsyncData<EventoVerificacionEmail>) avisos++;
    });

    exitosas.add(null);
    await pumpEventQueue();
    exitosas.add(null);
    await pumpEventQueue();

    expect(avisos, 2);
  });
}
