// Las notas borradas se quedan 90 días en «Ver borradas» y cada una dice cuándo se va (HU-UBI-012,
// vista 32E, artboard E·05; decisión de Cristian del 27/10, #509). «Hoy» es el 22/10/2026 a las 15:00.
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_persona_falsos.dart';
import '../../helpers/nota_ubicacion_falsos.dart';
import 'notas_lugar_arnes.dart';
import 'notas_persona_arnes.dart';

void main() {
  // Borrada hoy a las 14:30: 22/10 + 90 días = 20/01 (el año siguiente).
  final borradaHoy = DateTime(2026, 10, 22, 14, 30);
  // Borrada el 05/10: se va el 03/01.
  final borradaEl0510 = DateTime(2026, 10, 5, 9);
  // Borrada el 24/07 a las 16:00: se va hoy mismo a las 16:00 (todavía está a las 15:00).
  final borradaSeVaHoy = DateTime(2026, 7, 24, 16);
  // Borrada el 24/07 a las 14:00: se fue hoy a las 14:00 (ya pasó de los 90 días).
  final borradaSeFue = DateTime(2026, 7, 24, 14);

  NotaPersonaRepositorioFalso repoCon({
    ContextoNotasPersona contexto = const ContextoNotasPersona(nombre: 'María'),
  }) => NotaPersonaRepositorioFalso(
    contexto: contexto,
    notas: [
      notaDePrueba('hoy', 'Borrada de hoy.', borrada: borradaHoy),
      notaDePrueba('octubre', 'Borrada de octubre.', creada: borradaEl0510, borrada: borradaEl0510),
      notaDePrueba('activa', 'Sigue activa.', creada: DateTime(2026, 10, 20, 9)),
    ],
  );

  Future<void> abrirBorradas(WidgetTester tester, int cantidad) async {
    await tester.tap(find.text('Ver borradas ($cantidad)'));
    await asentar(tester);
  }

  group('E·05 · «Se borra el …»', () {
    testWidgets('dadas notas borradas, cuando abro «Ver borradas», cada una dice cuándo se va', (
      tester,
    ) async {
      await montarNotas(tester, repo: repoCon());
      await abrirBorradas(tester, 2);

      expect(find.text('Se borra el 20/01'), findsOneWidget);
      expect(find.text('Se borra el 03/01'), findsOneWidget);
      expect(find.byKey(ClavesNotas.seBorraEl), findsNWidgets(2));
      expect(find.text('Restaurar'), findsNWidgets(2));
    });

    testWidgets('dado que la fecha cruza de año, se escribe solo el día y el mes', (tester) async {
      await montarNotas(tester, repo: repoCon());
      await abrirBorradas(tester, 2);

      expect(find.textContaining('2027'), findsNothing);
      expect(find.textContaining('/27'), findsNothing);
    });

    testWidgets('dada una nota que se va hoy a las 16:00, a las 15:00 todavía está y dice «hoy»', (
      tester,
    ) async {
      final repo = NotaPersonaRepositorioFalso(
        notas: [notaDePrueba('b', 'Última hora.', creada: borradaSeVaHoy, borrada: borradaSeVaHoy)],
      );
      await montarNotas(tester, repo: repo);
      await abrirBorradas(tester, 1);

      expect(find.text('Última hora.'), findsOneWidget);
      expect(find.text('Se borra el 22/10'), findsOneWidget);
    });

    testWidgets('dada una nota que ya pasó de los 90 días, no se cuenta ni se muestra', (
      tester,
    ) async {
      final repo = NotaPersonaRepositorioFalso(
        notas: [
          notaDePrueba('vencida', 'Pasó el plazo.', creada: borradaSeFue, borrada: borradaSeFue),
          notaDePrueba('reciente', 'Todavía está.', borrada: borradaHoy),
        ],
      );
      await montarNotas(tester, repo: repo);

      expect(find.text('Ver borradas (1)'), findsOneWidget);
      await abrirBorradas(tester, 1);
      expect(find.text('Todavía está.'), findsOneWidget);
      expect(find.text('Pasó el plazo.'), findsNothing);
    });

    testWidgets('dadas solo notas vencidas, «Ver borradas» no aparece', (tester) async {
      final repo = NotaPersonaRepositorioFalso(
        notas: [notaDePrueba('vencida', 'Pasó el plazo.', borrada: borradaSeFue)],
      );
      await montarNotas(tester, repo: repo);

      expect(find.textContaining('Ver borradas'), findsNothing);
    });

    testWidgets('dado que se vence una nota con «Ver borradas» abierto, desaparece al refrescar', (
      tester,
    ) async {
      var hora = DateTime(2026, 7, 24, 15);
      final repo = NotaPersonaRepositorioFalso(
        notas: [
          notaDePrueba('b1', 'Pasa el plazo.', creada: borradaSeFue, borrada: borradaSeFue),
          notaDePrueba(
            'b2',
            'Se queda.',
            creada: DateTime(2026, 7, 25, 12),
            borrada: DateTime(2026, 7, 25, 12),
          ),
        ],
      );
      await montarNotas(tester, repo: repo, reloj: () => hora);
      await abrirBorradas(tester, 2);
      expect(find.text('Pasa el plazo.'), findsOneWidget);

      // Pasan los 90 días (el reloj sigue de largo) y la lista se vuelve a armar con un cambio.
      hora = DateTime(2026, 10, 22, 15, 1);
      await repo.restaurar(id: 'b2', ahora: hora);
      await asentar(tester);

      expect(find.text('Pasa el plazo.'), findsNothing);
      expect(find.text('No hay notas borradas.'), findsOneWidget);
    });

    testWidgets('dada una persona en solo lectura, las borradas dicen cuándo se van y no se '
        'restauran', (tester) async {
      final repo = repoCon(
        contexto: const ContextoNotasPersona(
          nombre: 'María',
          causa: CausaSoloLectura.personaDeBaja,
        ),
      );
      await montarNotas(tester, repo: repo);
      await abrirBorradas(tester, 2);

      expect(find.text('Se borra el 20/01'), findsOneWidget);
      expect(find.text('Restaurar'), findsNothing);
    });

    testWidgets('dado un lector de pantalla, la nota lee su fecha, su texto y cuándo se va', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarNotas(tester, repo: repoCon(), lector: true);
      await abrirBorradas(tester, 2);

      expect(
        find.bySemanticsLabel(
          RegExp(r'^hoy a las 14:20\. Borrada de hoy\.\. Se borra el 20/01\.$'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^el 05/10\. Borrada de octubre\.\. Se borra el 03/01\.$')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^Restaurar la nota del 05/10$')), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('dado «Restaurar», la nota vuelve a la lista y ya no figura como borrada', (
      tester,
    ) async {
      final repo = repoCon();
      await montarNotas(tester, repo: repo);
      await abrirBorradas(tester, 2);

      await tester.tap(find.bySemanticsLabel(RegExp('^Restaurar la nota')).first);
      await asentar(tester);

      expect(repo.cuantas('restaurar'), 1);
      expect(find.byKey(ClavesNotas.seBorraEl), findsOneWidget);
    });

    testWidgets('dado el texto al 200 % en un teléfono chico, el plazo se lee y nada se desborda', (
      tester,
    ) async {
      await montarNotas(tester, repo: repoCon(), escala: 2, tamano: const Size(320, 568));
      await tester.scrollUntilVisible(
        find.text('Ver borradas (2)'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Ver borradas (2)'));
      await asentar(tester);
      await tester.tap(find.text('Ver borradas (2)'));
      await asentar(tester);

      await tester.scrollUntilVisible(
        find.text('Se borra el 03/01'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Se borra el 03/01'), findsOneWidget);
    });

    testWidgets('dado un texto de nota muy largo y el 200 %, el plazo queda debajo y sin recorte', (
      tester,
    ) async {
      final repo = NotaPersonaRepositorioFalso(
        notas: [notaDePrueba('larga', 'palabra ' * 120, borrada: borradaHoy)],
      );
      await montarNotas(tester, repo: repo, escala: 2, tamano: const Size(320, 568));
      await tester.scrollUntilVisible(
        find.text('Ver borradas (1)'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Ver borradas (1)'));
      await asentar(tester);
      await tester.tap(find.text('Ver borradas (1)'));
      await asentar(tester);

      await tester.scrollUntilVisible(
        find.text('Se borra el 20/01'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      final texto = tester.getRect(find.textContaining('palabra').first);
      final plazo = tester.getRect(find.text('Se borra el 20/01'));
      expect(plazo.top, greaterThanOrEqualTo(texto.bottom));
    });
  });

  group('las notas de un lugar (vista 39) no tienen ese plazo', () {
    testWidgets('dado un lugar con una nota borrada hace 200 días, sigue y no dice «Se borra»', (
      tester,
    ) async {
      final repo = NotaUbicacionRepositorioFalso(
        notas: [
          notaDeLugar(
            'vieja',
            'Portón roto.',
            creada: DateTime(2026, 1, 1),
            borrada: DateTime(2026, 1, 2),
          ),
        ],
      );
      await montarPestanaLugar(tester, repo: repo);

      expect(find.text('Ver borradas (1)'), findsOneWidget);
      await tester.ensureVisible(find.text('Ver borradas (1)'));
      await tester.tap(find.text('Ver borradas (1)'));
      await asentarLugar(tester);

      expect(find.text('Portón roto.'), findsOneWidget);
      expect(find.textContaining('Se borra el'), findsNothing);
    });
  });
}
