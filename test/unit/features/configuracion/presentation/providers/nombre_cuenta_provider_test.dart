// El nombre de la cuenta (#243): sale de la sesión, con la copia de la DB cifrada de respaldo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/features/auth/data/datasources/sesion_usuario_local_data_source.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/configuracion/presentation/providers/nombre_cuenta_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';

class _SesionFija extends SesionNotifier {
  _SesionFija(this._sesion);

  final Sesion? _sesion;

  @override
  Future<Sesion?> build() async => _sesion;
}

/// La DB «abierta» sin cifrado ni helper: el provider solo necesita el `AppDatabase`.
class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase? _db;

  @override
  AppDatabase? build() => _db;
}

Sesion _sesion({String? nombre, String usuarioId = 'u-1'}) => Sesion(
  usuarioId: usuarioId,
  email: 'ana@example.com',
  accessToken: 'jwt',
  expiraEn: DateTime.utc(2026, 10, 30),
  nombre: nombre,
);

void main() {
  late AppDatabase db;
  late SesionUsuarioLocalDataSource copia;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    copia = SesionUsuarioLocalDataSource(db);
  });

  tearDown(() => db.close());

  ProviderContainer armar(Sesion? sesion, {bool conDb = true}) {
    final c = ProviderContainer(
      overrides: [
        sesionProvider.overrideWith(() => _SesionFija(sesion)),
        dbLocalProvider.overrideWith(() => _DbFija(conDb ? db : null)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<String?> nombre(ProviderContainer c) async {
    await c.read(sesionProvider.future);
    await c.read(nombreGuardadoProvider.future);
    return c.read(nombreCuentaProvider);
  }

  test('con nombre en la sesión, es ese', () async {
    expect(await nombre(armar(_sesion(nombre: 'Lucía'))), 'Lucía');
  });

  test('sin nombre en la sesión ni copia (una cuenta vieja), es null: saludo a secas', () async {
    expect(await nombre(armar(_sesion())), isNull);
    expect(await nombre(armar(_sesion(nombre: '   '))), isNull);
  });

  test('sin sesión, es null', () async {
    expect(await nombre(armar(null)), isNull);
  });

  test('si la sesión no lo trae pero la copia sí, usa la copia', () async {
    await copia.guardar('u-1', 'Lucía');

    expect(await nombre(armar(_sesion())), 'Lucía');
  });

  test('la copia de otro usuario nunca se usa', () async {
    await copia.guardar('u-2', 'Otra Persona');

    expect(await nombre(armar(_sesion())), isNull);
  });

  test('sin DB abierta, con nombre en la sesión, igual hay nombre', () async {
    expect(await nombre(armar(_sesion(nombre: 'Lucía'), conDb: false)), 'Lucía');
  });

  group('copiaNombreSesionProvider', () {
    Future<void> esperarEscritura() => Future<void>.delayed(const Duration(milliseconds: 50));

    test('con sesión con nombre y DB abierta, guarda la copia', () async {
      final c = armar(_sesion(nombre: 'Lucía'));
      await c.read(sesionProvider.future);

      c.read(copiaNombreSesionProvider);
      await esperarEscritura();

      expect(await copia.leer('u-1'), 'Lucía');
    });

    test('si el nombre cambia entre ingresos, la copia se actualiza', () async {
      await copia.guardar('u-1', 'Lucía');
      final c = armar(_sesion(nombre: 'Lucía Beatriz'));
      await c.read(sesionProvider.future);

      c.read(copiaNombreSesionProvider);
      await esperarEscritura();

      expect(await copia.leer('u-1'), 'Lucía Beatriz');
    });

    test('con sesión sin nombre no guarda nada', () async {
      final c = armar(_sesion());
      await c.read(sesionProvider.future);

      c.read(copiaNombreSesionProvider);
      await esperarEscritura();

      expect(await db.select(db.sesionUsuarios).get(), isEmpty);
    });

    test('sin DB abierta no falla ni guarda', () async {
      final c = armar(_sesion(nombre: 'Lucía'), conDb: false);
      await c.read(sesionProvider.future);

      c.read(copiaNombreSesionProvider);
      await esperarEscritura();

      expect(await db.select(db.sesionUsuarios).get(), isEmpty);
    });
  });
}
