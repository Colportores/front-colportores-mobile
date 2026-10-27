// QA de la vista 11 «Espacios» (HU-UBI-007, #211, PR #468), ronda 3: el aviso que ahora se ve DENTRO
// de la hoja de la ubicación (el freno de la cuenta restringida, #383, y la edición que no se pudo
// abrir) en vez de un `SnackBar` que la propia hoja tapaba. Con las fuentes reales de `assets/fonts/`:
//  - matriz causa (4) × 360×640 y 412×915 × texto 1,0 y 2,0: el aviso se ve (el toque lo alcanza),
//    cae dentro de la hoja y de la pantalla, no hay overflow, es región viva y los botones de la hoja
//    siguen disponibles;
//  - casos límite: segundo toque, el aviso que cambia de causa, la cuenta que vuelve a ser activa, lo
//    ya abierto que se termina, el atrás, reentrar y una lista larga desplazada hasta el final.
// Las capturas (`--dart-define=QA_CAPTURAS=true`) van a `.dart_tool/qa_capturas/` (gitignored).
import 'dart:async';

import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista11_211_arnes.dart';

/// Una cuenta que el test puede cambiar con la hoja abierta.
class _CuentaMutable extends EstadoCuentaNotifier {
  _CuentaMutable(this._inicial);

  final EstadoCuenta _inicial;

  @override
  Future<EstadoCuenta?> build() async => _inicial;

  void poner(EstadoCuenta nuevo) => state = AsyncData(nuevo);
}

/// Cada camino por el que la hoja muestra el aviso.
enum _Causa {
  suspendidaAgregar('suspendida · «+ Departamento»', EstadoCuenta.suspendida),
  suspendidaFila('suspendida · fila de un depto', EstadoCuenta.suspendida),
  pendienteEditar('pendiente · «Editar edificio»', EstadoCuenta.pendienteAsignacion),
  edicionFalla('la edición no se pudo abrir', EstadoCuenta.activa);

  const _Causa(this.rotulo, this.cuenta);

  final String rotulo;
  final EstadoCuenta cuenta;

  String get texto => switch (this) {
    suspendidaAgregar || suspendidaFila => TextosModuloBloqueado.suspendida,
    pendienteEditar => TextosModuloBloqueado.pendiente,
    edicionFalla => 'No pudimos abrir la edición. Probá de nuevo.',
  };
}

final _aviso = find.byKey(ClavesHojaUbicacion.aviso);

class _Montaje {
  _Montaje(this.hoja, this.cuenta);

  final MontajeHoja hoja;
  final _CuentaMutable Function() cuenta;
}

/// Monta la hoja con la cuenta [cuenta] (cambiable) y la deja abierta.
Future<_Montaje> _montar(
  WidgetTester tester, {
  EstadoCuenta cuenta = EstadoCuenta.activa,
  Size tamano = telefonoGrande211,
  double escala = 1,
  List<Espacio>? espacios,
}) async {
  await cargarFuentes211(tester);
  late _CuentaMutable notificador;
  final m = await montarHoja(
    tester,
    espacios: espacios ?? deptosDelCanvas(),
    tamano: tamano,
    escala: escala,
    abrir: false,
    extras: [estadoCuentaProvider.overrideWith(() => notificador = _CuentaMutable(cuenta))],
  );
  // La pantalla principal de la app escucha la cuenta; sin esto un `read` la deja cargando.
  final contenedor = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  final suscripcion = contenedor.listen(estadoCuentaProvider, (_, _) {});
  addTearDown(suscripcion.close);
  await asentarHoja(tester);
  await abrirLaHoja(tester);
  return _Montaje(m, () => notificador);
}

/// Lleva la hoja al aviso de [causa].
Future<_Montaje> _llegarAlAviso(
  WidgetTester tester,
  _Causa causa, {
  Size tamano = telefonoGrande211,
  double escala = 1,
}) async {
  final m = await _montar(tester, cuenta: causa.cuenta, tamano: tamano, escala: escala);
  switch (causa) {
    case _Causa.suspendidaAgregar:
      await tester.tap(botonAgregarDepto);
    case _Causa.suspendidaFila:
      await tester.tap(filaDepto('e-102'));
    case _Causa.pendienteEditar:
      await tester.tap(botonEditarUbicacion);
    case _Causa.edicionFalla:
      final espera = Completer<SalidaModificarUbicacion?>();
      m.hoja.esperaEdicion = espera;
      await tester.tap(botonEditarUbicacion);
      await tester.pump();
      espera.completeError(StateError('no abrió'));
  }
  await asentarHoja(tester);
  return m;
}

/// El aviso con [texto] está a la vista: lo alcanza un toque, cae dentro de la hoja y de la pantalla
/// y no es un `SnackBar`.
void _seVe(WidgetTester tester, String texto) {
  final enAviso = find.descendant(of: _aviso, matching: find.text(texto));
  expect(enAviso, findsOneWidget, reason: 'falta el aviso «$texto»');
  expect(enAviso.hitTestable(), findsOneWidget, reason: 'el aviso está tapado');
  final rect = tester.getRect(enAviso);
  final hoja = tester.getRect(hojaUbicacion);
  final pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(hoja.contains(rect.topLeft) && hoja.contains(rect.bottomRight), isTrue, reason: '$rect');
  expect(rect.top >= 0 && rect.bottom <= pantalla.height, isTrue, reason: '$rect');
  expect(find.byType(SnackBar), findsNothing);
}

String _nombre(_Causa c, Size t, double escala) =>
    'aviso_${c.name}_${t.width.toInt()}x${t.height.toInt()}_x$escala';

/// `true` corre los tests que documentan un hallazgo (hoy con `skip`).
const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  group('el aviso dentro de la hoja: causa × tamaño × texto (fuentes reales)', () {
    for (final tamano in [telefonoChico211, telefonoGrande211]) {
      for (final escala in [1.0, 2.0]) {
        for (final causa in _Causa.values) {
          testWidgets(
            'dado que ${causa.rotulo}, a ${tamano.width.toInt()}×${tamano.height.toInt()} '
            'con texto ×$escala, entonces el aviso se ve, es región viva y los botones siguen '
            'disponibles',
            (tester) async {
              final h = tester.ensureSemantics();
              await _llegarAlAviso(tester, causa, tamano: tamano, escala: escala);
              await tester.pump(const Duration(milliseconds: 400));

              expect(tester.takeException(), isNull);
              _seVe(tester, causa.texto);
              expectSinTextoFueraDeLosCostados211(tester, tamano);
              final nodo = tester.getSemantics(find.text(causa.texto));
              expect(nodo.flagsCollection.isLiveRegion, isTrue, reason: 'se anuncia');
              expect(habilitado(tester, botonAgregarDepto), isTrue);
              expect(habilitado(tester, botonEditarUbicacion), isTrue);
              expect(hojaDepto, findsNothing);
              await capturar211(tester, _nombre(causa, tamano, escala));
              h.dispose();
            },
          );
        }
      }
    }
  });

  group('casos límite del aviso', () {
    testWidgets('un segundo toque en «+ Departamento» con el aviso puesto deja un solo aviso y '
        'ninguna hoja', (tester) async {
      await _llegarAlAviso(tester, _Causa.suspendidaAgregar);

      await tester.tap(botonAgregarDepto);
      await tester.tap(botonAgregarDepto);
      await asentarHoja(tester);

      expect(_aviso, findsOneWidget);
      _seVe(tester, TextosModuloBloqueado.suspendida);
      expect(hojaDepto, findsNothing);
      expect(habilitado(tester, botonAgregarDepto), isTrue);
    });

    testWidgets('el aviso cambia de causa sin apilarse: la edición que falló y luego la cuenta '
        'que se suspende', (tester) async {
      final m = await _llegarAlAviso(tester, _Causa.edicionFalla);
      _seVe(tester, _Causa.edicionFalla.texto);

      m.hoja.esperaEdicion = null;
      m.cuenta().poner(EstadoCuenta.suspendida);
      await tester.pump();
      await tester.tap(botonEditarUbicacion);
      await asentarHoja(tester);

      expect(_aviso, findsOneWidget);
      _seVe(tester, TextosModuloBloqueado.suspendida);
      expect(find.text(_Causa.edicionFalla.texto), findsNothing);
    });

    testWidgets('si la cuenta vuelve a ser activa, el siguiente toque abre el alta y el aviso se '
        'va', (tester) async {
      final m = await _llegarAlAviso(tester, _Causa.suspendidaAgregar);

      m.cuenta().poner(EstadoCuenta.activa);
      await tester.pump();
      await tester.tap(botonAgregarDepto);
      await asentarHoja(tester);

      expect(hojaDepto, findsOneWidget);
      expect(_aviso, findsNothing);
    });

    testWidgets('lo que ya estaba abierto se termina: el alta abierta con la cuenta activa se '
        'guarda aunque la cuenta se suspenda después', (tester) async {
      final m = await _montar(tester);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '301');

      m.cuenta().poner(EstadoCuenta.suspendida);
      await tester.pump();
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(m.hoja.repo.espacios.map((e) => e.numeroDepto), contains('301'));
      expect(hojaDepto, findsNothing);
      // De vuelta en la hoja, empezar algo nuevo ya no se puede, y lo dice.
      await tester.tap(botonAgregarDepto);
      await asentarHoja(tester);
      expect(hojaDepto, findsNothing);
      _seVe(tester, TextosModuloBloqueado.suspendida);
    });

    testWidgets('el atrás con el aviso puesto cierra la hoja y al reabrirla no queda el aviso', (
      tester,
    ) async {
      await _llegarAlAviso(tester, _Causa.pendienteEditar);

      await tester.binding.handlePopRoute();
      await asentarHoja(tester);
      expect(hojaUbicacion, findsNothing);

      await abrirLaHoja(tester);
      expect(hojaUbicacion, findsOneWidget);
      expect(_aviso, findsNothing);
    });

    testWidgets('con el aviso puesto se sale subiendo la lista hasta la «✕» (y el atrás y la '
        'cortina también)', (tester) async {
      await _llegarAlAviso(tester, _Causa.suspendidaFila, escala: 2, tamano: telefonoChico211);

      tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!.jumpTo(0);
      await asentarHoja(tester);
      expect(cerrarHojaUbicacion.hitTestable(), findsOneWidget);
      await tester.tap(cerrarHojaUbicacion);
      await asentarHoja(tester);

      expect(hojaUbicacion, findsNothing);
    });

    testWidgets('con 200 deptos y la lista desplazada hasta el final, tocar un depto con la '
        'cuenta suspendida deja el aviso a la vista', (tester) async {
      final muchos = [
        for (var i = 1; i <= 200; i++)
          espacioDe('e-$i', '$i', piso: '${(i - 1) ~/ 10 + 1}', orden: i % 59),
      ];
      await _montar(
        tester,
        cuenta: EstadoCuenta.suspendida,
        tamano: telefonoChico211,
        espacios: muchos,
      );
      final controlador = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      for (var i = 0; i < 12; i++) {
        controlador.jumpTo(controlador.position.maxScrollExtent);
        await asentarHoja(tester, 2);
      }
      final ultima = find.byKey(ClavesHojaUbicacion.fila('e-200'));
      expect(ultima, findsOneWidget);

      await tester.tap(ultima);
      await asentarHoja(tester);

      expect(hojaDepto, findsNothing);
      _seVe(tester, TextosModuloBloqueado.suspendida);
    });

    testWidgets('el aviso no incluye la dirección ni el número del depto (privacidad)', (
      tester,
    ) async {
      await _llegarAlAviso(tester, _Causa.suspendidaFila);
      final texto = tester
          .widget<Text>(find.descendant(of: _aviso, matching: find.byType(Text)).last)
          .data!;
      expect(texto.contains('Mataojo'), isFalse);
      expect(texto.contains('102'), isFalse);
    });
  });

  // ---------------------------------------------------------------- hallazgo
  // skip: QA #211 — `_avisar` hace `Scrollable.ensureVisible(aviso)` con la alineación por defecto
  // (el aviso queda en el borde de arriba) y, como el encabezado es el primer hijo de la lista, la
  // dirección, la cuenta de deptos y la «✕» salen de la vista aunque el aviso ya se viera entero
  // (360×640, 412×915, texto ×1 y ×2). Salir sigue siendo posible (atrás, cortina, subir la lista).
  group('el encabezado de la hoja sigue a la vista con el aviso puesto', () {
    for (final tamano in [telefonoChico211, telefonoGrande211]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('a ${tamano.width.toInt()}×${tamano.height.toInt()} con texto ×$escala, la '
            '«✕» y la dirección se ven tras el aviso', (tester) async {
          await _llegarAlAviso(tester, _Causa.suspendidaAgregar, tamano: tamano, escala: escala);

          expect(cerrarHojaUbicacion.hitTestable(), findsOneWidget, reason: 'la «✕» quedó fuera');
          expect(find.text('Mataojo 2044').hitTestable(), findsOneWidget);
        }, skip: !_verHallazgos);
      }
    }
  });
}
