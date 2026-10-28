// QA de #274 / PR #548 (vista 03 «Alta de ubicación»): la pantalla de verdad con el adaptador real
// (`CiudadesParaAltaLocal` sobre la base en memoria, con los datos de la demo del 31/10) en vez del
// falso. Estados de la ciudad: detectada, de tu zona, de tu campaña, «Elegir», sin ciudades, falla de
// lectura con «Reintentar» (el teléfono todavía no bajó el catálogo), todos a 360×640 y a texto 2,0.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/campanias_del_colportor_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/zona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/zona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/ciudades_para_alta_local.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:dartz/dartz.dart' show Left, Right;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/replica_de_campanias.dart';
import '../../helpers/replica_demo_lsm_qa_548.dart';

const _telefonoChico = Size(360, 640);
const _telefonoGrande = Size(412, 915);

final _raiz = GlobalKey();

class _Anfitrion extends StatelessWidget {
  const _Anfitrion({required this.salidas, required this.colportor});

  final List<SalidaAltaUbicacion?> salidas;
  final String colportor;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async =>
            salidas.add(await AltaUbicacionPage.abrir(context, colportorId: colportor)),
        child: const Text('abrir'),
      ),
    ),
  );
}

final class _Montaje {
  _Montaje(this.db, this.replica, this.salidas, this.repo);

  final AppDatabase db;
  final ReplicaDeCampanias replica;
  final List<SalidaAltaUbicacion?> salidas;
  final RepoAltaFalso repo;
}

/// Deja correr lo que necesita tiempo real (la base en memoria) y después los cuadros.
Future<void> _asentar(WidgetTester tester, [int veces = 6]) async {
  for (var i = 0; i < veces; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
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

Finder get _registrar => find.widgetWithText(FilledButton, TextosAlta.registrar);

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<FilledButton>(boton).onPressed != null;

Future<void> _cargarFuentes(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final (familia, archivo) in const [
      ('Inter', 'Inter.ttf'),
      ('SourceSerif4', 'SourceSerif4.ttf'),
      ('JetBrainsMono', 'JetBrainsMono.ttf'),
    ]) {
      final bytes = File('assets/fonts/$archivo').readAsBytesSync();
      final cargador = FontLoader(familia)..addFont(Future.value(ByteData.view(bytes.buffer)));
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

/// PNG de la pantalla en `.dart_tool/qa_capturas/` (gitignored, fuera del commit).
Future<void> _capturar(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/548_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<_Montaje> _montar(
  WidgetTester tester, {
  required Map<String, List<Map<String, Object?>>>? pull,
  String colportor = colportorDemoId,
  GpsFalso? gps,
  Size tamano = _telefonoChico,
  double escala = 1,
  bool abrir = true,
  bool terminoElPull = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
  addTearDown(() => tester.runAsync(db.close));
  final replica = ReplicaDeCampanias(db);
  if (pull != null) {
    await tester.runAsync(() async {
      await replica.bajar(pull);
      if (terminoElPull) await replica.terminoUnPull();
    });
  }
  final ciudades = CiudadesParaAltaLocal(
    campanias: CampaniasDelColportorLocalDataSourceDrift(db),
    zonas: ZonaRepositoryImpl(ZonaLocalDataSourceDrift(db), logger: loggerMudo()),
    ahora: () => DateTime.utc(2026, 10, 31, 15),
    logger: loggerMudo(),
  );
  final repo = RepoAltaFalso();
  final m = _Montaje(db, replica, [], repo);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesAlta(
        gps:
            gps ??
            GpsFalso(
              Right(
                lecturaGps(
                  6,
                  punto: const Coordenadas(lat: lat1Uap, lon: lon1Uap),
                ),
              ),
            ),
        geocodificador: GeocodificadorFalso(
          (_) => const DireccionDelPunto(calle: 'Hipólito Yrigoyen', numero: '120'),
        ),
        puertoCiudades: ciudades,
        repo: repo,
        ahora: DateTime.utc(2026, 10, 31, 15),
      ),
      child: RepaintBoundary(
        key: _raiz,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: _Anfitrion(salidas: m.salidas, colportor: colportor),
        ),
      ),
    ),
  );
  if (abrir) {
    await tester.tap(find.text('abrir'));
    await _asentar(tester);
  }
  return m;
}

GpsFalso _sinGps() =>
    GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado)));

void main() {
  group('colportor.demo en Libertador San Martín, con el adaptador real', () {
    testWidgets('con el GPS en Zona UAP: «Libertador San Martín · detectada», se elige «Casa» y se '
        'registra con la ciudad de la demo', (tester) async {
      final m = await _montar(tester, pull: _demo());

      expect(find.text('Libertador San Martín'), findsOneWidget);
      expect(find.text('detectada · Cambiar'), findsOneWidget);
      expect(find.text(TextosAlta.ciudadesNoLeidas), findsNothing);
      expect(find.text(TextosAlta.sinCiudades), findsNothing);
      await _tocar(tester, find.text('Casa'));
      expect(_habilitado(tester, _registrar), isTrue);
      await _tocar(tester, _registrar);

      final creada = m.salidas.single! as UbicacionCreada;
      expect(creada.ubicacion.ciudadId, ciudadLsmId);
    });

    testWidgets('sin permiso de GPS: la ciudad es la de su zona, «de tu zona · Cambiar», y se '
        'registra tocando el mapa', (tester) async {
      await _montar(tester, pull: _demo(), gps: _sinGps());

      expect(find.text('Libertador San Martín'), findsOneWidget);
      expect(find.text('de tu zona · Cambiar'), findsOneWidget);
      expect(find.text(TextosAlta.ciudadesNoLeidas), findsNothing);
    });

    testWidgets('«Cambiar» muestra solo Libertador San Martín (la campaña tiene una sola ciudad)', (
      tester,
    ) async {
      await _montar(tester, pull: _demo(), gps: _sinGps());

      await _tocar(tester, find.text('de tu zona · Cambiar'));

      expect(find.text('Elegí la ciudad'), findsOneWidget);
      expect(find.text('Libertador San Martín'), findsNWidgets(2));
      expect(find.text('Montevideo'), findsNothing);
    });
  });

  group('inscripta en Libertador San Martín y en Montevideo', () {
    testWidgets('«Cambiar» lista las dos y se puede registrar en Montevideo', (tester) async {
      final m = await _montar(
        tester,
        pull: sumarMontevideo(_demo(), usuario: colportorDemoId),
        gps: _sinGps(),
      );

      await _tocar(tester, find.text('de tu zona · Cambiar'));
      expect(find.text('Libertador San Martín'), findsNWidgets(2));
      expect(find.text('Montevideo'), findsOneWidget);
      await _tocar(tester, find.text('Montevideo'));
      await _tocar(tester, find.text('Casa'));
      // Sin GPS el punto se marca en el mapa.
      await tester.tapAt(tester.getTopLeft(find.byType(Scaffold).last) + const Offset(180, 120));
      await _asentar(tester);

      expect(find.text('Montevideo'), findsOneWidget);
      expect(m.repo.llamadas, isEmpty, reason: 'nada se guarda hasta tocar «Registrar»');
    });
  });

  group('el teléfono todavía no bajó el catálogo (instalación nueva o recién actualizada)', () {
    testWidgets('falla de lectura con «Reintentar»; cuando llega el pull, «Reintentar» trae la '
        'ciudad y deja registrar; nunca «Tu campaña todavía no tiene ciudades»', (tester) async {
      final m = await _montar(tester, pull: null);
      await _tocar(tester, find.text('Casa'));

      expect(find.text(TextosAlta.ciudadesNoLeidas), findsOneWidget);
      expect(find.text(TextosAlta.sinCiudades), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isFalse);

      // Todavía sin red: «Reintentar» vuelve a fallar, el aviso sigue y el botón no se traba.
      await _tocar(tester, find.text('Reintentar'));
      expect(find.text(TextosAlta.ciudadesNoLeidas), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.runAsync(() async {
        await m.replica.bajar(_demo());
        await m.replica.terminoUnPull();
      });
      await _tocar(tester, find.text('Reintentar'));

      expect(find.text(TextosAlta.ciudadesNoLeidas), findsNothing);
      expect(find.text('Libertador San Martín'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isTrue);
    });

    testWidgets('las filas llegaron pero el pull no terminó: sigue la falla de lectura, no «sin '
        'ciudades»', (tester) async {
      await _montar(tester, pull: _demo(), terminoElPull: false);

      expect(find.text(TextosAlta.ciudadesNoLeidas), findsOneWidget);
      expect(find.text(TextosAlta.sinCiudades), findsNothing);
    });

    testWidgets('dos toques seguidos en «Reintentar» no rompen nada y la ciudad aparece una vez', (
      tester,
    ) async {
      final m = await _montar(tester, pull: null);
      await tester.runAsync(() async {
        await m.replica.bajar(_demo());
        await m.replica.terminoUnPull();
      });

      await _traer(tester, find.text('Reintentar'));
      await tester.tap(find.text('Reintentar'));
      await tester.tap(find.text('Reintentar'), warnIfMissed: false);
      await _asentar(tester);

      expect(find.text('Libertador San Martín'), findsOneWidget);
      expect(find.text(TextosAlta.ciudadesNoLeidas), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('la campaña de verdad no tiene ciudades', () {
    testWidgets('el aviso dice qué hacer y no se puede registrar', (tester) async {
      final sinCiudades =
          {
              ..._demo(),
              'campania_ciudad': <Map<String, Object?>>[],
              'zona': <Map<String, Object?>>[],
            }
            ..['campania_colportor'] = [
              filaInscripcion(
                'dede0000-0000-7000-800b-000000000002',
                campania: campaniaLsmId,
                usuario: colportorDemoId,
              ),
            ];
      await _montar(tester, pull: sinCiudades);
      await _tocar(tester, find.text('Casa'));

      expect(find.text(TextosAlta.sinCiudades), findsOneWidget);
      expect(find.text(TextosAlta.ciudadesNoLeidas), findsNothing);
      expect(_habilitado(tester, _registrar), isFalse);
    });
  });

  group('hallazgos de QA #548', () {
    // `testWidgets` solo acepta `skip: bool`: el motivo, con la convención «QA #<issue>», va en la
    // descripción. El implementador saca el `skip` cuando lo arregla.
    testWidgets(
      'QA #274: a 360×640 el aviso «No pudimos leer las ciudades…» y su «Reintentar» se ven sin '
      'desplazar la hoja',
      (tester) async {
        await _montar(tester, pull: null);

        // Hoy el aviso queda cortado a una línea sobre el pie fijo y «Reintentar» está bajo el borde
        // de la pantalla (y = 789 con 640 de alto): hay que desplazar la hoja para llegar a la salida.
        expect(find.text('Reintentar').hitTestable(), findsOneWidget);
      },
      skip: true,
    );
  });

  group('accesibilidad: 360×640 y 412×915, texto 1,0 y 2,0', () {
    final estados = <String, Future<_Montaje> Function(WidgetTester, Size, double)>{
      'detectada': (t, tam, esc) => _montar(t, pull: _demo(), tamano: tam, escala: esc),
      'de tu zona': (t, tam, esc) =>
          _montar(t, pull: _demo(), gps: _sinGps(), tamano: tam, escala: esc),
      'falla de lectura': (t, tam, esc) => _montar(t, pull: null, tamano: tam, escala: esc),
    };
    for (final MapEntry(key: nombre, value: abrir) in estados.entries) {
      for (final (tamano, escala) in [
        (_telefonoChico, 1.0),
        (_telefonoChico, 2.0),
        (_telefonoGrande, 2.0),
      ]) {
        testWidgets('$nombre a ${tamano.width.toInt()}×${tamano.height.toInt()} texto $escala: '
            'sin overflow, toque 48/44, etiquetas y contraste', (tester) async {
          final handle = tester.ensureSemantics();
          await abrir(tester, tamano, escala);

          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    }

    testWidgets(
      'el aviso de la falla de lectura se anuncia (live region) para el lector de pantalla',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _montar(tester, pull: null);

        final nodo = tester.getSemantics(find.text(TextosAlta.ciudadesNoLeidas));
        expect(
          nodo.getSemanticsData().flagsCollection.isLiveRegion ||
              _ancestroConLive(tester, find.text(TextosAlta.ciudadesNoLeidas)),
          isTrue,
          reason: 'un error que aparece solo tiene que anunciarse',
        );
        handle.dispose();
      },
    );
  });

  group('capturas para la revisión visual (`.dart_tool/qa_capturas`, no se commitean)', () {
    for (final (nombre, escala, tamano) in [
      ('detectada_360_x1', 1.0, _telefonoChico),
      ('detectada_360_x2', 2.0, _telefonoChico),
      ('detectada_412_x1', 1.0, _telefonoGrande),
    ]) {
      testWidgets('detectada $nombre', (tester) async {
        await _cargarFuentes(tester);
        await _montar(tester, pull: _demo(), tamano: tamano, escala: escala);
        await _capturar(tester, nombre);
      });
    }
    for (final (nombre, escala) in [('falla_360_x1', 1.0), ('falla_360_x2', 2.0)]) {
      testWidgets('falla de lectura $nombre', (tester) async {
        await _cargarFuentes(tester);
        await _montar(tester, pull: null, escala: escala);
        await _capturar(tester, nombre);
      });
    }
    testWidgets('de tu zona 360 x1', (tester) async {
      await _cargarFuentes(tester);
      await _montar(tester, pull: _demo(), gps: _sinGps());
      await _capturar(tester, 'de_tu_zona_360_x1');
    });
    testWidgets('lista Cambiar con dos ciudades 360 x1', (tester) async {
      await _cargarFuentes(tester);
      await _montar(
        tester,
        pull: sumarMontevideo(_demo(), usuario: colportorDemoId),
        gps: _sinGps(),
      );
      await _tocar(tester, find.text('de tu zona · Cambiar'));
      await _capturar(tester, 'cambiar_dos_ciudades_360_x1');
    });
    testWidgets('sin ciudades 360 x1', (tester) async {
      await _cargarFuentes(tester);
      await _montar(
        tester,
        pull: {
          ..._demo(),
          'campania_ciudad': <Map<String, Object?>>[],
          'zona': <Map<String, Object?>>[],
        },
      );
      await _capturar(tester, 'sin_ciudades_360_x1');
    });
  });
}

bool _ancestroConLive(WidgetTester tester, Finder f) {
  SemanticsNode? n = tester.getSemantics(f);
  while (n != null) {
    if (n.getSemanticsData().flagsCollection.isLiveRegion) return true;
    n = n.parent;
  }
  return false;
}

Map<String, List<Map<String, Object?>>> _demo() => pullDemoLsm(
  usuario: colportorDemoId,
  inscripcion: 'dede0000-0000-7000-800b-000000000002',
  zona: zonaCentroId,
);
