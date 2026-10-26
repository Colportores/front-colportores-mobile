// HU-UBI-001 · vista 39 (#451): sumar una casa arrastrando el pin sobre el mapa de la vista 06. Cubre
// el botón del pin (M·01), N·01 «Soltar el pin: ¿está acá?» y el paso a N·03 «¿Qué pasó?» de la casa
// recién registrada. N·02 «¿Qué hay acá?» y su registro están en `hoja_que_hay_aca_451_test.dart`.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_notifier.dart'
    show altaUbicacionProvider;
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart'
    show ContextoDeVisita;
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart'
    show espacioRepositoryProvider;
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pin_nueva_casa.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas, gpsSinPermiso;

const _pantalla = Size(390, 844);
const _telefonoChico = Size(360, 640);

/// El espacio de una casa recién registrada.
Espacio _espacioDe(String ubicacionId) => Espacio(
  id: 'esp-$ubicacionId',
  ubicacionId: ubicacionId,
  numeroDepto: Espacio.deptoPorDefecto,
  auditoria: Auditoria(
    createdAt: DateTime.utc(2026, 10, 26, 12),
    updatedAt: DateTime.utc(2026, 10, 26, 12),
    createdBy: 'col-1',
  ),
);

/// Solo sabe listar los espacios de una ubicación.
final class _EspaciosFalsos implements EspacioRepository {
  _EspaciosFalsos({this.sinEspacio = false});

  final bool sinEspacio;

  @override
  Future<Either<Failure, List<Espacio>>> listar(
    String ubicacionId, {
    bool incluirBajas = false,
  }) async {
    return Right(sinEspacio ? const [] : [_espacioDe(ubicacionId)]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Monta el mapa con la dirección que contesta [geocodificador] (por defecto «Grecia 3307»).
Future<MontajeMapaUbicaciones> _montar(
  WidgetTester tester, {
  GpsFalso? gps,
  GeocodificadorFalso? geocodificador,
  Size tamano = _pantalla,
  double escala = 1,
  FutureOr<Object?> Function(ContextoDeVisita)? registrarVisitaDeCasaNueva,
  EspacioRepository? espacios,
  RepoListaFalso? repo,
}) => montarMapaUbicaciones(
  tester,
  repo: repo ?? RepoListaFalso(canvas()),
  gps: gps,
  tamano: tamano,
  escala: escala,
  registrarVisitaDeCasaNueva: registrarVisitaDeCasaNueva,
  otrosOverrides: [
    geocodificadorInversoProvider.overrideWithValue(
      geocodificador ??
          GeocodificadorFalso((_) => const DireccionDelPunto(calle: 'Grecia', numero: '3307')),
    ),
    esperaPuntoAltaProvider.overrideWithValue(const Duration(milliseconds: 20)),
    espacioRepositoryProvider.overrideWithValue(espacios ?? _EspaciosFalsos()),
  ],
);

/// El centro del círculo del botón del pin.
Offset _centroDelBoton(WidgetTester tester) =>
    tester.getCenter(find.byKey(ClavesPinNuevaCasa.boton));

/// Lleva el pin desde el botón hasta [destino] con el dedo y lo suelta.
Future<void> _arrastrarPinA(WidgetTester tester, Offset destino) async {
  final gesto = await tester.startGesture(_centroDelBoton(tester));
  await tester.pump();
  await gesto.moveTo(_centroDelBoton(tester) + const Offset(-30, -60));
  await tester.pump();
  await gesto.moveTo(destino);
  await tester.pump();
  await gesto.up();
  await asentarLista(tester);
}

final _pinPuesto = find.byKey(ClavesPinNuevaCasa.puesto);
final _pinEnArrastre = find.byKey(ClavesPinNuevaCasa.enArrastre);
final _direccion = find.byKey(ClavesPinNuevaCasa.direccion);

/// Donde el mapa dibuja [punto] ahora, en coordenadas de la vista.
Offset _dondeCae(MontajeMapaUbicaciones m, Coordenadas punto, {Size tamano = _pantalla}) {
  final p = ProyeccionMercator.aPantalla(
    punto,
    m.mapa.camara!,
    ancho: tamano.width,
    alto: tamano.height,
  );
  return Offset(p.x, p.y);
}

void main() {
  group('M·01 · el botón del pin', () {
    testWidgets('reemplaza al «Nueva»: la mira, su leyenda y 48 dp para el dedo', (tester) async {
      await _montar(tester);

      expect(botonNueva, findsOneWidget);
      expect(find.text('Arrastrá para sumar una casa'), findsOneWidget);
      expect(find.text('Nueva'), findsNothing);
      final circulo = tester.getSize(find.byKey(ClavesPinNuevaCasa.boton));
      expect(circulo.width, greaterThanOrEqualTo(48));
      expect(circulo.height, greaterThanOrEqualTo(48));
      // El lector de pantalla lo nombra como el canvas y dice la alternativa al arrastre.
      final semantica = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(
          'Pin: arrastralo al mapa para sumar una casa. Tocalo para ponerlo en el centro del mapa.',
        ),
        findsOneWidget,
      );
      semantica.dispose();
    });

    testWidgets(
      'con el texto muy grande la leyenda se va y queda el círculo, que sigue nombrado y se toca',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final m = await _montar(tester, tamano: _telefonoChico, escala: 2);

        expect(find.text('Arrastrá para sumar una casa'), findsNothing);
        expect(
          find.bySemanticsLabel(RegExp('^Pin: arrastralo al mapa para sumar una casa')),
          findsOneWidget,
        );
        expect(tester.getSize(find.byKey(ClavesPinNuevaCasa.boton)), const Size(52, 52));

        await tester.tap(botonNueva);
        await asentarLista(tester);
        expect(confirmarPosicion, findsOneWidget);
        expect(m.altas, isEmpty);
        semantica.dispose();
      },
    );

    testWidgets('mantener el dedo en el mapa ya no empieza un alta', (tester) async {
      final m = await _montar(tester);

      m.mapa.tocarLargo(const Coordenadas(lat: -34.9, lon: -56.2));
      await asentarLista(tester);

      expect(confirmarPosicion, findsNothing);
      expect(_pinPuesto, findsNothing);
    });
  });

  group('N·01 · soltar el pin: ¿está acá?', () {
    testWidgets('arrastrar el pin hasta el mapa y soltarlo lo deja ahí, con la dirección del mapa y '
        '«Confirmar posición»', (tester) async {
      final m = await _montar(tester);
      const destino = Offset(180, 300);

      await _arrastrarPinA(tester, destino);

      expect(_pinPuesto, findsOneWidget);
      expect(find.text('Confirmar posición'), findsOneWidget);
      expect(_direccion, findsOneWidget);
      expect(tester.widget<Text>(_direccion).data, 'Grecia 3307');
      // El punto es el del pin (24 dp más abajo de donde se lo llevó, que es lo que cae al soltar).
      final esperado = ProyeccionMercator.dePantalla(
        destino.dx,
        destino.dy - 48,
        m.mapa.camara!,
        ancho: 390,
        alto: 844,
      );
      await tester.tap(confirmarPosicion);
      await asentarLista(tester);
      expect(m.altas, hasLength(1));
      expect(m.altas.single!.lat, closeTo(esperado.lat, 1e-9));
      expect(m.altas.single!.lon, closeTo(esperado.lon, 1e-9));
    });

    testWidgets('mientras se lleva, el pin va sobre el dedo y la hoja no cambia', (tester) async {
      await _montar(tester);
      final altura = altoHoja(tester);

      final gesto = await tester.startGesture(_centroDelBoton(tester));
      await tester.pump();
      await gesto.moveTo(const Offset(200, 400));
      await tester.pump();

      expect(_pinEnArrastre, findsOneWidget);
      expect(tester.getCenter(_pinEnArrastre).dx, closeTo(200, 1));
      expect(tester.getCenter(_pinEnArrastre).dy, closeTo(400 - 72, 1));
      expect(altoHoja(tester), altura);
      expect(confirmarPosicion, findsNothing);

      await gesto.up();
      await asentarLista(tester);
      expect(_pinEnArrastre, findsNothing);
      expect(confirmarPosicion, findsOneWidget);
    });

    testWidgets('cargando: «Buscando la dirección…» hasta que el mapa contesta', (tester) async {
      final geo = GeocodificadorFalso(
        (_) => const DireccionDelPunto(calle: 'Grecia', numero: '3307'),
      )..bloqueo = Completer<void>();
      await _montar(tester, geocodificador: geo);

      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(tester.widget<Text>(_direccion).data, 'Buscando la dirección…');
      expect(confirmarPosicion, findsOneWidget, reason: 'se puede confirmar sin esperar');

      geo.bloqueo!.complete();
      await asentarLista(tester);

      expect(tester.widget<Text>(_direccion).data, 'Grecia 3307');
    });

    testWidgets('sin dirección en el mapa: lo dice, y se puede confirmar igual', (tester) async {
      await _montar(tester, geocodificador: GeocodificadorFalso());

      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(tester.widget<Text>(_direccion).data, 'Sin dirección en el mapa');
      expect(confirmarPosicion, findsOneWidget);
    });

    testWidgets('soltarlo sobre la lista no suma nada y dice cómo hacerlo', (tester) async {
      final m = await _montar(tester);

      await _arrastrarPinA(tester, const Offset(200, 836));

      expect(_pinPuesto, findsNothing);
      expect(confirmarPosicion, findsNothing);
      expect(find.text('Soltá el pin sobre el mapa, arriba de la lista.'), findsOneWidget);
      expect(m.altas, isEmpty);
      // El botón sigue ahí para intentarlo de nuevo.
      expect(botonNueva, findsOneWidget);
      await _arrastrarPinA(tester, const Offset(200, 300));
      expect(confirmarPosicion, findsOneWidget);
    });

    testWidgets('tocar el pin (sin arrastrarlo) lo deja en el GPS, con el mapa a nivel de calle', (
      tester,
    ) async {
      final m = await _montar(tester);

      await tester.tap(botonNueva);
      await asentarLista(tester);

      await tester.tap(confirmarPosicion);
      await asentarLista(tester);
      expect(m.altas.single, puntoItalia);
      // El mapa va al punto del GPS, a nivel de calle, y el pin queda a la vista.
      expect(m.mapa.camara!.zoom, greaterThanOrEqualTo(MapaAlta.zoomCalle));
    });

    testWidgets('tocar el pin sin GPS lo deja en el centro de lo que se ve del mapa', (
      tester,
    ) async {
      final m = await _montar(tester, gps: gpsSinPermiso());
      final alturaDeLaHoja = altoHoja(tester);

      await tester.tap(botonNueva);
      await asentarLista(tester);

      final centro = tester.getCenter(_pinPuesto);
      expect(centro.dx, closeTo(195, 1));
      // Centrado en lo que la hoja deja libre: la mitad de (alto − hoja).
      expect(centro.dy, closeTo((844 - alturaDeLaHoja) / 2, 1.5));
      await tester.tap(confirmarPosicion);
      await asentarLista(tester);
      // El punto que se confirma cae donde está el pin (a esta escala un píxel son muchos metros).
      final donde = _dondeCae(m, m.altas.single!);
      expect(donde.dx, closeTo(centro.dx, 1.5));
      expect(donde.dy, closeTo(centro.dy, 1.5));
    });

    testWidgets('con una vista previa abierta, soltar el pin la cierra', (tester) async {
      final m = await _montar(tester);
      m.mapa.tocarPunto('a');
      await asentarLista(tester);
      expect(vistaPrevia, findsOneWidget);

      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(vistaPrevia, findsNothing);
      expect(seleccionadaId(tester), isNull);
      expect(confirmarPosicion, findsOneWidget);
    });
  });

  group('N·01 · reubicar el pin', () {
    testWidgets('tocar el mapa lo lleva ahí y la dirección se vuelve a pedir', (tester) async {
      final geo = GeocodificadorFalso(
        (p) => p.lat > -34.9
            ? const DireccionDelPunto(calle: 'Grecia', numero: '3307')
            : const DireccionDelPunto(calle: 'Mataojo', numero: '2044'),
      );
      final m = await _montar(tester, geocodificador: geo);
      await tester.tap(botonNueva);
      await asentarLista(tester);
      expect(tester.widget<Text>(_direccion).data, 'Grecia 3307');

      const otro = Coordenadas(lat: -34.91, lon: -56.13);
      m.mapa.tocar(otro);
      await asentarLista(tester);

      expect(tester.widget<Text>(_direccion).data, 'Mataojo 2044');
      final centro = tester.getCenter(_pinPuesto);
      final donde = _dondeCae(m, otro);
      expect(centro.dx, closeTo(donde.dx, 1));
      expect(centro.dy, closeTo(donde.dy, 1));
    });

    testWidgets('arrastrar el pin puesto lo lleva a otro lado', (tester) async {
      final m = await _montar(tester, gps: gpsSinPermiso());
      await tester.tap(botonNueva);
      await asentarLista(tester);
      final antes = tester.getCenter(_pinPuesto);

      await tester.dragFrom(antes, const Offset(60, -80));
      await asentarLista(tester);

      final despues = tester.getCenter(_pinPuesto);
      expect(despues.dx, closeTo(antes.dx + 60, 2));
      expect(despues.dy, closeTo(antes.dy - 80, 2));
      await tester.tap(confirmarPosicion);
      await asentarLista(tester);
      // El alta quedó con el punto donde se llevó el pin (no con el inicial).
      final punto = contenedorDeLaPestana(
        tester,
      ).read(altaUbicacionProvider(m.parametrosDeAltas.single)).punto!;
      final donde = _dondeCae(m, punto);
      expect(donde.dx, closeTo(despues.dx, 1.5));
      expect(donde.dy, closeTo(despues.dy, 1.5));
      expect(punto, isNot(m.altas.single));
    });

    testWidgets('mover el mapa con el pin puesto: el pin se queda en su lugar del mapa', (
      tester,
    ) async {
      final m = await _montar(tester);
      await tester.tap(botonNueva);
      await asentarLista(tester);
      const elPunto = puntoItalia;
      final antes = tester.getCenter(_pinPuesto);

      // Un dedo corre el mapa 100 dp hacia el este.
      final camara = m.mapa.camara!;
      final centro = ProyeccionMercator.aPixeles(camara.centro, camara.zoom);
      m.mapa.moverPorGesto(
        CamaraMapa(
          centro: ProyeccionMercator.aCoordenadas(centro.x + 100, centro.y, camara.zoom),
          zoom: camara.zoom,
        ),
      );
      await tester.pump();

      final despues = tester.getCenter(_pinPuesto);
      expect(despues.dx, closeTo(antes.dx - 100, 1.5));
      expect(despues.dy, closeTo(antes.dy, 1.5));
      expect(_dondeCae(m, elPunto).dx, closeTo(despues.dx, 1.5));
    });

    testWidgets('tocar una casa que ya existe con el pin puesto mueve el pin, no abre su hoja', (
      tester,
    ) async {
      final m = await _montar(tester);
      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(m.mapa.config!.puntosTocables, isFalse, reason: 'con el pin puesto no se tocan casas');
      expect(vistaPrevia, findsNothing);
      expect(seleccionadaId(tester), isNull);
    });
  });

  group('N·01 · cancelar', () {
    testWidgets('la ✕ saca el pin y devuelve el botón y la hoja de siempre', (tester) async {
      await _montar(tester);
      await tester.tap(botonNueva);
      await asentarLista(tester);
      expect(botonNueva, findsNothing);

      await tester.tap(cancelarPosicion);
      await asentarLista(tester);

      expect(_pinPuesto, findsNothing);
      expect(confirmarPosicion, findsNothing);
      expect(botonNueva, findsOneWidget);
      expect(hoja, findsOneWidget);
    });

    testWidgets('el atrás del sistema saca el pin, y el siguiente atrás ya no hace nada', (
      tester,
    ) async {
      await _montar(tester);
      await tester.tap(botonNueva);
      await asentarLista(tester);

      await tester.binding.handlePopRoute();
      await asentarLista(tester);

      expect(_pinPuesto, findsNothing);
      expect(botonNueva, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'cambiar de pestaña con el pin puesto lo saca: al volver, el mapa está como estaba',
      (tester) async {
        final m = await _montar(tester);
        await tester.tap(botonNueva);
        await asentarLista(tester);

        m.activa.value = false;
        await asentarLista(tester);
        m.activa.value = true;
        await asentarLista(tester);

        expect(_pinPuesto, findsNothing);
        expect(confirmarPosicion, findsNothing);
        expect(botonNueva, findsOneWidget);
      },
    );

    testWidgets('cancelar y volver a poner el pin: es un alta nueva, sin lo de la anterior', (
      tester,
    ) async {
      final m = await _montar(tester, gps: gpsSinPermiso());
      await tester.tap(botonNueva);
      await asentarLista(tester);
      await tester.tap(cancelarPosicion);
      await asentarLista(tester);

      await _arrastrarPinA(tester, const Offset(100, 200));
      await tester.tap(confirmarPosicion);
      await asentarLista(tester);

      expect(m.altas, hasLength(1));
    });
  });

  group('N·03 · la casa recién registrada sigue a «¿Qué pasó?»', () {
    Ubicacion nueva({TipoUbicacion tipo = TipoUbicacion.casa}) =>
        filaLista('nueva', tipo: tipo, calle: 'Grecia', numero: '3307', metrosAlNorte: 5).ubicacion;

    /// Registra desde el pin: el alta devuelve [ubicacion] y la lista ya la trae.
    Future<MontajeMapaUbicaciones> registrar(
      WidgetTester tester, {
      required Ubicacion ubicacion,
      FutureOr<Object?> Function(ContextoDeVisita)? quePaso,
      EspacioRepository? espacios,
      Size tamano = _pantalla,
      double escala = 1,
    }) async {
      final repo = RepoListaFalso(canvas());
      final m = await _montar(
        tester,
        repo: repo,
        registrarVisitaDeCasaNueva: quePaso,
        espacios: espacios,
        tamano: tamano,
        escala: escala,
      );
      repo.emitir([
        ...canvas(),
        filaLista('nueva', tipo: ubicacion.tipo, calle: 'Grecia', numero: '3307', metrosAlNorte: 5),
      ]);
      m.salidaAlta = UbicacionCreada(ubicacion);
      await tocarPinYConfirmar(tester);
      return m;
    }

    testWidgets('una casa abre «¿Qué pasó?» con la ubicación y su espacio ya resueltos', (
      tester,
    ) async {
      final recibidos = <ContextoDeVisita>[];
      final m = await registrar(
        tester,
        ubicacion: nueva(),
        quePaso: (datos) {
          recibidos.add(datos);
          return false;
        },
      );

      expect(recibidos, [(ubicacionId: 'nueva', espacioId: 'esp-nueva')]);
      // Volver (false) deja la casa registrada y seleccionada, con su hoja.
      expect(seleccionadaId(tester), 'nueva');
      expect(vistaPrevia, findsOneWidget);
      expect(punto(m.mapa, 'nueva').estilo, EstiloPunto.seleccionado);
      expect(confirmarPosicion, findsNothing);
      expect(botonNueva, findsOneWidget);
    });

    testWidgets(
      'si se guardó una visita (true), la hoja de la casa se cierra y el mapa queda libre',
      (tester) async {
        await registrar(tester, ubicacion: nueva(), quePaso: (_) => true);

        expect(seleccionadaId(tester), isNull);
        expect(vistaPrevia, findsNothing);
      },
    );

    for (final tipo in [TipoUbicacion.edificio, TipoUbicacion.negocio]) {
      testWidgets('un ${tipo.name} queda registrado y seleccionado, sin pasar por «¿Qué pasó?»', (
        tester,
      ) async {
        var llamadas = 0;
        await registrar(
          tester,
          ubicacion: nueva(tipo: tipo),
          quePaso: (_) {
            llamadas++;
            return true;
          },
        );

        expect(llamadas, 0);
        expect(seleccionadaId(tester), 'nueva');
        expect(vistaPrevia, findsOneWidget);
      });
    }

    testWidgets('sin destino enganchado la casa queda registrada y seleccionada', (tester) async {
      await registrar(tester, ubicacion: nueva());

      expect(seleccionadaId(tester), 'nueva');
      expect(vistaPrevia, findsOneWidget);
    });

    testWidgets('si no se puede leer el espacio de la casa, queda con su hoja y no se abre nada', (
      tester,
    ) async {
      var llamadas = 0;
      await registrar(
        tester,
        ubicacion: nueva(),
        espacios: _EspaciosFalsos(sinEspacio: true),
        quePaso: (_) {
          llamadas++;
          return true;
        },
      );

      expect(llamadas, 0);
      expect(seleccionadaId(tester), 'nueva');
    });

    testWidgets('si «¿Qué pasó?» no se puede abrir, lo dice y la casa queda con su hoja', (
      tester,
    ) async {
      await registrar(
        tester,
        ubicacion: nueva(),
        quePaso: (_) => throw StateError('sin navegador'),
      );

      expect(find.text('No pudimos abrir «Registrar visita». Probá de nuevo.'), findsOneWidget);
      expect(seleccionadaId(tester), 'nueva');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'una ubicación que ya existía (aviso de duplicado) se abre como siempre, sin «¿Qué pasó?»',
      (tester) async {
        var llamadas = 0;
        final m = await _montar(
          tester,
          registrarVisitaDeCasaNueva: (_) {
            llamadas++;
            return true;
          },
        );
        m.salidaAlta = const UbicacionReutilizada('c');

        await tocarPinYConfirmar(tester);

        expect(llamadas, 0);
        expect(seleccionadaId(tester), 'c');
        expect(botonNueva, findsOneWidget);
      },
    );

    testWidgets('dos altas seguidas: la segunda empieza de cero, con su propio pin', (
      tester,
    ) async {
      final repo = RepoListaFalso(canvas());
      final m = await _montar(
        tester,
        repo: repo,
        gps: gpsSinPermiso(),
        registrarVisitaDeCasaNueva: (_) => false,
      );
      repo.emitir([
        ...canvas(),
        filaLista('nueva', calle: 'Grecia', numero: '3307', metrosAlNorte: 5),
      ]);
      m.salidaAlta = UbicacionCreada(nueva());
      await tocarPinYConfirmar(tester);

      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(confirmarPosicion, findsOneWidget);
      expect(vistaPrevia, findsNothing, reason: 'la casa de antes se cierra al soltar otro pin');
      expect(m.altas, hasLength(1));
    });

    testWidgets('el pin se pone y se confirma una sola vez aunque la hoja tarde en cerrarse', (
      tester,
    ) async {
      final m = await _montar(tester);
      m.esperaAlta = Completer<SalidaAltaUbicacion?>();

      await tester.tap(botonNueva);
      await asentarLista(tester);
      await tester.tap(confirmarPosicion);
      await tester.tap(confirmarPosicion);
      await asentarLista(tester);

      expect(m.altas, hasLength(1));
    });
  });

  group('datos límite y texto grande', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('360×640 · texto $escala: el botón, el pin y N·01 entran sin desbordar', (
        tester,
      ) async {
        await _montar(tester, tamano: _telefonoChico, escala: escala);

        // Los botones no se pisan con «Referencias» ni salen de la pantalla.
        final boton = tester.getRect(find.byKey(ClavesPinNuevaCasa.boton));
        expect(boton.left, greaterThanOrEqualTo(0));
        expect(boton.right, lessThanOrEqualTo(360));
        expect(boton.bottom, lessThanOrEqualTo(640));
        expect(tester.takeException(), isNull);

        await tester.tap(botonNueva);
        await asentarLista(tester);

        final panel = tester.getRect(find.byKey(ClavesPinNuevaCasa.posicion));
        expect(panel.bottom, closeTo(640, 1));
        expect(panel.height, lessThanOrEqualTo(640 * .6 + 1));
        final confirmar = tester.getRect(confirmarPosicion);
        expect(confirmar.height, greaterThanOrEqualTo(56));
        expect(
          confirmar.bottom,
          lessThanOrEqualTo(640),
          reason: 'la acción queda siempre a la vista',
        );
        expect(tester.takeException(), isNull);
        // El pin sigue a la vista, por encima del panel.
        final pin = tester.getCenter(_pinPuesto);
        expect(pin.dy, lessThan(panel.top));
      });
    }

    testWidgets('una dirección larguísima se lee entera en el título', (tester) async {
      final calle =
          'Avenida de los Treinta y Tres Orientales y Doctor Luis Alberto de Herrera ' * 2;
      await _montar(
        tester,
        tamano: _telefonoChico,
        escala: 2,
        geocodificador: GeocodificadorFalso(
          (_) => DireccionDelPunto(calle: calle.trim(), numero: '1234567890'),
        ),
      );

      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(tester.widget<Text>(_direccion).data, contains('1234567890'));
      expect(tester.takeException(), isNull);
      expect(confirmarPosicion, findsOneWidget);
    });
  });
}
