// Almacén seguro en memoria que se queda esperando en el borrado de una clave puntual, para tener la
// cuenta de «Borrar datos locales» (HU-AUTH-010) a mitad de camino mientras el test hace otra cosa.
import 'dart:async';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';

/// Un [AlmacenSeguro] que se comporta como [AlmacenSeguroEnMemoria] salvo en el `borrar` de la clave
/// que pida [trabarEnBorrar]: ahí avisa que llegó ([llegoAlTrabado]) y espera a [soltar] antes de
/// borrar. Sirve para frenar `CustodiaClaveDb.olvidarDatosDelUsuario` entre dos `borrar`: lo anterior
/// ya está borrado y lo que sigue, todavía no.
///
/// Crear las esperas dentro del test (no en `setUp`): [trabarEnBorrar] las arma recién ahí.
final class AlmacenQueSeTraba implements AlmacenSeguro {
  AlmacenQueSeTraba([Map<ClaveSegura, String>? inicial])
    : _interno = AlmacenSeguroEnMemoria(inicial);

  final AlmacenSeguroEnMemoria _interno;
  ClaveSegura? _trabadaEn;
  Completer<void>? _llego;
  Completer<void>? _puerta;

  /// Lo que hay guardado ahora, como en [AlmacenSeguroEnMemoria.contenido].
  Map<ClaveSegura, String> get contenido => _interno.contenido;

  /// Desde ahora, el próximo `borrar(clave)` se queda esperando a [soltar].
  void trabarEnBorrar(ClaveSegura clave) {
    _trabadaEn = clave;
    _llego = Completer<void>();
    _puerta = Completer<void>();
  }

  /// Se completa cuando un `borrar` ya quedó esperando en la clave de [trabarEnBorrar].
  Future<void> get llegoAlTrabado => _llego!.future;

  /// Deja seguir al `borrar` que está esperando (y a los que vengan, sin trabarse otra vez).
  void soltar() => _puerta!.complete();

  @override
  Future<String?> leer(ClaveSegura clave) => _interno.leer(clave);

  @override
  Future<void> escribir(ClaveSegura clave, String valor) => _interno.escribir(clave, valor);

  @override
  Future<void> borrar(ClaveSegura clave) async {
    if (clave == _trabadaEn) {
      _trabadaEn = null;
      _llego!.complete();
      await _puerta!.future;
    }
    await _interno.borrar(clave);
  }

  @override
  Future<void> borrarTodo() => _interno.borrarTodo();
}
