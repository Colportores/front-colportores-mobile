// HU-SYNC-006 (#610, «Recup. luego») — Volver a abrir el asistente de recuperación desde
// Configuración: solo mientras el teléfono no tenga nada cargado, y nunca sobre algo que no se vio.
// Abrirlo es reiniciar la raíz de la app (decisión de Cristian, 04/11, «Motor vivo»): se quita la marca
// de «resuelto» y se pide el reinicio; el arranque nuevo ofrece el asistente.
import 'package:colportores_mobile/core/arranque/reinicio_de_raiz.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/recuperacion_pendiente_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/recuperacion_arnes.dart';

void main() {
  late ArnesRecuperacion arnes;
  late int reinicios;

  ProviderContainer armar({bool conSesion = true, bool habilitado = true}) {
    arnes.habilitado = habilitado;
    final c = ProviderContainer(
      overrides: [
        ...arnes.overridesDelAsistente,
        reiniciarRaizProvider.overrideWithValue(() => reinicios++),
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

  setUp(() {
    arnes = ArnesRecuperacion();
    reinicios = 0;
  });

  group('reabrir()', () {
    test('dado un teléfono sin datos que ya resolvió el asistente, quita la marca y reinicia '
        'la app', () async {
      final c = armar();
      await yaResuelto(c);

      final resultado = await c.read(recuperacionPendienteProvider.notifier).reabrir();

      expect(resultado, ReaperturaDeLaRecuperacion.abierta);
      expect(reinicios, 1);
      expect(arnes.resuelta.usuarios, isEmpty, reason: 'el arranque nuevo lo vuelve a ofrecer');
    });

    test(
      'la raíz nueva (un contenedor nuevo) ofrece el asistente sin que nadie lo fuerce',
      () async {
        final c = armar();
        await yaResuelto(c);
        await c.read(recuperacionPendienteProvider.notifier).reabrir();

        final arranqueNuevo = armar();
        await arranqueNuevo.read(sesionProvider.future);

        expect(await arranqueNuevo.read(recuperacionPendienteProvider.future), isTrue);
      },
    );

    test(
      'no deja nada escuchando: el estado de esta raíz no cambia, la que se reinicia es otra',
      () async {
        final c = armar();
        await yaResuelto(c);

        await c.read(recuperacionPendienteProvider.notifier).reabrir();

        expect(
          c.read(recuperacionPendienteProvider).value,
          isFalse,
          reason: 'el asistente no se abre sobre la raíz de antes (con su motor y sus lecturas)',
        );
      },
    );

    test('con datos cargados no se abre y no se toca nada', () async {
      final c = armar();
      await yaResuelto(c);
      arnes.lector.sinDatos = false;

      final resultado = await c.read(recuperacionPendienteProvider.notifier).reabrir();

      expect(resultado, ReaperturaDeLaRecuperacion.hayDatos);
      expect(c.read(recuperacionPendienteProvider).value, isFalse);
      expect(reinicios, 0);
      expect(arnes.resuelta.usuarios, {usuarioDePrueba});
    });

    test('si no se pudo mirar la base, no se abre (nunca sobre algo que no se vio)', () async {
      final c = armar();
      await yaResuelto(c);
      arnes.lector.errorAlMirar = StateError('base cerrada');

      final resultado = await c.read(recuperacionPendienteProvider.notifier).reabrir();

      expect(resultado, ReaperturaDeLaRecuperacion.noSePudoMirar);
      expect(c.read(recuperacionPendienteProvider).value, isFalse);
      expect(reinicios, 0);
      expect(arnes.resuelta.usuarios, {usuarioDePrueba});
    });

    test('si no se pudo quitar la marca, no se reinicia: abriría la app de siempre', () async {
      final c = armar();
      await yaResuelto(c);
      arnes.resuelta.errorAlDesmarcar = StateError('almacén cerrado');

      final resultado = await c.read(recuperacionPendienteProvider.notifier).reabrir();

      expect(resultado, ReaperturaDeLaRecuperacion.noDisponible);
      expect(reinicios, 0);

      // Nada quedó trabado: con el almacén de vuelta, se puede volver a probar.
      arnes.resuelta.errorAlDesmarcar = null;
      expect(
        await c.read(recuperacionPendienteProvider.notifier).reabrir(),
        ReaperturaDeLaRecuperacion.abierta,
      );
      expect(reinicios, 1);
    });

    test('con el asistente apagado no se abre y ni mira la base', () async {
      final c = armar(habilitado: false);
      await c.read(sesionProvider.future);
      await c.read(recuperacionPendienteProvider.future);
      final miradasAlArmar = arnes.lector.miradas;

      final resultado = await c.read(recuperacionPendienteProvider.notifier).reabrir();

      expect(resultado, ReaperturaDeLaRecuperacion.noDisponible);
      expect(arnes.lector.miradas, miradasAlArmar);
      expect(reinicios, 0);
    });

    test('sin sesión no hay a quién abrírselo', () async {
      final c = armar(conSesion: false);
      await c.read(sesionProvider.future);
      await c.read(recuperacionPendienteProvider.future);

      final resultado = await c.read(recuperacionPendienteProvider.notifier).reabrir();

      expect(resultado, ReaperturaDeLaRecuperacion.noDisponible);
      expect(reinicios, 0);
    });

    test('abierto de nuevo, terminarlo lo anota y la raíz sigue', () async {
      final c = armar();
      await yaResuelto(c);
      await c.read(recuperacionPendienteProvider.notifier).reabrir();
      // El arranque nuevo, con su asistente abierto.
      final nuevo = armar();
      await nuevo.read(sesionProvider.future);
      expect(await nuevo.read(recuperacionPendienteProvider.future), isTrue);

      await nuevo.read(recuperacionPendienteProvider.notifier).terminar();

      expect(nuevo.read(recuperacionPendienteProvider).value, isFalse);
      expect(arnes.resuelta.marcas, 1);
      expect(arnes.resuelta.usuarios, {usuarioDePrueba});
    });

    test('abrir dos veces seguidas no deja nada a medias', () async {
      final c = armar();
      await yaResuelto(c);
      final notificador = c.read(recuperacionPendienteProvider.notifier);

      final resultados = await Future.wait([notificador.reabrir(), notificador.reabrir()]);

      expect(resultados, everyElement(ReaperturaDeLaRecuperacion.abierta));
      expect(reinicios, greaterThanOrEqualTo(1), reason: 'el reiniciador junta los pedidos');
      expect(arnes.resuelta.usuarios, isEmpty);
    });
  });

  group('recuperarDespuesDisponibleProvider (la fila de Configuración)', () {
    test('disponible con un teléfono sin datos', () async {
      final c = armar();
      await c.read(sesionProvider.future);

      expect(
        await c.read(recuperarDespuesDisponibleProvider.future),
        FilaRecuperarRespaldo.disponible,
      );
    });

    test('apagada con datos cargados (16G·04: se ve y dice por qué)', () async {
      final c = armar();
      await c.read(sesionProvider.future);
      arnes.lector.sinDatos = false;

      expect(
        await c.read(recuperarDespuesDisponibleProvider.future),
        FilaRecuperarRespaldo.apagadaConDatos,
      );
    });

    test('no se muestra si no se pudo mirar la base', () async {
      final c = armar();
      await c.read(sesionProvider.future);
      arnes.lector.errorAlMirar = StateError('base cerrada');

      expect(await c.read(recuperarDespuesDisponibleProvider.future), FilaRecuperarRespaldo.oculta);
    });

    test('no se muestra con el asistente apagado ni sin sesión', () async {
      final apagado = armar(habilitado: false);
      await apagado.read(sesionProvider.future);
      expect(
        await apagado.read(recuperarDespuesDisponibleProvider.future),
        FilaRecuperarRespaldo.oculta,
      );

      final sinSesion = armar(conSesion: false);
      await sinSesion.read(sesionProvider.future);
      expect(
        await sinSesion.read(recuperarDespuesDisponibleProvider.future),
        FilaRecuperarRespaldo.oculta,
      );
    });
  });
}
