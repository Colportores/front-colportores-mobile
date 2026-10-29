// El filtro por estado del historial de la ficha (vista 32B·03, HU-UBI-009): «Todo», «Con saldo» y
// «Entrega pendiente».
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/services/cuenta_de_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/services/filtro_de_historial.dart';
import 'package:test/test.dart';

VentaEnFicha _venta(String id, String talonario, int monto) => VentaEnFicha(
  id: id,
  fecha: DateTime.utc(2026, 10, 12),
  numeroTalonario: talonario,
  montoCentavos: monto,
  lineas: const [],
);

CobroEnFicha _cobro(String id, int monto, {String? talonario}) => CobroEnFicha(
  id: id,
  fecha: DateTime.utc(2026, 10, 20),
  montoCentavos: monto,
  efectivo: true,
  numeroTalonario: talonario,
);

EntregaEnFicha _entrega(String id, {required bool pendiente}) => EntregaEnFicha(
  id: id,
  fecha: DateTime.utc(2026, 10, 26),
  pendiente: pendiente,
  lineas: const [],
);

final _visita = VisitaEnFicha(
  id: 'vis',
  fecha: DateTime.utc(2026, 10, 5),
  resultado: TipoResultadoVisita.entrevista,
);

ResumenCuentaPersona _cuenta({required int saldo}) => ResumenCuentaPersona(
  compradoCentavos: 450000,
  pagadoCentavos: 450000 - saldo,
  saldoCentavos: saldo,
  entregasHechas: 1,
  entregasTotales: 2,
);

List<String> _ids(List<MovimientoDeFicha> l) => [for (final m in l) m.id];

void main() {
  final historial = <MovimientoDeFicha>[
    _cobro('cob-1', 60000, talonario: '0042'),
    _entrega('ent-1', pendiente: true),
    _venta('ven-1', '0042', 120000),
    _entrega('ent-0', pendiente: false),
    _venta('ven-0', '0040', 30000),
    _visita,
  ];

  test('«Todo» deja todo, en el mismo orden', () {
    final r = FiltroDeHistorialDeFicha.aplicar(historial, FiltroDeHistorial.todo);

    expect(_ids(r), _ids(historial));
  });

  test('«Entrega pendiente» deja solo las entregas por hacer', () {
    final r = FiltroDeHistorialDeFicha.aplicar(historial, FiltroDeHistorial.entregaPendiente);

    expect(_ids(r), ['ent-1']);
  });

  test('«Con saldo» deja las ventas que todavía se deben, también si se pagó una parte', () {
    final r = FiltroDeHistorialDeFicha.aplicar(
      historial,
      FiltroDeHistorial.conSaldo,
      resumen: _cuenta(saldo: 120000),
    );

    expect(_ids(r), ['ven-1', 'ven-0']);
  });

  test('«Con saldo» no deja la venta cobrada entera (ni la cobrada de más)', () {
    final pagadas = <MovimientoDeFicha>[
      _venta('ven-1', '0042', 120000),
      _cobro('cob-1', 70000, talonario: '0042'),
      _cobro('cob-2', 50000, talonario: '0042'),
      _venta('ven-2', '0043', 1000),
      _cobro('cob-3', 5000, talonario: '0043'),
    ];

    final r = FiltroDeHistorialDeFicha.aplicar(
      pagadas,
      FiltroDeHistorial.conSaldo,
      resumen: _cuenta(saldo: 1000),
    );

    expect(r, isEmpty);
  });

  test('«Con saldo» con una cuenta sin saldo no contradice la tarjeta de arriba', () {
    final r = FiltroDeHistorialDeFicha.aplicar(
      historial,
      FiltroDeHistorial.conSaldo,
      resumen: _cuenta(saldo: 0),
    );

    expect(r, isEmpty);
  });

  test(
    '«Con saldo» sin fuente de cobros (cuenta desconocida) no afirma ninguna deuda ni se ofrece',
    () {
      expect(FiltroDeHistorialDeFicha.aplicar(historial, FiltroDeHistorial.conSaldo), isEmpty);
      expect(FiltroDeHistorialDeFicha.disponibles(null), [
        FiltroDeHistorial.todo,
        FiltroDeHistorial.entregaPendiente,
      ]);
      expect(FiltroDeHistorialDeFicha.disponibles(_cuenta(saldo: 0)), FiltroDeHistorial.values);
    },
  );

  test('un cobro sin número de venta no se descuenta de ninguna', () {
    final r = FiltroDeHistorialDeFicha.aplicar(
      [_venta('ven-1', '0042', 120000), _cobro('cob-1', 120000)],
      FiltroDeHistorial.conSaldo,
      resumen: _cuenta(saldo: 120000),
    );

    expect(_ids(r), ['ven-1']);
  });

  test('un historial vacío queda vacío con cualquier filtro', () {
    for (final f in FiltroDeHistorial.values) {
      expect(FiltroDeHistorialDeFicha.aplicar(const [], f), isEmpty);
    }
  });
}
