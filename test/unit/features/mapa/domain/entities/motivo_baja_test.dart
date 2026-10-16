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

    test('paraMostrar devuelve el motivo guardado y, para una unión de duplicados, «Unida a otra '
        'ubicación» (nunca el código ni el uuid)', () {
      expect(MotivosBaja.paraMostrar('Ya no existe'), 'Ya no existe');
      expect(MotivosBaja.paraMostrar('  Ya no existe '), 'Ya no existe');
      expect(MotivosBaja.paraMostrar('duplicado_de_ub-a'), 'Unida a otra ubicación');
      expect(MotivosBaja.paraMostrar('  duplicado_de_ub-a '), MotivosBaja.unidaAOtra);
      expect(MotivosBaja.paraMostrar(null), isNull);
      expect(MotivosBaja.paraMostrar(''), isNull);
    });

    test('un texto libre que solo contiene el prefijo en el medio sí se muestra', () {
      expect(MotivosBaja.paraMostrar('era duplicado_de_otra'), 'era duplicado_de_otra');
    });

    test('conservadaDe devuelve el uuid de la ubicación que se conservó, solo de una unión', () {
      expect(MotivosBaja.conservadaDe('duplicado_de_ub-a'), 'ub-a');
      expect(MotivosBaja.conservadaDe('  duplicado_de_ub-a '), 'ub-a');
      expect(MotivosBaja.conservadaDe('duplicado_de_'), isNull);
      expect(MotivosBaja.conservadaDe('era duplicado_de_otra'), isNull);
      expect(MotivosBaja.conservadaDe('Ya no existe'), isNull);
      expect(MotivosBaja.conservadaDe(null), isNull);
    });

    test('esUnion es verdadero solo con el prefijo exacto al principio del motivo', () {
      expect(MotivosBaja.esUnion('duplicado_de_ub-a'), isTrue);
      expect(MotivosBaja.esUnion('  duplicado_de_ub-a  '), isTrue);
      expect(MotivosBaja.esUnion('duplicado_de_'), isTrue);
      expect(MotivosBaja.esUnion('era duplicado_de_otra'), isFalse);
      expect(MotivosBaja.esUnion('duplicado de la casa'), isFalse);
      expect(MotivosBaja.esUnion('Duplicado_de_ub-a'), isFalse);
      expect(MotivosBaja.esUnion('Ya no existe'), isFalse);
      expect(MotivosBaja.esUnion(''), isFalse);
      expect(MotivosBaja.esUnion(null), isFalse);
    });
  });
}
