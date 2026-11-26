// «Nombre ubic.» (Cristian, 24/11; #769, backend-supabase 0206): el campo opcional «Nombre del lugar» de
// hasta 80 caracteres en el alta con pin sobre el mapa principal (vista 41, N·02 «¿Qué hay acá?»), con el aviso
// de no poner datos de clientes. Es opcional: sin escribir nada el alta es la de siempre.
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/alta_sobre_el_mapa.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/zonas_falsas.dart';
import 'mapa_ubicaciones_arnes.dart';

final _principal = find.byKey(ClavesAltaMapa.principal);
final _campoNombre = find.byKey(ClavesAltaMapa.nombre);

const _avisoDelNombre = 'Es el nombre del lugar. No pongas nombres ni datos de tus clientes.';

final class _Alta {
  _Alta(this.m, this.repo);

  final MontajeMapaUbicaciones m;
  final RepoAltaFalso repo;
}

Future<_Alta> _montar(WidgetTester tester, {RepoAltaFalso? repo, double escala = 1}) async {
  final alta = repo ?? RepoAltaFalso();
  final lista = RepoListaFalso([filaLista('vieja', calle: 'Grecia', numero: '3301')])..alta = alta;
  var secuencia = 0;
  final m = await montarMapaUbicaciones(
    tester,
    repo: lista,
    escala: escala,
    altaReal: true,
    otrosOverrides: [
      geocodificadorInversoProvider.overrideWithValue(
        GeocodificadorFalso((_) => const DireccionDelPunto(calle: 'Grecia', numero: '3307')),
      ),
      ubicadorZonaProvider.overrideWithValue(ubicadorSinZonas()),
      esperaPuntoAltaProvider.overrideWithValue(const Duration(milliseconds: 20)),
      generadorIdUbicacionProvider.overrideWithValue(() => 'nueva-${++secuencia}'),
    ],
  );
  return _Alta(m, alta);
}

Future<void> _asentar(WidgetTester tester, [int veces = 12]) => asentarLista(tester, veces);

Future<void> _tocar(WidgetTester tester, Finder boton) async {
  await tester.ensureVisible(boton);
  await tester.pump();
  await tester.tap(boton);
  await _asentar(tester);
}

/// Abre el alta y confirma la posición: queda en N·02, con el formulario.
Future<void> _hastaQueHayAca(WidgetTester tester) async {
  await tester.tap(botonNueva);
  await _asentar(tester);
  await _tocar(tester, _principal);
}

Future<void> _escribirNombre(WidgetTester tester, String texto) async {
  await tester.ensureVisible(_campoNombre);
  await tester.pump();
  await tester.enterText(_campoNombre, texto);
  await _asentar(tester);
}

RepoAltaFalso _conDuplicados(List<CandidataDuplicado> candidatas) {
  var intento = 0;
  return RepoAltaFalso()
    ..comportamiento = (u) async => ++intento == 1
        ? Right(AltaConDuplicados(candidatas: candidatas))
        : Right(AltaRegistrada(ubicacion: u));
}

void main() {
  group('41A·02 · N·02: el campo «Nombre del lugar»', () {
    testWidgets(
      'está debajo del número, dice que es opcional y avisa que no son datos de clientes',
      (tester) async {
        await _montar(tester);
        await _hastaQueHayAca(tester);
        await tester.ensureVisible(_campoNombre);
        await tester.pump();

        expect(_campoNombre, findsOneWidget);
        expect(find.text('NOMBRE DEL LUGAR · OPCIONAL'), findsOneWidget);
        expect(find.text('Ej.: Farmacia Italia'), findsOneWidget);
        expect(find.text(_avisoDelNombre), findsOneWidget);
        expect(
          tester.getTopLeft(_campoNombre).dy,
          greaterThan(tester.getTopLeft(find.byKey(ClavesAltaMapa.numero)).dy),
        );
      },
    );

    testWidgets('sin escribir nada el alta se registra sin nombre, como siempre', (tester) async {
      final a = await _montar(tester);
      await _hastaQueHayAca(tester);

      await _tocar(tester, _principal);

      expect(a.repo.llamadas.single.ubicacion.nombre, isNull);
    });

    testWidgets('lo que se escribe se registra recortado', (tester) async {
      final a = await _montar(tester);
      await _hastaQueHayAca(tester);

      await _escribirNombre(tester, '  Farmacia Italia ');
      await _tocar(tester, _principal);

      expect(a.repo.llamadas.single.ubicacion.nombre, 'Farmacia Italia');
    });

    testWidgets('el campo no deja pasar de 80 caracteres', (tester) async {
      final a = await _montar(tester);
      await _hastaQueHayAca(tester);

      await _escribirNombre(tester, 'a' * 95);
      await _tocar(tester, _principal);

      expect(a.repo.llamadas.single.ubicacion.nombre, hasLength(Ubicacion.largoMaximoDelNombre));
    });

    testWidgets('el atrás del teléfono de N·02 a N·01 y de vuelta conserva lo escrito', (
      tester,
    ) async {
      final a = await _montar(tester);
      await _hastaQueHayAca(tester);
      await _escribirNombre(tester, 'Farmacia Italia');

      await tester.binding.handlePopRoute();
      await _asentar(tester);
      await _tocar(tester, _principal);

      expect(tester.widget<TextField>(_campoNombre).controller!.text, 'Farmacia Italia');
      await _tocar(tester, _principal);
      expect(a.repo.llamadas.single.ubicacion.nombre, 'Farmacia Italia');
    });

    testWidgets('con un posible duplicado, «Crear igual» el nombre sigue y se guarda', (
      tester,
    ) async {
      final a = await _montar(
        tester,
        repo: _conDuplicados([candidata('vieja', calle: 'Grecia', numero: '3307')]),
      );
      await _hastaQueHayAca(tester);
      await _escribirNombre(tester, 'Farmacia Italia');
      await _tocar(tester, _principal);

      await _tocar(tester, find.byKey(ClavesAltaMapa.crearIgual));
      await tester.enterText(find.byKey(ClavesAltaMapa.justificacion), 'Es el fondo, otra puerta');
      await _asentar(tester);
      await _tocar(tester, _principal);

      expect(a.repo.llamadas, hasLength(2));
      expect(a.repo.llamadas.last.ubicacion.nombre, 'Farmacia Italia');
      expect(a.repo.llamadas.last.justificacion, 'Es el fondo, otra puerta');
    });

    testWidgets('con el texto al 200 % el campo y su aviso entran sin desbordar', (tester) async {
      await _montar(tester, escala: 2);
      await _hastaQueHayAca(tester);
      await tester.ensureVisible(_campoNombre);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text(_avisoDelNombre), findsOneWidget);
      await _escribirNombre(tester, 'a' * 80);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(_campoNombre).height, greaterThanOrEqualTo(48));
    });
  });
}
