// HU-SYNC-006 (#175) — La marca de «el asistente de recuperación ya se resolvió» sobre el almacén
// seguro: por usuario, sin lanzar al escribir.
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/features/respaldo/data/repositories/recuperacion_resuelta_repository_impl.dart';
import 'package:colportores_mobile/features/respaldo/domain/repositories/recuperacion_resuelta_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';
import '../../../helpers/respaldo_drive_falsos.dart';

void main() {
  late AlmacenControlable almacen;
  late RecuperacionResueltaRepositoryImpl repo;

  setUp(() {
    almacen = AlmacenControlable();
    repo = RecuperacionResueltaRepositoryImpl(almacen, logger: loggerMudo());
  });

  test('sin marca, no está resuelta', () async {
    expect(await repo.estaResuelta('u-1'), isFalse);
  });

  test('marcarla la deja resuelta para ese usuario y no para otro', () async {
    await repo.marcarResuelta('u-1');

    expect(await repo.estaResuelta('u-1'), isTrue);
    expect(await repo.estaResuelta('u-2'), isFalse);
    expect(almacen.contenido[ClaveSegura.recuperacionResuelta], 'u-1');
  });

  test('si no se puede escribir, no lanza (se vuelve a ofrecer, que es lo seguro)', () async {
    almacen.alEscribir = true;

    await repo.marcarResuelta('u-1');

    expect(await repo.estaResuelta('u-1'), isFalse);
  });

  test('si no se puede leer, lanza: quien pregunta decide qué hacer', () async {
    almacen.alLeer = true;

    expect(() => repo.estaResuelta('u-1'), throwsA(isA<AlmacenSeguroException>()));
  });

  test('«nunca se ofrece» es el valor por defecto de la app: dice que ya está resuelta', () async {
    const repo = RecuperacionNuncaSeOfrece();

    expect(await repo.estaResuelta('u-1'), isTrue);
    await repo.marcarResuelta('u-1');
  });
}
