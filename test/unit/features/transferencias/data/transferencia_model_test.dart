// El DTO de la transferencia (HU-STK-005, #512): la lista exacta de claves que suben y los códigos de
// estado.
import 'package:colportores_mobile/features/transferencias/data/models/transferencia_model.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/transferencia.dart';
import 'package:test/test.dart';

import '../../../../helpers/transferencias_en_memoria.dart';

void main() {
  test('el encabezado sube con estas claves y nada más', () {
    final json = TransferenciaModel.encabezadoAJson(transferenciaDeEjemplo());
    expect(json.keys.toSet(), {
      'id',
      'origen_id',
      'destino_id',
      'estado',
      'created_at',
      'updated_at',
      'created_by',
      'deleted_at',
      'sync_version',
    });
    expect(json['estado'], 'PENDIENTE_AUTORIZACION');
    expect(json['created_at'], '2026-10-23T17:35:00.000Z');
  });

  test('la cancelación sube solo id, estado y la auditoría (sin origen_id ni destino_id)', () {
    final t = transferenciaDeEjemplo();
    final cancelada = Transferencia(
      id: t.id,
      origenId: t.origenId,
      destinoId: t.destinoId,
      estado: EstadoDeTransferencia.cancelada,
      lineas: t.lineas,
      solicitanteId: t.solicitanteId,
      fechaSolicitud: t.fechaSolicitud,
      numero: t.numero,
      auditoria: t.auditoria,
    );
    final json = TransferenciaModel.cancelacionAJson(cancelada);
    expect(json.keys.toSet(), {
      'id',
      'estado',
      'created_at',
      'updated_at',
      'created_by',
      'deleted_at',
      'sync_version',
    });
    expect(json['estado'], 'CANCELADO');
  });

  test('la línea sube con su transferencia, su producto y la cantidad', () {
    final t = transferenciaDeEjemplo();
    final json = TransferenciaModel.lineaAJson(t.lineas.single, t);
    expect(json['id'], 'l-1');
    expect(json['transferencia_id'], 't-1');
    expect(json['producto_id'], 'p-1');
    expect(json['cantidad'], 2);
  });

  test('cada estado va y vuelve; EJECUTADO se lee como autorizada', () {
    for (final e in EstadoDeTransferencia.values) {
      expect(TransferenciaModel.estadoDesdeCodigo(TransferenciaModel.codigoDelEstado(e)), e);
    }
    expect(TransferenciaModel.estadoDesdeCodigo('EJECUTADO'), EstadoDeTransferencia.autorizada);
    expect(TransferenciaModel.estadoDesdeCodigo('???'), EstadoDeTransferencia.porAutorizar);
  });
}
