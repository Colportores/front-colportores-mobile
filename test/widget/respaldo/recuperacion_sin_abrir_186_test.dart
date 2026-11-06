// HU-SYNC-006 (#186, decisión del 04/11 de #610 P1, «Varios resp.») — Cuando la contraseña abre solo
// algunos de los respaldos, la pantalla de «Tus datos están de vuelta» (34·08) y la de «Recuperamos casi
// todo» (34·07) dicen cuántos no se pudieron abrir y que siguen en Drive, sin tocar. Y no lo dicen si
// se abrieron todos.
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/recuperacion_arnes.dart';

RespaldoEnDrive _respaldo(String llave, {int dia = 22}) => RespaldoEnDrive(
  llave: llave,
  fecha: DateTime(2026, 10, dia, 3, 10),
  partes: 5,
  bytes: 10 * 1024 * 1024,
  completo: true,
  tieneLlave: true,
);

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tocar(WidgetTester tester, Finder objetivo) async {
  await tester.ensureVisible(objetivo);
  await tester.tap(objetivo);
  await _asentar(tester);
}

Future<void> _recuperar(WidgetTester tester, ArnesRecuperacion arnes) async {
  await abrirAsistente(tester, arnes);
  await tester.tap(cta);
  await _asentar(tester);
  await tester.enterText(campoContrasena, 'la-de-antes');
  await _asentar(tester);
  await tester.tap(cta);
  await _asentar(tester);
}

final _aviso = find.byKey(const Key('recuperacion_sin_abrir'));

void main() {
  late ArnesRecuperacion arnes;

  setUp(() {
    arnes = ArnesRecuperacion();
    arnes.servicio.busqueda = VariosRespaldosEnDrive([_respaldo('a'), _respaldo('b', dia: 15)]);
  });

  group('34·08: lo que no se pudo abrir', () {
    testWidgets('con uno sin abrir, lo dice en singular y que sigue en Drive', (tester) async {
      arnes.servicio.resultado = RecuperacionHecha(informeDePrueba(sinAbrir: 1));
      await _recuperar(tester, arnes);

      expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
      expect(_aviso, findsOneWidget);
      expect(
        find.text(
          'No pudimos abrir 1 respaldo con tu contraseña. Sigue en tu Google Drive, sin tocar.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('con varios sin abrir, lo dice en plural', (tester) async {
      arnes.servicio.resultado = RecuperacionHecha(informeDePrueba(sinAbrir: 3));
      await _recuperar(tester, arnes);

      expect(
        find.text(
          'No pudimos abrir 3 respaldos con tu contraseña. Siguen en tu Google Drive, sin tocar.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('si se abrieron todos, no dice nada de más', (tester) async {
      arnes.servicio.resultado = RecuperacionHecha(informeDePrueba());
      await _recuperar(tester, arnes);

      expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
      expect(_aviso, findsNothing);
    });

    testWidgets('con texto al doble y un teléfono chico no se desborda', (tester) async {
      arnes.servicio.resultado = RecuperacionHecha(informeDePrueba(sinAbrir: 12));
      await abrirAsistente(tester, arnes, tamano: const Size(360, 740), escala: 2);
      await _tocar(tester, cta);
      await tester.ensureVisible(campoContrasena);
      await tester.enterText(campoContrasena, 'la-de-antes');
      await _asentar(tester);
      await _tocar(tester, cta);

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_aviso);
      expect(_aviso, findsOneWidget);
    });
  });

  group('34·07: recuperación parcial con respaldos sin abrir', () {
    testWidgets('el aviso también aparece cuando una parte dañada cortó la cadena', (tester) async {
      arnes.servicio.resultado = RecuperacionHecha(
        informeDePrueba(parcial: true, restauradas: 3, totales: 5, sinAbrir: 2),
      );
      await _recuperar(tester, arnes);

      expect(tester.widget<Text>(titulo).data, 'Recuperamos casi todo');
      expect(_aviso, findsOneWidget);
      expect(
        find.text(
          'No pudimos abrir 2 respaldos con tu contraseña. Siguen en tu Google Drive, sin tocar.',
        ),
        findsOneWidget,
      );
    });
  });
}
