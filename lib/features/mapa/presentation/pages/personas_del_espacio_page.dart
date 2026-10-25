import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../domain/entities/persona_del_espacio.dart';
import '../formato_ubicaciones.dart';
import '../providers/personas_providers.dart';
import '../textos_personas.dart';
import '../widgets/piezas_alta.dart';
import 'alta_persona_page.dart';

/// Los clientes de un departamento (HU-UBI-008, vista 11·04 «Departamento con sus clientes»): el título
/// del espacio y la lista de personas que el colportor guardó en él, con «+ Agregar cliente».
///
/// Lo que el artboard dibuja y no es de esta pantalla queda fuera: «Registrar visita» y el estado de la
/// entrevista (las visitas, #151), «Editar» (el depto, #211) y las visitas de cada cliente (todavía no
/// hay visitas que contar). Tampoco hay `›` en las filas: la ficha de la persona (HU-UBI-009) es otro
/// issue.
///
/// - Cargando, vacío, error al leer y espacio que ya no está son estados propios.
/// - Con el espacio dado de baja es de solo lectura: se ven los clientes y no se puede agregar.
/// - Al volver del alta con una persona nueva muestra «Guardamos a Jorge en este teléfono.» (32A·05).
class PersonasDelEspacioPage extends ConsumerStatefulWidget {
  const PersonasDelEspacioPage({super.key, required this.espacioId, required this.colportorId});

  final String espacioId;

  /// UUID del usuario con la sesión iniciada (`created_by` de las altas).
  final String colportorId;

  static Future<void> abrir(
    BuildContext context, {
    required String espacioId,
    required String colportorId,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PersonasDelEspacioPage(espacioId: espacioId, colportorId: colportorId),
    ),
  );

  @override
  ConsumerState<PersonasDelEspacioPage> createState() => _PersonasDelEspacioPageState();
}

class _PersonasDelEspacioPageState extends ConsumerState<PersonasDelEspacioPage> {
  /// Ya se está abriendo el alta: un segundo toque no abre otra encima.
  var _abriendoAlta = false;

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
      ..invalidate(personasDelEspacioProvider(widget.espacioId));
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

    final Widget cuerpo;
    if (contexto.hasError || personas.hasError) {
      cuerpo = _ErrorDeLectura(alReintentar: _reintentar);
    } else if (noEncontrado) {
      cuerpo = const _Mensaje(texto: TextosPersonas.espacioNoEncontrado);
    } else if (!contexto.hasValue || !personas.hasValue) {
      cuerpo = const _Cargando();
    } else if (personas.requireValue.isEmpty) {
      cuerpo = _ListaDeClientes(clientes: const [], deBaja: deBaja);
    } else {
      cuerpo = _ListaDeClientes(clientes: personas.requireValue, deBaja: deBaja);
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Cabecera(
              direccion: datos == null
                  ? null
                  : FormatoUbicaciones.direccion(datos.ubicacion).toUpperCase(),
            ),
            if (datos != null)
              _Titulo(
                titulo: FormatoPersonas.tituloEspacio(datos.espacio, datos.ubicacion),
                piso: FormatoPersonas.pisoDelEspacio(datos.espacio),
              ),
            const Divider(height: 1),
            _EncabezadoClientes(cantidad: cantidad, alAgregar: puedeAgregar ? _agregar : null),
            Expanded(child: cuerpo),
          ],
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.direccion});

  final String? direccion;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 14, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: TextosPersonas.volver,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left, size: 28),
          ),
          if (direccion != null)
            Expanded(
              child: Text(
                direccion!,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w500,
                  color: navy,
                ),
              ),
            ),
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

class _ListaDeClientes extends StatelessWidget {
  const _ListaDeClientes({required this.clientes, required this.deBaja});

  final List<PersonaDelEspacio> clientes;
  final bool deBaja;

  @override
  Widget build(BuildContext context) {
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
    // Avisos de arriba + filas + vacío + nota de privacidad: una sola lista que se desplaza.
    final delante = avisoBaja == null ? 0 : 1;
    final vacio = clientes.isEmpty ? 1 : 0;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: delante + vacio + clientes.length + 1,
      itemBuilder: (context, i) {
        if (i < delante) return avisoBaja;
        i -= delante;
        if (vacio == 1) {
          if (i == 0) return const _SinClientes();
          i -= 1;
        }
        if (i < clientes.length) return _FilaCliente(cliente: clientes[i]);
        return const _NotaDePrivacidad();
      },
    );
  }
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
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: ColoresAlta.azulFondo, shape: BoxShape.circle),
              child: Text(
                FormatoPersonas.iniciales(persona),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
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
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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
    return SingleChildScrollView(
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
