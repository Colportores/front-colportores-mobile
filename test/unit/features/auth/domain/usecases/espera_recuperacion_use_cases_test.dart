// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
//
// La espera de 60 s de «Olvidé mi contraseña» se cuenta desde la hora del último envío que guarda
// el teléfono (HU-AUTH-004, decisión de Cristian del 02/10 en #223; seguimiento #281).
import 'package:colportores_mobile/features/auth/domain/repositories/ultimo_envio_recuperacion_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/espera_recuperacion_use_cases.dart';
import 'package:test/test.dart';

/// Guarda la hora en una variable, como la guardaría el teléfono (siempre en UTC).
final class _UltimoEnvioFalso implements UltimoEnvioRecuperacionRepository {
  _UltimoEnvioFalso([this.guardado]);

  DateTime? guardado;
  int escrituras = 0;

  @override
  Future<DateTime?> leer() async => guardado;

  @override
  Future<void> guardar(DateTime cuando) async {
    escrituras++;
    guardado = cuando.toUtc();
  }
}

void main() {
  final envio = DateTime.utc(2026, 10, 8, 10);

  Future<Duration> esperaA(_UltimoEnvioFalso repo, DateTime ahora) async {
    final resultado = await ConsultarEsperaRecuperacionUseCase(repo)(
      ConsultarEsperaRecuperacionParams(ahora: ahora),
    );
    return resultado.getOrElse(() => fail('consultar la espera nunca falla'));
  }

  group('ConsultarEsperaRecuperacionUseCase', () {
    test('la espera es de 60 segundos (HU-AUTH-004)', () {
      expect(ConsultarEsperaRecuperacionUseCase.espera, const Duration(seconds: 60));
    });

    test('dado que nunca se pidió un enlace, cuando se consulta, no hay espera', () async {
      expect(await esperaA(_UltimoEnvioFalso(), envio), Duration.zero);
    });

    test('dado un envío hace 20 s, cuando se consulta, faltan 40 s', () async {
      final repo = _UltimoEnvioFalso(envio);

      expect(
        await esperaA(repo, envio.add(const Duration(seconds: 20))),
        const Duration(seconds: 40),
      );
    });

    test('dado un envío recién hecho, cuando se consulta, faltan los 60 s completos', () async {
      expect(await esperaA(_UltimoEnvioFalso(envio), envio), const Duration(seconds: 60));
    });

    test('dado un envío hace 59,999 s, cuando se consulta, falta 1 milisegundo', () async {
      final repo = _UltimoEnvioFalso(envio);

      expect(
        await esperaA(repo, envio.add(const Duration(milliseconds: 59999))),
        const Duration(milliseconds: 1),
      );
    });

    for (final (nombre, pasado) in [
      ('justo 60 s', const Duration(seconds: 60)),
      ('61 s', const Duration(seconds: 61)),
      ('un día', const Duration(days: 1)),
    ]) {
      test('dado un envío hace $nombre, cuando se consulta, ya no hay espera', () async {
        expect(await esperaA(_UltimoEnvioFalso(envio), envio.add(pasado)), Duration.zero);
      });
    }

    for (final (nombre, adelantado) in [
      ('1 milisegundo', const Duration(milliseconds: 1)),
      ('20 s', const Duration(seconds: 20)),
      ('3 horas', const Duration(hours: 3)),
      ('un año', const Duration(days: 365)),
    ]) {
      test('dado que la hora guardada quedó $nombre en el futuro (se atrasó el reloj), cuando se '
          'consulta, cuenta como recién enviada: 60 s, no más', () async {
        final repo = _UltimoEnvioFalso(envio.add(adelantado));

        expect(await esperaA(repo, envio), const Duration(seconds: 60));
      });
    }

    test(
      'la hora de ahora puede estar en hora local: se compara el instante, no el huso',
      () async {
        final repo = _UltimoEnvioFalso(DateTime.utc(2026, 10, 8, 10));
        final ahoraLocal = DateTime.utc(2026, 10, 8, 10, 0, 45).toLocal();

        expect(await esperaA(repo, ahoraLocal), const Duration(seconds: 15));
      },
    );

    test('consultar no cambia lo guardado', () async {
      final repo = _UltimoEnvioFalso(envio);

      await esperaA(repo, envio.add(const Duration(seconds: 10)));

      expect(repo.guardado, envio);
      expect(repo.escrituras, 0);
    });

    // Decisión del agente de decisiones, 10/10 (#318): la hora futura se corrige sola.
    for (final (nombre, adelantado) in [
      ('1 milisegundo', const Duration(milliseconds: 1)),
      ('3 horas', const Duration(hours: 3)),
      ('un año', const Duration(days: 365)),
    ]) {
      test('dado que la hora guardada quedó $nombre en el futuro, cuando se consulta, se guarda '
          'la hora de ahora y la espera baja desde ahí', () async {
        final repo = _UltimoEnvioFalso(envio.add(adelantado));

        expect(await esperaA(repo, envio), const Duration(seconds: 60));
        expect(repo.guardado, envio, reason: 'la hora de ahora reemplazó a la del futuro');
        expect(repo.escrituras, 1);

        expect(
          await esperaA(repo, envio.add(const Duration(seconds: 20))),
          const Duration(seconds: 40),
          reason: 'la próxima entrada ya cuenta desde la hora corregida, no 60 s completos',
        );
        expect(repo.escrituras, 1, reason: 'con la hora ya corregida no se vuelve a escribir');
      });
    }

    test('dado que la hora guardada está en el futuro, cuando el reloj la alcanza, entonces ya '
        'no hay espera después de los 60 s corregidos', () async {
      final repo = _UltimoEnvioFalso(envio.add(const Duration(hours: 3)));
      await esperaA(repo, envio);

      expect(await esperaA(repo, envio.add(const Duration(seconds: 60))), Duration.zero);
    });

    test('dado que la hora guardada es la misma de ahora, cuando se consulta, no se reescribe '
        'ni se pasa de 60 s', () async {
      final repo = _UltimoEnvioFalso(envio);

      expect(await esperaA(repo, envio), const Duration(seconds: 60));
      expect(repo.escrituras, 0);
    });
  });

  group('RegistrarEnvioRecuperacionUseCase', () {
    test(
      'dado un envío, cuando se registra, queda guardada su hora y la espera corre desde ahí',
      () async {
        final repo = _UltimoEnvioFalso();

        final resultado = await RegistrarEnvioRecuperacionUseCase(repo)(
          RegistrarEnvioRecuperacionParams(cuando: envio),
        );

        expect(resultado.isRight(), isTrue);
        expect(repo.guardado, envio);
        expect(
          await esperaA(repo, envio.add(const Duration(seconds: 25))),
          const Duration(seconds: 35),
        );
      },
    );

    test('dado otro envío, cuando se registra, reemplaza al anterior', () async {
      final repo = _UltimoEnvioFalso(envio);
      final despues = envio.add(const Duration(minutes: 5));

      await RegistrarEnvioRecuperacionUseCase(repo)(
        RegistrarEnvioRecuperacionParams(cuando: despues),
      );

      expect(repo.guardado, despues);
      expect(
        await esperaA(repo, despues.add(const Duration(seconds: 10))),
        const Duration(seconds: 50),
      );
    });
  });
}
