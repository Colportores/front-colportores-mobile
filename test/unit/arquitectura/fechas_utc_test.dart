// Invariante transversal: toda entidad de dominio guarda sus `DateTime` en UTC.
//
// `DateTime.==` compara también el flag `isUtc`, pero `hashCode` no. Sin normalizar, la misma
// fila hidratada desde la DB local (`isUtc: false`) y desde el cloud (`DateTime.parse('…Z')`,
// `isUtc: true`) da **desigual con el mismo hashCode**: rompe `Set`/`Map` y le muestra al sync
// engine un cambio fantasma en cada pull. Estos tests fallan si alguna entidad deja de
// normalizar en su constructor.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/usuario_rol.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta.dart';
import 'package:test/test.dart';

void main() {
  // Local a propósito: es lo que devuelve la hidratación desde la DB local.
  final local = DateTime(2026, 9, 18, 10, 30);
  final utc = local.toUtc();

  Auditoria auditoriaCon(DateTime fecha) =>
      Auditoria(createdAt: fecha, updatedAt: fecha, deletedAt: fecha);

  group('Invariante de fechas en UTC', () {
    test('dado un DateTime local, cuando se construye una Auditoria, todas sus fechas quedan '
        'en UTC', () {
      final a = auditoriaCon(local);

      expect(a.createdAt.isUtc, isTrue);
      expect(a.updatedAt.isUtc, isTrue);
      expect(a.deletedAt!.isUtc, isTrue);
      expect(a.createdAt, equals(utc));
    });

    test('dado el mismo instante como local y como UTC, cuando se comparan dos Auditoria, son '
        'iguales y comparten hashCode (el sync engine no ve un cambio fantasma)', () {
      final desdeLocal = auditoriaCon(local);
      final desdeCloud = auditoriaCon(utc);

      expect(desdeLocal, equals(desdeCloud));
      expect(desdeLocal.hashCode, equals(desdeCloud.hashCode));
    });

    test('dado el mismo instante como local y como UTC, cuando se comparan dos Visita, son '
        'iguales y comparten hashCode', () {
      Visita construir(DateTime fecha) => Visita(
        id: 'vis-1',
        espacioPersonaId: 'ep-1',
        fecha: fecha,
        tipoResultado: TipoResultadoVisita.venta,
        colportorId: 'u-1',
        jornadaId: 'jor-1',
        auditoria: auditoriaCon(fecha),
      );

      expect(construir(local), equals(construir(utc)));
      expect(construir(local).hashCode, equals(construir(utc).hashCode));
      expect(construir(local).fecha.isUtc, isTrue);
    });

    test('dado un DateTime local, cuando se construye cualquier entidad con fecha, el campo '
        'queda en UTC', () {
      final auditoria = auditoriaCon(local);

      final campania = Campania(
        id: 'cam-1',
        nombre: 'Verano 2026',
        tipo: TipoCampania.verano,
        fechaInicio: local,
        fechaFin: local,
        ciudadId: 'ciu-1',
        auditoria: auditoria,
      );
      final usuarioRol = UsuarioRol(
        id: 'ur-1',
        usuarioId: 'u-1',
        rolId: 'rol-1',
        validoDesde: local,
        validoHasta: local,
        auditoria: auditoria,
      );
      final cobranza = Cobranza(
        id: 'cob-1',
        ventaId: 'venta-1',
        montoCentavos: 50000,
        medio: MedioCobranza.efectivo,
        fecha: local,
        numeroCuota: 1,
        auditoria: auditoria,
      );
      final jornada = Jornada(
        id: 'jor-1',
        colportorId: 'u-1',
        inicio: local,
        fin: local,
        auditoria: auditoria,
      );
      final venta = Venta(
        id: 'ven-1',
        espacioPersonaId: 'ep-1',
        numeroTalonario: 'T-001',
        montoTotalCentavos: 120000,
        fecha: local,
        colportorId: 'u-1',
        visitaId: 'vis-1',
        auditoria: auditoria,
      );
      final sesion = Sesion(
        usuarioId: 'u-1',
        email: 'colportor@example.com',
        accessToken: 'jwt',
        expiraEn: local,
      );

      expect(campania.fechaInicio.isUtc, isTrue);
      expect(campania.fechaFin.isUtc, isTrue);
      expect(usuarioRol.validoDesde.isUtc, isTrue);
      expect(usuarioRol.validoHasta!.isUtc, isTrue);
      expect(cobranza.fecha.isUtc, isTrue);
      expect(jornada.inicio.isUtc, isTrue);
      expect(jornada.fin!.isUtc, isTrue);
      expect(venta.fecha.isUtc, isTrue);
      expect(sesion.expiraEn.isUtc, isTrue);
    });

    test('dado que la fecha ya viene en UTC, cuando se normaliza, el instante no se corre', () {
      final a = auditoriaCon(utc);

      expect(a.createdAt, equals(utc));
      expect(a.createdAt.millisecondsSinceEpoch, equals(local.millisecondsSinceEpoch));
    });
  });
}
