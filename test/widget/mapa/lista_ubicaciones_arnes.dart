// Arnés de los tests de la lista de ubicaciones (vista 05): monta la pestaña con los fakes de
// `lista_ubicaciones_falsos.dart` y deja a mano las búsquedas más usadas.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';

/// Deja correr los fotogramas que hacen falta (la base emite en el turno siguiente y las hojas se
/// animan) sin esperar a los indicadores que giran para siempre.
Future<void> asentarLista(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Monta la pestaña «Lista» como la ve el colportor `col-1`.
///
/// [activa] `false` la deja montada pero fuera de vista (como las demás pestañas del
/// `IndexedStack`); [activaCambiante] la va cambiando durante el test. [escala] es el `textScaler`.
Future<void> montarLista(
  WidgetTester tester, {
  RepoListaFalso? repo,
  GpsFalso? gps,
  CiudadesParaAlta? ciudades,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool activa = true,
  ValueNotifier<bool>? activaCambiante,
  ValueChanged<String>? alAbrir,
  Future<void> Function()? alRegistrar,
  Key? clave,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesLista(repo: repo ?? RepoListaFalso(), gps: gps, ciudades: ciudades),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: activaCambiante ?? ValueNotifier(activa),
            builder: (context, estaActiva, _) => ListaUbicacionesPage(
              key: clave,
              colportorId: 'col-1',
              activa: estaActiva,
              alAbrirUbicacion: alAbrir,
              alRegistrar: alRegistrar,
            ),
          ),
        ),
      ),
    ),
  );
  await asentarLista(tester);
}

final botonFiltros = find.text('☷ Filtros');
final botonNueva = find.byKey(const Key('lista_nueva'));
final botonOrden = find.byKey(const Key('lista_orden'));
final campoBusqueda = find.byKey(const Key('lista_busqueda'));
final botonVerUbicaciones = find.byKey(const Key('hoja_filtros_ver'));

/// El chip de un filtro activo, por su texto.
Finder chipFiltro(String texto) => find.widgetWithText(ChipFiltroLista, texto);

/// Escribe en el buscador y deja pasar la espera de 250 ms.
Future<void> buscarEnLista(WidgetTester tester, String texto) async {
  await tester.enterText(campoBusqueda, texto);
  await tester.pump(const Duration(milliseconds: 300));
  await asentarLista(tester);
}

/// Abre la hoja de filtros.
Future<void> abrirHojaFiltros(WidgetTester tester) async {
  await tester.tap(botonFiltros);
  await asentarLista(tester);
}

/// En la hoja de filtros: toca «Ver N ubicaciones».
Future<void> verUbicaciones(WidgetTester tester) async {
  await tester.tap(botonVerUbicaciones);
  await asentarLista(tester);
}
