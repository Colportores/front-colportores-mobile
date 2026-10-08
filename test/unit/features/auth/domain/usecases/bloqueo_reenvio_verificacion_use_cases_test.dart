// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
//
// El candado del reenvío del email de verificación es de una hora desde el rechazo por límite, por
// dirección de correo, y se guarda en el teléfono (HU-AUTH-002, decisión de Cristian del 30/09 en
// #221 y #239; seguimiento #249).
import 'package:colportores_mobile/features/auth/domain/repositories/bloqueo_reenvio_verificacion_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/bloqueo_reenvio_verificacion_use_cases.dart';
import 'package:test/test.dart';

/// Guarda los bloqueos en un mapa, como los guardaría el teléfono (siempre en UTC).
final class _BloqueosFalsos implements BloqueoReenvioVerificacionRepository {
  _BloqueosFalsos([Map<String, DateTime>? inicial]) : guardado = {...?inicial};

  final Map<String, DateTime> guardado;
  final List<(String, DateTime, DateTime)> escrituras = [];

  @override
  Future<Map<String, DateTime>> leer() async => Map.of(guardado);

  @override
  Future<void> guardar(String correo, DateTime vence, {required DateTime ahora}) async {
    escrituras.add((correo, vence, ahora));
    guardado[correo] = vence.toUtc();
  }
}

void main() {
  final rechazo = DateTime.utc(2026, 10, 8, 10);

  Future<Map<String, DateTime>> vigentesA(_BloqueosFalsos repo, DateTime ahora) async {
    final resultado = await ConsultarBloqueosReenvioVerificacionUseCase(repo)(
      ConsultarBloqueosReenvioVerificacionParams(ahora: ahora),
    );
    return resultado.getOrElse(() => fail('consultar los candados nunca falla'));
  }

  Future<DateTime> registrar(_BloqueosFalsos repo, String correo, DateTime ahora) async {
    final resultado = await RegistrarBloqueoReenvioVerificacionUseCase(repo)(
      RegistrarBloqueoReenvioVerificacionParams(correo: correo, ahora: ahora),
    );
    return resultado.getOrElse(() => fail('registrar el candado nunca falla'));
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
      final repo = _BloqueosFalsos();

      final vence = await registrar(repo, ' Lucia@Correo.com ', rechazo);

      expect(vence, rechazo.add(const Duration(minutes: 60)));
      expect(repo.guardado, {'lucia@correo.com': rechazo.add(const Duration(minutes: 60))});
      expect(
        repo.escrituras.single.$3,
        rechazo,
        reason: 'le pasa el ahora para descartar vencidos',
      );
    });

    test('registrar otra dirección no toca el candado de la primera', () async {
      final repo = _BloqueosFalsos();
      await registrar(repo, 'ana@correo.com', rechazo);

      await registrar(repo, 'luis@correo.com', rechazo.add(const Duration(minutes: 5)));

      expect(repo.guardado.keys, containsAll(['ana@correo.com', 'luis@correo.com']));
      expect(repo.guardado['ana@correo.com'], rechazo.add(const Duration(minutes: 60)));
    });

    test('registrar la misma dirección otra vez reemplaza el vencimiento', () async {
      final repo = _BloqueosFalsos();
      await registrar(repo, 'ana@correo.com', rechazo);

      final despues = rechazo.add(const Duration(minutes: 61));
      await registrar(repo, 'Ana@Correo.com', despues);

      expect(repo.guardado, {'ana@correo.com': despues.add(const Duration(minutes: 60))});
    });

    test('una dirección en blanco no se guarda, pero devuelve el vencimiento', () async {
      final repo = _BloqueosFalsos();

      final vence = await registrar(repo, '   ', rechazo);

      expect(vence, rechazo.add(const Duration(minutes: 60)));
      expect(repo.escrituras, isEmpty);
    });
  });

  group('ConsultarBloqueosReenvioVerificacionUseCase', () {
    test('dado que no hay candados guardados, cuando se consulta, no hay ninguno', () async {
      expect(await vigentesA(_BloqueosFalsos(), rechazo), isEmpty);
    });

    test('dado un candado vigente, cuando se consulta, vuelve con su vencimiento', () async {
      final vence = rechazo.add(const Duration(minutes: 60));
      final repo = _BloqueosFalsos({'ana@correo.com': vence});

      expect(await vigentesA(repo, rechazo.add(const Duration(minutes: 30))), {
        'ana@correo.com': vence,
      });
    });

    test('a los 59 min 59,999 s sigue vigente; a los 60 min exactos ya no', () async {
      final vence = rechazo.add(const Duration(minutes: 60));
      final repo = _BloqueosFalsos({'ana@correo.com': vence});

      expect(await vigentesA(repo, vence.subtract(const Duration(milliseconds: 1))), {
        'ana@correo.com': vence,
      });
      expect(await vigentesA(repo, vence), isEmpty);
    });

    test('los vencidos no vuelven, y los vigentes de otras direcciones sí', () async {
      final repo = _BloqueosFalsos({
        'vieja@correo.com': rechazo.add(const Duration(minutes: 10)),
        'nueva@correo.com': rechazo.add(const Duration(minutes: 55)),
      });

      final vigentes = await vigentesA(repo, rechazo.add(const Duration(minutes: 30)));

      expect(vigentes.keys, ['nueva@correo.com']);
    });

    test('un candado nunca dura más de una hora aunque el reloj se haya atrasado', () async {
      // Se guardó con el reloj adelantado 5 horas; después se corrigió.
      final repo = _BloqueosFalsos({'ana@correo.com': rechazo.add(const Duration(hours: 6))});

      final vigentes = await vigentesA(repo, rechazo);

      expect(vigentes['ana@correo.com'], rechazo.add(const Duration(minutes: 60)));
    });

    test('un vencimiento justo a la hora no se acorta', () async {
      final vence = rechazo.add(const Duration(minutes: 60));
      final repo = _BloqueosFalsos({'ana@correo.com': vence});

      expect((await vigentesA(repo, rechazo))['ana@correo.com'], vence);
    });

    test('compara instantes: una hora local y una UTC del mismo instante dan lo mismo', () async {
      final vence = rechazo.add(const Duration(minutes: 60));
      final repo = _BloqueosFalsos({'ana@correo.com': vence});
      final ahoraLocal = rechazo.add(const Duration(minutes: 30)).toLocal();

      expect(await vigentesA(repo, ahoraLocal), {'ana@correo.com': vence});
    });
  });
}
