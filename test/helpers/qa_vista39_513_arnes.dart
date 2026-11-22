// Arnés del QA de la vista 39 R·02/R·03 en «Agendar visita» (#513): monta la pantalla con el arnés del
// implementador (`montarAgendar`), con las fuentes reales del proyecto (las del arnés de #408), y sabe
// llegar a cada estado de los dos artboards y a los que el canvas no dibuja (cargando, vacío, error de
// lectura, muchas entrevistas, hoja de solo día, selector de hora, hora pasada, guardando, falla).
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/entrevista_cercana.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408, chico;

export 'qa_vista23_408_arnes.dart' show chico, grande, sinTextoCortado408, usarFuentesReales408;

const conHallazgos513 = bool.fromEnvironment('QA_HALLAZGOS');
const conCapturas513 = bool.fromEnvironment('QA_CAPTURAS');

final boton513 = find.byKey(ClavesAgendarVisita.botonAgendar);
final campo513 = find.byKey(ClavesAgendarVisita.campoDiaYHora);
final tarjeta513 = find.byKey(ClavesAgendarVisita.tarjetaFecha);
final interruptor513 = find.byKey(ClavesAgendarVisita.interruptorEstricta);
final horaAcordada513 = find.byKey(ClavesAgendarVisita.campoHoraAcordada);

/// Dos entrevistas el lunes 26/10 (el canvas dibuja «2 entrevistas a menos de 300 m»): «Primera tarde».
List<EntrevistaCercana> dosEnLaTarde513() => [
  EntrevistaCercana(fecha: DateTime(2026, 10, 26, 16, 45)),
  EntrevistaCercana(fecha: DateTime(2026, 10, 26, 17, 15)),
];

/// [n] entrevistas el miércoles 28/10 (el día más largo de escribir), «Fin de tarde».
List<EntrevistaCercana> muchas513(int n) => [
  for (var i = 0; i < n; i++)
    EntrevistaCercana(
      fecha: DateTime(2026, 10, 28, 19, 20).add(Duration(seconds: i)),
      slotCodigo: 'late_afternoon',
    ),
];

Future<void> tocar513(WidgetTester tester, Finder f, {int fotogramas = 12}) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await asentarAgendar(tester, fotogramas);
}

/// Lo que el test necesita de la pantalla montada.
final class Montaje513 {
  Montaje513({required this.arnes, required this.lectura, required this.repo});

  final ArnesAgendar arnes;
  final EntrevistasCercanasFalsas lectura;
  final AgendaRepositorioQueAgenda repo;
}

Future<Montaje513> montar513(
  WidgetTester tester, {
  List<EntrevistaCercana>? cercanas,
  EntrevistasCercanasFalsas? lectura,
  AgendaRepositorioQueAgenda? repo,
  TipoAgenda tipo = TipoAgenda.entrevista,
  DateTime? ahora,
  Size tamano = chico,
  double escala = 1,
  bool abrir = true,
}) async {
  await cargarFuentes408(tester);
  final falsa = lectura ?? EntrevistasCercanasFalsas(cercanas ?? dosEnLaTarde513());
  final registra = repo ?? AgendaRepositorioQueAgenda();
  final arnes = await montarAgendar(
    tester,
    cercanas: falsa,
    repo: registra,
    tipo: tipo,
    ahora: ahora,
    tamano: tamano,
    escala: escala,
    abrir: abrir,
  );
  return Montaje513(arnes: arnes, lectura: falsa, repo: registra);
}

/// Los estados que una persona puede alcanzar con R·02 y R·03.
enum Estado513 {
  r02Sugerida('R·02 sugerida'),
  r02Muchas('R·02 120 entrevistas, miércoles'),
  r02Cargando('R·02 cargando la lectura'),
  r02Vacio('R·02 vacío: sin entrevistas cerca'),
  r02Error('R·02 falla la lectura'),
  r02Cobranza('R·02 cobranza (sin tarjeta ni interruptor)'),
  r02FranjaCambiada('R·02 franja cambiada a mano'),
  r02Hoja('R·02 hoja «Día y hora» desde Cambiar'),
  r03Estricta('R·03 estricta'),
  r03HojaDia('R·03 hoja «Día» (solo el día)'),
  r03Selector('R·03 selector de hora del sistema'),
  r03HoraPasada('R·03 hora acordada que ya pasó'),
  r03Pregunta('R·03 hoja «Esa hora ya pasó»'),
  r03Agendando('R·03 agendando'),
  r03Error('R·03 falla al guardar');

  const Estado513(this.rotulo);
  final String rotulo;
}

/// Monta y lleva la pantalla al [estado].
Future<Montaje513> llegarA513(
  WidgetTester tester,
  Estado513 estado, {
  Size tamano = chico,
  double escala = 1,
}) async {
  Future<Montaje513> m({
    List<EntrevistaCercana>? cercanas,
    EntrevistasCercanasFalsas? lectura,
    AgendaRepositorioQueAgenda? repo,
    TipoAgenda tipo = TipoAgenda.entrevista,
  }) => montar513(
    tester,
    cercanas: cercanas,
    lectura: lectura,
    repo: repo,
    tipo: tipo,
    tamano: tamano,
    escala: escala,
  );

  /// Estricta con la hora de hoy a las 10:00 (el reloj marca las 14:35): la hora ya pasó.
  Future<Montaje513> estrictaConHoraPasada({AgendaRepositorioQueAgenda? repo}) async {
    final x = await m(cercanas: const [], repo: repo);
    await tocar513(tester, interruptor513);
    await tocar513(tester, tarjeta513);
    await tocar513(tester, find.byKey(ClavesAgendarVisita.dia(0)));
    await tocar513(tester, find.byKey(ClavesAgendarVisita.hojaListo));
    return x;
  }

  switch (estado) {
    case Estado513.r02Sugerida:
      return m();
    case Estado513.r02Muchas:
      return m(cercanas: muchas513(120));
    case Estado513.r02Cargando:
      return m(lectura: EntrevistasCercanasFalsas(dosEnLaTarde513(), compuerta: Completer<void>()));
    case Estado513.r02Vacio:
      return m(cercanas: const []);
    case Estado513.r02Error:
      return m(lectura: EntrevistasCercanasFalsas(const [], falla: StateError('sin base')));
    case Estado513.r02Cobranza:
      return m(tipo: TipoAgenda.cobranza);
    case Estado513.r02FranjaCambiada:
      final x = await m();
      await tocar513(tester, find.text('Media tarde'));
      return x;
    case Estado513.r02Hoja:
      final x = await m();
      await tocar513(tester, tarjeta513);
      return x;
    case Estado513.r03Estricta:
      final x = await m();
      await tocar513(tester, interruptor513);
      return x;
    case Estado513.r03HojaDia:
      final x = await m();
      await tocar513(tester, interruptor513);
      await tocar513(tester, tarjeta513);
      return x;
    case Estado513.r03Selector:
      final x = await m();
      await tocar513(tester, interruptor513);
      await tocar513(tester, horaAcordada513);
      return x;
    case Estado513.r03HoraPasada:
      return estrictaConHoraPasada();
    case Estado513.r03Pregunta:
      final x = await estrictaConHoraPasada();
      await tocar513(tester, boton513);
      return x;
    case Estado513.r03Agendando:
      final repo = AgendaRepositorioQueAgenda()..compuerta = Completer<void>();
      final x = await m(repo: repo);
      await tocar513(tester, interruptor513);
      await tester.ensureVisible(boton513);
      await tester.tap(boton513);
      await tester.pump(const Duration(milliseconds: 50));
      return x;
    case Estado513.r03Error:
      final repo = AgendaRepositorioQueAgenda()..fallas.add(const FailureInesperado());
      final x = await m(repo: repo);
      await tocar513(tester, interruptor513);
      await tocar513(tester, boton513);
      return x;
  }
}

/// La pantalla completa (incluidas las hojas) como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar513(WidgetTester tester, String nombre) async {
  if (!conCapturas513) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/513_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
