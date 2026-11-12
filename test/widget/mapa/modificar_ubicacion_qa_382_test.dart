// QA del PR #456 (issue #382, HU-UBI-004 / S13): al pasar a Casa sin espacios, la casa recibe su
// espacio default. No hay vista nueva (la hoja 07·01 no cambia): el estado «Edificio · Sin espacios»
// con Casa elegida ya existía. Lo que se prueba acá, de punta a punta con la base real (pantalla,
// caso de uso, repositorio y Drift en memoria):
//  1. El estado de la hoja (sin espacios, Casa elegida) en 360x640 y 412x915 a 100 % y 200 %: guías
//     de accesibilidad y sin overflow. Capturas con `--dart-define=QA_CAPTURAS=true`.
//  2. El guardado crea el espacio y la hoja reabierta dice «Casa · 1 espacio»; ida y vuelta no suma otro.
//  3. El sync trae o saca deptos con la hoja abierta: 0 → 1 (se usa el que llegó), 0 → 2 (bloqueo),
//     1 → 0 (la casa recibe su espacio y el de baja queda).
//  4. Falla a mitad, reintento y doble toque con la base real.
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
    File('${dir.path}/456_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
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

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<FilledButton>(boton).onPressed != null;

const _tamanos = <(String, Size, double)>[
  ('360x640 a 100 %', Size(360, 640), 1.0),
  ('360x640 a 200 %', Size(360, 640), 2.0),
  ('412x915 a 100 %', Size(412, 915), 1.0),
  ('412x915 a 200 %', Size(412, 915), 2.0),
];

String _nombreArchivo(String s) => s.replaceAll(' a 100 %', '_1x').replaceAll(' a 200 %', '_2x');

void main() {
  group('QA #382 · la hoja «Sin espacios» con Casa elegida (07·01) en los tamaños', () {
    for (final (nombre, tamano, escala) in _tamanos) {
      for (final tipo in [TipoUbicacion.edificio, TipoUbicacion.negocio]) {
        testWidgets('${tipo.name} sin espacios → Casa: sin aviso ni línea, «Guardar cambios» '
            'habilitado y guías en $nombre', (tester) async {
          final handle = tester.ensureSemantics();
          await _montar(
            tester,
            RepoEdicionFalso(ubicacionGuardada(tipo: tipo), espacios: 0),
            tamano: tamano,
            escala: escala,
          );
          await _tocar(tester, find.text('Casa'));

          expect(find.textContaining('Borralo'), findsNothing);
          expect(find.textContaining('queda como el espacio'), findsNothing);
          expect(_habilitado(tester, _guardar), isTrue);
          await _capturar(tester, 'sin_espacios_${tipo.name}_${_nombreArchivo(nombre)}');
          await _guias(tester);
          handle.dispose();
        });
      }
    }
  });

  group('QA #382 · de punta a punta con la base real (Drift en memoria)', () {
    final t0 = DateTime.utc(2026, 10, 21, 13, 45, 10, 123);

    late AppDatabase db;
    late EncoladorSyncEnMemoria encolador;
    late UbicacionRepositoryImpl repositorio;

    Future<void> preparar(
      WidgetTester tester, {
      TipoUbicacion tipo = TipoUbicacion.edificio,
      List<({String id, String? numero, bool baja})> deptos = const [],
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

    Future<List<EspacioFila>> filas(WidgetTester tester) async =>
        (await tester.runAsync(() => db.select(db.espacios).get()))!;

    Future<List<EspacioFila>> activos(WidgetTester tester) async =>
        (await filas(tester)).where((e) => e.deletedAt == null).toList();

    Future<Ubicacion> ubicacion(WidgetTester tester) async => (await tester.runAsync(
      () => repositorio.obtener('ubi-1').then((r) => r.toOption().toNullable()),
    ))!;

    List<String> entidades() => [for (final c in encolador.encolados) c.entidad];

    Future<void> insertarDepto(WidgetTester tester, String id, String numero) => tester.runAsync(
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

    Future<void> darDeBajaDepto(WidgetTester tester, String id) => tester.runAsync(
      () => (db.update(
        db.espacios,
      )..where((x) => x.id.equals(id))).write(EspaciosCompanion(deletedAt: Value(t0))),
    );

    for (final tipo in [TipoUbicacion.edificio, TipoUbicacion.negocio]) {
      testWidgets('${tipo.name} sin espacios → Casa: la casa recibe su espacio sin número, se '
          'encola ubicación y espacio en orden y la hoja reabierta dice «Casa · 1 espacio»', (
        tester,
      ) async {
        await preparar(tester, tipo: tipo);
        final e = await _montar(tester, repositorio);
        expect(find.textContaining('Sin espacios'), findsOneWidget);

        await _tocar(tester, find.text('Casa'));
        await _tocar(tester, _guardar);

        expect(e.salidas.single, isA<UbicacionEditada>());
        expect((await ubicacion(tester)).tipo, TipoUbicacion.casa);
        final espacio = (await activos(tester)).single;
        expect(
          (espacio.ubicacionId, espacio.numeroDepto, espacio.createdBy),
          ('ubi-1', null, 'col-1'),
        );
        expect(entidades(), ['ubicacion', 'espacio']);

        await _abrir(tester);
        expect(find.textContaining('Casa · 1 espacio'), findsOneWidget);
        await tester.runAsync(db.close);
      });
    }

    testWidgets('Edificio sin espacios → Negocio: no se crea ningún espacio', (tester) async {
      await preparar(tester);
      await _montar(tester, repositorio);

      await _tocar(tester, find.text('Negocio'));
      await _tocar(tester, _guardar);

      expect((await ubicacion(tester)).tipo, TipoUbicacion.negocio);
      expect(await filas(tester), isEmpty);
      expect(entidades(), ['ubicacion']);
      await tester.runAsync(db.close);
    });

    testWidgets('ida y vuelta Casa → Edificio → Casa: el espacio es el mismo y no se encola otro '
        'insert', (tester) async {
      await preparar(tester);
      await _montar(tester, repositorio);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _guardar);
      final primero = (await activos(tester)).single.id;
      encolador.encolados.clear();

      await _abrir(tester);
      await _tocar(tester, find.text('Edificio'));
      await _tocar(tester, _guardar);
      await _abrir(tester);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _guardar);

      expect((await ubicacion(tester)).tipo, TipoUbicacion.casa);
      expect((await activos(tester)).map((e) => e.id), [primero]);
      expect(entidades(), ['ubicacion', 'ubicacion']);
      await tester.runAsync(db.close);
    });

    testWidgets('con la calle y el número también cambiados, Casa recibe su espacio', (
      tester,
    ) async {
      await preparar(tester);
      await _montar(tester, repositorio);
      await _tocar(tester, find.text('Casa'));
      await tester.enterText(find.byType(TextField).at(0), 'Av. Brasil');
      await tester.enterText(find.byType(TextField).at(1), '1238');
      await _asentar(tester);

      await _tocar(tester, _guardar);

      final u = await ubicacion(tester);
      expect((u.tipo, u.calle, u.numero), (TipoUbicacion.casa, 'Av. Brasil', '1238'));
      expect(await activos(tester), hasLength(1));
      await tester.runAsync(db.close);
    });

    testWidgets('sin deptos y el sync trae uno con la hoja abierta (0 → 1): se usa ese depto, que '
        'pierde el número, y no se crea otro', (tester) async {
      await preparar(tester);
      final e = await _montar(tester, repositorio);
      await _tocar(tester, find.text('Casa'));

      await insertarDepto(tester, 'e1', '4C');
      await _asentar(tester);

      expect(
        find.text('El departamento 4C queda como el espacio de la casa, sin número.'),
        findsOneWidget,
      );
      expect(_habilitado(tester, _guardar), isTrue);

      await _tocar(tester, _guardar);

      expect(e.salidas.single, isA<UbicacionEditada>());
      final todos = await filas(tester);
      expect(todos.map((x) => x.id), ['e1']);
      expect(todos.single.numeroDepto, isNull);
      expect(entidades(), ['ubicacion', 'espacio']);
      await tester.runAsync(db.close);
    });

    testWidgets('sin deptos y el sync trae dos con la hoja abierta (0 → 2): bloquea y no crea ni '
        'toca nada', (tester) async {
      await preparar(tester);
      await _montar(tester, repositorio);
      await _tocar(tester, find.text('Casa'));

      await insertarDepto(tester, 'e1', '1A');
      await insertarDepto(tester, 'e2', '2B');
      await _asentar(tester);

      expect(find.text(_aviso2), findsOneWidget);
      expect(_habilitado(tester, _guardar), isFalse);
      expect((await ubicacion(tester)).tipo, TipoUbicacion.edificio);
      expect((await filas(tester)).map((x) => x.numeroDepto).toSet(), {'1A', '2B'});
      expect(encolador.encolados, isEmpty);
      await tester.runAsync(db.close);
    });

    testWidgets('con un depto que se da de baja con la hoja abierta (1 → 0): la línea se va y la '
        'casa recibe su espacio nuevo; el de baja queda como estaba', (tester) async {
      await preparar(tester, deptos: [(id: 'e1', numero: '3B', baja: false)]);
      final e = await _montar(tester, repositorio);
      await _tocar(tester, find.text('Casa'));
      expect(find.textContaining('queda como el espacio'), findsOneWidget);

      await darDeBajaDepto(tester, 'e1');
      await _asentar(tester);

      expect(find.textContaining('queda como el espacio'), findsNothing);
      expect(_habilitado(tester, _guardar), isTrue);

      await _tocar(tester, _guardar);

      expect(e.salidas.single, isA<UbicacionEditada>());
      final baja = (await filas(tester)).singleWhere((x) => x.id == 'e1');
      expect((baja.numeroDepto, baja.deletedAt), ('3B', t0));
      expect(await activos(tester), hasLength(1));
      expect(entidades(), ['ubicacion', 'espacio']);
      await tester.runAsync(db.close);
    });

    testWidgets('falla a mitad (el encolado del espacio): no queda nada a medias, el botón vuelve, '
        'lo tipeado sigue y el reintento crea el espacio', (tester) async {
      await preparar(tester);
      final e = await _montar(tester, repositorio);
      await _tocar(tester, find.text('Casa'));
      await tester.enterText(find.byType(TextField).at(1), '1238');
      await _asentar(tester);
      encolador
        ..fallarCon = StateError('motor apagado')
        ..fallarDespuesDe = encolador.encolados.length + 1;

      await _tocar(tester, _guardar);

      expect(find.text(TextosModificar.noPudimosGuardar), findsOneWidget);
      expect(_habilitado(tester, _guardar), isTrue);
      expect(_guardandoBoton, findsNothing);
      expect(find.widgetWithText(TextField, '1238'), findsOneWidget);
      expect((await ubicacion(tester)).tipo, TipoUbicacion.edificio);
      expect(await filas(tester), isEmpty);
      expect(e.salidas, isEmpty);

      encolador.fallarCon = null;
      await _tocar(tester, _guardar);

      expect(e.salidas.single, isA<UbicacionEditada>());
      expect((await ubicacion(tester)).tipo, TipoUbicacion.casa);
      expect(await activos(tester), hasLength(1));
      await tester.runAsync(db.close);
    });

    testWidgets('doble toque en «Guardar cambios» con la base real: un solo espacio y una sola '
        'salida', (tester) async {
      await preparar(tester);
      final e = await _montar(tester, repositorio);
      await _tocar(tester, find.text('Casa'));

      await _traer(tester, _guardar);
      await tester.tap(_guardar);
      await tester.tap(_guardar, warnIfMissed: false);
      await _asentar(tester);

      expect(e.salidas, hasLength(1));
      expect(await activos(tester), hasLength(1));
      expect(entidades().where((x) => x == 'espacio'), hasLength(1));
      await tester.runAsync(db.close);
    });
  });
}
