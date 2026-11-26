// «Nombre ubic.» (Cristian, 24/11; #769, backend-supabase 0206): el campo opcional «Nombre del lugar» de hasta
// 80 caracteres en la edición de una ubicación (vista 07, «Editar ubicación»), con el aviso de no poner datos
// de clientes. Se carga con el nombre que ya tiene; cambiarlo (o borrarlo) habilita «Guardar cambios».
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/campos_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/baja_ubicacion_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';

class _Anfitrion extends StatelessWidget {
  const _Anfitrion(this.salidas);

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

Future<void> _asentar(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<RepoEdicionFalso> _montar(
  WidgetTester tester, {
  Ubicacion? ubicacion,
  double escala = 1,
  Size tamano = const Size(390, 844),
  List<SalidaModificarUbicacion?>? salidas,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = RepoEdicionFalso(ubicacion ?? ubicacionGuardada(), espacios: 1);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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

Finder get _guardar => find.widgetWithText(FilledButton, TextosModificar.guardarCambios);

Finder get _campoNombre => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == TextosCampos.nombreSugerencia,
);

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<FilledButton>(boton).onPressed != null;

Future<void> _escribir(WidgetTester tester, String texto) async {
  await _traer(tester, _campoNombre);
  await tester.enterText(_campoNombre, texto);
  await tester.pump();
}

void main() {
  group('vista 07 · el campo «Nombre del lugar»', () {
    testWidgets(
      'sin nombre guardado está vacío, dice que es opcional y avisa que no son datos de clientes',
      (tester) async {
        await _montar(tester);
        await _traer(tester, _campoNombre);

        expect(tester.widget<TextField>(_campoNombre).controller!.text, isEmpty);
        expect(find.text('NOMBRE DEL LUGAR · OPCIONAL'), findsOneWidget);
        expect(
          find.text('Es el nombre del lugar. No pongas nombres ni datos de tus clientes.'),
          findsOneWidget,
        );
        expect(_habilitado(tester, _guardar), isFalse, reason: 'todavía no cambió nada');
      },
    );

    testWidgets('con nombre guardado lo muestra y tampoco habilita «Guardar» hasta cambiarlo', (
      tester,
    ) async {
      await _montar(tester, ubicacion: ubicacionGuardada(nombre: 'Farmacia Italia'));
      await _traer(tester, _campoNombre);

      expect(tester.widget<TextField>(_campoNombre).controller!.text, 'Farmacia Italia');
      expect(_habilitado(tester, _guardar), isFalse);
    });

    testWidgets('ponerle nombre habilita «Guardar» y guarda el nombre recortado', (tester) async {
      final repo = await _montar(tester);

      await _escribir(tester, '  Farmacia Italia ');
      expect(_habilitado(tester, _guardar), isTrue);
      await _tocar(tester, _guardar);

      expect(repo.escrituras.single.nueva.nombre, 'Farmacia Italia');
    });

    testWidgets('cambiar el nombre y volver a escribir el que tenía deja «Guardar» apagado', (
      tester,
    ) async {
      await _montar(tester, ubicacion: ubicacionGuardada(nombre: 'Farmacia Italia'));

      await _escribir(tester, 'Otra');
      expect(_habilitado(tester, _guardar), isTrue);
      await _escribir(tester, 'Farmacia Italia');

      expect(_habilitado(tester, _guardar), isFalse);
    });

    testWidgets('borrarlo habilita «Guardar» y la ubicación queda sin nombre', (tester) async {
      final repo = await _montar(tester, ubicacion: ubicacionGuardada(nombre: 'Farmacia Italia'));

      await _escribir(tester, '');
      expect(_habilitado(tester, _guardar), isTrue);
      await _tocar(tester, _guardar);

      expect(repo.escrituras.single.nueva.nombre, isNull);
    });

    testWidgets('editar otra cosa deja el nombre como estaba', (tester) async {
      final repo = await _montar(tester, ubicacion: ubicacionGuardada(nombre: 'Farmacia Italia'));
      final calle = find.byType(TextField).at(0);

      await _traer(tester, calle);
      await tester.enterText(calle, 'Av. Brasil');
      await tester.pump();
      await _tocar(tester, _guardar);

      expect(repo.escrituras.single.nueva.calle, 'Av. Brasil');
      expect(repo.escrituras.single.nueva.nombre, 'Farmacia Italia');
    });

    testWidgets('el campo no deja pasar de 80 caracteres', (tester) async {
      await _montar(tester);

      await _escribir(tester, 'a' * 95);

      expect(
        tester.widget<TextField>(_campoNombre).controller!.text,
        hasLength(Ubicacion.largoMaximoDelNombre),
      );
    });

    testWidgets('dos toques seguidos en «Guardar» guardan una sola vez', (tester) async {
      final repo = await _montar(tester);
      await _escribir(tester, 'Farmacia Italia');

      await _traer(tester, _guardar);
      await tester.tap(_guardar);
      await tester.tap(_guardar, warnIfMissed: false);
      await _asentar(tester);

      expect(repo.escrituras, hasLength(1));
    });

    testWidgets(
      'si guardar falla a mitad, el nombre escrito sigue en el campo y se puede reintentar',
      (tester) async {
        final repo = await _montar(tester);
        repo.comportamiento = (nueva, numero, duplicados) =>
            throw StateError('la base no pudo guardar');
        await _escribir(tester, 'Farmacia Italia');

        await _tocar(tester, _guardar);

        expect(tester.widget<TextField>(_campoNombre).controller!.text, 'Farmacia Italia');
        expect(tester.takeException(), isNull);
        expect(_habilitado(tester, _guardar), isTrue, reason: 'el botón no queda trabado');
      },
    );

    testWidgets('volver atrás y reentrar muestra el nombre que quedó guardado', (tester) async {
      final salidas = <SalidaModificarUbicacion?>[];
      final repo = await _montar(tester, salidas: salidas);
      await _escribir(tester, 'Farmacia Italia');
      await _tocar(tester, _guardar);
      expect(repo.actual!.nombre, 'Farmacia Italia');

      await tester.tap(find.text('abrir'));
      await _asentar(tester);

      await _traer(tester, _campoNombre);
      expect(tester.widget<TextField>(_campoNombre).controller!.text, 'Farmacia Italia');
    });

    for (final (nombre, tamano) in [
      ('360×640', const Size(360, 640)),
      ('320×568', const Size(320, 568)),
    ]) {
      testWidgets(
        'con el texto al 200 % en $nombre un nombre de 80 caracteres entra sin desbordar',
        (tester) async {
          await _montar(
            tester,
            ubicacion: ubicacionGuardada(nombre: ('Farmacia Italia ' * 6).substring(0, 80)),
            escala: 2,
            tamano: tamano,
          );
          await _traer(tester, _campoNombre);

          expect(tester.takeException(), isNull);
          expect(tester.getSize(_campoNombre).height, greaterThanOrEqualTo(48));
        },
      );
    }
  });
}
