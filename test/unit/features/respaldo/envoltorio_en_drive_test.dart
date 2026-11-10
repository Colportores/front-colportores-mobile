// La DEK envuelta con la contraseña viaja con el respaldo (ADR-006, HU-SYNC-006): sin ella el respaldo
// no se abre en un teléfono nuevo. Se sube junto a cada base, identificada por la llave de la cadena,
// y se vuelve a subir cuando cambia la contraseña. Nunca lanza.
import 'dart:convert';

import 'package:colportores_mobile/features/respaldo/data/services/envoltorio_en_drive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/testing.dart';

import '../../../helpers/logger_mudo.dart';

void main() {
  late FakeKeyEnvelopes drive;
  late String? local;
  late bool desactualizado;
  late bool sinDrive;
  late EnvoltorioEnDrive servicio;

  setUp(() {
    drive = FakeKeyEnvelopes();
    local = '{"v":1,"alg":"x"}';
    desactualizado = false;
    sinDrive = false;
    servicio = EnvoltorioEnDrive(
      envoltorios: () async => sinDrive ? null : drive,
      keyId: () async => 'llave-1',
      envoltorioLocal: () async => local,
      desactualizado: () async => desactualizado,
      logger: loggerMudo(),
    );
  });

  test('sube el envoltorio local con la llave de la cadena', () async {
    expect(await servicio.sincronizar(), ResultadoEnvoltorio.subido);

    expect(utf8.decode(drive.guardados['llave-1']!), '{"v":1,"alg":"x"}');
  });

  test('si ya es el mismo, no lo vuelve a subir: no cuesta una subida por respaldo', () async {
    await servicio.sincronizar();

    expect(await servicio.sincronizar(), ResultadoEnvoltorio.alDia);
    expect(drive.subidas, 1);
  });

  test('cuando cambia la contraseña el envoltorio local es otro y se vuelve a subir', () async {
    await servicio.sincronizar();
    local = '{"v":1,"alg":"x","sal":"nueva"}';

    expect(await servicio.sincronizar(), ResultadoEnvoltorio.subido);

    expect(utf8.decode(drive.guardados['llave-1']!), contains('nueva'));
    expect(drive.subidas, 2);
  });

  test('sin Drive conectado no hace nada', () async {
    sinDrive = true;

    expect(await servicio.sincronizar(), ResultadoEnvoltorio.omitido);
    expect(drive.subidas, 0);
  });

  test(
    'un envoltorio marcado como desactualizado no se sube: no abriría con la contraseña vigente',
    () async {
      desactualizado = true;

      expect(await servicio.sincronizar(), ResultadoEnvoltorio.omitido);
      expect(drive.subidas, 0);
    },
  );

  test('sin envoltorio local no hay nada que subir', () async {
    local = null;

    expect(await servicio.sincronizar(), ResultadoEnvoltorio.omitido);
  });

  test('si Drive no contesta, no lanza: queda para el próximo respaldo', () async {
    drive.failOnPut = true;

    expect(await servicio.sincronizar(), ResultadoEnvoltorio.fallido);

    drive.failOnPut = false;
    expect(await servicio.sincronizar(), ResultadoEnvoltorio.subido);
  });

  test('si el almacén falla al leer el envoltorio, tampoco lanza', () async {
    final roto = EnvoltorioEnDrive(
      envoltorios: () async => drive,
      keyId: () async => throw StateError('sin DEK'),
      envoltorioLocal: () async => local,
      desactualizado: () async => false,
      logger: loggerMudo(),
    );

    expect(await roto.sincronizar(), ResultadoEnvoltorio.fallido);
  });
}
