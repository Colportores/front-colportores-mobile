import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/presentation/flujo_agendar_visita.dart';
import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../domain/entities/ficha_de_persona.dart';
import '../../domain/services/filtro_de_historial.dart';
import '../../domain/usecases/ficha_persona_use_cases.dart';
import '../../domain/usecases/restaurar_espacio_use_case.dart';
import '../formato_espacios.dart';
import '../providers/baja_persona_providers.dart';
import '../providers/espacios_providers.dart';
import '../providers/ficha_persona_providers.dart';
import '../providers/hoja_casa_providers.dart';
import '../providers/personas_providers.dart';
import '../textos_baja_persona.dart';
import '../textos_ficha_persona.dart';
import '../textos_notas.dart';
import '../textos_personas.dart';
import '../widgets/hoja_baja_persona.dart';
import '../widgets/piezas_alta.dart';
import '../widgets/piezas_ficha_persona.dart';
import '../widgets/piezas_notas.dart';
import 'nota_persona_form_page.dart';
import 'notas_de_persona_page.dart';

/// La ficha de una persona (HU-UBI-009, vista 32B): su teléfono (enmascarado hasta tocar «Ver», con
/// «Llamar»), lo que compró, recibió y pagó, la última nota y el historial por fecha. Se abre desde la
/// pestaña Personas de la hoja de la casa, con la persona y el espacio ya resueltos, y al terminar
/// vuelve a ella.
///
/// - Cargando (32B·06), error al leer con «Reintentar» (32B·07) y sin historial (32B·05) son estados
///   propios. Sin conexión es igual que con: todo es local.
/// - **Solo lectura** con la persona de baja (32B·04, «Reactivar») o su depto de baja (32B·08,
///   «Reactivar el depto»; decisión de Cristian del 23/10): se ve todo el historial y las notas, y no se
///   agrega ni se cambia nada. «Llamar» no escribe nada, así que sigue.
/// - El teléfono se vuelve a ocultar al salir: no se guarda.
/// - Más de 100 movimientos: se muestran de a 100 con «Ver más».
/// - «MOSTRAR» (32B·03) filtra el historial por estado: «Todo», «Con saldo» o «Entrega pendiente». No
///   se guarda: al reentrar vuelve a «Todo».
/// - Bajo la cuenta, las acciones rápidas de HU-VEN-005 (32B·01): «+ Agendar cobranza» abre «Agendar
///   visita» de cobranza con la casa y la persona puestas, y «Registrar entrega» abre la pantalla de
///   entregas pendientes (`registrarEntregaDesdeLaFichaProvider`; sin destino no se dibuja). No están
///   con la persona de baja o el depto de baja (32B·04 y 32B·08), ni en la ficha vacía (32B·05) ni
///   sin ventas. Con una de las dos abriéndose, la otra queda apagada.
/// - La ubicación alternativa es de la vista 22: no está acá.
class FichaPersonaPage extends ConsumerStatefulWidget {
  const FichaPersonaPage({
    super.key,
    required this.personaId,
    required this.espacioId,
    required this.colportorId,
  });

  final String personaId;

  /// El espacio desde el que se abrió (en un edificio, el depto).
  final String espacioId;

  /// UUID del usuario con la sesión iniciada (`created_by` de las notas nuevas).
  final String colportorId;

  /// De a cuántos movimientos se muestra el historial.
  static const pagina = 100;

  static Future<void> abrir(
    BuildContext context, {
    required String personaId,
    required String espacioId,
    required String colportorId,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          FichaPersonaPage(personaId: personaId, espacioId: espacioId, colportorId: colportorId),
    ),
  );

  @override
  ConsumerState<FichaPersonaPage> createState() => _FichaPersonaPageState();
}

enum _OpcionDelMenu { editar, baja }

class _FichaPersonaPageState extends ConsumerState<FichaPersonaPage> {
  /// «Ver» (32B·02): el teléfono entero hasta salir de la ficha. No se guarda.
  var _telefonoVisible = false;

  /// Cuántos movimientos se muestran.
  var _mostrar = FichaPersonaPage.pagina;

  /// El filtro por estado del historial (32B·03).
  var _filtro = FiltroDeHistorial.todo;

  /// Ya se está abriendo algo (el marcador, las notas, la baja, la edición): un segundo toque no abre
  /// otra cosa encima.
  var _abriendo = false;

  var _reactivandoPersona = false;
  var _reactivandoDepto = false;

  ClaveDeFicha get _clave => (personaId: widget.personaId, espacioId: widget.espacioId);

  void _reintentar() => ref.invalidate(fichaDePersonaProvider(_clave));

  void _avisar(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: MediaQuery.accessibleNavigationOf(context),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF0E1A2B),
          content: Text(texto),
        ),
      );
  }

  /// Corre [accion] si no hay otra cosa abriéndose. El guard se suelta pase lo que pase.
  Future<void> _unaAlaVez(Future<void> Function() accion) async {
    if (_abriendo) return;
    setState(() => _abriendo = true);
    try {
      await accion();
    } on Object {
      if (mounted) _avisar(TextosFicha.noPudimosAbrir);
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  Future<void> _llamar(FichaDePersona ficha) => _unaAlaVez(() async {
    final resultado = await ref.read(llamarAPersonaUseCaseProvider)(
      personaId: ficha.persona.id,
      telefono: ficha.persona.telefono,
    );
    if (!mounted) return;
    if (resultado == ResultadoDeLlamada.noSePudoAbrir) {
      _avisar(TextosFicha.noPudimosAbrirElTelefono);
    }
  });

  Future<void> _nuevaNota() => _unaAlaVez(() async {
    if (frenaPorCuentaRestringida(context, ref)) return;
    // Un aviso viejo taparía el botón de abajo del formulario.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final guardada = await NotaPersonaFormPage.abrir(
      context,
      personaId: widget.personaId,
      colportorId: widget.colportorId,
    );
    if (!mounted || guardada == null) return;
    mostrarAvisoDeNota(
      ScaffoldMessenger.of(context),
      mediaQuery: MediaQuery.of(context),
      texto: TextosNotas.guardada,
    );
  });

  Future<void> _verNotas() => _unaAlaVez(
    () => NotasDePersonaPage.abrir(
      context,
      personaId: widget.personaId,
      colportorId: widget.colportorId,
    ),
  );

  Future<void> _editar() => _unaAlaVez(() async {
    if (frenaPorCuentaRestringida(context, ref)) return;
    final editar = ref.read(editarPersonaDesdeLaFichaProvider);
    if (editar == null) return;
    await editar(widget.personaId);
  });

  /// «+ Agendar cobranza» (32B·01, HU-VEN-005): «Agendar visita» de cobranza con la casa y la persona ya
  /// puestas. Al guardar vuelve acá con el aviso «Agendada…».
  Future<void> _agendarCobranza() => _unaAlaVez(() async {
    if (frenaPorCuentaRestringida(context, ref)) return;
    // El vínculo de la persona con este depto: la agenda cuelga de él.
    final personas = await ref
        .read(personaRepositoryProvider)
        .observarDelEspacio(widget.espacioId)
        .first;
    final vinculo = personas.where((p) => p.persona.id == widget.personaId).firstOrNull?.vinculo;
    if (!mounted) return;
    if (vinculo == null || widget.colportorId.trim().isEmpty) {
      _avisar(TextosFicha.noPudimosAbrir);
      return;
    }
    await FlujoAgendarVisita.abrir(
      context,
      espacioId: widget.espacioId,
      espacioPersonaId: vinculo.id,
      colportorId: widget.colportorId,
      tipo: TipoAgenda.cobranza,
    );
  });

  /// «Registrar entrega» (32B·01, HU-VEN-005): la pantalla de entregas pendientes de esta persona. Al
  /// volver, la ficha, que lee en vivo, ya muestra lo entregado.
  Future<void> _registrarEntrega() => _unaAlaVez(() async {
    final destino = ref.read(registrarEntregaDesdeLaFichaProvider);
    if (destino == null) return;
    if (frenaPorCuentaRestringida(context, ref)) return;
    await destino((personaId: widget.personaId, espacioId: widget.espacioId));
  });

  Future<void> _darDeBaja(FichaDePersona ficha) => _unaAlaVez(() async {
    if (frenaPorCuentaRestringida(context, ref)) return;
    await mostrarHojaBajaPersona(context, persona: ficha.persona);
  });

  /// Tocar una venta del historial abre su devolución (vista 31, HU-VEN-004). Al volver, la ficha, que
  /// lee en vivo, ya muestra el saldo nuevo.
  Future<void> _devolver(String ventaId) => _unaAlaVez(() async {
    final destino = ref.read(devolverVentaDesdeLaFichaProvider);
    if (destino == null) return;
    if (frenaPorCuentaRestringida(context, ref)) return;
    await destino((ventaId: ventaId, personaId: widget.personaId, espacioId: widget.espacioId));
  });

  Future<void> _registrarVisita(FichaDePersona ficha) => _unaAlaVez(() async {
    final destino = ref.read(registrarVisitaDesdeLaCasaProvider);
    final lugar = ficha.lugar;
    if (destino == null || lugar == null) return;
    await destino((ubicacionId: lugar.ubicacion.id, espacioId: widget.espacioId, agendaId: null));
  });

  /// «Reactivar» (32B·04): la persona vuelve a estar activa y la ficha, que lee en vivo, deja de ser de
  /// solo lectura. Si falla, el botón vuelve a quedar tocable y el aviso dice qué hacer.
  Future<void> _reactivarPersona(FichaDePersona ficha) async {
    if (_reactivandoPersona) return;
    if (frenaPorCuentaRestringida(context, ref)) return;
    final nombre = FormatoBajaPersona.nombreDePila(ficha.persona);
    setState(() => _reactivandoPersona = true);
    var salio = false;
    try {
      final r = await ref.read(reactivarPersonaUseCaseProvider)(ficha.persona.id);
      r.fold((falla) {
        if (mounted) {
          _avisar(mensajeDeFallaDePersona(falla, TextosFicha.noPudimosReactivar(nombre)));
        }
      }, (_) => salio = true);
    } on Object {
      if (mounted) _avisar(TextosFicha.noPudimosReactivar(nombre));
    } finally {
      if (mounted) setState(() => _reactivandoPersona = false);
    }
    if (salio && mounted) _avisar(TextosBajaPersona.activaDeNuevo(nombre));
  }

  /// «Reactivar el depto» (32B·08): el depto vuelve con todo lo suyo y la ficha deja de ser de solo
  /// lectura. Los mismos avisos que al reactivarlo desde la hoja de la ubicación.
  Future<void> _reactivarDepto(FichaDePersona ficha) async {
    final lugar = ficha.lugar;
    if (_reactivandoDepto || lugar == null) return;
    if (frenaPorCuentaRestringida(context, ref)) return;
    setState(() => _reactivandoDepto = true);
    Failure? falla;
    var salio = false;
    try {
      final r = await ref.read(restaurarEspacioUseCaseProvider)(
        RestaurarEspacioParams(id: lugar.espacio.id),
      );
      falla = r.fold<Failure?>((f) => f, (_) => null);
      salio = r.isRight();
    } on Object catch (causa) {
      falla = FailureInesperado(causa: causa);
    } finally {
      if (mounted) setState(() => _reactivandoDepto = false);
    }
    if (!mounted) return;
    if (salio) {
      _avisar(TextosEspacios.reactivado(lugar.espacio, lugar.ubicacion.tipo));
      return;
    }
    _avisar(switch (falla) {
      FailureValidacion(:final campos) when campos.containsKey('numeroDepto') =>
        TextosEspacios.reactivarRepetido(lugar.espacio, lugar.ubicacion.tipo),
      FailureValidacion(:final campos) when campos.containsKey('ubicacionId') =>
        TextosEspacios.ubicacionDeBaja,
      _ => TextosEspacios.noPudimosReactivar,
    });
  }

  @override
  Widget build(BuildContext context) {
    final lectura = ref.watch(fichaDePersonaProvider(_clave));
    final ficha = lectura.asData?.value;
    final ahora = ref.watch(relojPersonaProvider)();
    final editar = ref.watch(editarPersonaDesdeLaFichaProvider);

    final Widget cuerpo;
    if (lectura.hasError && ficha == null) {
      cuerpo = _Mensaje(
        clave: ClavesFicha.error,
        texto: TextosFicha.noPudimosLeer(null),
        alReintentar: _reintentar,
      );
    } else if (lectura.hasValue && ficha == null) {
      cuerpo = const _Mensaje(texto: TextosFicha.personaNoEncontrada);
    } else if (ficha == null) {
      cuerpo = const SingleChildScrollView(child: CargandoFicha(nombre: null));
    } else {
      cuerpo = _CuerpoDeLaFicha(
        ficha: ficha,
        ahora: ahora,
        telefonoVisible: _telefonoVisible,
        mostrar: _mostrar,
        filtro: _filtro,
        reactivandoPersona: _reactivandoPersona,
        reactivandoDepto: _reactivandoDepto,
        puedeRegistrarVisita: ref.watch(registrarVisitaDesdeLaCasaProvider) != null,
        alVerTelefono: () => setState(() => _telefonoVisible = true),
        alLlamar: _abriendo ? null : () => _llamar(ficha),
        alAgregarTelefono: editar == null || ficha.soloLectura ? null : _editar,
        alNuevaNota: _nuevaNota,
        alVerNotas: _verNotas,
        alVerMas: () => setState(() => _mostrar += FichaPersonaPage.pagina),
        alElegirFiltro: (f) => setState(() {
          _filtro = f;
          _mostrar = FichaPersonaPage.pagina;
        }),
        alDevolver: ref.watch(devolverVentaDesdeLaFichaProvider) == null || ficha.soloLectura
            ? null
            : _devolver,
        alRegistrarVisita: () => _registrarVisita(ficha),
        conEntrega: ref.watch(registrarEntregaDesdeLaFichaProvider) != null,
        ocupado: _abriendo,
        alAgendarCobranza: _agendarCobranza,
        alRegistrarEntrega: _registrarEntrega,
        alReactivarPersona: () => _reactivarPersona(ficha),
        alReactivarDepto: () => _reactivarDepto(ficha),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Cabecera(
              alVolver: () => Navigator.of(context).maybePop(),
              // Sin la ficha, o en solo lectura, no hay nada que cambiar desde acá.
              alElegir: ficha == null || ficha.soloLectura ? null : _elegir,
              conEditar: editar != null,
              ficha: ficha,
            ),
            Expanded(child: cuerpo),
          ],
        ),
      ),
    );
  }

  void _elegir(_OpcionDelMenu opcion) {
    final ficha = ref.read(fichaDePersonaProvider(_clave)).asData?.value;
    if (ficha == null) return;
    switch (opcion) {
      case _OpcionDelMenu.editar:
        unawaited(_editar());
      case _OpcionDelMenu.baja:
        unawaited(_darDeBaja(ficha));
    }
  }
}

/// La fila de arriba: atrás, «PERSONA» y el menú «⋯».
class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.alVolver,
    required this.alElegir,
    required this.conEditar,
    required this.ficha,
  });

  final VoidCallback alVolver;

  /// `null`: sin menú (todavía no hay ficha, o es de solo lectura).
  final ValueChanged<_OpcionDelMenu>? alElegir;
  final bool conEditar;
  final FichaDePersona? ficha;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 6, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: TextosFicha.volver,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: alVolver,
            icon: const Icon(Icons.chevron_left, size: 28),
          ),
          Expanded(
            child: Text(
              TextosFicha.rotulo,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w500,
                color: navy,
              ),
            ),
          ),
          if (alElegir != null)
            PopupMenuButton<_OpcionDelMenu>(
              key: ClavesFicha.menu,
              tooltip: TextosFicha.masOpciones,
              icon: const Icon(Icons.more_horiz),
              iconSize: 28,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onSelected: alElegir,
              itemBuilder: (_) => [
                if (conEditar)
                  const PopupMenuItem(
                    key: ClavesFicha.opcionEditar,
                    value: _OpcionDelMenu.editar,
                    child: Text(TextosFicha.editarPersona),
                  ),
                const PopupMenuItem(
                  key: ClavesFicha.opcionBaja,
                  value: _OpcionDelMenu.baja,
                  child: Text(TextosFicha.darDeBaja),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Un estado que no es la ficha (error al leer, persona que no está): el mensaje, centrado y
/// desplazable.
class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.texto, this.alReintentar, this.clave});

  final String texto;
  final VoidCallback? alReintentar;
  final Key? clave;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: clave,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: alReintentar == null
          ? Text(texto, style: Theme.of(context).textTheme.bodyLarge)
          : AvisoAlta(
              color: ColoresAlta.rojo,
              glyph: '!',
              texto: texto,
              acciones: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: alReintentar,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: ColoresAlta.azul,
                  ),
                  child: const Text(TextosFicha.reintentar),
                ),
              ),
            ),
    );
  }
}

class _CuerpoDeLaFicha extends StatelessWidget {
  const _CuerpoDeLaFicha({
    required this.ficha,
    required this.ahora,
    required this.telefonoVisible,
    required this.mostrar,
    required this.filtro,
    required this.reactivandoPersona,
    required this.reactivandoDepto,
    required this.puedeRegistrarVisita,
    required this.alVerTelefono,
    required this.alLlamar,
    required this.alAgregarTelefono,
    required this.alNuevaNota,
    required this.alVerNotas,
    required this.alVerMas,
    required this.alElegirFiltro,
    required this.alDevolver,
    required this.alRegistrarVisita,
    required this.conEntrega,
    required this.ocupado,
    required this.alAgendarCobranza,
    required this.alRegistrarEntrega,
    required this.alReactivarPersona,
    required this.alReactivarDepto,
  });

  final FichaDePersona ficha;
  final DateTime ahora;
  final bool telefonoVisible;
  final int mostrar;
  final FiltroDeHistorial filtro;
  final bool reactivandoPersona;
  final bool reactivandoDepto;
  final bool puedeRegistrarVisita;
  final VoidCallback alVerTelefono;
  final VoidCallback? alLlamar;
  final VoidCallback? alAgregarTelefono;
  final VoidCallback alNuevaNota;
  final VoidCallback alVerNotas;
  final VoidCallback alVerMas;
  final ValueChanged<FiltroDeHistorial> alElegirFiltro;

  /// `null`: las ventas no se tocan (ficha de solo lectura, sin destino o ya abriéndose algo).
  final ValueChanged<String>? alDevolver;
  final VoidCallback alRegistrarVisita;

  /// Hay a dónde llevar «Registrar entrega»; sin destino el botón no se dibuja.
  final bool conEntrega;

  /// Ya se está abriendo algo: las acciones rápidas quedan apagadas.
  final bool ocupado;
  final VoidCallback alAgendarCobranza;
  final VoidCallback alRegistrarEntrega;
  final VoidCallback alReactivarPersona;
  final VoidCallback alReactivarDepto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final persona = ficha.persona;
    final nombreCompleto = FormatoPersonas.nombreCompleto(persona);
    final lugar = ficha.lugar;
    final subtitulo = lugar == null
        ? null
        : FormatoPersonas.dondeEstaElEspacio(lugar.espacio, lugar.ubicacion);
    final soloLectura = ficha.soloLectura;
    final historial = ficha.historial;
    final vacia = historial.isEmpty && ficha.resumen == null;
    final opciones = FiltroDeHistorialDeFicha.disponibles(ficha.resumen);
    // Si la opción elegida dejó de estar (la cuenta se dejó de saber), vale «Todo».
    final filtro = opciones.contains(this.filtro) ? this.filtro : FiltroDeHistorial.todo;
    final filtrado = FiltroDeHistorialDeFicha.aplicar(historial, filtro, resumen: ficha.resumen);
    final visibles = filtrado.length <= mostrar ? filtrado : filtrado.sublist(0, mostrar);
    final faltan = filtrado.length - visibles.length;
    final notas = ficha.notas;
    // 32B·05: la persona sin nada que mostrar ve solo el aviso de que todavía no hay visitas ni ventas.
    final mostrarNotas = notas.total > 0 || !vacia;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Semantics(
          header: true,
          child: Text(
            nombreCompleto.isEmpty ? TextosFicha.rotulo : nombreCompleto,
            style: theme.textTheme.headlineMedium,
          ),
        ),
        if (subtitulo != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitulo, style: theme.textTheme.bodyMedium),
          ),
        const SizedBox(height: 14),
        if (soloLectura) ...[
          _AvisoSoloLectura(
            ficha: ficha,
            ahora: ahora,
            reactivandoPersona: reactivandoPersona,
            reactivandoDepto: reactivandoDepto,
            alReactivarPersona: alReactivarPersona,
            alReactivarDepto: alReactivarDepto,
          ),
          const SizedBox(height: 10),
        ],
        TarjetaTelefono(
          telefono: persona.telefono,
          visible: telefonoVisible,
          alVer: alVerTelefono,
          alLlamar: alLlamar,
          alAgregar: alAgregarTelefono,
        ),
        if (vacia)
          FichaSinHistorial(
            nombre: FormatoBajaPersona.nombreDePila(persona),
            alRegistrarVisita: soloLectura || !puedeRegistrarVisita || lugar == null
                ? null
                : alRegistrarVisita,
          )
        else ...[
          const SizedBox(height: 8),
          // Sin ventas no hay cuenta que sumar: lo dice la HU («Sin movimientos aún»), sin inventar un $ 0.
          if (ficha.resumen case final cuenta?) ...[
            TarjetaCuenta(cuenta: cuenta),
            // 32B·01: agendar la cobranza y registrar la entrega sin salir de la ficha. Con la persona o
            // el depto de baja (32B·04 y 32B·08) la ficha es de solo lectura y no se ofrecen. Cada acción
            // aparece solo si hay algo que hacer (decisión del 30/10, regla R4): «Agendar cobranza» con
            // saldo y «Registrar entrega» con entregas pendientes; sin ninguna, no hay bloque.
            if (!soloLectura &&
                lugar != null &&
                (cuenta.tieneSaldo || (conEntrega && cuenta.entregasPendientes > 0))) ...[
              const SizedBox(height: 10),
              AccionesRapidasDeLaFicha(
                conCobranza: cuenta.tieneSaldo,
                conEntrega: conEntrega && cuenta.entregasPendientes > 0,
                ocupado: ocupado,
                alAgendarCobranza: alAgendarCobranza,
                alRegistrarEntrega: alRegistrarEntrega,
              ),
            ],
          ] else
            const SinMovimientosDeCuenta(),
        ],
        if (mostrarNotas) ...[
          const SizedBox(height: 14),
          _SeccionDeNotas(
            notas: notas,
            ahora: ahora,
            soloLectura: soloLectura,
            alNuevaNota: alNuevaNota,
            alVerNotas: alVerNotas,
          ),
        ],
        if (historial.isNotEmpty) ...[
          const SizedBox(height: 14),
          FiltroDelHistorial(opciones: opciones, elegido: filtro, alElegir: alElegirFiltro),
          const SizedBox(height: 14),
          const RotuloDeSeccion(texto: TextosFicha.historial),
          const SizedBox(height: 6),
          if (filtrado.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                TextosFicha.sinResultadosDelFiltro(filtro),
                key: ClavesFicha.sinResultados,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          Column(
            key: ClavesFicha.historial,
            children: [
              for (final m in visibles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilaDeHistorial(
                    movimiento: m,
                    ahora: ahora,
                    alTocar: m is VentaEnFicha && alDevolver != null
                        ? () => alDevolver!(m.id)
                        : null,
                  ),
                ),
            ],
          ),
          if (faltan > 0)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                key: ClavesFicha.verMas,
                onPressed: alVerMas,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: ColoresAlta.azul,
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                child: Text(TextosFicha.verMas(faltan)),
              ),
            ),
        ],
      ],
    );
  }
}

/// «NOTAS · SOLO EN TU TELÉFONO» con «+ Nota» (o «Ver (2)» en solo lectura) y la última nota.
class _SeccionDeNotas extends StatelessWidget {
  const _SeccionDeNotas({
    required this.notas,
    required this.ahora,
    required this.soloLectura,
    required this.alNuevaNota,
    required this.alVerNotas,
  });

  final NotasDeLaFicha notas;
  final DateTime ahora;
  final bool soloLectura;
  final VoidCallback alNuevaNota;
  final VoidCallback alVerNotas;

  @override
  Widget build(BuildContext context) {
    final ultima = notas.ultima;
    return Column(
      key: ClavesFicha.notas,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RotuloDeSeccion(
          texto: TextosFicha.notasRotulo,
          accion: soloLectura ? TextosFicha.verNotas(notas.total) : TextosFicha.masNota,
          alAccion: soloLectura ? (notas.total == 0 ? null : alVerNotas) : alNuevaNota,
          claveAccion: ClavesFicha.botonNota,
        ),
        if (ultima == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(TextosFicha.sinNotas, style: Theme.of(context).textTheme.bodyMedium),
          )
        else
          TarjetaUltimaNota(
            rotulo: FormatoFicha.rotuloDeLaNota(ultima, notas.total, ahora),
            texto: FormatoFicha.vistaPrevia(ultima.texto),
            alTocar: alVerNotas,
          ),
      ],
    );
  }
}

/// El aviso de solo lectura (32B·04 y 32B·08) con su «Reactivar» o «Reactivar el depto». El del depto
/// solo se ofrece si el depto es lo que está de baja y su ubicación sigue activa: si la ubicación
/// también está de baja, el depto no puede volver solo.
class _AvisoSoloLectura extends StatelessWidget {
  const _AvisoSoloLectura({
    required this.ficha,
    required this.ahora,
    required this.reactivandoPersona,
    required this.reactivandoDepto,
    required this.alReactivarPersona,
    required this.alReactivarDepto,
  });

  final FichaDePersona ficha;
  final DateTime ahora;
  final bool reactivandoPersona;
  final bool reactivandoDepto;
  final VoidCallback alReactivarPersona;
  final VoidCallback alReactivarDepto;

  @override
  Widget build(BuildContext context) {
    final lugar = ficha.lugar;
    final String? etiqueta;
    final bool ocupado;
    final VoidCallback? alTocar;
    final Key clave;
    if (ficha.personaDeBaja) {
      etiqueta = TextosFicha.reactivar;
      ocupado = reactivandoPersona;
      alTocar = alReactivarPersona;
      clave = ClavesFicha.botonReactivar;
    } else if (lugar != null && lugar.espacio.estaBorrada && !lugar.ubicacion.estaBorrada) {
      etiqueta = TextosFicha.reactivarDepto;
      ocupado = reactivandoDepto;
      alTocar = alReactivarDepto;
      clave = ClavesFicha.botonReactivarDepto;
    } else {
      etiqueta = null;
      ocupado = false;
      alTocar = null;
      clave = ClavesFicha.aviso;
    }
    return KeyedSubtree(
      key: ClavesFicha.aviso,
      child: AvisoAlta(
        color: ColoresAlta.ambarBorde,
        colorInsignia: ColoresAlta.ambar,
        glyph: '!',
        texto: TextosFicha.avisoSoloLectura(
          ficha.contexto,
          ahora,
          ubicacionDeBaja: lugar?.ubicacion.estaBorrada ?? false,
        ),
        acciones: etiqueta == null
            ? null
            : Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: clave,
                  onPressed: ocupado ? null : alTocar,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: ColoresAlta.azul,
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  child: Text(ocupado ? TextosFicha.reactivando : etiqueta),
                ),
              ),
      ),
    );
  }
}
