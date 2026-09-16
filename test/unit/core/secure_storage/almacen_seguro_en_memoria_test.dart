// Test del fake del almacén seguro: si el fake miente, todo lo que se apoya en él miente.
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:test/test.dart';

void main() {
  late AlmacenSeguroEnMemoria almacen;

  setUp(() => almacen = AlmacenSeguroEnMemoria());

  group('AlmacenSeguroEnMemoria', () {
    group('dado que el almacén está vacío', () {
      test('cuando lee una clave, devuelve null', () async {
        expect(await almacen.leer(ClaveSegura.salDb), isNull);
      });

      test('cuando borra una clave que no existe, no lanza', () async {
        await expectLater(almacen.borrar(ClaveSegura.salDb), completes);
      });
    });

    group('dado que hay valores guardados', () {
      setUp(() async {
        await almacen.escribir(ClaveSegura.salDb, 'sal');
        await almacen.escribir(ClaveSegura.dbInicializada, 'true');
      });

      test('cuando lee, devuelve lo escrito', () async {
        expect(await almacen.leer(ClaveSegura.salDb), 'sal');
        expect(await almacen.leer(ClaveSegura.dbInicializada), 'true');
      });

      test('cuando reescribe una clave, reemplaza el valor anterior', () async {
        await almacen.escribir(ClaveSegura.salDb, 'otra');

        expect(await almacen.leer(ClaveSegura.salDb), 'otra');
      });

      test('cuando borra una clave, no toca las demás', () async {
        await almacen.borrar(ClaveSegura.salDb);

        expect(await almacen.leer(ClaveSegura.salDb), isNull);
        expect(await almacen.leer(ClaveSegura.dbInicializada), 'true');
      });

      test('cuando borra todo, el almacén queda vacío', () async {
        await almacen.borrarTodo();

        expect(almacen.contenido, isEmpty);
      });

      test('cuando se inspecciona el contenido, no se lo puede modificar', () {
        expect(() => almacen.contenido[ClaveSegura.salDb] = 'x', throwsUnsupportedError);
      });
    });

    group('dado un dispositivo donde el almacén seguro no funciona', () {
      setUp(() => almacen.simularFalla = true);

      test('cuando se opera, cada operación lanza AlmacenSeguroException', () async {
        final falla = throwsA(isA<AlmacenSeguroException>());

        await expectLater(almacen.leer(ClaveSegura.salDb), falla);
        await expectLater(almacen.escribir(ClaveSegura.salDb, 'sal'), falla);
        await expectLater(almacen.borrar(ClaveSegura.salDb), falla);
        await expectLater(almacen.borrarTodo(), falla);
      });
    });

    test('cuando se construye con valores iniciales, los expone sin compartir el mapa', () async {
      final inicial = {ClaveSegura.salDb: 'sal'};
      final conDatos = AlmacenSeguroEnMemoria(inicial);

      await conDatos.escribir(ClaveSegura.dbInicializada, 'true');

      expect(await conDatos.leer(ClaveSegura.salDb), 'sal');
      expect(inicial, hasLength(1), reason: 'el mapa de entrada no se muta');
    });
  });

  group('AlmacenSeguroException', () {
    test('cuando se imprime, muestra operación y clave sin el valor guardado', () {
      const falla = AlmacenSeguroException(operacion: 'escribir', clave: ClaveSegura.salDb);

      expect(falla.toString(), 'AlmacenSeguroException(escribir, salDb)');
    });

    test('cuando no apunta a una clave, la omite', () {
      const falla = AlmacenSeguroException(operacion: 'borrarTodo');

      expect(falla.toString(), 'AlmacenSeguroException(borrarTodo)');
    });
  });

  group('ClaveSegura', () {
    test('los ids son los nombres documentados y no se repiten', () {
      expect(ClaveSegura.salDb.id, 'db_salt');
      expect(ClaveSegura.dbInicializada.id, 'db_initialized');
      expect(ClaveSegura.values.map((c) => c.id).toSet(), hasLength(ClaveSegura.values.length));
    });
  });
}
