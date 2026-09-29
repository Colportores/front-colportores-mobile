// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'dart:math' as math;

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:test/test.dart';

/// Metros → grados de latitud con el radio de la Tierra de `Coordenadas`.
double _grados(double metros) => metros / 111195.08;

Ubicacion _ubicacion({
  String id = 'ub-existente',
  String? calle = 'Av. Italia',
  String? numero = '1234',
  double metrosAlNorte = 0,
  double lon = -56.125,
  String ciudadId = 'mvd',
  DateTime? creada,
  DateTime? deletedAt,
}) => Ubicacion(
  id: id,
  tipo: TipoUbicacion.casa,
  calle: calle,
  numero: numero,
  lat: -34.891 + _grados(metrosAlNorte),
  lon: lon,
  ciudadId: ciudadId,
  auditoria: Auditoria(
    createdAt: creada ?? DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    deletedAt: deletedAt,
  ),
);

void main() {
  const criterio = CriterioDuplicadoUbicacion();
  const conD1a = CriterioDuplicadoUbicacion(mismaDireccionAdmiteConservarAmbos: false);
  final nueva = _ubicacion(id: 'ub-nueva');

  group('CriterioDuplicadoUbicacion.comparar — misma dirección', () {
    test('dado la misma calle, número y ciudad a 200 m, cuando se compara, es candidata por misma '
        'dirección a esa distancia', () {
      final existente = _ubicacion(metrosAlNorte: 200);

      final candidata = criterio.comparar(nueva, existente)!;

      expect(candidata.ubicacion, existente);
      expect(candidata.motivo, MotivoDuplicado.mismaDireccion);
      expect(candidata.distanciaMetros, closeTo(200, 0.01));
    });

    test('dado mayúsculas y espacios en los bordes distintos, cuando se compara, es la misma '
        'dirección', () {
      final existente = _ubicacion(calle: '  AV. ITALIA ', numero: ' 1234 ', metrosAlNorte: 200);

      expect(criterio.comparar(nueva, existente)?.motivo, MotivoDuplicado.mismaDireccion);
    });

    test('dado espacios internos o acentos distintos, cuando se compara, no es la misma dirección '
        '(solo trim y minúsculas, como el índice de la opción (a) de D1)', () {
      expect(
        criterio.comparar(nueva, _ubicacion(calle: 'Av.  Italia', metrosAlNorte: 200)),
        isNull,
      );
      expect(criterio.comparar(nueva, _ubicacion(calle: 'Av. Itália', metrosAlNorte: 200)), isNull);
    });

    test(
      'dado la misma calle y número en otra ciudad, cuando se compara lejos, no es candidata',
      () {
        final otraCiudad = _ubicacion(ciudadId: 'canelones', metrosAlNorte: 200);

        expect(criterio.comparar(nueva, otraCiudad), isNull);
      },
    );

    test('dado otro número en la misma calle, cuando se compara lejos, no es candidata', () {
      expect(criterio.comparar(nueva, _ubicacion(numero: '1236', metrosAlNorte: 200)), isNull);
    });

    test('dado que a una de las dos le falta la calle o el número (o está en blanco), cuando se '
        'compara lejos, no es candidata: solo cuenta la distancia', () {
      expect(criterio.comparar(nueva, _ubicacion(calle: null, metrosAlNorte: 200)), isNull);
      expect(criterio.comparar(nueva, _ubicacion(numero: null, metrosAlNorte: 200)), isNull);
      expect(criterio.comparar(nueva, _ubicacion(calle: '   ', metrosAlNorte: 200)), isNull);
      final sinDireccion = _ubicacion(id: 'n', calle: null, numero: null);
      expect(criterio.comparar(sinDireccion, _ubicacion(calle: null, metrosAlNorte: 200)), isNull);
    });
  });

  group('CriterioDuplicadoUbicacion.comparar — cercanía', () {
    test('dado otra dirección a 4 m, cuando se compara, es candidata por cercanía', () {
      final existente = _ubicacion(calle: 'Comercio', numero: '10', metrosAlNorte: 4);

      final candidata = criterio.comparar(nueva, existente)!;

      expect(candidata.motivo, MotivoDuplicado.cercania);
      expect(candidata.distanciaMetros, closeTo(4, 0.01));
    });

    test('dado otra dirección a 4,99 m, a 5,01 m y a 6 m, cuando se compara, solo la primera es '
        'candidata ("a menos de 5 m")', () {
      Ubicacion a(double metros) => _ubicacion(calle: 'Comercio', metrosAlNorte: metros);

      expect(criterio.comparar(nueva, a(4.99)), isNotNull);
      expect(criterio.comparar(nueva, a(5.01)), isNull);
      expect(criterio.comparar(nueva, a(6)), isNull);
    });

    test('dado otra ciudad a 3 m, cuando se compara, es candidata por cercanía (la distancia no '
        'mira la ciudad)', () {
      final otraCiudad = _ubicacion(ciudadId: 'canelones', metrosAlNorte: 3);

      expect(criterio.comparar(nueva, otraCiudad)?.motivo, MotivoDuplicado.cercania);
    });

    test('dado que a las dos les falta la dirección, cuando están a 3 m, es candidata por '
        'cercanía', () {
      final sinDireccion = _ubicacion(id: 'n', calle: null, numero: null);

      final candidata = criterio.comparar(sinDireccion, _ubicacion(calle: null, metrosAlNorte: 3));

      expect(candidata?.motivo, MotivoDuplicado.cercania);
    });

    test('dado la misma dirección a 2 m, cuando se compara, cuenta como misma dirección', () {
      expect(
        criterio.comparar(nueva, _ubicacion(metrosAlNorte: 2))?.motivo,
        MotivoDuplicado.mismaDireccion,
      );
    });
  });

  group('CriterioDuplicadoUbicacion.comparar — exclusiones', () {
    test('dado una existente dada de baja, cuando se compara, no es candidata', () {
      final deBaja = _ubicacion(metrosAlNorte: 1, deletedAt: DateTime.utc(2026, 9, 2));

      expect(criterio.comparar(nueva, deBaja), isNull);
    });

    test('dado la misma ubicación (mismo id), cuando se compara, no es candidata', () {
      expect(criterio.comparar(nueva, _ubicacion(id: 'ub-nueva')), isNull);
    });
  });

  group('CriterioDuplicadoUbicacion — decisión D1 (conservar ambos con la misma dirección)', () {
    test('dado el criterio por defecto, cuando hay una candidata por misma dirección, admite '
        'conservar ambos (hoy: opción (c) de D1)', () {
      expect(CriterioDuplicadoUbicacion.mismaDireccionAdmiteConservarAmbosPorDefecto, isTrue);
      expect(
        criterio.comparar(nueva, _ubicacion(metrosAlNorte: 200))!.admiteConservarAmbos,
        isTrue,
      );
      expect(criterio.alSeguirIgual, isNull);
      expect(criterio.esSeguirIgual, isFalse);
    });

    test('dado D1 en la opción (a), cuando hay candidatas, la de misma dirección no admite '
        'conservar ambos y la de cercanía sí', () {
      final mismaDireccion = conD1a.comparar(nueva, _ubicacion(metrosAlNorte: 200))!;
      final cercana = conD1a.comparar(nueva, _ubicacion(calle: 'Comercio', metrosAlNorte: 3))!;

      expect(mismaDireccion.admiteConservarAmbos, isFalse);
      expect(cercana.admiteConservarAmbos, isTrue);
    });

    test('dado D1 en la opción (a), cuando el colportor sigue igual, solo frenan las de misma '
        'dirección', () {
      final alSeguir = conD1a.alSeguirIgual!;
      final mismaDireccion = _ubicacion(id: 'misma', metrosAlNorte: 200);
      final cercana = _ubicacion(id: 'cerca', calle: 'Comercio', metrosAlNorte: 3);

      expect(alSeguir.esSeguirIgual, isTrue);
      expect(alSeguir.candidatas(nueva, [mismaDireccion, cercana]).map((c) => c.ubicacion.id), [
        'misma',
      ]);
    });
  });

  group('CriterioDuplicadoUbicacion.candidatas', () {
    test('dado varias existentes, cuando se buscan candidatas, devuelve solo las candidatas de la '
        'más cercana a la más lejana', () {
      final misma200 = _ubicacion(id: 'misma200', metrosAlNorte: 200);
      final cerca3 = _ubicacion(id: 'cerca3', calle: 'Comercio', metrosAlNorte: 3);
      final cerca1 = _ubicacion(id: 'cerca1', calle: null, metrosAlNorte: 1);
      final lejos = _ubicacion(id: 'lejos', calle: 'Comercio', metrosAlNorte: 80);

      expect(
        criterio.candidatas(nueva, [misma200, lejos, cerca3, cerca1]).map((c) => c.ubicacion.id),
        ['cerca1', 'cerca3', 'misma200'],
      );
    });
  });

  group('CriterioDuplicadoUbicacion.pares', () {
    List<String> claves(List<ParDuplicado> pares) => [for (final p in pares) p.clave];

    test('dado dos con la misma dirección a 200 m, cuando se escanea, hay un par por misma '
        'dirección con la más vieja como A', () {
      final nueva = _ubicacion(id: 'x-nueva', metrosAlNorte: 200, creada: DateTime.utc(2026, 9, 5));
      final vieja = _ubicacion(id: 'y-vieja', creada: DateTime.utc(2026, 9, 1));

      final par = criterio.pares([nueva, vieja]).single;

      expect(par.a, vieja);
      expect(par.b, nueva);
      expect(par.motivo, MotivoDuplicado.mismaDireccion);
      expect(par.distanciaMetros, closeTo(200, 0.01));
      expect(par.admiteConservarAmbos, isTrue);
    });

    test('dado dos creadas en el mismo instante, cuando se escanea, A es la de id menor', () {
      final par = criterio.pares([
        _ubicacion(id: 'b'),
        _ubicacion(id: 'a', metrosAlNorte: 1),
      ]).single;

      expect(par.a.id, 'a');
    });

    test('dado tres con la misma dirección, cuando se escanea, aparecen los tres pares una sola '
        'vez cada uno', () {
      final pares = criterio.pares([
        _ubicacion(id: 'a', metrosAlNorte: 0),
        _ubicacion(id: 'b', metrosAlNorte: 100),
        _ubicacion(id: 'c', metrosAlNorte: 300),
      ]);

      expect(claves(pares), unorderedEquals(['a|b', 'a|c', 'b|c']));
    });

    test('dado puntos cada 3 m sobre una línea con direcciones distintas, cuando se escanea, solo '
        'se aparean los vecinos (a 6 m ya no)', () {
      final pares = criterio.pares([
        for (var i = 0; i < 4; i++)
          _ubicacion(id: 'p$i', calle: 'Calle $i', metrosAlNorte: 3.0 * i),
      ]);

      expect(claves(pares), unorderedEquals(['p0|p1', 'p1|p2', 'p2|p3']));
      expect(pares.every((p) => p.motivo == MotivoDuplicado.cercania), isTrue);
    });

    test('dado un par que cumple las dos reglas, cuando se escanea, aparece una vez y por misma '
        'dirección', () {
      final pares = criterio.pares([_ubicacion(id: 'a'), _ubicacion(id: 'b', metrosAlNorte: 2)]);

      expect(pares, hasLength(1));
      expect(pares.single.motivo, MotivoDuplicado.mismaDireccion);
    });

    test(
      'dado un par con una baja, cuando se escanea, no se reporta (las bajas no participan)',
      () {
        final pares = criterio.pares([
          _ubicacion(id: 'a'),
          _ubicacion(id: 'b', metrosAlNorte: 1, deletedAt: DateTime.utc(2026, 9, 2)),
        ]);

        expect(pares, isEmpty);
      },
    );

    test('dado pares por los dos motivos, cuando se escanea, primero los de misma dirección y '
        'después los de cercanía, cada grupo del más cercano al más lejano', () {
      final pares = criterio.pares([
        _ubicacion(id: 'm1', metrosAlNorte: 0),
        _ubicacion(id: 'm2', metrosAlNorte: 50),
        _ubicacion(id: 'n1', numero: '99', metrosAlNorte: 1000),
        _ubicacion(id: 'n2', numero: '99', metrosAlNorte: 1010),
        _ubicacion(id: 'c1', calle: 'Uno', metrosAlNorte: 2000),
        _ubicacion(id: 'c2', calle: 'Dos', metrosAlNorte: 2004),
        _ubicacion(id: 'd1', calle: 'Tres', metrosAlNorte: 3000),
        _ubicacion(id: 'd2', calle: 'Cuatro', metrosAlNorte: 3001),
      ]);

      expect(claves(pares), ['n1|n2', 'm1|m2', 'd1|d2', 'c1|c2']);
    });

    test('dado D1 en la opción (a), cuando se escanea, el par de misma dirección no admite '
        'conservar ambos', () {
      final par = conD1a.pares([
        _ubicacion(id: 'a'),
        _ubicacion(id: 'b', metrosAlNorte: 100),
      ]).single;

      expect(par.admiteConservarAmbos, isFalse);
    });

    test('dado muchas ubicaciones al azar, cuando se escanea, da los mismos pares que comparar '
        'todas contra todas', () {
      final azar = math.Random(207);
      const calles = ['Uno', 'Dos', 'Tres', null];
      final ubicaciones = [
        for (var i = 0; i < 80; i++)
          _ubicacion(
            id: 'u${i.toString().padLeft(2, '0')}',
            calle: calles[azar.nextInt(calles.length)],
            numero: '${azar.nextInt(3)}',
            ciudadId: azar.nextBool() ? 'mvd' : 'canelones',
            metrosAlNorte: azar.nextDouble() * 40,
            lon: -56.125 + azar.nextDouble() * 0.0004,
            deletedAt: azar.nextInt(10) == 0 ? DateTime.utc(2026, 9, 2) : null,
          ),
      ];
      final esperadas = <String>{
        for (final (i, x) in ubicaciones.indexed)
          for (final y in ubicaciones.skip(i + 1))
            if (!x.estaBorrada && criterio.comparar(x, y) != null) ParDuplicado.claveDe(x.id, y.id),
      };

      final pares = criterio.pares(ubicaciones);

      expect(esperadas, isNotEmpty);
      expect(claves(pares).toSet(), esperadas);
      expect(pares, hasLength(esperadas.length));
    });
  });

  group('ParDuplicado.clave', () {
    test('dado dos id en cualquier orden, cuando se arma la clave, es la misma', () {
      expect(ParDuplicado.claveDe('b', 'a'), ParDuplicado.claveDe('a', 'b'));
      expect(ParDuplicado.claveDe('a', 'b'), 'a|b');
    });
  });

  group('CriterioDuplicadoUbicacion — normalización', () {
    test('dado una calle o número, cuando se normaliza para duplicados, queda sin espacios en los '
        'bordes y en minúsculas', () {
      expect(CriterioDuplicadoUbicacion.normalizarDireccion('  Av. ÑANDÚ  '), 'av. ñandú');
    });

    test('dado un texto con acentos, ñ y espacios de más, cuando se normaliza para buscar, queda '
        'plano', () {
      expect(
        CriterioDuplicadoUbicacion.normalizar('  Güemes   Ñandubay  Él '),
        'guemes nandubay el',
      );
    });
  });
}
