// La ficha de una persona (HU-UBI-009, #403): cómo se arma y se mantiene al día, y «Llamar» con su
// auditoría sin el número.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ficha_persona_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/ficha_persona_use_cases.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/ficha_persona_falsos.dart';
import '../../../../../helpers/nota_persona_falsos.dart';
import '../../../../../helpers/persona_falsos.dart';
import '../../../../../widget/mapa/baja_persona_arnes.dart' show CuentasFalsas, cuentaConSaldo;

void main() {
  late FichaPersonaRepositorioFalso fichas;
  late NotaPersonaRepositorioFalso notas;
  late CuentasFalsas cuentas;
  late MovimientosFalsos movimientos;
  late EspacioConUbicacion lugar;

  ObservarFichaDePersonaUseCase armar({EspacioRepositorioParaPersonas? espacios}) =>
      ObservarFichaDePersonaUseCase(
        fichas: fichas,
        notas: notas,
        espacios: espacios ?? EspacioRepositorioParaPersonas(lugar),
        cuentas: cuentas,
        movimientos: movimientos,
      );

  setUp(() {
    fichas = FichaPersonaRepositorioFalso(
      persona: mariaDePrueba(),
      historial: [visitaEnFicha('vis-1', DateTime.utc(2026, 10, 5, 14))],
    );
    notas = NotaPersonaRepositorioFalso(
      notas: [
        notaDePrueba('n1', 'Pidió volver el sábado', creada: DateTime(2026, 10, 22, 14, 20)),
        notaDePrueba('n2', 'Trabaja en la farmacia', creada: DateTime(2026, 10, 5, 9)),
        notaDePrueba('n3', 'Borrada', borrada: DateTime(2026, 10, 6)),
      ],
    );
    cuentas = CuentasFalsas();
    movimientos = MovimientosFalsos();
    lugar = (espacio: espacioDePersonas(numeroDepto: '3B'), ubicacion: ubicacionDePersonas());
  });

  group('ObservarFichaDePersonaUseCase', () {
    test('arma la ficha: persona, lugar, contexto, solo la última nota y el historial', () async {
      final ficha = (await armar()(personaId: 'per-1', espacioId: 'esp-1').first)!;

      expect(ficha.persona.nombre, 'María');
      expect(ficha.lugar, lugar);
      expect(ficha.contexto.nombre, 'María');
      expect(ficha.soloLectura, isFalse);
      expect(ficha.notas.total, 2, reason: 'las borradas no cuentan');
      expect(ficha.notas.ultima!.id, 'n1');
      expect(ficha.historial.map((m) => m.id), ['vis-1']);
      expect(ficha.resumen, isNull);
    });

    test('suma la cuenta cuando hay de dónde saberla', () async {
      cuentas.cuenta = cuentaConSaldo;

      final ficha = (await armar()(personaId: 'per-1', espacioId: 'esp-1').first)!;

      expect(ficha.resumen, cuentaConSaldo);
    });

    test(
      'junta las visitas y ventas con las entregas y los cobros, la más nueva primero',
      () async {
        movimientos.poner([
          CobroEnFicha(
            id: 'cob-1',
            fecha: DateTime.utc(2026, 10, 20, 12),
            montoCentavos: 60000,
            efectivo: true,
          ),
          EntregaEnFicha(
            id: 'ent-1',
            fecha: DateTime.utc(2026, 10, 26, 12),
            pendiente: true,
            lineas: const [LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1)],
          ),
        ]);

        final ficha = (await armar()(personaId: 'per-1', espacioId: 'esp-1').first)!;

        expect(ficha.historial.map((m) => m.id), ['ent-1', 'cob-1', 'vis-1']);
      },
    );

    test('sin notas: total 0 y ninguna última', () async {
      notas = NotaPersonaRepositorioFalso();

      final ficha = (await armar()(personaId: 'per-1', espacioId: 'esp-1').first)!;

      expect(ficha.notas, NotasDeLaFicha.ninguna);
    });

    test('la persona de baja es de solo lectura con la causa de las notas', () async {
      fichas = FichaPersonaRepositorioFalso(
        persona: mariaDePrueba(baja: DateTime.utc(2026, 10, 22)),
      );
      notas.contexto = ContextoNotasPersona(
        nombre: 'María',
        causa: CausaSoloLectura.personaDeBaja,
        bajaDesde: DateTime.utc(2026, 10, 22),
      );

      final ficha = (await armar()(personaId: 'per-1', espacioId: 'esp-1').first)!;

      expect(ficha.soloLectura, isTrue);
      expect(ficha.personaDeBaja, isTrue);
    });

    test('si la persona ya no está en el teléfono, sale null', () async {
      fichas = FichaPersonaRepositorioFalso();

      expect(await armar()(personaId: 'per-1', espacioId: 'esp-1').first, isNull);
    });

    test('si el contexto de las notas no la encuentra, sale null', () async {
      notas.contexto = null;

      expect(await armar()(personaId: 'per-1', espacioId: 'esp-1').first, isNull);
    });

    test(
      'si el espacio no está (el pull no garantiza el orden), la ficha sale sin lugar',
      () async {
        final ficha = (await armar(espacios: EspacioRepositorioParaPersonas(null))(
          personaId: 'per-1',
          espacioId: 'esp-1',
        ).first)!;

        expect(ficha.lugar, isNull);
        expect(ficha.persona.nombre, 'María');
      },
    );

    test('un error al leer cualquier parte sale por el stream, no una ficha a medias', () async {
      fichas.errorAlObservar = StateError('no se pudo leer');
      await expectLater(
        armar()(personaId: 'per-1', espacioId: 'esp-1'),
        emitsError(isA<StateError>()),
      );

      fichas.errorAlObservar = null;
      notas.fallaDeContexto = const FailureInesperado();
      await expectLater(
        armar()(personaId: 'per-1', espacioId: 'esp-1'),
        emitsError(isA<FailureInesperado>()),
      );

      notas.fallaDeContexto = null;
      cuentas.lanza = StateError('no se pudo leer la cuenta');
      await expectLater(
        armar()(personaId: 'per-1', espacioId: 'esp-1'),
        emitsError(isA<StateError>()),
      );
    });

    test('al cambiar algo (una nota nueva, una visita) emite una ficha nueva', () async {
      final salidas = <FichaDePersona?>[];
      final sub = armar()(personaId: 'per-1', espacioId: 'esp-1').listen(salidas.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      fichas.poner(
        LecturaDeFicha(
          persona: mariaDePrueba(),
          historial: [
            visitaEnFicha('vis-2', DateTime.utc(2026, 10, 21)),
            visitaEnFicha('vis-1', DateTime.utc(2026, 10, 5, 14)),
          ],
        ),
      );
      await pumpEventQueue();

      expect(salidas.last!.historial.map((m) => m.id), ['vis-2', 'vis-1']);
    });

    test('dos cambios seguidos: la respuesta de la lectura vieja se descarta', () async {
      final salidas = <FichaDePersona?>[];
      cuentas.secuencia.addAll([cuentaConSaldo, null]);
      final sub = armar()(personaId: 'per-1', espacioId: 'esp-1').listen(salidas.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      final antes = salidas.length;

      // Una lectura queda esperando y llega otra: solo vale la última.
      final compuerta = Completer<void>();
      cuentas.compuerta = compuerta;
      fichas.poner(LecturaDeFicha(persona: mariaDePrueba(), historial: const []));
      await pumpEventQueue();
      cuentas.compuerta = null;
      fichas.poner(
        LecturaDeFicha(
          persona: mariaDePrueba(),
          historial: [visitaEnFicha('vis-9', DateTime.utc(2026, 10, 25))],
        ),
      );
      await pumpEventQueue();
      compuerta.complete();
      await pumpEventQueue();

      expect(salidas.length, greaterThan(antes));
      expect(salidas.last!.historial.map((m) => m.id), ['vis-9']);
    });

    test('al dejar de escuchar no queda nada suscripto', () async {
      final sub = armar()(personaId: 'per-1', espacioId: 'esp-1').listen((_) {});
      await pumpEventQueue();

      await sub.cancel();
      fichas.poner(LecturaDeFicha(persona: mariaDePrueba(), historial: const []));
      await pumpEventQueue();

      expect(fichas.observaciones, 1);
    });
  });

  group('LlamarAPersonaUseCase', () {
    late MarcadorFalso marcador;
    final ahora = DateTime.utc(2026, 10, 29, 12);

    LlamarAPersonaUseCase llamar() => LlamarAPersonaUseCase(fichas, marcador, ahora: () => ahora);

    setUp(() => marcador = MarcadorFalso());

    test('audita click_to_call con el id de la persona y abre el marcador', () async {
      final r = await llamar()(personaId: 'per-1', telefono: '099 123 456');

      expect(r, ResultadoDeLlamada.abierto);
      expect(fichas.llamadas, [(personaId: 'per-1', ahora: ahora)]);
      expect(marcador.numeros, ['099123456']);
    });

    test('sin teléfono no audita ni marca', () async {
      for (final vacio in [null, '', '   ', 'sin número']) {
        expect(await llamar()(personaId: 'per-1', telefono: vacio), ResultadoDeLlamada.sinTelefono);
      }
      expect(fichas.llamadas, isEmpty);
      expect(marcador.numeros, isEmpty);
    });

    test('si la auditoría falla o lanza, la llamada sale igual', () async {
      fichas.fallaAlLlamar = const FailureInesperado();
      expect(await llamar()(personaId: 'per-1', telefono: '099123456'), ResultadoDeLlamada.abierto);
    });

    test('sin marcador (tablet, iOS) o con un error, dice que no se pudo abrir', () async {
      marcador.abre = false;
      expect(
        await llamar()(personaId: 'per-1', telefono: '099123456'),
        ResultadoDeLlamada.noSePudoAbrir,
      );

      marcador
        ..abre = true
        ..lanza = StateError('sin canal');
      expect(
        await llamar()(personaId: 'per-1', telefono: '099123456'),
        ResultadoDeLlamada.noSePudoAbrir,
      );
    });

    test('el número nunca viaja a la auditoría', () async {
      await llamar()(personaId: 'per-1', telefono: '099123456');

      expect(fichas.llamadas.single.toString(), isNot(contains('099123456')));
    });

    test('numeroParaMarcar deja solo dígitos y el + del comienzo', () {
      expect(LlamarAPersonaUseCase.numeroParaMarcar('+598 99 123 456'), '+59899123456');
      expect(LlamarAPersonaUseCase.numeroParaMarcar('(099) 123-456'), '099123456');
      expect(LlamarAPersonaUseCase.numeroParaMarcar(' 2 900 11 22 '), '29001122');
      expect(LlamarAPersonaUseCase.numeroParaMarcar('abc'), isNull);
      expect(LlamarAPersonaUseCase.numeroParaMarcar(null), isNull);
    });
  });
}
