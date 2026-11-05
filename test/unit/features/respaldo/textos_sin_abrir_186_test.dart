// HU-SYNC-006 (#186, decisión del 04/11 de #610 P1) — El aviso de los respaldos que la contraseña no
// abrió: singular para uno, plural desde dos, y nunca «(s)» ni «(n)».
import 'package:colportores_mobile/features/respaldo/presentation/textos_recuperacion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('con uno: «respaldo» y «Sigue», en singular', () {
    expect(
      TextosRecuperacion.respaldosSinAbrir(1),
      'No pudimos abrir 1 respaldo con tu contraseña. Sigue en tu Google Drive, sin tocar.',
    );
  });

  test('con dos o más: «respaldos» y «Siguen», en plural', () {
    expect(
      TextosRecuperacion.respaldosSinAbrir(2),
      'No pudimos abrir 2 respaldos con tu contraseña. Siguen en tu Google Drive, sin tocar.',
    );
    expect(
      TextosRecuperacion.respaldosSinAbrir(12),
      'No pudimos abrir 12 respaldos con tu contraseña. Siguen en tu Google Drive, sin tocar.',
    );
  });

  test('ninguna cantidad deja «(s)» ni «(n)» en el texto', () {
    for (final n in [1, 2, 3, 10, 100]) {
      expect(TextosRecuperacion.respaldosSinAbrir(n), isNot(matches(r'\((s|n)\)')));
    }
  });
}
