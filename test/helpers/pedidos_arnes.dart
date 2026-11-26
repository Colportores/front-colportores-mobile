// Arnés de los pedidos a la casa editora (vista 37, HU-STK-009, #387): los repositorios que el test maneja,
// la cuenta y la deuda del canvas, y el montaje de las pantallas con el tema real, a un tamaño y a una
// escala de texto dados.
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/resumen_de_cuenta.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/armado_del_pedido.dart';
import 'package:colportores_mobile/features/pedidos/presentation/pages/detalle_de_pedido_page.dart';
import 'package:colportores_mobile/features/pedidos/presentation/pages/mis_pedidos_page.dart';
import 'package:colportores_mobile/features/pedidos/presentation/pages/pedir_pedido_page.dart';
import 'package:colportores_mobile/features/pedidos/presentation/providers/pedidos_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'cuenta_arnes.dart';
import 'deuda_casa_arnes.dart';
import 'pedidos_falsos.dart';

/// «Ahora» de los tests de pantalla: el 23/11 a las 10:00 (hora del teléfono, así «hoy» y «ayer» no cambian
/// según la zona).
final ahoraLocal = DateTime(2026, 11, 23, 10);

/// Todo lo que maneja el test de una pantalla de pedidos.
final class ArnesDePedidos {
  ArnesDePedidos({
    ArmadoFalso? armado,
    PedidosFalsos? pedidos,
    RepositorioDeCuentaControlable? cuenta,
    RepositorioDeDeudaControlable? deudaRepo,
    int? limitePesos,
    int deudaPesos = 18400,
  }) : armado = armado ?? ArmadoFalso(),
       pedidos = pedidos ?? PedidosFalsos(),
       cuenta =
           cuenta ??
           RepositorioDeCuentaControlable(
             inicial: ResumenDeCuenta(enMano: cifra(2400), porCobrar: cifra(9700)),
           ),
       repoDeDeuda =
           deudaRepo ??
           RepositorioDeDeudaControlable(
             guardada: lectura(deuda(total: deudaPesos), leidaEn: DateTime(2026, 11, 22, 21)),
           ) {
    if (limitePesos != null) {
      this.armado.contexto = ContextoLocalDelPedido(
        librosPorEntregar: this.armado.contexto.librosPorEntregar,
        limiteDeudaCentavos: limitePesos * 100,
      );
    }
  }

  final ArmadoFalso armado;
  final PedidosFalsos pedidos;
  final RepositorioDeCuentaControlable cuenta;
  final RepositorioDeDeudaControlable repoDeDeuda;

  var _n = 0;

  /// Los ids que genera la pantalla: `id-1` (el pedido) y `id-2`, `id-3`… (las líneas), en ese orden.
  String generarId() => 'id-${++_n}';

  /// Los overrides de las pantallas de pedidos. Con [conCuenta] `false` no incluye el de la cuenta: lo pone
  /// `montarCuenta` con su propio repositorio (Riverpod no deja sobrescribir un provider dos veces).
  List<Override> overrides({
    MonitorConectividad? monitor,
    TipoConexion conexion = TipoConexion.wifi,
    bool conCuenta = true,
  }) => [
    pedidoRepositoryProvider.overrideWithValue(pedidos),
    armadoDelPedidoRepositoryProvider.overrideWithValue(armado),
    if (conCuenta) resumenDeCuentaRepositoryProvider.overrideWithValue(cuenta),
    // También deja el reloj de Mi Cuenta en [ahoraDeLaDeuda]; el de los pedidos, en [ahoraLocal].
    ...overridesDeDeuda(repoDeDeuda),
    relojPedidoProvider.overrideWithValue(() => ahoraLocal),
    generadorIdPedidoProvider.overrideWithValue(generarId),
    monitorConectividadProvider.overrideWithValue(monitor ?? ConexionFija(conexion)),
  ];
}

Future<void> _montar(
  WidgetTester tester,
  ArnesDePedidos arnes,
  Widget home, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  TipoConexion conexion = TipoConexion.wifi,
  MonitorConectividad? monitor,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: arnes.overrides(monitor: monitor, conexion: conexion),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  // El primer cuadro, las lecturas de la base y lo que cambió, pintado.
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

/// Monta «Nuevo pedido» (37A) abierto desde una pantalla de abajo, para poder volver atrás.
Future<void> montarPedir(
  WidgetTester tester,
  ArnesDePedidos arnes, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  TipoConexion conexion = TipoConexion.wifi,
  MonitorConectividad? monitor,
}) async {
  await _montar(
    tester,
    arnes,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const Key('abrir_pedir'),
            onPressed: () => PedirPedidoPage.abrir(context, colportorId: 'col-1'),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
    tamano: tamano,
    escala: escala,
    conexion: conexion,
    monitor: monitor,
  );
  await tester.tap(find.byKey(const Key('abrir_pedir')));
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Monta «Mis pedidos» (37B) solo.
Future<void> montarMisPedidos(
  WidgetTester tester,
  ArnesDePedidos arnes, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) => _montar(
  tester,
  arnes,
  const MisPedidosPage(colportorId: 'col-1'),
  tamano: tamano,
  escala: escala,
);

/// Monta el detalle de un pedido (37B·02, 37B·03) solo.
Future<void> montarDetalle(
  WidgetTester tester,
  ArnesDePedidos arnes,
  String pedidoId, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) => _montar(
  tester,
  arnes,
  DetalleDePedidoPage(colportorId: 'col-1', pedidoId: pedidoId),
  tamano: tamano,
  escala: escala,
);

/// Toca [finder] y deja correr los cuadros.
Future<void> tocar(WidgetTester tester, Finder finder, {int cuadros = 3}) async {
  await tester.ensureVisible(finder);
  // El desplazamiento se nota en el render recién en el cuadro siguiente.
  await tester.pump();
  await tester.tap(finder);
  for (var i = 0; i < cuadros; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Toca el «+» de un producto [veces] veces.
Future<void> sumar(WidgetTester tester, String productoId, int veces) async {
  for (var i = 0; i < veces; i++) {
    await tocar(tester, find.byKey(Key('pedido_mas_$productoId')), cuadros: 1);
  }
}
