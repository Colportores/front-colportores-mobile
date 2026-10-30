import 'dart:typed_data';

import 'puertos_de_fotos.dart';
import 'reglas_de_ticket.dart';

/// Un paso de la escalera de compresión: el lado mayor en píxeles y la calidad JPEG.
final class PasoDeCompresion {
  const PasoDeCompresion({required this.ladoMaximo, required this.calidad});
  final int ladoMaximo;
  final int calidad;
}

/// La foto ya comprimida, lista para la vista previa.
final class FotoComprimida {
  const FotoComprimida({required this.bytes, required this.paso, required this.indiceDelPaso});

  final Uint8List bytes;

  /// Con qué paso salió.
  final PasoDeCompresion paso;

  /// El índice de [PoliticaDeCompresion.escalera] con el que salió: con «No se lee bien», la vista
  /// previa vuelve a llamar con un índice menor (más calidad).
  final int indiceDelPaso;

  /// Cabe en el techo blando de 200 KB (S42). Si no, salió con más peso para que se lea.
  bool get cabeEnElObjetivo => bytes.length <= ReglasDeTicket.objetivoBytesDeLaFoto;
}

/// Cómo se achica la foto del ticket (HU-COB-007, S42): **la legibilidad del texto gana sobre el
/// tamaño**.
///
/// La escalera va de más calidad a menos. Se queda con el primer paso cuyo resultado entra en
/// ≈200 KB; si ninguno entra, se queda con el de más calidad que pasa el tope del servidor (2 MiB),
/// aunque pese más que 200 KB. La vista previa pregunta «¿Se lee bien el ticket?»: con «No», se
/// vuelve a llamar con un paso de más calidad.
final class PoliticaDeCompresion {
  PoliticaDeCompresion(this._compresor);

  final CompresorDeImagen _compresor;

  /// De más a menos calidad. Los números son los de partida (pendiente de confirmar con Cristian):
  /// 200 KB es un techo blando, no una regla dura.
  static const escalera = [
    PasoDeCompresion(ladoMaximo: 2000, calidad: 85),
    PasoDeCompresion(ladoMaximo: 1600, calidad: 80),
    PasoDeCompresion(ladoMaximo: 1600, calidad: 70),
    PasoDeCompresion(ladoMaximo: 1280, calidad: 70),
  ];

  /// Comprime [original] a partir del paso [desdeElPaso] de la [escalera] (0 = el de más calidad).
  /// Devuelve `null` si no se puede leer como imagen o si ni así entra en 2 MiB.
  Future<FotoComprimida?> comprimir(Uint8List original, {int desdeElPaso = 0}) async {
    FotoComprimida? deMasCalidadQueEntra;
    for (var i = desdeElPaso.clamp(0, escalera.length - 1); i < escalera.length; i++) {
      final paso = escalera[i];
      final bytes = await _compresor.comprimirComoJpeg(
        original,
        ladoMaximo: paso.ladoMaximo,
        calidad: paso.calidad,
      );
      if (bytes == null) return null;
      final foto = FotoComprimida(bytes: bytes, paso: paso, indiceDelPaso: i);
      if (foto.cabeEnElObjetivo) return foto;
      if (deMasCalidadQueEntra == null && ReglasDeTicket.fotoValida(bytes.length)) {
        deMasCalidadQueEntra = foto;
      }
    }
    return deMasCalidadQueEntra;
  }
}
