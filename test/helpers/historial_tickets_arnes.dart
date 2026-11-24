// Arnés de «Mis tickets» (vista 38B, HU-COB-009, #388): un historial que el test maneja, un visor de
// fotos guionado y el montaje de la lista con el tema real, a un tamaño y a una escala dados. El
// formulario de «Cargar ticket» y el de «Cargar de nuevo» salen del arnés de «Registrar depósito».
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/repositories/historial_de_tickets_repository.dart';
import 'package:colportores_mobile/features/tickets/domain/services/visor_de_fotos.dart';
import 'package:colportores_mobile/features/tickets/presentation/pages/historial_de_tickets_page.dart';
import 'package:colportores_mobile/features/tickets/presentation/providers/tickets_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'deposito_arnes.dart';

/// 10/11/2026 12:00 en Montevideo (el «ahora» de [ahoraDeposito]).
final hoyDelHistorial = ahoraDeposito;

/// Una fila del historial con los valores del canvas 38B·01 por defecto.
ItemDelHistorial itemDePrueba(
  String id, {
  DateTime? fecha,
  int pesos = 4800,
  LugarDelTicket lugar = LugarDelTicket.banco,
  ConceptoDeDeposito? concepto = ConceptoDeDeposito.casaEditora,
  EstadoDelItem estado = EstadoDelItem.porValidar,
  String? ticketId,
  String? cobroId,
  String? autorizacion = '004512',
  TipoDeTarjeta? tarjeta = TipoDeTarjeta.debito,
  String? motivo,
  DateTime? validadoEn,
  bool fotoSubida = false,
  bool hayCopiaLocal = true,
  bool fotoRechazada = false,
}) => ItemDelHistorial(
  id: id,
  depositoId: lugar == LugarDelTicket.cobroConTarjeta ? null : id,
  ticketId: lugar == LugarDelTicket.retiro ? null : (ticketId ?? 't-$id'),
  // El ticket de un cobro con tarjeta está ligado a su cobro (`cobro-<id>`); pasá `cobroId: ''` para
  // un ticket que ya no lo está.
  cobroId: lugar == LugarDelTicket.cobroConTarjeta
      ? (cobroId == '' ? null : (cobroId ?? 'cobro-$id'))
      : null,
  fecha: fecha ?? hoyDelHistorial,
  montoCentavos: pesos * 100,
  lugar: lugar,
  concepto: concepto,
  estado: estado,
  numeroAutorizacion: autorizacion,
  tarjetaTipo: tarjeta,
  motivoRechazo: motivo,
  validadoEn: validadoEn,
  fotoSubida: fotoSubida,
  hayCopiaLocal: hayCopiaLocal,
  fotoRechazada: fotoRechazada,
);

/// Las cuatro filas del canvas 38B·01: por validar de hoy, rechazado del 20/10, validado del 15/10
/// (retiro, alquiler) y validado del 08/10 (oficina).
List<ItemDelHistorial> filasDelCanvas() => [
  itemDePrueba('d1'),
  itemDePrueba(
    'd2',
    fecha: DateTime.utc(2026, 10, 20, 15),
    pesos: 2000,
    estado: EstadoDelItem.rechazado,
    motivo: 'La foto no se lee',
    autorizacion: '003981',
    tarjeta: null,
  ),
  itemDePrueba(
    'd3',
    fecha: DateTime.utc(2026, 10, 15, 15),
    pesos: 6000,
    lugar: LugarDelTicket.retiro,
    concepto: ConceptoDeDeposito.alquiler,
    estado: EstadoDelItem.validado,
    autorizacion: null,
    tarjeta: null,
    validadoEn: DateTime.utc(2026, 10, 16, 15),
  ),
  itemDePrueba(
    'd4',
    fecha: DateTime.utc(2026, 10, 8, 15),
    pesos: 9500,
    lugar: LugarDelTicket.oficina,
    estado: EstadoDelItem.validado,
    autorizacion: null,
    tarjeta: null,
    validadoEn: DateTime.utc(2026, 10, 9, 15),
  ),
];

/// Un historial que el test maneja: cada suscripción abre un `Stream` nuevo y el test decide qué emite
/// y cuándo (o si falla).
final class HistorialControlable implements HistorialDeTicketsRepository {
  HistorialControlable({this.inicial});

  /// Lo que emite cada suscripción apenas se abre; `null` = queda cargando hasta que el test emita.
  HistorialDeTickets? inicial;

  /// Si es `true`, la próxima suscripción falla en vez de emitir [inicial].
  bool fallaAlSuscribir = false;

  /// Cuántas veces se suscribieron (un «Reintentar» suma una).
  var suscripciones = 0;

  /// Los cobros con tarjeta que el teléfono tiene vivos, por id (lo que lee «Cargar de nuevo»).
  final cobros = <String, Cobranza>{};

  /// Cuántas veces se pidió un cobro.
  var cobrosPedidos = 0;

  /// Si no es `null`, la próxima lectura de un cobro lanza esto.
  Object? fallaAlLeerElCobro;

  final _abiertos = <StreamController<HistorialDeTickets>>[];

  @override
  Stream<HistorialDeTickets> observar() {
    suscripciones++;
    final controlador = StreamController<HistorialDeTickets>();
    _abiertos.add(controlador);
    if (fallaAlSuscribir) {
      controlador.addError(StateError('no se pudo leer'));
    } else if (inicial != null) {
      controlador.add(inicial!);
    }
    return controlador.stream;
  }

  void emitir(HistorialDeTickets historial) => _abiertos.last.add(historial);

  @override
  Future<Cobranza?> cobroConTarjeta(String cobroId) async {
    cobrosPedidos++;
    final falla = fallaAlLeerElCobro;
    if (falla != null) {
      fallaAlLeerElCobro = null;
      throw falla;
    }
    return cobros[cobroId];
  }
}

/// Historial con [items] y la última bajada en [bajadoEn].
HistorialDeTickets historialCon(List<ItemDelHistorial> items, {DateTime? bajadoEn}) =>
    HistorialDeTickets(items: items, bajadoEn: bajadoEn ?? DateTime(2026, 11, 9, 21));

/// El visor de fotos guionado: devuelve lo que diga [respuestas] en orden (la última se repite) y
/// cuenta los pedidos.
final class VisorGuionado implements VisorDeFotosDeTicket {
  VisorGuionado([List<FotoParaVer>? respuestas])
    : respuestas = respuestas ?? [const FotoNoDisponible()];

  final List<FotoParaVer> respuestas;
  final pedidos = <String>[];

  @override
  Future<FotoParaVer> ver(String ticketId) async {
    pedidos.add(ticketId);
    final i = pedidos.length - 1;
    return respuestas[i < respuestas.length ? i : respuestas.length - 1];
  }
}

/// Monta «Mis tickets» (o, con [abrir] en `false`, una pantalla con un botón que la abre) con el arnés
/// del formulario de depósito detrás: «+ Cargar ticket» y «Cargar de nuevo» abren el formulario de
/// verdad.
Future<void> montarHistorial(
  WidgetTester tester,
  HistorialControlable repo, {
  ArnesDeDeposito? arnes,
  VisorDeFotosDeTicket? visor,
  Size tamano = const Size(390, 844),
  double escala = 1,
  bool abrir = true,
  List<Override> extras = const [],
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final a = arnes ?? ArnesDeDeposito();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...a.overrides,
        historialDeTicketsRepositoryProvider.overrideWithValue(repo),
        visorDeFotosDeTicketProvider.overrideWithValue(visor ?? VisorGuionado()),
        ...extras,
      ],
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
                key: const Key('abrir_historial'),
                onPressed: () => HistorialDeTicketsPage.abrir(context, colportorId: 'col-1'),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirHistorial(tester);
}

Future<void> abrirHistorial(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('abrir_historial')));
  await tester.pumpAndSettle();
}

/// Vuelve atrás con el botón de la cabecera.
Future<void> volverAtras(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('venta_atras')));
  await tester.pumpAndSettle();
}

Finder fila(String id) => find.byKey(Key('tickets_fila_$id'));
