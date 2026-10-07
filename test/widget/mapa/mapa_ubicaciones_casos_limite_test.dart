// HU-UBI-003 · vista 06 (#199): los casos límite de cada flujo del mapa de ubicaciones. Doble toque
// y doble envío, fallas a mitad de la acción, dos acciones seguidas, volver atrás y reentrar, y los
// datos extremos (vacío, listas largas, textos largos). Los artboards del canvas están en
// `mapa_ubicaciones_page_test.dart`; el texto 2.0 y los 48 dp, en
// `mapa_ubicaciones_accesibilidad_test.dart`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart'
    show LecturaGps;
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas, gpsSinPermiso;

const _textoSinAlta = 'No pudimos abrir «Nueva ubicación». Probá de nuevo.';
const _textoOtroColportor =
    'Esa ubicación ya la registró otro colportor. No hace falta registrarla de nuevo.';

/// La cámara que deja un gesto del colportor: el mapa centrado en [centro] a nivel de calle.
CamaraMapa _gesto(Coordenadas centro) => CamaraMapa(centro: centro, zoom: MapaAlta.zoomCalle);

void main() {
  group('«Nueva» y el dedo mantenido en el mapa · el alta', () {
    testWidgets('«Nueva» abre el alta sin punto; si se cierra sin registrar no cambia nada', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      final altura = altoHoja(tester);

      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(m.altas, [null]);
      expect(vistaPrevia, findsNothing);
      expect(altoHoja(tester), altura);
      expect(find.text(_textoSinAlta), findsNothing);
    });

    testWidgets('mantener el dedo en el mapa abre el alta con ese punto', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      const punto = Coordenadas(lat: -34.9, lon: -56.2);

      m.mapa.tocarLargo(punto);
      await asentarLista(tester);

      expect(m.altas, [punto]);
    });

    testWidgets('un toque corto en un lugar vacío del mapa no hace nada', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      final altura = altoHoja(tester);

      m.mapa.tocar(const Coordenadas(lat: -34.9, lon: -56.2));
      await asentarLista(tester);

      expect(m.altas, isEmpty);
      expect(vistaPrevia, findsNothing);
      expect(altoHoja(tester), altura);
    });

    testWidgets('al registrar, la nueva ubicación queda seleccionada, con su vista previa, y el '
        'mapa la centra a nivel de calle', (tester) async {
      final repo = RepoListaFalso(canvas());
      final m = await montarMapaUbicaciones(tester, repo: repo);
      final nueva = filaLista('nueva', calle: 'Rivera', numero: '900', metrosAlNorte: 20);
      repo.emitir([...canvas(), nueva]);
      m.salidaAlta = UbicacionCreada(nueva.ubicacion);

      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(vistaPrevia, findsOneWidget);
      expect(find.text('Rivera 900'), findsOneWidget);
      expect(punto(m.mapa, 'nueva').estilo, EstiloPunto.seleccionado);
      expect(m.mapa.camara!.zoom, greaterThanOrEqualTo(MapaAlta.zoomCalle));
      expect(altoHoja(tester), closeTo(844 / 3, 1));
    });

    testWidgets('al reutilizar una existente (aviso de duplicado) se abre la que ya estaba', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      m.salidaAlta = const UbicacionReutilizada('c');

      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(vistaPrevia, findsOneWidget);
      expect(find.text('Av. Italia 1236'), findsOneWidget);
      expect(punto(m.mapa, 'c').estilo, EstiloPunto.seleccionado);
    });

    testWidgets('reutilizar una que no es del colportor (la registró otro) avisa, y no deja una '
        'vista previa vacía, el mapa quieto y nada elegido', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      m.salidaAlta = const UbicacionReutilizada('de-otro');
      final movimientos = m.mapa.movimientos.length;

      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(find.text(_textoOtroColportor), findsOneWidget);
      expect(vistaPrevia, findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(seleccionadaId(tester), isNull);
      // Ni se dibuja la ajena ni se centra el mapa en ella ni se sube la hoja.
      expect(hayPunto(m.mapa, 'de-otro'), isFalse);
      expect(m.mapa.movimientos.length, movimientos);
      expect(altoHoja(tester), AlturaHoja.altoMinimizada(TextScaler.noScaling));
    });

    testWidgets('reutilizar una ajena con otra elegida cierra la elegida: la selección no queda '
        'colgada ni reaparece si esa ubicación entra después a la lista', (tester) async {
      final repo = RepoListaFalso(canvas());
      final m = await montarMapaUbicaciones(tester, repo: repo);
      m.mapa.tocarPunto('a');
      await asentarLista(tester);
      expect(seleccionadaId(tester), 'a');
      m.salidaAlta = const UbicacionReutilizada('de-otro');

      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(find.text(_textoOtroColportor), findsOneWidget);
      expect(seleccionadaId(tester), isNull);
      expect(vistaPrevia, findsNothing);

      // Si más adelante esa ubicación llegara a la lista (el pull de ubicaciones ajenas), no se abre
      // sola: nadie la eligió.
      repo.emitir([...canvas(), filaLista('de-otro', calle: 'Rivera', numero: '77')]);
      await asentarLista(tester);

      expect(vistaPrevia, findsNothing);
      expect(seleccionadaId(tester), isNull);
    });

    testWidgets('el aviso de la ajena no se acumula: dos altas seguidas dejan un solo aviso', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      m.salidaAlta = const UbicacionReutilizada('de-otro');

      for (var i = 0; i < 2; i++) {
        await tester.tap(botonNueva);
        await asentarLista(tester);
      }

      expect(m.altas.length, 2);
      expect(find.text(_textoOtroColportor), findsOneWidget);
    });

    testWidgets('si el alta falla al abrirse avisa qué hacer y «Nueva» se puede volver a tocar', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      m.fallaAlta = StateError('sin navegador');

      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(find.text(_textoSinAlta), findsOneWidget);
      expect(m.altas.length, 1);

      m.fallaAlta = null;
      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(m.altas.length, 2);
    });

    testWidgets('si el alta falla a mitad de camino (después de abrirse) pasa lo mismo', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      m.esperaAlta = Completer<SalidaAltaUbicacion?>();

      await tester.tap(botonNueva);
      await asentarLista(tester);
      m.esperaAlta!.completeError(StateError('se cerró la base'));
      await asentarLista(tester);

      expect(find.text(_textoSinAlta), findsOneWidget);

      m.esperaAlta = null;
      await tester.tap(botonNueva);
      await asentarLista(tester);
      expect(m.altas.length, 2);
    });

    testWidgets('doble toque en «Nueva»: un solo alta; con el alta abierta tampoco se abre otro '
        'con el dedo mantenido, y al cerrarla se puede abrir de nuevo', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      m.esperaAlta = Completer<SalidaAltaUbicacion?>();

      await tester.tap(botonNueva);
      await tester.tap(botonNueva);
      await asentarLista(tester);
      m.mapa.tocarLargo(const Coordenadas(lat: -34.9, lon: -56.2));
      await asentarLista(tester);

      expect(m.altas.length, 1);

      m.esperaAlta!.complete(null);
      await asentarLista(tester);
      m.esperaAlta = null;
      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(m.altas.length, 2);
    });

    testWidgets('si el colportor sale de la pestaña mientras el alta está abierta, al volver el '
        'resultado no rompe nada', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      m.esperaAlta = Completer<SalidaAltaUbicacion?>();
      await tester.tap(botonNueva);
      await asentarLista(tester);

      await tester.pumpWidget(const SizedBox());
      m.esperaAlta!.complete(UbicacionCreada(canvas().first.ubicacion));
      await asentarLista(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('dos acciones seguidas', () {
    testWidgets('dos marcadores tocados antes de que termine el primero: queda la segunda vista '
        'previa, una sola, y el mapa en ella', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      m.mapa.tocarPunto('a');
      m.mapa.tocarPunto('b');
      await asentarLista(tester);

      expect(vistaPrevia, findsOneWidget);
      expect(find.text('Av. Italia 1250'), findsOneWidget);
      expect(find.text('Av. Italia 1234'), findsNothing);
      expect(punto(m.mapa, 'b').estilo, EstiloPunto.seleccionado);
      expect(punto(m.mapa, 'a').estilo, EstiloPunto.cercano);
    });

    testWidgets('una fila de la lista y enseguida un marcador: gana el último toque', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await tocarAsa(tester, 2);

      await tester.tap(fila('d'));
      m.mapa.tocarPunto('a');
      await asentarLista(tester);

      expect(find.text('Av. Italia 1234'), findsOneWidget);
      expect(find.text('Comercio 2381'), findsNothing);
      expect(punto(m.mapa, 'a').estilo, EstiloPunto.seleccionado);
      expect(punto(m.mapa, 'd').estilo, EstiloPunto.contexto);
    });

    testWidgets('«✕» tocada dos veces, y volver a elegir la misma ubicación', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      m.mapa.tocarPunto('a');
      await asentarLista(tester);

      await tester.tap(cerrarVistaPrevia);
      await tester.tap(cerrarVistaPrevia, warnIfMissed: false);
      await asentarLista(tester);
      expect(vistaPrevia, findsNothing);
      expect(punto(m.mapa, 'a').estilo, EstiloPunto.cercano);

      m.mapa.tocarPunto('a');
      await asentarLista(tester);
      expect(vistaPrevia, findsOneWidget);
      expect(punto(m.mapa, 'a').estilo, EstiloPunto.seleccionado);
    });

    testWidgets('dos toques seguidos al asa suben una sola altura', (tester) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      await tester.tap(asa);
      await tester.tap(asa);
      await asentarLista(tester, 6);

      expect(altoHoja(tester), closeTo(844 / 3, 1));
    });

    testWidgets('«Mi ubicación» dos veces: la lectura más nueva es la que vale, aunque la más '
        'vieja llegue después', (tester) async {
      final gps = GpsFalso();
      final c2 = Completer<Either<Failure, LecturaGps>>();
      final c3 = Completer<Either<Failure, LecturaGps>>();
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gps);
      gps.porLectura = (numero) => switch (numero) {
        2 => c2.future,
        3 => c3.future,
        _ => Future.value(Right(lecturaGps(6))),
      };
      const vieja = Coordenadas(lat: -34.8870, lon: -56.1302);
      const nueva = Coordenadas(lat: -34.8860, lon: -56.1302);

      await tester.tap(botonMiUbicacion);
      await tester.tap(botonMiUbicacion);
      await asentarLista(tester);
      c3.complete(Right(lecturaGps(5, punto: nueva)));
      await asentarLista(tester);
      c2.complete(Right(lecturaGps(5, punto: vieja)));
      await asentarLista(tester);

      expect(gps.lecturas, 3);
      expect(punto(m.mapa, 'gps').coordenadas, nueva);
      expect(m.repo.activas, 1);
    });

    testWidgets('«Activar GPS» tocado dos veces abre un solo diálogo del sistema', (tester) async {
      final gps = gpsSinPermiso()..bloqueoActivacion = Completer<void>();
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gps);
      await tocarAsa(tester);

      await tester.tap(find.byKey(ClavesMapaUbicaciones.activarGps));
      await tester.tap(find.byKey(ClavesMapaUbicaciones.activarGps), warnIfMissed: false);
      await asentarLista(tester);
      expect(gps.activaciones.length, 1, reason: 'el diálogo del sistema sigue abierto');

      gps.bloqueoActivacion!.complete();
      await asentarLista(tester);
      expect(gps.activaciones.length, 1);
      expect(gps.lecturas, 2);
    });

    testWidgets('si el sistema no puede abrir el permiso, «Activar GPS» sigue disponible', (
      tester,
    ) async {
      final gps = gpsSinPermiso()..alActivar = () => throw StateError('sin ajustes');
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gps);
      await tocarAsa(tester);

      await tester.tap(find.byKey(ClavesMapaUbicaciones.activarGps));
      await asentarLista(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesMapaUbicaciones.activarGps), findsOneWidget);

      await tester.tap(find.byKey(ClavesMapaUbicaciones.activarGps));
      await asentarLista(tester);
      expect(gps.activaciones.length, 2);
    });

    testWidgets('«Reintentar» tocado dos veces vuelve a leer una sola vez', (tester) async {
      final repo = RepoListaFalso(canvas())..fallaAlSuscribir = true;
      await montarMapaUbicaciones(tester, repo: repo);
      repo.fallaAlSuscribir = false;

      await tester.tap(find.byKey(ClavesMapaUbicaciones.reintentar));
      await tester.tap(find.byKey(ClavesMapaUbicaciones.reintentar), warnIfMissed: false);
      await asentarLista(tester);

      expect(repo.activas, 1);
      expect(fila('a'), findsOneWidget);
    });

    testWidgets('«Referencias» tocado dos veces abre una sola leyenda', (tester) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      await tester.tap(chipReferencias);
      await tester.tap(chipReferencias, warnIfMissed: false);
      await asentarLista(tester);

      expect(hojaReferencias, findsOneWidget);
    });
  });

  group('volver atrás y reentrar', () {
    testWidgets('con la pestaña sin abrir no se arma el mapa ni se lee la base ni el GPS', (
      tester,
    ) async {
      final repo = RepoListaFalso(canvas());
      final gps = GpsFalso();
      final m = await montarMapaUbicaciones(tester, repo: repo, gps: gps, activa: false);

      expect(m.mapa.armada, isFalse);
      expect(gps.lecturas, 0);
      expect(repo.suscripciones, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      m.activa.value = true;
      await asentarLista(tester);

      expect(m.mapa.armada, isTrue);
      expect(gps.lecturas, 1);
      // La base se lee dos veces: sin posición, y otra vez con la posición del GPS cuando llega.
      expect(repo.suscripciones, 2);
      expect(repo.activas, 1);
      expect(fila('a'), findsNothing);
      expect(find.byKey(ClavesMapaUbicaciones.pestanaCercania), findsOneWidget);
    });

    testWidgets('al volver a la pestaña refresca el GPS y conserva la selección, la altura de la '
        'hoja y el lugar al que el colportor movió el mapa', (tester) async {
      final repo = RepoListaFalso(canvas());
      final m = await montarMapaUbicaciones(tester, repo: repo);
      m.mapa.tocarPunto('a');
      await asentarLista(tester);
      const aparte = Coordenadas(lat: -34.7, lon: -56.0);
      m.mapa.moverPorGesto(_gesto(aparte));
      await tester.pump();
      final altura = altoHoja(tester);

      m.activa.value = false;
      await asentarLista(tester);
      m.activa.value = true;
      await asentarLista(tester);

      expect(m.gps.lecturas, 2);
      expect(vistaPrevia, findsOneWidget);
      expect(altoHoja(tester), altura);
      expect(m.mapa.camara!.centro, aparte);
      expect(repo.activas, 1);
    });

    testWidgets('si no tenía GPS por el permiso, volver a la pestaña no vuelve a pedirlo', (
      tester,
    ) async {
      final gps = gpsSinPermiso();
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gps);

      m.activa.value = false;
      await asentarLista(tester);
      m.activa.value = true;
      await asentarLista(tester);

      expect(gps.lecturas, 1);
      expect(gps.activaciones, isEmpty);
    });

    testWidgets('«Referencias» se abre, se cierra y se vuelve a abrir', (tester) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      for (var i = 0; i < 2; i++) {
        await tester.tap(chipReferencias);
        await asentarLista(tester);
        expect(hojaReferencias, findsOneWidget);
        await tester.tap(find.byKey(ClavesMapaUbicaciones.cerrarReferencias));
        await asentarLista(tester);
        expect(hojaReferencias, findsNothing);
      }
    });

    testWidgets('el alta se abre, se cierra sin registrar y se puede abrir otra vez', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      for (var i = 0; i < 3; i++) {
        await tester.tap(botonNueva);
        await asentarLista(tester);
      }

      expect(m.altas, [null, null, null]);
    });

    testWidgets('si la base se vacía mientras se ve una vista previa, vuelve el vacío con la '
        'hoja a la vista', (tester) async {
      final repo = RepoListaFalso(canvas());
      final m = await montarMapaUbicaciones(tester, repo: repo);
      m.mapa.tocarPunto('a');
      await asentarLista(tester);

      repo.emitir(const []);
      await asentarLista(tester);

      expect(vistaPrevia, findsNothing);
      expect(find.byKey(ClavesMapaUbicaciones.vacio), findsOneWidget);
    });
  });

  group('datos límite', () {
    testWidgets('300 ubicaciones: todas en el mapa, la cuenta las dice y la lista se desplaza', (
      tester,
    ) async {
      final repo = RepoListaFalso([
        for (var i = 0; i < 300; i++)
          filaLista(
            'u$i',
            calle: 'Calle $i',
            numero: '${i + 1}',
            metrosAlNorte: 100.0 + i * 10,
            espacios: i % 5,
          ),
      ]);
      final m = await montarMapaUbicaciones(tester, repo: repo);

      expect(m.mapa.config!.puntos.length, 301);
      expect(
        find.descendant(
          of: find.byKey(ClavesMapaUbicaciones.pestanaCercania),
          matching: find.text('300'),
        ),
        findsOneWidget,
      );

      await tocarAsa(tester, 2);
      expect(fila('u0'), findsOneWidget);
      expect(fila('u299'), findsNothing);
      for (var i = 0; i < 40 && fila('u299').evaluate().isEmpty; i++) {
        await tester.fling(find.byType(ListView), const Offset(0, -3000), 8000);
        await asentarLista(tester, 4);
      }
      expect(fila('u299'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una sola ubicación: «1 ubicación» en el lector de pantalla y sin plural', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarMapaUbicaciones(tester, repo: RepoListaFalso([filaLista('a')]));

      expect(find.bySemanticsLabel('Cercanía, 1 ubicación'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('direcciones larguísimas y sin número ni calle no desbordan ni quedan vacías', (
      tester,
    ) async {
      final calle = 'Avenida General Don José Gervasio Artigas y Camino Maldonado ' * 4;
      final repo = RepoListaFalso([
        filaLista('larga', calle: calle, numero: '1234567890', metrosAlNorte: 30),
        filaLista('sin', calle: '', numero: '', metrosAlNorte: 50),
      ]);
      final m = await montarMapaUbicaciones(tester, repo: repo, escala: 2);
      await tocarAsa(tester, 2);

      expect(fila('larga'), findsOneWidget);
      // Con el texto al doble la primera fila ocupa casi toda la hoja: la otra se alcanza con el dedo.
      for (var i = 0; i < 10 && find.text('Sin dirección').evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await asentarLista(tester, 4);
      }
      expect(find.text('Sin dirección'), findsOneWidget);
      m.mapa.tocarPunto('larga');
      await asentarLista(tester);
      expect(vistaPrevia, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ubicaciones a muy distintas distancias, hasta en otro departamento: el '
        'encuadre las incluye a todas sin GPS', (tester) async {
      final repo = RepoListaFalso([
        filaLista('mvd', metrosAlNorte: 10),
        filaLista('salto', metrosAlNorte: 480000),
      ]);
      final m = await montarMapaUbicaciones(tester, repo: repo, gps: gpsSinPermiso());

      expect(m.mapa.camara!.zoom, lessThan(MapaAlta.zoomCalle));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin GPS, al llegar la lectura el mapa pasa a ella una sola vez y no vuelve a '
        'mover la cámara por cada cambio de la lista', (tester) async {
      final repo = RepoListaFalso(canvas());
      final gps = GpsFalso();
      final m = await montarMapaUbicaciones(tester, repo: repo, gps: gps);
      final movimientos = m.mapa.movimientos.length;

      repo.emitir([...canvas(), filaLista('x', metrosAlNorte: 300)]);
      await asentarLista(tester);
      repo.emitir(canvas());
      await asentarLista(tester);

      expect(m.mapa.movimientos.length, movimientos);
    });

    testWidgets('si el colportor mueve el mapa antes de que llegue el GPS, la cámara no se le '
        'quita de las manos', (tester) async {
      final gps = GpsFalso()..bloqueo = Completer<void>();
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gps);
      const aparte = Coordenadas(lat: -34.7, lon: -56.0);
      m.mapa.moverPorGesto(_gesto(aparte));
      await tester.pump();

      gps.bloqueo!.complete();
      await asentarLista(tester);

      expect(m.mapa.camara!.centro, aparte);
      expect(punto(m.mapa, 'gps').estilo, EstiloPunto.gps);
    });

    testWidgets('«Buscando GPS…» mientras llega la lectura, sin ordenar por cercanía todavía', (
      tester,
    ) async {
      final gps = GpsFalso()..bloqueo = Completer<void>();
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gps);

      await tocarAsa(tester);
      expect(find.text('Buscando GPS…'), findsOneWidget);
      expect(tester.widget<BotonMiUbicacion>(botonMiUbicacion).alPresionar, isNull);

      gps.bloqueo!.complete();
      await asentarLista(tester);

      expect(find.text('Buscando GPS…'), findsNothing);
      expect(hayPunto(m.mapa, 'gps'), isTrue);
    });

    testWidgets('el alto de la hoja nunca pasa del 70 % del mapa, aunque la pantalla sea baja', (
      tester,
    ) async {
      await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(canvas()),
        tamano: const Size(360, 480),
        escala: 2,
      );
      await tocarAsa(tester, 2);

      expect(altoHoja(tester), lessThanOrEqualTo(480 * 0.7 + 0.5));
      expect(
        altoHoja(tester),
        greaterThanOrEqualTo(AlturaHoja.altoMinimizada(const TextScaler.linear(2))),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
