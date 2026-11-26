import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/abridor_de_pagina_url_launcher.dart';
import '../../domain/services/abridor_de_pagina.dart';

/// Quien abre una página web en el navegador (hoy, «términos de uso» del registro). Los tests lo
/// reemplazan con uno propio: el de verdad habla con la plataforma.
final abridorDePaginaProvider = Provider<AbridorDePagina>(
  (ref) => const AbridorDePaginaUrlLauncher(),
);
