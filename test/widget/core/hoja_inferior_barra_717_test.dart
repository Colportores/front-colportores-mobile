// Issue #717 — la interfaz no se superpone con la barra de navegación de Android.
//
// En Android 15 o más la app se dibuja de borde a borde: la barra de navegación (tres botones o línea
// de gestos) flota sobre el pie de la pantalla. Las hojas inferiores se abren por
// `mostrarHojaInferior`, que deja su contenido sobre esa barra y su fondo hasta el borde. Acá se
// simula la barra con un inset inferior de 48 dp (tres botones) y se mide dónde quedan los botones
// del pie de la hoja.
import 'package:colportores_mobile/core/presentation/hoja_inferior.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/configuracion/presentation/widgets/hoja_cerrar_sesion.dart';
import 'package:colportores_mobile/features/respaldo/presentation/widgets/hoja_empezar_sin_recuperar.dart';
import 'package:colportores_mobile/features/respaldo/presentation/widgets/hoja_recuperar_respaldo.dart';
import 'package:colportores_mobile/features/tiles/presentation/widgets/hoja_borrar_mapa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pantalla = Size(400, 800);
const _barra = 48.0;

/// La pantalla de 400 × 800 con [barra] dp de barra de navegación abajo y [teclado] dp de teclado.
/// Como en el teléfono, `padding` es lo que de `viewPadding` no tapa el teclado.
void _fijarPantalla(WidgetTester tester, {double barra = _barra, double teclado = 0}) {
  tester.view.physicalSize = _pantalla;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = FakeViewPadding(bottom: barra);
  tester.view.padding = FakeViewPadding(bottom: (barra - teclado).clamp(0, barra));
  if (teclado > 0) tester.view.viewInsets = FakeViewPadding(bottom: teclado);
  addTearDown(tester.view.reset);
}

/// Monta una app con un botón «Abrir» que ejecuta [abrir].
Future<void> _montar(WidgetTester tester, void Function(BuildContext context) abrir) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('abrir'),
              onPressed: () => abrir(context),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _abrir(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('abrir')));
  await tester.pumpAndSettle();
}

/// Donde termina el widget con [clave], en pixeles desde arriba.
double _pie(WidgetTester tester, Key clave) => tester.getBottomLeft(find.byKey(clave)).dy;

const _cierraAbajo = Key('pie_de_la_hoja');

Widget _hojaConPie() => const Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    SizedBox(height: 120),
    SizedBox(key: _cierraAbajo, height: 56, width: double.infinity),
  ],
);

void main() {
  group('mostrarHojaInferior (#717)', () {
    testWidgets('el pie de la hoja queda encima de la barra de navegación', (tester) async {
      _fijarPantalla(tester);
      await _montar(
        tester,
        (c) => mostrarHojaInferior<void>(context: c, builder: (_) => _hojaConPie()),
      );
      await _abrir(tester);

      expect(_pie(tester, _cierraAbajo), _pantalla.height - _barra);
    });

    testWidgets('el fondo de la hoja sigue llegando hasta el borde de la pantalla', (tester) async {
      _fijarPantalla(tester);
      await _montar(
        tester,
        (c) => mostrarHojaInferior<void>(context: c, builder: (_) => _hojaConPie()),
      );
      await _abrir(tester);

      expect(tester.getBottomLeft(find.byType(BottomSheet)).dy, _pantalla.height);
    });

    testWidgets('con gestos (barra fina) el margen es el de la barra de gestos', (tester) async {
      _fijarPantalla(tester, barra: 24);
      await _montar(
        tester,
        (c) => mostrarHojaInferior<void>(context: c, builder: (_) => _hojaConPie()),
      );
      await _abrir(tester);

      expect(_pie(tester, _cierraAbajo), _pantalla.height - 24);
    });

    testWidgets('sin barra (otros teléfonos) no agrega margen', (tester) async {
      _fijarPantalla(tester, barra: 0);
      await _montar(
        tester,
        (c) => mostrarHojaInferior<void>(context: c, builder: (_) => _hojaConPie()),
      );
      await _abrir(tester);

      expect(_pie(tester, _cierraAbajo), _pantalla.height);
    });

    testWidgets('una hoja que ya traía su SafeArea no suma el margen dos veces', (tester) async {
      _fijarPantalla(tester);
      await _montar(
        tester,
        (c) => mostrarHojaInferior<void>(
          context: c,
          builder: (_) => SafeArea(child: _hojaConPie()),
        ),
      );
      await _abrir(tester);

      expect(_pie(tester, _cierraAbajo), _pantalla.height - _barra);
    });

    testWidgets('con el teclado abierto la hoja sube con el teclado, sin sumar la barra', (
      tester,
    ) async {
      _fijarPantalla(tester, teclado: 300);
      await _montar(
        tester,
        (c) => mostrarHojaInferior<void>(
          context: c,
          isScrollControlled: true,
          // Como las hojas de la app con campos: se levantan con el teclado por su cuenta.
          builder: (contexto) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(contexto).bottom),
            child: _hojaConPie(),
          ),
        ),
      );
      await _abrir(tester);

      // El teclado tapa la barra: la hoja termina donde empieza el teclado (800 − 300), no 48 dp antes.
      expect(_pie(tester, _cierraAbajo), _pantalla.height - 300);
    });

    testWidgets('`conBarraInferior: false` deja el margen a la hoja (la que se arrastra)', (
      tester,
    ) async {
      _fijarPantalla(tester);
      await _montar(
        tester,
        (c) => mostrarHojaInferior<void>(
          context: c,
          conBarraInferior: false,
          builder: (_) => _hojaConPie(),
        ),
      );
      await _abrir(tester);

      expect(_pie(tester, _cierraAbajo), _pantalla.height);
    });

    testWidgets('un cierre de la hoja devuelve su resultado', (tester) async {
      _fijarPantalla(tester);
      bool? salio;
      await _montar(tester, (c) async {
        salio = await mostrarHojaInferior<bool>(
          context: c,
          builder: (contexto) => TextButton(
            key: const Key('confirmar'),
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Confirmar'),
          ),
        );
      });
      await _abrir(tester);
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();

      expect(salio, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('las hojas de la app quedan sobre la barra de navegación (#717)', () {
    final alto = _pantalla.height - _barra;

    testWidgets('«¿Cerrar sesión?»: «Confirmar» y «Cancelar» quedan visibles y tocables', (
      tester,
    ) async {
      _fijarPantalla(tester);
      await _montar(
        tester,
        (c) => mostrarHojaCerrarSesion(c, pendientes: 0, cerrar: () async => true),
      );
      await _abrir(tester);

      expect(_pie(tester, const Key('configuracion_dialogo_cancelar')), lessThanOrEqualTo(alto));
      expect(_pie(tester, const Key('configuracion_dialogo_confirmar')), lessThanOrEqualTo(alto));
    });

    testWidgets('«¿Empezar sin recuperar?»: sus dos botones quedan sobre la barra', (tester) async {
      _fijarPantalla(tester);
      await _montar(tester, mostrarHojaEmpezarSinRecuperar);
      await _abrir(tester);

      expect(_pie(tester, const Key('recuperacion_hoja_confirmar')), lessThanOrEqualTo(alto));
      expect(_pie(tester, const Key('recuperacion_hoja_volver')), lessThanOrEqualTo(alto));
    });

    testWidgets('«Recuperar mi respaldo»: «Empezar» y «Ahora no» quedan sobre la barra', (
      tester,
    ) async {
      _fijarPantalla(tester);
      await _montar(tester, (c) => mostrarHojaRecuperarRespaldo(c, cuentaDrive: 'ana@example.com'));
      await _abrir(tester);

      expect(
        _pie(tester, const Key('configuracion_hoja_recuperar_ahora_no')),
        lessThanOrEqualTo(alto),
      );
      expect(
        _pie(tester, const Key('configuracion_hoja_recuperar_empezar')),
        lessThanOrEqualTo(alto),
      );
    });

    testWidgets('«Borrar mapa»: «Borrar» y «Cancelar» quedan sobre la barra', (tester) async {
      _fijarPantalla(tester);
      await _montar(tester, (c) => mostrarHojaBorrarMapa(c, nombre: 'Montevideo'));
      await _abrir(tester);

      expect(_pie(tester, const Key('mapas_offline_borrar_cancelar')), lessThanOrEqualTo(alto));
      expect(_pie(tester, const Key('mapas_offline_borrar_confirmar')), lessThanOrEqualTo(alto));
    });

    testWidgets('con el texto al 200 % el pie sigue sobre la barra', (tester) async {
      _fijarPantalla(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: temaClaro(),
          builder: (context, hijo) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
            child: hijo!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('abrir'),
                  onPressed: () => mostrarHojaEmpezarSinRecuperar(context),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await _abrir(tester);

      // Con la letra grande la hoja se desplaza; al llegar al final, el botón queda sobre la barra.
      final confirmar = find.byKey(const Key('recuperacion_hoja_confirmar'));
      await tester.ensureVisible(confirmar);
      await tester.pumpAndSettle();
      expect(_pie(tester, const Key('recuperacion_hoja_confirmar')), lessThanOrEqualTo(alto));
    });
  });
}
