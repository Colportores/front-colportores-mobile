import 'dart:async';

import 'package:dartz/dartz.dart' show Either, Unit;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../cobranzas/presentation/providers/cobranzas_providers.dart'
    show saldoPendienteRepositoryProvider;
import '../../../mapa/presentation/providers/cobranza_recien_agendada_providers.dart';
import '../../../mapa/presentation/providers/hoja_casa_providers.dart'
    show contextoDeLaCasaProvider;
import '../../../mapa/presentation/providers/mapa_ubicaciones_notifier.dart';
import '../../../mapa/presentation/providers/personas_providers.dart';
import '../../../mapa/presentation/textos_personas.dart' show FormatoPersonas;
import '../../../ventas/domain/entities/cliente_de_la_venta.dart';
import '../../../ventas/domain/entities/nueva_venta.dart' show VentaGuardada;
import '../../../ventas/presentation/flujo_cuando_cobrar.dart';
import '../../../ventas/presentation/pages/nueva_venta_page.dart';
import '../../../ventas/presentation/pages/venta_registrada_page.dart';
import '../../../ventas/presentation/providers/nueva_venta_notifier.dart' show ArgumentosDeVenta;
import '../../../ventas/presentation/providers/ventas_providers.dart'
    show ContextoDeCobroDeLaVenta, cobrarDespuesDeLaVentaProvider;
import '../../domain/entities/agenda.dart';
import '../../domain/entities/entrevista_en_curso.dart';
import '../../domain/usecases/cerrar_entrevista_con_venta_use_case.dart';
import '../../domain/usecases/finalizar_entrevista_use_case.dart';
import '../providers/agenda_providers.dart';
import '../providers/entrevista_providers.dart';
import '../providers/rotulo_entrevista_providers.dart';
import 'hoja_entrevista_en_curso.dart';
import 'hoja_termino_entrevista.dart';
import 'textos_entrevista.dart';

/// El recorrido de una entrevista en curso, de la hoja R·05 a «Terminó la entrevista» (R·06 / R·07).
/// Lo abren el aviso fijo del mapa, la hoja de la casa (#444) y el cierre de la jornada.
abstract final class FlujoEntrevista {
  /// R·05: abre «Entrevista en curso» de [colportorId] y, si toca «Finalizar entrevista», sigue a
  /// [terminar]. Sin entrevista en curso no hace nada.
  static Future<SalidaTerminoEntrevista?> abrir(
    BuildContext context,
    WidgetRef ref, {
    required String colportorId,
  }) async {
    final notificador = ref.read(entrevistaEnCursoProvider(colportorId).notifier);
    final estado = await notificador.esperarLectura();
    final entrevista = estado.entrevista;
    if (entrevista == null || !context.mounted) return null;
    final rotulo = await _rotulo(ref, entrevista);
    if (!context.mounted) return null;

    final finalizar = await mostrarHojaEntrevistaEnCurso(
      context,
      direccion: rotulo.direccion,
      persona: rotulo.persona,
      inicio: entrevista.inicio,
      notaInicial: estado.notaBorrador,
      alEscribirNota: notificador.escribirNota,
      reloj: ref.read(relojEntrevistaProvider),
    );
    if (finalizar != true || !context.mounted) return null;
    return terminar(context, ref, colportorId: colportorId, pedirSalida: estado.recuperada);
  }

  /// R·06: «Terminó la entrevista» de la que [colportorId] tiene en curso.
  ///
  /// La salida es «ahora» salvo que [pedirSalida]: si la app se cerró con la entrevista abierta o se
  /// termina la jornada con ella abierta, la hora de salida **no se inventa**, se le pide
  /// (decisión de Cristian, 23/10, #450). Devuelve cómo se cerró la hoja, o `null` si no había
  /// entrevista o se cerró sin elegir (la entrevista sigue en curso).
  ///
  /// «Sí, registrar la venta» sigue por la venta (vista 27) con la casa, la persona y la visita ya
  /// puestas ([_registrarLaVenta], #428): devuelve [VentaGuardadaEnLaEntrevista] si se guardó, o
  /// [VentaSinCompletar] si no (por R44 no se guarda el resultado y la entrevista sigue en curso).
  /// [desdeLaJornada] es `true` cuando se llega desde «Finalizar jornada»: el aviso de la venta que no
  /// se completó dice que hay que terminar la entrevista para cerrar la jornada, y la casa no se
  /// vuelve a elegir en el mapa. Con [conVenta] en `false` la hoja devuelve [QuiereRegistrarLaVenta] sin
  /// seguir (la cuenta restringida, a la espera de la decisión de Cristian, «Venta susp.»).
  static Future<SalidaTerminoEntrevista?> terminar(
    BuildContext context,
    WidgetRef ref, {
    required String colportorId,
    bool pedirSalida = false,
    bool desdeLaJornada = false,
    bool conVenta = true,
  }) async {
    final notificador = ref.read(entrevistaEnCursoProvider(colportorId).notifier);
    final estado = await notificador.esperarLectura();
    final entrevista = estado.entrevista;
    if (entrevista == null || !context.mounted) return null;
    final rotulo = await _rotulo(ref, entrevista);
    if (!context.mounted) return null;

    final reloj = ref.read(relojEntrevistaProvider);
    final salida = pedirSalida ? null : reloj();
    final mensajero = ScaffoldMessenger.maybeOf(context);
    // «Sin salida» (25/10): si la casa ya no está en el teléfono no hay dónde guardar la visita; la
    // entrevista se suelta y la hoja se cierra con un aviso, para no dejar trabado el cierre de la
    // jornada.
    var sinLugar = false;
    final resultado = await mostrarHojaTerminoEntrevista(
      context,
      direccion: rotulo.direccion,
      persona: rotulo.persona,
      entrada: entrevista.inicio,
      salida: salida,
      entradaInferida: false,
      reloj: reloj,
      alGuardar: (entrada, salida) async {
        final guardado = await notificador.finalizar(entrada: entrada, salida: salida);
        // `null`: ya había un guardado en curso (no pasa con la hoja, que lo impide).
        if (guardado == null) return const FailureInesperado();
        return guardado.fold<Failure?>((falla) {
          if (falla != entrevistaSinLugar) return falla;
          sinLugar = true;
          return null;
        }, (_) => null);
      },
    );
    if (resultado is EntrevistaGuardada) {
      mensajero?.showSnackBar(
        SnackBar(
          content: Text(
            sinLugar
                ? TextosEntrevista.sinLugar
                : TextosEntrevista.guardada(_lugar(rotulo.direccion)),
          ),
        ),
      );
    }
    if (resultado is QuiereRegistrarLaVenta && conVenta) {
      if (!context.mounted) return const VentaSinCompletar();
      return _registrarLaVenta(
        context,
        ref,
        colportorId: colportorId,
        persona: rotulo.persona,
        direccion: rotulo.direccion,
        desdeLaJornada: desdeLaJornada,
        preparar: () =>
            notificador.prepararVenta(entrada: resultado.entrada, salida: resultado.salida),
        guardarVisita: notificador.guardarVisitaDeLaVenta,
        soltar: notificador.soltarTrasLaVenta,
      );
    }
    return resultado;
  }

  /// R·07: «Terminó la entrevista» **sin inicio registrado**. La entrada es la hora de la visita
  /// anterior de la colportora (con el aviso de que se tomó de ahí) o, si no tiene ninguna, queda
  /// para elegir. La salida es «ahora». Los ids de la visita se fijan al abrir la hoja: reintentar
  /// tras una falla no la guarda dos veces.
  static Future<SalidaTerminoEntrevista?> terminarSinInicio(
    BuildContext context,
    WidgetRef ref, {
    required String colportorId,
    required String espacioId,
    required String espacioPersonaId,
    required String direccion,
    required String persona,
    String? agendaId,
    String? jornadaId,
  }) async {
    final notificador = ref.read(entrevistaEnCursoProvider(colportorId).notifier);
    final entrada = await notificador.horaDeLaVisitaAnterior();
    if (!context.mounted) return null;
    final reloj = ref.read(relojEntrevistaProvider);
    final ids = ref.read(registrarResultadoVisitaUseCaseProvider).nuevosIds();
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final resultado = await mostrarHojaTerminoEntrevista(
      context,
      direccion: direccion,
      persona: persona,
      entrada: entrada,
      salida: reloj(),
      entradaInferida: entrada != null,
      reloj: reloj,
      alGuardar: (entrada, salida) async {
        final guardado = await notificador.finalizarSinInicio(
          FinalizarEntrevistaParams(
            ids: ids,
            espacioId: espacioId,
            espacioPersonaId: espacioPersonaId,
            colportorId: colportorId,
            entrada: entrada,
            salida: salida,
            agendaId: agendaId,
            jornadaId: jornadaId,
            nota: ref.read(entrevistaEnCursoProvider(colportorId)).notaBorrador,
          ),
        );
        return guardado.fold<Failure?>((falla) => falla, (_) => null);
      },
    );
    if (resultado is EntrevistaGuardada) {
      mensajero?.showSnackBar(
        SnackBar(content: Text(TextosEntrevista.guardada(_lugar(direccion)))),
      );
    }
    if (resultado is QuiereRegistrarLaVenta) {
      if (!context.mounted) return const VentaSinCompletar();
      final casoDeUso = ref.read(cerrarEntrevistaConVentaUseCaseProvider);
      return _registrarLaVenta(
        context,
        ref,
        colportorId: colportorId,
        persona: persona,
        direccion: direccion,
        desdeLaJornada: false,
        // Sin entrevista en curso no hay nada que soltar: la visita se guarda con la venta.
        preparar: () => casoDeUso.preparar(
          FinalizarEntrevistaParams(
            ids: ids,
            espacioId: espacioId,
            espacioPersonaId: espacioPersonaId,
            colportorId: colportorId,
            entrada: resultado.entrada,
            salida: resultado.salida,
            agendaId: agendaId,
            jornadaId: jornadaId,
            nota: ref.read(entrevistaEnCursoProvider(colportorId)).notaBorrador,
          ),
        ),
        guardarVisita: casoDeUso.guardarVisita,
      );
    }
    return resultado;
  }

  /// «Sí, registrar la venta» (R·06 / R·07 → vista 27 → R·08; #428).
  ///
  /// 1. [preparar] arma la visita `VENTA` sin guardar nada. Si ya no hay casa o persona, un aviso dice
  ///    qué pasó y la entrevista sigue en curso.
  /// 2. Abre la venta con la casa, la persona y la visita puestas. Al registrarla, la visita `VENTA` se
  ///    guarda en la misma transacción ([guardarVisita]): si la venta no se guarda, la visita tampoco
  ///    (R44). Después, [soltar] cierra la entrevista en curso.
  /// 3. 27A·14 «Venta registrada: ¿y ahora?»: «Cobrar ahora» abre el cobro (vista 28). El grupo ENTREGA
  ///    llega con HU-VEN-002 (#159, #160): hasta entonces no se dibuja.
  /// 4. Con saldo —lo que quedó sin cobrar—, pregunta «¿Cuándo volvés a cobrar?» y agenda la cobranza
  ///    (decisión «Agenda cobro»).
  /// 5. R·08: vuelve a la casa, que ya muestra la cobranza pendiente y la cita con «Cambiar».
  static Future<SalidaTerminoEntrevista> _registrarLaVenta(
    BuildContext context,
    WidgetRef ref, {
    required String colportorId,
    required String persona,
    required String direccion,
    required bool desdeLaJornada,
    required Future<Either<Failure, VentaDeLaEntrevista>> Function() preparar,
    required Future<void> Function(VentaDeLaEntrevista) guardarVisita,
    Future<Either<Failure, Unit>> Function(VentaDeLaEntrevista)? soltar,
  }) async {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final navegador = Navigator.of(context);
    // Al guardar la venta la entrevista se suelta y el aviso fijo del mapa (de donde puede venir este
    // flujo) sale del árbol: su `context` y su `ref` se desmontan a mitad de camino. Lo que sigue usa
    // el contexto del navegador y el contenedor, que duran lo que dura la app.
    final contenedor = ProviderScope.containerOf(context);
    final contextoFirme = navegador.context;
    void avisar(String texto) => mensajero
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(texto)));
    final noSeGuardo = desdeLaJornada
        ? TextosEntrevista.ventaNoGuardadaEnLaJornada(persona)
        : TextosEntrevista.ventaNoGuardada(persona);

    VentaDeLaEntrevista? venta;
    Failure? falla;
    try {
      (await preparar()).fold((f) => falla = f, (v) => venta = v);
    } on Object {
      falla = const FailureInesperado();
    }
    final preparada = venta;
    if (preparada == null) {
      // Las fallas de validación ya dicen qué pasó y qué hacer; cualquier otra, el aviso común.
      final f = falla;
      avisar(f is FailureValidacion ? TextosEntrevista.ventaNoGuardadaCon(f.mensaje) : noSeGuardo);
      return const VentaSinCompletar();
    }

    final cliente = await _cliente(ref, preparada, persona: persona, direccion: direccion);
    if (!context.mounted) return const VentaSinCompletar();
    final guardada = await navegador.push(
      NuevaVentaPage.ruta(
        argumentos: ArgumentosDeVenta(
          colportorId: colportorId,
          cliente: cliente,
          visitaId: preparada.visitaId,
        ),
        antesDeGuardar: () => guardarVisita(preparada),
      ),
    );
    if (guardada == null) {
      avisar(noSeGuardo);
      return const VentaSinCompletar();
    }

    // La venta y la visita ya están guardadas: lo que sigue no las deshace.
    var cerrada = true;
    if (soltar != null) {
      try {
        cerrada = (await soltar(preparada)).isRight();
      } on Object {
        cerrada = false;
      }
    }
    final numero = guardada.venta.numeroTalonario;
    // El «Venta 0039 guardada.» se dice después de «Venta registrada» y del cobro: antes taparía sus
    // botones, abajo de todo.
    void avisarLaVenta() => avisar(
      cerrada
          ? TextosEntrevista.ventaGuardada(numero)
          : TextosEntrevista.ventaGuardadaEntrevistaAbierta,
    );

    Agenda? cita;
    if (contextoFirme.mounted) {
      final cobrar = contenedor.read(cobrarDespuesDeLaVentaProvider);
      final seguimiento = await _ventaRegistrada(
        contextoFirme,
        guardada: guardada,
        nombre: cliente.nombre,
        conCobro: cobrar != null,
      );
      var saldo = guardada.totalCentavos;
      if (seguimiento?.cobrarAhora == true && cobrar != null) {
        saldo = await _cobrarAhora(
          contenedor,
          cobrar,
          guardada: guardada,
          espacioId: preparada.espacioId,
          espacioPersonaId: preparada.espacioPersonaId,
          colportorId: colportorId,
        );
      }
      avisarLaVenta();
      if (contextoFirme.mounted) {
        await FlujoCuandoCobrar.preguntar(
          contextoFirme,
          contenedor,
          guardada: guardada,
          espacioId: preparada.espacioId,
          espacioPersonaId: preparada.espacioPersonaId,
          colportorId: colportorId,
          persona: cliente.nombre,
          direccion: cliente.direccion,
          saldoCentavos: saldo,
          alAgendar: (agenda) => cita = agenda,
        );
      }
    } else {
      avisarLaVenta();
    }
    if (!desdeLaJornada) {
      await _volverALaCasa(
        contenedor,
        colportorId,
        preparada.espacioId,
        cobranza: cita,
        persona: cliente.nombre,
      );
    }
    return VentaGuardadaEnLaEntrevista(numeroTalonario: numero);
  }

  /// 27A·14 «Venta registrada: ¿y ahora?». Sin salida del atrás: se sale con «Listo» (o «Terminar sin
  /// nada») y es lo que elige lo que se hace después. `null` = terminó sin pedir nada.
  static Future<SeguimientoDeLaVenta?> _ventaRegistrada(
    BuildContext context, {
    required VentaGuardada guardada,
    required String nombre,
    required bool conCobro,
  }) => Navigator.of(context).push<SeguimientoDeLaVenta>(
    MaterialPageRoute(
      builder: (ruta) => VentaRegistradaPage(
        guardada: guardada,
        nombreDelCliente: nombre,
        conCobro: conCobro,
        alContinuar: (seguimiento) => Navigator.of(ruta).pop(seguimiento),
        alTerminar: () => Navigator.of(ruta).pop(),
      ),
    ),
  );

  /// «Cobrar ahora»: abre el cobro (vista 28) y devuelve lo que quedó sin cobrar, en centavos. Si no
  /// se cobró, o no se puede leer cuánto, es el total de la venta: preguntar «¿Cuándo volvés a cobrar?»
  /// de más es mejor que dejar una deuda sin cita.
  static Future<int> _cobrarAhora(
    ProviderContainer ref,
    Future<bool> Function(ContextoDeCobroDeLaVenta) cobrar, {
    required VentaGuardada guardada,
    required String espacioId,
    required String espacioPersonaId,
    required String colportorId,
  }) async {
    final total = guardada.totalCentavos;
    try {
      final cobrado = await cobrar((
        ventaId: guardada.venta.id,
        espacioId: espacioId,
        espacioPersonaId: espacioPersonaId,
        colportorId: colportorId,
      ));
      if (!cobrado) return total;
      final venta = await ref
          .read(saldoPendienteRepositoryProvider)
          .observarVenta(guardada.venta.id)
          .first
          .timeout(const Duration(seconds: 2));
      return venta?.saldoCentavos ?? total;
    } on Object {
      return total;
    }
  }

  /// A quién y dónde se le vende: el nombre y «Mataojo 2044 · Depto 3B» de lo que hoy hay en el
  /// teléfono; si no se pueden leer, lo que ya mostraba la entrevista.
  static Future<ClienteDeLaVenta> _cliente(
    WidgetRef ref,
    VentaDeLaEntrevista venta, {
    required String persona,
    required String direccion,
  }) async {
    var nombre = persona.trim();
    var lugar = direccion.trim();
    try {
      final contexto = (await ref.read(espacioRepositoryProvider).buscar(venta.espacioId)).fold(
        (_) => null,
        (c) => c,
      );
      if (contexto != null) {
        lugar = FormatoPersonas.dondeEstaElEspacio(contexto.espacio, contexto.ubicacion);
      }
    } on Object {
      // Se queda con la dirección que ya mostraba la entrevista.
    }
    try {
      final personas = await ref
          .read(personaRepositoryProvider)
          .observarDelEspacio(venta.espacioId)
          .first
          .timeout(const Duration(seconds: 2));
      for (final p in personas) {
        if (p.vinculo.id == venta.espacioPersonaId) {
          final leido = [
            p.persona.nombre,
            p.persona.apellido,
          ].where((t) => t.trim().isNotEmpty).join(' ');
          if (leido.isNotEmpty) nombre = leido;
          break;
        }
      }
    } on Object {
      // Se queda con el nombre que ya mostraba la entrevista.
    }
    return ClienteDeLaVenta(
      espacioPersonaId: venta.espacioPersonaId,
      nombre: nombre.isEmpty ? TextosEntrevista.sinNombre : nombre,
      direccion: lugar,
    );
  }

  /// R·08: la casa de la venta queda elegida en el mapa, con su hoja abierta: ahí están la cobranza
  /// pendiente («$ Cobrar») y, si quedó agendada ([cobranza]), su tarjeta con «Cambiar». Si el mapa
  /// no está montado, no hace nada.
  static Future<void> _volverALaCasa(
    ProviderContainer ref,
    String colportorId,
    String espacioId, {
    Agenda? cobranza,
    String persona = '',
  }) async {
    try {
      // La hoja que ya estaba abierta lee de nuevo: lo que la persona debe cambió con la venta (y con
      // «Cobrar ahora»), y el contexto de la casa solo se entera si se lo pide (QA de #428, R·08).
      ref.invalidate(contextoDeLaCasaProvider);
      final proveedor = mapaUbicacionesProvider(colportorId);
      if (!ref.exists(proveedor)) return;
      final lugar = (await ref.read(espacioRepositoryProvider).buscar(espacioId)).fold<String?>(
        (_) => null,
        (c) => c?.ubicacion.id,
      );
      if (lugar == null || !ref.exists(proveedor)) return;
      if (cobranza != null) {
        ref.read(cobranzaRecienAgendadaProvider.notifier).marcar((
          ubicacionId: lugar,
          agendaId: cobranza.id,
          persona: persona,
        ));
      }
      ref.read(proveedor.notifier).seleccionar(lugar);
    } on Object {
      // Sin la casa elegida, la colportora igual la toca en el mapa: no se rompe nada.
    }
  }

  static Future<RotuloEntrevista> _rotulo(WidgetRef ref, EntrevistaEnCurso entrevista) async {
    try {
      return await ref.read(rotuloDeEntrevistaProvider(entrevista).future);
    } on Object {
      return (direccion: '', persona: '');
    }
  }

  /// «Grecia 3307», o «La casa» si no se sabe la dirección.
  static String _lugar(String direccion) => direccion.isEmpty ? 'La casa' : direccion;
}
