// HU-UBI-002 / vista 05: los textos de las filas, los chips y los contadores de la lista.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/consulta_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_state.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/alta_ubicacion_falsos.dart' show canelones, montevideo;
import '../../../../helpers/lista_ubicaciones_falsos.dart';

void main() {
  // Hora local: las reglas de «hoy» y «ayer» son de calendario local.
  final ahora = DateTime(2026, 10, 6, 15, 30);
  const nbsp = ' ';
  // Las filas de `filaLista` se actualizaron 2 h antes de `ahoraLista`: media hora después, «hace 2 h».
  final ahoraFilas = ahoraLista.add(const Duration(minutes: 30));

  ItemListaUbicacion item(
    String id, {
    EstadoCasa? estado,
    int espacios = 2,
    DateTime? entrevista,
    DateTime? baja,
    TipoUbicacion tipo = TipoUbicacion.casa,
    double? distancia,
  }) {
    final fila = filaLista(
      id,
      tipo: tipo,
      estado: estado,
      espacios: espacios,
      entrevista: entrevista,
      baja: baja,
    );
    return ItemListaUbicacion(
      ubicacion: fila.ubicacion,
      cantidadEspacios: espacios,
      estado: estado,
      proximaEntrevista: entrevista,
      distanciaMetros: distancia,
    );
  }

  ListaUbicaciones lista({
    OrdenListaUbicaciones orden = OrdenListaUbicaciones.recientes,
    int total = 8,
    int general = 30,
    int bajas = 0,
  }) => ListaUbicaciones(
    items: const [],
    total: total,
    porTipo: const {},
    porEstado: const {},
    totalGeneral: general,
    totalBajas: bajas,
    estadosConocidos: false,
    hayMas: false,
    ordenAplicado: orden,
    sinUbicaciones: false,
  );

  group('estados', () {
    test('dado cada estado de la casa, cuando se rotula, entonces es el literal del canvas', () {
      expect(FormatoListaUbicaciones.estado(EstadoCasa.sinVisita), 'Sin visita');
      expect(FormatoListaUbicaciones.estado(EstadoCasa.noContesto), 'No contestó');
      expect(FormatoListaUbicaciones.estado(EstadoCasa.entrevistaAgendada), 'Entrevista agendada');
      expect(FormatoListaUbicaciones.estado(EstadoCasa.entrevistaHecha), 'Entrevista hecha');
      expect(FormatoListaUbicaciones.estado(EstadoCasa.ventaCompleta), 'Venta completa');
      expect(FormatoListaUbicaciones.estado(EstadoCasa.cobranzaPendiente), 'Cobranza pendiente');
      expect(FormatoListaUbicaciones.estado(EstadoCasa.entregaYPago), 'Entrega y pago');
      expect(FormatoListaUbicaciones.estado(EstadoCasa.rechazo), 'Rechazó');
    });

    test('dado cada estado, cuando se pide su glifo, entonces «Sin visita» no lleva ninguno', () {
      expect(FormatoListaUbicaciones.glifo(EstadoCasa.sinVisita), '');
      expect(FormatoListaUbicaciones.glifo(EstadoCasa.noContesto), '–');
      expect(FormatoListaUbicaciones.glifo(EstadoCasa.entrevistaAgendada), '◷');
      expect(FormatoListaUbicaciones.glifo(EstadoCasa.entrevistaHecha), '✓');
      expect(FormatoListaUbicaciones.glifo(EstadoCasa.ventaCompleta), '★');
      expect(FormatoListaUbicaciones.glifo(EstadoCasa.cobranzaPendiente), r'$');
      expect(FormatoListaUbicaciones.glifo(EstadoCasa.entregaYPago), '⇢');
      expect(FormatoListaUbicaciones.glifo(EstadoCasa.rechazo), '✕');
    });

    test('todos los estados tienen rótulo y los glifos (menos uno) son distintos', () {
      final glifos = {for (final e in EstadoCasa.values) FormatoListaUbicaciones.glifo(e)};
      expect(glifos, hasLength(EstadoCasa.values.length));
      for (final e in EstadoCasa.values) {
        expect(FormatoListaUbicaciones.estado(e), isNotEmpty);
      }
    });
  });

  group('espacios', () {
    test('dado 0, 1 y varios, cuando se cuentan, entonces concuerdan en singular y plural', () {
      expect(FormatoListaUbicaciones.espacios(0), 'sin espacios');
      expect(FormatoListaUbicaciones.espacios(-3), 'sin espacios');
      expect(FormatoListaUbicaciones.espacios(1), '1 espacio');
      expect(FormatoListaUbicaciones.espacios(2), '2 espacios');
      expect(FormatoListaUbicaciones.espacios(120), '120 espacios');
    });
  });

  group('hace', () {
    test('dado menos de un minuto, o un reloj atrasado, entonces dice «ahora»', () {
      expect(
        FormatoListaUbicaciones.hace(ahora.subtract(const Duration(seconds: 30)), ahora),
        'ahora',
      );
      expect(FormatoListaUbicaciones.hace(ahora.add(const Duration(minutes: 5)), ahora), 'ahora');
    });

    test('dado menos de una hora, entonces dice minutos', () {
      expect(
        FormatoListaUbicaciones.hace(ahora.subtract(const Duration(minutes: 1)), ahora),
        'hace 1 min',
      );
      expect(
        FormatoListaUbicaciones.hace(ahora.subtract(const Duration(minutes: 59)), ahora),
        'hace 59 min',
      );
    });

    test('dado el mismo día, entonces dice horas hasta 5 h y «hoy» después', () {
      final tarde = DateTime(2026, 10, 6, 23, 30);
      expect(FormatoListaUbicaciones.hace(DateTime(2026, 10, 6, 13, 30), ahora), 'hace 2 h');
      expect(FormatoListaUbicaciones.hace(DateTime(2026, 10, 6, 10, 30), ahora), 'hace 5 h');
      expect(FormatoListaUbicaciones.hace(DateTime(2026, 10, 6, 8, 0), tarde), 'hoy');
    });

    test('dado el día anterior, entonces dice «ayer», aunque hayan pasado menos de 24 h', () {
      expect(FormatoListaUbicaciones.hace(DateTime(2026, 10, 5, 23, 50), ahora), 'ayer');
      expect(FormatoListaUbicaciones.hace(DateTime(2026, 10, 5, 8), ahora), 'ayer');
    });

    test('dado entre 2 y 29 días, entonces dice «hace N d»', () {
      expect(FormatoListaUbicaciones.hace(DateTime(2026, 10, 3, 9), ahora), 'hace 3 d');
      expect(FormatoListaUbicaciones.hace(DateTime(2026, 9, 7, 9), ahora), 'hace 29 d');
    });

    test('dado 30 días o más, entonces dice la fecha, con el año si es otro', () {
      expect(FormatoListaUbicaciones.hace(DateTime(2026, 9, 6, 9), ahora), '06/09');
      expect(FormatoListaUbicaciones.hace(DateTime(2025, 12, 31, 9), ahora), '31/12/2025');
    });
  });

  group('entrevista', () {
    test('dado hoy, mañana y los días de la semana que viene, entonces dice el día y la hora', () {
      // 6/10/2026 es martes.
      expect(FormatoListaUbicaciones.entrevista(DateTime(2026, 10, 6, 18), ahora), 'hoy 18:00');
      expect(
        FormatoListaUbicaciones.entrevista(DateTime(2026, 10, 7, 9, 5), ahora),
        'mañana 09:05',
      );
      expect(FormatoListaUbicaciones.entrevista(DateTime(2026, 10, 8, 10), ahora), 'jue 10:00');
      expect(FormatoListaUbicaciones.entrevista(DateTime(2026, 10, 12, 10), ahora), 'lun 10:00');
    });

    test('dado más de una semana o una fecha pasada, entonces dice dd/MM y la hora', () {
      expect(FormatoListaUbicaciones.entrevista(DateTime(2026, 10, 13, 10), ahora), '13/10 10:00');
      expect(
        FormatoListaUbicaciones.entrevista(DateTime(2026, 10, 1, 16, 45), ahora),
        '01/10 16:45',
      );
    });
  });

  group('meta (la segunda línea de la fila)', () {
    test('dado un estado de venta, entonces es «Estado · N espacios»', () {
      final i = item('a', estado: EstadoCasa.cobranzaPendiente, espacios: 2);
      expect(FormatoListaUbicaciones.meta(i, ahora), 'Cobranza pendiente · 2 espacios');
    });

    test('dado «Entrevista agendada» con hora, entonces muestra cuándo en vez de los espacios', () {
      final i = item(
        'a',
        estado: EstadoCasa.entrevistaAgendada,
        entrevista: DateTime(2026, 10, 8, 10),
      );
      expect(FormatoListaUbicaciones.meta(i, ahora), 'Entrevista agendada · jue 10:00');
    });

    test('dado «Entrevista agendada» sin hora, entonces cae a los espacios', () {
      final i = item('a', estado: EstadoCasa.entrevistaAgendada, espacios: 1);
      expect(FormatoListaUbicaciones.meta(i, ahora), 'Entrevista agendada · 1 espacio');
    });

    test('dado que el estado no se conoce, entonces el tipo ocupa su lugar', () {
      expect(
        FormatoListaUbicaciones.meta(item('a', tipo: TipoUbicacion.edificio, espacios: 12), ahora),
        'Edificio · 12 espacios',
      );
      expect(
        FormatoListaUbicaciones.meta(item('a', tipo: TipoUbicacion.negocio, espacios: 0), ahora),
        'Negocio · sin espacios',
      );
    });

    test('dado una baja, entonces dice la fecha de la baja', () {
      final i = item('a', baja: DateTime.utc(2026, 9, 12, 15));
      expect(FormatoListaUbicaciones.meta(i, ahora), 'Casa · dada de baja el 12/09');
    });
  });

  group('derecha', () {
    test('dado el orden por cercanía y la distancia conocida, entonces muestra los metros', () {
      final l = lista(orden: OrdenListaUbicaciones.cercania);
      expect(
        FormatoListaUbicaciones.derecha(item('a', distancia: 42), l, ahoraFilas),
        '42${nbsp}m',
      );
      expect(
        FormatoListaUbicaciones.derecha(item('a', distancia: 1480), l, ahoraFilas),
        '1,5${nbsp}km',
      );
    });

    test('dado el orden por última actualización, entonces nunca muestra la distancia', () {
      final l = lista();
      final i = item('a', distancia: 42);
      expect(FormatoListaUbicaciones.derecha(i, l, ahoraFilas), 'hace 2 h');
    });

    test('dado el orden por cercanía pero sin distancia, entonces cae a la actualización', () {
      final l = lista(orden: OrdenListaUbicaciones.cercania);
      expect(FormatoListaUbicaciones.derecha(item('a'), l, ahoraFilas), 'hace 2 h');
    });
  });

  group('etiqueta de lector de pantalla', () {
    test('dado una fila normal, entonces lee dirección, meta y cuándo', () {
      final i = item('a', estado: EstadoCasa.ventaCompleta);
      expect(
        FormatoListaUbicaciones.etiquetaFila(i, lista(), ahoraFilas),
        'Av. Italia 1234. Venta completa · 2 espacios. hace 2 h',
      );
    });

    test('dado una baja, entonces lo dice antes de la meta', () {
      final i = item('a', baja: DateTime.utc(2026, 9, 12, 15));
      expect(
        FormatoListaUbicaciones.etiquetaFila(i, lista(), ahoraFilas),
        startsWith('Av. Italia 1234. Baja. Casa · dada de baja el 12/09'),
      );
    });
  });

  group('filtros y contadores', () {
    test('la proximidad usa espacio duro antes de la unidad', () {
      expect(FormatoListaUbicaciones.proximidad(ProximidadLista.cualquiera), 'Cualquiera');
      expect(FormatoListaUbicaciones.proximidad(ProximidadLista.cien), '100${nbsp}m');
      expect(FormatoListaUbicaciones.proximidad(ProximidadLista.trescientos), '300${nbsp}m');
      expect(FormatoListaUbicaciones.proximidad(ProximidadLista.unKilometro), '1${nbsp}km');
    });

    test('el chip de la proximidad es «Cerca de mí · 300 m»', () {
      expect(
        FormatoListaUbicaciones.chipProximidad(ProximidadLista.trescientos),
        'Cerca de mí · 300${nbsp}m',
      );
    });

    test('el contador dice «N de M» y suma las bajas solo si las hay', () {
      expect(FormatoListaUbicaciones.contador(lista()), '8 de 30');
      expect(
        FormatoListaUbicaciones.contador(lista(total: 33, general: 33, bajas: 1)),
        '33 de 33 · 1 baja',
      );
      expect(
        FormatoListaUbicaciones.contador(lista(total: 25, general: 33, bajas: 3)),
        '25 de 33 · 3 bajas',
      );
    });

    test('«Ver N ubicaciones» concuerda en singular', () {
      expect(FormatoListaUbicaciones.verUbicaciones(0), 'Ver 0 ubicaciones');
      expect(FormatoListaUbicaciones.verUbicaciones(1), 'Ver 1 ubicación');
      expect(FormatoListaUbicaciones.verUbicaciones(8), 'Ver 8 ubicaciones');
    });

    test('el GPS redondea la precisión y nunca baja de 1 m', () {
      expect(FormatoListaUbicaciones.gps(8), '◎ GPS ±8${nbsp}m');
      expect(FormatoListaUbicaciones.gps(7.6), '◎ GPS ±8${nbsp}m');
      expect(FormatoListaUbicaciones.gps(0.2), '◎ GPS ±1${nbsp}m');
      expect(FormatoListaUbicaciones.gps(double.nan), '◎ GPS ±1${nbsp}m');
      expect(FormatoListaUbicaciones.gps(double.infinity), '◎ GPS ±1${nbsp}m');
    });
  });

  group('ciudad', () {
    test('dado la lectura de la campaña, entonces devuelve el nombre de la ciudad pedida', () {
      const lectura = Right<Failure, List<CiudadCatalogo>>([montevideo, canelones]);
      expect(FormatoListaUbicaciones.ciudad(lectura, 'ciu-can'), 'Canelones');
    });

    test(
      'dado que no se pudo leer, no hay lectura o la ciudad ya no está, entonces dice «Ciudad»',
      () {
        const falla = Left<Failure, List<CiudadCatalogo>>(FailureInesperado());
        expect(FormatoListaUbicaciones.ciudad(falla, 'ciu-can'), 'Ciudad');
        expect(FormatoListaUbicaciones.ciudad(null, 'ciu-can'), 'Ciudad');
        const lectura = Right<Failure, List<CiudadCatalogo>>([montevideo]);
        expect(FormatoListaUbicaciones.ciudad(lectura, 'ciu-can'), 'Ciudad');
      },
    );
  });
}
