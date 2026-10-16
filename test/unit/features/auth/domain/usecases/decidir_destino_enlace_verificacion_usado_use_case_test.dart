// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
// HU-AUTH-002, «"Vencido" vs "ya usado"»: los tres casos del enlace con `otp_expired`.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/domain/entities/destino_enlace_verificacion_usado.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/decidir_destino_enlace_verificacion_usado_use_case.dart';
import 'package:test/test.dart';

void main() {
  const useCase = DecidirDestinoEnlaceVerificacionUsadoUseCase();

  Future<DestinoEnlaceVerificacionUsado> decidir({
    bool haySesion = false,
    Future<Failure?> Function()? login,
  }) async {
    final resultado = await useCase(
      DecidirDestinoEnlaceParams(haySesion: haySesion, loginEnSilencio: login),
    );
    return resultado.getOrElse(() => fail('el caso de uso nunca devuelve Left'));
  }

  group('DecidirDestinoEnlaceVerificacionUsadoUseCase', () {
    group('caso 1 — sesión activa', () {
      test('dado que hay sesión, es "ya verificado" y no hace login en silencio', () async {
        var intentos = 0;
        final destino = await decidir(
          haySesion: true,
          login: () async {
            intentos++;
            return null;
          },
        );

        expect(destino, DestinoEnlaceVerificacionUsado.yaVerificado);
        expect(intentos, 0);
      });
    });

    group('caso 2 — la pantalla de espera sigue abierta: login en silencio', () {
      test('si el login entra, es "ya verificado"', () async {
        expect(await decidir(login: () async => null), DestinoEnlaceVerificacionUsado.yaVerificado);
      });

      test('si responde email_not_confirmed, el enlace expiró', () async {
        expect(
          await decidir(login: () async => const FailureEmailNoVerificado()),
          DestinoEnlaceVerificacionUsado.expirado,
        );
      });

      for (final falla in <Failure>[
        const FailureSinConexion(),
        const FailureCredencialesInvalidas(),
        const FailureServidor(),
        const FailureInesperado(),
      ]) {
        test('si falla por otra cosa (${falla.codigo}), cae en el caso genérico', () async {
          expect(await decidir(login: () async => falla), DestinoEnlaceVerificacionUsado.noSabemos);
        });
      }

      test('si el login lanza, cae en el caso genérico (el dominio no propaga)', () async {
        expect(
          await decidir(login: () async => throw StateError('boom')),
          DestinoEnlaceVerificacionUsado.noSabemos,
        );
      });

      test('hace un solo intento de login', () async {
        var intentos = 0;
        await decidir(
          login: () async {
            intentos++;
            return const FailureEmailNoVerificado();
          },
        );
        expect(intentos, 1);
      });
    });

    group('caso 3 — sin sesión ni datos en memoria', () {
      test('es el texto genérico ("Ir al login" y "Reenviar")', () async {
        expect(await decidir(), DestinoEnlaceVerificacionUsado.noSabemos);
      });
    });
  });
}
