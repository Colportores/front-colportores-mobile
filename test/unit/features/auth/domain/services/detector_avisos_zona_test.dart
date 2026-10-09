// El aviso de zona (HU-CAM-006, #251): cuándo el teléfono le dice al colportor «Te asignaron la zona
// <zona> en <campaña>.» o «Ya no tenés zona en <campaña>.», y cuándo calla. Es una función de lo que
// el teléfono tiene y de lo que ya avisó, así que no depende de cuántas veces llegó el pull.
import 'package:colportores_mobile/features/auth/domain/entities/aviso_zona.dart';
import 'package:colportores_mobile/features/auth/domain/entities/inscripcion_con_zona.dart';
import 'package:colportores_mobile/features/auth/domain/services/detector_avisos_zona.dart';
import 'package:flutter_test/flutter_test.dart';

InscripcionConZona _inscripcion({
  String id = 'insc-1',
  String campania = 'Campaña Primavera 2026',
  String? zonaId,
  String? zonaNombre,
  bool dadaDeBaja = false,
}) => InscripcionConZona(
  id: id,
  campaniaId: 'camp-$id',
  campaniaNombre: campania,
  zonaId: zonaId,
  zonaNombre: zonaNombre,
  dadaDeBaja: dadaDeBaja,
);

ResultadoAvisosZona _detectar(
  List<InscripcionConZona> actuales, {
  Map<String, String?> avisadas = const {},
}) => DetectorAvisosZona.detectar(avisadas: avisadas, actuales: actuales);

void main() {
  group('te asignaron una zona', () {
    test('dado que la inscripción tenía otra zona avisada, cuando llega la nueva, avisa la nueva '
        'con los nombres de la campaña y de la zona', () {
      final resultado = _detectar(
        [_inscripcion(zonaId: 'z-centro', zonaNombre: 'Centro')],
        avisadas: {'insc-1': 'z-norte'},
      );

      expect(resultado.avisos, [
        const ZonaAsignada(
          inscripcionId: 'insc-1',
          campaniaNombre: 'Campaña Primavera 2026',
          zonaId: 'z-centro',
          zonaNombre: 'Centro',
        ),
      ]);
      expect(resultado.silenciosas, isEmpty);
    });

    test('dado que estaba sin zona, cuando le asignan una, avisa', () {
      final resultado = _detectar(
        [_inscripcion(zonaId: 'z-centro', zonaNombre: 'Centro')],
        avisadas: {'insc-1': null},
      );

      expect(resultado.avisos.single, isA<ZonaAsignada>());
    });

    test('dado que el teléfono nunca vio la inscripción y ya trae zona (primer pull, o app '
        'reinstalada), avisa: es la zona que tiene hoy', () {
      final resultado = _detectar([_inscripcion(zonaId: 'z-centro', zonaNombre: 'Centro')]);

      expect(resultado.avisos.single, isA<ZonaAsignada>());
    });

    test('dado que la zona es la misma que ya se avisó, calla (dos pulls con el mismo cambio '
        'avisan una sola vez)', () {
      final resultado = _detectar(
        [_inscripcion(zonaId: 'z-centro', zonaNombre: 'Centro')],
        avisadas: {'insc-1': 'z-centro'},
      );

      expect(resultado.avisos, isEmpty);
      expect(resultado.silenciosas, isEmpty);
    });

    test('dado que cambia solo el nombre de la zona (la renombró el coordinador), calla: la zona '
        'es la misma', () {
      final resultado = _detectar(
        [_inscripcion(zonaId: 'z-centro', zonaNombre: 'Centro histórico')],
        avisadas: {'insc-1': 'z-centro'},
      );

      expect(resultado.avisos, isEmpty);
    });

    test('dado que la zona vuelve a ser la que ya se avisó antes de pasar por otra, avisa cada '
        'cambio (se compara contra la última avisada)', () {
      final primero = _detectar(
        [_inscripcion(zonaId: 'z-norte', zonaNombre: 'Norte')],
        avisadas: {'insc-1': 'z-centro'},
      );
      expect(primero.avisos.single, isA<ZonaAsignada>());

      final despues = _detectar(
        [_inscripcion(zonaId: 'z-centro', zonaNombre: 'Centro')],
        avisadas: {'insc-1': 'z-norte'},
      );
      expect(despues.avisos.single, isA<ZonaAsignada>());
    });

    test('el nombre se limpia de espacios alrededor', () {
      final resultado = _detectar([
        _inscripcion(campania: '  Primavera  ', zonaId: 'z', zonaNombre: ' Centro \n'),
      ]);

      expect(
        resultado.avisos.single,
        const ZonaAsignada(
          inscripcionId: 'insc-1',
          campaniaNombre: 'Primavera',
          zonaId: 'z',
          zonaNombre: 'Centro',
        ),
      );
    });

    for (final (nombre, zonaNombre) in const [
      ('todavía no llegó a la réplica', null),
      ('viene vacío', ''),
      ('viene en blanco', '   '),
    ]) {
      test('dado que el nombre de la zona $nombre, no avisa ni anota nada: espera al próximo '
          'pull, sin inventar un nombre', () {
        final resultado = _detectar([_inscripcion(zonaId: 'z-centro', zonaNombre: zonaNombre)]);

        expect(resultado.avisos, isEmpty);
        expect(resultado.silenciosas, isEmpty);
      });
    }

    test('dado que la campaña no tiene nombre, no avisa ni anota nada', () {
      final resultado = _detectar([
        _inscripcion(campania: ' ', zonaId: 'z-centro', zonaNombre: 'Centro'),
      ]);

      expect(resultado.avisos, isEmpty);
      expect(resultado.silenciosas, isEmpty);
    });
  });

  group('ya no tenés zona', () {
    test('dado que tenía una zona avisada y sigue inscripto sin zona («Quitar»), avisa con el '
        'nombre de la campaña', () {
      final resultado = _detectar([_inscripcion()], avisadas: {'insc-1': 'z-centro'});

      expect(resultado.avisos, [
        const ZonaQuitada(inscripcionId: 'insc-1', campaniaNombre: 'Campaña Primavera 2026'),
      ]);
      expect(resultado.silenciosas, isEmpty);
    });

    test('dado que ya se avisó que quedó sin zona, calla', () {
      final resultado = _detectar([_inscripcion()], avisadas: {'insc-1': null});

      expect(resultado.avisos, isEmpty);
      expect(resultado.silenciosas, isEmpty);
    });

    test('dado que el teléfono nunca vio la inscripción y no trae zona (alta sin zona), no avisa '
        'y la anota sin zona: la primera zona que le asignen sí es un cambio', () {
      final resultado = _detectar([_inscripcion()]);

      expect(resultado.avisos, isEmpty);
      expect(resultado.silenciosas, {'insc-1': null});

      final despues = _detectar([
        _inscripcion(zonaId: 'z-centro', zonaNombre: 'Centro'),
      ], avisadas: resultado.silenciosas);
      expect(despues.avisos.single, isA<ZonaAsignada>());
    });

    test('dado que la campaña no tiene nombre, no avisa que quedó sin zona', () {
      final resultado = _detectar([_inscripcion(campania: '')], avisadas: {'insc-1': 'z-centro'});

      expect(resultado.avisos, isEmpty);
    });
  });

  group('lo sacaron de la campaña (la inscripción llega dada de baja)', () {
    test('dado que tenía una zona avisada, no avisa «Ya no tenés zona»: alcanza con la '
        'notificación de remoción; anota sin zona', () {
      final resultado = _detectar(
        [_inscripcion(dadaDeBaja: true)],
        avisadas: {'insc-1': 'z-centro'},
      );

      expect(resultado.avisos, isEmpty);
      expect(resultado.silenciosas, {'insc-1': null});
    });

    test('dado que la baja todavía trae la zona, tampoco avisa «Te asignaron»', () {
      final resultado = _detectar([
        _inscripcion(zonaId: 'z-centro', zonaNombre: 'Centro', dadaDeBaja: true),
      ]);

      expect(resultado.avisos, isEmpty);
      expect(resultado.silenciosas, {'insc-1': null});
    });

    test('dado que ya estaba anotada sin zona, no hay nada que anotar', () {
      final resultado = _detectar([_inscripcion(dadaDeBaja: true)], avisadas: {'insc-1': null});

      expect(resultado.avisos, isEmpty);
      expect(resultado.silenciosas, isEmpty);
    });

    test('dado que lo vuelven a sumar (inscripción nueva, sin zona), no avisa nada y la primera '
        'zona que le asignen se avisa', () {
      final baja = _detectar([_inscripcion(dadaDeBaja: true)], avisadas: {'insc-1': 'z-centro'});
      final vuelve = _detectar([_inscripcion(id: 'insc-2')], avisadas: {...baja.silenciosas});
      expect(vuelve.avisos, isEmpty);

      final conZona = _detectar(
        [_inscripcion(id: 'insc-2', zonaId: 'z-norte', zonaNombre: 'Norte')],
        avisadas: {...baja.silenciosas, ...vuelve.silenciosas},
      );
      expect(conZona.avisos.single, isA<ZonaAsignada>());
    });
  });

  group('varias inscripciones y datos límite', () {
    test('cada inscripción se evalúa por su cuenta y los avisos salen en el orden de las '
        'inscripciones', () {
      final resultado = _detectar(
        [
          _inscripcion(id: 'a', campania: 'Campaña A', zonaId: 'z1', zonaNombre: 'Centro'),
          _inscripcion(id: 'b', campania: 'Campaña B'),
          _inscripcion(id: 'c', campania: 'Campaña C', zonaId: 'z3', zonaNombre: 'Norte'),
          _inscripcion(id: 'd', campania: 'Campaña D'),
        ],
        avisadas: {'a': null, 'b': 'z2', 'c': 'z3'},
      );

      expect(resultado.avisos.map((aviso) => aviso.inscripcionId), ['a', 'b']);
      expect(resultado.avisos[0], isA<ZonaAsignada>());
      expect(resultado.avisos[1], isA<ZonaQuitada>());
      expect(resultado.silenciosas, {'d': null});
    });

    test('sin inscripciones no hay nada que avisar (aunque haya avisadas viejas)', () {
      final resultado = _detectar(const [], avisadas: {'insc-1': 'z-centro'});

      expect(resultado.avisos, isEmpty);
      expect(resultado.silenciosas, isEmpty);
    });

    test('nombres larguísimos pasan enteros: el recorte es de la pantalla, no del dato', () {
      final largo = 'Zona ${'Muy larga ' * 40}';
      final resultado = _detectar([_inscripcion(zonaId: 'z', zonaNombre: largo)]);

      expect((resultado.avisos.single as ZonaAsignada).zonaNombre, largo.trim());
    });

    test('mil inscripciones se evalúan sin problema', () {
      final inscripciones = [
        for (var i = 0; i < 1000; i++)
          _inscripcion(id: 'insc-$i', zonaId: 'z-$i', zonaNombre: 'Zona $i'),
      ];

      final resultado = _detectar(inscripciones);

      expect(resultado.avisos, hasLength(1000));
    });
  });

  group('el aviso', () {
    test(
      'ZonaAsignada guarda la zona nueva y ZonaQuitada ninguna: es lo que se anota al cerrarlo',
      () {
        const asignada = ZonaAsignada(
          inscripcionId: 'i',
          campaniaNombre: 'C',
          zonaId: 'z',
          zonaNombre: 'Z',
        );
        const quitada = ZonaQuitada(inscripcionId: 'i', campaniaNombre: 'C');

        expect(asignada.zonaId, 'z');
        expect(quitada.zonaId, isNull);
      },
    );

    test('dos avisos con los mismos datos son iguales (la pantalla no se reconstruye de más)', () {
      const uno = ZonaQuitada(inscripcionId: 'i', campaniaNombre: 'C');
      const otro = ZonaQuitada(inscripcionId: 'i', campaniaNombre: 'C');

      expect(uno, otro);
      expect(uno.hashCode, otro.hashCode);
    });
  });
}
