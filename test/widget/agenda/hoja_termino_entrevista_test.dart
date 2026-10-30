// R·06 «Finalizar: horas y ¿hubo venta?» y R·07 «Sin inicio registrado» (vista 39, HU-VIS-005, #450):
// las horas, el «¿Hubo venta?», el aviso del inicio inferido, las horas que no se inventan y los
// casos límite del guardado (doble toque, falla a mitad, letra grande).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_termino_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _entrada = DateTime(2026, 10, 23, 14, 23);
final _salida = DateTime(2026, 10, 23, 14, 41);

void main() {
  var ahora = DateTime(2026, 10, 23, 14, 41);
  final guardados = <({DateTime entrada, DateTime salida})>[];
  Future<Failure?> Function(DateTime, DateTime) alGuardar = (e, s) async => null;
  SalidaTerminoEntrevista? salidaDeLaHoja;
  var hojaCerrada = false;

  setUp(() {
    ahora = DateTime(2026, 10, 23, 14, 41);
    guardados.clear();
    salidaDeLaHoja = null;
    hojaCerrada = false;
    alGuardar = (e, s) async {
      guardados.add((entrada: e, salida: s));
      return null;
    };
  });

  /// Monta la hoja como en la app: un botón que la abre y recoge cómo se cerró.
  Future<void> montar(
    WidgetTester tester, {
    DateTime? entrada,
    DateTime? salida,
    bool inferida = false,
    String direccion = 'Grecia 3307',
    String persona = 'Pedro Gómez',
    double escala = 1,
    Size tamano = const Size(390, 844),
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  salidaDeLaHoja = await mostrarHojaTerminoEntrevista(
                    context,
                    direccion: direccion,
                    persona: persona,
                    entrada: entrada,
                    salida: salida,
                    entradaInferida: inferida,
                    reloj: () => ahora,
                    alGuardar: (e, s) => alGuardar(e, s),
                  );
                  hojaCerrada = true;
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  bool habilitado(WidgetTester tester, Key clave) =>
      tester.widget<ButtonStyleButton>(find.byKey(clave)).onPressed != null;

  Future<void> tocar(WidgetTester tester, Key clave) async {
    await tester.ensureVisible(find.byKey(clave));
    await tester.tap(find.byKey(clave));
    await tester.pumpAndSettle();
  }

  group('R·06 · Finalizar: horas y ¿hubo venta?', () {
    testWidgets('muestra el título, el lugar y la persona, las dos horas y la duración', (
      tester,
    ) async {
      await montar(tester, entrada: _entrada, salida: _salida);

      expect(find.text('Terminó la entrevista'), findsOneWidget);
      expect(find.text('Grecia 3307 · Pedro Gómez'), findsOneWidget);
      expect(find.text('Entrada'), findsOneWidget);
      expect(find.text('14:23  ✎'), findsOneWidget);
      expect(find.text('Salida'), findsOneWidget);
      expect(find.text('14:41  ✎'), findsOneWidget);
      expect(find.text('Duración'), findsOneWidget);
      expect(find.text('18 min'), findsOneWidget);
      expect(find.text('¿HUBO VENTA?'), findsOneWidget);
      expect(find.text('Sí, registrar la venta'), findsOneWidget);
      expect(find.text('No, guardar y volver al mapa'), findsOneWidget);
    });

    testWidgets('con las dos horas puestas no hay aviso de inicio ni de hora pendiente', (
      tester,
    ) async {
      await montar(tester, entrada: _entrada, salida: _salida);

      expect(find.byKey(ClavesEntrevista.avisoSinInicio), findsNothing);
      expect(find.byKey(ClavesEntrevista.avisoPedirHora), findsNothing);
      expect(find.byKey(ClavesEntrevista.avisoError), findsNothing);
    });

    testWidgets('«No, guardar y volver al mapa» guarda con las horas y cierra la hoja', (
      tester,
    ) async {
      await montar(tester, entrada: _entrada, salida: _salida);

      await tocar(tester, ClavesEntrevista.guardarYVolver);

      expect(guardados, hasLength(1));
      expect(guardados.single.entrada, _entrada);
      expect(guardados.single.salida, _salida);
      expect(salidaDeLaHoja, isA<EntrevistaGuardada>());
      expect(find.byKey(ClavesEntrevista.hojaTermino), findsNothing);
    });

    testWidgets('«Sí, registrar la venta» devuelve las horas y no guarda nada (R44)', (
      tester,
    ) async {
      await montar(tester, entrada: _entrada, salida: _salida);

      await tocar(tester, ClavesEntrevista.registrarVenta);

      expect(guardados, isEmpty);
      final salida = salidaDeLaHoja! as QuiereRegistrarLaVenta;
      expect(salida.entrada, _entrada);
      expect(salida.salida, _salida);
    });

    testWidgets(
      'se corrige la salida de a 5 minutos con la hoja de la jornada y la duración la sigue',
      (tester) async {
        await montar(tester, entrada: _entrada, salida: _salida);

        await tocar(tester, ClavesEntrevista.filaSalida);
        expect(find.text('¿A qué hora terminó la entrevista?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('hoja_hora_menos')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('hoja_hora_usar')));
        await tester.pumpAndSettle();

        expect(find.text('14:36  ✎'), findsOneWidget);
        expect(find.text('13 min'), findsOneWidget);

        await tocar(tester, ClavesEntrevista.guardarYVolver);
        expect(guardados.single.salida, DateTime(2026, 10, 23, 14, 36));
      },
    );

    testWidgets('la salida no se puede llevar antes de la entrada', (tester) async {
      await montar(tester, entrada: _entrada, salida: _salida);

      await tocar(tester, ClavesEntrevista.filaSalida);
      for (var i = 0; i < 6; i++) {
        final menos = find.byKey(const Key('hoja_hora_menos'));
        final boton = tester.widget<OutlinedButton>(
          find.descendant(of: menos, matching: find.byType(OutlinedButton)),
        );
        if (boton.onPressed == null) break;
        await tester.tap(menos);
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('hoja_hora_usar')));
      await tester.pumpAndSettle();

      // 14:41 → 14:36 → 14:31 → 14:26 → 14:23 (tope: la entrada).
      expect(find.text('14:23  ✎'), findsNWidgets(2));
      expect(find.text('Duración'), findsOneWidget);
      expect(find.text('menos de 1 min'), findsOneWidget);
    });

    testWidgets('la entrada se corrige hasta la salida y no más allá', (tester) async {
      await montar(tester, entrada: _entrada, salida: _salida);

      await tocar(tester, ClavesEntrevista.filaEntrada);
      expect(find.text('¿A qué hora empezó la entrevista?'), findsOneWidget);
      // Más tarde que la entrada (+5): el botón «+5» baja los minutos hacia atrás.
      await tester.tap(find.byKey(const Key('hoja_hora_mas')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('hoja_hora_usar')));
      await tester.pumpAndSettle();

      expect(find.text('14:28  ✎'), findsOneWidget);
      expect(find.text('13 min'), findsOneWidget);
    });

    testWidgets('cancelar la hoja de la hora deja las horas como estaban', (tester) async {
      await montar(tester, entrada: _entrada, salida: _salida);

      await tocar(tester, ClavesEntrevista.filaSalida);
      await tester.tap(find.byKey(const Key('hoja_hora_menos')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('hoja_hora_cancelar')));
      await tester.pumpAndSettle();

      expect(find.text('14:41  ✎'), findsOneWidget);
      expect(find.byKey(ClavesEntrevista.hojaTermino), findsOneWidget);
    });

    testWidgets('la hora cruza la medianoche sin romper la duración', (tester) async {
      ahora = DateTime(2026, 10, 24, 0, 10);
      await montar(
        tester,
        entrada: DateTime(2026, 10, 23, 23, 50),
        salida: DateTime(2026, 10, 24, 0, 10),
      );

      expect(find.text('20 min'), findsOneWidget);
    });
  });

  group(
    'una entrevista que quedó abierta de días atrás (el día se ve si la hora no es de hoy)',
    () {
      final antes = DateTime(2026, 10, 21, 14, 23);

      testWidgets('la entrada de otro día lleva el día; la salida de hoy, no', (tester) async {
        await montar(tester, entrada: antes, salida: _salida);

        expect(find.text('Miércoles 21 · 14:23  ✎'), findsOneWidget);
        expect(find.text('14:41  ✎'), findsOneWidget);
      });

      testWidgets('las horas de hoy se ven solo como HH:mm', (tester) async {
        await montar(tester, entrada: _entrada, salida: _salida);

        expect(find.textContaining('Viernes'), findsNothing);
        expect(find.text('14:23  ✎'), findsOneWidget);
      });

      testWidgets('la hoja de la hora dice el día de la hora que se mira', (tester) async {
        await montar(tester, entrada: antes, salida: null);

        await tocar(tester, ClavesEntrevista.filaSalida);

        // El tope de la salida es la entrada + 12 h: ya es el jueves.
        expect(find.byKey(const Key('hoja_hora_nota')), findsOneWidget);
        expect(find.text('Jueves 22'), findsOneWidget);
      });

      testWidgets('la hoja de la hora de hoy no agrega ninguna aclaración', (tester) async {
        await montar(tester, entrada: _entrada, salida: _salida);

        await tocar(tester, ClavesEntrevista.filaSalida);

        expect(find.byKey(const Key('hoja_hora_nota')), findsNothing);
      });

      testWidgets('el lector de pantalla también dice el día', (tester) async {
        final semantica = tester.ensureSemantics();
        await montar(tester, entrada: antes, salida: null);

        expect(find.bySemanticsLabel('Entrada, Miércoles 21 · 14:23'), findsOneWidget);
        semantica.dispose();
      });
    },
  );

  group('R·07 · Sin inicio registrado', () {
    testWidgets('avisa que tomó la hora de la visita anterior y la deja para revisar', (
      tester,
    ) async {
      await montar(
        tester,
        entrada: DateTime(2026, 10, 23, 14, 10),
        salida: _salida,
        inferida: true,
      );

      expect(
        find.text(
          'No registramos el inicio. Tomamos la hora de tu visita anterior (14:10). Revisala.',
        ),
        findsOneWidget,
      );
      expect(find.text('14:10  ✎'), findsOneWidget);
      expect(find.text('14:41  ✎'), findsOneWidget);
      expect(find.text('31 min'), findsOneWidget);
      expect(habilitado(tester, ClavesEntrevista.guardarYVolver), isTrue);
    });

    testWidgets('la hora tomada se puede corregir y el aviso sigue diciendo de dónde salió', (
      tester,
    ) async {
      await montar(
        tester,
        entrada: DateTime(2026, 10, 23, 14, 10),
        salida: _salida,
        inferida: true,
      );

      await tocar(tester, ClavesEntrevista.filaEntrada);
      await tester.tap(find.byKey(const Key('hoja_hora_mas')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('hoja_hora_usar')));
      await tester.pumpAndSettle();

      expect(find.text('14:15  ✎'), findsOneWidget);
      await tocar(tester, ClavesEntrevista.guardarYVolver);
      expect(guardados.single.entrada, DateTime(2026, 10, 23, 14, 15));
    });

    testWidgets(
      'sin ninguna visita anterior no se inventa la entrada: se pide y no se sigue sin ella',
      (tester) async {
        await montar(tester, entrada: null, salida: _salida, inferida: false);

        expect(find.byKey(ClavesEntrevista.avisoSinInicio), findsNothing);
        expect(find.text(TextosEntrevista.pedirEntrada), findsOneWidget);
        expect(find.text('Elegir  ✎'), findsOneWidget);
        expect(find.byKey(ClavesEntrevista.duracion), findsNothing);
        expect(habilitado(tester, ClavesEntrevista.guardarYVolver), isFalse);
        expect(habilitado(tester, ClavesEntrevista.registrarVenta), isFalse);

        await tocar(tester, ClavesEntrevista.filaEntrada);
        await tester.tap(find.byKey(const Key('hoja_hora_usar')));
        await tester.pumpAndSettle();

        expect(find.text(TextosEntrevista.pedirEntrada), findsNothing);
        expect(habilitado(tester, ClavesEntrevista.guardarYVolver), isTrue);
      },
    );
  });

  group(
    'la salida no se inventa (app cerrada o jornada que termina con la entrevista abierta)',
    () {
      testWidgets('sin salida pide la hora, apaga los dos botones y dice por qué', (tester) async {
        await montar(tester, entrada: _entrada, salida: null);

        expect(find.text(TextosEntrevista.pedirSalida), findsOneWidget);
        expect(find.text('Elegir  ✎'), findsOneWidget);
        expect(find.byKey(ClavesEntrevista.duracion), findsNothing);
        expect(habilitado(tester, ClavesEntrevista.guardarYVolver), isFalse);
        expect(habilitado(tester, ClavesEntrevista.registrarVenta), isFalse);
      });

      testWidgets('al elegir la hora se habilitan y guarda con esa salida', (tester) async {
        await montar(tester, entrada: _entrada, salida: null);

        await tocar(tester, ClavesEntrevista.filaSalida);
        await tester.tap(find.byKey(const Key('hoja_hora_menos')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('hoja_hora_usar')));
        await tester.pumpAndSettle();

        expect(find.text(TextosEntrevista.pedirSalida), findsNothing);
        expect(habilitado(tester, ClavesEntrevista.guardarYVolver), isTrue);
        await tocar(tester, ClavesEntrevista.guardarYVolver);
        expect(guardados.single.salida, DateTime(2026, 10, 23, 14, 36));
      });

      testWidgets('sin las dos horas lo dice en un solo aviso', (tester) async {
        await montar(tester, entrada: null, salida: null);

        expect(find.text(TextosEntrevista.pedirAmbas), findsOneWidget);
        expect(habilitado(tester, ClavesEntrevista.guardarYVolver), isFalse);
      });

      testWidgets('tocar un botón apagado no guarda ni cierra', (tester) async {
        await montar(tester, entrada: _entrada, salida: null);

        await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarYVolver));
        await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver), warnIfMissed: false);
        await tester.pump();

        expect(guardados, isEmpty);
        expect(hojaCerrada, isFalse);
      });
    },
  );

  group('casos límite del guardado', () {
    testWidgets('mientras guarda dice «Guardando…» y ninguno de los dos botones responde', (
      tester,
    ) async {
      final espera = Completer<Failure?>();
      alGuardar = (e, s) => espera.future;
      await montar(tester, entrada: _entrada, salida: _salida);

      await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarYVolver));
      await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
      await tester.pump();

      expect(find.text('Guardando…'), findsOneWidget);
      expect(habilitado(tester, ClavesEntrevista.guardarYVolver), isFalse);
      expect(habilitado(tester, ClavesEntrevista.registrarVenta), isFalse);
      expect(hojaCerrada, isFalse);

      espera.complete(null);
      await tester.pumpAndSettle();
      expect(salidaDeLaHoja, isA<EntrevistaGuardada>());
    });

    testWidgets('un doble toque guarda una sola vez', (tester) async {
      final espera = Completer<Failure?>();
      var llamadas = 0;
      alGuardar = (e, s) {
        llamadas++;
        return espera.future;
      };
      await montar(tester, entrada: _entrada, salida: _salida);

      await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarYVolver));
      await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
      await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver), warnIfMissed: false);
      await tester.pump();

      expect(llamadas, 1);
      espera.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets(
      'si falla a mitad, el aviso dice qué hacer, los botones vuelven y se puede reintentar',
      (tester) async {
        var intento = 0;
        alGuardar = (e, s) async {
          intento++;
          guardados.add((entrada: e, salida: s));
          return intento == 1 ? const FailureInesperado() : null;
        };
        await montar(tester, entrada: _entrada, salida: _salida);

        await tocar(tester, ClavesEntrevista.guardarYVolver);

        expect(find.text(TextosEntrevista.noPudimosGuardar), findsOneWidget);
        expect(find.text('Guardando…'), findsNothing);
        expect(habilitado(tester, ClavesEntrevista.guardarYVolver), isTrue);
        expect(habilitado(tester, ClavesEntrevista.registrarVenta), isTrue);
        expect(hojaCerrada, isFalse);

        await tocar(tester, ClavesEntrevista.guardarYVolver);
        expect(guardados, hasLength(2));
        expect(salidaDeLaHoja, isA<EntrevistaGuardada>());
      },
    );

    testWidgets('si lo que guarda lanza una excepción tampoco queda «Guardando…» para siempre', (
      tester,
    ) async {
      alGuardar = (e, s) async => throw StateError('se cayó');
      await montar(tester, entrada: _entrada, salida: _salida);

      await tocar(tester, ClavesEntrevista.guardarYVolver);

      expect(find.text(TextosEntrevista.noPudimosGuardar), findsOneWidget);
      expect(habilitado(tester, ClavesEntrevista.guardarYVolver), isTrue);
    });

    testWidgets('si las horas no valen muestra el mensaje de la validación', (tester) async {
      alGuardar = (e, s) async => const FailureValidacion(
        campos: {
          'salida': 'La salida no puede ser antes de la entrada. Corregí una de las dos horas.',
        },
        mensaje: 'La salida no puede ser antes de la entrada. Corregí una de las dos horas.',
      );
      await montar(tester, entrada: _entrada, salida: _salida);

      await tocar(tester, ClavesEntrevista.guardarYVolver);

      expect(
        find.text('La salida no puede ser antes de la entrada. Corregí una de las dos horas.'),
        findsOneWidget,
      );
    });

    testWidgets('corregir una hora limpia el aviso de error', (tester) async {
      alGuardar = (e, s) async => const FailureInesperado();
      await montar(tester, entrada: _entrada, salida: _salida);
      await tocar(tester, ClavesEntrevista.guardarYVolver);
      expect(find.byKey(ClavesEntrevista.avisoError), findsOneWidget);

      await tocar(tester, ClavesEntrevista.filaSalida);
      await tester.tap(find.byKey(const Key('hoja_hora_usar')));
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesEntrevista.avisoError), findsNothing);
    });

    testWidgets('mientras guarda las horas no se pueden tocar', (tester) async {
      final espera = Completer<Failure?>();
      alGuardar = (e, s) => espera.future;
      await montar(tester, entrada: _entrada, salida: _salida);
      await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarYVolver));
      await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
      await tester.pump();

      await tester.tap(find.byKey(ClavesEntrevista.filaSalida), warnIfMissed: false);
      await tester.pump();

      expect(find.byKey(const Key('hoja_hora_ajuste')), findsNothing);
      espera.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets('dos toques seguidos en una hora abren una sola hoja de hora', (tester) async {
      await montar(tester, entrada: _entrada, salida: _salida);

      await tester.ensureVisible(find.byKey(ClavesEntrevista.filaSalida));
      await tester.tap(find.byKey(ClavesEntrevista.filaSalida));
      await tester.tap(find.byKey(ClavesEntrevista.filaSalida), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hoja_hora_ajuste')), findsOneWidget);
    });
  });

  group('datos límite', () {
    testWidgets('a 200 % de letra en 320×568 todo se alcanza desplazando y nada desborda', (
      tester,
    ) async {
      await montar(
        tester,
        entrada: DateTime(2026, 10, 23, 14, 10),
        salida: _salida,
        inferida: true,
        escala: 2,
        tamano: const Size(320, 568),
      );
      expect(tester.takeException(), isNull);

      await tocar(tester, ClavesEntrevista.guardarYVolver);

      expect(guardados, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('con la persona y el lugar muy largos no desborda', (tester) async {
      await montar(
        tester,
        entrada: _entrada,
        salida: _salida,
        direccion: 'Avenida General José Gervasio Artigas esquina Bulevar España 1234',
        persona: 'María de los Ángeles Fernández de la Rosa Gómez',
        tamano: const Size(320, 568),
        escala: 2,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('una entrevista de horas se lee «2 h 5 min»', (tester) async {
      ahora = DateTime(2026, 10, 23, 16, 30);
      await montar(
        tester,
        entrada: DateTime(2026, 10, 23, 14, 25),
        salida: DateTime(2026, 10, 23, 16, 30),
      );

      expect(find.text('2 h 5 min'), findsOneWidget);
    });

    testWidgets('las filas de hora miden al menos 48 dp y se anuncian como botones', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montar(tester, entrada: _entrada, salida: _salida);

      expect(
        tester.getSize(find.byKey(ClavesEntrevista.filaEntrada)).height,
        greaterThanOrEqualTo(48),
      );
      expect(find.bySemanticsLabel('Entrada, 14:23'), findsOneWidget);
      expect(find.bySemanticsLabel('Salida, 14:41'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('una hora sin elegir se anuncia «sin elegir», no «Elegir»', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar(tester, entrada: _entrada, salida: null);

      expect(find.bySemanticsLabel('Salida, sin elegir'), findsOneWidget);
      semantica.dispose();
    });
  });
}
