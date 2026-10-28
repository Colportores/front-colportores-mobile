// Dobles y semillas de «Entregar ahora» (HU-VEN-002, #430 y #432): la venta de la vista 27 (una
// colección de 2 libros más una revista suelta), el catálogo que le pone nombre y un repositorio en
// memoria que se puede trabar o hacer fallar.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/color_house_status.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_diferida.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/productos_de_la_entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/entrega_repository.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/fuente_de_productos_de_la_entrega.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/entregar_ahora_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'campo_falsos.dart' show auditoriaDe, t0;
import 'venta_falsos.dart';
import 'venta_ui_falsos.dart' show asentar;

/// El catálogo de los tests de entrega: lo que siempre va, dos libros y una revista.
const productosDeEntrega = ProductosDeLaEntrega(
  nombres: {
    'p-camino': 'El camino a Cristo',
    'p-vida-feliz': 'Vida Feliz',
    'p-deseado': 'El Deseado de todas las gentes',
    'p-salud': 'Salud y Hogar',
    'p-hijos': 'Nuestros Hijos',
    'p-nuestra-salud': 'Nuestra Salud',
  },
  baseDeCombos: {
    'k-2': {'p-camino', 'p-vida-feliz', 'p-deseado'},
  },
);

/// Una colección de 2 libros (la base + «Salud y Hogar» + «Nuestros Hijos») por $ 8.900.
VentaGuardada ventaConColeccion({
  String id = 'v-1',
  String talonario = '0042',
  int monto = 890000,
  bool conRevista = false,
}) => VentaGuardada(
  venta: ventaDe(id, talonario: talonario, monto: monto),
  items: [
    itemDe(
      'i-1',
      id,
      productoId: null,
      coleccionId: 'k-2',
      componentes: const [
        ComponenteVendido(productoId: 'p-camino'),
        ComponenteVendido(productoId: 'p-vida-feliz'),
        ComponenteVendido(productoId: 'p-deseado'),
        ComponenteVendido(productoId: 'p-salud'),
        ComponenteVendido(productoId: 'p-hijos'),
      ],
      cantidad: 1,
      precio: monto,
    ),
    if (conRevista) itemDe('i-2', id, productoId: 'p-nuestra-salud', cantidad: 2, precio: 12000),
  ],
);

/// Un producto suelto: [cantidad] ejemplares de «Nuestra Salud».
VentaGuardada ventaDeUnaRevista({int cantidad = 2, int monto = 0}) => VentaGuardada(
  venta: ventaDe('v-1', talonario: '0042', monto: monto),
  items: [itemDe('i-1', 'v-1', productoId: 'p-nuestra-salud', cantidad: cantidad, precio: 0)],
);

Entrega entregaDe(
  String id,
  String productoId, {
  int cantidad = 1,
  bool pendiente = false,
  String ventaId = 'v-1',
  DateTime? fechaPrevista,
}) => Entrega(
  id: id,
  ventaId: ventaId,
  productoId: productoId,
  cantidad: cantidad,
  pendiente: pendiente,
  fechaPrevista: fechaPrevista,
  fechaEntrega: pendiente ? null : t0,
  auditoria: auditoriaDe(),
);

/// [EntregaRepository] en memoria: guarda lo que le llega, o responde con [falla].
class EntregasEnMemoria implements EntregaRepository {
  /// Lo que hay guardado, por venta.
  final guardadas = <String, List<Entrega>>{};

  /// Cada llamada a [entregarAhora], en orden.
  final recibidas = <({String ventaId, List<Entrega> filas})>[];

  /// Las próximas veces que [entregarAhora] falla (una por una).
  final fallas = <Failure>[];

  /// Las próximas veces que [deLaVenta] falla.
  var fallasDeLectura = 0;

  /// Si no es `null`, [entregarAhora] se queda esperando.
  Completer<void>? compuerta;

  /// El color con que responde [entregarAhora].
  ColorHouseStatus? colorDeLaCasa = ColorHouseStatus.cobranzaPendiente;

  var lecturas = 0;

  // --- Entrega diferida (HU-VEN-003, #433) ---

  /// Cada llamada a [diferir], en orden.
  final diferidas =
      <({String ventaId, DateTime fechaPrevista, List<Entrega> filasNuevas, String idDeLaCita})>[];

  /// Cada llamada a [cumplir], en orden.
  final cumplidas =
      <({String ventaId, Set<String>? entregaIds, DateTime? nuevaFecha, String idDeLaCita})>[];

  /// Lo que responde [diferir] / [cumplir]; sin esto responden con una falla.
  EntregaDiferida? respuestaDeDiferir;
  EntregaCumplida? respuestaDeCumplir;

  /// Las próximas veces que [diferir] / [cumplir] fallan (una por una).
  final fallasAlDiferir = <Failure>[];
  final fallasAlCumplir = <Failure>[];

  /// Si no es `null`, [diferir] y [cumplir] se quedan esperando.
  Completer<void>? compuertaDeDiferida;

  @override
  Future<Either<Failure, EntregaDiferida>> diferir(
    String ventaId, {
    required DateTime fechaPrevista,
    required DateTime ahora,
    required List<Entrega> filasNuevas,
    required String idDeLaCita,
  }) async {
    diferidas.add((
      ventaId: ventaId,
      fechaPrevista: fechaPrevista,
      filasNuevas: filasNuevas,
      idDeLaCita: idDeLaCita,
    ));
    final espera = compuertaDeDiferida;
    if (espera != null) await espera.future;
    if (fallasAlDiferir.isNotEmpty) return Left(fallasAlDiferir.removeAt(0));
    final r = respuestaDeDiferir;
    return r == null ? const Left(FailureEntregaNoGuardada()) : Right(r);
  }

  @override
  Future<Either<Failure, EntregaCumplida>> cumplir(
    String ventaId, {
    required DateTime ahora,
    required String idDeLaCita,
    Set<String>? entregaIds,
    DateTime? nuevaFecha,
  }) async {
    cumplidas.add((
      ventaId: ventaId,
      entregaIds: entregaIds,
      nuevaFecha: nuevaFecha,
      idDeLaCita: idDeLaCita,
    ));
    final espera = compuertaDeDiferida;
    if (espera != null) await espera.future;
    if (fallasAlCumplir.isNotEmpty) return Left(fallasAlCumplir.removeAt(0));
    final r = respuestaDeCumplir;
    return r == null ? const Left(FailureEntregaNoGuardada()) : Right(r);
  }

  final _pendientes = StreamController<List<EntregaPendiente>>.broadcast();

  /// Lo último que se emitió: quien empieza a mirar lo recibe enseguida. `null`: todavía no hubo nada
  /// y la lista queda «cargando».
  List<EntregaPendiente>? pendientesActuales;

  /// Si no es `null`, quien empieza a mirar las entregas pendientes recibe este error.
  Object? errorDePendientes;

  /// Emite [lista] a quien esté mirando las entregas pendientes (y a quien empiece después).
  void emitirPendientes(List<EntregaPendiente> lista) {
    pendientesActuales = lista;
    _pendientes.add(lista);
  }

  @override
  Stream<List<EntregaPendiente>> observarPendientes({String? espacioPersonaId}) async* {
    final error = errorDePendientes;
    if (error != null) throw error;
    final actual = pendientesActuales;
    if (actual != null) yield actual;
    yield* _pendientes.stream;
  }

  @override
  Future<Either<Failure, EntregaRegistrada>> entregarAhora(
    String ventaId,
    List<Entrega> filas,
  ) async {
    recibidas.add((ventaId: ventaId, filas: filas));
    final espera = compuerta;
    if (espera != null) await espera.future;
    if (fallas.isNotEmpty) return Left(fallas.removeAt(0));
    final existentes = guardadas[ventaId];
    if (existentes != null && existentes.isNotEmpty) {
      return Right(
        EntregaRegistrada(entregas: existentes, colorDeLaCasa: colorDeLaCasa, yaEstaba: true),
      );
    }
    guardadas[ventaId] = filas;
    return Right(EntregaRegistrada(entregas: filas, colorDeLaCasa: colorDeLaCasa));
  }

  @override
  Future<Either<Failure, List<Entrega>>> deLaVenta(String ventaId) async {
    lecturas++;
    if (fallasDeLectura > 0) {
      fallasDeLectura--;
      return const Left(FailureEntregaNoDisponible());
    }
    return Right(guardadas[ventaId] ?? const []);
  }
}

class FuenteDeProductosFalsa implements FuenteDeProductosDeLaEntrega {
  FuenteDeProductosFalsa([this.productos = productosDeEntrega]);

  ProductosDeLaEntrega productos;
  var fallas = 0;
  var lecturas = 0;
  Completer<void>? bloqueo;

  @override
  Future<Either<Failure, ProductosDeLaEntrega>> leer({
    required Set<String> productoIds,
    required Set<String> comboIds,
  }) async {
    lecturas++;
    final espera = bloqueo;
    if (espera != null) await espera.future;
    if (fallas > 0) {
      fallas--;
      return const Left(FailureEntregaNoDisponible());
    }
    return Right(productos);
  }
}

/// Todo lo que el test controla de «Entregar ahora».
final class EntornoDeEntrega {
  EntornoDeEntrega({EntregasEnMemoria? entregas, FuenteDeProductosFalsa? fuente})
    : entregas = entregas ?? EntregasEnMemoria(),
      fuente = fuente ?? FuenteDeProductosFalsa();

  final EntregasEnMemoria entregas;
  final FuenteDeProductosFalsa fuente;
  DateTime ahora = DateTime.utc(2026, 10, 28, 13);
  var _ids = 0;

  List<Override> get overrides => [
    entregaRepositoryProvider.overrideWithValue(entregas),
    fuenteDeProductosDeLaEntregaProvider.overrideWithValue(fuente),
    relojVentaProvider.overrideWithValue(() => ahora),
    generadorIdVentaProvider.overrideWithValue(() => 'e-${++_ids}'),
  ];
}

/// Cómo se cerró la pantalla, para los tests.
final class SalidaDeEntrega {
  EntregaRegistrada? registrada;
  var cerrada = false;
  final cobrar = <EntregaRegistrada>[];
  final agendar = <EntregaRegistrada>[];
}

/// Monta «Entregar ahora» sobre una pantalla desde la que se abre (así se prueba volver y reentrar).
Future<SalidaDeEntrega> montarEntrega(
  WidgetTester tester,
  EntornoDeEntrega e,
  VentaGuardada guardada, {
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool conCobro = false,
  bool conAgendar = false,
  bool abrir = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final salida = SalidaDeEntrega();
  await tester.pumpWidget(
    ProviderScope(
      overrides: e.overrides,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir_entrega'),
                onPressed: () async {
                  final r = await Navigator.of(context).push(
                    EntregarAhoraPage.ruta(
                      guardada: guardada,
                      nombreDelCliente: 'María Fernández',
                      alCobrar: conCobro ? salida.cobrar.add : null,
                      alAgendarCobranza: conAgendar ? salida.agendar.add : null,
                    ),
                  );
                  salida.registrada = r;
                  salida.cerrada = true;
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) {
    await tester.tap(find.byKey(const Key('abrir_entrega')));
    await asentar(tester);
  }
  return salida;
}
