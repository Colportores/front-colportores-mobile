import 'dart:ui' show Rect;

import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_principal_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ControladorFalso implements ControladorMapaBase {
  _ControladorFalso(this.camara);

  @override
  CamaraMapa camara;

  final movimientos = <CamaraMapa>[];

  @override
  Future<void> moverCamara(CamaraMapa camara) async {
    movimientos.add(camara);
    this.camara = camara;
  }
}

const _montevideo = Coordenadas(lat: -34.9, lon: -56.16);
const _grecia = Coordenadas(lat: -34.88, lon: -56.07);

void main() {
  late ProviderContainer contenedor;
  late MapaPrincipalNotifier mapa;

  setUp(() {
    contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);
    mapa = contenedor.read(mapaPrincipalProvider.notifier);
  });

  test('arranca explorando, sin mapa armado', () {
    expect(contenedor.read(mapaPrincipalProvider), const Explorando());
    expect(mapa.hayMapa(), isFalse);
    expect(mapa.camara(), isNull);
  });

  test('sin mapa armado, llevarA no mueve nada y lo dice', () async {
    final movio = await mapa.llevarA(
      const CamaraMapa(centro: _grecia, zoom: 17),
      por: IntencionCamara.elegirCasa,
    );
    expect(movio, isFalse);
  });

  test('con el mapa registrado, llevarA mueve su cámara', () async {
    final controlador = _ControladorFalso(const CamaraMapa(centro: _montevideo, zoom: 12));
    mapa.registrar(controlador);
    const destino = CamaraMapa(centro: _grecia, zoom: 17);

    final movio = await mapa.llevarA(destino, por: IntencionCamara.revisarPar);

    expect(movio, isTrue);
    expect(controlador.movimientos, [destino]);
    expect(mapa.camara(), destino);
  });

  test('cambiar de modo no mueve la cámara', () {
    final controlador = _ControladorFalso(const CamaraMapa(centro: _montevideo, zoom: 12));
    mapa
      ..registrar(controlador)
      ..cambiarModo(const CasaElegida('u-1'))
      ..cambiarModo(const MoviendoPunto(ubicacionId: 'u-1', antes: _montevideo, nueva: _grecia))
      ..cambiarModo(const ComparandoDuplicado(a: 'u-1', b: 'u-2'))
      ..cambiarModo(const ColocandoPin(ParametrosAlta(colportorId: 'col-1')))
      ..volverAExplorar();

    expect(controlador.movimientos, isEmpty);
    expect(contenedor.read(mapaPrincipalProvider), const Explorando());
  });

  test('terminar un alta vuelve a explorar solo si el mapa sigue en esa alta', () {
    const primera = ParametrosAlta(colportorId: 'col-1', apertura: 1);
    const segunda = ParametrosAlta(colportorId: 'col-1', apertura: 2);

    mapa
      ..cambiarModo(const ColocandoPin(primera))
      ..terminarAlta(primera);
    expect(contenedor.read(mapaPrincipalProvider), const Explorando());

    mapa
      ..cambiarModo(const ColocandoPin(segunda))
      ..terminarAlta(primera);
    expect(contenedor.read(mapaPrincipalProvider), const ColocandoPin(segunda));

    mapa
      ..cambiarModo(const CasaElegida('u-1'))
      ..terminarAlta(segunda);
    expect(contenedor.read(mapaPrincipalProvider), const CasaElegida('u-1'));
  });

  group('encuadrar la nueva y las existentes arriba de la hoja (41B)', () {
    // Un mapa de 360×640 a pantalla completa; la hoja del aviso arranca en y = 400.
    const area = Rect.fromLTWH(0, 0, 360, 640);
    const borde = 400.0;
    const reserva = 90.0;

    ({double x, double y}) enPantalla(_ControladorFalso c, Coordenadas p) =>
        ProyeccionMercator.aPantalla(p, c.camara, ancho: area.width, alto: area.height);

    void dentro(_ControladorFalso c, List<Coordenadas> puntos) {
      for (final p in puntos) {
        final (:x, :y) = enPantalla(c, p);
        expect(x, inInclusiveRange(0, area.width), reason: 'x de $p');
        expect(y, greaterThanOrEqualTo(reserva), reason: 'sin lugar para la etiqueta: y=$y');
        expect(y, lessThanOrEqualTo(borde), reason: 'bajo la hoja: y=$y');
      }
    }

    test('sin mapa armado no mueve nada y lo dice', () async {
      expect(
        await mapa.encuadrarArribaDe(
          const [_grecia],
          bordeDeLaHoja: borde,
          por: IntencionCamara.compararDuplicado,
        ),
        isFalse,
      );
    });

    for (final rumbo in [0.0, 37.0]) {
      test('cerca: mantiene el zoom y el rumbo, y las deja con lugar para la etiqueta '
          '(rumbo $rumbo)', () async {
        // La nueva quedó pegada arriba (como tras «Confirmar posición» con la hoja alta de N·02).
        final c = _ControladorFalso(
          CamaraMapa(centro: const Coordenadas(lat: -34.883, lon: -56.07), zoom: 17, rumbo: rumbo),
        );
        mapa.registrar(c, area: () => area);
        const puntos = [_grecia, Coordenadas(lat: -34.8801, lon: -56.0702)];
        expect(
          mapa.estaALaVista(_grecia, bordeDeLaHoja: borde, margen: 24, margenArriba: reserva),
          isFalse,
        );

        final movio = await mapa.encuadrarArribaDe(
          puntos,
          bordeDeLaHoja: borde,
          por: IntencionCamara.compararDuplicado,
          reservaArriba: reserva,
        );

        expect(movio, isTrue);
        expect(c.movimientos, hasLength(1));
        expect(c.camara.zoom, 17);
        expect(c.camara.rumbo, rumbo);
        dentro(c, puntos);
      });
    }

    test('lejos: aleja lo justo para que entren todas', () async {
      final c = _ControladorFalso(const CamaraMapa(centro: _grecia, zoom: 18));
      mapa.registrar(c, area: () => area);
      const puntos = [_grecia, Coordenadas(lat: -34.879, lon: -56.073)];

      await mapa.encuadrarArribaDe(
        puntos,
        bordeDeLaHoja: borde,
        por: IntencionCamara.compararDuplicado,
        reservaArriba: reserva,
      );

      expect(c.camara.zoom, lessThan(18));
      dentro(c, puntos);
    });
  });

  test('estaALaVista con margen arriba: un punto sin lugar para su etiqueta no cuenta', () {
    final c = _ControladorFalso(const CamaraMapa(centro: _grecia, zoom: 17));
    mapa.registrar(c, area: () => const Rect.fromLTWH(0, 0, 360, 640));
    // _grecia cae en el medio (y = 320); con la hoja en 400 se ve, con 60 dp arriba también.
    expect(mapa.estaALaVista(_grecia, bordeDeLaHoja: 400, margen: 24), isTrue);
    expect(mapa.estaALaVista(_grecia, bordeDeLaHoja: 400, margen: 24, margenArriba: 330), isFalse);
  });

  test('soltar un controlador viejo no suelta el nuevo (la pestaña se rearmó)', () {
    final viejo = _ControladorFalso(const CamaraMapa(centro: _montevideo, zoom: 12));
    final nuevo = _ControladorFalso(const CamaraMapa(centro: _grecia, zoom: 15));
    mapa
      ..registrar(viejo)
      ..registrar(nuevo)
      ..soltar(viejo);

    expect(mapa.hayMapa(), isTrue);
    expect(mapa.camara(), nuevo.camara);

    mapa.soltar(nuevo);
    expect(mapa.hayMapa(), isFalse);
  });

  test('el modo no se pierde aunque nadie lo esté mirando (vive con la app)', () async {
    mapa.cambiarModo(const CasaElegida('u-7'));
    // Sin oyentes, un provider que se libera solo volvería a «Explorando».
    await contenedor.pump();
    await Future<void>.delayed(Duration.zero);

    expect(contenedor.read(mapaPrincipalProvider), const CasaElegida('u-7'));
  });

  test('los modos se comparan por lo que llevan', () {
    expect(const CasaElegida('a'), const CasaElegida('a'));
    expect(const CasaElegida('a'), isNot(const CasaElegida('b')));
    expect(
      const MoviendoPunto(ubicacionId: 'a', antes: _montevideo),
      isNot(const MoviendoPunto(ubicacionId: 'a', antes: _montevideo, nueva: _grecia)),
    );
    expect(
      const ColocandoPin(ParametrosAlta(colportorId: 'col-1', puntoInicial: _grecia)),
      const ColocandoPin(ParametrosAlta(colportorId: 'col-1', puntoInicial: _grecia)),
    );
    expect(
      const ComparandoDuplicado(a: 'x', b: 'y'),
      isNot(const ComparandoDuplicado(a: 'y', b: 'x')),
    );
  });
}
