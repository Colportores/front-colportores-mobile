// HU-COB-001: las reglas del cobro en efectivo antes de tocar la base (#436).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/domain/repositories/cobranza_repository.dart';
import 'package:colportores_mobile/features/cobranzas/domain/usecases/registrar_cobro_efectivo_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

final _ahora = DateTime.utc(2026, 10, 23, 13, 45);

final class _Repo implements CobranzaRepository {
  final recibidos = <Cobranza>[];

  @override
  Future<Either<Failure, CobroRegistrado>> registrar(Cobranza cobro) async {
    recibidos.add(cobro);
    return Right(
      CobroRegistrado(
        cobranza: cobro,
        venta: VentaConSaldo(
          ventaId: cobro.ventaId,
          numeroTalonario: '0042',
          fecha: _ahora,
          montoTotalCentavos: 150000,
          cobradoCentavos: cobro.montoCentavos,
        ),
      ),
    );
  }

  @override
  Future<Either<Failure, VentaConSaldo?>> ventaConSaldo(String ventaId) async => const Right(null);

  @override
  Future<Either<Failure, List<VentaConSaldo>>> ventasConSaldoDe(String personaId) async =>
      const Right([]);
}

void main() {
  late _Repo repo;
  late RegistrarCobroEfectivoUseCase caso;

  RegistrarCobroEfectivoParams params({int monto = 50000, DateTime? fecha, String venta = 'v-1'}) =>
      RegistrarCobroEfectivoParams(
        cobroId: 'c-1',
        ventaId: venta,
        montoCentavos: monto,
        colportorId: 'col-1',
        fecha: fecha,
      );

  setUp(() {
    repo = _Repo();
    caso = RegistrarCobroEfectivoUseCase(repo, ahora: () => _ahora);
  });

  test('arma un cobro EFECTIVO de la venta, con la fecha de hoy por defecto', () async {
    final r = await caso(params());

    final cobro = repo.recibidos.single;
    expect(
      [cobro.id, cobro.ventaId, cobro.montoCentavos, cobro.medio],
      ['c-1', 'v-1', 50000, MedioCobranza.efectivo],
    );
    expect(cobro.fecha, _ahora);
    expect(cobro.auditoria.createdBy, 'col-1');
    expect(r.isRight(), isTrue);
  });

  test('un monto vacío, cero o negativo no llega a la base', () async {
    for (final monto in [0, -1]) {
      final r = await caso(params(monto: monto));
      expect(r.fold((f) => f, (_) => null), isA<FailureCobroMontoInvalido>());
    }
    expect(repo.recibidos, isEmpty);
  });

  test('un monto más grande que el entero del servidor no llega a la base', () async {
    final r = await caso(params(monto: RegistrarCobroEfectivoUseCase.maximoCentavos + 1));

    expect(r.fold((f) => f, (_) => null), isA<FailureCobroMontoInvalido>());
  });

  test('la fecha de mañana (en Montevideo) se rechaza; la de hoy a la noche no', () async {
    final manana = await caso(params(fecha: DateTime.utc(2026, 10, 24, 12)));
    expect(manana.fold((f) => f, (_) => null), isA<FailureCobroFechaInvalida>());
    final hoyAlaNoche = await caso(params(fecha: DateTime.utc(2026, 10, 24, 2)));
    expect(hoyAlaNoche.isRight(), isTrue);
    expect(repo.recibidos.length, 1);
  });

  test('sin ids no guarda nada', () async {
    final r = await caso(params(venta: '  '));

    expect(r.fold((f) => f, (_) => null), isA<FailureCobroNoGuardado>());
    expect(repo.recibidos, isEmpty);
  });
}
