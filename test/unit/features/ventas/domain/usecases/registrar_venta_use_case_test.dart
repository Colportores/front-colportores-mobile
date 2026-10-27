import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/linea_de_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/registrar_venta_use_case.dart';
import 'package:test/test.dart';

import '../../../../../helpers/venta_falsos.dart';

void main() {
  final ahora = DateTime.utc(2026, 10, 23, 14);
  late VentasEnMemoria repo;
  late RegistrarVentaUseCase registrar;

  setUp(() {
    repo = VentasEnMemoria();
    var n = 0;
    registrar = RegistrarVentaUseCase(repo, generarId: () => 'id-${++n}', ahora: () => ahora);
  });

  const libros = LineaDeProducto(productoId: 'prod-1', cantidad: 3, precioCentavos: 50000);
  const packFamiliar = LineaDeCombo(
    comboId: 'combo-1',
    cantidad: 1,
    precioCentavos: 120000,
    componentes: [
      ComponenteVendido(productoId: 'libro-1'),
      ComponenteVendido(productoId: 'revista-1', cantidad: 2),
    ],
  );

  NuevaVenta venta({
    String ventaId = 'v-1',
    String talonario = 'T-100',
    List<LineaDeVenta> lineas = const [libros],
    int? cobrado,
    String motivo = '',
    String? visitaId,
    String persona = 'ep-1',
    String colportor = 'col-1',
  }) => NuevaVenta(
    ventaId: ventaId,
    colportorId: colportor,
    espacioPersonaId: persona,
    numeroTalonario: talonario,
    lineas: lineas,
    totalCobradoCentavos: cobrado,
    motivoMontoManual: motivo,
    visitaId: visitaId,
  );

  Future<Failure> rechazada(NuevaVenta v) async {
    final r = await registrar(RegistrarVentaParams(venta: v));
    expect(repo.recibidas, isEmpty, reason: 'una venta inválida no llega a guardarse');
    return r.fold((f) => f, (_) => throw StateError('debía fallar'));
  }

  group('venta simple', () {
    test(
      '3 libros a \$ 500: el monto se calcula \$ 1.500 y se guarda con la foto del precio',
      () async {
        final r = await registrar(RegistrarVentaParams(venta: venta()));

        final guardada = r.getOrElse(() => throw StateError('falló'));
        expect(guardada.venta.montoTotalCentavos, 150000);
        expect(guardada.venta.numeroTalonario, 'T-100');
        expect(guardada.venta.fecha, ahora);
        expect(guardada.venta.motivoMontoManual, isNull);
        final item = guardada.items.single;
        expect(item.productoId, 'prod-1');
        expect(item.coleccionId, isNull);
        expect(item.componentes, isNull);
        expect(
          [item.cantidad, item.precioUnitarioCentavos, item.subtotalCentavos],
          [3, 50000, 150000],
        );
        expect(repo.recibidas.single.diferencia, isNull);
      },
    );

    test('el talonario se guarda sin los espacios de los bordes', () async {
      await registrar(RegistrarVentaParams(venta: venta(talonario: '  0042 \n')));

      expect(repo.recibidas.single.venta.numeroTalonario, '0042');
    });

    test('la visita de la entrevista queda atada a la venta', () async {
      await registrar(RegistrarVentaParams(venta: venta(visitaId: 'vis-9')));

      expect(repo.recibidas.single.venta.visitaId, 'vis-9');
    });
  });

  group('combos', () {
    test('«Pack Familiar» es UN ítem de \$ 1.200 con lo que traía copiado', () async {
      final r = await registrar(RegistrarVentaParams(venta: venta(lineas: [packFamiliar])));

      final guardada = r.getOrElse(() => throw StateError('falló'));
      expect(guardada.venta.montoTotalCentavos, 120000);
      final item = guardada.items.single;
      expect(item.productoId, isNull);
      expect(item.coleccionId, 'combo-1');
      expect(item.componentes, packFamiliar.componentes);
    });

    test('producto y combo juntos: dos ítems, cada uno con su id', () async {
      final r = await registrar(RegistrarVentaParams(venta: venta(lineas: [libros, packFamiliar])));

      final guardada = r.getOrElse(() => throw StateError('falló'));
      expect(guardada.venta.montoTotalCentavos, 270000);
      expect(guardada.items.map((i) => i.id).toSet(), hasLength(2));
      expect(guardada.items.every((i) => i.ventaId == 'v-1'), isTrue);
    });

    test('un combo sin sus productos no se vende (el servidor lo rechazaría)', () async {
      const vacio = LineaDeCombo(
        comboId: 'combo-1',
        cantidad: 1,
        precioCentavos: 1000,
        componentes: [],
      );

      final falla = await rechazada(venta(lineas: [vacio])) as FailureValidacion;

      expect(falla.campos.keys, ['lineas']);
    });
  });

  group('monto a mano (S38)', () {
    test('guarda el monto de la colportora, el motivo recortado y la diferencia', () async {
      await registrar(
        RegistrarVentaParams(
          venta: venta(cobrado: 135000, motivo: '  descuento por pago en efectivo \n'),
        ),
      );

      final recibida = repo.recibidas.single;
      expect(recibida.venta.montoTotalCentavos, 135000);
      expect(recibida.venta.motivoMontoManual, 'descuento por pago en efectivo');
      expect(recibida.diferencia, -15000);
    });

    test('sin motivo se guarda igual, con null', () async {
      await registrar(RegistrarVentaParams(venta: venta(cobrado: 100000, motivo: '   ')));

      expect(repo.recibidas.single.venta.motivoMontoManual, isNull);
      expect(repo.recibidas.single.venta.montoTotalCentavos, 100000);
    });

    test(
      'un motivo de más de 500 caracteres se corta: una venta nunca se rechaza por el motivo',
      () async {
        await registrar(RegistrarVentaParams(venta: venta(cobrado: 1, motivo: 'x' * 900)));

        expect(repo.recibidas.single.venta.motivoMontoManual!.runes.length, 500);
      },
    );

    test('un monto igual al calculado no es un cambio: sin diferencia ni motivo', () async {
      await registrar(RegistrarVentaParams(venta: venta(cobrado: 150000, motivo: 'por las dudas')));

      expect(repo.recibidas.single.diferencia, isNull);
      expect(repo.recibidas.single.venta.motivoMontoManual, isNull);
    });

    test('subir el monto también deja la diferencia (positiva)', () async {
      await registrar(RegistrarVentaParams(venta: venta(cobrado: 160000)));

      expect(repo.recibidas.single.diferencia, 10000);
    });

    test('cobrar 0 a mano es válido: se regaló la venta', () async {
      await registrar(RegistrarVentaParams(venta: venta(cobrado: 0)));

      expect(repo.recibidas.single.venta.montoTotalCentavos, 0);
    });

    test('un monto negativo o más grande que el entero del servidor se rechaza', () async {
      for (final cobrado in [-1, 2147483648]) {
        final falla = await rechazada(venta(cobrado: cobrado)) as FailureValidacion;
        expect(falla.campos.keys, ['total']);
      }
    });
  });

  group('misioneros sin cobrar', () {
    test('la venta solo de regalos vale 0 y los ítems quedan con precio 0', () async {
      const regalo = LineaDeProducto(
        productoId: 'm-1',
        cantidad: 3,
        precioCentavos: 15000,
        sinCobrar: true,
      );

      final r = await registrar(RegistrarVentaParams(venta: venta(lineas: [regalo])));

      final guardada = r.getOrElse(() => throw StateError('falló'));
      expect(guardada.venta.montoTotalCentavos, 0);
      expect(guardada.items.single.precioUnitarioCentavos, 0);
      expect(guardada.items.single.subtotalCentavos, 0);
    });
  });

  group('validación: nada se guarda', () {
    test('sin talonario', () async {
      for (final vacio in ['', '   ', '\n']) {
        final falla = await rechazada(venta(talonario: vacio)) as FailureValidacion;
        expect(falla.campos.keys, ['talonario']);
      }
    });

    test('talonario de más de 30 caracteres', () async {
      final falla = await rechazada(venta(talonario: '9' * 31)) as FailureValidacion;

      expect(falla.campos['talonario'], contains('largo'));
    });

    test('sin ítems (una venta debe tener al menos un venta_item)', () async {
      final falla = await rechazada(venta(lineas: const [])) as FailureValidacion;

      expect(falla.campos['lineas'], contains('al menos un producto'));
    });

    test('cantidad 0, negativa o absurda', () async {
      for (final cantidad in [0, -1, RegistrarVentaUseCase.maximoPorLinea + 1]) {
        final linea = LineaDeProducto(productoId: 'p', cantidad: cantidad, precioCentavos: 100);
        final falla = await rechazada(venta(lineas: [linea])) as FailureValidacion;
        expect(falla.campos.keys, ['lineas']);
      }
    });

    test('un total más grande que el entero del servidor', () async {
      const enorme = LineaDeProducto(productoId: 'p', cantidad: 99999, precioCentavos: 99999);

      final falla = await rechazada(venta(lineas: [enorme])) as FailureValidacion;

      expect(falla.campos.keys, ['total']);
    });

    test('sin colportor, sin persona o sin id de venta', () async {
      final falla =
          await rechazada(venta(ventaId: ' ', colportor: '', persona: '')) as FailureValidacion;

      expect(falla.campos.keys, containsAll(['ids', 'colportorId', 'persona']));
    });

    test('las fallas de validación no llevan ni el talonario ni el motivo', () async {
      final falla = await rechazada(venta(talonario: '', motivo: 'dato del cliente', cobrado: -5));

      expect('$falla', isNot(contains('dato del cliente')));
    });
  });

  group('fallas del repositorio y doble toque', () {
    test('un talonario repetido vuelve tal cual, sin perder lo cargado', () async {
      repo.respuesta = FailureTalonarioRepetido(numero: '0042', ventaDel: DateTime(2026, 3, 12));

      final r = await registrar(RegistrarVentaParams(venta: venta(talonario: '0042')));

      expect(
        r.fold((f) => f.mensaje, (_) => ''),
        'Ya usaste el talonario 0042 este año (venta del 12/03). Revisá el número.',
      );
    });

    test('«No pudimos guardar la venta» es el texto del canvas y no habla de datos perdidos', () {
      const falla = FailureVentaNoGuardada();

      expect(
        falla.mensaje,
        'No pudimos guardar la venta en tu teléfono. No se perdió nada de lo que cargaste: '
        'probá de nuevo.',
      );
    });

    test('el hook de la entrevista corre antes de guardar y su falla la propaga el repo', () async {
      var corrio = false;

      await registrar(
        RegistrarVentaParams(venta: venta(), antesDeGuardar: () async => corrio = true),
      );

      expect(corrio, isTrue);
    });

    test('el mismo ventaId dos veces llega dos veces al repo, que es quien la deduplica', () async {
      await registrar(RegistrarVentaParams(venta: venta()));
      await registrar(RegistrarVentaParams(venta: venta()));

      expect(repo.recibidas.map((r) => r.venta.id), ['v-1', 'v-1']);
    });
  });
}
