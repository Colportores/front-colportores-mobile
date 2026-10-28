// Test de dominio: Dart puro. La regla de prioridad de ADR-003 (§8.4) sin DB ni Flutter.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/color_house_status.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/house_status.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/calculador_color_casa.dart';
import 'package:test/test.dart';

typedef _R = TipoResultadoVisita;
typedef _C = ColorHouseStatus;

void main() {
  group('ColorHouseStatus (ADR-003, §8.4)', () {
    test('dado los siete colores, cuando se listan, van de la prioridad 1 a la 7 con el código '
        'del servidor', () {
      expect(
        {for (final c in _C.values) c.prioridad: c.codigo},
        {
          1: 'ENTREGA_Y_COBRANZA_PENDIENTE',
          2: 'COBRANZA_PENDIENTE',
          3: 'ENTREVISTA_PROGRAMADA',
          4: 'VENTA_COMPLETA',
          5: 'ENTREVISTA_SIN_VENTA',
          6: 'SIN_CONTESTAR',
          7: 'RECHAZO',
        },
      );
    });

    test('dado el código de cada color, cuando se lee de vuelta, es el mismo color', () {
      for (final c in _C.values) {
        expect(_C.desdeCodigo(c.codigo), c);
      }
    });

    test('dado un código que el servidor no tiene, cuando se lee, lanza ArgumentError', () {
      expect(() => _C.desdeCodigo('SIN_VISITA'), throwsArgumentError);
    });

    test('dado varios colores, cuando se pide el de mayor prioridad, gana el número más chico', () {
      expect(
        _C.elDeMayorPrioridad([_C.rechazo, _C.sinContestar, _C.entrevistaSinVenta]),
        _C.entrevistaSinVenta,
      );
      expect(_C.elDeMayorPrioridad([_C.rechazo]), _C.rechazo);
      expect(
        _C.elDeMayorPrioridad([_C.entrevistaProgramada, _C.ventaCompleta]),
        _C.entrevistaProgramada,
      );
    });

    test('dado que no hay ningún color, cuando se pide el de mayor prioridad, es null', () {
      expect(_C.elDeMayorPrioridad(const []), isNull);
    });
  });

  group('HouseStatus', () {
    test('dado una fila de la cache, cuando se lee su prioridad, sale del color', () {
      final estado = HouseStatus(
        ubicacionId: 'ub-1',
        lat: -34.9,
        lon: -56.16,
        tipoUbicacion: TipoUbicacion.casa,
        color: _C.entrevistaProgramada,
        auditoria: Auditoria(createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026)),
      );

      expect(estado.prioridad, 3);
      expect(estado.estaBorrada, isFalse);
    });
  });

  group('CalculadorColorCasa', () {
    test(
      'dado una casa sin agendas ni visitas, cuando se calcula, no hay color: es «Sin visita»',
      () {
        expect(CalculadorColorCasa.calcular(), isNull);
      },
    );

    test('dado una agenda de entrevista pendiente, cuando se calcula, la casa es entrevista '
        'programada (3)', () {
      expect(
        CalculadorColorCasa.calcular(agendasPendientes: [TipoAgenda.entrevista]),
        _C.entrevistaProgramada,
      );
    });

    test('dado una agenda de cobranza pendiente, cuando se calcula, no pinta nada: la cobranza '
        'pendiente depende de una venta con saldo (S9)', () {
      expect(CalculadorColorCasa.calcular(agendasPendientes: [TipoAgenda.cobranza]), isNull);
    });

    test('dado una visita de cobranza, cuando se calcula, no pinta nada ni pisa a las demás: queda '
        'en el historial (decisión «Visita cobro», 23/10)', () {
      expect(CalculadorColorCasa.calcular(resultadosDeVisitas: [_R.cobranza]), isNull);
      expect(
        CalculadorColorCasa.calcular(resultadosDeVisitas: [_R.cobranza, _R.noContesto]),
        _C.sinContestar,
      );
    });

    test('dado el resultado de una visita, cuando se calcula, cada uno tiene su color', () {
      expect(
        CalculadorColorCasa.calcular(resultadosDeVisitas: [_R.entrevista]),
        _C.entrevistaSinVenta,
      );
      expect(CalculadorColorCasa.calcular(resultadosDeVisitas: [_R.noContesto]), _C.sinContestar);
      expect(CalculadorColorCasa.calcular(resultadosDeVisitas: [_R.rechazo]), _C.rechazo);
    });

    test('dado una visita de venta, cuando se calcula, no pinta nada hasta que exista la venta '
        '(S9)', () {
      expect(CalculadorColorCasa.calcular(resultadosDeVisitas: [_R.venta]), isNull);
    });

    test('dado una venta con algo para cobrar, cuando se calcula, la casa queda en entrega y '
        'cobranza pendientes (1) y gana a todo lo demás (HU-VEN-001)', () {
      expect(
        CalculadorColorCasa.calcular(
          ventas: [_sinEntregar(150000)],
          agendasPendientes: [TipoAgenda.entrevista],
          resultadosDeVisitas: [_R.venta, _R.rechazo],
        ),
        _C.entregaYCobranzaPendiente,
      );
    });

    test(
      'dado una venta de \$ 0 (todo regalado), cuando se calcula, no pinta nada por sí sola',
      () {
        expect(CalculadorColorCasa.calcular(ventas: [_sinEntregar(0)]), isNull);
        expect(
          CalculadorColorCasa.calcular(
            ventas: [_sinEntregar(0)],
            resultadosDeVisitas: [_R.rechazo],
          ),
          _C.rechazo,
        );
      },
    );

    test('dado una venta entregada con saldo, cuando se calcula, queda en cobranza pendiente (2) '
        '(HU-VEN-002)', () {
      expect(
        CalculadorColorCasa.calcular(
          ventas: [const VentaParaElColor(saldoCentavos: 250000, entregada: true)],
          resultadosDeVisitas: [_R.rechazo],
        ),
        _C.cobranzaPendiente,
      );
    });

    test('dado una venta entregada y sin saldo, cuando se calcula, es venta completa (4) '
        '(HU-VEN-002)', () {
      expect(
        CalculadorColorCasa.calcular(
          ventas: [const VentaParaElColor(saldoCentavos: 0, entregada: true)],
          resultadosDeVisitas: [_R.entrevista],
        ),
        _C.ventaCompleta,
      );
      // La agenda de una entrevista (3) todavía le gana: ADR-003 §8.4.
      expect(
        CalculadorColorCasa.calcular(
          ventas: [const VentaParaElColor(saldoCentavos: 0, entregada: true)],
          agendasPendientes: [TipoAgenda.entrevista],
        ),
        _C.entrevistaProgramada,
      );
    });

    test('dado dos ventas, una entregada con saldo y otra sin entregar, cuando se calcula, gana '
        'la que más falta (1)', () {
      expect(
        CalculadorColorCasa.calcular(
          ventas: [const VentaParaElColor(saldoCentavos: 100, entregada: true), _sinEntregar(100)],
        ),
        _C.entregaYCobranzaPendiente,
      );
    });

    test('dado una agenda pendiente y un rechazo, cuando se calcula, gana la agenda (3 antes que '
        '7)', () {
      expect(
        CalculadorColorCasa.calcular(
          agendasPendientes: [TipoAgenda.entrevista],
          resultadosDeVisitas: [_R.rechazo],
        ),
        _C.entrevistaProgramada,
      );
    });

    test('dado una entrevista dada, un no contestó y un rechazo, cuando se calcula, gana la '
        'entrevista (5 antes que 6 y 7)', () {
      expect(
        CalculadorColorCasa.calcular(
          resultadosDeVisitas: [_R.rechazo, _R.noContesto, _R.entrevista],
        ),
        _C.entrevistaSinVenta,
      );
    });

    test('dado un no contestó y un rechazo, cuando se calcula, gana el no contestó (6 antes que '
        '7)', () {
      expect(
        CalculadorColorCasa.calcular(resultadosDeVisitas: [_R.rechazo, _R.noContesto]),
        _C.sinContestar,
      );
    });

    test('dado los mismos hechos en otro orden, cuando se calcula, el color es el mismo', () {
      final hechos = [_R.rechazo, _R.noContesto, _R.entrevista, _R.venta];
      final alReves = hechos.reversed.toList();

      expect(
        CalculadorColorCasa.calcular(resultadosDeVisitas: hechos),
        CalculadorColorCasa.calcular(resultadosDeVisitas: alReves),
      );
    });

    test('dado una agenda de cobranza y una de entrevista, cuando se calcula, la de entrevista '
        'pinta la casa', () {
      expect(
        CalculadorColorCasa.calcular(
          agendasPendientes: [TipoAgenda.cobranza, TipoAgenda.entrevista],
        ),
        _C.entrevistaProgramada,
      );
    });
  });
}

VentaParaElColor _sinEntregar(int saldo) =>
    VentaParaElColor(saldoCentavos: saldo, entregada: false);
