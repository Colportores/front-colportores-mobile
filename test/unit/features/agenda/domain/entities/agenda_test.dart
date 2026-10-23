// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/motivo_rechazo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  Agenda construir({
    EstadoAgenda estado = EstadoAgenda.pendiente,
    DateTime? fecha,
    Auditoria? auditoriaPropia,
  }) => Agenda(
    id: 'age-1',
    espacioPersonaId: 'ep-1',
    tipo: TipoAgenda.entrevista,
    fechaProgramada: fecha ?? DateTime.utc(2026, 10, 25, 14),
    estado: estado,
    colportorId: 'u-1',
    auditoria: auditoriaPropia ?? auditoria,
  );

  group('Agenda', () {
    test('dado una agenda sin más datos, cuando se construye, queda pendiente, no estricta y sin '
        'visita', () {
      final agenda = construir();

      expect(agenda.estado, EstadoAgenda.pendiente);
      expect(agenda.esEstricta, isFalse);
      expect(agenda.visitaId, isNull);
      expect(agenda.slotCodigo, isNull);
      expect(agenda.ubicacionAltId, isNull);
    });

    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      expect(construir(), equals(construir()));
      expect(construir().hashCode, equals(construir().hashCode));
    });

    test('dado que el estado difiere, cuando se comparan, no son iguales', () {
      expect(construir(), isNot(equals(construir(estado: EstadoAgenda.cancelada))));
    });

    test('dado una fecha local y la misma en UTC, cuando se comparan, son iguales y la fecha '
        'queda en UTC al milisegundo', () {
      final local = DateTime(2026, 10, 25, 14, 0, 0, 123, 999);
      final utc = local.toUtc();

      final a = construir(fecha: local);

      expect(a.fechaProgramada.isUtc, isTrue);
      expect(a.fechaProgramada.microsecond, 0);
      expect(a, equals(construir(fecha: utc)));
    });

    test('dado el estado, cuando se consulta estaPendiente, solo lo es la agenda pendiente y sin '
        'baja', () {
      expect(construir().estaPendiente, isTrue);
      expect(construir(estado: EstadoAgenda.completada).estaPendiente, isFalse);
      expect(construir(estado: EstadoAgenda.cancelada).estaPendiente, isFalse);
      expect(
        construir(
          auditoriaPropia: Auditoria(
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            deletedAt: DateTime(2026, 1, 2),
          ),
        ).estaPendiente,
        isFalse,
      );
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final agenda = construir(
        auditoriaPropia: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(agenda.estaBorrada, isTrue);
    });
  });

  group('TipoAgenda y EstadoAgenda', () {
    test('dado el catálogo del servidor, cuando se listan, cada valor lleva el código de la '
        'columna', () {
      expect(
        {for (final t in TipoAgenda.values) t: t.codigo},
        {TipoAgenda.entrevista: 'ENTREVISTA', TipoAgenda.cobranza: 'COBRANZA'},
      );
      expect(
        {for (final e in EstadoAgenda.values) e: e.codigo},
        {
          EstadoAgenda.pendiente: 'PENDIENTE',
          EstadoAgenda.completada: 'COMPLETADA',
          EstadoAgenda.cancelada: 'CANCELADA',
        },
      );
    });

    test('dado el código de cada valor, cuando se lee de vuelta, es el mismo valor', () {
      for (final t in TipoAgenda.values) {
        expect(TipoAgenda.desdeCodigo(t.codigo), t);
      }
      for (final e in EstadoAgenda.values) {
        expect(EstadoAgenda.desdeCodigo(e.codigo), e);
      }
    });

    test('dado un código que el servidor no tiene, cuando se lee, lanza ArgumentError', () {
      expect(() => TipoAgenda.desdeCodigo('VENTA'), throwsArgumentError);
      expect(() => EstadoAgenda.desdeCodigo('NO_CUMPLIDA'), throwsArgumentError);
    });

    test(
      'dado el estado, cuando se consulta estaCerrada, solo lo está lo cumplido o cancelado',
      () {
        expect(EstadoAgenda.pendiente.estaCerrada, isFalse);
        expect(EstadoAgenda.completada.estaCerrada, isTrue);
        expect(EstadoAgenda.cancelada.estaCerrada, isTrue);
      },
    );
  });

  group('NotaDeCampo y MotivoRechazoAgenda', () {
    test('dado una nota, cuando se interpola, el texto no aparece', () {
      final nota = NotaDeCampo(id: 'n-1', texto: 'el perro es bravo', auditoria: auditoria);

      expect('$nota', isNot(contains('perro')));
      expect(
        nota,
        equals(NotaDeCampo(id: 'n-1', texto: 'el perro es bravo', auditoria: auditoria)),
      );
    });

    test('dado cada motivo de rechazo, cuando se lee, dice a qué campo va y guía a la persona', () {
      for (final motivo in MotivoRechazoAgenda.values) {
        expect(motivo.campo, anyOf('persona', 'agenda'));
        expect(motivo.mensaje, endsWith('.'));
      }
    });
  });
}
