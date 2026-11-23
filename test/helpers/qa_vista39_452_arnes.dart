// Arnés del QA de «Edificio y sus deptos» (vista 39, #452): monta la hoja de la casa con un edificio, sus
// deptos y el repositorio en memoria de espacios, con las fuentes reales del proyecto, y sabe llegar a
// cada estado de N·04, N·06, C·09 y C·10 y a los que el canvas no dibuja. Las capturas solo se sacan con
// `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resumen_del_depto.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/deptos_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart'
    show AlturaHoja;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agenda_items_falsos.dart';
import 'espacios_falsos.dart';
import 'modificar_ubicacion_falsos.dart';
import 'persona_falsos.dart';

const conCapturas452 = bool.fromEnvironment('QA_CAPTURAS');

/// `false` solo para las guías de contraste de Flutter (con las fuentes reales dan falsos negativos).
bool usarFuentesReales452 = true;
bool _fuentesCargadas = false;

Future<void> cargarFuentes452(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales452) return;
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

const chico452 = Size(360, 640);
const grande452 = Size(412, 915);

const ubicacionId452 = 'ubi-1';

/// Los deptos del canvas (C·09), desordenados: la hoja los ordena por piso.
final d4A452 = espacioDe('d-4a', '4A', piso: '4', orden: 1);
final d1A452 = espacioDe('d-1a', '1A', piso: '1', orden: 2);
final d3B452 = espacioDe('d-3b', '3B', piso: '3', orden: 3);
final d2A452 = espacioDe('d-2a', '2A', piso: '2', orden: 4);

final ahora452 = hoyEspacios;

/// El resumen de los deptos del canvas: 1A no contestó ayer, 2A tiene una entrevista, 3B debe y 4A está
/// sin visita.
final resumenDelCanvas452 = <String, ResumenDelDepto>{
  'd-1a': ResumenDelDepto(
    estado: EstadoCasa.noContesto,
    ultimaVisita: ahora452.subtract(const Duration(days: 1)),
  ),
  'd-2a': ResumenDelDepto(
    estado: EstadoCasa.entrevistaAgendada,
    proximaEntrevista: ahora452.add(const Duration(days: 1)),
  ),
  'd-3b': ResumenDelDepto(estado: EstadoCasa.cobranzaPendiente),
  'd-4a': ResumenDelDepto(),
};

/// María Fernández, que vive en el 3B y debe $ 1.200 (C·10).
final PersonaDelEspacio maria452 = clienteDePersonas('p-maria', 'María', apellido: 'Fernández');

final class Montaje452 {
  Montaje452(this.repo, this.ubicacion, this.item);

  final EspacioRepoFalso repo;
  final Ubicacion ubicacion;
  final ItemListaUbicacion item;
  final lecturas = <ClaveDeLaCasa>[];
  final visitas = <ContextoDeVisita>[];
  var cierres = 0;

  /// Lo que contesta «Registrar visita» (por defecto, `false`: se cerró «¿Qué pasó?» sin elegir).
  Object? salidaVisita = false;
  Completer<Object?>? esperaVisita;
  Object? lanzaVisita;

  /// El resumen de los deptos que lee la hoja (un `Stream` por lectura).
  Stream<Map<String, ResumenDelDepto>> Function() resumen = () => Stream.value(resumenDelCanvas452);

  /// El contexto de la casa que lee la hoja con un depto elegido (C·10).
  Stream<ContextoDeLaCasa> Function(String espacioId)? contextoDe;

  final atras = ValueNotifier<VoidCallback?>(null);
}

/// Monta la hoja de la casa con [tipo] y [espacios]. [altoHoja] limita el alto (la hoja a un tercio o a la
/// mitad de un mapa), sin él ocupa toda la pantalla.
Future<Montaje452> montar452(
  WidgetTester tester, {
  TipoUbicacion tipo = TipoUbicacion.edificio,
  List<Espacio>? espacios,
  bool recien = false,
  bool arriba = false,
  bool conRegistrar = true,
  bool conAtras = false,
  double escala = 1,
  Size tamano = chico452,
  double? metros = 35,
  DateTime? baja,
  String calle = 'Grecia',
  String numero = '3313',
  AlturaHoja? altura,
  String? colportorId = 'col-1',
  void Function(Montaje452 m)? antes,
}) async {
  await cargarFuentes452(tester);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final ubicacion = ubicacionGuardada(
    id: ubicacionId452,
    tipo: tipo,
    calle: calle,
    numero: numero,
    deBajaDesde: baja,
  );
  final item = ItemListaUbicacion(
    ubicacion: ubicacion,
    estado: EstadoCasa.cobranzaPendiente,
    distanciaMetros: metros,
  );
  final m = Montaje452(
    EspacioRepoFalso(ubicacion, espacios: espacios ?? [d4A452, d1A452, d3B452, d2A452]),
    ubicacion,
    item,
  );
  antes?.call(m);
  addTearDown(m.atras.dispose);
  var secuencia = 0;
  final escalador = TextScaler.linear(escala);
  Widget hoja = HojaCasa(
    item: item,
    ahora: ahora452,
    alCerrar: () => m.cierres++,
    colportorId: colportorId,
    arriba: arriba,
    recienRegistrada: recien,
    atras: conAtras ? m.atras : null,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consultaAgendaRepositoryProvider.overrideWithValue(ConsultaAgendaFalsa()),
        personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
        contextoDeLaCasaProvider.overrideWith((ref, clave) {
          m.lecturas.add(clave);
          final espacioId = clave.espacioId;
          if (espacioId != null && m.contextoDe != null) return m.contextoDe!(espacioId);
          return Stream.value(
            espacioId == null
                ? const ContextoDeLaCasa()
                : ContextoDeLaCasa(
                    espacioId: espacioId,
                    personas: espacioId == 'd-3b' ? [maria452] : const [],
                    saldosCentavos: const {'p-maria': 120000},
                  ),
          );
        }),
        registrarVisitaDesdeLaCasaProvider.overrideWithValue(
          conRegistrar
              ? (contexto) async {
                  m.visitas.add(contexto);
                  final lanza = m.lanzaVisita;
                  if (lanza != null) throw lanza;
                  final espera = m.esperaVisita;
                  if (espera != null) return espera.future;
                  return m.salidaVisita;
                }
              : null,
        ),
        espacioRepositoryProvider.overrideWithValue(m.repo),
        ubicacionRepositoryProvider.overrideWithValue(RepoEdicionFalso(ubicacion)),
        contadorPersonasEspacioProvider.overrideWithValue(ContadorPersonasFalso()),
        generadorIdEspacioProvider.overrideWithValue(() => 'nuevo-${++secuencia}'),
        relojEspaciosProvider.overrideWithValue(() => ahora452),
        resumenDeLosDeptosProvider.overrideWith((ref, clave) => m.resumen()),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: escalador),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              if (altura != null) {
                // Como en el mapa: una hoja blanca de un tercio o de la mitad, con el asa de 48 dp.
                final alto = altura.alto(
                  pantalla: tamano.height,
                  disponible: tamano.height - 56,
                  escala: escalador,
                );
                hoja = Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: alto,
                    child: Column(
                      children: [
                        const SizedBox(height: AlturaHoja.altoAsa),
                        Expanded(child: hoja),
                      ],
                    ),
                  ),
                );
              }
              return ColoredBox(color: Colors.white, child: hoja);
            },
          ),
        ),
      ),
    ),
  );
  await asentar452(tester);
  return m;
}

Future<void> asentar452(WidgetTester tester, [int veces = 6]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

String texto452(WidgetTester tester, Key clave) => tester.widget<Text>(find.byKey(clave)).data!;

Finder fila452(Espacio e) => find.byKey(ClavesDeptosDeLaCasa.fila(e.id));

/// Toca el depto [e] (lo trae a la vista antes) y deja que la hoja lo abra.
Future<void> tocarDepto452(WidgetTester tester, Espacio e) async {
  await tester.ensureVisible(fila452(e));
  await tester.pump();
  await tester.tap(fila452(e));
  await asentar452(tester);
}

/// La pantalla completa como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar452(WidgetTester tester, String nombre) async {
  if (!conCapturas452) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/452_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado452(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Los estados de la matriz: cada uno monta y deja la hoja lista.
enum Estado452 {
  n04('n04'),
  n04Vacio('n04_vacio'),
  n06('n06'),
  n06Vacio('n06_vacio'),
  c09('c09'),
  c09Vacio('c09_vacio'),
  c09Cargando('c09_cargando'),
  c09Error('c09_error'),
  c09Baja('c09_baja'),
  c09Lejos('c09_lejos'),
  c09SinResumen('c09_sin_resumen'),
  c09Negocio('c09_negocio'),
  c10('c10'),
  c10Baja('c10_baja'),
  c10Arriba('c10_arriba'),
  c10Error('c10_error'),
  c10Cargando('c10_cargando'),
  c10SinPersonas('c10_sin_personas');

  const Estado452(this.id);
  final String id;
}

/// Monta [estado] en [tamano] con [escala].
Future<Montaje452> llegarA452(
  WidgetTester tester,
  Estado452 estado, {
  Size tamano = chico452,
  double escala = 1,
  AlturaHoja? altura,
}) async {
  switch (estado) {
    case Estado452.n04:
      return montar452(
        tester,
        recien: true,
        espacios: [d1A452, d2A452],
        tamano: tamano,
        escala: escala,
        altura: altura,
      );
    case Estado452.n04Vacio:
      return montar452(
        tester,
        recien: true,
        espacios: const [],
        tamano: tamano,
        escala: escala,
        altura: altura,
      );
    case Estado452.n06:
    case Estado452.n06Vacio:
      final m = await montar452(
        tester,
        recien: true,
        espacios: estado == Estado452.n06 ? [d1A452, d2A452, d3B452] : const [],
        tamano: tamano,
        escala: escala,
        altura: altura,
      );
      await tester.ensureVisible(find.byKey(ClavesDeptosDeLaCasa.seguir));
      await tester.pump();
      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.seguir));
      await asentar452(tester);
      return m;
    case Estado452.c09:
      return montar452(tester, tamano: tamano, escala: escala, altura: altura);
    case Estado452.c09Vacio:
      return montar452(tester, espacios: const [], tamano: tamano, escala: escala, altura: altura);
    case Estado452.c09Cargando:
      final espera = Completer<void>();
      return _sinAsentar(
        tester,
        tamano,
        escala,
        altura,
        (m) => m.repo.esperaAlListar = espera,
        espera,
      );
    case Estado452.c09Error:
      return montar452(
        tester,
        tamano: tamano,
        escala: escala,
        altura: altura,
        antes: (m) => m.repo.fallaAlListar = const FailureInesperado(causa: 'sin DB'),
      );
    case Estado452.c09Baja:
      return montar452(
        tester,
        baja: DateTime.utc(2026, 10, 18, 12),
        tamano: tamano,
        escala: escala,
        altura: altura,
      );
    case Estado452.c09Lejos:
      return montar452(tester, metros: 650, tamano: tamano, escala: escala, altura: altura);
    case Estado452.c09SinResumen:
      return montar452(
        tester,
        tamano: tamano,
        escala: escala,
        altura: altura,
        antes: (m) => m.resumen = () => Stream.error(StateError('sin DB')),
      );
    case Estado452.c09Negocio:
      return montar452(
        tester,
        tipo: TipoUbicacion.negocio,
        calle: 'Grecia',
        numero: '3310',
        espacios: [d1A452, d2A452],
        tamano: tamano,
        escala: escala,
        altura: altura,
      );
    case Estado452.c10:
      final m = await montar452(tester, tamano: tamano, escala: escala, altura: altura);
      await tocarDepto452(tester, d3B452);
      return m;
    case Estado452.c10SinPersonas:
      final m = await montar452(tester, tamano: tamano, escala: escala, altura: altura);
      await tocarDepto452(tester, d4A452);
      return m;
    case Estado452.c10Baja:
      final m = await montar452(
        tester,
        baja: DateTime.utc(2026, 10, 18, 12),
        tamano: tamano,
        escala: escala,
        altura: altura,
      );
      await tocarDepto452(tester, d3B452);
      return m;
    case Estado452.c10Arriba:
      final m = await montar452(
        tester,
        arriba: true,
        tamano: tamano,
        escala: escala,
        altura: altura,
      );
      await tocarDepto452(tester, d3B452);
      return m;
    case Estado452.c10Error:
      final m = await montar452(
        tester,
        tamano: tamano,
        escala: escala,
        altura: altura,
        antes: (m) => m.contextoDe = (id) => Stream<ContextoDeLaCasa>.error(StateError('sin DB')),
      );
      await tocarDepto452(tester, d3B452);
      return m;
    case Estado452.c10Cargando:
      final m = await montar452(
        tester,
        tamano: tamano,
        escala: escala,
        altura: altura,
        antes: (m) => m.contextoDe = (id) => StreamController<ContextoDeLaCasa>().stream,
      );
      await tocarDepto452(tester, d3B452);
      return m;
  }
}

Future<Montaje452> _sinAsentar(
  WidgetTester tester,
  Size tamano,
  double escala,
  AlturaHoja? altura,
  void Function(Montaje452 m) antes,
  Completer<void> espera,
) async {
  addTearDown(() {
    if (!espera.isCompleted) espera.complete();
  });
  return montar452(tester, tamano: tamano, escala: escala, altura: altura, antes: antes);
}
