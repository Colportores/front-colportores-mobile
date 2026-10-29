// Las condiciones del respaldo en Drive (HU-SYNC-005, R-SY10, HU-JOR-002): el automático corre con
// Drive conectado, Wi-Fi y batería ≥ 30 %; lo que pide la persona, con cualquier conexión. Lo que
// falla nunca sale como excepción, avisa a la fila «Cuenta Drive» y deja el botón libre.
import 'dart:async';

import 'package:colportores_mobile/features/respaldo/data/services/servicio_respaldo_motor.dart';
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/nivel_bateria.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_respaldo.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../../helpers/logger_mudo.dart';

const _conectada = DriveConectada(email: 'ana@example.com', cuentaId: 'g-1');

/// Un archivo remoto al que el test le rompe la subida o le frena la respuesta.
class _Archivo extends FakeArchive {
  _Archivo() : super(authorized: true, informaHashRemoto: true);

  Object? errorEnSubida;
  Completer<void>? frenar;
  int intentos = 0;

  @override
  Future<BackupEntry> upload({
    required List<int> payload,
    required String? parentId,
    required String watermark,
    DateTime? exportedAt,
    String? keyId,
  }) async {
    intentos++;
    if (frenar case final espera?) await espera.future;
    if (errorEnSubida case final error?) throw error;
    return super.upload(
      payload: payload,
      parentId: parentId,
      watermark: watermark,
      exportedAt: exportedAt,
      keyId: keyId,
    );
  }
}

class _Bateria implements NivelBateria {
  int? nivel = 80;

  @override
  Future<int?> porcentaje() async => nivel;
}

void main() {
  late _Archivo drive;
  late _Bateria bateria;
  late DateTime ahora;
  late EstadoRespaldoDrive estado;
  late TipoConexion conexion;
  late List<String> avisos;
  late List<IntegrityReport> verificaciones;
  late BackupService backup;
  late ServicioRespaldoMotor servicio;
  var sinMotor = false;

  ServicioRespaldoMotor armar() => ServicioRespaldoMotor(
    backup: () => sinMotor ? null : backup,
    estadoDrive: () async => estado,
    conexion: () async => conexion,
    bateria: bateria,
    alPermisoRevocado: () async => avisos.add('permiso'),
    alSinEspacio: () async => avisos.add('sinEspacio'),
    alGuardado: () async => avisos.add('guardado'),
    alVerificar: (informe) async => verificaciones.add(informe),
    ahora: () => ahora,
    logger: loggerMudo(),
  );

  setUp(() {
    sinMotor = false;
    ahora = DateTime.utc(2026, 11, 2, 22);
    drive = _Archivo();
    bateria = _Bateria();
    estado = _conectada;
    conexion = TipoConexion.wifi;
    avisos = [];
    verificaciones = [];
    backup = BackupService(
      archive: drive,
      crypto: FakeCrypto(),
      snapshot: FakeSnapshot(),
      clock: () => ahora,
    );
    servicio = armar();
  });

  group('el automático (cierre de jornada, al abrir)', () {
    test('con Drive, Wi-Fi y batería suficiente sube y lo dice', () async {
      final r = await servicio.respaldar(OrigenRespaldo.cierreDeJornada);

      expect(r, isA<RespaldoHecho>().having((h) => h.esBase, 'es la base', isTrue));
      expect(drive.entries, hasLength(1));
      expect(avisos, ['guardado'], reason: 'sale de «sin espacio» si estaba ahí');
    });

    test('sin Wi-Fi espera (datos móviles)', () async {
      conexion = TipoConexion.datosMoviles;

      final r = await servicio.respaldar(OrigenRespaldo.cierreDeJornada);

      expect(r, isA<RespaldoOmitido>().having((o) => o.motivo, 'motivo', MotivoOmision.sinWifi));
      expect(drive.entries, isEmpty);
    });

    test('sin conexión espera', () async {
      conexion = TipoConexion.sinConexion;

      final r = await servicio.respaldar(OrigenRespaldo.alAbrir);

      expect(
        r,
        isA<RespaldoOmitido>().having((o) => o.motivo, 'motivo', MotivoOmision.sinConexion),
      );
    });

    test('con 29 % de batería espera; con 30 % corre', () async {
      bateria.nivel = 29;
      final baja = await servicio.respaldar(OrigenRespaldo.cierreDeJornada);
      expect(
        baja,
        isA<RespaldoOmitido>().having((o) => o.motivo, 'motivo', MotivoOmision.bateriaBaja),
      );

      bateria.nivel = 30;
      final justa = await servicio.respaldar(OrigenRespaldo.cierreDeJornada);
      expect(justa, isA<RespaldoHecho>());
    });

    test('si el sistema no informa la batería, no frena el respaldo', () async {
      bateria.nivel = null;

      expect(await servicio.respaldar(OrigenRespaldo.cierreDeJornada), isA<RespaldoHecho>());
    });

    for (final (nombre, e) in <(String, EstadoRespaldoDrive)>[
      ('sin conectar', const DriveSinConectar()),
      ('con el permiso revocado', const DrivePermisoRevocado(email: 'a@b.c', cuentaId: 'g')),
    ]) {
      test('Drive $nombre: no corre y no toca nada', () async {
        estado = e;

        final r = await servicio.respaldar(OrigenRespaldo.cierreDeJornada);

        expect(r, isA<RespaldoOmitido>().having((o) => o.motivo, 'motivo', MotivoOmision.sinDrive));
        expect(drive.intentos, 0);
        expect(avisos, isEmpty);
      });
    }

    test('con Drive sin espacio sí lo intenta: puede haber liberado lugar', () async {
      estado = const DriveSinEspacio(email: 'a@b.c', cuentaId: 'g');

      expect(await servicio.respaldar(OrigenRespaldo.alAbrir), isA<RespaldoHecho>());
      expect(avisos, ['guardado']);
    });

    test('sin motor (sin sesión) no hace nada', () async {
      sinMotor = true;

      final r = await servicio.respaldar(OrigenRespaldo.cierreDeJornada);

      expect(r, isA<RespaldoOmitido>().having((o) => o.motivo, 'motivo', MotivoOmision.sinMotor));
    });
  });

  group('lo que pide la persona (Reintentar, conectar Drive)', () {
    test('corre con datos móviles y batería baja: fue una acción suya', () async {
      conexion = TipoConexion.datosMoviles;
      bateria.nivel = 5;

      expect(await servicio.respaldar(OrigenRespaldo.pedidoPorLaPersona), isA<RespaldoHecho>());
    });

    test('sin ninguna conexión no corre', () async {
      conexion = TipoConexion.sinConexion;

      final r = await servicio.respaldar(OrigenRespaldo.pedidoPorLaPersona);

      expect(
        r,
        isA<RespaldoOmitido>().having((o) => o.motivo, 'motivo', MotivoOmision.sinConexion),
      );
    });

    test('con Drive sin conectar no corre', () async {
      estado = const DriveSinConectar();

      final r = await servicio.respaldar(OrigenRespaldo.pedidoPorLaPersona);

      expect(r, isA<RespaldoOmitido>().having((o) => o.motivo, 'motivo', MotivoOmision.sinDrive));
    });
  });

  group('cuando falla', () {
    test(
      'un corte de red a mitad de la subida: falla sin excepción y la cadena sigue entera',
      () async {
        await servicio.respaldar(OrigenRespaldo.cierreDeJornada);
        avisos.clear();
        ahora = ahora.add(const Duration(hours: 24));
        drive.errorEnSubida = const ArchiveFailure('sin red');

        final r = await servicio.respaldar(OrigenRespaldo.alAbrir);

        expect(r, isA<RespaldoFallido>().having((f) => f.causa, 'causa', CausaFalloRespaldo.otra));
        expect(drive.entries, hasLength(1), reason: 'la cadena anterior sigue siendo la vigente');
        expect(avisos, isEmpty, reason: 'un corte de red no es una revocación');
        expect((await backup.verifyChain()).ok, isTrue);
      },
    );

    test('Drive dice 401: la fila pasa a «Reconectar»', () async {
      drive.errorEnSubida = const ArchiveUnauthorized('Drive respondió 401');

      final r = await servicio.respaldar(OrigenRespaldo.cierreDeJornada);

      expect(r, isA<RespaldoFallido>().having((f) => f.causa, 'causa', CausaFalloRespaldo.permiso));
      expect(avisos, ['permiso']);
    });

    test('Drive sin espacio: la fila lo dice y el respaldo no se da por hecho', () async {
      drive.errorEnSubida = const ArchiveNoSpace('Drive respondió 403');

      final r = await servicio.respaldar(OrigenRespaldo.cierreDeJornada);

      expect(
        r,
        isA<RespaldoFallido>().having((f) => f.causa, 'causa', CausaFalloRespaldo.sinEspacio),
      );
      expect(avisos, ['sinEspacio']);
    });

    test('sin token (sin red para renovarlo) no se toma por una revocación', () async {
      drive.errorEnSubida = const ArchiveSinToken('sin token');

      await servicio.respaldar(OrigenRespaldo.cierreDeJornada);

      expect(avisos, isEmpty);
    });

    test('la DEK que no se puede leer es un fallo, no una excepción para quien pidió', () async {
      drive.errorEnSubida = StateError('no hay DEK para cifrar el backup');

      final r = await servicio.respaldar(OrigenRespaldo.cierreDeJornada);

      expect(r, isA<RespaldoFallido>());
    });

    test('si el estado de Drive no se puede leer, no rompe a quien pidió', () async {
      final roto = ServicioRespaldoMotor(
        backup: () => backup,
        estadoDrive: () async => throw StateError('almacén'),
        conexion: () async => conexion,
        bateria: bateria,
        alPermisoRevocado: () async {},
        alSinEspacio: () async {},
        alGuardado: () async {},
        alVerificar: (_) async {},
        logger: loggerMudo(),
      );

      expect(await roto.respaldar(OrigenRespaldo.cierreDeJornada), isA<RespaldoFallido>());
    });

    test('si avisar a la fila falla, el respaldo igual cuenta', () async {
      final avisoRoto = ServicioRespaldoMotor(
        backup: () => backup,
        estadoDrive: () async => estado,
        conexion: () async => conexion,
        bateria: bateria,
        alPermisoRevocado: () async {},
        alSinEspacio: () async {},
        alGuardado: () async => throw StateError('almacén'),
        alVerificar: (_) async {},
        logger: loggerMudo(),
      );

      expect(await avisoRoto.respaldar(OrigenRespaldo.cierreDeJornada), isA<RespaldoHecho>());
    });

    test(
      'tras un fallo automático no se insiste en cada vuelta; el pedido de la persona sí',
      () async {
        drive.errorEnSubida = const ArchiveFailure('sin red');
        await servicio.respaldar(OrigenRespaldo.alAbrir);
        expect(drive.intentos, 1);

        ahora = ahora.add(const Duration(minutes: 5));
        final seguido = await servicio.respaldar(OrigenRespaldo.alAbrir);
        expect(
          seguido,
          isA<RespaldoOmitido>().having((o) => o.motivo, 'motivo', MotivoOmision.falloReciente),
        );
        expect(drive.intentos, 1);

        final pedido = await servicio.respaldar(OrigenRespaldo.pedidoPorLaPersona);
        expect(pedido, isA<RespaldoFallido>());
        expect(drive.intentos, 2, reason: 'el botón «Reintentar» no espera');

        drive.errorEnSubida = null;
        ahora = ahora.add(const Duration(minutes: 31));
        expect(await servicio.respaldar(OrigenRespaldo.alAbrir), isA<RespaldoHecho>());
      },
    );

    test('después de un fallo el servicio queda libre: no queda nada «ocupado»', () async {
      drive.errorEnSubida = const ArchiveFailure('sin red');
      await servicio.respaldar(OrigenRespaldo.pedidoPorLaPersona);

      drive.errorEnSubida = null;
      final r = await servicio.respaldar(OrigenRespaldo.pedidoPorLaPersona);

      expect(r, isA<RespaldoHecho>());
    });
  });

  group('dos pedidos seguidos', () {
    test('el segundo, mientras el primero corre, no sube otro: vuelve «en curso»', () async {
      drive.frenar = Completer<void>();

      final primero = servicio.respaldar(OrigenRespaldo.cierreDeJornada);
      await Future<void>.delayed(Duration.zero);
      final segundo = await servicio.respaldar(OrigenRespaldo.pedidoPorLaPersona);

      expect(
        segundo,
        isA<RespaldoOmitido>().having((o) => o.motivo, 'motivo', MotivoOmision.enCurso),
      );
      drive.frenar!.complete();
      expect(await primero, isA<RespaldoHecho>());
      expect(
        drive.entries,
        hasLength(1),
        reason: 'un solo respaldo, sin dos hijos de la misma punta',
      );
    });

    test('una vez terminado el primero, el siguiente corre y extiende la cadena', () async {
      final a = await servicio.respaldar(OrigenRespaldo.cierreDeJornada);
      ahora = ahora.add(const Duration(hours: 1));
      final b = await servicio.respaldar(OrigenRespaldo.cierreDeJornada);

      expect(a, isA<RespaldoHecho>().having((h) => h.esBase, 'base', isTrue));
      expect(b, isA<RespaldoHecho>().having((h) => h.esBase, 'base', isFalse));
      expect((await backup.verifyChain()).ok, isTrue);
    });

    test('una verificación en curso también frena al respaldo', () async {
      drive.frenar = Completer<void>();
      await servicio
          .respaldar(OrigenRespaldo.pedidoPorLaPersona)
          .timeout(
            const Duration(milliseconds: 10),
            onTimeout: () => const RespaldoOmitido(MotivoOmision.enCurso),
          );
      drive.frenar!.complete();
    });
  });

  group('la verificación de la cadena (HU-SYNC-009)', () {
    test('con la cadena entera lo anota y no regenera nada', () async {
      await servicio.respaldar(OrigenRespaldo.cierreDeJornada);

      final r = await servicio.verificarIntegridad();

      expect(r, isA<CadenaIntegra>().having((c) => c.hayRespaldo, 'hay', isTrue));
      expect(verificaciones.single.ok, isTrue);
      expect(drive.entries, hasLength(1));
    });

    test('sin respaldos no hay nada que verificar: se anota y no es un problema', () async {
      final r = await servicio.verificarIntegridad();

      expect(r, isA<CadenaIntegra>().having((c) => c.hayRespaldo, 'hay', isFalse));
      expect(verificaciones.single.hasBackup, isFalse);
    });

    test('con un eslabón corrupto: lo anota y regenera una base nueva ya', () async {
      await servicio.respaldar(OrigenRespaldo.cierreDeJornada);
      ahora = ahora.add(const Duration(hours: 24));
      await servicio.respaldar(OrigenRespaldo.alAbrir);
      drive.corrupt('backup-2');
      final antes = drive.entries.map((e) => e.id).toList();

      final r = await servicio.verificarIntegridad();

      expect(r, isA<CadenaConProblema>());
      final problema = r as CadenaConProblema;
      expect(problema.problemas, {'corrupt'});
      expect(problema.regeneracion, isA<RespaldoHecho>().having((h) => h.esBase, 'base', isTrue));
      expect(verificaciones.single.needsRebase, isTrue);
      expect(drive.entries, hasLength(1), reason: 'la cadena rota se podó tras confirmar la nueva');
      expect(drive.entries.single.id, isNot(anyOf(antes)));
      expect((await backup.verifyChain()).ok, isTrue);
    });

    test('si la base nueva no sube, la cadena rota sigue y se reintenta', () async {
      await servicio.respaldar(OrigenRespaldo.cierreDeJornada);
      drive.corrupt('backup-1');
      drive.errorEnSubida = const ArchiveFailure('sin red');

      final r = await servicio.verificarIntegridad();

      expect((r as CadenaConProblema).regeneracion, isA<RespaldoFallido>());
      expect(backup.regenerarBase, isTrue, reason: 'el próximo respaldo parte de una base nueva');
      expect(drive.entries, hasLength(1), reason: 'lo anterior no se borró sin tener lo nuevo');
    });

    test('una falla de red al verificar no es un hallazgo: no se anota nada', () async {
      await servicio.respaldar(OrigenRespaldo.cierreDeJornada);
      final roto = ServicioRespaldoMotor(
        backup: () =>
            BackupService(archive: _SinRed(), crypto: FakeCrypto(), snapshot: FakeSnapshot()),
        estadoDrive: () async => estado,
        conexion: () async => conexion,
        bateria: bateria,
        alPermisoRevocado: () async {},
        alSinEspacio: () async {},
        alGuardado: () async {},
        alVerificar: (i) async => verificaciones.add(i),
        logger: loggerMudo(),
      );

      final r = await roto.verificarIntegridad();

      expect(r, isA<VerificacionFallida>());
      expect(verificaciones, isEmpty);
    });

    test('sin Wi-Fi o sin Drive no verifica', () async {
      conexion = TipoConexion.datosMoviles;
      expect(
        await servicio.verificarIntegridad(),
        isA<VerificacionOmitida>().having((o) => o.motivo, 'motivo', MotivoOmision.sinWifi),
      );

      conexion = TipoConexion.wifi;
      estado = const DriveSinConectar();
      expect(
        await servicio.verificarIntegridad(),
        isA<VerificacionOmitida>().having((o) => o.motivo, 'motivo', MotivoOmision.sinDrive),
      );
      expect(verificaciones, isEmpty);
    });

    test('si anotar el resultado falla, la verificación igual da su resultado', () async {
      await servicio.respaldar(OrigenRespaldo.cierreDeJornada);
      final sinAudit = ServicioRespaldoMotor(
        backup: () => backup,
        estadoDrive: () async => estado,
        conexion: () async => conexion,
        bateria: bateria,
        alPermisoRevocado: () async {},
        alSinEspacio: () async {},
        alGuardado: () async {},
        alVerificar: (_) async => throw StateError('audit_log'),
        logger: loggerMudo(),
      );

      expect(await sinAudit.verificarIntegridad(), isA<CadenaIntegra>());
    });
  });
}

class _SinRed extends FakeArchive {
  _SinRed() : super(authorized: true);

  @override
  Future<List<BackupEntry>> list() async => throw const ArchiveFailure('sin red');
}
