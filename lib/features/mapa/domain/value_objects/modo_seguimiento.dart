/// Cómo sigue el mapa principal a la colportora (decisión de Cristian, 05/11, «GPS viejo», #670).
///
/// Son los tres estados del botón de ubicación del mapa, como en Maps. Se pasa de uno al otro con
/// [siguiente]; mover el mapa con el dedo vuelve a [libre].
enum ModoSeguimiento {
  /// El mapa no sigue a nadie: la colportora lo mueve donde quiera. Sin seguimiento no hay un
  /// stream del GPS abierto (no gasta batería).
  libre,

  /// El mapa se mantiene centrado en la colportora, con el norte arriba.
  seguir,

  /// Como [seguir], y además el mapa gira para que lo que está delante de la colportora quede
  /// arriba (hacia dónde se mueve, o mira, el teléfono).
  seguirYGirar;

  /// El modo al que pasa el botón con un toque: libre, seguir, seguir y girar, y de nuevo libre.
  ModoSeguimiento get siguiente => switch (this) {
    libre => seguir,
    seguir => seguirYGirar,
    seguirYGirar => libre,
  };

  /// Hay un stream del GPS abierto mientras el mapa está a la vista.
  bool get sigue => this != libre;

  /// El mapa gira con el rumbo.
  bool get gira => this == seguirYGirar;
}
