import 'package:url_launcher/url_launcher.dart';

import '../../domain/services/abridor_de_pagina.dart';

/// [AbridorDePagina] sobre `url_launcher`: la página se lee en el navegador del teléfono, no dentro
/// de la app (decisión «Términos» del 07/10: «una página web»).
final class AbridorDePaginaUrlLauncher implements AbridorDePagina {
  const AbridorDePaginaUrlLauncher();

  @override
  Future<bool> abrir(Uri direccion) => launchUrl(direccion, mode: LaunchMode.externalApplication);
}
