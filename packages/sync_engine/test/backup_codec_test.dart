// La parte no-nativa de ADR-003, probada en la VM.

import 'dart:convert';

import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

/// Un "cifrado" de mentira que registra qué le llegó: alcanza para verificar el
/// orden comprimir → cifrar, que es lo único que no puede estar al revés.
class CryptoDePrueba extends CompressingCrypto {
  CryptoDePrueba({super.isolateThreshold = 64 * 1024});

  final List<List<int>> recibido = [];

  @override
  Future<List<int>> encryptBytes(List<int> plaintext) async {
    recibido.add(plaintext);
    return plaintext.reversed.toList();
  }

  @override
  Future<List<int>> decryptBytes(List<int> ciphertext) async =>
      ciphertext.reversed.toList();
}

/// Un backup realista: JSON con muchos strings repetidos.
List<int> _backupDeEjemplo({int filas = 500}) => utf8.encode(jsonEncode({
      'venta': [
        for (var i = 0; i < filas; i++)
          {
            'id': '018f2c4e-6b7d-7a11-9f3c-8e2d5b6a7c$i',
            'total': '1200.00',
            'estado': 'PENDIENTE_DE_COBRO',
            'sync_version': 1,
          }
      ],
    }));

void main() {
  test('ida y vuelta: lo que entra es lo que sale', () async {
    final crypto = CryptoDePrueba();
    final original = _backupDeEjemplo();

    final cifrado = await crypto.encrypt(original);
    expect(await crypto.decrypt(cifrado), original);
  });

  test('comprime antes de cifrar, no al revés', () async {
    final crypto = CryptoDePrueba();
    final original = _backupDeEjemplo();

    await crypto.encrypt(original);

    final loQueSeCifro = crypto.recibido.single;
    expect(loQueSeCifro.length, lessThan(original.length),
        reason: 'al cifrar primero, el ciphertext es ruido y el ruido no '
            'comprime: el colportor pagaría el backup entero sin comprimir');
  });

  test('un backup real se achica de verdad', () async {
    final crypto = CryptoDePrueba();
    final original = _backupDeEjemplo(filas: 2000);
    final cifrado = await crypto.encrypt(original);

    expect(cifrado.length, lessThan(original.length ~/ 5),
        reason: 'la DB de un colportor son strings repetidos; '
            '${original.length} → ${cifrado.length} bytes');
  });

  test('los payloads grandes pasan por un isolate y salen iguales', () async {
    // Umbral bajo para forzar el camino del isolate.
    final crypto = CryptoDePrueba(isolateThreshold: 1024);
    final original = _backupDeEjemplo(filas: 3000);

    expect(original.length, greaterThan(1024));
    final cifrado = await crypto.encrypt(original);
    expect(await crypto.decrypt(cifrado), original,
        reason: 'lo que corre en un isolate no puede capturar this');
  });

  test('los payloads chicos no pagan el arranque del isolate', () async {
    final crypto = CryptoDePrueba();
    final chico = utf8.encode('{"venta":[]}');
    expect(await crypto.decrypt(await crypto.encrypt(chico)), chico);
  });

  group('digest', () {
    test('es SHA-256 en hexadecimal', () {
      final crypto = CryptoDePrueba();
      // Vector conocido: sha256("abc").
      expect(crypto.digest(utf8.encode('abc')),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('un byte distinto es otro hash', () {
      final crypto = CryptoDePrueba();
      expect(crypto.digest(const [1, 2, 3]),
          isNot(crypto.digest(const [1, 2, 4])));
    });

    test('se calcula sobre el ciphertext: verificar no necesita la clave',
        () async {
      final crypto = CryptoDePrueba();
      final cifrado = await crypto.encrypt(_backupDeEjemplo());

      expect(crypto.digest(cifrado), isNotEmpty,
          reason: 'verifyChain() corre sin descifrar nada');
    });
  });

  test('encaja con BackupService sin que se entere', () async {
    final crypto = CryptoDePrueba();
    // El archivo hashea con el mismo crypto que cifra, como en producción.
    final drive = FakeArchive(authorized: true, digest: crypto.digest);
    final snap = FakeSnapshot()..state = {'persona': 'Ana Gómez'};
    final service =
        BackupService(archive: drive, crypto: crypto, snapshot: snap);

    await service.backupNow(watermark: 'w-1');
    expect((await service.verifyChain()).ok, isTrue);

    final subido = await drive.download('backup-1');
    expect(utf8.decode(subido, allowMalformed: true), isNot(contains('Ana')));

    expect((await service.restore())!.id, 'backup-1');
    expect(snap.restored!['persona'], 'Ana Gómez');
  });
}
