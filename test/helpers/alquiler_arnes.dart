// Arnés de «Mi alquiler» (HU-CTA-007, vista 38C, #389): un repositorio que el test maneja, los datos
// del canvas y el montaje de la pantalla con el tema real, a un tamaño y a una escala de texto dados.
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/alquiler.dart';
import 'package:colportores_mobile/features/cuenta/domain/repositories/alquiler_repository.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/alquiler_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'deposito_arnes.dart';

/// «Ahora» de los tests: el 22/11 a las 10:00 (hora del teléfono).
final ahoraDelAlquiler = DateTime(2026, 11, 22, 10);

/// Un día a mediodía en la hora del teléfono (así «15/10» no cambia según la zona).
DateTime diaDeAlquiler(int mes, int d) => DateTime(2026, mes, d, 12);

/// Un pago de alquiler; el monto va en pesos.
PagoDeAlquiler pagoDe(
  int pesos, {
  DateTime? fecha,
  DestinoDeDeposito destino = DestinoDeDeposito.retiroCoordinador,
  EstadoDePagoDeAlquiler estado = EstadoDePagoDeAlquiler.validado,
  String? motivo,
}) => PagoDeAlquiler(
  montoCentavos: pesos * 100,
  fecha: fecha ?? diaDeAlquiler(10, 15),
  destino: destino,
  estado: estado,
  motivoDelRechazo: motivo,
);

/// El alquiler de una campaña; los montos van en pesos y los pagos, del más nuevo al más viejo.
AlquilerDeCampania campaniaCon({
  String id = 'c-1',
  String nombre = 'Primavera 2026',
  int monto = 18500,
  List<PagoDeAlquiler> pagos = const [],
}) =>
    AlquilerDeCampania(campaniaId: id, campania: nombre, montoCentavos: monto * 100, pagos: pagos);

/// El alquiler del colportor con las campañas dadas (y las de baja, #740). [trasladado] (en pesos) es lo que el
/// servidor dice que pasó a la deuda con la casa editora (`cuenta_colportor.alquiler_trasladado`, #753): el
/// teléfono no lo deduce de los pagos.
AlquilerDelColportor alquilerCon(
  List<AlquilerDeCampania> campanias, {
  DateTime? bajadoEn,
  int trasladado = 0,
  List<AlquilerDeBaja> bajas = const [],
}) => AlquilerDelColportor(
  campanias: campanias,
  bajas: bajas,
  bajadoEn: bajadoEn,
  trasladadoCentavos: trasladado * 100,
);

/// Una decisión del coordinador sobre lo pagado de una baja; el monto va en pesos.
DecisionDeAlquiler decisionDe(DestinoDeLoPagado destino, int pesos, {DateTime? en}) =>
    DecisionDeAlquiler(
      destino: destino,
      montoCentavos: pesos * 100,
      decididaEn: en ?? diaDeAlquiler(11, 12),
    );

/// La campaña de una baja (#740): sus pagos y las decisiones vigentes del coordinador, la más nueva
/// primero.
AlquilerDeBaja bajaCon({
  String id = 'b-1',
  String nombre = 'Otoño 2026',
  List<PagoDeAlquiler> pagos = const [],
  List<DecisionDeAlquiler> decisiones = const [],
}) => AlquilerDeBaja(campaniaId: id, campania: nombre, pagos: pagos, decisiones: decisiones);

/// Ana se dio de baja de Otoño después de pagar \$ 5.000 y su coordinador todavía no decidió.
final alquilerDeBajaPorDecidir = alquilerCon(
  const [],
  bajas: [
    bajaCon(pagos: [pagoDe(5000)]),
  ],
);

/// 38C·01: $ 18.500 de alquiler, $ 6.000 pagados (un retiro validado el 15/10): faltan $ 12.500.
final alquilerDelCanvas = alquilerCon([
  campaniaCon(pagos: [pagoDe(6000)]),
]);

/// 38C·02: lo mismo, con otros $ 6.000 por validar.
final alquilerConPorValidar = alquilerCon([
  campaniaCon(
    pagos: [
      pagoDe(6000, fecha: diaDeAlquiler(11, 20), estado: EstadoDePagoDeAlquiler.porValidar),
      pagoDe(6000),
    ],
  ),
]);

/// 38C·03: pagado entero.
final alquilerPagado = alquilerCon([
  campaniaCon(pagos: [pagoDe(18500)]),
]);

/// Un repositorio que el test maneja: cada suscripción abre un `Stream` nuevo y el test decide qué
/// emite y cuándo (o si falla).
final class RepositorioDeAlquilerControlable implements AlquilerRepository {
  RepositorioDeAlquilerControlable({this.inicial});

  /// Lo que emite cada suscripción apenas se abre; `null` = queda cargando hasta que el test emita.
  AlquilerDelColportor? inicial;

  /// Si es `true`, la próxima suscripción falla en vez de emitir [inicial].
  bool fallaAlSuscribir = false;

  /// Cuántas veces se suscribieron (un «Reintentar» suma una).
  var suscripciones = 0;

  final _abiertos = <StreamController<AlquilerDelColportor>>[];

  StreamController<AlquilerDelColportor> get ultimo => _abiertos.last;

  @override
  Stream<AlquilerDelColportor> observar(String colportorId) {
    suscripciones++;
    final controlador = StreamController<AlquilerDelColportor>();
    _abiertos.add(controlador);
    if (fallaAlSuscribir) {
      controlador.addError(const FailureAlquilerNoDisponible());
    } else if (inicial != null) {
      controlador.add(inicial!);
    }
    return controlador.stream;
  }

  void emitir(AlquilerDelColportor alquiler) => ultimo.add(alquiler);

  void fallar() => ultimo.addError(const FailureAlquilerNoDisponible());
}

/// Los overrides de «Mi alquiler»: el repositorio, el reloj y la conexión.
List<Override> overridesDeAlquiler(
  RepositorioDeAlquilerControlable repo, {
  TipoConexion conexion = TipoConexion.wifi,
}) => [
  alquilerRepositoryProvider.overrideWithValue(repo),
  relojCuentaProvider.overrideWithValue(() => ahoraDelAlquiler),
  conexionProvider.overrideWith((ref) => Stream.value(conexion)),
];

/// Monta [AlquilerPage] sola, a [tamano] y con el texto a [escala]. [otros] suma overrides (los últimos
/// no pueden repetir un proveedor ya pisado acá).
Future<void> montarAlquiler(
  WidgetTester tester,
  RepositorioDeAlquilerControlable repo, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  TipoConexion conexion = TipoConexion.wifi,
  List<Override> otros = const [],
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesDeAlquiler(repo, conexion: conexion),
        ...otros,
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const AlquilerPage(colportorId: 'col-1'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Monta una pantalla de inicio con un botón que abre «Mi alquiler» (como Mi Cuenta) y la abre. Con
/// [deposito], «Cargar pago de alquiler» abre de verdad «Registrar depósito» con esos falsos (que traen
/// su propia conexión y su propio reloj de la cuenta).
Future<void> montarAlquilerDesdeUnBoton(
  WidgetTester tester,
  RepositorioDeAlquilerControlable repo, {
  ArnesDeDeposito? deposito,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: deposito == null
          ? overridesDeAlquiler(repo)
          : [
              alquilerRepositoryProvider.overrideWithValue(repo),
              relojCuentaProvider.overrideWithValue(() => ahoraDelAlquiler),
              ...deposito.overrides,
            ],
      child: MaterialApp(
        theme: temaClaro(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir_alquiler'),
                onPressed: () => AlquilerPage.abrir(context, colportorId: 'col-1'),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir_alquiler')));
  await tester.pumpAndSettle();
}
