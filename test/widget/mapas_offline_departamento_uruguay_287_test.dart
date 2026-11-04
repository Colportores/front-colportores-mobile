// «Mapas offline» con el mapa del departamento y el de todo Uruguay (vista 35, HU-SYNC-010, #287):
// los dos mapas grandes que elige la colportora. Antes de bajarlos ve el peso y el espacio libre; si
// no entran, la app le dice cuánto falta; y los borra desde la misma pantalla (decisión de Cristian,
// 06/10, «Tope mapa»). Con el descargador REAL sobre los puertos falsos (sin red, disco ni HTTP).
import 'dart:async';

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
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mapa_descargas_arnes.dart';
import '../helpers/tiles_falsos.dart';

final class _Fuente implements FuenteLugarDeTrabajo {
  const _Fuente(this.lugar);

  final LugarDeTrabajo lugar;

  @override
  Future<Either<Failure, LugarDeTrabajo>> leer() async => Right(lugar);
}

LugarDeTrabajo _lugarEn(String departamento) => LugarDeTrabajo(
  ambito: AmbitoTrabajo(ciudadId: 'c-1', departamentoId: departamento),
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

final _ciudad86 = _paquete('ciudad-montevideo', NivelCobertura.ciudad, 'c-1', 'Montevideo', 86);
final _depto250 = _paquete(
  'depto-san-jose',
  NivelCobertura.departamento,
  'san jose',
  'San José',
  250,
);
final _uruguay1200 = _paquete('uruguay', NivelCobertura.uruguay, null, 'Todo Uruguay', 1200);

/// Uruguay con bytes de verdad, para las pruebas que bajan el archivo.
final _bytesUruguay = bytesDePrueba(5500, semilla: 11);
final _uruguayReal = paqueteDe(
  _bytesUruguay,
  id: 'uruguay',
  nivel: NivelCobertura.uruguay,
  ambitoId: null,
);

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

final class _Montaje {
  _Montaje(this.arnes);

  final ArnesMapa arnes;
  final abierto = ValueNotifier<bool>(true);
}

Future<_Montaje> _montar(
  WidgetTester tester, {
  required ArnesMapa arnes,
  LugarDeTrabajo? lugar,
  int libres = 4000 * 1000 * 1000,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => unawaited(arnes.cerrar()));
  final espacio = EspacioFalso()..libres = libres;
  final montaje = _Montaje(arnes);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...arnes.overrides,
        fuenteLugarDeTrabajoProvider.overrideWithValue(_Fuente(lugar ?? _lugarEn('san jose'))),
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

ArnesMapa _arnes(List<PaqueteTiles> catalogo, {TipoConexion conexion = TipoConexion.wifi}) =>
    ArnesMapa(conexion: conexion, catalogo: catalogo, servirPaqueteMontevideo: false);

Finder _clave(String clave) => find.byKey(Key(clave));

bool _habilitado(WidgetTester tester, String clave) =>
    tester.widget<ButtonStyleButton>(_clave(clave)).onPressed != null;

Future<void> _elegir(WidgetTester tester, NivelCobertura nivel) async {
  await tester.tap(_clave('mapas_offline_nivel_${nivel.name}'));
  await _asentar(tester);
}

void main() {
  group('35-01 · elegir el mapa del departamento y el de Uruguay', () {
    testWidgets('se ofrecen con su peso, y el espacio libre se ve antes de bajar', (tester) async {
      await _montar(tester, arnes: _arnes([_ciudad86, _depto250, _uruguay1200]));

      expect(find.text('San José · 250 MB'), findsOneWidget);
      // Uruguay pesa más de 1000 MB: se muestra en GB, redondeado para arriba.
      expect(find.text('1,2 GB'), findsOneWidget);
      expect(find.text('Todavía no está disponible'), findsNothing);

      await _elegir(tester, NivelCobertura.uruguay);
      expect(_clave('mapas_offline_espacio_libre'), findsOneWidget);
      expect(
        find.text('Se baja con Wi-Fi. En el teléfono te quedan 4,0 GB libres.'),
        findsOneWidget,
      );
      expect(_habilitado(tester, 'mapas_offline_descargar'), isTrue);
    });

    testWidgets('el departamento se reconoce aunque la ciudad lo nombre con tildes y mayúsculas', (
      tester,
    ) async {
      await _montar(tester, arnes: _arnes([_ciudad86, _depto250]), lugar: _lugarEn('  San  José '));

      expect(find.text('San José · 250 MB'), findsOneWidget);
    });

    testWidgets('el mapa de otro departamento no se ofrece: el catálogo no trae el suyo', (
      tester,
    ) async {
      await _montar(tester, arnes: _arnes([_ciudad86, _depto250]), lugar: _lugarEn('rocha'));

      expect(find.text('San José · 250 MB'), findsNothing);
      expect(find.text('Todavía no está disponible'), findsWidgets);
      await tester.tap(_clave('mapas_offline_nivel_departamento'));
      await _asentar(tester);
      expect(
        tester
            .getSemantics(_clave('mapas_offline_nivel_departamento'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
    });

    testWidgets('sin los paquetes en el catálogo no promete que «llegan con Pro»', (tester) async {
      await _montar(tester, arnes: _arnes([_ciudad86]));

      expect(find.text('Llega con el paso a Pro'), findsNothing);
      expect(find.text('Todavía no está disponible'), findsNWidgets(2));
    });
  });

  group('35-04 · si no entran, dice cuánto falta', () {
    testWidgets('Uruguay: el peso, lo que queda y lo que falta; no deja descargar', (tester) async {
      await _montar(tester, arnes: _arnes([_ciudad86, _uruguay1200]), libres: 400 * 1000 * 1000);
      await _elegir(tester, NivelCobertura.uruguay);

      expect(
        find.text(
          'No hay lugar: Todo Uruguay ocupa 1,2 GB y te quedan 400 MB. Te faltan 800 MB. '
          'Elegí un mapa más chico o liberá espacio.',
        ),
        findsOneWidget,
      );
      expect(_clave('mapas_offline_espacio_libre'), findsNothing);
      expect(_habilitado(tester, 'mapas_offline_descargar'), isFalse);
    });

    testWidgets('departamento: con 1 MB de falta lo dice en singular', (tester) async {
      await _montar(
        tester,
        arnes: _arnes([_ciudad86, _depto250]),
        libres: 249 * 1000 * 1000 + 500 * 1000,
      );
      await _elegir(tester, NivelCobertura.departamento);

      expect(find.textContaining('Te falta 1 MB.'), findsOneWidget);
      expect(_habilitado(tester, 'mapas_offline_descargar'), isFalse);
    });

    testWidgets('la ciudad sigue con el texto del canvas, sin «Te faltan»', (tester) async {
      await _montar(tester, arnes: _arnes([_ciudad86]), libres: 40 * 1000 * 1000);

      expect(find.textContaining('Te falta'), findsNothing);
      expect(
        find.text(
          'No hay lugar: Montevideo ocupa 86 MB y te quedan 40 MB. Liberá espacio en el teléfono.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('si libera lugar y vuelve a leer, el aviso se va y deja descargar', (tester) async {
      final arnes = _arnes([_ciudad86, _uruguay1200]);
      await _montar(tester, arnes: arnes, libres: 400 * 1000 * 1000);
      await _elegir(tester, NivelCobertura.uruguay);
      expect(_habilitado(tester, 'mapas_offline_descargar'), isFalse);

      final contenedor = ProviderScope.containerOf(tester.element(find.byType(MapasOfflinePage)));
      final espacio = contenedor.read(medidorEspacioDiscoProvider) as EspacioFalso;
      espacio.libres = 2000 * 1000 * 1000;
      await contenedor.read(mapasOfflineProvider.notifier).cargar();
      await _asentar(tester);

      expect(_clave('mapas_offline_sin_espacio'), findsNothing);
      expect(_habilitado(tester, 'mapas_offline_descargar'), isTrue);
    });
  });

  group('descargar Uruguay', () {
    testWidgets('baja el mapa, lo deja listo y la tarjeta ofrece «Borrar mapa»', (tester) async {
      final arnes = ArnesMapa(catalogo: [_ciudad86, _uruguayReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[_uruguayReal.origen] = _bytesUruguay;
      await _montar(tester, arnes: arnes);
      await _elegir(tester, NivelCobertura.uruguay);

      await tester.tap(_clave('mapas_offline_descargar'));
      await _asentar(tester);

      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
      expect(_clave('mapas_offline_listo_uruguay'), findsOneWidget);
      expect(find.textContaining('está disponible sin conexión.'), findsOneWidget);
      expect(_clave('mapas_offline_borrar_uruguay'), findsOneWidget);
      expect(arnes.repositorio.registrados.map((p) => p.id), ['uruguay']);
    });

    testWidgets('doble toque en «Descargar» pide una sola vez', (tester) async {
      final arnes = ArnesMapa(catalogo: [_ciudad86, _uruguayReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[_uruguayReal.origen] = _bytesUruguay
        ..servidor.retenerDespuesDe = 2000;
      await _montar(tester, arnes: arnes);
      await _elegir(tester, NivelCobertura.uruguay);

      await tester.tap(_clave('mapas_offline_descargar'));
      await tester.tap(_clave('mapas_offline_descargar'), warnIfMissed: false);
      await _asentar(tester);

      expect(arnes.servidor.pedidos, [0]);
    });

    testWidgets('falla a mitad: la tarjeta lo dice, «Reintentar» queda habilitado y termina', (
      tester,
    ) async {
      final arnes = ArnesMapa(catalogo: [_ciudad86, _uruguayReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[_uruguayReal.origen] = _bytesUruguay
        ..servidor.statusError = 500;
      await _montar(tester, arnes: arnes);
      await _elegir(tester, NivelCobertura.uruguay);

      await tester.tap(_clave('mapas_offline_descargar'));
      await _asentar(tester);

      expect(_clave('mapas_offline_falla_uruguay'), findsOneWidget);
      expect(find.text('No se pudo'), findsOneWidget);
      expect(_habilitado(tester, 'mapas_offline_reintentar_uruguay'), isTrue);

      arnes.servidor.statusError = null;
      await tester.tap(_clave('mapas_offline_reintentar_uruguay'));
      await _asentar(tester);

      expect(_clave('mapas_offline_listo_uruguay'), findsOneWidget);
      expect(arnes.repositorio.registrados.map((p) => p.id), ['uruguay']);
    });

    testWidgets('volver atrás y reentrar sigue mostrando la descarga en marcha', (tester) async {
      final arnes = ArnesMapa(catalogo: [_ciudad86, _uruguayReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[_uruguayReal.origen] = _bytesUruguay
        ..servidor.retenerDespuesDe = 2000;
      final montaje = await _montar(tester, arnes: arnes);
      await _elegir(tester, NivelCobertura.uruguay);
      await tester.tap(_clave('mapas_offline_descargar'));
      await _asentar(tester);

      montaje.abierto.value = false;
      await _asentar(tester);
      montaje.abierto.value = true;
      await _asentar(tester);

      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
      expect(_clave('mapas_offline_tarjeta_uruguay'), findsOneWidget);
      expect(find.text('36 %'), findsOneWidget);
      expect(arnes.servidor.pedidos, [0]);
    });

    testWidgets('el descargador no encuentra lugar: dice cuánto falta y no deja nada trabado', (
      tester,
    ) async {
      final arnes = ArnesMapa(catalogo: [_ciudad86, _uruguayReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[_uruguayReal.origen] = _bytesUruguay;
      arnes.espacio.libres = 1000;
      await _montar(tester, arnes: arnes);
      await _elegir(tester, NivelCobertura.uruguay);

      await tester.tap(_clave('mapas_offline_descargar'));
      await _asentar(tester);

      expect(find.textContaining('Espacio insuficiente - faltan'), findsWidgets);
      expect(arnes.repositorio.registrados, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('borrar el mapa del departamento o el de Uruguay', () {
    testWidgets('«Borrar mapa» saca Uruguay, libera el espacio y lo dice en GB', (tester) async {
      final arnes = _arnes([_ciudad86, _uruguay1200]);
      await arnes.repositorio.registrar(descargadoDe(_uruguay1200));
      await _montar(tester, arnes: arnes);

      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
      expect(find.text('1,2 GB · listo para usar sin conexión'), findsOneWidget);

      await tester.tap(_clave('mapas_offline_borrar_uruguay'));
      await _asentar(tester);
      expect(find.text('¿Borrar el mapa de Todo Uruguay?'), findsOneWidget);
      await tester.tap(_clave('mapas_offline_borrar_confirmar'));
      await _asentar(tester);

      expect(arnes.repositorio.registrados, isEmpty);
      expect(find.text('Mapa borrado. Liberaste 1,2 GB.'), findsOneWidget);
      expect(find.text('MAPAS OFFLINE · 01'), findsOneWidget);
    });

    testWidgets('«Cancelar» deja el mapa; si no se puede borrar lo dice y el botón sigue vivo', (
      tester,
    ) async {
      final arnes = _arnes([_ciudad86, _depto250]);
      await arnes.repositorio.registrar(descargadoDe(_depto250));
      await _montar(tester, arnes: arnes);

      await tester.tap(_clave('mapas_offline_borrar_depto-san-jose'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_borrar_cancelar'));
      await _asentar(tester);
      expect(arnes.repositorio.registrados, isNotEmpty);

      arnes.repositorio.falloQuitar = const FailureInesperado();
      await tester.tap(_clave('mapas_offline_borrar_depto-san-jose'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_borrar_confirmar'));
      await _asentar(tester);

      expect(_clave('mapas_offline_falla'), findsOneWidget);
      expect(arnes.repositorio.registrados, isNotEmpty);
      expect(
        tester.widget<TextButton>(_clave('mapas_offline_borrar_depto-san-jose')).onPressed,
        isNotNull,
      );

      // Y al reintentar, ya sin la falla, se borra: ningún «ocupado» quedó trabado.
      arnes.repositorio.falloQuitar = null;
      await tester.tap(_clave('mapas_offline_borrar_depto-san-jose'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_borrar_confirmar'));
      await _asentar(tester);
      expect(arnes.repositorio.registrados, isEmpty);
    });

    testWidgets('borrar uno y enseguida el otro: se van los dos, sin pisarse', (tester) async {
      final arnes = _arnes([_ciudad86, _depto250, _uruguay1200]);
      await arnes.repositorio.registrar(descargadoDe(_depto250));
      await arnes.repositorio.registrar(descargadoDe(_uruguay1200));
      await _montar(tester, arnes: arnes);

      await tester.tap(_clave('mapas_offline_borrar_depto-san-jose'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_borrar_confirmar'));
      await _asentar(tester);
      expect(find.text('Mapa borrado. Liberaste 250 MB.'), findsOneWidget);

      await tester.tap(_clave('mapas_offline_borrar_uruguay'));
      await _asentar(tester);
      await tester.tap(_clave('mapas_offline_borrar_confirmar'));
      await _asentar(tester);

      expect(arnes.repositorio.registrados, isEmpty);
      expect(find.text('Mapa borrado. Liberaste 1,2 GB.'), findsOneWidget);
    });
  });

  group('achicar desde Uruguay', () {
    testWidgets('elegir la ciudad pide confirmar y dice cuánto se libera, en GB', (tester) async {
      final arnes = _arnes([_ciudad86, _uruguay1200]);
      await arnes.repositorio.registrar(descargadoDe(_uruguay1200));
      await _montar(tester, arnes: arnes);

      await tester.tap(_clave('mapas_offline_cambiar_cobertura'));
      await _asentar(tester);
      await _elegir(tester, NivelCobertura.ciudad);
      await tester.tap(_clave('mapas_offline_descargar'));
      await _asentar(tester);

      expect(find.text('¿Quedarte solo con tu ciudad?'), findsOneWidget);
      expect(
        find.text(
          'Borramos el mapa de Todo Uruguay y liberás 1,1 GB. Fuera de Montevideo, el mapa sin '
          'señal se ve en blanco.',
        ),
        findsOneWidget,
      );

      await tester.tap(_clave('mapas_offline_achicar_cancelar'));
      await _asentar(tester);
      expect(arnes.repositorio.registrados.map((p) => p.id), ['uruguay']);
      expect(arnes.servidor.pedidos, isEmpty);
    });
  });

  group('datos límite', () {
    testWidgets('el aviso de «cuánto falta» a textScaler 2.0 y con el teléfono chico no desborda', (
      tester,
    ) async {
      await _montar(
        tester,
        arnes: _arnes([_ciudad86, _depto250, _uruguay1200]),
        libres: 400 * 1000 * 1000,
        escala: 2,
        tamano: const Size(360, 640),
      );
      // A 2.0 en un teléfono chico la opción queda abajo de la ventana: se elige por el notificador.
      ProviderScope.containerOf(
        tester.element(find.byType(MapasOfflinePage)),
      ).read(mapasOfflineProvider.notifier).elegir(NivelCobertura.uruguay);
      await _asentar(tester);

      expect(_clave('mapas_offline_sin_espacio'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nombres largos y pesos de GB en la lista a textScaler 2.0 no desbordan', (
      tester,
    ) async {
      final largo = 'Un departamento con un nombre larguísimo para probar el corte de línea ' * 2;
      final depto = _paquete('depto-largo', NivelCobertura.departamento, 'san jose', largo, 250);
      final uruguay = _paquete('uruguay', NivelCobertura.uruguay, null, largo, 1200);
      final arnes = _arnes([depto, uruguay]);
      await arnes.repositorio.registrar(descargadoDe(depto));
      await arnes.repositorio.registrar(descargadoDe(uruguay));
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

    testWidgets('sin conexión y sin catálogo no promete nada de Uruguay y deja reintentar', (
      tester,
    ) async {
      final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, servirPaqueteMontevideo: false);
      arnes.repositorio.falloCatalogo = const FailureSinConexion();
      await _montar(tester, arnes: arnes);

      expect(
        find.text('Necesitás conexión para ver los mapas que se pueden descargar.'),
        findsOneWidget,
      );
      expect(find.text('Llega con el paso a Pro'), findsNothing);
      expect(_habilitado(tester, 'mapas_offline_descargar'), isFalse);
    });
  });
}
