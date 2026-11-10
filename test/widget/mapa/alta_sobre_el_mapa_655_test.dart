// #655, entrega 1 (vista 41): el alta con pin sobre el mapa principal (41A·01 a 41A·06, con 41A·04B)
// y el aviso de duplicado (41B·01 a 41B·04), con sus casos límite. El mapa es la vista falsa; el
// alta es la de verdad (sus puertos son los fakes de `alta_ubicacion_falsos.dart`).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_principal_provider.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/alta_sobre_el_mapa.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/zonas_falsas.dart';
import 'mapa_ubicaciones_arnes.dart';

/// Unos 40 m al este de Av. Italia: ahí el mapa dice «Mataojo 2047».
const _mataojo = Coordenadas(lat: -34.88761, lon: -56.12980);

final _principal = find.byKey(ClavesAltaMapa.principal);
final _secundario = find.byKey(ClavesAltaMapa.secundario);
final _hojaAlta = find.byKey(ClavesAltaMapa.hoja);
final _pin = find.byKey(const Key('alta_mapa_pin'));

DireccionDelPunto? _direccion(Coordenadas p) =>
    (p.lat - puntoItalia.lat).abs() < 1e-6 && (p.lon - puntoItalia.lon).abs() < 1e-6
    ? const DireccionDelPunto(calle: 'Grecia', numero: '3307')
    : const DireccionDelPunto(calle: 'Mataojo', numero: '2047');

final class _Alta {
  _Alta(this.m, this.repo);

  final MontajeMapaUbicaciones m;
  final RepoAltaFalso repo;
}

Future<_Alta> _montar(
  WidgetTester tester, {
  GpsFalso? gps,
  RepoAltaFalso? repo,
  GeocodificadorFalso? geocodificador,
  double escala = 1,
}) async {
  final alta = repo ?? RepoAltaFalso();
  final lista = RepoListaFalso([
    filaLista('vieja', calle: 'Grecia', numero: '3301'),
    filaLista('a', calle: 'Grecia', numero: '3305', metrosAlNorte: 12),
    filaLista('b', calle: 'Grecia', numero: '3309', metrosAlNorte: 4),
  ])..alta = alta;
  var secuencia = 0;
  final m = await montarMapaUbicaciones(
    tester,
    repo: lista,
    gps: gps,
    escala: escala,
    altaReal: true,
    otrosOverrides: [
      geocodificadorInversoProvider.overrideWithValue(
        geocodificador ?? GeocodificadorFalso(_direccion),
      ),
      ubicadorZonaProvider.overrideWithValue(ubicadorSinZonas()),
      esperaPuntoAltaProvider.overrideWithValue(const Duration(milliseconds: 20)),
      generadorIdUbicacionProvider.overrideWithValue(() => 'nueva-${++secuencia}'),
    ],
  );
  return _Alta(m, alta);
}

Future<void> _asentar(WidgetTester tester, [int veces = 12]) => asentarLista(tester, veces);

/// Toca el pin para sumar una casa (lo deja en la ubicación de la colportora).
Future<void> _abrir(WidgetTester tester) async {
  await tester.tap(botonNueva);
  await _asentar(tester);
}

Future<void> _tocar(WidgetTester tester, Finder boton) async {
  await tester.ensureVisible(boton);
  await tester.pump();
  await tester.tap(boton);
  await _asentar(tester);
}

AltaUbicacionState? _estado(WidgetTester tester) {
  final contenedor = contenedorDeLaPestana(tester);
  final modo = contenedor.read(mapaPrincipalProvider);
  return modo is ColocandoPin ? contenedor.read(altaUbicacionProvider(modo.alta)) : null;
}

String _texto(Finder boton) =>
    (find.descendant(of: boton, matching: find.byType(Text)).evaluate().first.widget as Text).data!;

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<ButtonStyleButton>(boton).onPressed != null;

RepoAltaFalso _conDuplicados(List<CandidataDuplicado> candidatas) {
  var intento = 0;
  return RepoAltaFalso()
    ..comportamiento = (u) async => ++intento == 1
        ? Right(AltaConDuplicados(candidatas: candidatas))
        : Right(AltaRegistrada(ubicacion: u));
}

/// Abre el alta y confirma la posición: queda en N·02.
Future<void> _hastaQueHayAca(WidgetTester tester) async {
  await _abrir(tester);
  await _tocar(tester, _principal);
}

void main() {
  group('41A·01 · N·01: el pin en tu ubicación', () {
    testWidgets('tocar el pin lo deja en tu GPS con la dirección y la ciudad del mapa', (
      tester,
    ) async {
      final a = await _montar(tester);
      final antes = a.m.mapa.movimientos.length;

      await _abrir(tester);

      expect(_hojaAlta, findsOneWidget);
      expect(find.text('Grecia 3307'), findsOneWidget);
      expect(find.text('◎ Del mapa · Montevideo'), findsOneWidget);
      expect(find.text('Arrastrá el pin o tocá el mapa para moverlo.'), findsOneWidget);
      expect(_texto(_principal), 'Confirmar posición');
      expect(find.text('◎ GPS ±6 m'), findsOneWidget);
      expect(_pin, findsOneWidget);
      expect(_estado(tester)!.punto, puntoItalia);
      // La hoja de «Cercanía» y los botones se apartan mientras dura el alta.
      expect(botonNueva, findsNothing);
      expect(a.m.mapa.movimientos.length, antes, reason: 'el GPS ya estaba a la vista');
    });

    testWidgets('tocar el mapa mueve el pin ahí, sin mover el mapa', (tester) async {
      final a = await _montar(tester);
      await _abrir(tester);
      final antes = a.m.mapa.movimientos.length;

      a.m.mapa.tocar(_mataojo);
      await _asentar(tester);

      expect(_estado(tester)!.punto, _mataojo);
      expect(find.text('Mataojo 2047'), findsOneWidget);
      expect(a.m.mapa.movimientos.length, antes);
    });

    testWidgets('arrastrar el pin lo mueve adonde se suelta (manual)', (tester) async {
      await _montar(tester);
      await _abrir(tester);
      final camara = contenedorDeLaPestana(tester).read(mapaPrincipalProvider.notifier).camara()!;

      await tester.drag(_pin, const Offset(60, -40));
      await _asentar(tester);

      final estado = _estado(tester)!;
      expect(estado.punto, isNot(puntoItalia));
      expect(estado.origen, OrigenCoordenadas.manual);
      expect(camara, contenedorDeLaPestana(tester).read(mapaPrincipalProvider.notifier).camara());
    });

    testWidgets('la ✕ cierra sin guardar nada y el mapa vuelve como estaba', (tester) async {
      final a = await _montar(tester);
      await _abrir(tester);

      await _tocar(tester, find.byKey(ClavesAltaMapa.cerrar));

      expect(_hojaAlta, findsNothing);
      expect(a.repo.llamadas, isEmpty);
      expect(contenedorDeLaPestana(tester).read(mapaPrincipalProvider), const Explorando());
      expect(botonNueva, findsOneWidget);
    });

    testWidgets('el atrás del teléfono en N·01 cierra; volver a abrir arranca de cero', (
      tester,
    ) async {
      await _montar(tester);
      await _abrir(tester);
      await _tocar(tester, _principal);
      await tester.enterText(find.byKey(ClavesAltaMapa.numero), '3307 B');
      await _asentar(tester);

      // N·02 → N·01 (lo escrito sigue) → cierra.
      await tester.binding.handlePopRoute();
      await _asentar(tester);
      expect(find.text('Grecia 3307 B'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _asentar(tester);
      expect(_hojaAlta, findsNothing);

      await _abrir(tester);
      expect(find.text('Grecia 3307'), findsOneWidget);
      expect(_estado(tester)!.numero.fuente, FuenteCampo.delMapa);
    });

    testWidgets('dos toques seguidos al pin abren un solo alta', (tester) async {
      await _montar(tester);

      final donde = tester.getCenter(botonNueva);

      await tester.tapAt(donde);
      await tester.pump();
      // El botón ya se apartó: el segundo toque cae en el mapa (y a lo sumo mueve el pin).
      await tester.tapAt(donde);
      await _asentar(tester);

      expect(_hojaAlta, findsOneWidget);
      expect(find.byKey(ClavesAltaMapa.principal), findsOneWidget);
    });
  });

  group('41A·01 · arrastrar el pin desde su botón', () {
    testWidgets('soltarlo sobre el mapa abre el alta con el pin ahí (manual)', (tester) async {
      await _montar(tester);
      final desde = tester.getCenter(botonNueva);

      final gesto = await tester.startGesture(desde);
      for (var i = 0; i < 10; i++) {
        await gesto.moveBy(const Offset(-15, -30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesto.up();
      await _asentar(tester);

      final estado = _estado(tester)!;
      expect(_hojaAlta, findsOneWidget);
      expect(estado.punto, isNot(puntoItalia));
      expect(estado.origen, OrigenCoordenadas.manual);
      expect(find.text('Mataojo 2047'), findsOneWidget);
    });
  });

  group('41A·02 · sin GPS o sin permiso', () {
    testWidgets('chip «✕ Sin GPS», «Tocá donde está el lugar», «Activar GPS» y «Registrar» '
        'deshabilitado; tocar el mapa pone el pin', (tester) async {
      final gps = GpsFalso(
        const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado)),
      );
      final a = await _montar(tester, gps: gps);
      await _abrir(tester);

      expect(find.text('Casa nueva'), findsOneWidget);
      expect(find.text('✕ Sin GPS'), findsOneWidget);
      expect(find.byKey(ClavesAltaMapa.tocaElMapa), findsOneWidget);
      expect(find.text('Activar GPS'), findsOneWidget);
      expect(_texto(_principal), 'Registrar');
      expect(_habilitado(tester, _principal), isFalse);

      a.m.mapa.tocar(_mataojo);
      await _asentar(tester);

      expect(find.byKey(ClavesAltaMapa.tocaElMapa), findsNothing);
      expect(find.text('Mataojo 2047'), findsOneWidget);
      expect(_texto(_principal), 'Confirmar posición');
    });

    testWidgets('«Activar GPS» pide activar el GPS', (tester) async {
      final gps = GpsFalso(
        const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado)),
      );
      await _montar(tester, gps: gps);
      await _abrir(tester);

      await _tocar(tester, find.text('Activar GPS'));

      expect(gps.activaciones, isNotEmpty);
    });
  });

  group('41A·03 · GPS impreciso (±85 m)', () {
    testWidgets('chip ámbar, el aviso y sus dos salidas', (tester) async {
      await _montar(tester, gps: GpsFalso(Right(lecturaGps(85))));
      await _abrir(tester);

      expect(find.text('! GPS ±85 m'), findsOneWidget);
      expect(find.text(AltaConBajaPrecision.aviso), findsOneWidget);
      expect(_texto(_principal), 'Ajustar manualmente');
      expect(_texto(_secundario), 'Continuar');
    });

    testWidgets('«Continuar» sigue a N·02 con ese punto y acomoda el mapa una vez', (tester) async {
      final a = await _montar(tester, gps: GpsFalso(Right(lecturaGps(85))));
      await _abrir(tester);
      final antes = a.m.mapa.movimientos.length;

      await _tocar(tester, _secundario);

      expect(find.text('¿Qué hay acá?'), findsOneWidget);
      expect(_estado(tester)!.precisionDecidida, isTrue);
      expect(a.m.mapa.movimientos.length, antes + 1);
    });

    testWidgets('«Ajustar manualmente» deja el pin listo para moverlo, en N·01', (tester) async {
      await _montar(tester, gps: GpsFalso(Right(lecturaGps(85))));
      await _abrir(tester);

      await _tocar(tester, _principal);

      expect(find.text(AltaConBajaPrecision.aviso), findsNothing);
      expect(_texto(_principal), 'Confirmar posición');
      expect(_estado(tester)!.paso, PasoAlta.posicion);
    });
  });

  group('41A·04 · N·02 «¿Qué hay acá?»', () {
    testWidgets('«Confirmar posición» acomoda el pin arriba de la hoja (una vez) y muestra N·02', (
      tester,
    ) async {
      final a = await _montar(tester);
      await _abrir(tester);
      final antes = a.m.mapa.movimientos.length;

      await _tocar(tester, _principal);

      expect(find.text('¿Qué hay acá?'), findsOneWidget);
      expect(find.text('Grecia 3307 · Montevideo'), findsOneWidget);
      expect(find.text('Una o varias personas'), findsOneWidget);
      expect(find.text('Varios deptos'), findsOneWidget);
      expect(find.text('Un comercio'), findsOneWidget);
      expect(find.text('CIUDAD'), findsOneWidget);
      expect(find.text('◎ Del mapa  ›'), findsOneWidget);
      expect(find.byKey(ClavesAltaMapa.velo), findsOneWidget);
      expect(a.m.mapa.movimientos.length, antes + 1);
      // El pin quedó arriba de la hoja.
      final pin = tester.getRect(_pin);
      expect(pin.bottom, lessThan(tester.getTopLeft(_hojaAlta).dy));
    });

    testWidgets('«Registrar» crea la casa, cierra el alta y la deja elegida', (tester) async {
      final a = await _montar(tester);
      await _hastaQueHayAca(tester);

      await _tocar(tester, _principal);

      expect(a.repo.llamadas, hasLength(1));
      expect(a.repo.llamadas.single.ubicacion.calle, 'Grecia');
      expect(_hojaAlta, findsNothing);
      expect(seleccionadaId(tester), 'nueva-1');
    });

    testWidgets('dos toques a «Registrar» registran una sola vez', (tester) async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      final a = await _montar(tester, repo: repo);
      await _hastaQueHayAca(tester);

      await tester.ensureVisible(_principal);
      await tester.tap(_principal);
      await tester.pump();
      expect(_texto(_principal), 'Registrando…');
      await tester.tap(_principal, warnIfMissed: false);
      await tester.pump();
      repo.bloqueo!.complete();
      await _asentar(tester);

      expect(a.repo.llamadas, hasLength(1));
      expect(_hojaAlta, findsNothing);
    });

    testWidgets('si falla, avisa y «Registrar» vuelve a andar (no queda trabado)', (tester) async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async => ++intento == 1
            ? const Left(FailureInesperado(causa: 'disco'))
            : Right(AltaRegistrada(ubicacion: u));
      final a = await _montar(tester, repo: repo);
      await _hastaQueHayAca(tester);

      await _tocar(tester, _principal);
      expect(_hojaAlta, findsOneWidget);
      expect(_habilitado(tester, _principal), isTrue);
      expect(_texto(_principal), 'Registrar');

      await _tocar(tester, _principal);
      expect(a.repo.llamadas, hasLength(2));
      expect(_hojaAlta, findsNothing);
    });

    testWidgets('«Volver» vuelve a N·01 sin mover el mapa', (tester) async {
      final a = await _montar(tester);
      await _hastaQueHayAca(tester);
      final antes = a.m.mapa.movimientos.length;

      await _tocar(tester, _secundario);

      expect(_texto(_principal), 'Confirmar posición');
      expect(a.m.mapa.movimientos.length, antes);
    });
  });

  group('41A·04B · «Elegí la ciudad»', () {
    testWidgets('lista las ciudades con su origen, busca, y elegir otra vuelve a N·02 «Editado» '
        'sin mover el mapa', (tester) async {
      final a = await _montar(tester);
      await _hastaQueHayAca(tester);
      final antes = a.m.mapa.movimientos.length;

      await _tocar(tester, find.byKey(ClavesAltaMapa.ciudad));

      expect(find.text('Elegí la ciudad'), findsWidgets);
      expect(find.text('Del mapa'), findsOneWidget);
      expect(find.text('De tu campaña'), findsOneWidget);
      expect(_texto(_principal), 'Usar Montevideo');

      await tester.enterText(find.byKey(ClavesAltaMapa.buscarCiudad), 'cane');
      await _asentar(tester);
      expect(find.byKey(ClavesAltaMapa.opcionCiudad(montevideo.id)), findsNothing);

      await _tocar(tester, find.byKey(ClavesAltaMapa.opcionCiudad(canelones.id)));
      expect(_texto(_principal), 'Usar Canelones');
      await _tocar(tester, _principal);

      expect(find.text('¿Qué hay acá?'), findsOneWidget);
      expect(find.text('✎ Editado  ›'), findsOneWidget);
      expect(_estado(tester)!.ciudad, canelones);
      expect(a.m.mapa.movimientos.length, antes);
    });

    testWidgets('una búsqueda sin resultados lo dice', (tester) async {
      await _montar(tester);
      await _hastaQueHayAca(tester);
      await _tocar(tester, find.byKey(ClavesAltaMapa.ciudad));

      await tester.enterText(find.byKey(ClavesAltaMapa.buscarCiudad), 'zzz');
      await _asentar(tester);

      expect(find.text(TextosAltaMapa.sinResultados), findsOneWidget);
    });

    testWidgets('«Volver» no cambia la ciudad', (tester) async {
      await _montar(tester);
      await _hastaQueHayAca(tester);
      await _tocar(tester, find.byKey(ClavesAltaMapa.ciudad));
      await _tocar(tester, find.byKey(ClavesAltaMapa.opcionCiudad(canelones.id)));

      await _tocar(tester, _secundario);

      expect(_estado(tester)!.ciudad, montevideo);
      expect(find.text('◎ Del mapa  ›'), findsOneWidget);
    });
  });

  group('41A·05 · editado y calle actualizada', () {
    testWidgets('mover el pin actualiza la calle; el número escrito no se toca y avisa qué dice '
        'el mapa', (tester) async {
      final a = await _montar(tester);
      await _hastaQueHayAca(tester);
      await tester.enterText(find.byKey(ClavesAltaMapa.numero), '3307 B');
      await _asentar(tester);
      await _tocar(tester, _secundario);

      a.m.mapa.tocar(_mataojo);
      await _asentar(tester);
      await _tocar(tester, _principal);

      expect(find.text('Calle actualizada'), findsOneWidget);
      expect(find.text('Mataojo 3307 B · Montevideo'), findsOneWidget);
      expect(find.text('Lo escribiste vos: no lo cambiamos. El mapa dice 2047.'), findsOneWidget);
    });
  });

  group('41A·06 · teclado y textos largos', () {
    testWidgets('con el teclado abierto la hoja sube y se desplaza por dentro; el mapa no se '
        'recentra', (tester) async {
      final a = await _montar(tester);
      await _hastaQueHayAca(tester);
      final antes = a.m.mapa.movimientos.length;

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.showKeyboard(find.byKey(ClavesAltaMapa.numero));
      await _asentar(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getBottomLeft(_hojaAlta).dy, lessThanOrEqualTo(844 - 300 + 0.5));
      await tester.ensureVisible(_principal);
      expect(a.m.mapa.movimientos.length, antes);
    });

    testWidgets('textScaler 2.0 y una calle larguísima: sin desbordes y todo alcanzable', (
      tester,
    ) async {
      final larga = 'Avenida ${'Doctor Luis Alberto de Herrera ' * 4}';
      await _montar(
        tester,
        escala: 2,
        geocodificador: GeocodificadorFalso((_) => DireccionDelPunto(calle: larga, numero: '3307')),
      );
      await _abrir(tester);
      expect(tester.takeException(), isNull);

      await _tocar(tester, _principal);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_principal);
      await tester.pump();
      expect(_habilitado(tester, _principal), isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('41B · el aviso de duplicado', () {
    testWidgets('41B·01: una a 12 m — la tarjeta, «Reutilizar esta» elige la existente', (
      tester,
    ) async {
      final repo = _conDuplicados([
        candidata('vieja', calle: 'Grecia', numero: '3307', estado: null),
      ]);
      final a = await _montar(tester, repo: repo);
      await _hastaQueHayAca(tester);

      await _tocar(tester, _principal);

      final metros = FormatoUbicaciones.distancia(12);
      expect(find.text('Ya existe una ubicación a $metros'), findsOneWidget);
      expect(find.text('Misma dirección y misma ciudad.'), findsOneWidget);
      expect(find.text('La nueva'), findsOneWidget);
      expect(find.text('Ya registrada · a $metros'), findsOneWidget);
      expect(find.byKey(ClavesAltaMapa.velo), findsNothing);
      expect(hayPunto(a.m.mapa, 'vieja'), isTrue);
      expect(punto(a.m.mapa, 'vieja').estilo, EstiloPunto.seleccionado);

      await _tocar(tester, _principal);

      expect(_hojaAlta, findsNothing);
      expect(a.repo.llamadas, hasLength(1), reason: 'no se creó otra');
      expect(seleccionadaId(tester), 'vieja');
    });

    testWidgets('41B·01: «Cancelar» vuelve a N·01 con el pin donde estaba', (tester) async {
      await _montar(tester, repo: _conDuplicados([candidata('vieja')]));
      await _hastaQueHayAca(tester);
      await _tocar(tester, _principal);

      await _tocar(tester, _secundario);

      expect(_texto(_principal), 'Confirmar posición');
      expect(_estado(tester)!.punto, puntoItalia);
      expect(find.text('La nueva'), findsNothing);
    });

    testWidgets('41B·02: varias — letras, tocar una fila resalta su marcador sin mover el mapa, '
        'y su «Reutilizar esta»', (tester) async {
      final a = await _montar(
        tester,
        repo: _conDuplicados([
          candidata('a', metros: 12, motivo: MotivoDuplicado.cercania),
          candidata('b', metros: 4, motivo: MotivoDuplicado.cercania),
        ]),
      );
      await _hastaQueHayAca(tester);
      await _tocar(tester, _principal);
      final antes = a.m.mapa.movimientos.length;

      expect(find.text('Hay 2 ubicaciones cerca'), findsOneWidget);
      expect(find.text('Si alguna es este lugar, reutilizala.'), findsOneWidget);
      expect(find.text('A · a ${FormatoUbicaciones.distancia(4)}'), findsOneWidget);
      expect(find.text('B · a ${FormatoUbicaciones.distancia(12)}'), findsOneWidget);
      expect(punto(a.m.mapa, 'a').estilo, EstiloPunto.candidata);

      await _tocar(tester, find.byKey(ClavesAltaMapa.candidata('a')));

      expect(punto(a.m.mapa, 'a').estilo, EstiloPunto.seleccionado);
      expect(punto(a.m.mapa, 'b').estilo, EstiloPunto.candidata);
      expect(a.m.mapa.movimientos.length, antes);

      final reutilizarA = find.descendant(
        of: find.byKey(ClavesAltaMapa.candidata('a')),
        matching: find.text('Reutilizar esta'),
      );
      await _tocar(tester, reutilizarA);
      expect(seleccionadaId(tester), 'a');
    });

    testWidgets('41B·03: «Crear igual» pide la justificación (obligatoria) y crea la nueva', (
      tester,
    ) async {
      final a = await _montar(
        tester,
        repo: _conDuplicados([candidata('vieja', calle: 'Grecia', numero: '3307')]),
      );
      await _hastaQueHayAca(tester);
      await _tocar(tester, _principal);

      await _tocar(tester, find.byKey(ClavesAltaMapa.crearIgual));

      expect(find.text('Crear igual'), findsWidgets);
      expect(
        find.text(
          'Ya existe Grecia 3307 a ${FormatoUbicaciones.distancia(12)}. '
          'Contá por qué este lugar es otro.',
        ),
        findsOneWidget,
      );
      expect(find.text('JUSTIFICACIÓN · OBLIGATORIA'), findsOneWidget);
      expect(find.text('Queda guardada en tu teléfono.'), findsOneWidget);
      expect(find.byKey(ClavesAltaMapa.velo), findsOneWidget);
      expect(_habilitado(tester, _principal), isFalse);

      await tester.enterText(find.byKey(ClavesAltaMapa.justificacion), 'corto');
      await _asentar(tester);
      expect(_habilitado(tester, _principal), isFalse);

      // «Volver» y reentrar: lo escrito sigue.
      await _tocar(tester, _secundario);
      await _tocar(tester, find.byKey(ClavesAltaMapa.crearIgual));
      expect(find.text('corto'), findsOneWidget);

      await tester.enterText(find.byKey(ClavesAltaMapa.justificacion), 'Es el fondo, otra puerta');
      await _asentar(tester);
      expect(_habilitado(tester, _principal), isTrue);
      await _tocar(tester, _principal);

      expect(a.repo.llamadas, hasLength(2));
      expect(a.repo.llamadas.last.justificacion, 'Es el fondo, otra puerta');
      expect(_hojaAlta, findsNothing);
      expect(seleccionadaId(tester), 'nueva-1');
    });

    testWidgets('41B·03: si «Crear igual» falla, el botón vuelve a andar', (tester) async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async => switch (++intento) {
          1 => Right(AltaConDuplicados(candidatas: [candidata('vieja')])),
          2 => const Left(FailureInesperado(causa: 'disco')),
          _ => Right(AltaRegistrada(ubicacion: u)),
        };
      final a = await _montar(tester, repo: repo);
      await _hastaQueHayAca(tester);
      await _tocar(tester, _principal);
      await _tocar(tester, find.byKey(ClavesAltaMapa.crearIgual));
      await tester.enterText(find.byKey(ClavesAltaMapa.justificacion), 'Es el fondo, otra puerta');
      await _asentar(tester);

      await _tocar(tester, _principal);
      expect(_hojaAlta, findsOneWidget);
      expect(_habilitado(tester, _principal), isTrue);

      await _tocar(tester, _principal);
      expect(a.repo.llamadas, hasLength(3));
      expect(_hojaAlta, findsNothing);
    });

    testWidgets('41B·04: la misma dirección a menos de 100 m — solo «Abrir la existente»', (
      tester,
    ) async {
      final a = await _montar(
        tester,
        repo: _conDuplicados([
          candidata(
            'vieja',
            metros: 26,
            calle: 'Grecia',
            numero: '3307',
            admiteConservarAmbos: false,
          ),
        ]),
      );
      await _hastaQueHayAca(tester);
      await _tocar(tester, _principal);

      expect(find.text('Ya registraste Grecia 3307'), findsOneWidget);
      expect(
        find.text(
          'Está a ${FormatoUbicaciones.distancia(26)}, en la misma ciudad. '
          'Una dirección se registra una sola vez.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(ClavesAltaMapa.crearIgual), findsNothing);
      expect(_texto(_principal), 'Abrir la existente');

      await _tocar(tester, _principal);

      expect(_hojaAlta, findsNothing);
      expect(a.repo.llamadas, hasLength(1));
      expect(seleccionadaId(tester), 'vieja');
    });

    testWidgets('41B: el atrás del teléfono va de a un paso (Crear igual → aviso → N·01)', (
      tester,
    ) async {
      await _montar(tester, repo: _conDuplicados([candidata('vieja')]));
      await _hastaQueHayAca(tester);
      await _tocar(tester, _principal);
      await _tocar(tester, find.byKey(ClavesAltaMapa.crearIgual));

      await tester.binding.handlePopRoute();
      await _asentar(tester);
      expect(_estado(tester)!.paso, PasoAlta.duplicado);
      await tester.binding.handlePopRoute();
      await _asentar(tester);
      expect(_estado(tester)!.paso, PasoAlta.posicion);
      expect(_hojaAlta, findsOneWidget);
    });

    testWidgets('41B: textScaler 2.0 con varias candidatas, sin desbordes', (tester) async {
      await _montar(
        tester,
        escala: 2,
        repo: _conDuplicados([
          for (var i = 0; i < 6; i++)
            candidata('c$i', metros: 10.0 + i, calle: 'Calle ${'muy larga ' * 5}$i'),
        ]),
      );
      await _hastaQueHayAca(tester);
      await _tocar(tester, _principal);

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(ClavesAltaMapa.crearIgual));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('la cámara solo se mueve cuando se pide', () {
    testWidgets('mientras el alta está abierta el mapa no sigue al GPS', (tester) async {
      final a = await _montar(tester);
      await _abrir(tester);
      final antes = a.m.mapa.movimientos.length;

      a.m.gps.moverse(lecturaGps(5, punto: _mataojo));
      await _asentar(tester);

      expect(a.m.mapa.movimientos.length, antes);
    });

    testWidgets('un gesto sobre el mapa mueve el pin con el mapa (sigue en el mismo lugar)', (
      tester,
    ) async {
      final a = await _montar(tester);
      await _abrir(tester);
      final antes = tester.getRect(_pin);
      final camara = a.m.mapa.camara!;

      a.m.mapa.moverPorGesto(
        CamaraMapa(
          centro: Coordenadas(lat: camara.centro.lat + 0.001, lon: camara.centro.lon),
          zoom: camara.zoom,
        ),
      );
      await _asentar(tester);

      expect(tester.getRect(_pin), isNot(antes));
      expect(_estado(tester)!.punto, puntoItalia);
    });
  });
}
