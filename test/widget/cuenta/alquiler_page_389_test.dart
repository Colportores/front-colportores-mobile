// «Mi alquiler» (vista 38C, HU-CTA-007, #389): un test por artboard (38C·01 a 38C·05), los estados que el
// canvas no dibuja (cargando, error, pagado de más, rechazado, devuelto, dos campañas) y los casos
// límite de cada flujo: el doble toque en «Cargar pago de alquiler», volver atrás y reentrar, el
// «Reintentar» del error, la lista larga, los textos largos y el texto al 200 %.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/alquiler.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/alquiler_page.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alquiler_arnes.dart';
import '../../helpers/deposito_arnes.dart';

Future<void> _con(WidgetTester tester, AlquilerDelColportor alquiler, {double escala = 1}) async {
  await montarAlquiler(tester, RepositorioDeAlquilerControlable(inicial: alquiler), escala: escala);
}

void main() {
  group('38C·01 · Deuda de alquiler', () {
    testWidgets(
      'dado que mi campaña cobra \$ 18.500 y pagué \$ 6.000, cuando abro «Alquiler», veo lo '
      'que me falta, el monto, lo pagado y el pago',
      (tester) async {
        await _con(tester, alquilerDelCanvas);

        expect(find.text('MI CUENTA'), findsOneWidget);
        expect(find.text('Alquiler'), findsOneWidget);
        expect(find.text('Primavera 2026 · monto fijo por campaña'), findsOneWidget);
        expect(find.text('TE FALTA PAGAR'), findsOneWidget);
        expect(find.text(r'$ 12.500'), findsOneWidget);
        expect(find.text('Alquiler de la campaña'), findsOneWidget);
        expect(find.text(r'$ 18.500'), findsOneWidget);
        expect(find.text('Pagado (validado)'), findsOneWidget);
        expect(
          find.text('Es una deuda: no te frena para vender, pedir ni cobrar.'),
          findsOneWidget,
        );
        expect(find.text('PAGOS'), findsOneWidget);
        expect(find.text('15/10 · RETIRO'), findsOneWidget);
        expect(find.text('Validado'), findsOneWidget);
        expect(find.text('Se acreditó al alquiler'), findsOneWidget);
        expect(find.text('Cargar pago de alquiler'), findsOneWidget);
        // Sin pago por validar ni de más: ningún aviso.
        expect(find.byKey(const Key('alquiler_por_validar_0')), findsNothing);
        expect(find.byKey(const Key('alquiler_de_mas_0')), findsNothing);
      },
    );

    testWidgets('dado que todavía no pagué nada, cuando abro «Alquiler», falta todo el monto y no '
        'hay lista de pagos', (tester) async {
      await _con(tester, alquilerCon([campaniaCon()]));

      expect(find.byKey(const Key('alquiler_te_falta_0')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('alquiler_te_falta_0'))).data, r'$ 18.500');
      expect(tester.widget<Text>(find.byKey(const Key('alquiler_pagado_0'))).data, r'$ 0');
      expect(find.text('PAGOS'), findsNothing);
      expect(find.text('Cargar pago de alquiler'), findsOneWidget);
    });

    testWidgets('«No te frena» no es un botón ni un enlace: la pantalla es de lectura y solo el '
        'botón del pie y «Volver» se tocan', (tester) async {
      await _con(tester, alquilerDelCanvas);

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('el lector de pantalla lee la cifra, cada pago y el botón', (tester) async {
      final manejador = tester.ensureSemantics();
      await _con(tester, alquilerDelCanvas);

      expect(find.bySemanticsLabel(r'te falta pagar, $ 12.500'), findsOneWidget);
      expect(find.bySemanticsLabel(r'Alquiler de la campaña, $ 18.500'), findsOneWidget);
      expect(find.bySemanticsLabel(r'Pagado (validado), $ 6.000'), findsOneWidget);
      expect(
        find.bySemanticsLabel(r'15/10, RETIRO. $ 6.000. Validado. Se acreditó al alquiler.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Cargar pago de alquiler'), findsOneWidget);
      manejador.dispose();
    });

    testWidgets('el botón y «Volver» miden al menos 48 dp', (tester) async {
      await _con(tester, alquilerDelCanvas);

      expect(
        tester.getSize(find.byKey(const Key('alquiler_cargar_pago_0'))).height,
        greaterThanOrEqualTo(48),
      );
      final volver = tester.getSize(find.byKey(const Key('alquiler_volver')));
      expect(volver.width, greaterThanOrEqualTo(48));
      expect(volver.height, greaterThanOrEqualTo(48));
    });
  });

  group('38C·02 · Con un pago por validar', () {
    testWidgets('el aviso dice cuánto está por validar y que no baja hasta que se valide; el saldo '
        'no cambia y el pago aparece con su estado', (tester) async {
      await _con(tester, alquilerConPorValidar);

      expect(
        find.text(
          r'Tenés $ 6.000 por validar. Se descuentan cuando tu coordinador valide el ticket.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<Text>(find.byKey(const Key('alquiler_te_falta_0'))).data, r'$ 12.500');
      expect(tester.widget<Text>(find.byKey(const Key('alquiler_pagado_0'))).data, r'$ 6.000');
      expect(find.text('Por validar'), findsOneWidget);
      expect(find.text('Espera la validación de tu coordinador'), findsOneWidget);
      expect(find.text('HOY · RETIRO'), findsNothing);
      expect(find.text('20/11 · RETIRO'), findsOneWidget);
    });

    testWidgets('un pago de hoy dice «HOY» y el banco y la oficina se nombran', (tester) async {
      await _con(
        tester,
        alquilerCon([
          campaniaCon(
            pagos: [
              pagoDe(
                1000,
                fecha: ahoraDelAlquiler,
                destino: DestinoDeDeposito.banco,
                estado: EstadoDePagoDeAlquiler.porValidar,
              ),
              pagoDe(2000, fecha: diaDeAlquiler(11, 2), destino: DestinoDeDeposito.oficina),
            ],
          ),
        ]),
      );

      expect(find.text('HOY · BANCO'), findsOneWidget);
      expect(find.text('02/11 · OFICINA'), findsOneWidget);
    });

    testWidgets('el aviso se anuncia como región viva (llega con la pantalla abierta)', (
      tester,
    ) async {
      final manejador = tester.ensureSemantics();
      await _con(tester, alquilerConPorValidar);

      final nodo = tester.getSemantics(find.byKey(const Key('alquiler_por_validar_0')));
      expect(nodo.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      manejador.dispose();
    });
  });

  group('38C·03 · Pagado', () {
    testWidgets('con todo pagado la cifra queda en \$ 0 en verde y no hay botón', (tester) async {
      await _con(tester, alquilerPagado);

      final cifra = tester.widget<Text>(find.byKey(const Key('alquiler_te_falta_0')));
      expect(cifra.data, r'$ 0');
      expect(cifra.style?.color, const Color(0xFF1F6E3A));
      expect(find.text('Cargar pago de alquiler'), findsNothing);
      expect(find.text('Pagado (validado)'), findsOneWidget);
      expect(find.byKey(const Key('alquiler_de_mas_0')), findsNothing);
    });

    testWidgets(
      'dado que pagué \$ 3.000 de un alquiler de \$ 2.500, el alquiler queda en \$ 0 y dice '
      'que los \$ 500 de más bajaron mi deuda con la casa editora',
      (tester) async {
        await _con(
          tester,
          alquilerCon([
            campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
          ]),
        );

        expect(tester.widget<Text>(find.byKey(const Key('alquiler_te_falta_0'))).data, r'$ 0');
        expect(tester.widget<Text>(find.byKey(const Key('alquiler_pagado_0'))).data, r'$ 3.000');
        expect(
          find.text(r'Pagaste $ 500 de más. Se descontaron de tu deuda con la casa editora.'),
          findsOneWidget,
        );
        expect(find.text('Cargar pago de alquiler'), findsNothing);
      },
    );

    testWidgets('lo pagado de más no se muestra como «a favor»', (tester) async {
      await _con(
        tester,
        alquilerCon([
          campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
        ]),
      );

      expect(find.textContaining('a favor'), findsNothing);
      expect(find.textContaining('A favor'), findsNothing);
    });
  });

  group('38C·04 · La campaña no cobra alquiler', () {
    testWidgets('sin ninguna campaña con alquiler, dice que no cobra y no hay cifras ni botón', (
      tester,
    ) async {
      await _con(tester, AlquilerDelColportor.vacio);

      expect(find.text('Esta campaña no cobra alquiler'), findsOneWidget);
      expect(find.text('TE FALTA PAGAR'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Alquiler'), findsOneWidget); // el título
    });

    testWidgets(
      'si el coordinador quita el alquiler con la pantalla abierta, pasa a «no cobra» sin '
      'recargar',
      (tester) async {
        final repo = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
        await montarAlquiler(tester, repo);
        expect(find.text('TE FALTA PAGAR'), findsOneWidget);

        repo.emitir(AlquilerDelColportor.vacio);
        await tester.pumpAndSettle();

        expect(find.text('Esta campaña no cobra alquiler'), findsOneWidget);
        expect(find.text('TE FALTA PAGAR'), findsNothing);
      },
    );
  });

  group('38C·05 · Sin conexión', () {
    testWidgets('se ve lo último que bajó, con su hora, y el botón sigue andando', (tester) async {
      await montarAlquiler(
        tester,
        RepositorioDeAlquilerControlable(
          inicial: alquilerCon(alquilerDelCanvas.campanias, bajadoEn: DateTime(2026, 11, 21, 21)),
        ),
        conexion: TipoConexion.sinConexion,
      );

      expect(find.text('Sin conexión. Es lo que sabíamos ayer a las 21:00.'), findsOneWidget);
      expect(find.text(r'$ 12.500'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
        reason: 'el depósito se registra en el teléfono aunque no haya red',
      );
    });

    testWidgets('la hora se dice «hoy» o con la fecha según cuándo fue', (tester) async {
      await montarAlquiler(
        tester,
        RepositorioDeAlquilerControlable(
          inicial: alquilerCon(alquilerDelCanvas.campanias, bajadoEn: DateTime(2026, 11, 22, 7, 5)),
        ),
        conexion: TipoConexion.sinConexion,
      );
      expect(find.text('Sin conexión. Es lo que sabíamos hoy a las 07:05.'), findsOneWidget);

      await montarAlquiler(
        tester,
        RepositorioDeAlquilerControlable(
          inicial: alquilerCon(alquilerDelCanvas.campanias, bajadoEn: DateTime(2026, 10, 28, 9)),
        ),
        conexion: TipoConexion.sinConexion,
      );
      expect(find.text('Sin conexión. Es lo que sabíamos el 28/10 a las 09:00.'), findsOneWidget);
    });

    testWidgets('si nunca bajó nada, el aviso dice qué hacer y no inventa una hora', (
      tester,
    ) async {
      await montarAlquiler(
        tester,
        RepositorioDeAlquilerControlable(inicial: AlquilerDelColportor.vacio),
        conexion: TipoConexion.sinConexion,
      );

      expect(
        find.text(
          'Sin conexión. Todavía no bajamos los datos de tu alquiler: conectate para verlos.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('con red no hay aviso', (tester) async {
      await _con(tester, alquilerDelCanvas);

      expect(find.textContaining('Sin conexión'), findsNothing);
    });
  });

  group('Cargando y error', () {
    testWidgets('mientras se arma se ven bloques grises y el lector lo dice; nunca «no cobra»', (
      tester,
    ) async {
      final manejador = tester.ensureSemantics();
      await montarAlquiler(tester, RepositorioDeAlquilerControlable());

      expect(find.byKey(const Key('alquiler_esqueleto_total')), findsOneWidget);
      expect(find.bySemanticsLabel('Cargando tu alquiler'), findsOneWidget);
      expect(find.text('Esta campaña no cobra alquiler'), findsNothing);
      expect(find.text('Cargar pago de alquiler'), findsNothing);
      manejador.dispose();
    });

    testWidgets('si no se puede leer, el error con «Reintentar» y nunca «no cobra alquiler»', (
      tester,
    ) async {
      final repo = RepositorioDeAlquilerControlable()..fallaAlSuscribir = true;
      await montarAlquiler(tester, repo);

      expect(find.text('No pudimos traer tu alquiler.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Esta campaña no cobra alquiler'), findsNothing);
      expect(find.text('TE FALTA PAGAR'), findsNothing);
    });

    testWidgets('«Reintentar» vuelve a leer y, si ahora anda, muestra el alquiler; un doble toque '
        'no pide dos veces', (tester) async {
      final repo = RepositorioDeAlquilerControlable()..fallaAlSuscribir = true;
      await montarAlquiler(tester, repo);
      expect(repo.suscripciones, 1);

      repo
        ..fallaAlSuscribir = false
        ..inicial = alquilerDelCanvas;
      await tester.tap(find.text('Reintentar'));
      await tester.tap(find.text('Reintentar'), warnIfMissed: false);
      await tester.pump();
      await tester.pump();

      expect(repo.suscripciones, 2);
      expect(find.text(r'$ 12.500'), findsOneWidget);
      expect(find.text('No pudimos traer tu alquiler.'), findsNothing);
    });

    testWidgets('«Reintentar» que vuelve a fallar deja el error otra vez, sin trabarse', (
      tester,
    ) async {
      final repo = RepositorioDeAlquilerControlable()..fallaAlSuscribir = true;
      await montarAlquiler(tester, repo);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();

      expect(repo.suscripciones, 2);
      expect(find.text('Reintentar'), findsOneWidget);
      // Y se puede probar de nuevo.
      repo
        ..fallaAlSuscribir = false
        ..inicial = alquilerDelCanvas;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();
      expect(find.text(r'$ 12.500'), findsOneWidget);
    });

    testWidgets('una falla después de los primeros datos no borra lo que ya se veía', (
      tester,
    ) async {
      final repo = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
      await montarAlquiler(tester, repo);

      repo.fallar();
      await tester.pumpAndSettle();

      expect(find.text(r'$ 12.500'), findsOneWidget);
      expect(find.text('Esta campaña no cobra alquiler'), findsNothing);
    });
  });

  group('Al día solo', () {
    testWidgets('cuando baja del servidor un pago validado, el saldo y la lista se actualizan sin '
        'recargar', (tester) async {
      final repo = RepositorioDeAlquilerControlable(inicial: alquilerConPorValidar);
      await montarAlquiler(tester, repo);
      expect(find.byKey(const Key('alquiler_por_validar_0')), findsOneWidget);

      repo.emitir(
        alquilerCon([
          campaniaCon(
            pagos: [
              pagoDe(6000, fecha: diaDeAlquiler(11, 20)),
              pagoDe(6000),
            ],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('alquiler_te_falta_0'))).data, r'$ 6.500');
      expect(tester.widget<Text>(find.byKey(const Key('alquiler_pagado_0'))).data, r'$ 12.000');
      expect(find.byKey(const Key('alquiler_por_validar_0')), findsNothing);
      expect(find.text('Validado'), findsNWidgets(2));
      expect(repo.suscripciones, 1);
    });

    testWidgets('si el coordinador cambia el monto, el saldo se recalcula', (tester) async {
      final repo = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
      await montarAlquiler(tester, repo);

      repo.emitir(
        alquilerCon([
          campaniaCon(monto: 10000, pagos: [pagoDe(6000)]),
        ]),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('alquiler_te_falta_0'))).data, r'$ 4.000');
      expect(tester.widget<Text>(find.byKey(const Key('alquiler_monto_0'))).data, r'$ 10.000');
    });

    testWidgets('si el último pago deja todo pagado, el botón desaparece', (tester) async {
      final repo = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
      await montarAlquiler(tester, repo);
      expect(find.text('Cargar pago de alquiler'), findsOneWidget);

      repo.emitir(alquilerPagado);
      await tester.pumpAndSettle();

      expect(find.text('Cargar pago de alquiler'), findsNothing);
    });
  });

  group('Pagos rechazados y devueltos', () {
    testWidgets('un retiro rechazado se ve con su motivo, no baja el saldo y dice qué hacer', (
      tester,
    ) async {
      await _con(
        tester,
        alquilerCon([
          campaniaCon(
            pagos: [
              pagoDe(
                3000,
                fecha: diaDeAlquiler(11, 1),
                estado: EstadoDePagoDeAlquiler.rechazado,
                motivo: 'el monto no coincide',
              ),
              pagoDe(6000),
            ],
          ),
        ]),
      );

      expect(find.text('Rechazado'), findsOneWidget);
      expect(find.text('No se acreditó: «el monto no coincide». Cargalo de nuevo'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('alquiler_te_falta_0'))).data, r'$ 12.500');
      expect(tester.widget<Text>(find.byKey(const Key('alquiler_pagado_0'))).data, r'$ 6.000');
    });

    testWidgets('un rechazo sin motivo escrito no inventa uno', (tester) async {
      await _con(
        tester,
        alquilerCon([
          campaniaCon(pagos: [pagoDe(3000, estado: EstadoDePagoDeAlquiler.rechazado)]),
        ]),
      );

      expect(find.text('No se acreditó. Cargalo de nuevo'), findsOneWidget);
    });

    testWidgets('un pago que el coordinador devolvió se ve como devuelto y no cuenta', (
      tester,
    ) async {
      await _con(
        tester,
        alquilerCon([
          campaniaCon(
            pagos: [
              pagoDe(4000, estado: EstadoDePagoDeAlquiler.devuelto),
              pagoDe(6000),
            ],
          ),
        ]),
      );

      expect(find.text('Devuelto'), findsOneWidget);
      expect(find.text('Te lo devolvieron: ya no cuenta'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('alquiler_pagado_0'))).data, r'$ 6.000');
    });
  });

  group('Dos campañas', () {
    final dos = alquilerCon([
      campaniaCon(id: 'c-nueva', nombre: 'Primavera 2026', pagos: [pagoDe(6000)]),
      campaniaCon(id: 'c-vieja', nombre: 'Otoño 2026', monto: 10000, pagos: [pagoDe(10000)]),
    ]);

    testWidgets('cada campaña tiene su bloque, su saldo y, si debe, su botón', (tester) async {
      await _con(tester, dos);

      expect(find.text('Primavera 2026 · monto fijo por campaña'), findsOneWidget);
      expect(find.text('Otoño 2026 · monto fijo por campaña'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('alquiler_te_falta_0'))).data, r'$ 12.500');
      expect(tester.widget<Text>(find.byKey(const Key('alquiler_te_falta_1'))).data, r'$ 0');
      expect(find.byKey(const Key('alquiler_cargar_pago_0')), findsOneWidget);
      expect(find.byKey(const Key('alquiler_cargar_pago_1')), findsNothing);
      // El pago de cada una va en su bloque.
      expect(find.byKey(const Key('alquiler_pago_0_0')), findsOneWidget);
      expect(find.byKey(const Key('alquiler_pago_1_0')), findsOneWidget);
    });

    testWidgets('el pago de más de una campaña no se mezcla con el saldo de la otra', (
      tester,
    ) async {
      await _con(
        tester,
        alquilerCon([
          campaniaCon(id: 'c-1', nombre: 'A', monto: 1000, pagos: [pagoDe(1500)]),
          campaniaCon(id: 'c-2', nombre: 'B', monto: 2000, pagos: [pagoDe(500)]),
        ]),
      );

      expect(tester.widget<Text>(find.byKey(const Key('alquiler_te_falta_0'))).data, r'$ 0');
      expect(tester.widget<Text>(find.byKey(const Key('alquiler_te_falta_1'))).data, r'$ 1.500');
      expect(find.byKey(const Key('alquiler_de_mas_0')), findsOneWidget);
      expect(find.byKey(const Key('alquiler_de_mas_1')), findsNothing);
    });
  });

  group('Cargar pago de alquiler', () {
    testWidgets('abre «Registrar depósito» con el alquiler puesto y la campaña decidida; un doble '
        'toque abre una sola pantalla', (tester) async {
      final arnes = ArnesDeDeposito();
      final repo = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
      await montarAlquilerDesdeUnBoton(tester, repo, deposito: arnes);

      await tester.tap(find.byKey(const Key('alquiler_cargar_pago_0')));
      await tester.tap(find.byKey(const Key('alquiler_cargar_pago_0')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);
      expect(find.text('Paga el alquiler de Primavera 2026.'), findsOneWidget);

      // Cierra con «atrás»: vuelve «Mi alquiler», no otra pantalla de depósito debajo.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsNothing);
      expect(find.byType(AlquilerPage), findsOneWidget);
    });

    testWidgets('el depósito se registra para el alquiler y para esa campaña, sin preguntar cuál', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito(campania: null);
      final repo = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
      await montarAlquilerDesdeUnBoton(tester, repo, deposito: arnes);

      await tester.tap(find.byKey(const Key('alquiler_cargar_pago_0')));
      await tester.pumpAndSettle();
      await escribirMonto(tester, '1800');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      await tocarRegistrar(tester);

      final guardado = arnes.depositos.guardados.single;
      expect(guardado.concepto, ConceptoDeDeposito.alquiler);
      expect(guardado.campaniaId, 'c-1');
      expect(guardado.destino, DestinoDeDeposito.retiroCoordinador);
      expect(guardado.montoCentavos, 180000);
    });

    testWidgets('al volver, el botón vuelve a andar: se puede cargar otro pago', (tester) async {
      final arnes = ArnesDeDeposito();
      final repo = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
      await montarAlquilerDesdeUnBoton(tester, repo, deposito: arnes);

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('alquiler_cargar_pago_0')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('deposito_pagina')), findsOneWidget, reason: 'vuelta $i');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('deposito_pagina')), findsNothing);
      }
    });

    testWidgets('con dos campañas que deben, cada botón abre el depósito de SU campaña', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      final repo = RepositorioDeAlquilerControlable(
        inicial: alquilerCon([
          campaniaCon(id: 'c-1', nombre: 'Primavera 2026'),
          campaniaCon(id: 'c-2', nombre: 'Otoño 2026'),
        ]),
      );
      await montarAlquilerDesdeUnBoton(tester, repo, deposito: arnes);

      await tester.scrollUntilVisible(
        find.byKey(const Key('alquiler_cargar_pago_1')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('alquiler_cargar_pago_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('alquiler_cargar_pago_1')));
      await tester.pumpAndSettle();

      expect(find.text('Paga el alquiler de Otoño 2026.'), findsOneWidget);
    });
  });

  group('Volver atrás y reentrar', () {
    testWidgets(
      '«Volver» cierra la pantalla y al reentrar se lee de nuevo, sin dejar nada trabado',
      (tester) async {
        final repo = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
        await montarAlquilerDesdeUnBoton(tester, repo);
        expect(find.byType(AlquilerPage), findsOneWidget);

        await tester.tap(find.byKey(const Key('alquiler_volver')));
        await tester.pumpAndSettle();
        expect(find.byType(AlquilerPage), findsNothing);

        repo.inicial = alquilerPagado;
        await tester.tap(find.byKey(const Key('abrir_alquiler')));
        await tester.pumpAndSettle();

        expect(find.byType(AlquilerPage), findsOneWidget);
        expect(tester.widget<Text>(find.byKey(const Key('alquiler_te_falta_0'))).data, r'$ 0');
        expect(repo.suscripciones, 2);
      },
    );

    testWidgets('«atrás» del sistema también cierra', (tester) async {
      final repo = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
      await montarAlquilerDesdeUnBoton(tester, repo);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(AlquilerPage), findsNothing);
    });
  });

  group('Datos límite', () {
    testWidgets('con 30 pagos la lista se desplaza hasta el último y el botón queda al final', (
      tester,
    ) async {
      final pagos = [
        for (var i = 0; i < 30; i++) pagoDe(100 + i, fecha: DateTime(2026, 10, 1 + (i % 28), 12)),
      ];
      final repo = RepositorioDeAlquilerControlable(
        inicial: alquilerCon([campaniaCon(monto: 99999, pagos: pagos)]),
      );
      await montarAlquiler(tester, repo);

      await tester.scrollUntilVisible(
        find.byKey(const Key('alquiler_cargar_pago_0')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('alquiler_pago_0_29')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un nombre de campaña muy largo se parte en renglones y no desborda', (
      tester,
    ) async {
      await _con(
        tester,
        alquilerCon([
          campaniaCon(
            nombre:
                'Campaña de otoño del hemisferio sur con colportores de Montevideo, Canelones, '
                'Maldonado y todo el litoral 2026',
          ),
        ]),
        escala: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('monto fijo por campaña'), findsOneWidget);
    });

    testWidgets('un monto enorme se achica antes de cortarse', (tester) async {
      await _con(
        tester,
        alquilerCon([
          campaniaCon(monto: 123456789, pagos: [pagoDe(1)]),
        ]),
        escala: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('alquiler_te_falta_0')), findsOneWidget);
    });

    for (final tamano in const [Size(320, 568), Size(360, 640), Size(412, 915)]) {
      testWidgets('con el texto al 200 % a ${tamano.width.toInt()}×${tamano.height.toInt()} nada '
          'desborda y todo se alcanza desplazando', (tester) async {
        await montarAlquiler(
          tester,
          RepositorioDeAlquilerControlable(inicial: alquilerConPorValidar),
          tamano: tamano,
          escala: 2,
        );

        await tester.scrollUntilVisible(
          find.byKey(const Key('alquiler_cargar_pago_0')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Cargar pago de alquiler'), findsOneWidget);
      });
    }

    testWidgets('con el texto al 300 % el aviso y las filas no desbordan', (tester) async {
      await _con(tester, alquilerConPorValidar, escala: 3);

      expect(tester.takeException(), isNull);
    });
  });

  test('FailureAlquilerNoDisponible dice qué pasó y no se parece a «no cobra alquiler»', () {
    const falla = FailureAlquilerNoDisponible();
    expect(falla.mensaje, 'No pudimos traer tu alquiler.');
    expect(falla.codigo, 'ALQUILER_NO_DISPONIBLE');
  });
}
