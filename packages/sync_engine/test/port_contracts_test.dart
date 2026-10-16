// Los fakes tienen que pasar el mismo contrato que las implementaciones reales.
//
// Si no lo pasaran, el motor estaría verificado contra un comportamiento que
// nadie va a reproducir. Es también la prueba de que la suite publicada corre:
// en `front-colportores-mobile` este archivo es el mismo, cambiando los fakes
// por DriftJobStore, DriftLocalStore y DriveAdapter.

import 'package:sync_engine/port_contracts.dart';
import 'package:sync_engine/testing.dart';

void main() {
  runJobStoreContract('InMemoryJobStore', InMemoryJobStore.new);
  runLocalStoreContract('InMemoryLocalStore', InMemoryLocalStore.new);
  runArchiveContract('FakeArchive', () => FakeArchive(authorized: true));
}
