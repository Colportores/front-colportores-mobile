// Test de dominio: Dart puro (HU-UBI-002).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/consulta_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/armador_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 12);
  const yo = 'col-1';
  const aqui = Coordenadas(lat: -34.9, lon: -56.15);

  /// `metrosAlNorte` de [aqui]; `minutos` desde t0 es el `updated_at`.
  Ubicacion ub(
    String id, {
    TipoUbicacion tipo = TipoUbicacion.casa,
    String? calle = 'Rivadavia',
    String? numero = '100',
    double metrosAlNorte = 0,
    String ciudad = 'mvd',
    int minutos = 0,
    bool baja = false,
    String? dueno = yo,
  }) => Ubicacion(
    id: id,
    tipo: tipo,
    calle: calle,
    numero: numero,
    lat: aqui.lat + metrosAlNorte / 111195.08,
    lon: aqui.lon,
    ciudadId: ciudad,
    auditoria: Auditoria(
      createdAt: t0,
      updatedAt: t0.add(Duration(minutes: minutos)),
      createdBy: dueno,
      deletedAt: baja ? t0.add(Duration(minutes: minutos)) : null,
    ),
  );

  List<String> ids(ConsultaListaUbicaciones c, List<Ubicacion> todas) => [
    for (final i in ArmadorListaUbicaciones.armar(todas, c).items) i.ubicacion.id,
  ];

  const consulta = ConsultaListaUbicaciones(colportorId: yo);

  group('lista base', () {
    test('sin ubicaciones: vacía, sin más páginas y con los tres tipos en 0', () {
      final r = ArmadorListaUbicaciones.armar(const [], consulta);
      expect(r.estaVacia, isTrue);
      expect(r.items, isEmpty);
      expect(r.hayMas, isFalse);
      expect(r.porTipo, {for (final t in TipoUbicacion.values) t: 0});
    });

    test('solo las del colportor y sin bajas por defecto', () {
      final todas = [
        ub('mia'),
        ub('ajena', dueno: 'col-2'),
        ub('baja', baja: true),
        ub('sin-dueno', dueno: null),
      ];
      expect(ids(consulta, todas), ['mia']);
    });

    test('orden por defecto: updated_at descendente, empate por id', () {
      final todas = [ub('b'), ub('c', minutos: 5), ub('a'), ub('d', minutos: 9)];
      expect(ids(consulta, todas), ['d', 'c', 'a', 'b']);
    });

    test('sin posición no hay distancias', () {
      final r = ArmadorListaUbicaciones.armar([ub('a')], consulta);
      expect(r.items.single.distanciaMetros, isNull);
    });
  });

  group('filtros', () {
    final todas = [
      ub('casa-mvd'),
      ub('neg-mvd', tipo: TipoUbicacion.negocio),
      ub('edi-mvd', tipo: TipoUbicacion.edificio),
      ub('casa-sal', ciudad: 'sal'),
    ];

    test('por tipo (uno o varios)', () {
      expect(
        ids(const ConsultaListaUbicaciones(colportorId: yo, tipos: {TipoUbicacion.negocio}), todas),
        ['neg-mvd'],
      );
      expect(
        ids(
          const ConsultaListaUbicaciones(
            colportorId: yo,
            tipos: {TipoUbicacion.negocio, TipoUbicacion.edificio},
          ),
          todas,
        ),
        unorderedEquals(['neg-mvd', 'edi-mvd']),
      );
    });

    test('por ciudad', () {
      expect(ids(const ConsultaListaUbicaciones(colportorId: yo, ciudadId: 'sal'), todas), [
        'casa-sal',
      ]);
    });

    test('filtro combinado tipo + ciudad + búsqueda: cumplen todos', () {
      final r = ids(
        const ConsultaListaUbicaciones(
          colportorId: yo,
          tipos: {TipoUbicacion.casa},
          ciudadId: 'mvd',
          busqueda: 'rivadavia',
        ),
        todas,
      );
      expect(r, ['casa-mvd']);
    });

    test('los contadores: total con todos los filtros, porTipo sin el filtro de tipo', () {
      final r = ArmadorListaUbicaciones.armar(
        todas,
        const ConsultaListaUbicaciones(
          colportorId: yo,
          tipos: {TipoUbicacion.casa},
          ciudadId: 'mvd',
        ),
      );
      expect(r.total, 1);
      expect(r.porTipo, {
        TipoUbicacion.casa: 1,
        TipoUbicacion.negocio: 1,
        TipoUbicacion.edificio: 1,
      });
    });

    test('incluir bajas: aparecen marcadas como baja y no interactivas', () {
      final r = ArmadorListaUbicaciones.armar([
        ub('viva'),
        ub('baja', baja: true, minutos: 3),
      ], const ConsultaListaUbicaciones(colportorId: yo, incluirBajas: true));
      expect([for (final i in r.items) i.ubicacion.id], ['baja', 'viva']);
      expect([for (final i in r.items) i.esBaja], [true, false]);
      expect([for (final i in r.items) i.esInteractiva], [false, true]);
    });
  });

  group('búsqueda por calle + número', () {
    final todas = [
      ub('riv100', calle: 'Rivadavia', numero: '100'),
      ub('riv250', calle: 'Rivadavia', numero: '250'),
      ub('itl100', calle: 'Av. Italia', numero: '100'),
      ub('sin-calle', calle: null, numero: '7'),
      ub('sin-nada', calle: null, numero: null),
      ub('ñandú', calle: 'Ñandú', numero: '5'),
    ];

    List<String> busca(String? texto) =>
        ids(ConsultaListaUbicaciones(colportorId: yo, busqueda: texto), todas)..sort();

    test('substring de la calle', () => expect(busca('rivad'), ['riv100', 'riv250']));
    test('substring del número', () => expect(busca('100'), ['itl100', 'riv100']));
    test('calle + número juntos', () => expect(busca('rivadavia 25'), ['riv250']));
    test('palabras en cualquier orden', () => expect(busca('250 rivadavia'), ['riv250']));
    test('calle que coincide pero número que no: sin resultados', () {
      expect(busca('rivadavia 999'), isEmpty);
    });
    test('sin acentos ni mayúsculas', () => expect(busca('NANDU'), ['ñandú']));
    test('con acentos escritos', () => expect(busca('ñandú'), ['ñandú']));
    test('ubicaciones sin calle se buscan por número', () => expect(busca('7'), ['sin-calle']));
    test('vacía, en blanco o nula = sin búsqueda', () {
      expect(busca(''), hasLength(6));
      expect(busca('   '), hasLength(6));
      expect(busca(null), hasLength(6));
    });
  });

  group('posición y cercanía', () {
    final todas = [
      ub('lejos', metrosAlNorte: 900, minutos: 9),
      ub('cerca', metrosAlNorte: 50, minutos: 1),
      ub('medio', metrosAlNorte: 300, minutos: 5),
    ];

    test('cercanía: ascendente por distancia, con la distancia en metros', () {
      final r = ArmadorListaUbicaciones.armar(
        todas,
        const ConsultaListaUbicaciones(
          colportorId: yo,
          orden: OrdenListaUbicaciones.cercania,
          posicion: aqui,
        ),
      );
      expect([for (final i in r.items) i.ubicacion.id], ['cerca', 'medio', 'lejos']);
      expect(r.items[0].distanciaMetros, closeTo(50, 0.5));
      expect(r.items[2].distanciaMetros, closeTo(900, 1));
      expect(r.ordenAplicado, OrdenListaUbicaciones.cercania);
    });

    test('cercanía: empate de distancia por updated_at descendente', () {
      final r = ids(
        const ConsultaListaUbicaciones(
          colportorId: yo,
          orden: OrdenListaUbicaciones.cercania,
          posicion: aqui,
        ),
        [ub('vieja', metrosAlNorte: 100), ub('nueva', metrosAlNorte: 100, minutos: 4)],
      );
      expect(r, ['nueva', 'vieja']);
    });

    test('orden recientes con posición: mantiene la distancia en cada ítem', () {
      final r = ArmadorListaUbicaciones.armar(
        todas,
        const ConsultaListaUbicaciones(colportorId: yo, posicion: aqui),
      );
      expect([for (final i in r.items) i.ubicacion.id], ['lejos', 'medio', 'cerca']);
      expect(r.items.every((i) => i.distanciaMetros != null), isTrue);
      expect(r.ordenAplicado, OrdenListaUbicaciones.recientes);
    });

    test('cercanía sin GPS cae a recientes y lo dice', () {
      final r = ArmadorListaUbicaciones.armar(
        todas,
        const ConsultaListaUbicaciones(colportorId: yo, orden: OrdenListaUbicaciones.cercania),
      );
      expect([for (final i in r.items) i.ubicacion.id], ['lejos', 'medio', 'cerca']);
      expect(r.ordenAplicado, OrdenListaUbicaciones.recientes);
    });

    test('posición (0, 0) o fuera de rango cuenta como sin GPS', () {
      for (final p in const [Coordenadas(lat: 0, lon: 0), Coordenadas(lat: 91, lon: 0)]) {
        final r = ArmadorListaUbicaciones.armar(
          todas,
          ConsultaListaUbicaciones(
            colportorId: yo,
            orden: OrdenListaUbicaciones.cercania,
            posicion: p,
            radioMaxMetros: 10,
          ),
        );
        expect(r.total, 3, reason: '$p');
        expect(r.ordenAplicado, OrdenListaUbicaciones.recientes);
        expect(r.items.first.distanciaMetros, isNull);
      }
    });

    test('proximidad: solo las que están dentro del radio', () {
      expect(
        ids(
          const ConsultaListaUbicaciones(colportorId: yo, posicion: aqui, radioMaxMetros: 400),
          todas,
        ),
        ['medio', 'cerca'],
      );
    });

    test('el radio sin posición se ignora', () {
      expect(
        ids(const ConsultaListaUbicaciones(colportorId: yo, radioMaxMetros: 1), todas),
        hasLength(3),
      );
    });
  });

  group('paginación de 50', () {
    final muchas = [
      for (var i = 0; i < 120; i++) ub('u${i.toString().padLeft(3, '0')}', minutos: i),
    ];

    test('la primera página trae 50, el total 120 y hay más', () {
      final r = ArmadorListaUbicaciones.armar(muchas, consulta);
      expect(ConsultaListaUbicaciones.tamanoPagina, 50);
      expect(r.items, hasLength(50));
      expect(r.total, 120);
      expect(r.hayMas, isTrue);
      expect(r.items.first.ubicacion.id, 'u119');
    });

    test('pedir más: limite + 50 trae las 100 más recientes', () {
      final r = ArmadorListaUbicaciones.armar(
        muchas,
        const ConsultaListaUbicaciones(colportorId: yo, limite: 100),
      );
      expect(r.items, hasLength(100));
      expect(r.hayMas, isTrue);
    });

    test('la última página no tiene más', () {
      final r = ArmadorListaUbicaciones.armar(
        muchas,
        const ConsultaListaUbicaciones(colportorId: yo, limite: 150),
      );
      expect(r.items, hasLength(120));
      expect(r.hayMas, isFalse);
    });

    test('un límite negativo se trata como 0', () {
      final r = ArmadorListaUbicaciones.armar(
        muchas,
        const ConsultaListaUbicaciones(colportorId: yo, limite: -5),
      );
      expect(r.items, isEmpty);
      expect(r.total, 120);
    });
  });
}
