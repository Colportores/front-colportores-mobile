// Test de dominio: Dart puro. «Entregar ahora» (HU-VEN-002, #430) con un repositorio falso.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/entrega_repository.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/entregar_ahora_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

class _RepoFalso implements EntregaRepository {
  Failure? respuesta;
  final llamadas =
      <({String ventaId, String colportorId, DateTime ahora, String Function() generarId})>[];

  @override
  Future<Either<Failure, EntregaRegistrada>> entregarAhora(
    String ventaId, {
    required String colportorId,
    required DateTime ahora,
    required String Function() generarId,
  }) async {
    llamadas.add((ventaId: ventaId, colportorId: colportorId, ahora: ahora, generarId: generarId));
    final falla = respuesta;
    return falla == null ? const Right(EntregaRegistrada(entregas: [])) : Left(falla);
  }

  @override
  Future<Either<Failure, List<Entrega>>> deLaVenta(String ventaId) async => const Right([]);
}

void main() {
  late _RepoFalso repo;
  var n = 0;
  String generar() => 'e-${++n}';

  setUp(() {
    repo = _RepoFalso();
    n = 0;
  });

  EntregarAhoraUseCase caso({DateTime Function()? ahora}) =>
      EntregarAhoraUseCase(repo, generarId: generar, ahora: ahora);

  test('dado una venta, cuando entrega ahora, pasa la venta, quien entrega, la hora en UTC y el '
      'generador de ids al repositorio', () async {
    final hora = DateTime(2026, 10, 29, 15, 30);

    final r = await caso(ahora: () => hora)(
      const EntregarAhoraParams(ventaId: 'v-1', colportorId: 'col-1'),
    );

    expect(r.isRight(), isTrue);
    final llamada = repo.llamadas.single;
    expect(llamada.ventaId, 'v-1');
    expect(llamada.colportorId, 'col-1');
    expect(llamada.ahora, hora.toUtc());
    expect(llamada.ahora.isUtc, isTrue);
    expect(llamada.generarId(), 'e-1');
  });

  test('dado ids con espacios, cuando entrega ahora, los recorta', () async {
    await caso()(const EntregarAhoraParams(ventaId: ' v-1 ', colportorId: ' col-1 '));

    expect(repo.llamadas.single.ventaId, 'v-1');
    expect(repo.llamadas.single.colportorId, 'col-1');
  });

  test('dado un id vacío, cuando entrega ahora, no guarda nada y avisa que no se guardó', () async {
    for (final params in const [
      EntregarAhoraParams(ventaId: '', colportorId: 'col-1'),
      EntregarAhoraParams(ventaId: 'v-1', colportorId: '  '),
    ]) {
      final r = await caso()(params);

      expect(r.fold((f) => f, (_) => null), isA<FailureEntregaNoGuardada>());
    }
    expect(repo.llamadas, isEmpty);
  });

  test(
    'dado un repositorio que falla, cuando entrega ahora, devuelve esa falla tal cual',
    () async {
      repo.respuesta = const FailureEntregaNoGuardada(causa: 'StateError');

      final r = await caso()(const EntregarAhoraParams(ventaId: 'v-1', colportorId: 'col-1'));

      expect(r.fold((f) => f, (_) => null), const FailureEntregaNoGuardada(causa: 'StateError'));
    },
  );

  test('dado el texto de la falla, cuando se lee, dice qué pasó y qué hacer', () {
    const falla = FailureEntregaNoGuardada();

    expect(falla.mensaje, contains('No se registró nada'));
    expect(falla.mensaje, contains('probá de nuevo'));
  });
}
