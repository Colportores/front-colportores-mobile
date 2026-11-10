// QA de «Mapas offline» con el departamento y Uruguay (vista 35, HU-SYNC-010, #287): lo que los
// tests del implementador no miden. Cada estado del canvas (35-01 a 35-09, cargando, sin catálogo,
// error de lugar, error de descarga) con los dos mapas grandes, a 360x640 y 412x915 con el texto al
// 100 % y al 200 %: sin overflow y con tres de las cuatro guías de accesibilidad de Flutter (el
// contraste va en `qa_mapas_offline_departamento_uruguay_287_contraste_test.dart`, sin fuentes
// reales). Además: el aviso de «Te faltan X MB» a la vista, los bordes de singular y plural, la
// normalización del departamento y los casos límite de acciones superpuestas. Las capturas con
// `--dart-define=QA_CAPTURAS=true` (a `.dart_tool/qa_capturas`, fuera del repo).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/lugar_de_trabajo.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/fuente_lugar_de_trabajo.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:colportores_mobile/features/tiles/presentation/pages/mapas_offline_page.dart';
import 'package:colportores_mobile/features/tiles/presentation/providers/mapas_offline_providers.dart';
import 'package:colportores_mobile/features/tiles/presentation/textos_mapas_offline.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mapa_descargas_arnes.dart';
import '../helpers/tiles_falsos.dart';

const _capturar = bool.fromEnvironment('QA_CAPTURAS');

/// Con las fuentes de prueba (Ahem) el contraste se mide bien; con las reales da falsos negativos.
const _sinFuentes = bool.fromEnvironment('QA_SIN_FUENTES');

// ---------------------------------------------------------------------------------------------
// Datos.
// ---------------------------------------------------------------------------------------------

final class _Fuente implements FuenteLugarDeTrabajo {
  const _Fuente(this.lugar);

  final LugarDeTrabajo lugar;

  @override
  Future<Either<Failure, LugarDeTrabajo>> leer() async => Right(lugar);
}

final class _FuenteQueFalla implements FuenteLugarDeTrabajo {
  const _FuenteQueFalla();

  @override
  Future<Either<Failure, LugarDeTrabajo>> leer() async =>
      const Left(FailureLugarDeTrabajoNoDisponible());
}

final class _FuenteLenta implements FuenteLugarDeTrabajo {
  final espera = Completer<void>();

  @override
  Future<Either<Failure, LugarDeTrabajo>> leer() async {
    await espera.future;
    return Right(_lugarEn('san jose'));
  }
}

LugarDeTrabajo _lugarEn(String? departamento, {String? zona}) => LugarDeTrabajo(
  ambito: AmbitoTrabajo(zonaId: zona, ciudadId: 'c-1', departamentoId: departamento),
  zonaNombre: zona == null ? null : 'Cerro Norte',
  ciudadNombre: 'Montevideo',
);

PaqueteTiles _paquete(
  String id,
  NivelCobertura nivel,
  String? ambitoId,
  String nombre,
  int bytes, {
  String version = 'v1',
}) => PaqueteTiles(
  id: id,
  nivel: nivel,
  ambitoId: ambitoId,
  nombre: nombre,
  version: version,
  partes: [
    ParteTiles(
      origen: Uri.parse('https://tiles.test/$id.pmtiles'),
      tamanoBytes: bytes,
      sha256: 'a' * 64,
    ),
  ],
);

const _mb = 1000 * 1000;
final _ciudad86 = _paquete(
  'ciudad-montevideo',
  NivelCobertura.ciudad,
  'c-1',
  'Montevideo',
  86 * _mb,
);
final _depto250 = _paquete(
  'depto-san-jose',
  NivelCobertura.departamento,
  'san jose',
  'San José',
  250 * _mb,
);
final _uruguay1200 = _paquete('uruguay', NivelCobertura.uruguay, null, 'Todo Uruguay', 1200 * _mb);
final _uruguay1200v2 = _paquete(
  'uruguay',
  NivelCobertura.uruguay,
  null,
  'Todo Uruguay',
  1300 * _mb,
  version: 'v2',
);

final _bytesUruguay = bytesDePrueba(5500, semilla: 11);
final _uruguayReal = paqueteDe(
  _bytesUruguay,
  id: 'uruguay',
  nivel: NivelCobertura.uruguay,
  ambitoId: null,
);
final _bytesDepto = bytesDePrueba(4200, semilla: 5);
final _deptoReal = paqueteDe(
  _bytesDepto,
  id: 'depto-san-jose',
  nivel: NivelCobertura.departamento,
  ambitoId: 'san jose',
);

ArnesMapa _arnes(List<PaqueteTiles> catalogo, {TipoConexion conexion = TipoConexion.wifi}) =>
    ArnesMapa(conexion: conexion, catalogo: catalogo, servirPaqueteMontevideo: false);

// ---------------------------------------------------------------------------------------------
// Montaje.
// ---------------------------------------------------------------------------------------------

_Montaje? _ultimo;

final class _Montaje {
  final abierto = ValueNotifier<bool>(true);
  final raiz = GlobalKey();
}

bool _fuentesCargadas = false;

Future<void> _cargarFuentes(WidgetTester tester) async {
  if (_fuentesCargadas || _sinFuentes) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await c.load();
    }
    final dart = File(Platform.resolvedExecutable);
    final iconos = File(
      '${dart.parent.parent.parent.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (iconos.existsSync()) {
      final c = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(iconos.readAsBytesSync().buffer)));
      await c.load();
    }
  });
  _fuentesCargadas = true;
}

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_Montaje> _montar(
  WidgetTester tester, {
  required ArnesMapa arnes,
  LugarDeTrabajo? lugar,
  FuenteLugarDeTrabajo? fuente,
  int libres = 4000 * _mb,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool asentar = true,
}) async {
  await _cargarFuentes(tester);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => unawaited(arnes.cerrar()));
  final espacio = EspacioFalso()..libres = libres;
  final montaje = _Montaje();
  _ultimo = montaje;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...arnes.overrides,
        fuenteLugarDeTrabajoProvider.overrideWithValue(
          fuente ?? _Fuente(lugar ?? _lugarEn('san jose')),
        ),
        medidorEspacioDiscoProvider.overrideWithValue(espacio),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: RepaintBoundary(key: montaje.raiz, child: child!),
        ),
        home: ValueListenableBuilder<bool>(
          valueListenable: montaje.abierto,
          builder: (_, abierto, _) =>
              abierto ? const MapasOfflinePage() : const Scaffold(body: Text('afuera')),
        ),
      ),
    ),
  );
  if (asentar) await _asentar(tester);
  return montaje;
}

Finder _clave(String clave) => find.byKey(Key(clave));

bool _habilitado(WidgetTester tester, String clave) =>
    tester.widget<ButtonStyleButton>(_clave(clave)).onPressed != null;

/// Toca llevando antes el control a la vista (a 360x640 con texto al 200 % queda bajo el pliegue).
Future<void> _tocar(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 80, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(finder);
  await _asentar(tester);
}

Future<void> _elegir(WidgetTester tester, NivelCobertura nivel) =>
    _tocar(tester, _clave('mapas_offline_nivel_${nivel.name}'));

/// ¿El aviso [clave] está entero dentro de la pantalla ahora mismo?
bool _aLaVista(WidgetTester tester, String clave) {
  final f = _clave(clave);
  if (f.evaluate().isEmpty) return false;
  final r = tester.getRect(f);
  final pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
  return r.top >= 0 && r.bottom <= pantalla.height;
}

// ---------------------------------------------------------------------------------------------
// Los estados del canvas con los dos mapas grandes.
// ---------------------------------------------------------------------------------------------

typedef _Armar = Future<void> Function(WidgetTester tester, Size tamano, double escala);

Future<void> _estado01(WidgetTester tester, Size t, double e, NivelCobertura nivel) async {
  await _montar(tester, arnes: _arnes([_ciudad86, _depto250, _uruguay1200]), tamano: t, escala: e);
  await _elegir(tester, nivel);
}

Future<void> _sinEspacio(WidgetTester tester, Size t, double e, NivelCobertura nivel) async {
  await _montar(
    tester,
    arnes: _arnes([_ciudad86, _depto250, _uruguay1200]),
    tamano: t,
    escala: e,
    libres: 40 * _mb,
  );
  await _elegir(tester, nivel);
}

Future<ArnesMapa> _bajando(WidgetTester tester, Size t, double e, {bool pausar = false}) async {
  final arnes = _arnes([_ciudad86, _uruguayReal])
    ..servidor.archivos[_uruguayReal.origen] = _bytesUruguay
    ..servidor.retenerDespuesDe = 2000;
  await _montar(tester, arnes: arnes, tamano: t, escala: e);
  await _elegir(tester, NivelCobertura.uruguay);
  await _tocar(tester, _clave('mapas_offline_descargar'));
  if (pausar) await _tocar(tester, _clave('mapas_offline_pausar_uruguay'));
  return arnes;
}

final _estados = <String, _Armar>{
  '35-01 elegir Uruguay': (t, s, e) => _estado01(t, s, e, NivelCobertura.uruguay),
  '35-01 elegir departamento': (t, s, e) => _estado01(t, s, e, NivelCobertura.departamento),
  '35-02 datos móviles con Uruguay': (t, s, e) async {
    await _montar(
      t,
      arnes: _arnes([_ciudad86, _uruguay1200], conexion: TipoConexion.datosMoviles),
      tamano: s,
      escala: e,
    );
    await _elegir(t, NivelCobertura.uruguay);
  },
  '35-03 sin zona (departamento elegido)': (t, s, e) =>
      _estado01(t, s, e, NivelCobertura.departamento),
  '35-04 sin espacio · Uruguay': (t, s, e) => _sinEspacio(t, s, e, NivelCobertura.uruguay),
  '35-04 sin espacio · departamento': (t, s, e) =>
      _sinEspacio(t, s, e, NivelCobertura.departamento),
  '35-04 sin espacio · ciudad': (t, s, e) => _sinEspacio(t, s, e, NivelCobertura.ciudad),
  '35-05 descargando Uruguay': (t, s, e) async {
    await _bajando(t, s, e);
  },
  '35-06 pausada Uruguay': (t, s, e) async {
    await _bajando(t, s, e, pausar: true);
  },
  '35-07 Uruguay descargado': (t, s, e) async {
    final arnes = _arnes([_ciudad86, _uruguay1200]);
    await arnes.repositorio.registrar(descargadoDe(_uruguay1200));
    await _montar(t, arnes: arnes, tamano: s, escala: e);
  },
  '35-07 departamento y Uruguay descargados': (t, s, e) async {
    final arnes = _arnes([_ciudad86, _depto250, _uruguay1200]);
    await arnes.repositorio.registrar(descargadoDe(_depto250));
    await arnes.repositorio.registrar(descargadoDe(_uruguay1200));
    await _montar(t, arnes: arnes, tamano: s, escala: e);
  },
  '35-08 versión nueva de Uruguay': (t, s, e) async {
    final arnes = _arnes([_ciudad86, _uruguay1200v2]);
    await arnes.repositorio.registrar(descargadoDe(_uruguay1200));
    await _montar(t, arnes: arnes, tamano: s, escala: e);
  },
  '35-09 achicar desde Uruguay': (t, s, e) async {
    final arnes = _arnes([_ciudad86, _uruguay1200]);
    await arnes.repositorio.registrar(descargadoDe(_uruguay1200));
    await _montar(t, arnes: arnes, tamano: s, escala: e);
    await _tocar(t, _clave('mapas_offline_cambiar_cobertura'));
    await _elegir(t, NivelCobertura.ciudad);
    await _tocar(t, _clave('mapas_offline_descargar'));
  },
  'cargando': (t, s, e) async {
    await _montar(
      t,
      arnes: _arnes([_ciudad86, _uruguay1200]),
      fuente: _FuenteLenta(),
      tamano: s,
      escala: e,
      asentar: false,
    );
    await t.pump(const Duration(milliseconds: 60));
  },
  'sin catálogo y sin conexión': (t, s, e) async {
    final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, servirPaqueteMontevideo: false);
    arnes.repositorio.falloCatalogo = const FailureSinConexion();
    await _montar(t, arnes: arnes, tamano: s, escala: e);
  },
  'no se sabe dónde trabaja': (t, s, e) async {
    await _montar(
      t,
      arnes: _arnes([_ciudad86, _uruguay1200]),
      fuente: const _FuenteQueFalla(),
      tamano: s,
      escala: e,
    );
  },
  'error de descarga de Uruguay': (t, s, e) async {
    final arnes = _arnes([_ciudad86, _uruguayReal])
      ..servidor.archivos[_uruguayReal.origen] = _bytesUruguay
      ..servidor.statusError = 500;
    await _montar(t, arnes: arnes, tamano: s, escala: e);
    await _elegir(t, NivelCobertura.uruguay);
    await _tocar(t, _clave('mapas_offline_descargar'));
  },
};

const _tamanos = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

void main() {
  group('matriz de estados × tamaños × escala: sin overflow y con las guías de toque', () {
    for (final estado in _estados.entries) {
      for (final tam in _tamanos.entries) {
        for (final escala in [1.0, 2.0]) {
          testWidgets('${estado.key} · ${tam.key} · ×${escala.toInt()}', (tester) async {
            await estado.value(tester, tam.value, escala);
            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          });
        }
      }
    }
  });

  // Se corre con --dart-define=QA_SIN_FUENTES=true (sin fuentes reales el layout es de prueba).
  group('contraste de texto (guía de Flutter) en cada estado, 412x915 al 100 %', () {
    for (final estado in _estados.entries) {
      testWidgets(estado.key, (tester) async {
        await estado.value(tester, const Size(412, 915), 1);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }, skip: !_sinFuentes);
    }
  });

  group('35-04 · «Te faltan X MB» a la vista cuando se elige un mapa que no entra', () {
    for (final nivel in [NivelCobertura.uruguay, NivelCobertura.departamento]) {
      for (final tam in _tamanos.entries) {
        for (final escala in [1.0, 2.0]) {
          testWidgets(
            '${nivel.name} · ${tam.key} · ×${escala.toInt()}: el aviso queda a la vista y no deja descargar',
            (tester) async {
              await _sinEspacio(tester, tam.value, escala, nivel);

              expect(_clave('mapas_offline_sin_espacio'), findsOneWidget);
              expect(_habilitado(tester, 'mapas_offline_descargar'), isFalse);
              expect(
                _aLaVista(tester, 'mapas_offline_sin_espacio'),
                isTrue,
                reason: 'la colportora eligió ${nivel.name} y el aviso con cuánto falta no se ve',
              );
            },
          );
        }
      }
    }

    testWidgets('el aviso se anuncia al lector (región viva) y trae la acción a mano', (
      tester,
    ) async {
      await _sinEspacio(tester, const Size(412, 915), 1, NivelCobertura.uruguay);
      final semantica = tester.getSemantics(_clave('mapas_offline_sin_espacio'));
      expect(semantica, isSemantics(isLiveRegion: true));
      expect(
        find.text(
          'No hay lugar: Todo Uruguay ocupa 1,2 GB y te quedan 40 MB. Te faltan 1,2 GB. '
          'Elegí un mapa más chico o liberá espacio.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'la salida existe: el aviso nombra el mapa más chico y esas opciones se pueden tocar',
      (tester) async {
        await _sinEspacio(tester, const Size(412, 915), 1, NivelCobertura.uruguay);
        // 40 MB libres: la ciudad (86 MB) tampoco entra, pero «Mi departamento» y «Mi ciudad» siguen
        // tocables para ver su peso; nada queda trabado.
        await _elegir(tester, NivelCobertura.departamento);
        expect(
          find.textContaining(
            'No hay lugar: San José ocupa 250 MB y te quedan 40 MB. Te faltan 210 MB.',
          ),
          findsOneWidget,
        );
        await _elegir(tester, NivelCobertura.ciudad);
        expect(
          find.text(
            'No hay lugar: Montevideo ocupa 86 MB y te quedan 40 MB. Liberá espacio en el teléfono.',
          ),
          findsOneWidget,
          reason: 'la ciudad queda con el texto del canvas, sin «Te faltan»',
        );
      },
    );
  });

  group('«Te faltan» · singular, plural y bordes de unidad', () {
    // (libres, esperado). El mapa de Uruguay pesa 1200 MB.
    final casos = <(String, int, String)>[
      ('1 MB exacto', 1199 * _mb, 'Te falta 1 MB.'),
      ('un byte menos del peso', 1200 * _mb - 1, 'Te falta 1 MB.'),
      ('11 MB', 1189 * _mb, 'Te faltan 11 MB.'),
      ('101 MB', 1099 * _mb, 'Te faltan 101 MB.'),
      ('999 MB', 201 * _mb, 'Te faltan 999 MB.'),
      ('1000 MB justos', 200 * _mb, 'Te faltan 1,0 GB.'),
      ('1,2 GB (libres 0)', 0, 'Te faltan 1,2 GB.'),
    ];
    for (final c in casos) {
      testWidgets(c.$1, (tester) async {
        await _montar(
          tester,
          arnes: _arnes([_ciudad86, _uruguay1200]),
          tamano: const Size(412, 915),
          libres: c.$2,
        );
        await _elegir(tester, NivelCobertura.uruguay);
        expect(find.textContaining(c.$3), findsOneWidget);
        expect(_habilitado(tester, 'mapas_offline_descargar'), isFalse);
      });
    }

    testWidgets('justo lo que pesa (libres = peso): entra y deja descargar', (tester) async {
      await _montar(
        tester,
        arnes: _arnes([_ciudad86, _uruguay1200]),
        tamano: const Size(412, 915),
        libres: 1200 * _mb,
      );
      await _elegir(tester, NivelCobertura.uruguay);
      expect(_clave('mapas_offline_sin_espacio'), findsNothing);
      expect(_habilitado(tester, 'mapas_offline_descargar'), isTrue);
    });

    test('el avance de una descarga cambia de unidad en el borde de los 1000 MB', () {
      expect(TextosMapasOffline.avanceDe(412 * _mb, 999 * _mb), '412 de 999 MB');
      expect(TextosMapasOffline.avanceDe(412 * _mb, 1200 * _mb), '412 MB de 1,2 GB');
      expect(TextosMapasOffline.avanceDe(0, 1200 * _mb), '0 MB de 1,2 GB');
      expect(TextosMapasOffline.avanceDe(1199 * _mb, 1200 * _mb), '1,1 GB de 1,2 GB');
    });
  });

  group('el departamento se compara por su nombre normalizado', () {
    final casos = <(String, String?, bool)>[
      ('con tilde y mayúsculas', 'SAN JOSÉ', true),
      ('espacios de más', '  san   jose ', true),
      ('Río Negro', 'Río Negro', true),
      ('otro departamento', 'Florida', false),
      ('vacío', '', false),
      ('solo espacios', '    ', false),
      ('sin departamento', null, false),
    ];
    for (final c in casos) {
      testWidgets('${c.$1} → ${c.$3 ? 'se ofrece' : 'no se ofrece'}', (tester) async {
        final catalogo = c.$1 == 'Río Negro'
            ? _paquete('depto-rn', NivelCobertura.departamento, 'rio negro', 'Río Negro', 300 * _mb)
            : _depto250;
        await _montar(
          tester,
          arnes: _arnes([_ciudad86, catalogo]),
          lugar: _lugarEn(c.$2),
          tamano: const Size(412, 915),
        );
        final peso = c.$1 == 'Río Negro' ? 'Río Negro · 300 MB' : 'San José · 250 MB';
        expect(find.text(peso), c.$3 ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('el catálogo con el nombre sin normalizar («San José») también cubre', (
      tester,
    ) async {
      final raro = _paquete('d', NivelCobertura.departamento, 'San José', 'San José', 250 * _mb);
      await _montar(tester, arnes: _arnes([_ciudad86, raro]), tamano: const Size(412, 915));
      expect(find.text('San José · 250 MB'), findsOneWidget);
    });

    test('un departamento con otro departamento nunca se confunde por prefijo', () {
      final p = _depto250;
      expect(p.cubre(const AmbitoTrabajo(ciudadId: 'c', departamentoId: 'san')), isFalse);
      expect(p.cubre(const AmbitoTrabajo(ciudadId: 'c', departamentoId: 'san jose 2')), isFalse);
      expect(p.cubre(const AmbitoTrabajo(ciudadId: 'c', departamentoId: 'San José')), isTrue);
    });
  });

  group('lo que lee el lector de pantalla en cada opción', () {
    testWidgets('«Todo Uruguay» dice su peso; la que no está disponible se anuncia apagada', (
      tester,
    ) async {
      await _montar(tester, arnes: _arnes([_ciudad86, _uruguay1200]), tamano: const Size(412, 915));
      final uruguay = tester.getSemantics(_clave('mapas_offline_nivel_uruguay'));
      expect(uruguay.label, 'Todo Uruguay. 1,2 GB');
      final depto = tester.getSemantics(_clave('mapas_offline_nivel_departamento'));
      expect(depto.label, 'Mi departamento. Todavía no está disponible');
      expect(depto, isSemantics(isEnabled: false));
    });
  });

  group('casos límite del flujo con Uruguay y el departamento', () {
    testWidgets('alternar rápido entre los dos mapas deja una sola elección', (tester) async {
      await _montar(
        tester,
        arnes: _arnes([_ciudad86, _depto250, _uruguay1200]),
        tamano: const Size(412, 915),
      );
      for (var i = 0; i < 4; i++) {
        await tester.tap(_clave('mapas_offline_nivel_departamento'));
        await tester.pump(const Duration(milliseconds: 10));
        await tester.tap(_clave('mapas_offline_nivel_uruguay'));
        await tester.pump(const Duration(milliseconds: 10));
      }
      await _asentar(tester);
      final marcadas = [
        for (final n in NivelCobertura.values)
          if (tester
                  .getSemantics(_clave('mapas_offline_nivel_${n.name}'))
                  .getSemanticsData()
                  .flagsCollection
                  .isChecked ==
              ui.CheckedState.isTrue)
            n,
      ];
      expect(marcadas, [NivelCobertura.uruguay]);
    });

    testWidgets('pausar y seguir Uruguay: sigue del byte que quedó y termina', (tester) async {
      final arnes = await _bajando(tester, const Size(412, 915), 1, pausar: true);
      expect(find.text('En pausa'), findsOneWidget);
      expect(_habilitado(tester, 'mapas_offline_seguir_uruguay'), isTrue);

      arnes.servidor.retenerDespuesDe = null;
      await _tocar(tester, _clave('mapas_offline_seguir_uruguay'));
      expect(_clave('mapas_offline_listo_uruguay'), findsOneWidget);
      expect(arnes.servidor.pedidos.first, 0);
      expect(arnes.servidor.pedidos.length, 2);
      expect(arnes.servidor.pedidos.last, greaterThan(0));
      expect(arnes.repositorio.registrados.map((p) => p.id), ['uruguay']);
    });

    testWidgets('borrar el departamento mientras baja Uruguay: se va uno y el otro sigue', (
      tester,
    ) async {
      final arnes = _arnes([_ciudad86, _deptoReal, _uruguayReal])
        ..servidor.archivos[_uruguayReal.origen] = _bytesUruguay
        ..servidor.archivos[_deptoReal.origen] = _bytesDepto;
      await arnes.repositorio.registrar(descargadoDe(_deptoReal));
      await _montar(tester, arnes: arnes, tamano: const Size(412, 915));
      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);

      await _tocar(tester, _clave('mapas_offline_cambiar_cobertura'));
      await _elegir(tester, NivelCobertura.uruguay);
      arnes.servidor.retenerDespuesDe = 2000;
      await _tocar(tester, _clave('mapas_offline_descargar'));
      // Desde «Cambiar cobertura» la descarga en marcha se ve en la lista.
      expect(_clave('mapas_offline_tarjeta_uruguay'), findsOneWidget);
      expect(_clave('mapas_offline_tarjeta_depto-san-jose'), findsOneWidget);

      await _tocar(tester, _clave('mapas_offline_borrar_depto-san-jose'));
      await _tocar(tester, _clave('mapas_offline_borrar_confirmar'));
      expect(_clave('mapas_offline_tarjeta_depto-san-jose'), findsNothing);
      expect(_clave('mapas_offline_tarjeta_uruguay'), findsOneWidget);
      expect(find.text('36 %'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // QA #287: la colportora que ya tiene su ciudad toca «Cambiar cobertura», elige Uruguay y
    // «Descargar»: la descarga arranca (hay un pedido al servidor) pero la pantalla sigue en la 01, sin
    // barra de progreso ni aviso, con «Descargar» habilitado: «cambiando» solo se apaga al terminar.
    testWidgets(
      'bajar Uruguay desde «Cambiar cobertura» muestra la descarga en marcha (progreso visible)',
      (tester) async {
        final arnes = _arnes([_ciudad86, _uruguayReal])
          ..servidor.archivos[_uruguayReal.origen] = _bytesUruguay
          ..servidor.retenerDespuesDe = 2000;
        await arnes.repositorio.registrar(descargadoDe(_ciudad86));
        await _montar(tester, arnes: arnes, tamano: const Size(412, 915));
        await _tocar(tester, _clave('mapas_offline_cambiar_cobertura'));
        await _elegir(tester, NivelCobertura.uruguay);

        await _tocar(tester, _clave('mapas_offline_descargar'));

        expect(arnes.servidor.pedidos, [0], reason: 'la descarga sí arrancó');
        expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
        expect(_clave('mapas_offline_tarjeta_uruguay'), findsOneWidget);
        expect(find.text('36 %'), findsOneWidget);
      },
    );

    testWidgets(
      'con Uruguay bajando desde «Cambiar cobertura», «Descargar» no queda habilitado para tocarlo otra vez',
      (tester) async {
        final arnes = _arnes([_ciudad86, _uruguayReal])
          ..servidor.archivos[_uruguayReal.origen] = _bytesUruguay
          ..servidor.retenerDespuesDe = 2000;
        await arnes.repositorio.registrar(descargadoDe(_ciudad86));
        await _montar(tester, arnes: arnes, tamano: const Size(412, 915));
        await _tocar(tester, _clave('mapas_offline_cambiar_cobertura'));
        await _elegir(tester, NivelCobertura.uruguay);
        await _tocar(tester, _clave('mapas_offline_descargar'));
        if (_clave('mapas_offline_descargar').evaluate().isNotEmpty) {
          await tester.tap(_clave('mapas_offline_descargar'));
          await _asentar(tester);
        }
        expect(arnes.servidor.pedidos, [0], reason: 'un segundo toque no pide otra vez');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('«Atrás» desde «Cambiar cobertura» vuelve a la lista y de ahí sale', (
      tester,
    ) async {
      final arnes = _arnes([_ciudad86, _uruguay1200]);
      await arnes.repositorio.registrar(descargadoDe(_uruguay1200));
      await _montar(tester, arnes: arnes, tamano: const Size(412, 915));
      await _tocar(tester, _clave('mapas_offline_cambiar_cobertura'));
      expect(find.text('MAPAS OFFLINE · 01'), findsOneWidget);
      await _tocar(tester, _clave('mapas_offline_atras'));
      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
      expect(_clave('mapas_offline_listo_uruguay'), findsOneWidget);
    });

    testWidgets('sin conexión: Uruguay se puede elegir y el botón dice «Descargar con Wi-Fi»', (
      tester,
    ) async {
      await _montar(
        tester,
        arnes: _arnes([_ciudad86, _uruguay1200], conexion: TipoConexion.sinConexion),
        tamano: const Size(412, 915),
      );
      await _elegir(tester, NivelCobertura.uruguay);
      expect(find.text('Descargar con Wi-Fi'), findsOneWidget);
      expect(_clave('mapas_offline_sin_conexion'), findsOneWidget);
    });

    testWidgets('Uruguay descargado: elegirlo de nuevo dice que ya lo tiene y no ofrece bajarlo', (
      tester,
    ) async {
      final arnes = _arnes([_ciudad86, _uruguay1200]);
      await arnes.repositorio.registrar(descargadoDe(_uruguay1200));
      await _montar(tester, arnes: arnes, tamano: const Size(412, 915));
      await _tocar(tester, _clave('mapas_offline_cambiar_cobertura'));
      await _elegir(tester, NivelCobertura.uruguay);
      expect(_clave('mapas_offline_ya_lo_tenes'), findsOneWidget);
      expect(_habilitado(tester, 'mapas_offline_descargar'), isFalse);
    });
  });

  group('privacidad', () {
    test('ni el paquete ni el ámbito imprimen sus datos en toString', () {
      expect(_depto250.toString(), isNot(contains('san jose')));
      expect(
        const AmbitoTrabajo(ciudadId: 'c-secreta', departamentoId: 'san jose').toString(),
        isNot(contains('c-secreta')),
      );
    });
  });

  testWidgets('capturas', (tester) async {
    await _cargarFuentes(tester);
    Directory('.dart_tool/qa_capturas').createSync(recursive: true);
    var n = 0;
    for (final estado in _estados.entries) {
      for (final tam in _tamanos.entries) {
        for (final escala in [1.0, 2.0]) {
          await estado.value(tester, tam.value, escala);
          await tester.pump(const Duration(milliseconds: 80));
          await tester.runAsync(() async {
            final r = tester.renderObject<RenderRepaintBoundary>(find.byKey(_ultimo!.raiz));
            final img = await r.toImage();
            final bd = (await img.toByteData(format: ui.ImageByteFormat.png))!;
            final nombre = estado.key.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
            File(
              '.dart_tool/qa_capturas/287_${nombre}_${tam.key}_x${escala.toInt()}.png',
            ).writeAsBytesSync(Uint8List.view(bd.buffer));
          });
          n++;
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
    expect(n, _estados.length * 4);
  }, skip: !_capturar);
}
