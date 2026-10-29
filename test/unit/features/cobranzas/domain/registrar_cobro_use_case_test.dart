// HU-COB-001, HU-COB-002 y HU-COB-003: las reglas del cobro antes de tocar la base (#436, #164).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/domain/repositories/cobranza_repository.dart';
import 'package:colportores_mobile/features/cobranzas/domain/usecases/registrar_cobro_use_case.dart';
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
  late RegistrarCobroUseCase caso;

  RegistrarCobroParams params({
    int monto = 50000,
    DateTime? fecha,
    String venta = 'v-1',
    MedioCobranza medio = MedioCobranza.efectivo,
    TipoTarjeta? tipo,
    String? marca,
    String? aprobacion,
    String? referencia,
    String? banco,
  }) => RegistrarCobroParams(
    cobroId: 'c-1',
    ventaId: venta,
    montoCentavos: monto,
    colportorId: 'col-1',
    fecha: fecha,
    medio: medio,
    tarjetaTipo: tipo,
    tarjetaMarca: marca,
    numeroAprobacion: aprobacion,
    referenciaTransferencia: referencia,
    bancoOrigen: banco,
  );

  setUp(() {
    repo = _Repo();
    caso = RegistrarCobroUseCase(repo, ahora: () => _ahora);
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
    final r = await caso(params(monto: RegistrarCobroUseCase.maximoCentavos + 1));

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

  group('con tarjeta (HU-COB-002)', () {
    test('arma un cobro TARJETA con el tipo, la marca y el número de aprobación', () async {
      await caso(
        params(
          medio: MedioCobranza.tarjeta,
          tipo: TipoTarjeta.credito,
          marca: 'Visa',
          aprobacion: '884213',
        ),
      );

      final cobro = repo.recibidos.single;
      expect(cobro.medio, MedioCobranza.tarjeta);
      expect(cobro.tarjetaTipo, TipoTarjeta.credito);
      expect(cobro.tarjetaMarca, 'Visa');
      expect(cobro.numeroAprobacion, '884213');
      expect(cobro.referenciaTransferencia, isNull);
      expect(cobro.bancoOrigen, isNull);
    });

    test('la marca y la aprobación son opcionales: sin ellas se guarda igual', () async {
      final r = await caso(params(medio: MedioCobranza.tarjeta, tipo: TipoTarjeta.debito));

      expect(r.isRight(), isTrue);
      final cobro = repo.recibidos.single;
      expect([cobro.tarjetaMarca, cobro.numeroAprobacion], [null, null]);
    });

    test('los textos se guardan sin espacios de más y los vacíos como «sin dato»', () async {
      await caso(params(medio: MedioCobranza.tarjeta, marca: '  Naranja   X ', aprobacion: '   '));

      final cobro = repo.recibidos.single;
      expect(cobro.tarjetaMarca, 'Naranja X');
      expect(cobro.numeroAprobacion, isNull);
    });

    test(
      'con otro medio los datos de la tarjeta se descartan (el servidor los rechazaría)',
      () async {
        for (final medio in [MedioCobranza.efectivo, MedioCobranza.transferencia]) {
          repo.recibidos.clear();
          await caso(
            params(medio: medio, tipo: TipoTarjeta.credito, marca: 'Visa', aprobacion: '884213'),
          );

          final cobro = repo.recibidos.single;
          expect(
            [cobro.tarjetaTipo, cobro.tarjetaMarca, cobro.numeroAprobacion],
            [null, null, null],
            reason: medio.name,
          );
        }
      },
    );

    test('el largo que acepta el servidor (40) pasa, y uno más no llega a la base', () async {
      final justo = 'A' * RegistrarCobroUseCase.maximoAprobacion;
      final ok = await caso(params(medio: MedioCobranza.tarjeta, aprobacion: justo));
      expect(ok.isRight(), isTrue);
      repo.recibidos.clear();

      for (final r in [
        await caso(params(medio: MedioCobranza.tarjeta, aprobacion: '${justo}A')),
        await caso(params(medio: MedioCobranza.tarjeta, marca: 'M' * 41)),
      ]) {
        expect(r.fold((f) => f, (_) => null), isA<FailureCobroDatoDelMedioInvalido>());
      }
      expect(repo.recibidos, isEmpty);
    });
  });

  group('por transferencia (HU-COB-003)', () {
    test('arma un cobro TRANSFERENCIA con la referencia y el banco de origen', () async {
      await caso(params(medio: MedioCobranza.transferencia, referencia: 'TX-12345', banco: 'BROU'));

      final cobro = repo.recibidos.single;
      expect(cobro.medio, MedioCobranza.transferencia);
      expect(cobro.referenciaTransferencia, 'TX-12345');
      expect(cobro.bancoOrigen, 'BROU');
      expect(cobro.tarjetaTipo, isNull);
      expect(cobro.tarjetaMarca, isNull);
      expect(cobro.numeroAprobacion, isNull);
    });

    test('la referencia y el banco son opcionales', () async {
      final r = await caso(params(medio: MedioCobranza.transferencia));

      expect(r.isRight(), isTrue);
      final cobro = repo.recibidos.single;
      expect([cobro.referenciaTransferencia, cobro.bancoOrigen], [null, null]);
    });

    test('con otro medio la referencia y el banco se descartan', () async {
      for (final medio in [MedioCobranza.efectivo, MedioCobranza.tarjeta]) {
        repo.recibidos.clear();
        await caso(params(medio: medio, referencia: 'TX-1', banco: 'BROU'));

        final cobro = repo.recibidos.single;
        expect(
          [cobro.referenciaTransferencia, cobro.bancoOrigen],
          [null, null],
          reason: medio.name,
        );
      }
    });

    test('el banco acepta 60 y la referencia 40; pasados esos largos no llega a la base', () async {
      final ok = await caso(
        params(medio: MedioCobranza.transferencia, referencia: '9' * 40, banco: 'B' * 60),
      );
      expect(ok.isRight(), isTrue);
      repo.recibidos.clear();

      for (final r in [
        await caso(params(medio: MedioCobranza.transferencia, referencia: '9' * 41)),
        await caso(params(medio: MedioCobranza.transferencia, banco: 'B' * 61)),
      ]) {
        expect(r.fold((f) => f, (_) => null), isA<FailureCobroDatoDelMedioInvalido>());
      }
      expect(repo.recibidos, isEmpty);
    });

    test('la tilde y la Ñ del banco se conservan', () async {
      await caso(params(medio: MedioCobranza.transferencia, banco: ' Banco  Ñandú Itaú '));

      expect(repo.recibidos.single.bancoOrigen, 'Banco Ñandú Itaú');
    });
  });

  group('limpiar', () {
    test('junta los espacios, saltos, no separables y de ancho cero, y recorta', () {
      expect(RegistrarCobroUseCase.limpiar(' a \n b​c  '), 'a b c');
    });

    test('nulo, vacío o solo espacios quedan en nulo', () {
      expect(RegistrarCobroUseCase.limpiar(null), isNull);
      expect(RegistrarCobroUseCase.limpiar(''), isNull);
      expect(RegistrarCobroUseCase.limpiar(' \n\t '), isNull);
    });
  });
}
