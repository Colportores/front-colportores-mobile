import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../domain/entities/persona_del_espacio.dart';
import '../../domain/repositories/espacio_repository.dart' show EspacioConUbicacion;
import '../formato_espacios.dart' show TextosEspacios;
import '../formato_hoja_casa.dart';
import '../formato_ubicaciones.dart';
import '../providers/baja_persona_providers.dart';
import '../providers/hoja_casa_providers.dart';
import '../providers/personas_providers.dart';
import '../textos_personas.dart';
import '../widgets/bajas_de_personas.dart';
import '../widgets/hoja_depto.dart';
import '../widgets/piezas_alta.dart';
import '../widgets/piezas_visita_del_depto.dart';
import 'alta_persona_page.dart';

/// Las claves de la ficha del depto (vista 11·04).
abstract final class ClavesPersonasDelEspacio {
  static const editar = Key('personas_espacio_editar');
}

/// Los clientes de un departamento (HU-UBI-008, vista 11·04 «Departamento con sus clientes»): el título
/// del espacio y la lista de personas que el colportor guardó en él, con «+ Agregar cliente».
///
/// **Estado de la última visita y «Registrar visita»** (HU-VIS-005, #151): debajo del título, la píldora
/// con «Entrevista hecha · 20/09» (o «Sin visitas todavía») y el botón. Se registra por depto, no por
/// edificio: el botón lleva a «¿Qué pasó?» (vista 39, C·06) con este espacio puesto
/// ([registrarVisitaDesdeLaCasaProvider]); sin destino enganchado, o con el depto dado de baja, no se
/// ofrece. Al volver, el estado ya es el nuevo (se lee en vivo) y la pantalla sigue donde estaba.
///
/// **Se abre** tocando un depto en la hoja del edificio (vista 11·01) o con «Ver depto 102 ›» del
/// número repetido (11·03) (#679, decisión §2 del 10/11).
///
/// **«Editar»** (encabezado del canvas 11·04): abre la edición del depto (`HojaDepto`, 11·02 con los
/// datos cargados), donde también se da de baja. Al guardar, la ficha sigue abierta con el depto al
/// día; si se dio de baja, o se eligió «Ver depto N ›» de otro depto, la ficha se cierra y devuelve esa
/// salida ([SalidaHojaDepto]) a quien la abrió (la hoja del edificio la aplica). Con el depto dado de
/// baja no se ofrece (solo lectura: se reactiva desde «Dados de baja» de la hoja). Un doble toque abre
/// una sola edición; con la cuenta restringida avisa y no la abre.
///
/// Lo que el artboard dibuja y no es de esta pantalla queda fuera: las visitas de cada cliente
/// (todavía no hay visitas por persona que contar). Tampoco hay `›` en las filas: la ficha de la
/// persona (HU-UBI-009) es otro issue.
///
/// - Cargando, vacío, error al leer y espacio que ya no está son estados propios.
/// - Con el espacio dado de baja es de solo lectura: se ven los clientes y no se puede agregar.
/// - Al volver del alta con una persona nueva muestra «Guardamos a Jorge en este teléfono.» (32A·05).
/// - Con personas dadas de baja (HU-UBI-011) aparece «Mostrar bajas» (32D·04): las bajas se ven en gris,
///   con la fecha y el saldo si se conoce, y «Reactivar» las vuelve a la lista (32D·05). Con el espacio
///   dado de baja se ven pero no se reactivan. Son las piezas de `bajas_de_personas.dart`, las mismas
///   de la pestaña «Personas» de la hoja de la casa.
class PersonasDelEspacioPage extends ConsumerStatefulWidget {
  const PersonasDelEspacioPage({super.key, required this.espacioId, required this.colportorId});

  final String espacioId;

  /// UUID del usuario con la sesión iniciada (`created_by` de las altas).
  final String colportorId;

  /// Abre la ficha del depto [espacioId]. Devuelve la salida de su edición cuando la cierra (el depto
  /// se dio de baja, o se eligió «Ver depto N ›» de otro), o `null` si el colportor volvió.
  static Future<SalidaHojaDepto?> abrir(
    BuildContext context, {
    required String espacioId,
    required String colportorId,
  }) => Navigator.of(context).push<SalidaHojaDepto>(
    MaterialPageRoute(
      builder: (_) => PersonasDelEspacioPage(espacioId: espacioId, colportorId: colportorId),
    ),
  );

  @override
  ConsumerState<PersonasDelEspacioPage> createState() => _PersonasDelEspacioPageState();
}

class _PersonasDelEspacioPageState extends ConsumerState<PersonasDelEspacioPage>
    with BajasDePersonasDelEspacio {
  /// Ya se está abriendo el alta: un segundo toque no abre otra encima.
  var _abriendoAlta = false;

  /// Ya está abierta la edición del depto («Editar»): un segundo toque no abre otra encima.
  var _editando = false;

  /// Ya se está abriendo «Registrar visita»: un segundo toque no abre otro «¿Qué pasó?» encima. El botón
  /// no se apaga (apagado sobre el azul oscuro no se lee): el segundo toque simplemente no hace nada.
  var _registrando = false;

  /// El encabezado (título, última visita y «CLIENTES · N») va fijo, como en el canvas 11·04 (`flex:none`).
  /// Si medido ocupa más de [_topeDelEncabezado] de la altura (texto grande en una pantalla chica), pasa
  /// a desplazarse con la lista: así nada desborda y la lista de clientes no se queda sin lugar.
  var _encabezadoEnLista = false;
  final _claveDelEncabezado = GlobalKey();

  /// Qué parte de la altura puede ocupar el encabezado fijo.
  static const _topeDelEncabezado = 0.4;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cambió el tamaño o el texto: se vuelve a medir con el encabezado fijo.
    _encabezadoEnLista = false;
  }

  /// Mide el encabezado fijo después del cuadro y, si no entra en el tope, lo pasa a la lista.
  void _medirEncabezado(double alturaDeLaPantalla) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _encabezadoEnLista) return;
      final tamano = _claveDelEncabezado.currentContext?.size;
      if (tamano != null && tamano.height > alturaDeLaPantalla * _topeDelEncabezado) {
        setState(() => _encabezadoEnLista = true);
      }
    });
  }

  /// «Registrar visita» de este depto. Si la apertura falla, el aviso dice qué hacer y el botón sigue
  /// tocable (la guarda se suelta pase lo que pase).
  Future<void> _registrarVisita(String ubicacionId) async {
    if (_registrando) return;
    final destino = ref.read(registrarVisitaDesdeLaCasaProvider);
    if (destino == null) return;
    _registrando = true;
    // Un aviso viejo (la falla de una vez anterior) se va con el nuevo intento.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    try {
      await destino((ubicacionId: ubicacionId, espacioId: widget.espacioId, agendaId: null));
    } on Object {
      if (mounted) _avisar(TextosHojaCasa.noPudimosAbrirVisita);
    } finally {
      _registrando = false;
    }
  }

  Future<void> _agregar() async {
    if (_abriendoAlta) return;
    // Con la cuenta restringida mientras esta pantalla estaba abierta no se da de alta a nadie.
    if (frenaPorCuentaRestringida(context, ref)) return;
    _abriendoAlta = true;
    try {
      final guardada = await AltaPersonaPage.abrir(
        context,
        espacioId: widget.espacioId,
        colportorId: widget.colportorId,
      );
      if (!mounted || guardada == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF0E1A2B),
            content: Text(TextosPersonas.guardada(guardada.nombre)),
          ),
        );
    } finally {
      _abriendoAlta = false;
    }
  }

  void _reintentar() {
    ref
      ..invalidate(contextoEspacioProvider(widget.espacioId))
      ..invalidate(personasDelEspacioProvider(widget.espacioId))
      ..invalidate(bajasDelEspacioProvider(widget.espacioId))
      ..invalidate(ultimaVisitaDelEspacioProvider(widget.espacioId));
  }

  void _avisar(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF0E1A2B),
          content: Text(texto),
        ),
      );
  }

  @override
  void avisarReactivada(String texto) => _avisar(texto);

  @override
  void avisarFallaAlReactivar(String texto) => _avisar(texto);

  /// «Editar» (11·04): la edición del depto (11·02 con los datos cargados), donde también se da de baja.
  Future<void> _editar(EspacioConUbicacion datos) async {
    if (_editando) return;
    // Con la cuenta restringida mientras esta pantalla estaba abierta no se edita el depto.
    if (frenaPorCuentaRestringida(context, ref)) return;
    _editando = true;
    SalidaHojaDepto? salida;
    try {
      salida = await mostrarHojaDepto(
        context,
        ubicacion: datos.ubicacion,
        colportorId: widget.colportorId,
        espacio: datos.espacio,
      );
    } finally {
      _editando = false;
    }
    if (!mounted) return;
    switch (salida) {
      case DeptoEditado():
        // El número o el piso cambiaron: el título se vuelve a leer.
        ref.invalidate(contextoEspacioProvider(widget.espacioId));
      case DeptoDadoDeBaja() || VerDeptoElegido():
        // Lo aplica la hoja del edificio (la baja, o abrir el otro depto): la ficha se cierra.
        Navigator.of(context).pop(salida);
      case DeptoAgregado() || null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final contexto = ref.watch(contextoEspacioProvider(widget.espacioId));
    final personas = ref.watch(personasDelEspacioProvider(widget.espacioId));
    final datos = contexto.asData?.value;
    final noEncontrado = contexto.hasValue && datos == null;
    final deBaja =
        datos != null && (datos.espacio.auditoria.estaBorrada || datos.ubicacion.estaBorrada);
    final puedeAgregar = datos != null && !deBaja;
    final cantidad = personas.asData?.value.length;
    // El estado de la última visita: sin la lectura (cargando o con error) no se dice ninguno.
    final ultima = ref.watch(ultimaVisitaDelEspacioProvider(widget.espacioId));
    final destinoDeVisita = ref.watch(registrarVisitaDesdeLaCasaProvider);
    final puedeRegistrar = datos != null && !deBaja && destinoDeVisita != null;

    // El cuerpo: una pieza por renglón de la lista que se desplaza.
    final List<Widget Function()> cuerpo;
    if (contexto.hasError || personas.hasError) {
      cuerpo = [() => _ErrorDeLectura(alReintentar: _reintentar)];
    } else if (noEncontrado) {
      cuerpo = [() => const _Mensaje(texto: TextosPersonas.espacioNoEncontrado)];
    } else if (!contexto.hasValue || !personas.hasValue) {
      cuerpo = [() => const _Cargando()];
    } else {
      cuerpo = _itemsDeClientes(
        clientes: personas.requireValue,
        deBaja: deBaja,
        bajas: piezasDeBajas(
          espacioId: widget.espacioId,
          // Con el espacio dado de baja es de solo lectura: las bajas se ven y no se reactivan.
          puedeReactivar: puedeAgregar,
          ahora: ref.read(relojPersonaProvider)(),
        ),
      );
    }
    final encabezado = <Widget Function()>[
      if (datos != null)
        () => _Titulo(
          titulo: FormatoPersonas.tituloEspacio(datos.espacio, datos.ubicacion),
          piso: FormatoPersonas.pisoDelEspacio(datos.espacio),
        ),
      if (datos != null)
        () => VisitaDelDepto(
          conEstado: ultima.hasValue,
          ultima: ultima.asData?.value,
          alRegistrar: puedeRegistrar ? () => _registrarVisita(datos.ubicacion.id) : null,
        ),
      () => const Divider(height: 1),
      () => _EncabezadoClientes(cantidad: cantidad, alAgregar: puedeAgregar ? _agregar : null),
    ];

    // Depende del tamaño y del texto: cuando cambian se vuelve a medir (`didChangeDependencies`).
    final alto = MediaQuery.sizeOf(context).height;
    MediaQuery.textScalerOf(context);
    if (!_encabezadoEnLista) _medirEncabezado(alto);

    final Widget lista;
    if (_encabezadoEnLista) {
      final items = [...encabezado, ...cuerpo];
      lista = ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: items.length,
        itemBuilder: (context, i) => items[i](),
      );
    } else {
      lista = ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: cuerpo.length,
        itemBuilder: (context, i) => cuerpo[i](),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Cabecera(
              direccion: datos == null
                  ? null
                  : FormatoUbicaciones.direccion(datos.ubicacion).toUpperCase(),
              // El depto dado de baja es de solo lectura: no se edita (se reactiva desde la hoja).
              alEditar: datos == null || deBaja ? null : () => _editar(datos),
            ),
            if (!_encabezadoEnLista)
              // Sin tope propio de altura el encabezado se mide entero; lo que se ve nunca pasa del tope
              // (si lo pasa, el cuadro siguiente lo manda a la lista).
              ClipRect(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: alto * _topeDelEncabezado),
                  child: UnconstrainedBox(
                    constrainedAxis: Axis.horizontal,
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      key: _claveDelEncabezado,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final pieza in encabezado) pieza()],
                    ),
                  ),
                ),
              ),
            Expanded(child: lista),
          ],
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.direccion, required this.alEditar});

  final String? direccion;

  /// «Editar» del depto (canvas 11·04, a la derecha); `null` = no se ofrece.
  final VoidCallback? alEditar;

  /// Hasta cuánto crece «Editar» con el texto grande: al 300 % no entra al lado de «‹» en 320 dp.
  static const _escalaMaximaDeEditar = 2.0;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    // Con el texto grande la dirección no entra al lado de «Editar» (quedaría una letra por renglón):
    // va debajo, a todo el ancho.
    final grande = MediaQuery.textScalerOf(context).scale(14) > 20;
    final volver = IconButton(
      tooltip: TextosPersonas.volver,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.chevron_left, size: 28),
    );
    final textoDireccion = direccion == null
        ? null
        : Text(
            direccion!,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 10,
              letterSpacing: 2,
              fontWeight: FontWeight.w500,
              color: navy,
            ),
          );
    final editar = alEditar == null
        ? null
        : MediaQuery.withClampedTextScaling(
            maxScaleFactor: _escalaMaximaDeEditar,
            child: Semantics(
              button: true,
              label: TextosEspacios.editarDepartamento,
              onTap: alEditar,
              excludeSemantics: true,
              child: TextButton(
                key: ClavesPersonasDelEspacio.editar,
                onPressed: alEditar,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: ColoresAlta.azul,
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                child: const Text(TextosPersonas.editar),
              ),
            ),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 14, 4),
      child: grande && textoDireccion != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [volver, const Spacer(), ?editar]),
                Padding(padding: const EdgeInsets.only(left: 14), child: textoDireccion),
              ],
            )
          : Row(
              children: [
                volver,
                Expanded(child: textoDireccion ?? const SizedBox.shrink()),
                ?editar,
              ],
            ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({required this.titulo, required this.piso});

  final String titulo;
  final String? piso;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 4,
        spacing: 12,
        children: [
          Semantics(header: true, child: Text(titulo, style: theme.textTheme.headlineMedium)),
          if (piso != null) Text(piso!, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// «CLIENTES · 2» y «+ Agregar cliente». Sin [alAgregar] (espacio dado de baja o que no está) el
/// enlace no se muestra.
class _EncabezadoClientes extends StatelessWidget {
  const _EncabezadoClientes({required this.cantidad, required this.alAgregar});

  final int? cantidad;
  final VoidCallback? alAgregar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(
                cantidad == null ? 'CLIENTES' : TextosPersonas.clientes(cantidad!),
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: ColoresAlta.gris,
                ),
              ),
            ),
          ),
          if (alAgregar != null)
            Flexible(
              child: TextButton(
                onPressed: alAgregar,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: ColoresAlta.azul,
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                child: const Text(TextosPersonas.agregarCliente, textAlign: TextAlign.end),
              ),
            ),
        ],
      ),
    );
  }
}

/// Las filas de la lista de clientes, una por renglón de la lista que se desplaza: el aviso del espacio
/// dado de baja, los clientes (o «Todavía no hay clientes»), «Mostrar bajas» con las bajas y su error
/// ([bajas], las piezas compartidas de `bajas_de_personas.dart`) y la nota de privacidad.
List<Widget Function()> _itemsDeClientes({
  required List<PersonaDelEspacio> clientes,
  required bool deBaja,
  required List<Widget Function()> bajas,
}) {
  final avisoBaja = deBaja
      ? const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: AvisoAlta(
            color: ColoresAlta.ambarBorde,
            colorInsignia: ColoresAlta.ambar,
            glyph: '!',
            texto: TextosPersonas.espacioDeBaja,
          ),
        )
      : null;
  return [
    if (avisoBaja != null) () => avisoBaja,
    if (clientes.isEmpty) () => const _SinClientes(),
    for (final cliente in clientes) () => _FilaCliente(cliente: cliente),
    ...bajas,
    () => const _NotaDePrivacidad(),
  ];
}

class _FilaCliente extends StatelessWidget {
  const _FilaCliente({required this.cliente});

  final PersonaDelEspacio cliente;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final persona = cliente.persona;
    final nombre = FormatoPersonas.nombreCompleto(persona);
    final gris = theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$nombre. ${FormatoPersonas.telefonoParaLector(persona.telefono)}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.extension<ColoresColportaje>()?.borde ?? ColoresAlta.grisFondo,
            ),
          ),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: ColoresAlta.azulFondo,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  FormatoPersonas.iniciales(persona),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    maxLines: lineasDelNombreDePersona(context),
                    overflow: desbordeDelNombreDePersona(context),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    FormatoPersonas.telefonoOculto(persona.telefono),
                    style: TextStyle(fontSize: 12.5, color: gris),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SinClientes extends StatelessWidget {
  const _SinClientes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Column(
        children: [
          Icon(Icons.group_outlined, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            TextosPersonas.sinClientes,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            TextosPersonas.sinClientesAyuda,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// «Los datos de los clientes quedan solo en tu celular…»: el cierre de la lista en el canvas.
class _NotaDePrivacidad extends StatelessWidget {
  const _NotaDePrivacidad();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F1EA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF0E1A2B),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const ExcludeSemantics(
                child: Icon(Icons.lock_outline, size: 14, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                TextosPersonas.notaDePrivacidad,
                style: TextStyle(fontSize: 12.5, height: 1.4, color: ColoresAlta.tinta),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: TextosPersonas.cargando,
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                constraints: const BoxConstraints(minHeight: 62),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: ColoresAlta.grisFondo,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: ColoresAlta.grisFondo,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: AvisoAlta(
        color: ColoresAlta.ambarBorde,
        colorInsignia: ColoresAlta.ambar,
        glyph: '!',
        texto: texto,
      ),
    );
  }
}

class _ErrorDeLectura extends StatelessWidget {
  const _ErrorDeLectura({required this.alReintentar});

  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: AvisoAlta(
        color: ColoresAlta.rojo,
        glyph: '!',
        texto: TextosPersonas.noPudimosLeer,
        acciones: Align(
          alignment: Alignment.centerLeft,
          child: EnlaceAlta(texto: TextosPersonas.reintentar, alPresionar: alReintentar),
        ),
      ),
    );
  }
}
