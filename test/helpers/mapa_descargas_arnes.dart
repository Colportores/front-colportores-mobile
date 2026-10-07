// Arnés de los tests del aviso del mapa (#190): el descargador de paquetes REAL, armado con los
// puertos falsos de `tiles_falsos.dart` (sin red, disco ni HTTP), y lo que el aviso necesita de la
// app (la conexión, el catálogo, los ajustes del sistema).
//
// Nada de esto toca el bucket `mapas`: el catálogo es una lista en memoria con paquetes de ejemplo
// (la publicación real es manual, jueves 08/10).
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/dispositivo/abridor_ajustes_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_ubicaciones_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/descargador_paquetes_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:colportores_mobile/features/tiles/presentation/providers/tiles_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'tiles_falsos.dart';

/// Montevideo: la ciudad `c-1` de los paquetes de prueba (`paqueteDe` / `paqueteEnPartes`).
const ambitoMontevideo = AmbitoTrabajo(ciudadId: 'c-1');

/// La ciudad del mapa de la vista 06 fija (sin preguntarle al puerto de ciudades): los tests del
/// aviso y de la hoja no dependen de cómo se averigua. Va como
/// `ambitoMapaUbicacionesProvider.overrideWith2((_) => AmbitoFijo(ambito))`; sin ciudad,
/// `AmbitoFijo(const AmbitoTrabajo())`.
final class AmbitoFijo extends AmbitoMapaUbicacionesNotifier {
  AmbitoFijo(this._ambito) : super('col-1');

  final AmbitoTrabajo _ambito;

  @override
  AmbitoTrabajo build() => _ambito;
}

/// Los bytes del paquete de ejemplo: chico, para que la descarga entera corra en el test. Pesa 1 MB
/// redondeado para arriba, así que el botón dice «Descargar mapa · 1 MB».
final bytesDelMapa = bytesDePrueba(5500);

/// El mismo paquete de Montevideo, como lo trae el catálogo.
final paqueteMontevideo = paqueteDe(
  bytesDelMapa,
  id: 'ciudad-montevideo',
  nivel: NivelCobertura.ciudad,
  ambitoId: 'c-1',
);

/// Un paquete de la ciudad que pesa [bytes] (no se descarga: solo sirve para el peso del botón).
PaqueteTiles paquetePesado(int bytes) => PaqueteTiles(
  id: 'ciudad-montevideo',
  nivel: NivelCobertura.ciudad,
  ambitoId: 'c-1',
  version: 'v-pesado',
  partes: [
    ParteTiles(
      origen: Uri.parse('https://tiles.test/ciudad-montevideo.pmtiles'),
      tamanoBytes: bytes,
      sha256: 'a' * 64,
    ),
  ],
);

/// Un paquete de otra ciudad: el catálogo no trae el de Montevideo.
final paqueteCanelones = paqueteDe(
  bytesDePrueba(3000, semilla: 9),
  id: 'ciudad-canelones',
  nivel: NivelCobertura.ciudad,
  ambitoId: 'c-2',
);

/// El abridor de ajustes: cuántas veces abrió la red, y una espera para probar el doble toque.
final class AjustesRedFalsos implements AbridorAjustesSistema {
  int aperturasDeRed = 0;
  bool resultado = true;
  bool lanza = false;
  Completer<void>? espera;

  @override
  Future<bool> abrirRed() async {
    aperturasDeRed++;
    await espera?.future;
    if (lanza) throw StateError('el abridor falló');
    return resultado;
  }

  @override
  Future<bool> abrirSeguridad() async => true;

  @override
  Future<bool> abrirAlmacenamiento() async => true;
}

/// La conectividad falsa, contando cuántas veces se lee la conexión (cada `descargar` la lee una
/// vez al prepararse).
final class ConectividadContada implements MonitorConectividad {
  final _base = ConectividadFalsa();
  int lecturas = 0;

  set tipo(TipoConexion nuevo) => _base.tipo = nuevo;

  void cambiarA(TipoConexion nueva) => _base.cambiarA(nueva);

  @override
  Future<TipoConexion> actual() {
    lecturas++;
    return _base.actual();
  }

  @override
  Stream<TipoConexion> get cambios => _base.cambios;
}

/// Todo lo que el aviso del mapa lee de la app, con un descargador real sobre fakes.
final class ArnesMapa {
  ArnesMapa({
    TipoConexion conexion = TipoConexion.wifi,
    List<PaqueteTiles>? catalogo,
    bool servirPaqueteMontevideo = true,
  }) {
    conectividad.tipo = conexion;
    repositorio.paquetesCatalogo = [...?catalogo];
    if (servirPaqueteMontevideo) servidor.archivos[paqueteMontevideo.origen] = bytesDelMapa;
    descargador = DescargadorPaquetesTiles(
      conectividad: conectividad,
      espacio: espacio,
      cliente: servidor,
      archivos: archivos,
      checksum: ChecksumFalso(archivos),
      repository: repositorio,
    );
  }

  final conectividad = ConectividadContada();
  final espacio = EspacioFalso();
  // Bajo `testWidgets` (FakeAsync) el cancelado del cuerpo no vuelve si no es de la zona actual.
  final servidor = ServidorFalso()..cancelaEnLaZonaActual = true;
  final archivos = ArchivosEnMemoria();
  final repositorio = RepositorioTilesEnMemoria();
  final ajustes = AjustesRedFalsos();
  late final DescargadorPaquetesTiles descargador;

  /// Lo que se registró como descargado: el paquete de Montevideo cuando la descarga terminó.
  bool get montevideoDescargado => repositorio.registrados.any((p) => p.id == 'ciudad-montevideo');

  List<Override> get overrides => [
    monitorConectividadProvider.overrideWithValue(conectividad),
    paquetesTilesRepositoryProvider.overrideWithValue(repositorio),
    descargadorPaquetesTilesProvider.overrideWithValue(descargador),
    abridorAjustesSistemaProvider.overrideWithValue(ajustes),
  ];

  Future<void> cerrar() => descargador.cerrar();
}

/// El montaje: el arnés y un interruptor para sacar el aviso del árbol y volver a ponerlo («volver
/// atrás y reentrar»); el estado de la sesión vive en el `ProviderScope`, no en el aviso.
final class MontajeAviso {
  MontajeAviso(this.arnes);

  final ArnesMapa arnes;
  final abierto = ValueNotifier<bool>(true);

  /// Cuántos toques llegaron al mapa de abajo (los que el aviso no se quedó).
  int toquesAlMapa = 0;
}

class _EscenaAviso extends StatelessWidget {
  const _EscenaAviso(this.ambito, this.modo, this.alTocarMapa);

  final AmbitoTrabajo ambito;
  final AvisoMapaModo modo;
  final VoidCallback alTocarMapa;

  @override
  Widget build(BuildContext context) {
    final aviso = AvisoMapaConectado(ambito: ambito, modo: modo);
    if (modo == AvisoMapaModo.flotante) {
      return Stack(
        children: [
          Positioned.fill(
            // Con nombre: la guía de nombres no acepta un fondo tocable sin él.
            child: Semantics(
              label: 'Mapa',
              container: true,
              child: GestureDetector(
                onTap: alTocarMapa,
                child: const ColoredBox(color: ColoresAlta.fondoMapa),
              ),
            ),
          ),
          aviso,
        ],
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [aviso]),
    );
  }
}

Future<void> asentarAviso(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<MontajeAviso> montarAviso(
  WidgetTester tester, {
  TipoConexion conexion = TipoConexion.wifi,
  List<PaqueteTiles>? catalogo,
  AmbitoTrabajo ambito = ambitoMontevideo,
  AvisoMapaModo modo = AvisoMapaModo.flotante,
  Size tamano = const Size(390, 844),
  double escala = 1,
  ArnesMapa? arnes,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final propio = arnes ?? ArnesMapa(conexion: conexion, catalogo: catalogo);
  addTearDown(() => unawaited(propio.cerrar()));
  final montaje = MontajeAviso(propio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: propio.overrides,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: montaje.abierto,
            builder: (_, abierto, _) => abierto
                ? _EscenaAviso(ambito, modo, () => montaje.toquesAlMapa++)
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
  await asentarAviso(tester);
  return montaje;
}

Future<void> tocarAviso(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await asentarAviso(tester);
}

Future<void> salirYReentrarAviso(WidgetTester tester, MontajeAviso montaje) async {
  montaje.abierto.value = false;
  await asentarAviso(tester);
  montaje.abierto.value = true;
  await asentarAviso(tester);
}
