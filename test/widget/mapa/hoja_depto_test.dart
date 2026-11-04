// Vista 11 «Espacios», artboards 11·02 «Nuevo departamento» y 11·03 «Departamento repetido»
// (HU-UBI-007, #211): el alta de un depto, su edición, su baja y los avisos de la HU (la baja con
// personas y el bloqueo del último espacio activo). Un test por artboard, por aviso literal y por caso
// límite: doble toque, falla a mitad de la acción, dos acciones seguidas antes de que termine la
// primera, volver atrás y reentrar, datos límite y texto del sistema al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import 'hoja_espacios_arnes.dart';

final _delCanvas = [
  espacioDe('e-101', '101', piso: '1', orden: 1),
  espacioDe('e-102', '102', piso: '1', orden: 2),
  espacioDe('e-201', '201', piso: '2', orden: 3),
];

const _repetido102 = 'Ya existe el departamento 102 en este edificio.';
const _avisoDeLaHu =
    'Este espacio tiene 3 personas. Sus datos se conservarán pero el espacio quedará '
    'marcado como baja.';
const _ultimoDeLaHu =
    'No podés borrar el último espacio activo con personas. Agregá otro o reubicá las personas '
    'primero.';

void main() {
  group('11·02 Nuevo departamento', () {
    testWidgets('dibuja el rótulo, el título, los dos campos y los dos botones del canvas', (
      tester,
    ) async {
      await montarHoja(tester, espacios: _delCanvas);

      await abrirAltaDepto(tester);

      expect(find.text('MATAOJO 2044 · EDIFICIO'), findsOneWidget);
      expect(find.text('Nuevo departamento'), findsOneWidget);
      expect(find.text('NÚMERO · OBLIGATORIO'), findsOneWidget);
      expect(find.text('PISO · OPCIONAL'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Agregar'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Agregar y cargar otro'), findsOneWidget);
      expect(textoDe(tester, campoNumero), '');
      expect(textoDe(tester, campoPiso), '');
      expect(tester.takeException(), isNull);
    });

    testWidgets('no tiene campo de notas ni de descripción: solo número y piso (decisión de '
        'Cristian, 06/10; la nota por depto es #290)', (tester) async {
      await montarHoja(tester);

      await abrirAltaDepto(tester);

      expect(find.descendant(of: hojaDepto, matching: find.byType(TextField)), findsNWidgets(2));
      expect(find.textContaining('Nota'), findsNothing);
      expect(find.textContaining('escripción'), findsNothing);
    });

    testWidgets('el teclado del número arranca numérico y la tecla «ABC» lo pasa a letras (y '
        '«123» lo devuelve)', (tester) async {
      await montarHoja(tester);
      await abrirAltaDepto(tester);

      TextInputType tipo() => tester.widget<TextField>(campoNumero).keyboardType;
      expect(tipo(), TextInputType.number);
      expect(
        find.descendant(of: find.byKey(ClavesHojaDepto.numero), matching: find.text('ABC')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ClavesHojaDepto.alternarTecladoNumero));
      await asentarHoja(tester);
      expect(tipo(), TextInputType.text);
      expect(
        find.descendant(of: find.byKey(ClavesHojaDepto.numero), matching: find.text('123')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ClavesHojaDepto.alternarTecladoNumero));
      await asentarHoja(tester);
      expect(tipo(), TextInputType.number);
    });

    testWidgets('«Agregar» guarda el depto con su piso, cierra la hoja y la lista lo muestra en su '
        'grupo', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas, tamano: const Size(390, 1400));
      await abrirAltaDepto(tester);

      await escribir(tester, campoNumero, '301');
      await escribir(tester, campoPiso, '3');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(hojaDepto, findsNothing);
      final nuevo = m.repo.espacios.last;
      expect(nuevo.id, 'nuevo-1');
      expect(nuevo.numeroDepto, '301');
      expect(nuevo.piso, '3');
      expect(nuevo.ubicacionId, 'ubi-1');
      expect(nuevo.auditoria.createdBy, 'col-1');
      expect(find.text('Depto 301'), findsOneWidget);
      expect(find.text('PISO 3'), findsOneWidget);
      expect(find.text('4 deptos'), findsOneWidget);
    });

    testWidgets('el piso es opcional: sin piso el depto va a «SIN PISO»', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas, tamano: const Size(390, 1400));
      await abrirAltaDepto(tester);

      await escribir(tester, campoNumero, '9');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(m.repo.espacios.last.piso, isNull);
      expect(find.byKey(ClavesHojaUbicacion.grupo(null)), findsOneWidget);
    });

    testWidgets('el número y el piso se guardan sin los espacios de los bordes', (tester) async {
      final m = await montarHoja(tester);
      await abrirAltaDepto(tester);

      await escribir(tester, campoNumero, '  3B  ');
      await escribir(tester, campoPiso, '   ');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(m.repo.espacios.single.numeroDepto, '3B');
      expect(m.repo.espacios.single.piso, isNull);
    });

    testWidgets('sin número no guarda nada: lo pide en el campo y el botón sigue disponible', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      await abrirAltaDepto(tester);

      await escribir(tester, campoNumero, '   ');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(find.text('Ingresá el número o nombre del espacio.'), findsOneWidget);
      expect(m.repo.espacios, hasLength(3));
      expect(m.repo.llamadas, isEmpty);
      expect(hojaDepto, findsOneWidget);
      expect(habilitado(tester, botonAgregar), isTrue);
      expect(habilitado(tester, botonAgregarYCargarOtro), isTrue);

      await escribir(tester, campoNumero, '4');
      expect(find.text('Ingresá el número o nombre del espacio.'), findsNothing);
    });

    testWidgets('el número admite letras y guiones («PB-A», «Local 4»)', (tester) async {
      final m = await montarHoja(tester);
      await abrirAltaDepto(tester);

      await escribir(tester, campoNumero, 'PB-A');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);
      await escribir(tester, campoNumero, 'Local 4');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(m.repo.espacios.map((e) => e.numeroDepto), ['PB-A', 'Local 4']);
    });
  });

  group('«Agregar y cargar otro»', () {
    testWidgets('agrega el depto y deja el formulario listo para el siguiente: número vacío, mismo '
        'piso y la hoja abierta', (tester) async {
      final m = await montarHoja(tester);
      await abrirAltaDepto(tester);

      await escribir(tester, campoNumero, '101');
      await escribir(tester, campoPiso, '1');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);

      expect(m.repo.espacios, hasLength(1));
      expect(hojaDepto, findsOneWidget);
      expect(textoDe(tester, campoNumero), '');
      expect(textoDe(tester, campoPiso), '1');
      expect(habilitado(tester, botonAgregar), isTrue);
    });

    testWidgets('«PB-A» y «pb a» son el mismo número: el segundo es repetido (canvas 11·03)', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: [espacioDe('e-pba', 'PB-A', piso: 'PB')]);
      await abrirAltaDepto(tester);

      await escribir(tester, campoNumero, 'pb a');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(find.text('Ya existe el departamento PB-A en este edificio.'), findsOneWidget);
      expect(m.repo.espacios, hasLength(1));
      expect(textoDe(tester, campoNumero), 'pb a', reason: 'lo escrito no se pierde');
    });

    testWidgets('al editar, cambiar «PB-B» a «pb a» choca con «PB-A»', (tester) async {
      final m = await montarHoja(
        tester,
        espacios: [
          espacioDe('e-pba', 'PB-A', piso: 'PB'),
          espacioDe('e-pbb', 'PB-B', piso: 'PB'),
        ],
      );
      await abrirEdicionDepto(tester, 'e-pbb');

      await escribir(tester, campoNumero, 'pb a');
      await tester.tap(botonGuardarDepto);
      await asentarHoja(tester);

      expect(find.text('Ya existe el departamento PB-A en este edificio.'), findsOneWidget);
      expect(m.repo.espacios.map((e) => e.numeroDepto), ['PB-A', 'PB-B']);
    });

    testWidgets(
      '«Agregar y cargar otro» confirma a la vista «Depto 101 agregado.» sobre el campo y '
      'la línea se va cuando empieza a escribir el siguiente',
      (tester) async {
        await montarHoja(tester);
        await abrirAltaDepto(tester);
        expect(find.byKey(ClavesHojaDepto.agregado), findsNothing);

        await escribir(tester, campoNumero, '101');
        await tester.tap(botonAgregarYCargarOtro);
        await asentarHoja(tester);

        expect(find.byKey(ClavesHojaDepto.agregado), findsOneWidget);
        expect(find.text('Depto 101 agregado.'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(ClavesHojaDepto.agregado)).dy,
          lessThan(tester.getTopLeft(campoNumero).dy),
          reason: 'la línea va sobre el campo',
        );

        await escribir(tester, campoNumero, '1');
        await tester.pump();
        expect(find.byKey(ClavesHojaDepto.agregado), findsNothing);
        expect(find.text('Depto 101 agregado.'), findsNothing);
      },
    );

    testWidgets('la línea de «agregado» no es región viva (el lector la recibe una sola vez, como '
        'anuncio) y la del último se reemplaza por la del siguiente', (tester) async {
      await montarHoja(tester);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '101');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);

      final semantica = tester.getSemantics(find.text('Depto 101 agregado.'));
      expect(semantica.flagsCollection.isLiveRegion, isFalse);

      await escribir(tester, campoNumero, '102');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);
      expect(find.text('Depto 101 agregado.'), findsNothing);
      expect(find.text('Depto 102 agregado.'), findsOneWidget);
    });

    testWidgets('si el siguiente falla, la línea del anterior se va y queda el aviso de la falla', (
      tester,
    ) async {
      final m = await montarHoja(tester);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '101');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);
      expect(find.text('Depto 101 agregado.'), findsOneWidget);

      m.repo.fallas.add(const FailureInesperado(causa: 'disco'));
      await escribir(tester, campoNumero, '102');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);

      expect(find.text('Depto 101 agregado.'), findsNothing);
      expect(find.byKey(ClavesHojaDepto.falla), findsOneWidget);
      expect(habilitado(tester, botonAgregar), isTrue);
    });

    testWidgets('dos seguidos agregan dos deptos distintos con ids distintos; la lista de abajo '
        'los muestra al cerrar', (tester) async {
      final m = await montarHoja(tester, tamano: const Size(390, 1400));
      await abrirAltaDepto(tester);

      await escribir(tester, campoNumero, '101');
      await escribir(tester, campoPiso, '1');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);
      await escribir(tester, campoNumero, '102');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);
      await escribir(tester, campoNumero, '103');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(m.repo.espacios.map((e) => e.numeroDepto), ['101', '102', '103']);
      expect(m.repo.espacios.map((e) => e.id).toSet(), hasLength(3));
      expect(m.repo.espacios.map((e) => e.piso), ['1', '1', '1']);
      expect(find.text('3 deptos'), findsOneWidget);
      expect(find.text('Depto 102'), findsOneWidget);
    });

    testWidgets('el número que se acaba de cargar ya es repetido para el siguiente', (
      tester,
    ) async {
      final m = await montarHoja(tester);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '101');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);

      await escribir(tester, campoNumero, '101');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);

      expect(find.text('Ya existe el departamento 101 en este edificio.'), findsOneWidget);
      expect(m.repo.espacios, hasLength(1));
    });

    testWidgets('dos acciones seguidas antes de que termine la primera: la segunda espera y no se '
        'pisa ni se pierde ninguna', (tester) async {
      final m = await montarHoja(tester);
      await abrirAltaDepto(tester);
      final espera = Completer<void>();
      m.repo.espera = espera;

      await escribir(tester, campoNumero, '101');
      await tester.tap(botonAgregarYCargarOtro);
      await tester.pump();
      // Con la primera en curso nada más se toca.
      expect(habilitado(tester, botonAgregar), isFalse);
      expect(habilitado(tester, botonAgregarYCargarOtro), isFalse);
      await tester.tap(botonAgregar, warnIfMissed: false);
      await tester.pump();
      expect(m.repo.llamadas, ['agregar:nuevo-1']);

      espera.complete();
      await asentarHoja(tester);
      expect(m.repo.espacios, hasLength(1));
      expect(hojaDepto, findsOneWidget);

      await escribir(tester, campoNumero, '102');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);
      expect(m.repo.espacios.map((e) => e.numeroDepto), ['101', '102']);
      expect(m.idsGenerados, ['nuevo-1', 'nuevo-2']);
    });
  });

  group('11·03 Departamento repetido', () {
    testWidgets(
      'si el número ya existe en el edificio avisa con el texto del canvas, ofrece «Ver depto '
      '102 ›» y no agrega nada',
      (tester) async {
        final m = await montarHoja(tester, espacios: _delCanvas);
        await abrirAltaDepto(tester);

        await escribir(tester, campoNumero, '102');
        await tester.tap(botonAgregar);
        await asentarHoja(tester);

        expect(find.text(_repetido102), findsOneWidget);
        expect(find.text('Ver depto 102 ›'), findsOneWidget);
        expect(m.repo.espacios, hasLength(3));
        expect(hojaDepto, findsOneWidget);
        expect(textoDe(tester, campoNumero), '102', reason: 'lo escrito no se pierde');
        expect(habilitado(tester, botonAgregar), isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('el repetido se compara sin espacios ni mayúsculas: «1 02» o «PB a» vs «pb  A»', (
      tester,
    ) async {
      final m = await montarHoja(
        tester,
        espacios: [
          espacioDe('e-pb', 'pb A', piso: 'PB'),
          espacioDe('e-102', '102', piso: '1'),
        ],
      );
      await abrirAltaDepto(tester);

      await escribir(tester, campoNumero, 'PB  a');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);
      expect(find.text('Ya existe el departamento pb A en este edificio.'), findsOneWidget);

      await escribir(tester, campoNumero, '1 02');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);
      expect(find.text(_repetido102), findsOneWidget);
      expect(m.repo.espacios, hasLength(2));
    });

    testWidgets('un depto dado de baja no cuenta: su número se puede volver a usar', (
      tester,
    ) async {
      final m = await montarHoja(
        tester,
        espacios: [espacioDe('e-102', '102', piso: '1', baja: DateTime.utc(2026, 10, 21))],
      );
      await abrirAltaDepto(tester);

      await escribir(tester, campoNumero, '102');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(find.text(_repetido102), findsNothing);
      expect(m.repo.activos.map((e) => e.numeroDepto), ['102']);
    });

    testWidgets('al cambiar el número el aviso de repetido se va', (tester) async {
      await montarHoja(tester, espacios: _delCanvas);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '102');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);
      expect(avisoRepetido, findsOneWidget);

      await escribir(tester, campoNumero, '103');

      expect(avisoRepetido, findsNothing);
    });

    testWidgets('«Ver depto 102 ›» cierra la hoja y deja a la vista y señalado ese depto', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: _delCanvas, tamano: const Size(390, 1400));
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '102');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      await tester.tap(enlaceVerRepetido);
      await asentarHoja(tester);

      expect(hojaDepto, findsNothing);
      expect(hojaUbicacion, findsOneWidget);
      expect(m.repo.espacios, hasLength(3));
      final fila = tester.widget<Material>(
        find.ancestor(of: filaDepto('e-102'), matching: find.byType(Material)).first,
      );
      final otra = tester.widget<Material>(
        find.ancestor(of: filaDepto('e-101'), matching: find.byType(Material)).first,
      );
      expect(fila.color, isNot(otra.color), reason: 'el depto 102 queda señalado');
    });

    testWidgets('con muchos deptos «Ver depto» llega a una fila lejana', (tester) async {
      await montarHoja(
        tester,
        espacios: [
          for (var i = 1; i <= 200; i++)
            espacioDe('e-$i', '$i', piso: '${(i - 1) ~/ 10 + 1}', orden: i % 59),
        ],
      );
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '190');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      await tester.tap(enlaceVerRepetido);
      await asentarHoja(tester, 30);

      expect(filaDepto('e-190'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('casos límite del alta', () {
    testWidgets('doble toque en «Agregar»: un solo depto', (tester) async {
      final m = await montarHoja(tester);
      await abrirAltaDepto(tester);
      final espera = Completer<void>();
      m.repo.espera = espera;
      await escribir(tester, campoNumero, '101');

      await tester.tap(botonAgregar);
      await tester.tap(botonAgregar, warnIfMissed: false);
      await tester.pump();
      expect(m.repo.llamadas, ['agregar:nuevo-1']);
      expect(habilitado(tester, botonAgregar), isFalse);
      expect(find.text('Agregando…'), findsOneWidget);
      espera.complete();
      await asentarHoja(tester);

      expect(m.repo.espacios, hasLength(1));
      expect(hojaDepto, findsNothing);
    });

    testWidgets('doble toque en «+ Departamento»: se abre una sola hoja', (tester) async {
      await montarHoja(tester, espacios: _delCanvas);

      await tester.tap(botonAgregarDepto);
      await tester.tap(botonAgregarDepto, warnIfMissed: false);
      await asentarHoja(tester);
      expect(hojaDepto, findsOneWidget);

      await tester.binding.handlePopRoute();
      await asentarHoja(tester);
      expect(hojaDepto, findsNothing, reason: 'no quedó otra hoja debajo');
      expect(habilitado(tester, botonAgregarDepto), isTrue);
    });

    testWidgets('mientras guarda la hoja no se puede cerrar con el atrás del sistema', (
      tester,
    ) async {
      final m = await montarHoja(tester);
      await abrirAltaDepto(tester);
      final espera = Completer<void>();
      m.repo.espera = espera;
      await escribir(tester, campoNumero, '101');
      await tester.tap(botonAgregar);
      await tester.pump();

      await tester.binding.handlePopRoute();
      await asentarHoja(tester);
      expect(hojaDepto, findsOneWidget);

      espera.complete();
      await asentarHoja(tester);
      expect(hojaDepto, findsNothing);
      expect(m.repo.espacios, hasLength(1));
    });

    testWidgets('falla a mitad del alta: avisa, los botones vuelven a estar disponibles y el '
        'reintento no duplica el depto', (tester) async {
      final m = await montarHoja(tester);
      await abrirAltaDepto(tester);
      m.repo.fallas.add(const FailureInesperado(causa: 'disco'));
      await escribir(tester, campoNumero, '101');

      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(find.text('No pudimos guardar el departamento. Probá de nuevo.'), findsOneWidget);
      expect(m.repo.espacios, isEmpty);
      expect(habilitado(tester, botonAgregar), isTrue);
      expect(habilitado(tester, botonAgregarYCargarOtro), isTrue);
      expect(find.text('Agregando…'), findsNothing);

      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(m.repo.espacios, hasLength(1));
      expect(m.repo.llamadas, [
        'agregar:nuevo-1',
        'agregar:nuevo-1',
      ], reason: 'mismo id: idempotente');
      expect(hojaDepto, findsNothing);
    });

    testWidgets('una excepción del repositorio tampoco deja el botón en «Agregando…»', (
      tester,
    ) async {
      final m = await montarHoja(tester);
      await abrirAltaDepto(tester);
      m.repo.lanzas.add(StateError('roto'));
      await escribir(tester, campoNumero, '101');

      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);

      expect(avisoFalla, findsOneWidget);
      expect(habilitado(tester, botonAgregar), isTrue);
      expect(habilitado(tester, botonAgregarYCargarOtro), isTrue);
      expect(find.text('Agregando…'), findsNothing);
    });

    testWidgets('el aviso de una falla se va al volver a intentar', (tester) async {
      final m = await montarHoja(tester);
      await abrirAltaDepto(tester);
      m.repo.fallas.add(const FailureInesperado(causa: 'disco'));
      await escribir(tester, campoNumero, '101');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);
      expect(avisoFalla, findsOneWidget);

      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);

      expect(avisoFalla, findsNothing);
    });

    testWidgets('una ubicación dada de baja no admite deptos y lo dice', (tester) async {
      final u = edificioMataojo();
      final m = await montarHoja(tester, ubicacion: u);
      await abrirAltaDepto(tester);
      m.repo.fallas.add(
        const FailureValidacion(
          campos: {
            'ubicacionId':
                'La ubicación está dada de baja: restaurala antes de agregarle espacios.',
          },
        ),
      );
      await escribir(tester, campoNumero, '1');

      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(
        find.text('La ubicación está dada de baja: restaurala antes de agregarle espacios.'),
        findsOneWidget,
      );
      expect(habilitado(tester, botonAgregar), isTrue);
    });

    testWidgets('volver atrás y reentrar: la hoja del alta arranca vacía, sin avisos y con un id '
        'nuevo', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '102');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);
      expect(avisoRepetido, findsOneWidget);

      await tester.binding.handlePopRoute();
      await asentarHoja(tester);
      expect(hojaDepto, findsNothing);
      await abrirAltaDepto(tester);

      expect(textoDe(tester, campoNumero), '');
      expect(avisoRepetido, findsNothing);
      expect(avisoFalla, findsNothing);
      await escribir(tester, campoNumero, '301');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);
      expect(m.repo.espacios.last.id, m.idsGenerados.last);
      expect(m.repo.espacios, hasLength(4));
    });

    testWidgets(
      'datos límite: el número se corta a 40 caracteres, el piso a 20 y un pegado en varias '
      'líneas queda en una',
      (tester) async {
        await montarHoja(tester);
        await abrirAltaDepto(tester);

        await escribir(tester, campoNumero, 'A' * 80);
        await escribir(tester, campoPiso, 'P' * 50);
        expect(textoDe(tester, campoNumero), hasLength(40));
        expect(textoDe(tester, campoPiso), hasLength(20));

        await escribir(tester, campoNumero, '1\n2\r\n3');
        expect(textoDe(tester, campoNumero), isNot(contains('\n')));
      },
    );

    testWidgets('texto del sistema al 200 %: la hoja entra sin desbordes y los botones se ven', (
      tester,
    ) async {
      await montarHoja(tester, espacios: _delCanvas, escala: 2, tamano: const Size(360, 700));
      await abrirAltaDepto(tester);

      await escribir(tester, campoNumero, '102');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      for (final b in [botonAgregar, botonAgregarYCargarOtro]) {
        final caja = tester.getRect(b);
        expect(caja.height, greaterThanOrEqualTo(48));
        expect(caja.left, greaterThanOrEqualTo(0));
        expect(caja.right, lessThanOrEqualTo(360));
      }
      expect(find.text(_repetido102), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con el teclado abierto la hoja sube y el botón sigue a la vista', (tester) async {
      await montarHoja(tester, tamano: const Size(390, 700));
      await abrirAltaDepto(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await asentarHoja(tester);

      // El campo que se escribe queda sobre el teclado y los botones se alcanzan desplazando.
      final campo = tester.getRect(campoNumero);
      expect(campo.top, greaterThanOrEqualTo(0));
      expect(campo.bottom, lessThanOrEqualTo(700 - 300 + 1));
      await tester.ensureVisible(botonAgregarYCargarOtro);
      await asentarHoja(tester);
      expect(tester.getRect(botonAgregarYCargarOtro).bottom, lessThanOrEqualTo(700 - 300 + 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('edición de un depto', () {
    testWidgets('tocar un depto abre la hoja con sus datos y «Guardar»', (tester) async {
      await montarHoja(tester, espacios: _delCanvas);

      await abrirEdicionDepto(tester, 'e-102');

      expect(find.text('Editar departamento'), findsOneWidget);
      expect(textoDe(tester, campoNumero), '102');
      expect(textoDe(tester, campoPiso), '1');
      expect(botonGuardarDepto, findsOneWidget);
      expect(botonAgregar, findsNothing);
      expect(botonDarDeBaja, findsOneWidget);
    });

    testWidgets('cambia el número y el piso y la lista se reordena', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas, tamano: const Size(390, 1400));
      await abrirEdicionDepto(tester, 'e-102');

      await escribir(tester, campoNumero, '302');
      await escribir(tester, campoPiso, '3');
      await tester.tap(botonGuardarDepto);
      await asentarHoja(tester);

      expect(hojaDepto, findsNothing);
      final guardado = m.repo.espacios.firstWhere((e) => e.id == 'e-102');
      expect(guardado.numeroDepto, '302');
      expect(guardado.piso, '3');
      expect(find.text('Depto 302'), findsOneWidget);
      expect(find.text('Depto 102'), findsNothing);
      expect(find.text('PISO 3'), findsOneWidget);
    });

    testWidgets('puede quitarle el piso', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      await abrirEdicionDepto(tester, 'e-102');

      await escribir(tester, campoPiso, '');
      await tester.tap(botonGuardarDepto);
      await asentarHoja(tester);

      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-102').piso, isNull);
    });

    testWidgets('puede ponerle número a un depto sin número (11·01 «Sin número» → «Editar»)', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: [espacioDe('e-1', null)]);
      await abrirEdicionDepto(tester, 'e-1');
      expect(textoDe(tester, campoNumero), '');

      await escribir(tester, campoNumero, '12');
      await tester.tap(botonGuardarDepto);
      await asentarHoja(tester);

      expect(m.repo.espacios.single.numeroDepto, '12');
      expect(find.text('Depto 12'), findsOneWidget);
      expect(find.text('Sin número'), findsNothing);
    });

    testWidgets('si lo dejan sin número no guarda y lo pide', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      await abrirEdicionDepto(tester, 'e-102');

      await escribir(tester, campoNumero, '');
      await tester.tap(botonGuardarDepto);
      await asentarHoja(tester);

      expect(find.text('Ingresá el número o nombre del espacio.'), findsOneWidget);
      expect(m.repo.llamadas, isEmpty);
      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-102').numeroDepto, '102');
    });

    testWidgets('con el número de otro depto avisa que está repetido y ofrece verlo', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      await abrirEdicionDepto(tester, 'e-102');

      await escribir(tester, campoNumero, '101');
      await tester.tap(botonGuardarDepto);
      await asentarHoja(tester);

      expect(find.text('Ya existe el departamento 101 en este edificio.'), findsOneWidget);
      expect(find.text('Ver depto 101 ›'), findsOneWidget);
      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-102').numeroDepto, '102');
    });

    testWidgets(
      'guardar sin cambiar el número (solo el piso) no lo toma por repetido de sí mismo',
      (tester) async {
        final m = await montarHoja(tester, espacios: _delCanvas);
        await abrirEdicionDepto(tester, 'e-102');

        await escribir(tester, campoPiso, '9');
        await tester.tap(botonGuardarDepto);
        await asentarHoja(tester);

        expect(find.textContaining('Ya existe'), findsNothing);
        expect(m.repo.espacios.firstWhere((e) => e.id == 'e-102').piso, '9');
      },
    );

    testWidgets('doble toque en «Guardar»: una sola escritura; y si falla, el botón vuelve', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      await abrirEdicionDepto(tester, 'e-102');
      final espera = Completer<void>();
      m.repo.espera = espera;
      m.repo.fallas.add(const FailureInesperado(causa: 'x'));
      await escribir(tester, campoNumero, '150');

      await tester.tap(botonGuardarDepto);
      await tester.tap(botonGuardarDepto, warnIfMissed: false);
      await tester.pump();
      expect(m.repo.llamadas, ['modificar:e-102']);
      expect(find.text('Guardando…'), findsOneWidget);
      expect(habilitado(tester, botonDarDeBaja), isFalse);
      espera.complete();
      await asentarHoja(tester);

      expect(find.text('No pudimos guardar el departamento. Probá de nuevo.'), findsOneWidget);
      expect(habilitado(tester, botonGuardarDepto), isTrue);
      expect(habilitado(tester, botonDarDeBaja), isTrue);

      await tester.tap(botonGuardarDepto);
      await asentarHoja(tester);
      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-102').numeroDepto, '150');
    });

    testWidgets('doble toque en una fila: la hoja de edición se abre una sola vez', (tester) async {
      await montarHoja(tester, espacios: _delCanvas);

      await tester.tap(filaDepto('e-101'));
      await tester.tap(filaDepto('e-102'), warnIfMissed: false);
      await asentarHoja(tester);

      expect(hojaDepto, findsOneWidget);
      expect(textoDe(tester, campoNumero), '101');
    });
  });

  group('baja de un depto', () {
    testWidgets('sin personas: pide confirmar, y al confirmar el depto deja de aparecer', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      await abrirEdicionDepto(tester, 'e-102');

      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      expect(find.text('¿Dar de baja el depto 102?'), findsOneWidget);
      expect(find.text('Deja de aparecer en la lista del edificio.'), findsOneWidget);
      expect(m.repo.llamadas, isEmpty, reason: 'todavía no se escribió nada');

      await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
      await asentarHoja(tester);

      expect(hojaDepto, findsNothing);
      expect(m.repo.activos.map((e) => e.id), ['e-101', 'e-201']);
      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-102').estaBorrada, isTrue);
      expect(find.text('Depto 102'), findsNothing);
      expect(find.text('2 deptos'), findsOneWidget);
    });

    testWidgets('«Cancelar» no da de baja nada y deja la hoja como estaba', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      await abrirEdicionDepto(tester, 'e-102');
      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);

      await tester.tap(find.byKey(ClavesHojaDepto.cancelarBaja));
      await asentarHoja(tester);

      expect(hojaDepto, findsOneWidget);
      expect(m.repo.llamadas, isEmpty);
      expect(habilitado(tester, botonDarDeBaja), isTrue);
      expect(habilitado(tester, botonGuardarDepto), isTrue);
    });

    testWidgets('con personas: muestra el aviso literal de la HU y recién al confirmar da de baja; '
        'los datos de las personas no se tocan', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas, personas: {'e-102': 3});
      await abrirEdicionDepto(tester, 'e-102');

      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);

      expect(find.text(_avisoDeLaHu), findsOneWidget);
      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-102').estaBorrada, isFalse);

      await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
      await asentarHoja(tester);

      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-102').estaBorrada, isTrue);
      expect(m.contador.personas['e-102'], 3, reason: 'las personas se conservan');
      expect(find.text('Depto 102'), findsNothing);
    });

    testWidgets('con una sola persona el aviso va en singular', (tester) async {
      await montarHoja(tester, espacios: _delCanvas, personas: {'e-102': 1});
      await abrirEdicionDepto(tester, 'e-102');

      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);

      expect(
        find.text(
          'Este espacio tiene 1 persona. Sus datos se conservarán pero el espacio quedará marcado '
          'como baja.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('con personas, «Cancelar» en el aviso no da de baja nada', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas, personas: {'e-102': 3});
      await abrirEdicionDepto(tester, 'e-102');
      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);

      await tester.tap(find.byKey(ClavesHojaDepto.cancelarBaja));
      await asentarHoja(tester);

      expect(m.repo.llamadas, isEmpty);
      expect(hojaDepto, findsOneWidget);
    });

    testWidgets('el último espacio activo con personas no se puede dar de baja: dice el aviso '
        'literal de la HU y no cambia nada', (tester) async {
      final m = await montarHoja(
        tester,
        espacios: [espacioDe('e-1', '101', piso: '1')],
        personas: {'e-1': 2},
      );
      await abrirEdicionDepto(tester, 'e-1');

      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);

      expect(find.byKey(ClavesHojaDepto.bajaBloqueada), findsOneWidget);
      expect(find.text(_ultimoDeLaHu), findsOneWidget);
      expect(find.text(_avisoDeLaHu), findsNothing);
      expect(m.repo.llamadas, isEmpty);

      await tester.tap(find.text('Entendido'));
      await asentarHoja(tester);

      expect(hojaDepto, findsOneWidget);
      expect(habilitado(tester, botonDarDeBaja), isTrue);
      expect(m.repo.espacios.single.estaBorrada, isFalse);
    });

    testWidgets('el último espacio sin personas sí se puede dar de baja', (tester) async {
      final m = await montarHoja(tester, espacios: [espacioDe('e-1', '101')]);
      await abrirEdicionDepto(tester, 'e-1');

      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
      await asentarHoja(tester);

      expect(m.repo.espacios.single.estaBorrada, isTrue);
      expect(find.text('Todavía no hay departamentos'), findsOneWidget);
    });

    testWidgets('con otro espacio activo, el que tiene personas sí se puede dar de baja con el '
        'aviso', (tester) async {
      final m = await montarHoja(
        tester,
        espacios: [espacioDe('e-1', '101'), espacioDe('e-2', '102')],
        personas: {'e-1': 3},
      );
      await abrirEdicionDepto(tester, 'e-1');

      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
      await asentarHoja(tester);

      expect(m.repo.activos.map((e) => e.id), ['e-2']);
    });

    testWidgets('falla a mitad de la baja: avisa y los botones vuelven a estar disponibles', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      await abrirEdicionDepto(tester, 'e-102');
      m.repo.fallas.add(const FailureInesperado(causa: 'disco'));

      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
      await asentarHoja(tester);

      expect(find.text('No pudimos guardar el departamento. Probá de nuevo.'), findsNothing);
      expect(find.text('No pudimos dar de baja el departamento. Probá de nuevo.'), findsOneWidget);
      expect(habilitado(tester, botonDarDeBaja), isTrue);
      expect(habilitado(tester, botonGuardarDepto), isTrue);
      expect(find.text('Dando de baja…'), findsNothing);
      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-102').estaBorrada, isFalse);

      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
      await asentarHoja(tester);
      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-102').estaBorrada, isTrue);
    });

    testWidgets('si no se pueden contar las personas lo dice y no deja el botón trabado', (
      tester,
    ) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      await abrirEdicionDepto(tester, 'e-102');
      m.contador.lanza = StateError('roto');

      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);

      expect(find.text('No pudimos dar de baja el departamento. Probá de nuevo.'), findsOneWidget);
      expect(habilitado(tester, botonDarDeBaja), isTrue);
      expect(m.repo.llamadas, isEmpty);
    });

    testWidgets('doble toque en «Dar de baja»: un solo aviso', (tester) async {
      await montarHoja(tester, espacios: _delCanvas, personas: {'e-102': 2});
      await abrirEdicionDepto(tester, 'e-102');

      await tester.tap(botonDarDeBaja);
      await tester.tap(botonDarDeBaja, warnIfMissed: false);
      await asentarHoja(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('dos acciones seguidas: con la baja en curso «Guardar» espera', (tester) async {
      final m = await montarHoja(tester, espacios: _delCanvas);
      await abrirEdicionDepto(tester, 'e-102');
      final espera = Completer<void>();
      m.repo.espera = espera;
      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
      await tester.pump();
      await tester.pump();

      expect(habilitado(tester, botonGuardarDepto), isFalse);
      expect(find.text('Dando de baja…'), findsOneWidget);
      espera.complete();
      await asentarHoja(tester);

      expect(m.repo.llamadas, ['baja:e-102']);
      expect(hojaDepto, findsNothing);
    });
  });
}
