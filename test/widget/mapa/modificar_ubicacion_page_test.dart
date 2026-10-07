// Vista 07 «Modificar ubicación» (HU-UBI-004, #202): un test por artboard del canvas, por estado, por
// aviso literal de la HU y por caso límite (doble toque, falla a mitad, dos acciones seguidas,
// volver y reentrar, datos límite y texto a 200 %).
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_modificacion_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:dartz/dartz.dart' show Left, Right;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';

/// Lo que se mueve el punto hacia el norte para estar a unos 18 m («Moviste el punto 18 m»).
const _norte18m = 0.00016;

/// Y para estar a unos 150 m, más que el umbral de 100 m del aviso.
const _norte150m = 0.00135;

Coordenadas _alNorte(double grados) =>
    Coordenadas(lat: puntoItalia.lat + grados, lon: puntoItalia.lon);

/// La pantalla que abre la edición y guarda cómo se cerró.
class _Anfitrion extends StatelessWidget {
  const _Anfitrion({required this.salidas, this.alDarDeBaja});

  final List<SalidaModificarUbicacion?> salidas;
  final VoidCallback? alDarDeBaja;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async => salidas.add(
            await ModificarUbicacionPage.abrir(
              context,
              colportorId: 'col-1',
              ubicacionId: 'ubi-1',
              alDarDeBaja: alDarDeBaja,
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    );
  }
}

final class _Escenario {
  _Escenario({
    required this.repo,
    required this.ciudades,
    required this.geocodificador,
    required this.gps,
    required this.mapa,
  });

  final RepoEdicionFalso repo;
  final CiudadesFalsas ciudades;
  final GeocodificadorFalso geocodificador;
  final GpsFalso gps;

  /// La vista del mapa (MapLibre no se dibuja en `flutter test`): su cámara y lo que se le pidió dibujar.
  final FabricaMapaFalsa mapa;
  final salidas = <SalidaModificarUbicacion?>[];
  var dadasDeBaja = 0;
}

Future<void> _asentar(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_Escenario> _montar(
  WidgetTester tester, {
  Ubicacion? ubicacion,
  RepoEdicionFalso? repo,
  int espacios = 2,
  CiudadesFalsas? ciudades,
  GeocodificadorFalso? geocodificador,
  GpsFalso? gps,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
  bool conBaja = false,
  TipoConexion? conexion,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = _Escenario(
    repo: repo ?? RepoEdicionFalso(ubicacion ?? ubicacionGuardada(), espacios: espacios),
    ciudades: ciudades ?? CiudadesFalsas(),
    geocodificador:
        geocodificador ??
        GeocodificadorFalso((_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1250')),
    gps: gps ?? GpsFalso(),
    mapa: FabricaMapaFalsa(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesAlta(
          gps: e.gps,
          geocodificador: e.geocodificador,
          ciudades: e.ciudades,
          repo: e.repo,
          ahora: DateTime.utc(2026, 10, 2, 12),
          mapa: e.mapa,
        ),
        if (conexion != null) conexionProvider.overrideWith((ref) => Stream.value(conexion)),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: _Anfitrion(salidas: e.salidas, alDarDeBaja: conBaja ? () => e.dadasDeBaja++ : null),
      ),
    ),
  );
  if (abrir) await _abrir(tester);
  return e;
}

Future<void> _abrir(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await _asentar(tester);
}

/// Deja [f] a la vista en la hoja. Primero deja que el árbol se rearme (un `enterText` previo cambia
/// el alto de la hoja recién en el próximo cuadro) y solo desplaza la hoja si [f] no se alcanza.
Future<void> _traer(WidgetTester tester, Finder f) async {
  await tester.pump();
  if (f.hitTestable().evaluate().isEmpty) {
    await Scrollable.ensureVisible(tester.element(f), alignment: .5);
    await tester.pump();
  }
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await _traer(tester, f);
  await tester.tap(f);
  await _asentar(tester);
}

Finder get _guardar => find.widgetWithText(FilledButton, TextosModificar.guardarCambios);
Finder get _guardandoBoton => find.widgetWithText(FilledButton, TextosModificar.guardando);
Finder get _campoCalle => find.byType(TextField).at(0);
Finder get _campoNumero => find.byType(TextField).at(1);

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<FilledButton>(boton).onPressed != null;

Future<void> _escribirNumero(WidgetTester tester, String texto) async {
  await _traer(tester, _campoNumero);
  await tester.enterText(_campoNumero, texto);
  await tester.pump();
}

Future<void> _escribirCalle(WidgetTester tester, String texto) async {
  await _traer(tester, _campoCalle);
  await tester.enterText(_campoCalle, texto);
  await tester.pump();
}

/// El colportor arrastra el mapa: el pin (fijo en el centro) queda [grados] al norte del punto de
/// partida.
Future<void> _moverMapa(WidgetTester tester, _Escenario e, double grados) async {
  final camara = e.mapa.camara!;
  e.mapa.moverPorGesto(camara.conCentro(_alNorte(grados)));
  await _asentar(tester);
}

/// «Mover el punto», arrastrar [grados] al norte y «Guardar posición».
Future<void> _moverYGuardarPosicion(WidgetTester tester, _Escenario e, double grados) async {
  await _tocar(tester, find.text('Mover el punto'));
  await _moverMapa(tester, e, grados);
  await _tocar(tester, find.text('Guardar posición'));
}

Finder get _cerrar => find.byTooltip('Cerrar');

void main() {
  group('artboard 07 · 01 «Editar datos»', () {
    testWidgets('muestra lo guardado: dirección, resumen, tipo, ciudad, calle y número', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final e = await _montar(tester);

      expect(find.text('EDITAR UBICACIÓN'), findsOneWidget);
      expect(find.text('Av. Italia 1234'), findsOneWidget);
      expect(find.text('Casa · 2 espacios · creada el 12/08'), findsOneWidget);
      expect(find.text('Casa'), findsOneWidget);
      expect(find.text('Negocio'), findsOneWidget);
      expect(find.text('Edificio'), findsOneWidget);
      expect(find.text('CIUDAD · OBLIGATORIA'), findsOneWidget);
      expect(find.text('Montevideo'), findsOneWidget);
      expect(find.text('Cambiar'), findsOneWidget);
      expect(find.text('CALLE · OPCIONAL'), findsOneWidget);
      expect(find.text('NÚMERO'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Av. Italia'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1234'), findsOneWidget);
      expect(find.text('Mover el punto'), findsOneWidget);
      expect(find.text('Guardar cambios'), findsOneWidget);
      expect(find.text('Editado'), findsNothing);
      expect(find.byTooltip('Cerrar'), findsOneWidget);
      expect(find.bySemanticsLabel('Punto de la ubicación'), findsOneWidget);
      // El mapa queda fijo hasta tocar «Mover el punto»: no cambia la posición sin querer.
      expect(e.mapa.config!.interaccion, InteraccionMapa.ninguna);
      expect(e.mapa.config!.camaraInicial.centro, puntoItalia);
      expect(e.repo.escrituras, isEmpty);
      handle.dispose();
    });

    testWidgets('«Guardar cambios» está deshabilitado hasta que hay un cambio', (tester) async {
      await _montar(tester);

      expect(_habilitado(tester, _guardar), isFalse);
      await _tocar(tester, find.text('Negocio'));
      expect(_habilitado(tester, _guardar), isTrue);
      await _tocar(tester, find.text('Casa'));
      expect(_habilitado(tester, _guardar), isFalse, reason: 'volvió a lo guardado');
    });

    testWidgets('el tipo elegido se marca y el guardado ya lo trae elegido', (tester) async {
      await _montar(tester, ubicacion: ubicacionGuardada(tipo: TipoUbicacion.negocio));

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('Casa · 2 espacios · creada el 12/08'), findsNothing);
      expect(find.text('Negocio · 2 espacios · creada el 12/08'), findsOneWidget);
      await _tocar(tester, find.text('Edificio'));
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('el campo que cambió dice «Editado» y vuelve a lo normal si se deshace', (
      tester,
    ) async {
      await _montar(tester);

      await _escribirNumero(tester, '1238');
      expect(find.text('Editado'), findsOneWidget);
      expect(_habilitado(tester, _guardar), isTrue);

      await _escribirCalle(tester, 'Av. Brasil');
      expect(find.text('Editado'), findsNWidgets(2));

      await _escribirNumero(tester, '1234');
      await _escribirCalle(tester, 'Av. Italia');
      expect(find.text('Editado'), findsNothing);
      expect(_habilitado(tester, _guardar), isFalse);
    });

    testWidgets('los espacios en los bordes del texto no son un cambio', (tester) async {
      await _montar(tester);

      await _escribirNumero(tester, '  1234 ');

      expect(find.text('Editado'), findsNothing);
      expect(_habilitado(tester, _guardar), isFalse);
    });

    testWidgets('«Dar de baja» solo se dibuja si quien abre la pantalla lo ofrece', (tester) async {
      await _montar(tester);
      expect(find.text('Dar de baja'), findsNothing);
    });

    testWidgets('«Dar de baja» avisa a quien abrió la pantalla y no escribe nada', (tester) async {
      final e = await _montar(tester, conBaja: true);

      await _tocar(tester, find.text('Dar de baja'));

      expect(e.dadasDeBaja, 1);
      expect(e.repo.escrituras, isEmpty);
    });

    testWidgets('el resumen cuenta bien los espacios: ninguno, uno y varios', (tester) async {
      await _montar(tester, espacios: 0);
      expect(find.text('Casa · Sin espacios · creada el 12/08'), findsOneWidget);
    });

    testWidgets('un solo espacio va en singular', (tester) async {
      await _montar(tester, espacios: 1);
      expect(find.text('Casa · 1 espacio · creada el 12/08'), findsOneWidget);
    });

    testWidgets('si no se pudieron contar los espacios, el resumen no inventa la cuenta', (
      tester,
    ) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())..fallaAlContar = const FailureInesperado();
      await _montar(tester, repo: repo);

      expect(find.text('Casa · creada el 12/08'), findsOneWidget);
      expect(find.text('Guardar cambios'), findsOneWidget);
    });

    testWidgets('una ubicación creada otro año dice el año', (tester) async {
      await _montar(tester, ubicacion: ubicacionGuardada(creada: DateTime.utc(2025, 8, 12, 15)));

      expect(find.text('Casa · 2 espacios · creada el 12/08/2025'), findsOneWidget);
    });

    testWidgets('sin calle ni número la dirección dice «Sin dirección» y se les puede cargar', (
      tester,
    ) async {
      final e = await _montar(tester, ubicacion: ubicacionGuardada(calle: null, numero: null));

      expect(find.text('Sin dirección'), findsOneWidget);
      await _escribirCalle(tester, 'Av. Italia');
      await _tocar(tester, _guardar);

      expect(e.repo.escrituras.single.nueva.calle, 'Av. Italia');
      expect(e.repo.escrituras.single.nueva.numero, isNull);
    });

    testWidgets('si no se puede leer la campaña la ciudad dice «Ciudad» y se guarda igual', (
      tester,
    ) async {
      final e = await _montar(
        tester,
        ciudades: CiudadesFalsas()..fallaCampania = const FailureInesperado(),
      );

      expect(find.text('Ciudad'), findsOneWidget);
      expect(find.text('Montevideo'), findsNothing);
      await _escribirNumero(tester, '1238');
      await _tocar(tester, _guardar);

      expect(e.repo.escrituras.single.nueva.ciudadId, montevideo.id);
      expect(e.salidas.single, isA<UbicacionEditada>());
    });
  });

  group('artboard 07 · 02 «Mover el punto»', () {
    testWidgets('«Mover el punto» cambia el título y la hoja, y el mapa se puede mover', (
      tester,
    ) async {
      final e = await _montar(tester);

      await _tocar(tester, find.text('Mover el punto'));

      expect(find.text('MOVER EL PUNTO'), findsOneWidget);
      expect(find.text('EDITAR UBICACIÓN'), findsNothing);
      expect(find.text('Nueva posición'), findsOneWidget);
      expect(find.text('-34.88761, -56.13024'), findsOneWidget);
      expect(find.text('Guardar posición'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(_guardar, findsNothing);
      expect(find.text('Mover el punto'), findsNothing);
      expect(find.textContaining('Moviste el punto'), findsNothing);
      expect(find.byTooltip('Volver a mi ubicación'), findsOneWidget);
      expect(e.mapa.config!.interaccion, const InteraccionMapa());
      expect(find.textContaining('La dirección no cambia.'), findsOneWidget);
      expect(find.text('Usar 1250'), findsOneWidget);
    });

    testWidgets('al mover el mapa dice cuánto se movió y dibuja dónde estaba («Antes»)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final e = await _montar(tester);
      await _tocar(tester, find.text('Mover el punto'));
      expect(find.text('Antes'), findsNothing);

      await _moverMapa(tester, e, _norte18m);

      expect(find.text('Moviste el punto 18 m'), findsOneWidget);
      expect(find.text('Antes'), findsOneWidget);
      expect(find.bySemanticsLabel('Dónde estaba la ubicación antes de moverla'), findsOneWidget);
      expect(find.text('-34.88745, -56.13024'), findsOneWidget);
      expect(find.textContaining('Av. Italia 1250.'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('mover menos de un metro no cuenta como mover', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Mover el punto'));

      await _moverMapa(tester, e, 0.000001);

      expect(find.textContaining('Moviste el punto'), findsNothing);
      expect(find.text('Antes'), findsNothing);
    });

    testWidgets('«Usar 1250» toma el número del mapa y la calle igual no se ofrece', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Mover el punto'));
      await _moverMapa(tester, e, _norte18m);
      expect(find.text('Usar Av. Italia'), findsNothing);

      await _tocar(tester, find.text('Usar 1250'));
      await _tocar(tester, find.text('Guardar posición'));

      expect(find.widgetWithText(TextField, '1250'), findsOneWidget);
      expect(find.text('Editado'), findsOneWidget);
      expect(e.repo.escrituras, isEmpty, reason: 'todavía no se guardó nada');
    });

    testWidgets('si el mapa conoce otra calle, también se ofrece «Usar» para la calle', (
      tester,
    ) async {
      final e = await _montar(
        tester,
        geocodificador: GeocodificadorFalso(
          (_) => const DireccionDelPunto(calle: 'Av. Brasil', numero: '1250'),
        ),
      );
      await _tocar(tester, find.text('Mover el punto'));

      expect(find.text('Usar Av. Brasil'), findsOneWidget);
      expect(find.text('Usar 1250'), findsOneWidget);
      await _tocar(tester, find.text('Usar Av. Brasil'));
      await _tocar(tester, find.text('Guardar posición'));

      expect(find.widgetWithText(TextField, 'Av. Brasil'), findsOneWidget);
      expect(find.text('Editado'), findsOneWidget);
      expect(e.repo.escrituras, isEmpty);
    });

    testWidgets('«Guardar posición» pasa el punto al borrador sin escribir nada', (tester) async {
      final e = await _montar(tester);

      await _moverYGuardarPosicion(tester, e, _norte18m);

      expect(find.text('EDITAR UBICACIÓN'), findsOneWidget);
      expect(find.text('Av. Italia 1234'), findsOneWidget, reason: 'lo guardado no cambió');
      expect(_habilitado(tester, _guardar), isTrue);
      expect(e.repo.escrituras, isEmpty);
      expect(e.mapa.config!.interaccion, InteraccionMapa.ninguna);
      expect(e.mapa.camara!.centro.lat, closeTo(puntoItalia.lat + _norte18m, 1e-7));
    });

    testWidgets('«Cancelar» deja el borrador como estaba, con la dirección cargada', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Mover el punto'));
      await _moverMapa(tester, e, _norte18m);
      await _tocar(tester, find.text('Usar 1250'));

      await _tocar(tester, find.text('Cancelar'));

      expect(find.text('EDITAR UBICACIÓN'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1234'), findsOneWidget);
      expect(find.text('Editado'), findsNothing);
      expect(_habilitado(tester, _guardar), isFalse);
      expect(e.mapa.camara!.centro.lat, closeTo(puntoItalia.lat, 1e-7));
    });

    testWidgets('la ✕ y atrás en «Mover el punto» cancelan el ajuste, no cierran la pantalla', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Mover el punto'));
      await _moverMapa(tester, e, _norte18m);

      await _tocar(tester, _cerrar);
      expect(find.text('EDITAR UBICACIÓN'), findsOneWidget);
      expect(_habilitado(tester, _guardar), isFalse);

      await _tocar(tester, find.text('Mover el punto'));
      await _moverMapa(tester, e, _norte18m);
      await tester.binding.handlePopRoute();
      await _asentar(tester);

      expect(find.text('EDITAR UBICACIÓN'), findsOneWidget);
      expect(find.text('MOVER EL PUNTO'), findsNothing);
      expect(e.salidas, isEmpty);
    });

    testWidgets('un toque en el mapa pone el punto ahí', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Mover el punto'));

      e.mapa.tocar(_alNorte(_norte18m));
      await _asentar(tester);

      expect(find.text('-34.88745, -56.13024'), findsOneWidget);
      expect(find.text('Moviste el punto 18 m'), findsOneWidget);
    });

    testWidgets('un toque en el mapa fuera de «Mover el punto» no mueve nada', (tester) async {
      final e = await _montar(tester);

      e.mapa.tocar(_alNorte(_norte18m));
      await _asentar(tester);

      expect(_habilitado(tester, _guardar), isFalse);
      expect(find.text('Editado'), findsNothing);
    });

    testWidgets('«Volver a mi ubicación» lleva el pin a donde está el GPS', (tester) async {
      final gps = GpsFalso(Right(lecturaGps(5, punto: _alNorte(_norte18m))));
      final e = await _montar(tester, gps: gps);
      await _tocar(tester, find.text('Mover el punto'));

      await _tocar(tester, find.byTooltip('Volver a mi ubicación'));

      expect(find.text('-34.88745, -56.13024'), findsOneWidget);
      expect(find.text('Moviste el punto 18 m'), findsOneWidget);
      expect(e.mapa.config!.puntos.where((p) => p.estilo == EstiloPunto.gps), hasLength(1));
    });

    testWidgets('sin GPS avisa qué hacer y el pin no se mueve', (tester) async {
      final gps = GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.sinSenal)));
      await _montar(tester, gps: gps);
      await _tocar(tester, find.text('Mover el punto'));

      await _tocar(tester, find.byTooltip('Volver a mi ubicación'));

      expect(find.text(TextosModificar.sinGps), findsOneWidget);
      expect(find.text('-34.88761, -56.13024'), findsOneWidget);
    });

    testWidgets('dos pedidos de GPS seguidos: gana el último, aunque el primero llegue después', (
      tester,
    ) async {
      final primera = Completer<void>();
      final segunda = Completer<void>();
      final gps = GpsFalso()
        ..porLectura = (n) async {
          await (n == 1 ? primera : segunda).future;
          return Right(lecturaGps(5, punto: _alNorte(n == 1 ? _norte150m : _norte18m)));
        };
      await _montar(tester, gps: gps);
      await _tocar(tester, find.text('Mover el punto'));

      await tester.tap(find.byTooltip('Volver a mi ubicación'));
      await tester.pump();
      await tester.tap(find.byTooltip('Volver a mi ubicación'));
      await tester.pump();
      segunda.complete();
      await _asentar(tester);
      primera.complete();
      await _asentar(tester);

      expect(gps.lecturas, 2);
      expect(find.text('-34.88745, -56.13024'), findsOneWidget);
      expect(find.text('Moviste el punto 18 m'), findsOneWidget);
    });

    testWidgets('el guardado de la dirección del mapa que falla no rompe el ajuste', (
      tester,
    ) async {
      final geo = GeocodificadorFalso((_) => throw StateError('sin red'));
      final e = await _montar(tester, geocodificador: geo);
      await _tocar(tester, find.text('Mover el punto'));
      await _moverMapa(tester, e, _norte18m);

      expect(tester.takeException(), isNull);
      expect(find.text('Moviste el punto 18 m'), findsOneWidget);
      expect(find.text('La dirección no cambia.'), findsOneWidget);
      expect(find.textContaining('Usar'), findsNothing);
    });

    testWidgets('«Mover el punto» no se puede tocar mientras se guarda', (tester) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoEscritura = Completer<void>();
      await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1238');
      await tester.tap(_guardar);
      await tester.pump();

      await tester.tap(find.text('Mover el punto'), warnIfMissed: false);
      await _asentar(tester);

      expect(find.text('MOVER EL PUNTO'), findsNothing);
      expect(find.text('Guardando…'), findsOneWidget);
    });

    testWidgets('con el teclado abierto el botón «Mover el punto» se oculta', (tester) async {
      await _montar(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);

      await _asentar(tester);

      expect(find.text('Mover el punto'), findsNothing);
    });
  });

  group('artboard 07 · 03 «Guardado sin conexión»', () {
    testWidgets('sin conexión guarda en el celular y lo dice al volver al mapa', (tester) async {
      final e = await _montar(tester, conexion: TipoConexion.sinConexion);
      await _tocar(tester, find.text('Negocio'));

      await _tocar(tester, _guardar);

      expect(e.repo.escrituras, hasLength(1));
      expect(e.salidas.single, isA<UbicacionEditada>());
      expect(find.text('abrir'), findsOneWidget, reason: 'vuelve al mapa');
      expect(
        find.text(
          'Cambios guardados en tu celular. El estado se sincroniza cuando vuelva la conexión.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('con conexión vuelve al mapa sin ese aviso', (tester) async {
      final e = await _montar(tester, conexion: TipoConexion.wifi);
      await _tocar(tester, find.text('Negocio'));

      await _tocar(tester, _guardar);

      expect(e.salidas.single, isA<UbicacionEditada>());
      expect(find.text(TextosModificar.guardadoSinConexion), findsNothing);
    });

    testWidgets('si todavía no se sabe cómo está la conexión no afirma nada', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Negocio'));

      await _tocar(tester, _guardar);

      expect(e.salidas.single, isA<UbicacionEditada>());
      expect(find.text(TextosModificar.guardadoSinConexion), findsNothing);
    });

    testWidgets('guardar escribe tipo, calle, número y punto con la base de la edición', (
      tester,
    ) async {
      final e = await _montar(tester, conexion: TipoConexion.sinConexion);
      await _tocar(tester, find.text('Negocio'));
      await _escribirNumero(tester, '1238');

      await _tocar(tester, _guardar);

      final escritura = e.repo.escrituras.single;
      expect(escritura.baseUpdatedAt, tocadaElUltimoDia);
      expect(escritura.nueva.id, 'ubi-1');
      expect(escritura.nueva.tipo, TipoUbicacion.negocio);
      expect(escritura.nueva.calle, 'Av. Italia');
      expect(escritura.nueva.numero, '1238');
      expect(escritura.nueva.coordenadas, puntoItalia);
      expect(escritura.nueva.ciudadId, montevideo.id);
      expect(escritura.nueva.auditoria.updatedAt, DateTime.utc(2026, 10, 2, 12));
      expect(escritura.nueva.auditoria.createdAt, creadaEl12DeAgosto);
      final salida = e.salidas.single! as UbicacionEditada;
      expect(salida.ubicacion.numero, '1238');
      expect(salida.reactivada, isFalse);
    });
  });

  group('artboard 07 · 04 «Salir con cambios sin guardar»', () {
    testWidgets('la ✕ con cambios pregunta antes de descartarlos', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Negocio'));
      await _escribirNumero(tester, '1238');

      await _tocar(tester, _cerrar);

      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
      expect(
        find.text('Cambiaste el tipo y el número. Si salís ahora, se pierden.'),
        findsOneWidget,
      );
      expect(find.text('Seguir editando'), findsOneWidget);
      expect(find.text('Descartar'), findsOneWidget);
      expect(e.salidas, isEmpty);
    });

    testWidgets('«Seguir editando» vuelve a la edición con todo lo cargado', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Negocio'));
      await _escribirNumero(tester, '1238');
      await _tocar(tester, _cerrar);

      await _tocar(tester, find.text('Seguir editando'));

      expect(find.text('¿Descartar los cambios?'), findsNothing);
      expect(find.text('EDITAR UBICACIÓN'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1238'), findsOneWidget);
      expect(_habilitado(tester, _guardar), isTrue);
      expect(e.salidas, isEmpty);
    });

    testWidgets('«Descartar» cierra y no escribe nada en el teléfono', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Negocio'));
      await _escribirNumero(tester, '1238');
      await _tocar(tester, _cerrar);

      await _tocar(tester, find.text('Descartar'));

      expect(find.text('abrir'), findsOneWidget);
      expect(e.salidas.single, isNull);
      expect(e.repo.escrituras, isEmpty);
      expect(e.repo.actual, ubicacionGuardada(), reason: 'lo guardado sigue igual');
    });

    testWidgets('atrás del sistema con cambios hace la misma pregunta', (tester) async {
      final e = await _montar(tester);
      await _escribirNumero(tester, '1238');

      await tester.binding.handlePopRoute();
      await _asentar(tester);

      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
      expect(find.text('Cambiaste el número. Si salís ahora, se pierden.'), findsOneWidget);
      expect(e.salidas, isEmpty);
    });

    testWidgets('sin cambios la ✕ y atrás cierran sin preguntar', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, _cerrar);

      expect(find.text('¿Descartar los cambios?'), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
      expect(e.salidas.single, isNull);

      await _abrir(tester);
      await tester.binding.handlePopRoute();
      await _asentar(tester);

      expect(find.text('¿Descartar los cambios?'), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
      expect(e.salidas, hasLength(2));
    });

    testWidgets('doble toque en la ✕: una sola pregunta', (tester) async {
      await _montar(tester);
      await _escribirNumero(tester, '1238');

      await tester.tap(_cerrar);
      await tester.tap(_cerrar, warnIfMissed: false);
      await _asentar(tester);

      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
    });

    testWidgets('la pregunta lista lo que cambió, con comas y «y» al final', (tester) async {
      await _montar(tester);
      await _tocar(tester, find.text('Edificio'));
      await _escribirCalle(tester, 'Av. Brasil');
      await _escribirNumero(tester, '1238');

      await _tocar(tester, _cerrar);

      expect(
        find.text('Cambiaste el tipo, la calle y el número. Si salís ahora, se pierden.'),
        findsOneWidget,
      );
    });

    testWidgets('si lo que cambió es la posición o la ciudad, la pregunta lo dice', (tester) async {
      final e = await _montar(tester);
      await _moverYGuardarPosicion(tester, e, _norte18m);
      await _tocar(tester, find.text('Cambiar'));
      await _tocar(tester, find.text('Canelones'));

      await _tocar(tester, _cerrar);

      expect(
        find.text('Cambiaste la ciudad y la posición. Si salís ahora, se pierden.'),
        findsOneWidget,
      );
    });

    testWidgets('mientras guarda no se puede cerrar ni con la ✕ ni con atrás', (tester) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoEscritura = Completer<void>();
      final e = await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1238');
      await tester.tap(_guardar);
      await tester.pump();

      await tester.tap(_cerrar, warnIfMissed: false);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await _asentar(tester);

      expect(find.text('¿Descartar los cambios?'), findsNothing);
      expect(find.text('EDITAR UBICACIÓN'), findsOneWidget);
      expect(e.salidas, isEmpty);

      repo.bloqueoEscritura!.complete();
      await _asentar(tester);
      expect(e.salidas.single, isA<UbicacionEditada>());
    });
  });

  group('estados de la pantalla', () {
    testWidgets('cargando: dice que lee la ubicación y se puede cerrar', (tester) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoLectura = Completer<void>();
      final e = await _montar(tester, repo: repo);

      expect(find.text('Cargando la ubicación…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_guardar, findsNothing);
      expect(find.text('EDITAR UBICACIÓN'), findsOneWidget);

      await _tocar(tester, _cerrar);
      expect(e.salidas.single, isNull);

      // La lectura que llega con la pantalla ya cerrada no rompe nada.
      repo.bloqueoLectura!.complete();
      await _asentar(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la ubicación ya no está: lo dice y «Volver» cierra', (tester) async {
      final e = await _montar(tester, repo: RepoEdicionFalso(null));

      expect(
        find.text(
          'No encontramos esta ubicación en tu teléfono. Volvé a la lista y probá de nuevo.',
        ),
        findsOneWidget,
      );
      expect(_guardar, findsNothing);

      await _tocar(tester, find.text('Volver'));

      expect(find.text('abrir'), findsOneWidget);
      expect(e.salidas.single, isNull);
    });

    testWidgets('no se pudo leer: «Reintentar» vuelve a leer y abre la edición', (tester) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())..fallaAlLeer = const FailureInesperado();
      await _montar(tester, repo: repo);

      expect(find.text(TextosModificar.noPudimosAbrir), findsOneWidget);
      expect(find.text('No pudimos abrir esta ubicación. Probá de nuevo.'), findsOneWidget);
      expect(find.text('Ocurrió un error inesperado'), findsNothing);
      expect(_guardar, findsNothing);

      repo.fallaAlLeer = null;
      await _tocar(tester, find.text('Reintentar'));

      expect(find.text(TextosModificar.noPudimosAbrir), findsNothing);
      expect(find.text('Av. Italia 1234'), findsOneWidget);
      expect(repo.lecturas, 2);
    });

    testWidgets(
      'una lectura que lanza también deja reintentar, y mientras relee no hay otro botón',
      (tester) async {
        final repo = RepoEdicionFalso(ubicacionGuardada())..lanzaAlLeer = StateError('disco');
        await _montar(tester, repo: repo);
        expect(find.text(TextosModificar.noPudimosAbrir), findsOneWidget);

        repo
          ..lanzaAlLeer = null
          ..bloqueoLectura = Completer<void>();
        await tester.tap(find.text('Reintentar'));
        await tester.pump();
        expect(find.text('Reintentar'), findsNothing, reason: 'sin botón, no hay segundo toque');
        expect(find.text('Cargando la ubicación…'), findsOneWidget);
        repo.bloqueoLectura!.complete();
        await _asentar(tester);

        expect(repo.lecturas, 2);
        expect(find.text('Av. Italia 1234'), findsOneWidget);
      },
    );

    testWidgets('una falla de lectura con texto propio lo muestra', (tester) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())
        ..fallaAlLeer = const FailureUbicacionInexistente();
      await _montar(tester, repo: repo);

      expect(find.text(const FailureUbicacionInexistente().mensaje), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('guardando: el botón dice «Guardando…», no se toca y no se puede editar', (
      tester,
    ) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoEscritura = Completer<void>();
      final e = await _montar(tester, repo: repo, conBaja: true);
      await _escribirNumero(tester, '1238');

      await tester.tap(_guardar);
      await tester.pump();

      expect(_guardandoBoton, findsOneWidget);
      expect(_habilitado(tester, _guardandoBoton), isFalse);
      // Los campos no reciben teclas: lo que se ve es lo que se guarda.
      expect(tester.widget<TextField>(_campoCalle).readOnly, isTrue);
      expect(tester.widget<TextField>(_campoNumero).readOnly, isTrue);
      await tester.enterText(_campoNumero, '1238x');
      await tester.enterText(_campoCalle, 'Otra calle');
      await tester.pump();
      expect(tester.widget<TextField>(_campoNumero).controller!.text, '1238');
      expect(tester.widget<TextField>(_campoCalle).controller!.text, 'Av. Italia');
      await _tocar(tester, find.text('Negocio'));
      await tester.tap(find.text('Dar de baja'), warnIfMissed: false);
      await tester.pump();
      expect(e.dadasDeBaja, 0);

      repo.bloqueoEscritura!.complete();
      await _asentar(tester);
      expect(
        repo.escrituras.single.nueva.tipo,
        TipoUbicacion.casa,
        reason: 'el cambio de tipo no entró',
      );
      expect(repo.escrituras.single.nueva.numero, '1238', reason: 'lo tipeado después no entró');
      expect(repo.escrituras.single.nueva.calle, 'Av. Italia');
      expect(e.salidas.single, isA<UbicacionEditada>());
    });

    testWidgets('si el guardado falla mientras se seguía tipeando, el campo y el borrador coinciden', (
      tester,
    ) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoEscritura = Completer<void>();
      repo.comportamiento = (nueva, numero, _) async {
        if (numero == 1) return const Left(FailureInesperado());
        repo.actual = nueva;
        return Right(UbicacionModificada(ubicacion: nueva));
      };
      await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1238');

      await tester.tap(_guardar);
      await tester.pump();
      await tester.enterText(_campoNumero, '1238x');
      repo.bloqueoEscritura!.complete();
      await _asentar(tester);

      expect(find.text(TextosModificar.noPudimosGuardar), findsOneWidget);
      expect(tester.widget<TextField>(_campoNumero).controller!.text, '1238');
      expect(tester.widget<TextField>(_campoNumero).readOnly, isFalse);

      repo.bloqueoEscritura = null;
      await _tocar(tester, _guardar);
      expect(repo.escrituras.last.nueva.numero, '1238');
    });
  });

  group('mover menos de 1 m no es un cambio', () {
    testWidgets('volver a menos de 1 m de lo guardado deshace el cambio de posición', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _moverYGuardarPosicion(tester, e, _norte18m);
      expect(_habilitado(tester, _guardar), isTrue);

      await _moverYGuardarPosicion(tester, e, 0.000004);

      expect(_habilitado(tester, _guardar), isFalse, reason: 'quedó a menos de 1 m de lo guardado');
      await _tocar(tester, _cerrar);
      expect(find.text(TextosModificar.descartarTitulo), findsNothing);
      expect(e.salidas.single, isNull);
      expect(e.repo.escrituras, isEmpty);
    });

    testWidgets('con otro cambio, la posición a menos de 1 m no figura entre lo que se pierde', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _escribirNumero(tester, '1238');
      await _moverYGuardarPosicion(tester, e, 0.000004);

      await _tocar(tester, _cerrar);

      expect(find.textContaining('Cambiaste el número.'), findsOneWidget);
      expect(find.textContaining('la posición'), findsNothing);
    });

    testWidgets('un ajuste de más de 1 m sí cuenta y se guarda la posición nueva', (tester) async {
      final e = await _montar(tester);

      await _moverYGuardarPosicion(tester, e, _norte18m);

      expect(_habilitado(tester, _guardar), isTrue);
      await _tocar(tester, _guardar);
      expect(e.repo.escrituras.single.nueva.lat, closeTo(puntoItalia.lat + _norte18m, 1e-7));
    });
  });

  group('avisos literales de la HU', () {
    testWidgets('de edificio a otro tipo con espacios: avisa y no deja guardar', (tester) async {
      final e = await _montar(
        tester,
        ubicacion: ubicacionGuardada(tipo: TipoUbicacion.edificio),
        espacios: 3,
      );
      expect(find.textContaining('Borralos o reubicalos primero.'), findsNothing);

      await _tocar(tester, find.text('Casa'));

      expect(
        find.text('Esta ubicación tiene 3 espacios. Borralos o reubicalos primero.'),
        findsOneWidget,
      );
      expect(_habilitado(tester, _guardar), isFalse);
      expect(e.repo.escrituras, isEmpty);

      await _tocar(tester, find.text('Negocio'));
      expect(
        find.text('Esta ubicación tiene 3 espacios. Borralos o reubicalos primero.'),
        findsOneWidget,
      );

      await _tocar(tester, find.text('Edificio'));
      expect(find.textContaining('Borralos o reubicalos primero.'), findsNothing);
    });

    testWidgets('con un solo espacio el aviso va en singular', (tester) async {
      final e = await _montar(
        tester,
        ubicacion: ubicacionGuardada(tipo: TipoUbicacion.edificio),
        espacios: 1,
      );

      await _tocar(tester, find.text('Casa'));

      expect(
        find.text('Esta ubicación tiene 1 espacio. Borralo o reubicalo primero.'),
        findsOneWidget,
      );
      expect(find.textContaining('1 espacios'), findsNothing);
      expect(_habilitado(tester, _guardar), isFalse);
      expect(e.repo.escrituras, isEmpty);
    });

    testWidgets('con un solo espacio que aparece al guardar, el aviso también va en singular', (
      tester,
    ) async {
      final e = await _montar(
        tester,
        ubicacion: ubicacionGuardada(tipo: TipoUbicacion.edificio),
        espacios: 0,
      );
      e.repo.espacios = 1;
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, _guardar);

      expect(
        find.text('Esta ubicación tiene 1 espacio. Borralo o reubicalo primero.'),
        findsOneWidget,
      );
      expect(e.repo.escrituras, isEmpty);
    });

    testWidgets('de edificio sin espacios a otro tipo se guarda', (tester) async {
      final e = await _montar(
        tester,
        ubicacion: ubicacionGuardada(tipo: TipoUbicacion.edificio),
        espacios: 0,
      );

      await _tocar(tester, find.text('Casa'));
      expect(find.textContaining('Borralos o reubicalos primero.'), findsNothing);
      await _tocar(tester, _guardar);

      expect(e.repo.escrituras.single.nueva.tipo, TipoUbicacion.casa);
    });

    testWidgets('de casa a edificio con espacios no se bloquea', (tester) async {
      final e = await _montar(tester);

      await _tocar(tester, find.text('Edificio'));
      expect(find.textContaining('Borralos o reubicalos primero.'), findsNothing);
      await _tocar(tester, _guardar);

      expect(e.repo.escrituras.single.nueva.tipo, TipoUbicacion.edificio);
    });

    testWidgets('si los espacios cambiaron desde que se abrió, el guardado lo dice una sola vez', (
      tester,
    ) async {
      final e = await _montar(
        tester,
        ubicacion: ubicacionGuardada(tipo: TipoUbicacion.edificio),
        espacios: 0,
      );
      e.repo.espacios = 3;
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, _guardar);

      expect(
        find.text('Esta ubicación tiene 3 espacios. Borralos o reubicalos primero.'),
        findsOneWidget,
      );
      expect(e.repo.escrituras, isEmpty);
      expect(_habilitado(tester, _guardar), isTrue, reason: 'puede volver a intentarlo');
    });

    testWidgets('si no se pueden contar los espacios, el guardado de edificio a otro tipo falla', (
      tester,
    ) async {
      final repo = RepoEdicionFalso(ubicacionGuardada(tipo: TipoUbicacion.edificio))
        ..fallaAlContar = const FailureInesperado();
      await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, _guardar);

      expect(find.text(TextosModificar.noPudimosGuardar), findsOneWidget);
      expect(repo.escrituras, isEmpty);
    });

    testWidgets('más de 100 m: «Las nuevas coordenadas están a 150m…» y «Confirmar» guarda', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _moverYGuardarPosicion(tester, e, _norte150m);

      await _tocar(tester, _guardar);

      expect(
        find.text('Las nuevas coordenadas están a 150m de la ubicación original. ¿Confirmás?'),
        findsOneWidget,
      );
      expect(e.repo.escrituras, isEmpty);

      await _tocar(tester, find.text('Confirmar'));

      expect(e.repo.escrituras, hasLength(1));
      expect(e.repo.escrituras.single.nueva.coordenadas, _alNorte(_norte150m));
      expect(e.salidas.single, isA<UbicacionEditada>());
    });

    testWidgets('más de 100 m: «Cancelar» no guarda y el borrador sigue acá', (tester) async {
      final e = await _montar(tester);
      await _moverYGuardarPosicion(tester, e, _norte150m);
      await _tocar(tester, _guardar);

      await _tocar(tester, find.text('Cancelar'));

      expect(e.repo.escrituras, isEmpty);
      expect(e.salidas, isEmpty);
      expect(find.text('EDITAR UBICACIÓN'), findsOneWidget);
      expect(_habilitado(tester, _guardar), isTrue);

      // Se puede volver a intentar: la pregunta se hace de nuevo.
      await _tocar(tester, _guardar);
      expect(find.textContaining('Las nuevas coordenadas están a 150m'), findsOneWidget);
      await _tocar(tester, find.text('Confirmar'));
      expect(e.repo.escrituras, hasLength(1));
    });

    testWidgets('hasta 100 m no pregunta', (tester) async {
      final e = await _montar(tester);
      await _moverYGuardarPosicion(tester, e, 0.0008);

      await _tocar(tester, _guardar);

      expect(find.textContaining('Las nuevas coordenadas están a'), findsNothing);
      expect(e.repo.escrituras, hasLength(1));
    });

    testWidgets('una ubicación en baja: «¿Reactivarla al guardar?» y al confirmar la reactiva', (
      tester,
    ) async {
      final e = await _montar(
        tester,
        ubicacion: ubicacionGuardada(deBajaDesde: DateTime.utc(2026, 9, 1, 12)),
      );
      await _escribirNumero(tester, '1238');

      await _tocar(tester, _guardar);

      expect(find.text('Esta ubicación está en baja. ¿Reactivarla al guardar?'), findsOneWidget);
      expect(e.repo.escrituras, isEmpty);

      await _tocar(tester, find.text('Confirmar'));

      expect(e.repo.escrituras.single.nueva.auditoria.deletedAt, isNull);
      final salida = e.salidas.single! as UbicacionEditada;
      expect(salida.reactivada, isTrue);
    });

    testWidgets('una ubicación en baja: «Cancelar» no la reactiva ni guarda', (tester) async {
      final e = await _montar(
        tester,
        ubicacion: ubicacionGuardada(deBajaDesde: DateTime.utc(2026, 9, 1, 12)),
      );
      await _escribirNumero(tester, '1238');
      await _tocar(tester, _guardar);

      await _tocar(tester, find.text('Cancelar'));

      expect(e.repo.escrituras, isEmpty);
      expect(e.repo.actual!.estaBorrada, isTrue);
      expect(e.salidas, isEmpty);
    });

    testWidgets('cambiar la ciudad pide confirmación y guarda la nueva', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Cambiar'));
      expect(find.text('Elegí la ciudad'), findsOneWidget);
      await _tocar(tester, find.text('Canelones'));

      expect(find.text('Elegí la ciudad'), findsNothing);
      expect(find.text('Canelones'), findsOneWidget);
      expect(find.text('Editado'), findsOneWidget);
      expect(_habilitado(tester, _guardar), isTrue);

      await _tocar(tester, _guardar);
      expect(
        find.text(
          'Cambiar la ciudad reubica esta ubicación en otra zona del mapa. ¿Confirmás el cambio?',
        ),
        findsOneWidget,
      );
      await _tocar(tester, find.text('Confirmar'));

      expect(e.repo.escrituras.single.nueva.ciudadId, canelones.id);
      expect(e.salidas.single, isA<UbicacionEditada>());
    });

    testWidgets('elegir la misma ciudad no es un cambio', (tester) async {
      await _montar(tester);
      await _tocar(tester, find.text('Cambiar'));
      await _tocar(tester, find.text('Canelones'));
      await _tocar(tester, find.text('Cambiar'));

      await _tocar(tester, find.text('Montevideo'));

      expect(find.text('Editado'), findsNothing);
      expect(_habilitado(tester, _guardar), isFalse);
    });

    testWidgets('reactivar, cambiar de ciudad y mover más de 100 m: tres preguntas, en ese orden', (
      tester,
    ) async {
      final e = await _montar(
        tester,
        ubicacion: ubicacionGuardada(deBajaDesde: DateTime.utc(2026, 9, 1, 12)),
      );
      await _moverYGuardarPosicion(tester, e, _norte150m);
      await _tocar(tester, find.text('Cambiar'));
      await _tocar(tester, find.text('Canelones'));
      await _tocar(tester, _guardar);

      expect(find.textContaining('¿Reactivarla al guardar?'), findsOneWidget);
      await _tocar(tester, find.text('Confirmar'));
      expect(find.textContaining('Cambiar la ciudad reubica'), findsOneWidget);
      await _tocar(tester, find.text('Confirmar'));
      expect(find.textContaining('Las nuevas coordenadas están a 150m'), findsOneWidget);
      expect(e.repo.escrituras, isEmpty, reason: 'todavía falta una');
      await _tocar(tester, find.text('Confirmar'));

      expect(e.repo.escrituras, hasLength(1), reason: 'una sola escritura con las tres');
      final salida = e.salidas.single! as UbicacionEditada;
      expect(salida.reactivada, isTrue);
      expect(salida.ubicacion.ciudadId, canelones.id);
    });

    testWidgets('cancelar la segunda de tres preguntas no guarda nada', (tester) async {
      final e = await _montar(
        tester,
        ubicacion: ubicacionGuardada(deBajaDesde: DateTime.utc(2026, 9, 1, 12)),
      );
      await _tocar(tester, find.text('Cambiar'));
      await _tocar(tester, find.text('Canelones'));
      await _tocar(tester, _guardar);
      await _tocar(tester, find.text('Confirmar'));
      expect(find.textContaining('Cambiar la ciudad reubica'), findsOneWidget);

      await _tocar(tester, find.text('Cancelar'));

      expect(e.repo.escrituras, isEmpty);
      expect(e.salidas, isEmpty);
      expect(find.text('EDITAR UBICACIÓN'), findsOneWidget);
    });

    testWidgets('cerrar la pregunta sin elegir es lo mismo que cancelar', (tester) async {
      final e = await _montar(tester);
      await _moverYGuardarPosicion(tester, e, _norte150m);
      await _tocar(tester, _guardar);

      await tester.tapAt(const Offset(5, 5));
      await _asentar(tester);

      expect(find.textContaining('Las nuevas coordenadas están a'), findsNothing);
      expect(e.repo.escrituras, isEmpty);
      expect(_habilitado(tester, _guardar), isTrue);
    });
  });

  group('aviso de duplicado (vista 04, desde la edición)', () {
    Future<_Escenario> montarConDuplicada(WidgetTester tester, {int? hastaLlamada}) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())
        ..comportamiento = (u, n, _) async => n == 1
            ? Right(ModificacionConDuplicados(candidatas: [candidata('existente')]))
            : Right(UbicacionModificada(ubicacion: u));
      final e = await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1236');
      await _tocar(tester, _guardar);
      return e;
    }

    testWidgets('un cambio que deja la ubicación junto a otra abre el aviso y no guarda', (
      tester,
    ) async {
      final e = await montarConDuplicada(tester);

      expect(find.text('Ya existe una ubicación a 12 m'), findsOneWidget);
      expect(find.text('Reutilizar esta'), findsOneWidget);
      expect(find.text('Crear igual'), findsOneWidget);
      expect(e.salidas, isEmpty);
      expect(e.repo.actual, ubicacionGuardada());
    });

    testWidgets('«Cancelar» vuelve a la edición con todo lo cargado', (tester) async {
      final e = await montarConDuplicada(tester);

      await _tocar(tester, find.text('Cancelar'));

      expect(find.text('Ya existe una ubicación a 12 m'), findsNothing);
      expect(find.text('EDITAR UBICACIÓN'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1236'), findsOneWidget);
      expect(_habilitado(tester, _guardar), isTrue);
      expect(e.salidas, isEmpty);
    });

    testWidgets('«Reutilizar esta» abre la otra ubicación y no guarda la edición', (tester) async {
      final e = await montarConDuplicada(tester);

      await _tocar(tester, find.text('Reutilizar esta'));

      final salida = e.salidas.single;
      expect(salida, isA<UbicacionExistenteElegida>());
      expect((salida! as UbicacionExistenteElegida).ubicacionId, 'existente');
      expect(e.repo.escrituras, hasLength(1), reason: 'solo el intento que dio candidatas');
      expect(e.repo.actual, ubicacionGuardada());
    });

    testWidgets('«Crear igual» con la justificación guarda lo editado', (tester) async {
      final e = await montarConDuplicada(tester);
      await _tocar(tester, find.text('Crear igual'));
      expect(find.text('¿Por qué es otra ubicación?'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'Es el local de al lado');
      await tester.pump();
      await _tocar(tester, find.widgetWithText(FilledButton, 'Crear igual'));

      expect(e.repo.escrituras, hasLength(2));
      expect(e.repo.escrituras.last.nueva.numero, '1236');
      expect(e.repo.escrituras.last.duplicados, isNotNull);
      expect(e.salidas.single, isA<UbicacionEditada>());
      expect(find.text('abrir'), findsOneWidget);
    });

    testWidgets('doble toque en «Crear igual»: una sola escritura más', (tester) async {
      final e = await montarConDuplicada(tester);
      await _tocar(tester, find.text('Crear igual'));
      await tester.enterText(find.byType(TextField).last, 'Es el local de al lado');
      await tester.pump();
      e.repo.bloqueoEscritura = Completer<void>();

      final crear = find.widgetWithText(FilledButton, 'Crear igual');
      await tester.tap(crear);
      await tester.tap(crear, warnIfMissed: false);
      await tester.pump();
      e.repo.bloqueoEscritura!.complete();
      await _asentar(tester);

      expect(e.repo.escrituras, hasLength(2));
      expect(e.salidas, hasLength(1));
    });

    testWidgets('«Crear igual» que falla: el mensaje y el botón vuelve a habilitarse', (
      tester,
    ) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())
        ..comportamiento = (u, n, _) async => switch (n) {
          1 => Right(ModificacionConDuplicados(candidatas: [candidata('existente')])),
          2 => const Left(FailureInesperado()),
          _ => Right(UbicacionModificada(ubicacion: u)),
        };
      final e = await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1236');
      await _tocar(tester, _guardar);
      await _tocar(tester, find.text('Crear igual'));
      await tester.enterText(find.byType(TextField).last, 'Es el local de al lado');
      await tester.pump();

      await _tocar(tester, find.widgetWithText(FilledButton, 'Crear igual'));

      expect(e.salidas, isEmpty);
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Crear igual')).onPressed,
        isNotNull,
      );

      await _tocar(tester, find.widgetWithText(FilledButton, 'Crear igual'));
      expect(e.salidas.single, isA<UbicacionEditada>());
      expect(repo.escrituras, hasLength(3));
    });

    testWidgets('las confirmaciones que ya se dieron no se vuelven a preguntar al «Crear igual»', (
      tester,
    ) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())
        ..comportamiento = (u, n, _) async => n == 1
            ? Right(ModificacionConDuplicados(candidatas: [candidata('existente')]))
            : Right(UbicacionModificada(ubicacion: u));
      final e = await _montar(tester, repo: repo);
      await _moverYGuardarPosicion(tester, e, _norte150m);
      await _tocar(tester, _guardar);
      await _tocar(tester, find.text('Confirmar'));
      expect(find.text('Crear igual'), findsOneWidget);

      await _tocar(tester, find.text('Crear igual'));
      await tester.enterText(find.byType(TextField).last, 'Es el local de al lado');
      await tester.pump();
      await _tocar(tester, find.widgetWithText(FilledButton, 'Crear igual'));

      expect(find.textContaining('Las nuevas coordenadas están a'), findsNothing);
      expect(repo.escrituras, hasLength(2));
      expect(e.salidas.single, isA<UbicacionEditada>());
    });

    testWidgets('«Crear igual» de una ubicación en baja dice que la reactivó', (tester) async {
      final repo = RepoEdicionFalso(ubicacionGuardada(deBajaDesde: DateTime.utc(2026, 9, 1, 12)))
        ..comportamiento = (u, n, _) async => n == 1
            ? Right(ModificacionConDuplicados(candidatas: [candidata('existente')]))
            : Right(UbicacionModificada(ubicacion: u));
      final e = await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1236');
      await _tocar(tester, _guardar);
      await _tocar(tester, find.text('Confirmar'));

      await _tocar(tester, find.text('Crear igual'));
      await tester.enterText(find.byType(TextField).last, 'Es el local de al lado');
      await tester.pump();
      await _tocar(tester, find.widgetWithText(FilledButton, 'Crear igual'));

      expect((e.salidas.single! as UbicacionEditada).reactivada, isTrue);
    });

    testWidgets('sin «Crear igual» (misma dirección a menos de 100 m) solo se puede reutilizar', (
      tester,
    ) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())
        ..comportamiento = (u, n, _) async => Right(
          ModificacionConDuplicados(
            candidatas: [candidata('existente', metros: 15, admiteConservarAmbos: false)],
          ),
        );
      await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1236');

      await _tocar(tester, _guardar);

      expect(find.text('Crear igual'), findsNothing);
      expect(find.text('Reutilizar esta'), findsNothing);
      expect(find.text('Abrir la existente'), findsOneWidget);
    });
  });

  group('cambio concurrente y fallas al guardar', () {
    testWidgets('si la ubicación cambió mientras se editaba, avisa y no deja guardar encima', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _escribirNumero(tester, '1238');
      // El pull trajo una corrección del coordinador mientras tanto.
      e.repo.actual = ubicacionGuardada(
        tipo: TipoUbicacion.negocio,
        actualizada: DateTime.utc(2026, 10, 1, 9),
      );

      await _tocar(tester, _guardar);

      expect(
        find.text(
          'Esta ubicación cambió mientras la editabas. Abrila de nuevo y repetí el cambio.',
        ),
        findsOneWidget,
      );
      expect(e.repo.escrituras, isEmpty, reason: 'no se pisó nada');
      expect(find.widgetWithText(TextField, '1238'), findsOneWidget, reason: 'el borrador sigue');
      expect(_habilitado(tester, _guardar), isFalse);

      // Seguir editando no la vuelve a habilitar ni borra el aviso.
      await _escribirNumero(tester, '1240');
      expect(_habilitado(tester, _guardar), isFalse);
      expect(find.textContaining('Esta ubicación cambió mientras la editabas.'), findsOneWidget);
    });

    testWidgets('después del cambio concurrente se descarta y se reabre con lo nuevo', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _escribirNumero(tester, '1238');
      e.repo.actual = ubicacionGuardada(
        tipo: TipoUbicacion.negocio,
        actualizada: DateTime.utc(2026, 10, 1, 9),
      );
      await _tocar(tester, _guardar);

      await _tocar(tester, _cerrar);
      await _tocar(tester, find.text('Descartar'));
      await _abrir(tester);

      expect(find.text('Negocio · 2 espacios · creada el 12/08'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1234'), findsOneWidget);
      expect(_habilitado(tester, _guardar), isFalse);
      await _tocar(tester, find.text('Edificio'));
      await _tocar(tester, _guardar);
      expect(e.repo.escrituras, hasLength(1));
    });

    testWidgets('un doble envío que ya entró cierra como guardado, sin escribir otra vez', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _escribirNumero(tester, '1238');
      e.repo.actual = ubicacionGuardada(numero: '1238', actualizada: DateTime.utc(2026, 10, 2, 11));

      await _tocar(tester, _guardar);

      expect(e.repo.escrituras, isEmpty);
      expect((e.salidas.single! as UbicacionEditada).ubicacion.numero, '1238');
    });

    testWidgets('si falla a mitad: avisa, el botón vuelve y lo cargado se conserva', (
      tester,
    ) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())
        ..comportamiento = (u, n, _) async =>
            n == 1 ? const Left(FailureInesperado()) : Right(UbicacionModificada(ubicacion: u));
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Negocio'));
      await _escribirNumero(tester, '1238');

      await _tocar(tester, _guardar);

      expect(find.text(TextosModificar.noPudimosGuardar), findsOneWidget);
      expect(find.text('Ocurrió un error inesperado'), findsNothing);
      expect(_habilitado(tester, _guardar), isTrue);
      expect(_guardandoBoton, findsNothing);
      expect(find.widgetWithText(TextField, '1238'), findsOneWidget);
      expect(e.salidas, isEmpty);

      await _tocar(tester, _guardar);

      expect(find.text(TextosModificar.noPudimosGuardar), findsNothing);
      expect(e.salidas.single, isA<UbicacionEditada>());
      expect(repo.escrituras.last.nueva.numero, '1238');
      expect(repo.escrituras.last.nueva.tipo, TipoUbicacion.negocio);
    });

    testWidgets('una escritura que lanza deja el botón habilitado, no «Guardando…» para siempre', (
      tester,
    ) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())
        ..comportamiento = (u, n, _) async =>
            n == 1 ? throw StateError('disco lleno') : Right(UbicacionModificada(ubicacion: u));
      final e = await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1238');

      await _tocar(tester, _guardar);

      expect(find.text(TextosModificar.noPudimosGuardar), findsOneWidget);
      expect(_guardandoBoton, findsNothing);
      expect(_habilitado(tester, _guardar), isTrue);
      expect(tester.takeException(), isNull);

      await _tocar(tester, _guardar);
      expect(e.salidas.single, isA<UbicacionEditada>());
    });

    testWidgets('las fallas con texto propio lo conservan', (tester) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())
        ..comportamiento = (u, n, _) async => const Left(FailureUbicacionAjenaFueraDeZona());
      await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1238');

      await _tocar(tester, _guardar);

      expect(find.text(const FailureUbicacionAjenaFueraDeZona().mensaje), findsOneWidget);
      expect(_habilitado(tester, _guardar), isTrue);
    });

    testWidgets('el aviso de falla se va al seguir editando', (tester) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())
        ..comportamiento = (u, n, _) async => const Left(FailureInesperado());
      await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1238');
      await _tocar(tester, _guardar);
      expect(find.text(TextosModificar.noPudimosGuardar), findsOneWidget);

      await _escribirNumero(tester, '1239');

      expect(find.text(TextosModificar.noPudimosGuardar), findsNothing);
    });

    testWidgets('doble toque en «Guardar cambios»: una sola escritura', (tester) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoEscritura = Completer<void>();
      final e = await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1238');

      await _traer(tester, _guardar);
      await tester.tap(_guardar);
      await tester.tap(_guardar, warnIfMissed: false);
      repo.bloqueoEscritura!.complete();
      await _asentar(tester);

      expect(repo.escrituras, hasLength(1));
      expect(e.salidas, hasLength(1));
    });

    testWidgets('dos cambios seguidos antes de guardar entran los dos en una escritura', (
      tester,
    ) async {
      final e = await _montar(tester);

      await tester.tap(find.text('Edificio'));
      await tester.enterText(_campoNumero, '1238');
      await tester.pump();
      await _tocar(tester, _guardar);

      final nueva = e.repo.escrituras.single.nueva;
      expect(nueva.tipo, TipoUbicacion.edificio);
      expect(nueva.numero, '1238');
    });

    testWidgets('sin cambios, un guardado forzado no escribe nada', (tester) async {
      final e = await _montar(tester);

      // El botón está deshabilitado: ni siquiera con un toque directo.
      await tester.tap(_guardar, warnIfMissed: false);
      await _asentar(tester);

      expect(e.repo.escrituras, isEmpty);
      expect(e.salidas, isEmpty);
    });
  });

  group('volver atrás y reentrar', () {
    testWidgets('lo que se descartó no aparece al volver a abrir', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Negocio'));
      await _escribirNumero(tester, '1238');
      await _tocar(tester, _cerrar);
      await _tocar(tester, find.text('Descartar'));

      await _abrir(tester);

      expect(find.widgetWithText(TextField, '1234'), findsOneWidget);
      expect(find.text('Editado'), findsNothing);
      expect(_habilitado(tester, _guardar), isFalse);
      expect(e.repo.lecturas, 2, reason: 'cada apertura lee de nuevo');
    });

    testWidgets('lo guardado aparece al volver a abrir', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Negocio'));
      await _escribirNumero(tester, '1238');
      await _tocar(tester, _guardar);
      expect(e.salidas.single, isA<UbicacionEditada>());

      await _abrir(tester);

      expect(find.text('Av. Italia 1238'), findsOneWidget);
      expect(find.text('Negocio · 2 espacios · creada el 12/08'), findsOneWidget);
      expect(_habilitado(tester, _guardar), isFalse);
    });

    testWidgets('«Mover el punto» no arrastra el ajuste de la apertura anterior', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Mover el punto'));
      await _moverMapa(tester, e, _norte18m);
      await _tocar(tester, _cerrar);
      await _tocar(tester, _cerrar);
      expect(e.salidas.single, isNull);

      await _abrir(tester);
      await _tocar(tester, find.text('Mover el punto'));

      expect(find.text('-34.88761, -56.13024'), findsOneWidget);
      expect(find.textContaining('Moviste el punto'), findsNothing);
    });

    testWidgets('«Mover el punto» dos veces seguidas parte del punto del borrador', (tester) async {
      final e = await _montar(tester);
      await _moverYGuardarPosicion(tester, e, _norte18m);

      await _tocar(tester, find.text('Mover el punto'));

      expect(find.text('-34.88745, -56.13024'), findsOneWidget);
      expect(find.text('Moviste el punto 18 m'), findsOneWidget);
      await _tocar(tester, find.text('Cancelar'));
      expect(find.text('EDITAR UBICACIÓN'), findsOneWidget);
      expect(
        _habilitado(tester, _guardar),
        isTrue,
        reason: 'el punto de antes sigue en el borrador',
      );
    });
  });

  group('datos límite', () {
    testWidgets(
      'calle y número en el largo máximo se muestran, se editan y se guardan sin desbordar',
      (tester) async {
        final e = await _montar(
          tester,
          ubicacion: ubicacionGuardada(calle: 'C' * 120, numero: '9' * 20),
          escala: 2,
          tamano: const Size(360, 640),
        );

        expect(tester.takeException(), isNull);
        await _escribirCalle(tester, 'D' * 120);
        await _escribirNumero(tester, '8' * 20);
        await _tocar(tester, _guardar);

        expect(tester.takeException(), isNull);
        final nueva = e.repo.escrituras.single.nueva;
        expect(nueva.calle, 'D' * 120);
        expect(nueva.numero, '8' * 20);
      },
    );

    testWidgets('lo que se escribe de más sobre el largo máximo se corta', (tester) async {
      final e = await _montar(tester);

      await _escribirCalle(tester, 'D' * 200);
      await _escribirNumero(tester, '8' * 40);
      await _tocar(tester, _guardar);

      final nueva = e.repo.escrituras.single.nueva;
      expect(nueva.calle, 'D' * 120);
      expect(nueva.numero, '8' * 20);
    });

    testWidgets('una dirección larguísima en el encabezado no se desborda a texto 2x', (
      tester,
    ) async {
      await _montar(
        tester,
        ubicacion: ubicacionGuardada(calle: 'Avenida del Libertador General ${'San Martín ' * 8}'),
        escala: 2,
        tamano: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Avenida del Libertador General'), findsWidgets);
    });

    testWidgets('un nombre de ciudad larguísimo no se desborda a texto 2x', (tester) async {
      final larga = CiudadCatalogo(id: 'ciu-mvd', nombre: 'San José de Mayo ${'del Este ' * 12}');
      await _montar(
        tester,
        ciudades: CiudadesFalsas(campania: [larga]),
        escala: 2,
        tamano: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('San José de Mayo'), findsOneWidget);
    });

    testWidgets('un catálogo de 40 ciudades se recorre y se elige la última', (tester) async {
      final catalogo = [
        montevideo,
        for (var i = 0; i < 40; i++) CiudadCatalogo(id: 'c$i', nombre: 'Ciudad $i'),
      ];
      final e = await _montar(
        tester,
        ciudades: CiudadesFalsas(campania: catalogo),
        escala: 2,
        tamano: const Size(360, 640),
      );

      await _tocar(tester, find.textContaining('Cambiar'));
      await tester.scrollUntilVisible(
        find.text('Ciudad 39'),
        300,
        scrollable: find
            .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
            .first,
      );
      await tester.tap(find.text('Ciudad 39'));
      await _asentar(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Ciudad 39'), findsOneWidget);
      await _tocar(tester, _guardar);
      await _tocar(tester, find.text('Confirmar'));
      expect(e.repo.escrituras.single.nueva.ciudadId, 'c39');
    });

    for (final (nombre, tamano, escala) in <(String, Size, double)>[
      ('360×640', const Size(360, 640), 1.0),
      ('412×915', const Size(412, 915), 1.0),
      ('360×640 con texto a 200 %', const Size(360, 640), 2.0),
    ]) {
      testWidgets('«Editar datos» cumple las guías de accesibilidad en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        await _montar(tester, tamano: tamano, escala: escala, conBaja: true);
        // Sin desplazar la hoja: un campo a medio ver tendría un blanco de toque recortado.
        await tester.enterText(_campoNumero, '1238');
        await _asentar(tester);

        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });

      testWidgets('«Mover el punto» cumple las guías de accesibilidad en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        final e = await _montar(tester, tamano: tamano, escala: escala);
        await _tocar(tester, find.text('Mover el punto'));
        await _moverMapa(tester, e, _norte18m);

        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('el aviso de edificio con espacios a texto 2x no se desborda y cumple las guías', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(
        tester,
        ubicacion: ubicacionGuardada(tipo: TipoUbicacion.edificio),
        espacios: 12,
        escala: 2,
        tamano: const Size(360, 640),
      );
      await _tocar(tester, find.text('Casa'));

      expect(
        find.text('Esta ubicación tiene 12 espacios. Borralos o reubicalos primero.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('la pregunta de descartar a texto 2x no se desborda', (tester) async {
      await _montar(tester, escala: 2, tamano: const Size(360, 640));
      await _tocar(tester, find.text('Edificio'));
      await _escribirCalle(tester, 'Av. Brasil');
      await _escribirNumero(tester, '1238');

      await _tocar(tester, _cerrar);

      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('los estados de carga y de error a texto 2x no se desbordan', (tester) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())..fallaAlLeer = const FailureInesperado();
      await _montar(tester, repo: repo, escala: 2, tamano: const Size(360, 640));

      expect(find.text(TextosModificar.noPudimosAbrir), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
