import 'package:dartz/dartz.dart' show Either;

import '../../../core/error/failure.dart';
import '../domain/entities/consulta_lista_ubicaciones.dart';
import '../domain/entities/estado_casa.dart';
import '../domain/entities/lista_ubicaciones.dart';
import '../domain/entities/motivo_baja.dart';
import '../domain/services/ciudades_para_alta.dart';
import 'formato_ubicaciones.dart';
import 'providers/lista_ubicaciones_state.dart';

/// Los textos de la lista de ubicaciones (vista 05, HU-UBI-002). Los literales son los del canvas;
/// los que el canvas no dibuja (fechas lejanas, entrevistas, sin GPS) son propuestas marcadas en el
/// pendiente de la HU.
abstract final class FormatoListaUbicaciones {
  static const espacioDuro = FormatoUbicaciones.espacioDuro;

  /// El rótulo de cada estado, tal cual el de «ESTADO DE LA CASA».
  static String estado(EstadoCasa estado) => switch (estado) {
    EstadoCasa.sinVisita => 'Sin visita',
    EstadoCasa.noContesto => 'No contestó',
    EstadoCasa.entrevistaAgendada => 'Entrevista agendada',
    EstadoCasa.entrevistaHecha => 'Entrevista hecha',
    EstadoCasa.ventaCompleta => 'Venta completa',
    EstadoCasa.cobranzaPendiente => 'Cobranza pendiente',
    EstadoCasa.entregaYPago => 'Entrega y pago',
    EstadoCasa.rechazo => 'Rechazó',
  };

  /// El glifo que va dentro de la insignia del estado («Sin visita» no lleva: es un círculo vacío).
  static String glifo(EstadoCasa estado) => switch (estado) {
    EstadoCasa.sinVisita => '',
    EstadoCasa.noContesto => '–',
    EstadoCasa.entrevistaAgendada => '◷',
    EstadoCasa.entrevistaHecha => '✓',
    EstadoCasa.ventaCompleta => '★',
    EstadoCasa.cobranzaPendiente => r'$',
    EstadoCasa.entregaYPago => '⇢',
    EstadoCasa.rechazo => '✕',
  };

  /// «1 espacio», «2 espacios»; «sin espacios» si no queda ninguno.
  static String espacios(int cantidad) => switch (cantidad) {
    <= 0 => 'sin espacios',
    1 => '1 espacio',
    _ => '$cantidad espacios',
  };

  /// «dd/MM» en hora local.
  static String diaMes(DateTime momento) {
    final m = momento.toLocal();
    return '${_dos(m.day)}/${_dos(m.month)}';
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');

  /// Cuántos días de calendario (en hora local) hay de [desde] a [hasta]: 0 = el mismo día.
  static int diasDeCalendario(DateTime desde, DateTime hasta) {
    final a = desde.toLocal();
    final b = hasta.toLocal();
    return DateTime.utc(
      b.year,
      b.month,
      b.day,
    ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  }

  /// La última actualización de una fila: «hace 2 h», «hoy», «ayer», «hace 3 d» (canvas). Menos de
  /// un minuto: «ahora»; de 30 días en adelante, la fecha («12/09», con el año si es otro).
  static String hace(DateTime momento, DateTime ahora) {
    final transcurrido = ahora.difference(momento);
    if (transcurrido.isNegative || transcurrido.inMinutes < 1) return 'ahora';
    if (transcurrido.inMinutes < 60) return 'hace ${transcurrido.inMinutes} min';
    final dias = diasDeCalendario(momento, ahora);
    if (dias == 0) return transcurrido.inHours < 6 ? 'hace ${transcurrido.inHours} h' : 'hoy';
    if (dias == 1) return 'ayer';
    if (dias < 30) return 'hace $dias d';
    final m = momento.toLocal();
    final anio = m.year == ahora.toLocal().year ? '' : '/${m.year}';
    return '${diaMes(momento)}$anio';
  }

  static const _diasSemana = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

  /// La entrevista agendada: «jue 10:00» (canvas) en la semana que viene, «hoy 10:00»,
  /// «mañana 10:00», y «12/10 10:00» si es más lejos o ya pasó.
  static String entrevista(DateTime cuando, DateTime ahora) {
    final c = cuando.toLocal();
    final hora = '${_dos(c.hour)}:${_dos(c.minute)}';
    final dias = diasDeCalendario(ahora, cuando);
    if (dias == 0) return 'hoy $hora';
    if (dias == 1) return 'mañana $hora';
    if (dias >= 2 && dias <= 6) return '${_diasSemana[c.weekday - 1]} $hora';
    return '${diaMes(cuando)} $hora';
  }

  /// La segunda línea de una fila (canvas): «Cobranza pendiente · 2 espacios», «Entrevista
  /// agendada · jue 10:00», «Casa · baja el 12/09 · Ya no existe». Sin estado conocido (todavía no hay
  /// `house_status` local), el tipo ocupa el lugar del estado.
  static String meta(ItemListaUbicacion item, DateTime ahora) {
    final u = item.ubicacion;
    final tipo = FormatoUbicaciones.tipo(u.tipo);
    if (item.esBaja) {
      // Canvas 09·03: «Casa · baja el 12/09 · Ya no existe». El motivo, si se conoce.
      final motivo = MotivosBaja.paraMostrar(item.motivoBaja);
      return '$tipo · baja el ${diaMes(u.auditoria.deletedAt!)}${motivo == null ? '' : ' · $motivo'}';
    }
    final estado = item.estado;
    if (estado == null) return '$tipo · ${espacios(item.cantidadEspacios)}';
    final cuando = item.proximaEntrevista;
    final detalle = estado == EstadoCasa.entrevistaAgendada && cuando != null
        ? entrevista(cuando, ahora)
        : espacios(item.cantidadEspacios);
    return '${FormatoListaUbicaciones.estado(estado)} · $detalle';
  }

  /// Lo que va a la derecha de la fila: la distancia con el orden por cercanía, y si no la última
  /// actualización (canvas: «La distancia solo aparece con el orden por cercanía»).
  static String derecha(ItemListaUbicacion item, ListaUbicaciones lista, DateTime ahora) {
    final distancia = item.distanciaMetros;
    if (lista.ordenAplicado == OrdenListaUbicaciones.cercania && distancia != null) {
      return FormatoUbicaciones.distancia(distancia);
    }
    return hace(item.ubicacion.auditoria.updatedAt, ahora);
  }

  /// La etiqueta de lector de pantalla de una fila.
  static String etiquetaFila(ItemListaUbicacion item, ListaUbicaciones lista, DateTime ahora) {
    final partes = [
      FormatoUbicaciones.direccion(item.ubicacion),
      if (item.esBaja) 'Baja',
      meta(item, ahora),
      derecha(item, lista, ahora),
    ];
    return partes.join('. ');
  }

  /// El texto de «Proximidad».
  static String proximidad(ProximidadLista proximidad) => switch (proximidad) {
    ProximidadLista.cualquiera => 'Cualquiera',
    ProximidadLista.cien => '100${espacioDuro}m',
    ProximidadLista.trescientos => '300${espacioDuro}m',
    ProximidadLista.unKilometro => '1${espacioDuro}km',
  };

  /// El chip de la proximidad. «Cerca de mí» es del canvas («Textos propuesta»).
  static String chipProximidad(ProximidadLista proximidad) =>
      'Cerca de mí · ${FormatoListaUbicaciones.proximidad(proximidad)}';

  /// «8 de 30», «25 de 33 · 3 bajas».
  static String contador(ListaUbicaciones lista) {
    final base = '${lista.total} de ${lista.totalGeneral}';
    if (lista.totalBajas <= 0) return base;
    return '$base · ${lista.totalBajas == 1 ? '1 baja' : '${lista.totalBajas} bajas'}';
  }

  /// «Ver 8 ubicaciones», «Ver 1 ubicación».
  static String verUbicaciones(int cantidad) =>
      'Ver $cantidad ${cantidad == 1 ? 'ubicación' : 'ubicaciones'}';

  /// «◎ GPS ±8 m»: la precisión de la última lectura, redondeada y nunca menor a 1 m.
  static String gps(double precisionMetros) {
    final p = precisionMetros.isFinite ? precisionMetros.round() : 0;
    return '◎ GPS ±${p < 1 ? 1 : p}${espacioDuro}m';
  }

  /// El nombre de la ciudad [id] entre las que se leyeron, o «Ciudad» si no se pudieron leer o ya
  /// no está en la campaña.
  static String ciudad(Either<Failure, List<CiudadCatalogo>>? lectura, String id) {
    final ciudades = lectura?.fold<List<CiudadCatalogo>>((_) => const [], (c) => c) ?? const [];
    for (final c in ciudades) {
      if (c.id == id) return c.nombre;
    }
    return 'Ciudad';
  }
}
