// QA de «Recuperar mis datos en un celular nuevo» (vista 34, HU-SYNC-006, #175): el texto literal de
// cada artboard y de cada escenario de la HU, los casos límite de cada flujo, el tamaño de la
// pantalla con texto grande, el lector de pantalla y la privacidad de la contraseña.
//
// Los casos que dejan un hallazgo van con `skip` (se corren con `--dart-define=QA_HALLAZGOS=true`).
// Las capturas solo con `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas`).
import 'dart:async';

import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/respaldo/domain/repositories/recuperacion_resuelta_repository.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/asistente_recuperacion_notifier.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/recuperacion_pendiente_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_recuperacion_175_arnes.dart';

const verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// ¿Algún nodo de semántica por encima de [texto] es una región viva (se anuncia solo)?
bool esRegionViva(WidgetTester tester, Finder texto) {
  var n = tester.getSemantics(texto);
  while (true) {
    if (n.flagsCollection.isLiveRegion) return true;
    final padre = n.parent;
    if (padre == null) return false;
    n = padre;
  }
}

/// Un almacén de «resuelto» que falla al anotar (el almacén seguro rechaza la escritura).
final class ResueltaQueFalla implements RecuperacionResueltaRepository {
  int marcas = 0;

  @override
  Future<bool> estaResuelta(String usuarioId) async => false;

  @override
  Future<void> marcarResuelta(String usuarioId) async {
    marcas++;
    throw StateError('el almacén seguro no deja escribir');
  }
}

void main() {
  // ---------------------------------------------------------------------------------------------
  // 0 · Cobertura del canvas: cada artboard con su texto literal.
  group('Cobertura del canvas: texto literal de cada artboard', () {
    final tabla = <Estado175, ({String paso, String titulo, String cta, String? cta2})>{
      Estado175.c01Encontrado: (
        paso: 'RECUPERAR · PASO 1 DE 3',
        titulo: 'Encontramos un respaldo',
        cta: 'Recuperar mis datos',
        cta2: 'Empezar sin recuperar',
      ),
      Estado175.c02Conectar: (
        paso: 'RECUPERAR · PASO 1 DE 3',
        titulo: 'Buscá tu respaldo',
        cta: 'Conectar con Google',
        cta2: 'Empezar sin recuperar',
      ),
      Estado175.c03Contrasena: (
        paso: 'RECUPERAR · PASO 2 DE 3',
        titulo: 'Abrí tu copia',
        cta: 'Abrir copia',
        cta2: 'Empezar sin recuperar',
      ),
      Estado175.c04Distinta: (
        paso: 'RECUPERAR · PASO 2 DE 3',
        titulo: 'Abrí tu copia',
        cta: 'Abrir copia',
        cta2: 'Empezar sin recuperar',
      ),
      Estado175.c05Restaurando: (
        paso: 'RECUPERAR · PASO 3 DE 3',
        titulo: 'Restaurando',
        cta: 'Restaurando…',
        cta2: 'Cancelar',
      ),
      Estado175.c06Reintentar: (
        paso: 'RECUPERAR · PASO 3 DE 3',
        titulo: 'Se cortó la conexión',
        cta: 'Reintentar',
        cta2: 'Cancelar',
      ),
      Estado175.c07Parcial: (
        paso: 'RECUPERAR · PASO 3 DE 3',
        titulo: 'Recuperamos casi todo',
        cta: 'Seguir con lo recuperado',
        cta2: 'Ver qué quedó afuera',
      ),
      Estado175.c08Listo: (
        paso: 'RECUPERAR · PASO 3 DE 3',
        titulo: 'Tus datos están de vuelta',
        cta: 'Ir a mi inicio',
        cta2: null,
      ),
      Estado175.c09SinRespaldo: (
        paso: 'RECUPERAR · PASO 1 DE 3',
        titulo: 'No encontramos un respaldo',
        cta: 'Probar con otra cuenta',
        cta2: 'Empezar sin recuperar',
      ),
      Estado175.c10SinConexion: (
        paso: 'RECUPERAR · PASO 1 DE 3',
        titulo: 'Recuperar mis datos',
        cta: 'Reintentar',
        cta2: 'Empezar sin recuperar',
      ),
    };
    for (final e in tabla.entries) {
      testWidgets(
        'dado ${e.key.rotulo}, cuando se muestra, entonces dice paso, título y botones del canvas',
        (tester) async {
          final a = await llegarA175(tester, e.key);
          expect(tester.widget<Text>(paso).data, e.value.paso);
          expect(tester.widget<Text>(titulo).data, e.value.titulo);
          expect(textoDe(cta), e.value.cta);
          if (e.value.cta2 == null) {
            expect(cta2, findsNothing);
          } else {
            expect(textoDe(cta2), e.value.cta2);
          }
          await liberar175(tester, a);
        },
      );
    }

    testWidgets('34·01: el texto, la tarjeta del respaldo y el peso del canvas', (tester) async {
      final a = await llegarA175(tester, Estado175.c01Encontrado);
      expect(
        find.text(
          'Podés traer a este teléfono todo lo que tenías: ubicaciones, personas, notas, ventas y '
          'cobros.',
        ),
        findsOneWidget,
      );
      expect(find.text('Respaldo del 22/10 a las 03:10'), findsOneWidget);
      expect(find.text('15 partes · 38 MB'), findsOneWidget);
      await liberar175(tester, a);
    });

    testWidgets('34·02: el texto (con la decisión del 31/10 que no afirma un respaldo)', (
      tester,
    ) async {
      final a = await llegarA175(tester, Estado175.c02Conectar);
      expect(
        find.text(
          'Si ya usaste Colportaje en otro teléfono, tu respaldo está en tu Google Drive. Conectalo '
          'para buscarlo; solo esta app puede abrir esos archivos. Si es la primera vez que usás '
          'la app, tocá «Empezar sin recuperar».',
        ),
        findsOneWidget,
      );
      await liberar175(tester, a);
    });

    testWidgets('34·03: ayuda del campo y confirmación previa de la HU («X MB»)', (tester) async {
      final a = await llegarA175(tester, Estado175.c03Contrasena);
      expect(find.text('CONTRASEÑA'), findsOneWidget);
      expect(find.text('La que usabas cuando se hizo este respaldo.'), findsOneWidget);
      expect(
        find.text('Vamos a restaurar 38 MB. La operación puede tardar varios minutos.'),
        findsOneWidget,
      );
      await liberar175(tester, a);
    });

    testWidgets('34·04: el texto del error es el de la HU (R32) y lo escrito no se pierde', (
      tester,
    ) async {
      final a = await llegarA175(tester, Estado175.c04Distinta);
      expect(
        find.text(
          'Esta contraseña no abre tu copia; probá la que usabas cuando hiciste el último respaldo.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(campoContrasena).controller!.text, 'la-de-antes');
      await liberar175(tester, a);
    });

    testWidgets('34·05: «12/15 partes» y el aviso de que lo anterior no se toca', (tester) async {
      final a = await llegarA175(tester, Estado175.c05Restaurando);
      expect(tester.widget<Text>(progresoValor).data, '12/15 partes');
      expect(
        find.text(
          'Lo que había en este teléfono no se toca hasta que termine. Si se corta, no se pierde '
          'nada.',
        ),
        findsOneWidget,
      );
      await liberar175(tester, a);
    });

    testWidgets('34·06: «Quedó en la parte 12» y el aviso con el texto del canvas', (tester) async {
      final a = await llegarA175(tester, Estado175.c06Reintentar);
      expect(find.text('Quedó en la parte 12'), findsOneWidget);
      expect(
        find.text(
          'Se cortó la conexión. Lo que tenías antes en el teléfono no se tocó. Cuando vuelva, '
          'seguimos desde la parte 12.',
        ),
        findsOneWidget,
      );
      await liberar175(tester, a);
    });

    testWidgets('34·07: parte dañada, qué quedó afuera y qué se restauró', (tester) async {
      final a = await llegarA175(tester, Estado175.c07Parcial);
      expect(find.textContaining('La parte 14 de 15 está dañada'), findsOneWidget);
      expect(find.textContaining('Restauramos todo hasta el 21/10 a las 03:10'), findsOneWidget);
      expect(find.text('Quedó afuera'), findsOneWidget);
      expect(find.text('Restaurado'), findsOneWidget);
      expect(find.text('Todo lo anterior'), findsOneWidget);
      expect(find.textContaining('Si tenés el teléfono viejo'), findsOneWidget);
      await liberar175(tester, a);
    });

    testWidgets('34·08: «Como el 22/10 a las 03:10» y las cuatro cantidades', (tester) async {
      final a = await llegarA175(tester, Estado175.c08Listo);
      expect(tester.widget<Text>(heroTexto).data, 'Como el 22/10 a las 03:10');
      for (final (rotulo, valor) in [
        ('Ubicaciones', '214'),
        ('Personas', '96'),
        ('Ventas', '41'),
        ('Cobros', '63'),
      ]) {
        expect(find.text(rotulo), findsOneWidget);
        expect(find.text(valor), findsOneWidget);
      }
      await liberar175(tester, a);
    });

    testWidgets('34·09: el texto del canvas con la cuenta que se probó', (tester) async {
      final a = await llegarA175(tester, Estado175.c09SinRespaldo);
      expect(find.textContaining('no hay un respaldo de Colportaje'), findsOneWidget);
      expect(
        find.textContaining('Si lo hiciste con otra cuenta de Google, probá con esa.'),
        findsOneWidget,
      );
      await liberar175(tester, a);
    });

    testWidgets('34·10: «Necesitás conexión (mejor Wi-Fi) para traer tu respaldo.»', (
      tester,
    ) async {
      final a = await llegarA175(tester, Estado175.c10SinConexion);
      expect(find.text('Necesitás conexión (mejor Wi-Fi) para traer tu respaldo.'), findsOneWidget);
      expect(botonApagado175(tester, cta), isTrue);
      await liberar175(tester, a);
    });
  });

  // ---------------------------------------------------------------------------------------------
  // 1 · Escenarios de la HU (Dado / Cuando / Entonces).
  group('HU-SYNC-006: escenarios', () {
    testWidgets(
      'Restore completo: dado un respaldo, cuando abro la copia con mi contraseña, entonces se '
      'muestra lo que volvió y «Ir a mi inicio» sigue',
      (tester) async {
        final a = await llegarA175(tester, Estado175.c01Encontrado);
        await abrirCopia175(tester);
        expect(a.servicio.recuperaciones, 1);
        expect(a.servicio.ultimaContrasena, 'la-de-antes');
        expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
        expect(a.resuelta.usuarios, {
          usuarioDePrueba,
        }, reason: 'ya hay datos: no se vuelve a ofrecer');
        await liberar175(tester, a);
      },
    );

    testWidgets(
      'Versión más nueva: el texto es el de la HU, hay botón «Actualizar» y no se marca como '
      'resuelto (la base queda intacta)',
      (tester) async {
        final a = await llegarA175(tester, Estado175.versionNueva);
        expect(
          find.text(
            'Tus datos son de una versión más nueva de la app. Actualizala para seguir usando tus '
            'datos.',
          ),
          findsOneWidget,
        );
        expect(textoDe(cta), 'Actualizar');
        expect(a.resuelta.usuarios, isEmpty);
        await liberar175(tester, a);
      },
    );

    testWidgets(
      'Patch corrupto: dado un respaldo con una parte dañada, entonces dice hasta cuándo se '
      'restauró y deja continuar',
      (tester) async {
        final a = await llegarA175(tester, Estado175.c07Parcial);
        expect(find.textContaining('hasta el 21/10 a las 03:10'), findsOneWidget);
        expect(textoDe(cta), 'Seguir con lo recuperado');
        // La HU pide «Reintentar» o «Aceptar y continuar»; el canvas solo dibuja el segundo y la
        // decisión del 31/10 (comentario #6540829396) suma «Reintentar» como tercera acción.
        expect(textoDe(cta3), 'Reintentar');
        await liberar175(tester, a);
      },
    );

    testWidgets(
      'Fallo de red: dado que se corta a mitad, entonces pausa y «Reintentar» sigue desde donde '
      'quedó con la misma contraseña',
      (tester) async {
        final a = await llegarA175(tester, Estado175.c06Reintentar);
        a.servicio.resultado = RecuperacionHecha(informeDePrueba());
        await tocar175(tester, cta);
        expect(a.servicio.recuperaciones, 2);
        expect(a.servicio.ultimaContrasena, 'la-de-antes');
        expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
        await liberar175(tester, a);
      },
    );

    testWidgets(
      'Cancelación: dado que estoy a mitad, cuando toco «Cancelar», entonces se corta, no se anota '
      'nada y puedo volver a empezar',
      (tester) async {
        final a = await llegarA175(tester, Estado175.c05Restaurando);
        await tocar175(tester, cta2);
        a.servicio.compuertaRecuperar!.complete();
        await asentar175(tester);
        expect(a.servicio.ultimaCancelacion!.cancelada, isTrue);
        expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
        expect(a.resuelta.usuarios, isEmpty);

        // Empezar de nuevo funciona: otra contraseña, otra restauración.
        a.servicio.frenarRecuperar = false;
        a.servicio.compuertaRecuperar = null;
        a.servicio.resultado = RecuperacionHecha(informeDePrueba());
        await abrirCopia175(tester, contrasena: 'otra');
        expect(a.servicio.recuperaciones, 2);
        expect(a.servicio.ultimaContrasena, 'otra');
        expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
        await liberar175(tester, a);
      },
    );
  });

  // ---------------------------------------------------------------------------------------------
  // 2 · Validación de la contraseña (el único campo).
  group('Contraseña: validación de entradas', () {
    testWidgets('vacía: «Abrir copia» apagado y Enter no hace nada', (tester) async {
      final a = await llegarA175(tester, Estado175.c01Encontrado);
      await tocar175(tester, cta);
      expect(botonApagado175(tester, cta), isTrue);
      await tester.tap(campoContrasena);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await asentar175(tester);
      expect(a.servicio.recuperaciones, 0);
      await liberar175(tester, a);
    });

    for (final (nombre, contrasena) in [
      ('solo espacios', '   '),
      ('con espacios al borde', '  clave con espacios  '),
      ('con emoji', 'clave🔐🙂'),
      ('con caracteres especiales', r'Ñandú-ü"\\<>&%$#@!'),
      ('de 300 caracteres pegada', 'a' * 300),
    ]) {
      testWidgets('$nombre: se manda tal cual, sin recortar ni cambiar', (tester) async {
        final a = await llegarA175(tester, Estado175.c01Encontrado);
        await abrirCopia175(tester, contrasena: contrasena);
        expect(a.servicio.ultimaContrasena, contrasena);
        await liberar175(tester, a);
      });
    }

    testWidgets('Enter con texto abre la copia una sola vez aunque se toque el botón', (
      tester,
    ) async {
      final a = await llegarA175(tester, Estado175.c01Encontrado);
      a.servicio.frenarRecuperar = true;
      await irAContrasena175(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.tap(cta, warnIfMissed: false);
      await asentar175(tester);
      expect(a.servicio.recuperaciones, 1);
      await liberar175(tester, a);
    });

    testWidgets('después de «no abre la copia»: lo tipeado sigue, editar saca el aviso y se puede '
        'volver a intentar', (tester) async {
      final a = await llegarA175(tester, Estado175.c04Distinta);
      expect(find.byKey(const Key('recuperacion_contrasena_error')), findsOneWidget);
      await tester.enterText(campoContrasena, 'la-de-antes!');
      await asentar175(tester);
      expect(find.byKey(const Key('recuperacion_contrasena_error')), findsNothing);
      expect(botonApagado175(tester, cta), isFalse);
      a.servicio.resultado = RecuperacionHecha(informeDePrueba());
      await tocar175(tester, cta);
      expect(a.servicio.ultimaContrasena, 'la-de-antes!');
      expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
      await liberar175(tester, a);
    });

    testWidgets(
      'dos contraseñas equivocadas seguidas: el aviso vuelve y el botón no queda ocupado',
      (tester) async {
        final a = await llegarA175(tester, Estado175.c04Distinta);
        await tester.enterText(campoContrasena, 'otra-mala');
        await asentar175(tester);
        await tocar175(tester, cta);
        expect(find.byKey(const Key('recuperacion_contrasena_error')), findsOneWidget);
        expect(botonApagado175(tester, cta), isFalse);
        expect(a.servicio.recuperaciones, 2);
        await liberar175(tester, a);
      },
    );

    testWidgets('el ojo muestra y oculta con su tooltip', (tester) async {
      final a = await llegarA175(tester, Estado175.c03Contrasena);
      expect(tester.widget<TextField>(campoContrasena).obscureText, isTrue);
      expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
      await tocar175(tester, verContrasena);
      expect(tester.widget<TextField>(campoContrasena).obscureText, isFalse);
      expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
      await liberar175(tester, a);
    });
  });

  // ---------------------------------------------------------------------------------------------
  // 3 · Casos límite de cada flujo.
  group('Casos límite', () {
    testWidgets('falla a mitad (el servicio lanza): ningún estado «ocupado» queda trabado y se '
        'puede reintentar', (tester) async {
      final a = await llegarA175(tester, Estado175.c01Encontrado);
      a.servicio.errorAlRecuperar = StateError('se cayó el disco');
      await abrirCopia175(tester);
      expect(tester.widget<Text>(titulo).data, 'No pudimos recuperar tus datos');
      expect(botonApagado175(tester, cta), isFalse);
      expect(botonApagado175(tester, cta2), isFalse);
      a.servicio.errorAlRecuperar = null;
      await tocar175(tester, cta);
      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
      await liberar175(tester, a);
    });

    testWidgets('«Cancelar» dos veces seguidas corta una sola vez y el botón queda apagado', (
      tester,
    ) async {
      final a = await llegarA175(tester, Estado175.c05Restaurando);
      await tester.tap(cta2);
      await tester.pump();
      expect(botonApagado175(tester, cta2), isTrue);
      await tester.tap(cta2, warnIfMissed: false);
      a.servicio.compuertaRecuperar!.complete();
      await asentar175(tester);
      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
      expect(a.servicio.recuperaciones, 1);
      await liberar175(tester, a);
    });

    testWidgets('mientras restaura no hay «Empezar sin recuperar» (no se puede salir a mitad)', (
      tester,
    ) async {
      final a = await llegarA175(tester, Estado175.c05Restaurando);
      expect(find.text('Empezar sin recuperar'), findsNothing);
      await liberar175(tester, a);
    });

    testWidgets('armando la copia ya no se puede cancelar: no hay botón «Cancelar»', (
      tester,
    ) async {
      final a = await llegarA175(tester, Estado175.c05Aplicando);
      expect(find.text('Cancelar'), findsNothing);
      expect(find.text('Armando tu copia…'), findsOneWidget);
      await liberar175(tester, a);
    });

    testWidgets('«Reintentar» de 34·06 con doble toque restaura una sola vez más', (tester) async {
      final a = await llegarA175(tester, Estado175.c06Reintentar);
      a.servicio.frenarRecuperar = true;
      await tester.tap(cta);
      await tester.tap(cta, warnIfMissed: false);
      await asentar175(tester);
      expect(a.servicio.recuperaciones, 2);
      await liberar175(tester, a);
    });

    testWidgets('«Empezar sin recuperar» mientras busca: sigue la app y la búsqueda tardía no '
        'rompe nada', (tester) async {
      final a = await llegarA175(tester, Estado175.buscando);
      await tocar175(tester, cta2);
      expect(a.resuelta.usuarios, {usuarioDePrueba});
      a.servicio.compuertaBuscar!.complete();
      await asentar175(tester);
      expect(tester.takeException(), isNull);
      await liberar175(tester, a);
    });

    testWidgets('la conexión se va con el respaldo a la vista: «Abrir copia» sin red cae en 34·06 '
        'y al volver se puede reintentar', (tester) async {
      final a = await llegarA175(tester, Estado175.c01Encontrado);
      a.conexion.cambiarA(TipoConexion.sinConexion);
      await asentar175(tester);
      a.servicio.resultado = const RecuperacionSinConexion(hechas: 0, total: 15);
      await abrirCopia175(tester);
      expect(tester.widget<Text>(titulo).data, 'Se cortó la conexión');
      expect(find.text('Todavía no bajamos ninguna parte'), findsOneWidget);
      expect(botonApagado175(tester, cta), isTrue);
      a.conexion.cambiarA(TipoConexion.wifi);
      await asentar175(tester);
      expect(botonApagado175(tester, cta), isFalse);
      await liberar175(tester, a);
    });

    testWidgets('sin respaldo → «Probar con otra cuenta» y Google cancelado deja el aviso sin '
        'trabar el botón', (tester) async {
      final a = await llegarA175(tester, Estado175.c09SinRespaldo);
      a.drive.google.errorAlConectar = null;
      a.servicio.busqueda = const SinRespaldoEnDrive();
      await tocar175(tester, cta);
      expect(botonApagado175(tester, cta), isFalse);
      expect(a.servicio.busquedas, greaterThanOrEqualTo(2));
      await liberar175(tester, a);
    });

    testWidgets('«Seguir con lo recuperado» (34·07) y «Ir a mi inicio» (34·08): un doble toque '
        'anota una sola vez', (tester) async {
      for (final estado in [Estado175.c07Parcial, Estado175.c08Listo]) {
        final a = await llegarA175(tester, estado);
        final marcasAntes = a.resuelta.marcas;
        a.resuelta.compuertaMarcar = Completer<void>();
        await tester.tap(cta);
        await tester.tap(cta, warnIfMissed: false);
        await asentar175(tester);
        expect(a.resuelta.marcas - marcasAntes, 1, reason: estado.rotulo);
        a.resuelta.compuertaMarcar!.complete();
        await liberar175(tester, a);
      }
    });

    testWidgets('34·07 «Reintentar» que falla: vuelve a 34·07 con el aviso, sin botón trabado y lo '
        'recuperado sigue ahí', (tester) async {
      final a = await llegarA175(tester, Estado175.c07ReintentoFallido);
      expect(tester.widget<Text>(titulo).data, 'Recuperamos casi todo');
      expect(
        find.text('No pudimos reintentar. Lo que ya recuperaste sigue en este teléfono.'),
        findsOneWidget,
      );
      for (final b in [cta, cta2, cta3]) {
        expect(botonApagado175(tester, b), isFalse);
      }
      // Se puede volver a intentar y esta vez termina.
      a.servicio.resultado = RecuperacionHecha(informeDePrueba());
      await tocar175(tester, cta3);
      expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
      expect(a.servicio.recuperaciones, 3);
      await liberar175(tester, a);
    });

    testWidgets('34·07 «Reintentar» con doble toque corre una sola vez más y muestra «Restaurando» '
        'con «Cancelar»; cancelar vuelve a 34·07', (tester) async {
      final a = await llegarA175(tester, Estado175.c07Parcial);
      a.servicio.frenarRecuperar = true;
      await tester.ensureVisible(cta3);
      await tester.tap(cta3);
      await tester.tap(cta3, warnIfMissed: false);
      await asentar175(tester);
      expect(a.servicio.recuperaciones, 2);
      expect(tester.widget<Text>(titulo).data, 'Restaurando');
      expect(textoDe(cta2), 'Cancelar');
      await tocar175(tester, cta2);
      a.servicio.compuertaRecuperar!.complete();
      await asentar175(tester);
      expect(tester.widget<Text>(titulo).data, 'Recuperamos casi todo');
      expect(botonApagado175(tester, cta), isFalse);
      await liberar175(tester, a);
    });

    testWidgets('un respaldo de una sola parte y de 0 bytes no rompen la tarjeta', (tester) async {
      final a = ArnesRecuperacion();
      a.servicio.busqueda = RespaldoEncontrado(
        RespaldoEnDrive(
          llave: 'k',
          fecha: DateTime(2026, 1, 2, 3, 4),
          partes: 1,
          bytes: 0,
          completo: true,
          tieneLlave: true,
        ),
      );
      await abrirAsistente175(tester, a);
      expect(find.text('1 parte · 0 MB'), findsOneWidget);
      await liberar175(tester, a);
    });
  });

  // ---------------------------------------------------------------------------------------------
  // 4 · Hallazgos (el estado actual de la rama; con skip hasta que se arreglen).
  group('Hallazgos', () {
    // skip: QA #175: si el almacén seguro no deja anotar «resuelto» después de restaurar, la
    // pantalla dice «No pudimos recuperar… No se tocó nada de tu teléfono» con los datos ya traídos.
    testWidgets('H1: restaurar bien pero fallar al anotar «resuelto» no dice que no se tocó nada', (
      tester,
    ) async {
      final a = ArnesRecuperacion();
      final resuelta = ResueltaQueFalla();
      await _abrirConResuelta(tester, a, resuelta);
      await abrirCopia175(tester);
      // Los datos ya volvieron: la pantalla no puede decir lo contrario.
      expect(find.textContaining('No se tocó nada de tu teléfono'), findsNothing);
      expect(tester.widget<Text>(titulo).data, isNot('No pudimos recuperar tus datos'));
      await liberar175(tester, a);
    });

    // QA #175 (decidido §2): «Ir a mi inicio»/«Empezar sin recuperar» con el almacén seguro fallando
    // no lanza ni muestra aviso (la persona no puede hacer nada): solo un log y la app sigue.
    testWidgets(
      'H2: «Empezar sin recuperar» con el almacén fallando no lanza y la app sigue sin aviso',
      (tester) async {
        final a = ArnesRecuperacion();
        final resuelta = ResueltaQueFalla();
        await _abrirConResuelta(tester, a, resuelta);
        final c = ProviderScope.containerOf(tester.element(pagina));
        await c.read(sesionProvider.future);
        expect(await c.read(recuperacionPendienteProvider.future), isTrue);

        await tocar175(tester, cta2);

        expect(tester.takeException(), isNull, reason: 'la falla no sale sin atrapar');
        expect(resuelta.marcas, 1);
        expect(c.read(recuperacionPendienteProvider).value, isFalse, reason: 'la raíz sigue');
        expect(botonApagado175(tester, cta2), isFalse, reason: 'el botón no queda trabado');
        expect(find.textContaining('No pudimos'), findsNothing, reason: 'sin aviso inútil');
        await liberar175(tester, a);
      },
    );
    // skip: QA #175: 34·08 «Listo» pinta el círculo con la tilde y «Como el 22/10…» pegados a la
    // izquierda; en el canvas (bloque `hero`) van centrados en la pantalla.
    testWidgets('H3: 34·08 el círculo y «Como el…» van centrados, como en el canvas', (
      tester,
    ) async {
      final a = await llegarA175(tester, Estado175.c08Listo);
      final centro = tester.getCenter(find.byKey(const Key('recuperacion_hero'))).dx;
      final mitad = tester.view.physicalSize.width / tester.view.devicePixelRatio / 2;
      expect(
        centro,
        closeTo(mitad, 2),
        reason: 'hero en $centro, la pantalla tiene su centro en $mitad',
      );
      await liberar175(tester, a);
    }, skip: !verHallazgos);
  });

  // ---------------------------------------------------------------------------------------------
  // 5 · Lector de pantalla.
  group('Lector de pantalla', () {
    testWidgets('el título es un encabezado y el error de la contraseña se anuncia solo', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      final a = await llegarA175(tester, Estado175.c04Distinta);
      expect(tester.getSemantics(titulo), isSemantics(isHeader: true));
      expect(
        esRegionViva(
          tester,
          find.text(
            'Esta contraseña no abre tu copia; probá la que usabas cuando hiciste el último '
            'respaldo.',
          ),
        ),
        isTrue,
      );
      await liberar175(tester, a);
      h.dispose();
    });

    for (final (estado, texto) in [
      (Estado175.c10SinConexion, 'Necesitás conexión (mejor Wi-Fi) para traer tu respaldo.'),
      (Estado175.c05Restaurando, 'Lo que había en este teléfono no se toca'),
      (Estado175.c06Reintentar, 'Se cortó la conexión. Lo que tenías antes'),
      (Estado175.c07Parcial, 'La parte 14 de 15 está dañada'),
      (Estado175.c07ReintentoFallido, 'No pudimos reintentar'),
      (Estado175.c02ConAviso, 'No conectamos tu Drive'),
      (Estado175.sinPermiso, 'Google ya no nos deja abrir tu Drive'),
    ]) {
      testWidgets('${estado.rotulo}: el aviso es una región viva', (tester) async {
        final h = tester.ensureSemantics();
        final a = await llegarA175(tester, estado);
        expect(esRegionViva(tester, find.textContaining(texto)), isTrue);
        await liberar175(tester, a);
        h.dispose();
      });
    }

    testWidgets('«Buscando…» se anuncia (región viva) y la barra de progreso tiene su rótulo', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      var a = await llegarA175(tester, Estado175.buscando);
      expect(
        esRegionViva(tester, find.textContaining('Buscando tu respaldo en Google Drive')),
        isTrue,
      );
      await liberar175(tester, a);
      a = await llegarA175(tester, Estado175.c05Restaurando);
      expect(
        tester.getSemantics(find.byKey(const Key('recuperacion_progreso'))).label,
        contains('Bajando partes…, 12/15 partes'),
      );
      await liberar175(tester, a);
      h.dispose();
    });

    testWidgets('el botón apagado de 34·05 («Restaurando…») se lee como botón no habilitado', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      final a = await llegarA175(tester, Estado175.c05Restaurando);
      expect(tester.getSemantics(cta), isSemantics(isButton: true, isEnabled: false));
      await liberar175(tester, a);
      h.dispose();
    });
  });

  // ---------------------------------------------------------------------------------------------
  // 6 · Tamaños y texto grande (sin overflow ni texto cortado, todo alcanzable).
  group('Tamaños', () {
    for (final tamano in [chico175, grande175]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado175.values) {
          testWidgets(
            '${estado.rotulo} · ${sufijo175(tamano, escala)}: sin overflow ni texto cortado, '
            'botones alcanzables',
            (tester) async {
              final a = await llegarA175(tester, estado, tamano: tamano, escala: escala);
              expect(tester.takeException(), isNull);
              sinTextoCortado175(tester);
              for (final boton in [cta, cta2, cta3]) {
                if (boton.evaluate().isEmpty) continue;
                await tester.ensureVisible(boton);
                await tester.pump();
                final r = tester.getRect(boton);
                final v = tester.view.physicalSize / tester.view.devicePixelRatio;
                expect(r.left >= 0 && r.right <= v.width, isTrue, reason: 'ancho de ${r.size}');
                expect(r.top >= 0 && r.bottom <= v.height, isTrue, reason: 'alto: $r');
              }
              await capturar175(tester, '${estado.name}_${sufijo175(tamano, escala)}');
              await liberar175(tester, a);
            },
          );
        }
      }
    }

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        '34·03 con el teclado abierto (280 dp) a 360×640 ×$escala: el campo y el botón se '
        'alcanzan y no hay overflow',
        (tester) async {
          final a = await llegarA175(tester, Estado175.c03Contrasena, escala: escala);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          addTearDown(tester.view.resetViewInsets);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(campoContrasena);
          await tester.pump();
          await tester.ensureVisible(cta);
          await tester.pump();
          final v = tester.view.physicalSize / tester.view.devicePixelRatio;
          final util = v.height - 280;
          expect(
            tester.getRect(cta).bottom <= util + 0.5,
            isTrue,
            reason: 'el botón queda bajo el teclado',
          );
          await capturar175(tester, 'teclado_x$escala');
          await liberar175(tester, a);
        },
      );
    }
  });

  // ---------------------------------------------------------------------------------------------
  // 7 · Privacidad.
  group('Privacidad', () {
    testWidgets('la contraseña no está en el estado del asistente ni en su toString', (
      tester,
    ) async {
      final a = await llegarA175(tester, Estado175.c05Restaurando);
      final contexto = tester.element(pagina);
      final estado = ProviderScope.containerOf(contexto).read(asistenteRecuperacionProvider);
      expect(estado.toString().contains('la-de-antes'), isFalse);
      expect(estado.props.any((p) => '$p'.contains('la-de-antes')), isFalse);
      await liberar175(tester, a);
    });

    test('InformeRecuperacion y RespaldoEnDrive no vuelcan datos de personas en toString', () {
      final texto = '${informeDePrueba()} $respaldoDePrueba';
      expect(texto.contains('@'), isFalse);
    });
  });
}

/// El asistente con un almacén de «resuelto» propio (para hacerlo fallar).
Future<void> _abrirConResuelta(
  WidgetTester tester,
  ArnesRecuperacion a,
  RecuperacionResueltaRepository resuelta,
) async {
  await abrirAsistente175(tester, a, resuelta: resuelta);
}
