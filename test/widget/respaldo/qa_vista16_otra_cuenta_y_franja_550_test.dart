// QA de #550 (HU-SYNC-004), vista 16, artboards 16E·01 a 16E·04 y 16F·01 a 16F·04. Texto literal del
// canvas por estado, avisos con región viva, casos límite de los flujos (falla a mitad, hoja que no se
// cierra mientras trabaja, reentrada) y privacidad. Los hallazgos van con `skip` y su motivo; se
// activan con `--dart-define=QA_HALLAZGOS=true`.
import 'dart:async';

import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/domain/repositories/respaldo_drive_repository.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista16_550_arnes.dart';

const _qaHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// El primer respaldo que espera a que el test lo suelte (la copia tarda).
final class _PrimerRespaldoQueTarda implements PrimerRespaldoDrive {
  final compuerta = Completer<void>();

  /// Hasta que el test lo arma, el primer respaldo sale al toque (el armado conecta dos veces).
  bool tarda = false;
  int llamadas = 0;

  @override
  Future<bool> hacer() async {
    if (!tarda) return true;
    llamadas++;
    await compuerta.future;
    return true;
  }
}

Finder _en(Finder dentro, String texto) => find.descendant(of: dentro, matching: find.text(texto));

void main() {
  group('16E·01 a 16E·04: el texto literal del canvas', () {
    testWidgets('16E·01 hoja: título, frase, tres filas, «No se borra nada» y los dos botones', (
      tester,
    ) async {
      await armarEstado550(tester, Estado550.hoja01);

      expect(_en(hojaOtra, 'Esta no es la cuenta de tu respaldo'), findsOneWidget);
      expect(
        _en(
          hojaOtra,
          'Tu respaldo anterior quedó en ana.gomez@gmail.com. '
          'Ahora te conectaste con lu.silva.casa@gmail.com.',
        ),
        findsOneWidget,
      );
      for (final t in [
        'Respaldo anterior',
        'ana.gomez@gmail.com',
        'Último respaldo',
        '20/10 · 03:10',
        'Cuenta de ahora',
        'lu.silva.casa@gmail.com',
        'No se borra nada: el respaldo anterior sigue en la otra cuenta.',
        'Volver a la cuenta anterior',
        'Seguir con la cuenta nueva',
      ]) {
        expect(_en(hojaOtra, t), findsOneWidget, reason: t);
      }
    });

    testWidgets('16E·01 fila: la cuenta nueva y «Todavía sin respaldo en esta cuenta»', (
      tester,
    ) async {
      await armarEstado550(tester, Estado550.filaPendiente);

      expect(_en(filaDrive, 'lu.silva.casa@gmail.com'), findsOneWidget);
      expect(_en(filaDrive, 'Todavía sin respaldo en esta cuenta'), findsOneWidget);
    });

    testWidgets('16E·02 confirmación: título, qué pasa y los dos botones', (tester) async {
      await armarEstado550(tester, Estado550.hoja02);

      expect(_en(hojaSeguir, '¿Seguir con la cuenta nueva?'), findsOneWidget);
      expect(
        _en(
          hojaSeguir,
          'Desde esta noche el respaldo se guarda en lu.silva.casa@gmail.com. '
          'El anterior queda en ana.gomez@gmail.com: no se borra, pero deja de actualizarse.',
        ),
        findsOneWidget,
      );
      expect(find.text('Seguir con la cuenta nueva'), findsOneWidget);
      expect(find.text('Volver a la anterior'), findsOneWidget);
    });

    testWidgets('16E·03 volvió: «Listo. Tu respaldo sigue en ana.gomez@gmail.com.»', (
      tester,
    ) async {
      await armarEstado550(tester, Estado550.volvio03);

      expect(hojaOtra, findsNothing);
      expect(find.text('Listo. Tu respaldo sigue en ana.gomez@gmail.com.'), findsOneWidget);
    });

    testWidgets('16E·04 sin conexión: «Necesitás conexión para cambiar de cuenta.»', (
      tester,
    ) async {
      await armarEstado550(tester, Estado550.hoja04);

      expect(
        _en(avisoSinConexionHoja, 'Necesitás conexión para cambiar de cuenta.'),
        findsOneWidget,
      );
    });
  });

  group('16F·01 a 16F·04: el texto literal del canvas', () {
    testWidgets('16F·01 revocado: texto y «Reconectar en Configuración»', (tester) async {
      await armarEstado550(tester, Estado550.hoy01);

      expect(
        _en(
          franjaRevocada,
          'Google ya no nos deja guardar tu respaldo. Lo que cargues desde ahora no tiene copia.',
        ),
        findsOneWidget,
      );
      expect(_en(franjaRevocada, 'Reconectar en Configuración'), findsOneWidget);
    });

    testWidgets('16F·02 Drive lleno: texto y «Ver en Configuración»', (tester) async {
      await armarEstado550(tester, Estado550.hoy02);

      expect(
        _en(franjaLlena, 'Tu Drive está lleno. El respaldo de anoche no se guardó.'),
        findsOneWidget,
      );
      expect(_en(franjaLlena, 'Ver en Configuración'), findsOneWidget);
    });

    testWidgets('16F·04 oculta: «Te lo recordamos mañana. Lo ves en Configuración.» y la marca', (
      tester,
    ) async {
      await armarEstado550(tester, Estado550.hoy04);

      expect(franjaRevocada, findsNothing);
      expect(find.text('Te lo recordamos mañana. Lo ves en Configuración.'), findsOneWidget);
      expect(marcaEngranaje, findsOneWidget);
    });

    testWidgets('el engranaje con la marca dice su motivo al lector de pantalla', (tester) async {
      final handle = tester.ensureSemantics();
      await armarEstado550(tester, Estado550.hoy04);

      final datos = tester.getSemantics(engranaje).getSemanticsData();
      expect(datos.tooltip, contains('aviso'));
      handle.dispose();
    });

    testWidgets('el engranaje con la marca no se lee con un «!» suelto antes de su motivo', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await armarEstado550(tester, Estado550.hoy04);

      // skip: QA #550 — el `Badge` pone «!» como etiqueta del botón y el lector lo dice suelto.
      expect(tester.getSemantics(engranaje).label.trim(), isNot('!'));
      handle.dispose();
    }, skip: !_qaHallazgos);
  });

  group('Los avisos se anuncian (región viva)', () {
    testWidgets('el error al volver a la cuenta anterior es una región viva', (tester) async {
      final handle = tester.ensureSemantics();
      await armarEstado550(tester, Estado550.hojaError);

      expect(avisoErrorHoja, findsOneWidget);
      expect(tester.getSemantics(avisoErrorHoja), isSemantics(isLiveRegion: true));
      handle.dispose();
    });

    testWidgets('«Necesitás conexión para cambiar de cuenta.» es una región viva', (tester) async {
      final handle = tester.ensureSemantics();
      await armarEstado550(tester, Estado550.hoja04);

      expect(tester.getSemantics(avisoSinConexionHoja), isSemantics(isLiveRegion: true));
      handle.dispose();
    });

    testWidgets('la franja de Hoy es una región viva', (tester) async {
      final handle = tester.ensureSemantics();
      await armarEstado550(tester, Estado550.hoy01);

      expect(tester.getSemantics(franjaRevocada), isSemantics(isLiveRegion: true));
      handle.dispose();
    });
  });

  group('Casos límite de la hoja de otra cuenta', () {
    testWidgets('un error al volver no queda pegado: cerrar la hoja y reabrirla la deja limpia', (
      tester,
    ) async {
      final mundo = await armarEstado550(tester, Estado550.hojaError);
      expect(avisoErrorHoja, findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(hojaOtra, findsNothing);
      mundo.drive.google.errorAlConectar = null;
      await tocarFila550(tester);

      expect(hojaOtra, findsOneWidget);
      expect(avisoErrorHoja, findsNothing, reason: 'la hoja nueva arranca sin el error anterior');
      expect(tester.widget<FilledButton>(botonVolver).onPressed, isNotNull);
    });

    testWidgets('«Seguir» falla al anotar la elección: avisa, sigue por confirmar y se reintenta', (
      tester,
    ) async {
      final mundo = await armarEstado550(tester, Estado550.hoja02);
      mundo.drive.almacen.alEscribir = true;
      await tocar550(tester, botonConfirmarSeguir);

      expect(avisoErrorHoja, findsOneWidget);
      expect(hojaSeguir, findsOneWidget, reason: 'sigue en la confirmación, no se pierde la hoja');
      expect(tester.widget<FilledButton>(botonConfirmarSeguir).onPressed, isNotNull);
      expect(
        mundo.container.read(estadoRespaldoDriveProvider).value,
        isA<DriveCuentaPorConfirmar>(),
      );

      mundo.drive.almacen.alEscribir = false;
      await tocar550(tester, botonConfirmarSeguir);
      expect(hojaSeguir, findsNothing);
      expect(mundo.container.read(estadoRespaldoDriveProvider).value, isA<DriveConectada>());
    });

    testWidgets('mientras el primer respaldo corre: la hoja no se cierra, ni con el atrás ni con '
        'la barrera, y los dos botones esperan', (tester) async {
      final primero = _PrimerRespaldoQueTarda();
      final mundo = Mundo550(primerRespaldo: primero);
      await montar550(
        tester,
        mundo,
        antes: (u) async {
          await mundo.drive.repo.conectar(u);
          mundo.drive.google.cuenta = cuentaNueva550;
          await mundo.drive.repo.conectar(u);
        },
      );
      await irAConfiguracion550(tester);
      await tocarFila550(tester);
      await tocar550(tester, botonSeguir);
      primero.tarda = true;

      await tester.ensureVisible(botonConfirmarSeguir);
      await tester.tap(botonConfirmarSeguir);
      await tester.pump(const Duration(milliseconds: 100));
      expect(primero.llamadas, 1);

      expect(tester.widget<FilledButton>(botonConfirmarSeguir).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(botonConfirmarVolver).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(hojaSeguir, findsOneWidget, reason: 'el atrás no cierra mientras trabaja');
      await tester.tapAt(const Offset(195, 20));
      await tester.pump(const Duration(milliseconds: 300));
      expect(hojaSeguir, findsOneWidget, reason: 'la barrera tampoco');

      primero.compuerta.complete();
      await tester.pumpAndSettle();
      expect(hojaSeguir, findsNothing);
      expect(primero.llamadas, 1, reason: 'una sola copia');
    });

    testWidgets('con otra cuenta por confirmar Hoy no muestra la franja ni la marca (respaldo '
        'frenado sin aviso: pendiente P1 del implementador)', (tester) async {
      await armarEstado550(tester, Estado550.filaPendiente);
      await tester.tap(find.byKey(const Key('configuracion_atras')));
      await tester.pumpAndSettle();

      expect(franjaRevocada, findsNothing);
      expect(franjaLlena, findsNothing);
      expect(marcaEngranaje, findsNothing);
    });

    testWidgets('con otra cuenta por confirmar se puede desconectar Drive desde Configuración '
        '(la HU: «Revocar autorización es siempre posible desde Configuración»)', (tester) async {
      await armarEstado550(tester, Estado550.hoja01);

      // La hoja ofrece volver o seguir; ninguna ofrece desconectar, y la fila ya no abre la hoja de
      // «¿Desconectar Google Drive?».
      final haySalida =
          find.text('Desconectar').evaluate().isNotEmpty ||
          find.text('Desconectar Google Drive').evaluate().isNotEmpty;
      expect(haySalida, isTrue);
    }, skip: !_qaHallazgos);
  });

  group('Privacidad', () {
    test('toString de las cuentas y de los resultados no deja el correo en un log', () {
      const otra = DriveCuentaPorConfirmar(
        email: 'lu.silva.casa@gmail.com',
        cuentaId: 'g-200',
        anteriorEmail: 'ana.gomez@gmail.com',
        anteriorCuentaId: 'g-100',
      );
      expect(otra.toString(), isNot(contains('@')));
      expect(const DriveQuedoEnOtraCuenta(otra).toString(), isNot(contains('@')));
    });
  });

  group('Reentrada', () {
    testWidgets('«Volver» con conexión caída: el botón espera y no abre Google', (tester) async {
      final mundo = await armarEstado550(tester, Estado550.hoja04);

      await tester.ensureVisible(botonVolver);
      await tester.tap(botonVolver, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(mundo.drive.google.conexiones, 2, reason: 'las dos del armado, ninguna más');
      expect(tester.widget<FilledButton>(botonVolver).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(botonSeguir).onPressed, isNotNull);
    });
  });
}
