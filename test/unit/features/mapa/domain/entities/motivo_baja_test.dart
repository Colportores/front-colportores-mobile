// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_baja.dart';
import 'package:test/test.dart';

void main() {
  group('MotivosBaja', () {
    test('los motivos rápidos son los del canvas 09·01, en su orden, y «Otro» va aparte', () {
      expect(MotivosBaja.rapidos, ['Ya no existe', 'Está deshabitada', 'No quiere visitas']);
      expect(MotivosBaja.otro, 'Otro');
    });

    test('paraGuardar recorta los espacios y devuelve null si no queda nada', () {
      expect(MotivosBaja.paraGuardar('  Se mudaron  '), 'Se mudaron');
      expect(MotivosBaja.paraGuardar('   '), isNull);
      expect(MotivosBaja.paraGuardar(''), isNull);
      expect(MotivosBaja.paraGuardar(null), isNull);
    });

    test('paraMostrar devuelve el motivo guardado, pero no el de una unión de duplicados', () {
      expect(MotivosBaja.paraMostrar('Ya no existe'), 'Ya no existe');
      expect(MotivosBaja.paraMostrar('  Ya no existe '), 'Ya no existe');
      expect(MotivosBaja.paraMostrar('duplicado_de_ub-a'), isNull);
      expect(MotivosBaja.paraMostrar(null), isNull);
      expect(MotivosBaja.paraMostrar(''), isNull);
    });

    test('un texto libre que solo contiene el prefijo en el medio sí se muestra', () {
      expect(MotivosBaja.paraMostrar('era duplicado_de_otra'), 'era duplicado_de_otra');
    });
  });
}
