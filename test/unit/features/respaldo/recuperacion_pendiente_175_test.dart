// HU-SYNC-006 (#175) — Cuándo la app le ofrece el asistente de recuperación: un teléfono sin datos,
// una vez por usuario, y nunca sobre algo que no se pudo mirar.
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/recuperacion_pendiente_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/recuperacion_arnes.dart';

void main() {
  late ArnesRecuperacion arnes;

  ProviderContainer armar({bool conSesion = true}) {
    final c = ProviderContainer(
      overrides: [
        ...arnes.overridesDelAsistente,
        sesionProvider.overrideWith(
          () => SesionFijaParaRecuperacion(conSesion ? sesionDePrueba() : null),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<bool> pendiente(ProviderContainer c) async {
    await c.read(sesionProvider.future);
    return c.read(recuperacionPendienteProvider.future);
  }

  setUp(() => arnes = ArnesRecuperacion());

  test('por defecto el asistente está apagado y no se ofrece nunca', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(c.read(asistenteDeRecuperacionHabilitadoProvider), isFalse);
  });

  test('un teléfono sin datos que no lo resolvió: se ofrece', () async {
    expect(await pendiente(armar()), isTrue);
    expect(arnes.resuelta.usuarios, isEmpty, reason: 'ofrecer no lo da por resuelto');
  });

  test('ya resuelto para este usuario: no se ofrece y ni siquiera mira la base', () async {
    arnes.resuelta.usuarios.add(usuarioDePrueba);

    expect(await pendiente(armar()), isFalse);
    expect(arnes.lector.miradas, 0);
  });

  test('lo resolvió otra persona del mismo teléfono: a esta se le ofrece', () async {
    arnes.resuelta.usuarios.add('u-otra');

    expect(await pendiente(armar()), isTrue);
  });

  test('con datos ya guardados no se ofrece y queda anotado: nunca pisa lo que hay', () async {
    arnes.lector.sinDatos = false;

    expect(await pendiente(armar()), isFalse);
    expect(arnes.resuelta.usuarios, {usuarioDePrueba});
  });

  test('sin sesión no hay a quién ofrecérselo', () async {
    expect(await pendiente(armar(conSesion: false)), isFalse);
  });

  test('si no se pudo leer la marca, no se ofrece y la app sigue', () async {
    arnes.resuelta.errorAlLeer = StateError('almacén roto');

    expect(await pendiente(armar()), isFalse);
  });

  test('si no se pudo mirar la base, no se ofrece (nunca sobre algo que no se vio)', () async {
    arnes.lector.errorAlMirar = StateError('base cerrada');

    expect(await pendiente(armar()), isFalse);
    expect(arnes.resuelta.usuarios, isEmpty);
  });

  test('terminar: se anota, deja de ofrecerse y no se vuelve a mirar la base', () async {
    final c = armar();
    expect(await pendiente(c), isTrue);

    await c.read(recuperacionPendienteProvider.notifier).terminar();

    expect(c.read(recuperacionPendienteProvider).value, isFalse);
    expect(arnes.resuelta.usuarios, {usuarioDePrueba});
    expect(arnes.lector.miradas, 1);
  });

  test('es estable: aunque la recuperación llene la base, el asistente no se va solo', () async {
    final c = armar();
    expect(await pendiente(c), isTrue);

    arnes.lector.sinDatos = false;

    expect(c.read(recuperacionPendienteProvider).value, isTrue);
    expect(arnes.lector.miradas, 1);
  });
}
