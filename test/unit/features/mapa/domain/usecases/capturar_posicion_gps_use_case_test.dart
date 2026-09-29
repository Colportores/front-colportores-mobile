// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proveedor_gps.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/capturar_posicion_gps_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

final class _GpsFijo implements ProveedorGps {
  _GpsFijo(this.respuesta);

  final Either<Failure, LecturaGps> respuesta;

  @override
  Future<Either<Failure, LecturaGps>> posicionActual() async => respuesta;
}

void main() {
  Future<Either<Failure, LecturaGps>> capturar(Either<Failure, LecturaGps> gps) =>
      CapturarPosicionGpsUseCase(_GpsFijo(gps))(const NoParams());

  group('CapturarPosicionGpsUseCase', () {
    test('dado una lectura válida, cuando captura, la devuelve con su precisión', () async {
      const lectura = LecturaGps(
        coordenadas: Coordenadas(lat: -34.891, lon: -56.125),
        precisionMetros: 8,
      );

      expect(await capturar(const Right(lectura)), const Right<Failure, LecturaGps>(lectura));
    });

    test('dado una lectura imprecisa (> 50 m), cuando captura, la devuelve igual: se advierte al '
        'confirmar el alta', () async {
      const lectura = LecturaGps(
        coordenadas: Coordenadas(lat: -34.891, lon: -56.125),
        precisionMetros: 120,
      );

      expect(await capturar(const Right(lectura)), const Right<Failure, LecturaGps>(lectura));
    });

    test('dado que el GPS reporta (0, 0), cuando captura, lo trata como sin GPS', () async {
      const lectura = LecturaGps(coordenadas: Coordenadas(lat: 0, lon: 0), precisionMetros: 5);

      expect(
        await capturar(const Right(lectura)),
        const Left<Failure, LecturaGps>(FailureGpsNoDisponible(motivo: MotivoSinGps.sinSenal)),
      );
    });

    test('dado una lectura fuera de rango, cuando captura, la trata como sin GPS', () async {
      const lectura = LecturaGps(coordenadas: Coordenadas(lat: 95, lon: 0), precisionMetros: 5);

      expect((await capturar(const Right(lectura))).isLeft(), isTrue);
    });

    for (final motivo in MotivoSinGps.values) {
      test('dado GPS no disponible (${motivo.name}), cuando captura, devuelve el Failure con su '
          'motivo', () async {
        final r = await capturar(Left(FailureGpsNoDisponible(motivo: motivo)));

        expect(r, Left<Failure, LecturaGps>(FailureGpsNoDisponible(motivo: motivo)));
        expect(
          r.fold((f) => f.mensaje, (_) => ''),
          contains('Marcar en el mapa'),
          reason: 'el aviso guía hacia la colocación manual',
        );
      });
    }
  });
}
