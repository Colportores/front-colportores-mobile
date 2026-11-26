// Pedir una transferencia (HU-STK-005, #512): las reglas que el servidor rechazaría con `23514`/`23505` se
// validan antes de guardar, y la fila nace por autorizar.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/transferencia.dart';
import 'package:colportores_mobile/features/transferencias/domain/usecases/pedir_transferencia_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../helpers/transferencias_en_memoria.dart';

PedirTransferenciaParams _params({
  String transferenciaId = 't-1',
  String colportorId = 'juan',
  String entregaId = 'ana',
  List<MaterialPedido> materiales = const [MaterialPedido(productoId: 'p-1', cantidad: 2)],
  List<String>? ids,
}) => PedirTransferenciaParams(
  transferenciaId: transferenciaId,
  colportorId: colportorId,
  entregaId: entregaId,
  materiales: materiales,
  idsDeLineas: ids ?? [for (var i = 0; i < materiales.length; i++) 'l-$i'],
);

void main() {
  final ahora = DateTime.utc(2026, 10, 23, 17, 35);
  late TransferenciasEnMemoria repo;
  late PedirTransferenciaUseCase caso;

  setUp(() {
    repo = TransferenciasEnMemoria();
    caso = PedirTransferenciaUseCase(repo, ahora: () => ahora);
  });

  test('nace por autorizar: quien da es la otra, quien recibe es quien pide', () async {
    final r = await caso(_params());
    final pedida = r.getOrElse(() => throw StateError('falló')).transferencia;
    expect(pedida.estado, EstadoDeTransferencia.porAutorizar);
    expect(pedida.origenId, 'ana');
    expect(pedida.destinoId, 'juan');
    expect(pedida.lineas.single.productoId, 'p-1');
    expect(pedida.lineas.single.cantidad, 2);
    expect(pedida.auditoria.createdBy, 'juan');
    expect(pedida.auditoria.createdAt, ahora);
    expect(pedida.enCola, isTrue);
    expect(repo.pedidos, hasLength(1));
  });

  final casosInvalidos = <String, PedirTransferenciaParams>{
    'sin materiales': _params(materiales: const []),
    'consigo misma': _params(entregaId: 'juan'),
    'sin compañero': _params(entregaId: ' '),
    'sin id de transferencia': _params(transferenciaId: ''),
    'cantidad cero': _params(materiales: const [MaterialPedido(productoId: 'p-1', cantidad: 0)]),
    'cantidad negativa': _params(
      materiales: const [MaterialPedido(productoId: 'p-1', cantidad: -1)],
    ),
    'cantidad de más': _params(
      materiales: const [MaterialPedido(productoId: 'p-1', cantidad: 1000)],
    ),
    'producto repetido': _params(
      materiales: const [
        MaterialPedido(productoId: 'p-1', cantidad: 1),
        MaterialPedido(productoId: 'p-1', cantidad: 2),
      ],
    ),
    'faltan ids de línea': _params(ids: const []),
    'id de línea vacío': _params(ids: const [' ']),
  };
  casosInvalidos.forEach((nombre, params) {
    test('no guarda nada: $nombre', () async {
      final r = await caso(params);
      expect(r, const Left<Failure, Object>(FailureTransferenciaInvalida()));
      expect(repo.pedidos, isEmpty);
    });
  });

  test('999 unidades entran (el tope)', () async {
    final r = await caso(
      _params(materiales: const [MaterialPedido(productoId: 'p-1', cantidad: 999)]),
    );
    expect(r.isRight(), isTrue);
  });

  test('dos productos distintos entran, cada uno con su id de línea', () async {
    final r = await caso(
      _params(
        materiales: const [
          MaterialPedido(productoId: 'p-1', cantidad: 1),
          MaterialPedido(productoId: 'p-2', cantidad: 3),
        ],
      ),
    );
    final lineas = r.getOrElse(() => throw StateError('falló')).transferencia.lineas;
    expect(
      [for (final l in lineas) (l.id, l.productoId, l.cantidad)],
      [('l-0', 'p-1', 1), ('l-1', 'p-2', 3)],
    );
  });

  test('el mismo id es idempotente: un segundo toque no pide dos', () async {
    await caso(_params());
    final r = await caso(_params());
    expect(r.getOrElse(() => throw StateError('falló')).yaEstaba, isTrue);
    expect(repo.pedidos, hasLength(1));
  });

  test('si el repositorio falla, devuelve su falla y se puede reintentar con lo mismo', () async {
    repo.fallas.add(const FailureTransferenciaNoGuardada(causa: 'x'));
    expect((await caso(_params())).isLeft(), isTrue);
    expect(repo.pedidos, isEmpty);
    expect((await caso(_params())).isRight(), isTrue);
    expect(repo.pedidos, hasLength(1));
  });
}
