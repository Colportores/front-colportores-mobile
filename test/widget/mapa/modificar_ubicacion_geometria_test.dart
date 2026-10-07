// Vista 07 «Modificar ubicación» (HU-UBI-004, #202): la geometría en el teléfono chico (360×640) y con
// el texto al 200 %, con las fuentes reales del proyecto (con la fuente de prueba de `flutter_test`
// cada letra mide un cuadrado y los rótulos parecen más grandes de lo que son).
//
// Lo que se prueba (QA de #202, ronda 1; decisiones de la tanda 34):
// - «Guardar cambios» y «Guardar posición» quedan fijos al pie de la hoja y se ven enteros.
// - Los rótulos del mapa escalan con el texto y nunca tapan el pin; el pin sigue marcando el centro
//   del mapa (el punto que se guarda).
// - La insignia «Editado» no se parte a mitad de palabra.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/campos_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/mapa_base_falso.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';

/// Unos 18 m al norte del punto guardado.
const _norte18m = 0.00016;

class _Anfitrion extends StatelessWidget {
  const _Anfitrion();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => ModificarUbicacionPage.abrir(
            context,
            colportorId: 'col-1',
            ubicacionId: 'ubi-1',
            alDarDeBaja: () {},
          ),
          child: const Text('abrir'),
        ),
      ),
    );
  }
}

Future<void> _asentar(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<(RepoEdicionFalso, FabricaMapaFalsa)> _montar(
  WidgetTester tester, {
  double escala = 1,
  Size tamano = const Size(360, 640),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = RepoEdicionFalso(ubicacionGuardada());
  final mapa = FabricaMapaFalsa();
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
        mapa: mapa,
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const _Anfitrion(),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await _asentar(tester);
  return (repo, mapa);
}

Finder get _guardar => find.widgetWithText(FilledButton, TextosModificar.guardarCambios);
Finder get _guardarPosicion => find.widgetWithText(FilledButton, TextosModificar.guardarPosicion);
Finder get _campoNumero => find.byType(TextField).at(1);

/// El pin de la ubicación (no el «Antes», que es una gota sin colocar).
Finder get _pin => find.byWidgetPredicate((w) => w is PinAlta && w.colocado);

/// La píldora blanca que rodea al texto [texto].
Rect _pildora(WidgetTester tester, Finder texto) {
  final pildora = find.ancestor(of: texto, matching: find.byType(Material));
  return tester.getRect(pildora.first);
}

void _sinSolape(Rect a, Rect b, String que) {
  expect(a.overlaps(b), isFalse, reason: '$que: $a se pisa con $b');
}

/// El pin queda dentro de la pantalla y su punta es el centro del mapa.
void _pinMarcaElCentro(WidgetTester tester) {
  final pin = tester.getRect(_pin);
  final mapa = tester.getRect(find.byType(MapaBase));
  expect(pin.bottom, closeTo(mapa.center.dy, 1), reason: 'la punta del pin es el centro del mapa');
  expect(pin.center.dx, closeTo(mapa.center.dx, 1));
  expect(pin.top, greaterThanOrEqualTo(0));
}

void main() {
  setUpAll(cargarFuentesReales);

  for (final escala in [1.0, 2.0]) {
    group('07 en 360×640 con el texto al ${(escala * 100).round()} %', () {
      testWidgets('«Guardar cambios» queda fijo al pie y entero a la vista', (tester) async {
        await _montar(tester, escala: escala);
        await tester.enterText(_campoNumero, '1238');
        await _asentar(tester);

        final r = tester.getRect(_guardar);
        expect(r.bottom, lessThanOrEqualTo(640), reason: 'el botón no queda cortado');
        expect(r.top, greaterThanOrEqualTo(0));
        expect(tester.takeException(), isNull);

        // Fijo: desplazar el resto de la hoja no lo mueve.
        final hoja = find.descendant(
          of: find.byType(HojaModificarDatos),
          matching: find.byType(SingleChildScrollView),
        );
        await tester.drag(hoja.first, const Offset(0, -300));
        await _asentar(tester);
        expect(tester.getRect(_guardar), r);
      });

      testWidgets('«Dar de baja» queda debajo de «Guardar cambios», también fijo y entero', (
        tester,
      ) async {
        await _montar(tester, escala: escala);

        final baja = tester.getRect(find.text(TextosModificar.darDeBaja));
        expect(baja.bottom, lessThanOrEqualTo(640));
        expect(baja.top, greaterThanOrEqualTo(tester.getRect(_guardar).bottom - 1));
      });

      testWidgets('el aviso de falla queda a la vista, arriba del botón', (tester) async {
        final (repo, _) = await _montar(tester, escala: escala);
        repo.comportamiento = (_, _, _) async => throw StateError('disco');
        await tester.enterText(_campoNumero, '1238');
        await _asentar(tester);

        await tester.tap(_guardar);
        await _asentar(tester);

        final aviso = tester.getRect(
          find.ancestor(
            of: find.text(TextosModificar.noPudimosGuardar),
            matching: find.byType(AvisoAlta),
          ),
        );
        final guardar = tester.getRect(_guardar);
        final hoja = tester.getRect(find.byType(HojaModificarDatos));
        // El aviso empieza a la vista, arriba del botón. Con el texto normal entra entero; al 200 %
        // es más alto que el área que se desplaza y el resto se lee desplazando.
        expect(aviso.top, greaterThanOrEqualTo(hoja.top - .5));
        expect(aviso.top, lessThan(guardar.top));
        if (escala == 1) expect(aviso.bottom, lessThanOrEqualTo(guardar.top + 1));
        expect(guardar.bottom, lessThanOrEqualTo(640));
      });

      testWidgets('«Editar ubicación»: el título no tapa el pin y el pin marca el centro', (
        tester,
      ) async {
        await _montar(tester, escala: escala);

        final titulo = _pildora(tester, find.text(TextosModificar.tituloEditar));
        _sinSolape(titulo, tester.getRect(_pin), 'título');
        _pinMarcaElCentro(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('«Mover el punto»: los rótulos no tapan el pin y los botones se ven enteros', (
        tester,
      ) async {
        final (_, mapa) = await _montar(tester, escala: escala);
        await tester.tap(find.text(TextosModificar.moverElPunto));
        await _asentar(tester);
        final centro = mapa.camara!.centro;
        mapa.moverPorGesto(
          mapa.camara!.conCentro(Coordenadas(lat: centro.lat + _norte18m, lon: centro.lon)),
        );
        await _asentar(tester);

        final titulo = _pildora(tester, find.text(TextosModificar.tituloMover));
        final moviste = _pildora(tester, find.textContaining('Moviste el punto'));
        final pin = tester.getRect(_pin);
        _sinSolape(titulo, pin, 'título');
        _sinSolape(moviste, pin, '«Moviste el punto»');
        _sinSolape(titulo, moviste, 'título vs «Moviste el punto»');
        _pinMarcaElCentro(tester);

        final guardarPosicion = tester.getRect(_guardarPosicion);
        expect(guardarPosicion.bottom, lessThanOrEqualTo(640));
        expect(tester.getRect(find.text(TextosModificar.cancelar)).bottom, lessThanOrEqualTo(640));
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('07 · la insignia «Editado»', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('en 360×640 al ${(escala * 100).round()} % no se parte y entra en su columna', (
        tester,
      ) async {
        await _montar(tester, escala: escala);
        await tester.enterText(_campoNumero, '1238');
        await _asentar(tester);

        final insignia = tester.getRect(find.byType(InsigniaCampo));
        final campo = find.ancestor(
          of: find.byType(InsigniaCampo),
          matching: find.byType(CampoDireccionUbicacion),
        );
        final columna = tester.getRect(campo);
        expect(insignia.left, greaterThanOrEqualTo(columna.left - .5));
        expect(insignia.right, lessThanOrEqualTo(columna.right + .5));
        final parrafo = tester.renderObject<RenderParagraph>(find.text('Editado'));
        final cajas = parrafo.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 'Editado'.length),
        );
        expect(cajas, hasLength(1), reason: '«Editado» no se parte en dos renglones');
        // Va en el renglón de abajo del rótulo «NÚMERO», no pegada a él.
        final etiqueta = tester.getRect(find.text('NÚMERO'));
        expect(insignia.top, greaterThanOrEqualTo(etiqueta.bottom - 1));
      });
    }
  });
}
