// HU-NOT-004 / #516: los avisos del servidor se leen de `usuario.notif_preferences` y se guardan con
// `guardar_mis_preferencias_de_avisos` (backend-supabase 0166). Importa supabase_flutter: flutter_test.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/features/notificaciones/data/repositories/avisos_del_servidor_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/avisos_del_servidor.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/avisos_del_servidor_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/logger_mudo.dart';

AvisosDelServidorSupabase _repo({
  Future<Object?> Function()? leer,
  Future<void> Function(Map<String, Object?>)? guardar,
  Duration tope = const Duration(seconds: 5),
}) => AvisosDelServidorSupabase(
  leerFila: leer ?? () async => null,
  guardarRpc: guardar ?? (_) async {},
  tope: tope,
  logger: loggerMudo(),
);

void main() {
  group('leer', () {
    test('la fila sin preferencias (null): los valores de siempre', () async {
      expect(await _repo().leer(), const AvisosDelServidor());
    });

    test('traduce lo que contestó el select', () async {
      final avisos = await _repo(
        leer: () async => {'cuotas': false, 'hora_cuota': '07:00', 'otra': 1},
      ).leer();
      expect(avisos.cuotas, isFalse);
      expect(avisos.horaCuota, const HoraDelAviso(7, 0));
      expect(avisos.otras, {'otra': 1});
    });

    test('un valor raro del servidor no rompe la pantalla', () async {
      expect(await _repo(leer: () async => 'cualquier cosa').leer(), const AvisosDelServidor());
    });
  });

  group('guardar', () {
    test('manda el objeto entero a la función', () async {
      Map<String, Object?>? recibido;
      await _repo(guardar: (o) async => recibido = o).guardar(
        const AvisosDelServidor(tickets: false, horaAgenda: HoraDelAviso(21, 30), otras: {'x': 1}),
      );
      expect(recibido, {
        'x': 1,
        'pedidos': true,
        'tickets': false,
        'cuotas': true,
        'asignaciones': true,
        'agenda': true,
        'hora_cuota': '09:00',
        'hora_agenda': '21:30',
      });
    });
  });

  group('las fallas se traducen', () {
    for (final (nombre, error, esperado) in <(String, Object, bool)>[
      ('sin red (SocketException)', const SocketException('sin ruta'), true),
      ('cliente HTTP caído', http.ClientException('cortado'), true),
      ('la sesión no se pudo renovar por la red', AuthRetryableFetchException(message: 'x'), true),
      ('tiempo agotado', TimeoutException('x'), true),
      ('error del servidor', const PostgrestException(message: 'x', code: '23514'), false),
      ('sin sesión válida', const AuthException('vencida'), false),
    ]) {
      test('$nombre, al leer', () {
        expect(
          _repo(leer: () => Future<Object?>.error(error)).leer(),
          throwsA(esperado ? isA<AvisosSinConexionException>() : isA<AvisosServidorException>()),
        );
      });
      test('$nombre, al guardar', () {
        expect(
          _repo(guardar: (_) => Future<void>.error(error)).guardar(const AvisosDelServidor()),
          throwsA(esperado ? isA<AvisosSinConexionException>() : isA<AvisosServidorException>()),
        );
      });
    }

    test('el SQLSTATE queda en la falla y no hay nada más', () async {
      try {
        await _repo(
          guardar: (_) => Future<void>.error(const PostgrestException(message: 'x', code: '23514')),
        ).guardar(const AvisosDelServidor());
        fail('tenía que lanzar');
      } on AvisosServidorException catch (e) {
        expect(e.codigo, '23514');
        expect(e.toString(), 'AvisosServidorException(23514)');
      }
    });

    test('una sesión que no sirve es 42501', () async {
      try {
        await _repo(leer: () => Future<Object?>.error(const AuthException('vencida'))).leer();
        fail('tenía que lanzar');
      } on AvisosServidorException catch (e) {
        expect(e.codigo, '42501');
      }
    });

    test(
      'un servidor que no contesta cuenta como sin conexión (no deja cargando para siempre)',
      () {
        final nunca = Completer<Object?>();
        expect(
          _repo(leer: () => nunca.future, tope: const Duration(milliseconds: 20)).leer(),
          throwsA(isA<AvisosSinConexionException>()),
        );
        final nunca2 = Completer<void>();
        expect(
          _repo(
            guardar: (_) => nunca2.future,
            tope: const Duration(milliseconds: 20),
          ).guardar(const AvisosDelServidor()),
          throwsA(isA<AvisosSinConexionException>()),
        );
      },
    );

    test('un error que no es de red ni del servidor sale tal cual', () {
      expect(
        _repo(leer: () => Future<Object?>.error(StateError('bug'))).leer(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
