// «Mapas offline» (vista 35, HU-SYNC-010, #132): las diez pantallas del canvas y sus casos límite,
// con el descargador REAL sobre los puertos falsos (sin red, disco ni HTTP).
import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/lugar_de_trabajo.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/fuente_lugar_de_trabajo.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:colportores_mobile/features/tiles/presentation/pages/mapas_offline_page.dart';
import 'package:colportores_mobile/features/tiles/presentation/providers/mapas_offline_providers.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mapa_descargas_arnes.dart';
import '../helpers/tiles_falsos.dart';

final class _FuenteFalsa implements FuenteLugarDeTrabajo {
  _FuenteFalsa(this.resultado);

  Either<Failure, LugarDeTrabajo> resultado;
  int lecturas = 0;

  @override
  Future<Either<Failure, LugarDeTrabajo>> leer() async {
    lecturas++;
    return resultado;
  }
}

const _conZona = LugarDeTrabajo(
  ambito: AmbitoTrabajo(zonaId: 'z-1', ciudadId: 'c-1', departamentoId: 'd-1'),
  zonaNombre: 'Cerro Norte',
  ciudadNombre: 'Montevideo',
);
const _sinZona = LugarDeTrabajo(
  ambito: AmbitoTrabajo(ciudadId: 'c-1', departamentoId: 'd-1'),
  ciudadNombre: 'Montevideo',
);

/// Un paquete sin bytes reales (solo se muestra, no se baja): pesa [megas] MB.
PaqueteTiles _paquete(
  String id,
  NivelCobertura nivel,
  String? ambitoId,
  String nombre,
  int megas, {
  String version = 'v1',
}) {
  return PaqueteTiles(
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
}

final _ciudad86 = _paquete('ciudad-montevideo', NivelCobertura.ciudad, 'c-1', 'Montevideo', 86);
final _zona14 = _paquete('zona-cerro-norte', NivelCobertura.zona, 'z-1', 'Cerro Norte', 14);

/// Montevideo con bytes de verdad, para las pruebas que bajan el archivo.
final _bytes = bytesDePrueba(5500);
final _ciudadReal = paqueteDe(
  _bytes,
  id: 'ciudad-montevideo',
  nivel: NivelCobertura.ciudad,
  ambitoId: 'c-1',
);

final class _Montaje {
  _Montaje(this.arnes, this.fuente, this.espacio);

  final ArnesMapa arnes;
  final _FuenteFalsa fuente;
  final EspacioFalso espacio;
  final abierto = ValueNotifier<bool>(true);

  ProviderContainer contenedor(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MapasOfflinePage)));
}

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_Montaje> _montar(
  WidgetTester tester, {
  Either<Failure, LugarDeTrabajo> lugar = const Right(_conZona),
  List<PaqueteTiles> catalogo = const [],
  TipoConexion conexion = TipoConexion.wifi,
  int libres = 2100 * 1000 * 1000,
  double escala = 1,
  Size tamano = const Size(390, 844),
  ArnesMapa? arnes,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final propio =
      arnes ?? ArnesMapa(conexion: conexion, catalogo: catalogo, servirPaqueteMontevideo: false);
  addTearDown(() => unawaited(propio.cerrar()));
  final espacio = EspacioFalso()..libres = libres;
  final fuente = _FuenteFalsa(lugar);
  final montaje = _Montaje(propio, fuente, espacio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...propio.overrides,
        fuenteLugarDeTrabajoProvider.overrideWithValue(fuente),
        medidorEspacioDiscoProvider.overrideWithValue(espacio),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: ValueListenableBuilder<bool>(
          valueListenable: montaje.abierto,
          builder: (_, abierto, _) =>
              abierto ? const MapasOfflinePage() : const Scaffold(body: Text('afuera')),
        ),
      ),
    ),
  );
  await _asentar(tester);
  return montaje;
}

Finder _clave(String clave) => find.byKey(Key(clave));

bool _habilitado(WidgetTester tester, String clave) {
  final boton = tester.widget<ButtonStyleButton>(_clave(clave));
  return boton.onPressed != null;
}

void main() {
  group('pantalla 01 · elegir cobertura', () {
    testWidgets('35-01: cuatro niveles, la ciudad vigente, la ayuda y el espacio libre', (
      tester,
    ) async {
      await _montar(tester, lugar: const Right(_sinZona), catalogo: [_ciudad86]);

      expect(find.text('MAPAS OFFLINE · 01'), findsOneWidget);
      expect(find.text('Para usar el mapa sin señal.'), findsOneWidget);
      expect(find.text('Mi zona'), findsOneWidget);
      expect(find.text('Mi ciudad'), findsOneWidget);
      expect(find.text('Mi departamento'), findsOneWidget);
      expect(find.text('Todo Uruguay'), findsOneWidget);
      expect(find.text('Montevideo · 86 MB'), findsOneWidget);
      expect(find.text('Llega con el paso a Pro'), findsNWidgets(2));
      expect(_clave('mapas_offline_ayuda_ciudad'), findsOneWidget);
      expect(
        find.text('Se baja con Wi-Fi. En el teléfono te quedan 2,1 GB libres.'),
        findsOneWidget,
      );
      expect(find.text('Descargar'), findsOneWidget);
      expect(_habilitado(tester, 'mapas_offline_descargar'), isTrue);
    });

    testWidgets('35-03: sin zona asignada, «Mi zona» no se puede elegir y rige la ciudad', (
      tester,
    ) async {
      await _montar(tester, lugar: const Right(_sinZona), catalogo: [_ciudad86, _zona14]);

      expect(find.text('No tenés zona asignada'), findsOneWidget);
      await tester.tap(_clave('mapas_offline_nivel_zona'));
      await _asentar(tester);
      expect(
        tester.getSemantics(_clave('mapas_offline_nivel_ciudad')).flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      expect(
        tester.getSemantics(_clave('mapas_offline_nivel_zona')).flagsCollection.isChecked,
        CheckedState.isFalse,
      );
      expect(find.text('Cerro Norte · 14 MB'), findsNothing);
    });

    testWidgets('con zona y paquete de zona en el catálogo, la zona rige por defecto', (
      tester,
    ) async {
      await _montar(tester, catalogo: [_ciudad86, _zona14]);

      expect(find.text('Cerro Norte · 14 MB'), findsOneWidget);
      expect(find.text('Montevideo · 86 MB'), findsOneWidget);
    });

    testWidgets('el catálogo sin paquete de zona lo dice: la ciudad la cubre', (tester) async {
      await _montar(tester, catalogo: [_ciudad86]);

      expect(find.text('Todavía no está disponible. Tu ciudad lo cubre.'), findsOneWidget);
    });

    testWidgets('departamento y Uruguay se ofrecen, con su peso, cuando el catálogo los trae', (
      tester,
    ) async {
      await _montar(
        tester,
        catalogo: [
          _ciudad86,
          _paquete(
            'depto-mvd',
            NivelCobertura.departamento,
            'd-1',
            'Montevideo (departamento)',
            250,
          ),
          _paquete('uruguay', NivelCobertura.uruguay, null, 'Uruguay', 900),
        ],
      );

      expect(find.text('Montevideo (departamento) · 250 MB'), findsOneWidget);
      expect(find.text('900 MB'), findsOneWidget);
      expect(find.text('Llega con el paso a Pro'), findsNothing);
      await tester.tap(_clave('mapas_offline_nivel_uruguay'));
      await _asentar(tester);
      expect(find.text('Todo Uruguay'), findsOneWidget);
    });

    testWidgets('35-02: con datos móviles la descarga espera al Wi-Fi', (tester) async {
      await _montar(tester, catalogo: [_ciudad86], conexion: TipoConexion.datosMoviles);

      expect(
        find.text('Estás con datos móviles. La descarga empieza cuando te conectes a Wi-Fi.'),
        findsOneWidget,
      );
      expect(find.text('Descargar con Wi-Fi'), findsOneWidget);
      expect(_habilitado(tester, 'mapas_offline_descargar'), isTrue);
    });

    testWidgets('sin conexión la descarga queda en cola hasta el Wi-Fi', (tester) async {
      await _montar(tester, catalogo: [_ciudad86], conexion: TipoConexion.sinConexion);

      expect(
        find.text('No hay conexión. La descarga empieza cuando te conectes a Wi-Fi.'),
        findsOneWidget,
      );
      expect(find.text('Descargar con Wi-Fi'), findsOneWidget);
    });

    testWidgets('35-04: sin espacio lo dice con el peso y lo que queda, y no deja descargar', (
      tester,
    ) async {
      await _montar(
        tester,
        lugar: const Right(_sinZona),
        catalogo: [_ciudad86],
        libres: 40 * 1000 * 1000,
      );

      expect(
        find.text(
          'No hay lugar: Montevideo ocupa 86 MB y te quedan 40 MB. Liberá espacio en el teléfono.',
        ),
        findsOneWidget,
      );
      expect(_clave('mapas_offline_espacio_libre'), findsNothing);
      expect(_habilitado(tester, 'mapas_offline_descargar'), isFalse);
    });

    testWidgets('35-04 con una opción más chica la sugiere', (tester) async {
      await _montar(tester, catalogo: [_ciudad86, _zona14], libres: 40 * 1000 * 1000);
      // La zona (14 MB) entra: rige y no hay aviso. Se elige la ciudad (86 MB) y no entra.
      expect(_clave('mapas_offline_sin_espacio'), findsNothing);
      await tester.tap(_clave('mapas_offline_nivel_ciudad'));
      await _asentar(tester);

      expect(find.textContaining('Elegí un mapa más chico o liberá espacio.'), findsOneWidget);
      expect(_habilitado(tester, 'mapas_offline_descargar'), isFalse);
    });

    testWidgets('sin catálogo: dice qué falta y «Reintentar» vuelve a leer', (tester) async {
      final arnes = ArnesMapa(servirPaqueteMontevideo: false);
      arnes.repositorio.falloCatalogo = const FailureSinConexion();
      final montaje = await _montar(tester, arnes: arnes);

      expect(
        find.text('Necesitás conexión para ver los mapas que se pueden descargar.'),
        findsOneWidget,
      );
      expect(_habilitado(tester, 'mapas_offline_descargar'), isFalse);

      arnes.repositorio
        ..falloCatalogo = null
        ..paquetesCatalogo = [_ciudad86];
      await tester.tap(find.text('Reintentar'));
      await _asentar(tester);

      expect(
        find.text('Necesitás conexión para ver los mapas que se pueden descargar.'),
        findsNothing,
      );
      expect(find.text('Montevideo · 86 MB'), findsOneWidget);
      expect(montaje.fuente.lecturas, 2);
    });

    testWidgets('si no se sabe dónde trabaja no afirma «sin zona»: lo dice y deja reintentar', (
      tester,
    ) async {
      final montaje = await _montar(
        tester,
        lugar: const Left(FailureLugarDeTrabajoNoDisponible()),
        catalogo: [_ciudad86],
      );

      expect(
        find.text('No pudimos saber en qué zona y ciudad trabajás. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('No tenés zona asignada'), findsNothing);

      montaje.fuente.resultado = const Right(_conZona);
      await tester.tap(find.text('Reintentar'));
      await _asentar(tester);

      expect(
        find.text('No pudimos saber en qué zona y ciudad trabajás. Probá de nuevo.'),
        findsNothing,
      );
      expect(find.text('Montevideo · 86 MB'), findsOneWidget);
    });
  });

  group('descarga (35-05 a 35-07)', () {
    testWidgets('«Descargar» baja el mapa: pasa por 35-05 y termina en 35-07 con el aviso', (
      tester,
    ) async {
      final arnes = ArnesMapa(catalogo: [_ciudadReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[_ciudadReal.origen] = _bytes
        ..servidor.retenerDespuesDe = 2000;
      final montaje = await _montar(tester, arnes: arnes, lugar: const Right(_sinZona));

      await tester.tap(_clave('mapas_offline_descargar'));
      await _asentar(tester);

      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
      expect(_clave('mapas_offline_etiqueta_ciudad-montevideo'), findsOneWidget);
      expect(find.text('Descargando'), findsWidgets);
      expect(find.text('36 %'), findsOneWidget);
      expect(
        find.text('Podés seguir usando la app. Si la cerrás, la descarga sigue sola al volver.'),
        findsOneWidget,
      );
      expect(_clave('mapas_offline_pausar_ciudad-montevideo'), findsOneWidget);

      unawaited(arnes.servidor.abierto?.close());
      arnes.servidor.retenerDespuesDe = null;
      // El resto del archivo: se pide de nuevo desde donde quedó.
      await tester.tap(_clave('mapas_offline_pausar_ciudad-montevideo'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_seguir_ciudad-montevideo'));
      await _asentar(tester);

      expect(find.text('Descargado'), findsWidgets);
      expect(_clave('mapas_offline_listo_ciudad-montevideo'), findsOneWidget);
      expect(find.text('El mapa de Centro está disponible sin conexión.'), findsOneWidget);
      expect(find.text('Cambiar cobertura'), findsOneWidget);
      expect(find.text('Borrar mapa'), findsOneWidget);
      expect(arnes.repositorio.registrados.map((p) => p.id), ['ciudad-montevideo']);
      expect(montaje.arnes.servidor.pedidos.first, 0);
    });

    testWidgets('doble toque en «Descargar» pide una sola vez', (tester) async {
      final arnes = ArnesMapa(catalogo: [_ciudadReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[_ciudadReal.origen] = _bytes
        ..servidor.retenerDespuesDe = 2000;
      await _montar(tester, arnes: arnes, lugar: const Right(_sinZona));

      await tester.tap(_clave('mapas_offline_descargar'));
      await tester.tap(_clave('mapas_offline_descargar'), warnIfMissed: false);
      await _asentar(tester);

      expect(arnes.servidor.pedidos, [0]);
    });

    testWidgets('falla al empezar: dice por qué, el botón vuelve a estar habilitado y reintenta', (
      tester,
    ) async {
      final arnes = ArnesMapa(catalogo: [_ciudadReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[_ciudadReal.origen] = _bytes
        ..servidor.statusError = 500;
      await _montar(tester, arnes: arnes, lugar: const Right(_sinZona));

      await tester.tap(_clave('mapas_offline_descargar'));
      await _asentar(tester);

      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
      expect(_clave('mapas_offline_falla_ciudad-montevideo'), findsOneWidget);
      expect(find.text('No se pudo'), findsOneWidget);
      expect(_habilitado(tester, 'mapas_offline_reintentar_ciudad-montevideo'), isTrue);

      arnes.servidor.statusError = null;
      await tester.tap(_clave('mapas_offline_reintentar_ciudad-montevideo'));
      await _asentar(tester);

      expect(find.text('Descargado'), findsWidgets);
      expect(arnes.repositorio.registrados, isNotEmpty);
    });

    testWidgets('35-06: se cae el Wi-Fi a mitad y la pausa dice que sigue sola', (tester) async {
      final arnes = ArnesMapa(catalogo: [_ciudadReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[_ciudadReal.origen] = _bytes
        ..servidor.retenerDespuesDe = 2000;
      await _montar(tester, arnes: arnes, lugar: const Right(_sinZona));
      await tester.tap(_clave('mapas_offline_descargar'));
      await _asentar(tester);

      arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
      await _asentar(tester);

      expect(find.text('En pausa'), findsOneWidget);
      expect(find.text('Pausada: sin Wi-Fi. Sigue sola cuando vuelva.'), findsOneWidget);
      expect(_clave('mapas_offline_seguir_ciudad-montevideo'), findsOneWidget);

      arnes.servidor.retenerDespuesDe = null;
      arnes.conectividad.cambiarA(TipoConexion.wifi);
      await _asentar(tester);

      expect(find.text('Descargado'), findsWidgets);
    });

    testWidgets('pausa a mano: «Seguir» reanuda desde el byte que quedó', (tester) async {
      final arnes = ArnesMapa(catalogo: [_ciudadReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[_ciudadReal.origen] = _bytes
        ..servidor.retenerDespuesDe = 2000;
      await _montar(tester, arnes: arnes, lugar: const Right(_sinZona));
      await tester.tap(_clave('mapas_offline_descargar'));
      await _asentar(tester);

      await tester.tap(_clave('mapas_offline_pausar_ciudad-montevideo'));
      await _asentar(tester);
      expect(find.text('En pausa'), findsOneWidget);
      expect(find.text('Pausada. Tocá Seguir para continuar.'), findsOneWidget);

      arnes.servidor.retenerDespuesDe = null;
      await tester.tap(_clave('mapas_offline_seguir_ciudad-montevideo'));
      await _asentar(tester);

      expect(arnes.servidor.pedidos.last, greaterThan(0));
      expect(find.text('Descargado'), findsWidgets);
    });

    testWidgets('volver atrás y reentrar sigue mostrando la descarga en marcha', (tester) async {
      final arnes = ArnesMapa(catalogo: [_ciudadReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[_ciudadReal.origen] = _bytes
        ..servidor.retenerDespuesDe = 2000;
      final montaje = await _montar(tester, arnes: arnes, lugar: const Right(_sinZona));
      await tester.tap(_clave('mapas_offline_descargar'));
      await _asentar(tester);

      montaje.abierto.value = false;
      await _asentar(tester);
      expect(find.text('afuera'), findsOneWidget);
      montaje.abierto.value = true;
      await _asentar(tester);

      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
      expect(find.text('36 %'), findsOneWidget);
      expect(arnes.servidor.pedidos, [0]);
    });

    testWidgets('35-07: «Borrar mapa» lo saca, libera el espacio y lo avisa', (tester) async {
      final arnes = ArnesMapa(catalogo: [_ciudad86], servirPaqueteMontevideo: false);
      await arnes.repositorio.registrar(descargadoDe(_ciudad86));
      await _montar(tester, arnes: arnes);

      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
      expect(find.text('86 MB · listo para usar sin conexión'), findsOneWidget);

      await tester.tap(_clave('mapas_offline_borrar_ciudad-montevideo'));
      await _asentar(tester);

      expect(arnes.repositorio.registrados, isEmpty);
      expect(find.text('Mapa borrado. Liberaste 86 MB.'), findsOneWidget);
      expect(find.text('MAPAS OFFLINE · 01'), findsOneWidget);
    });

    testWidgets('si no se puede borrar lo dice y el mapa sigue ahí', (tester) async {
      final arnes = ArnesMapa(catalogo: [_ciudad86], servirPaqueteMontevideo: false);
      await arnes.repositorio.registrar(descargadoDe(_ciudad86));
      arnes.repositorio.falloQuitar = const FailureInesperado();
      await _montar(tester, arnes: arnes);

      await tester.tap(_clave('mapas_offline_borrar_ciudad-montevideo'));
      await _asentar(tester);

      expect(_clave('mapas_offline_falla'), findsOneWidget);
      expect(arnes.repositorio.registrados, isNotEmpty);
      expect(_clave('mapas_offline_borrar_ciudad-montevideo'), findsOneWidget);
      final boton = tester.widget<TextButton>(_clave('mapas_offline_borrar_ciudad-montevideo'));
      expect(boton.onPressed, isNotNull);
    });

    testWidgets('35-08: la versión nueva se ofrece con su peso y «Actualizar» la baja', (
      tester,
    ) async {
      final nueva = _paquete(
        'ciudad-montevideo',
        NivelCobertura.ciudad,
        'c-1',
        'Montevideo',
        12,
        version: 'v2',
      );
      final arnes = ArnesMapa(catalogo: [nueva], servirPaqueteMontevideo: false);
      await arnes.repositorio.registrar(descargadoDe(_ciudad86));
      await _montar(tester, arnes: arnes);

      expect(
        find.text('Hay una versión nueva del mapa de Montevideo (12 MB). Se baja con Wi-Fi.'),
        findsOneWidget,
      );
      expect(find.text('Actualizar'), findsOneWidget);
    });
  });

  group('35-09 · achicar la cobertura', () {
    testWidgets(
      '«Cambiar cobertura» abre la 01 y elegir la zona pide confirmar antes de borrar la ciudad',
      (tester) async {
        final arnes = ArnesMapa(catalogo: [_ciudad86, _zona14], servirPaqueteMontevideo: false);
        await arnes.repositorio.registrar(descargadoDe(_ciudad86));
        await _montar(tester, arnes: arnes);

        await tester.tap(_clave('mapas_offline_cambiar_cobertura'));
        await _asentar(tester);
        expect(find.text('MAPAS OFFLINE · 01'), findsOneWidget);

        await tester.tap(_clave('mapas_offline_nivel_zona'));
        await _asentar(tester);
        await tester.tap(_clave('mapas_offline_descargar'));
        await _asentar(tester);

        expect(find.text('¿Quedarte solo con tu zona?'), findsOneWidget);
        expect(
          find.text(
            'Borramos el mapa de Montevideo y liberás 72 MB. Fuera de Cerro Norte, el mapa sin señal '
            'se ve en blanco.',
          ),
          findsOneWidget,
        );

        await tester.tap(_clave('mapas_offline_achicar_cancelar'));
        await _asentar(tester);

        expect(arnes.repositorio.registrados.map((p) => p.id), ['ciudad-montevideo']);
        expect(arnes.servidor.pedidos, isEmpty);
      },
    );

    testWidgets('confirmar baja la zona y, al terminar, borra la ciudad', (tester) async {
      final bytesZona = bytesDePrueba(3000, semilla: 7);
      final zona = paqueteDe(
        bytesZona,
        id: 'zona-cerro-norte',
        nivel: NivelCobertura.zona,
        ambitoId: 'z-1',
      );
      final arnes = ArnesMapa(catalogo: [_ciudad86, zona], servirPaqueteMontevideo: false)
        ..servidor.archivos[zona.origen] = bytesZona;
      await arnes.repositorio.registrar(descargadoDe(_ciudad86));
      await _montar(tester, arnes: arnes);

      await tester.tap(_clave('mapas_offline_cambiar_cobertura'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_nivel_zona'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_descargar'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_achicar_confirmar'));
      await _asentar(tester);

      expect(arnes.repositorio.registrados.map((p) => p.id), ['zona-cerro-norte']);
      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
      expect(_clave('mapas_offline_tarjeta_ciudad-montevideo'), findsNothing);
    });

    testWidgets('si la zona no termina de bajar, la ciudad no se borra', (tester) async {
      final bytesZona = bytesDePrueba(3000, semilla: 7);
      final zona = paqueteDe(
        bytesZona,
        id: 'zona-cerro-norte',
        nivel: NivelCobertura.zona,
        ambitoId: 'z-1',
      );
      final arnes = ArnesMapa(catalogo: [_ciudad86, zona], servirPaqueteMontevideo: false)
        ..servidor.archivos[zona.origen] = bytesZona
        ..servidor.statusError = 500;
      await arnes.repositorio.registrar(descargadoDe(_ciudad86));
      await _montar(tester, arnes: arnes);

      await tester.tap(_clave('mapas_offline_cambiar_cobertura'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_nivel_zona'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_descargar'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_achicar_confirmar'));
      await _asentar(tester);

      expect(arnes.repositorio.registrados.map((p) => p.id), ['ciudad-montevideo']);
    });

    testWidgets('el paso atrás de «Cambiar cobertura» vuelve a la lista, no sale', (tester) async {
      final arnes = ArnesMapa(catalogo: [_ciudad86], servirPaqueteMontevideo: false);
      await arnes.repositorio.registrar(descargadoDe(_ciudad86));
      await _montar(tester, arnes: arnes);

      await tester.tap(_clave('mapas_offline_cambiar_cobertura'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_atras'));
      await _asentar(tester);

      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
    });
  });

  group('datos límite', () {
    testWidgets('cuatro mapas descargados con textos largos, a textScaler 2.0, sin desbordes', (
      tester,
    ) async {
      final largo = 'Un nombre larguísimo de departamento para probar el corte de línea ' * 2;
      final paquetes = [
        _paquete('zona-1', NivelCobertura.zona, 'z-1', largo, 14),
        _paquete('ciudad-1', NivelCobertura.ciudad, 'c-1', largo, 86),
        _paquete('depto-1', NivelCobertura.departamento, 'd-1', largo, 250),
        _paquete('uruguay', NivelCobertura.uruguay, null, largo, 900),
      ];
      final arnes = ArnesMapa(catalogo: paquetes, servirPaqueteMontevideo: false);
      for (final p in paquetes) {
        await arnes.repositorio.registrar(descargadoDe(p));
      }
      await _montar(tester, arnes: arnes, escala: 2, tamano: const Size(360, 640));

      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(
        _clave('mapas_offline_cambiar_cobertura'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('la elección a textScaler 2.0 y con el teléfono chico no desborda', (tester) async {
      await _montar(
        tester,
        catalogo: [_ciudad86, _zona14],
        escala: 2,
        tamano: const Size(360, 640),
        libres: 40 * 1000 * 1000,
      );

      expect(find.text('MAPAS OFFLINE · 01'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
