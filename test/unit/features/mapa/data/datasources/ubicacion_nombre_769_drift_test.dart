// El nombre opcional de la ubicación («Nombre ubic.» de Cristian, 24/11; backend-supabase 0206, #313; #769)
// contra las tablas reales: AppDatabase en memoria, del caso de uso al repositorio y a Drift, con el encolado
// dentro de la transacción. Es un texto libre de hasta 80 caracteres que sale del teléfono: se recorta, el
// vacío es «sin nombre» y nunca se pierde al editar otra cosa de la ubicación.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_modificacion_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/modificar_ubicacion_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/registrar_ubicacion_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/zonas_falsas.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 26, 13);
  final t1 = DateTime.utc(2026, 11, 26, 14);
  const italia = Coordenadas(lat: -34.891, lon: -56.125);

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift local;
  late RegistrarUbicacionUseCase registrar;
  late ModificarUbicacionUseCase modificar;
  var ids = 0;

  setUp(() {
    ids = 0;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    final repositorio = UbicacionRepositoryImpl(local, logger: loggerMudo());
    registrar = RegistrarUbicacionUseCase(
      repositorio,
      generarId: () => 'id-${++ids}',
      ubicador: ubicadorSinZonas(),
      ahora: () => t0,
    );
    modificar = ModificarUbicacionUseCase(
      repositorio,
      generarId: () => 'esp-nuevo',
      ubicador: ubicadorSinZonas(),
      ahora: () => t1,
    );
  });
  tearDown(() => db.close());

  /// Un alta en [italia], o [norte] metros al norte (otra ubicación, lejos de las candidatas a duplicado).
  RegistrarUbicacionParams alta({
    String? nombre,
    String calle = 'Av. Italia',
    String? id,
    double norte = 0,
  }) => RegistrarUbicacionParams(
    colportorId: 'col-1',
    tipo: TipoUbicacion.negocio,
    punto: PuntoCapturado.gps(
      LecturaGps(
        coordenadas: Coordenadas(lat: italia.lat + norte / 111195.08, lon: italia.lon),
        precisionMetros: 10,
      ),
    ),
    ciudadId: 'mvd',
    calle: calle,
    numero: '2810',
    nombre: nombre,
    id: id ?? registrar.nuevoId(),
  );

  Future<UbicacionModel> registrada(String? nombre, {double norte = 0}) async {
    final r = await registrar(alta(nombre: nombre, norte: norte, calle: 'Calle $norte'));
    final creada = r.getOrElse(() => throw StateError('falló')) as AltaRegistrada;
    return (await local.obtener(creada.ubicacion.id))!;
  }

  ModificarUbicacionParams edicion(
    UbicacionModel base, {
    String? nombre,
    String? calle,
    DateTime? baseUpdatedAt,
  }) => ModificarUbicacionParams(
    id: base.id,
    colportorId: 'col-1',
    tipo: base.tipo,
    coordenadas: base.coordenadas,
    baseUpdatedAt: baseUpdatedAt ?? base.auditoria.updatedAt,
    ciudadId: base.ciudadId,
    calle: calle ?? base.calle,
    numero: base.numero,
    nombre: nombre,
  );

  Future<Either<Failure, ResultadoModificacionUbicacion>> editar(ModificarUbicacionParams p) =>
      modificar(p);

  group('alta con nombre', () {
    test('el nombre se recorta, se guarda y sube con la fila entera', () async {
      final guardada = await registrada('  Farmacia Italia  ');

      expect(guardada.nombre, 'Farmacia Italia');
      final subida = encolador.encolados.firstWhere((c) => c.entidad == 'ubicacion');
      expect(subida.operacion, OperacionSync.insert);
      expect(subida.payload['nombre'], 'Farmacia Italia');
    });

    test(
      'sin nombre o en blanco la ubicación queda sin nombre (null), como las de antes',
      () async {
        expect((await registrada(null)).nombre, isNull);
        expect((await registrada('   ', norte: 500)).nombre, isNull);
        expect(
          encolador.encolados
              .where((c) => c.entidad == 'ubicacion')
              .map((c) => c.payload['nombre']),
          everyElement(isNull),
        );
      },
    );

    test('80 caracteres entran; 81 no se guardan ni se encolan y dicen qué corregir', () async {
      final justo = 'a' * Ubicacion.largoMaximoDelNombre;
      expect((await registrada(justo)).nombre, justo);
      final antes = encolador.encolados.length;

      final r = await registrar(
        alta(nombre: '${'a' * Ubicacion.largoMaximoDelNombre}b', norte: 500),
      );

      final falla = r.swap().getOrElse(() => throw StateError('debía fallar'));
      expect(falla, isA<FailureValidacion>());
      expect((falla as FailureValidacion).campos.keys, contains('nombre'));
      expect(encolador.encolados, hasLength(antes));
      expect(await db.select(db.ubicaciones).get(), hasLength(1));
    });

    test('el nombre se cuenta recortado: 80 letras con espacios de más entran', () async {
      final r = await registrar(alta(nombre: '  ${'a' * Ubicacion.largoMaximoDelNombre}  '));

      expect(r.isRight(), isTrue);
    });
  });

  group('edición del nombre', () {
    test('cambiar solo el nombre guarda y sube el cambio (un update con la fila entera)', () async {
      final base = await registrada('Farmacia Italia');
      encolador.encolados.clear();

      final r = await editar(edicion(base, nombre: '  Farmacia Italia 2 '));

      expect(r.getOrElse(() => throw StateError('falló')), isA<UbicacionModificada>());
      expect((await local.obtener(base.id))!.nombre, 'Farmacia Italia 2');
      final cambio = encolador.encolados.single;
      expect(cambio.operacion, OperacionSync.update);
      expect(cambio.payload['nombre'], 'Farmacia Italia 2');
      expect(cambio.payload['sync_version'], base.auditoria.syncVersion);
    });

    test('ponerlo en blanco lo borra: queda sin nombre y sube null', () async {
      final base = await registrada('Farmacia Italia');
      encolador.encolados.clear();

      await editar(edicion(base, nombre: '   '));

      expect((await local.obtener(base.id))!.nombre, isNull);
      expect(encolador.encolados.single.payload['nombre'], isNull);
    });

    test('ponerle nombre a una ubicación que no tenía lo suma', () async {
      final base = await registrada(null);

      await editar(edicion(base, nombre: 'Almacén Don Pedro'));

      expect((await local.obtener(base.id))!.nombre, 'Almacén Don Pedro');
    });

    test('lo mismo que ya tenía no escribe ni encola nada (sin cambios)', () async {
      final base = await registrada('Farmacia Italia');
      encolador.encolados.clear();

      final r = await editar(edicion(base, nombre: 'Farmacia Italia'));

      expect(r.getOrElse(() => throw StateError('falló')), isA<ModificacionSinCambios>());
      expect(encolador.encolados, isEmpty);
      expect((await local.obtener(base.id))!.auditoria.updatedAt, t0);
    });

    test(
      'cambiar otra cosa y pasar el nombre que tenía lo conserva (y sube con la fila)',
      () async {
        final base = await registrada('Farmacia Italia');
        encolador.encolados.clear();

        await editar(edicion(base, nombre: 'Farmacia Italia', calle: 'Av. Brasil'));

        final guardada = (await local.obtener(base.id))!;
        expect((guardada.calle, guardada.nombre), ('Av. Brasil', 'Farmacia Italia'));
        expect(encolador.encolados.single.payload['nombre'], 'Farmacia Italia');
      },
    );

    test('doble toque en «Guardar»: el segundo es el mismo éxito y no vuelve a encolar', () async {
      final base = await registrada('Farmacia Italia');
      encolador.encolados.clear();
      final pedido = edicion(base, nombre: 'Farmacia Nueva');

      await editar(pedido);
      final segundo = await editar(pedido);

      expect(segundo.isRight(), isTrue);
      expect(encolador.encolados, hasLength(1));
      expect((await local.obtener(base.id))!.nombre, 'Farmacia Nueva');
    });

    test('más de 80 caracteres no se guarda ni se encola y dice qué corregir', () async {
      final base = await registrada('Farmacia Italia');
      encolador.encolados.clear();

      final r = await editar(edicion(base, nombre: 'a' * (Ubicacion.largoMaximoDelNombre + 1)));

      final falla = r.swap().getOrElse(() => throw StateError('debía fallar'));
      expect(falla, isA<FailureValidacion>());
      expect((falla as FailureValidacion).campos.keys, contains('nombre'));
      expect(encolador.encolados, isEmpty);
      expect((await local.obtener(base.id))!.nombre, 'Farmacia Italia');
    });

    test('si el encolado falla el nombre tampoco queda (todo o nada)', () async {
      final base = await registrada('Farmacia Italia');
      encolador
        ..encolados.clear()
        ..fallarCon = StateError('motor apagado');

      final r = await editar(edicion(base, nombre: 'Farmacia Nueva'));

      expect(r.isLeft(), isTrue);
      expect((await local.obtener(base.id))!.nombre, 'Farmacia Italia');
    });

    test(
      'una ubicación vieja sin nombre, editada en otra cosa, sigue sin nombre y no inventa uno',
      () async {
        final base = await registrada(null);

        await editar(edicion(base, calle: 'Av. Brasil'));

        expect((await local.obtener(base.id))!.nombre, isNull);
        expect(base.auditoria, isA<Auditoria>());
      },
    );
  });
}
