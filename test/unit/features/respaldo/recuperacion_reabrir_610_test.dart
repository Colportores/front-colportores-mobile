// HU-SYNC-006 (#610, «Recup. luego») — Volver a abrir el asistente de recuperación desde
// Configuración: solo mientras el teléfono no tenga nada cargado, y nunca sobre algo que no se vio.
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/recuperacion_pendiente_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/recuperacion_arnes.dart';

void main() {
  late ArnesRecuperacion arnes;

  ProviderContainer armar({bool conSesion = true, bool habilitado = true}) {
    arnes.habilitado = habilitado;
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

  Future<void> yaResuelto(ProviderContainer c) async {
    arnes.resuelta.usuarios.add(usuarioDePrueba);
    await c.read(sesionProvider.future);
    expect(await c.read(recuperacionPendienteProvider.future), isFalse);
  }

  setUp(() => arnes = ArnesRecuperacion());

  group('reabrir()', () {
    test('dado un teléfono sin datos que ya resolvió el asistente, lo vuelve a ofrecer', () async {
      final c = armar();
      await yaResuelto(c);

      final resultado = await c.read(recuperacionPendienteProvider.notifier).reabrir();

      expect(resultado, ReaperturaDeLaRecuperacion.abierta);
      expect(c.read(recuperacionPendienteProvider).value, isTrue);
      expect(arnes.resuelta.usuarios, {usuarioDePrueba}, reason: 'abrir no borra la marca');
    });

    test('con datos cargados no se abre y no se toca nada', () async {
      final c = armar();
      await yaResuelto(c);
      arnes.lector.sinDatos = false;

      final resultado = await c.read(recuperacionPendienteProvider.notifier).reabrir();

      expect(resultado, ReaperturaDeLaRecuperacion.hayDatos);
      expect(c.read(recuperacionPendienteProvider).value, isFalse);
    });

    test('si no se pudo mirar la base, no se abre (nunca sobre algo que no se vio)', () async {
      final c = armar();
      await yaResuelto(c);
      arnes.lector.errorAlMirar = StateError('base cerrada');

      final resultado = await c.read(recuperacionPendienteProvider.notifier).reabrir();

      expect(resultado, ReaperturaDeLaRecuperacion.noSePudoMirar);
      expect(c.read(recuperacionPendienteProvider).value, isFalse);
    });

    test('con el asistente apagado no se abre y ni mira la base', () async {
      final c = armar(habilitado: false);
      await c.read(sesionProvider.future);
      await c.read(recuperacionPendienteProvider.future);
      final miradasAlArmar = arnes.lector.miradas;

      final resultado = await c.read(recuperacionPendienteProvider.notifier).reabrir();

      expect(resultado, ReaperturaDeLaRecuperacion.noDisponible);
      expect(arnes.lector.miradas, miradasAlArmar);
    });

    test('sin sesión no hay a quién abrírselo', () async {
      final c = armar(conSesion: false);
      await c.read(sesionProvider.future);
      await c.read(recuperacionPendienteProvider.future);

      final resultado = await c.read(recuperacionPendienteProvider.notifier).reabrir();

      expect(resultado, ReaperturaDeLaRecuperacion.noDisponible);
    });

    test('abierto de nuevo, terminarlo lo anota y la raíz sigue', () async {
      final c = armar();
      await yaResuelto(c);
      await c.read(recuperacionPendienteProvider.notifier).reabrir();

      await c.read(recuperacionPendienteProvider.notifier).terminar();

      expect(c.read(recuperacionPendienteProvider).value, isFalse);
      expect(arnes.resuelta.marcas, 1);
    });

    test('abrir dos veces seguidas no deja nada a medias', () async {
      final c = armar();
      await yaResuelto(c);
      final notificador = c.read(recuperacionPendienteProvider.notifier);

      final resultados = await Future.wait([notificador.reabrir(), notificador.reabrir()]);

      expect(resultados, everyElement(ReaperturaDeLaRecuperacion.abierta));
      expect(c.read(recuperacionPendienteProvider).value, isTrue);
    });
  });

  group('recuperarDespuesDisponibleProvider (la fila de Configuración)', () {
    test('se muestra con un teléfono sin datos', () async {
      final c = armar();
      await c.read(sesionProvider.future);

      expect(await c.read(recuperarDespuesDisponibleProvider.future), isTrue);
    });

    test('no se muestra con datos cargados', () async {
      final c = armar();
      await c.read(sesionProvider.future);
      arnes.lector.sinDatos = false;

      expect(await c.read(recuperarDespuesDisponibleProvider.future), isFalse);
    });

    test('no se muestra si no se pudo mirar la base', () async {
      final c = armar();
      await c.read(sesionProvider.future);
      arnes.lector.errorAlMirar = StateError('base cerrada');

      expect(await c.read(recuperarDespuesDisponibleProvider.future), isFalse);
    });

    test('no se muestra con el asistente apagado ni sin sesión', () async {
      final apagado = armar(habilitado: false);
      await apagado.read(sesionProvider.future);
      expect(await apagado.read(recuperarDespuesDisponibleProvider.future), isFalse);

      final sinSesion = armar(conSesion: false);
      await sinSesion.read(sesionProvider.future);
      expect(await sinSesion.read(recuperarDespuesDisponibleProvider.future), isFalse);
    });
  });
}
