// Test del adaptador sobre flutter_secure_storage. El plugin se mockea: los tests nunca tocan
// el Keystore ni el canal nativo.
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro_keystore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockFlutterSecureStorage plugin;
  late AlmacenSeguroKeystore almacen;

  setUp(() {
    plugin = _MockFlutterSecureStorage();
    almacen = AlmacenSeguroKeystore(storage: plugin);
  });

  group('AlmacenSeguroKeystore', () {
    group('dado que el Keystore responde', () {
      test('cuando lee, usa el id documentado de la clave y devuelve el valor', () async {
        when(() => plugin.read(key: any(named: 'key'))).thenAnswer((_) async => 'dek');

        expect(await almacen.leer(ClaveSegura.dekDb), 'dek');
        verify(() => plugin.read(key: 'db_dek')).called(1);
      });

      test('cuando la clave no existe, devuelve null', () async {
        when(() => plugin.read(key: any(named: 'key'))).thenAnswer((_) async => null);

        expect(await almacen.leer(ClaveSegura.dbInicializada), isNull);
      });

      test('cuando escribe, manda id y valor al plugin', () async {
        when(
          () => plugin.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenAnswer((_) async {});

        await almacen.escribir(ClaveSegura.dbInicializada, 'true');

        verify(() => plugin.write(key: 'db_initialized', value: 'true')).called(1);
      });

      test('cuando borra, borra solo esa clave', () async {
        when(() => plugin.delete(key: any(named: 'key'))).thenAnswer((_) async {});

        await almacen.borrar(ClaveSegura.dekDb);

        verify(() => plugin.delete(key: 'db_dek')).called(1);
      });

      test('cuando borra todo, delega en deleteAll', () async {
        when(() => plugin.deleteAll()).thenAnswer((_) async {});

        await almacen.borrarTodo();

        verify(() => plugin.deleteAll()).called(1);
      });
    });

    group('dado un dispositivo donde el Keystore falla', () {
      test('cuando la plataforma lanza, la traduce a AlmacenSeguroException', () async {
        final dePlataforma = PlatformException(code: 'Exception', message: 'keystore roto');
        when(() => plugin.read(key: any(named: 'key'))).thenThrow(dePlataforma);

        await expectLater(
          almacen.leer(ClaveSegura.dekDb),
          throwsA(
            isA<AlmacenSeguroException>()
                .having((e) => e.operacion, 'operacion', 'leer')
                .having((e) => e.clave, 'clave', ClaveSegura.dekDb)
                .having((e) => e.causa, 'causa', dePlataforma),
          ),
        );
      });

      test('cuando falla borrarTodo, la excepción no apunta a ninguna clave', () async {
        when(() => plugin.deleteAll()).thenThrow(PlatformException(code: 'Exception'));

        await expectLater(
          almacen.borrarTodo(),
          throwsA(
            isA<AlmacenSeguroException>()
                .having((e) => e.operacion, 'operacion', 'borrarTodo')
                .having((e) => e.clave, 'clave', isNull),
          ),
        );
      });

      test('cuando el plugin no está registrado, también la traduce', () async {
        when(
          () => plugin.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenThrow(MissingPluginException('sin implementación'));

        await expectLater(
          almacen.escribir(ClaveSegura.dekDb, 'dek'),
          throwsA(isA<AlmacenSeguroException>()),
        );
      });

      test('cuando es un Error del programa, lo deja pasar sin disfrazarlo', () async {
        when(() => plugin.read(key: any(named: 'key'))).thenThrow(StateError('bug'));

        await expectLater(almacen.leer(ClaveSegura.dekDb), throwsA(isA<StateError>()));
      });
    });

    group('dado que no se le inyecta plugin', () {
      // Fija las opciones de plataforma de ADR-006 que enumera la doc del adaptador: si alguien
      // las cambia, este test lo obliga a actualizar la doc (y el ADR) junto con el código.
      late AlmacenSeguroKeystore porDefecto;

      setUp(() => porDefecto = AlmacenSeguroKeystore());

      test('cuando arma las opciones de Android, deja resetOnError en false: la app decide cuándo '
          'borrar, no el plugin (ADR-006)', () {
        expect(porDefecto.opcionesAndroid.toMap()['resetOnError'], 'false');
      });

      test('cuando arma las opciones de Android, deja encryptedSharedPreferences en false', () {
        expect(porDefecto.opcionesAndroid.toMap()['encryptedSharedPreferences'], 'false');
      });

      test('cuando arma las opciones de iOS, usa first_unlock_this_device: la DEK se lee con el '
          'equipo bloqueado y no viaja a otro equipo (ADR-006)', () {
        expect(
          porDefecto.opcionesIos.accessibility,
          KeychainAccessibility.first_unlock_this_device,
        );
      });

      test('cuando arma las opciones de iOS, no sincroniza por iCloud Keychain', () {
        expect(porDefecto.opcionesIos.synchronizable, isFalse);
      });
    });
  });
}
