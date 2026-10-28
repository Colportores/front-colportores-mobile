// «Entregar ahora» (HU-VEN-002, #430): qué filas arma el caso de uso y qué rechaza sin guardar nada.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/entregar_ahora_use_case.dart';
import 'package:test/test.dart';

import '../../../../../helpers/entrega_falsos.dart';

void main() {
  late EntregasEnMemoria repo;
  late EntregarAhoraUseCase caso;
  final ahora = DateTime.utc(2026, 10, 28, 13, 5, 7, 123);
  var ids = 0;

  setUp(() {
    repo = EntregasEnMemoria();
    ids = 0;
    caso = EntregarAhoraUseCase(repo, generarId: () => 'e-${++ids}', ahora: () => ahora);
  });

  EntregarAhoraParams params({
    List<ComponenteVendido> entregar = const [ComponenteVendido(productoId: 'p-1')],
    List<ComponenteVendido> pendientes = const [],
  }) => EntregarAhoraParams(
    ventaId: 'v-1',
    colportorId: 'col-1',
    aEntregar: entregar,
    quedanPendientes: pendientes,
  );

  test('lo tildado queda entregado, con la hora de ahora y sin pendiente', () async {
    final r = await caso(params());

    expect(r.isRight(), isTrue);
    final fila = repo.recibidas.single.filas.single;
    expect(
      [fila.id, fila.ventaId, fila.productoId, fila.cantidad, fila.pendiente],
      ['e-1', 'v-1', 'p-1', 1, false],
    );
    expect(fila.fechaEntrega, ahora);
    expect(fila.auditoria.createdBy, 'col-1');
  });

  test('lo destildado queda pendiente: sin fecha de entrega', () async {
    await caso(
      params(
        entregar: const [ComponenteVendido(productoId: 'p-1')],
        pendientes: const [ComponenteVendido(productoId: 'p-2', cantidad: 3)],
      ),
    );

    final filas = {for (final f in repo.recibidas.single.filas) f.productoId: f};
    expect(filas['p-1']!.pendiente, isFalse);
    expect(filas['p-2']!.pendiente, isTrue);
    expect(filas['p-2']!.fechaEntrega, isNull);
    expect(filas['p-2']!.cantidad, 3);
  });

  test('el mismo producto en varias filas de pantalla es una sola fila con la suma', () async {
    await caso(
      params(
        entregar: const [
          ComponenteVendido(productoId: 'p-1'),
          ComponenteVendido(productoId: 'p-1', cantidad: 2),
          ComponenteVendido(productoId: 'p-2'),
        ],
      ),
    );

    final filas = repo.recibidas.single.filas;
    expect(filas, hasLength(2));
    expect({for (final f in filas) f.productoId: f.cantidad}, {'p-1': 3, 'p-2': 1});
  });

  test('cada fila lleva su id propio', () async {
    await caso(
      params(
        entregar: const [ComponenteVendido(productoId: 'p-1')],
        pendientes: const [ComponenteVendido(productoId: 'p-2')],
      ),
    );

    expect(repo.recibidas.single.filas.map((f) => f.id), ['e-1', 'e-2']);
  });

  test('sin nada para entregar es FailureValidacion del campo productos y no guarda', () async {
    final r = await caso(
      params(
        entregar: const [],
        pendientes: const [ComponenteVendido(productoId: 'p-2')],
      ),
    );

    final falla = r.fold((f) => f, (_) => null) as FailureValidacion;
    expect(falla.campos.keys, ['productos']);
    expect(repo.recibidas, isEmpty);
  });

  test('una cantidad fuera de 1 a 99999 se rechaza sin guardar', () async {
    for (final cantidad in [0, -1, 100000]) {
      final r = await caso(
        params(
          entregar: [ComponenteVendido(productoId: 'p-1', cantidad: cantidad)],
        ),
      );

      expect(r.fold((f) => f, (_) => null), isA<FailureValidacion>(), reason: '$cantidad');
    }
    expect(repo.recibidas, isEmpty);
  });

  test('la falla del repositorio llega tal cual', () async {
    repo.fallas.add(const FailureEntregaNoGuardada());

    final r = await caso(params());

    expect(r.fold((f) => f, (_) => null), isA<FailureEntregaNoGuardada>());
  });
}
