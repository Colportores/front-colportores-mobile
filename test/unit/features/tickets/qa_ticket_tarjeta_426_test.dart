// QA del ticket de tarjeta (HU-COB-007, #426): lo que las pruebas del PR no cubren. El PR no trae
// pantallas (son la vista 29 C, #427), así que acá se prueba lo que esas pantallas van a necesitar:
// entradas pegadas o raras, doble toque simultáneo con el disco de verdad, y reentrada.
import 'dart:io';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/tickets/data/datasources/ticket_local_data_source_drift.dart';
import 'package:colportores_mobile/features/tickets/data/repositories/ticket_repository_impl.dart';
import 'package:colportores_mobile/features/tickets/data/services/almacen_de_fotos_en_disco.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/usecases/borrar_copia_local_de_ticket_use_case.dart';
import 'package:colportores_mobile/features/tickets/domain/usecases/registrar_ticket_use_case.dart';
import 'package:dartz/dartz.dart' hide id;
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../helpers/logger_mudo.dart';
import '../../../helpers/tickets_falsos.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late Directory carpeta;
  late TicketRepositoryImpl repo;
  late RegistrarTicketUseCase registrar;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    carpeta = Directory.systemTemp.createTempSync('qa426_');
    repo = TicketRepositoryImpl(
      TicketLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria()),
      AlmacenDeFotosEnDisco(carpeta.path),
      logger: loggerMudo(),
      ahora: () => ahoraTicket,
    );
    registrar = RegistrarTicketUseCase(repo, ahora: () => ahoraTicket);
  });
  tearDown(() async {
    await db.close();
    if (carpeta.existsSync()) carpeta.deleteSync(recursive: true);
  });

  RegistrarTicketParams params(
    String id, {
    int monto = 150000,
    String? autorizacion = '123456',
    TipoDeTarjeta? tarjeta = TipoDeTarjeta.debito,
    String? marca,
    String? cobroId,
    int fotoBytes = 1000,
  }) => RegistrarTicketParams(
    ticketId: id,
    colportorId: 'col-1',
    tipo: TipoDeTicket.cobroTarjeta,
    montoCentavos: monto,
    foto: fotoDePrueba(fotoBytes),
    tipoDeImagen: TipoDeImagen.jpeg,
    fecha: ahoraTicket,
    numeroAutorizacion: autorizacion,
    tarjetaTipo: tarjeta,
    tarjetaMarca: marca,
    cobroId: cobroId,
  );

  Future<int> cuantosTickets() async => (await db.select(db.tickets).get()).length;

  Future<void> cobro(String id, {String? ticketId}) => db
      .into(db.cobranzas)
      .insert(
        CobranzasCompanion.insert(
          id: id,
          ventaId: 'v-1',
          monto: 150000,
          medio: 'TARJETA',
          fecha: ahoraTicket,
          ticketId: Value(ticketId),
          createdAt: ahoraTicket,
          updatedAt: ahoraTicket,
        ),
      );

  group('Edge «falta el número de autorización»: entradas raras del campo', () {
    test('solo espacios, tabuladores y saltos de línea cuentan como vacío', () async {
      for (final texto in ['   ', '\t', '\n', ' \t\n ']) {
        final r = await registrar(params('t-${texto.hashCode}', autorizacion: texto));
        expect(r.fold((f) => f, (_) => null), isA<FailureTicketSinAutorizacion>());
      }
      expect(await cuantosTickets(), 0);
      expect(carpeta.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test('texto pegado muy largo (10 mil caracteres): no guarda nada y dice el límite', () async {
      final r = await registrar(params('t-largo', autorizacion: '9' * 10000));
      final falla = r.fold((f) => f, (_) => null);
      expect(falla, isA<FailureTicketTextoLargo>());
      expect(falla!.mensaje, contains('40'));
      expect(await cuantosTickets(), 0);
    });

    test('40 caracteres entran; 41 no; el límite se mide sin los espacios de los bordes', () async {
      expect((await registrar(params('t-40', autorizacion: '1' * 40))).isRight(), isTrue);
      expect((await registrar(params('t-41', autorizacion: '1' * 41))).isLeft(), isTrue);
      expect(
        (await registrar(params('t-borde', autorizacion: '  ${'1' * 40}  '))).isRight(),
        isTrue,
      );
    });

    test(
      'emoji y caracteres especiales en la autorización o la marca se guardan tal cual',
      () async {
        final r = await registrar(
          params('t-emoji', autorizacion: 'AB-12/3 ñ 😀', marca: 'Visa 💳'),
        );
        final ok = r.getOrElse(() => throw StateError('no guardó'));
        expect(ok.ticket.numeroAutorizacion, 'AB-12/3 ñ 😀');
        expect(ok.ticket.tarjetaMarca, 'Visa 💳');
        final fila = await db.select(db.tickets).getSingle();
        expect(fila.numeroAutorizacion, 'AB-12/3 ñ 😀');
      },
    );

    test('monto: 1 centavo entra, el máximo entra, uno más no, y no guarda el archivo', () async {
      expect((await registrar(params('t-min', monto: 1))).isRight(), isTrue);
      expect((await registrar(params('t-max', monto: 2147483647))).isRight(), isTrue);
      expect((await registrar(params('t-sobra', monto: 2147483648))).isLeft(), isTrue);
      expect((await registrar(params('t-neg', monto: -5))).isLeft(), isTrue);
      expect(carpeta.listSync(recursive: true).whereType<File>().length, 2);
    });

    test('foto de exactamente 2 MiB entra; un byte más no', () async {
      expect((await registrar(params('t-2mib', fotoBytes: 2 * 1024 * 1024))).isRight(), isTrue);
      expect((await registrar(params('t-2mib1', fotoBytes: 2 * 1024 * 1024 + 1))).isLeft(), isTrue);
    });
  });

  group('Acciones superpuestas (doble toque) con el disco de verdad', () {
    test(
      'dos «Enviar» a la vez con el mismo id: los dos ven el ticket guardado, uno solo en la DB '
      'y la foto sigue ahí',
      () async {
        // El almacén en memoria de los tests del PR no puede ver esta carrera: escribe y renombra el
        // mismo temporal `<id>.jpg.parcial` desde las dos llamadas.
        final causas = <String?>{};
        for (var i = 0; i < 40; i++) {
          final id = 't-doble-$i';
          final resultados = await Future.wait([registrar(params(id)), registrar(params(id))]);
          for (final r in resultados) {
            r.fold((f) => causas.add(f is FailureTicketNoGuardado ? f.causa : f.codigo), (_) {});
          }
          expect(await cuantosTickets(), i + 1, reason: 'un ticket por id, nunca dos ni cero');
          final foto = File('${carpeta.path}/tickets/$id.jpg');
          expect(foto.existsSync(), isTrue, reason: 'la foto del ticket registrado no se pierde');
        }
        expect(causas, isEmpty, reason: 'un doble toque no puede mostrar «No pudimos guardar»');
      },
      skip:
          'QA #426: dos registrar() a la vez con el mismo id escriben el mismo temporal '
          '`<id>.jpg.parcial`; el segundo rename falla y una de las dos llamadas devuelve '
          'FailureTicketNoGuardado aunque el ticket quedó guardado (40 de 40 corridas)',
    );

    test('control: con el almacén en memoria dos registrar() a la vez con el mismo id andan bien '
        '(la carrera es del archivo, no de la DB)', () async {
      final enMemoria = AlmacenDeFotosEnMemoria();
      final repoMemoria = TicketRepositoryImpl(
        TicketLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria()),
        enMemoria,
        logger: loggerMudo(),
        ahora: () => ahoraTicket,
      );
      final caso = RegistrarTicketUseCase(repoMemoria, ahora: () => ahoraTicket);

      final resultados = await Future.wait([caso(params('t-1')), caso(params('t-1'))]);

      expect(resultados.every((r) => r.isRight()), isTrue);
      expect(await cuantosTickets(), 1);
      expect(enMemoria.archivos.keys, ['/fotos/t-1.jpg']);
    });

    test('dos «Borrar copia local» a la vez: los dos terminan bien y no queda archivo', () async {
      final r = await registrar(params('t-1'));
      expect(r.isRight(), isTrue);
      await (db.update(
        db.tickets,
      )..where((t) => t.id.equals('t-1'))).write(const TicketsCompanion(syncVersion: Value(1)));
      expect((await repo.marcarFotoSubida('t-1', 'u/t-1.jpg')).isRight(), isTrue);

      final borrar = BorrarCopiaLocalDeTicketUseCase(repo);
      final resultados = await Future.wait([borrar('t-1'), borrar('t-1')]);

      expect(resultados.every((r) => r.isRight()), isTrue);
      expect(File('${carpeta.path}/tickets/t-1.jpg').existsSync(), isFalse);
      expect(await repo.bytesDeLaFoto('t-1'), const Right<Failure, dynamic>(null));
    });

    test('reentrada: registrar con el mismo id después de borrar la copia no deja un archivo '
        'huérfano ni vuelve a encolar', () async {
      await registrar(params('t-1'));
      await (db.update(
        db.tickets,
      )..where((t) => t.id.equals('t-1'))).write(const TicketsCompanion(syncVersion: Value(1)));
      await repo.marcarFotoSubida('t-1', 'u/t-1.jpg');
      await BorrarCopiaLocalDeTicketUseCase(repo)('t-1');

      final otra = await registrar(params('t-1'));

      expect(otra.getOrElse(() => throw StateError('falló')).yaEstaba, isTrue);
      expect(File('${carpeta.path}/tickets/t-1.jpg').existsSync(), isFalse);
    });
  });

  group('Cobro ya ligado a otro ticket (reentrada a «Sacar foto del ticket»)', () {
    test(
      'el aviso dice que ya tiene ticket y no que el cobro no existe',
      () async {
        await cobro('c-1');
        expect((await registrar(params('t-1', cobroId: 'c-1'))).isRight(), isTrue);

        // Ana sale de la pantalla antes de ver el éxito y vuelve a sacar la foto: la pantalla genera
        // otro id para el mismo cobro.
        final r = await registrar(params('t-2', cobroId: 'c-1'));

        final falla = r.fold((f) => f, (_) => null);
        expect(falla, isA<FailureTicketCobroInvalido>());
        expect(falla!.mensaje, isNot(contains('No encontramos')));
      },
      skip:
          'QA #426: FailureTicketCobroInvalido dice «No encontramos ese cobro» también cuando el '
          'cobro existe y ya tiene su ticket; no dice qué hacer',
    );

    test('la segunda carga no deja archivo ni fila de más', () async {
      await cobro('c-1');
      await registrar(params('t-1', cobroId: 'c-1'));
      await registrar(params('t-2', cobroId: 'c-1'));

      expect(await cuantosTickets(), 1);
      expect(File('${carpeta.path}/tickets/t-2.jpg').existsSync(), isFalse);
    });
  });
}
