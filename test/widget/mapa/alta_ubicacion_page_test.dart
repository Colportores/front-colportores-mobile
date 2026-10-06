// Vista 03 «Alta de ubicación» (HU-UBI-001, #193): un test por artboard del canvas, por escenario de
// la HU y por caso límite (doble toque, falla a mitad, reentrada, datos límite, texto a 200 %).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/data/services/fuentes_sin_adaptador_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/services/resolutores_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_duplicado_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:dartz/dartz.dart' show Left, Right;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/mapa_base_falso.dart';

/// Atajo: el GPS que no da ubicación por [motivo].
GpsFalso _gpsSin(MotivoSinGps motivo) => GpsFalso(Left(FailureGpsNoDisponible(motivo: motivo)));

/// La pantalla que abre el alta y guarda cómo se cerró.
class _Anfitrion extends StatelessWidget {
  const _Anfitrion({required this.salidas, this.puntoInicial});

  final List<SalidaAltaUbicacion?> salidas;
  final Coordenadas? puntoInicial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async => salidas.add(
            await AltaUbicacionPage.abrir(
              context,
              colportorId: 'col-1',
              puntoInicial: puntoInicial,
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
    required this.gps,
    required this.geocodificador,
    required this.ciudades,
    required this.repo,
    required this.mapa,
  });

  final GpsFalso gps;
  final GeocodificadorFalso geocodificador;
  final CiudadesFalsas ciudades;
  final RepoAltaFalso repo;

  /// La vista del mapa (MapLibre no se dibuja en `flutter test`): su cámara y lo que se le pidió dibujar.
  final FabricaMapaFalsa mapa;
  final salidas = <SalidaAltaUbicacion?>[];
}

Future<void> _asentar(WidgetTester tester, [int veces = 6]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_Escenario> _montar(
  WidgetTester tester, {
  GpsFalso? gps,
  GeocodificadorFalso? geocodificador,
  CiudadesFalsas? ciudades,
  RepoAltaFalso? repo,
  double escala = 1,
  Size tamano = const Size(390, 844),
  Coordenadas? puntoInicial,
  bool abrir = true,
  List<MarcadorMapa> marcadores = const [],
  CiudadesParaAlta? puertoCiudades,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = _Escenario(
    gps: gps ?? GpsFalso(),
    geocodificador:
        geocodificador ??
        GeocodificadorFalso((_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1234')),
    ciudades: ciudades ?? CiudadesFalsas(),
    repo: repo ?? RepoAltaFalso(),
    mapa: FabricaMapaFalsa(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesAlta(
        gps: e.gps,
        geocodificador: e.geocodificador,
        ciudades: e.ciudades,
        puertoCiudades: puertoCiudades,
        repo: e.repo,
        ahora: DateTime.utc(2026, 10, 2, 12),
        marcadores: marcadores,
        mapa: e.mapa,
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: _Anfitrion(salidas: e.salidas, puntoInicial: puntoInicial),
      ),
    ),
  );
  if (abrir) {
    await tester.tap(find.text('abrir'));
    await _asentar(tester);
  }
  return e;
}

/// Deja [f] a la vista en la hoja. Primero deja que el árbol se rearme (un `enterText` previo cambia
/// el alto de la hoja recién en el próximo cuadro) y solo desplaza la hoja si [f] no se alcanza: sin
/// eso, `ensureVisible` llevaba el texto al borde de arriba y dejaba el botón cortado, y las guías de
/// accesibilidad medían un botón de 36 en vez de 52.
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

Finder get _registrar => find.widgetWithText(FilledButton, TextosAlta.registrar);

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<FilledButton>(boton).onPressed != null;

Finder get _mapa => find.byType(MapaBase).first;

/// Lo que está dentro de la hoja inferior abierta (y no en el alta que queda debajo).
Finder _enHoja(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

/// Ningún resto de los estados que Cristian sacó (02/10): «no encontrada», «ambigua» ni «Solicitar alta».
void _sinEstadosViejos() {
  expect(find.text('Solicitar alta de ciudad al administrador'), findsNothing);
  expect(find.text('Seleccionar ciudad manualmente'), findsNothing);
  expect(find.textContaining('No encontramos la ciudad'), findsNothing);
  expect(find.textContaining('cerca del límite'), findsNothing);
  expect(find.textContaining('le avisamos al administrador'), findsNothing);
}

/// El borde punteado de la gota del pin sin colocar.
Finder get _bordePunteado =>
    find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BordePunteadoGota);

/// Un pellizco de dos dedos sobre el centro del mapa: cada dedo se aleja [izquierda] y [derecha]
/// píxeles por paso (desparejo, como un pellizco real, que además corre el punto focal).
Future<void> _pellizcar(
  WidgetTester tester, {
  required double izquierda,
  required double derecha,
}) async {
  final centro = tester.getCenter(_mapa);
  final a = await tester.startGesture(centro - const Offset(40, 0), pointer: 1);
  final b = await tester.startGesture(centro + const Offset(40, 0), pointer: 2);
  for (var i = 0; i < 6; i++) {
    await a.moveBy(Offset(-izquierda, 0));
    await b.moveBy(Offset(derecha, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await a.up();
  await b.up();
  await _asentar(tester, 10);
}

void main() {
  group('artboard 03A · 01 «GPS preciso»', () {
    testWidgets('muestra el chip, el punto, la ciudad detectada y la dirección «Del mapa»', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(tester);

      expect(find.text('GPS ±6 m'), findsOneWidget);
      expect(find.text('Mové el mapa para ajustar el punto'), findsOneWidget);
      expect(find.text('Nueva ubicación'), findsOneWidget);
      expect(find.text('-34.88761, -56.13024'), findsOneWidget);
      expect(find.text('±6 m'), findsOneWidget);
      expect(find.text('CIUDAD · OBLIGATORIA'), findsOneWidget);
      expect(find.text('Montevideo'), findsOneWidget);
      expect(find.text('detectada · Cambiar'), findsOneWidget);
      expect(find.text('CALLE · OPCIONAL'), findsOneWidget);
      expect(find.text('NÚMERO'), findsOneWidget);
      expect(find.text('Del mapa'), findsNWidgets(2));
      expect(find.widgetWithText(TextField, 'Av. Italia'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1234'), findsOneWidget);
      expect(find.bySemanticsLabel('Punto de la nueva ubicación'), findsOneWidget);
      expect(find.byTooltip('Volver a mi ubicación'), findsOneWidget);
      expect(find.byTooltip('Cerrar'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('con GPS preciso se registra con un toque en «Casa» y otro en «Registrar»', (
      tester,
    ) async {
      final e = await _montar(tester);
      expect(_habilitado(tester, _registrar), isFalse, reason: 'el tipo es obligatorio');

      await _tocar(tester, find.text('Casa'));
      expect(_habilitado(tester, _registrar), isTrue);
      await _tocar(tester, _registrar);

      final salida = e.salidas.single;
      expect(salida, isA<UbicacionCreada>());
      final u = (salida! as UbicacionCreada).ubicacion;
      expect(u.tipo, TipoUbicacion.casa);
      expect(u.calle, 'Av. Italia');
      expect(u.numero, '1234');
      expect(u.ciudadId, montevideo.id);
      expect(e.repo.llamadas.single.espacio, isNotNull, reason: 'espacio default de la casa');
      expect(find.text('abrir'), findsOneWidget, reason: 'vuelve al mapa');
    });

    testWidgets('el tipo no viene elegido y el elegido se marca', (tester) async {
      await _montar(tester);

      expect(find.byIcon(Icons.check), findsNothing);
      await _tocar(tester, find.text('Negocio'));

      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('mientras guarda: «Registrando…», deshabilitado, y no se puede cerrar', (
      tester,
    ) async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));

      await _traer(tester, _registrar);
      await tester.tap(_registrar);
      await tester.pump();

      expect(find.text('Registrando…'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed, isNull);
      await tester.tap(find.byTooltip('Cerrar'), warnIfMissed: false);
      await tester.pump();
      expect(e.salidas, isEmpty);
      expect(find.text('Nueva ubicación'), findsOneWidget);

      repo.bloqueo!.complete();
      await _asentar(tester);
      expect(e.salidas.single, isA<UbicacionCreada>());
    });

    testWidgets('doble toque en «Registrar»: una sola ubicación', (tester) async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));

      await _traer(tester, _registrar);
      await tester.tap(_registrar);
      await tester.tap(_registrar, warnIfMissed: false);
      repo.bloqueo!.complete();
      await _asentar(tester);

      expect(repo.llamadas, hasLength(1));
      expect(e.salidas, hasLength(1));
    });

    testWidgets('si falla a mitad: avisa, el botón vuelve a habilitarse y lo cargado se conserva', (
      tester,
    ) async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async =>
            ++intento == 1 ? const Left(FailureInesperado()) : Right(AltaRegistrada(ubicacion: u));
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Edificio'));
      await tester.enterText(find.widgetWithText(TextField, '1234'), '1240');

      await _tocar(tester, _registrar);

      expect(find.text(TextosAlta.noPudimosGuardar), findsOneWidget);
      expect(find.text('Ocurrió un error inesperado'), findsNothing);
      expect(_habilitado(tester, _registrar), isTrue);
      expect(find.text('Registrar'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1240'), findsOneWidget);
      expect(e.salidas, isEmpty);

      await _tocar(tester, _registrar);

      expect(e.salidas.single, isA<UbicacionCreada>());
      expect(repo.llamadas.map((l) => l.ubicacion.id).toSet(), hasLength(1));
      expect(repo.llamadas.last.ubicacion.numero, '1240');
    });

    testWidgets(
      'las fallas que no son inesperadas conservan su texto (y sin conexión dice para qué)',
      (tester) async {
        var intento = 0;
        final repo = RepoAltaFalso()
          ..comportamiento = (u) async {
            intento++;
            if (intento == 1) return const Left(FailureServidor());
            if (intento == 2) return const Left(FailureSinConexion());
            return Right(AltaRegistrada(ubicacion: u));
          };
        await _montar(tester, repo: repo);
        await _tocar(tester, find.text('Casa'));

        await _tocar(tester, _registrar);
        expect(find.text('El servidor no pudo procesar la solicitud'), findsOneWidget);
        expect(find.text(TextosAlta.noPudimosGuardar), findsNothing);
        expect(_habilitado(tester, _registrar), isTrue);

        await _tocar(tester, _registrar);
        expect(find.text('Necesitás conexión para registrar la ubicación.'), findsOneWidget);
        expect(find.text('El servidor no pudo procesar la solicitud'), findsNothing);
      },
    );
  });

  group('artboard 03A · 02 «Sin GPS o permiso denegado»', () {
    testWidgets('muestra el aviso, «Activar GPS», la pista y «Registrar» deshabilitado', (
      tester,
    ) async {
      await _montar(tester, gps: _gpsSin(MotivoSinGps.permisoDenegado));

      expect(find.text('Sin GPS'), findsOneWidget);
      expect(
        find.text('No tenemos tu ubicación. Tocá el mapa donde está el lugar o activá el GPS.'),
        findsOneWidget,
      );
      expect(find.text('Activar GPS'), findsOneWidget);
      expect(find.text('Tocá donde está el lugar'), findsOneWidget);
      expect(find.text('Montevideo'), findsOneWidget);
      expect(find.text('de tu zona · Cambiar'), findsOneWidget);
      expect(find.text('Marcá el punto en el mapa para registrar.'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isFalse);
      expect(find.text('Del mapa'), findsNothing);
      expect(find.text('Volver a mi ubicación'), findsNothing);
      await _tocar(tester, find.text('Casa'));
      expect(_habilitado(tester, _registrar), isFalse, reason: 'falta el punto');
    });

    testWidgets('«Activar GPS» pide lo que corresponde y, si ahora hay señal, toma la posición', (
      tester,
    ) async {
      final gps = _gpsSin(MotivoSinGps.servicioApagado);
      gps.alActivar = () => gps.respuesta = Right(lecturaGps(9));
      await _montar(tester, gps: gps);

      await _tocar(tester, find.text('Activar GPS'));

      expect(gps.activaciones, [MotivoSinGps.servicioApagado]);
      expect(find.text('GPS ±9 m'), findsOneWidget);
      expect(find.text('Activar GPS'), findsNothing);
      expect(find.text('-34.88761, -56.13024'), findsOneWidget);
    });

    testWidgets('al volver a la app desde los ajustes se vuelve a intentar', (tester) async {
      final gps = _gpsSin(MotivoSinGps.servicioApagado);
      await _montar(tester, gps: gps);
      expect(find.text('Sin GPS'), findsOneWidget);

      gps.respuesta = Right(lecturaGps(5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _asentar(tester);

      expect(find.text('GPS ±5 m'), findsOneWidget);
    });

    testWidgets(
      '«Marcar en el mapa»: un toque en el mapa pone el punto, a mano, y deja registrar',
      (tester) async {
        final e = await _montar(tester, gps: _gpsSin(MotivoSinGps.sinSenal));

        await tester.tapAt(tester.getBottomLeft(_mapa) + const Offset(200, -15));
        await tester.pump(const Duration(milliseconds: 400));
        await _asentar(tester);

        expect(find.text('Mové el mapa para ajustar el punto'), findsOneWidget);
        expect(find.text('Marcado a mano'), findsOneWidget);
        expect(find.text('Marcá el punto en el mapa para registrar.'), findsNothing);
        expect(find.text('detectada · Cambiar'), findsOneWidget);
        expect(find.text('Del mapa'), findsNWidgets(2));
        await _tocar(tester, find.text('Casa'));
        expect(_habilitado(tester, _registrar), isTrue);
        await _tocar(tester, _registrar);
        expect(e.salidas.single, isA<UbicacionCreada>());
        expect(e.repo.llamadas.single.origen.name, 'manual');
      },
    );
  });

  group('artboard 03A · 03 «GPS impreciso (±85 m)»', () {
    testWidgets('advierte con el texto de la HU y «Registrar» espera la decisión', (tester) async {
      final e = await _montar(tester, gps: GpsFalso(Right(lecturaGps(85))));
      await _tocar(tester, find.text('Casa'));

      expect(find.text('GPS ±85 m'), findsOneWidget);
      expect(find.text('±85 m'), findsOneWidget);
      expect(
        find.text('Tu ubicación tiene baja precisión. ¿Querés ajustar manualmente o continuar?'),
        findsOneWidget,
      );
      expect(find.text('Ajustar manualmente'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isFalse);
      expect(
        find.text('Elegí «Ajustar manualmente» o «Continuar» para registrar.'),
        findsOneWidget,
      );
      expect(e.repo.llamadas, isEmpty);
    });

    testWidgets('«Continuar»: el aviso se va y se puede registrar', (tester) async {
      final e = await _montar(tester, gps: GpsFalso(Right(lecturaGps(85))));
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, find.text('Continuar'));

      expect(find.text('Continuar'), findsNothing);
      expect(_habilitado(tester, _registrar), isTrue);
      await _tocar(tester, _registrar);
      expect(e.salidas.single, isA<UbicacionCreada>());
    });

    testWidgets('«Ajustar manualmente»: el aviso se va y mover el mapa lo deja a mano', (
      tester,
    ) async {
      await _montar(tester, gps: GpsFalso(Right(lecturaGps(85))));
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, find.text('Ajustar manualmente'));
      await tester.drag(_mapa, const Offset(0, 80));
      await _asentar(tester);

      expect(find.text('Ajustar manualmente'), findsNothing);
      expect(find.text('Marcado a mano'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isTrue);
    });

    testWidgets('mover el mapa sin decidir también sirve: el punto ya es a mano', (tester) async {
      await _montar(tester, gps: GpsFalso(Right(lecturaGps(85))));
      await _tocar(tester, find.text('Casa'));

      await tester.drag(_mapa, const Offset(0, 80));
      await _asentar(tester);

      expect(find.text('Ajustar manualmente'), findsNothing);
      expect(_habilitado(tester, _registrar), isTrue);
    });

    testWidgets('«Volver a mi ubicación» vuelve a pedir la decisión', (tester) async {
      await _montar(tester, gps: GpsFalso(Right(lecturaGps(85))));
      await _tocar(tester, find.text('Continuar'));
      await tester.drag(_mapa, const Offset(0, 80));
      await _asentar(tester);

      await _tocar(tester, find.byTooltip('Volver a mi ubicación'));

      expect(find.text('Ajustar manualmente'), findsOneWidget);
      expect(find.text('-34.88761, -56.13024'), findsOneWidget);
    });
  });

  group('artboard 03A · 04 «Número editado»', () {
    testWidgets('lo escrito queda «Editado»; al mover el mapa se ofrece «Usar 1250» sin pisarlo', (
      tester,
    ) async {
      final e = await _montar(tester);
      await tester.enterText(find.widgetWithText(TextField, '1234'), '1236');
      await tester.pump();
      expect(find.text('Editado'), findsOneWidget);
      expect(find.text('Del mapa'), findsOneWidget);

      e.geocodificador.respuesta = (_) =>
          const DireccionDelPunto(calle: 'Av. Italia', numero: '1250');
      await tester.drag(_mapa, const Offset(0, 80));
      await _asentar(tester);

      expect(find.widgetWithText(TextField, '1236'), findsOneWidget);
      expect(find.text('El punto está en Av. Italia 1250.'), findsOneWidget);
      expect(find.text('Usar 1250'), findsOneWidget);

      await _tocar(tester, find.text('Usar 1250'));

      expect(find.widgetWithText(TextField, '1250'), findsOneWidget);
      expect(find.text('Usar 1250'), findsNothing);
      expect(find.text('Editado'), findsNothing);
      expect(find.text('Del mapa'), findsNWidgets(2));
    });

    testWidgets('al moverse la calle que vino del mapa aparece «Calle actualizada» un rato', (
      tester,
    ) async {
      final e = await _montar(tester);
      e.geocodificador.respuesta = (_) => const DireccionDelPunto(calle: 'Rivera', numero: '5');

      await tester.drag(_mapa, const Offset(0, 80));
      await _asentar(tester);

      expect(find.text('Calle actualizada'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Rivera'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Calle actualizada'), findsNothing);
      expect(find.text('Mové el mapa para ajustar el punto'), findsOneWidget);
    });

    testWidgets('la calle editada también se respeta, con su «Usar»', (tester) async {
      final e = await _montar(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Av. Italia'), 'Italia');
      await tester.pump();
      e.geocodificador.respuesta = (_) =>
          const DireccionDelPunto(calle: 'Av. Italia', numero: '1234');

      await tester.drag(_mapa, const Offset(0, 80));
      await _asentar(tester);

      expect(find.text('Usar Av. Italia'), findsOneWidget);
      await _tocar(tester, find.text('Usar Av. Italia'));
      expect(find.widgetWithText(TextField, 'Av. Italia'), findsOneWidget);
    });

    testWidgets('sin conexión la dirección queda vacía para escribirla y se registra igual', (
      tester,
    ) async {
      final e = await _montar(tester, geocodificador: GeocodificadorFalso());
      expect(find.text('Del mapa'), findsNothing);
      expect(find.text('Calle'), findsOneWidget);
      expect(find.text('Nº'), findsOneWidget);

      await _tocar(tester, find.text('Negocio'));
      await _tocar(tester, _registrar);

      expect(e.salidas.single, isA<UbicacionCreada>());
      expect(e.repo.llamadas.single.ubicacion.calle, isNull);
      expect(find.text('Necesitás conexión'), findsNothing);
    });

    testWidgets('con la dirección sin contestar (señal mala), la ciudad ya conocida aparece y se '
        'registra sin esperar', (tester) async {
      final geocodificador = GeocodificadorFalso(
        (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1234'),
      )..bloqueo = Completer<void>();
      final e = await _montar(tester, geocodificador: geocodificador);

      expect(find.text('Buscando la ciudad…'), findsNothing);
      expect(find.text('Montevideo'), findsOneWidget);
      expect(find.text('detectada · Cambiar'), findsOneWidget);
      await _tocar(tester, find.text('Casa'));
      expect(_habilitado(tester, _registrar), isTrue);
      await _tocar(tester, _registrar);

      expect(e.salidas.single, isA<UbicacionCreada>());
      expect(e.repo.llamadas.single.ubicacion.ciudadId, montevideo.id);
      expect(e.repo.llamadas.single.ubicacion.calle, isNull);
    });
  });

  group('ciudad (decisión de Cristian, 02/10: la ciudad de tu campaña siempre se propone)', () {
    const deCampania = CiudadPropuesta(canelones, OrigenPropuesta.deCampania);

    testWidgets('«Cambiar» abre la lista de la campaña, elegir una cambia la ciudad', (
      tester,
    ) async {
      await _montar(tester);

      await _tocar(tester, find.text('detectada · Cambiar'));
      expect(find.text('Elegí la ciudad'), findsOneWidget);
      expect(find.text('Canelones'), findsOneWidget);
      await _tocar(tester, find.text('Canelones'));

      expect(find.text('Elegí la ciudad'), findsNothing);
      expect(find.text('Canelones'), findsOneWidget);
      expect(find.text('Cambiar'), findsOneWidget);
      _sinEstadosViejos();
    });

    testWidgets(
      'sin zona del punto ni asignada, se propone la ciudad de la campaña y se registra',
      (tester) async {
        final e = await _montar(tester, ciudades: CiudadesFalsas(propone: (_) => deCampania));

        expect(find.text('Canelones'), findsOneWidget);
        expect(find.text('de tu campaña · Cambiar'), findsOneWidget);
        await _tocar(tester, find.text('Casa'));
        expect(_habilitado(tester, _registrar), isTrue);
        await _tocar(tester, _registrar);

        expect((e.salidas.single! as UbicacionCreada).ubicacion.ciudadId, canelones.id);
        _sinEstadosViejos();
      },
    );

    testWidgets('con varias ciudades y sin punto ni zona asignada: «Elegir» y la ayuda bajo '
        '«Registrar»; al marcar el punto se propone', (tester) async {
      await _montar(
        tester,
        gps: _gpsSin(MotivoSinGps.sinSenal),
        ciudades: CiudadesFalsas(
          propone: (punto) => punto == null ? const FaltaElPunto() : deCampania,
        ),
      );

      expect(find.text('Sin ciudad'), findsOneWidget);
      expect(find.text('Elegir'), findsOneWidget);
      expect(find.text('Marcá el punto en el mapa para registrar.'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isFalse);

      await tester.tapAt(tester.getBottomLeft(_mapa) + const Offset(200, -15));
      await tester.pump(const Duration(milliseconds: 400));
      await _asentar(tester);

      expect(find.text('de tu campaña · Cambiar'), findsOneWidget);
      expect(find.text('Sin ciudad'), findsNothing);
      await _tocar(tester, find.text('Casa'));
      expect(_habilitado(tester, _registrar), isTrue);
      _sinEstadosViejos();
    });

    testWidgets('mientras busca: «Buscando la ciudad…», sin poder registrar y sin quedar trabado', (
      tester,
    ) async {
      final ciudades = CiudadesFalsas()..bloqueoPropuesta = Completer<void>();
      final e = await _montar(tester, ciudades: ciudades);
      await _tocar(tester, find.text('Casa'));

      expect(find.text('Buscando la ciudad…'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isFalse);
      expect(e.repo.llamadas, isEmpty);

      ciudades.bloqueoPropuesta!.complete();
      await _asentar(tester);

      expect(find.text('Buscando la ciudad…'), findsNothing);
      expect(find.text('detectada · Cambiar'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isTrue);
    });

    testWidgets('la campaña sin ciudades: el aviso dice qué hacer, no hay lista que abrir y no se '
        'registra; «Reintentar» lo resuelve', (tester) async {
      final ciudades = CiudadesFalsas(propone: (_) => const CampaniaSinCiudades());
      final e = await _montar(tester, ciudades: ciudades);
      await _tocar(tester, find.text('Casa'));

      expect(find.text(TextosAlta.sinCiudades), findsOneWidget);
      expect(find.text('Sin ciudad'), findsOneWidget);
      expect(find.text('Cambiar'), findsNothing);
      expect(find.text('Elegir'), findsNothing);
      expect(_habilitado(tester, _registrar), isFalse);
      await tester.tap(find.text('Sin ciudad'), warnIfMissed: false);
      await _asentar(tester);
      expect(find.text('Elegí la ciudad'), findsNothing);
      expect(e.repo.llamadas, isEmpty);
      _sinEstadosViejos();

      ciudades.propone = (_) => const CiudadPropuesta(montevideo, OrigenPropuesta.detectada);
      await _tocar(tester, find.text('Reintentar'));

      expect(find.text(TextosAlta.sinCiudades), findsNothing);
      expect(find.text('detectada · Cambiar'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isTrue);
    });

    testWidgets('«Reintentar» sin ciudades en la campaña: el aviso sigue y se puede volver a '
        'tocar', (tester) async {
      final ciudades = CiudadesFalsas(propone: (_) => const CampaniaSinCiudades());
      await _montar(tester, ciudades: ciudades);

      await _tocar(tester, find.text('Reintentar'));
      await _tocar(tester, find.text('Reintentar'));

      expect(find.text(TextosAlta.sinCiudades), findsOneWidget);
      expect(ciudades.propuestas, hasLength(3));
    });

    testWidgets('si no se pueden leer las ciudades: aviso con «Reintentar», se puede elegir de la '
        'lista y no queda «Buscando la ciudad…»', (tester) async {
      final ciudades = CiudadesFalsas()..fallaPropuesta = const FailureInesperado();
      final e = await _montar(tester, ciudades: ciudades);
      await _tocar(tester, find.text('Casa'));

      expect(find.text(TextosAlta.ciudadesNoLeidas), findsOneWidget);
      expect(find.text('Buscando la ciudad…'), findsNothing);
      expect(find.text('Sin ciudad'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isFalse);

      await _tocar(tester, find.text('Elegir'));
      await _tocar(tester, find.text('Canelones'));

      expect(find.text(TextosAlta.ciudadesNoLeidas), findsNothing);
      expect(_habilitado(tester, _registrar), isTrue);
      await _tocar(tester, _registrar);
      expect((e.salidas.single! as UbicacionCreada).ubicacion.ciudadId, canelones.id);
    });

    testWidgets('sin la fuente de ciudades (lo que hay hoy en producción): la falla de lectura con '
        '«Reintentar» y nunca «Tu campaña todavía no tiene ciudades»', (tester) async {
      final e = await _montar(
        tester,
        puertoCiudades: CiudadesParaAltaSinFuente(logger: loggerMudo()),
      );
      await _tocar(tester, find.text('Casa'));

      expect(find.text(TextosAlta.ciudadesNoLeidas), findsOneWidget);
      expect(find.text(TextosAlta.sinCiudades), findsNothing);
      expect(find.text('Buscando la ciudad…'), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isFalse);

      await _tocar(tester, find.text('Reintentar'));
      expect(find.text(TextosAlta.ciudadesNoLeidas), findsOneWidget);
      expect(find.text(TextosAlta.sinCiudades), findsNothing);

      // «Elegir»: la lista tampoco dice que la campaña no tiene ciudades, da el error y «Reintentar».
      await _tocar(tester, find.text('Elegir'));
      expect(_enHoja(find.text(TextosAlta.ciudadesNoLeidas)), findsOneWidget);
      expect(_enHoja(find.text(TextosAlta.sinCiudades)), findsNothing);
      expect(_enHoja(find.text('Reintentar')), findsOneWidget);
      expect(e.repo.llamadas, isEmpty);
      _sinEstadosViejos();
    });

    testWidgets('si no se pueden leer y se reintenta con éxito, la ciudad se propone sola', (
      tester,
    ) async {
      final ciudades = CiudadesFalsas()..fallaPropuesta = const FailureInesperado();
      await _montar(tester, ciudades: ciudades);

      ciudades.fallaPropuesta = null;
      await _tocar(tester, find.text('Reintentar'));

      expect(find.text(TextosAlta.ciudadesNoLeidas), findsNothing);
      expect(find.text('detectada · Cambiar'), findsOneWidget);
    });

    testWidgets('la ciudad elegida no se pisa al mover el mapa', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('detectada · Cambiar'));
      await _tocar(tester, find.text('Canelones'));

      await tester.drag(_mapa, const Offset(0, 80));
      await _asentar(tester);

      expect(find.text('Marcado a mano'), findsOneWidget);
      expect(find.text('Canelones'), findsOneWidget);
      expect(find.text('Cambiar'), findsOneWidget);
      expect(e.ciudades.propuestas, [puntoItalia], reason: 'ya eligió: no se vuelve a proponer');
    });

    testWidgets('doble toque en una ciudad de la lista: elige una vez y no cierra el alta', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('detectada · Cambiar'));

      await tester.tap(find.text('Canelones'));
      await tester.tap(find.text('Canelones'), warnIfMissed: false);
      await _asentar(tester);

      expect(find.text('Nueva ubicación'), findsOneWidget);
      expect(find.text('Elegí la ciudad'), findsNothing);
      expect(e.salidas, isEmpty);
    });

    testWidgets('volver atrás desde la lista deja la ciudad como estaba, y se puede reabrir', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('detectada · Cambiar'));

      await tester.binding.handlePopRoute();
      await _asentar(tester);

      expect(find.text('Elegí la ciudad'), findsNothing);
      expect(find.text('Nueva ubicación'), findsOneWidget);
      expect(find.text('detectada · Cambiar'), findsOneWidget);

      await _tocar(tester, find.text('detectada · Cambiar'));

      expect(find.text('Elegí la ciudad'), findsOneWidget);
      expect(e.ciudades.consultasCampania, 2);
    });

    testWidgets('la lista: cargando con texto, con error y «Reintentar», y vacía con el aviso', (
      tester,
    ) async {
      final ciudades = CiudadesFalsas()..bloqueoCampania = Completer<void>();
      await _montar(tester, ciudades: ciudades);

      await tester.ensureVisible(find.text('detectada · Cambiar'));
      await tester.pump();
      await tester.tap(find.text('detectada · Cambiar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Buscando ciudades…'), findsOneWidget);
      ciudades
        ..fallaCampania = const FailureServidor()
        ..bloqueoCampania!.complete();
      await _asentar(tester);
      expect(find.text('El servidor no pudo procesar la solicitud'), findsOneWidget);
      expect(find.text('Buscando ciudades…'), findsNothing);

      ciudades
        ..fallaCampania = null
        ..campania = const [];
      await _tocar(tester, find.text('Reintentar'));
      expect(_enHoja(find.text(TextosAlta.sinCiudades)), findsOneWidget);
      expect(find.text('Solicitar alta de ciudad al administrador'), findsNothing);
    });

    testWidgets(
      'si la fuente de la lista lanza, se ve el error con «Reintentar» y no el cargando',
      (tester) async {
        final ciudades = CiudadesFalsas()..lanzaAlListar = StateError('sin base');
        await _montar(tester, ciudades: ciudades);

        await _tocar(tester, find.text('detectada · Cambiar'));

        expect(find.text('Ocurrió un error inesperado'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(find.text('Buscando ciudades…'), findsNothing);
      },
    );
  });

  group('mapa: pellizco, pin sin colocar y fondo sin tiles', () {
    testWidgets('un pellizco de zoom no mueve el punto del GPS ni lo pasa a «Marcado a mano»', (
      tester,
    ) async {
      final e = await _montar(tester);
      final zoomAntes = e.mapa.camara!.zoom;

      await _pellizcar(tester, izquierda: 6, derecha: 14);

      expect(e.mapa.camara!.zoom, greaterThan(zoomAntes), reason: 'el pellizco sí hizo zoom');
      expect(find.text('Marcado a mano'), findsNothing);
      expect(find.text('GPS ±6 m'), findsOneWidget);
      expect(find.text('-34.88761, -56.13024'), findsOneWidget);
    });

    testWidgets('el pellizco hace el zoom sobre el centro: el mapa vuelve al punto al soltar', (
      tester,
    ) async {
      final e = await _montar(tester);

      await _pellizcar(tester, izquierda: 6, derecha: 14);

      final camara = e.mapa.camara!;
      expect(camara.centro.lat, closeTo(puntoItalia.lat, 1e-6));
      expect(camara.centro.lon, closeTo(puntoItalia.lon, 1e-6));
      expect(
        ProyeccionMercator.distanciaPixeles(camara.centro, puntoItalia, camara.zoom),
        lessThan(MapaAlta.umbralMovimientoPx),
      );
    });

    testWidgets('el zoom con doble toque está apagado: acerca sobre el punto tocado, no el pin', (
      tester,
    ) async {
      final e = await _montar(tester);

      expect(e.mapa.config!.dobleToqueZoom, isFalse);
      expect(e.mapa.config!.interaccion.zoom, isTrue);
      expect(e.mapa.config!.interaccion.desplazar, isTrue);
    });

    testWidgets('después de un pellizco, arrastrar el mapa sí deja el punto «a mano»', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _pellizcar(tester, izquierda: 6, derecha: 14);

      await tester.drag(_mapa, const Offset(0, 80));
      await _asentar(tester);

      expect(find.text('Marcado a mano'), findsOneWidget);
      expect(e.geocodificador.pedidos.length, greaterThan(1), reason: 'pidió la dirección nueva');
    });

    testWidgets(
      'mientras guarda el mapa no se mueve: si el alta falla, el pin sigue en el punto que '
      'se registra',
      (tester) async {
        final repo = RepoAltaFalso()
          ..bloqueo = Completer<void>()
          ..comportamiento = (_) async => const Left(FailureInesperado());
        final e = await _montar(tester, repo: repo);
        await _tocar(tester, find.text('Casa'));

        await _traer(tester, _registrar);
        await tester.tap(_registrar);
        await tester.pump();
        expect(find.text('Registrando…'), findsOneWidget);
        await tester.drag(_mapa, const Offset(0, 120), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
        repo.bloqueo!.complete();
        await _asentar(tester);

        expect(_registrar, findsOneWidget, reason: 'falló: el botón vuelve');
        expect(_habilitado(tester, _registrar), isTrue);
        final centro = e.mapa.camara!.centro;
        expect(centro.lat, closeTo(puntoItalia.lat, 1e-6));
        expect(centro.lon, closeTo(puntoItalia.lon, 1e-6));
        expect(find.text('GPS ±6 m'), findsOneWidget);
        expect(find.text('Marcado a mano'), findsNothing);
        expect(find.text('-34.88761, -56.13024'), findsOneWidget);
        await _tocar(tester, _registrar);
        expect(repo.llamadas.last.ubicacion.lat, puntoItalia.lat);
      },
    );

    testWidgets('sin punto el pin es una gota blanca con borde punteado; con punto, navy y lleno', (
      tester,
    ) async {
      await _montar(tester, gps: _gpsSin(MotivoSinGps.sinSenal));

      expect(find.byType(PinAlta), findsOneWidget);
      expect(tester.widget<PinAlta>(find.byType(PinAlta)).colocado, isFalse);
      expect(_bordePunteado, findsOneWidget);

      await tester.tapAt(tester.getBottomLeft(_mapa) + const Offset(200, -15));
      await tester.pump(const Duration(milliseconds: 400));
      await _asentar(tester);

      expect(tester.widget<PinAlta>(find.byType(PinAlta)).colocado, isTrue);
      expect(_bordePunteado, findsNothing);
    });

    testWidgets(
      'el borde punteado se dibuja con trazos de 3 px y repinta solo si cambia el color',
      (tester) async {
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: CustomPaint(painter: BordePunteadoGota(color: ColoresAlta.gris)),
              ),
            ),
          ),
        );

        expect(
          tester.renderObject(find.byType(CustomPaint)),
          paints
            ..path(color: ColoresAlta.gris, style: PaintingStyle.stroke, strokeWidth: 3)
            ..path()
            ..path(),
        );
        const pintor = BordePunteadoGota(color: ColoresAlta.gris);
        expect(pintor.shouldRepaint(const BordePunteadoGota(color: ColoresAlta.gris)), isFalse);
        expect(pintor.shouldRepaint(const BordePunteadoGota(color: Colors.red)), isTrue);
      },
    );

    testWidgets('sin tiles: color liso del diseño y el aviso de la HU-UBI-003, sin capa de tiles', (
      tester,
    ) async {
      final e = await _montar(tester);

      expect(e.mapa.config!.fuente.tipo, FuenteTiles.sinTiles);
      expect(e.mapa.config!.fuente.hayTiles, isFalse);
      expect(e.mapa.config!.fondo, ColoresAlta.fondoMapa);
      expect(
        find.text('Sin tiles para esta zona. Descargá tu ciudad en Configuración.'),
        findsOneWidget,
      );
    });
  });

  group('cerrar, volver y reentrar', () {
    testWidgets('✕ cierra sin registrar y no deja nada', (tester) async {
      final e = await _montar(tester);

      await _tocar(tester, find.byTooltip('Cerrar'));

      expect(e.salidas, [null]);
      expect(e.repo.llamadas, isEmpty);
    });

    testWidgets('el atrás del sistema también cierra', (tester) async {
      final e = await _montar(tester);

      await tester.binding.handlePopRoute();
      await _asentar(tester);

      expect(e.salidas, [null]);
    });

    testWidgets('al reentrar arranca de cero: sin tipo y leyendo el GPS otra vez', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, find.byTooltip('Cerrar'));
      expect(e.gps.lecturas, 1);

      await tester.tap(find.text('abrir'));
      await _asentar(tester);

      expect(e.gps.lecturas, 2);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(_habilitado(tester, _registrar), isFalse);
    });

    testWidgets('un alta por tap largo arranca en ese punto con «Marcado a mano»', (tester) async {
      await _montar(
        tester,
        puntoInicial: const Coordenadas(lat: -34.9, lon: -56.2),
        gps: _gpsSin(MotivoSinGps.sinSenal),
      );

      expect(find.text('-34.90000, -56.20000'), findsOneWidget);
      expect(find.text('Marcado a mano'), findsOneWidget);
      expect(find.text('Marcá el punto en el mapa para registrar.'), findsNothing);
    });
  });

  group('aviso de duplicado (vista 04, desde el alta)', () {
    testWidgets('«Registrar» con una candidata abre la hoja y no crea nada', (tester) async {
      final repo = RepoAltaFalso()
        ..comportamiento = (_) async =>
            Right(AltaConDuplicados(candidatas: [candidata('existente')]));
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, _registrar);

      expect(find.text('Ya existe una ubicación a 12 m'), findsOneWidget);
      expect(find.text('Misma dirección y misma ciudad.'), findsOneWidget);
      expect(find.text('Av. Italia 1234'), findsOneWidget);
      expect(find.text('Casa · Montevideo'), findsOneWidget);
      expect(find.text('Actualizada hace 3 días'), findsOneWidget);
      expect(find.text('Reutilizar esta'), findsOneWidget);
      expect(find.text('Crear igual'), findsOneWidget);
      expect(find.text(TextosDuplicado.sinCrearIgual), findsNothing, reason: 'con «Crear igual»');
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('La nueva'), findsOneWidget);
      expect(find.text('Ya registrada'), findsOneWidget);
      expect(e.salidas, isEmpty);
    });

    testWidgets('«Reutilizar esta» abre la existente sin modificarla', (tester) async {
      final repo = RepoAltaFalso()
        ..comportamiento = (_) async =>
            Right(AltaConDuplicados(candidatas: [candidata('existente')]));
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      await _tocar(tester, find.text('Reutilizar esta'));

      final salida = e.salidas.single;
      expect(salida, isA<UbicacionReutilizada>());
      expect((salida! as UbicacionReutilizada).ubicacionId, 'existente');
      expect(repo.llamadas, hasLength(1), reason: 'no se creó otra');
    });

    testWidgets('«Cancelar» vuelve al alta con todo lo cargado', (tester) async {
      final repo = RepoAltaFalso()
        ..comportamiento = (_) async =>
            Right(AltaConDuplicados(candidatas: [candidata('existente')]));
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await tester.enterText(find.widgetWithText(TextField, '1234'), '1236');
      await tester.pump();
      await _tocar(tester, _registrar);

      await _tocar(tester, find.text('Cancelar'));

      expect(find.text('Ya existe una ubicación a 12 m'), findsNothing);
      expect(find.text('Nueva ubicación'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1236'), findsOneWidget);
      expect(find.text('-34.88761, -56.13024'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isTrue);
      expect(e.salidas, isEmpty);
    });

    testWidgets('«Crear igual» pide la justificación (mínimo 10 caracteres) y crea', (
      tester,
    ) async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async => ++intento == 1
            ? Right(AltaConDuplicados(candidatas: [candidata('existente')]))
            : Right(AltaRegistrada(ubicacion: u));
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      await _tocar(tester, find.text('Crear igual'));

      expect(find.text('¿Por qué es otra ubicación?'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('Av. Italia 1234 · a 12 m'), findsOneWidget);
      expect(find.text('JUSTIFICACIÓN · OBLIGATORIA'), findsOneWidget);
      expect(find.text('Otra puerta en el mismo número'), findsOneWidget);
      expect(find.text('Local en planta baja'), findsOneWidget);
      expect(find.text('Otra unidad del edificio'), findsOneWidget);
      expect(find.text('La ve tu coordinador.'), findsOneWidget);
      expect(find.text('0 / 200'), findsOneWidget);
      final crear = find.widgetWithText(FilledButton, 'Crear igual');
      expect(tester.widget<FilledButton>(crear).onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'Corta');
      await tester.pump();
      expect(tester.widget<FilledButton>(crear).onPressed, isNull, reason: 'menos de 10');

      await _tocar(tester, find.text('Otra puerta en el mismo número'));
      expect(find.text('30 / 200'), findsOneWidget);
      expect(tester.widget<FilledButton>(crear).onPressed, isNotNull);
      await _tocar(tester, crear);

      expect(e.salidas.single, isA<UbicacionCreada>());
      expect(repo.llamadas, hasLength(2));
      expect(repo.llamadas[1].ubicacion.id, repo.llamadas[0].ubicacion.id);
    });

    testWidgets('en blanco o solo espacios no alcanza, y el texto se corta a 200', (tester) async {
      final repo = RepoAltaFalso()
        ..comportamiento = (_) async =>
            Right(AltaConDuplicados(candidatas: [candidata('existente')]));
      await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);
      await _tocar(tester, find.text('Crear igual'));
      final crear = find.widgetWithText(FilledButton, 'Crear igual');

      await tester.enterText(find.byType(TextField).last, '               ');
      await tester.pump();
      expect(tester.widget<FilledButton>(crear).onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'x' * 500);
      await tester.pump();
      expect(find.text('200 / 200'), findsOneWidget);
    });

    testWidgets('«Volver» deja la hoja con las candidatas', (tester) async {
      final repo = RepoAltaFalso()
        ..comportamiento = (_) async =>
            Right(AltaConDuplicados(candidatas: [candidata('existente')]));
      await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);
      await _tocar(tester, find.text('Crear igual'));

      await _tocar(tester, find.byTooltip('Volver'));

      expect(find.text('Ya existe una ubicación a 12 m'), findsOneWidget);
      expect(find.text('¿Por qué es otra ubicación?'), findsNothing);
    });

    testWidgets('«Crear igual» que falla: el mensaje, el botón vuelve y lo escrito queda', (
      tester,
    ) async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async {
          intento++;
          if (intento == 1) return Right(AltaConDuplicados(candidatas: [candidata('existente')]));
          if (intento == 2) return const Left(FailureInesperado());
          return Right(AltaRegistrada(ubicacion: u));
        };
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);
      await _tocar(tester, find.text('Crear igual'));
      await tester.enterText(find.byType(TextField).last, 'Local en planta baja, otra puerta');
      await tester.pump();
      final crear = find.widgetWithText(FilledButton, 'Crear igual');

      await _tocar(tester, crear);

      expect(_enHoja(find.text(TextosAlta.noPudimosGuardar)), findsOneWidget);
      expect(_enHoja(find.text('Ocurrió un error inesperado')), findsNothing);
      expect(tester.widget<FilledButton>(crear).onPressed, isNotNull);
      expect(find.text('Local en planta baja, otra puerta'), findsOneWidget);
      expect(e.salidas, isEmpty);

      await _tocar(tester, crear);
      expect(e.salidas.single, isA<UbicacionCreada>());
    });

    testWidgets('doble toque en «Crear igual»: una sola alta', (tester) async {
      var intento = 0;
      final bloqueo = Completer<void>();
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async {
          intento++;
          if (intento == 1) return Right(AltaConDuplicados(candidatas: [candidata('existente')]));
          await bloqueo.future;
          return Right(AltaRegistrada(ubicacion: u));
        };
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);
      await _tocar(tester, find.text('Crear igual'));
      await tester.enterText(find.byType(TextField).last, 'Otra unidad del edificio');
      await tester.pump();
      final crear = find.widgetWithText(FilledButton, 'Crear igual');

      await tester.tap(crear);
      await tester.pump();
      expect(_enHoja(find.text('Registrando…')), findsOneWidget);
      await tester.tap(_enHoja(find.text('Registrando…')), warnIfMissed: false);
      bloqueo.complete();
      await _asentar(tester);

      expect(repo.llamadas, hasLength(2));
      expect(e.salidas, hasLength(1));
    });

    testWidgets('si al crear igual aparecen candidatas que no lo admiten, vuelve a la lista', (
      tester,
    ) async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async {
          intento++;
          return Right(
            AltaConDuplicados(
              candidatas: [
                if (intento == 1) candidata('a') else candidata('b', admiteConservarAmbos: false),
              ],
            ),
          );
        };
      await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);
      await _tocar(tester, find.text('Crear igual'));
      await tester.enterText(find.byType(TextField).last, 'Otra puerta en el mismo número');
      await tester.pump();

      await _tocar(tester, find.widgetWithText(FilledButton, 'Crear igual'));

      expect(find.text('Ya existe una ubicación a 12 m'), findsOneWidget);
      expect(find.text('Abrir la existente'), findsOneWidget);
      expect(find.text('Crear igual'), findsNothing);
    });

    testWidgets('misma dirección a menos de 100 m: «Abrir la existente» y sin «Crear igual»', (
      tester,
    ) async {
      final repo = RepoAltaFalso()
        ..comportamiento = (_) async => Right(
          AltaConDuplicados(candidatas: [candidata('existente', admiteConservarAmbos: false)]),
        );
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      expect(find.text('Abrir la existente'), findsOneWidget);
      expect(find.text('Reutilizar esta'), findsNothing);
      expect(find.text('Crear igual'), findsNothing);
      expect(find.text('Cancelar'), findsOneWidget);

      await _tocar(tester, find.text('Abrir la existente'));
      expect((e.salidas.single! as UbicacionReutilizada).ubicacionId, 'existente');
    });

    testWidgets(
      'sin «Crear igual» (D1) la hoja dice por qué y qué hacer, debajo de «Misma dirección y misma '
      'ciudad.»',
      (tester) async {
        final repo = RepoAltaFalso()
          ..comportamiento = (_) async => Right(
            AltaConDuplicados(candidatas: [candidata('existente', admiteConservarAmbos: false)]),
          );
        await _montar(tester, repo: repo);
        await _tocar(tester, find.text('Casa'));
        await _tocar(tester, _registrar);

        final explicacion = find.text(
          'No puede haber dos ubicaciones con la misma dirección a menos de 100 m. '
          'Si es otra puerta, abrí la existente y agregala como espacio.',
        );
        expect(explicacion, findsOneWidget);
        expect(
          tester.getTopLeft(explicacion).dy,
          greaterThan(tester.getBottomLeft(find.text(TextosDuplicado.misma)).dy - 1),
        );
        expect(find.text('Crear igual'), findsNothing);
      },
    );

    testWidgets('la falla inesperada al «Crear igual» dice qué hacer; las demás fallas, su texto', (
      tester,
    ) async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async {
          intento++;
          if (intento == 1) return Right(AltaConDuplicados(candidatas: [candidata('existente')]));
          if (intento == 2) return const Left(FailureServidor());
          if (intento == 3) return const Left(FailureInesperado());
          return Right(AltaRegistrada(ubicacion: u));
        };
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);
      await _tocar(tester, find.text('Crear igual'));
      await tester.enterText(find.byType(TextField).last, 'Local en planta baja, otra puerta');
      await tester.pump();
      final crear = find.widgetWithText(FilledButton, 'Crear igual');

      await _tocar(tester, crear);
      expect(_enHoja(find.text('El servidor no pudo procesar la solicitud')), findsOneWidget);
      expect(_enHoja(find.text(TextosAlta.noPudimosGuardar)), findsNothing);
      expect(tester.widget<FilledButton>(crear).onPressed, isNotNull);

      await _tocar(tester, crear);
      expect(_enHoja(find.text(TextosAlta.noPudimosGuardar)), findsOneWidget);
      expect(_enHoja(find.text('El servidor no pudo procesar la solicitud')), findsNothing);
      expect(find.text('Local en planta baja, otra puerta'), findsOneWidget);
      expect(tester.widget<FilledButton>(crear).onPressed, isNotNull);
      expect(e.salidas, isEmpty);

      await _tocar(tester, crear);
      expect(e.salidas.single, isA<UbicacionCreada>());
    });

    group('regla D1 con el criterio real (las candidatas las calcula el criterio de la app)', () {
      /// Un repositorio que decide los duplicados con el criterio que le llega a `registrar` (el
      /// real: lo arma el caso de uso de la app) contra [existentes], como lo hace la base del
      /// teléfono, y guarda en [existentes] lo que se crea. El test no arma ninguna candidata.
      RepoAltaFalso repoConCriterioReal(List<Ubicacion> existentes) {
        late final RepoAltaFalso repo;
        repo = RepoAltaFalso()
          ..comportamiento = (u) async {
            final criterio = repo.llamadas.last.duplicados;
            final candidatas = criterio?.candidatas(u, existentes) ?? const [];
            if (candidatas.isNotEmpty) return Right(AltaConDuplicados(candidatas: candidatas));
            existentes.add(u);
            return Right(AltaRegistrada(ubicacion: u));
          };
        return repo;
      }

      testWidgets(
        '«av.  itália» 1234 a 15 m de «Av. Italia» 1234: no crea el alta en silencio y la '
        'hoja no ofrece «Crear igual»',
        (tester) async {
          final existentes = [candidata('existente', metros: 15).ubicacion];
          final repo = repoConCriterioReal(existentes);
          final e = await _montar(tester, repo: repo);
          await _tocar(tester, find.text('Casa'));
          await tester.enterText(find.widgetWithText(TextField, 'Av. Italia'), 'av.  itália');
          await tester.pump();

          await _tocar(tester, _registrar);

          expect(repo.llamadas, hasLength(1));
          expect(existentes, hasLength(1), reason: 'no se creó nada');
          expect(e.salidas, isEmpty);
          expect(find.textContaining('Ya existe una ubicación a'), findsOneWidget);
          expect(find.text('Abrir la existente'), findsOneWidget);
          expect(find.text('Crear igual'), findsNothing);
          expect(find.text('Reutilizar esta'), findsNothing);
        },
      );

      testWidgets(
        'la misma dirección a 15 m: sin «Crear igual», y «Abrir la existente» no crea otra',
        (tester) async {
          final existentes = [candidata('existente', metros: 15).ubicacion];
          final repo = repoConCriterioReal(existentes);
          final e = await _montar(tester, repo: repo);
          await _tocar(tester, find.text('Casa'));

          await _tocar(tester, _registrar);

          expect(find.text('Abrir la existente'), findsOneWidget);
          expect(find.text('Crear igual'), findsNothing);
          await _tocar(tester, find.text('Abrir la existente'));
          expect((e.salidas.single! as UbicacionReutilizada).ubicacionId, 'existente');
          expect(existentes, hasLength(1));
          expect(repo.llamadas, hasLength(1));
        },
      );

      testWidgets('control: la misma dirección a 150 m avisa y admite las dos: «Crear igual» con '
          'la justificación crea la nueva', (tester) async {
        final existentes = [candidata('existente', metros: 150).ubicacion];
        final repo = repoConCriterioReal(existentes);
        final e = await _montar(tester, repo: repo);
        await _tocar(tester, find.text('Casa'));

        await _tocar(tester, _registrar);

        expect(find.text('Reutilizar esta'), findsOneWidget);
        expect(find.text('Crear igual'), findsOneWidget);
        expect(existentes, hasLength(1));
        await _tocar(tester, find.text('Crear igual'));
        await tester.enterText(find.byType(TextField).last, 'Otra casa en la misma calle');
        await tester.pump();
        await _tocar(tester, find.widgetWithText(FilledButton, 'Crear igual'));

        expect(e.salidas.single, isA<UbicacionCreada>());
        expect(existentes, hasLength(2));
        expect(repo.llamadas, hasLength(2));
        expect(repo.llamadas[1].duplicados?.esSeguirIgual, isTrue);
      });
    });

    testWidgets(
      'a menos de 5 m con otra dirección: el subtítulo es «Revisá si es el mismo lugar…»',
      (tester) async {
        final repo = RepoAltaFalso()
          ..comportamiento = (_) async => Right(
            AltaConDuplicados(
              candidatas: [candidata('x', metros: 3, motivo: MotivoDuplicado.cercania)],
            ),
          );
        await _montar(tester, repo: repo);
        await _tocar(tester, find.text('Casa'));
        await _tocar(tester, _registrar);

        expect(find.text('Ya existe una ubicación a 3 m'), findsOneWidget);
        expect(find.text('Revisá si es el mismo lugar antes de crear otra.'), findsOneWidget);
      },
    );

    testWidgets('con varias candidatas: A y B por distancia, cada una con «Reutilizar esta»', (
      tester,
    ) async {
      final repo = RepoAltaFalso()
        ..comportamiento = (_) async => Right(
          AltaConDuplicados(
            candidatas: [
              candidata('lejos', numero: '1234'),
              candidata('cerca', metros: 4, numero: '1236'),
            ],
          ),
        );
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      expect(find.text('Hay 2 ubicaciones cerca'), findsOneWidget);
      expect(find.text('Si alguna es este lugar, reutilizala.'), findsOneWidget);
      expect(find.text('A a 4 m'), findsOneWidget);
      expect(find.text('B a 12 m'), findsOneWidget);
      expect(find.text('Reutilizar esta'), findsNWidgets(2));
      expect(find.text('Crear igual'), findsOneWidget);
      expect(find.text('Av. Italia 1236'), findsOneWidget);

      await _tocar(tester, find.text('Reutilizar esta').last);

      expect((e.salidas.single! as UbicacionReutilizada).ubicacionId, 'lejos');
    });

    testWidgets('lista larga de candidatas: se puede recorrer y elegir una', (tester) async {
      final repo = RepoAltaFalso()
        ..comportamiento = (_) async => Right(
          AltaConDuplicados(
            candidatas: [for (var i = 0; i < 6; i++) candidata('c$i', metros: 4.0 + i)],
          ),
        );
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      expect(find.text('Hay 6 ubicaciones cerca'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Cancelar'),
        200,
        scrollable: find
            .descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('Cancelar'), findsOneWidget);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(e.salidas, isEmpty);
    });
  });

  group('datos límite y accesibilidad', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('las pantallas del alta no se desbordan a texto ${escala}x en 360×640', (
        tester,
      ) async {
        final repo = RepoAltaFalso()
          ..comportamiento = (_) async => Right(
            AltaConDuplicados(
              candidatas: [
                candidata('a', metros: 4),
                candidata('b', numero: '1236'),
              ],
            ),
          );
        await _montar(
          tester,
          repo: repo,
          escala: escala,
          tamano: const Size(360, 640),
          gps: GpsFalso(Right(lecturaGps(85))),
          ciudades: CiudadesFalsas(
            propone: (_) => const CiudadPropuesta(canelones, OrigenPropuesta.deCampania),
          ),
        );
        expect(tester.takeException(), isNull);
        await _tocar(tester, find.text('Casa'));
        await _tocar(tester, find.text('Continuar'));
        await _tocar(tester, find.text('de tu campaña · Cambiar'));
        expect(tester.takeException(), isNull);
        await _tocar(tester, find.text('Montevideo'));
        await _tocar(tester, _registrar);
        expect(find.text('Hay 2 ubicaciones cerca'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Crear igual'),
          200,
          scrollable: find
              .descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable))
              .first,
        );
        await _tocar(tester, find.text('Crear igual'));
        expect(find.text('¿Por qué es otra ubicación?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('calle y número larguísimos se cortan al límite y no rompen el diseño', (
      tester,
    ) async {
      final e = await _montar(
        tester,
        escala: 2,
        tamano: const Size(360, 640),
        geocodificador: GeocodificadorFalso(),
      );
      await tester.ensureVisible(find.widgetWithText(TextField, 'Calle'));
      await tester.enterText(find.widgetWithText(TextField, 'Calle'), 'C' * 400);
      await tester.enterText(find.widgetWithText(TextField, 'Nº'), '9' * 100);
      await tester.pump();
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      expect(tester.takeException(), isNull);
      final u = e.repo.llamadas.single.ubicacion;
      expect(u.calle, hasLength(120));
      expect(u.numero, hasLength(20));
    });

    for (final (nombre, ciudades) in <(String, CiudadesFalsas Function())>[
      ('sin ciudades', () => CiudadesFalsas(propone: (_) => const CampaniaSinCiudades())),
      ('no se pueden leer', () => CiudadesFalsas()..fallaPropuesta = const FailureInesperado()),
    ]) {
      testWidgets('el aviso de ciudad ($nombre) no se desborda a texto 2x y cumple las guías', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _montar(tester, escala: 2, tamano: const Size(360, 640), ciudades: ciudades());
        await _tocar(tester, find.text('Casa'));

        expect(find.text('Reintentar'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('un nombre de ciudad larguísimo no se desborda', (tester) async {
      final larga = CiudadCatalogo(id: 'x', nombre: 'San José de Mayo ${'del Este ' * 12}');
      await _montar(
        tester,
        escala: 2,
        tamano: const Size(360, 640),
        ciudades: CiudadesFalsas(
          propone: (_) => CiudadPropuesta(larga, OrigenPropuesta.detectada),
          campania: [larga],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('San José de Mayo'), findsOneWidget);
    });

    testWidgets('un catálogo de 40 ciudades se recorre', (tester) async {
      final catalogo = [
        for (var i = 0; i < 40; i++) CiudadCatalogo(id: 'c$i', nombre: 'Ciudad $i'),
      ];
      await _montar(
        tester,
        escala: 2,
        tamano: const Size(360, 640),
        ciudades: CiudadesFalsas(campania: catalogo),
      );

      await _tocar(tester, find.textContaining('Cambiar'));
      await tester.scrollUntilVisible(
        find.text('Ciudad 39'),
        300,
        scrollable: find
            .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
            .first,
      );

      expect(find.text('Ciudad 39'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final tamano in [const Size(360, 640), const Size(412, 915)]) {
      testWidgets(
        'cumple las guías de accesibilidad en ${tamano.width.toInt()}×${tamano.height.toInt()}',
        (tester) async {
          final handle = tester.ensureSemantics();
          await _montar(tester, tamano: tamano);
          await _tocar(tester, find.text('Casa'));

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        },
      );
    }

    testWidgets('el estado «sin GPS» y el aviso de baja precisión cumplen las guías', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, gps: _gpsSin(MotivoSinGps.permisoDenegado));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('la hoja de duplicados cumple las guías', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = RepoAltaFalso()
        ..comportamiento = (_) async => Right(AltaConDuplicados(candidatas: [candidata('a')]));
      await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  group('contexto del mapa', () {
    testWidgets('las ubicaciones ya registradas alrededor se dibujan como marcadores', (
      tester,
    ) async {
      final e = await _montar(
        tester,
        marcadores: [
          for (var i = 0; i < 3; i++)
            MarcadorMapa(
              ubicacionId: 'm$i',
              tipo: TipoUbicacion.casa,
              lat: puntoItalia.lat + i * 0.0001,
              lon: puntoItalia.lon,
            ),
        ],
      );
      await _asentar(tester, 12);

      final contexto = e.mapa.config!.puntos.where((p) => p.estilo == EstiloPunto.contexto);
      expect(contexto.map((p) => p.id), ['m0', 'm1', 'm2']);
      expect(tester.takeException(), isNull);
    });
  });

  group('el mapa del alta sobre MapaBase (#286)', () {
    testWidgets('con GPS: el punto azul y su radio de precisión son capas del mapa', (
      tester,
    ) async {
      final e = await _montar(tester);

      final gps = e.mapa.config!.puntos.singleWhere((p) => p.estilo == EstiloPunto.gps);
      expect(gps.coordenadas, puntoItalia);
      expect(e.mapa.config!.precision, const CirculoPrecision(centro: puntoItalia, radioMetros: 6));
    });

    testWidgets('sin GPS no hay punto azul ni radio, y el mapa muestra el país', (tester) async {
      final e = await _montar(tester, gps: _gpsSin(MotivoSinGps.sinSenal));

      expect(e.mapa.config!.puntos.where((p) => p.estilo == EstiloPunto.gps), isEmpty);
      expect(e.mapa.config!.precision, isNull);
      expect(e.mapa.camara!.centro, MapaAlta.centroPorDefecto);
      expect(e.mapa.camara!.zoom, MapaAlta.zoomPais);
      expect(e.mapa.movimientos, isEmpty, reason: 'sin punto no hay a dónde centrar');
    });

    testWidgets('con la lectura del GPS la cámara queda sobre el punto, a zoom de calle', (
      tester,
    ) async {
      final e = await _montar(tester);

      expect(e.mapa.camara!.centro.lat, closeTo(puntoItalia.lat, 1e-6));
      expect(e.mapa.camara!.centro.lon, closeTo(puntoItalia.lon, 1e-6));
      expect(e.mapa.camara!.zoom, greaterThanOrEqualTo(MapaAlta.zoomCalle));
    });

    testWidgets('«Volver a mi ubicación» devuelve la cámara al punto del GPS', (tester) async {
      final e = await _montar(tester);
      await tester.drag(_mapa, const Offset(0, 120));
      await _asentar(tester);
      expect(
        ProyeccionMercator.distanciaPixeles(
          e.mapa.camara!.centro,
          puntoItalia,
          e.mapa.camara!.zoom,
        ),
        greaterThan(MapaAlta.umbralMovimientoPx),
        reason: 'el arrastre sí movió el mapa',
      );

      await _tocar(tester, find.byTooltip('Volver a mi ubicación'));
      await _asentar(tester);

      expect(e.mapa.camara!.centro.lat, closeTo(puntoItalia.lat, 1e-6));
      expect(e.mapa.camara!.centro.lon, closeTo(puntoItalia.lon, 1e-6));
      expect(find.text('Marcado a mano'), findsNothing);
      expect(find.text('GPS ±6 m'), findsOneWidget);
    });

    testWidgets('un toque en el mapa centra la cámara ahí y deja el punto a mano', (tester) async {
      final e = await _montar(tester, gps: _gpsSin(MotivoSinGps.sinSenal));
      const tocado = Coordenadas(lat: -34.9, lon: -56.2);

      e.mapa.tocar(tocado);
      await _asentar(tester);

      expect(find.text('Marcado a mano'), findsOneWidget);
      expect(e.mapa.camara!.centro.lat, closeTo(tocado.lat, 1e-6));
      expect(e.mapa.camara!.centro.lon, closeTo(tocado.lon, 1e-6));
      expect(e.mapa.camara!.zoom, greaterThanOrEqualTo(MapaAlta.zoomCalle));
    });

    testWidgets('miles de ubicaciones alrededor son datos del mapa, no widgets', (tester) async {
      final e = await _montar(
        tester,
        marcadores: [
          for (var i = 0; i < 3000; i++)
            MarcadorMapa(
              ubicacionId: 'm$i',
              tipo: TipoUbicacion.casa,
              lat: puntoItalia.lat + (i % 50) * 0.00005,
              lon: puntoItalia.lon + (i ~/ 50) * 0.00005,
            ),
        ],
      );
      await _asentar(tester, 12);

      expect(e.mapa.config!.puntos, hasLength(3001));
      expect(tester.takeException(), isNull);
    });
  });

  group('vista previa de la hoja de duplicados (#286)', () {
    /// El `MapaBase` chico de la hoja: el único sin gestos.
    MapaBase vistaPrevia(WidgetTester tester) => tester
        .widgetList<MapaBase>(find.byType(MapaBase, skipOffstage: false))
        .singleWhere((m) => !m.interaccion.hay);

    Future<_Escenario> abrirHoja(WidgetTester tester, List<CandidataDuplicado> candidatas) async {
      final repo = RepoAltaFalso()
        ..comportamiento = (_) async => Right(AltaConDuplicados(candidatas: candidatas));
      final e = await _montar(tester, repo: repo);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);
      return e;
    }

    testWidgets('con una candidata: la nueva y la ya registrada, sin letras, sin gestos', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await abrirHoja(tester, [candidata('c1')]);

      final previa = vistaPrevia(tester);
      expect(previa.puntos.map((p) => p.id), ['c1', 'nueva']);
      expect(previa.puntos.map((p) => p.estilo), [EstiloPunto.candidata, EstiloPunto.nuevo]);
      expect(previa.puntos.map((p) => p.letra), [null, null]);
      expect(previa.puntos.last.coordenadas, puntoItalia);
      expect(previa.interaccion, InteraccionMapa.ninguna);
      expect(previa.fondo, ColoresAlta.fondoMapa);
      // Entran las dos ubicaciones, con margen para que no queden pegadas al borde.
      expect(previa.ajuste!.puntos, [puntoItalia, candidata('c1').ubicacion.coordenadas]);
      expect(previa.ajuste!.margen, 40);
      expect(find.bySemanticsLabel(RegExp('Vista previa del mapa')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('con varias: A y B, en el orden de la lista', (tester) async {
      await abrirHoja(tester, [candidata('lejos'), candidata('cerca', metros: 4)]);

      final previa = vistaPrevia(tester);
      expect(previa.puntos.map((p) => p.id), ['cerca', 'lejos', 'nueva']);
      expect(previa.puntos.map((p) => p.letra), ['A', 'B', null]);
      expect(previa.ajuste!.puntos, hasLength(3));
    });

    testWidgets('lista larga: todas las candidatas entran en el recuadro de la vista previa', (
      tester,
    ) async {
      await abrirHoja(tester, [for (var i = 0; i < 12; i++) candidata('c$i', metros: 5.0 + i)]);

      final previa = vistaPrevia(tester);
      expect(previa.puntos, hasLength(13));
      expect(previa.ajuste!.puntos, hasLength(13));
      expect(tester.takeException(), isNull);
    });
  });
}
