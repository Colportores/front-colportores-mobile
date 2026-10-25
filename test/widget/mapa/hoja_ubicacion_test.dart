// Vista 11 «Espacios», artboard 11·01 «Edificio con departamentos» (HU-UBI-007, #211): la hoja de la
// ubicación con sus deptos agrupados por piso. Un test por estado (cargando, vacío, error, lista), por
// regla de la lista (orden, «Sin número», «Sin piso») y por caso límite (doble toque, volver y
// reentrar, listas largas, textos largos y texto a 200 %). Nada de lo que carga o lista clientes se
// muestra (decisión de Cristian del 06/10): ni «+ Agregar cliente», ni «Registrar visita», ni el
// atajo de la casa al alta de una persona.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';
import 'hoja_espacios_arnes.dart';

/// Los deptos del canvas: tres en el piso 1, dos en el 2 y uno sin piso.
final _delCanvas = [
  espacioDe('e-101', '101', piso: '1', orden: 1),
  espacioDe('e-102', '102', piso: '1', orden: 2),
  espacioDe('e-103', '103', piso: '1', orden: 3),
  espacioDe('e-201', '201', piso: '2', orden: 4),
  espacioDe('e-202', '202', piso: '2', orden: 5),
  espacioDe('e-9', '9', orden: 6),
];

double _y(WidgetTester tester, Finder f) => tester.getTopLeft(f.first).dy;

/// Un estado de cuenta fijo (#383).
class _CuentaFija extends EstadoCuentaNotifier {
  _CuentaFija(this._estado);

  final EstadoCuenta _estado;

  @override
  Future<EstadoCuenta?> build() async => _estado;
}

/// Monta la hoja con la cuenta en [cuenta] y deja su estado escuchado, como lo hace la pantalla
/// principal de la app (un `read` solo lo deja cargando la primera vez).
Future<MontajeHoja> _montarConCuenta(WidgetTester tester, EstadoCuenta cuenta) async {
  final m = await montarHoja(
    tester,
    espacios: _delCanvas,
    extras: [estadoCuentaProvider.overrideWith(() => _CuentaFija(cuenta))],
  );
  final contenedor = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  final suscripcion = contenedor.listen(estadoCuentaProvider, (_, _) {});
  addTearDown(suscripcion.close);
  await asentarHoja(tester);
  return m;
}

/// El aviso DENTRO de la hoja (no un `SnackBar`: la hoja es un modal y lo taparía).
final _avisoDeLaHoja = find.byKey(ClavesHojaUbicacion.aviso);

/// El texto [texto] está en el aviso de la hoja y se ve de verdad: el toque lo alcanza (no lo cubre
/// la hoja ni otra cosa) y cae dentro de la pantalla y de la hoja.
void _seVeElAviso(WidgetTester tester, String texto) {
  final enAviso = find.descendant(of: _avisoDeLaHoja, matching: find.text(texto));
  expect(enAviso, findsOneWidget);
  expect(enAviso.hitTestable(), findsOneWidget, reason: 'el aviso no está tapado');
  final rect = tester.getRect(enAviso);
  final hoja = tester.getRect(find.byKey(ClavesHojaUbicacion.hoja));
  final pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(hoja.contains(rect.topLeft) && hoja.contains(rect.bottomRight), isTrue);
  expect(rect.bottom <= pantalla.height && rect.right <= pantalla.width, isTrue);
  expect(
    find.byType(SnackBar),
    findsNothing,
    reason: 'el aviso no es un SnackBar tapado por la hoja',
  );
}

void main() {
  group('11·01 Edificio con departamentos', () {
    testWidgets('dibuja el rótulo, la dirección, la cuenta y los dos botones del canvas', (
      tester,
    ) async {
      await montarHoja(tester, espacios: _delCanvas);

      expect(find.text('EDIFICIO · A 25 M'), findsOneWidget);
      expect(find.text('Mataojo 2044'), findsOneWidget);
      expect(find.text('6 deptos'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '+ Departamento'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Editar edificio'), findsOneWidget);
      expect(cerrarHojaUbicacion, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('agrupa los deptos por piso: «PISO 1», «PISO 2» y «SIN PISO» al final, con su '
        'cuenta', (tester) async {
      await montarHoja(tester, espacios: _delCanvas, tamano: const Size(390, 1400));

      final piso1 = find.byKey(ClavesHojaUbicacion.grupo('1'));
      final piso2 = find.byKey(ClavesHojaUbicacion.grupo('2'));
      final sinPiso = find.byKey(ClavesHojaUbicacion.grupo(null));
      expect(find.descendant(of: piso1, matching: find.text('PISO 1')), findsOneWidget);
      expect(find.descendant(of: piso1, matching: find.text('3')), findsOneWidget);
      expect(find.descendant(of: piso2, matching: find.text('PISO 2')), findsOneWidget);
      expect(find.descendant(of: piso2, matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: sinPiso, matching: find.text('SIN PISO')), findsOneWidget);
      expect(find.descendant(of: sinPiso, matching: find.text('1')), findsOneWidget);
      expect(_y(tester, piso1), lessThan(_y(tester, filaDepto('e-101'))));
      expect(_y(tester, filaDepto('e-103')), lessThan(_y(tester, piso2)));
      expect(_y(tester, filaDepto('e-202')), lessThan(_y(tester, sinPiso)));
      expect(_y(tester, sinPiso), lessThan(_y(tester, filaDepto('e-9'))));
    });

    testWidgets('cada fila dice «Depto N» con su «›» y se lee como botón «Editar»', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarHoja(tester, espacios: _delCanvas, tamano: const Size(390, 1400));

      for (final n in ['101', '102', '103', '201', '202', '9']) {
        expect(find.text('Depto $n'), findsOneWidget);
      }
      expect(find.text('›'), findsNWidgets(6));
      expect(find.bySemanticsLabel('Depto 101. Editar.'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('sin la distancia (sin GPS) el rótulo es solo el tipo', (tester) async {
      await montarHoja(tester, espacios: _delCanvas, distancia: null);

      expect(find.text('EDIFICIO'), findsOneWidget);
    });

    testWidgets('con un solo depto la cuenta dice «1 depto»', (tester) async {
      await montarHoja(tester, espacios: [espacioDe('e-1', '1', piso: '1')]);

      expect(find.text('1 depto'), findsOneWidget);
    });

    testWidgets('un negocio también lista sus espacios y su botón dice «Editar negocio»', (
      tester,
    ) async {
      await montarHoja(
        tester,
        ubicacion: edificioMataojo(tipo: TipoUbicacion.negocio),
        espacios: [espacioDe('e-1', 'Local 1')],
      );

      expect(find.text('NEGOCIO · A 25 M'), findsOneWidget);
      expect(find.text('Editar negocio'), findsOneWidget);
      expect(find.text('Depto Local 1'), findsOneWidget);
    });

    testWidgets('el orden es natural: «PB» primero, 2 antes que 10, los pisos también, y los sin '
        'número al final del piso en el orden en que se dieron de alta', (tester) async {
      await montarHoja(
        tester,
        espacios: [
          espacioDe('e-10', '10', piso: '2', orden: 1),
          espacioDe('e-2', '2', piso: '2', orden: 2),
          espacioDe('e-sn2', null, piso: '2', orden: 4),
          espacioDe('e-sn1', null, piso: '2', orden: 3),
          espacioDe('e-p10', '1001', piso: '10', orden: 5),
          espacioDe('e-pb', '1', piso: 'PB', orden: 6),
        ],
        tamano: const Size(390, 1600),
      );

      final y = [
        for (final id in ['e-pb', 'e-2', 'e-10', 'e-sn1', 'e-sn2', 'e-p10'])
          _y(tester, filaDepto(id)),
      ];
      expect(y, orderedEquals([...y]..sort()), reason: 'orden de arriba a abajo');
    });
  });

  group('cuenta restringida con la hoja ya abierta (#383, convención de #469)', () {
    testWidgets('suspendida, «+ Departamento» no abre el alta y avisa por qué', (tester) async {
      await _montarConCuenta(tester, EstadoCuenta.suspendida);

      await tester.tap(botonAgregarDepto);
      await asentarHoja(tester);

      expect(hojaDepto, findsNothing);
      _seVeElAviso(tester, TextosModuloBloqueado.suspendida);
      expect(tester.takeException(), isNull);
    });

    testWidgets('suspendida, tocar la fila de un depto no abre su edición y avisa', (tester) async {
      await _montarConCuenta(tester, EstadoCuenta.suspendida);

      await tester.tap(filaDepto('e-102'));
      await asentarHoja(tester);

      expect(hojaDepto, findsNothing);
      _seVeElAviso(tester, TextosModuloBloqueado.suspendida);
    });

    testWidgets('pendiente, «Editar edificio» no abre la edición y avisa con el texto de esa '
        'cuenta', (tester) async {
      final m = await _montarConCuenta(tester, EstadoCuenta.pendienteAsignacion);

      await tester.tap(botonEditarUbicacion);
      await asentarHoja(tester);

      expect(m.ediciones, isEmpty);
      _seVeElAviso(tester, TextosModuloBloqueado.pendiente);
      expect(botonEditarUbicacion, findsOneWidget, reason: 'el botón sigue disponible');
    });

    testWidgets('activa, las tres entradas siguen abriendo lo suyo (control)', (tester) async {
      final m = await _montarConCuenta(tester, EstadoCuenta.activa);

      await tester.tap(botonAgregarDepto);
      await asentarHoja(tester);
      expect(hojaDepto, findsOneWidget);
      Navigator.of(tester.element(hojaDepto)).pop();
      await asentarHoja(tester);

      await tester.tap(filaDepto('e-102'));
      await asentarHoja(tester);
      expect(hojaDepto, findsOneWidget);
      Navigator.of(tester.element(hojaDepto)).pop();
      await asentarHoja(tester);

      await tester.tap(botonEditarUbicacion);
      await asentarHoja(tester);
      expect(m.ediciones, ['ubi-1']);
      expect(_avisoDeLaHoja, findsNothing);
    });
  });

  group('«Sin número» y «Sin piso» (decisión del orquestador, 06/10)', () {
    testWidgets('un depto sin número se muestra como «Sin número» (y numero_depto sigue nulo)', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: [espacioDe('e-1', null, piso: '1')]);

      expect(find.text('Sin número'), findsOneWidget);
      expect(find.text('Depto null'), findsNothing);
      expect(m.repo.espacios.single.numeroDepto, isNull);
    });

    testWidgets('varios sin número en el mismo edificio: todos «Sin número», sin contador', (
      tester,
    ) async {
      await montarHoja(
        tester,
        espacios: [
          espacioDe('e-1', null, orden: 1),
          espacioDe('e-2', null, orden: 2),
          espacioDe('e-3', null, orden: 3),
        ],
      );

      expect(find.text('Sin número'), findsNWidgets(3));
      expect(find.textContaining('Sin número 2'), findsNothing);
      expect(find.textContaining('Sin número #'), findsNothing);
    });

    testWidgets('los sin piso van en «SIN PISO» y se pueden abrir con «Editar»', (tester) async {
      await montarHoja(tester, espacios: [espacioDe('e-1', '7')]);

      expect(find.byKey(ClavesHojaUbicacion.grupo(null)), findsOneWidget);
      await abrirEdicionDepto(tester, 'e-1');
      expect(find.text('Editar departamento'), findsOneWidget);
      expect(textoDe(tester, campoNumero), '7');
      expect(textoDe(tester, campoPiso), '');
    });
  });

  group('estados', () {
    testWidgets('cargando: mientras lee la lista muestra «Cargando los departamentos…» y los '
        'botones ya están', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas, abrir: false);
      final espera = Completer<void>();
      m.repo.esperaAlListar = espera;

      await abrirLaHoja(tester);

      expect(find.byKey(ClavesHojaUbicacion.cargando), findsOneWidget);
      expect(find.text('Cargando los departamentos…'), findsOneWidget);
      expect(botonAgregarDepto, findsOneWidget);
      espera.complete();
      await asentarHoja(tester);
      expect(find.byKey(ClavesHojaUbicacion.cargando), findsNothing);
      expect(find.text('Depto 101'), findsOneWidget);
    });

    testWidgets('mientras lee la ubicación muestra el mismo aviso de carga', (tester) async {
      final m = await montarHoja(tester, abrir: false);
      m.ubicaciones.bloqueoLectura = Completer<void>();

      await abrirLaHoja(tester);

      expect(find.byKey(ClavesHojaUbicacion.cargando), findsOneWidget);
      m.ubicaciones.bloqueoLectura!.complete();
      await asentarHoja(tester);
      expect(find.text('Mataojo 2044'), findsOneWidget);
    });

    testWidgets('vacío: un edificio sin deptos invita a agregar el primero', (tester) async {
      await montarHoja(tester);

      expect(find.byKey(ClavesHojaUbicacion.vacio), findsOneWidget);
      expect(find.text('Todavía no hay departamentos'), findsOneWidget);
      expect(
        find.text('Tocá «+ Departamento» para agregar los que vas a visitar.'),
        findsOneWidget,
      );
      expect(find.text('0 deptos'), findsOneWidget);
      expect(botonAgregarDepto, findsOneWidget);
    });

    testWidgets('error: si no puede leer la lista lo dice y «Reintentar» vuelve a leer', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: _delCanvas, abrir: false);
      m.repo.fallaAlListar = const FailureInesperado(causa: 'x');

      await abrirLaHoja(tester);

      expect(find.byKey(ClavesHojaUbicacion.error), findsOneWidget);
      expect(
        find.text('No pudimos leer los departamentos de tu teléfono. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Depto 101'), findsNothing);
      expect(botonEditarUbicacion, findsOneWidget);

      m.repo.fallaAlListar = null;
      await tester.tap(find.byKey(ClavesHojaUbicacion.reintentar));
      await asentarHoja(tester);

      expect(find.byKey(ClavesHojaUbicacion.error), findsNothing);
      expect(find.text('Depto 101'), findsOneWidget);
    });

    testWidgets('error: el reintento que vuelve a fallar deja el aviso y el botón disponible', (
      tester,
    ) async {
      final m = await montarHoja(tester, abrir: false);
      m.repo.fallaAlListar = const FailureInesperado(causa: 'x');
      await abrirLaHoja(tester);

      await tester.tap(find.byKey(ClavesHojaUbicacion.reintentar));
      await asentarHoja(tester);
      await tester.tap(find.byKey(ClavesHojaUbicacion.reintentar));
      await asentarHoja(tester);

      expect(find.byKey(ClavesHojaUbicacion.error), findsOneWidget);
      expect(habilitado(tester, find.byKey(ClavesHojaUbicacion.reintentar)), isTrue);
    });

    testWidgets('error: si no puede leer la ubicación lo dice con «Reintentar»', (tester) async {
      final m = await montarHoja(tester, abrir: false);
      m.ubicaciones.lanzaAlLeer = StateError('roto');

      await abrirLaHoja(tester);

      expect(find.text('No pudimos abrir esta ubicación. Probá de nuevo.'), findsOneWidget);
      m.ubicaciones.lanzaAlLeer = null;
      await tester.tap(find.byKey(ClavesHojaUbicacion.reintentar));
      await asentarHoja(tester);
      expect(find.text('Mataojo 2044'), findsOneWidget);
    });

    testWidgets('una ubicación que ya no está en el teléfono dice que no se pudo abrir', (
      tester,
    ) async {
      final m = await montarHoja(tester, abrir: false);
      m.ubicaciones.actual = null;

      await abrirLaHoja(tester);

      expect(find.text('No pudimos abrir esta ubicación. Probá de nuevo.'), findsOneWidget);
    });

    testWidgets('sin conexión no aplica: la hoja lee y escribe en el teléfono, sin red', (
      tester,
    ) async {
      // Todo es local (offline-first): la hoja no pregunta por la conexión y funciona igual.
      await montarHoja(tester, espacios: _delCanvas);

      expect(find.textContaining('conexión'), findsNothing);
      expect(find.text('Depto 101'), findsOneWidget);
    });
  });

  group('una casa', () {
    testWidgets('no tiene deptos: sin «+ Departamento», sin lista y con «Editar casa»', (
      tester,
    ) async {
      await montarHoja(tester, ubicacion: edificioMataojo(tipo: TipoUbicacion.casa));

      expect(find.text('CASA · A 25 M'), findsOneWidget);
      expect(botonAgregarDepto, findsNothing);
      expect(find.byKey(ClavesHojaUbicacion.vacio), findsNothing);
      expect(find.text('0 deptos'), findsNothing);
      expect(find.text('Editar casa'), findsOneWidget);
    });
  });

  group('lo que queda para #140 y #151 (decisión de Cristian, 06/10)', () {
    testWidgets('no hay nada que cargue o liste clientes: ni «+ Agregar cliente», ni «Registrar '
        'visita», ni el atajo de la casa al alta de una persona', (tester) async {
      await montarHoja(tester, espacios: _delCanvas, personas: {'e-101': 2});

      for (final texto in [
        '+ Agregar cliente',
        'Agregar cliente',
        'Registrar visita',
        'Agendar',
        'Departamento con clientes',
        'Agregar persona',
        'Clientes',
      ]) {
        expect(find.textContaining(texto), findsNothing, reason: texto);
      }
      // Una fila con personas se ve igual que las demás: la hoja no cuenta ni lista clientes.
      expect(find.textContaining('cliente'), findsNothing);
      expect(find.textContaining('persona'), findsNothing);
    });

    testWidgets('tocar un depto abre su edición, no una ficha de clientes', (tester) async {
      await montarHoja(tester, espacios: _delCanvas, personas: {'e-101': 2});

      await abrirEdicionDepto(tester, 'e-101');

      expect(find.text('Editar departamento'), findsOneWidget);
      expect(find.textContaining('cliente'), findsNothing);
    });
  });

  group('«Editar edificio» (vista 07)', () {
    testWidgets('abre la edición de esa ubicación', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas);

      await tester.tap(botonEditarUbicacion);
      await asentarHoja(tester);

      expect(m.ediciones, ['ubi-1']);
      expect(hojaUbicacion, findsOneWidget, reason: 'sin guardar nada la hoja sigue abierta');
    });

    testWidgets('si la edición guarda, la hoja se cierra y devuelve lo que pasó para que el mapa '
        'seleccione la ubicación (07·03)', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      final editada = UbicacionEditada(edificioMataojo());
      m.salidaEdicion = editada;

      await tester.tap(botonEditarUbicacion);
      await asentarHoja(tester);

      expect(hojaUbicacion, findsNothing);
      expect(m.salidas, hasLength(1));
      expect(m.salidas.single, same(editada));
    });

    testWidgets(
      'si la ubicación se dio de baja desde la edición, la hoja se cierra y lo devuelve',
      (tester) async {
        final m = await montarHoja(tester, espacios: _delCanvas);
        m.salidaEdicion = UbicacionBajaRealizada(edificioMataojo());

        await tester.tap(botonEditarUbicacion);
        await asentarHoja(tester);

        expect(hojaUbicacion, findsNothing);
        expect(m.salidas.single, isA<UbicacionBajaRealizada>());
      },
    );

    testWidgets('si el aviso de duplicado manda a otra ubicación, la hoja devuelve cuál', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      m.salidaEdicion = const UbicacionExistenteElegida('ubi-2');

      await tester.tap(botonEditarUbicacion);
      await asentarHoja(tester);

      expect(m.salidas.single, isA<UbicacionExistenteElegida>());
      expect((m.salidas.single! as UbicacionExistenteElegida).ubicacionId, 'ubi-2');
    });

    testWidgets('doble toque: la edición se abre una sola vez y los botones esperan', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      m.esperaEdicion = Completer<SalidaModificarUbicacion?>();

      await tester.tap(botonEditarUbicacion);
      await tester.tap(botonEditarUbicacion, warnIfMissed: false);
      await tester.pump();

      expect(m.ediciones, hasLength(1));
      expect(habilitado(tester, botonEditarUbicacion), isFalse);
      expect(habilitado(tester, botonAgregarDepto), isFalse);
      m.esperaEdicion!.complete(null);
      await asentarHoja(tester);
      expect(habilitado(tester, botonEditarUbicacion), isTrue);
      expect(habilitado(tester, botonAgregarDepto), isTrue);
    });

    testWidgets('la edición que falla al abrirse avisa y no deja la hoja trabada', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      final espera = Completer<SalidaModificarUbicacion?>();
      m.esperaEdicion = espera;

      await tester.tap(botonEditarUbicacion);
      await tester.pump();
      expect(habilitado(tester, botonEditarUbicacion), isFalse);
      espera.completeError(StateError('no abrió'));
      await asentarHoja(tester);

      _seVeElAviso(tester, 'No pudimos abrir la edición. Probá de nuevo.');
      expect(habilitado(tester, botonEditarUbicacion), isTrue);
      expect(habilitado(tester, botonAgregarDepto), isTrue);
      expect(hojaUbicacion, findsOneWidget);
    });

    testWidgets('el aviso de la edición que falló se va al volver a intentar', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      final espera = Completer<SalidaModificarUbicacion?>();
      m.esperaEdicion = espera;
      await tester.tap(botonEditarUbicacion);
      await tester.pump();
      espera.completeError(StateError('no abrió'));
      await asentarHoja(tester);
      expect(_avisoDeLaHoja, findsOneWidget);

      m.esperaEdicion = null;
      await tester.tap(botonEditarUbicacion);
      await asentarHoja(tester);

      expect(m.ediciones, ['ubi-1', 'ubi-1']);
      expect(_avisoDeLaHoja, findsNothing);
    });

    testWidgets('con el texto al 200 % y 360×640 el aviso de la cuenta sigue a la vista', (
      tester,
    ) async {
      final m = await montarHoja(
        tester,
        espacios: _delCanvas,
        escala: 2,
        tamano: const Size(360, 640),
        abrir: false,
        extras: [estadoCuentaProvider.overrideWith(() => _CuentaFija(EstadoCuenta.suspendida))],
      );
      final contenedor = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final suscripcion = contenedor.listen(estadoCuentaProvider, (_, _) {});
      addTearDown(suscripcion.close);
      await asentarHoja(tester);
      await abrirLaHoja(tester);
      await tester.tap(botonEditarUbicacion);
      await asentarHoja(tester);

      expect(m.ediciones, isEmpty);
      _seVeElAviso(tester, TextosModuloBloqueado.suspendida);
    });
  });

  group('cerrar y volver a entrar', () {
    testWidgets('la ✕ cierra la hoja sin devolver nada', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas);

      await tester.tap(cerrarHojaUbicacion);
      await asentarHoja(tester);

      expect(hojaUbicacion, findsNothing);
      expect(m.salidas, [null]);
    });

    testWidgets('el atrás del sistema cierra la hoja', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas);

      await tester.binding.handlePopRoute();
      await asentarHoja(tester);

      expect(hojaUbicacion, findsNothing);
      expect(m.salidas, [null]);
    });

    testWidgets('al reentrar lee la lista al día: lo que cambió mientras estaba cerrada se ve', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: _delCanvas, tamano: const Size(390, 1400));
      await tester.tap(cerrarHojaUbicacion);
      await asentarHoja(tester);

      m.repo.espacios.add(espacioDe('e-301', '301', piso: '3', orden: 9));
      await abrirLaHoja(tester);

      expect(find.text('Depto 301'), findsOneWidget);
      expect(find.text('7 deptos'), findsOneWidget);
    });
  });

  group('datos límite', () {
    testWidgets(
      'una lista larga (300 deptos) se desplaza sin construirlos todos y llega al último',
      (tester) async {
        await montarHoja(
          tester,
          espacios: [
            for (var i = 1; i <= 300; i++)
              espacioDe('e-$i', '$i', piso: '${(i - 1) ~/ 10 + 1}', orden: i % 59),
          ],
        );

        expect(find.text('300 deptos'), findsOneWidget);
        expect(find.text('Depto 300'), findsNothing, reason: 'las filas son perezosas');
        await tester.scrollUntilVisible(
          find.text('Depto 300'),
          400,
          scrollable: find.descendant(of: hojaUbicacion, matching: find.byType(Scrollable)).first,
          maxScrolls: 200,
        );
        expect(find.text('Depto 300'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('textos largos: una dirección larga y un número de 40 caracteres no desbordan', (
      tester,
    ) async {
      await montarHoja(
        tester,
        ubicacion: ubicacionGuardada(
          tipo: TipoUbicacion.edificio,
          calle: 'Avenida Doctor Luis Alberto de Herrera y Obes de la Concepción',
          numero: '12345 bis',
        ),
        espacios: [
          espacioDe(
            'e-1',
            'Local comercial 4 planta baja fondo izq',
            piso: 'Entrepiso de servicio',
          ),
        ],
      );

      expect(find.textContaining('Avenida Doctor Luis Alberto'), findsOneWidget);
      expect(find.textContaining('Local comercial 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'texto del sistema al 200 %: la hoja sube casi a toda la pantalla, los botones y la '
      'lista se ven y no hay desbordes',
      (tester) async {
        await montarHoja(tester, espacios: _delCanvas, escala: 2);

        expect(botonAgregarDepto, findsOneWidget);
        expect(botonEditarUbicacion, findsOneWidget);
        expect(find.text('Depto 101'), findsOneWidget);
        expect(tester.getSize(hojaUbicacion).height, greaterThan(844 * 0.8));
        for (final b in [botonAgregarDepto, botonEditarUbicacion, cerrarHojaUbicacion]) {
          final caja = tester.getRect(b);
          expect(caja.height, greaterThanOrEqualTo(48));
          expect(caja.left, greaterThanOrEqualTo(0));
          expect(caja.right, lessThanOrEqualTo(390));
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('en un teléfono chico (320 × 568) con el texto al 200 % tampoco desborda', (
      tester,
    ) async {
      await montarHoja(tester, espacios: _delCanvas, escala: 2, tamano: const Size(320, 568));

      expect(botonAgregarDepto, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
