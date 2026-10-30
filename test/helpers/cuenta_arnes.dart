// Arnés de Mi Cuenta (HU-CTA-001, #170): un repositorio controlable por el test y el montaje de la
// pestaña con el tema real, a un tamaño y a una escala de texto dados.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/detalle_de_mi_plata.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/resumen_de_cuenta.dart';
import 'package:colportores_mobile/features/cuenta/domain/repositories/detalle_de_mi_plata_repository.dart';
import 'package:colportores_mobile/features/cuenta/domain/repositories/resumen_de_cuenta_repository.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/cuenta_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/mi_plata_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/cuenta/presentation/widgets/piezas_mi_plata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Una cifra con lo que hay y lo que cambió.
CifraDeCuenta cifra(int pesos, {int? variacion}) => CifraDeCuenta(
  totalCentavos: pesos * 100,
  variacionCentavos: variacion == null ? null : variacion * 100,
);

/// El resumen del canvas 33A·01: $ 2.400 en mano (+$ 1.800) y $ 9.700 por cobrar (−$ 1.300).
final resumenDelCanvas = ResumenDeCuenta(
  enMano: cifra(2400, variacion: 1800),
  porCobrar: cifra(9700, variacion: -1300),
);

/// La cuenta nueva (33A·04): ceros y nada de la semana anterior.
final resumenCuentaNueva = ResumenDeCuenta(enMano: cifra(0), porCobrar: cifra(0));

/// Un repositorio que el test maneja: cada suscripción abre un `Stream` nuevo y el test decide qué
/// emite y cuándo (o si falla).
final class RepositorioDeCuentaControlable implements ResumenDeCuentaRepository {
  RepositorioDeCuentaControlable({this.inicial});

  /// Lo que emite cada suscripción apenas se abre; `null` = queda cargando hasta que el test emita.
  ResumenDeCuenta? inicial;

  /// Si es `true`, la próxima suscripción falla en vez de emitir [inicial].
  bool fallaAlSuscribir = false;

  /// Cuántas veces se suscribieron (un «Reintentar» o volver a la pestaña suman una).
  var suscripciones = 0;

  final _abiertos = <StreamController<ResumenDeCuenta>>[];

  StreamController<ResumenDeCuenta> get ultimo => _abiertos.last;

  @override
  Stream<ResumenDeCuenta> observar(String colportorId) {
    suscripciones++;
    final controlador = StreamController<ResumenDeCuenta>();
    _abiertos.add(controlador);
    if (fallaAlSuscribir) {
      controlador.addError(const FailureCuentaNoDisponible());
    } else if (inicial != null) {
      controlador.add(inicial!);
    }
    return controlador.stream;
  }

  void emitir(ResumenDeCuenta resumen) => ultimo.add(resumen);

  void fallar() => ultimo.addError(const FailureCuentaNoDisponible());
}

/// Monta [CuentaPage] sola, dentro de un `Scaffold`, a [tamano] y con el texto a [escala].
Future<void> montarCuenta(
  WidgetTester tester,
  RepositorioDeCuentaControlable repo, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  bool activa = true,
  Key? boundary,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _arbol(repo, tamano: tamano, escala: escala, activa: activa, boundary: boundary),
  );
  await tester.pump();
}

Widget _arbol(
  RepositorioDeCuentaControlable repo, {
  required Size tamano,
  required double escala,
  required bool activa,
  Key? boundary,
}) => ProviderScope(
  overrides: [resumenDeCuentaRepositoryProvider.overrideWithValue(repo)],
  child: RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      theme: temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: Scaffold(
        body: CuentaPage(colportorId: 'col-1', activa: activa),
      ),
    ),
  ),
);

/// Vuelve a pintar la misma pantalla con [activa] cambiado: lo que hace la pantalla principal al
/// cambiar de pestaña.
Future<void> cambiarActiva(
  WidgetTester tester,
  RepositorioDeCuentaControlable repo, {
  required bool activa,
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  await tester.pumpWidget(_arbol(repo, tamano: tamano, escala: escala, activa: activa));
  await tester.pumpAndSettle();
}

// ---- Mi plata (HU-CTA-003, #172) ---------------------------------------------------------------

/// Un día de octubre a mediodía en la hora del teléfono (así «20/10» no cambia según la zona).
DateTime dia(int d) => DateTime(2026, 10, d, 12);

/// El detalle del canvas 33C·01 y 33C·02: $ 2.400 en mano en tres cobros y $ 9.700 por cobrar entre
/// tres clientes.
final detalleDelCanvas = DetalleDeMiPlata(
  enManoCentavos: 240000,
  enMano: [
    MovimientoEnMano(cliente: 'María Fernández', fecha: dia(20), centavos: 60000),
    MovimientoEnMano(cliente: 'Pedro Gómez', fecha: dia(21), centavos: 120000),
    MovimientoEnMano(cliente: 'Ana Rodríguez', fecha: dia(23), centavos: 60000),
  ],
  porCobrarCentavos: 970000,
  porCobrar: [
    SaldoDeCliente(cliente: 'Raúl Castro', desde: dia(1), centavos: 490000),
    SaldoDeCliente(cliente: 'Laura Méndez', desde: dia(8), centavos: 360000),
    SaldoDeCliente(cliente: 'María Fernández', desde: dia(12), centavos: 120000),
  ],
  deboCentavos: 0,
  deboAClientes: const [],
);

/// Un repositorio de detalle que el test maneja, igual que [RepositorioDeCuentaControlable].
final class RepositorioDeDetalleControlable implements DetalleDeMiPlataRepository {
  RepositorioDeDetalleControlable({this.inicial});

  DetalleDeMiPlata? inicial;
  bool fallaAlSuscribir = false;
  var suscripciones = 0;
  final _abiertos = <StreamController<DetalleDeMiPlata>>[];

  @override
  Stream<DetalleDeMiPlata> observar(String colportorId) {
    suscripciones++;
    final controlador = StreamController<DetalleDeMiPlata>();
    _abiertos.add(controlador);
    if (fallaAlSuscribir) {
      controlador.addError(const FailureCuentaNoDisponible());
    } else if (inicial != null) {
      controlador.add(inicial!);
    }
    return controlador.stream;
  }

  void emitir(DetalleDeMiPlata detalle) => _abiertos.last.add(detalle);

  void fallar() => _abiertos.last.addError(const FailureCuentaNoDisponible());
}

/// Monta Mi Cuenta con su detalle, para tocar una tarjeta y abrir «Mi plata».
Future<void> montarCuentaConDetalle(
  WidgetTester tester,
  RepositorioDeCuentaControlable resumen,
  RepositorioDeDetalleControlable detalle, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        resumenDeCuentaRepositoryProvider.overrideWithValue(resumen),
        detalleDeMiPlataRepositoryProvider.overrideWithValue(detalle),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const Scaffold(body: CuentaPage(colportorId: 'col-1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Monta «Mi plata» sola, con [abierta] desplegada.
Future<void> montarMiPlata(
  WidgetTester tester,
  RepositorioDeDetalleControlable detalle, {
  CategoriaDeMiPlata abierta = CategoriaDeMiPlata.enMano,
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [detalleDeMiPlataRepositoryProvider.overrideWithValue(detalle)],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: MiPlataPage(colportorId: 'col-1', abierta: abierta),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
