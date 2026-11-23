// `campaniaQueFrena` (HU-AUTH-008, #62): lo que lee quien frena la jornada y la venta desde un flujo que
// no es un widget (con un `ProviderContainer`, sin nadie escuchando el provider). Tiene que contestar
// igual que con una pantalla abierta.
import 'dart:async';

import 'package:colportores_mobile/features/auth/data/datasources/campanias_inscriptas_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/campanias_inscriptas_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/campanias_inscriptas_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Viernes 20/11/2026, 12:00 en Montevideo.
final _ahora = DateTime.utc(2026, 11, 20, 15);

const _porEmpezar = CampaniaInscripta(
  campaniaId: 'a',
  nombre: 'Verano 2027',
  fechaInicio: '2026-12-01',
);

const _enCurso = CampaniaInscripta(campaniaId: 'b', nombre: 'Primavera', fechaInicio: '2026-09-01');

final class _NuncaContesta implements CampaniasInscriptasDataSource {
  var cancelada = false;

  @override
  Stream<List<CampaniaInscripta>?> observar(String usuarioId) {
    final c = StreamController<List<CampaniaInscripta>?>(onCancel: () => cancelada = true);
    return c.stream;
  }
}

ProviderContainer _contenedor(CampaniasInscriptasDataSource fuente, {DateTime? ahora}) {
  final c = ProviderContainer(
    overrides: [
      campaniasInscriptasDataSourceProvider.overrideWithValue(fuente),
      relojCampaniaProvider.overrideWithValue(() => ahora ?? _ahora),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('con la campaña por empezar contesta cuál es, aunque nadie escuche el provider', () async {
    final c = _contenedor(CampaniasInscriptasEnMemoria([_porEmpezar]));

    final frena = await campaniaQueFrena(c.read, 'col-1');

    expect(frena?.nombre, 'Verano 2027');
    expect(frena?.diaYMes, '01/12');
  });

  test('con una campaña en curso, sin inscripciones o sin saber todavía: no frena', () async {
    expect(
      await campaniaQueFrena(
        _contenedor(CampaniasInscriptasEnMemoria([_enCurso, _porEmpezar])).read,
        'col-1',
      ),
      isNull,
    );
    expect(
      await campaniaQueFrena(_contenedor(CampaniasInscriptasEnMemoria()).read, 'col-1'),
      isNull,
    );
    expect(
      await campaniaQueFrena(_contenedor(CampaniasInscriptasEnMemoria(null)).read, 'col-1'),
      isNull,
    );
  });

  test('mira el día en cada lectura: el primer día de la campaña ya no frena', () async {
    var ahora = _ahora;
    final c = ProviderContainer(
      overrides: [
        campaniasInscriptasDataSourceProvider.overrideWithValue(
          CampaniasInscriptasEnMemoria([_porEmpezar]),
        ),
        relojCampaniaProvider.overrideWithValue(() => ahora),
      ],
    );
    addTearDown(c.dispose);

    expect(await campaniaQueFrena(c.read, 'col-1'), isNotNull);
    ahora = DateTime.utc(2026, 12, 1, 4);
    expect(await campaniaQueFrena(c.read, 'col-1'), isNull);
  });

  test('una lectura que falla no frena nada', () async {
    final fuente = CampaniasInscriptasEnMemoria()..falla = StateError('lectura rota');

    expect(await campaniaQueFrena(_contenedor(fuente).read, 'col-1'), isNull);
  });

  test(
    'una lectura que no contesta no traba: a los 3 s sigue sin frenar y cierra la suscripción',
    () async {
      final fuente = _NuncaContesta();
      final c = _contenedor(fuente);

      final frena = await campaniaQueFrena(c.read, 'col-1');

      expect(frena, isNull);
      expect(fuente.cancelada, isTrue);
    },
  );
}
