// QA del PR #346 (issue #311): el fin de sesión (HU-AUTH-007, vista 17 «Sesión vencida») que llega
// con la app todavía leyendo la sesión guardada, y el orden de dos fines de sesión casi juntos.
//
// Complementa los tests del autor (`sesion_notifier_test.dart`, grupo «fines de sesión que se
// pisan (#311)»): acá van los casos que busca un QA que desconfía del arreglo.
//  1. Sin sesión zombi: la sesión guardada desaparece del teléfono y el arranque siguiente no la
//     restaura, pero sí avisa lo mismo que se vio.
//  2. La sesión viva no se pierde: un «Entrar» o un registro en vuelo cuando llega el fin de sesión
//     del servidor (el estado `AsyncLoading` de esas acciones no puede contar como «arrancando»).
//  3. Duplicados: el mismo fin de sesión varias veces antes de publicarse la sesión se atiende una vez.
//  4. «Cerrar sesión» a propósito mientras el guardado del motivo espera al reloj.
//  5. Almacén roto, lectura de la sesión que falla, correo del saludo sin sesión.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/reloj_sesion_en_almacen.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/data/repositories/cierre_forzado_repository_impl.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_correo_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/cierre_forzado.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/cierre_forzado_repository.dart';
import 'package:colportores_mobile/features/auth/domain/services/reloj_sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/aviso_sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/reingreso_sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/db_local_repository_en_memoria.dart';

const _correo = 'ana@example.com';
const _password = 'secreto123';

SesionModel _sesionGuardada() => SesionModel(
  usuarioId: '11111111-1111-4111-8111-111111111111',
  email: _correo,
  accessToken: 'token-guardado',
  expiraEn: DateTime.now().toUtc().add(const Duration(days: 20)),
  nombre: 'Ana',
);

/// La sesión guardada en el teléfono. Con [conPuerta], [leerSesion] no sigue hasta que el test
/// completa la [puerta]: el arranque con el Keystore lento.
final class _LocalConPuerta implements AuthLocalDataSource {
  _LocalConPuerta({this.guardada, bool conPuerta = false})
    : puerta = conPuerta ? Completer<void>() : null;

  final Completer<void>? puerta;
  SesionModel? guardada;

  /// Si es `true`, leer la sesión lanza (el almacén seguro roto).
  bool explotar = false;

  @override
  Future<SesionModel?> leerSesion() async {
    await puerta?.future;
    if (explotar) throw StateError('almacén roto');
    return guardada;
  }

  @override
  Future<void> guardarSesion(SesionModel sesion) async => guardada = sesion;

  @override
  Future<void> borrarSesion() async => guardada = null;
}

/// Cuenta lo que se guarda y se borra del motivo del último cierre, sin cambiar su comportamiento.
final class _CierresContados implements CierreForzadoRepository {
  _CierresContados(this._real);

  final CierreForzadoRepository _real;
  final guardados = <MotivoExpiracion>[];
  int borrados = 0;

  @override
  Future<CierreForzado?> leer() => _real.leer();

  @override
  Future<void> guardar(CierreForzado cierre) {
    guardados.add(cierre.motivo);
    return _real.guardar(cierre);
  }

  @override
  Future<void> borrar() {
    borrados++;
    return _real.borrar();
  }
}

/// Reloj de la sesión cuya lectura se retiene (el Keystore lento): cada lectura espera su turno.
final class _RelojPorTurnos implements RelojSesion {
  bool retener = false;
  final turnos = <Completer<DateTime>>[];

  @override
  Future<DateTime> ahora() {
    if (!retener) return Future.value(DateTime.now().toUtc());
    final turno = Completer<DateTime>();
    turnos.add(turno);
    return turno.future;
  }

  @override
  Future<void> registrar(DateTime visto) async {}
}

/// Un arranque de la app: el almacén seguro, la sesión guardada y el servidor, todo en memoria.
final class _Arranque {
  _Arranque({
    SesionModel? guardada,
    bool conPuerta = false,
    Map<ClaveSegura, String>? almacenInicial,
    RelojSesion? reloj,
    _LocalConPuerta? local,
    AlmacenSeguroEnMemoria? almacenPrevio,
  }) : almacen = almacenPrevio ?? AlmacenSeguroEnMemoria(almacenInicial),
       local = local ?? _LocalConPuerta(guardada: guardada, conPuerta: conPuerta),
       remoto = AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _password}) {
    cierres = _CierresContados(CierreForzadoRepositoryImpl(almacen));
    container = ProviderContainer(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remoto),
        authLocalDataSourceProvider.overrideWithValue(this.local),
        ultimoCorreoRepositoryProvider.overrideWithValue(UltimoCorreoRepositoryImpl(almacen)),
        cierreForzadoRepositoryProvider.overrideWithValue(cierres),
        relojSesionProvider.overrideWithValue(reloj ?? RelojSesionEnMemoria()),
      ],
    );
    addTearDown(container.dispose);
  }

  final AlmacenSeguroEnMemoria almacen;
  final _LocalConPuerta local;
  final AuthRemoteDataSourceEnMemoria remoto;
  late final _CierresContados cierres;
  late final ProviderContainer container;

  /// Empieza a leer la sesión (lo que hace la app al arrancar).
  Future<Object?> leer() => container.read(sesionProvider.future);

  Failure? get aviso => container.read(avisoSesionProvider);
  DatosReingreso? get reingreso => container.read(reingresoSesionProvider);
  Object? get sesion => container.read(sesionProvider).value;
  String? get cierreGuardado => almacen.contenido[ClaveSegura.cierreForzado];
}

/// Deja correr lo que quedó pendiente: guardados del almacén, cierre de la DB.
Future<void> _asentar() async {
  await pumpEventQueue();
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await pumpEventQueue();
}

void main() {
  group('QA #311 — sin sesión zombi tras un fin de sesión temprano', () {
    for (final (motivo, aviso, prefijo) in <(MotivoExpiracion, Failure, String)>[
      (MotivoExpiracion.revocada, const FailureSesionRevocada(), 'revocada|'),
      (MotivoExpiracion.inactividad, const FailureSesionExpiradaPorInactividad(), 'inactividad|'),
    ]) {
      test('${motivo.name}: la sesión guardada se descarta del teléfono, el aviso lleva el correo '
          'y el nombre, y el arranque siguiente avisa lo mismo sin restaurarla', () async {
        final a = _Arranque(guardada: _sesionGuardada(), conPuerta: true);
        final lectura = a.leer();
        await pumpEventQueue();

        a.remoto.simularExpiracion(motivo);
        await pumpEventQueue();
        a.local.puerta!.complete();
        await lectura;
        await _asentar();

        expect(a.sesion, isNull, reason: 'la sesión terminó: no queda adentro');
        expect(a.local.guardada, isNull, reason: 'sesión zombi: seguiría guardada en el teléfono');
        expect(a.aviso, aviso);
        expect(a.reingreso, DatosReingreso(motivo: motivo, email: _correo, nombre: 'Ana'));
        expect(a.cierreGuardado, startsWith(prefijo));
        expect(a.cierres.guardados, [motivo], reason: 'se guarda una sola vez');

        // El arranque siguiente: el mismo almacén seguro, la sesión ya no está.
        final b = _Arranque(
          almacenPrevio: a.almacen,
          local: _LocalConPuerta(guardada: a.local.guardada),
        );
        expect(await b.leer(), isNull, reason: 'la sesión no se restaura');
        await _asentar();
        expect(b.aviso, aviso, reason: 'el arranque siguiente avisa lo mismo que se vio');
        expect(b.reingreso?.email, _correo);
        expect(b.cierreGuardado, startsWith(prefijo));
      });
    }

    test(
      'el mismo fin de sesión tres veces antes de publicarse la sesión: se atiende una vez',
      () async {
        final a = _Arranque(guardada: _sesionGuardada(), conPuerta: true);
        final lectura = a.leer();
        await pumpEventQueue();

        for (var i = 0; i < 3; i++) {
          a.remoto.simularExpiracion(MotivoExpiracion.revocada);
        }
        await pumpEventQueue();
        a.local.puerta!.complete();
        await lectura;
        await _asentar();

        expect(a.sesion, isNull);
        expect(a.local.guardada, isNull);
        expect(a.aviso, const FailureSesionRevocada());
        expect(a.cierres.guardados, [MotivoExpiracion.revocada], reason: 'una sola vez, no tres');
      },
    );

    test(
      'la sesión guardada vence por inactividad en este arranque y además llega el fin de sesión '
      'por el stream: gana el que llegó, una sola vez cada uno y nada de sesión',
      () async {
        final vencida = SesionModel(
          usuarioId: '11111111-1111-4111-8111-111111111111',
          email: _correo,
          accessToken: 'token-viejo',
          expiraEn: DateTime.now().toUtc().subtract(const Duration(days: 1)),
          nombre: 'Ana',
        );
        final a = _Arranque(
          guardada: vencida,
          conPuerta: true,
          almacenInicial: {ClaveSegura.ultimoCorreo: _correo},
        );
        final lectura = a.leer();
        await pumpEventQueue();

        a.remoto.simularExpiracion(MotivoExpiracion.revocada);
        await pumpEventQueue();
        a.local.puerta!.complete();
        expect(await lectura, isNull);
        await _asentar();

        expect(a.sesion, isNull);
        expect(a.local.guardada, isNull);
        expect(a.aviso, const FailureSesionRevocada());
        expect(
          a.cierreGuardado,
          startsWith('revocada|'),
          reason: 'en disco, el del aviso que se ve',
        );
        expect(a.reingreso?.email, _correo);
      },
    );

    test(
      'la sesión no se puede leer (almacén roto) y llega el fin de sesión temprano: el login sale '
      'con el aviso, sin excepciones sueltas',
      () async {
        final a = _Arranque(local: _LocalConPuerta(conPuerta: true)..explotar = true);
        final lectura = a.leer();
        await pumpEventQueue();

        a.remoto.simularExpiracion(MotivoExpiracion.revocada);
        await pumpEventQueue();
        a.local.puerta!.complete();
        await lectura;
        await _asentar();

        expect(a.sesion, isNull);
        expect(a.aviso, const FailureSesionRevocada());
        expect(a.cierreGuardado, startsWith('revocada|'));
      },
    );

    test('con el almacén seguro roto, el fin de sesión temprano igual cierra la sesión y deja el '
        'aviso (el motivo no se guarda, pero no se queda adentro)', () async {
      final a = _Arranque(guardada: _sesionGuardada(), conPuerta: true);
      final lectura = a.leer();
      await pumpEventQueue();

      a.remoto.simularExpiracion(MotivoExpiracion.revocada);
      await pumpEventQueue();
      a.almacen.simularFalla = true;
      a.local.puerta!.complete();
      await lectura;
      await _asentar();

      expect(a.sesion, isNull, reason: 'no queda adentro con la sesión revocada');
      expect(a.local.guardada, isNull);
      expect(a.aviso, const FailureSesionRevocada());
    });
  });

  group('QA #311 — la sesión viva no se pierde', () {
    test('sonda: Riverpod conserva el valor anterior en `state = AsyncLoading()` (el fin de sesión '
        'temprano se distingue por eso del «entrar» en vuelo)', () async {
      final a = _Arranque();
      expect(await a.leer(), isNull);
      a.remoto.demoraIniciarSesion = Completer<void>();

      final entrada = a.container
          .read(sesionProvider.notifier)
          .iniciarSesion(email: _correo, password: _password);
      await pumpEventQueue();
      final estado = a.container.read(sesionProvider);

      expect(estado.isLoading, isTrue);
      expect(estado.hasValue, isTrue, reason: 'si esto cambia, el arreglo del #311 deja de valer');
      a.remoto.demoraIniciarSesion!.complete();
      await entrada;
    });

    for (final motivo in MotivoExpiracion.values) {
      test(
        '«Entrar» en vuelo cuando llega el fin de sesión (${motivo.name}) de la sesión anterior: '
        'la sesión nueva queda abierta, sin aviso y sin motivo guardado',
        () async {
          final a = _Arranque();
          expect(await a.leer(), isNull);
          a.remoto.demoraIniciarSesion = Completer<void>();

          final entrada = a.container
              .read(sesionProvider.notifier)
              .iniciarSesion(email: _correo, password: _password);
          await pumpEventQueue();
          a.remoto.simularExpiracion(motivo);
          await pumpEventQueue();
          a.remoto.demoraIniciarSesion!.complete();
          expect(await entrada, isNull);
          await _asentar();

          expect(a.sesion, isNotNull, reason: 'la persona acaba de entrar: no se le cierra');
          expect(a.aviso, isNull);
          expect(a.reingreso, isNull);
          expect(a.cierreGuardado, isNull);
          expect(
            a.local.guardada,
            isNotNull,
            reason: 'la sesión nueva quedó guardada en el teléfono',
          );
        },
      );
    }

    test(
      'registro (con sesión) en vuelo cuando llega el fin de sesión de la anterior: la cuenta nueva '
      'queda adentro, sin aviso',
      () async {
        final a = _Arranque();
        expect(await a.leer(), isNull);
        a.remoto.demoraRegistrar = Completer<void>();

        final registro = a.container
            .read(sesionProvider.notifier)
            .registrar(
              nombre: 'Ana',
              apellido: 'Pérez',
              cedula: '12345678',
              email: 'nueva@example.com',
              password: 'Secreto123',
              aceptaTerminos: true,
              aceptaTradeOffE2E: true,
            );
        await pumpEventQueue();
        a.remoto.simularExpiracion(MotivoExpiracion.revocada);
        await pumpEventQueue();
        a.remoto.demoraRegistrar!.complete();
        final r = await registro;
        await _asentar();

        expect(r.isRight(), isTrue);
        expect(a.sesion, isNotNull);
        expect(a.aviso, isNull);
        expect(a.cierreGuardado, isNull);
      },
    );

    test(
      'el fin de sesión llega con la sesión ya publicada y la persona vuelve a entrar enseguida: '
      'queda adentro, sin aviso, y no queda motivo guardado',
      () async {
        final a = _Arranque(guardada: _sesionGuardada(), conPuerta: true);
        final lectura = a.leer();
        await pumpEventQueue();
        a.remoto.simularExpiracion(MotivoExpiracion.inactividad);
        await pumpEventQueue();
        a.local.puerta!.complete();
        await lectura;
        await _asentar();

        final falla = await a.container
            .read(sesionProvider.notifier)
            .iniciarSesion(email: _correo, password: _password);
        await _asentar();

        expect(falla, isNull);
        expect(a.sesion, isNotNull);
        expect(a.aviso, isNull);
        expect(a.reingreso, isNull);
        expect(a.cierreGuardado, isNull);
        expect(a.cierres.borrados, greaterThanOrEqualTo(1));
      },
    );
  });

  group('QA #311 — reentradas y fines de sesión que se suman', () {
    test('volver a la app (revisión de vigencia) mientras se lee la sesión: no hace nada y el fin '
        'de sesión temprano se atiende igual', () async {
      final a = _Arranque(guardada: _sesionGuardada(), conPuerta: true);
      final lectura = a.leer();
      await pumpEventQueue();
      a.remoto.simularExpiracion(MotivoExpiracion.revocada);
      await pumpEventQueue();

      await a.container.read(sesionProvider.notifier).revisarVigencia();
      expect(a.aviso, isNull, reason: 'todavía no hay sesión que revisar ni aviso que mostrar');
      a.local.puerta!.complete();
      await lectura;
      await _asentar();

      expect(a.sesion, isNull);
      expect(a.aviso, const FailureSesionRevocada());
      expect(a.cierres.guardados, [MotivoExpiracion.revocada]);
    });

    test(
      'un segundo fin de sesión (otro motivo) llega con la sesión ya publicada y el guardado del '
      'primero todavía espera al reloj: el aviso y el motivo guardado son los del último, aunque '
      'su lectura termine primero',
      () async {
        final reloj = _RelojPorTurnos()..retener = true;
        final a = _Arranque(guardada: _sesionGuardada(), conPuerta: true, reloj: reloj);
        final lectura = a.leer();
        await pumpEventQueue();
        a.remoto.simularExpiracion(MotivoExpiracion.revocada);
        await pumpEventQueue();
        a.local.puerta!.complete();
        await pumpEventQueue();
        reloj.turnos[0].complete(DateTime.now().toUtc());
        await lectura;
        await pumpEventQueue();
        expect(reloj.turnos, hasLength(2), reason: 'el guardado de la revocada espera su turno');

        a.remoto.simularExpiracion(MotivoExpiracion.inactividad);
        await pumpEventQueue();
        expect(reloj.turnos, hasLength(3), reason: 'el guardado de la inactividad espera el suyo');
        reloj.turnos[2].complete(DateTime.now().toUtc());
        await _asentar();
        reloj.turnos[1].complete(DateTime.now().toUtc());
        await _asentar();

        expect(a.sesion, isNull);
        expect(a.local.guardada, isNull);
        expect(a.aviso, const FailureSesionExpiradaPorInactividad());
        expect(a.cierreGuardado, startsWith('inactividad|'), reason: 'el de disco es el del aviso');
      },
    );
  });

  group('QA #311 — «Cerrar sesión» a propósito no se pisa', () {
    /// El fin de sesión temprano ya publicó la sesión y su guardado espera al reloj (Keystore lento):
    /// ahí la persona toca «Cerrar sesión». Devuelve el arranque ya asentado.
    Future<_Arranque> cierraAPropositoConElGuardadoEnEspera() async {
      final reloj = _RelojPorTurnos()..retener = true;
      final a = _Arranque(
        guardada: _sesionGuardada(),
        conPuerta: true,
        reloj: reloj,
        almacenInicial: {ClaveSegura.ultimoCorreo: _correo},
      );
      final lectura = a.leer();
      await pumpEventQueue();
      a.remoto.simularExpiracion(MotivoExpiracion.revocada);
      await pumpEventQueue();
      a.local.puerta!.complete();
      await pumpEventQueue();
      expect(reloj.turnos, hasLength(1), reason: 'la lectura de la vigencia de la sesión');
      reloj.turnos[0].complete(DateTime.now().toUtc());
      await lectura;
      await pumpEventQueue();
      expect(reloj.turnos, hasLength(2), reason: 'el guardado del motivo espera su turno');
      expect(a.sesion, isNotNull, reason: 'la sesión sigue publicada mientras tanto');

      await a.container.read(sesionProvider.notifier).cerrarSesion();
      reloj.turnos[1].complete(DateTime.now().toUtc());
      await _asentar();
      return a;
    }

    test('fin de sesión temprano y la persona toca «Cerrar sesión» mientras el guardado del motivo '
        'espera al reloj: no queda ni el motivo ni el correo guardados', () async {
      final a = await cierraAPropositoConElGuardadoEnEspera();

      expect(a.sesion, isNull);
      expect(a.cierreGuardado, isNull, reason: 'cerró a propósito: el motivo no se guarda');
      expect(a.almacen.contenido, isEmpty);
      expect(a.cierres.guardados, isEmpty);
    });

    // QA #346: el aviso se fija antes de esperar al reloj y nadie lo retira si la persona cierra
    // sesión a propósito en esa ventana; el login sale con «Tu sesión se cerró porque…». Es previo
    // al PR (el control de abajo falla igual con la app ya abierta); el camino temprano lo hace
    // alcanzable justo después del arranque.
    test(
      'fin de sesión temprano y «Cerrar sesión» a propósito en esa ventana: el login sale sin '
      'aviso ni saludo',
      () async {
        final a = await cierraAPropositoConElGuardadoEnEspera();

        expect(a.aviso, isNull, reason: 'cerró a propósito: no puede salir «se cerró tu sesión»');
        expect(a.reingreso, isNull);
      },
      skip:
          'QA #346: «Cerrar sesión» a propósito durante el guardado lento deja el aviso del fin de sesión (previo al PR)',
    );

    test('control (previo al PR): la misma carrera con la app ya abierta deja el aviso', () async {
      final reloj = _RelojPorTurnos();
      final a = _Arranque(guardada: _sesionGuardada(), reloj: reloj);
      expect(await a.leer(), isNotNull);
      await _asentar();
      reloj.retener = true;

      a.remoto.simularExpiracion(MotivoExpiracion.revocada);
      await pumpEventQueue();
      expect(reloj.turnos, hasLength(1));
      await a.container.read(sesionProvider.notifier).cerrarSesion();
      reloj.turnos[0].complete(DateTime.now().toUtc());
      await _asentar();

      expect(a.sesion, isNull);
      expect(a.cierreGuardado, isNull);
      expect(a.aviso, isNotNull, reason: 'documenta el comportamiento previo: el aviso queda');
    });
  });

  group('QA #311 — el saludo del login sin sesión que cerrar', () {
    test(
      'sin sesión guardada ni motivo pendiente, con el último correo en el teléfono, el fin de '
      'sesión temprano deja el correo en el saludo (igual que el arranque siguiente)',
      () async {
        final a = _Arranque(conPuerta: true, almacenInicial: {ClaveSegura.ultimoCorreo: _correo});
        final lectura = a.leer();
        await pumpEventQueue();

        a.remoto.simularExpiracion(MotivoExpiracion.revocada);
        await pumpEventQueue();
        a.local.puerta!.complete();
        await lectura;
        await _asentar();
        final enEsteArranque = a.reingreso;

        final b = _Arranque(almacenPrevio: a.almacen);
        await b.leer();
        await _asentar();

        expect(b.reingreso?.email, _correo, reason: 'el arranque siguiente sí pone el correo');
        expect(
          enEsteArranque?.email,
          b.reingreso?.email,
          reason: 'el saludo del arranque en que llegó el aviso no debería diferir del siguiente',
        );
      },
      skip:
          'QA #346: sin sesión ni motivo pendiente, el fin de sesión temprano no lee el último correo',
    );
  });
}
