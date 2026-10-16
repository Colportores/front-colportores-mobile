// HU-UBI-002 / vista 05: geometría de la lista a 360×640 y 412×915, texto 1.0 y 2.0, con las
// fuentes reales: sin overflow, nada fuera de pantalla, blancos táctiles de 48 dp y etiquetas.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'lista_ubicaciones_arnes.dart';

const _calleLarga = 'Avenida Doctor Luis Alberto de Herrera y Presidente General Flores';

List<UbicacionConResumen> _variadas() => [
  filaLista(
    'a',
    calle: 'Rivadavia',
    numero: '100',
    metrosAlNorte: 40,
    hace: const Duration(minutes: 5),
    estado: EstadoCasa.cobranzaPendiente,
    espacios: 2,
  ),
  filaLista(
    'b',
    tipo: TipoUbicacion.negocio,
    calle: _calleLarga,
    numero: 'Km 12 bis apto 1203',
    metrosAlNorte: 150,
    hace: const Duration(hours: 5),
    estado: EstadoCasa.entrevistaAgendada,
    entrevista: DateTime(2026, 10, 8, 10),
  ),
  filaLista(
    'c',
    tipo: TipoUbicacion.edificio,
    calle: 'Calle sin nombre conocido',
    numero: 's/n',
    metrosAlNorte: 900,
    hace: const Duration(days: 40),
    estado: EstadoCasa.entregaYPago,
    espacios: 120,
  ),
  filaLista(
    'd',
    calle: _calleLarga,
    numero: '4567',
    hace: const Duration(days: 20),
    baja: ahoraLista.subtract(const Duration(days: 20)),
  ),
  filaLista('e', calle: 'Colonia', numero: '2020', estado: EstadoCasa.ventaCompleta),
  filaLista('f', calle: 'Mercedes', numero: '1', estado: EstadoCasa.sinVisita),
  filaLista('g', calle: 'Paysandú', numero: '2', estado: EstadoCasa.noContesto),
  filaLista('h', calle: 'Soriano', numero: '3', estado: EstadoCasa.rechazo),
  filaLista('i', calle: 'Yí', numero: '4', estado: EstadoCasa.entrevistaHecha),
];

void main() {
  setUpAll(cargarFuentesReales);

  const tamanios = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

  /// Qué se comprueba en cada estado: ninguna excepción de layout y blancos táctiles.
  Future<void> comprobar(WidgetTester tester, Size tam) async {
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    // Nada se sale del ancho de la pantalla.
    for (final fila in find.byType(FilaUbicacionLista).evaluate()) {
      final caja = tester.getRect(find.byWidget(fila.widget));
      expect(caja.left, greaterThanOrEqualTo(0));
      expect(caja.right, lessThanOrEqualTo(tam.width));
    }
  }

  for (final MapEntry(key: nombre, value: tam) in tamanios.entries) {
    for (final escala in [1.0, 2.0]) {
      final marca = '$nombre, texto $escala';

      group('geometría · $marca', () {
        testWidgets('la lista con todos los estados, una baja y textos largos', (tester) async {
          final semantica = tester.ensureSemantics();
          final repo = RepoListaFalso(_variadas());
          await montarLista(
            tester,
            repo: repo,
            gps: GpsFalso(Right(lecturaGps(8))),
            tamano: tam,
            escala: escala,
            alAbrir: (_) {},
          );
          await abrirHojaFiltros(tester);
          await tester.ensureVisible(find.byKey(const Key('hoja_filtros_bajas')));
          await tester.tap(find.byKey(const Key('hoja_filtros_bajas')));
          await asentarLista(tester);
          await verUbicaciones(tester);

          expect(find.text('Rivadavia 100'), findsOneWidget);
          await comprobar(tester, tam);
          semantica.dispose();
        });

        testWidgets('la lista por cercanía muestra la distancia sin pisar la dirección', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await montarLista(
            tester,
            repo: RepoListaFalso(_variadas()),
            gps: GpsFalso(Right(lecturaGps(8))),
            tamano: tam,
            escala: escala,
            alAbrir: (_) {},
          );
          await tester.tap(botonOrden);
          await asentarLista(tester);
          await tester.tap(find.text('Por cercanía'));
          await asentarLista(tester);

          // Con letra grande entran pocas filas: alcanza con que se vea una distancia.
          expect(find.textContaining('\u00A0m'), findsWidgets);
          await comprobar(tester, tam);
          semantica.dispose();
        });

        testWidgets('el estado vacío', (tester) async {
          final semantica = tester.ensureSemantics();
          await montarLista(tester, tamano: tam, escala: escala);

          expect(find.text(TextosListaUbicaciones.registrarPrimera), findsOneWidget);
          await comprobar(tester, tam);
          semantica.dispose();
        });

        testWidgets('sin resultados', (tester) async {
          final semantica = tester.ensureSemantics();
          await montarLista(tester, repo: RepoListaFalso(_variadas()), tamano: tam, escala: escala);
          await buscarEnLista(tester, 'zzz');

          expect(find.text(TextosListaUbicaciones.limpiarFiltros), findsOneWidget);
          await comprobar(tester, tam);
          semantica.dispose();
        });

        testWidgets('el error de lectura, sin lista y con la lista a la vista', (tester) async {
          final semantica = tester.ensureSemantics();
          final repo = RepoListaFalso(_variadas())..fallaAlSuscribir = true;
          await montarLista(tester, repo: repo, tamano: tam, escala: escala);
          expect(find.text(TextosListaUbicaciones.errorLectura), findsOneWidget);
          await comprobar(tester, tam);

          repo.fallaAlSuscribir = false;
          await tester.tap(find.text(TextosListaUbicaciones.reintentar));
          await asentarLista(tester);
          repo.fallar(StateError('x'));
          await asentarLista(tester);
          expect(find.text(TextosListaUbicaciones.errorLectura), findsOneWidget);
          expect(find.text('Rivadavia 100'), findsOneWidget);
          await comprobar(tester, tam);
          semantica.dispose();
        });

        testWidgets('sin GPS y buscando GPS', (tester) async {
          final semantica = tester.ensureSemantics();
          final gps = GpsFalso()..bloqueo = Completer<void>();
          await montarLista(
            tester,
            repo: RepoListaFalso(_variadas()),
            gps: gps,
            tamano: tam,
            escala: escala,
          );
          expect(find.text('◎ Buscando GPS…'), findsOneWidget);
          await comprobar(tester, tam);
          gps.bloqueo!.complete();
          await asentarLista(tester);
          semantica.dispose();
        });

        testWidgets('con muchos filtros activos', (tester) async {
          final semantica = tester.ensureSemantics();
          await montarLista(
            tester,
            repo: RepoListaFalso(_variadas()),
            gps: GpsFalso(Right(lecturaGps(8))),
            tamano: tam,
            escala: escala,
          );
          await abrirHojaFiltros(tester);
          for (final t in ['Casa', 'Negocio', 'Edificio']) {
            await tester.ensureVisible(find.text(t));
            await tester.tap(find.text(t));
          }
          await tester.ensureVisible(find.text('Rechazó'));
          await tester.tap(find.text('Rechazó'));
          await asentarLista(tester);
          await tester.ensureVisible(botonVerUbicaciones);
          await verUbicaciones(tester);

          expect(chipFiltro('Casa'), findsOneWidget);
          await comprobar(tester, tam);
          semantica.dispose();
        });

        testWidgets('la hoja de filtros con estados, ciudad y proximidad', (tester) async {
          final semantica = tester.ensureSemantics();
          await montarLista(
            tester,
            repo: RepoListaFalso(_variadas()),
            gps: GpsFalso(Right(lecturaGps(8))),
            tamano: tam,
            escala: escala,
          );
          await abrirHojaFiltros(tester);

          expect(find.text('Filtros'), findsOneWidget);
          await comprobar(tester, tam);
          // El botón de aplicar queda a la vista aunque el contenido sea más alto que la pantalla.
          expect(tester.getRect(botonVerUbicaciones).bottom, lessThanOrEqualTo(tam.height));
          expect(tester.getRect(botonVerUbicaciones).top, greaterThanOrEqualTo(0));
          semantica.dispose();
        });

        testWidgets('la hoja de filtros sin conocer el estado de las casas, sin GPS', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await montarLista(
            tester,
            repo: RepoListaFalso([
              for (final f in _variadas())
                UbicacionConResumen(ubicacion: f.ubicacion, cantidadEspacios: f.cantidadEspacios),
            ]),
            gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado))),
            tamano: tam,
            escala: escala,
          );
          await abrirHojaFiltros(tester);

          expect(find.text('Necesita GPS'), findsOneWidget);
          await comprobar(tester, tam);
          semantica.dispose();
        });

        testWidgets('las hojas de orden y de ciudades', (tester) async {
          final semantica = tester.ensureSemantics();
          await montarLista(tester, repo: RepoListaFalso(_variadas()), tamano: tam, escala: escala);
          await tester.tap(botonOrden);
          await asentarLista(tester);
          expect(find.text('Ordenar'), findsOneWidget);
          await comprobar(tester, tam);
          await tester.tap(find.text('Última actualización').last);
          await asentarLista(tester);

          await abrirHojaFiltros(tester);
          await tester.ensureVisible(find.text('Todas'));
          await tester.tap(find.text('Todas'));
          await asentarLista(tester);
          expect(find.text('Montevideo'), findsOneWidget);
          await comprobar(tester, tam);
          semantica.dispose();
        });

        testWidgets('con el teclado abierto en el buscador', (tester) async {
          final semantica = tester.ensureSemantics();
          await montarLista(tester, repo: RepoListaFalso(_variadas()), tamano: tam, escala: escala);
          await tester.showKeyboard(campoBusqueda);
          await tester.enterText(campoBusqueda, 'rivad');
          await tester.pump(const Duration(milliseconds: 300));
          await asentarLista(tester);

          expect(find.byKey(const Key('lista_busqueda_borrar')), findsOneWidget);
          await comprobar(tester, tam);
          semantica.dispose();
        });
      });
    }
  }
}
