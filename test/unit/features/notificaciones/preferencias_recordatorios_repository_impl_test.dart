// Lo que el teléfono recuerda de las preferencias de los recordatorios (HU-NOT-004): sobre el almacén
// seguro, con las claves `recordatoriosActivados` y `anticipacionRecordatorios`.
import 'dart:async';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/preferencias_recordatorios_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AlmacenSeguroEnMemoria almacen;
  late PreferenciasRecordatoriosRepositoryImpl repositorio;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    repositorio = PreferenciasRecordatoriosRepositoryImpl(almacen);
  });

  group('leer', () {
    test('dado que nunca eligió nada, los recordatorios están prendidos con 30 minutos', () async {
      final p = await repositorio.leer();

      expect(p, const PreferenciasRecordatorios());
      expect(p.activados, isTrue);
      expect(p.anticipacionMinutos, 30);
    });

    test('dado lo guardado, lo lee', () async {
      await almacen.escribir(ClaveSegura.recordatoriosActivados, '0');
      await almacen.escribir(ClaveSegura.anticipacionRecordatorios, '75');

      expect(
        await repositorio.leer(),
        const PreferenciasRecordatorios(activados: false, anticipacionMinutos: 75),
      );
    });

    test('dado un valor de anticipación fuera de rango, lo acota a 5..120', () async {
      await almacen.escribir(ClaveSegura.anticipacionRecordatorios, '4');
      expect((await repositorio.leer()).anticipacionMinutos, 5);
      await almacen.escribir(ClaveSegura.anticipacionRecordatorios, '121');
      expect((await repositorio.leer()).anticipacionMinutos, 120);
      await almacen.escribir(ClaveSegura.anticipacionRecordatorios, '-30');
      expect((await repositorio.leer()).anticipacionMinutos, 5);
    });

    test('dado un valor que no es un número, vuelve a los 30 minutos', () async {
      for (final basura in ['', 'abc', '30.5', ' ']) {
        await almacen.escribir(ClaveSegura.anticipacionRecordatorios, basura);
        expect((await repositorio.leer()).anticipacionMinutos, 30, reason: '«$basura»');
      }
    });

    test('dado cualquier valor distinto de «0», los recordatorios están prendidos', () async {
      for (final valor in ['1', 'si', '', 'basura']) {
        await almacen.escribir(ClaveSegura.recordatoriosActivados, valor);
        expect((await repositorio.leer()).activados, isTrue, reason: '«$valor»');
      }
    });

    test('dado un almacén roto, lanza', () async {
      almacen.simularFalla = true;

      await expectLater(repositorio.leer(), throwsA(isA<AlmacenSeguroException>()));
    });
  });

  group('guardar', () {
    test('apagar y prender quedan guardados como 0 y 1', () async {
      await repositorio.guardarActivados(activados: false);
      expect(almacen.contenido[ClaveSegura.recordatoriosActivados], '0');
      expect((await repositorio.leer()).activados, isFalse);

      await repositorio.guardarActivados(activados: true);
      expect(almacen.contenido[ClaveSegura.recordatoriosActivados], '1');
      expect((await repositorio.leer()).activados, isTrue);
    });

    test('la anticipación se guarda acotada a 5..120', () async {
      await repositorio.guardarAnticipacion(60);
      expect(almacen.contenido[ClaveSegura.anticipacionRecordatorios], '60');
      await repositorio.guardarAnticipacion(0);
      expect(almacen.contenido[ClaveSegura.anticipacionRecordatorios], '5');
      await repositorio.guardarAnticipacion(1000);
      expect(almacen.contenido[ClaveSegura.anticipacionRecordatorios], '120');
    });

    test('guardar una cosa no toca la otra', () async {
      await repositorio.guardarAnticipacion(90);
      await repositorio.guardarActivados(activados: false);

      expect(
        await repositorio.leer(),
        const PreferenciasRecordatorios(activados: false, anticipacionMinutos: 90),
      );
    });

    test('dado un almacén que no deja escribir, lanza y no cambia nada', () async {
      almacen.simularFalla = true;

      await expectLater(
        repositorio.guardarAnticipacion(60),
        throwsA(isA<AlmacenSeguroException>()),
      );
      await expectLater(
        repositorio.guardarActivados(activados: false),
        throwsA(isA<AlmacenSeguroException>()),
      );
      almacen.simularFalla = false;
      expect(await repositorio.leer(), const PreferenciasRecordatorios());
    });

    test('una falla no frena las operaciones que vienen después', () async {
      almacen.simularFalla = true;
      await expectLater(
        repositorio.guardarAnticipacion(60),
        throwsA(isA<AlmacenSeguroException>()),
      );
      almacen.simularFalla = false;

      await repositorio.guardarAnticipacion(45);

      expect((await repositorio.leer()).anticipacionMinutos, 45);
    });
  });

  group('lo que lee RecordatoriosLocales', () {
    test('estan() y minutos() ven lo último que se guardó, en el orden en que se pidió', () async {
      unawaited(repositorio.guardarActivados(activados: false));
      unawaited(repositorio.guardarAnticipacion(10));

      expect(await repositorio.estan(), isFalse);
      expect(await repositorio.minutos(), 10);
    });
  });

  group('el fake en memoria', () {
    test('se comporta igual: guarda acotado, avisa lo guardado y lanza si se le pide', () async {
      final fake = PreferenciasRecordatoriosRepositoryEnMemoria();
      await fake.guardarAnticipacion(500);
      await fake.guardarActivados(activados: false);

      expect(
        await fake.leer(),
        const PreferenciasRecordatorios(activados: false, anticipacionMinutos: 120),
      );
      expect(fake.guardados, ['minutos:500', 'activados:false']);
      expect(await fake.estan(), isFalse);
      expect(await fake.minutos(), 120);

      fake.fallaAlGuardar = true;
      await expectLater(fake.guardarAnticipacion(30), throwsA(isA<AlmacenSeguroException>()));
      await expectLater(
        fake.guardarActivados(activados: true),
        throwsA(isA<AlmacenSeguroException>()),
      );
      fake
        ..fallaAlGuardar = false
        ..fallaAlLeer = true;
      await expectLater(fake.leer(), throwsA(isA<AlmacenSeguroException>()));
    });

    test('un guardado demorado espera a que se complete', () async {
      final fake = PreferenciasRecordatoriosRepositoryEnMemoria()
        ..guardadoDemorado = Completer<void>();
      var termino = false;

      final futuro = fake.guardarAnticipacion(60).then((_) => termino = true);
      await Future<void>.delayed(Duration.zero);
      expect(termino, isFalse);
      fake.guardadoDemorado!.complete();
      await futuro;

      expect(termino, isTrue);
    });
  });
}
