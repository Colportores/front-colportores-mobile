// «¿Te acompañó alguien?» de la jornada en curso (vista 20, 20J·01 a 20J·07; vista 21, 21J·01 y 21J·02;
// HU-JOR-003, #146): el interruptor, la hoja con la lista de coordinadores de la campaña, varios
// acompañantes por jornada, los errores y los casos límite de cada flujo.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/campanias_inscriptas_providers.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/data/repositories/fakes/acompaniamiento_repository_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/acompaniante.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/acompaniamiento_providers.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/jornada/presentation/widgets/seccion_acompaniamiento.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _ahora = DateTime(2026, 11, 20, 14, 35, 20);

final _sesion = Sesion(
  usuarioId: 'col-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token',
  expiraEn: DateTime.utc(2030),
);

const _marta = CoordinadorDeCampania(usuarioId: 'u-marta', nombre: 'Marta', apellido: 'Pérez');
const _daniel = CoordinadorDeCampania(usuarioId: 'u-daniel', nombre: 'Daniel', apellido: 'Ruiz');

JornadaModel _jornadaEnCurso() => JornadaModel.fromEntity(
  Jornada(
    id: 'jor-1',
    colportorId: 'col-1',
    inicio: DateTime(2026, 11, 20, 8, 10),
    auditoria: Auditoria(
      createdAt: DateTime(2026, 11, 20, 8, 10),
      updatedAt: DateTime(2026, 11, 20, 8, 10),
      createdBy: 'col-1',
    ),
  ),
);

Future<void> _montar(
  WidgetTester tester,
  AcompaniamientoRepositoryEnMemoria repo, {
  double escala = 1,
  Size tamanio = const Size(390, 844),
  bool conCampania = true,
}) async {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(
          JornadaLocalDataSourceEnMemoria(iniciales: [_jornadaEnCurso()]),
        ),
        relojJornadaProvider.overrideWithValue(() => _ahora),
        acompaniamientoRepositoryProvider.overrideWithValue(repo),
        // La campaña en curso el día de la jornada: de ella sale «tu campaña» (sin ella, «tus campañas»).
        if (conCampania)
          campaniasInscriptasProvider('col-1').overrideWith(
            (ref) => Stream.value(const [
              CampaniaInscripta(
                campaniaId: 'cam-1',
                nombre: 'Verano',
                fechaInicio: '2026-11-01',
                fechaFin: '2026-11-30',
              ),
            ]),
          ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(body: JornadaPage(sesion: _sesion)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Solo la sección, sin el resto de «Hoy»: a 320 dp y 200 % la fila de la hora de fin de «Hoy» ya desborda
/// en develop (no es de #146) y taparía lo que se mide acá.
Future<void> _montarSeccion(
  WidgetTester tester,
  AcompaniamientoRepositoryEnMemoria repo, {
  required double escala,
  required Size tamanio,
}) async {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [acompaniamientoRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SeccionAcompaniamiento(
              colportorId: 'col-1',
              jornada: _jornadaEnCurso().toEntity(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _interruptor() => find.byKey(const Key('acompaniamiento_interruptor'));
Finder _fila(String usuarioId) => find.byKey(Key('acompaniante_$usuarioId'));
Finder _listo() => find.byKey(const Key('hoja_acompaniantes_listo'));

Future<void> _abrirHoja(WidgetTester tester) async {
  await tester.ensureVisible(_interruptor());
  await tester.tap(_interruptor());
  await tester.pumpAndSettle();
}

/// Con alguien ya anotado (o pedido), la hoja se abre desde «Cambiar».
Future<void> _abrirCambiar(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('acompaniamiento_cambiar')));
  await tester.tap(find.byKey(const Key('acompaniamiento_cambiar')));
  await tester.pumpAndSettle();
}

Future<void> _elegirYListo(WidgetTester tester, List<String> usuarios) async {
  for (final u in usuarios) {
    await tester.ensureVisible(_fila(u));
    await tester.tap(_fila(u));
    await tester.pump();
  }
  await tester.ensureVisible(_listo());
  await tester.tap(_listo());
  await tester.pumpAndSettle();
}

void main() {
  late AcompaniamientoRepositoryEnMemoria repo;

  setUp(() => repo = AcompaniamientoRepositoryEnMemoria(lista: const [_marta, _daniel]));

  group('20J·01 · jornada sin acompañante', () {
    testWidgets('dado una jornada en curso, cuando entro, veo «¿Te acompañó alguien?» apagado', (
      tester,
    ) async {
      await _montar(tester, repo);

      expect(find.text('¿Te acompañó alguien?'), findsOneWidget);
      expect(find.text('Coordinador de tu campaña'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(_interruptor()).value, isFalse);
      expect(
        find.textContaining('administrador'),
        findsNothing,
        reason: 'solo coordinadores (09/11)',
      );
    });
  });

  group('20J·02 · elegir quién', () {
    testWidgets('al prender el interruptor se abre la lista de coordinadores, sin «Otra persona»', (
      tester,
    ) async {
      await _montar(tester, repo);

      await _abrirHoja(tester);

      expect(find.text('¿Quién te acompaña?'), findsOneWidget);
      expect(find.text('Marta Pérez'), findsOneWidget);
      expect(find.text('Daniel Ruiz'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.textContaining('Otra persona'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('hoja_acompaniantes')),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );
      expect(
        find.text('Nadie me acompañó'),
        findsNothing,
        reason: 'todavía no hay nadie que quitar',
      );
    });

    testWidgets('«Cancelar» cierra la hoja, no guarda nada y el interruptor sigue apagado', (
      tester,
    ) async {
      await _montar(tester, repo);
      await _abrirHoja(tester);
      await tester.tap(_fila('u-marta'));
      await tester.pump();

      await tester.tap(find.byKey(const Key('hoja_acompaniantes_cancelar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hoja_acompaniantes')), findsNothing);
      expect(repo.pedidos, isEmpty);
      expect(tester.widget<SwitchListTile>(_interruptor()).value, isFalse);
    });

    testWidgets('«Listo» sin marcar a nadie no guarda nada', (tester) async {
      await _montar(tester, repo);
      await _abrirHoja(tester);

      await tester.tap(_listo());
      await tester.pumpAndSettle();

      expect(repo.pedidos, isEmpty);
      expect(find.byKey(const Key('acompaniamiento_tarjeta')), findsNothing);
    });
  });

  group('20J·03 · con acompañante (guardado)', () {
    testWidgets(
      'elegir a Marta la anota, dice «Anotamos que te acompaña Marta.» y muestra su tarjeta',
      (tester) async {
        await _montar(tester, repo);
        await _abrirHoja(tester);

        await _elegirYListo(tester, ['u-marta']);

        expect(find.text('Anotamos que te acompaña Marta.'), findsOneWidget);
        expect(find.text('TE ACOMPAÑA'), findsOneWidget);
        expect(find.text('Marta Pérez'), findsOneWidget);
        expect(find.text('Cambiar'), findsOneWidget);
        expect(_interruptor(), findsNothing);
        expect(repo.guardadosDe('jor-1'), ['u-marta']);
      },
    );

    testWidgets(
      'puede acompañarla más de uno: los dos se anotan y la tarjeta dice «TE ACOMPAÑAN»',
      (tester) async {
        await _montar(tester, repo);
        await _abrirHoja(tester);

        await _elegirYListo(tester, ['u-marta', 'u-daniel']);

        expect(find.text('Anotamos que te acompañan Marta y Daniel.'), findsOneWidget);
        expect(find.text('TE ACOMPAÑAN'), findsOneWidget);
        expect(find.byKey(const Key('acompaniante_tarjeta_u-marta')), findsOneWidget);
        expect(find.byKey(const Key('acompaniante_tarjeta_u-daniel')), findsOneWidget);
        expect(repo.guardadosDe('jor-1'), ['u-daniel', 'u-marta']);
      },
    );

    testWidgets('volver atrás y reentrar muestra lo mismo que se guardó', (tester) async {
      await _montar(tester, repo);
      await _abrirHoja(tester);
      await _elegirYListo(tester, ['u-marta']);

      await tester.pumpWidget(const SizedBox());
      await _montar(tester, repo);

      expect(find.text('TE ACOMPAÑA'), findsOneWidget);
      expect(find.text('Marta Pérez'), findsOneWidget);
    });
  });

  group('20J·04 · cambiar o quitar', () {
    testWidgets(
      '«Cambiar» abre la hoja con los que ya acompañan marcados y suma a otro sin tocar al primero',
      (tester) async {
        await _montar(tester, repo);
        await _abrirHoja(tester);
        await _elegirYListo(tester, ['u-marta']);

        await tester.tap(find.byKey(const Key('acompaniamiento_cambiar')));
        await tester.pumpAndSettle();
        expect(tester.widget<CheckboxListTile>(_fila('u-marta')).value, isTrue);
        expect(tester.widget<CheckboxListTile>(_fila('u-daniel')).value, isFalse);
        await _elegirYListo(tester, ['u-daniel']);

        expect(repo.pedidos.last, {'u-marta', 'u-daniel'});
        expect(find.text('TE ACOMPAÑAN'), findsOneWidget);
      },
    );

    testWidgets('«Nadie me acompañó» los quita a todos y vuelve el interruptor apagado', (
      tester,
    ) async {
      await _montar(tester, repo);
      await _abrirHoja(tester);
      await _elegirYListo(tester, ['u-marta', 'u-daniel']);
      await tester.tap(find.byKey(const Key('acompaniamiento_cambiar')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('hoja_acompaniantes_nadie')));
      await tester.tap(find.byKey(const Key('hoja_acompaniantes_nadie')));
      await tester.pumpAndSettle();

      expect(find.text('Anotamos que nadie te acompañó.'), findsOneWidget);
      expect(_interruptor(), findsOneWidget);
      expect(tester.widget<SwitchListTile>(_interruptor()).value, isFalse);
      expect(repo.guardadosDe('jor-1'), isEmpty);
    });

    testWidgets('si no cambió nada, «Listo» no vuelve a guardar ni a subir', (tester) async {
      await _montar(tester, repo);
      await _abrirHoja(tester);
      await _elegirYListo(tester, ['u-marta']);
      await tester.tap(find.byKey(const Key('acompaniamiento_cambiar')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(_listo());
      await tester.tap(_listo());
      await tester.pumpAndSettle();

      expect(repo.pedidos, hasLength(1));
    });

    testWidgets('un acompañante que ya no está en la lista de hoy sigue marcado y se puede sacar', (
      tester,
    ) async {
      await _montar(tester, repo);
      await _abrirHoja(tester);
      await _elegirYListo(tester, ['u-marta', 'u-daniel']);
      // Marta dejó de contar: la lista de hoy ya no la trae, pero su acompañamiento queda.
      repo.lista = const [_daniel];
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('acompaniamiento_cambiar')));
      await tester.pumpAndSettle();

      expect(tester.widget<CheckboxListTile>(_fila('u-marta')).value, isTrue);
      await tester.ensureVisible(_fila('u-marta'));
      await tester.tap(_fila('u-marta'));
      await tester.pump();
      await tester.ensureVisible(_listo());
      await tester.tap(_listo());
      await tester.pumpAndSettle();
      expect(repo.guardadosDe('jor-1'), ['u-daniel']);
    });
  });

  group('campaña de la jornada desconocida', () {
    testWidgets('sin saber la campaña, los textos dicen «tus campañas»; sabiéndola, «tu campaña»', (
      tester,
    ) async {
      await _montar(tester, repo, conCampania: false);

      // Sin inscripciones leídas la campaña de la jornada no se conoce.
      expect(find.text('Coordinador de tus campañas'), findsOneWidget);
      await _abrirHoja(tester);
      expect(find.text('Coordinación de tus campañas'), findsNWidgets(2));
      expect(find.text('Coordinación de tu campaña'), findsNothing);
    });
  });

  group('20J·05 y 20J·06 · lista vacía y sin conexión', () {
    testWidgets('sin la lista bajada dice qué pasa y no deja elegir a nadie', (tester) async {
      repo.lista = const [];
      await _montar(tester, repo);

      await _abrirHoja(tester);

      expect(
        find.text(
          'Todavía no recibimos la lista de coordinadores de tu campaña. Se actualiza cuando haya conexión.',
        ),
        findsOneWidget,
      );
      expect(_listo(), findsNothing);
      await tester.tap(find.byKey(const Key('hoja_acompaniantes_cerrar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hoja_acompaniantes')), findsNothing);
      expect(repo.pedidos, isEmpty);
    });

    testWidgets('la lista que ya bajó se elige igual sin conexión: nada de la hoja pide red', (
      tester,
    ) async {
      // La lista viene de la base del teléfono (baja con la sincronización): elegir y guardar son locales.
      await _montar(tester, repo);
      await _abrirHoja(tester);

      await _elegirYListo(tester, ['u-daniel']);

      expect(find.textContaining('conexión'), findsNothing);
      expect(repo.guardadosDe('jor-1'), ['u-daniel']);
    });

    testWidgets('si la lista llega mientras la hoja está abierta, aparece sola', (tester) async {
      repo.lista = const [];
      await _montar(tester, repo);
      await _abrirHoja(tester);
      expect(find.byKey(const Key('hoja_acompaniantes_vacia')), findsOneWidget);

      repo.lista = const [_marta];
      await tester.pumpAndSettle();

      expect(_fila('u-marta'), findsOneWidget);
    });
  });

  group('20J·07 · error al guardar', () {
    testWidgets(
      'dice qué pasó y qué hacer, deja lo guardado como estaba y «Reintentar» lo vuelve a intentar',
      (tester) async {
        await _montar(tester, repo);
        await _abrirHoja(tester);
        repo.fallas = 1;

        await _elegirYListo(tester, ['u-marta']);

        expect(find.text('No pudimos guardar el acompañamiento. Probá de nuevo.'), findsOneWidget);
        expect(find.text('Anotamos que te acompaña Marta.'), findsNothing);
        expect(_interruptor(), findsOneWidget, reason: 'lo que estaba guardado no cambia');
        expect(find.textContaining('Guardando'), findsNothing, reason: 'nada queda trabado');

        await tester.tap(find.byKey(const Key('acompaniamiento_reintentar')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('acompaniamiento_error')), findsNothing);
        expect(find.text('Anotamos que te acompaña Marta.'), findsOneWidget);
        expect(repo.guardadosDe('jor-1'), ['u-marta']);
        expect(repo.pedidos, [
          {'u-marta'},
          {'u-marta'},
        ]);
      },
    );

    testWidgets('después de una falla se puede volver a elegir: el interruptor no queda trabado', (
      tester,
    ) async {
      await _montar(tester, repo);
      await _abrirHoja(tester);
      repo.fallas = 1;
      await _elegirYListo(tester, ['u-marta']);

      await _abrirHoja(tester);
      await _elegirYListo(tester, ['u-daniel']);

      expect(find.byKey(const Key('acompaniamiento_error')), findsNothing);
      expect(repo.guardadosDe('jor-1'), ['u-daniel']);
    });
  });

  group('casos límite', () {
    testWidgets('un doble toque en «Listo» guarda una sola vez y no saca la pantalla de abajo', (
      tester,
    ) async {
      await _montar(tester, repo);
      await _abrirHoja(tester);
      await tester.tap(_fila('u-marta'));
      await tester.pump();

      await tester.ensureVisible(_listo());
      await tester.tap(_listo());
      await tester.tap(_listo(), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(repo.pedidos, hasLength(1));
      expect(find.byType(JornadaPage), findsOneWidget);
    });

    testWidgets(
      'dos cambios seguidos antes de que termine el primero no se pisan: el último gana, en orden',
      (tester) async {
        await _montar(tester, repo);
        final compuerta = repo.compuerta = Completer<void>();
        await _abrirHoja(tester);
        await _elegirYListo(tester, ['u-marta']);
        // El primero sigue en vuelo: la pantalla ya muestra lo que se pidió y va un segundo cambio encima.
        expect(repo.pedidos, [
          {'u-marta'},
        ]);
        expect(find.text('TE ACOMPAÑA'), findsOneWidget);
        await _abrirCambiar(tester);
        expect(tester.widget<CheckboxListTile>(_fila('u-marta')).value, isTrue);
        await _elegirYListo(tester, ['u-daniel']);
        expect(repo.pedidos, hasLength(1), reason: 'el segundo espera su turno');

        repo.compuerta = null;
        compuerta.complete();
        await tester.pumpAndSettle();

        expect(repo.pedidos, [
          {'u-marta'},
          {'u-daniel', 'u-marta'},
        ]);
        expect(repo.guardadosDe('jor-1'), ['u-marta', 'u-daniel']);
        expect(find.text('TE ACOMPAÑAN'), findsOneWidget);
      },
    );

    testWidgets('una falla del primero no tapa el éxito del segundo', (tester) async {
      await _montar(tester, repo);
      final compuerta = repo.compuerta = Completer<void>();
      repo.fallas = 1;
      await _abrirHoja(tester);
      await _elegirYListo(tester, ['u-marta']);
      await _abrirCambiar(tester);
      await _elegirYListo(tester, ['u-daniel']);

      repo.compuerta = null;
      compuerta.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('acompaniamiento_error')), findsNothing);
      expect(repo.guardadosDe('jor-1'), ['u-daniel', 'u-marta']);
    });

    testWidgets(
      'una lista larga se recorre: 40 coordinadores con nombres largos y se marca el último',
      (tester) async {
        repo.lista = [
          for (var i = 0; i < 40; i++)
            CoordinadorDeCampania(
              usuarioId: 'u-$i',
              nombre: 'María de los Ángeles Fernández $i',
              apellido: 'Rodríguez de la Santísima Trinidad y Gómez',
            ),
        ];
        await _montar(tester, repo);
        await _abrirHoja(tester);

        await _elegirYListo(tester, ['u-39']);

        expect(repo.guardadosDe('jor-1'), ['u-39']);
        expect(tester.takeException(), isNull);
      },
    );

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'con el texto al ${(escala * 100).round()} % en 320×568 no se corta nada ni desborda',
        (tester) async {
          await _montarSeccion(tester, repo, escala: escala, tamanio: const Size(320, 568));
          await _abrirHoja(tester);
          expect(tester.takeException(), isNull);
          await _elegirYListo(tester, ['u-marta', 'u-daniel']);

          expect(tester.takeException(), isNull);
          expect(find.text('TE ACOMPAÑAN'), findsOneWidget);
        },
      );
    }

    testWidgets('el interruptor y los botones se pueden tocar: 48 dp o más y con su nombre', (
      tester,
    ) async {
      await _montar(tester, repo);
      final semantica = tester.ensureSemantics();

      expect(tester.getSize(_interruptor()).height, greaterThanOrEqualTo(48));
      await _abrirHoja(tester);
      expect(find.bySemanticsLabel(RegExp('Marta Pérez')), findsWidgets);
      expect(tester.getSize(_listo()).height, greaterThanOrEqualTo(48));
      semantica.dispose();
    });

    testWidgets('al cerrar la jornada el acompañamiento sigue en lo que se guardó', (tester) async {
      await _montar(tester, repo);
      await _abrirHoja(tester);
      await _elegirYListo(tester, ['u-marta']);

      final quienes = await repo.observarDe('jor-1').first;

      expect(quienes, const [
        Acompaniante(usuarioId: 'u-marta', nombre: 'Marta', apellido: 'Pérez'),
      ]);
    });
  });
}
