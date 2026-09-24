// Conformidad con convenciones-desarrollo.md §7.5 ("sin PII en logs: solo IDs").
//
// `EquatableConfig.stringify` arranca en `true` en debug, así que `Equatable.toString()`
// imprime `props`. Cualquier interpolación del objeto, `logger.d(entidad)` o excepción que lo
// incluya filtraría teléfono, notas del cliente, cédula o el JWT. Las entidades con esos campos
// apagan `stringify`; esto lo verifica con la config en `true`, que es el peor caso.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resultado_registro.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/usuario.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/iniciar_sesion_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/registrar_usuario_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

void main() {
  final stringifyOriginal = EquatableConfig.stringify;

  setUp(() {
    EquatableConfig.stringify = true;
  });

  tearDown(() {
    EquatableConfig.stringify = stringifyOriginal;
  });

  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  group('Sin PII en toString (convenciones-desarrollo.md §7.5)', () {
    test('dado una Persona con telefono y notas, cuando se interpola, no aparece ningun dato '
        'personal', () {
      final persona = Persona(
        id: 'per-1',
        nombre: 'Rosalia',
        apellido: 'Techera',
        telefono: '099123456',
        notasGlobales: 'prefiere que la visiten de tarde',
        auditoria: auditoria,
      );

      final texto = '$persona';

      expect(texto, isNot(contains('Rosalia')));
      expect(texto, isNot(contains('Techera')));
      expect(texto, isNot(contains('099123456')));
      expect(texto, isNot(contains('prefiere que la visiten de tarde')));
    });

    test('dado una Visita con notas, cuando se interpola, las notas no aparecen', () {
      final visita = Visita(
        id: 'vis-1',
        espacioPersonaId: 'ep-1',
        fecha: DateTime(2026, 9, 18),
        tipoResultado: TipoResultadoVisita.entrevista,
        notas: 'la hija esta enferma, volver el martes',
        colportorId: 'u-1',
        jornadaId: 'jor-1',
        auditoria: auditoria,
      );

      expect('$visita', isNot(contains('la hija esta enferma, volver el martes')));
    });

    test('dado un Usuario, cuando se interpola, no aparecen nombre, cedula ni email', () {
      const usuario = Usuario(
        id: 'u-1',
        nombre: 'Matias',
        apellido: 'Sosa',
        cedula: '48123456',
        email: 'matias@example.com',
      );

      final texto = '$usuario';

      expect(texto, isNot(contains('Matias')));
      expect(texto, isNot(contains('48123456')));
      expect(texto, isNot(contains('matias@example.com')));
    });

    test('dado una Sesion, cuando se interpola, no aparece el access token', () {
      final sesion = Sesion(
        usuarioId: 'u-1',
        email: 'matias@example.com',
        accessToken: 'jwt-super-secreto',
        expiraEn: DateTime(2026, 9, 18),
      );

      final texto = '$sesion';

      expect(texto, isNot(contains('jwt-super-secreto')));
      expect(texto, isNot(contains('matias@example.com')));
    });

    test('dado un IniciarSesionParams, cuando se interpola, no aparecen el email ni la '
        'contraseña', () {
      const params = IniciarSesionParams(email: 'matias@example.com', password: 'Secreta123');

      final texto = '$params';

      expect(texto, isNot(contains('matias@example.com')));
      expect(texto, isNot(contains('Secreta123')));
    });

    test('dado un RegistrarUsuarioParams, cuando se interpola, no aparecen nombre, cedula, '
        'email ni contraseña', () {
      const params = RegistrarUsuarioParams(
        nombre: 'Matias',
        apellido: 'Sosa',
        cedula: '48123456',
        email: 'matias@example.com',
        password: 'Secreta123',
        aceptaTerminos: true,
        aceptaTradeOffE2E: true,
      );

      final texto = '$params';

      expect(texto, isNot(contains('Matias')));
      expect(texto, isNot(contains('48123456')));
      expect(texto, isNot(contains('matias@example.com')));
      expect(texto, isNot(contains('Secreta123')));
    });

    test('dado un ResultadoRegistro, cuando se interpola, no aparece el email', () {
      final resultado = ResultadoRegistro(
        sesion: Sesion(
          usuarioId: 'u-1',
          email: 'matias@example.com',
          accessToken: 'jwt-super-secreto',
          expiraEn: DateTime(2026, 9, 18),
        ),
        email: 'matias@example.com',
      );

      final texto = '$resultado';

      expect(texto, isNot(contains('matias@example.com')));
      expect(texto, isNot(contains('jwt-super-secreto')));
    });

    test('dado que se apaga stringify, cuando se comparan dos entidades iguales, siguen siendo '
        'iguales (stringify no toca ==)', () {
      const a = Usuario(
        id: 'u-1',
        nombre: 'Matias',
        apellido: 'Sosa',
        cedula: '48123456',
        email: 'matias@example.com',
      );
      const b = Usuario(
        id: 'u-1',
        nombre: 'Matias',
        apellido: 'Sosa',
        cedula: '48123456',
        email: 'matias@example.com',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
