// La nota del depto (vista 11, «Nota depto», #290): la fila de la hoja del depto (11N·01, 11N·03,
// 11N·05), el formulario (11N·02, 11N·04, 11N·07), la pestaña Notas del depto (varias, con fecha;
// borrar con «Deshacer»; «Ver borradas» 90 días) y el principio de la nota más nueva en la lista de
// deptos (11N·06), con los casos límite de cada flujo.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resumen_del_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/notas_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/deptos_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/fila_nota_del_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_notas_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_ubicacion_falsos.dart';
import 'notas_lugar_arnes.dart' show ContadorDeRutas, ahoraDeLugar, asentarLugar, fijarTamanoLugar;

/// El depto 3B de los tests.
const _depto = 'e-3b';

Future<void> _montar(
  WidgetTester tester,
  Widget hijo, {
  NotaUbicacionRepositorioFalso? repo,
  double escala = 1,
  Size tamano = const Size(390, 844),
  List<NavigatorObserver> observadores = const [],
}) async {
  fijarTamanoLugar(tester, tamano);
  var contador = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notaDeptoRepositoryProvider.overrideWithValue(repo ?? NotaUbicacionRepositorioFalso()),
        relojPersonaProvider.overrideWithValue(() => ahoraDeLugar),
        generadorIdPersonaProvider.overrideWithValue(() => 'depto-nueva-${++contador}'),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        navigatorObservers: observadores,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: hijo),
        ),
      ),
    ),
  );
  await asentarLugar(tester);
}

Future<void> _montarFila(
  WidgetTester tester, {
  NotaUbicacionRepositorioFalso? repo,
  String? colportorId = 'col-1',
  bool soloLectura = false,
  double escala = 1,
  Size tamano = const Size(390, 844),
  List<NavigatorObserver> observadores = const [],
}) => _montar(
  tester,
  FilaNotaDelDepto(espacioId: _depto, colportorId: colportorId, soloLectura: soloLectura),
  repo: repo,
  escala: escala,
  tamano: tamano,
  observadores: observadores,
);

Future<void> _montarPestana(
  WidgetTester tester, {
  NotaUbicacionRepositorioFalso? repo,
  bool soloLectura = false,
}) => _montar(
  tester,
  PestanaNotasDeLaCasa(
    ubicacionId: 'ubi-1',
    espacioId: _depto,
    colportorId: 'col-1',
    soloLectura: soloLectura,
  ),
  repo: repo,
);

NotaUbicacionRepositorioFalso _repoCon(List<(String, String)> notas) =>
    NotaUbicacionRepositorioFalso(
      notas: [
        for (final (i, (id, texto)) in notas.indexed)
          notaDeLugar(id, texto, ubicacionId: _depto, creada: DateTime(2026, 10, 22, 14, 20 - i)),
      ],
    );

Future<void> _escribirYGuardar(WidgetTester tester, String texto) async {
  await tester.enterText(find.byKey(ClavesNotas.campo), texto);
  await tester.pump();
  await tester.tap(find.text('Guardar nota'));
  await asentarLugar(tester);
}

void main() {
  group('11N·01 depto sin nota', () {
    testWidgets(
      'dado un depto sin notas, cuando miro su hoja, veo «+ Agregar una nota» con su ejemplo y '
      'ninguna nota',
      (tester) async {
        await _montarFila(tester);

        expect(find.text('+ Agregar una nota'), findsOneWidget);
        expect(find.text('Por ejemplo, «timbre roto, tocar fuerte»'), findsOneWidget);
        expect(find.byKey(ClavesNotaDelDepto.editar), findsNothing);
        expect(
          tester.getSize(find.byKey(ClavesNotaDelDepto.agregar)).height,
          greaterThanOrEqualTo(48),
        );
      },
    );

    testWidgets('dado un depto de un lugar dado de baja o sin sesión, no ofrece agregar nada', (
      tester,
    ) async {
      await _montarFila(tester, soloLectura: true);
      expect(find.text('+ Agregar una nota'), findsNothing);

      await _montarFila(tester, colportorId: null);
      expect(find.text('+ Agregar una nota'), findsNothing);
    });

    testWidgets('dado que todavía lee, cuando carga, no dibuja nada que tape lo demás', (
      tester,
    ) async {
      await _montarFila(tester, repo: NotaUbicacionRepositorioCargando());

      expect(find.byKey(ClavesNotaDelDepto.fila), findsNothing);
      expect(find.byKey(ClavesNotaDelDepto.agregar), findsNothing);
      expect(find.byKey(ClavesNotaDelDepto.error), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('11N·02 y 11N·03 escribir la nota y verla en la hoja', () {
    testWidgets(
      'dado un depto sin notas, cuando toco «+ Agregar una nota», escribo y guardo, vuelve a la '
      'hoja con la nota y «Editar»',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso();
        await _montarFila(tester, repo: repo);

        await tester.tap(find.text('+ Agregar una nota'));
        await asentarLugar(tester);
        expect(find.text('Guardar nota'), findsOneWidget);
        expect(find.text('Estas notas viven solo en tu celular.'), findsOneWidget);
        await _escribirYGuardar(tester, 'timbre roto, tocar fuerte');

        expect(find.text('Guardar nota'), findsNothing, reason: 'volvió a la hoja del depto');
        expect(find.text('NOTA DEL DEPTO'), findsOneWidget);
        expect(find.text('timbre roto, tocar fuerte'), findsOneWidget);
        expect(find.text('Editar'), findsOneWidget);
        expect(find.text('+ Agregar una nota'), findsNothing);
        expect(repo.llamadas, ['agregar:depto-nueva-1']);
        expect(repo.notas.single.ubicacionId, _depto, reason: 'la nota es del depto');
      },
    );

    testWidgets('dado que cierro el formulario sin escribir, la hoja queda igual y no guarda', (
      tester,
    ) async {
      final repo = NotaUbicacionRepositorioFalso();
      await _montarFila(tester, repo: repo);
      await tester.tap(find.text('+ Agregar una nota'));
      await asentarLugar(tester);

      await tester.tap(find.byTooltip('Cerrar'));
      await asentarLugar(tester);

      expect(find.text('+ Agregar una nota'), findsOneWidget);
      expect(repo.llamadas, isEmpty);
    });

    testWidgets('dado un doble toque en «+ Agregar una nota», se abre un solo formulario', (
      tester,
    ) async {
      final rutas = ContadorDeRutas();
      await _montarFila(tester, observadores: [rutas]);

      final tarjeta = find.byKey(ClavesNotaDelDepto.agregar);
      await tester.tap(tarjeta);
      await tester.tap(tarjeta, warnIfMissed: false);
      await asentarLugar(tester);

      expect(rutas.empujadas, 1);
      expect(find.text('Guardar nota'), findsOneWidget);
    });

    testWidgets('dado un guardado en curso, un segundo toque en «Guardar nota» no guarda dos', (
      tester,
    ) async {
      final compuerta = Completer<void>();
      final repo = NotaUbicacionRepositorioFalso()..compuertas['agregar'] = compuerta;
      await _montarFila(tester, repo: repo);
      await tester.tap(find.text('+ Agregar una nota'));
      await asentarLugar(tester);

      await tester.enterText(find.byKey(ClavesNotas.campo), 'portón de rejas');
      await tester.pump();
      await tester.tap(find.text('Guardar nota'));
      await tester.pump();
      await tester.tap(find.text('Guardando…'), warnIfMissed: false);
      await tester.pump();
      compuerta.complete();
      await asentarLugar(tester);

      expect(repo.cuantas('agregar'), 1);
      expect(repo.notas, hasLength(1));
    });
  });

  group('11N·04 editar', () {
    testWidgets(
      'dado un depto con nota, cuando toco «Editar», cambio el texto y guardo, la hoja muestra el '
      'texto nuevo',
      (tester) async {
        final repo = _repoCon([('a', 'timbre roto, tocar fuerte')]);
        await _montarFila(tester, repo: repo);

        await tester.tap(find.byKey(ClavesNotaDelDepto.editar));
        await asentarLugar(tester);
        expect(
          tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller!.text,
          'timbre roto, tocar fuerte',
        );
        await _escribirYGuardar(tester, 'timbre arreglado');

        expect(find.text('timbre arreglado'), findsOneWidget);
        expect(find.text('timbre roto, tocar fuerte'), findsNothing);
        expect(repo.llamadas, ['editar:a']);
      },
    );

    testWidgets('dado que edito y vuelvo atrás sin cambiar nada, no se escribe nada', (
      tester,
    ) async {
      final repo = _repoCon([('a', 'timbre roto')]);
      await _montarFila(tester, repo: repo);
      await tester.tap(find.byKey(ClavesNotaDelDepto.editar));
      await asentarLugar(tester);

      await tester.tap(find.text('Guardar nota'));
      await asentarLugar(tester);

      expect(repo.textosRecibidos, isEmpty, reason: 'sin cambios no toca updated_at');
      expect(find.text('timbre roto'), findsOneWidget);
    });

    testWidgets('dado que vuelvo a entrar a editar después de cerrar, el texto es el guardado', (
      tester,
    ) async {
      final repo = _repoCon([('a', 'timbre roto')]);
      await _montarFila(tester, repo: repo);

      await tester.tap(find.byKey(ClavesNotaDelDepto.editar));
      await asentarLugar(tester);
      await tester.enterText(find.byKey(ClavesNotas.campo), 'algo sin guardar');
      await tester.tap(find.byTooltip('Cerrar'));
      await asentarLugar(tester);
      expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
      await tester.tap(find.text('Descartar'));
      await asentarLugar(tester);
      await tester.tap(find.byKey(ClavesNotaDelDepto.editar));
      await asentarLugar(tester);

      expect(
        tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller!.text,
        'timbre roto',
      );
    });

    testWidgets('dado un depto con varias notas, la hoja muestra la más nueva', (tester) async {
      await _montarFila(tester, repo: _repoCon([('nueva', 'la más nueva'), ('vieja', 'la vieja')]));

      expect(find.text('la más nueva'), findsOneWidget);
      expect(find.text('la vieja'), findsNothing);
    });

    testWidgets('dado un lugar de baja, la nota se ve pero no hay «Editar»', (tester) async {
      await _montarFila(tester, repo: _repoCon([('a', 'timbre roto')]), soloLectura: true);

      expect(find.text('timbre roto'), findsOneWidget);
      expect(find.byKey(ClavesNotaDelDepto.editar), findsNothing);
    });
  });

  group('11N·04 «Borrar nota» en el formulario de editar (decisión §2 de P2)', () {
    Finder borrar() => find.byKey(ClavesNotas.borrarDelFormulario);

    Future<void> abrirEdicion(WidgetTester tester) async {
      await tester.tap(find.byKey(ClavesNotaDelDepto.editar));
      await asentarLugar(tester);
    }

    testWidgets('dado el formulario de una nota nueva, no ofrece «Borrar nota»', (tester) async {
      await _montarFila(tester);
      await tester.tap(find.text('+ Agregar una nota'));
      await asentarLugar(tester);

      expect(borrar(), findsNothing);
    });

    testWidgets(
      'dado el formulario de editar, «Borrar nota» borra (baja restaurable), cierra y la hoja '
      'ofrece «Deshacer»; al deshacer la nota vuelve',
      (tester) async {
        final repo = _repoCon([('a', 'timbre roto')]);
        await _montarFila(tester, repo: repo);
        await abrirEdicion(tester);
        expect(find.text('Borrar nota'), findsOneWidget);

        await tester.tap(borrar());
        await asentarLugar(tester);

        expect(find.text('Guardar nota'), findsNothing, reason: 'el formulario se cerró');
        expect(repo.notas.single.estaBorrada, isTrue, reason: 'soft delete: la nota sigue');
        expect(find.text('+ Agregar una nota'), findsOneWidget);
        expect(find.text('Nota borrada.'), findsOneWidget);

        await tester.tap(find.text('Deshacer'));
        await asentarLugar(tester);
        expect(find.text('Nota restaurada.'), findsOneWidget);
        expect(repo.notas.single.estaBorrada, isFalse);
        expect(find.text('timbre roto'), findsOneWidget);
      },
    );

    testWidgets('dado un doble toque en «Borrar nota», borra una sola vez', (tester) async {
      final compuerta = Completer<void>();
      final repo = _repoCon([('a', 'timbre roto')])..compuertas['borrar'] = compuerta;
      await _montarFila(tester, repo: repo);
      await abrirEdicion(tester);

      await tester.tap(borrar());
      await tester.pump();
      await tester.tap(borrar(), warnIfMissed: false);
      await tester.pump();
      compuerta.complete();
      await asentarLugar(tester);

      expect(repo.cuantas('borrar'), 1);
    });

    testWidgets(
      'dado que borrar falla, el formulario sigue con el texto, dice qué hacer y todo vuelve a '
      'habilitarse; al reintentar borra',
      (tester) async {
        final repo = _repoCon([('a', 'timbre roto')])
          ..resultados['borrar'] = [const FailureInesperado(causa: 'x')];
        await _montarFila(tester, repo: repo);
        await abrirEdicion(tester);

        await tester.tap(borrar());
        await asentarLugar(tester);

        expect(find.text('No pudimos borrar la nota. Probá de nuevo.'), findsOneWidget);
        expect(find.text('Guardar nota'), findsOneWidget);
        expect(repo.notas.single.estaBorrada, isFalse);
        expect(
          tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller!.text,
          'timbre roto',
        );
        await tester.tap(borrar());
        await asentarLugar(tester);
        expect(repo.notas.single.estaBorrada, isTrue);
      },
    );

    testWidgets('dado que deshacer falla, el aviso manda a «Ver borradas» y reintenta', (
      tester,
    ) async {
      final repo = _repoCon([('a', 'timbre roto')])
        ..resultados['restaurar'] = [const FailureInesperado(causa: 'x')];
      await _montarFila(tester, repo: repo);
      await abrirEdicion(tester);
      await tester.tap(borrar());
      await asentarLugar(tester);

      await tester.tap(find.text('Deshacer'));
      await asentarLugar(tester);
      expect(find.textContaining('No pudimos deshacer el borrado'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await asentarLugar(tester);
      expect(repo.notas.single.estaBorrada, isFalse);
    });

    testWidgets(
      'desde la pestaña Notas: borrar en el formulario muestra «Nota borrada.» con «Deshacer»',
      (tester) async {
        final repo = _repoCon([('a', 'la nota')]);
        await _montarPestana(tester, repo: repo);
        await tester.tap(find.byKey(ClavesNotasDelLugar.nota('a')));
        await asentarLugar(tester);
        await tester.tap(find.byKey(ClavesNotas.botonEditar));
        await asentarLugar(tester);

        await tester.tap(borrar());
        await asentarLugar(tester);

        expect(find.text('Nota borrada.'), findsOneWidget);
        expect(find.text('Ver borradas (1)'), findsOneWidget);
        await tester.tap(find.byKey(ClavesNotasDelLugar.deshacer));
        await asentarLugar(tester);
        expect(find.text('la nota'), findsOneWidget);
      },
    );

    testWidgets('dado un depto, 320 dp y texto 2x, «Borrar nota» no desborda y mide 48 dp', (
      tester,
    ) async {
      await _montarFila(
        tester,
        repo: _repoCon([('a', 'timbre roto')]),
        escala: 2,
        tamano: const Size(320, 640),
      );
      await abrirEdicion(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(borrar()).height, greaterThanOrEqualTo(48));
    });
  });

  group('11N·05 nota larga', () {
    final larga =
        'Portero de 8 a 12. Después de las 12 tocar el 3B desde la calle; el timbre suena bajo, '
            'golpear la reja. ' *
        3;

    testWidgets(
      'dado una nota larga, la hoja la corta a tres renglones y el lector la lee entera',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await _montarFila(tester, repo: _repoCon([('a', larga)]));

        final texto = tester.widget<Text>(find.byKey(ClavesNotaDelDepto.texto));
        expect(texto.maxLines, 3);
        expect(texto.overflow, TextOverflow.ellipsis);
        expect(find.bySemanticsLabel('NOTA DEL DEPTO. $larga'), findsOneWidget);
        semantica.dispose();
      },
    );

    testWidgets('dado una nota de 5000 caracteres, la fila no desborda ni a 320 dp con texto 2x', (
      tester,
    ) async {
      final enorme = List.filled(5000, 'palabra').join(' ').substring(0, 5000);
      await _montarFila(
        tester,
        repo: _repoCon([('a', enorme)]),
        escala: 2,
        tamano: const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesNotaDelDepto.editar), findsOneWidget);
      expect(
        tester.getSize(find.byKey(ClavesNotaDelDepto.editar)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('dado «+ Agregar una nota» con texto 2x en 320 dp, no desborda', (tester) async {
      await _montarFila(tester, escala: 2, tamano: const Size(320, 640));

      expect(tester.takeException(), isNull);
      expect(find.text('+ Agregar una nota'), findsOneWidget);
    });
  });

  group('11N·07 error al guardar', () {
    testWidgets(
      'dado que guardar falla, el texto sigue, el botón vuelve a habilitarse y «Reintentar» '
      'guarda una sola nota',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso()
          ..resultados['agregar'] = [const FailureInesperado(causa: 'x')];
        await _montarFila(tester, repo: repo);
        await tester.tap(find.text('+ Agregar una nota'));
        await asentarLugar(tester);

        await _escribirYGuardar(tester, 'timbre roto, tocar fuerte');

        expect(find.text('No pudimos guardar la nota. El texto sigue acá.'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller!.text,
          'timbre roto, tocar fuerte',
        );
        await tester.tap(find.text('Reintentar'));
        await asentarLugar(tester);

        expect(find.text('Guardar nota'), findsNothing);
        expect(repo.notas, hasLength(1));
        expect(repo.llamadas, ['agregar:depto-nueva-1', 'agregar:depto-nueva-1']);
      },
    );

    testWidgets('dado que el depto se dio de baja mientras escribía, el formulario dice por qué', (
      tester,
    ) async {
      final repo = NotaUbicacionRepositorioFalso()
        ..resultados['agregar'] = [
          const FailureValidacion(campos: {'espacio': 'Este depto está dado de baja.'}),
        ];
      await _montarFila(tester, repo: repo);
      await tester.tap(find.text('+ Agregar una nota'));
      await asentarLugar(tester);

      await _escribirYGuardar(tester, 'algo');

      expect(find.text('Este depto está dado de baja.'), findsOneWidget);
      expect(repo.notas, isEmpty);
    });

    testWidgets('dado que no se pudo leer, la hoja lo dice y «Reintentar» vuelve a leer', (
      tester,
    ) async {
      final repo = NotaUbicacionRepositorioQueFallaUnaVez(
        notas: [notaDeLugar('a', 'timbre roto', ubicacionId: _depto)],
      );
      await _montarFila(tester, repo: repo);

      expect(find.byKey(ClavesNotaDelDepto.error), findsOneWidget);
      expect(find.text('No pudimos leer las notas del depto en tu teléfono.'), findsOneWidget);

      await tester.tap(find.byKey(ClavesNotaDelDepto.reintentar));
      await asentarLugar(tester);

      expect(find.byKey(ClavesNotaDelDepto.error), findsNothing);
      expect(find.text('timbre roto'), findsOneWidget);
    });
  });

  group('pestaña Notas del depto (varias, con fecha, borrar y restaurar)', () {
    testWidgets(
      'dado un depto con dos notas, la pestaña las lista por fecha y ofrece «+ Nota del depto»',
      (tester) async {
        await _montarPestana(tester, repo: _repoCon([('a', 'la más nueva'), ('b', 'la vieja')]));

        expect(find.text('+ Nota del depto'), findsOneWidget);
        expect(find.text('+ Nota del lugar'), findsNothing);
        expect(find.text('la más nueva'), findsOneWidget);
        expect(find.text('la vieja'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(ClavesNotasDelLugar.nota('a'))).dy,
          lessThan(tester.getTopLeft(find.byKey(ClavesNotasDelLugar.nota('b'))).dy),
        );
      },
    );

    testWidgets('dado un depto sin notas, la pestaña dice que no hay y qué hacer', (tester) async {
      await _montarPestana(tester);

      expect(find.byKey(ClavesNotasDelLugar.vacio), findsOneWidget);
      expect(find.text('+ Nota del depto'), findsOneWidget);
    });

    testWidgets(
      'dado que agrego una nota desde la pestaña, queda del depto y aparece con «Guardamos la nota»',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso();
        await _montarPestana(tester, repo: repo);

        await tester.tap(find.text('+ Nota del depto'));
        await asentarLugar(tester);
        await _escribirYGuardar(tester, 'perro en el palier');

        expect(find.text('Guardamos la nota en este teléfono.'), findsOneWidget);
        expect(find.text('perro en el palier'), findsOneWidget);
        expect(repo.notas.single.ubicacionId, _depto);
      },
    );

    testWidgets(
      'dado que borro una nota, sale de la lista con «Deshacer»; al deshacer vuelve; y «Ver '
      'borradas» la guarda 90 días y la restaura',
      (tester) async {
        final repo = _repoCon([('a', 'la más nueva'), ('b', 'la vieja')]);
        await _montarPestana(tester, repo: repo);

        await tester.tap(find.byKey(ClavesNotasDelLugar.nota('a')));
        await asentarLugar(tester);
        await tester.tap(find.byKey(ClavesNotas.botonBorrar));
        await asentarLugar(tester);
        expect(find.text('Nota borrada.'), findsOneWidget);
        expect(find.text('la más nueva'), findsNothing);
        expect(find.text('Ver borradas (1)'), findsOneWidget);

        await tester.tap(find.byKey(ClavesNotasDelLugar.deshacer));
        await asentarLugar(tester);
        expect(find.text('Nota restaurada.'), findsOneWidget);
        expect(find.text('la más nueva'), findsOneWidget);

        await tester.tap(find.byKey(ClavesNotasDelLugar.nota('b')));
        await asentarLugar(tester);
        await tester.tap(find.byKey(ClavesNotas.botonBorrar));
        await asentarLugar(tester);
        await tester.tap(find.byKey(ClavesNotasDelLugar.verBorradas));
        await asentarLugar(tester);
        expect(find.text('Notas del depto'), findsOneWidget, reason: 'las borradas son del depto');
        expect(find.text('la vieja'), findsOneWidget);

        await tester.tap(find.text('Restaurar'));
        await asentarLugar(tester);
        expect(find.text('Nota restaurada.'), findsOneWidget);
        expect(repo.notas.where((n) => n.estaBorrada), isEmpty);
      },
    );

    testWidgets('dado que borro dos notas seguidas sin esperar, las dos se borran', (tester) async {
      final repo = _repoCon([('a', 'primera'), ('b', 'segunda')]);
      await _montarPestana(tester, repo: repo);

      await tester.tap(find.byKey(ClavesNotasDelLugar.nota('a')));
      await asentarLugar(tester);
      await tester.tap(find.byKey(ClavesNotas.botonBorrar));
      await tester.pump();
      await tester.tap(find.byKey(ClavesNotasDelLugar.nota('b')));
      await asentarLugar(tester);
      await tester.tap(find.byKey(ClavesNotas.botonBorrar));
      await asentarLugar(tester);

      expect(repo.notas.where((n) => n.estaBorrada), hasLength(2));
      expect(repo.cuantas('borrar'), 2);
    });

    testWidgets('dado que borrar falla, la nota sigue y el aviso ofrece «Reintentar»', (
      tester,
    ) async {
      final repo = _repoCon([('a', 'la nota')])
        ..resultados['borrar'] = [const FailureInesperado(causa: 'x')];
      await _montarPestana(tester, repo: repo);

      await tester.tap(find.byKey(ClavesNotasDelLugar.nota('a')));
      await asentarLugar(tester);
      await tester.tap(find.byKey(ClavesNotas.botonBorrar));
      await asentarLugar(tester);
      expect(find.text('No pudimos borrar la nota. Probá de nuevo.'), findsOneWidget);
      expect(find.text('la nota'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await asentarLugar(tester);
      expect(find.text('Nota borrada.'), findsOneWidget);
    });

    testWidgets('dado que no se pudo leer, la pestaña dice «del depto» y reintenta', (
      tester,
    ) async {
      final repo = NotaUbicacionRepositorioQueFallaUnaVez(
        notas: [notaDeLugar('a', 'la nota', ubicacionId: _depto)],
      );
      await _montarPestana(tester, repo: repo);

      expect(find.text('No pudimos leer las notas del depto en tu teléfono.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await asentarLugar(tester);
      expect(find.text('la nota'), findsOneWidget);
    });

    testWidgets('dado un lugar de baja, la pestaña del depto se ve pero no se escribe', (
      tester,
    ) async {
      await _montarPestana(tester, repo: _repoCon([('a', 'la nota')]), soloLectura: true);

      expect(find.text('la nota'), findsOneWidget);
      expect(find.text('+ Nota del depto'), findsNothing);
      expect(find.byKey(ClavesNotasDelLugar.soloLectura), findsOneWidget);
    });
  });

  group('11N·06 lista de deptos con el principio de la nota', () {
    Espacio depto(String id, String numero) => Espacio(
      id: id,
      ubicacionId: 'ubi-1',
      numeroDepto: numero,
      auditoria: Auditoria(createdAt: DateTime.utc(2026, 10), updatedAt: DateTime.utc(2026, 10)),
    );

    Future<void> montarFila(
      WidgetTester tester,
      ResumenDelDepto? resumen, {
      double escala = 1,
      Size tamano = const Size(390, 844),
    }) async {
      fijarTamanoLugar(tester, tamano);
      await tester.pumpWidget(
        MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Scaffold(
            body: FilaDeptoDeLaCasa(
              espacio: depto('e-3b', '3B'),
              resumen: resumen,
              detalle: 'Sin visita',
              alTocar: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('dado un depto con nota, su fila dice «✎» y el principio de la nota', (
      tester,
    ) async {
      await montarFila(tester, ResumenDelDepto(notaMasNueva: 'timbre roto, tocar fuerte'));

      expect(find.text('✎ timbre roto, tocar fuerte'), findsOneWidget);
      expect(find.text('Sin visita'), findsOneWidget, reason: 'el estado sigue a la vista');
    });

    testWidgets('dado un depto sin nota, o con la nota en blanco, la fila no dice nada de notas', (
      tester,
    ) async {
      await montarFila(tester, ResumenDelDepto());
      expect(find.byKey(ClavesDeptosDeLaCasa.nota('e-3b')), findsNothing);

      await montarFila(tester, ResumenDelDepto(notaMasNueva: '   '));
      expect(find.byKey(ClavesDeptosDeLaCasa.nota('e-3b')), findsNothing);

      await montarFila(tester, null);
      expect(find.byKey(ClavesDeptosDeLaCasa.nota('e-3b')), findsNothing);
    });

    testWidgets(
      'dado una nota larga o de varios renglones, la fila muestra una sola línea cortada',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final larga = 'Portero de 8 a 12.\nDespués de las 12 tocar desde la calle. ' * 20;
        await montarFila(tester, ResumenDelDepto(notaMasNueva: larga));

        final texto = tester.widget<Text>(find.byKey(ClavesDeptosDeLaCasa.nota('e-3b')));
        expect(texto.maxLines, 1);
        expect(texto.overflow, TextOverflow.ellipsis);
        expect(tester.takeException(), isNull);
        // El lector dice la fila con lo que tiene.
        expect(find.bySemanticsLabel(RegExp('Depto 3B.*Nota: Portero de 8 a 12')), findsOneWidget);
        semantica.dispose();
      },
    );

    testWidgets('dado texto 2x en 320 dp, la fila con nota no desborda', (tester) async {
      await montarFila(
        tester,
        ResumenDelDepto(estado: EstadoCasa.cobranzaPendiente, notaMasNueva: 'timbre roto'),
        escala: 2,
        tamano: const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('✎ timbre roto'), findsOneWidget);
    });
  });
}
