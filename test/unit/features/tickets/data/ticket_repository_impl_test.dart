// El repositorio de tickets (HU-COB-007, #426): la DB real en memoria y el almacén de fotos en memoria.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/tickets/data/datasources/ticket_local_data_source_drift.dart';
import 'package:colportores_mobile/features/tickets/data/models/ticket_model.dart';
import 'package:colportores_mobile/features/tickets/data/repositories/ticket_repository_impl.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/tickets_falsos.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late AlmacenDeFotosEnMemoria almacen;
  late TicketRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    almacen = AlmacenDeFotosEnMemoria();
    repo = TicketRepositoryImpl(
      TicketLocalDataSourceDrift(db, encolador: encolador),
      almacen,
      logger: loggerMudo(),
      ahora: () => ahoraTicket.add(const Duration(minutes: 1)),
    );
  });
  tearDown(() => db.close());

  Future<Either2> registrar(String id, {String? cobroId}) async {
    final r = await repo.registrar(
      ticketDePrueba(id),
      foto: fotoDePrueba(),
      tipoDeImagen: TipoDeImagen.jpeg,
      cobroId: cobroId,
    );
    return r.fold(Either2.conFalla, Either2.conOk);
  }

  Future<void> servidorAcepto(String id) => (db.update(
    db.tickets,
  )..where((t) => t.id.equals(id))).write(const TicketsCompanion(syncVersion: Value(1)));

  group('registrar', () {
    test('guarda el archivo en el almacén y la ruta en la copia local', () async {
      final r = await registrar('t-1');

      expect(r.ok, isNotNull);
      expect(almacen.archivos.keys, ['/fotos/t-1.jpg']);
      expect(almacen.archivos['/fotos/t-1.jpg'], fotoDePrueba());
      final foto = await db.select(db.ticketFotosLocales).getSingle();
      expect(foto.rutaLocal, '/fotos/t-1.jpg');
      expect(foto.bytes, 1000);
    });

    test('si no se puede guardar el archivo, falla sin tocar la DB ni encolar', () async {
      almacen.fallarAlGuardarCon = StateError('disco lleno');

      final r = await registrar('t-1');

      expect(r.falla, isA<FailureTicketNoGuardado>());
      expect(await db.select(db.tickets).get(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });

    test('si falla la transacción, borra el archivo que había escrito', () async {
      encolador.fallarCon = StateError('sin motor');

      final r = await registrar('t-1');

      expect(r.falla, isA<FailureTicketNoGuardado>());
      expect(almacen.archivos, isEmpty);
      expect(await db.select(db.ticketFotosLocales).get(), isEmpty);
    });

    test('la falla no lleva el texto de la excepción, solo su tipo', () async {
      encolador.fallarCon = StateError('dato del cliente');

      final r = await registrar('t-1');

      expect((r.falla! as FailureTicketNoGuardado).causa, 'StateError');
      expect(r.falla!.mensaje, isNot(contains('cliente')));
    });

    test('un cobro inválido es FailureTicketCobroInvalido y no deja archivo', () async {
      final r = await registrar('t-1', cobroId: 'no-existe');

      expect(r.falla, isA<FailureTicketCobroInvalido>());
      expect(almacen.archivos, isEmpty);
    });

    test('con el mismo id otra vez devuelve lo que estaba y no deja un archivo de más', () async {
      await registrar('t-1');
      final otra = await repo.registrar(
        ticketDePrueba('t-1'),
        foto: fotoDePrueba(),
        tipoDeImagen: TipoDeImagen.jpeg,
      );

      expect(otra.getOrElse(() => throw StateError('')).yaEstaba, isTrue);
      expect(almacen.archivos.keys, ['/fotos/t-1.jpg']);
      expect(encolador.encolados, hasLength(1));
    });
  });

  group('subida de la foto', () {
    test('fotosPorSubir espera a que el servidor acepte la fila; después, bytesDeLaFoto lee el '
        'archivo', () async {
      await registrar('t-1');
      expect((await repo.fotosPorSubir()).getOrElse(() => []), isEmpty);

      await servidorAcepto('t-1');
      final lista = (await repo.fotosPorSubir()).getOrElse(() => []);

      expect(lista.map((f) => f.ticket.id), ['t-1']);
      expect((await repo.bytesDeLaFoto('t-1')).getOrElse(() => null), fotoDePrueba());
    });

    test('bytesDeLaFoto de un ticket sin copia o sin archivo es null, no una falla', () async {
      expect((await repo.bytesDeLaFoto('no-existe')).getOrElse(() => fotoDePrueba()), isNull);
      await registrar('t-1');
      almacen.archivos.clear();

      expect((await repo.bytesDeLaFoto('t-1')).getOrElse(() => fotoDePrueba()), isNull);
    });

    test(
      'marcarFotoSubida guarda la ruta con el reloj del repositorio y encola un update',
      () async {
        await registrar('t-1');
        await servidorAcepto('t-1');

        final t = (await repo.marcarFotoSubida(
          't-1',
          'u/t-1.jpg',
        )).getOrElse(() => throw StateError(''));

        expect(t.urlCloud, 'u/t-1.jpg');
        expect(t.auditoria.updatedAt, ahoraTicket.add(const Duration(minutes: 1)));
        expect(encolador.encolados.last.payload['url_cloud'], 'u/t-1.jpg');
      },
    );

    test('marcarFotoSubida de un ticket que no existe es FailureTicketNoEncontrado', () async {
      final r = await repo.marcarFotoSubida('no-existe', 'u/x.jpg');

      expect(r.swap().toOption().toNullable(), isA<FailureTicketNoEncontrado>());
    });

    test('anotarIntentoFallido de un ticket que no existe es FailureTicketNoEncontrado', () async {
      final r = await repo.anotarIntentoFallido('no-existe', codigo: 'red', definitivo: false);

      expect(r.swap().toOption().toNullable(), isA<FailureTicketNoEncontrado>());
    });
  });

  group('borrarCopiaLocal', () {
    test('con la foto subida borra el archivo y deja la nube intacta', () async {
      await registrar('t-1');
      await servidorAcepto('t-1');
      await repo.marcarFotoSubida('t-1', 'u/t-1.jpg');

      final r = await repo.borrarCopiaLocal('t-1');

      expect(r.isRight(), isTrue);
      expect(almacen.archivos, isEmpty);
      expect((await db.select(db.tickets).getSingle()).urlCloud, 'u/t-1.jpg');
      expect((await db.select(db.ticketFotosLocales).getSingle()).rutaLocal, isNull);
    });

    test('con la foto sin subir NO borra el archivo: perdería el ticket', () async {
      await registrar('t-1');

      final r = await repo.borrarCopiaLocal('t-1');

      expect(r.swap().toOption().toNullable(), isA<FailureTicketCopiaSinSubir>());
      expect(almacen.archivos.keys, ['/fotos/t-1.jpg']);
    });

    test('si el archivo no se puede borrar, la copia igual queda soltada y no falla', () async {
      await registrar('t-1');
      await servidorAcepto('t-1');
      await repo.marcarFotoSubida('t-1', 'u/t-1.jpg');
      almacen.fallarAlBorrarCon = StateError('bloqueado');

      final r = await repo.borrarCopiaLocal('t-1');

      expect(r.isRight(), isTrue);
      expect((await db.select(db.ticketFotosLocales).getSingle()).rutaLocal, isNull);
    });

    test('un ticket que no existe es FailureTicketNoEncontrado', () async {
      final r = await repo.borrarCopiaLocal('no-existe');

      expect(r.swap().toOption().toNullable(), isA<FailureTicketNoEncontrado>());
    });
  });

  group('observarTicket', () {
    test('devuelve el ticket guardado con su copia local y null si no existe', () async {
      await registrar('t-1');

      final r = (await repo.observarTicket('t-1').first)!;

      expect(r.ticket.id, 't-1');
      expect(r.foto.estado, EstadoDeSubida.pendiente);
      expect(r.foto.hayCopiaLocal, isTrue);
      expect(r.yaEstaba, isFalse);
      expect(await repo.observarTicket('no-existe').first, isNull);
    });
  });

  group('TicketModel', () {
    test('los códigos de ida y vuelta, y un estado desconocido se lee como pendiente', () {
      for (final t in TipoDeTicket.values) {
        expect(TicketModel.tipoDesdeCodigo(TicketModel.codigoDelTipo(t)), t);
      }
      for (final t in TipoDeTarjeta.values) {
        expect(TicketModel.tarjetaDesdeCodigo(TicketModel.codigoDeLaTarjeta(t)), t);
      }
      for (final e in EstadoDeTicket.values) {
        expect(TicketModel.estadoDesdeCodigo(TicketModel.codigoDelEstado(e)), e);
      }
      for (final e in EstadoDeSubida.values) {
        expect(TicketModel.subidaDesdeCodigo(TicketModel.codigoDeLaSubida(e)), e);
      }
      expect(TicketModel.estadoDesdeCodigo('RARO'), EstadoDeTicket.pendiente);
      expect(TicketModel.tarjetaDesdeCodigo('RARA'), isNull);
      expect(TicketModel.tarjetaDesdeCodigo(null), isNull);
      expect(() => TicketModel.tipoDesdeCodigo('RARO'), throwsArgumentError);
    });

    test('toJson usa las fechas en ISO-8601 UTC y el dinero en centavos', () {
      final json = TicketModel.toJson(ticketDePrueba('t-1', urlCloud: 'u/t-1.jpg'));

      expect(json['fecha'], '2026-10-30T15:00:07.321Z');
      expect(json['monto'], 150000);
      expect(json['url_cloud'], 'u/t-1.jpg');
      expect(json['tarjeta_tipo'], 'CREDITO');
    });
  });
}

/// Un `Either` aplanado para que los tests lean mejor.
final class Either2 {
  Either2.conOk(this.ok) : falla = null;
  Either2.conFalla(this.falla) : ok = null;

  final TicketRegistrado? ok;
  final Failure? falla;
}
