// Arnés de la hoja «Agendados» del mapa (vista 06, 06C·03, #407): monta la pestaña «Mapa» con una
// agenda falsa, los planes de cuotas de cada venta, el detalle y «+ Agendar» a mano.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cuota.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_agendados.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';

export '../../helpers/agenda_items_falsos.dart' show ConsultaAgendaFalsa;

/// «Ahora» de los tests: el de la lista de ubicaciones, en hora local.
final ahora407 = ahoraLista.toLocal();

/// El día de hoy (o [dias] después) a la [hora] local.
DateTime dia407(int hora, {int dias = 0, int minuto = 0}) =>
    DateTime(ahora407.year, ahora407.month, ahora407.day + dias, hora, minuto);

/// El punto a [metros] al norte de la Av. Italia (donde está el GPS falso).
Coordenadas alNorte(double metros) =>
    Coordenadas(lat: puntoItalia.lat + metros / 111320, lon: puntoItalia.lon);

/// Una visita agendada en la ubicación [ubicacionId] (calle [calle] [numero]), a [metros] del GPS.
ItemAgenda agendado(
  String id,
  DateTime cuando, {
  TipoAgenda tipo = TipoAgenda.entrevista,
  required String ubicacionId,
  String calle = 'Av. Italia',
  String numero = '1234',
  double metros = 40,
  String? ventaId,
  int? montoPrevisto,
  EstadoAgenda estado = EstadoAgenda.programada,
}) => ItemAgenda(
  agenda: Agenda(
    id: id,
    espacioId: 'esp-$id',
    espacioPersonaId: 'ep-$id',
    tipo: tipo,
    fechaProgramada: cuando.toUtc(),
    estado: estado,
    colportorId: 'col-1',
    ventaId: ventaId,
    montoPrevistoCentavos: montoPrevisto,
    auditoria: Auditoria(
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
      createdBy: 'col-1',
    ),
  ),
  personaNombre: 'Ana',
  personaApellido: 'Martínez',
  casa: DireccionDeAgenda(
    ubicacionId: ubicacionId,
    tipo: TipoUbicacion.casa,
    calle: calle,
    numero: numero,
    coordenadas: alNorte(metros),
  ),
);

/// El canvas 06C·03: una cobranza atrasada de ayer, una cuota hoy a las 15, una entrevista a las
/// 16:30, una entrega con pago a las 18 y una entrevista mañana a las 10.
List<ItemAgenda> agendaDelCanvas() => [
  agendado(
    'atr',
    dia407(18, dias: -1),
    tipo: TipoAgenda.cobranza,
    ubicacionId: 'u-rivera',
    calle: 'Rivera',
    numero: '3920',
    metros: 240,
    ventaId: 'v-rivera',
    montoPrevisto: 98000,
  ),
  agendado(
    'cuota',
    dia407(15),
    tipo: TipoAgenda.cobranza,
    ubicacionId: 'u-italia',
    ventaId: 'v-italia',
    montoPrevisto: 145000,
  ),
  agendado(
    'entrevista',
    dia407(16, minuto: 30),
    ubicacionId: 'u-comercio',
    calle: 'Comercio',
    numero: '2381',
    metros: 90,
  ),
  agendado(
    'entrega',
    dia407(18),
    tipo: TipoAgenda.entrega,
    ubicacionId: 'u-michigan',
    calle: 'Michigan',
    numero: '1588',
    metros: 145,
    ventaId: 'v-michigan',
  ),
  agendado(
    'manana',
    dia407(10, dias: 1),
    ubicacionId: 'u-mataojo',
    calle: 'Mataojo',
    numero: '2044',
    metros: 160,
  ),
];

/// Las casas del mapa: las cinco del canvas y dos sin nada agendado.
List<UbicacionConResumen> casasDelCanvas() => [
  filaLista('u-rivera', calle: 'Rivera', numero: '3920', metrosAlNorte: 240),
  filaLista('u-italia', metrosAlNorte: 40),
  filaLista('u-comercio', calle: 'Comercio', numero: '2381', metrosAlNorte: 90),
  filaLista('u-michigan', calle: 'Michigan', numero: '1588', metrosAlNorte: 145),
  filaLista('u-mataojo', calle: 'Mataojo', numero: '2044', metrosAlNorte: 160),
  filaLista('u-1250', numero: '1250', metrosAlNorte: 300),
  filaLista('u-1236', numero: '1236', metrosAlNorte: 350),
];

PlanDeCuotas planDe(
  String ventaId, {
  int total = 290000,
  int cobrado = 0,
  List<Cuota> cuotas = const [],
}) => PlanDeCuotas(
  venta: VentaConSaldo(
    ventaId: ventaId,
    numeroTalonario: '0012',
    fecha: DateTime.utc(2026, 9, 1),
    montoTotalCentavos: total,
    cobradoCentavos: cobrado,
  ),
  espacioId: 'esp',
  espacioPersonaId: 'ep',
  colportorId: 'col-1',
  cuotas: cuotas,
);

Cuota cuota407(String agendaId, int numero, int monto) => Cuota(
  agendaId: agendaId,
  numero: numero,
  fecha: ahora407,
  montoCentavos: monto,
  estado: EstadoAgenda.programada,
);

/// Los planes del canvas: la atrasada es la 1.ª cuota de su venta ($U 980), la de hoy la 2.ª
/// ($U 1.450) y la venta de la entrega todavía debe.
Map<String, PlanDeCuotas> planesDelCanvas() => {
  'v-rivera': planDe('v-rivera', cuotas: [cuota407('atr', 1, 98000), cuota407('otra-r', 2, 98000)]),
  'v-italia': planDe(
    'v-italia',
    cuotas: [cuota407('primera', 1, 145000), cuota407('cuota', 2, 145000)],
  ),
  'v-michigan': planDe('v-michigan', cobrado: 100000),
};

/// Lo que un test de la hoja «Agendados» necesita después de montar el mapa.
final class MontajeAgendados {
  MontajeAgendados(this.mapa, this.consulta);

  final MontajeMapaUbicaciones mapa;
  final ConsultaAgendaFalsa consulta;

  /// Los `id` de agenda cuyo detalle se abrió.
  final detalles = <String>[];

  /// Si no es `null`, el detalle espera a que se complete.
  Completer<void>? esperaDetalle;

  /// Si no es `null`, abrir el detalle lanza esto.
  Object? fallaDetalle;

  var agendados = 0;

  Future<Object?> abrirDetalle(String id) async {
    detalles.add(id);
    final falla = fallaDetalle;
    if (falla != null) throw falla;
    await esperaDetalle?.future;
    return null;
  }
}

/// Monta el mapa con la agenda [items] y los planes [planes]. Sin [conDetalle] las filas no se tocan;
/// con [conAgendar] el vacío ofrece «+ Agendar».
Future<MontajeAgendados> montarAgendados(
  WidgetTester tester, {
  List<ItemAgenda>? items,
  List<UbicacionConResumen>? casas,
  Map<String, PlanDeCuotas>? planes,
  ConsultaAgendaFalsa? consulta,
  GpsFalso? gps,
  bool conDetalle = true,
  bool conAgendar = false,
  double escala = 1,
  Size tamano = const Size(390, 2000),
}) async {
  final lector = consulta ?? ConsultaAgendaFalsa(items ?? agendaDelCanvas());
  final losPlanes = planes ?? planesDelCanvas();
  late MontajeAgendados montaje;
  final mapa = await montarMapaUbicaciones(
    tester,
    repo: RepoListaFalso(casas ?? casasDelCanvas()),
    gps: gps,
    escala: escala,
    tamano: tamano,
    // La agenda de la hoja «Agendados» (y de «Visitas agendadas» de la hoja de la casa).
    agendas: lector,
    otrosOverrides: <Override>[
      relojAgendaProvider.overrideWithValue(() => ahoraLista),
      if (conDetalle)
        abrirDetalleDeAgendaProvider.overrideWithValue((id) => montaje.abrirDetalle(id)),
      if (conAgendar)
        agendarDesdeLaAgendaProvider.overrideWithValue(() async {
          montaje.agendados++;
          // Abrir «Agendar visita» lleva su tiempo: un segundo toque mientras tanto no abre otra.
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return null;
        }),
      planDeLaVentaProvider.overrideWith(
        (ref, ventaId) => Stream<PlanDeCuotas?>.value(losPlanes[ventaId]),
      ),
    ],
  );
  montaje = MontajeAgendados(mapa, lector);
  return montaje;
}

final pestanaAgendados = find.byKey(ClavesAgendados.pestana);
Finder chip407(TipoAgenda? tipo) => find.byKey(ClavesAgendados.chip(tipo));
Finder fila407(String id) => find.byKey(ClavesAgendados.fila(id));

/// Toca «Agendados» y deja correr la hoja.
Future<void> abrirAgendados(WidgetTester tester) async {
  await tester.tap(pestanaAgendados);
  await asentarLista(tester, 8);
}

/// Lleva la fila [id] a la vista (la lista de la hoja se desplaza) y la toca.
Future<void> tocarFila(WidgetTester tester, String id) async {
  await tester.ensureVisible(fila407(id));
  await tester.pump();
  await tester.tap(fila407(id));
}

/// Desplaza la lista de la hoja hasta que la fila [id] esté construida y a la vista.
Future<void> verFila(WidgetTester tester, String id) => tester.scrollUntilVisible(
  fila407(id),
  120,
  scrollable: find.descendant(
    of: find.byKey(ClavesAgendados.lista),
    matching: find.byType(Scrollable),
  ),
);

/// El texto que se ve dentro de la fila [id].
bool filaDice(String id, String texto) =>
    find.descendant(of: fila407(id), matching: find.text(texto)).evaluate().isNotEmpty;
