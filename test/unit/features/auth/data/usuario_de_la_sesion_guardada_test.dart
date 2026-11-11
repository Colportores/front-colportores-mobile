// El usuario de la sesión guardada, para quien corre sin la app (el respaldo de la noche, #583).
import 'dart:convert';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/features/auth/data/datasources/usuario_de_la_sesion_guardada.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/respaldo_drive_falsos.dart';

void main() {
  late AlmacenControlable almacen;

  setUp(() => almacen = AlmacenControlable());

  Future<void> guardar(Object? sesion) =>
      almacen.escribir(ClaveSegura.sesionAuth, sesion is String ? sesion : jsonEncode(sesion));

  test('dada una sesión de Supabase, devuelve el id del usuario', () async {
    await guardar({
      'access_token': 'a.b.c',
      'refresh_token': 'r',
      'user': {'id': 'u-1', 'email': 'ana@example.com'},
    });

    expect(await usuarioDeLaSesionGuardada(almacen), 'u-1');
  });

  test('sin sesión guardada, null', () async {
    expect(await usuarioDeLaSesionGuardada(almacen), isNull);
  });

  test(
    'un valor que no es la sesión (JSON roto, lista, sin usuario, id vacío) es sin sesión',
    () async {
      for (final valor in <Object?>[
        '{esto no es json',
        [1, 2],
        {'access_token': 'x'},
        {'user': 'u-1'},
        {
          'user': {'id': 7},
        },
        {
          'user': {'id': '  '},
        },
      ]) {
        await guardar(valor);
        expect(await usuarioDeLaSesionGuardada(almacen), isNull, reason: '$valor');
      }
    },
  );

  // Decisión del 04/11 en #583 (QA P1), #691: «no pude leer el almacén» no es «no hay sesión».
  test(
    'si el almacén no se deja leer, lanza SesionGuardadaIlegible (no es «sin sesión»)',
    () async {
      almacen.alLeer = true;

      await expectLater(usuarioDeLaSesionGuardada(almacen), throwsA(isA<SesionGuardadaIlegible>()));
    },
  );

  test(
    'el error del almacén no viaja en la excepción (puede traer un pedazo de la sesión)',
    () async {
      almacen.alLeer = true;

      final error = await usuarioDeLaSesionGuardada(
        almacen,
      ).then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<SesionGuardadaIlegible>());
      expect(error.toString(), 'SesionGuardadaIlegible');
    },
  );

  test('cuando el almacén vuelve a leerse, devuelve el usuario como siempre', () async {
    await guardar({
      'user': {'id': 'u-2'},
    });
    almacen.alLeer = true;
    await expectLater(usuarioDeLaSesionGuardada(almacen), throwsA(isA<SesionGuardadaIlegible>()));

    almacen.alLeer = false;

    expect(await usuarioDeLaSesionGuardada(almacen), 'u-2');
  });
}
