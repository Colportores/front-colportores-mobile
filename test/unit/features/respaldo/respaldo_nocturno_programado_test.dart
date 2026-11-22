// Cuándo queda programado el respaldo de la noche (HU-SYNC-005, #583): con Drive conectado, y sin
// él no se despierta al teléfono para nada.
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/programador_respaldo_nocturno.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_automatico_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _conectada = DriveConectada(email: 'ana@example.com', cuentaId: 'g-1');

class _EstadoControlable extends EstadoRespaldoDriveNotifier {
  _EstadoControlable(this._inicial);

  final EstadoRespaldoDrive _inicial;

  @override
  Future<EstadoRespaldoDrive> build() async => _inicial;

  void poner(EstadoRespaldoDrive estado) => state = AsyncData(estado);
}

final class _Programador implements ProgramadorDeRespaldoNocturno {
  final llamadas = <String>[];

  @override
  Future<void> programar() async => llamadas.add('programar');

  @override
  Future<void> cancelar() async => llamadas.add('cancelar');
}

void main() {
  late _Programador programador;

  Future<(ProviderContainer, _EstadoControlable)> armar(EstadoRespaldoDrive inicial) async {
    final estado = _EstadoControlable(inicial);
    final container = ProviderContainer(
      overrides: [
        estadoRespaldoDriveProvider.overrideWith(() => estado),
        programadorDeRespaldoNocturnoProvider.overrideWithValue(programador),
      ],
    );
    addTearDown(container.dispose);
    container.read(respaldoNocturnoProgramadoProvider);
    await container.read(estadoRespaldoDriveProvider.future);
    await pumpEventQueue();
    return (container, estado);
  }

  setUp(() => programador = _Programador());

  test('mientras lee el estado no toca nada', () async {
    final container = ProviderContainer(
      overrides: [
        estadoRespaldoDriveProvider.overrideWith(() => _EstadoControlable(_conectada)),
        programadorDeRespaldoNocturnoProvider.overrideWithValue(programador),
      ],
    );
    addTearDown(container.dispose);

    container.read(respaldoNocturnoProgramadoProvider);

    expect(programador.llamadas, isEmpty);
  });

  test('Drive conectado al abrir la app: lo deja programado', () async {
    await armar(_conectada);

    expect(programador.llamadas, ['programar']);
  });

  test(
    'Drive sin espacio sigue programado: el permiso está vigente y la próxima noche puede',
    () async {
      await armar(const DriveSinEspacio(email: 'a@b.c', cuentaId: 'g'));

      expect(programador.llamadas, ['programar']);
    },
  );

  test('sin Drive conectado lo saca: no despierta al teléfono sin nada que subir', () async {
    await armar(const DriveSinConectar());

    expect(programador.llamadas, ['cancelar']);
  });

  test('con el permiso revocado lo saca hasta que reconecte', () async {
    final (_, estado) = await armar(_conectada);
    estado.poner(const DrivePermisoRevocado(email: 'a@b.c', cuentaId: 'g'));
    await pumpEventQueue();

    expect(programador.llamadas, ['programar', 'cancelar']);
  });

  test('al conectar Drive lo programa; al desconectar, lo saca', () async {
    final (_, estado) = await armar(const DriveSinConectar());

    estado.poner(_conectada);
    await pumpEventQueue();
    estado.poner(const DriveSinConectar());
    await pumpEventQueue();

    expect(programador.llamadas, ['cancelar', 'programar', 'cancelar']);
  });
}
