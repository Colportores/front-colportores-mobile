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

final _base = DateTime.utc(2026, 10, 20, 15);

/// Una visita con [resultado] que pasó [dia] días después de [_base].
ResultadoDeVisitaFechado _v(_R resultado, int dia) =>
    (resultado: resultado, fecha: _base.add(Duration(days: dia)));

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
      expect(CalculadorColorCasa.calcular(resultadosDeVisitas: [_v(_R.cobranza, 0)]), isNull);
      expect(
        CalculadorColorCasa.calcular(
          resultadosDeVisitas: [_v(_R.noContesto, 0), _v(_R.cobranza, 1)],
        ),
        _C.sinContestar,
      );
    });

    test('dado el resultado de una visita, cuando se calcula, cada uno tiene su color', () {
      expect(
        CalculadorColorCasa.calcular(resultadosDeVisitas: [_v(_R.entrevista, 0)]),
        _C.entrevistaSinVenta,
      );
      expect(
        CalculadorColorCasa.calcular(resultadosDeVisitas: [_v(_R.noContesto, 0)]),
        _C.sinContestar,
      );
      expect(CalculadorColorCasa.calcular(resultadosDeVisitas: [_v(_R.rechazo, 0)]), _C.rechazo);
    });

    test('dado una visita de venta, cuando se calcula, no pinta nada hasta que exista la venta '
        '(S9)', () {
      expect(CalculadorColorCasa.calcular(resultadosDeVisitas: [_v(_R.venta, 0)]), isNull);
    });

    test('dado una venta con algo para cobrar, cuando se calcula, la casa queda en entrega y '
        'cobranza pendientes (1) y gana a todo lo demás (HU-VEN-001)', () {
      expect(
        CalculadorColorCasa.calcular(
          montosDeVentas: [150000],
          agendasPendientes: [TipoAgenda.entrevista],
          resultadosDeVisitas: [_v(_R.venta, 0), _v(_R.rechazo, 1)],
        ),
        _C.entregaYCobranzaPendiente,
      );
    });

    test(
      'dado una venta con cobros, cuando se calcula, con saldo sigue pendiente (HU-COB-001)',
      () {
        expect(
          CalculadorColorCasa.calcular(
            ventas: [(montoCentavos: 150000, cobradoCentavos: 50000, entregada: true)],
          ),
          _C.entregaYCobranzaPendiente,
        );
      },
    );

    test('dado una venta pagada y entregada, cuando se calcula, es una venta completa', () {
      expect(
        CalculadorColorCasa.calcular(
          ventas: [(montoCentavos: 150000, cobradoCentavos: 150000, entregada: true)],
        ),
        _C.ventaCompleta,
      );
    });

    test('dado una venta con el saldo en cero pero sin entregar, cuando se calcula, sigue en 1 '
        '(pendiente hasta entregar)', () {
      expect(
        CalculadorColorCasa.calcular(
          ventas: [(montoCentavos: 150000, cobradoCentavos: 150000, entregada: false)],
        ),
        _C.entregaYCobranzaPendiente,
      );
    });

    test(
      'dado una venta pagada y otra con saldo, cuando se calcula, manda la que debe (1 gana a 4)',
      () {
        expect(
          CalculadorColorCasa.calcular(
            ventas: [
              (montoCentavos: 1000, cobradoCentavos: 1000, entregada: true),
              (montoCentavos: 5000, cobradoCentavos: 0, entregada: true),
            ],
          ),
          _C.entregaYCobranzaPendiente,
        );
      },
    );

    test('dado una venta de \$ 0 con cobros, cuando se calcula, no pinta nada por sí sola', () {
      expect(
        CalculadorColorCasa.calcular(
          ventas: [(montoCentavos: 0, cobradoCentavos: 0, entregada: true)],
        ),
        isNull,
      );
    });

    test(
      'dado una venta de \$ 0 (todo regalado), cuando se calcula, no pinta nada por sí sola',
      () {
        expect(CalculadorColorCasa.calcular(montosDeVentas: [0]), isNull);
        expect(
          CalculadorColorCasa.calcular(
            montosDeVentas: [0],
            resultadosDeVisitas: [_v(_R.rechazo, 0)],
          ),
          _C.rechazo,
        );
      },
    );

    test('dado una agenda pendiente y un rechazo, cuando se calcula, gana la agenda (3 antes que '
        '7)', () {
      expect(
        CalculadorColorCasa.calcular(
          agendasPendientes: [TipoAgenda.entrevista],
          resultadosDeVisitas: [_v(_R.rechazo, 0)],
        ),
        _C.entrevistaProgramada,
      );
    });

    test('dado una agenda pendiente y un rechazo más nuevo que la entrevista, cuando se calcula, '
        'sigue ganando la agenda: lo pendiente va por encima de la última visita', () {
      expect(
        CalculadorColorCasa.calcular(
          agendasPendientes: [TipoAgenda.entrevista],
          resultadosDeVisitas: [_v(_R.entrevista, 0), _v(_R.rechazo, 9)],
        ),
        _C.entrevistaProgramada,
      );
    });

    group('entre entrevista dada, sin contestar y rechazo manda el último resultado '
        '(«Rojo o verde», 23/10)', () {
      test('dado una entrevista y después un rechazo, cuando se calcula, la casa queda roja', () {
        expect(
          CalculadorColorCasa.calcular(
            resultadosDeVisitas: [_v(_R.entrevista, 0), _v(_R.rechazo, 7)],
          ),
          _C.rechazo,
        );
      });

      test('dado un rechazo y después una entrevista, cuando se calcula, la casa queda verde', () {
        expect(
          CalculadorColorCasa.calcular(
            resultadosDeVisitas: [_v(_R.rechazo, 0), _v(_R.entrevista, 7)],
          ),
          _C.entrevistaSinVenta,
        );
      });

      test('dado una entrevista y después un no contestó, cuando se calcula, manda el no '
          'contestó', () {
        expect(
          CalculadorColorCasa.calcular(
            resultadosDeVisitas: [_v(_R.entrevista, 0), _v(_R.noContesto, 3)],
          ),
          _C.sinContestar,
        );
      });

      test('dado un rechazo y después un no contestó, cuando se calcula, manda el no contestó '
          '(aunque el rechazo tenga el número más grande)', () {
        expect(
          CalculadorColorCasa.calcular(
            resultadosDeVisitas: [_v(_R.rechazo, 0), _v(_R.noContesto, 3)],
          ),
          _C.sinContestar,
        );
      });

      test('dado una entrevista, un no contestó y un rechazo, cuando se calcula, manda el más '
          'reciente sea cual sea', () {
        const orden = [_R.entrevista, _R.noContesto, _R.rechazo];
        const colores = {
          _R.entrevista: _C.entrevistaSinVenta,
          _R.noContesto: _C.sinContestar,
          _R.rechazo: _C.rechazo,
        };
        for (final ultima in orden) {
          final anteriores = orden.where((r) => r != ultima).toList();
          final visitas = [_v(anteriores[0], 0), _v(anteriores[1], 1), _v(ultima, 2)];

          expect(
            CalculadorColorCasa.calcular(resultadosDeVisitas: visitas),
            colores[ultima],
            reason: 'último: ${ultima.name}',
          );
        }
      });

      test('dado los mismos hechos en cualquier orden de llegada, cuando se calcula, el color es '
          'el mismo', () {
        final hechos = [
          _v(_R.rechazo, 0),
          _v(_R.noContesto, 2),
          _v(_R.entrevista, 5),
          _v(_R.rechazo, 9),
          _v(_R.venta, 11),
        ];

        expect(CalculadorColorCasa.calcular(resultadosDeVisitas: hechos), _C.rechazo);
        expect(CalculadorColorCasa.calcular(resultadosDeVisitas: hechos.reversed), _C.rechazo);
        expect(
          CalculadorColorCasa.calcular(
            resultadosDeVisitas: [hechos[3], hechos[0], hechos[4], hechos[2], hechos[1]],
          ),
          _C.rechazo,
        );
      });

      test('dado dos resultados en el mismo instante, cuando se calcula, gana el de número más '
          'chico, en cualquier orden', () {
        final entrevista = _v(_R.entrevista, 1);
        final rechazo = _v(_R.rechazo, 1);

        expect(
          CalculadorColorCasa.calcular(resultadosDeVisitas: [rechazo, entrevista]),
          _C.entrevistaSinVenta,
        );
        expect(
          CalculadorColorCasa.calcular(resultadosDeVisitas: [entrevista, rechazo]),
          _C.entrevistaSinVenta,
        );
      });

      test('dado un rechazo y después una visita de venta o de cobranza, cuando se calcula, la '
          'casa sigue roja: esas no pintan ni borran al rechazo (S9)', () {
        expect(
          CalculadorColorCasa.calcular(
            resultadosDeVisitas: [_v(_R.rechazo, 0), _v(_R.venta, 4), _v(_R.cobranza, 5)],
          ),
          _C.rechazo,
        );
      });

      test('dado una agenda de cobranza, una entrevista y después un rechazo, cuando se calcula, '
          'la cobranza no pinta y manda el último resultado', () {
        expect(
          CalculadorColorCasa.calcular(
            agendasPendientes: [TipoAgenda.cobranza],
            resultadosDeVisitas: [_v(_R.entrevista, 0), _v(_R.rechazo, 2)],
          ),
          _C.rechazo,
        );
      });
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
