// QA del PR #310 (issue #304, HU-UBI-004): con un solo departamento activo, un edificio pasa a Casa
// o Negocio sin bloqueo y el depto queda como el espacio de la casa, sin número (decisión de
// Cristian, 07/10, «Como el diseño»). Complementa a `modificar_ubicacion_page_test.dart` y a
// `modificar_ubicacion_qa_test.dart` con:
//  1. Las dos hojas nuevas (un depto y dos o más) con las guías de accesibilidad de Flutter a
//     360x640 y 412x915, con texto 100 % y 200 %, sin overflow. Capturas con
//     `--dart-define=QA_CAPTURAS=true` en `.dart_tool/qa_capturas/` (gitignored).
//  2. El rechazo tardío (aparece un 2.º depto entre abrir y guardar): la hoja no se contradice.
//  3. De punta a punta con la base real (pantalla, caso de uso, repositorio y Drift en memoria):
//     el espacio queda sin número, se encolan los dos cambios en orden y volver a Edificio no pisa nada.
//
// Los hallazgos de QA r1 (el aviso de bloqueo bajo el botón fijo a 200 % y el resumen viejo tras el
// rechazo) quedaron arreglados en la ronda final del PR: sus tests ya no van con `skip`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/mapa_base_falso.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

const _aviso2 = 'Esta ubicación tiene 2 espacios. Borralos o reubicalos primero.';
const _lineaCasa = 'El departamento 3B queda como el espacio de la casa, sin número.';
const _lineaNegocio = 'El departamento 3B queda como el espacio del negocio, sin número.';

/// Con las fuentes reales la guía de contraste de Flutter mide el borde suavizado de las letras
/// chicas y da falsos negativos; en el modo de capturas no corre (en el CI sí, con la fuente de prueba).
Future<void> _cargarFuentes(WidgetTester tester) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final loader = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
    // Los íconos de Material: sin esto flutter_test los pinta como cuadrados.
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final icons = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (icons.existsSync()) {
        final bytes = icons.readAsBytesSync();
        final loader = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
        break;
      }
    }
  });
}

final _raizCaptura = GlobalKey();

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raizCaptura));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/310_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<void> _guias(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (!_conCapturas) await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// La pantalla que abre la edición y guarda cómo se cerró.
class _Anfitrion extends StatelessWidget {
  const _Anfitrion({required this.salidas});

  final List<SalidaModificarUbicacion?> salidas;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async => salidas.add(
            await ModificarUbicacionPage.abrir(context, colportorId: 'col-1', ubicacionId: 'ubi-1'),
          ),
          child: const Text('abrir'),
        ),
      ),
    );
  }
}

final class _Escenario {
  _Escenario(this.repo) : mapa = FabricaMapaFalsa();

  final UbicacionRepository repo;
  final FabricaMapaFalsa mapa;
  final salidas = <SalidaModificarUbicacion?>[];
}

Future<void> _asentar(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_Escenario> _montar(
  WidgetTester tester,
  UbicacionRepository repo, {
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await _cargarFuentes(tester);
  final e = _Escenario(repo);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesAlta(
        gps: GpsFalso(),
        geocodificador: GeocodificadorFalso(
          (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1250'),
        ),
        ciudades: CiudadesFalsas(),
        repo: repo,
        ahora: DateTime.utc(2026, 10, 2, 12),
        mapa: e.mapa,
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => RepaintBoundary(
          key: _raizCaptura,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
        ),
        home: _Anfitrion(salidas: e.salidas),
      ),
    ),
  );
  if (abrir) await _abrir(tester);
  return e;
}

Future<void> _abrir(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await _asentar(tester);
}

Future<void> _traer(WidgetTester tester, Finder f) async {
  await tester.pump();
  if (f.hitTestable().evaluate().isEmpty) {
    await Scrollable.ensureVisible(tester.element(f), alignment: .5);
    await tester.pump();
  }
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await _traer(tester, f);
  await tester.tap(f);
  await _asentar(tester);
}

Finder get _guardar => find.widgetWithText(FilledButton, TextosModificar.guardarCambios);
Finder get _guardandoBoton => find.widgetWithText(FilledButton, TextosModificar.guardando);
Finder get _cerrar => find.byTooltip('Cerrar');

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<FilledButton>(boton).onPressed != null;

RepoEdicionFalso _edificioFalso(int espacios, {String? numeroDepto}) => RepoEdicionFalso(
  ubicacionGuardada(tipo: TipoUbicacion.edificio),
  espacios: espacios,
  numeroDepto: numeroDepto,
);

const _tamanos = <(String, Size, double)>[
  ('360x640 a 100 %', Size(360, 640), 1.0),
  ('360x640 a 200 %', Size(360, 640), 2.0),
  ('412x915 a 100 %', Size(412, 915), 1.0),
  ('412x915 a 200 %', Size(412, 915), 2.0),
];

String _nombreArchivo(String s) => s.replaceAll(' a 100 %', '_1x').replaceAll(' a 200 %', '_2x');

void main() {
  group('QA #304 · la hoja del cambio de tipo (07·01) en los tamaños y con texto grande', () {
    for (final (nombre, tamano, escala) in _tamanos) {
      testWidgets('un solo depto, Edificio → Casa: sin aviso, «Guardar cambios» habilitado y '
          'guías en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        await _montar(tester, _edificioFalso(1), tamano: tamano, escala: escala);
        await _tocar(tester, find.text('Casa'));

        expect(find.textContaining('Borralo'), findsNothing);
        expect(find.textContaining('tiene 1 espacio'), findsNothing);
        expect(_habilitado(tester, _guardar), isTrue);
        await _capturar(tester, 'S17_un_depto_${_nombreArchivo(nombre)}');
        await _guias(tester);
        handle.dispose();
      });

      testWidgets('dos deptos, Edificio → Casa: el aviso literal, sin poder guardar, y guías en '
          '$nombre', (tester) async {
        final handle = tester.ensureSemantics();
        await _montar(tester, _edificioFalso(2), tamano: tamano, escala: escala);
        await _tocar(tester, find.text('Casa'));

        expect(find.text(_aviso2), findsOneWidget);
        expect(_habilitado(tester, _guardar), isFalse);
        await _capturar(tester, 'S17_dos_deptos_${_nombreArchivo(nombre)}');
        await _guias(tester);
        handle.dispose();
      });
    }

    for (final (nombre, tamano, escala) in _tamanos) {
      testWidgets(
        'capturas del canvas 07·01, 07·02 y 07·04 en $nombre (solo con QA_CAPTURAS)',
        skip: !_conCapturas,
        (tester) async {
          final e = await _montar(
            tester,
            RepoEdicionFalso(ubicacionGuardada(), espacios: 2),
            tamano: tamano,
            escala: escala,
          );
          await _tocar(tester, find.text('Negocio'));
          await tester.enterText(find.byType(TextField).at(1), '1238');
          await _asentar(tester);
          await _capturar(tester, '07_01_${_nombreArchivo(nombre)}');

          await _tocar(tester, _cerrar);
          await _capturar(tester, '07_04_${_nombreArchivo(nombre)}');
          await _tocar(tester, find.text('Seguir editando'));
          await _tocar(tester, _cerrar);
          await _tocar(tester, find.text('Descartar'));

          await _tocar(tester, find.text('abrir'));
          await _tocar(tester, find.text('Mover el punto'));
          e.mapa.moverPorGesto(
            e.mapa.camara!.conCentro(
              Coordenadas(lat: puntoItalia.lat + 0.00016, lon: puntoItalia.lon),
            ),
          );
          await _asentar(tester);
          await _capturar(tester, '07_02_${_nombreArchivo(nombre)}');
        },
      );
    }

    testWidgets('con texto al 200 % en 360x640 el aviso de bloqueo se ve sin hacer scroll', (
      tester,
    ) async {
      await _montar(tester, _edificioFalso(2), tamano: const Size(360, 640), escala: 2);
      await _tocar(tester, find.text('Casa'));

      expect(find.text(_aviso2), findsOneWidget);
      expect(
        tester.getRect(find.text(_aviso2)).bottom,
        lessThanOrEqualTo(tester.getRect(_guardar).top),
        reason: 'el aviso queda tapado por el botón fijo',
      );
    });
  });

  group('QA #304 r2 · la línea «El departamento 3B queda como…» y el aviso a 200 %', () {
    for (final (nombre, tamano, escala) in _tamanos) {
      for (final (destino, linea) in [('Casa', _lineaCasa), ('Negocio', _lineaNegocio)]) {
        testWidgets('un depto «3B», Edificio → $destino: la línea se ve sin scroll, no bloquea y '
            'cumple las guías en $nombre', (tester) async {
          final handle = tester.ensureSemantics();
          await _montar(
            tester,
            _edificioFalso(1, numeroDepto: '3B'),
            tamano: tamano,
            escala: escala,
          );
          await _tocar(tester, find.text(destino));

          expect(find.text(linea), findsOneWidget);
          expect(
            tester.getRect(find.text(linea)).bottom,
            lessThanOrEqualTo(tester.getRect(_guardar).top),
            reason: 'la línea queda tapada por el botón fijo',
          );
          expect(tester.getRect(find.text(linea)).top, greaterThanOrEqualTo(0));
          expect(find.textContaining('Borralos'), findsNothing);
          expect(_habilitado(tester, _guardar), isTrue);
          await _capturar(tester, 'r2_linea_${destino}_${_nombreArchivo(nombre)}');
          await _guias(tester);
          handle.dispose();
        });
      }
    }

    testWidgets('Negocio → Casa con dos deptos, a 200 % en 360x640: el aviso se ve sin scroll', (
      tester,
    ) async {
      final repo = RepoEdicionFalso(ubicacionGuardada(tipo: TipoUbicacion.negocio), espacios: 2);
      await _montar(tester, repo, tamano: const Size(360, 640), escala: 2);
      await _tocar(tester, find.text('Casa'));

      expect(find.text(_aviso2), findsOneWidget);
      expect(
        tester.getRect(find.text(_aviso2)).bottom,
        lessThanOrEqualTo(tester.getRect(_guardar).top),
      );
      expect(_habilitado(tester, _guardar), isFalse);
      await _capturar(tester, 'r2_negocio_a_casa_2_deptos_360x640_2x');
    });

    testWidgets('la línea cambia de «casa» a «negocio» y se va al volver a Edificio', (
      tester,
    ) async {
      final repo = _edificioFalso(1, numeroDepto: '3B');
      await _montar(tester, repo);

      await _tocar(tester, find.text('Casa'));
      expect(find.text(_lineaCasa), findsOneWidget);
      await _tocar(tester, find.text('Negocio'));
      expect(find.text(_lineaCasa), findsNothing);
      expect(find.text(_lineaNegocio), findsOneWidget);
      await _tocar(tester, find.text('Edificio'));
      expect(find.textContaining('queda como el espacio'), findsNothing);
    });

    testWidgets('si el depto no tiene número no hay línea y se puede guardar', (tester) async {
      final sinNumero = _edificioFalso(1);
      await _montar(tester, sinNumero);
      await _tocar(tester, find.text('Casa'));
      expect(find.textContaining('queda como el espacio'), findsNothing);
      expect(_habilitado(tester, _guardar), isTrue);
    });
  });

  group('QA #304 · rechazo tardío: aparece un 2.º depto entre abrir y guardar', () {
    testWidgets('tras el rechazo la hoja no se contradice: el resumen dice los 2 espacios del '
        'aviso', (tester) async {
      final repo = _edificioFalso(1);
      await _montar(tester, repo);
      repo.espacios = 2;
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, _guardar);

      expect(find.text(_aviso2), findsOneWidget);
      expect(find.textContaining('1 espacio'), findsNothing, reason: 'el resumen quedó viejo');
      expect(repo.escrituras, isEmpty);
    });

    testWidgets('tras el rechazo no se escribe nada, «Guardar cambios» queda sin efecto (el aviso '
        'de bloqueo sigue a la vista) y no queda «Guardando…» trabado', (tester) async {
      final repo = _edificioFalso(1);
      await _montar(tester, repo);
      repo.espacios = 2;
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, _guardar);

      expect(find.text(_aviso2), findsOneWidget);
      expect(repo.escrituras, isEmpty);
      expect(_habilitado(tester, _guardar), isFalse);
      expect(_guardandoBoton, findsNothing, reason: 'no queda «Guardando…» trabado');
    });

    testWidgets('el rechazo no deja la hoja trabada: se puede tocar «Guardar» otra vez, volver a '
        '«Edificio» (el aviso se va) y cerrar sin preguntar', (tester) async {
      final repo = _edificioFalso(1);
      final e = await _montar(tester, repo);
      repo.espacios = 2;
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _guardar);

      await _tocar(tester, _guardar);
      expect(find.text(_aviso2), findsOneWidget, reason: 'un solo aviso, no se apilan');
      expect(repo.escrituras, isEmpty);

      await _tocar(tester, find.text('Edificio'));
      expect(find.textContaining('Borralos'), findsNothing);
      expect(_habilitado(tester, _guardar), isFalse);

      await _tocar(tester, _cerrar);
      expect(find.text('¿Descartar los cambios?'), findsNothing);
      expect(e.salidas, hasLength(1));
      expect(e.salidas.single, isNull);
    });

    testWidgets('el rechazo conserva lo tipeado: calle y número no se pierden', (tester) async {
      final repo = _edificioFalso(1);
      await _montar(tester, repo);
      repo.espacios = 3;
      await _tocar(tester, find.text('Negocio'));
      await tester.enterText(find.byType(TextField).at(0), 'Av. Brasil');
      await tester.enterText(find.byType(TextField).at(1), '1238');
      await _asentar(tester);

      await _tocar(tester, _guardar);

      expect(
        find.text('Esta ubicación tiene 3 espacios. Borralos o reubicalos primero.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Av. Brasil'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1238'), findsOneWidget);
      expect(repo.escrituras, isEmpty);
    });

    testWidgets(
      'un solo depto y el guardado tarda: el botón dice «Guardando…», un segundo toque no '
      'escribe otra vez y al terminar se cierra con el resultado',
      (tester) async {
        final repo = _edificioFalso(1)..bloqueoEscritura = Completer<void>();
        final e = await _montar(tester, repo);
        await _tocar(tester, find.text('Casa'));

        await _tocar(tester, _guardar);
        expect(_guardandoBoton, findsOneWidget);
        await tester.tap(_guardandoBoton, warnIfMissed: false);
        await _asentar(tester);
        expect(repo.escrituras, hasLength(1));

        repo.bloqueoEscritura!.complete();
        await _asentar(tester);

        expect(repo.escrituras, hasLength(1));
        expect(e.salidas.single, isA<UbicacionEditada>());
      },
    );
  });

  group('QA #304 · de punta a punta con la base real (Drift en memoria)', () {
    final t0 = DateTime.utc(2026, 9, 29, 13, 45, 10, 123);

    late AppDatabase db;
    late EncoladorSyncEnMemoria encolador;
    late UbicacionRepositoryImpl repositorio;

    Future<void> preparar(
      WidgetTester tester, {
      required List<({String id, String? numero, String? piso, bool baja})> deptos,
      TipoUbicacion tipo = TipoUbicacion.edificio,
    }) async {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      encolador = EncoladorSyncEnMemoria();
      final local = UbicacionLocalDataSourceDrift(db, encolador: encolador);
      repositorio = UbicacionRepositoryImpl(local, logger: loggerMudo());
      await tester.runAsync(() async {
        await local.insertar(
          UbicacionModel.fromEntity(ubicacionGuardada(tipo: tipo, actualizada: t0, creada: t0)),
        );
        for (final d in deptos) {
          await db
              .into(db.espacios)
              .insert(
                EspaciosCompanion.insert(
                  id: d.id,
                  ubicacionId: 'ubi-1',
                  numeroDepto: Value(d.numero),
                  piso: Value(d.piso),
                  createdAt: t0,
                  updatedAt: t0,
                  createdBy: const Value('col-1'),
                  deletedAt: Value(d.baja ? t0 : null),
                  syncVersion: const Value(7),
                ),
              );
        }
        encolador.encolados.clear();
      });
    }

    Future<EspacioFila> espacio(WidgetTester tester, String id) async => (await tester.runAsync(
      () => (db.select(db.espacios)..where((e) => e.id.equals(id))).getSingle(),
    ))!;

    Future<Ubicacion> ubicacion(WidgetTester tester) async => (await tester.runAsync(
      () => repositorio.obtener('ubi-1').then((r) => r.toOption().toNullable()),
    ))!;

    List<String> entidades() => [for (final c in encolador.encolados) c.entidad];

    /// Llega un departamento (el sync entrante, por ejemplo) a `ubi-1`.
    Future<void> insertarDepto(WidgetTester tester, String id, String numero) async {
      await tester.runAsync(
        () => db
            .into(db.espacios)
            .insert(
              EspaciosCompanion.insert(
                id: id,
                ubicacionId: 'ubi-1',
                numeroDepto: Value(numero),
                createdAt: t0,
                updatedAt: t0,
                syncVersion: const Value(1),
              ),
            ),
      );
    }

    /// El departamento [id] se da de baja (otro teléfono, por el sync).
    Future<void> darDeBajaDepto(WidgetTester tester, String id) => tester.runAsync(
      () => (db.update(
        db.espacios,
      )..where((x) => x.id.equals(id))).write(EspaciosCompanion(deletedAt: Value(t0))),
    );

    testWidgets(
      'un depto «3B»: Edificio → Casa deja el depto sin número, encola ubicación y espacio '
      'en orden, y la hoja reabierta dice «Casa · 1 espacio»',
      (tester) async {
        await preparar(tester, deptos: [(id: 'e1', numero: '3B', piso: '3', baja: false)]);
        final e = await _montar(tester, repositorio);
        expect(find.textContaining('Edificio · 1 espacio'), findsOneWidget);

        await _tocar(tester, find.text('Casa'));
        expect(find.textContaining('Borralo'), findsNothing);
        await _tocar(tester, _guardar);

        expect(e.salidas.single, isA<UbicacionEditada>());
        expect((await ubicacion(tester)).tipo, TipoUbicacion.casa);
        final fila = await espacio(tester, 'e1');
        expect(fila.numeroDepto, isNull);
        expect(fila.piso, '3', reason: 'lo demás del espacio queda');
        expect(fila.deletedAt, isNull);
        expect(entidades(), ['ubicacion', 'espacio']);

        await _abrir(tester);
        expect(find.textContaining('Casa · 1 espacio'), findsOneWidget);
        await tester.runAsync(db.close);
      },
    );

    testWidgets(
      'ida y vuelta: Casa → Edificio no toca el espacio; Edificio → Negocio otra vez ya no '
      'encola el espacio (no tiene número)',
      (tester) async {
        await preparar(tester, deptos: [(id: 'e1', numero: '3B', piso: null, baja: false)]);
        await _montar(tester, repositorio);
        await _tocar(tester, find.text('Casa'));
        await _tocar(tester, _guardar);
        expect(entidades(), ['ubicacion', 'espacio']);
        encolador.encolados.clear();

        await _abrir(tester);
        await _tocar(tester, find.text('Edificio'));
        await _tocar(tester, _guardar);

        expect((await ubicacion(tester)).tipo, TipoUbicacion.edificio);
        expect((await espacio(tester, 'e1')).numeroDepto, isNull, reason: 'sigue sin número');
        expect((await espacio(tester, 'e1')).deletedAt, isNull, reason: 'sigue activo');
        expect(entidades(), ['ubicacion']);
        encolador.encolados.clear();

        await _abrir(tester);
        expect(find.textContaining('Edificio · 1 espacio'), findsOneWidget);
        await _tocar(tester, find.text('Negocio'));
        expect(find.textContaining('Borralo'), findsNothing);
        await _tocar(tester, _guardar);

        expect((await ubicacion(tester)).tipo, TipoUbicacion.negocio);
        expect(entidades(), ['ubicacion']);
        await tester.runAsync(db.close);
      },
    );

    testWidgets('un depto activo y dos dados de baja: cuenta uno, pasa y no toca los de baja', (
      tester,
    ) async {
      await preparar(
        tester,
        deptos: [
          (id: 'e1', numero: '1A', piso: null, baja: false),
          (id: 'e2', numero: '2B', piso: null, baja: true),
          (id: 'e3', numero: '3C', piso: null, baja: true),
        ],
      );
      await _montar(tester, repositorio);
      expect(find.textContaining('Edificio · 1 espacio'), findsOneWidget);

      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _guardar);

      expect((await espacio(tester, 'e1')).numeroDepto, isNull);
      expect((await espacio(tester, 'e2')).numeroDepto, '2B');
      expect((await espacio(tester, 'e3')).numeroDepto, '3C');
      await tester.runAsync(db.close);
    });

    testWidgets('dos deptos activos: el aviso con la cuenta, sin poder guardar y sin tocar nada', (
      tester,
    ) async {
      await preparar(
        tester,
        deptos: [
          (id: 'e1', numero: '1A', piso: null, baja: false),
          (id: 'e2', numero: '2B', piso: null, baja: false),
        ],
      );
      await _montar(tester, repositorio);

      await _tocar(tester, find.text('Negocio'));

      expect(find.text(_aviso2), findsOneWidget);
      expect(_habilitado(tester, _guardar), isFalse);
      expect((await ubicacion(tester)).tipo, TipoUbicacion.edificio);
      expect((await espacio(tester, 'e1')).numeroDepto, '1A');
      expect(encolador.encolados, isEmpty);
      await tester.runAsync(db.close);
    });

    testWidgets(
      'el 2.º depto aparece mientras la hoja está abierta (sync entrante): la transacción '
      'rechaza, no suelta el número del 1.º y no encola nada',
      (tester) async {
        await preparar(tester, deptos: [(id: 'e1', numero: '1A', piso: null, baja: false)]);
        await _montar(tester, repositorio);
        await _tocar(tester, find.text('Casa'));
        await tester.runAsync(
          () => db
              .into(db.espacios)
              .insert(
                EspaciosCompanion.insert(
                  id: 'e2',
                  ubicacionId: 'ubi-1',
                  numeroDepto: const Value('2B'),
                  createdAt: t0,
                  updatedAt: t0,
                  syncVersion: const Value(1),
                ),
              ),
        );

        await _tocar(tester, _guardar);

        expect(find.text(_aviso2), findsOneWidget);
        expect((await ubicacion(tester)).tipo, TipoUbicacion.edificio);
        expect((await espacio(tester, 'e1')).numeroDepto, '1A');
        expect(encolador.encolados, isEmpty);
        await tester.runAsync(db.close);
      },
    );

    testWidgets(
      'Negocio → Casa con dos deptos activos: el aviso con la cuenta, sin poder guardar y '
      'sin tocar nada; a Edificio no se bloquea',
      (tester) async {
        await preparar(
          tester,
          tipo: TipoUbicacion.negocio,
          deptos: [
            (id: 'e1', numero: null, piso: null, baja: false),
            (id: 'e2', numero: '2B', piso: null, baja: false),
          ],
        );
        await _montar(tester, repositorio);

        await _tocar(tester, find.text('Casa'));
        expect(find.text(_aviso2), findsOneWidget);
        expect(_habilitado(tester, _guardar), isFalse);
        expect((await ubicacion(tester)).tipo, TipoUbicacion.negocio);
        expect((await espacio(tester, 'e2')).numeroDepto, '2B');
        expect(encolador.encolados, isEmpty);

        await _tocar(tester, find.text('Edificio'));
        expect(find.textContaining('Borralos'), findsNothing);
        expect(_habilitado(tester, _guardar), isTrue);
        await tester.runAsync(db.close);
      },
    );

    testWidgets('Negocio → Casa con un depto «3B»: la línea dice «de la casa», pasa y el depto '
        'queda sin número', (tester) async {
      await preparar(
        tester,
        tipo: TipoUbicacion.negocio,
        deptos: [(id: 'e1', numero: '3B', piso: '3', baja: false)],
      );
      final e = await _montar(tester, repositorio);

      await _tocar(tester, find.text('Casa'));
      expect(find.text(_lineaCasa), findsOneWidget);
      await _tocar(tester, _guardar);

      expect(e.salidas.single, isA<UbicacionEditada>());
      expect((await ubicacion(tester)).tipo, TipoUbicacion.casa);
      final fila = await espacio(tester, 'e1');
      expect(fila.numeroDepto, isNull);
      expect(fila.piso, '3');
      expect(fila.deletedAt, isNull);
      expect(entidades(), ['ubicacion', 'espacio']);
      await tester.runAsync(db.close);
    });

    testWidgets('la línea toma el número del depto activo, no el del dado de baja', (tester) async {
      await preparar(
        tester,
        deptos: [
          (id: 'e1', numero: '1A', piso: null, baja: true),
          (id: 'e2', numero: '3B', piso: null, baja: false),
        ],
      );
      await _montar(tester, repositorio);

      await _tocar(tester, find.text('Casa'));

      expect(find.text(_lineaCasa), findsOneWidget);
      expect(find.textContaining('1A'), findsNothing);
      await tester.runAsync(db.close);
    });

    testWidgets('un depto sin número: pasa a Casa sin línea', (tester) async {
      await preparar(tester, deptos: [(id: 'e1', numero: null, piso: null, baja: false)]);
      await _montar(tester, repositorio);

      await _tocar(tester, find.text('Casa'));

      expect(find.textContaining('queda como el espacio'), findsNothing);
      expect(_habilitado(tester, _guardar), isTrue);
      await tester.runAsync(db.close);
    });

    testWidgets('sin deptos: pasa a Casa sin línea ni bloqueo y no encola ningún espacio', (
      tester,
    ) async {
      await preparar(tester, deptos: const []);
      final e = await _montar(tester, repositorio);
      expect(find.textContaining('Edificio · Sin espacios'), findsOneWidget);

      await _tocar(tester, find.text('Casa'));
      expect(find.textContaining('queda como el espacio'), findsNothing);
      expect(find.textContaining('Borralos'), findsNothing);
      await _tocar(tester, _guardar);

      expect(e.salidas.single, isA<UbicacionEditada>());
      expect(entidades(), ['ubicacion']);
      await tester.runAsync(db.close);
    });

    testWidgets('dos deptos: el bloqueo y ninguna línea «queda como el espacio»', (tester) async {
      await preparar(
        tester,
        deptos: [
          (id: 'e1', numero: '3B', piso: null, baja: false),
          (id: 'e2', numero: '4C', piso: null, baja: false),
        ],
      );
      await _montar(tester, repositorio);

      await _tocar(tester, find.text('Casa'));

      expect(find.text(_aviso2), findsOneWidget);
      expect(find.textContaining('queda como el espacio'), findsNothing);
      await tester.runAsync(db.close);
    });

    testWidgets(
      'el 2.º depto llega del sync con la hoja abierta: la hoja avisa sola, antes de guardar, y '
      'cuando se da de baja se recupera sola, sin cerrar ni abrir de nuevo (#314)',
      (tester) async {
        await preparar(tester, deptos: [(id: 'e1', numero: '3B', piso: null, baja: false)]);
        final e = await _montar(tester, repositorio);
        await _tocar(tester, find.text('Casa'));
        expect(find.text(_lineaCasa), findsOneWidget);

        await insertarDepto(tester, 'e2', '4C');
        await _asentar(tester);

        expect(find.text(_aviso2), findsOneWidget);
        expect(find.textContaining('Edificio · 2 espacios'), findsOneWidget);
        expect(find.textContaining('queda como el espacio'), findsNothing);
        expect(_habilitado(tester, _guardar), isFalse);
        expect(encolador.encolados, isEmpty, reason: 'no se tocó «Guardar cambios»');

        await darDeBajaDepto(tester, 'e2');
        await _asentar(tester);

        expect(find.textContaining('Borralos'), findsNothing);
        expect(find.textContaining('Edificio · 1 espacio'), findsOneWidget);
        expect(find.text(_lineaCasa), findsOneWidget);
        expect(_habilitado(tester, _guardar), isTrue);

        await _tocar(tester, _guardar);

        expect(e.salidas.single, isA<UbicacionEditada>());
        expect((await ubicacion(tester)).tipo, TipoUbicacion.casa);
        expect((await espacio(tester, 'e1')).numeroDepto, isNull);
        expect((await espacio(tester, 'e2')).deletedAt, isNotNull);
        expect(entidades(), ['ubicacion', 'espacio']);
        await tester.runAsync(db.close);
      },
    );

    testWidgets(
      'el número del único depto cambia con la hoja abierta (sync entrante): la línea dice el '
      'número de ahora (#314)',
      (tester) async {
        await preparar(tester, deptos: [(id: 'e1', numero: '3B', piso: null, baja: false)]);
        await _montar(tester, repositorio);
        await _tocar(tester, find.text('Casa'));
        expect(find.text(_lineaCasa), findsOneWidget);

        await tester.runAsync(
          () => (db.update(db.espacios)..where((x) => x.id.equals('e1'))).write(
            const EspaciosCompanion(numeroDepto: Value('5D')),
          ),
        );
        await _asentar(tester);

        expect(find.text(_lineaCasa), findsNothing);
        expect(
          find.text('El departamento 5D queda como el espacio de la casa, sin número.'),
          findsOneWidget,
        );
        await tester.runAsync(db.close);
      },
    );

    testWidgets(
      'el único depto pierde su número con la hoja abierta: la línea se va y se guarda igual (#314)',
      (tester) async {
        await preparar(tester, deptos: [(id: 'e1', numero: '3B', piso: null, baja: false)]);
        final e = await _montar(tester, repositorio);
        await _tocar(tester, find.text('Casa'));
        expect(find.text(_lineaCasa), findsOneWidget);

        await tester.runAsync(
          () => (db.update(db.espacios)..where((x) => x.id.equals('e1'))).write(
            const EspaciosCompanion(numeroDepto: Value(null)),
          ),
        );
        await _asentar(tester);

        expect(find.textContaining('queda como el espacio'), findsNothing);
        expect(_habilitado(tester, _guardar), isTrue);
        await _tocar(tester, _guardar);
        expect(e.salidas.single, isA<UbicacionEditada>());
        await tester.runAsync(db.close);
      },
    );
  });
}
