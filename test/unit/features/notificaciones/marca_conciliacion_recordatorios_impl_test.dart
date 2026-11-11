// HU-NOT-005 / issue #416 — hasta dónde se revisaron los recordatorios que sonaron: sobre el almacén
// seguro, con la clave `ultimaConciliacionRecordatorios`.
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/marca_conciliacion_recordatorios_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AlmacenSeguroEnMemoria almacen;
  late MarcaConciliacionRecordatoriosImpl marca;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    marca = MarcaConciliacionRecordatoriosImpl(almacen);
  });

  test('dado que nunca se guardó, no hay marca', () async {
    expect(await marca.leer(), isNull);
  });

  test('dado lo guardado, lo lee en UTC y al milisegundo', () async {
    final hasta = DateTime.utc(2026, 10, 27, 15, 10, 5, 123);

    await marca.guardar(hasta);

    expect(
      almacen.contenido[ClaveSegura.ultimaConciliacionRecordatorios],
      '${hasta.millisecondsSinceEpoch}',
    );
    final leida = await marca.leer();
    expect(leida, hasta);
    expect(leida!.isUtc, isTrue);
  });

  test('dado una hora local, guarda el mismo instante', () async {
    final local = DateTime.utc(2026, 10, 27, 15, 10).toLocal();

    await marca.guardar(local);

    expect(await marca.leer(), DateTime.utc(2026, 10, 27, 15, 10));
  });

  test('dado un valor que no es un número, cuenta como nunca guardado', () async {
    for (final basura in ['', 'ayer', '12:00', '1.5e3x']) {
      await almacen.escribir(ClaveSegura.ultimaConciliacionRecordatorios, basura);
      expect(await marca.leer(), isNull, reason: basura);
    }
  });

  test('guardar de nuevo reemplaza la marca anterior', () async {
    await marca.guardar(DateTime.utc(2026, 10, 27, 12));
    await marca.guardar(DateTime.utc(2026, 10, 27, 15));

    expect(await marca.leer(), DateTime.utc(2026, 10, 27, 15));
  });

  group('en memoria', () {
    test('lee lo guardado y lanza cuando se le pide fallar', () async {
      final enMemoria = MarcaConciliacionRecordatoriosEnMemoria();
      expect(await enMemoria.leer(), isNull);

      await enMemoria.guardar(DateTime.utc(2026, 10, 27, 12));
      expect(await enMemoria.leer(), DateTime.utc(2026, 10, 27, 12));

      enMemoria.fallaAlLeer = true;
      await expectLater(enMemoria.leer(), throwsA(isA<AlmacenSeguroException>()));
      enMemoria.fallaAlGuardar = true;
      await expectLater(
        enMemoria.guardar(DateTime.utc(2026)),
        throwsA(isA<AlmacenSeguroException>()),
      );
    });
  });
}
