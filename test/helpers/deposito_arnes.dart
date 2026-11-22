// Arnés de «Registrar depósito» (vista 33 D, HU-CTA-004, #443): repositorios de depósitos y tickets
// que el test maneja, una cámara guionada y el montaje de la pantalla con el tema real.
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/domain/transaccion_local.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/totales_de_depositos.dart';
import 'package:colportores_mobile/features/depositos/domain/repositories/deposito_repository.dart';
import 'package:colportores_mobile/features/depositos/presentation/pages/registrar_deposito_page.dart';
import 'package:colportores_mobile/features/depositos/presentation/providers/depositos_providers.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:colportores_mobile/features/tickets/domain/services/captura_de_foto.dart';
import 'package:colportores_mobile/features/tickets/presentation/providers/tickets_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'cuenta_arnes.dart';
import 'tickets_falsos.dart';

/// 10/11/2026 12:00 en Montevideo.
final ahoraDeposito = DateTime.utc(2026, 11, 10, 15);

/// Los depósitos guardados; el test decide si falla o si se queda «registrando».
final class DepositosFalsos implements DepositoRepository {
  DepositosFalsos({this.porValidarCentavos = 50000});

  final int porValidarCentavos;
  final guardados = <Deposito>[];

  /// La próxima respuesta es esta falla (una sola vez).
  Failure? fallarUnaVezCon;

  /// Si no es `null`, [registrar] espera a que se complete.
  Completer<void>? espera;

  @override
  Future<Either<Failure, DepositoRegistrado>> registrar(Deposito deposito) async {
    guardados.add(deposito);
    await espera?.future;
    final falla = fallarUnaVezCon;
    if (falla != null) {
      fallarUnaVezCon = null;
      return Left(falla);
    }
    return Right(DepositoRegistrado(deposito: deposito));
  }

  @override
  Future<Either<Failure, List<Deposito>>> todos() async => Right(guardados);

  @override
  Stream<List<Deposito>> observar() => Stream.value(guardados);

  @override
  Future<Either<Failure, TotalesDeDepositos>> totales() async =>
      Right(TotalesDeDepositos(validadoCentavos: 0, porValidarCentavos: porValidarCentavos));
}

/// Los tickets guardados con su foto.
final class TicketsFalsos implements TicketRepository {
  final guardados = <({Ticket ticket, Uint8List foto})>[];

  @override
  Future<Either<Failure, TicketRegistrado>> registrar(
    Ticket ticket, {
    required Uint8List foto,
    required TipoDeImagen tipoDeImagen,
    String? cobroId,
  }) async {
    guardados.add((ticket: ticket, foto: foto));
    return Right(
      TicketRegistrado(
        ticket: ticket,
        foto: fotoLocalDePrueba(ticket.id, bytes: foto.length),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// La transacción sin base: corre el cuerpo tal cual.
final class TransaccionDirecta implements TransaccionLocal {
  @override
  Future<T> correr<T>(Future<T> Function() cuerpo) => cuerpo();
}

/// Cámara y galería guionadas: devuelven [resultados] en orden (el último se repite).
final class CapturadorGuionado implements CapturadorDeFoto {
  CapturadorGuionado([List<ResultadoDeCaptura>? resultados])
    : resultados = resultados ?? [FotoCapturada(fotoDePrueba(4000))];

  final List<ResultadoDeCaptura> resultados;
  final pedidos = <String>[];

  ResultadoDeCaptura _siguiente(String origen) {
    pedidos.add(origen);
    final i = pedidos.length - 1;
    return resultados[i < resultados.length ? i : resultados.length - 1];
  }

  @override
  Future<ResultadoDeCaptura> sacarFoto() async => _siguiente('camara');

  @override
  Future<ResultadoDeCaptura> elegirDeLaGaleria() async => _siguiente('galeria');

  @override
  Future<void> abrirLosAjustes() async {}
}

/// Todo lo que el test toca de la pantalla.
final class ArnesDeDeposito {
  ArnesDeDeposito({
    DepositosFalsos? depositos,
    CapturadorDeFoto? capturador,
    this.sinCamara = false,
    this.campania = 'camp-1',
    this.conexion = TipoConexion.wifi,
    this.legible = true,
    RepositorioDeCuentaControlable? cuenta,
    this.extras = const [],
  }) : depositos = depositos ?? DepositosFalsos(),
       capturador = capturador ?? CapturadorGuionado(),
       cuenta = cuenta ?? RepositorioDeCuentaControlable(inicial: resumenDelCanvas);

  final DepositosFalsos depositos;
  final tickets = TicketsFalsos();
  final CapturadorDeFoto capturador;
  final bool sinCamara;

  /// La campaña en curso para el alquiler; `null` = no está en ninguna.
  final String? campania;
  final TipoConexion conexion;

  /// El compresor puede leer la foto.
  final bool legible;
  final RepositorioDeCuentaControlable cuenta;

  /// Overrides de más que suma un test (los tickets sin subir de 38A-08, por ejemplo).
  final List<Override> extras;

  var _depositoIds = 0;
  var _ticketIds = 0;

  List<Override> get overrides => [
    resumenDeCuentaRepositoryProvider.overrideWithValue(cuenta),
    ...overridesSinCuenta,
  ];

  /// Lo mismo sin el resumen de la cuenta, para montarlo junto a Mi Cuenta (que trae el suyo).
  List<Override> get overridesSinCuenta => [
    depositoRepositoryProvider.overrideWithValue(depositos),
    ticketRepositoryProvider.overrideWithValue(tickets),
    transaccionDeDepositoProvider.overrideWithValue(TransaccionDirecta()),
    almacenDeFotosDeTicketProvider.overrideWithValue(AlmacenDeFotosEnMemoria()),
    relojDepositoProvider.overrideWithValue(() => ahoraDeposito),
    relojTicketProvider.overrideWithValue(() => ahoraDeposito),
    generadorIdDepositoProvider.overrideWithValue(() => 'd-${++_depositoIds}'),
    generadorIdTicketProvider.overrideWithValue(() => 't-${++_ticketIds}'),
    capturadorDeFotoProvider.overrideWithValue(sinCamara ? null : capturador),
    compresorDeImagenProvider.overrideWithValue(CompresorDePrueba([900], legible: legible)),
    campaniaDelAlquilerProvider.overrideWith((ref, _) async => campania),
    conexionProvider.overrideWith((ref) => Stream.value(conexion)),
    ...extras,
  ];
}

/// Monta una pantalla de inicio con un botón que abre «Registrar depósito» y lo abre. Lo que devolvió
/// la pantalla queda en [resultados].
Future<List<bool>> montarDeposito(
  WidgetTester tester,
  ArnesDeDeposito arnes, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  bool abrir = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final resultados = <bool>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: arnes.overrides,
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
                key: const Key('abrir_deposito'),
                onPressed: () async => resultados.add(
                  await RegistrarDepositoPage.abrir(context, colportorId: 'col-1'),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirDeposito(tester);
  return resultados;
}

Future<void> abrirDeposito(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('abrir_deposito')));
  await tester.pumpAndSettle();
}

/// Escribe el monto.
Future<void> escribirMonto(WidgetTester tester, String monto) async {
  await tester.enterText(
    find.descendant(of: find.byKey(const Key('deposito_monto')), matching: find.byType(TextField)),
    monto,
  );
  await tester.pump();
}

/// Desplaza el formulario hasta que [clave] se ve (la lista se arma de a poco: con la pantalla chica
/// o el texto grande, lo de abajo todavía no existe).
Future<void> verEnElFormulario(WidgetTester tester, Key clave) async {
  await tester.scrollUntilVisible(
    find.byKey(clave),
    150,
    scrollable: find
        .descendant(of: find.byKey(const Key('deposito_lista')), matching: find.byType(Scrollable))
        .first,
  );
  await tester.pump();
}

/// Toca la foto y elige la cámara en la hoja.
Future<void> sacarLaFoto(WidgetTester tester) async {
  await verEnElFormulario(tester, const Key('deposito_foto'));
  await tester.tap(find.byKey(const Key('deposito_foto')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('deposito_foto_camara')));
  await tester.pumpAndSettle();
}

/// Toca el botón «Registrar depósito» (o «Reintentar»).
Future<void> tocarRegistrar(WidgetTester tester, {bool esperar = true}) async {
  await tester.tap(find.byKey(const Key('venta_cta')));
  if (esperar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// El botón del pie, para mirar si está habilitado.
FilledButton botonRegistrar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('venta_cta')));
