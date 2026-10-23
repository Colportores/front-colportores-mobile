// HU-UBI-008 / vista 11·04 «Departamento con sus clientes» y 32A·05 «varias personas en el espacio»:
// la lista de clientes del depto, «+ Agregar cliente», el aviso al volver del alta y los estados que
// el canvas no dibuja (cargando, vacío, error al leer, espacio de baja, espacio que ya no está).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart';

PersonaRepositorioFalso _conDosClientes() => PersonaRepositorioFalso()
  ..sembrar([
    clienteDePersonas('p1', 'Ana', apellido: 'Martínez', telefono: '099 123 412', minutos: 0),
    clienteDePersonas('p2', 'Pedro', apellido: 'Rodríguez', minutos: 1),
  ]);

const _agregar = '+ Agregar cliente';

Future<void> _agregarJorge(WidgetTester tester) async {
  await tester.tap(find.text(_agregar));
  await asentar(tester);
  await tester.enterText(
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Obligatorio'),
    'Jorge',
  );
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Guardar persona'));
  await asentar(tester);
}

void main() {
  group('11·04 · departamento con sus clientes', () {
    testWidgets('dado un depto con dos clientes, cuando se abre, muestra el encabezado, las filas '
        'con iniciales, nombre y teléfono tapado, y la nota de privacidad', (tester) async {
      await montarClientes(tester, repo: _conDosClientes());

      expect(find.text('MATAOJO 2044'), findsOneWidget);
      expect(find.text('Depto 101'), findsOneWidget);
      expect(find.text('Piso 1'), findsOneWidget);
      expect(find.text('CLIENTES · 2'), findsOneWidget);
      expect(find.text(_agregar), findsOneWidget);
      expect(find.text('AM'), findsOneWidget);
      expect(find.text('Ana Martínez'), findsOneWidget);
      expect(find.text('Tel. 099 ••• 412'), findsOneWidget);
      expect(find.text('PR'), findsOneWidget);
      expect(find.text('Pedro Rodríguez'), findsOneWidget);
      expect(find.text('Sin teléfono'), findsOneWidget);
      expect(
        find.text(
          'Los datos de los clientes quedan solo en tu celular. Al coordinador le llega el '
          'estado de las visitas.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('dado lo que el canvas dibuja pero es de otros issues, cuando se abre, no hay '
        '«Registrar visita», «Editar» ni «›» muertos', (tester) async {
      await montarClientes(tester, repo: _conDosClientes());

      expect(find.text('Registrar visita'), findsNothing);
      expect(find.text('Editar'), findsNothing);
      expect(find.text('›'), findsNothing);
    });

    testWidgets(
      'dado un depto sin número, cuando se abre, el título dice «Sin número» y no hay piso',
      (tester) async {
        await montarClientes(tester, contexto: contextoActivo(numeroDepto: null, piso: null));

        expect(find.text('Sin número'), findsOneWidget);
        expect(find.text('Piso 1'), findsNothing);
      },
    );

    testWidgets('dado un cliente sin apellido, cuando se muestra, lleva una sola inicial y solo el '
        'nombre', (tester) async {
      final repo = PersonaRepositorioFalso()..sembrar([clienteDePersonas('p1', 'jorge')]);
      await montarClientes(tester, repo: repo);

      expect(find.text('J'), findsOneWidget);
      expect(find.text('jorge'), findsOneWidget);
    });

    testWidgets('dado «Volver», cuando se toca, regresa a la pantalla anterior', (tester) async {
      await montarClientes(tester, repo: _conDosClientes());

      await tester.tap(find.byTooltip('Volver'));
      await asentar(tester);

      expect(find.text('abrir clientes'), findsOneWidget);
      expect(find.text('CLIENTES · 2'), findsNothing);
    });

    testWidgets('dado que se vuelve atrás y se reentra, cuando se abre otra vez, la lista sigue '
        'igual', (tester) async {
      await montarClientes(tester, repo: _conDosClientes());
      await tester.tap(find.byTooltip('Volver'));
      await asentar(tester);

      await tester.tap(find.text('abrir clientes'));
      await asentar(tester);

      expect(find.text('CLIENTES · 2'), findsOneWidget);
      expect(find.text('Ana Martínez'), findsOneWidget);
    });
  });

  group('estados que el canvas no dibuja', () {
    testWidgets('dado que la lista todavía no llegó, cuando se abre, dice que está cargando y no '
        'ofrece agregar con datos a medias', (tester) async {
      final handle = tester.ensureSemantics();
      await montarClientes(tester, repo: PersonaRepositorioCargando());

      expect(find.bySemanticsLabel('Cargando los clientes'), findsOneWidget);
      expect(find.text('Todavía no hay clientes'), findsNothing);
      expect(find.text('CLIENTES'), findsOneWidget);
      handle.dispose();
    });

    testWidgets(
      'dado un depto sin clientes, cuando se abre, dice que todavía no hay y deja agregar',
      (tester) async {
        await montarClientes(tester);

        expect(find.text('CLIENTES · 0'), findsOneWidget);
        expect(find.text('Todavía no hay clientes'), findsOneWidget);
        expect(find.text('Los clientes que agregues van a aparecer acá.'), findsOneWidget);
        expect(find.text(_agregar), findsOneWidget);
      },
    );

    testWidgets('dado que la lectura falla, cuando se abre, muestra el error con «Reintentar» y al '
        'tocarlo se recupera', (tester) async {
      final repo = PersonaRepositorioQueFallaUnaVez()
        ..sembrar([clienteDePersonas('p1', 'Ana', apellido: 'Martínez')]);
      await montarClientes(tester, repo: repo);

      expect(find.text('No pudimos leer los clientes en tu teléfono.'), findsOneWidget);
      expect(find.text(_agregar), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await asentar(tester);

      expect(find.text('No pudimos leer los clientes en tu teléfono.'), findsNothing);
      expect(find.text('Ana Martínez'), findsOneWidget);
    });

    testWidgets('dado que no se pudo leer el espacio, cuando se abre, muestra el error con '
        '«Reintentar»', (tester) async {
      await montarClientes(tester, fallaDeContexto: const FailureInesperado(causa: 'x'));

      expect(find.text('No pudimos leer los clientes en tu teléfono.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('dado un espacio que ya no está en el teléfono, cuando se abre, lo dice y no deja '
        'agregar', (tester) async {
      await montarClientes(tester, contextoNulo: true);

      expect(find.text('El espacio ya no está en tu teléfono. Volvé a la lista.'), findsOneWidget);
      expect(find.text(_agregar), findsNothing);
    });

    testWidgets('dado un espacio dado de baja, cuando se abre, es de solo lectura: se ven los '
        'clientes y no se puede agregar', (tester) async {
      await montarClientes(
        tester,
        repo: _conDosClientes(),
        contexto: contextoActivo(espacioDeBaja: DateTime.utc(2026, 10, 20)),
      );

      expect(find.textContaining('Espacio dado de baja: solo lectura'), findsOneWidget);
      expect(find.text('Ana Martínez'), findsOneWidget);
      expect(find.text(_agregar), findsNothing);
    });
  });

  group('32A·05 · varias personas en el espacio', () {
    testWidgets('dado dos clientes, cuando agrega a Jorge, vuelve a la lista con tres y muestra '
        '«Guardamos a Jorge en este teléfono.»', (tester) async {
      final repo = _conDosClientes();
      await montarClientes(tester, repo: repo);

      await _agregarJorge(tester);

      expect(find.text('CLIENTES · 3'), findsOneWidget);
      expect(find.text('Jorge'), findsWidgets);
      expect(find.text('Guardamos a Jorge en este teléfono.'), findsOneWidget);
      expect(find.text('Nueva persona'), findsNothing);
    });

    testWidgets(
      'dado un depto sin clientes, cuando agrega al primero, la lista pasa de vacía a uno',
      (tester) async {
        await montarClientes(tester);
        expect(find.text('Todavía no hay clientes'), findsOneWidget);

        await _agregarJorge(tester);

        expect(find.text('Todavía no hay clientes'), findsNothing);
        expect(find.text('CLIENTES · 1'), findsOneWidget);
      },
    );

    testWidgets('dado el alta abierta, cuando se cierra sin guardar, no hay aviso y la lista queda '
        'igual', (tester) async {
      await montarClientes(tester, repo: _conDosClientes());
      await tester.tap(find.text(_agregar));
      await asentar(tester);

      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('CLIENTES · 2'), findsOneWidget);
    });

    testWidgets(
      'dado un doble toque en «+ Agregar cliente», cuando abre el alta, se abre una sola',
      (tester) async {
        await montarClientes(tester, repo: _conDosClientes());

        await tester.tap(find.text(_agregar));
        await tester.tap(find.text(_agregar), warnIfMissed: false);
        await asentar(tester);

        expect(find.text('Nueva persona'), findsOneWidget);
        await tester.tap(find.byTooltip('Cerrar'));
        await asentar(tester);
        expect(find.text('Nueva persona'), findsNothing);
        expect(find.text('CLIENTES · 2'), findsOneWidget);
      },
    );

    testWidgets('dado un alta que falla, cuando reintenta y sale bien, la lista tiene a la persona '
        'una sola vez', (tester) async {
      final repo = PersonaRepositorioFalso(resultados: [const FailureInesperado(causa: 'x')]);
      await montarClientes(tester, repo: repo);

      await tester.tap(find.text(_agregar));
      await asentar(tester);
      await tester.enterText(
        find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Obligatorio'),
        'Jorge',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar persona'));
      await asentar(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      await asentar(tester);

      expect(find.text('CLIENTES · 1'), findsOneWidget);
      expect(find.text('Guardamos a Jorge en este teléfono.'), findsOneWidget);
    });
  });

  group('datos límite y texto grande', () {
    testWidgets('dado 200 clientes, cuando se baja la lista, se llega a la nota de privacidad sin '
        'errores', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..sembrar([
          for (var i = 0; i < 200; i++)
            clienteDePersonas('p$i', 'Cliente', apellido: 'Número $i', minutos: i),
        ]);
      await montarClientes(tester, repo: repo);

      expect(find.text('CLIENTES · 200'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Los datos de los clientes quedan solo en tu celular'),
        400,
        scrollable: find.byType(Scrollable).last,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('dado nombres larguísimos y el texto al 200 %, cuando se muestra la lista, no se '
        'desborda', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..sembrar([
          clienteDePersonas(
            'p1',
            'Maximiliano Nepomuceno de la Santísima Trinidad ' * 2,
            apellido: 'Fernández de Córdoba y Rodríguez de la Peña ' * 2,
            telefono: '+598 99 123 456',
          ),
          clienteDePersonas('p2', 'Ana', minutos: 1),
        ]);
      await montarClientes(tester, repo: repo, escala: 2, tamano: const Size(320, 640));

      expect(tester.takeException(), isNull);
      expect(find.text('CLIENTES · 2'), findsOneWidget);
      expect(find.text(_agregar), findsOneWidget);
      expect(tester.getSize(find.text(_agregar)).height, greaterThan(0));
    });

    testWidgets('dado «+ Agregar cliente», cuando se mide, el objetivo táctil es de al menos 48 de '
        'alto', (tester) async {
      await montarClientes(tester, repo: _conDosClientes());

      final boton = find.widgetWithText(TextButton, _agregar);
      expect(tester.getSize(boton).height, greaterThanOrEqualTo(48));
    });

    testWidgets('dado una fila, cuando se lee con el lector de pantalla, dice el nombre y el final '
        'del teléfono, no el teléfono entero', (tester) async {
      final handle = tester.ensureSemantics();
      await montarClientes(tester, repo: _conDosClientes());

      expect(find.bySemanticsLabel('Ana Martínez. Teléfono terminado en 412'), findsOneWidget);
      expect(find.bySemanticsLabel('Pedro Rodríguez. Sin teléfono'), findsOneWidget);
      handle.dispose();
    });
  });
}
