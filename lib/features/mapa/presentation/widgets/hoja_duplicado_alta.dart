import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../formato_ubicaciones.dart';
import '../mapa_base/mapa_base.dart';
import '../mapa_base/modelo_mapa_base.dart';
import '../providers/alta_ubicacion_notifier.dart';
import '../providers/mapa_base_providers.dart';
import 'hoja_alta.dart';
import 'piezas_alta.dart';

/// Textos de la vista 04. Los literales de HU-UBI-001 («Reutilizar esta», «Crear igual»,
/// «Cancelar», «Abrir la existente») van tal cual; el resto es la propuesta del canvas.
abstract final class TextosDuplicado {
  static const reutilizar = 'Reutilizar esta';
  static const abrirExistente = 'Abrir la existente';
  static const crearIgual = 'Crear igual';
  static const cancelar = 'Cancelar';
  static const volver = 'Volver';
  static const misma = 'Misma dirección y misma ciudad.';

  /// Solo cuando no hay «Crear igual» (D1: misma dirección a menos de 100 m): por qué no se puede
  /// crear otra y qué hacer (decisión del 05/10, revisión de #267).
  static const sinCrearIgual =
      'No puede haber dos ubicaciones con la misma dirección a menos de 100 m. '
      'Si es otra puerta, abrí la existente y agregala como espacio.';
  static const revisa = 'Revisá si es el mismo lugar antes de crear otra.';
  static const siAlguna = 'Si alguna es este lugar, reutilizala.';
  static const porQue = '¿Por qué es otra ubicación?';
  static const justificacion = 'JUSTIFICACIÓN · OBLIGATORIA';
  static const cuenta = 'Contá por qué es otro lugar';
  static const laVeTuCoordinador = 'La ve tu coordinador.';
  static const laNueva = 'La nueva';
  static const yaRegistrada = 'Ya registrada';
  static const registrando = 'Registrando…';
  static const motivos = [
    'Otra puerta en el mismo número',
    'Local en planta baja',
    'Otra unidad del edificio',
  ];

  /// La justificación pide al menos 10 caracteres (decisión del canvas).
  static const minimoJustificacion = 10;
  static const maximoJustificacion = 200;

  static String titulo(List<CandidataDuplicado> c) => c.length == 1
      ? 'Ya existe una ubicación a ${FormatoUbicaciones.distancia(c.first.distanciaMetros)}'
      : 'Hay ${c.length} ubicaciones cerca';

  static String subtitulo(List<CandidataDuplicado> c) =>
      c.length > 1 ? siAlguna : (c.first.motivo == MotivoDuplicado.mismaDireccion ? misma : revisa);
}

/// Qué decidió el colportor en la vista 04.
sealed class DecisionDuplicado {
  const DecisionDuplicado();
}

/// «Reutilizar esta» / «Abrir la existente»: abrir la ubicación que ya existe, sin modificarla.
final class DecisionReutilizar extends DecisionDuplicado {
  const DecisionReutilizar(this.ubicacionId);

  final String ubicacionId;
}

/// «Crear igual» con justificación: la ubicación quedó registrada.
final class DecisionCreada extends DecisionDuplicado {
  const DecisionCreada(this.ubicacion);

  final Ubicacion ubicacion;
}

/// Abre la vista 04 sobre el alta, sin perder el mapa ni lo cargado. Devuelve la decisión, o `null`
/// si el colportor tocó «Cancelar» o cerró la hoja (el alta sigue como estaba).
///
/// [crearIgual] registra con la justificación y devuelve cómo terminó: si llegan candidatas nuevas
/// la hoja las muestra; si falla, el mensaje y el botón vuelve a quedar habilitado.
Future<DecisionDuplicado?> mostrarHojaDuplicado(
  BuildContext context, {
  required List<CandidataDuplicado> candidatas,
  required Coordenadas puntoNuevo,
  required Map<String, String> nombresCiudad,
  required Future<ResultadoRegistroAlta> Function(String justificacion) crearIgual,
  required DateTime Function() ahora,
}) => showModalBottomSheet<DecisionDuplicado>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Sin arrastrar para cerrar: mientras «Crear igual» guarda, la hoja no se puede cerrar de costado
  // (el arrastre no pasa por el `PopScope`). Las salidas son «Cancelar», «Reutilizar esta» y atrás.
  enableDrag: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaDuplicadoAlta(
    candidatas: candidatas,
    puntoNuevo: puntoNuevo,
    nombresCiudad: nombresCiudad,
    crearIgual: crearIgual,
    ahora: ahora,
  ),
);

enum _Paso { candidatas, justificacion }

/// La hoja de la vista 04: las candidatas a duplicado con vista previa del mapa y las tres salidas.
class HojaDuplicadoAlta extends StatefulWidget {
  const HojaDuplicadoAlta({
    super.key,
    required this.candidatas,
    required this.puntoNuevo,
    required this.nombresCiudad,
    required this.crearIgual,
    required this.ahora,
  });

  final List<CandidataDuplicado> candidatas;
  final Coordenadas puntoNuevo;
  final Map<String, String> nombresCiudad;
  final Future<ResultadoRegistroAlta> Function(String justificacion) crearIgual;
  final DateTime Function() ahora;

  @override
  State<HojaDuplicadoAlta> createState() => _HojaDuplicadoAltaState();
}

class _HojaDuplicadoAltaState extends State<HojaDuplicadoAlta> {
  final _texto = TextEditingController();
  late List<CandidataDuplicado> _candidatas = _ordenar(widget.candidatas);
  var _paso = _Paso.candidatas;
  var _enviando = false;
  Failure? _falla;

  static List<CandidataDuplicado> _ordenar(List<CandidataDuplicado> c) =>
      [...c]..sort((a, b) => a.distanciaMetros.compareTo(b.distanciaMetros));

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  /// «Crear igual» solo está si todas las candidatas lo admiten (HU-UBI-001, D1).
  bool get _puedeCrearIgual => _candidatas.every((c) => c.admiteConservarAmbos);

  bool get _justificacionValida => _texto.text.trim().length >= TextosDuplicado.minimoJustificacion;

  void _reutilizar(CandidataDuplicado c) =>
      Navigator.of(context).pop(DecisionReutilizar(c.ubicacion.id));

  /// Cambia de paso sin arrastrar el aviso rojo de un intento anterior: «No pudimos guardar…» habla
  /// del último «Crear igual», y al volver o reentrar a la justificación no hubo ningún intento nuevo.
  /// Lo escrito en la justificación se conserva (el controlador no se toca).
  void _irA(_Paso paso) => setState(() {
    _paso = paso;
    _falla = null;
  });

  Future<void> _crearIgual() async {
    if (_enviando || !_justificacionValida) return;
    setState(() {
      _enviando = true;
      _falla = null;
    });
    ResultadoRegistroAlta resultado;
    try {
      resultado = await widget.crearIgual(_texto.text.trim());
    } on Object catch (e) {
      resultado = AltaFallida(FailureInesperado(causa: e));
    }
    if (!mounted) return;
    switch (resultado) {
      case AltaCreada(:final ubicacion):
        Navigator.of(context).pop(DecisionCreada(ubicacion));
      case AltaConCandidatas(:final candidatas):
        setState(() {
          _enviando = false;
          _candidatas = _ordenar(candidatas);
          _paso = _Paso.candidatas;
        });
      case AltaFallida(:final falla):
        setState(() {
          _enviando = false;
          _falla = falla;
        });
      case AltaIgnorada():
        setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      // El atrás del sistema anda de a un paso, como el chevron «Volver»: desde la justificación
      // (B·03) vuelve a las candidatas y recién desde ahí cierra la hoja. Lo escrito se conserva
      // (el controlador vive en el estado). Mientras guarda no hace nada.
      canPop: !_enviando && _paso == _Paso.candidatas,
      onPopInvokedWithResult: (seCerro, _) {
        if (!seCerro && !_enviando && _paso == _Paso.justificacion) {
          _irA(_Paso.candidatas);
        }
      },
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + inset),
          child: _paso == _Paso.candidatas
              ? _construirCandidatas(context)
              : _construirJustificacion(context),
        ),
      ),
    );
  }

  Widget _construirCandidatas(BuildContext context) {
    final theme = Theme.of(context);
    final varias = _candidatas.length > 1;
    final etiquetaReutilizar = _candidatas.first.admiteConservarAmbos
        ? TextosDuplicado.reutilizar
        : TextosDuplicado.abrirExistente;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const InsigniaCirculo(color: ColoresAlta.ambar, glyph: '!', tamano: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      TextosDuplicado.titulo(_candidatas),
                      style: const TextStyle(
                        fontFamily: 'SourceSerif4',
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    TextosDuplicado.subtitulo(_candidatas),
                    style: theme.textTheme.bodyMedium?.copyWith(color: ColoresAlta.tinta),
                  ),
                  // Sin «Crear igual» (D1) se dice por qué y qué hacer, no solo se oculta el botón.
                  if (!_puedeCrearIgual) ...[
                    const SizedBox(height: 4),
                    Text(
                      TextosDuplicado.sinCrearIgual,
                      key: const Key('duplicado_sin_crear_igual'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: ColoresAlta.tinta),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _VistaPreviaMapa(nueva: widget.puntoNuevo, candidatas: _candidatas),
        const SizedBox(height: 14),
        for (var i = 0; i < _candidatas.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _TarjetaCandidata(
            candidata: _candidatas[i],
            letra: varias ? String.fromCharCode(65 + i) : null,
            ciudad: widget.nombresCiudad[_candidatas[i].ubicacion.ciudadId],
            ahora: widget.ahora(),
            etiquetaBoton: _candidatas[i].admiteConservarAmbos
                ? TextosDuplicado.reutilizar
                : TextosDuplicado.abrirExistente,
            principal: i == 0,
            alReutilizar: varias ? () => _reutilizar(_candidatas[i]) : null,
          ),
        ],
        const SizedBox(height: 16),
        if (!varias)
          FilledButton(
            onPressed: () => _reutilizar(_candidatas.first),
            child: Text(etiquetaReutilizar),
          ),
        if (_puedeCrearIgual) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _irA(_Paso.justificacion),
            child: const Text(TextosDuplicado.crearIgual),
          ),
        ],
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text(TextosDuplicado.cancelar),
        ),
      ],
    );
  }

  Widget _construirJustificacion(BuildContext context) {
    final theme = Theme.of(context);
    final cercana = _candidatas.first;
    final largo = _texto.text.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: TextosDuplicado.volver,
              onPressed: _enviando ? null : () => _irA(_Paso.candidatas),
              icon: const Icon(Icons.chevron_left),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: const Text(
                  TextosDuplicado.porQue,
                  style: TextStyle(
                    fontFamily: 'SourceSerif4',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const _Letra('A'),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${FormatoUbicaciones.direccion(cercana.ubicacion)} · a '
                '${FormatoUbicaciones.distancia(cercana.distanciaMetros)}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          TextosDuplicado.justificacion,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 1.4,
            color: ColoresAlta.gris,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final motivo in TextosDuplicado.motivos)
              _MotivoRapido(
                texto: motivo,
                alTocar: _enviando
                    ? null
                    : () => setState(() {
                        _texto.value = TextEditingValue(
                          text: motivo,
                          selection: TextSelection.collapsed(offset: motivo.length),
                        );
                      }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _texto,
          enabled: !_enviando,
          onChanged: (_) => setState(() {}),
          minLines: 3,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(TextosDuplicado.maximoJustificacion)],
          decoration: InputDecoration(
            hintText: TextosDuplicado.cuenta,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(
              child: Text(
                TextosDuplicado.laVeTuCoordinador,
                style: TextStyle(fontSize: 12.5, color: ColoresAlta.gris),
              ),
            ),
            Text(
              '$largo / ${TextosDuplicado.maximoJustificacion}',
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 12,
                color: ColoresAlta.gris,
              ),
            ),
          ],
        ),
        if (_falla != null) ...[
          const SizedBox(height: 12),
          AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: mensajeFallaAlta(_falla!)),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _justificacionValida && !_enviando ? _crearIgual : null,
          style: FilledButton.styleFrom(
            disabledBackgroundColor: ColoresAlta.grisFondo,
            disabledForegroundColor: ColoresAlta.gris,
            minimumSize: const Size.fromHeight(52),
          ),
          child: Text(_enviando ? TextosDuplicado.registrando : TextosDuplicado.crearIgual),
        ),
      ],
    );
  }
}

/// Un motivo sugerido de la justificación (B·03): toca y se copia al campo. Con el aspecto de chip
/// del canvas, pero el texto parte en renglones en vez de cortarse: un `ActionChip` lo deja en una
/// línea y lo desvanece con el texto al 200 % («Otra puerta en el mism…»).
class _MotivoRapido extends StatelessWidget {
  const _MotivoRapido({required this.texto, required this.alTocar});

  final String texto;

  /// `null` mientras se guarda.
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final activo = alTocar != null;
    return Semantics(
      button: true,
      enabled: activo,
      label: texto,
      excludeSemantics: true,
      onTap: alTocar,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
        ),
        child: InkWell(
          onTap: alTocar,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Center(
                widthFactor: 1,
                child: Text(
                  texto,
                  style: TextStyle(
                    fontSize: 14,
                    color: activo ? ColoresAlta.tinta : ColoresAlta.gris,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Letra extends StatelessWidget {
  const _Letra(this.letra);

  final String letra;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Candidata $letra',
      excludeSemantics: true,
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: ColoresAlta.azul, shape: BoxShape.circle),
        child: Text(
          letra,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _TarjetaCandidata extends StatelessWidget {
  const _TarjetaCandidata({
    required this.candidata,
    required this.letra,
    required this.ciudad,
    required this.ahora,
    required this.etiquetaBoton,
    required this.principal,
    required this.alReutilizar,
  });

  final CandidataDuplicado candidata;

  /// `null` si hay una sola candidata (sin rótulo).
  final String? letra;
  final String? ciudad;
  final DateTime ahora;
  final String etiquetaBoton;
  final bool principal;

  /// Con varias candidatas cada tarjeta lleva su botón; con una, el botón va al pie de la hoja.
  final VoidCallback? alReutilizar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = candidata.ubicacion;
    final detalle = [FormatoUbicaciones.tipo(u.tipo), ?ciudad].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ColoresAlta.grisBorde, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (letra != null) ...[_Letra(letra!), const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      FormatoUbicaciones.direccion(u),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(detalle, style: theme.textTheme.bodyMedium),
                    Text(
                      'Actualizada ${FormatoUbicaciones.hace(u.auditoria.updatedAt, ahora)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ColoresAlta.gris,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (letra != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    FormatoUbicaciones.distancia(candidata.distanciaMetros),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          if (alReutilizar != null) ...[
            const SizedBox(height: 10),
            principal
                ? FilledButton(onPressed: alReutilizar, child: Text(etiquetaBoton))
                : OutlinedButton(onPressed: alReutilizar, child: Text(etiquetaBoton)),
          ],
        ],
      ),
    );
  }
}

/// Vista previa de la vista 04: la ubicación nueva y las candidatas (A, B…) en un mapa chico, sin
/// moverlo.
class _VistaPreviaMapa extends ConsumerWidget {
  const _VistaPreviaMapa({required this.nueva, required this.candidatas});

  final Coordenadas nueva;
  final List<CandidataDuplicado> candidatas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final varias = candidatas.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label:
              'Vista previa del mapa con la ubicación nueva y '
              '${candidatas.length == 1 ? 'la ubicación ya registrada' : 'las ${candidatas.length} ubicaciones ya registradas'}',
          container: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 150,
              // Una imagen del mapa, sin gestos: los toques siguen de largo hacia el scroll de la hoja.
              child: MapaBase(
                fuente: ref.watch(fuenteMapaProvider),
                ajuste: AjusteMapa(
                  puntos: [nueva, for (final c in candidatas) c.ubicacion.coordenadas],
                  margen: 40,
                  zoomMaximo: 18,
                ),
                interaccion: InteraccionMapa.ninguna,
                fondo: ColoresAlta.fondoMapa,
                puntos: [
                  for (var i = 0; i < candidatas.length; i++)
                    PuntoMapa(
                      id: candidatas[i].ubicacion.id,
                      coordenadas: candidatas[i].ubicacion.coordenadas,
                      estilo: EstiloPunto.candidata,
                      letra: varias ? String.fromCharCode(65 + i) : null,
                    ),
                  PuntoMapa(id: 'nueva', coordenadas: nueva, estilo: EstiloPunto.nuevo),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            if (varias)
              for (var i = 0; i < candidatas.length; i++)
                Text(
                  '${String.fromCharCode(65 + i)} a ${FormatoUbicaciones.distancia(candidatas[i].distanciaMetros)}',
                  style: const TextStyle(fontSize: 12.5, color: ColoresAlta.tinta),
                ),
            _Leyenda(color: Theme.of(context).colorScheme.primary, texto: TextosDuplicado.laNueva),
            const _Leyenda(color: ColoresAlta.gris, texto: TextosDuplicado.yaRegistrada),
          ],
        ),
      ],
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(texto, style: const TextStyle(fontSize: 12.5, color: ColoresAlta.tinta)),
        ),
      ],
    );
  }
}
