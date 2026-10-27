// Arnés del QA de «Agendar una visita» (vista 23 A, #408): monta la pantalla con el repositorio que se
// le pase (el que registra, o el real sobre Drift en memoria), con las fuentes reales del proyecto, y
// sabe llegar a cada estado de los ocho artboards (23A·01 a 23A·08) y a los que el canvas no dibuja.
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/agenda_repository.dart';
import 'package:colportores_mobile/features/agenda/presentation/flujo_agendar_visita.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/hoja_con_quien_arnes.dart' show ObservadorDeRutas;
import 'agendar_visita_arnes.dart';
import 'notificaciones_arnes.dart' show Telefono;
import 'persona_falsos.dart';

const conCapturas408 = bool.fromEnvironment('QA_CAPTURAS');

/// `false` solo para las guías de contraste de Flutter (con las fuentes reales dan falsos negativos).
bool usarFuentesReales408 = true;
bool _fuentesCargadas = false;

Future<void> cargarFuentes408(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales408) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'];
    final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (raiz != null && iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
  });
  _fuentesCargadas = true;
}

const chico = Size(360, 640);
const grande = Size(412, 915);

final boton408 = find.byKey(ClavesAgendarVisita.botonAgendar);
final campo408 = find.byKey(ClavesAgendarVisita.campoDiaYHora);

/// Lo que el test necesita de la pantalla montada.
final class Montaje408 {
  Montaje408({
    required this.repo,
    required this.fake,
    required this.telefono,
    required this.rutas,
    required this.ahora,
  });

  final AgendaRepository repo;

  /// El repositorio que registra, o `null` si se montó con uno real.
  final AgendaRepositorioQueAgenda? fake;
  final Telefono telefono;
  final ObservadorDeRutas rutas;
  DateTime ahora;
  final resultados = <bool>[];
  var abiertas = 0;
}

/// Monta la pantalla igual que `montarAgendar`, pero con el repositorio de agenda que se pase.
Future<Montaje408> montar408(
  WidgetTester tester, {
  AgendaRepository? repoReal,
  AgendaRepositorioQueAgenda? fake,
  List<PersonaDelEspacio>? personas,
  EspacioConUbicacion? casa,
  bool sinCasa = false,
  Failure? fallaDeCasa,
  Completer<void>? casaDemorada,
  String? espacioPersonaId = 'ep-p1',
  TipoAgenda tipo = TipoAgenda.entrevista,
  DateTime? ahora,
  bool permisoConcedido = true,
  EstadoSistemaNotificaciones estadoSistema = EstadoSistemaNotificaciones.activadas,
  double escala = 1,
  Size tamano = chico,
  bool abrir = true,
  bool conTemaOscuro = false,
}) async {
  await cargarFuentes408(tester);
  final registra = repoReal == null ? (fake ?? AgendaRepositorioQueAgenda()) : null;
  final m = Montaje408(
    repo: repoReal ?? registra!,
    fake: registra,
    telefono: Telefono(estado: estadoSistema)..recordatorios.permisoConcedido = permisoConcedido,
    rutas: ObservadorDeRutas(),
    ahora: ahora ?? ahoraDelCanvas(),
  );
  var n = 0;
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final personasRepo = PersonaRepositorioFalso()..sembrar(personas ?? [mariaFernandez]);
  final lugar = sinCasa ? null : (casa ?? casaMataojo());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agendaRepositoryProvider.overrideWithValue(m.repo),
        generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
        relojVisitaProvider.overrideWithValue(() => m.ahora),
        ...m.telefono.overrides,
        personaRepositoryProvider.overrideWithValue(personasRepo),
        espacioRepositoryProvider.overrideWithValue(
          casaDemorada != null
              ? EspacioRepositorioLento(lugar, casaDemorada)
              : EspacioRepositorioParaPersonas(lugar, falla: fallaDeCasa),
        ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        navigatorObservers: [m.rutas],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  m.abiertas += 1;
                  final r = await FlujoAgendarVisita.abrir(
                    context,
                    espacioId: 'esp-1',
                    espacioPersonaId: espacioPersonaId,
                    colportorId: 'col-1',
                    tipo: tipo,
                  );
                  m.resultados.add(r);
                },
                child: const Text('abrir agenda'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirAgendar(tester);
  return m;
}

Future<void> tocar408(WidgetTester tester, Finder f, {int fotogramas = 12}) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await asentarAgendar(tester, fotogramas);
}

/// Elige hoy a las 11:00 (el reloj del canvas marca las 14:35, así que ya pasó).
Future<void> hoyALas11(WidgetTester tester) async {
  await tocar408(tester, campo408);
  await tocar408(tester, find.byKey(ClavesAgendarVisita.dia(0)));
  for (var i = 0; i < 12; i++) {
    await tester.tap(find.byKey(ClavesAgendarVisita.hojaMas));
    await tester.pump();
  }
  await tocar408(tester, find.byKey(ClavesAgendarVisita.hojaListo));
}

/// Los estados que una persona puede alcanzar en «Agendar visita».
enum Estado408 {
  e01Entrevista('23A·01 entrevista'),
  e01Cobranza('23A·01 cobranza'),
  e01SinPersona('23A·01 sin persona'),
  e02Hoja('23A·02 hoja día y hora'),
  e02OtroDia('23A·02 otro día elegido'),
  e03Campo('23A·03 campo con error'),
  e03Pregunta('23A·03 hoja «Esa hora ya pasó»'),
  e04Agendando('23A·04 agendando'),
  e06Error('23A·06 error al guardar'),
  e07SinPermiso('23A·07 sin permiso'),
  e07Ajustes('23A·07 permiso bloqueado'),
  e07YError('23A·07 + 23A·06'),
  e08SinConexion('23A·08 sin conexión'),
  cargandoCasa('cargando la casa'),
  errorDeLectura('error al leer la casa'),
  casaNoEsta('la casa ya no está');

  const Estado408(this.rotulo);
  final String rotulo;

  String get archivo => name;
}

/// Monta y lleva la pantalla al [estado].
Future<Montaje408> llegarA(
  WidgetTester tester,
  Estado408 estado, {
  Size tamano = chico,
  double escala = 1,
}) async {
  switch (estado) {
    case Estado408.e01Entrevista:
    case Estado408.e08SinConexion:
      return montar408(tester, tamano: tamano, escala: escala);
    case Estado408.e01Cobranza:
      return montar408(tester, tamano: tamano, escala: escala, tipo: TipoAgenda.cobranza);
    case Estado408.e01SinPersona:
      return montar408(tester, tamano: tamano, escala: escala, espacioPersonaId: null);
    case Estado408.e02Hoja:
      final m = await montar408(tester, tamano: tamano, escala: escala);
      await tocar408(tester, campo408);
      return m;
    case Estado408.e02OtroDia:
      final m = await montar408(tester, tamano: tamano, escala: escala);
      await tocar408(tester, campo408);
      await tocar408(tester, find.byKey(ClavesAgendarVisita.otroDia));
      await tocar408(tester, find.text('OK'));
      return m;
    case Estado408.e03Campo:
      final m = await montar408(tester, tamano: tamano, escala: escala);
      await hoyALas11(tester);
      return m;
    case Estado408.e03Pregunta:
      final m = await montar408(tester, tamano: tamano, escala: escala);
      await hoyALas11(tester);
      await tocar408(tester, boton408);
      return m;
    case Estado408.e04Agendando:
      final repo = AgendaRepositorioQueAgenda()..compuerta = Completer<void>();
      final m = await montar408(tester, tamano: tamano, escala: escala, fake: repo);
      await tester.tap(boton408);
      await tester.pump(const Duration(milliseconds: 50));
      return m;
    case Estado408.e06Error:
      final repo = AgendaRepositorioQueAgenda()..fallas.add(const FailureInesperado());
      final m = await montar408(tester, tamano: tamano, escala: escala, fake: repo);
      await tocar408(tester, boton408);
      return m;
    case Estado408.e07SinPermiso:
      return montar408(
        tester,
        tamano: tamano,
        escala: escala,
        permisoConcedido: false,
        estadoSistema: EstadoSistemaNotificaciones.apagadas,
      );
    case Estado408.e07Ajustes:
      final m = await montar408(
        tester,
        tamano: tamano,
        escala: escala,
        permisoConcedido: false,
        estadoSistema: EstadoSistemaNotificaciones.apagadas,
      );
      m.telefono.sistema.respuestaAlPedir = false;
      await tocar408(tester, find.byKey(ClavesAgendarVisita.accionNotificaciones));
      return m;
    case Estado408.e07YError:
      final repo = AgendaRepositorioQueAgenda()..fallas.add(const FailureInesperado());
      final m = await montar408(
        tester,
        tamano: tamano,
        escala: escala,
        fake: repo,
        permisoConcedido: false,
        estadoSistema: EstadoSistemaNotificaciones.apagadas,
      );
      await tocar408(tester, boton408);
      return m;
    case Estado408.cargandoCasa:
      return montar408(tester, tamano: tamano, escala: escala, casaDemorada: Completer<void>());
    case Estado408.errorDeLectura:
      return montar408(
        tester,
        tamano: tamano,
        escala: escala,
        fallaDeCasa: const FailureInesperado(),
      );
    case Estado408.casaNoEsta:
      return montar408(tester, tamano: tamano, escala: escala, sinCasa: true);
  }
}

/// La pantalla completa (incluidas las hojas) como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar408(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/408_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado408(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Lo que hay que tocar para que `ensureVisible` no falle por una hoja encima.
bool estaEnPantalla408(WidgetTester tester, Finder f) {
  final r = tester.getRect(f);
  final v = tester.view.physicalSize / tester.view.devicePixelRatio;
  return r.top >= 0 && r.left >= 0 && r.bottom <= v.height && r.right <= v.width;
}
