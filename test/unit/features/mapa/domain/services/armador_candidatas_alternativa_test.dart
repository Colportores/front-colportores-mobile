import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/armador_candidatas_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:test/test.dart';

import '../../../../../helpers/ubicacion_alternativa_falsos.dart';

void main() {
  // El selector de la ubicación alternativa (vista 22A·02 a 22A·05): busca y ordena.
  final italia = ubicacionParaAlternativa('ub-2', lat: -34.870, lon: -56.170);
  final mataojo = ubicacionParaAlternativa(
    'ub-3',
    calle: 'Mataojo',
    numero: '2051',
    tipo: TipoUbicacion.casa,
    lat: -34.8905,
    lon: -56.1605,
  );
  final rambla = ubicacionParaAlternativa(
    'ub-4',
    calle: 'Rambla Gandhi',
    numero: '470',
    tipo: TipoUbicacion.edificio,
    lat: -34.92,
    lon: -56.15,
  );
  const aqui = Coordenadas(lat: -34.89, lon: -56.16);

  group('dado el selector de la ubicación alternativa', () {
    test('cuando no hay GPS, entonces van por dirección y sin distancia', () {
      final lista = ArmadorCandidatasAlternativa.armar([rambla, italia, mataojo]);
      expect(lista.items.map((c) => c.ubicacion.id), ['ub-2', 'ub-3', 'ub-4']);
      expect(lista.items.every((c) => c.distanciaMetros == null), isTrue);
      expect(lista.porCercania, isFalse);
      expect(lista.hayCandidatas, isTrue);
    });

    test('cuando hay GPS, entonces van por cercanía y cada una trae su distancia', () {
      final lista = ArmadorCandidatasAlternativa.armar([rambla, italia, mataojo], posicion: aqui);
      expect(lista.items.map((c) => c.ubicacion.id), ['ub-3', 'ub-2', 'ub-4']);
      expect(lista.items.every((c) => c.distanciaMetros != null), isTrue);
      expect(lista.items.first.distanciaMetros, lessThan(lista.items.last.distanciaMetros!));
      expect(lista.porCercania, isTrue);
    });

    test('cuando el GPS es (0, 0) o está fuera de rango, entonces es como no tenerlo', () {
      final cero = ArmadorCandidatasAlternativa.armar([
        italia,
      ], posicion: const Coordenadas(lat: 0, lon: 0));
      final fuera = ArmadorCandidatasAlternativa.armar([
        italia,
      ], posicion: const Coordenadas(lat: 95, lon: 0));
      expect(cero.porCercania, isFalse);
      expect(cero.items.single.distanciaMetros, isNull);
      expect(fuera.porCercania, isFalse);
    });

    test('cuando dos están a la misma distancia, entonces desempata por dirección y por id', () {
      final a = ubicacionParaAlternativa('ub-9', calle: 'Zeta', numero: '1');
      final b = ubicacionParaAlternativa('ub-8', calle: 'Alfa', numero: '1');
      final lista = ArmadorCandidatasAlternativa.armar([a, b], posicion: aqui);
      expect(lista.items.map((c) => c.ubicacion.id), ['ub-8', 'ub-9']);
    });

    test('cuando busca, entonces cada palabra tiene que estar, sin acentos ni mayúsculas', () {
      final todas = [italia, mataojo, rambla];
      expect(
        ArmadorCandidatasAlternativa.armar(
          todas,
          busqueda: 'AV italia',
        ).items.map((c) => c.ubicacion.id),
        ['ub-2'],
      );
      expect(
        ArmadorCandidatasAlternativa.armar(
          todas,
          busqueda: '2051',
        ).items.map((c) => c.ubicacion.id),
        ['ub-3'],
      );
      expect(
        ArmadorCandidatasAlternativa.armar(
          todas,
          busqueda: 'gándhi 470',
        ).items.map((c) => c.ubicacion.id),
        ['ub-4'],
      );
      // El tipo hace de «nombre»: la ubicación no tiene otro.
      expect(
        ArmadorCandidatasAlternativa.armar(
          todas,
          busqueda: 'negocio',
        ).items.map((c) => c.ubicacion.id),
        ['ub-2'],
      );
      expect(ArmadorCandidatasAlternativa.armar(todas, busqueda: '   ').items, hasLength(3));
    });

    test('cuando nada coincide, entonces hay candidatas pero la lista sale vacía (22A·05)', () {
      final lista = ArmadorCandidatasAlternativa.armar([
        italia,
        mataojo,
      ], busqueda: 'Bulevar Artigas');
      expect(lista.items, isEmpty);
      expect(lista.hayCandidatas, isTrue);
    });

    test('cuando no hay ninguna ubicación para elegir, entonces es el vacío (22A·04)', () {
      final lista = ArmadorCandidatasAlternativa.armar(const []);
      expect(lista.items, isEmpty);
      expect(lista.hayCandidatas, isFalse);
      // Buscar en una lista vacía no cambia lo que es.
      expect(ArmadorCandidatasAlternativa.armar(const [], busqueda: 'x').hayCandidatas, isFalse);
    });

    test(
      'cuando una no tiene calle ni número, entonces igual se lista y se puede buscar por tipo',
      () {
        final sinDireccion = ubicacionParaAlternativa(
          'ub-5',
          calle: null,
          numero: null,
          tipo: TipoUbicacion.casa,
        );
        final lista = ArmadorCandidatasAlternativa.armar([sinDireccion, italia], busqueda: 'casa');
        expect(lista.items.map((c) => c.ubicacion.id), ['ub-5']);
      },
    );

    test('cuando son muchas, entonces se arman todas sin cortar', () {
      final muchas = [
        for (var i = 0; i < 300; i++)
          ubicacionParaAlternativa('ub-m$i', numero: '$i', lat: -34.89 + i * .0001),
      ];
      final lista = ArmadorCandidatasAlternativa.armar(muchas, posicion: aqui);
      expect(lista.items, hasLength(300));
      expect(lista.items.first.ubicacion.id, 'ub-m0');
    });
  });
}
