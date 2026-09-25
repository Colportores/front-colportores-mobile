import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/politica_sesion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/services/reloj_sesion.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/obtener_sesion_actual_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// Test de dominio: Dart puro.

class _MockAuthRepository extends Mock implements AuthRepository {}

final class _RelojFijo implements RelojSesion {
  _RelojFijo(this.instante);

  final DateTime instante;

  @override
  Future<DateTime> ahora() async => instante;

  @override
  Future<void> registrar(DateTime visto) async {}
}

void main() {
  late _MockAuthRepository repository;
  final ahora = DateTime.utc(2026, 9, 1, 12);

  Sesion sesionQueExpira(DateTime cuando) => Sesion(
    usuarioId: '01920000-0000-7000-8000-000000000001',
    email: 'ana@example.com',
    accessToken: 'jwt',
    expiraEn: cuando,
  );

  setUpAll(() => registerFallbackValue(MotivoExpiracion.inactividad));

  setUp(() {
    repository = _MockAuthRepository();
    when(() => repository.expirarSesion(any())).thenAnswer((_) async => const Right(unit));
  });

  Future<Either<Failure, Sesion?>> obtener() =>
      ObtenerSesionActualUseCase(repository, _RelojFijo(ahora))(const NoParams());

  group('ObtenerSesionActualUseCase (HU-AUTH-007, sesión deslizante de 30 días)', () {
    group('dado que hay una sesión guardada', () {
      test('dentro de la ventana, la devuelve aunque el JWT de acceso haya vencido', () async {
        // Emitida hace 25 días: el JWT de acceso (1 h) venció hace mucho, la sesión no.
        final emitida = ahora.subtract(const Duration(days: 25));
        final sesion = sesionQueExpira(PoliticaSesion.expiraEn(emitida));
        when(() => repository.sesionActual()).thenAnswer((_) async => Right(sesion));

        expect(await obtener(), Right<Failure, Sesion?>(sesion));
        verifyNever(() => repository.expirarSesion(any()));
      });

      test('vencida hace menos de 5 min (reloj desfasado), sigue vigente', () async {
        final sesion = sesionQueExpira(ahora.subtract(const Duration(minutes: 4)));
        when(() => repository.sesionActual()).thenAnswer((_) async => Right(sesion));

        expect(await obtener(), Right<Failure, Sesion?>(sesion));
      });

      test('Escenario: Expiración por inactividad — pasados los 30 días (y la tolerancia), la '
          'descarta y devuelve el aviso "Tu sesión expiró por inactividad. Iniciá sesión '
          'nuevamente."', () async {
        final vencida = sesionQueExpira(ahora.subtract(const Duration(minutes: 6)));
        when(() => repository.sesionActual()).thenAnswer((_) async => Right(vencida));

        final resultado = await obtener();

        expect(resultado, const Left<Failure, Sesion?>(FailureSesionExpiradaPorInactividad()));
        expect(
          const FailureSesionExpiradaPorInactividad().mensaje,
          'Tu sesión expiró por inactividad. Iniciá sesión nuevamente.',
        );
        verify(() => repository.expirarSesion(MotivoExpiracion.inactividad)).called(1);
      });
    });

    group('dado que no hay sesión', () {
      test('cuando consulta, devuelve null', () async {
        when(() => repository.sesionActual()).thenAnswer((_) async => const Right(null));

        expect(await obtener(), const Right<Failure, Sesion?>(null));
      });
    });

    group('dado que el repositorio falla o ya descartó la sesión al arrancar', () {
      for (final falla in const <Failure>[
        FailureInesperado(),
        FailureSesionExpiradaPorInactividad(),
      ]) {
        test('propaga ${falla.codigo}', () async {
          when(() => repository.sesionActual()).thenAnswer((_) async => Left(falla));

          expect(await obtener(), Left<Failure, Sesion?>(falla));
          verifyNever(() => repository.expirarSesion(any()));
        });
      }
    });
  });

  group('PoliticaSesion', () {
    test('la ventana es de 30 días desde la emisión, con 5 min de tolerancia de reloj', () {
      final emitida = DateTime.utc(2026, 8, 1, 10);
      final expira = PoliticaSesion.expiraEn(emitida);

      expect(expira, DateTime.utc(2026, 8, 31, 10));
      expect(PoliticaSesion.vencida(expira, expira.add(const Duration(minutes: 5))), isFalse);
      expect(PoliticaSesion.vencida(expira, expira.add(const Duration(minutes: 6))), isTrue);
    });

    test('compara en UTC aunque le pasen horas locales', () {
      final expira = DateTime.utc(2026, 8, 31, 10);

      expect(PoliticaSesion.vencida(expira, expira.toLocal()), isFalse);
      expect(PoliticaSesion.expiraEn(DateTime(2026, 8, 1)).isUtc, isTrue);
    });

    test('borde: justo en el instante de los 30 días (sin margen de tolerancia de por medio) '
        'todavía es vigente', () {
      final expira = PoliticaSesion.expiraEn(DateTime.utc(2026, 8, 1, 10));

      expect(PoliticaSesion.vencida(expira, expira), isFalse);
    });
  });
}
