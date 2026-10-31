// HU-SYNC-006 — El asistente de recuperación del primer arranque (vista 34, #175): cada artboard
// (34·01 a 34·10), los estados que la HU pide y el canvas no dibuja, y los casos límite de cada flujo.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../helpers/recuperacion_arnes.dart';
import '../../helpers/respaldo_drive_falsos.dart';

/// Deja correr los microtasks y unos cuadros: con círculos girando no se puede `pumpAndSettle`.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tocar(WidgetTester tester, Finder objetivo) async {
  await tester.ensureVisible(objetivo);
  await tester.tap(objetivo);
  await asentar(tester);
}

/// 34·01 → 34·03: elige recuperar y escribe la contraseña.
Future<void> irAContrasena(WidgetTester tester, {String contrasena = 'la-de-antes'}) async {
  await tocar(tester, cta);
  await tester.enterText(campoContrasena, contrasena);
  await asentar(tester);
}

/// 34·03 → 34·05: abre la copia.
Future<void> abrirCopia(WidgetTester tester, {String contrasena = 'la-de-antes'}) async {
  await irAContrasena(tester, contrasena: contrasena);
  await tocar(tester, cta);
}

bool botonApagado(WidgetTester tester, Finder boton) =>
    tester.widget<ButtonStyleButton>(boton).onPressed == null;

void main() {
  late ArnesRecuperacion arnes;

  setUp(() => arnes = ArnesRecuperacion());

  group('34·01 Encontrado', () {
    testWidgets('muestra el respaldo, el paso 1 de 3 y los dos botones del canvas', (tester) async {
      await abrirAsistente(tester, arnes);

      expect(tester.widget<Text>(paso).data, 'RECUPERAR · PASO 1 DE 3');
      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
      expect(find.text('Respaldo del 22/10 a las 03:10'), findsOneWidget);
      expect(find.text('15 partes · 38 MB'), findsOneWidget);
      expect(textoDe(cta), 'Recuperar mis datos');
      expect(textoDe(cta2), 'Empezar sin recuperar');
      expect(arnes.servicio.busquedas, 1);
    });

    testWidgets('«Buscando…»: mientras mira Drive se ve el progreso y se puede empezar sin '
        'recuperar', (tester) async {
      arnes.servicio.compuertaBuscar = Completer<void>();
      await abrirAsistente(tester, arnes);

      expect(buscando, findsOneWidget);
      expect(find.text('Buscando tu respaldo en Google Drive…'), findsOneWidget);
      expect(cta, findsNothing);
      expect(textoDe(cta2), 'Empezar sin recuperar');

      arnes.servicio.compuertaBuscar!.complete();
      await asentar(tester);
      expect(buscando, findsNothing);
      expect(tarjeta, findsOneWidget);
    });

    testWidgets('con una sola parte lo dice en singular', (tester) async {
      arnes.servicio.busqueda = RespaldoEncontrado(
        RespaldoEnDrive(
          llave: 'k',
          fecha: DateTime(2026, 10, 22, 3, 10),
          partes: 1,
          bytes: 1000,
          completo: true,
          tieneLlave: true,
        ),
      );
      await abrirAsistente(tester, arnes);

      expect(find.text('1 parte · 1 MB'), findsOneWidget);
    });

    testWidgets('«Empezar sin recuperar» anota que se resolvió, y un doble toque no lo anota '
        'dos veces', (tester) async {
      arnes.resuelta.compuertaMarcar = Completer<void>();
      await abrirAsistente(tester, arnes);

      await tester.tap(cta2);
      await tester.tap(cta2);
      await asentar(tester);

      expect(arnes.resuelta.marcas, 1);
      arnes.resuelta.compuertaMarcar!.complete();
      await asentar(tester);
      expect(arnes.resuelta.usuarios, {usuarioDePrueba});
    });
  });

  group('34·02 Conectar Drive', () {
    setUp(() => arnes.servicio.busqueda = const DriveSinPermiso());

    testWidgets('pide conectar con Google y deja empezar sin recuperar', (tester) async {
      await abrirAsistente(tester, arnes);

      expect(tester.widget<Text>(titulo).data, 'Buscá tu respaldo');
      expect(tester.widget<Text>(paso).data, 'RECUPERAR · PASO 1 DE 3');
      expect(textoDe(cta), 'Conectar con Google');
      expect(textoDe(cta2), 'Empezar sin recuperar');
    });

    testWidgets('al conectar, sigue con la búsqueda y muestra el respaldo', (tester) async {
      await abrirAsistente(tester, arnes);
      arnes.servicio.busqueda = RespaldoEncontrado(respaldoDePrueba);

      await tocar(tester, cta);

      expect(arnes.drive.google.conexiones, 1);
      expect(arnes.servicio.busquedas, 2);
      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget, reason: 'la cuenta en la tarjeta');
    });

    testWidgets('doble toque: Google se abre una sola vez y el botón dice «Conectando…»', (
      tester,
    ) async {
      await abrirAsistente(tester, arnes);
      arnes.drive.google.compuertaConectar = Completer<void>();

      await tester.tap(cta);
      await tester.pump();
      await tester.tap(cta, warnIfMissed: false);
      await asentar(tester);

      expect(arnes.drive.google.conexiones, 1);
      expect(textoDe(cta), 'Conectando…');
      expect(botonApagado(tester, cta), isTrue);

      arnes.drive.google.compuertaConectar!.complete();
      await asentar(tester);
      expect(arnes.servicio.busquedas, 2);
    });

    testWidgets(
      'cancelar en Google deja el aviso «No conectamos tu Drive…» y se puede reintentar',
      (tester) async {
        await abrirAsistente(tester, arnes);
        arnes.drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);

        await tocar(tester, cta);

        expect(find.text(const FailureDriveCancelado().mensaje), findsOneWidget);
        expect(textoDe(cta), 'Reintentar');
        expect(botonApagado(tester, cta), isFalse, reason: 'nada quedó trabado');

        arnes.drive.google.errorAlConectar = null;
        arnes.servicio.busqueda = RespaldoEncontrado(respaldoDePrueba);
        await tocar(tester, cta);
        expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
      },
    );

    testWidgets('un error inesperado al conectar no deja el botón ocupado', (tester) async {
      await abrirAsistente(tester, arnes);
      arnes.drive.google.errorAlConectar = StateError('Google se cayó');

      await tocar(tester, cta);

      expect(cta, findsOneWidget);
      expect(botonApagado(tester, cta), isFalse);
      expect(textoDe(cta), 'Reintentar');
    });
  });

  group('34·03 y 34·04 Contraseña', () {
    testWidgets('pide la contraseña, avisa cuánto pesa y no deja abrir sin escribirla', (
      tester,
    ) async {
      await abrirAsistente(tester, arnes);
      await tocar(tester, cta);

      expect(tester.widget<Text>(paso).data, 'RECUPERAR · PASO 2 DE 3');
      expect(tester.widget<Text>(titulo).data, 'Abrí tu copia');
      expect(find.text('Respaldo del 22/10 a las 03:10'), findsOneWidget);
      expect(
        find.text('Vamos a restaurar 38 MB. La operación puede tardar varios minutos.'),
        findsOneWidget,
      );
      expect(textoDe(cta), 'Abrir copia');
      expect(botonApagado(tester, cta), isTrue);

      await tester.enterText(campoContrasena, 'x');
      await asentar(tester);
      expect(botonApagado(tester, cta), isFalse);
    });

    testWidgets('la contraseña se oculta y se puede mostrar', (tester) async {
      await abrirAsistente(tester, arnes);
      await tocar(tester, cta);

      TextField campo() => tester.widget<TextField>(campoContrasena);
      expect(campo().obscureText, isTrue);
      await tocar(tester, verContrasena);
      expect(campo().obscureText, isFalse);
      await tocar(tester, verContrasena);
      expect(campo().obscureText, isTrue);
    });

    testWidgets('34·04: una contraseña distinta lo dice con el texto de la HU y deja volver a '
        'intentar sin perder lo escrito', (tester) async {
      arnes.servicio.resultado = const ContrasenaNoAbreElRespaldo();
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester, contrasena: 'otra');

      expect(tester.widget<Text>(titulo).data, 'Abrí tu copia');
      expect(
        find.text(
          'Esta contraseña no abre tu copia; probá la que usabas cuando hiciste el último respaldo.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(campoContrasena).controller!.text, 'otra');
      expect(botonApagado(tester, cta), isFalse);

      // Al escribir otra, el aviso se va.
      await tester.enterText(campoContrasena, 'la-buena');
      await asentar(tester);
      expect(errorContrasena, findsNothing);

      arnes.servicio.resultado = RecuperacionHecha(informeDePrueba());
      await tocar(tester, cta);
      expect(arnes.servicio.ultimaContrasena, 'la-buena');
      expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
    });

    testWidgets('«Empezar sin recuperar» sigue ahí', (tester) async {
      await abrirAsistente(tester, arnes);
      await tocar(tester, cta);

      expect(textoDe(cta2), 'Empezar sin recuperar');
    });
  });

  group('34·05 Restaurando', () {
    setUp(() {
      arnes.servicio.frenarRecuperar = true;
      arnes.servicio.progresos = const [
        ProgresoRecuperacion(PasoRecuperacion.bajando, hechas: 12, total: 15),
      ];
    });

    testWidgets('muestra «12/15 partes», el aviso y el botón ocupado', (tester) async {
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      expect(tester.widget<Text>(paso).data, 'RECUPERAR · PASO 3 DE 3');
      expect(tester.widget<Text>(titulo).data, 'Restaurando');
      expect(tester.widget<Text>(progresoValor).data, '12/15 partes');
      expect(tester.widget<LinearProgressIndicator>(progresoBarra).value, closeTo(0.8, 0.001));
      expect(find.text('Bajando partes…'), findsOneWidget);
      expect(
        find.text(
          'Lo que había en este teléfono no se toca hasta que termine. Si se corta, no se pierde '
          'nada.',
        ),
        findsOneWidget,
      );
      expect(textoDe(cta), 'Restaurando…');
      expect(botonApagado(tester, cta), isTrue);
      expect(textoDe(cta2), 'Cancelar');
    });

    testWidgets('doble toque en «Abrir copia»: se restaura una sola vez', (tester) async {
      await abrirAsistente(tester, arnes);
      await irAContrasena(tester);

      await tester.tap(cta);
      await tester.tap(cta, warnIfMissed: false);
      await asentar(tester);

      expect(arnes.servicio.recuperaciones, 1);
    });

    testWidgets('al terminar la bajada pasa a «Armando tu copia…» y ya no se puede cancelar', (
      tester,
    ) async {
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      arnes.servicio.alAvanzarActual!(const ProgresoRecuperacion(PasoRecuperacion.aplicando));
      await asentar(tester);

      expect(find.text('Armando tu copia…'), findsOneWidget);
      expect(cta2, findsNothing, reason: 'una vez aplicando, cancelar dejaría la base a medias');
    });

    testWidgets('Cancelar corta la descarga, no toca nada y vuelve a 34·01', (tester) async {
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      await tocar(tester, cta2);
      await tester.tap(cta2, warnIfMissed: false);
      await asentar(tester);
      expect(arnes.servicio.ultimaCancelacion!.cancelada, isTrue);
      expect(botonApagado(tester, cta2), isTrue, reason: 'ya se pidió cancelar');

      arnes.servicio.compuertaRecuperar!.complete();
      await asentar(tester);

      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
      expect(arnes.resuelta.marcas, 0, reason: 'cancelar no resuelve el asistente');
    });

    testWidgets('el trabajo pasa por los pasos de reenviar y traer lo último', (tester) async {
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      arnes.servicio.alAvanzarActual!(const ProgresoRecuperacion(PasoRecuperacion.reenviando));
      await asentar(tester);
      expect(find.text('Reenviando lo que estaba pendiente…'), findsOneWidget);
      expect(progresoValor, findsNothing);

      arnes.servicio.alAvanzarActual!(const ProgresoRecuperacion(PasoRecuperacion.reconciliando));
      await asentar(tester);
      expect(find.text('Trayendo lo último de tu cuenta…'), findsOneWidget);
    });

    testWidgets('si falla a mitad: avisa, el botón no queda ocupado y reintenta', (tester) async {
      arnes.servicio.errorAlRecuperar = StateError('se cayó');
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);
      arnes.servicio.compuertaRecuperar!.complete();
      await asentar(tester);

      expect(tester.widget<Text>(titulo).data, 'No pudimos recuperar tus datos');
      expect(botonApagado(tester, cta), isFalse);
      expect(textoDe(cta), 'Reintentar');
      expect(textoDe(cta2), 'Empezar sin recuperar');

      // «Reintentar» vuelve a buscar y deja elegir de nuevo.
      arnes.servicio.errorAlRecuperar = null;
      await tocar(tester, cta);
      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
      await abrirCopia(tester);
      expect(arnes.servicio.recuperaciones, 2);
    });
  });

  group('34·06 Interrumpida', () {
    setUp(() {
      arnes.servicio.resultado = const RecuperacionSinConexion(hechas: 12, total: 15);
    });

    testWidgets('dice dónde quedó y «Reintentar» retoma con la misma contraseña', (tester) async {
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester, contrasena: 'la-de-antes');

      expect(tester.widget<Text>(titulo).data, 'Se cortó la conexión');
      expect(find.text('Quedó en la parte 12'), findsOneWidget);
      expect(tester.widget<Text>(progresoValor).data, '12/15 partes');
      expect(textoDe(cta), 'Reintentar');
      expect(botonApagado(tester, cta), isFalse);

      arnes.servicio.resultado = RecuperacionHecha(informeDePrueba());
      await tocar(tester, cta);

      expect(arnes.servicio.recuperaciones, 2);
      expect(arnes.servicio.ultimaContrasena, 'la-de-antes');
      expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
    });

    testWidgets('sin conexión el botón queda apagado hasta que vuelve', (tester) async {
      await abrirAsistente(tester, arnes);
      arnes.conexion.cambiarA(TipoConexion.sinConexion);
      await asentar(tester);
      await abrirCopia(tester);

      expect(botonApagado(tester, cta), isTrue);

      arnes.conexion.cambiarA(TipoConexion.wifi);
      await asentar(tester);
      expect(botonApagado(tester, cta), isFalse);
    });

    testWidgets('si la conexión se corta y el motor sigue esperando, muestra 34·06 y retoma solo', (
      tester,
    ) async {
      arnes.servicio.compuertaRecuperar = Completer<void>();
      arnes.servicio.progresos = const [
        ProgresoRecuperacion(PasoRecuperacion.bajando, hechas: 12, total: 15),
      ];
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      arnes.servicio.alAvanzarActual!(
        const ProgresoRecuperacion(
          PasoRecuperacion.bajando,
          hechas: 12,
          total: 15,
          esperandoConexion: true,
        ),
      );
      await asentar(tester);
      expect(tester.widget<Text>(titulo).data, 'Se cortó la conexión');
      expect(botonApagado(tester, cta), isTrue, reason: 'el motor retoma solo');

      arnes.servicio.alAvanzarActual!(
        const ProgresoRecuperacion(PasoRecuperacion.bajando, hechas: 13, total: 15),
      );
      await asentar(tester);
      expect(tester.widget<Text>(titulo).data, 'Restaurando');
      expect(tester.widget<Text>(progresoValor).data, '13/15 partes');
    });

    testWidgets('cortada antes de bajar nada, lo dice sin inventar una parte', (tester) async {
      arnes.servicio.resultado = const RecuperacionSinConexion(hechas: 0, total: 15);
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      expect(find.text('Todavía no bajamos ninguna parte'), findsOneWidget);
    });

    testWidgets('«Cancelar» desde acá vuelve a 34·01', (tester) async {
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      await tocar(tester, cta2);

      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
    });
  });

  group('34·07 Parte dañada', () {
    setUp(() {
      arnes.servicio.resultado = RecuperacionHecha(
        informeDePrueba(parcial: true, restauradas: 11, totales: 15),
      );
    });

    testWidgets('avisa qué se recuperó y qué quedó afuera', (tester) async {
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      expect(tester.widget<Text>(titulo).data, 'Recuperamos casi todo');
      expect(find.textContaining('La parte 12 de 15 está dañada'), findsOneWidget);
      expect(find.text('Quedó afuera'), findsOneWidget);
      expect(find.text('Restaurado'), findsOneWidget);
      expect(find.textContaining('Si tenés el teléfono viejo'), findsOneWidget);
      expect(textoDe(cta), 'Seguir con lo recuperado');
      expect(textoDe(cta2), 'Ver qué quedó afuera');
    });

    testWidgets('«Ver qué quedó afuera» abre y cierra el detalle', (tester) async {
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      final detalle = find.byKey(const Key('recuperacion_detalle_afuera'));
      expect(detalle, findsNothing);
      await tocar(tester, cta2);
      expect(detalle, findsOneWidget);
      expect(textoDe(cta2), 'Ocultar lo que quedó afuera');
      await tocar(tester, cta2);
      expect(detalle, findsNothing);
    });

    testWidgets('«Seguir con lo recuperado» resuelve el asistente, una sola vez', (tester) async {
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);
      expect(arnes.resuelta.marcas, 1, reason: 'ya hay datos recuperados: se anota al recuperar');

      arnes.resuelta.compuertaMarcar = Completer<void>();
      await tester.tap(cta);
      await tester.tap(cta, warnIfMissed: false);
      await asentar(tester);
      expect(arnes.resuelta.marcas, 2);
      expect(textoDe(cta), 'Seguir con lo recuperado');

      arnes.resuelta.compuertaMarcar!.complete();
      await asentar(tester);
    });
  });

  group('34·08 Listo', () {
    testWidgets('dice de cuándo son los datos y cuánto volvió', (tester) async {
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
      expect(tester.widget<Text>(heroTexto).data, 'Como el 22/10 a las 03:10');
      for (final (rotulo, cantidad) in const [
        ('Ubicaciones', '214'),
        ('Personas', '96'),
        ('Ventas', '41'),
        ('Cobros', '63'),
      ]) {
        expect(find.text(rotulo), findsOneWidget);
        expect(find.text(cantidad), findsOneWidget);
      }
      expect(textoDe(cta), 'Ir a mi inicio');
      expect(cta2, findsNothing);
    });

    testWidgets('si no se puede contar lo que volvió, igual avisa que terminó', (tester) async {
      arnes.lector.errorAlResumir = StateError('no se pudo leer');
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
      expect(find.text('Ubicaciones'), findsNothing);
      expect(textoDe(cta), 'Ir a mi inicio');
    });

    testWidgets('«Ir a mi inicio»: anota la resolución y un doble toque no la repite', (
      tester,
    ) async {
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);
      expect(arnes.resuelta.marcas, 1);

      arnes.resuelta.compuertaMarcar = Completer<void>();
      await tester.tap(cta);
      await tester.tap(cta, warnIfMissed: false);
      await asentar(tester);
      expect(arnes.resuelta.marcas, 2);
      expect(botonApagado(tester, cta), isTrue);

      arnes.resuelta.compuertaMarcar!.complete();
      await asentar(tester);
      expect(arnes.resuelta.usuarios, {usuarioDePrueba});
    });
  });

  group('34·09 Sin respaldo', () {
    setUp(() => arnes.servicio.busqueda = const SinRespaldoEnDrive());

    testWidgets('dice que no hay respaldo y ofrece otra cuenta o empezar sin recuperar', (
      tester,
    ) async {
      await abrirAsistente(tester, arnes);

      expect(tester.widget<Text>(titulo).data, 'No encontramos un respaldo');
      expect(find.textContaining('no hay un respaldo de Colportaje'), findsOneWidget);
      expect(textoDe(cta), 'Probar con otra cuenta');
      expect(textoDe(cta2), 'Empezar sin recuperar');
    });

    testWidgets('«Probar con otra cuenta» abre Google y vuelve a buscar', (tester) async {
      await abrirAsistente(tester, arnes);

      await tocar(tester, cta);

      expect(arnes.drive.google.conexiones, 1);
      expect(arnes.servicio.busquedas, 2);
    });

    testWidgets('doble toque en «Probar con otra cuenta»: una sola conexión', (tester) async {
      await abrirAsistente(tester, arnes);
      arnes.drive.google.compuertaConectar = Completer<void>();

      await tester.tap(cta);
      await tester.tap(cta, warnIfMissed: false);
      await asentar(tester);
      expect(arnes.drive.google.conexiones, 1);

      arnes.drive.google.compuertaConectar!.complete();
      await asentar(tester);
    });
  });

  group('34·10 Sin conexión', () {
    setUp(() => arnes.servicio.busqueda = const BusquedaSinConexion());

    testWidgets('pide conexión y deja «Reintentar» apagado hasta que vuelve', (tester) async {
      await abrirAsistente(tester, arnes);
      arnes.conexion.cambiarA(TipoConexion.sinConexion);
      await asentar(tester);

      expect(tester.widget<Text>(titulo).data, 'Recuperar mis datos');
      expect(find.text('Necesitás conexión (mejor Wi-Fi) para traer tu respaldo.'), findsOneWidget);
      expect(textoDe(cta), 'Reintentar');
      expect(botonApagado(tester, cta), isTrue);
      expect(textoDe(cta2), 'Empezar sin recuperar');

      arnes.conexion.cambiarA(TipoConexion.wifi);
      arnes.servicio.busqueda = RespaldoEncontrado(respaldoDePrueba);
      await asentar(tester);
      await tocar(tester, cta);
      expect(arnes.servicio.busquedas, 2);
      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
    });
  });

  group('Casos que el canvas no dibuja', () {
    testWidgets('la búsqueda falla: lo dice, se puede reintentar y empezar sin recuperar', (
      tester,
    ) async {
      arnes.servicio.errorAlBuscar = StateError('se cayó');
      await abrirAsistente(tester, arnes);

      expect(tester.widget<Text>(titulo).data, 'No pudimos buscar tu respaldo');
      expect(botonApagado(tester, cta), isFalse);
      expect(textoDe(cta2), 'Empezar sin recuperar');

      arnes.servicio.errorAlBuscar = null;
      await tocar(tester, cta);
      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
    });

    testWidgets('el doble toque en «Reintentar» busca una sola vez', (tester) async {
      arnes.servicio.busqueda = const BusquedaFallida();
      await abrirAsistente(tester, arnes);
      arnes.servicio.compuertaBuscar = Completer<void>();

      await tester.tap(cta);
      await tester.tap(cta, warnIfMissed: false);
      await asentar(tester);

      expect(arnes.servicio.busquedas, 2);
      arnes.servicio.compuertaBuscar!.complete();
      await asentar(tester);
    });

    testWidgets('versión más nueva: el texto de la HU y cómo actualizar', (tester) async {
      arnes.servicio.resultado = const RespaldoDeVersionMasNueva(
        esquemaDelRespaldo: 30,
        esquemaDeLaApp: 24,
      );
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      expect(
        find.text(
          'Tus datos son de una versión más nueva de la app. Actualizala para seguir usando tus '
          'datos.',
        ),
        findsOneWidget,
      );
      expect(textoDe(cta), 'Actualizar');
      expect(find.byKey(const Key('recuperacion_como_actualizar')), findsNothing);
      await tocar(tester, cta);
      expect(find.byKey(const Key('recuperacion_como_actualizar')), findsOneWidget);
      expect(textoDe(cta2), 'Empezar sin recuperar');
    });

    testWidgets('respaldo sin clave: lo dice y no tiene salida trabada', (tester) async {
      arnes.servicio.resultado = const SinLlaveParaElRespaldo();
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      expect(tester.widget<Text>(titulo).data, 'No podemos abrir este respaldo');
      expect(botonApagado(tester, cta), isFalse);
      expect(textoDe(cta2), 'Empezar sin recuperar');
    });

    testWidgets('respaldo ilegible: lo dice y no se tocó nada', (tester) async {
      arnes.servicio.resultado = const RespaldoIlegible();
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      expect(tester.widget<Text>(titulo).data, 'No pudimos leer tu respaldo');
      expect(find.textContaining('No se tocó nada de tu teléfono'), findsOneWidget);
    });

    testWidgets('Drive deja de dar permiso a mitad: vuelve a conectar con el aviso', (
      tester,
    ) async {
      arnes.servicio.resultado = const RecuperacionSinPermiso();
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      expect(tester.widget<Text>(titulo).data, 'Buscá tu respaldo');
      expect(find.textContaining('Google ya no nos deja abrir tu Drive'), findsOneWidget);
    });

    testWidgets('hay respaldos de más de un teléfono: no se elige por la persona', (tester) async {
      arnes.servicio.busqueda = VariosRespaldosEnDrive([respaldoDePrueba, respaldoDePrueba]);
      await abrirAsistente(tester, arnes);

      expect(tester.widget<Text>(titulo).data, 'Encontramos más de un respaldo');
      expect(tarjeta, findsNothing);
      expect(textoDe(cta), 'Reintentar');
      expect(textoDe(cta2), 'Empezar sin recuperar');
    });

    testWidgets('un resultado fallido de la recuperación no deja nada trabado', (tester) async {
      arnes.servicio.resultado = const RecuperacionFallida();
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);

      expect(tester.widget<Text>(titulo).data, 'No pudimos recuperar tus datos');
      expect(botonApagado(tester, cta), isFalse);
    });
  });

  group('Volver atrás y reentrar', () {
    testWidgets('salir del asistente en plena descarga la cancela; al volver empieza de cero y sin '
        'la contraseña', (tester) async {
      arnes.servicio.compuertaRecuperar = Completer<void>();
      await abrirAsistente(tester, arnes);
      await abrirCopia(tester);
      final cancelacion = arnes.servicio.ultimaCancelacion!;

      await tester.pumpWidget(const SizedBox.shrink());
      expect(cancelacion.cancelada, isTrue);
      arnes.servicio.compuertaRecuperar!.complete();
      await tester.pump();

      arnes.servicio.compuertaRecuperar = null;
      await abrirAsistente(tester, arnes);
      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
      await tocar(tester, cta);
      expect(tester.widget<TextField>(campoContrasena).controller!.text, isEmpty);
      expect(arnes.servicio.busquedas, 2);
    });

    testWidgets('si la búsqueda termina cuando la pantalla ya no está, no pasa nada', (
      tester,
    ) async {
      arnes.servicio.compuertaBuscar = Completer<void>();
      await abrirAsistente(tester, arnes);

      await tester.pumpWidget(const SizedBox.shrink());
      arnes.servicio.compuertaBuscar!.complete();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('Datos límite y texto grande', () {
    const chico = Size(320, 568);

    Future<void> recorrer(WidgetTester tester, String nombre) async {
      arnes = ArnesRecuperacion();
      final s = arnes.servicio;
      switch (nombre) {
        case 'conectar':
          s.busqueda = const DriveSinPermiso();
        case 'sin respaldo':
          s.busqueda = const SinRespaldoEnDrive();
        case 'sin conexión':
          s.busqueda = const BusquedaSinConexion();
        case 'contraseña distinta':
          s.resultado = const ContrasenaNoAbreElRespaldo();
        case 'restaurando':
          s.compuertaRecuperar = Completer<void>();
          s.progresos = const [
            ProgresoRecuperacion(PasoRecuperacion.bajando, hechas: 12, total: 15),
          ];
        case 'interrumpida':
          s.resultado = const RecuperacionSinConexion(hechas: 12, total: 15);
        case 'parcial':
          s.resultado = RecuperacionHecha(
            informeDePrueba(parcial: true, restauradas: 11, totales: 15),
          );
        case 'versión más nueva':
          s.resultado = const RespaldoDeVersionMasNueva(esquemaDelRespaldo: 30, esquemaDeLaApp: 24);
      }
      await abrirAsistente(tester, arnes, tamano: chico, escala: 2);
      expect(tester.takeException(), isNull, reason: '$nombre: primera pantalla');
      const pasaPorContrasena = {
        'contraseña',
        'contraseña distinta',
        'restaurando',
        'interrumpida',
        'parcial',
        'listo',
        'versión más nueva',
      };
      if (pasaPorContrasena.contains(nombre)) {
        await tocar(tester, cta);
        expect(tester.takeException(), isNull, reason: '$nombre: contraseña');
        if (nombre != 'contraseña') {
          await tester.enterText(campoContrasena, 'x');
          await asentar(tester);
          await tocar(tester, cta);
        }
      }
      if (nombre == 'versión más nueva') await tocar(tester, cta);
      if (nombre == 'parcial') await tocar(tester, cta2);
      expect(tester.takeException(), isNull, reason: nombre);
      if (cta.evaluate().isNotEmpty) {
        await tester.ensureVisible(cta);
        expect(
          tester.getRect(cta).height,
          greaterThanOrEqualTo(48),
          reason: '$nombre: alto táctil',
        );
      }
    }

    for (final nombre in [
      'encontrado',
      'conectar',
      'sin respaldo',
      'sin conexión',
      'contraseña',
      'contraseña distinta',
      'restaurando',
      'interrumpida',
      'parcial',
      'listo',
      'versión más nueva',
    ]) {
      testWidgets('textScaler 2.0 en 320 x 568: «$nombre» no desborda y se alcanza', (
        tester,
      ) async {
        await recorrer(tester, nombre);
      });
    }

    testWidgets('una contraseña larguísima no rompe la tarjeta ni el campo', (tester) async {
      await abrirAsistente(tester, arnes, tamano: chico, escala: 2);
      await tocar(tester, cta);
      await tester.enterText(campoContrasena, 'x' * 300);
      await asentar(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('un respaldo enorme muestra el peso sin romperse', (tester) async {
      arnes.servicio.busqueda = RespaldoEncontrado(
        RespaldoEnDrive(
          llave: 'k',
          fecha: DateTime(2026, 10, 22, 3, 10),
          partes: 4200,
          bytes: 9 * 1024 * 1024 * 1024,
          completo: true,
          tieneLlave: true,
        ),
      );
      await abrirAsistente(tester, arnes);

      expect(find.text('4200 partes · 9216 MB'), findsOneWidget);
    });
  });
}
