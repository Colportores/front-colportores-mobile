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

  test('si el almacén no se deja leer, null y no lanza', () async {
    almacen.alLeer = true;

    expect(await usuarioDeLaSesionGuardada(almacen), isNull);
  });
}
