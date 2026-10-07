// HU-UBI-002 / vista 05 «Lista Ubicaciones» (05B·01, 05B·02, 05B·03 y los estados que el canvas no
// dibuja): la pestaña «Lista» con sus filtros, el orden, las bajas, el buscador y el GPS.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/data/services/fuentes_sin_adaptador_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'lista_ubicaciones_arnes.dart';

const _nbsp = ' ';

List<UbicacionConResumen> _muestra() => [
  filaLista(
    'casa-1',
    calle: 'Rivadavia',
    numero: '100',
    hace: const Duration(hours: 1),
    estado: EstadoCasa.cobranzaPendiente,
    espacios: 2,
  ),
  filaLista(
    'neg-1',
    tipo: TipoUbicacion.negocio,
    calle: 'Colonia',
    numero: '2020',
    hace: const Duration(hours: 5),
    estado: EstadoCasa.entrevistaAgendada,
    entrevista: DateTime(2026, 10, 8, 10),
  ),
  filaLista(
    'edi-1',
    tipo: TipoUbicacion.edificio,
    calle: 'Rivadavia',
    numero: '350',
    hace: const Duration(days: 2),
    estado: EstadoCasa.rechazo,
    espacios: 12,
  ),
];

/// Las mismas sin estado: lo que ve el colportor hoy, antes de que exista `house_status` local.
List<UbicacionConResumen> _sinEstado() => [
  for (final f in _muestra())
    UbicacionConResumen(ubicacion: f.ubicacion, cantidadEspacios: f.cantidadEspacios),
];

/// Quien dio de baja todo lo que registró: dos bajas y ninguna activa.
List<UbicacionConResumen> _soloBajas() => [
  filaLista(
    'baja-1',
    calle: 'Gral. Flores',
    numero: '1500',
    hace: const Duration(days: 20),
    baja: ahoraLista.subtract(const Duration(days: 20)),
  ),
  filaLista(
    'baja-2',
    calle: 'Rivera',
    numero: '3920',
    hace: const Duration(days: 30),
    baja: ahoraLista.subtract(const Duration(days: 30)),
  ),
];

List<UbicacionConResumen> _muchas(int n) => [
  for (var i = 0; i < n; i++)
    filaLista(
      'u-${i.toString().padLeft(3, '0')}',
      calle: 'Calle $i',
      numero: '${i + 1}',
      hace: Duration(minutes: i + 1),
      estado: EstadoCasa.noContesto,
    ),
];

void main() {
  group('05B · cuerpo de la lista', () {
    testWidgets('dado que todavía no llegó la lista, entonces muestra que está cargando', (
      tester,
    ) async {
      final repo = RepoListaFalso(_muestra())..bloqueo = Completer<void>();

      await montarLista(tester, repo: repo);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Av. Italia 1234'), findsNothing);
      expect(find.text(TextosListaUbicaciones.titulo), findsOneWidget);

      repo.bloqueo!.complete();
      await asentarLista(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Rivadavia 100'), findsOneWidget);
    });

    testWidgets('dado ubicaciones con estado, entonces cada fila dice dirección, estado y cuándo', (
      tester,
    ) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));

      expect(find.text('Rivadavia 100'), findsOneWidget);
      expect(find.text('Cobranza pendiente · 2 espacios'), findsOneWidget);
      expect(find.text('hace 1 h'), findsOneWidget);
      expect(find.text('Colonia 2020'), findsOneWidget);
      expect(find.text('Entrevista agendada · jue 10:00'), findsOneWidget);
      expect(find.text('Rivadavia 350'), findsOneWidget);
      expect(find.text('Rechazó · 12 espacios'), findsOneWidget);
      expect(find.text('hace 2 d'), findsOneWidget);
      expect(find.byType(InsigniaEstadoCasa), findsNWidgets(3));
      expect(find.text('3 de 3'), findsOneWidget);
      expect(find.text('Última actualización ▾'), findsOneWidget);
    });

    testWidgets('dado que todavía no se conoce el estado de las casas, entonces cada fila lleva el '
        'tipo y los espacios, con el ícono del tipo', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_sinEstado()));

      expect(find.text('Casa · 2 espacios'), findsOneWidget);
      expect(find.text('Negocio · 1 espacio'), findsOneWidget);
      expect(find.text('Edificio · 12 espacios'), findsOneWidget);
      expect(find.byType(InsigniaEstadoCasa), findsNothing);
      expect(find.byType(InsigniaTipoUbicacion), findsNWidgets(3));
    });

    testWidgets('dado que no registró ubicaciones, entonces ve el estado vacío con la invitación a '
        'registrar la primera y sin botón «Nueva»', (tester) async {
      await montarLista(tester);

      expect(find.text(TextosListaUbicaciones.vacioTitulo), findsOneWidget);
      expect(find.text(TextosListaUbicaciones.registrarPrimera), findsOneWidget);
      expect(botonNueva, findsNothing);
      expect(botonOrden, findsNothing);
      expect(find.textContaining(' de '), findsNothing);
      // Sin ninguna ubicación (ni bajas) no hay nada que mostrar: el vacío es el de siempre.
      expect(find.text(TextosListaUbicaciones.soloBajasTitulo), findsNothing);
      expect(find.byKey(const Key('lista_mostrar_bajas')), findsNothing);
    });

    testWidgets('dado que solo tiene ubicaciones dadas de baja y «Mostrar bajas» está apagado, '
        'entonces dice que no tiene ubicaciones activas y ofrece registrar una o mostrar las '
        'bajas, sin listarlas', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_soloBajas()));

      expect(find.text(TextosListaUbicaciones.soloBajasTitulo), findsOneWidget);
      expect(find.text('No tenés ubicaciones activas'), findsOneWidget);
      expect(find.text(TextosListaUbicaciones.soloBajasCuerpo), findsOneWidget);
      expect(find.text('Registrar una ubicación'), findsOneWidget);
      expect(find.byKey(const Key('lista_mostrar_bajas')), findsOneWidget);
      expect(find.text('Mostrar bajas'), findsOneWidget);
      // No es el vacío de quien nunca registró nada, y las bajas no se listan.
      expect(find.text(TextosListaUbicaciones.vacioTitulo), findsNothing);
      expect(find.text(TextosListaUbicaciones.registrarPrimera), findsNothing);
      expect(find.text('Gral. Flores 1500'), findsNothing);
      expect(find.text('BAJA'), findsNothing);
      expect(botonNueva, findsNothing);
      expect(botonOrden, findsNothing);
      // Sin contador «N de N»: no hay filas.
      expect(find.textContaining(RegExp(r'\d+ de \d+')), findsNothing);
    });

    testWidgets('dado el vacío de «solo bajas», cuando toca «Mostrar bajas», entonces prende el '
        'filtro, aparecen las bajas y al quitarlo vuelve el vacío', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_soloBajas()));

      await tester.tap(find.byKey(const Key('lista_mostrar_bajas')));
      await asentarLista(tester);

      expect(find.text(TextosListaUbicaciones.soloBajasTitulo), findsNothing);
      expect(find.text('Gral. Flores 1500'), findsOneWidget);
      expect(find.text('Rivera 3920'), findsOneWidget);
      expect(find.text('BAJA'), findsNWidgets(2));
      expect(chipFiltro('Con bajas'), findsOneWidget);
      expect(find.text('2 de 2 · 2 bajas'), findsOneWidget);

      await tester.tap(chipFiltro('Con bajas'));
      await asentarLista(tester);

      expect(find.text(TextosListaUbicaciones.soloBajasTitulo), findsOneWidget);
      expect(find.text('Gral. Flores 1500'), findsNothing);
    });

    testWidgets('dado el vacío de «solo bajas», cuando toca «Registrar una ubicación», entonces '
        'abre el alta una sola vez aunque toque dos veces seguidas', (tester) async {
      final abierta = Completer<void>();
      var altas = 0;
      await montarLista(
        tester,
        repo: RepoListaFalso(_soloBajas()),
        alRegistrar: () {
          altas++;
          return abierta.future;
        },
      );

      await tester.tap(find.byKey(const Key('lista_registrar_una')));
      await tester.tap(find.byKey(const Key('lista_registrar_una')));
      await tester.pump();

      expect(altas, 1);

      abierta.complete();
      await asentarLista(tester);
      await tester.tap(find.byKey(const Key('lista_registrar_una')));
      await tester.pump();

      expect(altas, 2);
    });

    testWidgets('dado que tiene una activa y una baja, cuando «Mostrar bajas» está apagado, '
        'entonces ve la lista de siempre, no el vacío de «solo bajas»', (tester) async {
      await montarLista(
        tester,
        repo: RepoListaFalso([
          filaLista('viva', calle: 'Rivadavia', numero: '100'),
          ..._soloBajas(),
        ]),
      );

      expect(find.text('Rivadavia 100'), findsOneWidget);
      expect(find.text(TextosListaUbicaciones.soloBajasTitulo), findsNothing);
      expect(find.text('1 de 1'), findsOneWidget);
      expect(botonNueva, findsOneWidget);
    });

    testWidgets('dado el estado vacío, cuando toca «Registrar tu primera ubicación», entonces abre '
        'el alta una sola vez aunque toque dos veces seguidas', (tester) async {
      final abierta = Completer<void>();
      var altas = 0;
      await montarLista(
        tester,
        alRegistrar: () {
          altas++;
          return abierta.future;
        },
      );

      await tester.tap(find.byKey(const Key('lista_registrar_primera')));
      await tester.tap(find.byKey(const Key('lista_registrar_primera')));
      await tester.pump();

      expect(altas, 1);

      // Al volver del alta se puede abrir otra.
      abierta.complete();
      await asentarLista(tester);
      await tester.tap(find.byKey(const Key('lista_registrar_primera')));
      await tester.pump();

      expect(altas, 2);
    });

    testWidgets('dado que los filtros no dejan ninguna, entonces dice «Sin resultados» y «Limpiar '
        'filtros» vuelve a mostrar todo y vacía el buscador', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));

      await buscarEnLista(tester, 'zzz');

      expect(find.text(TextosListaUbicaciones.sinResultadosTitulo), findsOneWidget);
      expect(find.text(TextosListaUbicaciones.vacioTitulo), findsNothing);
      expect(find.text('0 de 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lista_limpiar_filtros')));
      await asentarLista(tester);

      expect(find.text('Rivadavia 100'), findsOneWidget);
      expect(find.text('3 de 3'), findsOneWidget);
      expect(tester.widget<TextField>(campoBusqueda).controller!.text, isEmpty);
    });

    testWidgets('dado que falla la lectura sin lista, entonces muestra el error y «Reintentar» '
        'recupera la lista', (tester) async {
      final repo = RepoListaFalso(_muestra())..fallaAlSuscribir = true;
      await montarLista(tester, repo: repo);

      expect(find.text(TextosListaUbicaciones.errorLectura), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      repo.fallaAlSuscribir = false;
      await tester.tap(find.text(TextosListaUbicaciones.reintentar));
      await asentarLista(tester);

      expect(find.text(TextosListaUbicaciones.errorLectura), findsNothing);
      expect(find.text('Rivadavia 100'), findsOneWidget);
    });

    testWidgets('dado que reintenta y vuelve a fallar, entonces el botón sigue disponible', (
      tester,
    ) async {
      final repo = RepoListaFalso(_muestra())..fallaAlSuscribir = true;
      await montarLista(tester, repo: repo);

      await tester.tap(find.text(TextosListaUbicaciones.reintentar));
      await asentarLista(tester);
      await tester.tap(find.text(TextosListaUbicaciones.reintentar));
      await asentarLista(tester);

      expect(find.text(TextosListaUbicaciones.errorLectura), findsOneWidget);
      expect(find.text(TextosListaUbicaciones.reintentar), findsOneWidget);
      expect(repo.activas, 1);
    });

    testWidgets('dado un error de lectura con la lista a la vista, entonces la lista sigue y se '
        'avisa arriba con «Reintentar»', (tester) async {
      final repo = RepoListaFalso(_muestra());
      await montarLista(tester, repo: repo);

      repo.fallar(StateError('se cerró la base'));
      await asentarLista(tester);

      expect(find.text('Rivadavia 100'), findsOneWidget);
      expect(find.text(TextosListaUbicaciones.errorLectura), findsOneWidget);

      await tester.tap(find.text(TextosListaUbicaciones.reintentar));
      await asentarLista(tester);

      expect(find.text(TextosListaUbicaciones.errorLectura), findsNothing);
      expect(find.text('Rivadavia 100'), findsOneWidget);
    });

    testWidgets('dado que no hay base abierta, entonces muestra el error en vez de romperse', (
      tester,
    ) async {
      final repo = RepoListaFalso(_muestra())..lanzaAlPedir = StateError('sin base');
      await montarLista(tester, repo: repo);

      expect(find.text(TextosListaUbicaciones.errorLectura), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado un alta nueva, cuando la base emite, entonces aparece arriba sin recargar', (
      tester,
    ) async {
      final repo = RepoListaFalso(_muestra());
      await montarLista(tester, repo: repo);
      // Con el GPS ya leído la lista se pidió con la posición; de ahí en más, ninguna otra.
      final suscripcionesAntes = repo.suscripciones;

      repo.emitir([
        filaLista('nueva', calle: 'Av. 8 de Octubre', numero: '3333', hace: Duration.zero),
        ..._muestra(),
      ]);
      await asentarLista(tester);

      expect(find.text('Av. 8 de Octubre 3333'), findsOneWidget);
      expect(find.text('ahora'), findsOneWidget);
      expect(find.text('4 de 4'), findsOneWidget);
      expect(repo.suscripciones, suscripcionesAntes);
    });
  });

  group('05B · 03 Mostrar bajas activo', () {
    final conBaja = [
      ..._muestra(),
      filaLista(
        'baja-1',
        calle: 'Gral. Flores',
        numero: '1500',
        hace: const Duration(days: 20),
        baja: ahoraLista.subtract(const Duration(days: 20)),
      ),
    ];

    testWidgets('dado «Mostrar bajas» activo, entonces la baja se ve con su etiqueta, sin flecha y '
        'sin poder abrirse; el contador suma las bajas', (tester) async {
      final abiertas = <String>[];
      await montarLista(tester, repo: RepoListaFalso(conBaja), alAbrir: abiertas.add);
      expect(find.text('Gral. Flores 1500'), findsNothing);
      expect(find.text('3 de 3'), findsOneWidget);

      await abrirHojaFiltros(tester);
      await tester.tap(find.byKey(const Key('hoja_filtros_bajas')));
      await asentarLista(tester);
      await verUbicaciones(tester);

      expect(find.text('Gral. Flores 1500'), findsOneWidget);
      expect(find.text('BAJA'), findsOneWidget);
      expect(find.textContaining('dada de baja el'), findsOneWidget);
      expect(find.byType(InsigniaBaja), findsOneWidget);
      expect(find.text('4 de 4 · 1 baja'), findsOneWidget);
      expect(chipFiltro('Con bajas'), findsOneWidget);
      // Tres filas con flecha («›»); la baja no.
      expect(find.text('›'), findsNWidgets(3));

      await tester.tap(find.text('Gral. Flores 1500'));
      await tester.pump();
      expect(abiertas, isEmpty);

      await tester.tap(find.text('Rivadavia 100'));
      await tester.pump();
      expect(abiertas, ['casa-1']);
    });

    testWidgets('dado el chip «Con bajas», cuando se quita, entonces las bajas desaparecen', (
      tester,
    ) async {
      await montarLista(tester, repo: RepoListaFalso(conBaja));
      await abrirHojaFiltros(tester);
      await tester.tap(find.byKey(const Key('hoja_filtros_bajas')));
      await asentarLista(tester);
      await verUbicaciones(tester);

      await tester.tap(chipFiltro('Con bajas'));
      await asentarLista(tester);

      expect(find.text('Gral. Flores 1500'), findsNothing);
      expect(find.text('BAJA'), findsNothing);
      expect(chipFiltro('Con bajas'), findsNothing);
    });
  });

  group('05B · 01 Hoja de filtros', () {
    testWidgets('dado que se abre, entonces muestra los tres tipos con su contador y «Ver N '
        'ubicaciones»', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));

      await abrirHojaFiltros(tester);

      expect(find.text('Filtros'), findsOneWidget);
      expect(find.text('TIPO'), findsOneWidget);
      expect(find.text('Casa'), findsOneWidget);
      expect(find.text('Negocio'), findsOneWidget);
      expect(find.text('Edificio'), findsOneWidget);
      expect(find.text('ESTADO DE LA CASA'), findsOneWidget);
      expect(find.text('CIUDAD'), findsOneWidget);
      expect(find.text('PROXIMIDAD'), findsOneWidget);
      expect(find.text('Mostrar bajas'), findsOneWidget);
      expect(find.text('Limpiar'), findsOneWidget);
      expect(find.text('Ver 3 ubicaciones'), findsOneWidget);
    });

    testWidgets('dado que no se sabe el estado de las casas, entonces la hoja no ofrece el filtro '
        'por estado', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_sinEstado()));

      await abrirHojaFiltros(tester);

      expect(find.text('ESTADO DE LA CASA'), findsNothing);
      expect(find.text('Entrevista agendada'), findsNothing);
      expect(find.text('TIPO'), findsOneWidget);
    });

    testWidgets('dado que elige un tipo, entonces «Ver N» cuenta lo que quedaría y al aplicarlo '
        'queda el chip, el contador y el número del botón', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));
      await abrirHojaFiltros(tester);

      await tester.tap(find.text('Negocio'));
      await asentarLista(tester);

      expect(find.text('Ver 1 ubicación'), findsOneWidget);
      expect(find.text('✓ Negocio'), findsOneWidget);

      await verUbicaciones(tester);

      expect(find.text('Filtros'), findsNothing);
      expect(find.text('Colonia 2020'), findsOneWidget);
      expect(find.text('Rivadavia 100'), findsNothing);
      expect(chipFiltro('Negocio'), findsOneWidget);
      expect(find.text('1 de 3'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('dado tipo y estado combinados, entonces cada contador cuenta con el otro filtro '
        'aplicado', (tester) async {
      final filas = [
        filaLista('a', estado: EstadoCasa.cobranzaPendiente),
        filaLista('b', estado: EstadoCasa.cobranzaPendiente),
        filaLista('c', tipo: TipoUbicacion.negocio, estado: EstadoCasa.cobranzaPendiente),
        filaLista('d', estado: EstadoCasa.rechazo),
        filaLista('e', tipo: TipoUbicacion.edificio, estado: EstadoCasa.rechazo),
      ];
      await montarLista(tester, repo: RepoListaFalso(filas));
      await abrirHojaFiltros(tester);

      await tester.tap(find.text('Cobranza pendiente'));
      await asentarLista(tester);

      // Con «Cobranza pendiente» marcado: Casa 2, Negocio 1, Edificio 0.
      expect(find.text('Ver 3 ubicaciones'), findsOneWidget);
      final casa = find.ancestor(of: find.text('Casa'), matching: find.byType(Wrap)).first;
      expect(find.descendant(of: casa, matching: find.text('2')), findsOneWidget);

      await tester.tap(find.text('Casa'));
      await asentarLista(tester);
      expect(find.text('Ver 2 ubicaciones'), findsOneWidget);

      await verUbicaciones(tester);

      expect(find.byType(FilaUbicacionLista), findsNWidgets(2));
      expect(chipFiltro('Casa'), findsOneWidget);
      expect(chipFiltro('Cobranza pendiente'), findsOneWidget);
      expect(find.text('2 de 5'), findsOneWidget);
    });

    testWidgets('dado que cierra la hoja sin aplicar, entonces no cambia nada', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));
      await abrirHojaFiltros(tester);
      await tester.tap(find.text('Negocio'));
      await asentarLista(tester);

      await tester.tapAt(const Offset(20, 40));
      await asentarLista(tester);

      expect(find.text('Filtros'), findsNothing);
      expect(find.text('3 de 3'), findsOneWidget);
      expect(chipFiltro('Negocio'), findsNothing);
    });

    testWidgets('dado «Limpiar», entonces vacía el borrador de la hoja pero no la búsqueda', (
      tester,
    ) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));
      await buscarEnLista(tester, 'rivadavia');
      await abrirHojaFiltros(tester);
      await tester.tap(find.text('Edificio'));
      await asentarLista(tester);
      expect(find.text('Ver 1 ubicación'), findsOneWidget);

      await tester.tap(find.text('Limpiar'));
      await asentarLista(tester);

      expect(find.text('Ver 2 ubicaciones'), findsOneWidget);
      expect(find.text('✓ Edificio'), findsNothing);
    });

    testWidgets('dado un doble toque en «Ver N ubicaciones», entonces se cierra una sola vez y no '
        'cierra también la pantalla', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));
      await abrirHojaFiltros(tester);
      await tester.tap(find.text('Casa'));
      await asentarLista(tester);

      await tester.tap(botonVerUbicaciones);
      await tester.tap(botonVerUbicaciones, warnIfMissed: false);
      await asentarLista(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(TextosListaUbicaciones.titulo), findsOneWidget);
      expect(chipFiltro('Casa'), findsOneWidget);
    });

    testWidgets('dado que reabre la hoja, entonces trae los filtros que tenía puestos', (
      tester,
    ) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));
      await abrirHojaFiltros(tester);
      await tester.tap(find.text('Negocio'));
      await asentarLista(tester);
      await verUbicaciones(tester);

      await abrirHojaFiltros(tester);

      expect(find.text('✓ Negocio'), findsOneWidget);
      expect(find.text('Ver 1 ubicación'), findsOneWidget);
    });

    testWidgets(
      'dado que no hay GPS, entonces «Proximidad» se ve deshabilitada con «Necesita GPS»',
      (tester) async {
        await montarLista(tester, repo: RepoListaFalso(_muestra()), gps: gpsFallido());

        await abrirHojaFiltros(tester);

        expect(find.text('Necesita GPS'), findsOneWidget);
        await tester.tap(find.text('Necesita GPS'));
        await asentarLista(tester);
        expect(find.text('100${_nbsp}m'), findsNothing);
      },
    );

    testWidgets(
      'dado el GPS, cuando elige «Proximidad» 100 m, entonces filtra y deja el chip «Cerca '
      'de mí · 100 m»',
      (tester) async {
        final filas = [
          filaLista('cerca', calle: 'Cerca', numero: '1', metrosAlNorte: 30),
          filaLista('lejos', calle: 'Lejos', numero: '2', metrosAlNorte: 600),
        ];
        await montarLista(tester, repo: RepoListaFalso(filas), gps: GpsFalso(Right(lecturaGps(8))));
        await abrirHojaFiltros(tester);
        expect(find.text('Cualquiera'), findsOneWidget);

        await tester.tap(find.text('Cualquiera'));
        await asentarLista(tester);
        expect(find.text('Proximidad'), findsOneWidget);
        await tester.tap(find.text('100${_nbsp}m'));
        await asentarLista(tester);
        expect(find.text('Ver 1 ubicación'), findsOneWidget);
        await verUbicaciones(tester);

        expect(find.text('Cerca 1'), findsOneWidget);
        expect(find.text('Lejos 2'), findsNothing);
        expect(chipFiltro('Cerca de mí · 100${_nbsp}m'), findsOneWidget);
      },
    );

    testWidgets('dado «Ciudad», cuando elige una de la campaña, entonces filtra y el chip lleva su '
        'nombre', (tester) async {
      final filas = [
        filaLista('mvd', calle: 'Mvd', numero: '1'),
        filaLista('can', calle: 'Can', numero: '2', ciudadId: 'ciu-can'),
      ];
      await montarLista(tester, repo: RepoListaFalso(filas));
      await abrirHojaFiltros(tester);
      expect(find.text('Todas'), findsOneWidget);

      await tester.tap(find.text('Todas'));
      await asentarLista(tester);
      expect(find.text('Montevideo'), findsOneWidget);
      await tester.tap(find.text('Canelones'));
      await asentarLista(tester);

      expect(find.text('Canelones'), findsOneWidget);
      expect(find.text('Ver 1 ubicación'), findsOneWidget);
      await verUbicaciones(tester);

      expect(find.text('Can 2'), findsOneWidget);
      expect(find.text('Mvd 1'), findsNothing);
      expect(chipFiltro('Canelones'), findsOneWidget);
    });

    testWidgets(
      'dado que no se pueden leer las ciudades, entonces lo dice y «Reintentar» las vuelve '
      'a pedir',
      (tester) async {
        final ciudades = CiudadesFalsas()..fallaCampania = const FailureInesperado();
        await montarLista(tester, repo: RepoListaFalso(_muestra()), ciudades: ciudades);
        await abrirHojaFiltros(tester);

        await tester.tap(find.text('Todas'));
        await asentarLista(tester);
        expect(find.text(TextosListaUbicaciones.reintentar), findsOneWidget);

        ciudades.fallaCampania = null;
        await tester.tap(find.text(TextosListaUbicaciones.reintentar));
        await asentarLista(tester);

        expect(find.text('Montevideo'), findsOneWidget);
        expect(find.text('Canelones'), findsOneWidget);
      },
    );

    testWidgets(
      'dado el puerto de ciudades de hoy, sin adaptador, entonces la hoja avisa en vez de '
      'inventar ciudades',
      (tester) async {
        await montarLista(
          tester,
          repo: RepoListaFalso(_muestra()),
          ciudades: CiudadesParaAltaSinFuente(),
        );
        await abrirHojaFiltros(tester);
        expect(find.text('Todas'), findsOneWidget);

        await tester.tap(find.text('Todas'));
        await asentarLista(tester);

        expect(
          find.text('No pudimos leer las ciudades de tu campaña. Probá de nuevo.'),
          findsOneWidget,
        );
        expect(find.text(TextosListaUbicaciones.reintentar), findsOneWidget);
        expect(find.text('Montevideo'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('dado que no hay ciudades en la campaña, entonces la hoja de ciudades lo dice', (
      tester,
    ) async {
      final ciudades = CiudadesFalsas(campania: const []);
      await montarLista(tester, repo: RepoListaFalso(_muestra()), ciudades: ciudades);
      await abrirHojaFiltros(tester);

      await tester.tap(find.text('Todas'));
      await asentarLista(tester);

      expect(find.textContaining('ciudad'), findsWidgets);
      expect(find.text('Montevideo'), findsNothing);
    });
  });

  group('05B · 02 Orden por cercanía', () {
    final cercanas = [
      filaLista(
        'lejos',
        calle: 'Lejos',
        numero: '1',
        metrosAlNorte: 400,
        hace: const Duration(minutes: 5),
      ),
      filaLista(
        'cerca',
        calle: 'Cerca',
        numero: '2',
        metrosAlNorte: 42,
        hace: const Duration(hours: 9),
      ),
      filaLista(
        'medio',
        calle: 'Medio',
        numero: '3',
        metrosAlNorte: 150,
        hace: const Duration(hours: 3),
      ),
    ];

    testWidgets(
      'dado el GPS, cuando elige «Por cercanía», entonces ordena por distancia y cada fila '
      'muestra los metros en vez de la actualización',
      (tester) async {
        await montarLista(
          tester,
          repo: RepoListaFalso(cercanas),
          gps: GpsFalso(Right(lecturaGps(8))),
        );
        expect(find.text('hace 5 min'), findsOneWidget);

        await tester.tap(botonOrden);
        await asentarLista(tester);
        expect(find.text('Ordenar'), findsOneWidget);
        await tester.tap(find.text('Por cercanía'));
        await asentarLista(tester);

        expect(find.text('Por cercanía ▾'), findsOneWidget);
        expect(find.text('42${_nbsp}m'), findsOneWidget);
        expect(find.text('150${_nbsp}m'), findsOneWidget);
        expect(find.text('400${_nbsp}m'), findsOneWidget);
        expect(find.text('hace 5 min'), findsNothing);
        final alturas = [
          for (final t in ['Cerca 2', 'Medio 3', 'Lejos 1']) tester.getTopLeft(find.text(t)).dy,
        ];
        expect(alturas, [...alturas]..sort());

        await tester.tap(botonOrden);
        await asentarLista(tester);
        await tester.tap(find.text('Última actualización'));
        await asentarLista(tester);

        expect(find.text('Última actualización ▾'), findsOneWidget);
        expect(find.text('hace 5 min'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que no hay GPS, entonces «Por cercanía» está deshabilitada con «Necesita GPS»',
      (tester) async {
        await montarLista(tester, repo: RepoListaFalso(cercanas), gps: gpsFallido());

        await tester.tap(botonOrden);
        await asentarLista(tester);

        expect(find.text('Necesita GPS'), findsOneWidget);
        await tester.tap(find.text('Por cercanía'));
        await asentarLista(tester);

        // La hoja sigue abierta y el orden no cambió.
        expect(find.text('Ordenar'), findsOneWidget);
        await tester.tap(find.text('Última actualización').last);
        await asentarLista(tester);
        expect(find.text('Última actualización ▾'), findsOneWidget);
      },
    );
  });

  group('buscador', () {
    testWidgets('dado texto parcial de calle o número, entonces filtra por substring sin acentos', (
      tester,
    ) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));

      await buscarEnLista(tester, 'RIVAD');
      expect(find.byType(FilaUbicacionLista), findsNWidgets(2));

      await buscarEnLista(tester, 'rivadavia 35');
      expect(find.text('Rivadavia 350'), findsOneWidget);
      expect(find.byType(FilaUbicacionLista), findsOneWidget);

      await buscarEnLista(tester, '2020');
      expect(find.text('Colonia 2020'), findsOneWidget);
      expect(find.text('1 de 3'), findsOneWidget);
    });

    testWidgets('dado que escribe rápido, entonces espera a que pare antes de buscar', (
      tester,
    ) async {
      final repo = RepoListaFalso(_muestra());
      await montarLista(tester, repo: repo);
      final base = repo.suscripciones;

      await tester.enterText(campoBusqueda, 'r');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(campoBusqueda, 'ri');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(campoBusqueda, 'riv');
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.suscripciones, base);

      await tester.pump(const Duration(milliseconds: 300));
      await asentarLista(tester);

      expect(repo.suscripciones, base + 1);
      expect(find.byType(FilaUbicacionLista), findsNWidgets(2));
    });

    testWidgets('dado «Buscar» en el teclado, entonces busca en el acto', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));

      await tester.enterText(campoBusqueda, 'colonia');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await asentarLista(tester);

      expect(find.byType(FilaUbicacionLista), findsOneWidget);
    });

    testWidgets('dado un texto escrito, cuando toca la ✕ del campo, entonces lo borra y vuelve '
        'toda la lista', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));
      await buscarEnLista(tester, 'colonia');
      expect(find.byType(FilaUbicacionLista), findsOneWidget);

      await tester.tap(find.byKey(const Key('lista_busqueda_borrar')));
      await asentarLista(tester);

      expect(find.byType(FilaUbicacionLista), findsNWidgets(3));
      expect(find.byKey(const Key('lista_busqueda_borrar')), findsNothing);
    });

    testWidgets('dado un texto muy largo, entonces no rompe nada', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));

      await buscarEnLista(tester, 'x' * 400);

      expect(tester.takeException(), isNull);
      expect(find.text(TextosListaUbicaciones.sinResultadosTitulo), findsOneWidget);
    });
  });

  group('chips de filtros', () {
    testWidgets(
      'dado varios filtros, entonces cada uno tiene su chip y el botón cuenta cuántos hay',
      (tester) async {
        await montarLista(tester, repo: RepoListaFalso(_muestra()));
        await abrirHojaFiltros(tester);
        await tester.tap(find.text('Casa'));
        await tester.tap(find.text('Edificio'));
        await tester.tap(find.text('Rechazó'));
        await asentarLista(tester);
        await verUbicaciones(tester);

        expect(chipFiltro('Casa'), findsOneWidget);
        expect(chipFiltro('Edificio'), findsOneWidget);
        expect(chipFiltro('Rechazó'), findsOneWidget);
        expect(find.text('3'), findsWidgets);
      },
    );

    testWidgets('dado un chip, cuando toca su ✕, entonces quita solo ese filtro', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_muestra()));
      await abrirHojaFiltros(tester);
      await tester.tap(find.text('Casa'));
      await tester.tap(find.text('Edificio'));
      await asentarLista(tester);
      await verUbicaciones(tester);
      expect(find.byType(FilaUbicacionLista), findsNWidgets(2));

      await tester.tap(chipFiltro('Casa'));
      await asentarLista(tester);

      expect(chipFiltro('Casa'), findsNothing);
      expect(chipFiltro('Edificio'), findsOneWidget);
      expect(find.byType(FilaUbicacionLista), findsOneWidget);
    });

    testWidgets('dado muchos chips, entonces se desplazan sin romper el botón «Filtros»', (
      tester,
    ) async {
      await montarLista(
        tester,
        repo: RepoListaFalso(_muestra()),
        gps: GpsFalso(Right(lecturaGps(8))),
        tamano: const Size(360, 640),
      );
      await abrirHojaFiltros(tester);
      await tester.tap(find.text('Casa'));
      await tester.tap(find.text('Negocio'));
      await tester.tap(find.text('Edificio'));
      await tester.tap(find.text('Entrevista agendada'));
      await tester.tap(find.text('Rechazó'));
      await asentarLista(tester);
      await verUbicaciones(tester);

      expect(tester.takeException(), isNull);
      expect(botonFiltros, findsOneWidget);
    });
  });

  group('GPS', () {
    testWidgets('dado que la pestaña está a la vista, entonces muestra la precisión del GPS', (
      tester,
    ) async {
      await montarLista(
        tester,
        repo: RepoListaFalso(_muestra()),
        gps: GpsFalso(Right(lecturaGps(8))),
      );

      expect(find.text('◎ GPS ±8${_nbsp}m'), findsOneWidget);
    });

    testWidgets('dado que el GPS tarda, entonces dice «Buscando GPS…» y la lista ya se ve', (
      tester,
    ) async {
      final gps = GpsFalso()..bloqueo = Completer<void>();
      await montarLista(tester, repo: RepoListaFalso(_muestra()), gps: gps);

      expect(find.text('◎ Buscando GPS…'), findsOneWidget);
      expect(find.text('Rivadavia 100'), findsOneWidget);

      gps.bloqueo!.complete();
      await asentarLista(tester);

      expect(find.text('◎ GPS ±6${_nbsp}m'), findsOneWidget);
    });

    testWidgets(
      'dado que la pestaña no está a la vista, entonces no pide el GPS hasta que se abre',
      (tester) async {
        final gps = GpsFalso(Right(lecturaGps(7)));
        final activa = ValueNotifier(false);
        addTearDown(activa.dispose);
        await montarLista(
          tester,
          repo: RepoListaFalso(_muestra()),
          gps: gps,
          activaCambiante: activa,
        );
        expect(gps.lecturas, 0);
        expect(find.textContaining('GPS'), findsNothing);
        expect(find.text('Rivadavia 100'), findsOneWidget);

        activa.value = true;
        await asentarLista(tester);

        expect(gps.lecturas, 1);
        expect(find.text('◎ GPS ±7${_nbsp}m'), findsOneWidget);
      },
    );

    testWidgets('dado que vuelve a la pestaña, entonces refresca el GPS; sin permiso no vuelve a '
        'pedirlo en cada apertura', (tester) async {
      final gps = gpsFallido();
      final activa = ValueNotifier(true);
      addTearDown(activa.dispose);
      await montarLista(
        tester,
        repo: RepoListaFalso(_muestra()),
        gps: gps,
        activaCambiante: activa,
      );
      expect(gps.lecturas, 1);

      activa.value = false;
      await asentarLista(tester);
      activa.value = true;
      await asentarLista(tester);

      expect(gps.lecturas, 1);
    });

    testWidgets('dado que sin permiso no hay GPS, entonces la lista funciona, dice «Sin GPS» y '
        'tocarlo pide el permiso', (tester) async {
      final gps = gpsFallido();
      await montarLista(tester, repo: RepoListaFalso(_muestra()), gps: gps);

      expect(find.text('◎ Sin GPS'), findsOneWidget);
      expect(find.text('Rivadavia 100'), findsOneWidget);

      gps.alActivar = () => gps.respuesta = Right(lecturaGps(5));
      await tester.tap(find.text('◎ Sin GPS'));
      await asentarLista(tester);

      expect(gps.activaciones, [MotivoSinGps.permisoDenegado]);
      expect(find.text('◎ GPS ±5${_nbsp}m'), findsOneWidget);
    });

    testWidgets(
      'dado que se vuelve de los ajustes con el permiso dado, entonces el GPS se recupera '
      'solo',
      (tester) async {
        final gps = gpsFallido();
        await montarLista(tester, repo: RepoListaFalso(_muestra()), gps: gps);
        expect(find.text('◎ Sin GPS'), findsOneWidget);

        // Toca «Sin GPS»: lo manda a los ajustes (el fake no cambia nada) y sigue sin GPS.
        await tester.tap(find.text('◎ Sin GPS'));
        await asentarLista(tester);
        expect(gps.activaciones, hasLength(1));
        expect(find.text('◎ Sin GPS'), findsOneWidget);

        gps.respuesta = Right(lecturaGps(9));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await asentarLista(tester);

        expect(find.text('◎ GPS ±9${_nbsp}m'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que el permiso está denegado, cuando vuelve a la app desde otra (sin haber tocado '
      '«Sin GPS»), entonces no lo vuelve a pedir ni muestra el diálogo del permiso',
      (tester) async {
        final gps = gpsFallido();
        await montarLista(tester, repo: RepoListaFalso(_muestra()), gps: gps);
        expect(find.text('◎ Sin GPS'), findsOneWidget);
        final lecturas = gps.lecturas;

        for (var i = 0; i < 3; i++) {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await asentarLista(tester);
        }

        expect(gps.lecturas, lecturas);
        expect(gps.activaciones, isEmpty);
        expect(find.text('◎ Sin GPS'), findsOneWidget);
        expect(find.text('Rivadavia 100'), findsOneWidget);
      },
    );
  });

  group('«+ Nueva»', () {
    testWidgets('dado que hay ubicaciones, entonces el botón «Nueva» abre el alta una sola vez', (
      tester,
    ) async {
      final abierta = Completer<void>();
      var altas = 0;
      await montarLista(
        tester,
        repo: RepoListaFalso(_muestra()),
        alRegistrar: () {
          altas++;
          return abierta.future;
        },
      );

      await tester.tap(botonNueva);
      await tester.tap(botonNueva);
      await tester.pump();
      expect(altas, 1);

      abierta.complete();
      await asentarLista(tester);
      await tester.tap(botonNueva);
      await tester.pump();
      expect(altas, 2);
    });

    testWidgets('dado que se registra una ubicación, cuando vuelve del alta, entonces la lista ya '
        'la trae', (tester) async {
      final repo = RepoListaFalso(_muestra());
      await montarLista(
        tester,
        repo: repo,
        alRegistrar: () async {
          repo.emitir([filaLista('nueva', calle: 'Nueva', numero: '9'), ..._muestra()]);
        },
      );

      await tester.tap(botonNueva);
      await asentarLista(tester);

      expect(find.text('Nueva 9'), findsOneWidget);
      expect(find.text('4 de 4'), findsOneWidget);
    });
  });

  group('tocar una fila', () {
    testWidgets(
      'dado un destino, cuando toca una fila, entonces avisa cuál; una sola vez por toque',
      (tester) async {
        final abiertas = <String>[];
        await montarLista(tester, repo: RepoListaFalso(_muestra()), alAbrir: abiertas.add);

        await tester.tap(find.text('Colonia 2020'));
        await tester.pump();

        expect(abiertas, ['neg-1']);
        expect(find.text('›'), findsNWidgets(3));
      },
    );

    testWidgets(
      'dado que todavía no hay pantalla de destino, entonces las filas no se pueden tocar '
      'ni muestran la «›»',
      (tester) async {
        await montarLista(tester, repo: RepoListaFalso(_muestra()));

        final fila = find.ancestor(
          of: find.text('Colonia 2020'),
          matching: find.byType(FilaUbicacionLista),
        );
        expect(find.descendant(of: fila, matching: find.byType(InkWell)), findsNothing);
        expect(find.text('›'), findsNothing);
        await tester.tap(find.text('Colonia 2020'));
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('listas largas', () {
    testWidgets('dado más de 50, entonces carga de a 50 al llegar al final', (tester) async {
      final repo = RepoListaFalso(_muchas(120));
      await montarLista(tester, repo: repo, tamano: const Size(390, 700));

      expect(find.text('120 de 120'), findsOneWidget);
      expect(find.text('Calle 0 1'), findsOneWidget);

      // La primera página son 50 filas: la 51 no existe hasta que se llega al final.
      expect(find.text('Calle 50 51', skipOffstage: false), findsNothing);
      final lista = find.byKey(const Key('lista_filas'));
      await tester.dragUntilVisible(find.text('Calle 99 100'), lista, const Offset(0, -400));
      await asentarLista(tester);

      // La segunda página llegó (50 más) y, al final de la tercera, ya no hay pie de carga.
      expect(find.text('Calle 99 100'), findsOneWidget);
      await tester.dragUntilVisible(find.text('Calle 119 120'), lista, const Offset(0, -400));
      await asentarLista(tester);
      expect(find.text('Calle 119 120'), findsOneWidget);
      expect(find.text(TextosListaUbicaciones.cargandoMas), findsNothing);
      // Nunca dos suscripciones vivas de la misma pantalla.
      expect(repo.activas, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado que la base emite mientras se está leyendo la mitad, entonces el scroll no '
        'salta', (tester) async {
      final repo = RepoListaFalso(_muchas(40));
      await montarLista(tester, repo: repo, tamano: const Size(390, 700));
      await tester.drag(find.byKey(const Key('lista_filas')), const Offset(0, -900));
      await asentarLista(tester);
      final desplazable = find.descendant(
        of: find.byKey(const Key('lista_filas')),
        matching: find.byType(Scrollable),
      );
      final antes = tester.state<ScrollableState>(desplazable).position.pixels;
      expect(antes, greaterThan(0));
      final suscripcionesAntes = repo.suscripciones;

      repo.emitir([
        filaLista('u-000', calle: 'Cambiada', numero: '1', estado: EstadoCasa.noContesto),
        ..._muchas(40).skip(1),
      ]);
      await asentarLista(tester);

      expect(tester.state<ScrollableState>(desplazable).position.pixels, antes);
      expect(repo.suscripciones, suscripcionesAntes);
    });
  });

  group('volver arriba', () {
    double desplazado(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('lista_filas')),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;

    testWidgets('dado que leyó la mitad de la lista, cuando cambia la búsqueda, entonces vuelve '
        'al principio', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_muchas(40)), tamano: const Size(390, 700));
      await tester.drag(find.byKey(const Key('lista_filas')), const Offset(0, -900));
      await asentarLista(tester);
      expect(desplazado(tester), greaterThan(0));

      // «calle» no saca ninguna fila: sin volver arriba, la lista se quedaría donde estaba.
      await buscarEnLista(tester, 'calle');

      expect(find.text('40 de 40'), findsOneWidget);
      expect(desplazado(tester), 0);
      expect(find.text('Calle 0 1'), findsOneWidget);
    });

    testWidgets('dado que leyó la mitad de la lista, cuando aplica otros filtros, entonces vuelve '
        'al principio', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_muchas(40)), tamano: const Size(390, 700));
      await tester.drag(find.byKey(const Key('lista_filas')), const Offset(0, -900));
      await asentarLista(tester);
      expect(desplazado(tester), greaterThan(0));

      await abrirHojaFiltros(tester);
      await tester.tap(find.text('Casa'));
      await asentarLista(tester);
      await verUbicaciones(tester);

      expect(chipFiltro('Casa'), findsOneWidget);
      expect(desplazado(tester), 0);
    });

    testWidgets('dado que leyó la mitad de la lista, cuando cambia el orden, entonces se queda '
        'donde estaba', (tester) async {
      await montarLista(
        tester,
        repo: RepoListaFalso(_muchas(40)),
        gps: GpsFalso(Right(lecturaGps(8))),
        tamano: const Size(390, 700),
      );
      await tester.drag(find.byKey(const Key('lista_filas')), const Offset(0, -900));
      await asentarLista(tester);
      final antes = desplazado(tester);
      expect(antes, greaterThan(0));

      await tester.tap(botonOrden);
      await asentarLista(tester);
      await tester.tap(find.text('Por cercanía'));
      await asentarLista(tester);

      expect(find.text('Por cercanía ▾'), findsOneWidget);
      expect(desplazado(tester), greaterThan(0));
    });

    testWidgets('dado que llega al final de las primeras 50, cuando se cargan 50 más, entonces no '
        'vuelve al principio', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_muchas(120)), tamano: const Size(390, 700));

      // Se baja de a poco hasta que aparece la fila 56 (de la segunda página): en ningún paso la
      // lista puede haber vuelto arriba.
      final lista = find.byKey(const Key('lista_filas'));
      var previo = 0.0;
      for (var i = 0; i < 40; i++) {
        if (find.text('Calle 55 56', skipOffstage: false).evaluate().isNotEmpty) break;
        await tester.drag(lista, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 60));
        final ahora = desplazado(tester);
        expect(ahora, greaterThanOrEqualTo(previo), reason: 'paso $i');
        previo = ahora;
      }

      expect(find.text('Calle 55 56', skipOffstage: false), findsOneWidget);
      expect(previo, greaterThan(1500));
    });
  });

  group('volver atrás y reentrar', () {
    testWidgets('dado que sale de la pestaña y vuelve a entrar, entonces ve la lista con una sola '
        'suscripción viva', (tester) async {
      final repo = RepoListaFalso(_muestra());
      await montarLista(tester, repo: repo);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(repo.activas, 0);

      await montarLista(tester, repo: repo);

      expect(find.text('Rivadavia 100'), findsOneWidget);
      expect(repo.activas, 1);
    });

    testWidgets(
      'dado que otra pantalla se abre encima y se cierra, entonces la lista sigue igual',
      (tester) async {
        final repo = RepoListaFalso(_muestra());
        await montarLista(tester, repo: repo);
        await buscarEnLista(tester, 'colonia');

        final navegador = tester.state<NavigatorState>(find.byType(Navigator));
        unawaited(
          navegador.push(
            MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('otra'))),
          ),
        );
        await asentarLista(tester);
        navegador.pop();
        await asentarLista(tester);

        expect(find.byType(FilaUbicacionLista), findsOneWidget);
        expect(tester.widget<TextField>(campoBusqueda).controller!.text, 'colonia');
      },
    );
  });
}

/// El GPS sin permiso.
GpsFalso gpsFallido() =>
    GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado)));
