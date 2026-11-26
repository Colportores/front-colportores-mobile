// «Nombre ubic.» (Cristian, 24/11; #769, backend-supabase 0206): el campo opcional «Nombre del lugar» de
// hasta 80 caracteres en el alta de una ubicación (vista 03, la hoja «Nueva ubicación»), con el aviso de no
// poner datos de clientes. Es opcional: sin escribir nada el alta es la de siempre.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/campos_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/mapa_base_falso.dart';

/// La pantalla que abre el alta y guarda cómo se cerró.
class _Anfitrion extends StatelessWidget {
  const _Anfitrion(this.salidas);

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

Future<void> _asentar(WidgetTester tester, [int veces = 6]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<RepoAltaFalso> _montar(
  WidgetTester tester, {
  RepoAltaFalso? repo,
  double escala = 1,
  Size tamano = const Size(390, 844),
  List<SalidaAltaUbicacion?>? salidas,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repoFalso = repo ?? RepoAltaFalso();
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesAlta(
        geocodificador: GeocodificadorFalso(
          (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1234'),
        ),
        repo: repoFalso,
        ahora: DateTime.utc(2026, 11, 26, 12),
        mapa: FabricaMapaFalsa(),
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: _Anfitrion(salidas ?? []),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await _asentar(tester);
  return repoFalso;
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

/// El `TextField` del nombre: el que tiene el texto de ayuda «Ej.: Farmacia Italia».
Finder get _campoNombre => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == TextosCampos.nombreSugerencia,
);

String _textoDel(WidgetTester tester) => tester.widget<TextField>(_campoNombre).controller!.text;

void main() {
  group('vista 03 · el campo «Nombre del lugar»', () {
    testWidgets(
      'está después de la dirección, dice que es opcional y avisa que no son datos de clientes',
      (tester) async {
        await _montar(tester);
        await _traer(tester, _campoNombre);

        expect(find.text(TextosCampos.nombre), findsOneWidget);
        expect(find.text('NOMBRE DEL LUGAR · OPCIONAL'), findsOneWidget);
        expect(
          find.text('Es el nombre del lugar. No pongas nombres ni datos de tus clientes.'),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(_campoNombre).dy,
          greaterThan(tester.getTopLeft(find.byType(TextField).first).dy),
        );
      },
    );

    testWidgets('sin escribir nada el alta es la de siempre: «Registrar» habilitado y sin nombre', (
      tester,
    ) async {
      final salidas = <SalidaAltaUbicacion?>[];
      final repo = await _montar(tester, salidas: salidas);

      expect(tester.widget<FilledButton>(_registrar).onPressed, isNotNull);
      await _tocar(tester, _registrar);

      expect(repo.llamadas.single.ubicacion.nombre, isNull);
      expect(salidas.single, isA<UbicacionCreada>());
    });

    testWidgets('lo que se escribe se registra recortado', (tester) async {
      final repo = await _montar(tester);

      await tester.enterText(_campoNombre, '  Farmacia Italia ');
      await tester.pump();
      await _tocar(tester, _registrar);

      expect(repo.llamadas.single.ubicacion.nombre, 'Farmacia Italia');
    });

    testWidgets('solo espacios cuenta como sin nombre', (tester) async {
      final repo = await _montar(tester);

      await tester.enterText(_campoNombre, '     ');
      await tester.pump();
      await _tocar(tester, _registrar);

      expect(repo.llamadas.single.ubicacion.nombre, isNull);
    });

    testWidgets('el campo no deja pasar de 80 caracteres', (tester) async {
      final repo = await _montar(tester);

      await tester.enterText(_campoNombre, 'a' * 95);
      await tester.pump();

      expect(_textoDel(tester), hasLength(Ubicacion.largoMaximoDelNombre));
      await _tocar(tester, _registrar);
      expect(repo.llamadas.single.ubicacion.nombre, hasLength(Ubicacion.largoMaximoDelNombre));
    });

    testWidgets('un nombre pegado en varias líneas queda en una', (tester) async {
      final repo = await _montar(tester);

      await tester.enterText(_campoNombre, 'Farmacia\nItalia');
      await tester.pump();
      await _tocar(tester, _registrar);

      expect(repo.llamadas.single.ubicacion.nombre, isNot(contains('\n')));
    });

    testWidgets('dos toques seguidos en «Registrar» guardan una sola vez', (tester) async {
      final repo = await _montar(tester);
      await tester.enterText(_campoNombre, 'Farmacia Italia');
      await tester.pump();

      await _traer(tester, _registrar);
      await tester.tap(_registrar);
      await tester.tap(_registrar, warnIfMissed: false);
      await _asentar(tester);

      expect(repo.llamadas, hasLength(1));
      expect(repo.llamadas.single.ubicacion.nombre, 'Farmacia Italia');
    });

    for (final (nombre, tamano) in [
      ('360×640', const Size(360, 640)),
      ('320×568', const Size(320, 568)),
    ]) {
      testWidgets('con el texto al 200 % en $nombre el campo y su aviso entran sin desbordar', (
        tester,
      ) async {
        await _montar(tester, escala: 2, tamano: tamano);
        await _traer(tester, _campoNombre);

        expect(tester.takeException(), isNull);
        expect(
          find.text('Es el nombre del lugar. No pongas nombres ni datos de tus clientes.'),
          findsOneWidget,
        );
        await tester.enterText(_campoNombre, 'a' * 80);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(_campoNombre).height, greaterThanOrEqualTo(48));
      });
    }

    testWidgets('el campo es tocable (48 dp) y el lector de pantalla lo anuncia por su rótulo', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester);
      await _traer(tester, _campoNombre);

      expect(tester.getSize(_campoNombre).height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel(RegExp('NOMBRE DEL LUGAR')), findsWidgets);
      semantica.dispose();
    });
  });
}
