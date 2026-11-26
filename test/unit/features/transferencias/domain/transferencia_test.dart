// La entidad `Transferencia` y las reglas que la pantalla usa (HU-STK-005, #512): quién la pidió, quién
// la puede cancelar y desde qué cara la ve cada punta.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/transferencia.dart';
import 'package:colportores_mobile/features/transferencias/presentation/textos_transferencias.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 10, 23, 17, 35);

Transferencia _t({
  String origen = 'ana',
  String destino = 'juan',
  EstadoDeTransferencia estado = EstadoDeTransferencia.porAutorizar,
  String? solicitante,
  String? creador = 'juan',
  DateTime? fechaSolicitud,
}) => Transferencia(
  id: 't-1',
  origenId: origen,
  destinoId: destino,
  estado: estado,
  lineas: const [LineaDeTransferencia(id: 'l-1', productoId: 'p-1', cantidad: 2)],
  solicitanteId: solicitante,
  fechaSolicitud: fechaSolicitud,
  auditoria: Auditoria(createdAt: _t0, updatedAt: _t0, createdBy: creador),
);

void main() {
  group('quién la pidió', () {
    test(
      'la que Juan pidió desde su teléfono y todavía no subió: solicitante vacío, la creó él',
      () {
        final t = _t();
        expect(t.laPidio('juan'), isTrue);
        expect(t.laPidio('ana'), isFalse);
        expect(t.enCola, isTrue);
      },
    );

    test('con el solicitante que fijó el servidor', () {
      final t = _t(solicitante: 'juan', fechaSolicitud: _t0);
      expect(t.laPidio('juan'), isTrue);
      expect(t.laPidio('ana'), isFalse);
      expect(t.enCola, isFalse);
    });

    test('la que armó la coordinadora no la pidió nadie del teléfono', () {
      final t = _t(creador: 'marta', fechaSolicitud: _t0);
      expect(t.laPidio('juan'), isFalse);
      expect(t.laPidio('ana'), isFalse);
      expect(t.esDeCoordinacion('juan'), isTrue);
    });
  });

  group('«Cancelar tr.»: solo quien la pidió, solo mientras está por autorizar', () {
    test('quien la pidió, por autorizar', () {
      expect(_t(solicitante: 'juan').laPuedeCancelar('juan'), isTrue);
    });

    test('quien entrega no la cancela', () {
      expect(_t(solicitante: 'juan').laPuedeCancelar('ana'), isFalse);
    });

    for (final e in [
      EstadoDeTransferencia.autorizada,
      EstadoDeTransferencia.rechazada,
      EstadoDeTransferencia.cancelada,
    ]) {
      test('${e.name}: ya no se cancela', () {
        expect(_t(solicitante: 'juan', estado: e).laPuedeCancelar('juan'), isFalse);
      });
    }

    test('la de la coordinadora no se cancela desde el teléfono', () {
      expect(_t(creador: 'marta').laPuedeCancelar('juan'), isFalse);
    });
  });

  group('la cara con que la ve cada punta', () {
    test('la pidió él y recibe', () {
      expect(
        CaraDeLaTransferencia.de(_t(solicitante: 'juan'), 'juan'),
        CaraDeLaTransferencia.lePediste,
      );
    });

    test('se la piden a quien entrega', () {
      expect(
        CaraDeLaTransferencia.de(_t(solicitante: 'juan'), 'ana'),
        CaraDeLaTransferencia.tePidio,
      );
    });

    test('la ofrece quien entrega y se la ofrecen a quien recibe', () {
      final t = _t(solicitante: 'ana', creador: 'ana');
      expect(CaraDeLaTransferencia.de(t, 'ana'), CaraDeLaTransferencia.leOfreciste);
      expect(CaraDeLaTransferencia.de(t, 'juan'), CaraDeLaTransferencia.teOfrecio);
    });

    test('la de la coordinadora', () {
      final t = _t(creador: 'marta');
      expect(CaraDeLaTransferencia.de(t, 'juan'), CaraDeLaTransferencia.paraVos);
      expect(CaraDeLaTransferencia.de(t, 'ana'), CaraDeLaTransferencia.entregasA);
    });
  });

  test('la otra punta y el total', () {
    final t = _t();
    expect(t.contraparteDe('juan'), 'ana');
    expect(t.contraparteDe('ana'), 'juan');
    expect(t.totalDeUnidades, 2);
  });

  test('la hora de la fila: la del servidor si ya llegó y la del teléfono mientras tanto', () {
    expect(_t().pedidaEl, _t0);
    final llegada = _t0.add(const Duration(seconds: 3));
    expect(_t(fechaSolicitud: llegada).pedidaEl, llegada);
  });

  test('EstadoDeTransferencia.estaCerrada', () {
    expect(EstadoDeTransferencia.porAutorizar.estaCerrada, isFalse);
    expect(EstadoDeTransferencia.autorizada.estaCerrada, isTrue);
  });
}
