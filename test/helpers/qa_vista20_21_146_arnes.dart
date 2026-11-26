// Arnés de los tests de QA de las vistas 20 y 21 (HU-JOR-003, #146): «Hoy» con el interruptor «¿Te acompañó
// alguien?» y el cierre «Jornada cerrada» (21J·03), con el repositorio en memoria del implementador y los
// estados armados a un paso: cada estado de la vista es una función `Future<void> Function(WidgetTester)`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/campanias_inscriptas_providers.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/data/repositories/fakes/acompaniamiento_repository_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/acompaniante.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/tendencia_de_la_jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/repositories/acompaniamiento_repository.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/resumen_jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/acompaniamiento_providers.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:dartz/dartz.dart' show Either, Unit;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

final sesion146 = Sesion(
  usuarioId: 'col-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token',
  expiraEn: DateTime.utc(2030),
);

final ahora146 = DateTime(2026, 11, 20, 14, 35, 20);
final inicio146 = DateTime(2026, 11, 20, 8, 10);

const marta146 = CoordinadorDeCampania(usuarioId: 'u-marta', nombre: 'Marta', apellido: 'Pérez');
const daniel146 = CoordinadorDeCampania(usuarioId: 'u-daniel', nombre: 'Daniel', apellido: 'Ruiz');

/// Tamaños lógicos de la matriz de QA.
const telefonoChico146 = Size(360, 640);
const telefonoGrande146 = Size(412, 915);

Override campania146() => campaniasInscriptasProvider('col-1').overrideWith(
  (ref) => Stream.value(const [
    CampaniaInscripta(
      campaniaId: 'cam-1',
      nombre: 'Verano',
      fechaInicio: '2026-11-01',
      fechaFin: '2026-11-30',
    ),
  ]),
);

Jornada jornada146({DateTime? fin}) => Jornada(
  id: 'jor-1',
  colportorId: 'col-1',
  inicio: inicio146,
  fin: fin,
  auditoria: Auditoria(createdAt: inicio146, updatedAt: inicio146, createdBy: 'col-1'),
);

final raiz146 = GlobalKey();

/// Escala de texto que el test puede subir a mitad de camino.
final class Escala146 {
  Escala146([this.valor = 1]);
  double valor;
}

void fijarPantalla146(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home, Escala146 escala) => MaterialApp(
  theme: temaClaro(),
  builder: (context, child) => RepaintBoundary(
    key: raiz146,
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala.valor)),
      child: child!,
    ),
  ),
  home: home,
);

/// «Hoy» con la jornada en curso (20J·01 a 20J·07).
Future<void> montarHoy146(
  WidgetTester tester,
  AcompaniamientoRepository repo, {
  Size tamano = telefonoGrande146,
  Escala146? escala,
  bool conCampania = true,
  List<Override> extra = const [],
  Jornada? jornada,
}) async {
  fijarPantalla146(tester, tamano);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(
          JornadaLocalDataSourceEnMemoria(
            iniciales: [JornadaModel.fromEntity(jornada ?? jornada146())],
          ),
        ),
        relojJornadaProvider.overrideWithValue(() => ahora146),
        acompaniamientoRepositoryProvider.overrideWithValue(repo),
        if (conCampania) campania146(),
        ...extra,
      ],
      child: _app(Scaffold(body: JornadaPage(sesion: sesion146)), escala ?? Escala146()),
    ),
  );
  await tester.pumpAndSettle();
}

/// El cierre «Jornada cerrada» (21J·03), empujado sobre otra ruta como lo hace `JornadaPage`.
Future<void> montarResumen146(
  WidgetTester tester,
  AcompaniamientoRepository repo, {
  Size tamano = telefonoGrande146,
  Escala146? escala,
  bool conCampania = true,
  List<Override> extra = const [],
}) async {
  fijarPantalla146(tester, tamano);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        acompaniamientoRepositoryProvider.overrideWithValue(repo),
        if (conCampania) campania146(),
        ...extra,
      ],
      child: _app(
        ResumenJornadaPage(
          jornada: jornada146(fin: inicio146.add(const Duration(hours: 6, minutes: 25))),
        ),
        escala ?? Escala146(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder interruptor146() => find.byKey(const Key('acompaniamiento_interruptor'));
Finder cambiar146() => find.byKey(const Key('acompaniamiento_cambiar'));
Finder fila146(String usuarioId) => find.byKey(Key('acompaniante_$usuarioId'));
Finder listo146() => find.byKey(const Key('hoja_acompaniantes_listo'));
Finder reintentar146() => find.byKey(const Key('acompaniamiento_reintentar'));

Future<void> abrirHoja146(WidgetTester tester) async {
  final destino = interruptor146().evaluate().isNotEmpty ? interruptor146() : cambiar146();
  await tester.ensureVisible(destino);
  await tester.tap(destino);
  await tester.pumpAndSettle();
}

Future<void> marcarYListo146(WidgetTester tester, List<String> ids) async {
  for (final id in ids) {
    await tester.ensureVisible(fila146(id));
    await tester.tap(fila146(id));
    await tester.pump();
  }
  await tester.ensureVisible(listo146());
  await tester.tap(listo146());
  await tester.pumpAndSettle();
}

AcompaniamientoRepositoryEnMemoria repoCon146({
  List<CoordinadorDeCampania> lista = const [marta146, daniel146],
  TendenciaDeLaJornada? tendencia = const TendenciaDeLaJornada(
    casasVisitadas: 14,
    ventas: 2,
    casasVisitadasAntes: 11,
    ventasAntes: 3,
  ),
}) => AcompaniamientoRepositoryEnMemoria(lista: lista, tendencia: tendencia);

/// Deja a [ids] ya guardados en la jornada de las pruebas.
Future<void> guardarDe146(AcompaniamientoRepositoryEnMemoria repo, List<String> ids) async {
  await repo.guardar(jornadaId: 'jor-1', colportorId: 'col-1', usuarioIds: ids.toSet());
  repo.pedidos.clear();
}

/// Los estados de la vista, cada uno armado desde cero: nombre → cómo llegar.
final Map<String, Future<void> Function(WidgetTester, Size, double)> estados146 = {
  '20J01_sin_acompanante': (t, tam, esc) async {
    await montarHoy146(t, repoCon146(), tamano: tam, escala: Escala146(esc));
  },
  '20J02_hoja_elegir': (t, tam, esc) async {
    await montarHoy146(t, repoCon146(), tamano: tam, escala: Escala146(esc));
    await abrirHoja146(t);
  },
  '20J03_tarjeta_uno': (t, tam, esc) async {
    final repo = repoCon146();
    await guardarDe146(repo, ['u-marta']);
    await montarHoy146(t, repo, tamano: tam, escala: Escala146(esc));
  },
  '20J03_tarjeta_dos': (t, tam, esc) async {
    final repo = repoCon146();
    await guardarDe146(repo, ['u-marta', 'u-daniel']);
    await montarHoy146(t, repo, tamano: tam, escala: Escala146(esc));
  },
  '20J04_hoja_cambiar_o_quitar': (t, tam, esc) async {
    final repo = repoCon146();
    await guardarDe146(repo, ['u-marta']);
    await montarHoy146(t, repo, tamano: tam, escala: Escala146(esc));
    await abrirHoja146(t);
  },
  '20J05_hoja_lista_vacia': (t, tam, esc) async {
    await montarHoy146(
      t,
      repoCon146(lista: const []),
      tamano: tam,
      escala: Escala146(esc),
    );
    await abrirHoja146(t);
  },
  '20J07_error_al_guardar': (t, tam, esc) async {
    final repo = repoCon146()..fallas = 1;
    await montarHoy146(t, repo, tamano: tam, escala: Escala146(esc));
    await abrirHoja146(t);
    await marcarYListo146(t, ['u-marta']);
  },
  '20J_guardando': (t, tam, esc) async {
    final repo = repoCon146()..compuerta = Completer<void>();
    await montarHoy146(t, repo, tamano: tam, escala: Escala146(esc));
    await abrirHoja146(t);
    await tester146Pump(t, () => marcarYListo146(t, ['u-marta']));
  },
  '21J03_cerrada_nadie': (t, tam, esc) async {
    await montarResumen146(t, repoCon146(), tamano: tam, escala: Escala146(esc));
  },
  '21J03_cerrada_dos': (t, tam, esc) async {
    final repo = repoCon146();
    await guardarDe146(repo, ['u-marta', 'u-daniel']);
    await montarResumen146(t, repo, tamano: tam, escala: Escala146(esc));
  },
  '21J04_cerrada_primera': (t, tam, esc) async {
    final repo = repoCon146(tendencia: const TendenciaDeLaJornada(casasVisitadas: 14, ventas: 2));
    await guardarDe146(repo, ['u-marta']);
    await montarResumen146(t, repo, tamano: tam, escala: Escala146(esc));
  },
};

/// Corre [accion] sin esperar a que se asiente (un guardado con compuerta nunca termina solo).
Future<void> tester146Pump(WidgetTester tester, Future<void> Function() accion) async {
  try {
    await accion();
  } on Object {
    // `pumpAndSettle` no termina con el guardado colgado: lo que se ve ya está armado.
  }
  await tester.pump(const Duration(milliseconds: 300));
}

/// Carga las fuentes del proyecto y los íconos de Material (sin ellos `flutter_test` pinta cajas).
Future<void> cargarFuentes146(WidgetTester tester) async {
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
}

/// Una captura PNG en `.dart_tool/qa_capturas/` (gitignored): nunca se commitea.
Future<void> capturar146(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz146));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/146_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Lo que tiene que haber en pantalla para decir que se llegó a cada estado de [estados146].
final Map<String, Finder Function()> esperado146 = {
  '20J01_sin_acompanante': () => interruptor146(),
  '20J02_hoja_elegir': () => fila146('u-marta'),
  '20J03_tarjeta_uno': () => find.byKey(const Key('acompaniante_tarjeta_u-marta')),
  '20J03_tarjeta_dos': () => find.byKey(const Key('acompaniante_tarjeta_u-daniel')),
  '20J04_hoja_cambiar_o_quitar': () => find.byKey(const Key('hoja_acompaniantes_nadie')),
  '20J05_hoja_lista_vacia': () => find.byKey(const Key('hoja_acompaniantes_vacia')),
  '20J07_error_al_guardar': () => find.byKey(const Key('acompaniamiento_error')),
  '20J_guardando': () => find.text('Guardando…'),
  '21J03_cerrada_nadie': () => find.byKey(const Key('jornada_resumen_aviso_acompanio')),
  '21J03_cerrada_dos': () => find.byKey(const Key('jornada_resumen_acompanio_quienes')),
  '21J04_cerrada_primera': () => find.byKey(const Key('jornada_resumen_acompanio_quienes')),
};

/// Un repositorio cuya lista de coordinadores nunca llega (hoja «cargando»); lo demás es el de memoria.
final class RepoListaColgada146 implements AcompaniamientoRepository {
  final _real = AcompaniamientoRepositoryEnMemoria();
  final _colgada = StreamController<List<CoordinadorDeCampania>>();

  @override
  Stream<List<CoordinadorDeCampania>> observarLista({
    required String colportorId,
    Set<String>? campaniaIds,
  }) => _colgada.stream;

  @override
  Stream<List<Acompaniante>> observarDe(String jornadaId) => _real.observarDe(jornadaId);

  @override
  Future<Either<Failure, Unit>> guardar({
    required String jornadaId,
    required String colportorId,
    required Set<String> usuarioIds,
  }) => _real.guardar(jornadaId: jornadaId, colportorId: colportorId, usuarioIds: usuarioIds);

  @override
  Stream<TendenciaDeLaJornada?> observarTendencia({
    required String colportorId,
    required String jornadaId,
    required DateTime inicio,
    DateTime? fin,
    ({String desde, String? hasta})? campania,
  }) => _real.observarTendencia(
    colportorId: colportorId,
    jornadaId: jornadaId,
    inicio: inicio,
    fin: fin,
    campania: campania,
  );
}
