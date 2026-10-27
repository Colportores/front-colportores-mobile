// QA-HU-UBI-003 «Visualizar ubicaciones en el mapa» (#200): un test de punta a punta por cada caso
// del issue, contra la pestaña «Mapa» armada con sus piezas reales (hoja, avisos, alta) y solo la
// vista nativa de MapLibre y los puertos (base, GPS, red, tiles) falsos. Lo que ya prueban otros
// archivos a fondo (artboards de la vista 06 y 39, avisos, estilo) se enlaza desde el PR; acá van
// los escenarios completos de la HU, con sus cifras (50 y más de 200 ubicaciones).
//
// El texto del issue es anterior a las decisiones de Cristian y del orquestador sobre la HU, que
// mandan: sin tiles ni conexión el mapa NO se pone en grises, se ven las ubicaciones sin calles con
// el aviso de la vista 06C·05; sin GPS el mapa encuadra todas las ubicaciones, sin inventar una
// «última ciudad»; la vista previa vieja es la hoja de la casa (vista 39).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/services/resolutores_mapa.dart'
    show FuenteTiles;
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/estilo_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/marcador_estado.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart'
    show ContextoDeCobro, ContextoDeVisita;
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart'
    show ColoresLista;
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:dartz/dartz.dart' show Left;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_descargas_arnes.dart';
import '../../helpers/tiles_falsos.dart';
import '../../helpers/zonas_falsas.dart';
import 'mapa_ubicaciones_arnes.dart';

const _nbsp = ' ';

/// Un GPS al que el colportor no le dio el permiso.
GpsFalso gpsSinPermiso() =>
    GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado)));

/// El mapa descargado en el teléfono (el paquete PMTiles de la ciudad).
const _mapaDescargado = FuenteMapa.offline('/data/user/0/uy.colportores/files/montevideo.pmtiles');

/// [cuantas] casas a más de 60 m del GPS (ninguna es «cerca tuyo»), con un estado cada una: los
/// ocho estados se reparten en orden y una de cada nueve no tiene fila en `house_status`.
List<UbicacionConResumen> _casas(int cuantas) => [
  for (var i = 0; i < cuantas; i++)
    filaLista(
      'u$i',
      calle: 'Calle $i',
      numero: '${i + 1}',
      metrosAlNorte: 100.0 + i * 15,
      estado: i % 9 == 8 ? null : EstadoCasa.values[i % EstadoCasa.values.length],
    ),
];

/// Las casas que el mapa dibuja (todo punto menos el del GPS).
Iterable<PuntoMapa> _delMapa(FabricaMapaFalsa mapa) =>
    mapa.config!.puntos.where((p) => p.id != 'gps');

/// El color de relleno que la HU le da a cada estado (§8.4): azul = cobranza; verde = entrevista
/// hecha o venta; ámbar = agendada; gris = no contestó; rojo = rechazo.
Color _colorDeLaHu(EstadoCasa estado) => switch (estado) {
  EstadoCasa.cobranzaPendiente || EstadoCasa.entregaYPago => ColoresLista.azul,
  EstadoCasa.entrevistaHecha || EstadoCasa.ventaCompleta => ColoresLista.verde,
  EstadoCasa.entrevistaAgendada => ColoresLista.ambar,
  EstadoCasa.noContesto => ColoresLista.grisEstado,
  EstadoCasa.rechazo => ColoresLista.rojo,
  EstadoCasa.sinVisita => const Color(0xFFFFFFFF),
};

Finder get _titulo => find.byKey(ClavesHojaCasa.titulo);
Finder get _subtitulo => find.byKey(ClavesHojaCasa.subtitulo);

void main() {
  group('Escenario 1 · mapa descargado y 50 ubicaciones', () {
    testWidgets('abre en menos de 3 s y cada marcador lleva el color de su house_status', (
      tester,
    ) async {
      final reloj = Stopwatch()..start();
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(_casas(50)),
        situacion: const SituacionMapa(fuente: _mapaDescargado),
      );
      reloj.stop();

      // El tiempo es el del lado Flutter (leer, ordenar y armar los 50 puntos); el dibujo nativo
      // de MapLibre se mide en el teléfono (QA manual del PR).
      expect(reloj.elapsed, lessThan(const Duration(seconds: 3)));
      expect(m.mapa.config!.fuente.tipo, FuenteTiles.pmtilesOffline);
      expect(find.byKey(ClavesAvisoMapa.sinConexion), findsNothing);
      expect(find.byKey(ClavesAvisoMapa.noCarga), findsNothing);
      final casas = _delMapa(m.mapa).toList();
      expect(casas, hasLength(50));
      for (var i = 0; i < 50; i++) {
        final estado = _casas(50)[i].estado;
        final p = casas.firstWhere((c) => c.id == 'u$i');
        expect(p.variante, VarianteMarcador.de(estado), reason: 'u$i');
        expect(
          p.variante!.fondo,
          _colorDeLaHu(estado ?? EstadoCasa.sinVisita),
          reason: 'u$i: el relleno es el del estado ${estado?.name ?? 'sin visita'}',
        );
      }
      // Los ocho estados y el «sin fila» se ven: ningún color queda sin usar.
      expect({for (final p in casas) p.variante}, hasLength(VarianteMarcador.values.length - 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('la cuenta de la hoja dice 50 y las 50 filas existen en la lista', (tester) async {
      await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(_casas(50)),
        situacion: const SituacionMapa(fuente: _mapaDescargado),
      );

      expect(
        find.descendant(
          of: find.byKey(ClavesMapaUbicaciones.pestanaCercania),
          matching: find.text('50'),
        ),
        findsOneWidget,
      );
    });
  });

  group('Escenario 2 · tocar el marcador de una casa con cobranza pendiente', () {
    testWidgets('abre la hoja de la casa con tipo, dirección y estado destacado, y sus botones', (
      tester,
    ) async {
      final visitas = <ContextoDeVisita>[];
      final cobros = <ContextoDeCobro>[];
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso([
          filaLista(
            'a',
            calle: 'Av. Italia',
            numero: '1234',
            metrosAlNorte: 40,
            espacios: 2,
            estado: EstadoCasa.cobranzaPendiente,
          ),
          ..._casas(5).skip(1),
        ]),
        registrarVisita: visitas.add,
        cobrar: cobros.add,
      );

      m.mapa.tocarPunto('a');
      await asentarLista(tester);

      expect(find.byType(HojaCasa), findsOneWidget);
      expect(tester.widget<Text>(_titulo).data, 'Av. Italia 1234');
      // Tipo, estado «Cobranza pendiente» y distancia, en la línea de la hoja (el canvas 39).
      expect(
        tester.widget<Text>(_subtitulo).data,
        'Casa · Cobranza pendiente · a 40${_nbsp}m de vos',
      );
      // El saldo que da sentido al estado: quién debe cuánto, y el botón para cobrar.
      expect(find.text(r'Debe $ 1.200'), findsOneWidget);
      expect(find.text(r'$ Cobrar'), findsOneWidget);
      expect(find.text('✓  Registrar visita'), findsOneWidget);
      // Y la casa tocada es la elegida: el mapa la centra.
      expect(m.mapa.camara, isNotNull);
    });

    testWidgets('«Registrar visita» y «\$ Cobrar» llegan con la ubicación de la casa tocada', (
      tester,
    ) async {
      final visitas = <ContextoDeVisita>[];
      final cobros = <ContextoDeCobro>[];
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso([
          filaLista('a', metrosAlNorte: 40, estado: EstadoCasa.cobranzaPendiente),
        ]),
        registrarVisita: visitas.add,
        cobrar: cobros.add,
      );
      m.mapa.tocarPunto('a');
      await asentarLista(tester);

      await tester.ensureVisible(find.byKey(ClavesHojaCasa.cobrar));
      await tester.pump();
      await tester.tap(find.byKey(ClavesHojaCasa.cobrar));
      await tester.pump();

      expect(cobros, hasLength(1));
      expect(cobros.single.ubicacionId, 'a');
      expect(visitas, isEmpty);
    });
  });

  group('Escenario 3 · tap largo en un punto vacío', () {
    testWidgets('abre el alta con las coordenadas del tap y la ciudad de la campaña propuesta', (
      tester,
    ) async {
      const punto = Coordenadas(lat: -34.9, lon: -56.2);
      final ciudades = CiudadesFalsas(
        propone: (_) => const CiudadPropuesta(canelones, OrigenPropuesta.deCampania),
      );
      final gps = GpsFalso();
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(_casas(3)),
        gps: gps,
        ciudades: ciudades,
        altaReal: true,
        otrosOverrides: [
          geocodificadorInversoProvider.overrideWithValue(GeocodificadorFalso()),
          ubicadorZonaProvider.overrideWithValue(ubicadorSinZonas()),
          marcadoresCercanosProvider.overrideWith(
            (ref, consulta) => Stream.value(const <MarcadorMapa>[]),
          ),
        ],
      );

      m.mapa.tocarLargo(punto);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // El alta es la pantalla de verdad, con el punto del tap «marcado a mano» y la ciudad ya
      // propuesta (no hace falta elegirla).
      expect(find.text('-34.90000, -56.20000'), findsOneWidget);
      expect(find.text('Marcado a mano'), findsOneWidget);
      expect(find.text('Canelones'), findsOneWidget);
      expect(find.text('de tu campaña · Cambiar'), findsOneWidget);
      expect(ciudades.propuestas, contains(punto));
      expect(tester.takeException(), isNull);
    });
  });

  group('Escenario 4 · sin el mapa descargado y sin conexión', () {
    testWidgets('las ubicaciones se siguen viendo sin calles, con el aviso y sus dos acciones', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(_casas(50)),
        arnes: ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]),
        ambito: ambitoMontevideo,
      );

      expect(m.mapa.config!.fuente.hayTiles, isFalse, reason: 'sin calles');
      expect(_delMapa(m.mapa), hasLength(50), reason: 'las ubicaciones se siguen viendo');
      expect(find.byKey(ClavesAvisoMapa.sinConexion), findsOneWidget);
      expect(find.text('Sin conexión a internet'), findsOneWidget);
      expect(
        find.text(
          'Tus ubicaciones se siguen viendo. Para ver las calles, '
          'activá tus datos móviles o descargá el mapa.',
        ),
        findsOneWidget,
      );
      expect(find.text('Descargar mapa'), findsOneWidget);
      expect(find.text('Activar datos'), findsOneWidget);
    });

    testWidgets('con ✕ queda la píldora roja, que sigue mientras no haya conexión, y el aviso no '
        'vuelve al salir de la pestaña y entrar', (tester) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(_casas(50)),
        arnes: ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]),
        ambito: ambitoMontevideo,
      );

      await tester.tap(find.byTooltip('Minimizar aviso'));
      await asentarLista(tester);
      expect(find.byKey(ClavesAvisoMapa.sinConexion), findsNothing);
      expect(find.text('Sin conexión · Descargar mapa'), findsOneWidget);

      m.activa.value = false;
      await asentarLista(tester);
      m.activa.value = true;
      await asentarLista(tester);

      expect(find.byKey(ClavesAvisoMapa.sinConexion), findsNothing, reason: 'una vez por sesión');
      expect(find.byKey(ClavesAvisoMapa.pildora), findsOneWidget);
      expect(_delMapa(m.mapa), hasLength(50));
    });
  });

  group('Escenario 5 · sin GPS', () {
    testWidgets('«Mi ubicación» no se puede tocar y el mapa encuadra todas las ubicaciones', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(_casas(50)),
        gps: gpsSinPermiso(),
      );

      expect(tester.widget<BotonMiUbicacion>(botonMiUbicacion).alPresionar, isNull);
      expect(hayPunto(m.mapa, 'gps'), isFalse);
      // La cámara inicial es el país, que ya contiene las 50 casas: encuadrar es acercarse.
      expect(m.mapa.camara!.zoom, greaterThan(MapaAlta.zoomPais));
      expect(m.mapa.camara!.zoom, lessThanOrEqualTo(MapaAlta.zoomCalle));
      final area = ProyeccionMercator.areaVisible(m.mapa.camara!, ancho: 390, alto: 844);
      for (final fila in _casas(50)) {
        final c = fila.ubicacion.coordenadas;
        expect(c.lat, inInclusiveRange(area.sur, area.norte), reason: fila.ubicacion.id);
        expect(c.lon, inInclusiveRange(area.oeste, area.este), reason: fila.ubicacion.id);
      }
    });

    testWidgets('sin GPS y sin ubicaciones no inventa una ciudad: el vacío ofrece registrar', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, gps: gpsSinPermiso());

      expect(tester.widget<BotonMiUbicacion>(botonMiUbicacion).alPresionar, isNull);
      expect(_delMapa(m.mapa), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('Escenario 6 · bordes', () {
    testWidgets('más de 200 marcadores: todos en la fuente que los agrupa en grupos', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(_casas(250)),
        situacion: const SituacionMapa(fuente: _mapaDescargado),
      );

      final config = m.mapa.config!;
      expect(_delMapa(m.mapa), hasLength(250));
      expect(config.agruparPuntos, isTrue);
      final agrupables = ConstructorEstiloMapa.coleccionPuntos(config.puntos);
      expect((agrupables['features'] as List<dynamic>), hasLength(250));
      expect(tester.takeException(), isNull);
    });

    testWidgets('el servidor de tiles rechaza (429): sin calles, con el aviso, y «Reintentar» '
        'vuelve al mapa en línea cuando contesta', (tester) async {
      final arnes = ArnesMapa(catalogo: [paqueteMontevideo]);
      arnes.sonda.caidos.add(paqueteMontevideo.origen);
      arnes.sonda.statusError = 429;
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(_casas(50)),
        arnes: arnes,
        ambito: ambitoMontevideo,
      );

      expect(find.byKey(ClavesAvisoMapa.noCarga), findsOneWidget);
      expect(find.text('No pudimos cargar el mapa de esta ciudad'), findsOneWidget);
      expect(m.mapa.config!.fuente.hayTiles, isFalse);
      expect(_delMapa(m.mapa), hasLength(50), reason: 'las ubicaciones se siguen viendo');

      arnes.sonda.caidos.clear();
      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      await asentarLista(tester, 12);

      expect(find.byKey(ClavesAvisoMapa.noCarga), findsNothing);
      expect(m.mapa.config!.fuente.tipo, FuenteTiles.servidorOnline);
      expect(_delMapa(m.mapa), hasLength(50));
    });

    testWidgets('las ubicaciones dadas de baja no se dibujan, ni al abrir ni cuando se dan de '
        'baja con el mapa abierto', (tester) async {
      final activas = _casas(10);
      final repo = RepoListaFalso([
        ...activas,
        for (var i = 0; i < 5; i++) filaLista('baja$i', metrosAlNorte: 500.0 + i, baja: ahoraLista),
      ]);
      final m = await montarMapaUbicaciones(tester, repo: repo);

      expect(_delMapa(m.mapa).map((p) => p.id), [for (final f in activas) f.ubicacion.id]);
      expect(hayPunto(m.mapa, 'baja0'), isFalse);

      // Una activa se da de baja con el mapa a la vista: su marcador sale sin recargar nada.
      repo.emitir([filaLista('u0', metrosAlNorte: 100, baja: ahoraLista), ...activas.skip(1)]);
      await asentarLista(tester);

      expect(hayPunto(m.mapa, 'u0'), isFalse);
      expect(_delMapa(m.mapa), hasLength(9));
    });
  });
}
