// Cuándo la vista 25 dice «nunca» y avisa que los datos no tienen respaldo (25-11): lo que dice la
// fila «Cuenta Drive» de Configuración, sin afirmar nada mientras no se sabe.
import 'dart:async';

import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:colportores_mobile/features/sincronizacion/presentation/providers/sincronizacion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _DriveFalso extends EstadoRespaldoDriveNotifier {
  _DriveFalso(this._estado);

  final Future<EstadoRespaldoDrive> Function() _estado;

  @override
  Future<EstadoRespaldoDrive> build() => _estado();
}

ProviderContainer _con(Future<EstadoRespaldoDrive> Function() estado) {
  final c = ProviderContainer(
    overrides: [estadoRespaldoDriveProvider.overrideWith(() => _DriveFalso(estado))],
  );
  addTearDown(c.dispose);
  return c;
}

Future<bool> _configurado(EstadoRespaldoDrive estado) async {
  final c = _con(() async => estado);
  await c.read(estadoRespaldoDriveProvider.future);
  return c.read(respaldoConfiguradoProvider);
}

void main() {
  group('respaldoConfiguradoProvider', () {
    test('should say there is no backup when the Drive was never connected', () async {
      expect(await _configurado(const DriveSinConectar()), isFalse);
    });

    test('should say there is no backup when the permission was taken away', () async {
      expect(
        await _configurado(const DrivePermisoRevocado(email: 'a@b.c', cuentaId: 'g-1')),
        isFalse,
      );
    });

    test('should say there is a backup when the Drive is connected', () async {
      expect(await _configurado(const DriveConectada(email: 'a@b.c', cuentaId: 'g-1')), isTrue);
    });

    test('should not warn about a missing backup when the Drive has no space left', () async {
      expect(await _configurado(const DriveSinEspacio(email: 'a@b.c', cuentaId: 'g-1')), isTrue);
    });

    test('should not warn when the person still has to choose between two accounts', () async {
      expect(
        await _configurado(
          const DriveCuentaPorConfirmar(
            email: 'nueva@b.c',
            cuentaId: 'g-2',
            anteriorEmail: 'a@b.c',
            anteriorCuentaId: 'g-1',
          ),
        ),
        isTrue,
      );
    });

    test('should not claim anything while the state is still being read', () {
      final c = _con(() => Completer<EstadoRespaldoDrive>().future);

      expect(c.read(respaldoConfiguradoProvider), isTrue);
    });

    test('should not claim anything when the state could not be read', () async {
      final c = _con(() async => throw StateError('el almacén no se deja leer'));
      await expectLater(c.read(estadoRespaldoDriveProvider.future), throwsStateError);

      expect(c.read(respaldoConfiguradoProvider), isTrue);
    });
  });
}
