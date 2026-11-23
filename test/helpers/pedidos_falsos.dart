// Falsos de los pedidos a la casa editora (HU-STK-009, #387): productos del canvas 37A, situaciones y un
// repositorio que el test maneja.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/armado_del_pedido.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/pedido.dart';
import 'package:colportores_mobile/features/pedidos/domain/repositories/armado_del_pedido_repository.dart';
import 'package:colportores_mobile/features/pedidos/domain/repositories/pedido_repository.dart';
import 'package:dartz/dartz.dart';

/// Los productos del canvas 37A·01: dos libros bonificables, dos revistas y un misionero.
const saludYHogar = ProductoPedible(
  id: 'p-salud',
  nombre: 'Salud y Hogar',
  categoriaDelCatalogo: CategoriaDeProducto.bonificables,
  precioDeCompraCentavos: 187000,
  stock: 2,
  esBonificable: true,
);
const nuestrosHijos = ProductoPedible(
  id: 'p-hijos',
  nombre: 'Nuestros Hijos',
  categoriaDelCatalogo: CategoriaDeProducto.bonificables,
  precioDeCompraCentavos: 133000,
  esBonificable: true,
);
const vidaFeliz = ProductoPedible(
  id: 'p-vida',
  nombre: 'Vida Feliz',
  categoriaDelCatalogo: CategoriaDeProducto.revistas,
  precioDeCompraCentavos: 8500,
  stock: 8,
);
const nuestraSalud = ProductoPedible(
  id: 'p-nsalud',
  nombre: 'Nuestra Salud',
  categoriaDelCatalogo: CategoriaDeProducto.revistas,
  precioDeCompraCentavos: 8500,
  stock: 3,
);
const elCamino = ProductoPedible(
  id: 'p-camino',
  nombre: 'El camino a Cristo',
  categoriaDelCatalogo: CategoriaDeProducto.misioneros,
  precioDeCompraCentavos: 6000,
  stock: 5,
);

const productosDelCanvas = [saludYHogar, nuestrosHijos, vidaFeliz, nuestraSalud, elCamino];

/// 23/11/2026 12:00 en Montevideo.
final ahoraPedidos = DateTime.utc(2026, 11, 23, 15);

/// La situación del canvas 37A·01: debe $ 18.400, tiene $ 9.700 por cobrar y 4 libros por entregar. Con
/// [limitePesos] la campaña tiene límite (37A·02: $ 30.000).
SituacionDelColportor situacionDelCanvas({int? limitePesos, DateTime? bajadoEn}) =>
    SituacionDelColportor(
      deudaActualCentavos: 1840000,
      porCobrarCentavos: 970000,
      librosPorEntregar: 4,
      limiteDeudaCentavos: limitePesos == null ? null : limitePesos * 100,
      deudaLeidaEn: bajadoEn ?? DateTime.utc(2026, 11, 23, 14),
    );

Pedido pedidoDe({
  String id = 'ped-1',
  EstadoDelPedido estado = EstadoDelPedido.porAutorizar,
  List<LineaDelPedido>? lineas,
  DateTime? fecha,
  int montoCentavos = 1184000,
  bool excedeLimite = false,
  int? montoAutorizadoCentavos,
  String? motivoRechazo,
  int? numero,
}) {
  final f = fecha ?? ahoraPedidos;
  return Pedido(
    id: id,
    colportorId: 'col-1',
    estado: estado,
    lineas:
        lineas ??
        [
          LineaDelPedido(id: '$id-l1', productoId: 'p-salud', cantidad: 4),
          LineaDelPedido(id: '$id-l2', productoId: 'p-hijos', cantidad: 2),
          LineaDelPedido(id: '$id-l3', productoId: 'p-vida', cantidad: 20),
        ],
    fecha: f,
    montoCentavos: montoCentavos,
    excedeLimite: excedeLimite,
    montoAutorizadoCentavos: montoAutorizadoCentavos,
    motivoRechazo: motivoRechazo,
    numero: numero,
    auditoria: Auditoria(createdAt: f, updatedAt: f, createdBy: 'col-1'),
  );
}

/// Un repositorio de pedidos que el test maneja: guarda lo que se envía, puede fallar o quedarse esperando.
final class PedidosFalsos implements PedidoRepository {
  PedidosFalsos([List<Pedido> iniciales = const []]) {
    pedidos.addAll(iniciales);
  }

  final pedidos = <Pedido>[];
  final enviados = <Pedido>[];
  final cancelados = <String>[];
  final _cambios = StreamController<void>.broadcast();

  /// Las próximas respuestas de [enviar] son estas fallas, de a una.
  final fallasAlEnviar = <Failure>[];

  /// Las próximas respuestas de [cancelar] son estas fallas, de a una.
  final fallasAlCancelar = <Failure>[];

  /// Si no es `null`, [enviar] espera a que se complete.
  Completer<void>? esperaAlEnviar;

  /// Si no es `null`, [cancelar] espera a que se complete.
  Completer<void>? esperaAlCancelar;

  /// Si no es `null`, [observar] espera a que se complete antes de emitir (la carga de 37B·05).
  Completer<void>? esperaLectura;

  /// Si es `true`, [observar] falla.
  bool fallaAlLeer = false;

  var llamadasAEnviar = 0;
  var llamadasACancelar = 0;
  var lecturas = 0;

  void cambiar() => _cambios.add(null);

  @override
  Future<Either<Failure, PedidoEnviado>> enviar(Pedido pedido) async {
    llamadasAEnviar++;
    enviados.add(pedido);
    await esperaAlEnviar?.future;
    if (fallasAlEnviar.isNotEmpty) return Left(fallasAlEnviar.removeAt(0));
    final ya = pedidos.any((p) => p.id == pedido.id);
    if (!ya) pedidos.insert(0, pedido);
    cambiar();
    return Right(PedidoEnviado(pedido: pedido, yaEstaba: ya));
  }

  @override
  Future<Either<Failure, Pedido>> cancelar({
    required String id,
    required String colportorId,
    required DateTime ahora,
  }) async {
    llamadasACancelar++;
    cancelados.add(id);
    await esperaAlCancelar?.future;
    if (fallasAlCancelar.isNotEmpty) return Left(fallasAlCancelar.removeAt(0));
    final i = pedidos.indexWhere((p) => p.id == id);
    if (i < 0) return const Left(FailurePedidoNoCancelable());
    final actual = pedidos[i];
    final cancelado = Pedido(
      id: actual.id,
      colportorId: actual.colportorId,
      estado: EstadoDelPedido.cancelado,
      lineas: actual.lineas,
      fecha: actual.fecha,
      montoCentavos: actual.montoCentavos,
      excedeLimite: actual.excedeLimite,
      auditoria: actual.auditoria,
    );
    pedidos[i] = cancelado;
    cambiar();
    return Right(cancelado);
  }

  @override
  Stream<List<Pedido>> observar(String colportorId) async* {
    lecturas++;
    await esperaLectura?.future;
    if (fallaAlLeer) throw const FailurePedidosNoDisponibles();
    yield List.of(pedidos);
    await for (final _ in _cambios.stream) {
      yield List.of(pedidos);
    }
  }
}

/// De dónde salen los productos y el contexto en los tests de pantalla.
final class ArmadoFalso implements ArmadoDelPedidoRepository {
  ArmadoFalso({
    this.productos = productosDelCanvas,
    this.contexto = const ContextoLocalDelPedido(librosPorEntregar: 4),
    this.fallaProductos = false,
    this.nombres = const {
      'p-salud': 'Salud y Hogar',
      'p-hijos': 'Nuestros Hijos',
      'p-vida': 'Vida Feliz',
    },
  });

  List<ProductoPedible> productos;
  ContextoLocalDelPedido contexto;
  bool fallaProductos;
  Map<String, String> nombres;

  @override
  Stream<List<ProductoPedible>> observarProductos(String colportorId) {
    if (fallaProductos) return Stream.error(const FailurePedidosNoDisponibles());
    return Stream.value(productos);
  }

  @override
  Stream<Map<String, String>> observarNombres() => Stream.value(nombres);

  @override
  Stream<ContextoLocalDelPedido> observarContexto(String colportorId, DateTime hoy) =>
      Stream.value(contexto);
}
