// HU-UBI-011: los casos de uso de la baja y la reactivación de una persona.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_baja_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/services/cuenta_de_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/baja_persona_use_cases.dart';
import 'package:test/test.dart';

import '../../../../../helpers/persona_falsos.dart';

final class _Cuentas implements CuentasDePersonas {
  ResumenCuentaPersona? cuenta;
  Object? lanza;
  var consultas = 0;

  @override
  Future<ResumenCuentaPersona?> resumenDe(String personaId) async {
    consultas++;
    final error = lanza;
    if (error != null) throw error;
    return cuenta;
  }
}

const _conSaldo = ResumenCuentaPersona(
  compradoCentavos: 450000,
  pagadoCentavos: 330000,
  saldoCentavos: 120000,
  entregasHechas: 1,
  entregasTotales: 2,
);

void main() {
  final ahora = DateTime.utc(2026, 10, 25, 9, 30);
  late PersonaRepositorioFalso repo;
  late _Cuentas cuentas;
  late DarDeBajaPersonaUseCase darDeBaja;

  setUp(() {
    repo = PersonaRepositorioFalso()
      ..sembrar([clienteDePersonas('p1', 'María', apellido: 'Fernández')]);
    cuentas = _Cuentas();
    darDeBaja = DarDeBajaPersonaUseCase(repo, cuentas, ahora: () => ahora);
  });

  group('DarDeBajaPersonaUseCase', () {
    test('dada una persona sin ventas, cuando se da de baja, la da de baja con el reloj', () async {
      final r = await darDeBaja(const DarDeBajaPersonaParams(personaId: 'p1'));

      final resultado = r.getOrElse(() => throw StateError('falló'));
      expect(resultado, isA<PersonaDadaDeBaja>());
      expect((resultado as PersonaDadaDeBaja).persona.auditoria.deletedAt, ahora);
      expect(repo.bajasRecibidas.single.personaId, 'p1');
      expect(repo.bajasRecibidas.single.ahora, ahora);
    });

    test('dado un saldo en cero, la da de baja sin pedir confirmación', () async {
      cuentas.cuenta = const ResumenCuentaPersona(
        compradoCentavos: 1000,
        pagadoCentavos: 1000,
        saldoCentavos: 0,
        entregasHechas: 1,
        entregasTotales: 1,
      );

      final r = await darDeBaja(const DarDeBajaPersonaParams(personaId: 'p1'));

      expect(r.getOrElse(() => throw StateError('falló')), isA<PersonaDadaDeBaja>());
    });

    test('dada una persona con saldo, sin confirmar, no escribe y devuelve la cuenta', () async {
      cuentas.cuenta = _conSaldo;

      final r = await darDeBaja(const DarDeBajaPersonaParams(personaId: 'p1'));

      final resultado = r.getOrElse(() => throw StateError('falló'));
      expect(resultado, isA<BajaPersonaRequiereConfirmacion>());
      expect((resultado as BajaPersonaRequiereConfirmacion).cuenta, _conSaldo);
      expect(repo.bajasRecibidas, isEmpty);
    });

    test('dada una persona con saldo y la doble confirmación, la da de baja sin volver a mirar la '
        'cuenta', () async {
      cuentas.cuenta = _conSaldo;

      final r = await darDeBaja(const DarDeBajaPersonaParams(personaId: 'p1', confirmaSaldo: true));

      expect(r.getOrElse(() => throw StateError('falló')), isA<PersonaDadaDeBaja>());
      expect(cuentas.consultas, 0);
      expect(repo.bajasRecibidas, hasLength(1));
    });

    test('dada una cuenta que no se puede leer, no se da de baja: ante la duda se frena', () async {
      cuentas.lanza = StateError('INSERT con Ana Martínez 099 123 456');

      final r = await darDeBaja(const DarDeBajaPersonaParams(personaId: 'p1'));

      final falla = r.fold((f) => f, (_) => null);
      expect(falla, isA<FailureInesperado>());
      expect('${falla!.props}', isNot(contains('Martínez')));
      expect(repo.bajasRecibidas, isEmpty);
    });

    test('dado un motivo con espacios, lo recorta; vacío no se guarda', () async {
      await darDeBaja(const DarDeBajaPersonaParams(personaId: 'p1', motivo: '  Se mudó  '));
      await darDeBaja(const DarDeBajaPersonaParams(personaId: 'p1', motivo: '   '));

      expect(repo.bajasRecibidas.map((b) => b.motivo), ['Se mudó', null]);
    });

    test('dado un motivo demasiado largo o sin id, valida y no toca el repositorio', () async {
      final largo = await darDeBaja(DarDeBajaPersonaParams(personaId: 'p1', motivo: 'x' * 121));
      final sinId = await darDeBaja(const DarDeBajaPersonaParams(personaId: ' '));

      expect(
        (largo.fold((f) => f, (_) => null)! as FailureValidacion).campos.keys,
        contains('motivo'),
      );
      expect(
        (sinId.fold((f) => f, (_) => null)! as FailureValidacion).campos.keys,
        contains('persona'),
      );
      expect(repo.bajasRecibidas, isEmpty);
    });

    test('dada una falla del repositorio, la devuelve tal cual', () async {
      repo.resultadosBaja.add(
        const FailureValidacion(campos: {'persona': 'Su espacio está dado de baja'}),
      );

      final r = await darDeBaja(const DarDeBajaPersonaParams(personaId: 'p1'));

      expect(r.fold((f) => f, (_) => null), isA<FailureValidacion>());
    });
  });

  group('ReactivarPersonaUseCase', () {
    test('dada una persona de baja, cuando se reactiva, vuelve con el reloj', () async {
      repo = PersonaRepositorioFalso()..sembrar([clienteDeBajaDePersonas('p1', 'María')]);
      final reactivar = ReactivarPersonaUseCase(repo, ahora: () => ahora);

      final r = await reactivar('p1');

      expect(r.getOrElse(() => throw StateError('falló')).auditoria.deletedAt, isNull);
      expect(repo.reactivacionesRecibidas, ['p1']);
    });

    test('dado un id vacío, valida y no toca el repositorio', () async {
      final reactivar = ReactivarPersonaUseCase(repo, ahora: () => ahora);

      final r = await reactivar('  ');

      expect(r.fold((f) => f, (_) => null), isA<FailureValidacion>());
      expect(repo.reactivacionesRecibidas, isEmpty);
    });
  });

  group('ConsultarCuentaDePersonaUseCase', () {
    test('devuelve la cuenta, o null si no tiene ventas', () async {
      final consultar = ConsultarCuentaDePersonaUseCase(cuentas);

      expect((await consultar('p1')).getOrElse(() => throw StateError('falló')), isNull);
      cuentas.cuenta = _conSaldo;
      expect((await consultar('p1')).getOrElse(() => throw StateError('falló')), _conSaldo);
    });

    test('si la cuenta no se puede leer, devuelve la falla sin datos', () async {
      cuentas.lanza = StateError('Ana');
      final r = await ConsultarCuentaDePersonaUseCase(cuentas)('p1');

      expect(r.fold((f) => f, (_) => null), isA<FailureInesperado>());
    });
  });

  group('ResumenCuentaPersona', () {
    test('las entregas pendientes nunca son negativas y el saldo en cero no es deuda', () {
      const raro = ResumenCuentaPersona(
        compradoCentavos: 0,
        pagadoCentavos: 0,
        saldoCentavos: 0,
        entregasHechas: 3,
        entregasTotales: 2,
      );
      expect(raro.entregasPendientes, 0);
      expect(raro.tieneSaldo, isFalse);
      expect(_conSaldo.entregasPendientes, 1);
      expect(_conSaldo.tieneSaldo, isTrue);
    });

    test('la fuente por defecto no sabe de nadie', () async {
      expect(await const CuentasDePersonasSinFuente().resumenDe('p1'), isNull);
    });
  });
}
