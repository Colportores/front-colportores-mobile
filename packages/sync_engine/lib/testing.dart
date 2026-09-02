/// Fakes de los puertos, para la suite de conformidad y para que la app se
/// desarrolle entre hitos sin esperar al motor real (§6, §11).
///
/// Import aparte, como `package:http/testing.dart`: el código de test no entra
/// en el árbol de producción de la app.
library;

export 'src/testing/fake_backup.dart';
export 'src/testing/fake_connectivity.dart';
export 'src/testing/fake_realtime.dart';
export 'src/testing/in_memory_stores.dart';
export 'src/testing/fake_sync_transport.dart';
