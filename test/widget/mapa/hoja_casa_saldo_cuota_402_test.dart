// Vista 39, artboards C·01 y C·02 (HU-COB-005, #402): lo que debe cada persona y la cuota que toca en
// su fila, y las cifras al día después de cada cobro, sin recargar la hoja. Corre con el caso de uso
// real de la hoja (`ObservarContextoDeLaCasaUseCase`) y dobles de las ventas, los cobros y los planes.
//
// Inventario del canvas que cubre este archivo:
//  - C·01 «Tocar una casa: resumen» · «Pedro Gómez — Debe $ 1.200 · cuota sáb 26/10 — $ Cobrar».
//  - C·02 «Hoja arriba · Personas» · la misma fila por persona (y la de quien no debe nada).
//  - Estados de la HU: con saldo y cuota, con saldo sin plan, sin saldo, cuota vencida (30A-06 en la
//    fila), sin conexión (todo es local: igual que con conexión).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_del_lugar.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/cuotas_de_personas.dart';
import 'package:colportores_mobile/features/mapa/domain/services/lector_notas_del_lugar.dart';
import 'package:colportores_mobile/features/mapa/domain/services/saldos_de_personas.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/observar_contexto_de_la_casa_use_case.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart'
    show ColoresAlta;
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/persona_falsos.dart';

// Un viernes: 23/10/2026 a media tarde. El sábado de la cuota es el 24/10.
final _hoy = DateTime(2026, 10, 23, 14, 20);
final _sabado = DateTime(2026, 10, 24, 12, 30);
final _ayer = DateTime(2026, 10, 22, 12, 30);

final _ana = clienteDePersonas('p-ana', 'Ana', apellido: 'Gómez', minutos: 1);
final _luis = clienteDePersonas('p-luis', 'Luis', apellido: 'Pérez', minutos: 2);

final class _Espacios implements EspacioRepository {
  @override
  Future<Either<Failure, List<Espacio>>> listar(
    String ubicacionId, {
    bool incluirBajas = false,
  }) async => Right([espacioDePersonas(numeroDepto: null)]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Personas implements PersonaRepository {
  _Personas(this.lista);

  final List<PersonaDelEspacio> lista;

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) => Stream.value(lista);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _SinNotas implements LectorNotasDelLugar {
  @override
  Stream<NotaDelLugar?> observarMasReciente(String ubicacionId) => Stream.value(null);
}

/// Las ventas y los cobros del teléfono, reducidos a lo que la hoja lee: cuánto debe cada persona y la
/// cuota que le toca. [cobrar] hace lo que un cobro: baja el saldo y la base avisa.
final class _Cuentas implements SaldosDePersonas, CuotasDePersonas {
  Map<String, int> saldos = {'p-pedro': 120000};
  Map<String, DateTime> cuotas = {};
  Object? falla;
  var lecturas = 0;
  final cambios = StreamController<void>.broadcast();

  @override
  Future<Map<String, int>> saldosPendientes(Iterable<String> personaIds) async {
    lecturas++;
    final error = falla;
    if (error != null) throw error;
    return {
      for (final id in personaIds)
        if (saldos.containsKey(id)) id: saldos[id]!,
    };
  }

  @override
  Future<Map<String, DateTime>> proximaCuotaDe(Iterable<String> personaIds) async => {
    for (final id in personaIds)
      if (cuotas.containsKey(id)) id: cuotas[id]!,
  };

  /// Un cobro de [centavos] a [personaId]: lo que debe baja (nunca de cero) y la base avisa.
  void cobrar(String personaId, int centavos) {
    final nuevo = (saldos[personaId] ?? 0) - centavos;
    if (nuevo <= 0) {
      saldos.remove(personaId);
      cuotas.remove(personaId);
    } else {
      saldos[personaId] = nuevo;
    }
    cambios.add(null);
  }
}

final class _Montaje {
  final cuentas = _Cuentas();
  final cobros = <ContextoDeCobro>[];
  final lecturas = <ClaveDeLaCasa>[];
}

Future<void> _drenar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Widget _app({
  required _Montaje m,
  required List<PersonaDelEspacio> personas,
  required bool arriba,
  required double escala,
  FutureOr<void> Function(ContextoDeCobro)? cobrar,
}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      ...overridesHojaCasa(
        lectura: (clave) => ObservarContextoDeLaCasaUseCase(
          espacios: _Espacios(),
          personas: _Personas(personas),
          saldos: m.cuentas,
          notas: _SinNotas(),
          cuotas: m.cuentas,
          cambios: () => m.cuentas.cambios.stream,
        )(ubicacionId: clave.ubicacionId, tipo: clave.tipo),
        lecturas: m.lecturas,
        cobrar: (c) async {
          m.cobros.add(c);
          if (cobrar != null) await cobrar(c);
        },
      ),
    ],
    child: MaterialApp(
      theme: temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: HojaCasa(
            item: itemDeLaHoja(),
            ahora: _hoy,
            alCerrar: () {},
            arriba: arriba,
            colportorId: 'col-1',
          ),
        ),
      ),
    ),
  );
}

Future<_Montaje> _montar(
  WidgetTester tester, {
  _Montaje? montaje,
  List<PersonaDelEspacio>? personas,
  bool arriba = false,
  double escala = 1,
  Size tamano = const Size(390, 844),
  FutureOr<void> Function(ContextoDeCobro)? cobrar,
}) async {
  final m = montaje ?? _Montaje();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(m.cuentas.cambios.close);
  await tester.pumpWidget(
    _app(m: m, personas: personas ?? [pedroGomez], arriba: arriba, escala: escala, cobrar: cobrar),
  );
  await _drenar(tester);
  return m;
}

Finder get _cobrar => find.byKey(ClavesHojaCasa.cobrar);
Finder get _vencida => find.byKey(ClavesHojaCasa.cuotaVencida);
const _debe1200 = 'Debe \$ 1.200';

void main() {
  group('C·01 · la persona que debe, con su saldo y su cuota', () {
    testWidgets('con saldo y cuota: «Debe \$ 1.200 · cuota sáb 24/10» y «\$ Cobrar»', (
      tester,
    ) async {
      final m = _Montaje()..cuentas.cuotas = {'p-pedro': _sabado};
      await _montar(tester, montaje: m);

      expect(find.text('Pedro Gómez'), findsOneWidget);
      expect(find.text('$_debe1200 · cuota sáb 24/10'), findsOneWidget);
      expect(_cobrar, findsOneWidget);
      expect(_vencida, findsNothing);
    });

    testWidgets('con saldo y sin plan: solo el monto', (tester) async {
      await _montar(tester);

      expect(find.text(_debe1200), findsOneWidget);
      expect(find.textContaining('cuota'), findsNothing);
      expect(_cobrar, findsOneWidget);
    });

    testWidgets('sin saldo: ni «Debe», ni cuota, ni «\$ Cobrar» (aunque el plan traiga una)', (
      tester,
    ) async {
      final m = _Montaje()
        ..cuentas.saldos = {}
        ..cuentas.cuotas = {'p-pedro': _sabado};
      await _montar(tester, montaje: m);

      expect(find.text('Pedro Gómez'), findsOneWidget);
      expect(find.textContaining('Debe'), findsNothing);
      expect(find.textContaining('cuota'), findsNothing);
      expect(_cobrar, findsNothing);
    });

    testWidgets('cuota vencida: la fila lo dice con la fecha, en el color del aviso', (
      tester,
    ) async {
      final m = _Montaje()..cuentas.cuotas = {'p-pedro': _ayer};
      await _montar(tester, montaje: m);

      expect(find.text('$_debe1200 · cuota vencida el 22/10'), findsOneWidget);
      expect(_vencida, findsOneWidget);
      final estilo = tester.widget<Text>(_vencida).style!;
      expect(estilo.color, ColoresAlta.ambar);
      expect(estilo.fontWeight, FontWeight.w600);
      expect(_cobrar, findsOneWidget, reason: 'vencida o no, se puede cobrar');
    });

    testWidgets('la cuota de hoy todavía no venció', (tester) async {
      final m = _Montaje()..cuentas.cuotas = {'p-pedro': DateTime(2026, 10, 23, 9)};
      await _montar(tester, montaje: m);

      expect(find.text('$_debe1200 · cuota vie 23/10'), findsOneWidget);
      expect(_vencida, findsNothing);
    });

    testWidgets('el lector de pantalla oye el nombre, el monto, la cuota y que venció', (
      tester,
    ) async {
      final m = _Montaje()..cuentas.cuotas = {'p-pedro': _ayer};
      await _montar(tester, montaje: m);

      final asa = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'Pedro Gómez\. Debe .*1\.200 · cuota vencida el 22/10')),
        findsOneWidget,
      );
      asa.dispose();
    });
  });

  group('C·02 · la pestaña Personas', () {
    testWidgets('cada persona con su línea: con cuota, con saldo sin plan y la que no debe', (
      tester,
    ) async {
      final m = _Montaje()
        ..cuentas.saldos = {'p-pedro': 120000, 'p-ana': 24000}
        ..cuentas.cuotas = {'p-pedro': _sabado};
      await _montar(tester, montaje: m, personas: [pedroGomez, _ana, _luis], arriba: true);

      expect(find.text('$_debe1200 · cuota sáb 24/10'), findsOneWidget);
      expect(find.text('Debe \$ 240'), findsOneWidget);
      expect(find.text('Luis Pérez'), findsOneWidget);
      expect(find.byType(FilaPersonaDeLaCasa), findsNWidgets(3));
      expect(_cobrar, findsNWidgets(2), reason: 'Luis no debe: sin «\$ Cobrar»');
    });

    testWidgets('dos personas con cuota vencida y vigente a la vez', (tester) async {
      final m = _Montaje()
        ..cuentas.saldos = {'p-pedro': 120000, 'p-ana': 24000}
        ..cuentas.cuotas = {'p-pedro': _ayer, 'p-ana': _sabado};
      await _montar(tester, montaje: m, personas: [pedroGomez, _ana], arriba: true);

      expect(find.text('$_debe1200 · cuota vencida el 22/10'), findsOneWidget);
      expect(find.text('Debe \$ 240 · cuota sáb 24/10'), findsOneWidget);
      expect(_vencida, findsOneWidget);
    });
  });

  group('al día después de cada cobro, sin recargar', () {
    testWidgets('venta de 1.500 con un cobro de 500: al cobrar otros 300 pasa a \$ 700', (
      tester,
    ) async {
      final m = _Montaje()..cuentas.saldos = {'p-pedro': 100000};
      await _montar(tester, montaje: m);
      expect(find.text('Debe \$ 1.000'), findsOneWidget);

      m.cuentas.cobrar('p-pedro', 30000);
      await _drenar(tester);

      expect(find.text('Debe \$ 700'), findsOneWidget);
      expect(find.text('Debe \$ 1.000'), findsNothing);
      expect(m.lecturas, hasLength(1), reason: 'la hoja no se recargó: es la misma lectura');
    });

    testWidgets('tocar «\$ Cobrar», cobrar y volver: la fila ya dice lo que queda', (tester) async {
      final m = _Montaje()..cuentas.cuotas = {'p-pedro': _sabado};
      await _montar(tester, montaje: m, cobrar: (c) => m.cuentas.cobrar(c.personaId, 40000));

      await tester.tap(_cobrar);
      await _drenar(tester);

      expect(m.cobros.single.personaId, 'p-pedro');
      expect(find.text('Debe \$ 800 · cuota sáb 24/10'), findsOneWidget);
      expect(_cobrar, findsOneWidget);
    });

    testWidgets('el último cobro: la fila deja de deber y desaparece «\$ Cobrar» y la cuota', (
      tester,
    ) async {
      final m = _Montaje()..cuentas.cuotas = {'p-pedro': _sabado};
      await _montar(tester, montaje: m, cobrar: (c) => m.cuentas.cobrar(c.personaId, 120000));

      await tester.tap(_cobrar);
      await _drenar(tester);

      expect(find.text('Pedro Gómez'), findsOneWidget);
      expect(find.textContaining('Debe'), findsNothing);
      expect(find.textContaining('cuota'), findsNothing);
      expect(_cobrar, findsNothing);
    });

    testWidgets('cobrar la cuota vencida: la fila deja el aviso y pasa a la cuota que viene', (
      tester,
    ) async {
      final m = _Montaje()..cuentas.cuotas = {'p-pedro': _ayer};
      await _montar(tester, montaje: m);
      expect(_vencida, findsOneWidget);

      m.cuentas.saldos = {'p-pedro': 60000};
      m.cuentas.cuotas = {'p-pedro': DateTime(2026, 11, 2)};
      m.cuentas.cambios.add(null);
      await _drenar(tester);

      expect(find.text('Debe \$ 600 · cuota lun 02/11'), findsOneWidget);
      expect(_vencida, findsNothing);
    });

    testWidgets('dos cobros seguidos antes de que se asiente el primero: queda el último', (
      tester,
    ) async {
      final m = _Montaje()..cuentas.saldos = {'p-pedro': 100000};
      await _montar(tester, montaje: m);

      m.cuentas.cobrar('p-pedro', 30000);
      m.cuentas.cobrar('p-pedro', 20000);
      await _drenar(tester);

      expect(find.text('Debe \$ 500'), findsOneWidget);
      expect(find.text('Debe \$ 700'), findsNothing);
    });

    testWidgets('doble toque en «\$ Cobrar»: se abre un solo cobro y, al volver, se puede otro', (
      tester,
    ) async {
      final compuerta = Completer<void>();
      final m = _Montaje()..cuentas.saldos = {'p-pedro': 100000};
      await _montar(tester, montaje: m, cobrar: (_) => compuerta.future);

      await tester.tap(_cobrar);
      await tester.pump();
      await tester.tap(_cobrar);
      await tester.pump();
      expect(m.cobros, hasLength(1));

      m.cuentas.cobrar('p-pedro', 30000);
      compuerta.complete();
      await _drenar(tester);
      expect(find.text('Debe \$ 700'), findsOneWidget);

      await tester.tap(_cobrar);
      await _drenar(tester);
      expect(m.cobros, hasLength(2), reason: 'al terminar, el botón vuelve a estar habilitado');
    });

    testWidgets('falla a mitad del cobro: el botón vuelve a habilitarse y el saldo no cambia', (
      tester,
    ) async {
      final m = _Montaje()..cuentas.saldos = {'p-pedro': 100000};
      await _montar(tester, montaje: m, cobrar: (_) => throw StateError('no abrió'));

      await tester.tap(_cobrar);
      await _drenar(tester);

      expect(find.text('No pudimos abrir «\$ Cobrar». Probá de nuevo.'), findsOneWidget);
      expect(find.text('Debe \$ 1.000'), findsOneWidget);
      await tester.tap(_cobrar);
      await _drenar(tester);
      expect(m.cobros, hasLength(2));
    });

    testWidgets('si al volver a leer falla, la fila no afirma lo que no sabe', (tester) async {
      final m = _Montaje()..cuentas.saldos = {'p-pedro': 100000};
      await _montar(tester, montaje: m);

      m.cuentas.falla = StateError('la base no responde');
      m.cuentas.cambios.add(null);
      await _drenar(tester);

      expect(find.text('Pedro Gómez'), findsOneWidget);
      expect(find.textContaining('Debe'), findsNothing);
      expect(_cobrar, findsNothing);
    });

    testWidgets('volver atrás y reentrar: la hoja nueva lee lo de ahora', (tester) async {
      final m = _Montaje()..cuentas.saldos = {'p-pedro': 100000};
      await _montar(tester, montaje: m);
      expect(find.text('Debe \$ 1.000'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      final lecturasAlCerrar = m.cuentas.lecturas;
      m.cuentas.cobrar('p-pedro', 30000);
      await _drenar(tester);
      expect(m.cuentas.lecturas, lecturasAlCerrar, reason: 'cerrada, no lee más');

      await tester.pumpWidget(
        _app(m: m, personas: [pedroGomez], arriba: false, escala: 1, cobrar: null),
      );
      await _drenar(tester);

      expect(find.text('Debe \$ 700'), findsOneWidget);
    });

    testWidgets('el cobro llega mientras la hoja está en la pestaña Personas', (tester) async {
      final m = _Montaje()
        ..cuentas.saldos = {'p-pedro': 100000, 'p-ana': 24000}
        ..cuentas.cuotas = {'p-pedro': _sabado};
      await _montar(tester, montaje: m, personas: [pedroGomez, _ana], arriba: true);

      m.cuentas.cobrar('p-ana', 24000);
      m.cuentas.cobrar('p-pedro', 25000);
      await _drenar(tester);

      expect(find.text('Debe \$ 750 · cuota sáb 24/10'), findsOneWidget);
      expect(find.textContaining('Debe \$ 240'), findsNothing);
      expect(_cobrar, findsOneWidget);
    });
  });

  group('datos límite y texto grande', () {
    for (final escala in [2.0, 3.0]) {
      testWidgets('cuota vencida con un monto de siete cifras a 360 px y texto ×$escala', (
        tester,
      ) async {
        final m = _Montaje()
          ..cuentas.saldos = {'p-pedro': 99999999}
          ..cuentas.cuotas = {'p-pedro': _ayer};
        await _montar(tester, montaje: m, escala: escala, tamano: const Size(360, 740));

        expect(tester.takeException(), isNull);
        expect(find.textContaining('cuota vencida el 22/10'), findsOneWidget);
        expect(tester.getRect(find.byType(FilaPersonaDeLaCasa)).right, lessThanOrEqualTo(360));
        expect(tester.getSize(_cobrar).height, greaterThanOrEqualTo(48));
      });

      testWidgets('la pestaña con tres personas y cuotas a texto ×$escala no desborda', (
        tester,
      ) async {
        final m = _Montaje()
          ..cuentas.saldos = {'p-pedro': 120000, 'p-ana': 24000, 'p-luis': 5050}
          ..cuentas.cuotas = {'p-pedro': _ayer, 'p-ana': _sabado, 'p-luis': _sabado};
        await _montar(
          tester,
          montaje: m,
          personas: [pedroGomez, _ana, _luis],
          arriba: true,
          escala: escala,
          tamano: const Size(360, 740),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(FilaPersonaDeLaCasa), findsNWidgets(3));
        expect(find.text('Debe \$ 50,50 · cuota sáb 24/10'), findsOneWidget);
      });
    }

    testWidgets('una lista larga (40 personas con saldo) se lee al día después de un cobro', (
      tester,
    ) async {
      final personas = [
        for (var i = 0; i < 40; i++) clienteDePersonas('p-$i', 'Persona', apellido: 'N.º $i'),
      ];
      final m = _Montaje()
        ..cuentas.saldos = {for (final p in personas) p.persona.id: 10000}
        ..cuentas.cuotas = {for (final p in personas) p.persona.id: _sabado};
      await _montar(tester, montaje: m, personas: personas, arriba: true);

      m.cuentas.cobrar('p-0', 4000);
      await _drenar(tester);

      expect(find.text('Debe \$ 60 · cuota sáb 24/10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
