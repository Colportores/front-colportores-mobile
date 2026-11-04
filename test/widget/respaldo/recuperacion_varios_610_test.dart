// HU-SYNC-006 (#610, decisión de Cristian del 03/11, «Varios resp.» y «Recup. luego») — El asistente
// de recuperación con respaldos de más de un teléfono (se traen todos juntos) y el aviso de
// «Empezar sin recuperar».
import 'dart:async';

import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/recuperacion_arnes.dart';

/// Un respaldo de otro teléfono: distinto de [respaldoDePrueba] en llave, partes y peso.
RespaldoEnDrive _respaldo(String llave, {int partes = 15, int mb = 38, int dia = 22}) =>
    RespaldoEnDrive(
      llave: llave,
      fecha: DateTime(2026, 10, dia, 3, 10),
      partes: partes,
      bytes: mb * 1024 * 1024,
      completo: true,
      tieneLlave: true,
    );

final _primero = _respaldo('llave-1');
final _segundo = _respaldo('llave-2', partes: 9, mb: 20, dia: 15);

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tocar(WidgetTester tester, Finder objetivo) async {
  await tester.ensureVisible(objetivo);
  await tester.tap(objetivo);
  await _asentar(tester);
}

/// 34·01 con varios → contraseña escrita.
Future<void> _aContrasena(WidgetTester tester, {String contrasena = 'la-de-antes'}) async {
  await _tocar(tester, cta);
  await tester.enterText(campoContrasena, contrasena);
  await _asentar(tester);
}

Future<void> _abrirCopias(WidgetTester tester) async {
  await _aContrasena(tester);
  await _tocar(tester, cta);
}

bool _apagado(WidgetTester tester, Finder boton) =>
    tester.widget<ButtonStyleButton>(boton).onPressed == null;

String _tituloActual(WidgetTester tester) => tester.widget<Text>(titulo).data!;

void main() {
  late ArnesRecuperacion arnes;

  setUp(() {
    arnes = ArnesRecuperacion();
    arnes.servicio.busqueda = VariosRespaldosEnDrive([_primero, _segundo]);
  });

  group('Varios respaldos: se ofrecen todos juntos', () {
    testWidgets('dado dos respaldos, cuando abro el asistente, entonces los veo y se traen todos', (
      tester,
    ) async {
      await abrirAsistente(tester, arnes);

      expect(_tituloActual(tester), 'Encontramos más de un respaldo');
      expect(tester.widget<Text>(paso).data, 'RECUPERAR · PASO 1 DE 3');
      expect(
        find.text(
          'Encontramos 2 respaldos de teléfonos que usaste antes. Los traemos todos juntos y los '
          'juntamos en este teléfono: no se borra nada. Tarda más porque se descarga todo.',
        ),
        findsOneWidget,
      );
      expect(tarjeta, findsNWidgets(2));
      expect(find.text('Respaldo del 22/10 a las 03:10'), findsOneWidget);
      expect(find.text('Respaldo del 15/10 a las 03:10'), findsOneWidget);
      expect(find.text('15 partes · 38 MB'), findsOneWidget);
      expect(find.text('9 partes · 20 MB'), findsOneWidget);
      expect(textoDe(cta), 'Recuperar todos mis datos');
      expect(textoDe(cta2), 'Empezar sin recuperar');
      expect(arnes.servicio.recuperaciones, 0, reason: 'mirar no baja ni toca nada');
    });

    testWidgets('«Recuperar todos mis datos» pide la contraseña de las copias, en plural', (
      tester,
    ) async {
      await abrirAsistente(tester, arnes);
      await _tocar(tester, cta);

      expect(tester.widget<Text>(paso).data, 'RECUPERAR · PASO 2 DE 3');
      expect(_tituloActual(tester), 'Abrí tus copias');
      expect(tarjeta, findsNWidgets(2));
      expect(find.text('La que usabas cuando se hicieron estos respaldos.'), findsOneWidget);
      // La confirmación previa de la HU, con el peso de todo lo que se descarga: 38 + 20 MB.
      expect(
        find.text('Vamos a restaurar 58 MB. La operación puede tardar varios minutos.'),
        findsOneWidget,
      );
      expect(textoDe(cta), 'Abrir copias');
      expect(_apagado(tester, cta), isTrue, reason: 'sin contraseña no se abre nada');
    });

    testWidgets('«Abrir copias» recupera todos los respaldos con una sola contraseña', (
      tester,
    ) async {
      await abrirAsistente(tester, arnes);
      await _abrirCopias(tester);

      expect(arnes.servicio.recuperaciones, 1);
      expect(arnes.servicio.ultimaContrasena, 'la-de-antes');
      expect(arnes.servicio.ultimosRespaldos.map((r) => r.llave), ['llave-1', 'llave-2']);
      expect(_tituloActual(tester), 'Tus datos están de vuelta');
    });

    testWidgets('el avance cuenta las partes de todos los respaldos juntos', (tester) async {
      arnes.servicio.frenarRecuperar = true;
      await abrirAsistente(tester, arnes);
      await _abrirCopias(tester);

      expect(_tituloActual(tester), 'Restaurando');
      expect(tester.widget<Text>(progresoValor).data, '0/24 partes');

      arnes.servicio.alAvanzarActual!(
        const ProgresoRecuperacion(PasoRecuperacion.bajando, hechas: 12, total: 24),
      );
      await _asentar(tester);
      expect(tester.widget<Text>(progresoValor).data, '12/24 partes');
      arnes.servicio.compuertaRecuperar!.complete();
      await _asentar(tester);
    });

    testWidgets('la contraseña que no abre las copias lo dice en plural y deja probar otra', (
      tester,
    ) async {
      arnes.servicio.resultado = const ContrasenaNoAbreElRespaldo();
      await abrirAsistente(tester, arnes);
      await _abrirCopias(tester);

      expect(_tituloActual(tester), 'Abrí tus copias');
      expect(
        tester.widget<Text>(errorContrasena).data,
        'Esta contraseña no abre tus copias; probá la que usabas cuando hiciste los últimos '
        'respaldos.',
      );
      expect(tarjeta, findsNWidgets(2), reason: 'siguen a la vista los respaldos que se abren');

      arnes.servicio.resultado = RecuperacionHecha(informeDePrueba());
      await tester.enterText(campoContrasena, 'la-buena');
      await _asentar(tester);
      expect(errorContrasena, findsNothing);
      await _tocar(tester, cta);
      expect(arnes.servicio.ultimaContrasena, 'la-buena');
      expect(arnes.servicio.ultimosRespaldos, hasLength(2));
      expect(_tituloActual(tester), 'Tus datos están de vuelta');
    });

    testWidgets('con un solo respaldo todo sigue en singular', (tester) async {
      arnes.servicio.busqueda = RespaldoEncontrado(_primero);
      await abrirAsistente(tester, arnes);

      expect(_tituloActual(tester), 'Encontramos un respaldo');
      expect(textoDe(cta), 'Recuperar mis datos');
      await _tocar(tester, cta);
      expect(_tituloActual(tester), 'Abrí tu copia');
      expect(textoDe(cta), 'Abrir copia');
      expect(find.text('La que usabas cuando se hizo este respaldo.'), findsOneWidget);
    });
  });

  group('Varios respaldos: casos límite', () {
    testWidgets('doble toque en «Recuperar todos» y en «Abrir copias»: una sola restauración', (
      tester,
    ) async {
      arnes.servicio.frenarRecuperar = true;
      await abrirAsistente(tester, arnes);

      await tester.tap(cta);
      await tester.tap(cta, warnIfMissed: false);
      await _asentar(tester);
      expect(_tituloActual(tester), 'Abrí tus copias');

      await tester.enterText(campoContrasena, 'la-de-antes');
      await _asentar(tester);
      await tester.tap(cta);
      await tester.tap(cta, warnIfMissed: false);
      await _asentar(tester);
      expect(arnes.servicio.recuperaciones, 1);
      arnes.servicio.compuertaRecuperar!.complete();
      await _asentar(tester);
    });

    testWidgets('falla a mitad: avisa, nada queda trabado y «Reintentar» vuelve a ofrecer todos', (
      tester,
    ) async {
      arnes.servicio.errorAlRecuperar = StateError('se cayó');
      await abrirAsistente(tester, arnes);
      await _abrirCopias(tester);

      expect(_tituloActual(tester), 'No pudimos recuperar tus datos');
      expect(_apagado(tester, cta), isFalse);
      expect(textoDe(cta), 'Reintentar');
      expect(textoDe(cta2), 'Empezar sin recuperar');

      arnes.servicio.errorAlRecuperar = null;
      await _tocar(tester, cta);
      expect(_tituloActual(tester), 'Encontramos más de un respaldo');
      expect(tarjeta, findsNWidgets(2));
      await _abrirCopias(tester);
      expect(arnes.servicio.recuperaciones, 2);
      expect(arnes.servicio.ultimosRespaldos, hasLength(2));
    });

    testWidgets('«Cancelar» mientras baja vuelve a ofrecer todos, no a un solo respaldo', (
      tester,
    ) async {
      arnes.servicio.frenarRecuperar = true;
      await abrirAsistente(tester, arnes);
      await _abrirCopias(tester);

      await _tocar(tester, cta2);
      arnes.servicio.compuertaRecuperar!.complete();
      await _asentar(tester);

      expect(arnes.servicio.ultimaCancelacion!.cancelada, isTrue);
      expect(_tituloActual(tester), 'Encontramos más de un respaldo');
      expect(tarjeta, findsNWidgets(2));
      expect(textoDe(cta), 'Recuperar todos mis datos');
    });

    testWidgets('se corta la conexión y se cancela la espera: vuelve a ofrecer todos', (
      tester,
    ) async {
      arnes.servicio.frenarRecuperar = true;
      arnes.servicio.progresos = const [
        ProgresoRecuperacion(
          PasoRecuperacion.bajando,
          hechas: 7,
          total: 24,
          esperandoConexion: true,
        ),
      ];
      await abrirAsistente(tester, arnes);
      await _abrirCopias(tester);
      expect(_tituloActual(tester), 'Se cortó la conexión');

      // La recuperación terminó sin conexión y la persona deja de esperar.
      arnes.servicio.resultado = const RecuperacionSinConexion(hechas: 7, total: 24);
      arnes.servicio.compuertaRecuperar!.complete();
      await _asentar(tester);
      await _tocar(tester, cta2);

      expect(_tituloActual(tester), 'Encontramos más de un respaldo');
      expect(tarjeta, findsNWidgets(2));
    });

    testWidgets('«Reintentar» después de cortarse retoma con todos los respaldos', (tester) async {
      arnes.servicio.resultado = const RecuperacionSinConexion(hechas: 7, total: 24);
      await abrirAsistente(tester, arnes);
      await _abrirCopias(tester);
      expect(_tituloActual(tester), 'Se cortó la conexión');
      expect(find.text('Quedó en la parte 7'), findsOneWidget);

      arnes.servicio.resultado = RecuperacionHecha(informeDePrueba());
      await _tocar(tester, cta);
      expect(arnes.servicio.recuperaciones, 2);
      expect(arnes.servicio.ultimosRespaldos, hasLength(2));
      expect(_tituloActual(tester), 'Tus datos están de vuelta');
    });

    testWidgets('una parte dañada: «Reintentar» vuelve a correr con todos los respaldos', (
      tester,
    ) async {
      arnes.servicio.resultado = RecuperacionHecha(
        informeDePrueba(parcial: true, restauradas: 11, totales: 24),
      );
      await abrirAsistente(tester, arnes);
      await _abrirCopias(tester);
      expect(_tituloActual(tester), 'Recuperamos casi todo');

      arnes.servicio.resultado = RecuperacionHecha(informeDePrueba());
      await _tocar(tester, cta3);
      expect(arnes.servicio.recuperaciones, 2);
      expect(arnes.servicio.ultimosRespaldos, hasLength(2));
      expect(_tituloActual(tester), 'Tus datos están de vuelta');
    });

    testWidgets('volver atrás y reentrar: empieza de cero, sin la contraseña y con todos', (
      tester,
    ) async {
      arnes.servicio.compuertaRecuperar = Completer<void>();
      await abrirAsistente(tester, arnes);
      await _abrirCopias(tester);
      final cancelacion = arnes.servicio.ultimaCancelacion!;

      await tester.pumpWidget(const SizedBox.shrink());
      expect(cancelacion.cancelada, isTrue, reason: 'salir corta la descarga');
      arnes.servicio.compuertaRecuperar!.complete();
      await tester.pump();

      arnes.servicio.compuertaRecuperar = null;
      await abrirAsistente(tester, arnes);
      expect(_tituloActual(tester), 'Encontramos más de un respaldo');
      await _tocar(tester, cta);
      expect(tester.widget<TextField>(campoContrasena).controller!.text, isEmpty);
    });

    testWidgets('una lista larga de respaldos con el texto al 200 %: se ve entera y sin romper', (
      tester,
    ) async {
      arnes.servicio.busqueda = VariosRespaldosEnDrive([
        for (var i = 1; i <= 8; i++) _respaldo('llave-$i', partes: i + 3, mb: i * 7, dia: i),
      ]);
      await abrirAsistente(tester, arnes, tamano: const Size(360, 640), escala: 2);

      expect(tester.takeException(), isNull);
      expect(tarjeta, findsNWidgets(8));
      expect(
        find.textContaining('Encontramos 8 respaldos de teléfonos que usaste antes'),
        findsOneWidget,
      );
      await tester.ensureVisible(cta);
      expect(tester.takeException(), isNull);
      expect(textoDe(cta), 'Recuperar todos mis datos');

      await _tocar(tester, cta);
      expect(tester.takeException(), isNull);
      // 7·(1+…+8) = 252 MB.
      expect(find.textContaining('Vamos a restaurar 252 MB.'), findsOneWidget);
    });
  });

  group('«Empezar sin recuperar» avisa que después solo se puede mientras no se cargue nada', () {
    testWidgets('dado el asistente, cuando toco «Empezar sin recuperar», entonces me avisa y no '
        'termina todavía', (tester) async {
      await abrirAsistente(tester, arnes);
      await tester.tap(cta2);
      await _asentar(tester);

      expect(hojaEmpezar, findsOneWidget);
      expect(find.text('¿Empezar sin recuperar?'), findsOneWidget);
      expect(
        find.text(
          'Podés traer tu respaldo después desde Configuración, en «Recuperar mi respaldo», '
          'mientras no hayas cargado nada en este teléfono. Una vez que cargues datos, ya no vas '
          'a poder traerlo.',
        ),
        findsOneWidget,
      );
      expect(arnes.resuelta.marcas, 0, reason: 'todavía no se resolvió nada');
    });

    testWidgets('«Volver» cierra el aviso y el asistente sigue donde estaba', (tester) async {
      await abrirAsistente(tester, arnes);
      await tester.tap(cta2);
      await _asentar(tester);

      await tester.tap(hojaVolver);
      await _asentar(tester);

      expect(hojaEmpezar, findsNothing);
      expect(pagina, findsOneWidget);
      expect(arnes.resuelta.marcas, 0);
      expect(_apagado(tester, cta2), isFalse, reason: 'el botón no queda trabado');
    });

    testWidgets('cerrar el aviso tocando afuera tampoco termina el asistente', (tester) async {
      await abrirAsistente(tester, arnes);
      await tester.tap(cta2);
      await _asentar(tester);

      await tester.tapAt(const Offset(195, 20));
      await _asentar(tester);

      expect(hojaEmpezar, findsNothing);
      expect(arnes.resuelta.marcas, 0);
      expect(_apagado(tester, cta2), isFalse);
    });

    testWidgets('«Empezar sin recuperar» de la hoja anota que se resolvió, una sola vez', (
      tester,
    ) async {
      await abrirAsistente(tester, arnes);
      await tester.tap(cta2);
      await _asentar(tester);

      await tester.tap(hojaConfirmar);
      await tester.tap(hojaConfirmar, warnIfMissed: false);
      await _asentar(tester);

      expect(hojaEmpezar, findsNothing);
      expect(pagina, findsOneWidget, reason: 'un doble toque no saca también la pantalla de abajo');
      expect(arnes.resuelta.marcas, 1);
      expect(arnes.resuelta.usuarios, {usuarioDePrueba});
    });

    testWidgets('dos toques seguidos en «Empezar sin recuperar» abren un solo aviso', (
      tester,
    ) async {
      await abrirAsistente(tester, arnes);
      await tester.tap(cta2);
      await tester.tap(cta2, warnIfMissed: false);
      await _asentar(tester);

      expect(hojaEmpezar, findsOneWidget);
      await tester.tap(hojaVolver);
      await _asentar(tester);
      expect(hojaEmpezar, findsNothing, reason: 'con un solo «Volver» no queda otro debajo');
    });

    for (final (nombre, preparar) in <(String, void Function(ArnesRecuperacion))>[
      ('34·02 Conectar', (a) => a.servicio.busqueda = const DriveSinPermiso()),
      ('34·09 Sin respaldo', (a) => a.servicio.busqueda = const SinRespaldoEnDrive()),
      ('34·10 Sin conexión', (a) => a.servicio.busqueda = const BusquedaSinConexion()),
      ('búsqueda fallida', (a) => a.servicio.busqueda = const BusquedaFallida()),
      ('34·03 Contraseña', (a) => a.servicio.busqueda = RespaldoEncontrado(_primero)),
      ('varios respaldos', (a) {}),
    ]) {
      testWidgets('también avisa desde $nombre', (tester) async {
        preparar(arnes);
        await abrirAsistente(tester, arnes);
        if (nombre == '34·03 Contraseña') await _tocar(tester, cta);

        await tester.tap(cta2);
        await _asentar(tester);

        expect(hojaEmpezar, findsOneWidget);
        await tester.tap(hojaConfirmar);
        await _asentar(tester);
        expect(arnes.resuelta.usuarios, {usuarioDePrueba});
      });
    }

    testWidgets('a 320 dp con el texto al 200 % el aviso se lee entero y se puede tocar todo', (
      tester,
    ) async {
      await abrirAsistente(tester, arnes, tamano: const Size(320, 568), escala: 2);
      await _tocar(tester, cta2);

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(hojaConfirmar);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(hojaVolver).height,
        greaterThanOrEqualTo(52),
        reason: 'el botón es cómodo de tocar',
      );
      await tester.tap(hojaVolver);
      await _asentar(tester);
      expect(hojaEmpezar, findsNothing);
    });

    testWidgets(
      'con el almacén tardando en anotar, «Empezar sin recuperar» no lanza ni se repite',
      (tester) async {
        arnes.resuelta.compuertaMarcar = Completer<void>();
        await abrirAsistente(tester, arnes);
        await tester.tap(cta2);
        await _asentar(tester);
        await tester.tap(hojaConfirmar);
        await _asentar(tester);

        expect(arnes.resuelta.marcas, 1);
        arnes.resuelta.compuertaMarcar!.complete();
        await _asentar(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
