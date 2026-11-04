// Arnés de la QA de #508 (pestaña «Agenda», vista 23B, HU-VIS-002: estados cerrados en toda la
// campaña). Reusa el de #148 (fuentes reales, reloj fijo, `montar`) y suma los estados de la lista de
// la campaña: «Cumplidas» con más de una página («Ver más»), «Todas» mezcladas, «Canceladas»,
// cargando, error, vacío, sin resultados y textos límite. Las capturas solo con
// `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/` (gitignored).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agenda.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agenda_items_falsos.dart';
import 'qa_agenda_148_arnes.dart';

export 'qa_agenda_148_arnes.dart';

/// Los estados de la lista de la campaña (más la ventana, de control).
enum Estado508 {
  pendientes('control: Pendientes (ventana de 7 días)'),
  cumplidasConVerMas('Cumplidas con 60 (50 + «Ver más»)'),
  todasMezcla('Todas: los cuatro estados y una vencida'),
  canceladas('23B·05 Canceladas de la campaña'),
  cargando('23B·06 cargando (Cumplidas)'),
  error('23B·09 error al leer (Cumplidas)'),
  sinResultados('23B·08 Cumplidas sin resultados'),
  sinResultadosTipo('23B·08 Cobranzas + No cumplidas sin resultados'),
  larga('Todas con textos larguísimos y edificio'),
  hoja('23B·04 hoja Estado abierta');

  const Estado508(this.rotulo);
  final String rotulo;

  /// ¿Termina con «Ver más» al pie de la lista?
  bool get conVerMas => this == cumplidasConVerMas;
}

/// La [i]-ésima cumplida hacia atrás desde ayer: dos por día (9:00 y 15:00), con nombre `P000`…
ItemAgenda cerrada(
  int i, {
  EstadoAgenda estado = EstadoAgenda.cumplida,
  TipoAgenda tipo = TipoAgenda.entrevista,
}) {
  final dia = DateTime(2026, 10, 27).subtract(Duration(days: i ~/ 2));
  return itemAgenda(
    'k$i',
    DateTime(dia.year, dia.month, dia.day, i.isEven ? 15 : 9),
    estado: estado,
    tipo: tipo,
    nombre: 'P${i.toString().padLeft(3, '0')}',
  );
}

List<ItemAgenda> itemsDe508(Estado508 e) {
  switch (e) {
    case Estado508.pendientes:
      return [entrevista('e1', DateTime(2026, 10, 28, 17), nombre: 'Jorge')];
    case Estado508.cumplidasConVerMas:
      return [for (var i = 0; i < 60; i++) cerrada(i)];
    case Estado508.todasMezcla:
      return [
        entrevista('futura', DateTime(2026, 11, 3, 10), nombre: 'Futura'),
        entrevista('vencida', DateTime(2026, 10, 28, 8), nombre: 'Vencida'),
        cerrada(0),
        cerrada(1, estado: EstadoAgenda.noCumplida),
        cerrada(2, estado: EstadoAgenda.cancelada, tipo: TipoAgenda.cobranza),
        cerrada(8),
        cerrada(40, estado: EstadoAgenda.noCumplida, tipo: TipoAgenda.cobranza),
      ];
    case Estado508.canceladas:
      return [
        cerrada(3, estado: EstadoAgenda.cancelada),
        cerrada(9, estado: EstadoAgenda.cancelada, tipo: TipoAgenda.cobranza),
        cerrada(30, estado: EstadoAgenda.cancelada),
      ];
    case Estado508.cargando:
    case Estado508.error:
    case Estado508.sinResultados:
      return const [];
    case Estado508.sinResultadosTipo:
      return [cerrada(0), cerrada(1, estado: EstadoAgenda.cancelada)];
    case Estado508.larga:
      return [
        itemAgenda(
          'l1',
          DateTime(2026, 10, 12, 14),
          estado: EstadoAgenda.cumplida,
          nombre: 'María de los Ángeles Fernández de la Cruz y Benítez 🌟',
          apellido: 'Rodríguez-Sánchez Pereira de Albuquerque',
          calle: 'Avenida General Don José Gervasio Artigas y Carlos María Ramírez',
          numero: '1234 bis esquina Bulevar',
          tipoUbicacion: TipoUbicacion.edificio,
          numeroDepto: '1204-B torre norte',
        ),
        itemAgenda(
          'l2',
          DateTime(2026, 9, 30, 18),
          estado: EstadoAgenda.cancelada,
          nombre: null,
          apellido: null,
          calle: 'Calle sin nombre muy muy larga que no entra en una línea',
          numero: '99999',
          tipo: TipoAgenda.cobranza,
        ),
      ];
    case Estado508.hoja:
      return [cerrada(0)];
  }
}

/// El estado del filtro que el [e] elige (`null`: queda «Pendientes»).
String? _estadoDe(Estado508 e) => switch (e) {
  Estado508.cumplidasConVerMas ||
  Estado508.cargando ||
  Estado508.error ||
  Estado508.sinResultados ||
  Estado508.larga => 'Cumplidas',
  Estado508.todasMezcla => 'Todas',
  Estado508.canceladas => 'Canceladas',
  Estado508.sinResultadosTipo => 'No cumplidas',
  _ => null,
};

/// Lleva la pantalla al estado [e].
Future<ConsultaAgendaFalsa> llegarA508(
  WidgetTester tester,
  Estado508 e, {
  double escala = 1,
  Size tamano = telefonoChico,
  Destinos? destinos,
}) async {
  final repo = ConsultaAgendaFalsa(itemsDe508(e));
  await montar(tester, repo, escala: escala, tamano: tamano, destinos: destinos);
  if (e == Estado508.hoja) {
    await tester.tap(find.text('Pendientes ▾'));
    await tester.pumpAndSettle();
    return repo;
  }
  if (e == Estado508.sinResultadosTipo) {
    await tester.tap(find.text('Cobranzas'));
    await asentar(tester);
  }
  // Cargando y error se arman después de elegir el filtro: la campaña es otra lectura.
  if (e == Estado508.cargando) repo.congelada = true;
  if (e == Estado508.error) repo.error = StateError('boom');
  final estado = _estadoDe(e);
  if (estado != null) {
    await aplicar508(tester, estado);
    await asentar(tester);
    // Con el error de lectura el canvas (23B·09) muestra solo el aviso: sin la fila de filtros.
    if (e != Estado508.error) {
      expect(find.text('$estado ▾'), findsOneWidget, reason: 'no quedó en «$estado»');
    }
  }
  return repo;
}

/// Abre la hoja «Estado», elige [opcion] y toca «Aplicar», bajando la hoja si hace falta (con el
/// texto al 200 % el botón queda bajo el pliegue de la hoja, que se desplaza).
Future<void> aplicar508(WidgetTester tester, String opcion) async {
  await tester.tap(find.textContaining('▾'));
  await tester.pumpAndSettle();
  final fila = find.descendant(of: find.byType(BottomSheet), matching: find.text(opcion));
  await tester.ensureVisible(fila);
  await tester.pumpAndSettle();
  await tester.tap(fila);
  await tester.pumpAndSettle();
  final aplicar = find.byKey(const Key('agenda_aplicar_estado'));
  await tester.ensureVisible(aplicar);
  await tester.pumpAndSettle();
  await tester.tap(aplicar);
  await tester.pumpAndSettle();
}

/// Baja hasta el fin de la lista.
Future<void> irAlFinal(WidgetTester tester) async {
  final lista = find.byKey(const Key('agenda_filas'));
  for (var i = 0; i < 40; i++) {
    final antes = tester
        .state<ScrollableState>(find.descendant(of: lista, matching: find.byType(Scrollable)).first)
        .position
        .pixels;
    await tester.drag(lista, const Offset(0, -3000));
    await tester.pump();
    final despues = tester
        .state<ScrollableState>(find.descendant(of: lista, matching: find.byType(Scrollable)).first)
        .position
        .pixels;
    if (despues == antes) break;
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Cuántas filas hay dibujadas ahora (la lista es perezosa: solo las visibles).
int filasDibujadas(WidgetTester tester) => tester.widgetList(find.byType(FilaAgenda)).length;

/// Una captura PNG en `.dart_tool/qa_capturas/508_<nombre>.png`.
Future<void> capturar508(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/508_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
