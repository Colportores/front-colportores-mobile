// El cifrado del backup (RF-AL06, ADR-003), probado en la VM.
//
// Lo que se verifica no es "ida y vuelta funciona" —eso es una línea— sino las
// propiedades de las que depende que el backup sirva de algo: que dos backups
// iguales no se vean iguales, y que un byte cambiado se note en vez de pasar
// como dato bueno.

import 'dart:convert';

import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

List<int> _clave(int semilla) =>
    List<int>.generate(32, (i) => (i * 7 + semilla) % 256);

/// Un backup realista: JSON con muchos strings repetidos.
List<int> _backup({int filas = 200}) => utf8.encode(jsonEncode({
      'persona': [
        for (var i = 0; i < filas; i++)
          {
            'id': '018f2c4e-6b7d-7a11-9f3c-8e2d5b6a7c$i',
            'nombre': 'Juan Pérez',
            'telefono': '099123456',
            'nota': 'Volver el martes a la tarde',
          }
      ],
    }));

void main() {
  test('lo que se cifra se recupera igual', () async {
    final crypto = AesGcmCrypto(_clave(1));
    final original = _backup();

    final cifrado = await crypto.encrypt(original);
    expect(await crypto.decrypt(cifrado), original);
  });

  // La propiedad que más fácil se rompe si alguien intenta "hacerlo
  // determinístico para deduplicar": repetir un nonce con la misma clave no
  // filtra solo ese backup, permite falsificar cualquiera.
  test('dos backups idénticos no producen el mismo bloque', () async {
    final crypto = AesGcmCrypto(_clave(1));
    final datos = utf8.encode('la misma jornada, dos veces');

    final a = await crypto.encrypt(datos);
    final b = await crypto.encrypt(datos);

    expect(a, isNot(b), reason: 'el nonce tiene que ser nuevo en cada bloque');
    expect(await crypto.decrypt(a), datos);
    expect(await crypto.decrypt(b), datos);
  });

  test('un byte cambiado no se descifra: falla, no devuelve basura', () async {
    final crypto = AesGcmCrypto(_clave(1));
    final cifrado = await crypto.encrypt(_backup());

    // En el medio del ciphertext, ni en el nonce ni en el tag.
    final alterado = [...cifrado];
    final medio = alterado.length ~/ 2;
    alterado[medio] = alterado[medio] ^ 0x01;

    await expectLater(
      crypto.decrypt(alterado),
      throwsA(isA<BackupIlegible>()),
      reason: 'devolver bytes acá haría que el restore siga adelante con '
          'datos que nadie escribió',
    );
  });

  test('con otra clave tampoco', () async {
    final cifrado = await AesGcmCrypto(_clave(1)).encrypt(_backup());

    await expectLater(
      AesGcmCrypto(_clave(2)).decrypt(cifrado),
      throwsA(isA<BackupIlegible>()),
    );
  });

  test('un bloque más corto que su sobre falla con un motivo, no con un '
      'error de rango', () async {
    await expectLater(
      AesGcmCrypto(_clave(1)).decrypt(const [1, 2, 3]),
      throwsA(isA<BackupIlegible>()),
    );
  });

  test('una clave que no es de 256 bits no se acepta', () {
    expect(() => AesGcmCrypto(List<int>.filled(16, 0)), throwsArgumentError,
        reason: 'una clave más corta no es "menos segura": es otro algoritmo');
    expect(() => AesGcmCrypto(List<int>.filled(32, 0)), returnsNormally);
  });

  // Cierra el orden de ADR-003 de punta a punta: si alguien invirtiera
  // comprimir y cifrar, esto se dispara. Un ciphertext no comprime.
  test('comprime antes de cifrar, no al revés', () async {
    final crypto = AesGcmCrypto(_clave(1));
    final original = _backup();

    final cifrado = await crypto.encrypt(original);

    expect(cifrado.length, lessThan(original.length ~/ 2),
        reason: 'un backup de un colportor es mayormente texto repetido: es '
            'la diferencia entre subir megabytes o cientos de kilobytes de '
            'su plan de datos');
  });

  test('el digest es del bloque cifrado, para poder verificar sin la clave',
      () async {
    final crypto = AesGcmCrypto(_clave(1));
    final cifrado = await crypto.encrypt(_backup());

    expect(crypto.digest(cifrado), hasLength(64));
    expect(crypto.digest(cifrado), crypto.digest(cifrado));
    expect(crypto.digest(cifrado), isNot(crypto.digest(const [0])));
  });

  // Lo que cierra RF-AL06 no es que el cifrado ande suelto, sino que la cadena
  // de backup lo use: `DriveArchive` y `DriftSnapshot` ya estaban, faltaba
  // esto en el medio.
  group('la cadena de backup, con el cifrado de verdad', () {
    ({BackupService service, FakeArchive drive, FakeSnapshot snap}) armar(
      List<int> clave,
    ) {
      final crypto = AesGcmCrypto(clave);
      // El mismo digest de los dos lados, o `verifyChain()` compara un hash
      // contra otro y da cadena rota siempre.
      final drive = FakeArchive(authorized: true, digest: crypto.digest);
      final snap = FakeSnapshot();
      return (
        service: BackupService(archive: drive, crypto: crypto, snapshot: snap),
        drive: drive,
        snap: snap,
      );
    }

    // RD-01 y la Ley 18.331: `persona` y `nota` no salen del dispositivo. La
    // única excepción es este backup, y solo porque va cifrado. Si esto
    // fallara, el nombre y el teléfono de cada contacto de cada colportor
    // estarían en Drive en texto plano.
    test('lo que queda en Drive no tiene un solo dato personal legible',
        () async {
      final (:service, :drive, :snap) = armar(_clave(1));
      snap.state = {'nombre': 'Juan Pérez', 'telefono': '099123456'};

      final entrada = await service.backupNow(watermark: 'w-1');
      final subido = await drive.download(entrada.id);

      expect(utf8.decode(subido, allowMalformed: true), isNot(contains('Juan')));
      expect(
          utf8.decode(subido, allowMalformed: true), isNot(contains('099123456')));
    });

    test('otro teléfono con la misma clave restaura la cadena entera',
        () async {
      final clave = _clave(7);
      final (service: subida, :drive, snap: origen) = armar(clave);

      origen.state = {'a': 1};
      await subida.backupNow(watermark: 'w-1');
      origen.state = {'b': 2};
      await subida.backupNow(watermark: 'w-2');

      // El teléfono nuevo: otra DB local, el mismo Drive y la misma clave.
      final destino = FakeSnapshot();
      final segundo = BackupService(
        archive: drive,
        crypto: AesGcmCrypto(clave),
        snapshot: destino,
      );

      expect(await segundo.restore(), isNotNull);
      expect(destino.restored!.keys, containsAll(['a', 'b']));
    });

    // El otro lado de lo mismo, y la razón por la que de dónde sale la clave
    // es una decisión y no un detalle: si vive **solo** en el Keystore del
    // teléfono perdido, este test describe lo que le pasa al colportor que
    // cambia de teléfono, y RF-AL04 no se cumple.
    test('sin la clave, el backup no sirve para nada', () async {
      final (service: subida, :drive, :snap) = armar(_clave(7));
      snap.state = {'a': 1};
      await subida.backupNow(watermark: 'w-1');

      final otro = BackupService(
        archive: drive,
        crypto: AesGcmCrypto(_clave(8)),
        snapshot: FakeSnapshot(),
      );

      await expectLater(otro.restore(), throwsA(isA<BackupIlegible>()));
    });
  });
}
