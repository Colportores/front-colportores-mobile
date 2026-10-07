// HU-UBI-003 · vista 06 «Mapa de ubicaciones» (#199): un grupo por artboard del canvas
// (`06 Mapa Ubicaciones.dc.html`) y por estado que el canvas no dibuja. Los casos límite de cada
// flujo (doble toque, fallas, volver a entrar, datos extremos) están en
// `mapa_ubicaciones_casos_limite_test.dart`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_descargas_arnes.dart';
import 'mapa_ubicaciones_arnes.dart';

/// Las ubicaciones del canvas, de la más cercana a la más lejana (el GPS está en `puntoItalia`).
List<UbicacionConResumen> canvas() => [
  filaLista(
    'a',
    calle: 'Av. Italia',
    numero: '1234',
    metrosAlNorte: 40,
    espacios: 2,
    estado: EstadoCasa.cobranzaPendiente,
  ),
  filaLista('b', calle: 'Av. Italia', numero: '1250', metrosAlNorte: 55),
  filaLista('c', calle: 'Av. Italia', numero: '1236', metrosAlNorte: 58),
  filaLista(
    'd',
    tipo: TipoUbicacion.negocio,
    calle: 'Comercio',
    numero: '2381',
    metrosAlNorte: 90,
    estado: EstadoCasa.entrevistaAgendada,
  ),
  filaLista(
    'e',
    calle: 'Michigan',
    numero: '1540',
    metrosAlNorte: 120,
    estado: EstadoCasa.noContesto,
  ),
  filaLista(
    'f',
    tipo: TipoUbicacion.edificio,
    calle: 'Mataojo',
    numero: '2044',
    metrosAlNorte: 160,
    espacios: 6,
    estado: EstadoCasa.entrevistaHecha,
  ),
];

/// Un GPS al que el colportor no le dio el permiso.
GpsFalso gpsSinPermiso() =>
    GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado)));

void main() {
  group('06C·01 · hoja minimizada · cerca tuyo los marcadores muestran el número', () {
    testWidgets('dibuja la pestaña Cercanía con la cuenta, los botones y «Referencias»', (
      tester,
    ) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      final pestana = find.byKey(ClavesMapaUbicaciones.pestanaCercania);
      expect(find.descendant(of: pestana, matching: find.text('Cercanía')), findsOneWidget);
      expect(find.descendant(of: pestana, matching: find.text('6')), findsOneWidget);
      expect(botonMiUbicacion, findsOneWidget);
      expect(botonNueva, findsOneWidget);
      expect(find.descendant(of: botonNueva, matching: find.text('Nueva')), findsOneWidget);
      expect(chipReferencias, findsOneWidget);
      expect(find.text('Referencias'), findsOneWidget);
      // Minimizada solo se ve la pestaña: ninguna fila, ninguna vista previa.
      expect(altoHoja(tester), AlturaHoja.altoMinimizada(TextScaler.noScaling));
      expect(fila('a'), findsNothing);
      expect(vistaPrevia, findsNothing);
      // «Agendados» llega con las visitas (HU-VIS-001/002): por ahora la hoja no lo ofrece.
      expect(find.text('Agendados'), findsNothing);
    });

    testWidgets('a menos de 60 m del GPS el marcador crece y muestra su número de puerta; el '
        'resto, un círculo; el GPS, el punto azul con su radio y el área de cerca tuyo', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      final mapa = m.mapa;

      for (final (id, numero) in [('a', '1234'), ('b', '1250'), ('c', '1236')]) {
        expect(punto(mapa, id).estilo, EstiloPunto.cercano, reason: id);
        expect(punto(mapa, id).etiqueta, numero, reason: id);
      }
      for (final id in ['d', 'e', 'f']) {
        expect(punto(mapa, id).estilo, EstiloPunto.contexto, reason: id);
        expect(punto(mapa, id).etiqueta, isNull, reason: id);
      }
      expect(punto(mapa, 'gps').estilo, EstiloPunto.gps);
      expect(mapa.config!.precision!.radioMetros, 6);
      expect(mapa.config!.cercania!.radioMetros, 60);
      expect(mapa.config!.cercania!.centro, puntoItalia);
      expect(mapa.config!.agruparPuntos, isTrue);
      expect(mapa.config!.puntosTocables, isTrue);
    });

    testWidgets('al abrir, el mapa se centra en el GPS a nivel de calle', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      expect(m.mapa.camara!.centro, puntoItalia);
      expect(m.mapa.camara!.zoom, MapaAlta.zoomCalle);
    });

    testWidgets('un marcador sin número de puerta cerca tuyo dice «s/n»', (tester) async {
      final repo = RepoListaFalso([filaLista('x', calle: 'Rivera', numero: '', metrosAlNorte: 10)]);
      final m = await montarMapaUbicaciones(tester, repo: repo);

      expect(punto(m.mapa, 'x').etiqueta, 's/n');
    });

    testWidgets('«Mi ubicación» vuelve al GPS desde donde se haya movido el mapa y pide otra '
        'lectura', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      m.mapa.moverPorGesto(
        CamaraMapa(centro: ProyeccionMercator.aCoordenadas(100, 100, 5), zoom: 5),
      );
      await tester.pump();
      expect(m.gps.lecturas, 1);

      await tester.tap(botonMiUbicacion);
      await asentarLista(tester);

      expect(m.mapa.camara!.centro, puntoItalia);
      expect(m.mapa.camara!.zoom, MapaAlta.zoomCalle);
      expect(m.gps.lecturas, 2);
    });
  });

  group('06C·02 · hoja a 1/3 · Cercanía', () {
    testWidgets('el asa sube la hoja de a una altura y vuelve a la minimizada', (tester) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      final minimizada = altoHoja(tester);

      await tocarAsa(tester);
      expect(altoHoja(tester), closeTo(844 / 3, 1));

      await tocarAsa(tester);
      expect(altoHoja(tester), closeTo(844 / 2, 1));

      await tocarAsa(tester);
      expect(altoHoja(tester), minimizada);
    });

    testWidgets('lista de la más cercana a la más lejana, con la distancia a la derecha y sin '
        'flecha (todavía no hay a dónde ir)', (tester) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await tocarAsa(tester, 2);

      for (final id in ['a', 'b', 'c', 'd']) {
        expect(fila(id), findsOneWidget, reason: id);
      }
      final tops = [
        for (final id in ['a', 'b', 'c', 'd']) tester.getTopLeft(fila(id)).dy,
      ];
      expect(tops, [...tops]..sort());
      expect(find.text('Av. Italia 1234'), findsOneWidget);
      expect(find.text(FormatoUbicaciones.distancia(40)), findsOneWidget);
      expect(find.text(FormatoUbicaciones.distancia(55)), findsOneWidget);
      expect(find.text('Cobranza pendiente · 2 espacios'), findsOneWidget);
      expect(find.text('›'), findsNothing);
    });

    testWidgets('arrastrar el asa cambia la altura; soltar a medio camino va a la más cercana', (
      tester,
    ) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      await tester.drag(asa, const Offset(0, -150));
      await asentarLista(tester);
      expect(altoHoja(tester), closeTo(844 / 3, 1));

      await tester.drag(asa, const Offset(0, -150));
      await asentarLista(tester);
      expect(altoHoja(tester), closeTo(844 / 2, 1));

      await tester.drag(asa, const Offset(0, 400));
      await asentarLista(tester);
      expect(altoHoja(tester), AlturaHoja.altoMinimizada(TextScaler.noScaling));
    });

    testWidgets('un envión hacia arriba sube una sola altura aunque el dedo llegue lejos', (
      tester,
    ) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      await tester.fling(asa, const Offset(0, -500), 2000);
      await asentarLista(tester);

      expect(altoHoja(tester), closeTo(844 / 3, 1));
    });

    testWidgets('la lista es parte de la hoja: se desplaza sin mover el mapa', (tester) async {
      final repo = RepoListaFalso([
        for (var i = 0; i < 40; i++)
          filaLista('u$i', calle: 'Calle $i', numero: '${i + 1}', metrosAlNorte: 100.0 + i),
      ]);
      final m = await montarMapaUbicaciones(tester, repo: repo);
      await tocarAsa(tester, 2);
      final antes = m.mapa.movimientos.length;

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await asentarLista(tester);

      expect(m.mapa.movimientos.length, antes);
      expect(fila('u0'), findsNothing);
      expect(find.byKey(ClavesMapaUbicaciones.pestanaCercania), findsOneWidget);
    });
  });

  group('06C·03 · Agendados', () {
    testWidgets('no se ofrece: llega con las visitas (HU-VIS-001/002, S8), decisión de Cristian '
        'en el #199', (tester) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await tocarAsa(tester, 2);

      expect(find.text('Agendados'), findsNothing);
      expect(find.text('Atrasados'), findsNothing);
      expect(find.text('Cobranzas'), findsNothing);
    });
  });

  group('06C·04 · ubicación seleccionada · hoja a 1/3 (vista previa)', () {
    testWidgets('tocar un marcador sube la hoja a 1/3 con la vista previa y centra el mapa en él, '
        'sobre la parte que la hoja deja libre', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      m.mapa.tocarPunto('a');
      await asentarLista(tester);

      expect(altoHoja(tester), closeTo(844 / 3, 1));
      expect(vistaPrevia, findsOneWidget);
      expect(find.text('CASA · 2 ESPACIOS · A 40 M'), findsOneWidget);
      expect(find.text('Av. Italia 1234'), findsOneWidget);
      expect(find.text('Cobranza pendiente'), findsOneWidget);
      expect(fila('a'), findsNothing);
      // El marcador se ve con el aro; su número sigue visible.
      expect(punto(m.mapa, 'a').estilo, EstiloPunto.seleccionado);
      expect(punto(m.mapa, 'a').etiqueta, '1234');
      // El centro de la vista queda más al sur que el punto: el punto se ve arriba de la hoja.
      final centro = m.mapa.camara!.centro;
      final ubicacion = canvas().first.ubicacion.coordenadas;
      expect(centro.lat, lessThan(ubicacion.lat));
      expect(centro.lon, closeTo(ubicacion.lon, 1e-9));
    });

    testWidgets('el rótulo no inventa la distancia sin GPS', (tester) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(canvas()),
        gps: gpsSinPermiso(),
      );

      m.mapa.tocarPunto('d');
      await asentarLista(tester);

      expect(find.text('NEGOCIO · 1 ESPACIO'), findsOneWidget);
      expect(find.textContaining(' A '), findsNothing);
    });

    testWidgets('la ✕ cierra la vista previa y vuelve a la lista, en la misma altura', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      m.mapa.tocarPunto('a');
      await asentarLista(tester);

      await tester.tap(cerrarVistaPrevia);
      await asentarLista(tester);

      expect(vistaPrevia, findsNothing);
      expect(fila('a'), findsOneWidget);
      expect(altoHoja(tester), closeTo(844 / 3, 1));
      expect(punto(m.mapa, 'a').estilo, EstiloPunto.cercano);
    });

    testWidgets('tocar una fila de la lista abre su vista previa y centra el mapa en ella', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await tocarAsa(tester);

      await tester.tap(fila('b'));
      await asentarLista(tester);

      expect(vistaPrevia, findsOneWidget);
      expect(find.text('Av. Italia 1250'), findsOneWidget);
      expect(punto(m.mapa, 'b').estilo, EstiloPunto.seleccionado);
    });

    testWidgets('tocar «Tu ubicación» no abre ninguna vista previa', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      m.mapa.tocarPunto('gps');
      await asentarLista(tester);

      expect(vistaPrevia, findsNothing);
      expect(altoHoja(tester), AlturaHoja.altoMinimizada(TextScaler.noScaling));
    });

    testWidgets('con la ubicación dada de baja mientras se ve su vista previa, vuelve la lista', (
      tester,
    ) async {
      final repo = RepoListaFalso(canvas());
      final m = await montarMapaUbicaciones(tester, repo: repo);
      m.mapa.tocarPunto('a');
      await asentarLista(tester);
      expect(vistaPrevia, findsOneWidget);

      repo.emitir(canvas().skip(1).toList());
      await asentarLista(tester);

      expect(vistaPrevia, findsNothing);
      expect(fila('b'), findsOneWidget);
      expect(hayPunto(m.mapa, 'a'), isFalse);
    });

    testWidgets('los botones y la cuota de la vista previa llegan con sus HU: no se dibujan '
        '(HU-VIS-001/002 y HU-COB-005)', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      m.mapa.tocarPunto('a');
      await asentarLista(tester);

      for (final texto in ['Registrar visita', 'Agendar', 'Detalle']) {
        expect(find.text(texto), findsNothing, reason: texto);
      }
    });
  });

  group('06C·05 / 06C·06 · sin conexión y sin mapa descargado', () {
    testWidgets('con la ciudad conocida: el aviso rojo con «Descargar mapa» y «Activar datos»; '
        'el chip «Referencias» se corre', (tester) async {
      await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(canvas()),
        arnes: ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]),
        ambito: ambitoMontevideo,
      );

      expect(find.byKey(ClavesAvisoMapa.sinConexion), findsOneWidget);
      expect(find.text('Sin conexión a internet'), findsOneWidget);
      expect(find.text('Descargar mapa'), findsOneWidget);
      expect(find.text('Activar datos'), findsOneWidget);
      expect(chipReferencias, findsNothing);
      // Los botones de la hoja siguen a la mano.
      expect(botonNueva, findsOneWidget);
      expect(find.byKey(ClavesMapaUbicaciones.pestanaCercania), findsOneWidget);
    });

    testWidgets('la ✕ lo minimiza a la píldora «Sin conexión · Descargar mapa» y el mapa sigue '
        'con sus ubicaciones', (tester) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(canvas()),
        arnes: ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]),
        ambito: ambitoMontevideo,
      );

      await tester.tap(find.byTooltip('Minimizar aviso'));
      await asentarLista(tester);

      expect(find.byKey(ClavesAvisoMapa.sinConexion), findsNothing);
      expect(find.byKey(ClavesAvisoMapa.pildora), findsOneWidget);
      expect(find.text('Sin conexión · Descargar mapa'), findsOneWidget);
      expect(chipReferencias, findsNothing);
      expect(m.mapa.config!.puntos.length, 7);
    });

    testWidgets('sin ciudad conocida no se ofrece «Descargar mapa»: ni en la tarjeta ni en la '
        'píldora (decisión de Cristian en el #199)', (tester) async {
      await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(canvas()),
        arnes: ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]),
      );

      expect(find.byKey(ClavesAvisoMapa.sinConexion), findsOneWidget);
      expect(
        find.text(
          'Tus ubicaciones se siguen viendo. Para ver las calles, activá tus datos móviles.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Descargar mapa'), findsNothing);
      expect(find.text('Activar datos'), findsOneWidget);

      await tester.tap(find.byTooltip('Minimizar aviso'));
      await asentarLista(tester);

      expect(find.byKey(ClavesAvisoMapa.pildora), findsOneWidget);
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.textContaining('Descargar mapa'), findsNothing);
    });
  });

  group('06C·07 · con datos móviles y sin mapa descargado', () {
    testWidgets('«Estás viendo el mapa con datos móviles» con el peso y «Ahora no»; al descartarlo '
        'vuelve «Referencias»', (tester) async {
      await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(canvas()),
        arnes: ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]),
        ambito: ambitoMontevideo,
      );

      expect(find.byKey(ClavesAvisoMapa.datosMoviles), findsOneWidget);
      expect(find.text('Estás viendo el mapa con datos móviles'), findsOneWidget);
      expect(find.text('Descargar mapa · 1 MB'), findsOneWidget);
      expect(chipReferencias, findsNothing);

      await tester.tap(find.text('Ahora no'));
      await asentarLista(tester);

      expect(find.byKey(ClavesAvisoMapa.datosMoviles), findsNothing);
      expect(chipReferencias, findsOneWidget);
    });

    testWidgets('sin ciudad conocida no hay nada que descargar: ningún aviso y «Referencias» se '
        've', (tester) async {
      await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(canvas()),
        arnes: ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]),
      );

      expect(find.byKey(ClavesAvisoMapa.datosMoviles), findsNothing);
      expect(find.textContaining('Descargar mapa'), findsNothing);
      expect(chipReferencias, findsOneWidget);
    });
  });

  group('«Referencias» · la leyenda de los marcadores', () {
    testWidgets('abre la leyenda con los marcadores que el mapa dibuja y se cierra', (
      tester,
    ) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      await tester.tap(chipReferencias);
      await asentarLista(tester);

      expect(hojaReferencias, findsOneWidget);
      for (final texto in [
        'Sin visita',
        'Agrupadas',
        'Cerca tuyo: crece y muestra el número',
        'Tu ubicación',
      ]) {
        expect(find.text(texto), findsOneWidget, reason: texto);
      }

      await tester.tap(find.byKey(ClavesMapaUbicaciones.cerrarReferencias));
      await asentarLista(tester);
      expect(hojaReferencias, findsNothing);
    });
  });

  group('estados que el canvas no dibuja', () {
    testWidgets('cargando: la pestaña lo dice y la hoja, cuando se abre, muestra «Cargando '
        'ubicaciones» hasta que llega la lista', (tester) async {
      final repo = RepoListaFalso(canvas())..bloqueo = Completer<void>();
      await montarMapaUbicaciones(tester, repo: repo);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tocarAsa(tester);
      expect(find.byKey(ClavesMapaUbicaciones.cargando), findsOneWidget);
      expect(find.text('Cargando ubicaciones'), findsOneWidget);

      repo.bloqueo!.complete();
      await asentarLista(tester);

      expect(find.byKey(ClavesMapaUbicaciones.cargando), findsNothing);
      expect(fila('a'), findsOneWidget);
    });

    testWidgets('sin ubicaciones: la hoja sube sola y ofrece registrar la primera', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso());

      expect(altoHoja(tester), closeTo(844 / 2, 1));
      expect(find.byKey(ClavesMapaUbicaciones.vacio), findsOneWidget);
      expect(find.text('Todavía no registraste ubicaciones'), findsOneWidget);

      await tester.tap(find.byKey(ClavesMapaUbicaciones.registrarPrimera));
      await asentarLista(tester);

      expect(m.altas, [null]);
    });

    testWidgets('solo ubicaciones dadas de baja: no dice que no registró ninguna', (tester) async {
      final repo = RepoListaFalso([filaLista('z', baja: DateTime.utc(2026, 9, 12))]);
      await montarMapaUbicaciones(tester, repo: repo);

      expect(find.text('No tenés ubicaciones activas'), findsOneWidget);
      expect(find.text('Todavía no registraste ubicaciones'), findsNothing);
      expect(find.text('Registrar una ubicación'), findsOneWidget);
    });

    testWidgets('error de lectura: la hoja sube sola con «Reintentar», que vuelve a leer', (
      tester,
    ) async {
      final repo = RepoListaFalso(canvas())..fallaAlSuscribir = true;
      await montarMapaUbicaciones(tester, repo: repo);

      expect(altoHoja(tester), closeTo(844 / 2, 1));
      expect(find.text('No pudimos leer tus ubicaciones.'), findsOneWidget);

      repo.fallaAlSuscribir = false;
      await tester.tap(find.byKey(ClavesMapaUbicaciones.reintentar));
      await asentarLista(tester);

      expect(find.text('No pudimos leer tus ubicaciones.'), findsNothing);
      expect(fila('a'), findsOneWidget);
      expect(repo.activas, 1);
    });

    testWidgets('error después de tener la lista: se sigue viendo, con el aviso y «Reintentar»', (
      tester,
    ) async {
      final repo = RepoListaFalso(canvas());
      final m = await montarMapaUbicaciones(tester, repo: repo);
      await tocarAsa(tester);

      repo.fallar(StateError('se cerró la base'));
      await asentarLista(tester);

      expect(find.text('No pudimos leer tus ubicaciones.'), findsOneWidget);
      expect(fila('a'), findsOneWidget);
      expect(m.mapa.config!.puntos.length, 7);
    });

    testWidgets('sin GPS: «Mi ubicación» no está disponible y la hoja ofrece «Activar GPS»', (
      tester,
    ) async {
      final gps = gpsSinPermiso();
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gps);

      expect(tester.widget<BotonMiUbicacion>(botonMiUbicacion).alPresionar, isNull);
      expect(hayPunto(m.mapa, 'gps'), isFalse);
      expect(m.mapa.config!.cercania, isNull);
      expect(m.mapa.config!.puntos.where((p) => p.estilo == EstiloPunto.cercano), isEmpty);

      await tocarAsa(tester);
      expect(find.text('Sin GPS no podemos ordenarlas por cercanía.'), findsOneWidget);

      gps.alActivar = () => gps.respuesta = Right(lecturaGps(6));
      await tester.tap(find.byKey(ClavesMapaUbicaciones.activarGps));
      await asentarLista(tester);

      expect(gps.activaciones, [MotivoSinGps.permisoDenegado]);
      expect(tester.widget<BotonMiUbicacion>(botonMiUbicacion).alPresionar, isNotNull);
      expect(find.byKey(ClavesMapaUbicaciones.activarGps), findsNothing);
      expect(punto(m.mapa, 'gps').estilo, EstiloPunto.gps);
    });

    testWidgets('sin GPS el mapa encuadra todas las ubicaciones', (tester) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(canvas()),
        gps: gpsSinPermiso(),
      );

      final area = ProyeccionMercator.areaVisible(m.mapa.camara!, ancho: 390, alto: 844);
      for (final fila in canvas()) {
        final c = fila.ubicacion.coordenadas;
        expect(c.lat, inInclusiveRange(area.sur, area.norte));
        expect(c.lon, inInclusiveRange(area.oeste, area.este));
      }
      expect(m.mapa.camara!.zoom, lessThanOrEqualTo(MapaAlta.zoomCalle));
    });
  });
}
