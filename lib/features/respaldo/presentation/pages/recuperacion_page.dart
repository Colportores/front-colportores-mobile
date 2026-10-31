import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/presentation/widgets/texto_error_anunciado.dart';
import '../../../jornada/presentation/widgets/con_espera.dart';
import '../../../tiles/domain/services/puertos_descarga.dart';
import '../../domain/entities/estado_respaldo_drive.dart';
import '../../domain/services/lector_de_lo_recuperado.dart';
import '../../domain/services/servicio_recuperacion.dart';
import '../providers/asistente_recuperacion_notifier.dart';
import '../providers/respaldo_drive_providers.dart';
import '../textos_recuperacion.dart';
import '../widgets/aviso_drive.dart';

/// El asistente de recuperación del primer arranque (HU-SYNC-006, vista 34, artboards 34·01 a
/// 34·10): en un teléfono sin datos, si hay un respaldo en Drive, lo trae paso a paso. Va después de
/// preparar el espacio seguro (vista 13) y antes del permiso de notificaciones (vista 24).
///
/// Lo que había en el teléfono no se toca hasta que la restauración termina completa. Si una parte
/// está dañada, se restaura hasta donde se puede y se dice qué quedó afuera. «Empezar sin recuperar»
/// sigue disponible mientras no se esté restaurando.
class RecuperacionPage extends ConsumerStatefulWidget {
  const RecuperacionPage({super.key});

  @override
  ConsumerState<RecuperacionPage> createState() => _RecuperacionPageState();
}

class _RecuperacionPageState extends ConsumerState<RecuperacionPage> {
  final _contrasena = TextEditingController();
  bool _ocultar = true;

  /// 34·07: se abrió el detalle de «Ver qué quedó afuera».
  bool _verAfuera = false;

  /// 34·07 «Actualizar»: se mostró cómo actualizar.
  bool _comoActualizar = false;

  @override
  void dispose() {
    _contrasena.dispose();
    super.dispose();
  }

  AsistenteRecuperacion get _asistente => ref.read(asistenteRecuperacionProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(asistenteRecuperacionProvider);
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final sinRed = ref.watch(conexionProvider).value == TipoConexion.sinConexion;
    final cuenta = switch (ref.watch(estadoRespaldoDriveProvider).value) {
      DriveConCuenta(:final email) => email,
      _ => null,
    };
    // A texto grande los botones dejan la píldora (la etiqueta se parte en dos renglones).
    final grande = MediaQuery.textScalerOf(context).scale(14) > 20;
    final forma = grande
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
        : const StadiumBorder();
    final vista = _vistaDe(context, estado, sinRed: sinRed, cuenta: cuenta);

    return Scaffold(
      key: const Key('recuperacion_pagina'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, restricciones) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (restricciones.maxHeight - 48).clamp(0, double.infinity),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 14,
                    children: [
                      const SizedBox(height: 12),
                      Text(
                        TextosRecuperacion.paso(vista.paso),
                        key: const Key('recuperacion_paso'),
                        style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
                      ),
                      Semantics(
                        header: true,
                        child: Text(
                          vista.titulo,
                          key: const Key('recuperacion_titulo'),
                          style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                        ),
                      ),
                      ...vista.cuerpo,
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        if (vista.cta case final cta?)
                          FilledButton(
                            key: const Key('recuperacion_cta'),
                            onPressed: cta.alTocar,
                            style: _estiloCta(
                              context,
                              forma,
                              grande,
                              ocupado: cta.ocupado,
                              apagadoSinRed: cta.apagadoPorFaltaDeConexion,
                            ),
                            child: cta.ocupado
                                ? ConEspera(cta.texto)
                                : Text(cta.texto, textAlign: TextAlign.center),
                          ),
                        if (vista.cta2 case final cta2?)
                          OutlinedButton(
                            key: const Key('recuperacion_cta2'),
                            onPressed: cta2.alTocar,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: forma,
                              side: BorderSide(color: colores.bordeInput),
                              padding: EdgeInsets.symmetric(horizontal: grande ? 40 : 24),
                            ),
                            child: Text(cta2.texto, textAlign: TextAlign.center),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _estiloCta(
    BuildContext context,
    OutlinedBorder forma,
    bool grande, {
    required bool ocupado,
    required bool apagadoSinRed,
  }) {
    final base = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: forma,
      padding: EdgeInsets.symmetric(horizontal: grande ? 40 : 24, vertical: 17),
    );
    // Un botón apagado de Material pinta su texto al 38 %: sobre el azul no se lee. Mientras
    // trabaja, el azul al 85 % con letra blanca; apagado por falta de conexión, el gris del canvas.
    if (ocupado) return base.merge(ConEspera.estiloDelBoton(context));
    if (apagadoSinRed) {
      final colores = Theme.of(context).extension<ColoresColportaje>() ?? ColoresColportaje.unica;
      return base.merge(
        FilledButton.styleFrom(
          disabledBackgroundColor: colores.rellenoSuave,
          disabledForegroundColor: colores.gris,
        ),
      );
    }
    return base;
  }

  // ---------------------------------------------------------------------------------------------
  // Cada pantalla del asistente.

  _Vista _vistaDe(
    BuildContext context,
    EstadoAsistente estado, {
    required bool sinRed,
    required String? cuenta,
  }) {
    final respaldo = estado.respaldo;
    final empezarSinRecuperar = _Accion(
      TextosRecuperacion.empezarSinRecuperar,
      estado.terminando ? null : () => unawaited(_asistente.terminar()),
    );
    return switch (estado.pantalla) {
      PantallaAsistente.buscando => _Vista(
        paso: 1,
        titulo: TextosRecuperacion.tituloBuscando,
        cuerpo: const [_Buscando()],
        cta2: empezarSinRecuperar,
      ),
      PantallaAsistente.encontrado => _Vista(
        paso: 1,
        titulo: TextosRecuperacion.tituloEncontrado,
        cuerpo: [
          const _Texto(TextosRecuperacion.textoEncontrado),
          if (respaldo != null) _TarjetaRespaldo(respaldo: respaldo, cuenta: cuenta),
        ],
        cta: _Accion(TextosRecuperacion.recuperar, _asistente.elegirRecuperar),
        cta2: empezarSinRecuperar,
      ),
      PantallaAsistente.conectar => _Vista(
        paso: 1,
        titulo: TextosRecuperacion.tituloConectar,
        cuerpo: [
          const _Texto(TextosRecuperacion.textoConectar),
          if (estado.avisoDeDrive case final aviso?)
            AvisoDrive(clase: aviso.clase, texto: aviso.texto),
        ],
        cta: _Accion(
          estado.conectando
              ? TextosRecuperacion.conectando
              : (estado.avisoDeDrive == null
                    ? TextosRecuperacion.conectarConGoogle
                    : TextosRecuperacion.reintentar),
          estado.conectando ? null : () => unawaited(_asistente.conectarDrive()),
          ocupado: estado.conectando,
        ),
        cta2: empezarSinRecuperar,
      ),
      PantallaAsistente.sinRespaldo => _Vista(
        paso: 1,
        titulo: TextosRecuperacion.tituloSinRespaldo,
        cuerpo: [
          _Texto(
            cuenta == null
                ? TextosRecuperacion.sinRespaldoSinCuenta
                : TextosRecuperacion.sinRespaldoEn(cuenta),
          ),
          if (estado.avisoDeDrive case final aviso?)
            AvisoDrive(clase: aviso.clase, texto: aviso.texto),
        ],
        cta: _Accion(
          estado.conectando
              ? TextosRecuperacion.conectando
              : TextosRecuperacion.probarConOtraCuenta,
          estado.conectando ? null : () => unawaited(_asistente.probarConOtraCuenta()),
          ocupado: estado.conectando,
        ),
        cta2: empezarSinRecuperar,
      ),
      PantallaAsistente.sinConexion => _Vista(
        paso: 1,
        titulo: TextosRecuperacion.tituloSinConexion,
        cuerpo: const [
          AvisoDrive(
            clase: ClaseAvisoDrive.sinConexion,
            texto: TextosRecuperacion.necesitaConexion,
          ),
        ],
        cta: _Accion(
          TextosRecuperacion.reintentar,
          sinRed ? null : () => unawaited(_asistente.buscar()),
          apagadoPorFaltaDeConexion: sinRed,
        ),
        cta2: empezarSinRecuperar,
      ),
      PantallaAsistente.fallaBusqueda => _Vista(
        paso: 1,
        titulo: TextosRecuperacion.tituloNoPudimosBuscar,
        cuerpo: const [_Texto(TextosRecuperacion.noPudimosBuscar)],
        cta: _Accion(TextosRecuperacion.reintentar, () => unawaited(_asistente.buscar())),
        cta2: empezarSinRecuperar,
      ),
      PantallaAsistente.variosRespaldos => _Vista(
        paso: 1,
        titulo: TextosRecuperacion.tituloVariosRespaldos,
        cuerpo: const [_Texto(TextosRecuperacion.variosRespaldos)],
        cta: _Accion(TextosRecuperacion.reintentar, () => unawaited(_asistente.buscar())),
        cta2: empezarSinRecuperar,
      ),
      PantallaAsistente.contrasena => _vistaContrasena(estado, empezarSinRecuperar, cuenta),
      PantallaAsistente.restaurando => _vistaRestaurando(estado),
      PantallaAsistente.interrumpida => _vistaInterrumpida(estado, sinRed: sinRed),
      PantallaAsistente.parcial => _vistaParcial(estado),
      PantallaAsistente.listo => _vistaListo(estado),
      PantallaAsistente.versionMasNueva => _Vista(
        paso: 3,
        titulo: TextosRecuperacion.tituloVersionMasNueva,
        cuerpo: [
          const _Texto(TextosRecuperacion.versionMasNueva, clave: 'recuperacion_mensaje'),
          if (_comoActualizar)
            Semantics(
              liveRegion: true,
              child: const _Texto(
                TextosRecuperacion.actualizarComo,
                clave: 'recuperacion_como_actualizar',
              ),
            ),
        ],
        cta: _Accion(TextosRecuperacion.actualizar, () => setState(() => _comoActualizar = true)),
        cta2: empezarSinRecuperar,
      ),
      PantallaAsistente.sinLlave => _Vista(
        paso: 2,
        titulo: TextosRecuperacion.tituloSinLlave,
        cuerpo: const [_Texto(TextosRecuperacion.sinLlave)],
        cta: _Accion(TextosRecuperacion.reintentar, () => unawaited(_asistente.buscar())),
        cta2: empezarSinRecuperar,
      ),
      PantallaAsistente.ilegible => _Vista(
        paso: 3,
        titulo: TextosRecuperacion.tituloIlegible,
        cuerpo: const [_Texto(TextosRecuperacion.ilegible)],
        cta: _Accion(TextosRecuperacion.reintentar, () => unawaited(_asistente.buscar())),
        cta2: empezarSinRecuperar,
      ),
      PantallaAsistente.fallida => _Vista(
        paso: 3,
        titulo: TextosRecuperacion.tituloFallida,
        cuerpo: const [_Texto(TextosRecuperacion.fallida)],
        cta: _Accion(TextosRecuperacion.reintentar, () => unawaited(_asistente.buscar())),
        cta2: empezarSinRecuperar,
      ),
    };
  }

  _Vista _vistaContrasena(EstadoAsistente estado, _Accion empezarSinRecuperar, String? cuenta) {
    final respaldo = estado.respaldo;
    final vacia = _contrasena.text.isEmpty;
    return _Vista(
      paso: 2,
      titulo: TextosRecuperacion.tituloContrasena,
      cuerpo: [
        if (respaldo != null) _TarjetaRespaldo(respaldo: respaldo, cuenta: cuenta),
        _CampoContrasena(
          controlador: _contrasena,
          oculta: _ocultar,
          error: estado.contrasenaIncorrecta ? TextosRecuperacion.contrasenaNoAbre : null,
          alCambiar: (_) {
            _asistente.contrasenaEditada();
            setState(() {});
          },
          alAlternar: () => setState(() => _ocultar = !_ocultar),
          alEnviar: vacia ? null : () => unawaited(_asistente.abrirCopia(_contrasena.text)),
        ),
        if (respaldo != null)
          _Texto(
            TextosRecuperacion.confirmacionPrevia(TextosRecuperacion.peso(respaldo.bytes)),
            clave: 'recuperacion_confirmacion',
            chico: true,
          ),
      ],
      cta: _Accion(
        TextosRecuperacion.abrirCopia,
        vacia ? null : () => unawaited(_asistente.abrirCopia(_contrasena.text)),
      ),
      cta2: empezarSinRecuperar,
    );
  }

  _Vista _vistaRestaurando(EstadoAsistente estado) {
    final progreso = estado.progreso;
    final puedeCancelar = progreso?.sePuedeCancelar ?? true;
    return _Vista(
      paso: 3,
      titulo: TextosRecuperacion.tituloRestaurando,
      cuerpo: [
        _ProgresoDeRestauracion(progreso: progreso),
        const AvisoDrive(clase: ClaseAvisoDrive.info, texto: TextosRecuperacion.infoRestaurando),
      ],
      cta: const _Accion(TextosRecuperacion.restaurandoBoton, null, ocupado: true),
      cta2: puedeCancelar
          ? _Accion(TextosRecuperacion.cancelar, estado.cancelando ? null : _asistente.cancelar)
          : null,
    );
  }

  _Vista _vistaInterrumpida(EstadoAsistente estado, {required bool sinRed}) {
    final progreso = estado.progreso;
    final hechas = progreso?.hechas ?? 0;
    // «Reintentar» solo sirve cuando la restauración terminó sin conexión y la conexión volvió: si el
    // servicio sigue esperando, retoma solo.
    final puedeReintentar = estado.sinConexionAlCortarse && !sinRed;
    return _Vista(
      paso: 3,
      titulo: TextosRecuperacion.tituloInterrumpida,
      cuerpo: [
        _ProgresoDeRestauracion(progreso: progreso, interrumpida: true),
        AvisoDrive(
          clase: ClaseAvisoDrive.sinConexion,
          texto: hechas == 0
              ? TextosRecuperacion.sinConexionAlPrincipio
              : TextosRecuperacion.sinConexionALaMitad(hechas),
        ),
      ],
      cta: _Accion(
        TextosRecuperacion.reintentar,
        puedeReintentar ? () => unawaited(_asistente.reintentarRestauracion()) : null,
        apagadoPorFaltaDeConexion: !puedeReintentar,
      ),
      cta2: _Accion(TextosRecuperacion.cancelar, estado.cancelando ? null : _asistente.cancelar),
    );
  }

  _Vista _vistaParcial(EstadoAsistente estado) {
    final informe = estado.informe;
    final hasta = informe == null ? '' : TextosRecuperacion.diaYHora(informe.fechaDelRespaldo);
    final dia = informe == null ? '' : TextosRecuperacion.dia(informe.fechaDelRespaldo);
    final total = informe?.partesTotales ?? 0;
    return _Vista(
      paso: 3,
      titulo: TextosRecuperacion.tituloParcial,
      cuerpo: [
        AvisoDrive(
          clase: ClaseAvisoDrive.advertencia,
          texto: TextosRecuperacion.parteDanada(
            (informe?.partesRestauradas ?? 0) + 1,
            total,
            hasta,
          ),
        ),
        _Filas(
          filas: [
            (TextosRecuperacion.quedoAfuera, TextosRecuperacion.loPosteriorA(dia)),
            (TextosRecuperacion.restaurado, TextosRecuperacion.todoLoAnterior),
          ],
        ),
        _Texto(TextosRecuperacion.telefonoViejo(dia), clave: 'recuperacion_telefono_viejo'),
        if (_verAfuera)
          const _Texto(
            TextosRecuperacion.detalleQueQuedoAfuera,
            clave: 'recuperacion_detalle_afuera',
          ),
      ],
      cta: _Accion(
        TextosRecuperacion.seguirConLoRecuperado,
        estado.terminando ? null : () => unawaited(_asistente.terminar()),
        ocupado: estado.terminando,
      ),
      cta2: _Accion(
        _verAfuera
            ? TextosRecuperacion.ocultarQueQuedoAfuera
            : TextosRecuperacion.verQueQuedoAfuera,
        () => setState(() => _verAfuera = !_verAfuera),
      ),
    );
  }

  _Vista _vistaListo(EstadoAsistente estado) {
    final informe = estado.informe;
    final resumen = estado.resumen;
    return _Vista(
      paso: 3,
      titulo: TextosRecuperacion.tituloListo,
      cuerpo: [
        _Hero(
          texto: informe == null
              ? ''
              : TextosRecuperacion.comoElDia(TextosRecuperacion.diaYHora(informe.fechaDelRespaldo)),
        ),
        if (resumen != null) _FilasDeResumen(resumen: resumen),
      ],
      cta: _Accion(
        TextosRecuperacion.irAMiInicio,
        estado.terminando ? null : () => unawaited(_asistente.terminar()),
        ocupado: estado.terminando,
      ),
    );
  }
}

/// Lo que dibuja una pantalla del asistente.
final class _Vista {
  const _Vista({
    required this.paso,
    required this.titulo,
    required this.cuerpo,
    this.cta,
    this.cta2,
  });

  final int paso;
  final String titulo;
  final List<Widget> cuerpo;
  final _Accion? cta;
  final _Accion? cta2;
}

/// Un botón: su texto y qué hace (`null` = apagado).
final class _Accion {
  const _Accion(
    this.texto,
    this.alTocar, {
    this.ocupado = false,
    this.apagadoPorFaltaDeConexion = false,
  });

  final String texto;
  final VoidCallback? alTocar;

  /// Está trabajando: círculo girando y el texto («Restaurando…», «Conectando…»).
  final bool ocupado;

  /// Apagado porque no hay conexión: gris, no el 38 % de Material.
  final bool apagadoPorFaltaDeConexion;
}

class _Texto extends StatelessWidget {
  const _Texto(this.texto, {this.clave, this.chico = false});

  final String texto;
  final String? clave;
  final bool chico;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    return Text(
      texto,
      key: clave == null ? null : Key(clave!),
      style: chico
          ? theme.textTheme.bodySmall?.copyWith(color: colores.gris, height: 1.45)
          : theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
    );
  }
}

/// El estado de carga del paso 1.
class _Buscando extends StatelessWidget {
  const _Buscando();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        key: const Key('recuperacion_buscando'),
        spacing: 14,
        children: [
          const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          Expanded(
            child: Text(
              TextosRecuperacion.buscando,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Respaldo del 22/10 a las 03:10» con la cuenta de Google y «15 partes · 38 MB».
class _TarjetaRespaldo extends StatelessWidget {
  const _TarjetaRespaldo({required this.respaldo, required this.cuenta});

  final RespaldoEnDrive respaldo;
  final String? cuenta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    return Semantics(
      container: true,
      child: DecoratedBox(
        key: const Key('recuperacion_tarjeta'),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border.all(color: colores.borde),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            spacing: 14,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDE8D3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.cloud_outlined, size: 22, color: Color(0xFF1F6E3A)),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      'Respaldo del ${TextosRecuperacion.diaYHora(respaldo.fecha)}',
                      key: const Key('recuperacion_tarjeta_titulo'),
                      style: theme.textTheme.titleSmall,
                    ),
                    if (cuenta != null)
                      Text(
                        cuenta!,
                        style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                      ),
                    Text(
                      TextosRecuperacion.partesYPeso(respaldo.partes, respaldo.bytes),
                      key: const Key('recuperacion_tarjeta_detalle'),
                      style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El campo de la contraseña de la copia (34·03 y 34·04), con su ayuda y su error.
class _CampoContrasena extends StatelessWidget {
  const _CampoContrasena({
    required this.controlador,
    required this.oculta,
    required this.error,
    required this.alCambiar,
    required this.alAlternar,
    required this.alEnviar,
  });

  final TextEditingController controlador;
  final bool oculta;
  final String? error;
  final ValueChanged<String> alCambiar;
  final VoidCallback alAlternar;
  final VoidCallback? alEnviar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(
          TextosRecuperacion.campoContrasena,
          style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
        ),
        TextField(
          key: const Key('recuperacion_contrasena'),
          controller: controlador,
          obscureText: oculta,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onChanged: alCambiar,
          onSubmitted: (_) => alEnviar?.call(),
          decoration: InputDecoration(
            helperText: error == null ? TextosRecuperacion.ayudaContrasena : null,
            helperMaxLines: 6,
            error: error == null
                ? null
                : TextoErrorAnunciado(
                    error!,
                    textoKey: const Key('recuperacion_contrasena_error'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
            errorMaxLines: 6,
            suffixIcon: IconButton(
              key: const Key('recuperacion_contrasena_ver'),
              tooltip: oculta
                  ? TextosRecuperacion.mostrarContrasena
                  : TextosRecuperacion.ocultarContrasena,
              onPressed: alAlternar,
              icon: Icon(oculta ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            ),
          ),
        ),
      ],
    );
  }
}

/// La barra de la restauración con su etiqueta y «12/15 partes» (34·05 y 34·06).
class _ProgresoDeRestauracion extends StatelessWidget {
  const _ProgresoDeRestauracion({required this.progreso, this.interrumpida = false});

  final ProgresoRecuperacion? progreso;
  final bool interrumpida;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final p = progreso;
    final hechas = p?.hechas ?? 0;
    final total = p?.total ?? 0;
    final bajando = p == null || p.paso == PasoRecuperacion.bajando;
    final etiqueta = interrumpida
        ? (hechas == 0
              ? TextosRecuperacion.quedoEnElPrincipio
              : TextosRecuperacion.quedoEnLaParte(hechas))
        : switch (p?.paso) {
            null || PasoRecuperacion.buscando => TextosRecuperacion.bajandoBase,
            PasoRecuperacion.bajando =>
              hechas == 0 ? TextosRecuperacion.bajandoBase : TextosRecuperacion.bajandoPartes,
            PasoRecuperacion.aplicando => TextosRecuperacion.armandoLaCopia,
            PasoRecuperacion.reenviando => TextosRecuperacion.reenviando,
            PasoRecuperacion.reconciliando => TextosRecuperacion.trayendoLoUltimo,
            PasoRecuperacion.listo => TextosRecuperacion.trayendoLoUltimo,
          };
    // Con el conteo conocido, la barra avanza; en los pasos que no se cuentan por partes (armar,
    // reenviar, traer), gira.
    final fraccion = bajando && total > 0 ? (hechas / total).clamp(0.0, 1.0) : null;
    final valor = bajando && total > 0 ? TextosRecuperacion.partes(hechas, total) : null;
    return Semantics(
      container: true,
      label: [etiqueta, ?valor].join(', '),
      child: ExcludeSemantics(
        child: Column(
          key: const Key('recuperacion_progreso'),
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            // Con texto grande el valor baja a su propio renglón en vez de desbordar.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 10,
              runSpacing: 2,
              children: [
                Text(etiqueta, style: theme.textTheme.bodyMedium),
                if (valor != null)
                  Text(
                    valor,
                    key: const Key('recuperacion_progreso_valor'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
                  ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                key: const Key('recuperacion_progreso_barra'),
                value: interrumpida ? (fraccion ?? 0) : fraccion,
                minHeight: 8,
                backgroundColor: colores.borde,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filas «rótulo — valor» sueltas (34·07).
class _Filas extends StatelessWidget {
  const _Filas({required this.filas});

  final List<(String, String)> filas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    return DecoratedBox(
      key: const Key('recuperacion_filas'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: colores.borde),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            for (final (i, (rotulo, valor)) in filas.indexed) ...[
              if (i > 0) Divider(height: 1, color: colores.borde),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    Expanded(
                      child: Text(
                        rotulo,
                        style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        valor,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lo que volvió, con su cantidad (34·08).
class _FilasDeResumen extends StatelessWidget {
  const _FilasDeResumen({required this.resumen});

  final ResumenDeLoRecuperado resumen;

  @override
  Widget build(BuildContext context) => _Filas(
    filas: [
      (TextosRecuperacion.ubicaciones, '${resumen.ubicaciones}'),
      (TextosRecuperacion.personas, '${resumen.personas}'),
      (TextosRecuperacion.ventas, '${resumen.ventas}'),
      (TextosRecuperacion.cobros, '${resumen.cobros}'),
    ],
  );
}

/// El círculo verde con la tilde y «Como el 22/10 a las 03:10» (34·08).
class _Hero extends StatelessWidget {
  const _Hero({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Column(
        key: const Key('recuperacion_hero'),
        spacing: 12,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDDE8D3)),
              child: const Icon(Icons.check, size: 34, color: Color(0xFF1F6E3A)),
            ),
          ),
          Text(
            texto,
            key: const Key('recuperacion_hero_texto'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
