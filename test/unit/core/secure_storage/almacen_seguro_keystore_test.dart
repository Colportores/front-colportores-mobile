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
        when(() => plugin.read(key: any(named: 'key'))).thenAnswer((_) async => 'sal');

        expect(await almacen.leer(ClaveSegura.salDb), 'sal');
        verify(() => plugin.read(key: 'db_salt')).called(1);
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

        await almacen.borrar(ClaveSegura.salDb);

        verify(() => plugin.delete(key: 'db_salt')).called(1);
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
          almacen.leer(ClaveSegura.salDb),
          throwsA(
            isA<AlmacenSeguroException>()
                .having((e) => e.operacion, 'operacion', 'leer')
                .having((e) => e.clave, 'clave', ClaveSegura.salDb)
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
          almacen.escribir(ClaveSegura.salDb, 'sal'),
          throwsA(isA<AlmacenSeguroException>()),
        );
      });

      test('cuando es un Error del programa, lo deja pasar sin disfrazarlo', () async {
        when(() => plugin.read(key: any(named: 'key'))).thenThrow(StateError('bug'));

        await expectLater(almacen.leer(ClaveSegura.salDb), throwsA(isA<StateError>()));
      });
    });

    test('cuando no se le inyecta plugin, usa el FlutterSecureStorage real', () {
      expect(AlmacenSeguroKeystore(), isA<AlmacenSeguro>());
    });
  });
}
