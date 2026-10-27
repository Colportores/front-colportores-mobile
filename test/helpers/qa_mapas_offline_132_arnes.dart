// Arnés de los tests de QA de «Mapas offline» (vista 35, HU-SYNC-010, #132): llega a cada artboard de
// la vista y saca capturas PNG a `.dart_tool/qa_capturas/` (gitignored: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/inscripciones_con_zona_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/zonas_avisadas_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/inscripcion_con_zona.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/avisos_zona_providers.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/lugar_de_trabajo.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/fuente_lugar_de_trabajo.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:colportores_mobile/features/tiles/presentation/pages/mapas_offline_page.dart';
import 'package:colportores_mobile/features/tiles/presentation/providers/mapas_offline_providers.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/logger_mudo.dart';
import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;
import '../helpers/mapa_descargas_arnes.dart';
import '../helpers/tiles_falsos.dart';

const qaChico = Size(360, 640);
const qaGrande = Size(412, 915);
final qaCapturas = Platform.environment['QA_CAPTURAS'] == '1';
final qaRaiz = GlobalKey();

final class QaFuenteFalsa implements FuenteLugarDeTrabajo {
  QaFuenteFalsa(this.resultado);

  Either<Failure, LugarDeTrabajo> resultado;

  @override
  Future<Either<Failure, LugarDeTrabajo>> leer() async => resultado;
}

const qaConZona = LugarDeTrabajo(
  ambito: AmbitoTrabajo(zonaId: 'z-1', ciudadId: 'c-1', departamentoId: 'd-1'),
  zonaNombre: 'Cerro Norte',
  ciudadNombre: 'Montevideo',
);
const qaSinZona = LugarDeTrabajo(
  ambito: AmbitoTrabajo(ciudadId: 'c-1', departamentoId: 'd-1'),
  ciudadNombre: 'Montevideo',
);

PaqueteTiles qaPaquete(
  String id,
  NivelCobertura nivel,
  String? ambitoId,
  String nombre,
  int megas, {
  String version = 'v1',
}) => PaqueteTiles(
  id: id,
  nivel: nivel,
  ambitoId: ambitoId,
  nombre: nombre,
  version: version,
  partes: [
    ParteTiles(
      origen: Uri.parse('https://tiles.test/$id.pmtiles'),
      tamanoBytes: megas * 1000 * 1000,
      sha256: 'a' * 64,
    ),
  ],
);

final qaCiudad86 = qaPaquete('ciudad-montevideo', NivelCobertura.ciudad, 'c-1', 'Montevideo', 86);
final qaZona14 = qaPaquete('zona-cerro-norte', NivelCobertura.zona, 'z-1', 'Cerro Norte', 14);
final qaBytes = bytesDePrueba(5500);
final qaCiudadReal = paqueteDe(
  qaBytes,
  id: 'ciudad-montevideo',
  nivel: NivelCobertura.ciudad,
  ambitoId: 'c-1',
);

Future<void> qaAsentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> qaCargarFuentes(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(iconos.readAsBytesSync().buffer)));
        await cargador.load();
        break;
      }
    }
  });
}

Future<void> qaCapturar(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(qaRaiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/132_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

final class QaMontaje {
  QaMontaje(this.arnes, this.fuente);

  final ArnesMapa arnes;
  final QaFuenteFalsa fuente;
}

Future<QaMontaje> qaMontar(
  WidgetTester tester, {
  Either<Failure, LugarDeTrabajo> lugar = const Right(qaConZona),
  List<PaqueteTiles> catalogo = const [],
  TipoConexion conexion = TipoConexion.wifi,
  int libres = 2100 * 1000 * 1000,
  double escala = 1,
  Size tamano = qaChico,
  ArnesMapa? arnes,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final propio =
      arnes ?? ArnesMapa(conexion: conexion, catalogo: catalogo, servirPaqueteMontevideo: false);
  addTearDown(() => unawaited(propio.cerrar()));
  final espacio = EspacioFalso()..libres = libres;
  final fuente = QaFuenteFalsa(lugar);
  await tester.pumpWidget(
    RepaintBoundary(
      key: qaRaiz,
      child: ProviderScope(
        overrides: [
          ...propio.overrides,
          fuenteLugarDeTrabajoProvider.overrideWithValue(fuente),
          medidorEspacioDiscoProvider.overrideWithValue(espacio),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: const MapasOfflinePage(),
        ),
      ),
    ),
  );
  await qaAsentar(tester);
  return QaMontaje(propio, fuente);
}

Finder qaClave(String clave) => find.byKey(Key(clave));

/// Toca [clave] bajando la lista hasta que se vea (a textScaler 2.0 queda fuera de pantalla).
Future<void> qaTocar(WidgetTester tester, String clave) async {
  final f = qaClave(clave);
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await qaAsentar(tester);
}

/// Los artboards de la vista 35 (más los estados que el canvas no dibuja) que son la pantalla.
enum QaEstado { e01, e02, e03, e04, e05, e06, e07, e08, e09, sinCatalogo, sinLugar, fallaDescarga }

Future<void> qaLlegar(
  WidgetTester tester,
  QaEstado estado, {
  Size tamano = qaChico,
  double escala = 1,
  // Las guías de contraste miden píxeles: con la fuente real y 1 px por píxel lógico el suavizado de
  // los trazos finos da falsos rojos (1,3:1 sobre texto que se lee bien), así que ahí se usa la
  // fuente de prueba (bloques llenos). Los desbordes y las capturas, en cambio, piden la real.
  bool fuentes = false,
}) async {
  if (fuentes) await qaCargarFuentes(tester);
  ArnesMapa conBytes() => ArnesMapa(catalogo: [qaCiudadReal], servirPaqueteMontevideo: false)
    ..servidor.archivos[qaCiudadReal.origen] = qaBytes
    ..servidor.retenerDespuesDe = 2000;
  switch (estado) {
    case QaEstado.e01:
      await qaMontar(tester, catalogo: [qaCiudad86, qaZona14], tamano: tamano, escala: escala);
    case QaEstado.e02:
      await qaMontar(
        tester,
        catalogo: [qaCiudad86, qaZona14],
        conexion: TipoConexion.datosMoviles,
        tamano: tamano,
        escala: escala,
      );
    case QaEstado.e03:
      await qaMontar(
        tester,
        catalogo: [qaCiudad86],
        lugar: const Right(qaSinZona),
        tamano: tamano,
        escala: escala,
      );
    case QaEstado.e04:
      await qaMontar(
        tester,
        catalogo: [qaCiudad86, qaZona14],
        libres: 40 * 1000 * 1000,
        tamano: tamano,
        escala: escala,
      );
      await qaTocar(tester, 'mapas_offline_nivel_ciudad');
    case QaEstado.e05:
      await qaMontar(
        tester,
        arnes: conBytes(),
        lugar: const Right(qaSinZona),
        tamano: tamano,
        escala: escala,
      );
      await tester.tap(qaClave('mapas_offline_descargar'));
      await qaAsentar(tester);
    case QaEstado.e06:
      final arnes = conBytes();
      await qaMontar(
        tester,
        arnes: arnes,
        lugar: const Right(qaSinZona),
        tamano: tamano,
        escala: escala,
      );
      await tester.tap(qaClave('mapas_offline_descargar'));
      await qaAsentar(tester);
      arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
      await qaAsentar(tester);
    case QaEstado.e07:
      final arnes = ArnesMapa(catalogo: [qaCiudad86], servirPaqueteMontevideo: false);
      await arnes.repositorio.registrar(descargadoDe(qaCiudad86));
      await qaMontar(tester, arnes: arnes, tamano: tamano, escala: escala);
    case QaEstado.e08:
      final nueva = qaPaquete(
        'ciudad-montevideo',
        NivelCobertura.ciudad,
        'c-1',
        'Montevideo',
        12,
        version: 'v2',
      );
      final arnes = ArnesMapa(catalogo: [nueva], servirPaqueteMontevideo: false);
      await arnes.repositorio.registrar(descargadoDe(qaCiudad86));
      await qaMontar(tester, arnes: arnes, tamano: tamano, escala: escala);
    case QaEstado.e09:
      final arnes = ArnesMapa(catalogo: [qaCiudad86, qaZona14], servirPaqueteMontevideo: false);
      await arnes.repositorio.registrar(descargadoDe(qaCiudad86));
      await qaMontar(tester, arnes: arnes, tamano: tamano, escala: escala);
      await qaTocar(tester, 'mapas_offline_cambiar_cobertura');
      await qaTocar(tester, 'mapas_offline_nivel_zona');
      await qaTocar(tester, 'mapas_offline_descargar');
    case QaEstado.sinCatalogo:
      final arnes = ArnesMapa(servirPaqueteMontevideo: false)
        ..repositorio.falloCatalogo = const FailureSinConexion();
      await qaMontar(tester, arnes: arnes, tamano: tamano, escala: escala);
    case QaEstado.sinLugar:
      await qaMontar(
        tester,
        lugar: const Left(FailureLugarDeTrabajoNoDisponible()),
        catalogo: [qaCiudad86],
        tamano: tamano,
        escala: escala,
      );
    case QaEstado.fallaDescarga:
      final arnes = ArnesMapa(catalogo: [qaCiudadReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[qaCiudadReal.origen] = qaBytes
        ..servidor.statusError = 500;
      await qaMontar(
        tester,
        arnes: arnes,
        lugar: const Right(qaSinZona),
        tamano: tamano,
        escala: escala,
      );
      await tester.tap(qaClave('mapas_offline_descargar'));
      await qaAsentar(tester);
  }
}

double qaContraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

Future<void> qaGuias(WidgetTester tester) async {
  final semantica = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  semantica.dispose();
}

// --- 35-10: la hoja de la sugerencia, sobre «Hoy» ------------------------------------------------

final qaAhora = DateTime(2026, 10, 9, 9, 30);
final qaSesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class QaBackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

const qaLugarNorte = LugarDeTrabajo(
  ambito: AmbitoTrabajo(zonaId: 'z-norte', ciudadId: 'c-1', departamentoId: 'd-1'),
  zonaNombre: 'Cerro Norte',
  ciudadNombre: 'Montevideo',
);
const qaInscripcion = InscripcionConZona(
  id: 'insc-1',
  campaniaId: 'camp-1',
  campaniaNombre: 'Campaña Primavera 2026',
  zonaId: 'z-norte',
  zonaNombre: 'Cerro Norte',
);

Future<ArnesMapa> qaMontarSugerencia(
  WidgetTester tester, {
  Size tamano = qaChico,
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final bytesZona = bytesDePrueba(3000, semilla: 9);
  final zona = paqueteDe(bytesZona, id: 'zona-cerro-norte', ambitoId: 'z-norte');
  final arnes = ArnesMapa(catalogo: [zona], servirPaqueteMontevideo: false)
    ..servidor.archivos[zona.origen] = bytesZona;
  addTearDown(() => unawaited(arnes.cerrar()));
  final inscripciones = InscripcionesConZonaEnMemoria()..publicar([qaInscripcion]);
  final almacen = AlmacenSeguroEnMemoria();
  await tester.pumpWidget(
    RepaintBoundary(
      key: qaRaiz,
      child: ProviderScope(
        overrides: [
          ...arnes.overrides,
          fuenteLugarDeTrabajoProvider.overrideWithValue(QaFuenteFalsa(const Right(qaLugarNorte))),
          medidorEspacioDiscoProvider.overrideWithValue(
            EspacioFalso()..libres = 1000 * 1000 * 1000,
          ),
          inscripcionesConZonaDataSourceProvider.overrideWithValue(inscripciones),
          zonasAvisadasRepositoryProvider.overrideWithValue(
            ZonasAvisadasRepositoryImpl(almacen, logger: loggerMudo()),
          ),
          jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
          disparadorBackupProvider.overrideWithValue(QaBackupFalso()),
          relojJornadaProvider.overrideWithValue(() => qaAhora),
          ...overridesPestanaMapa(),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: InicioPage(sesion: qaSesion),
        ),
      ),
    ),
  );
  await qaAsentar(tester);
  return arnes;
}
