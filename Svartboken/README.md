# Svartboken

Addon för WoW Forever. Visar vilken spelare som gav dig killing blow i open world och samlar gängets dödsfall och anteckningar. Mobs och miljöskada räknas inte.

## Installera och uppdatera

Kör `Uppdatera-Svartboken.cmd`. Den hittar spelet, installerar senaste versionen och frågar om den ska uppdatera av sig själv när Windows startar. Kör filen igen när som helst för att uppdatera direkt, eller med `tabort` för att stänga av den automatiska uppdateringen.

Vill du installera för hand packar du upp zip-filen så att mappen hamnar här:

```
World of Warcraft\_forever_\Interface\AddOns\Svartboken\Svartboken.toc
```

Alla i gänget behöver addonet för att synken ska fungera. Är spelet igång när en uppdatering kommer räcker `/reload`.

## Användning

När du dör i open world visas en liten ruta med mördaren. Vänsterklick öppnar Svartboken, högerklick stänger rutan. Inget annat händer automatiskt: fönstret öppnas bara när du ber om det, och inget skrivs i chatten.

Öppna fönstret med `/sb` eller knappen vid minimapen.

- **Topplista:** vilka som dödat gänget mest.
- **Dödslogg:** alla dödsfall, nyast först.
- **Gänget:** varje medlems dödsfall och värsta fiende.
- **Anteckningar:** klicka på en rad i Topplista eller Dödslogg, skriv och tryck Spara. Anteckningen visas också i popupen nästa gång den personen dödar dig.

## Kommandon

| Kommando | Vad det gör |
| --- | --- |
| `/sb` | Öppna eller stäng fönstret |
| `/sb test` | Visa popupen en gång |
| `/sb flytta` | Flytta popupen, kör igen för att låsa |
| `/sb flytta reset` | Tillbaka till standardplatsen |
| `/sb popup på` eller `av` | Slå på eller av popupen |
| `/sb synk på` eller `av` | Slå på eller av synken |
| `/sb guild på` eller `av` | Synka även via guilden |
| `/sb kanal på` eller `av` | Slå på eller av den automatiska kanalen |
| `/sb gäng` | Öppna gänglistan |
| `/sb gäng add Anna Berg` och `/sb gäng del Anna Berg` | Lägg till eller ta bort ett namn |
| `/sb synktest` | Samma som knappen Testa |
| `/sb demo` och `/sb demo av` | Lägg till och ta bort påhittade rader |
| `/sb minimap` | Visa eller dölj minimapknappen |
| `/sb debug` | Visa vad klienten ger addonet |

## Bra att veta

- **Open world:** addonet lyssnar inte på något i BG, arena, dungeon, raid eller scenario. Dödsfall där sparas inte.
- **Bara spelare:** spelet talar om vem som styr den som gav dödsstöten, så mobs och miljöskada räknas aldrig. Dödas du av en spelares husdjur krediteras den senaste spelaren som slog dig. Finns ingen spelare bland slagen visas husdjuret i stället.
- **Synk:** dödsfall och sparade anteckningar skickas samtidigt till en dold kanal som alla med addonet går med i, till din grupp eller raid, till gänglistan och till guilden om guild-synk är på. Dubbletter sorteras bort. Den som är offline eller i en instans missar det som skickas, tills någon trycker på **Dela historik**.
- **Vem som är med:** vem som helst med addonet på samma ruleset kan hamna i samma tracker. Stäng av kanalen med `/sb kanal av` om du inte vill det.
- **Ny version:** när en kompis har en nyare version visas en rad i chatten och en text i fönstret.
- **Gänglistan:** öppnas med knappen **Gänglista** eller `/sb gäng`. Viskningar tas bara emot från namn på listan, så båda måste ha varandra där.
- **Testa:** knappen i gänglistan visar vilka som svarar.
- **Diagnos:** addonet sparar en kort logg i sin sparfil för felsökning. Den stannar på din dator.
- **Mördaren:** namnet kommer från spelets Death Recap, eftersom combat loggen är stängd för addons på Forever. Klassfärg visas när klienten ger klassen, eller om du haft fienden i target, mouseover eller på en nameplate.
- **Rensa:** tar bort dödsfallen men inte anteckningarna.
