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
