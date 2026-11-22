// Arnés del QA de «Cancelar una agenda» (vista 23 C, 23C·04 y 23C·05, #455): monta la pestaña
// «Agenda» real con el detalle real detrás de cada fila (como el de la implementación), con las fuentes
// reales del proyecto, los tamaños del QA y un enum con cada estado que una persona puede alcanzar. Las
// capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_cancelar_agenda.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agenda_items_falsos.dart';
import 'agendar_visita_arnes.dart' show casaMataojo, mariaFernandez;
import 'detalle_agenda_arnes.dart';
import 'notificaciones_arnes.dart' show Telefono;
import 'persona_falsos.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408, usarFuentesReales408;

export 'qa_vista23_408_arnes.dart' show conCapturas408, usarFuentesReales408;

const chico455 = Size(360, 640);
const grande455 = Size(412, 915);

const tituloEntrevista455 = '¿Cancelar la entrevista?';
const tituloCobranza455 = '¿Cancelar la cobranza?';
const cuerpoEntrevista455 =
    'Queda como cancelada (la ves con el filtro «Canceladas»), se borra el recordatorio y la casa '
    'vuelve a su estado anterior.';
const cuerpoCobranza455 =
    'Queda como cancelada (la ves con el filtro «Canceladas») y se borra el recordatorio.';
const canceladaOk455 = 'Agenda cancelada.';
const canceladaSinAviso455 =
    'Agenda cancelada. No pudimos borrar el recordatorio: puede sonar igual.';
const errorAlGuardar455 = 'No pudimos guardar el cambio. La agenda sigue como estaba.';
const yaTieneResultado455 = 'Esta visita ya tiene resultado: no se puede modificar ni cancelar.';
const yaNoSePuede455 = 'Esa agenda ya se cumplió o se canceló. Revisá la lista de agendados.';

/// Lo que el montaje deja ver al test.
final class Montaje455 {
  Montaje455({required this.repo, required this.consulta, required this.telefono});

  final AgendaRepositorioDetalle repo;
  final ConsultaAgendaFalsa consulta;
  final Telefono telefono;

  /// Cuántas veces la lista abrió el detalle.
  var aperturas = 0;
  final navegador = GlobalKey<NavigatorState>();
}

/// La fila de la agenda [id] en la lista, como la lee la pestaña.
List<ItemAgenda> filas455(
  TipoAgenda tipo,
  EstadoAgenda estado,
  DateTime ahora, {
  String id = 'ag-1',
  String nombre = 'María',
  String apellido = 'Fernández',
}) => [
  itemAgenda(
    id,
    DateTime(2026, 10, 24, 14, 30),
    tipo: tipo,
    estado: estado,
    nombre: nombre,
    apellido: apellido,
    calle: 'Mataojo',
    numero: '2044',
    espacioId: 'esp-1',
    actualizada: estado == EstadoAgenda.programada ? null : ahora,
  ),
];

/// Monta la pestaña «Agenda» real con el detalle real detrás de cada fila. Con [entrar] toca la fila.
/// Con [detalleSolo] el detalle es la única ruta (como al abrirlo desde un recordatorio en frío).
Future<Montaje455> montar455(
  WidgetTester tester, {
  TipoAgenda tipo = TipoAgenda.entrevista,
  bool entrar = true,
  bool recordatorioSeQueda = false,
  double escala = 1,
  Size tamano = chico455,
  String? nota,
  bool detalleSolo = false,
}) async {
  await cargarFuentes408(tester);
  final ahora = ahoraDelDetalle();
  final repo = AgendaRepositorioDetalle(
    DetalleDeAgenda(
      agenda: agendaDelDetalle(tipo: tipo),
      nota: nota,
    ),
  );
  final consulta = ConsultaAgendaFalsa(filas455(tipo, EstadoAgenda.programada, ahora));
  final telefono = Telefono();
  telefono.recordatorios.puedeCancelar = !recordatorioSeQueda;
  final montaje = Montaje455(repo: repo, consulta: consulta, telefono: telefono);
  repo.alCancelarAgenda = (cancelada) =>
      consulta.emitir(filas455(tipo, EstadoAgenda.cancelada, ahora));
  final personas = PersonaRepositorioFalso()..sembrar([mariaFernandez]);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agendaRepositoryProvider.overrideWithValue(repo),
        consultaAgendaRepositoryProvider.overrideWithValue(consulta),
        relojVisitaProvider.overrideWithValue(() => ahora),
        relojAgendaProvider.overrideWithValue(() => ahora),
        ...telefono.overrides,
        personaRepositoryProvider.overrideWithValue(personas),
        espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(casaMataojo())),
        abrirDetalleDeAgendaProvider.overrideWithValue((agendaId) {
          montaje.aperturas += 1;
          return DetalleAgendaPage.abrir(
            montaje.navegador.currentContext!,
            agendaId: agendaId,
            colportorId: 'col-1',
          );
        }),
      ],
      child: MaterialApp(
        navigatorKey: montaje.navegador,
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: detalleSolo
            ? const DetalleAgendaPage(agendaId: 'ag-1', colportorId: 'col-1')
            : const Scaffold(body: AgendaPage(colportorId: 'col-1')),
      ),
    ),
  );
  await asentarDetalle(tester);
  if (entrar && !detalleSolo) await entrar455(tester);
  return montaje;
}

Future<void> entrar455(WidgetTester tester) async {
  final fila = find.text('María Fernández');
  await tester.scrollUntilVisible(fila, 100, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(fila);
  await tester.pump();
  await tester.tap(fila);
  await asentarDetalle(tester);
}

/// Cierra la pantalla: el temporizador del minuto de la lista se cancela en `dispose`.
Future<void> desmontar455(WidgetTester tester) => tester.pumpWidget(const SizedBox.shrink());

Finder get enlace455 => find.descendant(
  of: find.byType(DetalleAgendaPage),
  matching: find.widgetWithText(TextButton, 'Cancelar agenda'),
);
Finder get hoja455 => find.byType(HojaCancelarAgenda);
Finder get confirmar455 => find.descendant(of: hoja455, matching: find.byType(FilledButton));
Finder get volver455 => find.descendant(of: hoja455, matching: find.byType(OutlinedButton));
Finder get detalle455 => find.byType(DetalleAgendaPage);

/// El área que se desplaza dentro de la hoja (lo que la colportora ve del texto y del aviso).
Finder get zonaDeLaHoja455 =>
    find.descendant(of: hoja455, matching: find.byType(SingleChildScrollView));

Future<void> abrirHoja455(WidgetTester tester) async {
  await tester.ensureVisible(enlace455);
  await tester.pump();
  await tester.tap(enlace455);
  await asentarDetalle(tester);
}

Future<void> confirmar455Tocar(WidgetTester tester) async {
  await tester.ensureVisible(confirmar455);
  await tester.pump();
  await tester.tap(confirmar455);
  await asentarDetalle(tester);
}

Future<void> filtrarCanceladas455(WidgetTester tester) async {
  await tester.tap(find.text('Pendientes ▾'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('agenda_estado_canceladas')));
  await tester.tap(find.text('Aplicar'));
  await tester.pumpAndSettle();
}

/// Los estados que una persona puede alcanzar al cancelar una agenda.
enum Estado455 {
  d01Detalle('23C·01 detalle con el enlace'),
  h04Entrevista('23C·04 hoja ¿Cancelar la entrevista?'),
  h04Cobranza('23C·04 hoja ¿Cancelar la cobranza?'),
  h04Cancelando('23C·04 hoja «Cancelando…»'),
  h07Error('23C·07 hoja con el aviso de error y «Reintentar»'),
  h06YaNoSePuede('23C·06 hoja: la agenda ya no se puede cancelar'),
  l05Cancelada('23C·05 lista con «Agenda cancelada.»'),
  l05SinRecordatorio('23C·05 lista con el aviso del recordatorio que quedó'),
  l05Canceladas('23B·05 lista con el filtro «Canceladas»'),
  d06Cumplida('23C·06 detalle de la agenda que se cumplió');

  const Estado455(this.rotulo);
  final String rotulo;

  String get archivo => name;

  /// Los estados donde la hoja está abierta.
  bool get conHoja => name.startsWith('h');
}

/// Lleva la pantalla al [estado].
Future<Montaje455> llegarA455(
  WidgetTester tester,
  Estado455 estado, {
  Size tamano = chico455,
  double escala = 1,
}) async {
  Future<Montaje455> montar({
    TipoAgenda tipo = TipoAgenda.entrevista,
    bool recordatorioSeQueda = false,
    String? nota,
  }) => montar455(
    tester,
    tipo: tipo,
    recordatorioSeQueda: recordatorioSeQueda,
    escala: escala,
    tamano: tamano,
    nota: nota,
  );

  switch (estado) {
    case Estado455.d01Detalle:
      return montar(nota: 'Pidió volver con el esposo');
    case Estado455.h04Entrevista:
      final m = await montar();
      await abrirHoja455(tester);
      return m;
    case Estado455.h04Cobranza:
      final m = await montar(tipo: TipoAgenda.cobranza);
      await abrirHoja455(tester);
      return m;
    case Estado455.h04Cancelando:
      final m = await montar();
      m.repo.compuertaAlCancelar = Completer<void>();
      await abrirHoja455(tester);
      await tester.ensureVisible(confirmar455);
      await tester.tap(confirmar455);
      await tester.pump(const Duration(milliseconds: 60));
      return m;
    case Estado455.h07Error:
      final m = await montar();
      m.repo.fallasAlCancelar.add(const FailureInesperado(causa: 'StateError'));
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      return m;
    case Estado455.h06YaNoSePuede:
      final m = await montar();
      await abrirHoja455(tester);
      m.repo.detalle = DetalleDeAgenda(agenda: agendaDelDetalle(estado: EstadoAgenda.cumplida));
      m.repo.fallasAlCancelar.add(const FailureValidacion(campos: {'agenda': yaNoSePuede455}));
      await confirmar455Tocar(tester);
      return m;
    case Estado455.l05Cancelada:
      final m = await montar();
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      return m;
    case Estado455.l05SinRecordatorio:
      final m = await montar(recordatorioSeQueda: true);
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      return m;
    case Estado455.l05Canceladas:
      final m = await montar();
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      await filtrarCanceladas455(tester);
      return m;
    case Estado455.d06Cumplida:
      final m = await montar();
      await abrirHoja455(tester);
      m.repo.detalle = DetalleDeAgenda(agenda: agendaDelDetalle(estado: EstadoAgenda.cumplida));
      m.repo.fallasAlCancelar.add(const FailureValidacion(campos: {'agenda': yaNoSePuede455}));
      await confirmar455Tocar(tester);
      await tester.ensureVisible(volver455);
      await tester.tap(volver455);
      await asentarDetalle(tester);
      return m;
  }
}

/// La pantalla completa (incluidas las hojas y el aviso) como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar455(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/455_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado455(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Las fuentes reales solo se apagan en el archivo de las guías de Flutter.
void sinFuentesReales455() => usarFuentesReales408 = false;

String sufijo455(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';
