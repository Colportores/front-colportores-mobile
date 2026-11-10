import '../../agenda/domain/entities/visita.dart' show TipoResultadoVisita;
import '../../cobranzas/domain/entities/cobranza.dart' show MedioCobranza;
import '../../cobranzas/domain/services/reparto_de_cuotas.dart' show CuotasDeUnCobro;
import '../../ventas/presentation/formato_venta.dart' show TextosVenta;
import '../domain/entities/evento_de_la_casa.dart';
import '../domain/entities/ficha_de_persona.dart' show LineaDeFicha;
import '../domain/services/historial_de_la_casa.dart';
import 'textos_baja_persona.dart' show FormatoBajaPersona;

/// Los textos de la pestaña Historial de la hoja arriba y del detalle de una visita (vista 39, C·03 y
/// C·04). Los rótulos del canvas van tal cual; lo que el canvas no dibuja (vacío, filtro sin
/// resultados, error, cargando, el título de «Rechazo» y de las visitas de cobranza, el medio de un
/// cobro) es propuesta y dice qué pasó y qué hacer (mapa §2: texto/aviso).
abstract final class TextosHistorialDeLaCasa {
  // --- Del canvas (C·03 y C·04) ---
  static const todo = 'Todo';
  static const entrevistas = 'Entrevistas';
  static const ventas = 'Ventas';
  static const cobros = 'Cobros';
  static const nadieAtendio = 'Nadie atendió';
  static const verLaVenta = 'Ver la venta';
  static const cerrar = 'Cerrar';
  static const notaDeLaVisita = 'NOTA DE LA VISITA';
  static const pagado = 'Pagado';
  static const saldo = 'Saldo';

  // --- Lo que el canvas no dibuja ---
  static const sinNombre = 'Sin nombre';
  static const rechazo = 'Rechazó la visita';
  static const pasadaACobrar = 'Pasó a cobrar';
  static const ventaRegistrada = 'Venta registrada';
  static const venta = 'Venta';
  static const libro = 'Libro';
  static const duracion = 'Duración';
  static const filtroDelHistorial = 'MOSTRAR';
  static const verTodo = 'Ver todo';
  static const reintentar = 'Reintentar';

  static const vacioTitulo = 'Todavía no pasó nada en esta casa';
  static const vacioAyuda =
      'Las visitas, las ventas y los cobros que registres acá aparecen en este historial.';

  static const cargando = 'Cargando el historial';
  static const noPudimosLeer = 'No pudimos leer el historial de esta casa en tu teléfono.';
  static const noPudimosAbrirElCobro = 'No pudimos abrir el cobro. Probá de nuevo.';
  static const noPudimosAbrirLaVenta = 'No pudimos abrir la venta. Probá de nuevo.';

  static String etiquetaDelFiltro(FiltroDeLaCasa filtro) => switch (filtro) {
    FiltroDeLaCasa.todo => todo,
    FiltroDeLaCasa.entrevistas => entrevistas,
    FiltroDeLaCasa.ventas => ventas,
    FiltroDeLaCasa.cobros => cobros,
  };

  /// Lo que lee el lector de pantalla de una opción del filtro: «Ventas, elegido».
  static String lectorDelFiltro(FiltroDeLaCasa filtro, {required bool elegido}) =>
      elegido ? '${etiquetaDelFiltro(filtro)}, elegido' : etiquetaDelFiltro(filtro);

  /// El filtro no deja ninguna fila.
  static String sinResultados(FiltroDeLaCasa filtro) => switch (filtro) {
    FiltroDeLaCasa.entrevistas => 'No hay entrevistas en esta casa.',
    FiltroDeLaCasa.ventas => 'No hay ventas en esta casa.',
    FiltroDeLaCasa.cobros => 'No hay cobros en esta casa.',
    FiltroDeLaCasa.todo => '',
  };

  static String verMas(int faltan) => 'Ver más ($faltan)';
}

/// Cómo se escribe cada fila del historial de la casa y su detalle.
abstract final class FormatoHistorialDeLaCasa {
  static String _dos(int n) => n.toString().padLeft(2, '0');

  /// «HOY 14:20» si pasó hoy; «12/10» (o «12/10/2025» de otro año) si no. En hora local.
  static String cuando(DateTime fecha, DateTime ahora) {
    final local = fecha.toLocal();
    final hoy = ahora.toLocal();
    final esHoy = local.year == hoy.year && local.month == hoy.month && local.day == hoy.day;
    return esHoy
        ? 'HOY ${_dos(local.hour)}:${_dos(local.minute)}'
        : FormatoBajaPersona.fechaCorta(fecha, ahora);
  }

  /// «22 MIN»: lo que duró la entrevista, al minuto. Una duración menor a un minuto es «1 MIN»: no se
  /// muestra un «0 MIN» que parezca un error.
  static String duracion(Duration duracion) {
    final minutos = duracion.inMinutes < 1 ? 1 : duracion.inMinutes;
    return '$minutos MIN';
  }

  /// «22 min», en el detalle.
  static String duracionLarga(Duration duracion) {
    final minutos = duracion.inMinutes < 1 ? 1 : duracion.inMinutes;
    return '$minutos min';
  }

  static String _rotuloDeLaVisita(TipoResultadoVisita r) => switch (r) {
    TipoResultadoVisita.entrevista => 'ENTREVISTA DADA',
    TipoResultadoVisita.noContesto => 'NO CONTESTÓ',
    TipoResultadoVisita.rechazo => 'RECHAZO',
    TipoResultadoVisita.cobranza => 'COBRANZA',
    TipoResultadoVisita.venta => 'VENTA',
  };

  /// La línea chica de arriba: «HOY 14:20 · COBRO», «12/10 · VENTA 0038», «05/10 · ENTREVISTA DADA ·
  /// 22 MIN».
  static String antetitulo(EventoDeLaCasa e, DateTime ahora) {
    final cuandoFue = cuando(e.fecha, ahora);
    return switch (e) {
      VisitaDeLaCasa(:final resultado, :final duracion) =>
        '$cuandoFue · ${_rotuloDeLaVisita(resultado)}'
            '${duracion == null ? '' : ' · ${FormatoHistorialDeLaCasa.duracion(duracion)}'}',
      VentaDeLaCasa(:final numeroTalonario) => '$cuandoFue · VENTA $numeroTalonario',
      CobroDeLaCasa() => '$cuandoFue · COBRO',
    };
  }

  static String _conPersona(String base, PersonaDelEvento? persona) {
    final nombre = persona?.nombreDePila ?? '';
    return nombre.isEmpty ? base : '$base · $nombre';
  }

  /// «Salud y Hogar + Nuestros Hijos × 2»: lo que se vendió, con la cantidad si es más de una.
  static String lineas(List<LineaDeFicha> lineas) =>
      lineas.map((l) => l.cantidad > 1 ? '${l.nombre} × ${l.cantidad}' : l.nombre).join(' + ');

  /// «Colección de 16 libros»: la primera fila del detalle de una venta (C·04), con N la suma de las
  /// cantidades de sus renglones.
  static String coleccion(List<LineaDeFicha> lineas) =>
      TextosVenta.coleccionDe(lineas.fold<int>(0, (n, l) => n + l.cantidad));

  /// «Salud y Hogar» o «Nuestros Hijos × 12»: el valor de la fila «Libro» de un renglón (C·04).
  static String libro(LineaDeFicha l) => l.cantidad > 1 ? '${l.nombre} × ${l.cantidad}' : l.nombre;

  /// La tercera línea de un cobro de una venta con plan (C·03): «Cuota 1 de 2», «Cuotas 1 y 2 de 3»,
  /// «Cuotas 1 a 3 de 4», «Parte de la cuota 2 de 3». Si el cobro completa unas cuotas y deja otra a
  /// medias, las nombra a las dos: «Cuota 1 y parte de la 2 de 3».
  static String cuotas(CuotasDeUnCobro c) {
    final de = ' de ${c.deTotal}';
    final n = c.completas;
    final parte = c.aMedias;
    if (n.isEmpty) return 'Parte de la cuota $parte$de';
    final seguidas = [for (var i = 1; i < n.length; i++) n[i] == n[i - 1] + 1].every((s) => s);
    final nombre = switch (n.length) {
      1 => 'Cuota ${n.first}',
      2 => 'Cuotas ${n.first} y ${n.last}',
      _ when seguidas => 'Cuotas ${n.first} a ${n.last}',
      _ => 'Cuotas ${n.sublist(0, n.length - 1).join(', ')} y ${n.last}',
    };
    return parte == null ? '$nombre$de' : '$nombre y parte de la $parte$de';
  }

  static String _medio(MedioCobranza medio) => switch (medio) {
    MedioCobranza.efectivo => 'en efectivo',
    MedioCobranza.tarjeta => 'con tarjeta',
    MedioCobranza.transferencia => 'por transferencia',
  };

  /// El título: «Pedro Gómez» (entrevista), «Nadie atendió», «$ 600 en efectivo · Pedro», «Salud y
  /// Hogar · Pedro».
  static String titulo(EventoDeLaCasa e) => switch (e) {
    VisitaDeLaCasa(:final resultado, :final persona) => switch (resultado) {
      TipoResultadoVisita.entrevista =>
        persona == null || persona.nombreCompleto.isEmpty
            ? TextosHistorialDeLaCasa.sinNombre
            : persona.nombreCompleto,
      TipoResultadoVisita.noContesto => TextosHistorialDeLaCasa.nadieAtendio,
      TipoResultadoVisita.rechazo => TextosHistorialDeLaCasa.rechazo,
      TipoResultadoVisita.cobranza => _conPersona(TextosHistorialDeLaCasa.pasadaACobrar, persona),
      TipoResultadoVisita.venta => _conPersona(TextosHistorialDeLaCasa.ventaRegistrada, persona),
    },
    VentaDeLaCasa(:final lineas, :final persona) => _conPersona(
      lineas.isEmpty ? TextosHistorialDeLaCasa.venta : FormatoHistorialDeLaCasa.lineas(lineas),
      persona,
    ),
    CobroDeLaCasa(:final montoCentavos, :final medio, :final persona) => _conPersona(
      '${FormatoBajaPersona.monto(montoCentavos)} ${_medio(medio)}',
      persona,
    ),
  };

  /// «✎ volver con la esposa»: la nota de la visita, en una línea.
  static String conNota(String nota) => '✎ ${nota.replaceAll(RegExp(r'\s+'), ' ').trim()}';

  /// La línea de abajo: la nota de una visita, «$ 4.800 · ✎ quiere Nuestros Hijos» de una venta; de un
  /// cobro, las cuotas que cubrió si la venta tiene plan («Cuota 1 de 2», [cuotas]) o si no «Venta
  /// 0038» (decisión del 10/11, P1 del QA de #677). `null` si no hay.
  static String? subtitulo(EventoDeLaCasa e) => switch (e) {
    VisitaDeLaCasa(:final nota) => nota == null ? null : conNota(nota),
    VentaDeLaCasa(:final montoCentavos, :final nota) =>
      nota == null
          ? FormatoBajaPersona.monto(montoCentavos)
          : '${FormatoBajaPersona.monto(montoCentavos)} · ${conNota(nota)}',
    CobroDeLaCasa(:final cuotas?) => FormatoHistorialDeLaCasa.cuotas(cuotas),
    CobroDeLaCasa(:final numeroTalonario) =>
      numeroTalonario == null ? null : 'Venta $numeroTalonario',
  };

  /// Lo que lee el lector de pantalla de una fila, de una vez.
  static String paraLector(EventoDeLaCasa e, DateTime ahora) {
    final sub = subtitulo(e);
    return [antetitulo(e, ahora), titulo(e), ?sub].join('. ');
  }

  /// El título del detalle: «Venta 0038 · 12/10», «Entrevista dada · 05/10».
  static String tituloDelDetalle(EventoDeLaCasa e, DateTime ahora) {
    final dia = FormatoBajaPersona.fechaCorta(e.fecha, ahora);
    final base = switch (e) {
      VentaDeLaCasa(:final numeroTalonario) => 'Venta $numeroTalonario',
      CobroDeLaCasa(:final numeroTalonario) =>
        numeroTalonario == null ? 'Cobro' : 'Cobro de la venta $numeroTalonario',
      VisitaDeLaCasa(:final resultado) => switch (resultado) {
        TipoResultadoVisita.entrevista => 'Entrevista dada',
        TipoResultadoVisita.noContesto => 'No contestó',
        TipoResultadoVisita.rechazo => 'Rechazo',
        TipoResultadoVisita.cobranza => 'Cobranza',
        TipoResultadoVisita.venta => 'Venta',
      },
    };
    return '$base · $dia';
  }

  /// La línea de abajo del título del detalle: «Pedro Gómez · Grecia 3310» (o solo la dirección).
  static String subtituloDelDetalle(EventoDeLaCasa e, String direccion) {
    final persona = switch (e) {
      VisitaDeLaCasa(:final persona) => persona,
      VentaDeLaCasa(:final persona) => persona,
      CobroDeLaCasa(:final persona) => persona,
    };
    final nombre = persona?.nombreCompleto ?? '';
    return nombre.isEmpty ? direccion : '$nombre · $direccion';
  }
}
