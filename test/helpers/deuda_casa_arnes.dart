// Arnés de la deuda con la casa editora (HU-CTA-002, #441): un repositorio que el test maneja, las
// lecturas del canvas 33B y el montaje de la pantalla con el tema real, a un tamaño y a una escala de
// texto dados.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/deuda_con_la_casa.dart';
import 'package:colportores_mobile/features/cuenta/domain/repositories/deuda_con_la_casa_repository.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/deuda_casa_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/deuda_casa_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// «Ahora» de los tests: el 4/11 a las 10:00 (hora del teléfono).
final ahoraDeLaDeuda = DateTime(2026, 11, 4, 10);

/// Un pedido con saldo; los montos van en pesos.
PedidoConSaldo pedido(
  String id,
  DateTime fecha, {
  required int monto,
  required int pagado,
  List<LineaDePedido> lineas = const [],
}) => PedidoConSaldo(
  pedidoId: id,
  fechaPedido: fecha,
  montoCentavos: monto * 100,
  pagadoCentavos: pagado * 100,
  saldoCentavos: (monto - pagado) * 100,
  lineas: lineas,
);

/// La deuda con los montos en pesos.
DeudaConLaCasa deuda({
  required int total,
  int? suma,
  int depositos = 0,
  List<PedidoConSaldo> pedidos = const [],
}) => DeudaConLaCasa(
  deudaTotalCentavos: total * 100,
  sumaDeSaldosCentavos: (suma ?? pedidos.fold<int>(0, (s, p) => s + p.saldoCentavos ~/ 100)) * 100,
  depositosValidadosCentavos: depositos * 100,
  pedidos: pedidos,
);

/// Una lectura de [deuda] que llegó a las [leidaEn].
LecturaDeLaDeuda lectura(DeudaConLaCasa deuda, {DateTime? leidaEn}) =>
    LecturaDeLaDeuda(deuda: deuda, leidaEn: (leidaEn ?? ahoraDeLaDeuda).toUtc());

/// 33B·01: $ 18.400 de deuda en dos pedidos.
final deudaDelCanvas = deuda(
  total: 18400,
  depositos: 23800,
  pedidos: [
    pedido(
      'p-1',
      DateTime.utc(2026, 10, 2, 15),
      monto: 37400,
      pagado: 22000,
      lineas: const [
        LineaDePedido(nombre: 'Salud y Hogar', cantidad: 10),
        LineaDePedido(nombre: 'Nuestros Hijos', cantidad: 6),
      ],
    ),
    pedido(
      'p-2',
      DateTime.utc(2026, 10, 15, 15),
      monto: 4800,
      pagado: 1800,
      lineas: const [LineaDePedido(nombre: 'Vida Feliz', cantidad: 40)],
    ),
  ],
);

/// Un repositorio que el test maneja: cada `leer` queda esperando hasta que el test lo conteste.
final class RepositorioDeDeudaControlable implements DeudaConLaCasaRepository {
  RepositorioDeDeudaControlable({this.guardada});

  /// Lo que tiene guardado el teléfono; `null` = nada.
  LecturaDeLaDeuda? guardada;

  /// Cuántas veces se le preguntó al servidor.
  var lecturas = 0;

  final _pedidos = <Completer<Either<Failure, LecturaDeLaDeuda>>>[];

  /// Cuántos pedidos al servidor siguen sin contestar.
  int get pendientes => _pedidos.where((c) => !c.isCompleted).length;

  @override
  Future<LecturaDeLaDeuda?> ultimaGuardada(String colportorId) async => guardada;

  @override
  Future<Either<Failure, LecturaDeLaDeuda>> leer(String colportorId) {
    lecturas++;
    final c = Completer<Either<Failure, LecturaDeLaDeuda>>();
    _pedidos.add(c);
    return c.future;
  }

  /// El servidor contesta el último pedido; lo guardado pasa a ser eso.
  void responder(LecturaDeLaDeuda l) {
    guardada = l;
    _pedidos.lastWhere((c) => !c.isCompleted).complete(Right(l));
  }

  /// El último pedido falla.
  void fallar([Failure falla = const FailureDeudaNoDisponible()]) =>
      _pedidos.lastWhere((c) => !c.isCompleted).complete(Left(falla));
}

/// Los overrides que dejan a la deuda manejada por [repo] y al reloj en [ahoraDeLaDeuda].
List<Override> overridesDeDeuda(DeudaConLaCasaRepository repo) => [
  deudaConLaCasaRepositoryProvider.overrideWithValue(repo),
  relojCuentaProvider.overrideWithValue(() => ahoraDeLaDeuda),
];

/// Monta [DeudaCasaPage] sola, a [tamano] y con el texto a [escala].
Future<void> montarDeuda(
  WidgetTester tester,
  RepositorioDeDeudaControlable repo, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesDeDeuda(repo),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const DeudaCasaPage(colportorId: 'col-1'),
      ),
    ),
  );
  // El primer cuadro, lo guardado, el pedido al servidor y lo que cambió, pintado.
  await tester.pump();
  await tester.pump();
  await tester.pump();
}
