// Vista 11 «Espacios» (HU-UBI-007, #473, seguimiento de #211): «Dados de baja» al pie de la hoja del
// edificio, con «Reactivar» en cada depto y el «Deshacer» de 8 s de la reactivación de una casa (vista
// 09·03 y 09·04). Sin artboard nuevo: se sigue el patrón de la 09 y de la 11·01.
//
// Un test por estado (sin bajas, plegado, desplegado, leyendo, error), por flujo (reactivar, deshacer, el
// plazo, el lector de pantalla) y por caso límite (doble toque, falla a mitad, dos acciones seguidas,
// volver y reentrar, listas largas, textos largos y texto a 200 %).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_con_deshacer.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_espacios_baja.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';
import 'hoja_espacios_arnes.dart';

final _baja = DateTime.utc(2026, 10, 22, 9);

/// Dos deptos activos en el piso 1 y dos dados de baja (uno en el piso 1 y otro en el 2).
List<Espacio> _delEdificio() => [
  espacioDe('e-101', '101', piso: '1', orden: 1),
  espacioDe('e-102', '102', piso: '1', orden: 2),
  espacioDe('e-103', '103', piso: '1', orden: 3, baja: _baja),
  espacioDe('e-204', '204', piso: '2', orden: 4, baja: _baja),
];

final _cabecera = find.byKey(ClavesDadosDeBaja.cabecera);
Finder _reactivar(String id) => find.byKey(ClavesDadosDeBaja.reactivar(id));
Finder _filaBaja(String id) => find.byKey(ClavesDadosDeBaja.fila(id));
final _textoDelAviso = find.byKey(ClavesAvisoDeshacer.texto);
final _deshacer = find.byKey(ClavesAvisoDeshacer.deshacer);
final _cerrarAviso = find.byKey(ClavesAvisoDeshacer.cerrar);
final _avisoRojo = find.byKey(ClavesHojaUbicacion.aviso);

const _grande = Size(390, 1600);

Future<MontajeHoja> _montar(
  WidgetTester tester, {
  List<Espacio>? espacios,
  Map<String, int>? personas,
  double escala = 1,
  bool lector = false,
  Size tamano = _grande,
  Ubicacion? ubicacion,
  bool abrir = true,
}) => montarHoja(
  tester,
  espacios: espacios ?? _delEdificio(),
  personas: personas,
  escala: escala,
  lector: lector,
  tamano: tamano,
  ubicacion: ubicacion,
  abrir: abrir,
);

final _desplazable = find.descendant(of: hojaUbicacion, matching: find.byType(Scrollable)).first;

/// Lleva [destino] a la vista (la lista es perezosa) y deja la hoja quieta.
Future<void> _irA(WidgetTester tester, Finder destino) async {
  await tester.scrollUntilVisible(destino, 200, scrollable: _desplazable, maxScrolls: 400);
  await tester.ensureVisible(destino);
  await asentarHoja(tester);
}

Future<void> _desplegar(WidgetTester tester) async {
  await _irA(tester, _cabecera);
  await tester.tap(_cabecera);
  await asentarHoja(tester);
}

Future<void> _tocarReactivar(WidgetTester tester, String id) async {
  await _irA(tester, _reactivar(id));
  await tester.tap(_reactivar(id));
  await asentarHoja(tester);
}

/// El aviso con «Deshacer» está DENTRO de la hoja y se ve de verdad: lo alcanza el toque, cae dentro de la
/// pantalla y de la hoja, y no es un `SnackBar` (la hoja modal lo taparía).
void _seVeElAviso(WidgetTester tester, String texto) {
  final enAviso = find.descendant(of: find.byType(AvisoDeshacerEnHoja), matching: find.text(texto));
  expect(enAviso, findsOneWidget, reason: 'el aviso «$texto» está en la hoja');
  expect(enAviso.hitTestable(), findsOneWidget, reason: 'el aviso no está tapado');
  final rect = tester.getRect(enAviso);
  final hoja = tester.getRect(hojaUbicacion);
  final pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(hoja.contains(rect.topLeft) && hoja.contains(rect.bottomRight), isTrue);
  expect(rect.bottom <= pantalla.height && rect.right <= pantalla.width, isTrue);
  expect(find.byType(SnackBar), findsNothing);
}

/// Un estado de cuenta fijo (#383).
class _CuentaFija extends EstadoCuentaNotifier {
  _CuentaFija(this._estado);

  final EstadoCuenta _estado;

  @override
  Future<EstadoCuenta?> build() async => _estado;
}

void main() {
  group('11·01 «Dados de baja» al pie del edificio', () {
    testWidgets('sin ningún depto dado de baja no hay «Dados de baja»', (tester) async {
      final m = await _montar(
        tester,
        espacios: [
          espacioDe('e-101', '101', piso: '1'),
          espacioDe('e-102', '102', piso: '1'),
        ],
      );

      expect(_cabecera, findsNothing);
      expect(find.textContaining('Dados de baja'), findsNothing);
      expect(m.repo.listadosConBajas, 1, reason: 'se leyó, y no había nada que mostrar');
      expect(tester.takeException(), isNull);
    });

    testWidgets('con bajas: «Dados de baja · 2» va al pie, plegado, y la cuenta de arriba no las '
        'cuenta', (tester) async {
      await _montar(tester);

      expect(find.text('2 deptos'), findsOneWidget);
      expect(find.text('Dados de baja · 2'), findsOneWidget);
      expect(find.text('▾'), findsOneWidget);
      expect(_filaBaja('e-103'), findsNothing, reason: 'plegado');
      expect(_reactivar('e-103'), findsNothing);
      expect(find.text('Depto 103'), findsNothing);
      final alPie = tester.getTopLeft(_cabecera).dy;
      expect(alPie, greaterThan(tester.getTopLeft(filaDepto('e-102')).dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'tocar la cabecera despliega los deptos con su piso y su «Reactivar»; otro toque los '
      'pliega',
      (tester) async {
        await _montar(tester);

        await _desplegar(tester);

        expect(find.text('▴'), findsOneWidget);
        for (final id in ['e-103', 'e-204']) {
          expect(_filaBaja(id), findsOneWidget);
          expect(
            find.descendant(of: _filaBaja(id), matching: find.text('Reactivar')),
            findsOneWidget,
          );
        }
        expect(find.descendant(of: _filaBaja('e-103'), matching: find.text('Depto 103')), findsOne);
        expect(find.descendant(of: _filaBaja('e-103'), matching: find.text('Piso 1')), findsOne);
        expect(find.descendant(of: _filaBaja('e-204'), matching: find.text('Piso 2')), findsOne);
        expect(
          tester.getTopLeft(_filaBaja('e-103')).dy,
          lessThan(tester.getTopLeft(_filaBaja('e-204')).dy),
          reason: 'por piso y por número, como la lista',
        );
        expect(
          tester.getTopLeft(_filaBaja('e-103')).dy,
          greaterThan(tester.getTopLeft(_cabecera).dy),
        );

        await _desplegar(tester);

        expect(_filaBaja('e-103'), findsNothing);
        expect(find.text('▾'), findsOneWidget);
      },
    );

    testWidgets('se lee como un botón desplegable y cada «Reactivar» dice de qué depto es', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester);

      expect(find.bySemanticsLabel('Dados de baja, 2 deptos'), findsOneWidget);
      final nodo = tester.getSemantics(find.bySemanticsLabel('Dados de baja, 2 deptos'));
      expect(nodo.getSemanticsData().flagsCollection.isButton, isTrue);

      await _desplegar(tester);

      expect(find.bySemanticsLabel('Reactivar Depto 103'), findsOneWidget);
      expect(find.bySemanticsLabel('Reactivar Depto 204'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Depto 103. Dado de baja.')), findsOneWidget);
      semantica.dispose();
    });

    testWidgets(
      'un edificio sin deptos activos y con bajas invita a agregar y deja ver las bajas',
      (tester) async {
        await _montar(
          tester,
          espacios: [espacioDe('e-1', '1', piso: '1', baja: _baja)],
        );

        expect(find.text('Todavía no hay deptos'), findsNothing);
        expect(find.text('Todavía no hay departamentos'), findsOneWidget);
        expect(find.text('Dados de baja · 1'), findsOneWidget);
        await _desplegar(tester);
        expect(_reactivar('e-1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'un depto sin número se ve como «Sin número» y se reactiva como «Depto sin número»',
      (tester) async {
        await _montar(tester, espacios: [espacioDe('e-sn', null, baja: _baja)]);
        await _desplegar(tester);

        expect(find.descendant(of: _filaBaja('e-sn'), matching: find.text('Sin número')), findsOne);
        await _tocarReactivar(tester, 'e-sn');
        _seVeElAviso(tester, 'Depto sin número reactivado. Vuelve a aparecer en el edificio.');
      },
    );

    testWidgets('una casa no tiene deptos: ni «Dados de baja» ni una lectura de bajas', (
      tester,
    ) async {
      final m = await _montar(tester, espacios: [], ubicacion: ubicacionGuardada());

      expect(_cabecera, findsNothing);
      expect(m.repo.listadosConBajas, 0);
    });

    testWidgets('un depto dado de baja desde su edición aparece enseguida en «Dados de baja»', (
      tester,
    ) async {
      await _montar(
        tester,
        espacios: [
          espacioDe('e-101', '101', piso: '1'),
          espacioDe('e-102', '102', piso: '1'),
        ],
      );
      expect(_cabecera, findsNothing);

      await abrirEdicionDepto(tester, 'e-102');
      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
      await asentarHoja(tester);

      expect(find.text('1 depto'), findsOneWidget);
      expect(find.text('Dados de baja · 1'), findsOneWidget);
      await _desplegar(tester);
      expect(_reactivar('e-102'), findsOneWidget);
    });
  });

  group('estados de la lectura de las bajas', () {
    testWidgets('mientras lee «Dados de baja» no muestra nada ni frena la lista', (tester) async {
      final espera = Completer<void>();
      final m = await _montar(tester, abrir: false);
      m.repo.esperaAlListarBajas = espera;
      await abrirLaHoja(tester);

      expect(find.text('Depto 101'), findsOneWidget, reason: 'la lista de activos ya se ve');
      expect(_cabecera, findsNothing);

      espera.complete();
      await asentarHoja(tester);
      expect(_cabecera, findsOneWidget);
    });

    testWidgets('si no puede leer las bajas lo dice con «Reintentar» y la lista sigue a la vista', (
      tester,
    ) async {
      final m = await _montar(tester, abrir: false);
      m.repo.fallaAlListarBajas = const FailureInesperado(causa: 'x');
      await abrirLaHoja(tester);

      expect(find.byKey(ClavesDadosDeBaja.error), findsOneWidget);
      expect(
        find.text('No pudimos leer los deptos dados de baja. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Depto 101'), findsOneWidget);
      expect(find.text('2 deptos'), findsOneWidget);

      m.repo.fallaAlListarBajas = const FailureInesperado(causa: 'x');
      await tester.tap(find.byKey(ClavesDadosDeBaja.reintentar));
      await asentarHoja(tester);
      expect(find.byKey(ClavesDadosDeBaja.error), findsOneWidget, reason: 'volvió a fallar');

      m.repo.fallaAlListarBajas = null;
      await tester.tap(find.byKey(ClavesDadosDeBaja.reintentar));
      await asentarHoja(tester);
      expect(find.byKey(ClavesDadosDeBaja.error), findsNothing);
      expect(find.text('Dados de baja · 2'), findsOneWidget);
    });
  });

  group('09·03 y 09·04 «Reactivar» un depto', () {
    testWidgets(
      'el depto vuelve a la lista, la cuenta sube y el aviso con «Deshacer» sale dentro de '
      'la hoja',
      (tester) async {
        final m = await _montar(tester);
        await _desplegar(tester);

        await _tocarReactivar(tester, 'e-103');

        expect(m.repo.llamadas, ['restaurar:e-103']);
        expect(m.repo.activos.map((e) => e.id), contains('e-103'));
        expect(filaDepto('e-103'), findsOneWidget);
        expect(find.text('3 deptos'), findsOneWidget);
        expect(find.text('Dados de baja · 1'), findsOneWidget);
        expect(_filaBaja('e-103'), findsNothing);
        expect(_filaBaja('e-204'), findsOneWidget, reason: 'sigue desplegado');
        _seVeElAviso(tester, 'Depto 103 reactivado. Vuelve a aparecer en el edificio.');
        expect(find.text('Deshacer'), findsOneWidget);
        expect(find.text('✓'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('en un negocio el aviso dice «en el negocio»', (tester) async {
      await _montar(
        tester,
        ubicacion: edificioMataojo(tipo: TipoUbicacion.negocio),
        espacios: [espacioDe('e-1', 'Local 1', baja: _baja)],
      );
      await _desplegar(tester);
      await _tocarReactivar(tester, 'e-1');

      _seVeElAviso(tester, 'Depto Local 1 reactivado. Vuelve a aparecer en el negocio.');
    });

    testWidgets('el último depto dado de baja que se reactiva hace desaparecer «Dados de baja»', (
      tester,
    ) async {
      await _montar(
        tester,
        espacios: [espacioDe('e-1', '1', piso: '1', baja: _baja)],
      );
      await _desplegar(tester);
      await _tocarReactivar(tester, 'e-1');

      expect(_cabecera, findsNothing);
      expect(find.text('1 depto'), findsOneWidget);
      expect(find.text('Deshacer'), findsOneWidget, reason: 'el aviso sigue ahí');
    });

    testWidgets(
      '«Deshacer» vuelve a dar de baja el depto, con sus personas sin volver a preguntar',
      (tester) async {
        final m = await _montar(tester, personas: {'e-103': 2});
        await _desplegar(tester);
        await _tocarReactivar(tester, 'e-103');

        await tester.tap(_deshacer);
        await asentarHoja(tester);

        expect(m.repo.llamadas, ['restaurar:e-103', 'baja:e-103']);
        expect(m.repo.espacios.firstWhere((e) => e.id == 'e-103').estaBorrada, isTrue);
        expect(filaDepto('e-103'), findsNothing);
        expect(find.text('2 deptos'), findsOneWidget);
        expect(find.text('Dados de baja · 2'), findsOneWidget);
        expect(_filaBaja('e-103'), findsOneWidget);
        _seVeElAviso(tester, 'Volvió a quedar de baja.');
        expect(_deshacer, findsNothing, reason: 'no hay nada más que deshacer');
        expect(_avisoRojo, findsNothing);
      },
    );

    testWidgets('el aviso dura 8 s y se va solo', (tester) async {
      await _montar(tester);
      await _desplegar(tester);
      await _tocarReactivar(tester, 'e-103');

      await tester.pump(const Duration(seconds: 7));
      expect(_textoDelAviso, findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(_textoDelAviso, findsNothing);
      expect(find.text('3 deptos'), findsOneWidget, reason: 'el depto sigue reactivado');
    });

    testWidgets('con lector de pantalla no se va solo, se puede cerrar con la ✕ y «Deshacer» sigue '
        'ahí', (tester) async {
      await _montar(tester, lector: true);
      await _desplegar(tester);
      await _tocarReactivar(tester, 'e-103');

      await tester.pump(const Duration(seconds: 30));
      expect(_textoDelAviso, findsOneWidget);
      expect(_deshacer, findsOneWidget);
      expect(tester.getSize(_cerrarAviso).shortestSide, greaterThanOrEqualTo(48));

      await tester.tap(_cerrarAviso);
      await tester.pump();
      expect(_textoDelAviso, findsNothing);
      expect(find.text('3 deptos'), findsOneWidget);
    });

    testWidgets('con lector, «Deshacer» sigue funcionando pasado el plazo', (tester) async {
      final m = await _montar(tester, lector: true);
      await _desplegar(tester);
      await _tocarReactivar(tester, 'e-103');
      await tester.pump(const Duration(seconds: 60));

      await tester.tap(_deshacer);
      await asentarHoja(tester);

      expect(m.repo.llamadas, ['restaurar:e-103', 'baja:e-103']);
      _seVeElAviso(tester, 'Volvió a quedar de baja.');
      expect(
        _cerrarAviso,
        findsOneWidget,
        reason: 'con lector el resultado también se cierra a mano',
      );
    });

    testWidgets('el resultado de deshacer también se va a los 8 s', (tester) async {
      await _montar(tester);
      await _desplegar(tester);
      await _tocarReactivar(tester, 'e-103');
      await tester.tap(_deshacer);
      await asentarHoja(tester);
      expect(_textoDelAviso, findsOneWidget);

      await tester.pump(const Duration(seconds: 9));

      expect(_textoDelAviso, findsNothing);
    });

    testWidgets('con la cuenta restringida «Reactivar» no reactiva nada y avisa por qué', (
      tester,
    ) async {
      final m = await montarHoja(
        tester,
        espacios: _delEdificio(),
        tamano: _grande,
        extras: [estadoCuentaProvider.overrideWith(() => _CuentaFija(EstadoCuenta.suspendida))],
      );
      final contenedor = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final suscripcion = contenedor.listen(estadoCuentaProvider, (_, _) {});
      addTearDown(suscripcion.close);
      await asentarHoja(tester);
      await _desplegar(tester);

      await _tocarReactivar(tester, 'e-103');

      expect(m.repo.llamadas, isEmpty);
      expect(
        find.descendant(of: _avisoRojo, matching: find.text(TextosModuloBloqueado.suspendida)),
        findsOneWidget,
      );
      expect(_reactivar('e-103'), findsOneWidget);
    });
  });

  group('casos límite del flujo', () {
    testWidgets('doble toque en «Reactivar»: reactiva una sola vez y el botón espera', (
      tester,
    ) async {
      final espera = Completer<void>();
      final m = await _montar(tester);
      await _desplegar(tester);
      m.repo.espera = espera;

      await tester.ensureVisible(_reactivar('e-103'));
      await tester.tap(_reactivar('e-103'));
      await tester.pump();
      expect(find.text('Reactivando…'), findsOneWidget);
      expect(habilitado(tester, _reactivar('e-103')), isFalse);
      await tester.tap(_reactivar('e-103'), warnIfMissed: false);
      await tester.pump();
      expect(habilitado(tester, _reactivar('e-204')), isTrue, reason: 'el otro depto no espera');

      espera.complete();
      await asentarHoja(tester);

      expect(m.repo.llamadas, ['restaurar:e-103']);
      _seVeElAviso(tester, 'Depto 103 reactivado. Vuelve a aparecer en el edificio.');
    });

    testWidgets(
      'la reactivación que falla deja el depto en bajas, el botón habilitado y un aviso que '
      'guía',
      (tester) async {
        final m = await _montar(tester);
        await _desplegar(tester);
        m.repo.fallas.add(const FailureInesperado(causa: 'x'));

        await _tocarReactivar(tester, 'e-103');

        expect(
          find.descendant(
            of: _avisoRojo,
            matching: find.text('No pudimos reactivar el departamento. Probá de nuevo.'),
          ),
          findsOneWidget,
        );
        expect(_textoDelAviso, findsNothing);
        expect(_reactivar('e-103'), findsOneWidget);
        expect(habilitado(tester, _reactivar('e-103')), isTrue);
        expect(find.text('Reactivar'), findsNWidgets(2));
        expect(find.text('Reactivando…'), findsNothing);

        // El reintento anda y el aviso de la falla se va.
        await _tocarReactivar(tester, 'e-103');
        expect(_avisoRojo, findsNothing);
        _seVeElAviso(tester, 'Depto 103 reactivado. Vuelve a aparecer en el edificio.');
      },
    );

    testWidgets('si el caso de uso lanza, tampoco queda trabado en «Reactivando…»', (tester) async {
      final m = await _montar(tester);
      await _desplegar(tester);
      m.repo.lanzas.add(StateError('x'));

      await _tocarReactivar(tester, 'e-103');

      expect(find.text('No pudimos reactivar el departamento. Probá de nuevo.'), findsOneWidget);
      expect(find.text('Reactivando…'), findsNothing);
      expect(habilitado(tester, _reactivar('e-103')), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'otro depto activo tomó el número mientras estaba de baja: no se reactiva y dice qué '
      'hacer',
      (tester) async {
        final m = await _montar(
          tester,
          espacios: [
            espacioDe('e-103', '103', piso: '1', orden: 1, baja: _baja),
            espacioDe('e-nuevo', '103', piso: '1', orden: 2),
          ],
        );
        await _desplegar(tester);

        await _tocarReactivar(tester, 'e-103');

        expect(
          find.descendant(
            of: _avisoRojo,
            matching: find.text(
              'No se puede reactivar el depto 103: ya hay otro con ese número en este edificio. '
              'Cambiale el número al que está activo y probá de nuevo.',
            ),
          ),
          findsOneWidget,
        );
        expect(m.repo.espacios.firstWhere((e) => e.id == 'e-103').estaBorrada, isTrue);
        expect(habilitado(tester, _reactivar('e-103')), isTrue);
        expect(_textoDelAviso, findsNothing);
      },
    );

    testWidgets(
      'si la ubicación se dio de baja mientras tanto lo dice con el texto de la gestión',
      (tester) async {
        final m = await _montar(tester);
        await _desplegar(tester);
        m.repo.fallas.add(
          const FailureValidacion(campos: {'ubicacionId': 'La ubicación está dada de baja.'}),
        );

        await _tocarReactivar(tester, 'e-103');

        expect(
          find.text('Esta ubicación está dada de baja: no se le pueden cambiar deptos.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('«Deshacer» que falla lo dice, el depto sigue reactivado y no queda trabado', (
      tester,
    ) async {
      final m = await _montar(tester);
      await _desplegar(tester);
      await _tocarReactivar(tester, 'e-103');
      m.repo.fallas.add(const FailureInesperado(causa: 'x'));

      await tester.tap(_deshacer);
      await asentarHoja(tester);

      _seVeElAviso(tester, 'No pudimos deshacer. Podés darlo de baja de nuevo desde su edición.');
      expect(m.repo.activos.map((e) => e.id), contains('e-103'));
      expect(filaDepto('e-103'), findsOneWidget);
      expect(_deshacer, findsNothing);
    });

    testWidgets(
      '«Deshacer» del último depto activo con personas no se puede: lo dice y no lo da de baja',
      (tester) async {
        final m = await _montar(
          tester,
          espacios: [espacioDe('e-1', '1', piso: '1', baja: _baja)],
          personas: {'e-1': 3},
        );
        await _desplegar(tester);
        await _tocarReactivar(tester, 'e-1');

        await tester.tap(_deshacer);
        await asentarHoja(tester);

        expect(m.repo.llamadas, ['restaurar:e-1']);
        _seVeElAviso(tester, 'No pudimos deshacer. Podés darlo de baja de nuevo desde su edición.');
        expect(filaDepto('e-1'), findsOneWidget);
      },
    );

    testWidgets('doble toque en «Deshacer»: da de baja una sola vez y el plazo no cierra el aviso '
        'mientras deshace', (tester) async {
      final m = await _montar(tester);
      await _desplegar(tester);
      await _tocarReactivar(tester, 'e-103');
      final espera = Completer<void>();
      m.repo.espera = espera;

      await tester.tap(_deshacer);
      await tester.pump();
      expect(tester.widget<TextButton>(_deshacer).onPressed, isNull, reason: 'apagado');
      await tester.tap(_deshacer, warnIfMissed: false);
      await tester.pump(const Duration(seconds: 12));
      expect(_textoDelAviso, findsOneWidget, reason: 'el plazo no lo cierra mientras deshace');

      espera.complete();
      await asentarHoja(tester);

      expect(m.repo.llamadas, ['restaurar:e-103', 'baja:e-103']);
      _seVeElAviso(tester, 'Volvió a quedar de baja.');
    });

    testWidgets('dos reactivaciones seguidas: las dos quedan hechas, el aviso es el del último y el '
        'plazo del primero no lo cierra', (tester) async {
      final m = await _montar(tester);
      await _desplegar(tester);

      await _tocarReactivar(tester, 'e-103');
      await tester.pump(const Duration(seconds: 5));
      await _tocarReactivar(tester, 'e-204');

      expect(m.repo.activos.map((e) => e.id), containsAll(['e-103', 'e-204']));
      expect(_cabecera, findsNothing);
      _seVeElAviso(tester, 'Depto 204 reactivado. Vuelve a aparecer en el edificio.');
      expect(find.text('Depto 103 reactivado. Vuelve a aparecer en el edificio.'), findsNothing);

      // A los 8 s del primero (3 s del segundo) el aviso del segundo sigue; a los 8 s del segundo, no.
      await tester.pump(const Duration(seconds: 3));
      expect(_textoDelAviso, findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      expect(_textoDelAviso, findsNothing);
      expect(find.text('4 deptos'), findsOneWidget);
    });

    testWidgets('«Deshacer» del primero mientras reactiva el segundo: el aviso del segundo no se '
        'pisa y nada se pierde', (tester) async {
      final m = await _montar(tester);
      await _desplegar(tester);
      await _tocarReactivar(tester, 'e-103');
      final espera = Completer<void>();
      m.repo.espera = espera;

      await tester.tap(_deshacer);
      await tester.pump();
      await _tocarReactivar(tester, 'e-204');
      _seVeElAviso(tester, 'Depto 204 reactivado. Vuelve a aparecer en el edificio.');

      espera.complete();
      await asentarHoja(tester);

      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-103').estaBorrada, isTrue);
      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-204').estaBorrada, isFalse);
      _seVeElAviso(tester, 'Depto 204 reactivado. Vuelve a aparecer en el edificio.');
      expect(find.text('Dados de baja · 1'), findsOneWidget);
      expect(find.text('3 deptos'), findsOneWidget);

      // Y el «Deshacer» que queda es el del segundo.
      await tester.tap(_deshacer);
      await asentarHoja(tester);
      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-204').estaBorrada, isTrue);
      expect(m.repo.llamadas.where((l) => l.startsWith('baja:')), ['baja:e-103', 'baja:e-204']);
    });

    testWidgets(
      'el «Deshacer» del primero que falla mientras sale el aviso del segundo no se pierde',
      (tester) async {
        final m = await _montar(tester);
        await _desplegar(tester);
        await _tocarReactivar(tester, 'e-103');
        final espera = Completer<void>();
        m.repo.espera = espera;
        await tester.tap(_deshacer);
        await tester.pump();
        await _tocarReactivar(tester, 'e-204');
        m.repo.fallas.add(const FailureInesperado(causa: 'x'));

        espera.complete();
        await asentarHoja(tester);

        _seVeElAviso(tester, 'Depto 204 reactivado. Vuelve a aparecer en el edificio.');
        expect(
          find.descendant(
            of: _avisoRojo,
            matching: find.text(
              'No pudimos deshacer. Podés darlo de baja de nuevo desde su edición.',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('cerrar la hoja con la reactivación en curso no rompe nada y el depto queda '
        'reactivado', (tester) async {
      final espera = Completer<void>();
      final m = await _montar(tester);
      await _desplegar(tester);
      m.repo.espera = espera;
      await _irA(tester, _reactivar('e-103'));
      await tester.tap(_reactivar('e-103'));
      await tester.pump();

      await tester.tap(cerrarHojaUbicacion);
      await asentarHoja(tester);
      espera.complete();
      await asentarHoja(tester);

      expect(hojaUbicacion, findsNothing);
      expect(m.repo.activos.map((e) => e.id), contains('e-103'));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'volver atrás y reentrar: lo reactivado está en la lista, el aviso no vuelve y las bajas '
      'arrancan plegadas',
      (tester) async {
        await _montar(tester);
        await _desplegar(tester);
        await _tocarReactivar(tester, 'e-103');
        expect(_textoDelAviso, findsOneWidget);

        await tester.tap(cerrarHojaUbicacion);
        await asentarHoja(tester);
        expect(hojaUbicacion, findsNothing);
        await abrirLaHoja(tester);

        expect(filaDepto('e-103'), findsOneWidget);
        expect(find.text('3 deptos'), findsOneWidget);
        expect(_textoDelAviso, findsNothing);
        expect(find.text('Dados de baja · 1'), findsOneWidget);
        expect(_filaBaja('e-204'), findsNothing, reason: 'plegado otra vez');
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('datos límite', () {
    testWidgets('300 deptos dados de baja: la lista se desplaza sin construirlos todos y llega al '
        'último', (tester) async {
      final m = await _montar(
        tester,
        tamano: const Size(390, 844),
        espacios: [
          espacioDe('e-0', '0', piso: '1', orden: 1),
          for (var i = 1; i <= 300; i++) espacioDe('b-$i', '$i', piso: 'B', orden: 2, baja: _baja),
        ],
      );
      expect(find.text('Dados de baja · 300'), findsOneWidget);
      await _desplegar(tester);
      expect(_filaBaja('b-300'), findsNothing, reason: 'las filas son perezosas');

      await _tocarReactivar(tester, 'b-300');

      _seVeElAviso(tester, 'Depto 300 reactivado. Vuelve a aparecer en el edificio.');
      expect(m.repo.activos.map((e) => e.id), contains('b-300'));
      expect(m.repo.espacios.where((e) => e.estaBorrada), hasLength(299));
      expect(tester.takeException(), isNull);
    });

    testWidgets('textos largos: un número de 40 caracteres y un piso largo no desbordan', (
      tester,
    ) async {
      await _montar(
        tester,
        tamano: const Size(320, 700),
        espacios: [
          espacioDe(
            'e-1',
            'Local comercial 4 planta baja fondo izq',
            piso: 'Entrepiso de servicio y azotea',
            baja: _baja,
          ),
        ],
      );
      await _desplegar(tester);

      await _irA(tester, _reactivar('e-1'));
      expect(find.textContaining('Local comercial 4'), findsOneWidget);
      await _tocarReactivar(tester, 'e-1');
      expect(find.textContaining('reactivado. Vuelve a aparecer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'texto del sistema al 200 %: las filas, el botón y el aviso se ven enteros y se tocan',
      (tester) async {
        await _montar(tester, escala: 2, tamano: const Size(390, 844));
        await _desplegar(tester);
        await _irA(tester, _reactivar('e-103'));

        final caja = tester.getRect(_reactivar('e-103'));
        expect(caja.height, greaterThanOrEqualTo(48));
        expect(caja.left, greaterThanOrEqualTo(0));
        expect(caja.right, lessThanOrEqualTo(390));

        await _tocarReactivar(tester, 'e-103');

        _seVeElAviso(tester, 'Depto 103 reactivado. Vuelve a aparecer en el edificio.');
        expect(tester.getSize(_deshacer).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('en un teléfono chico (320 × 568) con el texto al 200 % tampoco desborda', (
      tester,
    ) async {
      await _montar(tester, escala: 2, tamano: const Size(320, 568), lector: true);
      await _desplegar(tester);
      await _tocarReactivar(tester, 'e-103');

      _seVeElAviso(tester, 'Depto 103 reactivado. Vuelve a aparecer en el edificio.');
      expect(_cerrarAviso, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
