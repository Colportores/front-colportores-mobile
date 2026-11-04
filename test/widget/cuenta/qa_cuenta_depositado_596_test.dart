// QA de «Depositado» en Mi Cuenta (vista 33A, #596): lo que los tests del implementador no miden.
// Las cuatro guías de accesibilidad de Flutter en cada estado de la vista (incluidos el aviso de sin
// conexión, la cuenta nueva con «Depositado» en cero y los montos largos), a 360x640 y 412x915 con el
// texto al 100 % y al 200 %; el aviso entero a la vista (no cortado); y los casos límite de la
// conexión y del reloj. Los que documentan un hallazgo van con `skip` y se corren con
// `--dart-define=QA_HALLAZGOS=true`.
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/resumen_de_cuenta.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/cuenta/presentation/textos_cuenta.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

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

final _ahora = DateTime(2026, 10, 30, 12);
final _ayerALas21 = DateTime(2026, 10, 29, 21);

List<Override> _overrides(_Conexion c, {DateTime? ahora}) => [
  monitorConectividadProvider.overrideWithValue(c),
  relojCuentaProvider.overrideWithValue(() => ahora ?? _ahora),
];

ResumenDeCuenta _resumen({
  CifraDeCuenta? depositado,
  DateTime? al,
  CifraDeCuenta? enMano,
  CifraDeCuenta? porCobrar,
}) => ResumenDeCuenta(
  depositado: depositado,
  depositadoAl: depositado == null ? null : (al ?? _ayerALas21),
  enMano: enMano ?? cifra(2400, variacion: 1800),
  porCobrar: porCobrar ?? cifra(9700, variacion: -1300),
);

/// Un estado de la vista: cómo se arma el repositorio y la conexión.
typedef _Estado = ({RepositorioDeCuentaControlable Function() repo, TipoConexion conexion});

final _estados = <String, _Estado>{
  '33A·01 resumen con Depositado': (
    repo: () => RepositorioDeCuentaControlable(
      inicial: _resumen(depositado: cifra(26900, variacion: 5300)),
    ),
    conexion: TipoConexion.wifi,
  ),
  '33A·01 Depositado bajó': (
    repo: () =>
        RepositorioDeCuentaControlable(inicial: _resumen(depositado: cifra(100, variacion: -5300))),
    conexion: TipoConexion.wifi,
  ),
  '33A·01 sin primera bajada (sin tarjeta)': (
    repo: () => RepositorioDeCuentaControlable(inicial: _resumen()),
    conexion: TipoConexion.wifi,
  ),
  '33A·02 sin conexión': (
    repo: () => RepositorioDeCuentaControlable(
      inicial: _resumen(depositado: cifra(26900, variacion: 5300)),
    ),
    conexion: TipoConexion.sinConexion,
  ),
  '33A·02 sin conexión, bajada de hace un mes': (
    repo: () => RepositorioDeCuentaControlable(
      inicial: _resumen(depositado: cifra(26900, variacion: 5300), al: DateTime(2026, 10, 3, 8, 5)),
    ),
    conexion: TipoConexion.sinConexion,
  ),
  '33A·03 cargando': (repo: () => RepositorioDeCuentaControlable(), conexion: TipoConexion.wifi),
  '33A·04 cuenta nueva con Depositado en cero': (
    repo: () => RepositorioDeCuentaControlable(
      inicial: _resumen(depositado: cifra(0), enMano: cifra(0), porCobrar: cifra(0)),
    ),
    conexion: TipoConexion.wifi,
  ),
  '33A·05 error': (
    repo: () => RepositorioDeCuentaControlable()..fallaAlSuscribir = true,
    conexion: TipoConexion.wifi,
  ),
  'monto largo con centavos': (
    repo: () => RepositorioDeCuentaControlable(
      inicial: _resumen(
        depositado: const CifraDeCuenta(
          totalCentavos: 9999999999999,
          variacionCentavos: 8888888888888,
        ),
        enMano: const CifraDeCuenta(totalCentavos: 123456789012, variacionCentavos: -99999999),
        porCobrar: const CifraDeCuenta(totalCentavos: 987654321098, variacionCentavos: 1),
      ),
    ),
    conexion: TipoConexion.sinConexion,
  ),
};

Deposito _deposito({String? motivo}) => Deposito(
  id: 'dep-1',
  montoCentavos: 500000,
  fecha: DateTime(2026, 10, 20),
  destino: DestinoDeDeposito.retiroCoordinador,
  concepto: ConceptoDeDeposito.casaEditora,
  rechazadoEn: motivo == null ? null : DateTime(2026, 10, 21),
  motivoRechazo: motivo,
  auditoria: Auditoria(createdAt: DateTime(2026, 10, 20), updatedAt: DateTime(2026, 10, 20)),
);

void main() {
  group('accesibilidad y tamaños por estado', () {
    for (final estado in _estados.entries) {
      for (final tam in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
        for (final escala in [1.0, 2.0]) {
          testWidgets('${estado.key} a ${tam.key}, texto $escala: sin overflow, toque, etiqueta y '
              'contraste', (tester) async {
            final semantica = tester.ensureSemantics();
            await montarCuenta(
              tester,
              estado.value.repo(),
              tamano: tam.value,
              escala: escala,
              overrides: _overrides(_Conexion(estado.value.conexion)),
            );
            await tester.pump();
            await tester.pump();

            final falla = tester.takeException();
            expect(falla, isNull, reason: falla is FlutterError ? falla.toStringDeep() : '$falla');
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        }
      }
    }
  });

  group('33A·02 · el aviso, entero y a la vista', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('a 360x640 con el texto a $escala el aviso no se corta: su última palabra está '
          'dentro de la pantalla al bajar el scroll', (tester) async {
        await montarCuenta(
          tester,
          RepositorioDeCuentaControlable(
            inicial: _resumen(depositado: cifra(26900, variacion: 5300)),
          ),
          tamano: const Size(360, 640),
          escala: escala,
          overrides: _overrides(_Conexion(TipoConexion.sinConexion)),
        );
        await tester.pump();

        final aviso = find.byKey(const Key('cuenta_aviso_sin_conexion'));
        expect(aviso, findsOneWidget);
        final texto = tester.widget<Text>(aviso).data!;
        expect(
          texto,
          'Sin conexión. Lo depositado es de ayer a las 21:00; en mano y por cobrar están al día.',
        );
        // El texto se pinta sin recorte: su caja es tan alta como lo que pide a este ancho.
        final caja = tester.getSize(aviso);
        final medida = TextPainter(
          text: TextSpan(
            text: texto,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, height: 1.45),
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(escala),
        )..layout(maxWidth: caja.width);
        expect(caja.height, greaterThanOrEqualTo(medida.height - 1));
      });
    }

    testWidgets('«Depositado» y el aviso aparecen en el mismo cuadro: el aviso va arriba de las '
        'tarjetas y no las pisa', (tester) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(
          inicial: _resumen(depositado: cifra(26900, variacion: 5300)),
        ),
        overrides: _overrides(_Conexion(TipoConexion.sinConexion)),
      );
      await tester.pump();
      final aviso = tester.getRect(find.byKey(const Key('cuenta_aviso_sin_conexion')));
      final tarjeta = tester.getRect(find.byKey(const Key('cuenta_depositado')));
      expect(aviso.bottom, lessThanOrEqualTo(tarjeta.top));
    });
  });

  group('casos límite de la conexión', () {
    testWidgets('la conexión parpadea cinco veces seguidas: el aviso queda como la última, sin '
        'duplicarse', (tester) async {
      final c = _Conexion(TipoConexion.wifi);
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(
          inicial: _resumen(depositado: cifra(26900, variacion: 5300)),
        ),
        overrides: _overrides(c),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        c.cambiarA(TipoConexion.sinConexion);
        await tester.pumpAndSettle();
        c.cambiarA(TipoConexion.datosMoviles);
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
      c.cambiarA(TipoConexion.sinConexion);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsOneWidget);
      expect(find.byKey(const Key('cuenta_depositado')), findsOneWidget);
    });

    testWidgets('sin conexión llega la primera bajada: la tarjeta y el aviso aparecen juntos, '
        'sin recargar', (tester) async {
      final repo = RepositorioDeCuentaControlable(inicial: _resumen());
      await montarCuenta(tester, repo, overrides: _overrides(_Conexion(TipoConexion.sinConexion)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
      repo.emitir(_resumen(depositado: cifra(500)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsOneWidget);
      expect(find.text('DEPOSITADO'), findsOneWidget);
    });

    testWidgets('el error con la conexión caída muestra solo el error con «Reintentar», sin aviso '
        'de depósito', (tester) async {
      final repo = RepositorioDeCuentaControlable()..fallaAlSuscribir = true;
      await montarCuenta(tester, repo, overrides: _overrides(_Conexion(TipoConexion.sinConexion)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuenta_reintentar')), findsOneWidget);
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
    });

    testWidgets(
      '«Reintentar» tras un error con «Depositado» a la vista trae las tres tarjetas y el '
      'aviso si sigue sin conexión',
      (tester) async {
        final repo = RepositorioDeCuentaControlable()..fallaAlSuscribir = true;
        await montarCuenta(
          tester,
          repo,
          overrides: _overrides(_Conexion(TipoConexion.sinConexion)),
        );
        await tester.pumpAndSettle();
        repo
          ..fallaAlSuscribir = false
          ..inicial = _resumen(depositado: cifra(26900, variacion: 5300));
        await tester.tap(find.byKey(const Key('cuenta_reintentar')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cuenta_depositado')), findsOneWidget);
        expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsOneWidget);
      },
    );
  });

  group('el texto del aviso (FormatoCuenta.sinConexion): bordes', () {
    test('un minuto antes de medianoche y un minuto después son hoy y ayer', () {
      final ahora = DateTime(2026, 10, 30, 0, 1);
      expect(
        FormatoCuenta.sinConexion(DateTime(2026, 10, 29, 23, 59), ahora),
        contains('de ayer a las 23:59'),
      );
      expect(
        FormatoCuenta.sinConexion(DateTime(2026, 10, 30, 0, 0), ahora),
        contains('de hoy a las 00:00'),
      );
    });

    test('una bajada de otro año se escribe con día y mes y sin ambigüedad de mes (03/10)', () {
      expect(
        FormatoCuenta.sinConexion(DateTime(2025, 10, 3, 8, 5), DateTime(2026, 10, 30, 12)),
        contains('del 03/10 a las 08:05'),
      );
    });

    test('una bajada «del futuro» (el reloj del teléfono se atrasó) no dice «de hoy» ni '
        '«de ayer»', () {
      final texto = FormatoCuenta.sinConexion(
        DateTime(2026, 10, 31, 9),
        DateTime(2026, 10, 30, 12),
      );
      expect(texto, isNot(contains('de hoy')));
      expect(texto, isNot(contains('de ayer')));
    });

    test('la hora UTC de la bajada se muestra en hora local', () {
      final utc = DateTime.utc(2026, 10, 29, 21);
      final local = utc.toLocal();
      expect(
        FormatoCuenta.sinConexion(utc, DateTime(2026, 10, 30, 12)),
        contains('${local.hour.toString().padLeft(2, '0')}:00'),
      );
    });

    test('en un huso con cambio de hora, el día siguiente no se cuenta como «hoy» '
        '(23 h entre dos medianoches)', () {
      // Solo se puede ver con `TZ=America/Santiago` (o Asunción): sin cambio de hora la diferencia
      // entre dos medianoches siempre es de 24 h y el caso no existe.
      final a = DateTime(2026, 9, 6);
      final b = DateTime(2026, 9, 7);
      if (b.difference(a).inDays != 0) {
        markTestSkipped('el huso del test no tiene el salto de hora de septiembre');
        return;
      }
      expect(
        FormatoCuenta.sinConexion(DateTime(2026, 9, 6, 20), DateTime(2026, 9, 7, 12)),
        contains('de ayer'),
      );
    }, skip: !_verHallazgos);
  });

  group('hallazgos (con QA_HALLAZGOS=true)', () {
    testWidgets('el aviso de sin conexión se anuncia al lector de pantalla cuando aparece '
        '(región viva, como el error de 33A·05)', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(
          inicial: _resumen(depositado: cifra(26900, variacion: 5300)),
        ),
        overrides: _overrides(_Conexion(TipoConexion.sinConexion)),
      );
      await tester.pump();
      final nodo = tester.getSemantics(find.byKey(const Key('cuenta_aviso_sin_conexion')));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      semantica.dispose();
    }, skip: !_verHallazgos);

    test('un depósito rechazado no escribe el motivo del coordinador (texto libre) en su '
        '`toString` ni siquiera con `stringify` encendido', () {
      final original = EquatableConfig.stringify;
      EquatableConfig.stringify = true;
      addTearDown(() => EquatableConfig.stringify = original);
      final texto = '${_deposito(motivo: 'Falta el sello de Rosalia Techera')}';
      expect(texto, isNot(contains('Rosalia')));
    }, skip: !_verHallazgos);
  });

  test('con la configuración del proyecto (stringify apagado) el depósito no imprime nada', () {
    expect('${_deposito(motivo: 'Falta el sello de Rosalia Techera')}', isNot(contains('Rosalia')));
  });
}
