// «Cancelar tr.» (HU-STK-005, #512): quien la pidió la cancela mientras está por autorizar.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/transferencia.dart';
import 'package:colportores_mobile/features/transferencias/domain/usecases/cancelar_transferencia_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../helpers/transferencias_en_memoria.dart';

void main() {
  final ahora = DateTime.utc(2026, 10, 23, 18);
  late TransferenciasEnMemoria repo;
  late CancelarTransferenciaUseCase caso;

  setUp(() {
    repo = TransferenciasEnMemoria()..sembrar(transferenciaDeEjemplo());
    caso = CancelarTransferenciaUseCase(repo, ahora: () => ahora);
  });

  test('la pasa a cancelada con la hora de ahora', () async {
    final r = await caso(
      const CancelarTransferenciaParams(transferenciaId: 't-1', colportorId: 'juan'),
    );
    final t = r.getOrElse(() => throw StateError('falló'));
    expect(t.estado, EstadoDeTransferencia.cancelada);
    expect(t.auditoria.updatedAt, ahora);
  });

  test('un segundo toque responde bien sin hacer nada de más', () async {
    const p = CancelarTransferenciaParams(transferenciaId: 't-1', colportorId: 'juan');
    await caso(p);
    final r = await caso(p);
    expect(r.isRight(), isTrue);
    expect(repo.cancelaciones, 2);
  });

  test('quien entrega no la cancela', () async {
    final r = await caso(
      const CancelarTransferenciaParams(transferenciaId: 't-1', colportorId: 'ana'),
    );
    expect(r, const Left<Failure, Transferencia>(FailureTransferenciaNoCancelable()));
  });

  test('ya autorizada, ya no', () async {
    repo.sembrar(transferenciaDeEjemplo(estado: EstadoDeTransferencia.autorizada));
    final r = await caso(
      const CancelarTransferenciaParams(transferenciaId: 't-1', colportorId: 'juan'),
    );
    expect(r, const Left<Failure, Transferencia>(FailureTransferenciaNoCancelable()));
  });

  test('una que no existe', () async {
    final r = await caso(
      const CancelarTransferenciaParams(transferenciaId: 'nada', colportorId: 'juan'),
    );
    expect(r.isLeft(), isTrue);
  });

  test('ids vacíos no llegan al repositorio', () async {
    final r = await caso(
      const CancelarTransferenciaParams(transferenciaId: ' ', colportorId: 'juan'),
    );
    expect(r.isLeft(), isTrue);
    expect(repo.cancelaciones, 0);
  });
}
