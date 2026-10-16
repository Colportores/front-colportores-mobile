// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'dart:async';

import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/observar_errores_verificacion_use_case.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;
  late ObservarErroresVerificacionUseCase useCase;
  late StreamController<void> controlador;

  setUp(() {
    repository = _MockAuthRepository();
    controlador = StreamController<void>.broadcast();
    when(() => repository.erroresVerificacionEmail).thenAnswer((_) => controlador.stream);
    useCase = ObservarErroresVerificacionUseCase(repository);
  });

  tearDown(() => controlador.close());

  group('ObservarErroresVerificacionUseCase', () {
    test(
      'dado que el repositorio emite un error de verificación, cuando se observa, lo reenvía tal '
      'cual (sin transformarlo)',
      () async {
        final eventos = <void>[];
        final suscripcion = useCase(const NoParams()).listen(eventos.add);
        addTearDown(suscripcion.cancel);

        controlador.add(null);
        await Future<void>.delayed(Duration.zero);

        expect(eventos, hasLength(1));
        verify(() => repository.erroresVerificacionEmail).called(1);
      },
    );

    test(
      'dado que el repositorio no emitió nada todavía, cuando se observa, no llega ningún evento',
      () async {
        final eventos = <void>[];
        final suscripcion = useCase(const NoParams()).listen(eventos.add);
        addTearDown(suscripcion.cancel);

        await Future<void>.delayed(Duration.zero);

        expect(eventos, isEmpty);
      },
    );
  });
}
