// HU-VIS-005, vista 39: «Registrar visita: ¿qué pasó?» (C·06) y el aviso «Guardado» con «Deshacer»
// (R·01), #411. Cada estado del inventario del canvas y los casos límite de cada flujo: doble toque,
// falla a mitad de la acción, dos acciones seguidas, volver atrás y reentrar, datos límite y texto
// al 200 %. No hay estado «sin conexión»: todo es local.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/eleccion_de_cita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_de_la_entrevista.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_repositorio_falso.dart';
import '../../helpers/campo_falsos.dart';
import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart';
import 'registrar_visita_arnes.dart';

const _guardadoNoContesto = 'Guardado. Grecia 3307 quedó como «No contestó».';
const _guardadoRechazo = 'Guardado. Grecia 3307 quedó como «Rechazo».';
const _noPudimosGuardar = 'No pudimos guardar la visita. Probá de nuevo.';

final _pedro = clienteDePersonas('pedro', 'Pedro', apellido: 'Gómez');
final _ana = clienteDePersonas('ana', 'Ana', apellido: 'Gómez', minutos: 1);

Finder get _hoja => find.byKey(ClavesQuePaso.hoja);
Finder get _deshacer => find.text('Deshacer');
Finder get _snack => find.byType(SnackBar);

/// Deja correr el tiempo (los avisos viven 8 s) en pasos cortos.
Future<void> _correr(WidgetTester tester, Duration d) async {
  var hecho = Duration.zero;
  while (hecho < d) {
    await tester.pump(const Duration(milliseconds: 100));
    hecho += const Duration(milliseconds: 100);
  }
}

void main() {
  group('C·06 · ¿Qué pasó?: lo que se ve', () {
    testWidgets(
      'dado una casa sin destinos enganchados, cuando se abre, ofrece solo «No contestó» y '
      '«Rechazo», con el título, la dirección y «Cancelar»',
      (tester) async {
        await montarQuePaso(tester);

        expect(find.text('¿Qué pasó?'), findsOneWidget);
        expect(find.text('Grecia 3307'), findsOneWidget);
        expect(find.text('No contestó'), findsOneWidget);
        expect(find.text('Rechazo'), findsOneWidget);
        expect(find.text('Guarda y vuelve al mapa'), findsNWidgets(2));
        expect(find.text('Cancelar'), findsOneWidget);
        // Sin destino todavía: no se dibujan (HU-UBI-003).
        expect(find.text('Programar entrevista'), findsNothing);
        expect(find.text('Entrevista dada'), findsNothing);
        expect(find.text('Cobranza'), findsNothing);
        expect(find.byKey(ClavesQuePaso.falla), findsNothing);
      },
    );

    testWidgets('dado todos los destinos y alguien que debe, cuando se abre, ofrece las cinco '
        'opciones del canvas con su ayuda', (tester) async {
      await montarQuePaso(
        tester,
        personas: [_pedro],
        saldos: {'pedro': 120000},
        programar: true,
        entrevistaDada: true,
        cobrar: true,
      );

      expect(find.text('No contestó'), findsOneWidget);
      expect(find.text('Rechazo'), findsOneWidget);
      expect(find.text('Programar entrevista'), findsOneWidget);
      expect(find.text('Elegís día y franja'), findsOneWidget);
      expect(find.text('Entrevista dada'), findsOneWidget);
      expect(find.text('Empieza a contar el tiempo'), findsOneWidget);
      expect(find.text('Cobranza'), findsOneWidget);
      expect(find.text(r'Pedro Gómez debe $ 1.200'), findsOneWidget);
    });

    testWidgets('dado que nadie debe, cuando se abre, «Cobranza» no se ofrece aunque el cobro esté '
        'enganchado', (tester) async {
      await montarQuePaso(tester, personas: [_pedro], cobrar: true);

      expect(find.text('Cobranza'), findsNothing);
    });

    testWidgets('dado que no se puede leer lo que deben, cuando se abre, «Cobranza» no se ofrece y '
        'el resto sí (no se afirma lo que no se sabe)', (tester) async {
      await montarQuePaso(tester, personas: [_pedro], saldos: {'pedro': 0}, cobrar: true);

      expect(find.text('Cobranza'), findsNothing);
      expect(find.text('No contestó'), findsOneWidget);
    });

    testWidgets('dado varias personas que deben, cuando se abre, «Cobranza» nombra a la que más '
        'debe', (tester) async {
      await montarQuePaso(
        tester,
        personas: [_pedro, _ana],
        saldos: {'pedro': 50000, 'ana': 90000},
        cobrar: true,
      );

      expect(find.text(r'Ana Gómez debe $ 900'), findsOneWidget);
    });

    testWidgets('cada renglón mide 56 de alto o más y se anuncia como botón con su ayuda', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarQuePaso(tester);

      for (final o in [OpcionQuePaso.noContesto, OpcionQuePaso.rechazo]) {
        expect(tester.getSize(renglon(o)).height, greaterThanOrEqualTo(56));
      }
      expect(
        tester.getSemantics(find.bySemanticsLabel('No contestó. Guarda y vuelve al mapa')),
        isSemantics(
          label: 'No contestó. Guarda y vuelve al mapa',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      semantica.dispose();
    });
  });

  group('C·06 → R·01 · un toque guarda y vuelve al mapa', () {
    testWidgets(
      'dado «No contestó», cuando se toca, guarda la visita en la casa sin persona, cierra '
      'la hoja y avisa «Guardado» con «Deshacer»',
      (tester) async {
        final a = await montarQuePaso(tester);

        await elegir(tester, OpcionQuePaso.noContesto);

        final r = a.repo.recibidas.single;
        expect(r.visita.tipoResultado, TipoResultadoVisita.noContesto);
        expect(r.visita.espacioId, 'esp-1');
        expect(r.visita.espacioPersonaId, isNull);
        expect(r.visita.colportorId, 'col-1');
        expect(r.agendaId, isNull);
        expect(a.resultados, [true]);
        expect(_hoja, findsNothing);
        expect(find.text(_guardadoNoContesto), findsOneWidget);
        expect(_deshacer, findsOneWidget);
      },
    );

    testWidgets('dado «Rechazo», cuando se toca, guarda el rechazo y avisa que la casa quedó como '
        '«Rechazo»', (tester) async {
      final a = await montarQuePaso(tester);

      await elegir(tester, OpcionQuePaso.rechazo);

      expect(a.repo.recibidas.single.visita.tipoResultado, TipoResultadoVisita.rechazo);
      expect(find.text(_guardadoRechazo), findsOneWidget);
    });

    testWidgets(
      'dado una casa con una entrevista programada, cuando se toca «No contestó», la visita '
      'viene a cumplir esa agenda (queda «No cumplida»)',
      (tester) async {
        final repo = AgendaRepositorioFalso()
          ..programada = agendaDe('age-1')
          ..agendaNoCumplida = true
          ..agendaAfectadaId = 'age-1';
        final a = await montarQuePaso(tester, repo: repo);

        await elegir(tester, OpcionQuePaso.noContesto);

        expect(a.repo.recibidas.single.agendaId, 'age-1');
        expect(find.text(_guardadoNoContesto), findsOneWidget);
      },
    );

    testWidgets('dado que no se pudo leer la agenda de la casa, cuando se toca «No contestó», la '
        'visita se guarda igual, sin agenda', (tester) async {
      final repo = AgendaRepositorioFalso()..fallaLaLecturaDeLaAgenda = true;
      final a = await montarQuePaso(tester, repo: repo);

      await elegir(tester, OpcionQuePaso.noContesto);

      expect(a.repo.recibidas.single.agendaId, isNull);
      expect(a.resultados, [true]);
    });

    testWidgets('el aviso desaparece a los 8 segundos', (tester) async {
      await montarQuePaso(tester);
      await elegir(tester, OpcionQuePaso.noContesto);
      expect(_snack, findsOneWidget);

      await _correr(tester, const Duration(seconds: 7));
      expect(_snack, findsOneWidget);
      await _correr(tester, const Duration(seconds: 2));
      expect(_snack, findsNothing);
    });

    testWidgets('con un lector de pantalla el aviso no se cierra solo (WCAG 2.2.1)', (
      tester,
    ) async {
      await montarQuePaso(tester, lector: true);
      await elegir(tester, OpcionQuePaso.noContesto);

      await _correr(tester, const Duration(seconds: 20));

      expect(_snack, findsOneWidget);
      expect(_deshacer, findsOneWidget);
    });
  });

  group('R·01 · Deshacer', () {
    testWidgets('dado el aviso, cuando se toca «Deshacer», se da de baja esa visita con lo que '
        'tocó y se dice que se deshizo', (tester) async {
      final repo = AgendaRepositorioFalso()
        ..agendaCreadaId = 'age-nueva'
        ..agendaAfectadaId = 'age-vieja';
      final a = await montarQuePaso(tester, repo: repo);
      await elegir(tester, OpcionQuePaso.noContesto);

      await tester.tap(_deshacer);
      await asentar(tester);

      expect(a.repo.deshechas, [
        (visitaId: 'id-1', agendaCreadaId: 'age-nueva', agendaAfectadaId: 'age-vieja'),
      ]);
      expect(find.text('Se deshizo. Grecia 3307 vuelve a como estaba.'), findsOneWidget);
    });

    testWidgets('dado un doble toque en «Deshacer», cuando termina, se deshizo una sola vez', (
      tester,
    ) async {
      final repo = AgendaRepositorioFalso()..compuertaDeshacer = Completer<void>();
      final a = await montarQuePaso(tester, repo: repo);
      await elegir(tester, OpcionQuePaso.noContesto);

      await tester.tap(_deshacer);
      await tester.pump();
      await tester.tap(_deshacer, warnIfMissed: false);
      repo.compuertaDeshacer!.complete();
      await asentar(tester);

      expect(a.repo.deshechas, hasLength(1));
    });

    testWidgets('dado que «Deshacer» falla, cuando se toca, dice que la visita quedó guardada', (
      tester,
    ) async {
      final repo = AgendaRepositorioFalso()
        ..resultadosDeshacer.add(const FailureInesperado(causa: 'StateError'));
      await montarQuePaso(tester, repo: repo);
      await elegir(tester, OpcionQuePaso.noContesto);

      await tester.tap(_deshacer);
      await asentar(tester);

      expect(find.text('No pudimos deshacer. La visita quedó guardada.'), findsOneWidget);
      expect(repo.recibidas, hasLength(1));
    });

    testWidgets('dado dos resultados seguidos, cuando se guarda el segundo, su aviso reemplaza al '
        'primero y cada «Deshacer» es de su visita', (tester) async {
      final a = await montarQuePaso(tester);
      await elegir(tester, OpcionQuePaso.noContesto);
      expect(find.text(_guardadoNoContesto), findsOneWidget);

      await abrirQuePaso(tester);
      await elegir(tester, OpcionQuePaso.rechazo);
      await _correr(tester, const Duration(seconds: 1));

      expect(find.text(_guardadoRechazo), findsOneWidget);
      expect(find.text(_guardadoNoContesto), findsNothing);
      expect(a.repo.recibidas.map((r) => r.visita.id), ['id-1', 'id-3']);

      await tester.tap(_deshacer);
      await asentar(tester);

      expect(a.repo.deshechas.single.visitaId, 'id-3', reason: 'la del Rechazo, no la primera');
      expect(a.repo.recibidas, hasLength(2), reason: 'las dos quedaron guardadas');
    });

    testWidgets('dado un «Deshacer» en curso, cuando se guarda otra visita, su aviso no se pisa', (
      tester,
    ) async {
      final repo = AgendaRepositorioFalso()..compuertaDeshacer = Completer<void>();
      await montarQuePaso(tester, repo: repo);
      await elegir(tester, OpcionQuePaso.noContesto);
      await tester.tap(_deshacer);
      await tester.pump();

      await abrirQuePaso(tester);
      await elegir(tester, OpcionQuePaso.rechazo);
      repo.compuertaDeshacer!.complete();
      await _correr(tester, const Duration(seconds: 1));

      expect(find.text(_guardadoRechazo), findsOneWidget);
      expect(_deshacer, findsOneWidget);
    });
  });

  group('casos límite del guardado', () {
    testWidgets('dado un doble toque mientras guarda, cuando termina, hay una sola visita y la '
        'hoja muestra «Guardando…» con el resto apagado', (tester) async {
      final repo = AgendaRepositorioFalso()..compuerta = Completer<void>();
      final a = await montarQuePaso(tester, repo: repo);

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await tester.tap(renglon(OpcionQuePaso.noContesto), warnIfMissed: false);
      await tester.tap(renglon(OpcionQuePaso.rechazo), warnIfMissed: false);
      await tester.pump();

      expect(find.text('Guardando…'), findsOneWidget);
      expect(find.byKey(ClavesQuePaso.guardando), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byKey(ClavesQuePaso.cancelar)).onPressed,
        isNull,
        reason: 'mientras guarda no se cancela',
      );

      repo.compuerta!.complete();
      await asentar(tester);

      expect(a.repo.recibidas, hasLength(1));
      expect(a.repo.recibidas.single.visita.tipoResultado, TipoResultadoVisita.noContesto);
      expect(a.resultados, [true]);
    });

    testWidgets(
      'dado el atrás del sistema mientras guarda, cuando se aprieta, la hoja no se cierra '
      'ni se pierde el resultado',
      (tester) async {
        final repo = AgendaRepositorioFalso()..compuerta = Completer<void>();
        final a = await montarQuePaso(tester, repo: repo);
        await tester.tap(renglon(OpcionQuePaso.rechazo));
        await tester.pump();

        await tester.binding.handlePopRoute();
        await asentar(tester);
        expect(_hoja, findsOneWidget);

        repo.compuerta!.complete();
        await asentar(tester);

        expect(a.resultados, [true]);
        expect(find.text(_guardadoRechazo), findsOneWidget);
      },
    );

    testWidgets('dado una falla a mitad del guardado, cuando se muestra el aviso, los renglones '
        'vuelven a poder tocarse y el reintento no duplica la visita', (tester) async {
      final repo = AgendaRepositorioFalso()
        ..resultados.add(const FailureInesperado(causa: 'StateError'));
      final a = await montarQuePaso(tester, repo: repo);

      await elegir(tester, OpcionQuePaso.noContesto);

      expect(find.text(_noPudimosGuardar), findsOneWidget);
      expect(_hoja, findsOneWidget);
      expect(find.text('Guardando…'), findsNothing);
      expect(a.resultados, isEmpty, reason: 'la hoja sigue abierta');
      expect(find.text(_guardadoNoContesto), findsNothing);

      await elegir(tester, OpcionQuePaso.noContesto);

      expect(a.repo.recibidas.map((r) => r.visita.id), ['id-1', 'id-1'], reason: 'mismos ids');
      expect(find.text(_noPudimosGuardar), findsNothing);
      expect(a.resultados, [true]);
      expect(find.text(_guardadoNoContesto), findsOneWidget);
    });

    testWidgets('dado una falla y luego otra opción, cuando se elige, la visita nueva lleva otros '
        'ids (no hereda los de la opción que falló)', (tester) async {
      final repo = AgendaRepositorioFalso()
        ..resultados.add(const FailureInesperado(causa: 'StateError'));
      final a = await montarQuePaso(tester, repo: repo);
      await elegir(tester, OpcionQuePaso.noContesto);

      await elegir(tester, OpcionQuePaso.rechazo);

      expect(a.repo.recibidas.map((r) => r.visita.id), ['id-1', 'id-3']);
      expect(a.repo.recibidas.last.visita.tipoResultado, TipoResultadoVisita.rechazo);
    });

    testWidgets('dado que la casa ya no está en el teléfono, cuando se guarda, el aviso dice qué '
        'hacer', (tester) async {
      final repo = AgendaRepositorioFalso()
        ..resultados.add(const FailureValidacion(campos: {'espacio': 'no está'}));
      await montarQuePaso(tester, repo: repo);

      await elegir(tester, OpcionQuePaso.noContesto);

      expect(
        find.text('Esta casa ya no está en tu teléfono. Cerrá esta hoja y volvé a abrir la casa.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'dado que se tocó «Cancelar», cuando se cierra, no se guarda nada y se puede volver '
      'a entrar y guardar',
      (tester) async {
        final a = await montarQuePaso(tester);

        await tester.tap(find.byKey(ClavesQuePaso.cancelar));
        await asentar(tester);

        expect(_hoja, findsNothing);
        expect(a.resultados, [false]);
        expect(a.repo.recibidas, isEmpty);
        expect(_snack, findsNothing);

        await abrirQuePaso(tester);
        await elegir(tester, OpcionQuePaso.noContesto);

        expect(a.repo.recibidas, hasLength(1));
        expect(a.resultados, [false, true]);
      },
    );

    testWidgets('dado el atrás del sistema, cuando se aprieta, la hoja se cierra sin guardar', (
      tester,
    ) async {
      final a = await montarQuePaso(tester);

      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(_hoja, findsNothing);
      expect(a.resultados, [false]);
      expect(a.repo.recibidas, isEmpty);
    });

    testWidgets('dado que no hay colportor con la sesión abierta, cuando se guarda, no se guarda '
        'nada y el aviso lo dice', (tester) async {
      final a = await montarQuePaso(tester, colportorId: null);

      await elegir(tester, OpcionQuePaso.noContesto);

      expect(find.text(_noPudimosGuardar), findsOneWidget);
      expect(a.repo.recibidas, isEmpty);
    });

    testWidgets(
      'dado un edificio sin depto elegido, cuando se abre, avisa que todavía no se puede y '
      'no abre la hoja',
      (tester) async {
        final a = await montarQuePaso(tester, espacioId: null);

        expect(_hoja, findsNothing);
        expect(
          find.text('Todavía no se pueden registrar visitas en un edificio desde acá.'),
          findsOneWidget,
        );
        expect(a.resultados, [false]);
      },
    );

    testWidgets(
      'dado que no se puede leer la casa, cuando se abre, no abre la hoja y deja el error '
      'a quien la llamó (la hoja de la casa lo dice)',
      (tester) async {
        final a = await montarQuePaso(
          tester,
          fallaDeCasa: const FailureInesperado(causa: 'StateError'),
        );

        expect(_hoja, findsNothing);
        expect(a.errorAlAbrir, isNotNull);
        expect(a.resultados, isEmpty);
      },
    );

    testWidgets('dado que el espacio no está en el teléfono, cuando se abre, avisa y no abre la '
        'hoja', (tester) async {
      final a = await montarQuePaso(tester, sinCasa: true);

      expect(_hoja, findsNothing);
      expect(find.textContaining('ya no está en tu teléfono'), findsOneWidget);
      expect(a.resultados, [false]);
    });
  });

  group('datos límite y texto grande', () {
    testWidgets(
      'dado el texto al 200 % en una pantalla chica, cuando se abre la hoja con las cinco '
      'opciones, todo se alcanza y no se corta',
      (tester) async {
        await montarQuePaso(
          tester,
          personas: [_pedro],
          saldos: {'pedro': 120000},
          programar: true,
          entrevistaDada: true,
          cobrar: true,
          escala: 2,
          tamano: const Size(320, 568),
        );

        expect(tester.takeException(), isNull);
        for (final o in OpcionQuePaso.values) {
          await tester.ensureVisible(renglon(o));
          await tester.pump();
          expect(renglon(o), findsOneWidget);
        }
        await tester.ensureVisible(find.byKey(ClavesQuePaso.cancelar));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'dado el texto al 200 %, cuando se guarda, el aviso pone «Deshacer» debajo del texto '
      'y alcanza para tocarlo',
      (tester) async {
        final a = await montarQuePaso(tester, escala: 2, tamano: const Size(320, 568));

        await elegir(tester, OpcionQuePaso.noContesto);

        expect(tester.takeException(), isNull);
        final texto = tester.getRect(find.text(_guardadoNoContesto));
        final accion = tester.getRect(_deshacer);
        expect(accion.top, greaterThanOrEqualTo(texto.bottom - 1));
        expect(accion.height, greaterThanOrEqualTo(40));

        await tester.tap(_deshacer);
        await asentar(tester);
        expect(a.repo.deshechas, hasLength(1));
      },
    );

    testWidgets('dado una dirección y un nombre larguísimos, cuando se abre, no desborda', (
      tester,
    ) async {
      final larga = clienteDePersonas(
        'larga',
        'Maximiliano Alejandro Bartolomé',
        apellido: 'Rodríguez de la Santísima Trinidad y Tobago',
      );
      await montarQuePaso(
        tester,
        personas: [larga],
        saldos: {'larga': 123456700},
        cobrar: true,
        escala: 1.5,
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Maximiliano'), findsWidgets);
    });
  });

  group('Programar entrevista → «¿Con quién es la entrevista?»', () {
    testWidgets('dado una casa sin personas, cuando se elige, sigue sin preguntar con quién y la '
        'cita queda sin persona', (tester) async {
      final a = await montarQuePaso(tester, programar: true);

      await elegir(tester, OpcionQuePaso.programarEntrevista);

      expect(a.enganches.citas, [
        (ubicacionId: 'ub-1', espacioId: 'esp-1', espacioPersonaId: null, personaId: null),
      ]);
      expect(a.resultados, [true]);
      expect(_snack, findsNothing, reason: 'el aviso «Guardado» es de los resultados de un toque');
    });

    testWidgets('dado una sola persona, cuando se elige, la cita va con ella sin preguntar', (
      tester,
    ) async {
      final a = await montarQuePaso(tester, personas: [_pedro], programar: true);

      await elegir(tester, OpcionQuePaso.programarEntrevista);

      expect(a.enganches.citas.single.espacioPersonaId, 'ep-pedro');
      expect(a.enganches.citas.single.personaId, 'pedro');
      expect(find.text('¿Con quién es la entrevista?'), findsNothing);
    });

    testWidgets('dado varias personas, cuando se elige una y «Seguir», la cita va con ella', (
      tester,
    ) async {
      final a = await montarQuePaso(tester, personas: [_pedro, _ana], programar: true);

      await elegir(tester, OpcionQuePaso.programarEntrevista);
      expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);
      expect(find.text('Todavía no sé con quién'), findsOneWidget);
      await tester.tap(find.text('Ana Gómez'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Seguir'));
      await asentar(tester);

      expect(a.enganches.citas.single.espacioPersonaId, 'ep-ana');
      expect(a.resultados, [true]);
    });

    testWidgets('dado varias personas, cuando se toca «Todavía no sé con quién», la cita queda sin '
        'persona', (tester) async {
      final a = await montarQuePaso(tester, personas: [_pedro, _ana], programar: true);

      await elegir(tester, OpcionQuePaso.programarEntrevista);
      await tester.ensureVisible(find.byKey(ClavesConQuien.todaviaNoSe));
      await tester.tap(find.byKey(ClavesConQuien.todaviaNoSe));
      await asentar(tester);

      expect(a.enganches.citas.single.espacioPersonaId, isNull);
      expect(a.enganches.citas.single.personaId, isNull);
      expect(a.resultados, [true]);
    });

    testWidgets(
      'dado que se vuelve atrás desde «¿Con quién?», cuando se toca «Volver», «¿Qué pasó?» '
      'sigue abierta y se puede elegir otra cosa',
      (tester) async {
        final a = await montarQuePaso(tester, personas: [_pedro, _ana], programar: true);
        await elegir(tester, OpcionQuePaso.programarEntrevista);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Volver'));
        await asentar(tester);

        expect(_hoja, findsOneWidget);
        expect(find.text('Guardando…'), findsNothing);
        expect(a.enganches.citas, isEmpty);
        expect(a.resultados, isEmpty);

        await elegir(tester, OpcionQuePaso.noContesto);
        expect(a.resultados, [true]);
      },
    );

    testWidgets('dado que la agenda no se hizo, cuando el destino contesta que no, «¿Qué pasó?» '
        'sigue abierta', (tester) async {
      final a = await montarQuePaso(tester, programar: true);
      a.enganches.citaHecha = false;

      await elegir(tester, OpcionQuePaso.programarEntrevista);

      expect(_hoja, findsOneWidget);
      expect(a.resultados, isEmpty);
    });

    testWidgets('dado que el destino falla, cuando se elige, el aviso dice qué hacer y se puede '
        'reintentar', (tester) async {
      final a = await montarQuePaso(tester, programar: true);
      a.enganches.falla = StateError('no abrió');

      await elegir(tester, OpcionQuePaso.programarEntrevista);

      expect(find.text(_noPudimosGuardar), findsOneWidget);
      a.enganches.falla = null;

      await elegir(tester, OpcionQuePaso.programarEntrevista);

      expect(a.enganches.citas, hasLength(2));
      expect(a.resultados, [true]);
    });
  });

  group('Entrevista dada → «¿Con quién?»', () {
    testWidgets('dado una sola persona, cuando se elige, la entrevista sigue con ella', (
      tester,
    ) async {
      final a = await montarQuePaso(tester, personas: [_pedro], entrevistaDada: true);

      await elegir(tester, OpcionQuePaso.entrevistaDada);

      expect(
        a.enganches.entrevistas.single.persona,
        const PersonaDeLaEntrevista(personaId: 'pedro', espacioPersonaId: 'ep-pedro'),
      );
      expect(a.resultados, [true]);
    });

    testWidgets(
      'dado varias personas, cuando se elige una y «Empezar entrevista», sigue con ella',
      (tester) async {
        final a = await montarQuePaso(tester, personas: [_pedro, _ana], entrevistaDada: true);

        await elegir(tester, OpcionQuePaso.entrevistaDada);
        expect(find.text('¿Con quién es la entrevista?'), findsNothing, reason: 'es la de dar');
        expect(find.text('Todavía no sé con quién'), findsNothing);
        await tester.tap(find.text('Ana Gómez'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Empezar entrevista'));
        await asentar(tester);

        expect(a.enganches.entrevistas.single.persona.espacioPersonaId, 'ep-ana');
        expect(a.resultados, [true]);
      },
    );

    testWidgets('dado que se vuelve atrás, cuando se toca «Volver», «¿Qué pasó?» sigue abierta', (
      tester,
    ) async {
      final a = await montarQuePaso(tester, personas: [_pedro, _ana], entrevistaDada: true);
      await elegir(tester, OpcionQuePaso.entrevistaDada);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Volver'));
      await asentar(tester);

      expect(_hoja, findsOneWidget);
      expect(a.enganches.entrevistas, isEmpty);
    });
  });

  group('Cobranza → cobro', () {
    testWidgets('dado que el cobro se hizo, cuando vuelve, la visita queda como «Cobranza» con la '
        'persona que debía y la hoja se cierra', (tester) async {
      final a = await montarQuePaso(
        tester,
        personas: [_pedro],
        saldos: {'pedro': 120000},
        cobrar: true,
      );

      await elegir(tester, OpcionQuePaso.cobranza);

      expect(a.enganches.cobros, [(ubicacionId: 'ub-1', espacioId: 'esp-1', personaId: 'pedro')]);
      final r = a.repo.recibidas.single;
      expect(r.visita.tipoResultado, TipoResultadoVisita.cobranza);
      expect(r.visita.espacioPersonaId, 'ep-pedro');
      expect(r.agendaId, isNull);
      expect(a.resultados, [true]);
      expect(_snack, findsNothing);
    });

    testWidgets('dado que no se cobró, cuando vuelve, no se guarda ninguna visita y «¿Qué pasó?» '
        'sigue abierta', (tester) async {
      final a = await montarQuePaso(
        tester,
        personas: [_pedro],
        saldos: {'pedro': 120000},
        cobrar: true,
      );
      a.enganches.cobroHecho = false;

      await elegir(tester, OpcionQuePaso.cobranza);

      expect(a.repo.recibidas, isEmpty);
      expect(_hoja, findsOneWidget);
    });

    testWidgets(
      'dado que se cobró y el guardado de la visita falla, cuando se reintenta, el cobro no '
      'se repite y la visita no se duplica',
      (tester) async {
        final repo = AgendaRepositorioFalso()
          ..resultados.add(const FailureInesperado(causa: 'StateError'));
        final a = await montarQuePaso(
          tester,
          repo: repo,
          personas: [_pedro],
          saldos: {'pedro': 120000},
          cobrar: true,
        );

        await elegir(tester, OpcionQuePaso.cobranza);

        expect(find.text(_noPudimosGuardar), findsOneWidget);
        expect(a.enganches.cobros, hasLength(1));

        await elegir(tester, OpcionQuePaso.cobranza);

        expect(a.enganches.cobros, hasLength(1), reason: 'el cobro ya estaba hecho');
        expect(a.repo.recibidas.map((r) => r.visita.id), ['id-1', 'id-1']);
        expect(a.resultados, [true]);
      },
    );
  });

  group('Semantics', () {
    testWidgets('el título es un encabezado y «Cancelar» se alcanza con el lector', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarQuePaso(tester);

      expect(
        tester.getSemantics(find.text('¿Qué pasó?')),
        isSemantics(label: '¿Qué pasó?', isHeader: true),
      );
      expect(
        tester.getSemantics(find.byKey(ClavesQuePaso.cancelar)),
        isSemantics(label: 'Cancelar', isButton: true, isEnabled: true, hasTapAction: true),
      );
      semantica.dispose();
    });
  });

  group('EleccionDeCita', () {
    test('dado una cita con persona o sin ella, cuando se pregunta por el vínculo, lo dice', () {
      const conPedro = CitaConPersona(
        PersonaDeLaEntrevista(personaId: 'pedro', espacioPersonaId: 'ep-pedro'),
      );

      expect(conPedro.espacioPersonaId, 'ep-pedro');
      expect(const CitaSinPersona().espacioPersonaId, isNull);
      expect(const CitaSinPersona(), const CitaSinPersona());
      expect(conPedro, isNot(const CitaSinPersona()));
    });
  });
}
