// Arnés de los tests de QA del Historial de la hoja de la casa (vista 39, C·03 y C·04, #446, PR #677):
// lleva la hoja real, con el enganche de `main.dart`, a cada estado que una persona puede ver de la
// pestaña «Historial» y de su detalle, y saca capturas.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/446_*.png`
// (gitignored: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart'
    show TipoResultadoVisita;
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart'
    show MedioCobranza;
import 'package:colportores_mobile/features/mapa/domain/entities/evento_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart'
    show LineaDeFicha;
import 'package:colportores_mobile/features/mapa/domain/services/historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/historial_de_la_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_detalle_de_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/personas_arnes.dart' show contextoActivo;
import 'hoja_casa_falsos.dart';
import 'lista_ubicaciones_falsos.dart' show ahoraLista;
import 'persona_falsos.dart';
import 'qa_vista39_445_arnes.dart' show contextoC02;

export 'qa_baja_205_arnes.dart' show cargarFuentes205;
export 'qa_vista39_445_arnes.dart' show t320x568, t360x640, t412x915;

const conCapturas446 = bool.fromEnvironment('QA_CAPTURAS');

final raizCaptura446 = GlobalKey();

/// El «hoy» de la pestaña: domingo 25/10/2026 a las 16:00, hora local.
final ahora446 = DateTime(2026, 10, 25, 16);

DateTime fecha446(int mes, int dia, [int hora = 12, int minuto = 0, int anio = 2026]) =>
    DateTime(anio, mes, dia, hora, minuto).toUtc();

const pedro446 = PersonaDelEvento(nombre: 'Pedro', apellido: 'Gómez');

final cobroHoy446 = CobroDeLaCasa(
  id: 'cob-1',
  fecha: fecha446(10, 25, 14, 20),
  montoCentavos: 60000,
  medio: MedioCobranza.efectivo,
  ventaId: 'ven-1',
  numeroTalonario: '0038',
  persona: pedro446,
);

final venta446 = VentaDeLaCasa(
  id: 'ven-1',
  fecha: fecha446(10, 12, 14),
  numeroTalonario: '0038',
  montoCentavos: 480000,
  pagadoCentavos: 360000,
  lineas: const [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)],
  persona: pedro446,
  espacioPersonaId: 'ep-pedro',
  nota: 'quiere Nuestros Hijos',
);

final entrevista446 = VisitaDeLaCasa(
  id: 'vis-2',
  fecha: fecha446(10, 5, 17),
  resultado: TipoResultadoVisita.entrevista,
  persona: pedro446,
  nota: 'volver con la esposa',
  duracion: const Duration(minutes: 22),
);

final noContesto446 = VisitaDeLaCasa(
  id: 'vis-1',
  fecha: fecha446(10, 3, 15),
  resultado: TipoResultadoVisita.noContesto,
);

/// Lo de C·03: cobro de hoy, venta del 12, entrevista del 5 y «No contestó» del 3.
List<EventoDeLaCasa> eventosC03() => [cobroHoy446, venta446, entrevista446, noContesto446];

/// Una venta más: la de otro día, con otra persona.
final venta2446 = VentaDeLaCasa(
  id: 'ven-2',
  fecha: fecha446(10, 20, 11),
  numeroTalonario: '0045',
  montoCentavos: 24000,
  pagadoCentavos: 0,
  lineas: const [LineaDeFicha(nombre: 'Vida Feliz', cantidad: 2)],
  persona: const PersonaDelEvento(nombre: 'Ana', apellido: 'Gómez'),
  espacioPersonaId: 'ep-ana',
);

/// Setenta y cinco eventos de los cinco tipos, del más nuevo al más viejo.
List<EventoDeLaCasa> setentaYCinco446() => [
  for (var i = 0; i < 75; i++)
    switch (i % 5) {
      0 => VisitaDeLaCasa(
        id: 'v$i',
        fecha: fecha446(9, 1, 8).add(Duration(hours: 75 - i)),
        resultado: TipoResultadoVisita.noContesto,
      ),
      1 => VentaDeLaCasa(
        id: 'v$i',
        fecha: fecha446(9, 1, 8).add(Duration(hours: 75 - i)),
        numeroTalonario: '${1000 + i}',
        montoCentavos: 100000 + i,
        pagadoCentavos: 0,
        lineas: const [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)],
        persona: pedro446,
        espacioPersonaId: 'ep-pedro',
      ),
      2 => CobroDeLaCasa(
        id: 'v$i',
        fecha: fecha446(9, 1, 8).add(Duration(hours: 75 - i)),
        montoCentavos: 5000 + i,
        medio: MedioCobranza.tarjeta,
        ventaId: 'ven-x',
        numeroTalonario: '${1000 + i}',
        persona: pedro446,
      ),
      3 => VisitaDeLaCasa(
        id: 'v$i',
        fecha: fecha446(9, 1, 8).add(Duration(hours: 75 - i)),
        resultado: TipoResultadoVisita.entrevista,
        persona: pedro446,
      ),
      _ => VisitaDeLaCasa(
        id: 'v$i',
        fecha: fecha446(9, 1, 8).add(Duration(hours: 75 - i)),
        resultado: TipoResultadoVisita.rechazo,
      ),
    },
];

const _nombreLargo = 'Maximiliano Alejandro de los Santos Fernández-Rodríguez y Pérez de la Torre';
final _palabraLarga = 'Clave: ${'A1B2C3D4' * 30} 😀👍🏽 ${'ñandú' * 20}';

/// Eventos de nombres y notas largos: lo que más rompe una fila.
List<EventoDeLaCasa> textosLargos446() => [
  VentaDeLaCasa(
    id: 'l1',
    fecha: fecha446(10, 24, 10),
    numeroTalonario: '0099',
    montoCentavos: 123456789,
    pagadoCentavos: 23456789,
    lineas: const [
      LineaDeFicha(nombre: 'Salud y Hogar edición ampliada con tapa dura', cantidad: 3),
      LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1),
      LineaDeFicha(nombre: 'El Conflicto de los Siglos', cantidad: 12),
    ],
    persona: const PersonaDelEvento(nombre: _nombreLargo, apellido: _nombreLargo),
    espacioPersonaId: 'ep-largo',
    nota: _palabraLarga,
  ),
  VisitaDeLaCasa(
    id: 'l2',
    fecha: fecha446(10, 23, 9),
    resultado: TipoResultadoVisita.entrevista,
    persona: const PersonaDelEvento(nombre: _nombreLargo, apellido: _nombreLargo),
    nota: '${'Portón verde, timbre roto. ' * 190}FIN',
    duracion: const Duration(hours: 3, minutes: 5),
  ),
  CobroDeLaCasa(
    id: 'l3',
    fecha: fecha446(10, 22, 9),
    montoCentavos: 99999999,
    medio: MedioCobranza.transferencia,
    ventaId: 'l1',
    numeroTalonario: '0099',
    persona: const PersonaDelEvento(nombre: _nombreLargo),
  ),
  VisitaDeLaCasa(
    id: 'l4',
    fecha: fecha446(10, 21, 9),
    resultado: TipoResultadoVisita.cobranza,
    persona: const PersonaDelEvento(nombre: _nombreLargo),
  ),
];

/// Un historial que llega por partes: sirve para emitir y fallar a mitad.
final class HistorialControlado446 implements HistorialDeLaCasa {
  final lecturas = <StreamController<List<EventoDeLaCasa>>>[];

  @override
  Stream<List<EventoDeLaCasa>> observar(String espacioId) {
    final c = StreamController<List<EventoDeLaCasa>>();
    lecturas.add(c);
    return c.stream;
  }

  StreamController<List<EventoDeLaCasa>> get ultima => lecturas.last;
}

/// Un historial armado con una función por lectura (la n-ésima vez que se pide).
final class HistorialPorLectura446 implements HistorialDeLaCasa {
  HistorialPorLectura446(this._porLectura);

  final Stream<List<EventoDeLaCasa>> Function(int n) _porLectura;
  var pedidas = 0;

  @override
  Stream<List<EventoDeLaCasa>> observar(String espacioId) => _porLectura(pedidas++);
}

/// Deja correr los fotogramas que hacen falta sin esperar a los indicadores que giran para siempre.
Future<void> asentar446(WidgetTester tester, [int veces = 12]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Lo que un test necesita después de montar la hoja.
final class Montaje446 {
  Montaje446(this.fuente);

  final HistorialDeLaCasa fuente;
  final ventasAbiertas = <ContextoDeVentaDeLaCasa>[];
}

Future<Montaje446> montarHoja446(
  WidgetTester tester, {
  List<EventoDeLaCasa>? eventos,
  HistorialDeLaCasa? fuente,
  FutureOr<Object?> Function(ContextoDeVentaDeLaCasa)? verVenta,
  bool conVerVenta = true,
  FutureOr<Object?> Function(String)? verCobro,
  bool esBaja = false,
  double escala = 1,
  Size tamano = const Size(412, 915),
  bool irAHistorial = true,
  Montaje446? montaje,
}) async {
  final fuenteFinal = fuente ?? _Fija446(eventos ?? eventosC03());
  final m = montaje ?? Montaje446(fuenteFinal);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: <Override>[
        ...overridesHojaCasa(lectura: (_) => Stream.value(contextoC02)),
        personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
        espacioRepositoryProvider.overrideWithValue(
          EspacioRepositorioParaPersonas(contextoActivo()),
        ),
        fichaDePersonaDesdeLaCasaProvider.overrideWithValue(null),
        pestanaNotasDeLaCasaProvider.overrideWithValue(null),
        historialDeLaCasaFuenteProvider.overrideWithValue(fuenteFinal),
        relojPersonaProvider.overrideWithValue(() => ahora446),
        verCobroDesdeLaCasaProvider.overrideWithValue(verCobro),
        verVentaDesdeLaCasaProvider.overrideWithValue(
          conVerVenta
              ? (verVenta ??
                    (venta) {
                      m.ventasAbiertas.add(venta);
                      return true;
                    })
              : null,
        ),
        // Igual que `main.dart`.
        pestanaHistorialDeLaCasaProvider.overrideWithValue(
          (context, contexto) => PestanaHistorialDeLaCasa(
            espacioId: contexto.espacioId,
            direccion: contexto.direccion,
          ),
        ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: RepaintBoundary(key: raizCaptura446, child: child!),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: esBaja ? itemDeLaHoja(baja: DateTime(2026, 10, 1)) : itemDeLaHoja(),
              ahora: ahoraLista,
              alCerrar: () {},
              arriba: true,
              colportorId: 'col-1',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await asentar446(tester);
  if (irAHistorial) {
    await tester.ensureVisible(find.byKey(ClavesHojaCasa.pestana('historial')));
    await tester.pump();
    await tester.tap(find.byKey(ClavesHojaCasa.pestana('historial')));
    await asentar446(tester);
  }
  return m;
}

final class _Fija446 implements HistorialDeLaCasa {
  _Fija446(this._eventos);

  final List<EventoDeLaCasa> _eventos;

  @override
  Stream<List<EventoDeLaCasa>> observar(String espacioId) => Stream.value(_eventos);
}

/// Toca la fila [id] (la baja a la vista antes) y deja asentar.
Future<void> tocarFila446(WidgetTester tester, String id) async {
  final fila = find.byKey(ClavesHistorialDeLaCasa.fila(id));
  await tester.ensureVisible(fila);
  await tester.pump();
  await tester.tap(fila);
  await asentar446(tester);
}

/// Toca el botón de la clave [clave] de una hoja modal (la baja a la vista antes).
Future<void> tocarEnLaHoja446(WidgetTester tester, Key clave) async {
  final f = find.byKey(clave);
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await asentar446(tester);
}

/// Los renglones de texto cuyo `maxLines` los cortó con «…».
List<String> textosCortados446(WidgetTester tester) {
  final cortados = <String>[];
  void visitar(RenderObject r) {
    if (r is RenderParagraph && r.didExceedMaxLines) {
      cortados.add(r.text.toPlainText());
    }
    r.visitChildren(visitar);
  }

  visitar(tester.binding.renderViews.first);
  return cortados;
}

Future<void> capturar446(WidgetTester tester, String nombre) async {
  if (!conCapturas446) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/446_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

String sufijo446(Size tamano, double escala) =>
    '${tamano.width.toInt()}x${tamano.height.toInt()}_x$escala';

/// Los estados del Historial (y de su detalle) que una persona puede alcanzar.
enum Estado446 {
  c03,
  c03SinVerLaVenta,
  vacio,
  cargando,
  error,
  filtroEntrevistas,
  filtroSinResultados,
  detalleDeVenta,
  detalleDeEntrevista,
  detalleDeVisitaSinNota,
  detalleDeRechazo,
  avisoNoPudimosAbrirLaVenta,
  listaLarga,
  textosLargos,
  detalleLargo,
  dadaDeBaja,
}

Future<Montaje446> llegarA446(
  WidgetTester tester,
  Estado446 estado, {
  Size tamano = const Size(412, 915),
  double escala = 1,
}) async {
  Future<Montaje446> m({
    List<EventoDeLaCasa>? eventos,
    HistorialDeLaCasa? fuente,
    bool conVerVenta = true,
    FutureOr<Object?> Function(ContextoDeVentaDeLaCasa)? verVenta,
    bool esBaja = false,
  }) => montarHoja446(
    tester,
    eventos: eventos,
    fuente: fuente,
    conVerVenta: conVerVenta,
    verVenta: verVenta,
    esBaja: esBaja,
    tamano: tamano,
    escala: escala,
  );

  switch (estado) {
    case Estado446.c03:
      return m();
    case Estado446.c03SinVerLaVenta:
      return m(conVerVenta: false);
    case Estado446.vacio:
      return m(eventos: const []);
    case Estado446.cargando:
      return m(fuente: HistorialControlado446());
    case Estado446.error:
      return m(fuente: HistorialPorLectura446((_) => Stream.error(StateError('falla'))));
    case Estado446.filtroEntrevistas:
      final r = await m();
      await tester.ensureVisible(
        find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.entrevistas)),
      );
      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.entrevistas)));
      await asentar446(tester);
      return r;
    case Estado446.filtroSinResultados:
      final r = await m(eventos: [venta446, entrevista446]);
      await tester.ensureVisible(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.cobros)));
      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.cobros)));
      await asentar446(tester);
      return r;
    case Estado446.detalleDeVenta:
      final r = await m();
      await tocarFila446(tester, 'ven-1');
      return r;
    case Estado446.detalleDeEntrevista:
      final r = await m();
      await tocarFila446(tester, 'vis-2');
      return r;
    case Estado446.detalleDeVisitaSinNota:
      final r = await m();
      await tocarFila446(tester, 'vis-1');
      return r;
    case Estado446.detalleDeRechazo:
      final r = await m(
        eventos: [
          VisitaDeLaCasa(
            id: 'r1',
            fecha: fecha446(10, 24, 10),
            resultado: TipoResultadoVisita.rechazo,
            nota: 'Dijo que no quiere nada, volver en un año.',
          ),
        ],
      );
      await tocarFila446(tester, 'r1');
      return r;
    case Estado446.avisoNoPudimosAbrirLaVenta:
      final r = await m(verVenta: (_) => throw StateError('sin sesión'));
      await tocarFila446(tester, 'ven-1');
      await tocarEnLaHoja446(tester, ClavesDetalleDeVisita.verLaVenta);
      return r;
    case Estado446.listaLarga:
      return m(eventos: setentaYCinco446());
    case Estado446.textosLargos:
      return m(eventos: textosLargos446());
    case Estado446.detalleLargo:
      final r = await m(eventos: textosLargos446());
      await tocarFila446(tester, 'l1');
      return r;
    case Estado446.dadaDeBaja:
      return m(esBaja: true);
  }
}
