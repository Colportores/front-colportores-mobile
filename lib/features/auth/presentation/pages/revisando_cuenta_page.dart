import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import 'esperando_asignacion_page.dart';

/// El arranque mientras se consulta el estado de la cuenta (HU-AUTH-008, vista 18, #278): el
/// indicador con «Revisando con el servidor…», el texto de 18A·02, para que nunca sea un spinner
/// mudo. Dura como mucho lo que tarda el tope de `ConsultarEstadoCuentaUseCase` (15 s); pasado ese
/// tiempo la raíz pasa al aviso de sin conexión con «Reintentar» y Configuración.
class RevisandoCuentaPage extends StatelessWidget {
  const RevisandoCuentaPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    return Scaffold(
      key: const Key('revisando_cuenta_pagina'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            // Se anuncia al abrir: sin esto, quien usa un lector de pantalla no sabe qué espera.
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 16,
                children: [
                  const ExcludeSemantics(child: CircularProgressIndicator()),
                  Text(
                    TextosEsperaAsignacion.revisando,
                    key: const Key('revisando_cuenta_texto'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(color: colores.gris),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
