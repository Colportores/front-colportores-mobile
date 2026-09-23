// Presupuesto de datos y de memoria.
//
// RR-02 pide menos de 1 MB por sync. RA-PO01 apunta a celulares de 5+ años.
// Ninguno de los dos se cumple por buena voluntad: se cumple o no según cuántos
// bytes se manden y cuánto se cargue en memoria de una. Estos tests miden con
// una jornada y una temporada realistas, e imprimen los números.

import 'dart:convert';

import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

const _entidades = {'venta', 'visita', 'ubicacion', 'producto', 'persona'};

SpecRegistry _registro() => SpecRegistry([
      SyncSpec.push('venta', critical: true),
      SyncSpec.push('visita'),
      SyncSpec.push('ubicacion', alsoPull: true),
      SyncSpec.pull('producto'),
      SyncSpec.local('persona'),
    ], allEntities: _entidades);

/// Una venta con lo que realmente lleva: montos como String, sin PII.
Map<String, Object?> _venta(int i) => {
      'id': '018f2c4e-6b7d-7a11-9f3c-8e2d5b6a$i',
      'pk_ubicacion': '018f2c4e-6b7d-7a11-9f3c-8e2d5b6b$i',
      'total': '1200.00',
      'entregado': '800.00',
      'estado': 'PENDIENTE_DE_COBRO',
      'fecha': '2026-11-13T14:32:00.000Z',
      'sync_version': 1,
    };

Map<String, Object?> _visita(int i) => {
      'id': '018f2c4e-6b7d-7a11-9f3c-8e2d5b6c$i',
      'pk_ubicacion': '018f2c4e-6b7d-7a11-9f3c-8e2d5b6b$i',
      'resultado': 'NO_ESTABA',
      'fecha': '2026-11-13T14:32:00.000Z',
      'sync_version': 1,
    };

int _bytesEnElCable(FakeSyncTransport t) =>
    t.batches.fold(0, (n, lote) => n + batchBytes(lote));

void main() {
  test('una jornada entera entra en el presupuesto de RR-02', () async {
    final transport = FakeSyncTransport();
    final motor = SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: InMemoryJobStore(),
      store: InMemoryLocalStore(),
    );

    // Un día de campo: 120 visitas, 20 de las cuales terminan en venta.
    for (var i = 0; i < 120; i++) {
      await motor.stage('visita', Op.insert, _visita(i),
          clientOpId: 'op-vi-$i');
      if (i % 6 == 0) {
        await motor.stage('venta', Op.insert, _venta(i),
            clientOpId: 'op-ve-$i');
      }
    }
    await motor.syncNow();

    final bytes = _bytesEnElCable(transport);
    print('  jornada: ${transport.batches.length} lote(s), '
        '${(bytes / 1024).toStringAsFixed(1)} KB, 140 registros');

    expect(bytes, lessThan(1024 * 1024), reason: 'RR-02: < 1 MB por sync');

    // Acá los stage() van uno detrás del otro, así que la ventana de
    // criticalDebounce los junta a todos. En la calle las ventas están
    // separadas por horas y cada una sale sola, que es lo que se quiere: lo
    // que la ventana junta son las ráfagas —una venta con sus items—, no la
    // jornada entera.
    expect(transport.batches, hasLength(1),
        reason: 'antes de la ventana esto eran 21 requests: uno por venta');
    await motor.dispose();
  });

  test('7 días sin conexión: cuántos MB paga el colportor al reconectar',
      () async {
    final transport = FakeSyncTransport();
    final motor = SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: InMemoryJobStore(),
      store: InMemoryLocalStore(),
    );

    for (var d = 0; d < 7; d++) {
      for (var i = 0; i < 120; i++) {
        await motor.stage('visita', Op.insert, _visita(d * 1000 + i),
            clientOpId: 'op-vi-$d-$i');
        if (i % 6 == 0) {
          await motor.stage('venta', Op.insert, _venta(d * 1000 + i),
              clientOpId: 'op-ve-$d-$i');
        }
      }
    }
    for (var i = 0; i < 10; i++) {
      if ((await motor.syncNow()).pushed == 0) break;
    }

    final bytes = _bytesEnElCable(transport);
    print('  7 días: ${transport.batches.length} lotes, '
        '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB, 980 registros');

    // Sin gzip en el push (el contrato no lo pide para el BFF). Si esto se
    // pasa de unos pocos MB, comprimir el push deja de ser opcional.
    expect(bytes, lessThan(5 * 1024 * 1024));
    await motor.dispose();
  });

  test('editar la misma fila 50 veces manda 50 jobs: cuánto cuesta', () async {
    final transport = FakeSyncTransport();
    final motor = SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: InMemoryJobStore(),
      store: InMemoryLocalStore(),
    );

    // El colportor corrige el estado de la misma ubicación toda la tarde.
    await motor.stage('ubicacion', Op.insert,
        {'id': 'u-1', 'estado': 'NO_VISITADA', 'sync_version': 1},
        clientOpId: 'op-0');
    for (var i = 1; i <= 50; i++) {
      await motor.stage('ubicacion', Op.update,
          {'id': 'u-1', 'estado': 'INTENTO_$i', 'sync_version': i},
          clientOpId: 'op-$i', syncVersion: i);
    }
    await motor.syncNow();

    final bytes = _bytesEnElCable(transport);
    final ultimoSolo =
        batchBytes(PushBatch([transport.batches.last.jobs.last]));

    print('  51 ediciones de una fila: ${bytes}B en el cable; '
        'solo la última serían ~${ultimoSolo}B '
        '(${(bytes / ultimoSolo).toStringAsFixed(0)}× más)');

    // Documenta el costo, no lo arregla: compactar la outbox cambia lo que el
    // servidor ve y eso es una decisión del contrato, no del motor.
    expect(transport.batches.single.length, 51,
        reason: 'hoy no se compacta nada');
    await motor.dispose();
  });

  group('backup (ADR-003, RA-PO01)', () {
    /// Un cifrado de mentira que no cambia el tamaño: mide la compresión sola.
    late final crypto = _CryptoNeutro();

    test('una temporada entera comprime a un tamaño razonable', () async {
      // ~15.000 filas: una campaña de verano completa.
      final db = utf8.encode(jsonEncode({
        'venta': [for (var i = 0; i < 2000; i++) _venta(i)],
        'visita': [for (var i = 0; i < 12000; i++) _visita(i)],
        'persona': [
          for (var i = 0; i < 1000; i++)
            {
              'id': 'p-$i',
              'nombre': 'Nombre Apellido $i',
              'telefono': '3751000$i'
            }
        ],
      }));

      final reloj = Stopwatch()..start();
      final cifrado = await crypto.encrypt(db);
      final comprimir = reloj.elapsedMilliseconds;

      reloj.reset();
      final vuelta = await crypto.decrypt(cifrado);
      final descomprimir = reloj.elapsedMilliseconds;

      print('  temporada: ${(db.length / 1024 / 1024).toStringAsFixed(2)} MB → '
          '${(cifrado.length / 1024).toStringAsFixed(0)} KB '
          '(${(db.length / cifrado.length).toStringAsFixed(0)}× menos) · '
          'comprimir ${comprimir}ms · descomprimir ${descomprimir}ms');

      expect(vuelta, db);
      expect(cifrado.length, lessThan(db.length ~/ 5));

      // En un celular de 5 años esto es varias veces más lento. La cota está
      // para que un cambio que lo vuelva cuadrático se note acá y no en I4.
      expect(comprimir, lessThan(10000));
    });
  });
}

class _CryptoNeutro extends CompressingCrypto {
  @override
  Future<List<int>> encryptBytes(List<int> plaintext) async => plaintext;

  @override
  Future<List<int>> decryptBytes(List<int> ciphertext) async => ciphertext;
}
