// Arnés de los tests de QA de la pestaña «Agenda» (vista 23B, HU-VIS-002, #148): monta `AgendaPage`
// con las fuentes reales del proyecto (sin ellas `flutter_test` pinta cajas Ahem y las medidas de
// layout mienten), un reloj fijo y cada estado del canvas (23B·01 a 23B·09, la hoja «Estado», las
// atrasadas y las cerradas). Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a
// `.dart_tool/qa_capturas/` (gitignored: nunca se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'agenda_items_falsos.dart';

const conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Los hallazgos de la QA, con `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
const verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// Las fuentes reales: `false` en el archivo de contraste (con ellas `textContrastGuideline` da
/// falsos negativos: lee el fondo de una captura con glifos reales).
bool usarFuentesReales = true;

/// Los teléfonos de la matriz de QA.
const telefonoChico = Size(360, 640);
const telefonoGrande = Size(412, 915);
const tamanos = [telefonoChico, telefonoGrande];
const escalas = [1.0, 2.0];

/// Miércoles 28/10/2026, 10:00 (hora local).
final base = DateTime(2026, 10, 28, 10);

final raiz = GlobalKey();

var _fuentesCargadas = false;

Future<void> cargarFuentes(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final bytes = iconos.readAsBytesSync();
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await cargador.load();
        break;
      }
    }
  });
  _fuentesCargadas = true;
}

/// Un reloj que el test mueve a mano.
final class Reloj {
  Reloj(this.ahora);
  DateTime ahora;
  DateTime leer() => ahora;
}

/// Los destinos de afuera, con registro de cuántas veces se los llamó.
final class Destinos {
  final detalle = <String>[];
  final registrar = <ContextoDeVisita>[];
  var agendar = 0;
}

/// Monta [AgendaPage] sola, con todos los destinos disponibles (el peor caso: todo se ve).
Future<ValueNotifier<bool>> montar(
  WidgetTester tester,
  ConsultaAgendaFalsa repo, {
  Reloj? reloj,
  bool activa = true,
  Destinos? destinos,
  List<Override> overrides = const [],
  double escala = 1,
  Size tamano = telefonoChico,
  bool conDestinos = true,
}) async {
  await cargarFuentes(tester);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final d = destinos ?? Destinos();
  final visible = ValueNotifier<bool>(activa);
  final r = reloj ?? Reloj(base);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consultaAgendaRepositoryProvider.overrideWithValue(repo),
        relojAgendaProvider.overrideWithValue(r.leer),
        if (conDestinos) ...[
          abrirDetalleDeAgendaProvider.overrideWithValue((id) async {
            d.detalle.add(id);
            return null;
          }),
          registrarVisitaDesdeLaCasaProvider.overrideWithValue((contexto) async {
            d.registrar.add(contexto);
            return true;
          }),
          agendarDesdeLaAgendaProvider.overrideWithValue(() async {
            d.agendar++;
            return true;
          }),
        ],
        ...overrides,
      ],
      child: RepaintBoundary(
        key: raiz,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Scaffold(
            body: SafeArea(
              child: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (_, activa, _) => AgendaPage(colportorId: 'col-1', activa: activa),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await asentar(tester);
  return visible;
}

Future<void> asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Cada test termina desmontando la pantalla: el temporizador del minuto se cancela en `dispose`.
void probar(String descripcion, Future<void> Function(WidgetTester tester) cuerpo, {bool? skip}) {
  testWidgets(descripcion, (tester) async {
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: skip);
}

ItemAgenda entrevista(String id, DateTime cuando, {String nombre = 'Ana'}) =>
    itemAgenda(id, cuando, nombre: nombre);

ItemAgenda cobranza(String id, DateTime cuando, {String nombre = 'Luis'}) => itemAgenda(
  id,
  cuando,
  nombre: nombre,
  tipo: TipoAgenda.cobranza,
  calle: 'Rivera',
  numero: '77',
);

/// Cada artboard del canvas 23B (más las atrasadas y las cerradas, que el canvas no dibuja).
enum Estado148 {
  e01('23B·01 hoy y próximos 7 días'),
  e02('23B·02 hora vencida'),
  e03('23B·03 filtro cobranzas'),
  e04('23B·04 hoja Estado'),
  e05('23B·05 canceladas'),
  e06('23B·06 cargando'),
  e07('23B·07 sin agendas'),
  e08('23B·08 filtros sin resultados'),
  e09('23B·09 error de lectura'),
  atrasadas('ATRASADAS (P3)'),
  cerradas('cumplida, no cumplida y cancelada (filtro Todas)'),
  larga('textos larguísimos y edificio con depto'),
  muchas('30 agendas en un día');

  const Estado148(this.rotulo);
  final String rotulo;

  String get id => name;
}

/// Las agendas de cada estado.
List<ItemAgenda> itemsDe(Estado148 e) {
  final hoy = DateTime(2026, 10, 28);
  switch (e) {
    case Estado148.e01:
    case Estado148.e03:
      return [
        cobranza('c1', hoy.add(const Duration(hours: 16)), nombre: 'María'),
        entrevista('e1', hoy.add(const Duration(hours: 17, minutes: 30)), nombre: 'Jorge'),
        entrevista('e2', DateTime(2026, 10, 29, 10), nombre: 'Ana'),
        cobranza('c2', DateTime(2026, 10, 29, 12, 30), nombre: 'Pedro'),
        entrevista('e3', DateTime(2026, 10, 31, 15), nombre: 'Laura'),
      ];
    case Estado148.e02:
      return [
        entrevista('v1', hoy.add(const Duration(hours: 9, minutes: 30)), nombre: 'Jorge'),
        cobranza('c1', hoy.add(const Duration(hours: 16)), nombre: 'María'),
      ];
    case Estado148.e04:
      return [cobranza('c1', hoy.add(const Duration(hours: 16)), nombre: 'María')];
    case Estado148.e05:
      return [
        itemAgenda(
          'x1',
          DateTime(2026, 10, 29, 18),
          nombre: 'Raúl',
          estado: EstadoAgenda.cancelada,
          actualizada: DateTime(2026, 10, 22, 12),
        ),
        entrevista('e1', DateTime(2026, 10, 29, 19), nombre: 'Ana'),
      ];
    case Estado148.e06:
    case Estado148.e09:
    case Estado148.e07:
    case Estado148.e08:
      return const [];
    case Estado148.atrasadas:
      return [
        entrevista('a1', DateTime(2026, 10, 25, 11), nombre: 'Elena'),
        entrevista('a2', DateTime(2026, 10, 27, 16, 30), nombre: 'Raúl'),
        cobranza('a3', DateTime(2026, 10, 27, 18), nombre: 'Marta'),
        entrevista('h1', hoy.add(const Duration(hours: 9)), nombre: 'Jorge'),
        entrevista('m1', DateTime(2026, 10, 29, 9), nombre: 'Ana'),
      ];
    case Estado148.cerradas:
      return [
        itemAgenda(
          'k1',
          hoy.add(const Duration(hours: 8)),
          nombre: 'Elena',
          estado: EstadoAgenda.cumplida,
          actualizada: DateTime(2026, 10, 28, 8, 30),
        ),
        itemAgenda(
          'k2',
          hoy.add(const Duration(hours: 9)),
          nombre: 'Raúl',
          estado: EstadoAgenda.noCumplida,
          actualizada: DateTime(2026, 10, 28, 9, 40),
        ),
        itemAgenda(
          'k3',
          hoy.add(const Duration(hours: 13)),
          nombre: 'Marta',
          estado: EstadoAgenda.cancelada,
          actualizada: DateTime(2026, 10, 22, 12),
        ),
        entrevista('p1', hoy.add(const Duration(hours: 15)), nombre: 'Ana'),
      ];
    case Estado148.larga:
      return [
        itemAgenda(
          'l1',
          hoy.add(const Duration(hours: 14)),
          nombre: 'María de los Ángeles Fernández de la Cruz y Benítez 🌟',
          apellido: 'Rodríguez-Sánchez Pereira de Albuquerque',
          calle: 'Avenida General Don José Gervasio Artigas y Carlos María Ramírez',
          numero: '1234 bis esquina Bulevar',
          tipoUbicacion: TipoUbicacion.edificio,
          numeroDepto: '1204-B torre norte',
        ),
        itemAgenda(
          'l2',
          hoy.add(const Duration(hours: 18)),
          nombre: null,
          apellido: null,
          calle: 'Calle sin nombre muy muy larga que no entra en una línea',
          numero: '99999',
          tipo: TipoAgenda.cobranza,
        ),
      ];
    case Estado148.muchas:
      return [
        for (var i = 0; i < 30; i++)
          entrevista(
            'm$i',
            hoy.add(Duration(hours: 8 + i ~/ 4, minutes: (i % 4) * 15)),
            nombre: 'Persona $i',
          ),
      ];
  }
}

/// Lleva la pantalla al estado [e]: monta con sus datos y hace los toques que el estado pide.
Future<ConsultaAgendaFalsa> llegarA(
  WidgetTester tester,
  Estado148 e, {
  double escala = 1,
  Size tamano = telefonoChico,
  Destinos? destinos,
}) async {
  final repo = ConsultaAgendaFalsa(itemsDe(e));
  if (e == Estado148.e06) repo.congelada = true;
  if (e == Estado148.e09) repo.error = StateError('boom');
  await montar(tester, repo, escala: escala, tamano: tamano, destinos: destinos);
  switch (e) {
    case Estado148.e03:
      await tester.tap(find.text('Cobranzas'));
      await asentar(tester);
    case Estado148.e04:
      await tester.tap(find.text('Pendientes ▾'));
      await tester.pumpAndSettle();
    case Estado148.e05:
      await aplicarEstado(tester, 'Canceladas');
    case Estado148.e08:
      await tester.tap(find.text('Cobranzas'));
      await asentar(tester);
      await aplicarEstado(tester, 'Canceladas');
    case Estado148.cerradas:
      await aplicarEstado(tester, 'Todas');
    default:
      break;
  }
  return repo;
}

/// Abre la hoja «Estado», elige [opcion] y toca «Aplicar».
Future<void> aplicarEstado(WidgetTester tester, String opcion) async {
  await tester.tap(find.textContaining('▾'));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(opcion)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('agenda_aplicar_estado')));
  await tester.pumpAndSettle();
}

/// Una captura PNG de la pantalla en `.dart_tool/qa_capturas/148_<nombre>.png`.
Future<void> capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/148_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Contraste WCAG entre dos colores opacos.
double contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final oscuro = la > lb ? lb : la;
  return (claro + 0.05) / (oscuro + 0.05);
}

/// Ningún texto visible se sale de la pantalla por los costados.
void expectSinTextoFueraDeLosCostados(WidgetTester tester, Size tamano) {
  for (final e in find.byType(RichText).evaluate()) {
    final render = e.renderObject;
    if (render is! RenderBox || !render.attached || !render.hasSize) continue;
    final r = render.localToGlobal(Offset.zero) & render.size;
    expect(
      r.left >= -0.5 && r.right <= tamano.width + 0.5,
      isTrue,
      reason: 'un texto se sale de la pantalla: ${(e.widget as RichText).text.toPlainText()} $r',
    );
  }
}
