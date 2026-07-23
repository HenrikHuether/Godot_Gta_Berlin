# GTA Berlin – Minimum Prototype

Ein Godot-Prototyp gemäß `Concept.md`. Die editierbare Karte `scenes/BerlinMap.tscn`
bildet Berliner Stadtblöcke mit texturierten Gründerzeitfassaden, Straßen, Innenhöfen,
Stadtmobiliar und Landmarken ab. Die NPCs verwenden das riggte Modell `Assets/HumanV2.glb`.
Eine prozedurale Außenzone erweitert die befahrbare Karte auf 1,4 × 1,4 Kilometer – mit
Ringstraße, Ausfallstraßen, Gehwegen, Außenbezirken, Beleuchtung und Randbarrieren.
Spieler- und Polizeiauto verwenden ein farbbasiertes Golf-7-Modell ohne Texturen. Das
Spielerauto besitzt einen eigenen RigidBody-Controller mit vier einzeln berechneten
Radaufstandspunkten, Federung, Dämpfung, Stabilisatoren, Ackermann-Lenkung,
Frontantrieb, Automatikgetriebe und kombiniertem Reifen-Grip. Die
Feuerwehr fährt mit einem maßstäblichen, sauber auf der Straße stehenden HLF samt getrennt
blinkendem Front- und Heckblaulicht vor. Pistole, Sturmgewehr und Raketenwerfer besitzen
eigene First-Person-Modelle. Die Fahrphysik
berücksichtigt Beschleunigung, Reibung, Steigung und Bodenneigung. Schüsse verwenden
Magazine, Reservemunition, Nachladezeiten, waffenspezifische Streuung, Rückstoß,
Feuerraten, Distanzabfall und Kopftreffer; Mündungsfeuer, Hülsen, Leuchtspur und Einschlag
machen die Treffer nachvollziehbar. Prozedurale 3D-Sounds begleiten Schüsse,
Raketenstarts, Explosionen, brennende Fahrzeuge sowie Motor und ein mehrstimmiges
pneumatisches Martinshorn des HLF.

Ein EC135 steht auf der zentralen Straße als zweites Spielerfahrzeug bereit. Sein
RigidBody-Flugmodell simuliert Rotorhochlauf, Collective und Cyclic, Pedale,
Translationsauftrieb, Bodeneffekt, Vortex-Ring-State, geschwindigkeitsabhängigen Auftrieb,
anisotropen Luftwiderstand und eine schwache Stabilisierung. Haupt- und Heckrotor besitzen
eigene überstrichene Kollisionsscheiben: Ein Rotortreffer bricht die Blätter ab, nimmt
sofort den Auftrieb und lässt den Hubschrauber bis zum explosiven Aufschlag weiterfallen.

Mission 1 ist als vollständiger Vertical Slice spielbar: Mit einem Aktenkoffer fährt der
Spieler ins Regierungsviertel, verschafft sich Zugang zum Bundestag und übergibt die
Sendung am Empfang. Das dafür erzeugte Bundestag-Areal besitzt den realen
Reichstags-Grundriss von 138 × 98 Metern, eine maßstäbliche Glaskuppel, ein begehbares
Inneres, einen bewachten Haupteingang und einen versteckten Servicegang.

## Start

```bash
./run.sh
```

Alternativ `project.godot` im Godot-Editor öffnen und **F6/F5** drücken.

## Steuerung

- **WASD** – laufen bzw. fahren
- **Maus** – umsehen
- **Leertaste** – zu Fuß springen, im Auto die Handbremse betätigen
- **E** – nahe am Golf oder EC135 ein-/aussteigen
- **EC135: WASD** – Cyclic für Nicken und Rollen
- **EC135: Leertaste / X** – Collective erhöhen / senken
- **EC135: Q / R** – linkes / rechtes Pedal
- **1** – Pistole aus-/einrüsten
- **2** – Raketenwerfer aus-/einrüsten
- **3** – Sturmgewehr aus-/einrüsten
- **Linksklick** – schießen; das Sturmgewehr feuert im Automatikmodus bei gehaltenem Klick
- **R** – aktuelle Waffe nachladen
- **B** – Sturmgewehr zwischen Automatik und Einzelfeuer umschalten
- **Enter** – freie Eingabe im Wachmann-Dialog absenden
- **R** – nach Missionsabschluss oder Fahrzeugausfall die Mission neu starten
- **Esc** – Maus freigeben

## Mission 1: Sonderzustellung

1. Mit dem Aktenkoffer in den goldgelben Golf steigen.
2. Dem gelben Wegpunkt bis zum Bundestag im Regierungsviertel folgen.
3. Einen von zwei Zugängen wählen:
   - Den Wachmann über eine freie Texteingabe überzeugen. Die lokale Dialogauswertung
     reagiert auf Auftrag, Nachweise, Kooperation, Dringlichkeit und den Gesprächston;
     es gibt keine vorgegebenen Antwortoptionen oder einzelne Pflichtformulierung.
   - Die markierte Kiste mit **WASD** aus ihren Schleifspuren schieben und dadurch den
     verborgenen Servicegang freilegen.
4. Im Inneren am Empfang mit **E** den Aktenkoffer übergeben.

Der Dialog funktioniert vollständig offline. Seine Auswertung ist in
`scripts/persuasion_evaluator.gd` gekapselt und kann später durch einen LLM-Dienst
ersetzt werden, ohne den Missionsablauf umzubauen.

## Tests

```bash
godot3 --no-window --audio-driver Dummy --path . --script tests/test_persuasion_evaluator.gd
godot3 --no-window --audio-driver Dummy --path . --script tests/test_mission_one.gd
godot3 --no-window --audio-driver Dummy --path . --script tests/test_combat_systems.gd
godot3 --no-window --audio-driver Dummy --path . --script tests/test_vehicle_controller.gd
godot3 --no-window --audio-driver Dummy --path . --script tests/test_helicopter_controller.gd
godot3 --no-window --audio-driver Dummy --path . --script tests/benchmark_vehicle.gd
```

Der erste Test prüft mehrere friedliche Überzeugungswege, Drohungen, Verneinungen und
erneute Versuche. Der zweite prüft beide Missionsrouten, die Übergabe sowie Benzin,
Fahrzeugschaden und Fahndungsanstieg. Der dritte prüft Waffenmodelle, Gewehrtreffer,
Magazine, Nachladen, Spielerschaden, Torso-Zielpunkt, Sound, Fahrzeugzerstörung und das
HLF samt Bodenlage, Blaulicht, Audioausstattung und fünfminütigem Schlaucheinsatz. Der
Missionstest kontrolliert zusätzlich Kartengröße und die freie Reichstag-Baufläche. Der
Fahrzeugtest prüft Federkräfte, Reibungskreis, vier belastete Räder, Geradeausfahrt,
Bremsen und Lenkung. Der Hubschraubertest prüft Schub, Luftwiderstand, Bodeneffekt,
Rotorhochlauf, Flugsteuerung sowie die Zustandsfolge Rotorbruch, Fall und Aufschlag.
Der separate Kalibrierlauf hält Beschleunigung und Bremsweg in einem plausiblen
Straßenauto-Fenster.

## Fahrzeug und Fahndung

- Das Missionsauto verbraucht beim Fahren Benzin.
- **W/S** steuern getrennt Gas, Betriebsbremse und Rückwärtsfahrt; **A/D** lenken ohne das
  Gaspedal bei diagonaler Eingabe abzuschwächen. Die Lenkung wird mit dem Tempo begrenzt,
  **Leertaste** betätigt die Hinterrad-Handbremse.
- Asphalt, Gehwege und Gras besitzen unterschiedliche Haftung und Rollwiderstände.
- Harte Kollisionen und Waffentreffer beschädigen Fahrzeuge. Bei 0 % explodieren sie,
  werden zu einem verkohlten Wrack und brennen mit Licht-, Rauch- und Soundeffekt.
- Bei einem Fahrzeugausfall kann die Mission mit **R** neu begonnen werden.
- Straftaten erhöhen die sichtbare Fahndungsstufe. Gebäudeschäden lösen neben dem
  Feuerwehreinsatz auch einen Polizeieinsatz aus.

## Hubschrauber

- Der EC135 startet mit abgeschaltetem Triebwerk. Beim Einsteigen läuft der Rotor
  realistisch hoch; sichtbare Drehzahl, Collective-Stellung und Geschwindigkeit erscheinen
  im HUD.
- Collective bleibt wie ein echter Hebel in seiner Position. Für den Schwebeflug ist
  ungefähr die mittlere bis obere Stellung nötig; Vorwärtsfahrt liefert zusätzlichen
  Translationsauftrieb.
- Harte Landungen und Waffentreffer beschädigen den Rumpf; bei 0 HP oder einem
  katastrophalen Hochgeschwindigkeitsaufprall explodiert die EC135. Ein Rotorkontakt
  bleibt davon getrennt: Er nimmt den Auftrieb, lässt den Rumpf weiterfallen und
  löst die Explosion erst beim Aufschlag aus.
- Haupt- und Heckrotor verwenden getrennte, lückenlose Kollisionsscheiben. Kontakt mit
  Boden, Gebäuden oder Fahrzeugen zerstört die Blätter sofort und erzeugt sichtbare
  Rotortrümmer.
- Das EC135-Modell von GRIP420 wird unter CC BY 4.0 verwendet; die vollständige
  Quellenangabe steht in `Assets/Helicopters/EC135_ATTRIBUTION.txt`.

## Einsatzsysteme

- Treffer auf Zivilisten alarmieren zwei detaillierte, kollidierende Polizeiwagen. Beamte
  tragen Einsatzweste, Ausrüstungsgürtel, Funkgerät, Kappe und sichtbare Dienstpistole.
  Sie steigen aus, verfolgen den Spieler und treffen bei freier Schusslinie den Körper des
  Spielers beziehungsweise das besetzte Auto; der Zielpunkt liegt sichtbar am unteren
  Torso und Deckung unterbricht den Trefferstrahl.
- Spielerauto, Polizeiwagen und Feuerwehrfahrzeuge sind durch Kugeln, Raketen,
  Explosionsschaden und Kollisionen zerstörbar.
- Bei 0 HP kippt der Spieler rückwärts um. Eine vollständige Schwarzblende verdeckt den
  anschließenden Respawn und gibt die Steuerung erst nach dem Einblenden wieder frei.
- Bazooka-Treffer zerstören Gebäude. Das Gebäude wird durch ein kollidierendes Trümmerfeld
  mit Brandstellen ersetzt und ein HLF rückt mit räumlichem Motorgeräusch und Martinshorn
  über die nächste Straße an. Emissive Blaulichtflächen und blaue 3D-Lichter blitzen vorne
  und hinten und beleuchten dabei die Umgebung. Vier gestimmte Hornpfeifen, Obertöne,
  Ventilpausen und Doppler-Effekt geben dem Martinshorn einen räumlicheren Klang.
- Zwei Feuerwehrleute steigen auf der Brandseite neben dem Fahrzeug aus, richten einen
  sichtbaren Schlauch mit animiertem Wasserstrahl auf den Brand und löschen ihn nach fünf
  Minuten. Das Martinshorn verstummt unmittelbar bei der Ankunft; gleichzeitig alarmierte
  Polizeiwagen nutzen getrennte Spuren und können das HLF nicht mehr blockieren.

Benötigt wird **Godot 3.6.x**. `run.sh` verwendet zuerst die optionale lokale Kopie unter
`.tools/godot/` und fällt anschließend auf ein systemweit installiertes `godot3` zurück.
Nicht direkt benötigte `.blend`-Quelldateien liegen im von Godot ignorierten Ordner
`SourceAssets/`. Die verwendeten Szenen und Texturen werden direkt vom Spiel geladen.
# Godot_Gta_Berlin
