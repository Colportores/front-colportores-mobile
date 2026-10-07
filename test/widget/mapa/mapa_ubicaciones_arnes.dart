// Arnés de los tests del mapa de ubicaciones (vista 06): monta la pestaña «Mapa» con los fakes de
// la lista (`lista_ubicaciones_falsos.dart`), la vista nativa falsa de `MapaBase` y un alta que no
// abre pantalla, y deja a mano las búsquedas más usadas.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/mapa_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_ubicaciones_notifier.dart'
    show mapaUbicacionesProvider;
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_ubicaciones_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/situacion_mapa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
import '../../helpers/mapa_descargas_arnes.dart';
import 'lista_ubicaciones_arnes.dart' show asentarLista;

export '../../helpers/mapa_base_falso.dart' show FabricaMapaFalsa;
export 'lista_ubicaciones_arnes.dart' show asentarLista;

/// Lo que un test del mapa de ubicaciones necesita después de montarlo.
final class MontajeMapaUbicaciones {
  MontajeMapaUbicaciones({
    required this.repo,
    required this.gps,
    required this.mapa,
    required this.activa,
  });

  final RepoListaFalso repo;
  final GpsFalso gps;
  final FabricaMapaFalsa mapa;

  /// Si la pestaña está a la vista: cambiarlo es cambiar de pestaña y volver.
  final ValueNotifier<bool> activa;

  /// El punto de cada alta que se abrió (`null` si fue desde «Nueva», no desde el mapa).
  final altas = <Coordenadas?>[];

  /// Qué devuelve el alta al cerrarse. Con [esperaAlta] se queda abierta hasta completarla.
  SalidaAltaUbicacion? salidaAlta;
  Completer<SalidaAltaUbicacion?>? esperaAlta;

  /// Si no es `null`, abrir el alta lanza esto.
  Object? fallaAlta;

  Future<SalidaAltaUbicacion?> abrirAlta(Coordenadas? punto) async {
    altas.add(punto);
    final falla = fallaAlta;
    if (falla != null) throw falla;
    final espera = esperaAlta;
    if (espera != null) return espera.future;
    return salidaAlta;
  }
}

/// Monta la pestaña «Mapa» como la ve el colportor `col-1`, sobre Uruguay (sin ciudad conocida).
///
/// [activa] `false` la deja montada pero fuera de vista (como las demás pestañas del
/// `IndexedStack`). Con [arnes] el aviso sale de la conexión y del catálogo reales del arnés del
/// aviso; sin él, el mapa no tiene tiles ni aviso ([situacion] lo cambia). [ambito] es la ciudad del
/// mapa, fija (por defecto ninguna, como hoy: #274); con [ciudades] la ciudad sale, como en la app,
/// del puerto `CiudadesParaAlta` (y [ambito] no cuenta).
Future<MontajeMapaUbicaciones> montarMapaUbicaciones(
  WidgetTester tester, {
  RepoListaFalso? repo,
  GpsFalso? gps,
  FabricaMapaFalsa? mapa,
  SituacionMapa? situacion,
  ArnesMapa? arnes,
  AmbitoTrabajo? ambito,
  CiudadesFalsas? ciudades,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool activa = true,
  SalidaAltaUbicacion? salidaAlta,
  bool asentar = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final montaje = MontajeMapaUbicaciones(
    repo: repo ?? RepoListaFalso(),
    gps: gps ?? GpsFalso(),
    mapa: mapa ?? FabricaMapaFalsa(),
    activa: ValueNotifier(activa),
  )..salidaAlta = salidaAlta;
  if (arnes != null) addTearDown(() => unawaited(arnes.cerrar()));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...overridesLista(repo: montaje.repo, gps: montaje.gps, ciudades: ciudades),
        montaje.mapa.override,
        if (arnes != null)
          ...arnes.overrides
        else
          situacionMapaProvider.overrideWith(
            (ref, _) => situacion ?? const SituacionMapa(fuente: FuenteMapa.sinTiles()),
          ),
        if (ciudades == null)
          ambitoMapaUbicacionesProvider.overrideWith2(
            (_) => AmbitoFijo(ambito ?? const AmbitoTrabajo()),
          ),
      ],
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
            valueListenable: montaje.activa,
            builder: (context, estaActiva, _) => MapaUbicacionesPage(
              key: const Key('pestana_mapa'),
              colportorId: 'col-1',
              activa: estaActiva,
              alAbrirAlta: montaje.abrirAlta,
            ),
          ),
        ),
      ),
    ),
  );
  if (asentar) await asentarLista(tester);
  return montaje;
}

final hoja = find.byKey(ClavesMapaUbicaciones.hoja);
final asa = find.byKey(ClavesMapaUbicaciones.asa);
final botonMiUbicacion = find.byKey(ClavesMapaUbicaciones.miUbicacion);
final botonNueva = find.byKey(ClavesMapaUbicaciones.nueva);
final chipReferencias = find.byKey(ClavesMapaUbicaciones.referencias);
final vistaPrevia = find.byKey(ClavesMapaUbicaciones.vistaPrevia);
final cerrarVistaPrevia = find.byKey(ClavesMapaUbicaciones.cerrarVistaPrevia);
final hojaReferencias = find.byKey(ClavesMapaUbicaciones.hojaReferencias);
Finder fila(String id) => find.byKey(ClavesMapaUbicaciones.fila(id));

/// El alto de la hoja del mapa, para saber en qué altura está.
double altoHoja(WidgetTester tester) => tester.getSize(hoja).height;

/// Toca el asa [veces] veces seguidas, dejando correr la animación de la hoja entre toques.
Future<void> tocarAsa(WidgetTester tester, [int veces = 1]) async {
  for (var i = 0; i < veces; i++) {
    await tester.tap(asa);
    await asentarLista(tester, 6);
  }
}

/// El punto del mapa [id] según la última configuración de la vista falsa.
PuntoMapa punto(FabricaMapaFalsa mapa, String id) =>
    mapa.config!.puntos.firstWhere((p) => p.id == id);

/// ¿Está el punto [id] en el mapa?
bool hayPunto(FabricaMapaFalsa mapa, String id) => mapa.config!.puntos.any((p) => p.id == id);

/// Cuántos dp más abajo de [punto] cae el centro de la cámara de [mapa]. El mapa se centra en un
/// punto de modo que quede a la vista, en lo que la hoja deja libre: el centro de la vista queda
/// medio alto de hoja más abajo que el punto (0 si el mapa se centró en el punto mismo).
double dpBajoElPunto(FabricaMapaFalsa mapa, Coordenadas punto) {
  final camara = mapa.camara!;
  final centro = ProyeccionMercator.aPixeles(camara.centro, camara.zoom);
  final buscado = ProyeccionMercator.aPixeles(punto, camara.zoom);
  return centro.y - buscado.y;
}

/// Lo mismo, hacia el costado: cuántos dp a la derecha del punto cae el centro de la cámara.
double dpALaDerechaDelPunto(FabricaMapaFalsa mapa, Coordenadas punto) {
  final camara = mapa.camara!;
  final centro = ProyeccionMercator.aPixeles(camara.centro, camara.zoom);
  final buscado = ProyeccionMercator.aPixeles(punto, camara.zoom);
  return centro.x - buscado.x;
}

/// El contenedor de providers de la pestaña montada.
ProviderContainer contenedorDeLaPestana(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byKey(const Key('pestana_mapa'))));

/// La ubicación elegida del mapa (`null` si no hay ninguna), según el estado de la pestaña: es lo que
/// pinta la vista previa y el aro del marcador.
String? seleccionadaId(WidgetTester tester) =>
    contenedorDeLaPestana(tester).read(mapaUbicacionesProvider('col-1')).seleccionadaId;
