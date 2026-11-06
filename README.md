# Svartboken

Addon för WoW Forever som visar vilken spelare som gav dig killing blow i open world och delar statistik och anteckningar med ditt gäng. Mer om hur det fungerar finns i [Svartboken/README.md](Svartboken/README.md).

## För gänget

Ladda ner [Uppdatera-Svartboken.cmd](https://github.com/MaxHegdal/Svartboken/releases/latest/download/Uppdatera-Svartboken.cmd) och kör den en gång. Svara ja på frågan om automatisk uppdatering, så behöver du inte göra något mer.

Filen laddar bara ner `Svartboken.zip` från den här sidans releaser och lägger den i `_forever_\Interface\AddOns\Svartboken`. Med `Uppdatera-Svartboken.cmd tabort` stänger du av den automatiska uppdateringen.

## Publicera en ny version

Committa ändringarna och kör:

```
.\publicera.ps1 1.2.0 "Vad som är nytt"
```
