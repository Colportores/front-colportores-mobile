// Test de dominio: Dart puro (HU-UBI-002).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/consulta_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
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

  /// Las ubicaciones sin resumen (sin espacios ni estado): lo que ya cubrían los tests de la lista.
  ListaUbicaciones armar(Iterable<Ubicacion> todas, ConsultaListaUbicaciones c) =>
      ArmadorListaUbicaciones.armar([for (final u in todas) UbicacionConResumen(ubicacion: u)], c);

  List<String> ids(ConsultaListaUbicaciones c, List<Ubicacion> todas) => [
    for (final i in armar(todas, c).items) i.ubicacion.id,
  ];

  const consulta = ConsultaListaUbicaciones(colportorId: yo);

  group('lista base', () {
    test('sin ubicaciones: vacía, sin más páginas y con los tres tipos en 0', () {
      final r = armar(const [], consulta);
      expect(r.estaVacia, isTrue);
      expect(r.sinUbicaciones, isTrue);
      expect(r.sinResultados, isFalse);
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

    test('vacío contra sin resultados: con ubicaciones y filtros que no matchean no es "sin '
        'ubicaciones"', () {
      final todas = [ub('a'), ub('b', ciudad: 'sal')];
      for (final c in const [
        ConsultaListaUbicaciones(colportorId: yo, busqueda: 'inexistente'),
        ConsultaListaUbicaciones(colportorId: yo, ciudadId: 'otra'),
        ConsultaListaUbicaciones(colportorId: yo, tipos: {TipoUbicacion.edificio}),
      ]) {
        final r = armar(todas, c);
        expect(r.estaVacia, isTrue, reason: '$c');
        expect(r.sinUbicaciones, isFalse, reason: '$c');
        expect(r.sinResultados, isTrue, reason: '$c');
      }
      expect(armar(todas, consulta).sinResultados, isFalse);
    });

    test('las ubicaciones de otro colportor no cuentan como "tengo ubicaciones"', () {
      final r = armar([ub('ajena', dueno: 'col-2')], consulta);
      expect(r.sinUbicaciones, isTrue);
    });

    test('todas de baja: con "Mostrar bajas" apagado es sinUbicaciones; encendido, no', () {
      final bajas = [ub('a', baja: true), ub('b', baja: true)];
      final apagado = armar(bajas, consulta);
      expect(apagado.sinUbicaciones, isTrue);
      final encendido = armar(
        bajas,
        const ConsultaListaUbicaciones(colportorId: yo, incluirBajas: true),
      );
      expect(encendido.sinUbicaciones, isFalse);
      expect(encendido.total, 2);
    });

    test('las bajas con "Mostrar bajas" apagado no se listan pero se cuentan en bajasOcultas', () {
      final todas = [
        ub('viva'),
        ub('baja-1', baja: true),
        ub('baja-2', baja: true),
        ub('ajena-baja', baja: true, dueno: 'col-2'),
      ];
      final apagado = armar(todas, consulta);
      expect([for (final i in apagado.items) i.ubicacion.id], ['viva']);
      expect(apagado.bajasOcultas, 2);
      expect(apagado.soloBajas, isFalse);
      expect(apagado.totalBajas, 0);

      final encendido = armar(
        todas,
        const ConsultaListaUbicaciones(colportorId: yo, incluirBajas: true),
      );
      expect(encendido.total, 3);
      expect(encendido.bajasOcultas, 0);
      expect(encendido.totalBajas, 2);
    });

    test(
      'solo bajas con "Mostrar bajas" apagado es soloBajas; sin ninguna o con una activa, no',
      () {
        final soloBajas = armar([ub('a', baja: true), ub('b', baja: true)], consulta);
        expect(soloBajas.sinUbicaciones, isTrue);
        expect(soloBajas.bajasOcultas, 2);
        expect(soloBajas.soloBajas, isTrue);
        expect(soloBajas.items, isEmpty);

        final ninguna = armar(const [], consulta);
        expect(ninguna.sinUbicaciones, isTrue);
        expect(ninguna.soloBajas, isFalse);

        // Las bajas de otro colportor no cuentan: para este colportor no hay nada.
        final ajenas = armar([ub('a', baja: true, dueno: 'col-2')], consulta);
        expect(ajenas.soloBajas, isFalse);

        // Con «Mostrar bajas» encendido hay filas: ya no es el vacío.
        final encendido = armar([
          ub('a', baja: true),
        ], const ConsultaListaUbicaciones(colportorId: yo, incluirBajas: true));
        expect(encendido.soloBajas, isFalse);
      },
    );

    test('sin posición no hay distancias', () {
      final r = armar([ub('a')], consulta);
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
      final r = armar(
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
      final r = armar([
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
      final r = armar(
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
      final r = armar(todas, const ConsultaListaUbicaciones(colportorId: yo, posicion: aqui));
      expect([for (final i in r.items) i.ubicacion.id], ['lejos', 'medio', 'cerca']);
      expect(r.items.every((i) => i.distanciaMetros != null), isTrue);
      expect(r.ordenAplicado, OrdenListaUbicaciones.recientes);
    });

    test('cercanía sin GPS cae a recientes y lo dice', () {
      final r = armar(
        todas,
        const ConsultaListaUbicaciones(colportorId: yo, orden: OrdenListaUbicaciones.cercania),
      );
      expect([for (final i in r.items) i.ubicacion.id], ['lejos', 'medio', 'cerca']);
      expect(r.ordenAplicado, OrdenListaUbicaciones.recientes);
    });

    test('posición (0, 0) o fuera de rango cuenta como sin GPS', () {
      for (final p in const [Coordenadas(lat: 0, lon: 0), Coordenadas(lat: 91, lon: 0)]) {
        final r = armar(
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

    test('un radio cero, negativo o no finito no filtra (se ignora)', () {
      for (final radio in [0.0, -5.0, double.nan, double.infinity, double.negativeInfinity]) {
        expect(
          ids(
            ConsultaListaUbicaciones(colportorId: yo, posicion: aqui, radioMaxMetros: radio),
            todas,
          ),
          hasLength(3),
          reason: '$radio',
        );
      }
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
      final r = armar(muchas, consulta);
      expect(ConsultaListaUbicaciones.tamanoPagina, 50);
      expect(r.items, hasLength(50));
      expect(r.total, 120);
      expect(r.hayMas, isTrue);
      expect(r.items.first.ubicacion.id, 'u119');
    });

    test('pedir más: limite + 50 trae las 100 más recientes', () {
      final r = armar(muchas, const ConsultaListaUbicaciones(colportorId: yo, limite: 100));
      expect(r.items, hasLength(100));
      expect(r.hayMas, isTrue);
    });

    test('la última página no tiene más', () {
      final r = armar(muchas, const ConsultaListaUbicaciones(colportorId: yo, limite: 150));
      expect(r.items, hasLength(120));
      expect(r.hayMas, isFalse);
    });

    test('un límite negativo se trata como 0', () {
      final r = armar(muchas, const ConsultaListaUbicaciones(colportorId: yo, limite: -5));
      expect(r.items, isEmpty);
      expect(r.total, 120);
    });
  });

  group('resumen: espacios y estado de la casa', () {
    UbicacionConResumen fila(
      String id, {
      EstadoCasa? estado,
      int espacios = 1,
      TipoUbicacion tipo = TipoUbicacion.casa,
      bool baja = false,
      DateTime? entrevista,
      int minutos = 0,
    }) => UbicacionConResumen(
      ubicacion: ub(id, tipo: tipo, baja: baja, minutos: minutos),
      cantidadEspacios: espacios,
      estado: estado,
      proximaEntrevista: entrevista,
    );

    ListaUbicaciones armarFilas(List<UbicacionConResumen> filas, ConsultaListaUbicaciones c) =>
        ArmadorListaUbicaciones.armar(filas, c);

    test('cada fila lleva sus espacios, su estado y la hora de la entrevista', () {
      final entrevista = DateTime.utc(2026, 10, 8, 13);
      final r = armarFilas([
        fila('a', estado: EstadoCasa.entrevistaAgendada, espacios: 3, entrevista: entrevista),
      ], consulta);
      expect(r.items.single.cantidadEspacios, 3);
      expect(r.items.single.estado, EstadoCasa.entrevistaAgendada);
      expect(r.items.single.proximaEntrevista, entrevista);
    });

    test('filtrar por estado deja solo las que cumplen alguno de los pedidos', () {
      final r = armarFilas(
        [
          fila('cobra', estado: EstadoCasa.cobranzaPendiente, minutos: 3),
          fila('rechazo', estado: EstadoCasa.rechazo, minutos: 2),
          fila('nada', estado: EstadoCasa.sinVisita, minutos: 1),
        ],
        const ConsultaListaUbicaciones(
          colportorId: yo,
          estados: {EstadoCasa.cobranzaPendiente, EstadoCasa.rechazo},
        ),
      );
      expect([for (final i in r.items) i.ubicacion.id], ['cobra', 'rechazo']);
      expect(r.total, 2);
    });

    test('con un estado pedido, una ubicación de estado desconocido no entra', () {
      final r = armarFilas([
        fila('sabida', estado: EstadoCasa.rechazo),
        fila('desconocida'),
      ], const ConsultaListaUbicaciones(colportorId: yo, estados: {EstadoCasa.rechazo}));
      expect([for (final i in r.items) i.ubicacion.id], ['sabida']);
    });

    test('sin estado pedido entran todas, también las de estado desconocido', () {
      final r = armarFilas([fila('sabida', estado: EstadoCasa.rechazo), fila('x')], consulta);
      expect(r.total, 2);
    });

    test('tipo y estado se combinan con Y', () {
      final r = armarFilas(
        [
          fila('casa-cobra', estado: EstadoCasa.cobranzaPendiente),
          fila('neg-cobra', estado: EstadoCasa.cobranzaPendiente, tipo: TipoUbicacion.negocio),
          fila('casa-rechazo', estado: EstadoCasa.rechazo),
        ],
        const ConsultaListaUbicaciones(
          colportorId: yo,
          tipos: {TipoUbicacion.casa},
          estados: {EstadoCasa.cobranzaPendiente},
        ),
      );
      expect([for (final i in r.items) i.ubicacion.id], ['casa-cobra']);
    });

    test(
      'cada contador cuenta con los demás filtros aplicados («Casa 8» = casas con cobranza)',
      () {
        final filas = [
          fila('c1', estado: EstadoCasa.cobranzaPendiente),
          fila('c2', estado: EstadoCasa.cobranzaPendiente),
          fila('c3', estado: EstadoCasa.rechazo),
          fila('n1', estado: EstadoCasa.cobranzaPendiente, tipo: TipoUbicacion.negocio),
          fila('n2', estado: EstadoCasa.rechazo, tipo: TipoUbicacion.negocio),
          fila('e1', estado: EstadoCasa.sinVisita, tipo: TipoUbicacion.edificio),
        ];
        // Tipo = Casa y estado = cobranza pendiente.
        final r = armarFilas(
          filas,
          const ConsultaListaUbicaciones(
            colportorId: yo,
            tipos: {TipoUbicacion.casa},
            estados: {EstadoCasa.cobranzaPendiente},
          ),
        );
        expect(r.total, 2);
        // Por tipo: respeta el estado (cobranza), no el tipo.
        expect(r.porTipo, {
          TipoUbicacion.casa: 2,
          TipoUbicacion.negocio: 1,
          TipoUbicacion.edificio: 0,
        });
        // Por estado: respeta el tipo (casa), no el estado.
        expect(r.porEstado[EstadoCasa.cobranzaPendiente], 2);
        expect(r.porEstado[EstadoCasa.rechazo], 1);
        expect(r.porEstado[EstadoCasa.sinVisita], 0);
        expect(r.porEstado.keys, EstadoCasa.values);
      },
    );

    test('los contadores por estado no cuentan las de estado desconocido', () {
      final r = armarFilas([fila('x'), fila('y', estado: EstadoCasa.rechazo)], consulta);
      expect(r.porEstado[EstadoCasa.rechazo], 1);
      expect(r.porEstado.values.fold<int>(0, (a, b) => a + b), 1);
    });

    test('los contadores también respetan las bajas', () {
      final filas = [
        fila('viva', estado: EstadoCasa.rechazo),
        fila('baja', estado: EstadoCasa.rechazo, baja: true),
      ];
      expect(armarFilas(filas, consulta).porEstado[EstadoCasa.rechazo], 1);
      final conBajas = armarFilas(
        filas,
        const ConsultaListaUbicaciones(colportorId: yo, incluirBajas: true),
      );
      expect(conBajas.porEstado[EstadoCasa.rechazo], 2);
    });

    test('estadosConocidos es true si alguna del colportor trae estado', () {
      expect(armarFilas([fila('x')], consulta).estadosConocidos, isFalse);
      expect(armarFilas(const [], consulta).estadosConocidos, isFalse);
      expect(
        armarFilas([fila('x'), fila('y', estado: EstadoCasa.sinVisita)], consulta).estadosConocidos,
        isTrue,
      );
    });

    test('estadosConocidos ignora las ubicaciones de otro colportor', () {
      final ajena = UbicacionConResumen(
        ubicacion: ub('ajena', dueno: 'col-2'),
        estado: EstadoCasa.rechazo,
      );
      expect(ArmadorListaUbicaciones.armar([ajena], consulta).estadosConocidos, isFalse);
    });

    test('totalGeneral cuenta las del colportor sin filtros y totalBajas las de baja', () {
      final filas = [fila('a'), fila('b', tipo: TipoUbicacion.negocio), fila('c', baja: true)];
      final sinBajas = armarFilas(
        filas,
        const ConsultaListaUbicaciones(colportorId: yo, tipos: {TipoUbicacion.negocio}),
      );
      expect(sinBajas.total, 1);
      expect(sinBajas.totalGeneral, 2);
      expect(sinBajas.totalBajas, 0);

      final conBajas = armarFilas(
        filas,
        const ConsultaListaUbicaciones(
          colportorId: yo,
          tipos: {TipoUbicacion.negocio},
          incluirBajas: true,
        ),
      );
      expect(conBajas.total, 1);
      expect(conBajas.totalGeneral, 3);
      expect(conBajas.totalBajas, 1);
    });

    test('lo ajeno no entra en los totales', () {
      final r = ArmadorListaUbicaciones.armar([
        UbicacionConResumen(ubicacion: ub('mia')),
        UbicacionConResumen(ubicacion: ub('ajena', dueno: 'col-2')),
      ], consulta);
      expect(r.totalGeneral, 1);
    });
  });
}
