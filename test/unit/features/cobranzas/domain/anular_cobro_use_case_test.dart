import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/detalle_del_cobro.dart';
import 'package:colportores_mobile/features/cobranzas/domain/repositories/anulacion_de_cobro_repository.dart';
import 'package:colportores_mobile/features/cobranzas/domain/usecases/anular_cobro_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/anular_cobro_arnes.dart';

final class _Repo implements AnulacionDeCobroRepository {
  final pedidos =
      <({String id, MotivoDeAnulacion motivo, String? justificacion, DateTime ahora})>[];

  @override
  Future<Either<Failure, DetalleDelCobro?>> detalle(String cobranzaId) async =>
      Right(detalleDeEjemplo());

  @override
  Future<Either<Failure, AnulacionHecha>> anular({
    required String cobranzaId,
    required MotivoDeAnulacion motivo,
    required String colportorId,
    required DateTime ahora,
    String? justificacion,
  }) async {
    pedidos.add((id: cobranzaId, motivo: motivo, justificacion: justificacion, ahora: ahora));
    return Right(AnulacionHecha(detalle: detalleDeEjemplo()));
  }
}

void main() {
  late _Repo repo;
  late AnularCobroUseCase caso;
  final reloj = DateTime.utc(2026, 10, 23, 18);

  setUp(() {
    repo = _Repo();
    caso = AnularCobroUseCase(repo, ahora: () => reloj);
  });

  AnularCobroParams params({
    MotivoDeAnulacion? motivo = MotivoDeAnulacion.montoEquivocado,
    String? justificacion,
    String id = 'c-1',
    String colportor = 'col-1',
  }) => AnularCobroParams(
    cobranzaId: id,
    colportorId: colportor,
    motivo: motivo,
    justificacion: justificacion,
  );

  String? codigo(Either<Failure, AnulacionHecha> r) => r.fold((f) => f.codigo, (_) => null);

  test('sin motivo no anula nada', () async {
    expect(codigo(await caso(params(motivo: null))), 'COBRO_ANULACION_SIN_MOTIVO');
    expect(repo.pedidos, isEmpty);
  });

  test('«Otro» sin texto, con solo espacios o con más de 200 caracteres no anula nada', () async {
    for (final texto in [null, '', '   \n ', '​', 'a' * 201]) {
      final r = await caso(params(motivo: MotivoDeAnulacion.otro, justificacion: texto));
      expect(codigo(r), 'COBRO_ANULACION_SIN_MOTIVO', reason: 'texto: "$texto"');
    }
    expect(repo.pedidos, isEmpty);
  });

  test('«Otro» con 200 caracteres pasa, limpio de espacios de más', () async {
    await caso(params(motivo: MotivoDeAnulacion.otro, justificacion: '  ${'a' * 200} '));
    expect(repo.pedidos.single.justificacion, 'a' * 200);

    await caso(params(motivo: MotivoDeAnulacion.otro, justificacion: ' dos   palabras\n'));
    expect(repo.pedidos.last.justificacion, 'dos palabras');
  });

  test(
    'con un motivo de la lista el texto se descarta y se usa el reloj del teléfono en UTC',
    () async {
      await caso(
        params(motivo: MotivoDeAnulacion.registreDosVeces, justificacion: 'algo que no cuenta'),
      );

      final p = repo.pedidos.single;
      expect([p.id, p.motivo, p.justificacion], ['c-1', MotivoDeAnulacion.registreDosVeces, null]);
      expect(p.ahora, reloj);
      expect(p.ahora.isUtc, isTrue);
    },
  );

  test('sin id del cobro o de la cuenta no anula nada', () async {
    expect(codigo(await caso(params(id: ' '))), 'COBRO_NO_ANULADO');
    expect(codigo(await caso(params(colportor: ''))), 'COBRO_NO_ANULADO');
    expect(repo.pedidos, isEmpty);
  });

  test('la ventana: 72 h desde el cobro, inclusive', () {
    final d = detalleDeEjemplo();
    final limite = d.cobranza.fecha.add(const Duration(hours: 72));

    expect(d.puedeAnularseHasta, limite);
    expect(d.dentroDelPlazo(limite), isTrue);
    expect(d.dentroDelPlazo(limite.add(const Duration(microseconds: 1))), isFalse);
  });
}
