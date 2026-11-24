# Estilo, glyphs y sprites del mapa

Desde #673 la app ya no guarda una copia a mano del estilo: el estilo, los glyphs y los sprites
vienen del paquete `colportores_mapa` de [lib-mapa](https://github.com/Colportores/lib-mapa)
(ADR-019), que `pubspec.yaml` toma como dependencia git con el tag de la release (`ref: v1.0.0`,
`path: dart`; decisión de Cristian del 09/11, «Usar lib-mapa»). Siguen viajando **dentro de la app**
(ADR-011): son assets del paquete y Flutter los empaqueta como
`packages/colportores_mapa/assets/mapa/…`, así que el mapa offline no necesita red.

- `estilo/colportores.json`: el estilo único del mapa (el mismo que usa el panel), con
  `pmtiles://REEMPLAZAR` y URLs de glyphs y sprites de relleno que la app reemplaza al abrir el mapa
  (`ConstructorEstiloMapa`). Trae los números de puerta de OSM desde z16 (`address_label`, lib-mapa#3).
- `glyphs/` y `sprites/`: se copian al almacenamiento interno la primera vez que se abre el mapa
  (`PreparadorRecursosMapa`), porque MapLibre los lee con `file://`.
- Los tokens (colores y formas de los estados de casa, paleta y contraste de las zonas, zooms y
  atribución) salen del mismo paquete (`package:colportores_mapa/colportores_mapa.dart`).

## Cómo se actualiza

1. Se sube el `ref` de `colportores_mapa` en `pubspec.yaml` al tag nuevo de lib-mapa.
2. Si cambió algo de `assets/mapa/` del paquete (estilo, glyphs o sprites), se sube
   `PreparadorRecursosMapa.versionRecursosMapa` (así cada teléfono vuelve a copiar los glyphs y sprites).
3. Las capturas del estilo a z16, z17 y z18 son las de referencia de lib-mapa
   (`pruebas/visual/referencia/`, skill `capturas-mapa`).

## Licencias

Los avisos completos viajan con el paquete, en `assets/mapa/NOTICE.md` y `assets/mapa/NOTICE-assets.md`
de lib-mapa (en la caché de pub, `colportores_mapa/assets/mapa/`):

- **Glyphs**: Noto Sans (Regular, Medium e Italic), SIL Open Font License 1.1 (`glyphs/OFL.txt`).
- **Sprites**: hoja `grayscale` de [protomaps/basemaps-assets](https://github.com/protomaps/basemaps-assets),
  derivada de [tangrams/icons](https://github.com/tangrams/icons), MIT (© 2017 Mapzen).
- **Datos del mapa**: no están acá. Son los PMTiles que se cortan de los builds de
  [Protomaps](https://protomaps.com/), con datos de OpenStreetMap (© OpenStreetMap contributors,
  ODbL 1.0), y se bajan del bucket por ciudad. La atribución («© OpenStreetMap») la dibuja `MapaBase`
  con el token `TokensMapa.atribucionCorto` de la librería.
