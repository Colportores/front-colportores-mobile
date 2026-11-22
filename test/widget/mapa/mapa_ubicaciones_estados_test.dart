// HU-VIS-005 · vista 39 (#412): los marcadores del mapa de ubicaciones sobre `house_status`. Un grupo
// por artboard del canvas (`39 Casa en el Mapa.dc.html`): M·01 «De lejos: puntos de color» y M·02
// «Acercado: el número es el marcador», con la decisión de Cristian del 23/10 («Números casas»:
// «Cuadrados solo si entran») y los casos límite de cada flujo.
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/marcador_estado.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';

/// El punto [metros] al norte de [puntoItalia] (donde la lista falsa pone `metrosAlNorte`).
Coordenadas _alNorte(double metros) =>
    Coordenadas(lat: puntoItalia.lat + metros / 111320, lon: puntoItalia.lon);

/// Un zoom en que un dp mide ~3 cm: dos casas a 3 m ya están a ~100 dp.
const _zoomCerca = 21.0;

/// La cámara que deja el colportor al acercar con los dedos sobre [metros] al norte del GPS.
CamaraMapa _acercar(double metros, {double zoom = _zoomCerca}) =>
    CamaraMapa(centro: _alNorte(metros), zoom: zoom);

/// Tres casas bien separadas entre sí (3 m): a [_zoomCerca] sus cuadrados entran sin taparse.
List<UbicacionConResumen> _calle() => [
  filaLista('a', numero: '1234', metrosAlNorte: 100, estado: EstadoCasa.cobranzaPendiente),
  filaLista('b', numero: '1250', metrosAlNorte: 103, estado: EstadoCasa.ventaCompleta),
  filaLista('c', numero: '7', metrosAlNorte: 106),
];

/// Dos casas en el mismo punto, a 60 m del GPS: sus cuadrados nunca entran sin taparse, así que el
/// mapa se queda con puntos y grupos por mucho que se mire (un mapa con una sola casa a la vista
/// pasa a cuadrados enseguida, y estos tests prueban lo que se ve de lejos).
List<UbicacionConResumen> _quePidenPuntos() => [
  filaLista('par-1', numero: '1', metrosAlNorte: 80),
  filaLista('par-2', numero: '2', metrosAlNorte: 80),
];

Future<void> _acercarYAsentar(WidgetTester tester, FabricaMapaFalsa mapa, CamaraMapa camara) async {
  mapa.moverPorGesto(camara);
  await asentarLista(tester, 3);
}

Iterable<PuntoMapa> _casas(FabricaMapaFalsa mapa) =>
    mapa.config!.puntos.where((p) => p.id != 'gps');

void main() {
  group('M·01 · de lejos: puntos de color y símbolo del estado', () {
    testWidgets('dada una casa de cada estado, cuando se abre el mapa, entonces cada una es la '
        'insignia de su estado y la que no tiene estado sigue siendo el punto «Sin visita»', (
      tester,
    ) async {
      final filas = [
        for (final (i, estado) in EstadoCasa.values.indexed)
          filaLista('u$i', metrosAlNorte: 200.0 + i * 30, estado: estado),
        ..._quePidenPuntos(),
      ];
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(filas));

      for (final (i, estado) in EstadoCasa.values.indexed) {
        final p = punto(m.mapa, 'u$i');
        expect(p.variante, VarianteMarcador.de(estado), reason: estado.name);
        expect(
          p.estilo,
          estado == EstadoCasa.sinVisita ? EstiloPunto.contexto : EstiloPunto.conEstado,
          reason: estado.name,
        );
        expect(p.etiqueta, isNull, reason: 'de lejos no lleva número: ${estado.name}');
      }
    });

    testWidgets('dada una casa sin fila en house_status (estado null), cuando se abre, entonces '
        'se ve «Sin visita» y no una insignia', (tester) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso([filaLista('x', metrosAlNorte: 300), ..._quePidenPuntos()]),
      );

      expect(punto(m.mapa, 'x').estilo, EstiloPunto.contexto);
      expect(punto(m.mapa, 'x').variante, VarianteMarcador.sinVisita);
    });

    testWidgets('dado un edificio, cuando no tiene estado, entonces lleva el símbolo del '
        'edificio; con estado, el del depto más urgente', (tester) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso([
          ..._quePidenPuntos(),
          filaLista('e1', tipo: TipoUbicacion.edificio, metrosAlNorte: 300),
          filaLista(
            'e2',
            tipo: TipoUbicacion.edificio,
            metrosAlNorte: 330,
            estado: EstadoCasa.cobranzaPendiente,
          ),
        ]),
      );

      expect(punto(m.mapa, 'e1').variante, VarianteMarcador.edificio);
      expect(punto(m.mapa, 'e1').estilo, EstiloPunto.conEstado);
      expect(punto(m.mapa, 'e2').variante, VarianteMarcador.cobranzaPendiente);
    });

    testWidgets('las insignias de lejos se agrupan con las que tienen cerca (HU-UBI-003)', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso([
          filaLista('x', metrosAlNorte: 300, estado: EstadoCasa.rechazo),
          ..._quePidenPuntos(),
        ]),
      );

      expect(m.mapa.config!.agruparPuntos, isTrue);
      expect(punto(m.mapa, 'x').estilo.sinAgrupar, isFalse);
    });

    testWidgets('dada una casa cerca del GPS, cuando tiene estado, entonces la etiqueta de «cerca '
        'tuyo» lleva el color de su estado', (tester) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso([
          filaLista('c', numero: '1234', metrosAlNorte: 20, estado: EstadoCasa.rechazo),
          ..._quePidenPuntos(),
        ]),
      );

      expect(punto(m.mapa, 'c').estilo, EstiloPunto.cercano);
      expect(punto(m.mapa, 'c').variante, VarianteMarcador.rechazo);
      expect(punto(m.mapa, 'c').etiqueta, '1234');
    });
  });

  group('M·02 · acercado: el número es el marcador (cuadrados solo si entran)', () {
    testWidgets('dado el mapa recién abierto, cuando todavía no quedó quieto, entonces no hay '
        'cuadrados (un gesto no cambia el dibujo a mitad de camino)', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_calle()));

      expect(_casas(m.mapa).where((p) => p.estilo.esCuadrado), isEmpty);
    });

    testWidgets('dada una sola casa a la vista, cuando el mapa queda quieto, entonces entra y es '
        'un cuadrado: no hay un zoom fijo, depende de que entren todos', (tester) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso([filaLista('x', numero: '88', metrosAlNorte: 20)]),
      );

      expect(punto(m.mapa, 'x').estilo, EstiloPunto.cuadrado);
      expect(punto(m.mapa, 'x').etiqueta, '88');
    });

    testWidgets('dado que se acerca hasta que entran todos, cuando el mapa queda quieto, '
        'entonces TODAS las casas pasan a cuadrado con su número', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_calle()));

      await _acercarYAsentar(tester, m.mapa, _acercar(103));

      for (final p in _casas(m.mapa)) {
        expect(p.estilo, EstiloPunto.cuadrado, reason: p.id);
        expect(p.etiqueta, isNotNull, reason: p.id);
      }
      expect(punto(m.mapa, 'a').etiqueta, '1234');
      expect(punto(m.mapa, 'c').etiqueta, '7');
      expect(punto(m.mapa, 'a').variante, VarianteMarcador.cobranzaPendiente);
      expect(punto(m.mapa, 'b').variante, VarianteMarcador.ventaCompleta);
      expect(punto(m.mapa, 'c').variante, VarianteMarcador.sinVisita);
      expect(m.mapa.config!.hayCuadrados, isTrue);
    });

    testWidgets('dado que se acerca pero dos casas siguen tapándose, cuando queda quieto, '
        'entonces siguen los puntos: nunca se tapa una casa con otra', (tester) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso([
          filaLista('a', metrosAlNorte: 100, estado: EstadoCasa.ventaCompleta),
          filaLista('b', metrosAlNorte: 100.5),
        ]),
      );

      // Medio metro a ~3 cm por dp son ~17 dp: los cuadrados de 40 dp se pisarían.
      await _acercarYAsentar(tester, m.mapa, _acercar(100));

      expect(_casas(m.mapa).where((p) => p.estilo.esCuadrado), isEmpty);
      expect(m.mapa.config!.hayCuadrados, isFalse);
    });

    testWidgets('dado un mapa con cuadrados, cuando se aleja, entonces vuelven los puntos y los '
        'grupos', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_calle()));
      await _acercarYAsentar(tester, m.mapa, _acercar(103));
      expect(m.mapa.config!.hayCuadrados, isTrue);

      await _acercarYAsentar(tester, m.mapa, _acercar(103, zoom: 16));

      expect(m.mapa.config!.hayCuadrados, isFalse);
      expect(punto(m.mapa, 'a').estilo, EstiloPunto.conEstado);
      expect(punto(m.mapa, 'c').estilo, EstiloPunto.contexto);
    });

    testWidgets('dado un gesto en marcha, cuando el zoom ya alcanza pero el dedo sigue, entonces '
        'el dibujo no cambia hasta que el mapa queda quieto', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_calle()));

      m.mapa.moverSinTerminar(_acercar(103));
      await asentarLista(tester, 3);
      expect(m.mapa.config!.hayCuadrados, isFalse);

      m.mapa.avisarQuieta();
      await asentarLista(tester, 3);
      expect(m.mapa.config!.hayCuadrados, isTrue);
    });

    testWidgets('dado que se acerca a un lugar donde no hay casas, cuando queda quieto, entonces '
        'no se pasa a cuadrados (no hay nada que mostrar)', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_calle()));

      await _acercarYAsentar(tester, m.mapa, _acercar(5000));

      expect(m.mapa.config!.hayCuadrados, isFalse);
    });

    testWidgets('dado un toque en un cuadrado, cuando se elige la casa, entonces es el '
        'cuadrado seleccionado (con su aro) y los demás siguen siendo cuadrados', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_calle()));
      await _acercarYAsentar(tester, m.mapa, _acercar(103));

      m.mapa.tocarPunto('b');
      await asentarLista(tester);

      expect(vistaPrevia, findsOneWidget);
      expect(punto(m.mapa, 'b').estilo, EstiloPunto.cuadradoSeleccionado);
      expect(punto(m.mapa, 'a').estilo, EstiloPunto.cuadrado);
      expect(punto(m.mapa, 'b').etiqueta, '1250');

      await tester.tap(cerrarVistaPrevia);
      await asentarLista(tester);
      expect(punto(m.mapa, 'b').estilo, EstiloPunto.cuadrado);
    });

    testWidgets('dado el estado que cambia con el mapa a la vista, cuando house_status emite, '
        'entonces el cuadrado cambia de color sin tocar la cámara', (tester) async {
      final repo = RepoListaFalso(_calle());
      final m = await montarMapaUbicaciones(tester, repo: repo);
      await _acercarYAsentar(tester, m.mapa, _acercar(103));
      expect(punto(m.mapa, 'c').variante, VarianteMarcador.sinVisita);

      repo.emitir([
        for (final f in _calle())
          if (f.ubicacion.id == 'c')
            filaLista('c', numero: '7', metrosAlNorte: 106, estado: EstadoCasa.entregaYPago)
          else
            f,
      ]);
      await asentarLista(tester);

      expect(punto(m.mapa, 'c').variante, VarianteMarcador.entregaYPago);
      expect(punto(m.mapa, 'c').estilo, EstiloPunto.cuadrado);
    });
  });

  group('casos límite', () {
    testWidgets('dos cambios de estado seguidos, antes de que se dibuje el primero: queda el '
        'último y no se pierde ninguna casa', (tester) async {
      final repo = RepoListaFalso(_calle());
      final m = await montarMapaUbicaciones(tester, repo: repo);

      repo.emitir([
        filaLista('a', numero: '1234', metrosAlNorte: 100, estado: EstadoCasa.rechazo),
        ..._calle().skip(1),
      ]);
      repo.emitir([
        filaLista('a', numero: '1234', metrosAlNorte: 100, estado: EstadoCasa.ventaCompleta),
        ..._calle().skip(1),
      ]);
      await asentarLista(tester);

      expect(punto(m.mapa, 'a').variante, VarianteMarcador.ventaCompleta);
      expect(_casas(m.mapa), hasLength(3));
    });

    testWidgets('dado un doble toque sobre el mismo marcador, cuando llegan los dos, entonces '
        'queda una sola vista previa abierta y el cuadrado sigue elegido', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_calle()));
      await _acercarYAsentar(tester, m.mapa, _acercar(103));

      m.mapa.tocarPunto('a');
      m.mapa.tocarPunto('a');
      await asentarLista(tester);

      expect(vistaPrevia, findsOneWidget);
      expect(punto(m.mapa, 'a').estilo, EstiloPunto.cuadradoSeleccionado);
      expect(
        _casas(m.mapa).where((p) => p.estilo == EstiloPunto.cuadradoSeleccionado),
        hasLength(1),
      );
    });

    testWidgets('dos toques seguidos en dos cuadrados: gana el último, sin dejar dos elegidos', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_calle()));
      await _acercarYAsentar(tester, m.mapa, _acercar(103));

      m.mapa.tocarPunto('a');
      m.mapa.tocarPunto('c');
      await asentarLista(tester);

      expect(punto(m.mapa, 'c').estilo, EstiloPunto.cuadradoSeleccionado);
      expect(punto(m.mapa, 'a').estilo, EstiloPunto.cuadrado);
    });

    testWidgets('dado el mapa que sale de la pestaña y vuelve, cuando reentra, entonces los '
        'cuadrados siguen donde estaban (la cámara es la misma)', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_calle()));
      await _acercarYAsentar(tester, m.mapa, _acercar(103));
      expect(m.mapa.config!.hayCuadrados, isTrue);

      m.activa.value = false;
      await asentarLista(tester);
      m.activa.value = true;
      await asentarLista(tester);

      expect(m.mapa.config!.hayCuadrados, isTrue);
      expect(_casas(m.mapa), hasLength(3));
    });

    testWidgets('dado que no hay ubicaciones, cuando se acerca, entonces no hay puntos ni '
        'cuadrados ni errores', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso());

      await _acercarYAsentar(tester, m.mapa, _acercar(103));

      expect(_casas(m.mapa), isEmpty);
      expect(m.mapa.config!.hayCuadrados, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dada una lista larga (1.000 casas), cuando se acerca a una cuadra, entonces '
        'el cálculo no se cuelga y todas pasan a cuadrado si entran', (tester) async {
      final repo = RepoListaFalso([
        for (var i = 0; i < 1000; i++)
          filaLista(
            'u$i',
            numero: '${i + 1}',
            metrosAlNorte: 1000.0 + i * 3,
            estado: EstadoCasa.values[i % EstadoCasa.values.length],
          ),
      ]);
      final m = await montarMapaUbicaciones(tester, repo: repo);

      // Lejos: miles de casas en la vista, ni cerca de entrar.
      await _acercarYAsentar(tester, m.mapa, _acercar(2500, zoom: 16));
      expect(m.mapa.config!.hayCuadrados, isFalse);
      expect(_casas(m.mapa), hasLength(1000));

      // Sobre una casa y con el zoom al máximo, las que se ven (3 m = ~100 dp) entran.
      await _acercarYAsentar(tester, m.mapa, _acercar(2000));
      expect(m.mapa.config!.hayCuadrados, isTrue);
      expect(_casas(m.mapa).every((p) => p.estilo == EstiloPunto.cuadrado), isTrue);
    });

    testWidgets('dado un número de puerta larguísimo, cuando se acerca, entonces el cuadrado '
        'lleva la etiqueta completa y la capa lo parte en dos renglones', (tester) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso([
          filaLista('a', numero: '1234567890123', metrosAlNorte: 100, estado: EstadoCasa.rechazo),
        ]),
      );

      await _acercarYAsentar(tester, m.mapa, _acercar(100));

      expect(punto(m.mapa, 'a').estilo, EstiloPunto.cuadrado);
      expect(punto(m.mapa, 'a').etiqueta, '1234567890123');
    });

    testWidgets('dado el texto al doble (textScaler 2.0), cuando se acerca, entonces los '
        'cuadrados son los mismos: miden dp del mapa, no del texto', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_calle()), escala: 2);

      await _acercarYAsentar(tester, m.mapa, _acercar(103));

      expect(m.mapa.config!.hayCuadrados, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dada una falla al leer la base, cuando el stream falla, entonces las casas '
        'dejan de dibujarse sin dejar nada trabado, y al volver la lista vuelven con su estado', (
      tester,
    ) async {
      final repo = RepoListaFalso(_calle());
      final m = await montarMapaUbicaciones(tester, repo: repo);

      repo.fallar(StateError('base cerrada'));
      await asentarLista(tester);
      expect(tester.takeException(), isNull);

      repo.emitir(_calle());
      await asentarLista(tester);
      expect(punto(m.mapa, 'a').variante, VarianteMarcador.cobranzaPendiente);
    });

    testWidgets('dada una casa que se da de baja con los cuadrados puestos, cuando la lista '
        'emite, entonces sale del mapa y los demás se recalculan', (tester) async {
      final repo = RepoListaFalso(_calle());
      final m = await montarMapaUbicaciones(tester, repo: repo);
      await _acercarYAsentar(tester, m.mapa, _acercar(103));

      repo.emitir(_calle().skip(1).toList());
      await asentarLista(tester);

      expect(hayPunto(m.mapa, 'a'), isFalse);
      expect(m.mapa.config!.hayCuadrados, isTrue);
    });

    testWidgets('dado el zoom máximo con la hoja subida, cuando la hoja tapa casas, entonces las '
        'que quedan debajo no impiden los cuadrados', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_calle()));
      await _acercarYAsentar(tester, m.mapa, _acercar(103, zoom: MapaAlta.zoomCalle + 5));
      expect(m.mapa.config!.hayCuadrados, isTrue);

      await tocarAsa(tester, 2);

      expect(m.mapa.config!.hayCuadrados, isTrue);
    });
  });

  group('«Referencias»: la leyenda de los marcadores', () {
    testWidgets('dado el chip «Referencias», cuando se abre, entonces explica los ocho estados '
        'con su insignia', (tester) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(_calle()));

      await tester.tap(chipReferencias);
      await asentarLista(tester);

      for (final estado in [
        'No contestó',
        'Entrevista agendada',
        'Entrevista hecha',
        'Venta completa',
        'Cobranza pendiente',
        'Entrega y pago',
        'Rechazó',
      ]) {
        expect(find.text(estado), findsOneWidget, reason: estado);
      }
    });
  });
}
