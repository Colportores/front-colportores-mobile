// El recorrido completo de la entrevista (vista 39, R·05 → R·06 / R·07; #450): el aviso fijo que lleva
// de vuelta, salir y reentrar, la app que se cerró con la entrevista abierta, la venta y el guardado.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/services/destino_de_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/aviso_entrevista_en_curso.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/flujo_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_termino_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrevista_falsos.dart';

void main() {
  late MontajeEntrevista montaje;
  SalidaTerminoEntrevista? ultimaSalida;
  late ProviderContainer contenedor;

  setUp(() {
    montaje = MontajeEntrevista();
    ultimaSalida = null;
  });

  Future<void> montar(
    WidgetTester tester, {
    bool conAviso = true,
    double escala = 1,
    Size tamano = const Size(390, 844),
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: montaje.overrides,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                contenedor = ProviderScope.containerOf(context);
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      if (conAviso) const AvisoEntrevistaEnCurso(colportorId: 'col-1'),
                      ElevatedButton(
                        key: const Key('abrir'),
                        onPressed: () async => ultimaSalida = await FlujoEntrevista.abrir(
                          context,
                          ref,
                          colportorId: 'col-1',
                        ),
                        child: const Text('abrir'),
                      ),
                      ElevatedButton(
                        key: const Key('terminar'),
                        onPressed: () async => ultimaSalida = await FlujoEntrevista.terminar(
                          context,
                          ref,
                          colportorId: 'col-1',
                          pedirSalida: true,
                        ),
                        child: const Text('terminar'),
                      ),
                      ElevatedButton(
                        key: const Key('sin-inicio'),
                        onPressed: () async =>
                            ultimaSalida = await FlujoEntrevista.terminarSinInicio(
                              context,
                              ref,
                              colportorId: 'col-1',
                              espacioId: 'esp-1',
                              espacioPersonaId: 'ep-1',
                              direccion: 'Grecia 3307',
                              persona: 'Pedro Gómez',
                            ),
                        child: const Text('sin inicio'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tocarKey(WidgetTester tester, Key clave) async {
    await tester.ensureVisible(find.byKey(clave));
    await tester.tap(find.byKey(clave));
    await tester.pumpAndSettle();
  }

  /// La entrevista ya estaba guardada cuando la app arrancó (la app se cerró desde que empezó).
  Future<void> empezada(WidgetTester tester) async {
    await montaje.almacen.guardar(entrevistaDePrueba());
    await montar(tester);
  }

  /// La entrevista empezó en esta sesión, a las 14:23, y ahora son las 14:41.
  Future<void> empezadaEnEstaSesion(WidgetTester tester) async {
    montaje.reloj = () => inicioEntrevista;
    await montar(tester);
    await contenedor
        .read(entrevistaEnCursoProvider('col-1').notifier)
        .empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
    montaje.reloj = () => ahoraEntrevista;
    await tester.pumpAndSettle();
  }

  group('el aviso fijo sobre el mapa', () {
    testWidgets('sin entrevista en curso no dibuja nada', (tester) async {
      await montar(tester);

      expect(find.byKey(ClavesEntrevista.avisoFijo), findsNothing);
    });

    testWidgets('con una en curso dice dónde y cuánto va', (tester) async {
      await empezada(tester);

      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
      expect(find.text('Entrevista en curso · Grecia 3307 · 18 min'), findsOneWidget);
    });

    testWidgets('aparece cuando la entrevista empieza y desaparece cuando termina', (tester) async {
      await montar(tester);
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsNothing);

      await contenedor
          .read(entrevistaEnCursoProvider('col-1').notifier)
          .empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
      await tester.pumpAndSettle();
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);

      montaje.reloj = () => ahoraEntrevista.add(const Duration(minutes: 5));
      await contenedor
          .read(entrevistaEnCursoProvider('col-1').notifier)
          .finalizar(entrada: inicioEntrevista, salida: ahoraEntrevista);
      await tester.pumpAndSettle();
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsNothing);
    });

    testWidgets('el tiempo corre solo cada medio minuto', (tester) async {
      await empezada(tester);

      montaje.reloj = () => ahoraEntrevista.add(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 30));

      expect(find.text('Entrevista en curso · Grecia 3307 · 19 min'), findsOneWidget);
    });

    testWidgets('si no se sabe la dirección, dice solo «Entrevista en curso · 18 min»', (
      tester,
    ) async {
      montaje.rotulo = (direccion: '', persona: '');
      await empezada(tester);

      expect(find.text('Entrevista en curso · 18 min'), findsOneWidget);
    });

    testWidgets('un toque lleva de vuelta a la hoja de la entrevista', (tester) async {
      await empezada(tester);

      await tocarKey(tester, ClavesEntrevista.avisoFijo);

      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
      expect(find.text('Desde las 14:23'), findsOneWidget);
    });

    testWidgets('dos toques seguidos abren una sola hoja', (tester) async {
      await empezada(tester);

      await tester.tap(find.byKey(ClavesEntrevista.avisoFijo));
      await tester.tap(find.byKey(ClavesEntrevista.avisoFijo), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
    });

    testWidgets('se anuncia como un botón con el texto y a dónde lleva', (tester) async {
      final semantica = tester.ensureSemantics();
      await empezada(tester);

      expect(
        find.bySemanticsLabel('Entrevista en curso · Grecia 3307 · 18 min. Volver a la entrevista'),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(ClavesEntrevista.avisoFijo)).height,
        greaterThanOrEqualTo(48),
      );
      semantica.dispose();
    });

    testWidgets('el aviso entero es un botón para el lector y el texto contrasta al menos 4,5:1', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await empezada(tester);

      final datos = tester.getSemantics(find.byKey(ClavesEntrevista.avisoFijo));
      expect(datos.flagsCollection.isButton, isTrue);
      expect(datos.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      final texto = find.text('Entrevista en curso · Grecia 3307 · 18 min');
      final contexto = tester.element(texto);
      final color = Theme.of(contexto).textTheme.bodyMedium!.color!;
      final claro = Colors.white.computeLuminance();
      final oscuro = color.computeLuminance();
      expect((claro + 0.05) / (oscuro + 0.05), greaterThanOrEqualTo(4.5));
      semantica.dispose();
    });

    testWidgets('a 200 % de letra en 320×568 no desborda', (tester) async {
      montaje.rotulo = (
        direccion: 'Avenida General José Gervasio Artigas esquina Bulevar España 1234',
        persona: '',
      );
      await montaje.almacen.guardar(entrevistaDePrueba());
      await montar(tester, escala: 2, tamano: const Size(320, 568));

      expect(tester.takeException(), isNull);
    });
  });

  group('R·05 → R·06', () {
    testWidgets(
      'finalizar guarda la visita como «Entrevista dada» con la salida de ahora y avisa',
      (tester) async {
        await empezadaEnEstaSesion(tester);

        await tocarKey(tester, const Key('abrir'));
        expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
        await tocarKey(tester, ClavesEntrevista.finalizar);

        expect(find.text('Terminó la entrevista'), findsOneWidget);
        expect(find.text('14:23  ✎'), findsOneWidget);
        expect(find.text('14:41  ✎'), findsOneWidget);
        expect(find.text('18 min'), findsWidgets);

        await tocarKey(tester, ClavesEntrevista.guardarYVolver);

        expect(ultimaSalida, isA<EntrevistaGuardada>());
        final visita = montaje.agenda.recibidas.single.visita;
        expect(visita.tipoResultado, TipoResultadoVisita.entrevista);
        expect(visita.espacioPersonaId, 'ep-1');
        expect(montaje.almacen.guardadas, isEmpty);
        expect(find.text('Guardado. Grecia 3307 quedó como «Entrevista dada».'), findsOneWidget);
        expect(find.byKey(ClavesEntrevista.avisoFijo), findsNothing);
      },
    );

    testWidgets('la nota escrita en R·05 viaja con la visita', (tester) async {
      await empezadaEnEstaSesion(tester);

      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.botonNota);
      await tester.enterText(find.byKey(ClavesEntrevista.campoNota), 'volver con la esposa');
      await tocarKey(tester, ClavesEntrevista.finalizar);
      await tocarKey(tester, ClavesEntrevista.guardarYVolver);

      expect(montaje.agenda.recibidas.single.nota!.texto, 'volver con la esposa');
    });

    testWidgets('«Sí, registrar la venta» no guarda nada y la entrevista sigue en curso (R44)', (
      tester,
    ) async {
      await empezadaEnEstaSesion(tester);

      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.finalizar);
      await tocarKey(tester, ClavesEntrevista.registrarVenta);

      expect(ultimaSalida, isA<QuiereRegistrarLaVenta>());
      expect(montaje.agenda.recibidas, isEmpty);
      expect(montaje.almacen.guardadas, hasLength(1));
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
    });

    testWidgets('si no se puede guardar, la entrevista no se pierde y se puede reintentar', (
      tester,
    ) async {
      await empezadaEnEstaSesion(tester);
      montaje.agenda.falla = const FailureInesperado();

      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.finalizar);
      await tocarKey(tester, ClavesEntrevista.guardarYVolver);

      expect(find.text(TextosEntrevista.noPudimosGuardar), findsOneWidget);
      expect(montaje.almacen.guardadas, hasLength(1));

      montaje.agenda.falla = null;
      await tocarKey(tester, ClavesEntrevista.guardarYVolver);
      expect(ultimaSalida, isA<EntrevistaGuardada>());
      expect(montaje.almacen.guardadas, isEmpty);
    });
  });

  group('salir de la hoja y volver', () {
    testWidgets('cerrar la hoja sin finalizar deja la entrevista en curso con la misma hora', (
      tester,
    ) async {
      await empezada(tester);

      await tocarKey(tester, const Key('abrir'));
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsNothing);

      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
      await tocarKey(tester, ClavesEntrevista.avisoFijo);
      expect(find.text('Desde las 14:23'), findsOneWidget);
      expect(montaje.almacen.guardadas.values.single.inicio, inicioEntrevista.toUtc());
    });

    testWidgets('la nota escrita sobrevive a salir de la hoja y reentrar', (tester) async {
      await empezada(tester);

      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.botonNota);
      await tester.enterText(find.byKey(ClavesEntrevista.campoNota), 'tocar timbre');
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      await tocarKey(tester, ClavesEntrevista.avisoFijo);

      expect(find.text('tocar timbre'), findsOneWidget);
    });

    testWidgets('cerrar R·06 sin elegir deja la entrevista en curso', (tester) async {
      await empezada(tester);

      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.finalizar);
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      expect(ultimaSalida, isNull);
      expect(montaje.almacen.guardadas, hasLength(1));
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
    });
  });

  group('la app se cerró con la entrevista abierta', () {
    testWidgets(
      'al volver sigue en curso y, al finalizar, la salida se pide en vez de inventarla',
      (tester) async {
        await empezada(tester);

        await tocarKey(tester, const Key('abrir'));
        await tocarKey(tester, ClavesEntrevista.finalizar);

        expect(find.text(TextosEntrevista.pedirSalida), findsOneWidget);
        expect(find.text('Elegir  ✎'), findsOneWidget);
        expect(
          tester.widget<ButtonStyleButton>(find.byKey(ClavesEntrevista.guardarYVolver)).onPressed,
          isNull,
        );
        expect(montaje.agenda.recibidas, isEmpty);
      },
    );

    testWidgets('elegida la salida, se guarda con esa hora y la hora de inicio original', (
      tester,
    ) async {
      await empezada(tester);

      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.finalizar);
      await tocarKey(tester, ClavesEntrevista.filaSalida);
      await tester.tap(find.byKey(const Key('hoja_hora_menos')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('hoja_hora_usar')));
      await tester.pumpAndSettle();

      expect(find.text('14:23  ✎'), findsOneWidget);
      expect(find.text('14:36  ✎'), findsOneWidget);
      await tocarKey(tester, ClavesEntrevista.guardarYVolver);
      expect(ultimaSalida, isA<EntrevistaGuardada>());
    });

    testWidgets('una entrevista empezada en esta sesión usa la hora de ahora, sin pedirla', (
      tester,
    ) async {
      await montar(tester);
      await contenedor
          .read(entrevistaEnCursoProvider('col-1').notifier)
          .empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
      montaje.reloj = () => ahoraEntrevista;
      await tester.pumpAndSettle();

      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.finalizar);

      expect(find.text(TextosEntrevista.pedirSalida), findsNothing);
    });
  });

  group('terminar por pedido de la jornada', () {
    testWidgets('pide la salida aunque la entrevista sea de esta sesión', (tester) async {
      await empezada(tester);

      await tocarKey(tester, const Key('terminar'));

      expect(find.text('Terminó la entrevista'), findsOneWidget);
      expect(find.text(TextosEntrevista.pedirSalida), findsOneWidget);
    });

    testWidgets('sin entrevista en curso no abre nada y devuelve null', (tester) async {
      await montar(tester);

      await tocarKey(tester, const Key('terminar'));

      expect(find.text('Terminó la entrevista'), findsNothing);
      expect(ultimaSalida, isNull);
    });
  });

  group('«Sin salida» y la nota cifrada (25/10)', () {
    testWidgets('cerró la app con una nota escrita: al volver la encuentra en R·05', (
      tester,
    ) async {
      montaje.borrador.textos['not-1'] = 'perro suelto, tocar timbre';
      await empezada(tester);

      await tocarKey(tester, const Key('abrir'));

      expect(find.text('perro suelto, tocar timbre'), findsOneWidget);
    });

    testWidgets('lo que escribe en R·05 queda guardado en la base mientras sigue en curso', (
      tester,
    ) async {
      await empezada(tester);

      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.botonNota);
      await tester.enterText(find.byKey(ClavesEntrevista.campoNota), 'tocar timbre');
      await tester.pumpAndSettle();

      expect(montaje.borrador.textos['not-1'], 'tocar timbre');
    });

    testWidgets('la persona ya no está: se guarda igual, sin persona, y avisa como siempre', (
      tester,
    ) async {
      montaje.destino.destino = const DestinoDeEntrevista(espacioId: 'esp-1');
      await empezada(tester);

      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.finalizar);
      await tocarKey(tester, ClavesEntrevista.filaSalida);
      await tester.tap(find.byKey(const Key('hoja_hora_menos')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('hoja_hora_usar')));
      await tester.pumpAndSettle();
      await tocarKey(tester, ClavesEntrevista.guardarYVolver);

      expect(ultimaSalida, isA<EntrevistaGuardada>());
      expect(montaje.agenda.recibidas.single.visita.espacioPersonaId, isNull);
      expect(montaje.almacen.guardadas, isEmpty);
      expect(find.text('Guardado. Grecia 3307 quedó como «Entrevista dada».'), findsOneWidget);
    });

    testWidgets('la casa ya no está: la hoja se cierra con el aviso, la entrevista se suelta y el '
        'cierre de la jornada puede seguir', (tester) async {
      montaje.destino.sinDestino = true;
      await empezada(tester);

      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.finalizar);
      await tocarKey(tester, ClavesEntrevista.filaSalida);
      await tester.tap(find.byKey(const Key('hoja_hora_menos')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('hoja_hora_usar')));
      await tester.pumpAndSettle();
      await tocarKey(tester, ClavesEntrevista.guardarYVolver);

      expect(ultimaSalida, isA<EntrevistaGuardada>());
      expect(find.text(TextosEntrevista.sinLugar), findsOneWidget);
      expect(find.text('Guardado. Grecia 3307 quedó como «Entrevista dada».'), findsNothing);
      expect(montaje.agenda.recibidas, isEmpty);
      expect(montaje.almacen.guardadas, isEmpty);
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsNothing);
    });
  });

  group('R·07 · sin inicio registrado', () {
    testWidgets('toma la hora de la visita anterior, lo avisa y guarda con ella', (tester) async {
      montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 14, 10);
      await montar(tester, conAviso: false);

      await tocarKey(tester, const Key('sin-inicio'));

      expect(
        find.text(
          'No registramos el inicio. Tomamos la hora de tu visita anterior (14:10). Revisala.',
        ),
        findsOneWidget,
      );
      await tocarKey(tester, ClavesEntrevista.guardarYVolver);

      expect(ultimaSalida, isA<EntrevistaGuardada>());
      final visita = montaje.agenda.recibidas.single.visita;
      expect(visita.tipoResultado, TipoResultadoVisita.entrevista);
      expect(visita.espacioPersonaId, 'ep-1');
    });

    testWidgets('sin ninguna visita anterior pide la entrada en vez de inventarla', (tester) async {
      await montar(tester, conAviso: false);

      await tocarKey(tester, const Key('sin-inicio'));

      expect(find.byKey(ClavesEntrevista.avisoSinInicio), findsNothing);
      expect(find.text(TextosEntrevista.pedirEntrada), findsOneWidget);
    });

    testWidgets('reintentar tras una falla no guarda la visita dos veces: mismos ids', (
      tester,
    ) async {
      montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 14, 10);
      montaje.agenda.falla = const FailureInesperado();
      await montar(tester, conAviso: false);

      await tocarKey(tester, const Key('sin-inicio'));
      await tocarKey(tester, ClavesEntrevista.guardarYVolver);
      montaje.agenda.falla = null;
      await tocarKey(tester, ClavesEntrevista.guardarYVolver);

      expect(montaje.agenda.recibidas, hasLength(1));
    });
  });
}
