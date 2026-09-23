// HU-AUTH-006 (cerrar sesión) y HU-AUTH-010 (borrar datos locales): los use cases orquestan, la
// lógica de cada paso vive en los repositorios.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resultado_cierre_sesion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/borrar_datos_locales_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/cerrar_sesion_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/obtener_resumen_datos_locales_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/reintentar_revocacion_pendiente_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockDatosLocalesRepository extends Mock implements DatosLocalesRepository {}

void main() {
  late _MockAuthRepository auth;
  late _MockDatosLocalesRepository datos;

  setUp(() {
    auth = _MockAuthRepository();
    datos = _MockDatosLocalesRepository();
    when(
      auth.cerrarSesion,
    ).thenAnswer((_) async => const Right(ResultadoCierreSesion.revocacionPendiente));
  });

  test('CerrarSesionUseCase delega en el repositorio', () async {
    final r = await CerrarSesionUseCase(auth)(const NoParams());

    expect(
      r,
      const Right<Failure, ResultadoCierreSesion>(ResultadoCierreSesion.revocacionPendiente),
    );
  });

  test('ReintentarRevocacionPendienteUseCase delega en el repositorio', () async {
    when(auth.reintentarRevocacionPendiente).thenAnswer((_) async => const Right(unit));

    final r = await ReintentarRevocacionPendienteUseCase(auth)(const NoParams());

    expect(r, const Right<Failure, Unit>(unit));
  });

  test('ObtenerResumenDatosLocalesUseCase delega en el repositorio', () async {
    const resumen = ResumenDatosLocales(
      personas: 1,
      visitas: 2,
      operacionesSinSincronizar: 3,
      hayBackupEnDrive: false,
    );
    when(datos.resumen).thenAnswer((_) async => const Right(resumen));

    final r = await ObtenerResumenDatosLocalesUseCase(datos)(const NoParams());

    expect(r, const Right<Failure, ResumenDatosLocales>(resumen));
  });

  group('BorrarDatosLocalesUseCase', () {
    test('si el borrado sale bien, después cierra la sesión (revocación best-effort)', () async {
      when(
        () => datos.borrar(incluirBackupDrive: true),
      ).thenAnswer((_) async => const Right(ResultadoBorradoDatosLocales.completo));

      final r = await BorrarDatosLocalesUseCase(datos, auth)(
        const BorrarDatosLocalesParams(incluirBackupDrive: true),
      );

      expect(
        r,
        const Right<Failure, ResultadoBorradoDatosLocales>(ResultadoBorradoDatosLocales.completo),
      );
      verify(auth.cerrarSesion).called(1);
    });

    test('si el borrado se niega, la sesión sigue abierta', () async {
      when(
        () => datos.borrar(incluirBackupDrive: false),
      ).thenAnswer((_) async => const Left(FailureDatosSinSincronizar(4)));

      final r = await BorrarDatosLocalesUseCase(datos, auth)(
        const BorrarDatosLocalesParams(incluirBackupDrive: false),
      );

      expect(r, const Left<Failure, ResultadoBorradoDatosLocales>(FailureDatosSinSincronizar(4)));
      verifyNever(auth.cerrarSesion);
    });

    test('los params se comparan por valor', () {
      expect(
        const BorrarDatosLocalesParams(incluirBackupDrive: true),
        const BorrarDatosLocalesParams(incluirBackupDrive: true),
      );
    });
  });
}
