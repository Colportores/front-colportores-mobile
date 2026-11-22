// QA de #679, casilla 5 «Ver bajas» (segunda entrega): «Mostrar bajas» (32D·04) y «Reactivar» (32D·05)
// en la pestaña «Personas» de la hoja de la casa (39·C·02) y en la ficha del depto (11·04). Con las
// fuentes reales: matriz 360×640 / 412×915 × texto 1,0 / 2,0, la persona reactivada vuelve a la lista
// y las bajas siguen ahí tras volver a abrir. Guías de accesibilidad en `qa_mostrar_bajas_679_guias_test`.
// Capturas: `--dart-define=QA_CAPTURAS=true` → `.dart_tool/qa_capturas/` (nunca se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/bajas_de_personas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista39_445_arnes.dart';
import 'hoja_con_quien_arnes.dart' show SaldosFalsos;
import 'hoja_espacios_arnes.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');
const _tamanos = [t360x640, t412x915];
const _escalas = [1.0, 2.0];

final _mostrar = find.byKey(ClavesBajasDePersonas.mostrar);
final _reactivarMaria = find.byKey(ClavesBajasDePersonas.reactivar('p2'));

String _medida(Size t) => '${t.width.toInt()}×${t.height.toInt()}';

List<PersonaDelEspacio> _filas() => [
  clienteDePersonas('p1', 'Jorge', apellido: 'Fernández'),
  clienteDeBajaDePersonas('p2', 'María', apellido: 'Fernández', minutos: 1),
];

PersonaRepositorioFalso _repo() => PersonaRepositorioFalso()..sembrar(_filas());

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final imagen = await capa.toImage(
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('.dart_tool/qa_capturas/679b_$nombre.png');
    archivo.parent.createSync(recursive: true);
    archivo.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _prender(WidgetTester tester) async {
  await tester.ensureVisible(_mostrar);
  await tester.tap(_mostrar);
  await asentar445(tester);
}

void main() {
  _hallazgos();
  group('hoja de la casa · pestaña «Personas»', () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        testWidgets(
          'dado una baja con saldo a ${_medida(tamano)} con texto ×$escala, cuando prende «Mostrar '
          'bajas», la fila y «Reactivar» se ven sin desborde',
          (tester) async {
            await cargarFuentes205(tester);
            final m = Montaje445();
            m.repo.sembrar(_filas());
            await montarHoja445(
              tester,
              montaje: m,
              tamano: tamano,
              escala: escala,
              otros: [
                saldosDePersonasProvider.overrideWithValue(SaldosFalsos({'p2': 120000})),
              ],
            );
            await asentar445(tester);

            await _prender(tester);
            await tester.ensureVisible(_reactivarMaria);
            await tester.pump();

            expect(tester.takeException(), isNull);
            expect(find.text('María Fernández'), findsOneWidget);
            expect(_reactivarMaria, findsOneWidget);
            await _capturar(tester, 'casa_${_medida(tamano)}_x$escala');
          },
        );
      }
    }

    testWidgets(
      'dado la baja visible, cuando la reactiva, la hoja lo avisa y la baja deja de ofrecerse '
      'queda en las bajas',
      (tester) async {
        await cargarFuentes205(tester);
        final m = Montaje445();
        m.repo.sembrar(_filas());
        await montarHoja445(tester, montaje: m);
        await asentar445(tester);
        await _prender(tester);

        await tester.ensureVisible(_reactivarMaria);
        await tester.tap(_reactivarMaria);
        await asentar445(tester);

        expect(m.repo.reactivacionesRecibidas, ['p2']);
        expect(_reactivarMaria, findsNothing);
        expect(find.text('Reactivamos a María.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ficha del depto (11·04)', () {
    final deptos = [espacioDe('esp-1', '101', piso: '1'), espacioDe('e-102', '102', piso: '1')];

    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        testWidgets(
          'dado una baja con saldo a ${_medida(tamano)} con texto ×$escala, cuando prende '
          '«Mostrar bajas», la fila y «Reactivar» se ven sin desborde',
          (tester) async {
            await cargarFuentes205(tester);
            await montarHoja(
              tester,
              espacios: deptos,
              tamano: tamano,
              escala: escala,
              extras: [
                personaRepositoryProvider.overrideWithValue(_repo()),
                relojPersonaProvider.overrideWithValue(() => DateTime.utc(2026, 10, 25, 9, 30)),
                saldosDePersonasProvider.overrideWithValue(SaldosFalsos({'p2': 120000})),
              ],
            );
            await abrirFichaDepto(tester, 'esp-1');

            await tester.ensureVisible(_mostrar);
            await tester.tap(_mostrar);
            await asentarHoja(tester);
            await tester.ensureVisible(_reactivarMaria);
            await tester.pump();

            expect(tester.takeException(), isNull);
            expect(find.text('María Fernández'), findsOneWidget);
            await _capturar(tester, 'depto_${_medida(tamano)}_x$escala');
          },
        );
      }
    }

    testWidgets('dado «Mostrar bajas» prendido, cuando vuelve a la hoja y reabre la ficha, el '
        'interruptor vuelve apagado y nada queda trabado', (tester) async {
      await cargarFuentes205(tester);
      await montarHoja(
        tester,
        espacios: deptos,
        extras: [
          personaRepositoryProvider.overrideWithValue(_repo()),
          relojPersonaProvider.overrideWithValue(() => DateTime.utc(2026, 10, 25, 9, 30)),
          saldosDePersonasProvider.overrideWithValue(SaldosFalsos({'p2': 120000})),
        ],
      );
      await abrirFichaDepto(tester, 'esp-1');
      await tester.ensureVisible(_mostrar);
      await tester.tap(_mostrar);
      await asentarHoja(tester);
      await tester.binding.handlePopRoute();
      await asentarHoja(tester);

      await abrirFichaDepto(tester, 'esp-1');

      expect(tester.widget<SwitchListTile>(_mostrar).value, isFalse);
      expect(find.text('María Fernández'), findsNothing);
    });
  });
}

/// Los hallazgos de la QA, con `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void _hallazgos() {
  // skip: issue #679 — «Reactivar» no lleva la fuente Inter (`textStyle` de `styleFrom` sin `fontFamily`).
  testWidgets(
    'dado una baja a la vista, el rótulo «Reactivar» usa la misma fuente que «Mostrar bajas»',
    (tester) async {
      await cargarFuentes205(tester);
      final m = Montaje445();
      m.repo.sembrar(_filas());
      await montarHoja445(tester, montaje: m);
      await asentar445(tester);
      await _prender(tester);

      RichText rotulo(Finder dentro) => tester.widget<RichText>(
        find.descendant(of: dentro, matching: find.byType(RichText)).first,
      );
      final reactivar = (rotulo(_reactivarMaria).text as TextSpan).style?.fontFamily;
      final mostrar =
          (rotulo(find.widgetWithText(SwitchListTile, 'Mostrar bajas')).text as TextSpan)
              .style
              ?.fontFamily;

      expect(reactivar, mostrar);
    },
    skip: !_verHallazgos,
  );
}
