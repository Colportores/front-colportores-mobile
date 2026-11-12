// «Venta crece» (HU-VEN-001, #693): las reglas de qué venta está abierta y el caso de uso que suma.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/linea_de_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_abierta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_item.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_para_devolver.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/venta_que_crece_repository.dart';
import 'package:colportores_mobile/features/ventas/domain/services/reglas_de_venta_que_crece.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/sumar_a_la_venta_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/venta_falsos.dart';

final _t0 = DateTime.utc(2026, 10, 23, 15);

VentaAbierta _abierta({
  String id = 'v-39',
  int total = 120000,
  int cobrado = 40000,
  String? motivo,
  DateTime? fecha,
}) => VentaAbierta(
  ventaId: id,
  espacioPersonaId: 'ep-1',
  numeroTalonario: '0039',
  fecha: fecha ?? _t0,
  montoTotalCentavos: total,
  cobradoCentavos: cobrado,
  motivoMontoManual: motivo,
);

class _Repo implements VentaQueCreceRepository {
  final llamadas =
      <({String ventaId, List<VentaItem> items, int sumado, String? motivo, int? diferencia})>[];
  Failure? falla;

  @override
  Future<Either<Failure, CitasDeLaVenta>> citasDe(String ventaId) async =>
      const Right((cobranzaAgendada: false));

  @override
  Stream<List<VentaAbierta>> observarAbiertasDe(String personaId) => const Stream.empty();

  @override
  Future<Either<Failure, VentaQueCrecio>> sumar(
    String ventaId,
    List<VentaItem> itemsNuevos, {
    required String numeroTalonario,
    required int sumadoCentavos,
    required DateTime ahora,
    String? motivoMontoManual,
    int? diferenciaCentavos,
  }) async {
    llamadas.add((
      ventaId: ventaId,
      items: itemsNuevos,
      sumado: sumadoCentavos,
      motivo: motivoMontoManual,
      diferencia: diferenciaCentavos,
    ));
    final f = falla;
    if (f != null) return Left(f);
    return Right(
      VentaQueCrecio(
        venta: ventaDe(ventaId, talonario: numeroTalonario, monto: 120000 + sumadoCentavos),
        items: itemsNuevos,
        totalAnteriorCentavos: 120000,
        sumadoEl: ahora,
      ),
    );
  }
}

void main() {
  group('ReglasDeVentaQueCrece.estaAbierta', () {
    CuentaDeLaVenta cuenta({int total = 120000, int cobrado = 0, int devuelto = 0}) =>
        CuentaDeLaVenta(
          montoTotalCentavos: total,
          cobradoCentavos: cobrado,
          devueltoCentavos: devuelto,
        );

    test('con saldo o con algo por entregar, abierta', () {
      expect(
        ReglasDeVentaQueCrece.estaAbierta(
          borrada: false,
          todoDevuelto: false,
          cuenta: cuenta(cobrado: 40000),
          entregada: true,
        ),
        isTrue,
      );
      expect(
        ReglasDeVentaQueCrece.estaAbierta(
          borrada: false,
          todoDevuelto: false,
          cuenta: cuenta(cobrado: 120000),
          entregada: false,
        ),
        isTrue,
      );
    });

    test('pagada y entregada, anulada o con todo devuelto: cerrada («Venta cerrada»)', () {
      expect(
        ReglasDeVentaQueCrece.estaAbierta(
          borrada: false,
          todoDevuelto: false,
          cuenta: cuenta(cobrado: 120000),
          entregada: true,
        ),
        isFalse,
      );
      expect(
        ReglasDeVentaQueCrece.estaAbierta(
          borrada: true,
          todoDevuelto: false,
          cuenta: cuenta(),
          entregada: false,
        ),
        isFalse,
      );
      expect(
        ReglasDeVentaQueCrece.estaAbierta(
          borrada: false,
          todoDevuelto: true,
          cuenta: cuenta(devuelto: 120000),
          entregada: false,
        ),
        isFalse,
      );
    });

    test('ninguna, una o varias: con varias, la más reciente primero', () {
      expect(PasoVentaQueCrece.de(const []), isA<SinVentaAbierta>());
      expect(PasoVentaQueCrece.de([_abierta()]), isA<UnaVentaAbierta>());
      final paso = PasoVentaQueCrece.de([
        _abierta(id: 'v-31', fecha: _t0.subtract(const Duration(days: 11))),
        _abierta(id: 'v-39'),
      ]);
      expect(paso, isA<VariasVentasAbiertas>());
      expect([for (final v in (paso as VariasVentasAbiertas).ventas) v.ventaId], ['v-39', 'v-31']);
    });

    test('el total suma lo nuevo y no recalcula lo de antes', () {
      expect(
        ReglasDeVentaQueCrece.totalNuevo(anteriorCentavos: 120000, sumadoCentavos: 40000),
        160000,
      );
    });
  });

  group('SumarALaVentaUseCase', () {
    late _Repo repo;
    late SumarALaVentaUseCase sumar;
    var n = 0;

    setUp(() {
      repo = _Repo();
      n = 0;
      sumar = SumarALaVentaUseCase(repo, generarId: () => 'id-${++n}', ahora: () => _t0);
    });

    SumaALaVenta suma({
      List<LineaDeVenta>? lineas,
      int? aMano,
      String motivo = '',
      VentaAbierta? venta,
    }) => SumaALaVenta(
      sumaId: 'suma-1',
      colportorId: 'col-1',
      venta: venta ?? _abierta(),
      lineas:
          lineas ?? const [LineaDeProducto(productoId: 'p-2', cantidad: 1, precioCentavos: 40000)],
      sumadoACobrarCentavos: aMano,
      motivoMontoManual: motivo,
    );

    test(
      'suma con el precio de hoy, al mismo talonario, y el primer renglón lleva el id fijo',
      () async {
        final r = await sumar(
          suma(
            lineas: const [
              LineaDeProducto(productoId: 'p-2', cantidad: 1, precioCentavos: 40000),
              LineaDeCombo(
                comboId: 'c-1',
                cantidad: 1,
                precioCentavos: 90000,
                componentes: [ComponenteVendido(productoId: 'p-3')],
              ),
            ],
          ),
        );

        expect(r.isRight(), isTrue);
        final llamada = repo.llamadas.single;
        expect(llamada.ventaId, 'v-39');
        expect([for (final i in llamada.items) i.id], ['suma-1', 'id-1']);
        expect(llamada.sumado, 130000);
        expect([llamada.motivo, llamada.diferencia], [null, null]);
        expect(llamada.items.first.precioUnitarioCentavos, 40000);
        expect(llamada.items.last.coleccionId, 'c-1');
      },
    );

    test(
      'con el monto de lo que suma cambiado pide el motivo; con él, lo manda y la diferencia',
      () async {
        final sinMotivo = await sumar(suma(aMano: 30000));
        expect(sinMotivo.fold((f) => (f as FailureValidacion).campos.keys, (_) => null), [
          'motivo',
        ]);
        expect(repo.llamadas, isEmpty);

        await sumar(suma(aMano: 30000, motivo: '  descuento  '));
        final llamada = repo.llamadas.single;
        expect([llamada.sumado, llamada.motivo, llamada.diferencia], [30000, 'descuento', -10000]);
      },
    );

    // Decisión de Cristian del 11/11, «Dos motivos» (#706): se juntan con « · ».
    test('si la venta ya tiene un motivo, guarda los dos unidos con « · »', () async {
      final r = await sumar(
        suma(
          aMano: 30000,
          motivo: '  descuento del libro nuevo \n',
          venta: _abierta(motivo: ' redondeo '),
        ),
      );

      expect(r.isRight(), isTrue);
      final llamada = repo.llamadas.single;
      expect(llamada.motivo, 'redondeo · descuento del libro nuevo');
      expect(llamada.diferencia, -10000);
    });

    test('con un motivo ya puesto, el nuevo en blanco sigue faltando', () async {
      final r = await sumar(
        suma(
          aMano: 30000,
          motivo: '   ',
          venta: _abierta(motivo: 'redondeo'),
        ),
      );

      expect(
        r.fold((f) => (f as FailureValidacion).campos['motivo'], (_) => null),
        'Escribí por qué cambiaste el monto',
      );
      expect(repo.llamadas, isEmpty);
    });

    test('el tope de 500 se mide sobre el texto unido: justo en el borde entra', () async {
      final viejo = 'v' * 400;
      // 400 + « · » (3) + 97 = 500.
      final nuevo = 'n' * 97;
      final r = await sumar(
        suma(
          aMano: 30000,
          motivo: nuevo,
          venta: _abierta(motivo: viejo),
        ),
      );

      expect(r.isRight(), isTrue);
      expect(repo.llamadas.single.motivo!.runes.length, 500);
      expect(repo.llamadas.single.motivo, '$viejo · $nuevo');
    });

    test('si el unido pasa de 500 no guarda nada y dice cuántos quedan para lo nuevo', () async {
      final r = await sumar(
        suma(
          aMano: 30000,
          motivo: 'n' * 98,
          venta: _abierta(motivo: 'v' * 400),
        ),
      );

      expect(
        r.fold((f) => (f as FailureValidacion).campos['motivo'], (_) => null),
        SumarALaVentaUseCase.motivoNoEntra(97),
      );
      expect(SumarALaVentaUseCase.motivoNoEntra(97), contains('97'));
      expect(repo.llamadas, isEmpty);
    });

    test(
      'mide en caracteres visibles (puntos de código) y sin los espacios de los bordes',
      () async {
        // Un emoji de 2 unidades UTF-16 cuenta 1, y los espacios del borde no cuentan.
        final viejo = '😀' * 400;
        final r = await sumar(
          suma(
            aMano: 30000,
            motivo: '   ${'é' * 97}   ',
            venta: _abierta(motivo: viejo),
          ),
        );

        expect(r.isRight(), isTrue);
        expect(repo.llamadas.single.motivo!.runes.length, 500);
      },
    );

    test('con el motivo viejo ya en el tope no entra nada nuevo (quedan 0)', () async {
      final r = await sumar(
        suma(
          aMano: 30000,
          motivo: 'x',
          venta: _abierta(motivo: 'v' * 500),
        ),
      );

      expect(
        r.fold((f) => (f as FailureValidacion).campos['motivo'], (_) => null),
        SumarALaVentaUseCase.motivoNoEntra(0),
      );
      expect(repo.llamadas, isEmpty);
    });

    test('al monto calculado no pide motivo aunque la venta ya tenga uno', () async {
      final r = await sumar(suma(venta: _abierta(motivo: 'redondeo')));

      expect(r.isRight(), isTrue);
      expect(repo.llamadas.single.motivo, isNull);
    });

    test('los misioneros no se suman: no guarda nada', () async {
      final r = await sumar(
        suma(
          lineas: const [
            LineaDeProducto(productoId: 'm-1', cantidad: 1, precioCentavos: 0, sinCobrar: true),
          ],
        ),
      );

      expect(r.fold((f) => (f as FailureValidacion).campos.keys, (_) => null), ['lineas']);
      expect(repo.llamadas, isEmpty);
    });

    test(
      'sin renglones, con una cantidad mala o con un total que no entra, no guarda nada',
      () async {
        for (final mala in [
          suma(lineas: const []),
          suma(lineas: const [LineaDeProducto(productoId: 'p', cantidad: 0, precioCentavos: 100)]),
          suma(venta: _abierta(total: 2147483000)),
        ]) {
          expect((await sumar(mala)).isLeft(), isTrue);
        }
        expect(repo.llamadas, isEmpty);
      },
    );

    test('la falla del repositorio pasa tal cual (venta cerrada)', () async {
      repo.falla = const FailureVentaCerrada(numeroTalonario: '0039');

      final r = await sumar(suma());

      expect(r.fold((f) => f, (_) => null), const FailureVentaCerrada(numeroTalonario: '0039'));
    });
  });
}
