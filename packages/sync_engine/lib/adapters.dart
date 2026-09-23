/// Los adaptadores: el 10% del paquete que toca el mundo (Apéndice A).
///
/// `BffTransport` es Dart puro (`package:http`), así que se puede importar
/// desde un test de la VM. Los adaptadores que envuelvan plugins de Flutter van
/// a tener su propio entry point, para que importar uno no arrastre Flutter a
/// quien solo necesita el otro.
library;

export 'src/adapters/aes_gcm_crypto.dart';
export 'src/adapters/backup_codec.dart';
export 'src/adapters/bff_transport.dart';
export 'src/adapters/drive_archive.dart';
