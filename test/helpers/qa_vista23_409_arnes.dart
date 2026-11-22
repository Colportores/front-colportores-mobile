// Arnés del QA del detalle y de «Modificar agenda» (vista 23 C, #409): reusa el arnés de la
// implementación (`detalle_agenda_arnes.dart`) y le suma las fuentes reales del proyecto, los tamaños
// del QA y un enum con cada estado que una persona puede alcanzar (23C·01, 23C·02, 23C·03, 23C·06,
// 23C·07 y los que el canvas no dibuja). Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true`
// y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/modificar_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'campo_falsos.dart' show visitaDe;
import 'detalle_agenda_arnes.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408, usarFuentesReales408;

export 'qa_vista23_408_arnes.dart' show conCapturas408, usarFuentesReales408;

const chico409 = Size(360, 640);
const grande409 = Size(412, 915);

final guardar409 = find.byKey(ClavesModificarAgenda.guardar);
final campoHora409 = find.byKey(ClavesAgendarVisita.campoDiaYHora);
final modificar409 = find.byKey(ClavesDetalleAgenda.modificar);

/// Toca [f] (lo trae a la vista antes) y deja correr los fotogramas.
Future<void> tocar409(WidgetTester tester, Finder f, {int fotogramas = 12}) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await asentarDetalle(tester, fotogramas);
}

Future<void> repetir409(WidgetTester tester, Key tecla, int veces) async {
  for (var i = 0; i < veces; i++) {
    await tester.tap(find.byKey(tecla));
    await tester.pump();
  }
}

/// Sube la hora [pasos] veces de a 5 min (12 = una hora).
Future<void> subirHora409(WidgetTester tester, int pasos) async {
  await tocar409(tester, campoHora409);
  await repetir409(tester, ClavesAgendarVisita.hojaMas, pasos);
  await tocar409(tester, find.byKey(ClavesAgendarVisita.hojaListo));
}

/// Elige «Hoy» (14:30 con el reloj del canvas en 14:35: ya pasó).
Future<void> hoyAMediaTarde409(WidgetTester tester) async {
  await tocar409(tester, campoHora409);
  await tocar409(tester, find.byKey(ClavesAgendarVisita.dia(0)));
  await tocar409(tester, find.byKey(ClavesAgendarVisita.hojaListo));
}

/// Los estados que una persona puede alcanzar en el detalle y en «Modificar».
enum Estado409 {
  d01Programada('23C·01 programada'),
  d01SinRegistrar('23C·01 sin «Registrar resultado»'),
  d01Vacia('23C·01 sin franja ni nota'),
  d01Larga('23C·01 nota de 500 caracteres'),
  d01RecordatorioApagado('23C·01 recordatorios apagados'),
  d03Modificada('23C·03 modificada (aviso)'),
  d06Cumplida('23C·06 cumplida'),
  d06NoCumplida('23C·06 no cumplida'),
  d06Cancelada('23C·06 cancelada'),
  dCargando('detalle cargando'),
  dErrorAlLeer('detalle error al leer'),
  dNoEsta('detalle: la agenda ya no está'),
  m02Modificar('23C·02 modificar'),
  m02Cobranza('23C·02 pasa a cobranza'),
  m02Hoja('23C·02 hoja día y hora'),
  m02HoraPasada('23C·02 hora pasada en el campo'),
  m02Pregunta('23C·02 hoja «Esa hora ya pasó»'),
  m07Error('23C·07 error al guardar'),
  m07Guardando('23C·02 guardando'),
  mCasaCargando('modificar: la casa carga'),
  mCasaError('modificar: la casa no se pudo leer'),
  mSinPermiso('modificar: sin permiso de notificaciones'),
  mApagados('modificar: recordatorios apagados');

  const Estado409(this.rotulo);
  final String rotulo;

  String get archivo => name;

  /// Los estados que viven en «Modificar» (para saber a qué pantalla mirar).
  bool get esModificar => name.startsWith('m');
}

/// Monta y lleva la pantalla al [estado].
Future<ArnesDetalle> llegarA409(
  WidgetTester tester,
  Estado409 estado, {
  Size tamano = chico409,
  double escala = 1,
}) async {
  await cargarFuentes408(tester);
  Future<ArnesDetalle> montar({
    DetalleDeAgenda? detalle,
    AgendaRepositorioDetalle? repo,
    bool conRegistrar = true,
    Failure? fallaDeCasa,
    bool permisoConcedido = true,
    bool abrir = true,
  }) => montarDetalle(
    tester,
    detalle: detalle,
    repo: repo,
    conRegistrar: conRegistrar,
    fallaDeCasa: fallaDeCasa,
    permisoConcedido: permisoConcedido,
    abrir: abrir,
    escala: escala,
    tamano: tamano,
  );

  switch (estado) {
    case Estado409.d01Programada:
      return montar(
        detalle: DetalleDeAgenda(agenda: agendaDelDetalle(), nota: 'Pidió volver con el esposo'),
      );
    case Estado409.d01SinRegistrar:
      return montar(conRegistrar: false);
    case Estado409.d01Vacia:
      return montar(detalle: DetalleDeAgenda(agenda: agendaDelDetalle(slot: null)));
    case Estado409.d01Larga:
      return montar(
        detalle: DetalleDeAgenda(agenda: agendaDelDetalle(), nota: 'n' * 500),
      );
    case Estado409.d01RecordatorioApagado:
      final a = await montar(abrir: false);
      a.telefono.preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
      await abrirDetalle(tester);
      return a;
    case Estado409.d03Modificada:
      final a = await montar();
      await tocar409(tester, modificar409);
      await subirHora409(tester, 12);
      await tocar409(tester, guardar409);
      return a;
    case Estado409.d06Cumplida:
      return montar(
        detalle: DetalleDeAgenda(
          agenda: agendaDelDetalle(estado: EstadoAgenda.cumplida),
          visita: visitaDe('vis-1'),
        ),
      );
    case Estado409.d06NoCumplida:
      return montar(
        detalle: DetalleDeAgenda(
          agenda: agendaDelDetalle(estado: EstadoAgenda.noCumplida),
          visita: visitaDe('vis-1', resultado: TipoResultadoVisita.noContesto),
        ),
      );
    case Estado409.d06Cancelada:
      return montar(
        detalle: DetalleDeAgenda(agenda: agendaDelDetalle(estado: EstadoAgenda.cancelada)),
      );
    case Estado409.dCargando:
      return montar(
        repo: AgendaRepositorioDetalle(DetalleDeAgenda(agenda: agendaDelDetalle()))
          ..compuertaDeLectura = Completer<void>(),
      );
    case Estado409.dErrorAlLeer:
      return montar(
        repo: AgendaRepositorioDetalle(DetalleDeAgenda(agenda: agendaDelDetalle()))
          ..fallasDeLectura.add(const FailureInesperado()),
      );
    case Estado409.dNoEsta:
      return montar(repo: AgendaRepositorioDetalle(null));
    case Estado409.m02Modificar:
      final a = await montar(
        detalle: DetalleDeAgenda(agenda: agendaDelDetalle(), nota: 'Pidió volver con el esposo'),
      );
      await tocar409(tester, modificar409);
      return a;
    case Estado409.m02Cobranza:
      final a = await montar(
        detalle: DetalleDeAgenda(agenda: agendaDelDetalle(), nota: 'Pidió volver con el esposo'),
      );
      await tocar409(tester, modificar409);
      await tocar409(tester, find.text('Cobranza'));
      await subirHora409(tester, 6);
      return a;
    case Estado409.m02Hoja:
      final a = await montar();
      await tocar409(tester, modificar409);
      await tocar409(tester, campoHora409);
      return a;
    case Estado409.m02HoraPasada:
      final a = await montar();
      await tocar409(tester, modificar409);
      await hoyAMediaTarde409(tester);
      return a;
    case Estado409.m02Pregunta:
      final a = await montar();
      await tocar409(tester, modificar409);
      await hoyAMediaTarde409(tester);
      await tocar409(tester, guardar409);
      return a;
    case Estado409.m07Error:
      final a = await montar();
      a.repo.fallas.add(const FailureInesperado());
      await tocar409(tester, modificar409);
      await tocar409(tester, find.text('Cobranza'));
      await tocar409(tester, guardar409);
      // El aviso va arriba del formulario: se sube para verlo (y para que ninguna fila quede cortada
      // por el borde de la zona que se desplaza, que las guías miden como un toque más chico).
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 3000));
      await asentarDetalle(tester);
      return a;
    case Estado409.m07Guardando:
      final a = await montar();
      a.repo.compuerta = Completer<void>();
      await tocar409(tester, modificar409);
      await tocar409(tester, find.text('Cobranza'));
      await tester.ensureVisible(guardar409);
      await tester.tap(guardar409);
      await tester.pump(const Duration(milliseconds: 60));
      return a;
    case Estado409.mCasaCargando:
      // La casa de este arnés responde sola; la "carga" se ve en el primer cuadro.
      final a = await montar();
      await tester.tap(modificar409);
      await tester.pump();
      await tester.pump();
      return a;
    case Estado409.mCasaError:
      final a = await montar(fallaDeCasa: const FailureInesperado());
      await tocar409(tester, modificar409);
      return a;
    case Estado409.mSinPermiso:
      final a = await montar(permisoConcedido: false);
      await tocar409(tester, modificar409);
      return a;
    case Estado409.mApagados:
      final a = await montar(abrir: false);
      a.telefono.preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
      await abrirDetalle(tester);
      await tocar409(tester, modificar409);
      return a;
  }
}

/// La pantalla completa (incluidas las hojas y el aviso) como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar409(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/409_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado409(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Las fuentes reales solo se apagan en el archivo de las guías de Flutter.
void sinFuentesReales409() => usarFuentesReales408 = false;
