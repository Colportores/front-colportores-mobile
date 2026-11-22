// HU-NOT-002 — las piezas de dominio del recordatorio de una visita: la anticipación, el texto (sin
// el nombre del cliente), el payload y la entidad.
import 'package:colportores_mobile/features/agenda/domain/entities/anticipacion_recordatorio.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/agenda/domain/services/texto_recordatorio.dart';
import 'package:test/test.dart';

void main() {
  group('AnticipacionRecordatorio', () {
    test('dado que nadie la cambió, cuando se pide la de siempre, son 30 minutos', () {
      expect(AnticipacionRecordatorio.porDefecto, 30);
    });

    test('dado un valor dentro del rango (5 a 120), cuando se acota, queda igual', () {
      for (final minutos in [5, 6, 30, 60, 119, 120]) {
        expect(AnticipacionRecordatorio.acotar(minutos), minutos);
      }
    });

    test('dado un valor fuera del rango, cuando se acota, va al extremo más cercano', () {
      expect(AnticipacionRecordatorio.acotar(4), 5);
      expect(AnticipacionRecordatorio.acotar(0), 5);
      expect(AnticipacionRecordatorio.acotar(-30), 5);
      expect(AnticipacionRecordatorio.acotar(121), 120);
      expect(AnticipacionRecordatorio.acotar(100000), 120);
    });

    test(
      'dado AnticipacionFija, cuando se pregunta, devuelve siempre su valor (30 por defecto)',
      () async {
        expect(await const AnticipacionFija().minutos(), 30);
        expect(await const AnticipacionFija(45).minutos(), 45);
      },
    );
  });

  group('TextoRecordatorio', () {
    final catorce = DateTime(2026, 10, 27, 14);

    test(
      'dado una entrevista a las 14:00, cuando se arma el cuerpo, es el texto literal de la HU',
      () {
        expect(
          TextoRecordatorio.cuerpo(
            tipo: TipoAgenda.entrevista,
            direccion: 'Av. Italia 1234',
            fechaProgramada: catorce.toUtc(),
          ),
          'Entrevista en Av. Italia 1234 a las 14:00',
        );
      },
    );

    test(
      'dado una cobranza, cuando se arma el cuerpo, dice «Cobranza» y la hora con dos cifras',
      () {
        expect(
          TextoRecordatorio.cuerpo(
            tipo: TipoAgenda.cobranza,
            direccion: 'Mataojo 2044',
            fechaProgramada: DateTime(2026, 10, 27, 9, 5).toUtc(),
          ),
          'Cobranza en Mataojo 2044 a las 09:05',
        );
      },
    );

    test(
      'dado una dirección con saltos de línea y espacios repetidos, cuando se arma, queda en una línea',
      () {
        expect(
          TextoRecordatorio.cuerpo(
            tipo: TipoAgenda.entrevista,
            direccion: '  Av.  Italia\n1234 \t Depto 3B  ',
            fechaProgramada: catorce.toUtc(),
          ),
          'Entrevista en Av. Italia 1234 Depto 3B a las 14:00',
        );
      },
    );

    test('dado que no hay dirección, cuando se arma, sale sin «en …»', () {
      for (final vacia in ['', '   ', '\n']) {
        expect(
          TextoRecordatorio.cuerpo(
            tipo: TipoAgenda.entrevista,
            direccion: vacia,
            fechaProgramada: catorce.toUtc(),
          ),
          'Entrevista a las 14:00',
        );
      }
    });

    test(
      'dado una dirección larguísima, cuando se arma, no se corta (el sistema la despliega)',
      () {
        final larga = 'Calle ${'Muy Larga ' * 40}1234';
        final cuerpo = TextoRecordatorio.cuerpo(
          tipo: TipoAgenda.entrevista,
          direccion: larga,
          fechaProgramada: catorce.toUtc(),
        );
        expect(cuerpo, contains(larga.trim()));
      },
    );

    test('dado un id de agenda, cuando se arma el payload y se lee de vuelta, es el mismo id', () {
      const id = '0192f3a0-7b1c-7cde-9f01-aaaaaaaaaaaa';
      expect(TextoRecordatorio.payloadDe(id), 'agenda:$id');
      expect(TextoRecordatorio.agendaDelPayload(TextoRecordatorio.payloadDe(id)), id);
    });

    test('dado un payload ajeno, vacío o sin id, cuando se lee, no es de una agenda', () {
      expect(TextoRecordatorio.agendaDelPayload(null), isNull);
      expect(TextoRecordatorio.agendaDelPayload(''), isNull);
      expect(TextoRecordatorio.agendaDelPayload('agenda:'), isNull);
      expect(TextoRecordatorio.agendaDelPayload('pedido:123'), isNull);
    });
  });

  group('RecordatorioDeVisita', () {
    test(
      'dado la misma hora como local y como UTC, cuando se comparan, son iguales y quedan en UTC',
      () {
        final local = DateTime(2026, 10, 27, 14, 0, 0, 123, 456);
        RecordatorioDeVisita con(DateTime f) => RecordatorioDeVisita(
          agendaId: 'ag-1',
          tipo: TipoAgenda.entrevista,
          direccion: 'Av. Italia 1234',
          fechaProgramada: f,
        );

        expect(con(local), con(local.toUtc()));
        expect(con(local).hashCode, con(local.toUtc()).hashCode);
        expect(con(local).fechaProgramada.isUtc, isTrue);
        expect(con(local).fechaProgramada.microsecond, 0);
      },
    );
  });
}
