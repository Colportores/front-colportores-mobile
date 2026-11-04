// La tarjeta «DEPOSITADO» de Mi Cuenta y el aviso de sin conexión (vista 33A, #596): lo que el
// canvas dibuja en 33A·01, 33A·02, 33A·03 y 33A·04 con «Depositado», y los casos límite de cada
// flujo: la cifra que todavía no existe, la conexión que va y viene, los textos grandes y los montos
// largos.
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/resumen_de_cuenta.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/cuenta/presentation/textos_cuenta.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';

/// La conexión del teléfono a mano.
final class _Conexion implements MonitorConectividad {
  _Conexion(this.tipo);

  TipoConexion tipo;
  final _cambios = StreamController<TipoConexion>.broadcast();

  void cambiarA(TipoConexion nuevo) {
    tipo = nuevo;
    _cambios.add(nuevo);
  }

  @override
  Future<TipoConexion> actual() async => tipo;

  @override
  Stream<TipoConexion> get cambios => _cambios.stream;
}

/// «Ahora»: el viernes 30/10 a las 12:00 (hora local del test, para no depender de la zona).
final _ahora = DateTime(2026, 10, 30, 12);

/// Lo último que bajó: ayer a las 21:00, como en el canvas 33A·02.
final _ayerALas21 = DateTime(2026, 10, 29, 21);

/// El resumen del canvas 33A·01 con su tarjeta «DEPOSITADO»: $ 26.900, ▲ $ 5.300.
final _conDepositado = ResumenDeCuenta(
  depositado: cifra(26900, variacion: 5300),
  depositadoAl: _ayerALas21,
  enMano: cifra(2400, variacion: 1800),
  porCobrar: cifra(9700, variacion: -1300),
);

List<Override> _overrides(_Conexion conexion) => [
  monitorConectividadProvider.overrideWithValue(conexion),
  relojCuentaProvider.overrideWithValue(() => _ahora),
];

Color? _colorDe(WidgetTester tester, String texto) =>
    tester.widget<Text>(find.text(texto)).style?.color;

void main() {
  group('33A·01 · Resumen con «Depositado»', () {
    testWidgets('dado que el teléfono ya bajó lo del servidor, cuando abro «Mi cuenta», veo '
        '«Depositado» primero, con su total y cuánto cambió contra la semana pasada', (
      tester,
    ) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: _conDepositado),
        overrides: _overrides(_Conexion(TipoConexion.wifi)),
      );

      expect(find.text('DEPOSITADO'), findsOneWidget);
      expect(find.text(r'$ 26.900'), findsOneWidget);
      expect(find.text(r'▲ $ 5.300 contra la semana pasada'), findsOneWidget);
      // El orden del canvas: Depositado, En mano, Por cobrar.
      final y = [
        for (final k in ['depositado', 'enMano', 'porCobrar'])
          tester.getTopLeft(find.byKey(Key('cuenta_$k'))).dy,
      ];
      expect(y, orderedEquals([...y]..sort()));
      expect(y.toSet(), hasLength(3));
    });

    testWidgets('el lector de pantalla la lee de una vez, con el verbo y sin la flecha', (
      tester,
    ) async {
      final manejador = tester.ensureSemantics();
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: _conDepositado),
        overrides: _overrides(_Conexion(TipoConexion.wifi)),
      );

      expect(
        tester.getSemantics(find.byKey(const Key('cuenta_depositado'))).label,
        r'Depositado, $ 26.900. Subió $ 5.300 contra la semana pasada.',
      );
      manejador.dispose();
    });

    testWidgets('lo depositado que subió va en verde; que bajó o que no se movió, en gris', (
      tester,
    ) async {
      final repo = RepositorioDeCuentaControlable(inicial: _conDepositado);
      await montarCuenta(tester, repo, overrides: _overrides(_Conexion(TipoConexion.wifi)));
      expect(_colorDe(tester, r'▲ $ 5.300 contra la semana pasada'), const Color(0xFF1F6E3A));

      repo.emitir(
        ResumenDeCuenta(
          depositado: cifra(100, variacion: -50),
          depositadoAl: _ayerALas21,
          enMano: cifra(0, variacion: 0),
          porCobrar: cifra(0, variacion: 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(_colorDe(tester, r'▼ $ 50 contra la semana pasada'), const Color(0xFF5B6B82));

      repo.emitir(
        ResumenDeCuenta(
          depositado: cifra(100, variacion: 0),
          depositadoAl: _ayerALas21,
          enMano: cifra(0, variacion: 0),
          porCobrar: cifra(0, variacion: 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Igual que la semana pasada'), findsNWidgets(3));
      expect(find.textContaining('depositalo pronto'), findsNothing);
    });

    testWidgets('dado que el teléfono todavía no bajó nada, no se dibuja la tarjeta: ni un cero ni '
        'un número inventado', (tester) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        overrides: _overrides(_Conexion(TipoConexion.wifi)),
      );

      expect(find.text('DEPOSITADO'), findsNothing);
      expect(find.byKey(const Key('cuenta_depositado')), findsNothing);
      expect(find.text('EN MANO'), findsOneWidget);
      expect(find.text('POR COBRAR'), findsOneWidget);
    });

    testWidgets('«Depositado» llega con la primera bajada, sin recargar la pantalla', (
      tester,
    ) async {
      final repo = RepositorioDeCuentaControlable(inicial: resumenDelCanvas);
      await montarCuenta(tester, repo, overrides: _overrides(_Conexion(TipoConexion.wifi)));
      expect(find.text('DEPOSITADO'), findsNothing);

      repo.emitir(_conDepositado);
      await tester.pumpAndSettle();

      expect(find.text('DEPOSITADO'), findsOneWidget);
      expect(repo.suscripciones, 1);
    });

    testWidgets('no se puede tocar: sin detalle todavía, ni flecha ni toque', (tester) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: _conDepositado),
        overrides: _overrides(_Conexion(TipoConexion.wifi)),
      );

      expect(find.text('›'), findsNothing);
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
    });
  });

  group('33A·02 · Sin conexión', () {
    testWidgets('dado que no hay conexión y «Depositado» viene del servidor, cuando abro «Mi '
        'cuenta», un aviso dice de cuándo es y que lo demás está al día', (tester) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: _conDepositado),
        overrides: _overrides(_Conexion(TipoConexion.sinConexion)),
      );
      await tester.pump();

      expect(
        find.text(
          'Sin conexión. Lo depositado es de ayer a las 21:00; en mano y por cobrar están al día.',
        ),
        findsOneWidget,
      );
      // Las tres cifras se ven igual, y el aviso va arriba de todo.
      expect(find.text(r'$ 26.900'), findsOneWidget);
      expect(find.text(r'$ 2.400'), findsOneWidget);
      expect(find.text(r'$ 9.700'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('cuenta_aviso_sin_conexion'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('cuenta_depositado'))).dy),
      );
    });

    testWidgets('sin «Depositado» no hay nada viejo que decir: sin conexión no hay aviso', (
      tester,
    ) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        overrides: _overrides(_Conexion(TipoConexion.sinConexion)),
      );
      await tester.pump();

      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
      expect(find.textContaining('Sin conexión'), findsNothing);
    });

    testWidgets('con conexión no hay aviso', (tester) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: _conDepositado),
        overrides: _overrides(_Conexion(TipoConexion.datosMoviles)),
      );
      await tester.pump();

      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
    });

    testWidgets('la conexión que se va y vuelve: el aviso aparece y se retira solo, sin recargar', (
      tester,
    ) async {
      final repo = RepositorioDeCuentaControlable(inicial: _conDepositado);
      final conexion = _Conexion(TipoConexion.wifi);
      await montarCuenta(tester, repo, overrides: _overrides(conexion));
      await tester.pump();
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);

      conexion.cambiarA(TipoConexion.sinConexion);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsOneWidget);

      conexion.cambiarA(TipoConexion.wifi);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
      expect(repo.suscripciones, 1);
    });

    testWidgets('el lector de pantalla lee el aviso entero', (tester) async {
      final manejador = tester.ensureSemantics();
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: _conDepositado),
        overrides: _overrides(_Conexion(TipoConexion.sinConexion)),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel(RegExp(r'^Sin conexión\. Lo depositado es de ayer a las 21:00')),
        findsOneWidget,
      );
      manejador.dispose();
    });
  });

  group('33A·03 · Cargando', () {
    testWidgets('mientras calcula, un bloque gris por tarjeta, también para «Depositado»', (
      tester,
    ) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(),
        overrides: _overrides(_Conexion(TipoConexion.wifi)),
      );

      expect(find.byKey(const Key('cuenta_esqueleto_depositado')), findsOneWidget);
      expect(find.byKey(const Key('cuenta_esqueleto_enMano')), findsOneWidget);
      expect(find.byKey(const Key('cuenta_esqueleto_porCobrar')), findsOneWidget);
    });
  });

  group('33A·04 · Cuenta nueva', () {
    testWidgets('dado que ya bajó y no hay nada validado, «Depositado» está en cero y dice que no '
        'hay datos de la semana anterior', (tester) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(
          inicial: ResumenDeCuenta(
            depositado: cifra(0),
            depositadoAl: _ahora,
            enMano: cifra(0),
            porCobrar: cifra(0),
          ),
        ),
        overrides: _overrides(_Conexion(TipoConexion.wifi)),
      );

      expect(find.text(r'$ 0'), findsNWidgets(3));
      expect(find.text('Sin datos de la semana anterior'), findsNWidgets(3));
    });
  });

  group('datos límite', () {
    for (final tamano in [const Size(320, 568), const Size(360, 640), const Size(412, 915)]) {
      testWidgets('textos al 200 % a ${tamano.width.toInt()}×${tamano.height.toInt()}: las tres '
          'tarjetas y el aviso se alcanzan sin desbordar', (tester) async {
        await montarCuenta(
          tester,
          RepositorioDeCuentaControlable(inicial: _conDepositado),
          tamano: tamano,
          escala: 2,
          overrides: _overrides(_Conexion(TipoConexion.sinConexion)),
        );
        await tester.pump();

        for (final k in ['cuenta_aviso_sin_conexion', 'cuenta_depositado', 'cuenta_porCobrar']) {
          await tester.ensureVisible(find.byKey(Key(k)));
          await tester.pump();
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('un monto largo con centavos entra en la tarjeta, también al 200 %', (
      tester,
    ) async {
      final repo = RepositorioDeCuentaControlable(
        inicial: ResumenDeCuenta(
          depositado: const CifraDeCuenta(totalCentavos: 2147483647, variacionCentavos: 2147483647),
          depositadoAl: _ahora,
          enMano: cifra(0),
          porCobrar: cifra(0),
        ),
      );
      await montarCuenta(
        tester,
        repo,
        tamano: const Size(320, 568),
        escala: 2,
        overrides: _overrides(_Conexion(TipoConexion.wifi)),
      );

      expect(find.textContaining(r'$ 21.474.836,47'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('volver a la pestaña vuelve a leer y no deja el aviso viejo', (tester) async {
      final repo = RepositorioDeCuentaControlable(inicial: _conDepositado);
      final conexion = _Conexion(TipoConexion.sinConexion);
      await montarCuenta(tester, repo, activa: false, overrides: _overrides(conexion));
      await tester.pump();
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsOneWidget);

      conexion.cambiarA(TipoConexion.wifi);
      await tester.pump();
      await cambiarActiva(tester, repo, activa: true, overrides: _overrides(conexion));

      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
      expect(find.text('DEPOSITADO'), findsOneWidget);
    });
  });

  group('el texto del aviso (FormatoCuenta.sinConexion)', () {
    test('de hoy, dice «hoy»; de ayer, «ayer»; de antes, la fecha', () {
      expect(
        FormatoCuenta.sinConexion(DateTime(2026, 10, 30, 9, 5), DateTime(2026, 10, 30, 12)),
        'Sin conexión. Lo depositado es de hoy a las 09:05; en mano y por cobrar están al día.',
      );
      expect(
        FormatoCuenta.sinConexion(DateTime(2026, 10, 29, 21), DateTime(2026, 10, 30, 12)),
        'Sin conexión. Lo depositado es de ayer a las 21:00; en mano y por cobrar están al día.',
      );
      expect(
        FormatoCuenta.sinConexion(DateTime(2026, 10, 3, 8, 30), DateTime(2026, 10, 30, 12)),
        'Sin conexión. Lo depositado es del 03/10 a las 08:30; en mano y por cobrar están al día.',
      );
    });

    test('ayer a las 23:59 con «ahora» a las 00:01 sigue siendo ayer (cuenta días, no horas)', () {
      expect(
        FormatoCuenta.sinConexion(DateTime(2026, 10, 29, 23, 59), DateTime(2026, 10, 30, 0, 1)),
        contains('de ayer a las 23:59'),
      );
    });
  });
}
