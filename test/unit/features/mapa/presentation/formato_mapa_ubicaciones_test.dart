// HU-UBI-003 / vista 06: los textos de la vista previa y de los marcadores, y las alturas de la
// hoja. Sin widgets.
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart';
import 'package:flutter/widgets.dart' show TextScaler;
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/lista_ubicaciones_falsos.dart';

void main() {
  const nbsp = ' ';

  ItemListaUbicacion item(
    String id, {
    TipoUbicacion tipo = TipoUbicacion.casa,
    int espacios = 2,
    double? distancia,
    String numero = '1234',
  }) {
    final fila = filaLista(id, tipo: tipo, numero: numero, espacios: espacios);
    return ItemListaUbicacion(
      ubicacion: fila.ubicacion,
      cantidadEspacios: espacios,
      distanciaMetros: distancia,
    );
  }

  group('etiquetaPuerta', () {
    test('el número de puerta tal cual, sin espacios de más', () {
      expect(FormatoMapaUbicaciones.etiquetaPuerta(item('a').ubicacion), '1234');
      expect(FormatoMapaUbicaciones.etiquetaPuerta(item('a', numero: ' 56 ').ubicacion), '56');
    });

    test('sin número (el alta no lo exige) dice «s/n»', () {
      expect(FormatoMapaUbicaciones.etiquetaPuerta(item('a', numero: '').ubicacion), 's/n');
      expect(FormatoMapaUbicaciones.etiquetaPuerta(item('a', numero: '   ').ubicacion), 's/n');
    });
  });

  group('rotuloVistaPrevia', () {
    test('tipo, espacios y distancia, en mayúsculas como el canvas', () {
      expect(
        FormatoMapaUbicaciones.rotuloVistaPrevia(item('a', distancia: 40)),
        'CASA · 2 ESPACIOS · A 40${nbsp}M',
      );
    });

    test('sin GPS no hay distancia y no se inventa', () {
      expect(
        FormatoMapaUbicaciones.rotuloVistaPrevia(
          item('a', tipo: TipoUbicacion.negocio, espacios: 1),
        ),
        'NEGOCIO · 1 ESPACIO',
      );
    });

    test('una distancia que no es un número se omite', () {
      expect(
        FormatoMapaUbicaciones.rotuloVistaPrevia(item('a', distancia: double.nan)),
        'CASA · 2 ESPACIOS',
      );
      expect(
        FormatoMapaUbicaciones.rotuloVistaPrevia(item('a', distancia: double.infinity)),
        'CASA · 2 ESPACIOS',
      );
    });

    test('más de un kilómetro se escribe en km y sin espacios queda «sin espacios»', () {
      expect(
        FormatoMapaUbicaciones.rotuloVistaPrevia(
          item('a', tipo: TipoUbicacion.edificio, espacios: 0, distancia: 1500),
        ),
        'EDIFICIO · SIN ESPACIOS · A 1,5${nbsp}KM',
      );
    });
  });

  group('estadoVistaPrevia', () {
    final ahora = DateTime(2026, 10, 6, 15);

    test('el rótulo del estado', () {
      expect(
        FormatoMapaUbicaciones.estadoVistaPrevia(EstadoCasa.cobranzaPendiente, null, ahora),
        'Cobranza pendiente',
      );
      expect(
        FormatoMapaUbicaciones.estadoVistaPrevia(EstadoCasa.sinVisita, null, ahora),
        'Sin visita',
      );
    });

    test('una entrevista agendada dice cuándo', () {
      expect(
        FormatoMapaUbicaciones.estadoVistaPrevia(
          EstadoCasa.entrevistaAgendada,
          DateTime(2026, 10, 6, 18),
          ahora,
        ),
        'Entrevista agendada · hoy 18:00',
      );
    });

    test('una entrevista agendada sin hora no inventa una', () {
      expect(
        FormatoMapaUbicaciones.estadoVistaPrevia(EstadoCasa.entrevistaAgendada, null, ahora),
        'Entrevista agendada',
      );
    });

    test('la hora de otro estado no se muestra', () {
      expect(
        FormatoMapaUbicaciones.estadoVistaPrevia(
          EstadoCasa.entrevistaHecha,
          DateTime(2026, 10, 6, 18),
          ahora,
        ),
        'Entrevista hecha',
      );
    });
  });

  group('cuentaCercania', () {
    test('sin la lista todavía, solo el nombre de la pestaña', () {
      expect(FormatoMapaUbicaciones.cuentaCercania(null), 'Cercanía');
    });

    test('una ubicación en singular, las demás en plural, cero incluido', () {
      expect(FormatoMapaUbicaciones.cuentaCercania(1), 'Cercanía, 1 ubicación');
      expect(FormatoMapaUbicaciones.cuentaCercania(6), 'Cercanía, 6 ubicaciones');
      expect(FormatoMapaUbicaciones.cuentaCercania(0), 'Cercanía, 0 ubicaciones');
    });
  });

  group('AlturaHoja', () {
    test('el asa recorre minimizada, 1/3 y 1/2 y vuelve a empezar', () {
      expect(AlturaHoja.minimizada.siguiente, AlturaHoja.tercio);
      expect(AlturaHoja.tercio.siguiente, AlturaHoja.mitad);
      expect(AlturaHoja.mitad.siguiente, AlturaHoja.minimizada);
    });

    test('«más» y «menos» se detienen en los extremos', () {
      expect(AlturaHoja.minimizada.mas, AlturaHoja.tercio);
      expect(AlturaHoja.tercio.mas, AlturaHoja.mitad);
      expect(AlturaHoja.mitad.mas, AlturaHoja.mitad);
      expect(AlturaHoja.mitad.menos, AlturaHoja.tercio);
      expect(AlturaHoja.tercio.menos, AlturaHoja.minimizada);
      expect(AlturaHoja.minimizada.menos, AlturaHoja.minimizada);
    });

    test('cada altura se describe para el lector de pantalla', () {
      expect(AlturaHoja.minimizada.descripcion, 'Minimizada');
      expect(AlturaHoja.tercio.descripcion, 'A un tercio de la pantalla');
      expect(AlturaHoja.mitad.descripcion, 'A la mitad de la pantalla');
    });

    test('la minimizada mide 108 dp con el texto normal y crece con el texto grande', () {
      expect(AlturaHoja.altoMinimizada(TextScaler.noScaling), 108);
      final grande = AlturaHoja.altoMinimizada(const TextScaler.linear(2));
      expect(grande, greaterThan(108));
      expect(grande, lessThan(140));
    });

    test('1/3 y 1/2 son esa parte de la pantalla', () {
      const escala = TextScaler.noScaling;
      expect(
        AlturaHoja.tercio.alto(pantalla: 900, disponible: 900, escala: escala),
        closeTo(300, 1e-9),
      );
      expect(
        AlturaHoja.mitad.alto(pantalla: 900, disponible: 900, escala: escala),
        closeTo(450, 1e-9),
      );
      expect(AlturaHoja.minimizada.alto(pantalla: 900, disponible: 900, escala: escala), 108);
    });

    test('nunca tapa más del 70 % de lo disponible: el mapa sigue a la vista', () {
      const escala = TextScaler.noScaling;
      expect(
        AlturaHoja.mitad.alto(pantalla: 900, disponible: 500, escala: escala),
        closeTo(350, 1e-9),
      );
    });

    test('nunca baja de la minimizada, ni en una pantalla muy chica', () {
      const escala = TextScaler.noScaling;
      expect(AlturaHoja.tercio.alto(pantalla: 200, disponible: 200, escala: escala), 108);
      expect(AlturaHoja.mitad.alto(pantalla: 200, disponible: 100, escala: escala), 108);
    });
  });
}
