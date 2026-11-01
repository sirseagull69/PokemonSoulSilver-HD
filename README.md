# SoulSilver HD

Eigene Engine (Godot 4), die Karten aus der **eigenen** HeartGold-/SoulSilver-ROM des Nutzers lädt und im HD-2D-Stil darstellt: echtes Licht, Schatten, Umgebungsverdeckung, Bloom, Tilt-Shift. Gebaut fürs AYN Thor.

**Das Repo enthält keine Spieldaten.** Keine ROM, keine Grafiken, keine daraus gewonnenen Dateien – nur Code. Die App liest die ROM zur Laufzeit auf dem Gerät.

## Benutzen
1. APK aus dem Release `latest` installieren.
2. SoulSilver-/HeartGold-ROM (`.nds`) in `ROMs`, `Download` oder `Documents` legen – oder beim Start auswählen. Beim ersten Start „Zugriff auf alle Dateien“ erlauben.
3. Steuerung: linker Stick bewegen, rechter Stick drehen/zoomen, **A** Tag/Nacht, **Y** Wetter (klar/wolkig/Regen/Nebel), **B** Effekte an/aus.

## Aufbau
- `engine/rom/` – ROM-Dateisystem, NARC, BLZ (ARM9), G3D-Modelle (Displaylisten → Mesh), TEX0-Texturen
- `engine/world/map_loader.gd` – Kartenkopf-Tabelle (aus ARM9, selbstprüfend über Tileset), Matrix, Kartenblöcke, Gebäude
- `engine/world/look.gd` – Materialien, Tilt-Shift
- `engine/world/atmosphere.gd` – Tageszeit (weich), Wetter, Wolkenschatten, Sonnenstrahlen (volumetrischer Nebel), Regen, Lichter an Häusern nachts
- `engine/tests/load_test.gd` – Headless-Test, gibt nur Zahlen aus
- Branch `emulator-licht`: früherer Ansatz (WatermelonDS-Fork mit SSAO-Pass)

## Stand
- 0.2 (01.11.2026): Tag/Nacht repariert (wurde vorher ignoriert) und weich überblendet; Wetter mit Y; wandernde Wolkenschatten, Sonnenstrahlen, Regen, Nebel; warme Lichter vor Häusern nachts.
- 0.1.1 (01.11.2026): ROM-Suche auch auf SD-Karte, wartet auf Dateizugriff, eigener Auswahldialog statt nativem.
- 0.1 (01.11.2026): Neuborkia + Nachbarblöcke als 3D-Szene, freie Kamera, Licht. Platzhalter statt Spielfigur. Nicht auf dem Thor getestet.

## Lizenz
Code: MIT. Pokémon und alle Spielinhalte gehören Nintendo/Game Freak/The Pokémon Company; dieses Projekt enthält und verteilt keine davon.
