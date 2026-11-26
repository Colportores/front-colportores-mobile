// QA de #769 (PR #773, «Nombre ubic.», vistas 03 y 07): el campo opcional «Nombre del lugar» de hasta 80
// caracteres, con lo que el implementador no prueba: emoji y caracteres especiales (el campo cuenta
// caracteres visibles; el servidor, `char_length`, puntos de código; el caso de uso, unidades UTF-16), texto
// pegado muy largo, lo escrito que no se pierde tras una falla, y las guías de accesibilidad en los cuatro
// tamaños (360x640 y 412x915, texto al 100 % y al 200 %) con las fuentes reales.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/campos_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:dartz/dartz.dart' show Left;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/baja_ubicacion_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';
import '../../helpers/qa_vista37_387_arnes.dart' show cargarFuentes37, capturar37;

const _tamanos = <(String, Size)>[('360x640', Size(360, 640)), ('412x915', Size(412, 915))];

/// Texto al 100 % y al 200 %; con las fuentes reales de la app (anchos y desbordes) y con Ahem (el contraste: con
/// fuentes reales la guía mide el antialias del texto chico y da falsos positivos).
/// Primero con Ahem (el contraste) y después con las fuentes reales: cargarlas vale para todo el archivo.
const _skipEmoji =
    'QA #773: el campo cuenta caracteres visibles (80) pero el caso de uso cuenta unidades UTF-16 y el servidor '
    'puntos de código: 41 emoji se rechazan con «Revisá los datos» sin decir cuál campo';

final _matriz = <(String, Size, double, bool)>[
  for (final reales in const [true])
    for (final escala in const [1.0, 2.0])
      for (final (nombre, tamano) in _tamanos) (nombre, tamano, escala, reales),
];

Future<void> _fuentes(WidgetTester tester, bool reales) async {
  if (reales) await cargarFuentes37(tester);
}

void _sinDesborde(WidgetTester tester, bool reales) {
  final e = tester.takeException();
  if (reales) expect(e, isNull);
}

class _AnfitrionAlta extends StatelessWidget {
  const _AnfitrionAlta(this.salidas);

  final List<SalidaAltaUbicacion?> salidas;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async =>
            salidas.add(await AltaUbicacionPage.abrir(context, colportorId: 'col-1')),
        child: const Text('abrir'),
      ),
    ),
  );
}

class _AnfitrionEdicion extends StatelessWidget {
  const _AnfitrionEdicion(this.salidas);

  final List<SalidaModificarUbicacion?> salidas;

  @override
  Widget build(BuildContext context) => Scaffold(
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

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void _vista(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(List<Override> overrides, double escala, Widget home) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: temaClaro(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
      child: child!,
    ),
    home: home,
  ),
);

Future<RepoAltaFalso> _montarAlta(
  WidgetTester tester, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  List<SalidaAltaUbicacion?>? salidas,
}) async {
  _vista(tester, tamano);
  final repo = RepoAltaFalso();
  await tester.pumpWidget(
    _app(
      overridesAlta(
        geocodificador: GeocodificadorFalso(
          (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1234'),
        ),
        repo: repo,
        ahora: DateTime.utc(2026, 11, 26, 12),
        mapa: FabricaMapaFalsa(),
      ),
      escala,
      _AnfitrionAlta(salidas ?? []),
    ),
  );
  await tester.tap(find.text('abrir'));
  await _asentar(tester);
  return repo;
}

Future<RepoEdicionFalso> _montarEdicion(
  WidgetTester tester, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  Ubicacion? ubicacion,
}) async {
  _vista(tester, tamano);
  final repo = RepoEdicionFalso(ubicacion ?? ubicacionGuardada(), espacios: 1);
  final anfitrion = _AnfitrionEdicion(List<SalidaModificarUbicacion?>.empty(growable: true));
  await tester.pumpWidget(
    _app(
      [
        ...overridesAlta(
          geocodificador: GeocodificadorFalso(
            (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1250'),
          ),
          repo: repo,
          ahora: DateTime.utc(2026, 11, 26, 12),
          mapa: FabricaMapaFalsa(),
        ),
        consultorPendientesUbicacionProvider.overrideWithValue(PendientesFalso()),
      ],
      escala,
      anfitrion,
    ),
  );
  await tester.tap(find.text('abrir'));
  await _asentar(tester, 10);
  return repo;
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
Finder get _guardar => find.widgetWithText(FilledButton, TextosModificar.guardarCambios);
Finder get _campoNombre => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == TextosCampos.nombreSugerencia,
);

String _textoDel(WidgetTester tester) => tester.widget<TextField>(_campoNombre).controller!.text;

Future<void> _escribir(WidgetTester tester, String texto) async {
  await _traer(tester, _campoNombre);
  await tester.enterText(_campoNombre, texto);
  await tester.pump();
}

Future<void> _guias(WidgetTester tester, bool reales) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (!reales) await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  group('vista 03 · alta: tamaños y guías con el campo «Nombre del lugar»', () {
    for (final (nombre, tamano, escala, reales) in _matriz) {
      {
        testWidgets(
          '$nombre · texto ${escala}x ${reales ? 'real' : 'Ahem'} · vacío, con nombre largo y con las guías',
          (tester) async {
            await _fuentes(tester, reales);
            await _montarAlta(tester, tamano: tamano, escala: escala);
            await _traer(tester, _campoNombre);
            _sinDesborde(tester, reales);
            await _guias(tester, reales);
            if (reales) await capturar37(tester, '769_03_alta_nombre_vacio_${nombre}_$escala');

            await _escribir(tester, 'Farmacia ' * 20);
            expect(_textoDel(tester), hasLength(Ubicacion.largoMaximoDelNombre));
            _sinDesborde(tester, reales);
            await _guias(tester, reales);
            if (reales) await capturar37(tester, '769_03_alta_nombre_largo_${nombre}_$escala');
          },
        );
      }
    }
  });

  group('vista 07 · edición: tamaños y guías con el campo «Nombre del lugar»', () {
    for (final (nombre, tamano, escala, reales) in _matriz) {
      {
        testWidgets(
          '$nombre · texto ${escala}x ${reales ? 'real' : 'Ahem'} · con nombre guardado y con las guías',
          (tester) async {
            await _fuentes(tester, reales);
            await _montarEdicion(
              tester,
              tamano: tamano,
              escala: escala,
              ubicacion: ubicacionGuardada(nombre: 'Farmacia Italia'),
            );
            await _traer(tester, _campoNombre);
            expect(_textoDel(tester), 'Farmacia Italia');
            _sinDesborde(tester, reales);
            await _guias(tester, reales);
            if (reales) await capturar37(tester, '769_07_editar_nombre_${nombre}_$escala');
          },
        );
      }
    }
  });

  group('alta · entradas límite del nombre', () {
    testWidgets('texto pegado de 5 000 caracteres: el campo queda en 80 y se registra sin error', (
      tester,
    ) async {
      final repo = await _montarAlta(tester);
      await _escribir(tester, 'Casa de la esquina ' * 300);

      expect(_textoDel(tester), hasLength(80));
      await _tocar(tester, _registrar);

      expect(repo.llamadas, hasLength(1));
      expect(repo.llamadas.single.ubicacion.nombre!.length, lessThanOrEqualTo(80));
    });

    testWidgets('caracteres especiales (comillas, <, &, %, ;, --) se guardan tal cual', (
      tester,
    ) async {
      final repo = await _montarAlta(tester);
      const raro = '<b>"Casa" & \'Pepe\' 100%; -- x_y';
      await _escribir(tester, raro);
      await _tocar(tester, _registrar);

      expect(repo.llamadas.single.ubicacion.nombre, raro);
    });

    testWidgets('con tildes y eñes en el límite exacto (80 letras) se registra', (tester) async {
      final repo = await _montarAlta(tester);
      final nombre = 'ñ' * 80;
      await _escribir(tester, nombre);

      expect(_textoDel(tester), nombre);
      await _tocar(tester, _registrar);
      expect(repo.llamadas.single.ubicacion.nombre, nombre);
    });

    group('con emoji en el alta', () {
      testWidgets(
        'con emoji (41 = 41 caracteres para el campo y el servidor) «Registrar» guarda el nombre',
        (tester) async {
          final repo = await _montarAlta(tester);
          final nombre = '😀' * 41;
          await _escribir(tester, nombre);
          expect(_textoDel(tester), nombre, reason: 'el campo admite hasta 80 caracteres visibles');

          await _tocar(tester, _registrar);

          expect(
            repo.llamadas,
            hasLength(1),
            reason: 'el caso de uso contó UTF-16 (82) y lo rechazó',
          );
          expect(repo.llamadas.single.ubicacion.nombre, nombre);
        },
      );
    }, skip: _skipEmoji);

    testWidgets('si registrar falla, lo escrito en el nombre sigue y «Registrar» se puede tocar', (
      tester,
    ) async {
      final repo = await _montarAlta(tester);
      repo.comportamiento = (_) async => const Left(FailureInesperado());
      await _escribir(tester, 'Farmacia Italia');
      await _tocar(tester, _registrar);

      expect(find.text(TextosAlta.noPudimosGuardar), findsWidgets);
      expect(_textoDel(tester), 'Farmacia Italia');
      expect(tester.widget<FilledButton>(_registrar).onPressed, isNotNull);

      repo.comportamiento = null;
      await _tocar(tester, _registrar);
      expect(repo.llamadas, hasLength(2));
      expect(repo.llamadas.last.ubicacion.nombre, 'Farmacia Italia');
    });
  });

  group('edición · entradas límite del nombre', () {
    testWidgets('texto pegado de 5 000 caracteres: queda en 80 y «Guardar cambios» guarda', (
      tester,
    ) async {
      final repo = await _montarEdicion(tester);
      await _escribir(tester, 'Casa de la esquina ' * 300);

      expect(_textoDel(tester), hasLength(80));
      await _tocar(tester, _guardar);

      expect(repo.escrituras, hasLength(1));
    });

    group('con emoji en la edición', () {
      testWidgets('con emoji (41) «Guardar cambios» guarda el nombre', (tester) async {
        final repo = await _montarEdicion(tester);
        final nombre = '😀' * 41;
        await _escribir(tester, nombre);
        await _tocar(tester, _guardar);

        expect(
          repo.escrituras,
          hasLength(1),
          reason: 'el caso de uso contó UTF-16 (82) y lo rechazó',
        );
      });
    }, skip: _skipEmoji);

    testWidgets('solo espacios en un nombre que existía lo borra (queda sin nombre)', (
      tester,
    ) async {
      final repo = await _montarEdicion(
        tester,
        ubicacion: ubicacionGuardada(nombre: 'Farmacia Italia'),
      );
      await _escribir(tester, '      ');
      await _tocar(tester, _guardar);

      expect(repo.escrituras, hasLength(1));
      expect(repo.escrituras.single.nueva.nombre, isNull);
    });
  });
}
