// Test de dominio: Dart puro. Registrar una devolución (HU-VEN-004, #161) con un repositorio falso.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_para_devolver.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/devolucion_repository.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/registrar_devolucion_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

class _RepoFalso implements DevolucionRepository {
  Failure? respuesta;
  final pedidos = <PedidoDeDevolucion>[];

  @override
  Future<Either<Failure, VentaParaDevolver?>> ventaParaDevolver(String ventaId) async =>
      const Right(null);

  @override
  Future<Either<Failure, DevolucionRegistrada>> registrar(PedidoDeDevolucion pedido) async {
    pedidos.add(pedido);
    final falla = respuesta;
    if (falla != null) return Left(falla);
    return Right(
      DevolucionRegistrada(
        devolucion: Devolucion(
          id: pedido.id,
          ventaId: pedido.ventaId,
          productos: const [],
          fechaDevolucion: pedido.ahora,
          auditoria: Auditoria(
            createdAt: pedido.ahora,
            updatedAt: pedido.ahora,
            createdBy: pedido.colportorId,
          ),
        ),
        totalCentavos: 0,
        saldoCentavos: 0,
        deboAlClienteCentavos: 0,
        eraTotal: false,
        yaEstaba: false,
      ),
    );
  }
}

void main() {
  late _RepoFalso repo;
  setUp(() => repo = _RepoFalso());

  RegistrarDevolucionUseCase caso({DateTime Function()? ahora}) =>
      RegistrarDevolucionUseCase(repo, ahora: ahora);

  RegistrarDevolucionParams params({
    String devolucionId = 'd-1',
    String ventaId = 'v-1',
    String colportorId = 'col-1',
    Map<String, int> unidades = const {'i-1': 1},
    QueHacerConLaDiferencia? queHacer,
    String? motivo,
  }) => RegistrarDevolucionParams(
    devolucionId: devolucionId,
    ventaId: ventaId,
    colportorId: colportorId,
    unidadesPorRenglon: unidades,
    queHacer: queHacer,
    motivo: motivo,
  );

  test('dado una devolución, cuando se registra, pasa el pedido con la hora en UTC', () async {
    final hora = DateTime(2026, 10, 29, 15, 30);

    final r = await caso(ahora: () => hora)(
      params(queHacer: QueHacerConLaDiferencia.retener, unidades: {'i-1': 2, 'i-2': 0}),
    );

    expect(r.isRight(), isTrue);
    final pedido = repo.pedidos.single;
    expect(pedido.id, 'd-1');
    expect(pedido.ventaId, 'v-1');
    expect(pedido.colportorId, 'col-1');
    expect(pedido.unidadesPorRenglon, {'i-1': 2});
    expect(pedido.queHacer, QueHacerConLaDiferencia.retener);
    expect(pedido.ahora, hora.toUtc());
    expect(pedido.ahora.isUtc, isTrue);
  });

  test('dado ids con espacios, los recorta', () async {
    await caso()(params(devolucionId: ' d-1 ', ventaId: ' v-1 ', colportorId: ' col-1 '));

    expect(repo.pedidos.single.id, 'd-1');
    expect(repo.pedidos.single.ventaId, 'v-1');
    expect(repo.pedidos.single.colportorId, 'col-1');
  });

  test('dado un id vacío, no guarda nada y avisa que no se guardó', () async {
    for (final p in [params(devolucionId: ''), params(ventaId: '  '), params(colportorId: '')]) {
      final r = await caso()(p);

      expect(r.fold((f) => f, (_) => null), isA<FailureDevolucionNoGuardada>());
    }
    expect(repo.pedidos, isEmpty);
  });

  test('dado nada elegido, no guarda nada y dice sin_productos', () async {
    for (final unidades in const [
      <String, int>{},
      {'i-1': 0},
      {'i-1': -1},
    ]) {
      final r = await caso()(params(unidades: unidades));

      expect(
        r.fold((f) => f, (_) => null),
        isA<FailureDevolucionInvalida>().having((f) => f.causa, 'causa', 'sin_productos'),
      );
    }
    expect(repo.pedidos, isEmpty);
  });

  test('dado un motivo, lo pasa limpio; en blanco pasa null', () async {
    await caso()(params(motivo: '  no le gustó \n'));
    await caso()(params(devolucionId: 'd-2', motivo: '   '));

    expect(repo.pedidos[0].motivo, 'no le gustó');
    expect(repo.pedidos[1].motivo, isNull);
  });

  test('dado un motivo de más de 500 caracteres, lo corta en 500', () async {
    await caso()(params(motivo: 'a' * 600));

    expect(repo.pedidos.single.motivo, hasLength(500));
  });

  test('dado un repositorio que falla, devuelve esa falla tal cual', () async {
    repo.respuesta = const FailureDevolucionFueraDePlazo();

    final r = await caso()(params());

    expect(r.fold((f) => f, (_) => null), isA<FailureDevolucionFueraDePlazo>());
  });
}
