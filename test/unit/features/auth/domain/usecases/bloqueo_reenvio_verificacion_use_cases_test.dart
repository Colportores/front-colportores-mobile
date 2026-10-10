// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
//
// El candado del reenvío del email de verificación es de una hora desde el rechazo por límite, por
// dirección de correo, y se guarda en el teléfono (HU-AUTH-002, decisión de Cristian del 30/09 en
// #221 y #239; seguimiento #249). La espera de 60 s cuenta desde el último correo que salió a esa
// dirección, el del alta o un reenvío (decisión del orquestador, 08/10, #325).
import 'package:colportores_mobile/features/auth/domain/entities/reenvios_guardados.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/bloqueo_reenvio_verificacion_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/bloqueo_reenvio_verificacion_use_cases.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

/// Guarda lo que le piden como lo guardaría el teléfono (siempre en UTC).
final class _ReenviosFalsos implements BloqueoReenvioVerificacionRepository {
  _ReenviosFalsos([this.guardado = ReenviosGuardados.vacio]);

  ReenviosGuardados guardado;
  final List<(String, DateTime, DateTime)> bloqueos = [];
  final List<(String, DateTime, DateTime)> esperas = [];
  final List<DateTime> lecturas = [];

  @override
  Future<ReenviosGuardados> leer({required DateTime ahora}) async {
    lecturas.add(ahora);
    return guardado = guardado.vigentesA(ahora);
  }

  @override
  Future<void> guardar(String correo, DateTime vence, {required DateTime ahora}) async {
    bloqueos.add((correo, vence, ahora));
    guardado = guardado.conBloqueo(correo, vence);
  }

  @override
  Future<void> guardarEspera(String correo, DateTime vence, {required DateTime ahora}) async {
    esperas.add((correo, vence, ahora));
    guardado = guardado.conEspera(correo, vence);
  }

  @override
  Future<void> olvidar(String correo) async => guardado = guardado.sin(correo);

  @override
  Future<void> olvidarTodo() async => guardado = ReenviosGuardados.vacio;
}

void main() {
  final rechazo = DateTime.utc(2026, 10, 8, 10);

  Future<ReenviosGuardados> vigentesA(_ReenviosFalsos repo, DateTime ahora) async {
    final resultado = await ConsultarReenviosVerificacionUseCase(repo)(
      ConsultarReenviosVerificacionParams(ahora: ahora),
    );
    return resultado.getOrElse(() => fail('consultar los reenvíos nunca falla'));
  }

  Future<DateTime> registrar(_ReenviosFalsos repo, String correo, DateTime ahora) async {
    final resultado = await RegistrarBloqueoReenvioVerificacionUseCase(repo)(
      RegistrarBloqueoReenvioVerificacionParams(correo: correo, ahora: ahora),
    );
    return resultado.getOrElse(() => fail('registrar el candado nunca falla'));
  }

  Future<DateTime> registrarEnvio(_ReenviosFalsos repo, String correo, DateTime ahora) async {
    final resultado = await RegistrarEnvioVerificacionUseCase(repo)(
      RegistrarEnvioVerificacionParams(correo: correo, ahora: ahora),
    );
    return resultado.getOrElse(() => fail('registrar el envío nunca falla'));
  }

  group('correoParaBloqueo', () {
    test('saca los espacios de alrededor y pasa a minúsculas', () {
      expect(correoParaBloqueo('  Lucia.Silva@Correo.COM \n'), 'lucia.silva@correo.com');
    });

    test('una dirección en blanco queda vacía', () {
      expect(correoParaBloqueo('   '), '');
    });
  });

  group('RegistrarBloqueoReenvioVerificacionUseCase', () {
    test('el candado es de una hora (HU-AUTH-002)', () {
      expect(bloqueoReenvioVerificacion, const Duration(minutes: 60));
    });

    test('dado un rechazo por límite, cuando se registra, el candado vence una hora después y se '
        'guarda con la dirección normalizada', () async {
      final repo = _ReenviosFalsos();

      final vence = await registrar(repo, ' Lucia@Correo.com ', rechazo);

      expect(vence, rechazo.add(const Duration(minutes: 60)));
      expect(repo.guardado.bloqueos, {
        'lucia@correo.com': rechazo.add(const Duration(minutes: 60)),
      });
      expect(repo.bloqueos.single.$3, rechazo, reason: 'le pasa el ahora para descartar vencidos');
    });

    test('registrar otra dirección no toca el candado de la primera', () async {
      final repo = _ReenviosFalsos();
      await registrar(repo, 'ana@correo.com', rechazo);

      await registrar(repo, 'luis@correo.com', rechazo.add(const Duration(minutes: 5)));

      expect(repo.guardado.bloqueos.keys, containsAll(['ana@correo.com', 'luis@correo.com']));
      expect(repo.guardado.bloqueos['ana@correo.com'], rechazo.add(const Duration(minutes: 60)));
    });

    test('registrar la misma dirección otra vez reemplaza el vencimiento', () async {
      final repo = _ReenviosFalsos();
      await registrar(repo, 'ana@correo.com', rechazo);

      final despues = rechazo.add(const Duration(minutes: 61));
      await registrar(repo, 'Ana@Correo.com', despues);

      expect(repo.guardado.bloqueos, {'ana@correo.com': despues.add(const Duration(minutes: 60))});
    });

    test('una dirección en blanco no se guarda, pero devuelve el vencimiento', () async {
      final repo = _ReenviosFalsos();

      final vence = await registrar(repo, '   ', rechazo);

      expect(vence, rechazo.add(const Duration(minutes: 60)));
      expect(repo.bloqueos, isEmpty);
    });
  });

  group('RegistrarEnvioVerificacionUseCase', () {
    test('la espera es de 60 segundos (HU-AUTH-002)', () {
      expect(esperaReenvioVerificacion, const Duration(seconds: 60));
    });

    test('dado un correo que salió, cuando se registra, la espera vence 60 s después y se guarda '
        'con la dirección normalizada', () async {
      final repo = _ReenviosFalsos();

      final vence = await registrarEnvio(repo, ' Lucia@Correo.com ', rechazo);

      expect(vence, rechazo.add(const Duration(seconds: 60)));
      expect(repo.guardado.esperas, {'lucia@correo.com': rechazo.add(const Duration(seconds: 60))});
      expect(repo.guardado.bloqueos, isEmpty, reason: 'un envío no es un candado');
      expect(repo.esperas.single.$3, rechazo, reason: 'le pasa el ahora para descartar vencidos');
    });

    test(
      'un envío nuevo a la misma dirección reemplaza la espera; a otra, no toca la primera',
      () async {
        final repo = _ReenviosFalsos();
        await registrarEnvio(repo, 'ana@correo.com', rechazo);

        await registrarEnvio(repo, 'luis@correo.com', rechazo.add(const Duration(seconds: 10)));
        await registrarEnvio(repo, 'Ana@Correo.com', rechazo.add(const Duration(seconds: 70)));

        expect(repo.guardado.esperas, {
          'ana@correo.com': rechazo.add(const Duration(seconds: 130)),
          'luis@correo.com': rechazo.add(const Duration(seconds: 70)),
        });
      },
    );

    test('un envío no toca el candado de la dirección', () async {
      final repo = _ReenviosFalsos();
      await registrar(repo, 'ana@correo.com', rechazo);

      await registrarEnvio(repo, 'ana@correo.com', rechazo);

      expect(repo.guardado.bloqueos, {'ana@correo.com': rechazo.add(const Duration(minutes: 60))});
    });

    test('una dirección en blanco no se guarda, pero devuelve el vencimiento', () async {
      final repo = _ReenviosFalsos();

      final vence = await registrarEnvio(repo, '   ', rechazo);

      expect(vence, rechazo.add(const Duration(seconds: 60)));
      expect(repo.esperas, isEmpty);
    });
  });

  group('ConsultarReenviosVerificacionUseCase', () {
    test('dado que no hay nada guardado, cuando se consulta, no hay ninguno', () async {
      expect((await vigentesA(_ReenviosFalsos(), rechazo)).estaVacio, isTrue);
    });

    test('le pasa al repositorio la hora de ahora', () async {
      final repo = _ReenviosFalsos();

      await vigentesA(repo, rechazo);

      expect(repo.lecturas, [rechazo]);
    });

    test(
      'dado un candado y una espera vigentes, cuando se consulta, vuelven con su vencimiento',
      () async {
        final vence = rechazo.add(const Duration(minutes: 60));
        final venceEspera = rechazo.add(const Duration(minutes: 30, seconds: 40));
        final repo = _ReenviosFalsos(
          ReenviosGuardados(
            bloqueos: {'ana@correo.com': vence},
            esperas: {'ana@correo.com': venceEspera},
          ),
        );

        final vigentes = await vigentesA(repo, rechazo.add(const Duration(minutes: 30)));

        expect(vigentes.bloqueos, {'ana@correo.com': vence});
        expect(vigentes.esperas, {'ana@correo.com': venceEspera});
      },
    );

    test('lo vencido no vuelve, y lo vigente de otras direcciones sí', () async {
      final repo = _ReenviosFalsos(
        ReenviosGuardados(
          bloqueos: {
            'vieja@correo.com': rechazo.add(const Duration(minutes: 10)),
            'nueva@correo.com': rechazo.add(const Duration(minutes: 55)),
          },
        ),
      );

      final vigentes = await vigentesA(repo, rechazo.add(const Duration(minutes: 30)));

      expect(vigentes.bloqueos.keys, ['nueva@correo.com']);
    });
  });

  group('los parámetros no imprimen el correo', () {
    test('ni con EquatableConfig.stringify en true (§7.5)', () {
      final previo = EquatableConfig.stringify;
      addTearDown(() => EquatableConfig.stringify = previo);
      EquatableConfig.stringify = true;

      final bloqueo = RegistrarBloqueoReenvioVerificacionParams(
        correo: 'ana@correo.com',
        ahora: rechazo,
      );
      final envio = RegistrarEnvioVerificacionParams(correo: 'ana@correo.com', ahora: rechazo);

      expect('$bloqueo', isNot(contains('ana@correo.com')));
      expect('$envio', isNot(contains('ana@correo.com')));
    });
  });
}
