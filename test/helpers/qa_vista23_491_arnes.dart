// Arnés de los tests de QA de #491 (vista 23, artboard 23B·10 «En el mapa: tocar la casa»): monta la
// hoja de la casa con la lista «VISITAS AGENDADAS» en cada estado, dentro del alto REAL que le da el
// mapa (un tercio de la pantalla el resumen, la mitad la hoja arriba) y también en una pantalla
// entera (para las guías de accesibilidad, que no leen bien un nodo cortado por el borde del scroll).
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart'
    show ContextoDeVisita;
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart'
    show AlturaHoja;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'agenda_items_falsos.dart';
import 'hoja_casa_falsos.dart';
import 'lista_ubicaciones_falsos.dart' show ahoraLista;
import 'qa_agenda_148_arnes.dart' show cargarFuentes, conCapturas, telefonoChico;

export 'qa_agenda_148_arnes.dart'
    show
        cargarFuentes,
        conCapturas,
        contraste,
        escalas,
        expectSinTextoFueraDeLosCostados,
        tamanos,
        telefonoChico,
        telefonoGrande,
        usarFuentesReales,
        verHallazgos;

final raiz491 = GlobalKey();

/// Jueves 8/10/2026 y sábado 10/10/2026 (la hoja se monta el martes 6/10 de [ahoraLista]).
final jueves = DateTime(2026, 10, 8, 14, 30);
final sabado = DateTime(2026, 10, 10, 12, 30);

ItemAgenda entrevista491(String id, DateTime cuando, {String ub = 'u-1', String? nombre}) =>
    itemAgenda(
      id,
      cuando,
      nombre: nombre ?? 'María',
      apellido: nombre == null ? 'Fernández' : null,
      ubicacionId: ub,
    );

ItemAgenda cobranza491(String id, DateTime cuando, {String ub = 'u-1'}) => itemAgenda(
  id,
  cuando,
  tipo: TipoAgenda.cobranza,
  nombre: 'María',
  apellido: 'Fernández',
  ubicacionId: ub,
);

/// Los estados de la hoja con «Visitas agendadas» que se miran en la matriz.
enum Estado491 {
  canvas('23B·10 resumen: entrevista del jueves y cobranza del sábado'),
  canvasArriba('23B·10 hoja arriba (C·02)', arriba: true),
  sinVisitas('sin visitas: la sección no ocupa lugar'),
  vencida('visita cuya hora ya pasó'),
  edificio('edificio: «Depto 3B» en la visita'),
  alternativa('cobranza en otra dirección'),
  muchas('doce visitas', arriba: true),
  muchasResumen('doce visitas en el resumen'),
  larga('textos larguísimos y emoji'),
  otroAnio('visita de otro año'),
  error('error al leer las visitas'),
  errorArriba('error al leer las visitas, hoja arriba', arriba: true),
  cargando('visitas cargando'),
  sinDestinos('sin destino: filas sin «›» y sin «+ Agendar»'),
  baja('casa de baja (E·04): sin lista ni acciones');

  const Estado491(this.rotulo, {this.arriba = false});
  final String rotulo;
  final bool arriba;
}

List<ItemAgenda> itemsDe491(Estado491 e) {
  switch (e) {
    case Estado491.canvas:
    case Estado491.canvasArriba:
    case Estado491.sinDestinos:
    case Estado491.baja:
      return [entrevista491('ent', jueves), cobranza491('cob', sabado)];
    case Estado491.sinVisitas:
    case Estado491.cargando:
    case Estado491.error:
    case Estado491.errorArriba:
      return const [];
    case Estado491.vencida:
      return [entrevista491('vencida', DateTime(2026, 10, 5, 9)), cobranza491('cob', sabado)];
    case Estado491.edificio:
      return [
        itemAgenda(
          'ent',
          jueves,
          nombre: 'María',
          apellido: 'Fernández',
          tipoUbicacion: TipoUbicacion.edificio,
          numeroDepto: '3B',
          ubicacionId: 'u-1',
        ),
        itemAgenda(
          'cob',
          sabado,
          tipo: TipoAgenda.cobranza,
          nombre: 'Luis',
          apellido: 'Pérez',
          tipoUbicacion: TipoUbicacion.edificio,
          numeroDepto: '12',
          ubicacionId: 'u-1',
        ),
      ];
    case Estado491.alternativa:
      final base = cobranza491('cob', sabado);
      return [
        entrevista491('ent', jueves),
        ItemAgenda(
          agenda: base.agenda,
          personaNombre: 'María',
          personaApellido: 'Fernández',
          casa: base.casa,
          alternativa: const DireccionDeAgenda(
            ubicacionId: 'alt',
            tipo: TipoUbicacion.casa,
            calle: 'Av. Italia',
            numero: '2810',
          ),
        ),
      ];
    case Estado491.muchas:
    case Estado491.muchasResumen:
      return [
        for (var i = 0; i < 12; i++)
          i.isEven
              ? entrevista491('e$i', DateTime(2026, 10, 8 + i, 9 + i % 8), nombre: 'Persona $i')
              : cobranza491('c$i', DateTime(2026, 10, 8 + i, 9 + i % 8)),
      ];
    case Estado491.larga:
      return [
        itemAgenda(
          'l1',
          DateTime(2026, 10, 12, 14),
          nombre: 'María de los Ángeles Fernández de la Cruz y Benítez 🌟',
          apellido: 'Rodríguez-Sánchez Pereira de Albuquerque',
          ubicacionId: 'u-1',
        ),
        itemAgenda(
          'l2',
          DateTime(2026, 10, 15, 18),
          tipo: TipoAgenda.cobranza,
          nombre: 'Ñandú 🦩',
          apellido: 'Ibáñez',
          ubicacionId: 'u-1',
        ),
      ];
    case Estado491.otroAnio:
      return [
        itemAgenda('a25', DateTime(2027, 1, 5, 9), nombre: 'Anual', ubicacionId: 'u-1'),
        entrevista491('ent', jueves),
      ];
  }
}

/// Lo que un test necesita después de montar la hoja.
final class Montaje491 {
  Montaje491(this.repo);
  final ConsultaAgendaFalsa repo;
  final detalles = <String>[];
  final visitas = <ContextoDeVisita>[];
  var agendar = 0;
  final cierres = <int>[];
}

/// El alto que el mapa le da a la hoja: un tercio de la pantalla el resumen, la mitad arriba.
double altoDeLaHoja(Size tamano, double escala, {required bool arriba}) =>
    (arriba ? AlturaHoja.mitad : AlturaHoja.tercio).alto(
      pantalla: tamano.height,
      disponible: tamano.height,
      escala: TextScaler.linear(escala),
    );

/// Monta la hoja con las visitas de [e]. Con [enElMapa] va dentro del alto real que le da el mapa
/// (con el asa de 48 dp arriba); si no, en una pantalla entera.
Future<Montaje491> montar491(
  WidgetTester tester,
  Estado491 e, {
  double escala = 1,
  Size tamano = telefonoChico,
  bool enElMapa = true,
  List<ItemAgenda>? items,
  bool? arriba,
  bool conDetalle = true,
  bool conAgendar = true,
  FutureOr<Object?> Function(String agendaId)? detalle,
  FutureOr<Object?> Function()? agendar,
  List<Override> overrides = const [],
  ConsultaAgendaFalsa? repo,
}) async {
  await cargarFuentes(tester);
  final r = repo ?? ConsultaAgendaFalsa(items ?? itemsDe491(e));
  if (e == Estado491.error || e == Estado491.errorArriba) r.error ??= StateError('boom');
  if (e == Estado491.cargando) r.congelada = true;
  final m = Montaje491(r);
  final sinDestinos = e == Estado491.sinDestinos;
  final estaArriba = arriba ?? e.arriba;
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final item = switch (e) {
    Estado491.baja => itemDeLaHoja(baja: DateTime.utc(2026, 10, 1)),
    Estado491.edificio => itemDeLaHoja(tipo: TipoUbicacion.edificio),
    _ => itemDeLaHoja(),
  };
  final hoja = HojaCasa(
    item: item,
    ahora: ahoraLista,
    alCerrar: () => m.cierres.add(m.cierres.length),
    arriba: estaArriba,
    colportorId: 'col-1',
  );
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...overridesHojaCasa(registrarVisita: m.visitas.add, agendas: r),
        abrirDetalleDeAgendaProvider.overrideWithValue(
          conDetalle && !sinDestinos
              ? (id) async {
                  m.detalles.add(id);
                  return detalle?.call(id);
                }
              : null,
        ),
        agendarDesdeLaAgendaProvider.overrideWithValue(
          conAgendar && !sinDestinos
              ? () async {
                  m.agendar++;
                  return agendar?.call();
                }
              : null,
        ),
        ...overrides,
      ],
      child: RepaintBoundary(
        key: raiz491,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Scaffold(
            backgroundColor: const Color(0xFFEDEBE4),
            body: enElMapa
                ? Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      key: const Key('qa491_marco'),
                      height: altoDeLaHoja(tamano, escala, arriba: estaArriba),
                      color: Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AlturaHoja.altoAsa),
                          Expanded(child: hoja),
                        ],
                      ),
                    ),
                  )
                : SafeArea(
                    child: Align(alignment: Alignment.topCenter, child: hoja),
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return m;
}

/// Cada test termina desmontando la hoja.
void probar491(
  String descripcion,
  Future<void> Function(WidgetTester tester) cuerpo, {
  bool? skip,
}) {
  testWidgets(descripcion, (tester) async {
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: skip);
}

/// El marco (la hoja con su alto real) o, si no hay, la pantalla.
Rect marco491(WidgetTester tester) {
  final f = find.byKey(const Key('qa491_marco'));
  if (f.evaluate().isNotEmpty) return tester.getRect(f);
  return tester.view.physicalSize.topLeft(Offset.zero) & tester.view.physicalSize;
}

/// El área donde el usuario ve la hoja sin desplazar: bajo el asa.
Rect visibleDeLaHoja(WidgetTester tester) {
  final m = marco491(tester);
  return Rect.fromLTRB(m.left, m.top + AlturaHoja.altoAsa, m.right, m.bottom);
}

Finder get scrollDeLaHoja =>
    find.descendant(of: find.byType(HojaCasa), matching: find.byType(Scrollable));

/// Sube la hoja hasta el principio.
Future<void> alPrincipio(WidgetTester tester) async {
  final s = tester.state<ScrollableState>(scrollDeLaHoja.first);
  s.position.jumpTo(0);
  await tester.pump();
}

/// Baja la hoja hasta el final.
Future<void> alFinal491(WidgetTester tester) async {
  final s = tester.state<ScrollableState>(scrollDeLaHoja.first);
  s.position.jumpTo(s.position.maxScrollExtent);
  await tester.pump();
}

/// ¿El [f] está entero dentro de lo que se ve de la hoja ahora?
bool estaALaVista(WidgetTester tester, Finder f) {
  final r = tester.getRect(f.first);
  final v = visibleDeLaHoja(tester);
  return r.top >= v.top - 0.5 && r.bottom <= v.bottom + 0.5;
}

/// Una captura PNG en `.dart_tool/qa_capturas/491_<nombre>.png`.
Future<void> capturar491(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz491));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/491_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

String sufijo491(Size t, double escala) =>
    '${t.width.toInt()}_${escala.toString().replaceAll('.', '')}';
