# Spotlight nativo e impostazioni — verifica locale

20 settembre 2026. Prosecuzione autorizzata con Ponytail e strumenti CLI/AppleScript. Nessuna modifica al codice dell’app, nessuna attivazione del launcher addon, nessun permesso modificato. L’integrazione Spotlight è stata attivata temporaneamente e riportata al valore iniziale disattivato.

## Build e condizioni

La build firmata Apple Development è stata completata dallo script ufficiale su una copia locale di451 input identici al checkout, dopo la disponibilità del plist iCloud. Il collegamento Applications punta a CascadeAddonDevelopment. [Consegna della build](../../../.scratch/codex-addon/20260920-spotlight-native/delivery-resumed.json).

Prova limitata al sistema locale macOS27 e a un display1470×956. Le osservazioni usano il proprietario com.apple.campo e il discendente SpotlightSearchField: la finestra delle conversazioni Siri è distinta e non costituisce una prova della ricerca.

## Esiti osservati

| Controllo | Esito locale |
| --- | --- |
| Apertura dal comando «Apri Spotlight dal notch» | Campo nativo osservato; capsula assestata520×87. |
| Focus del campo | AXFocused=true sul campo identificato. |
| Calcolo sintetico | Inserimento AX di2+2 riuscito; risultato nativo4 osservato e catturato. Nessun risultato lanciato. Query cancellata. |
| Disattivazione con campo aperto | Ritorno da(475,64) alla posizione iniziale(475,65), con dimensioni native conservate. |
| Disattivazione dopo chiusura e riapertura | Misurato prima lo spostamento della capsula assestata; campo poi assente; riapertura con integrazione spenta a(475,65), uguale alla baseline. |
| Impostazioni | Finestra cascade.settings760×570 a(355,152), sidebar e controlli visibili; focus sul controllo settings.size. |
| Preferenze | spotlightEnabled ripristinato a0. |

[Evidenza strutturata](../../../.scratch/codex-addon/20260920-spotlight-native/native-qualification-result.json), [ciclo con chiusura](../../../.scratch/codex-addon/20260920-spotlight-native/closed-cycle.json), [risultato del calcolo](../../../.scratch/codex-addon/20260920-spotlight-native/native-calculation.png), [riavvio conclusivo](../../../.scratch/codex-addon/20260920-spotlight-native/restart-evidence.json).

La simulazione dei tasti non ha prodotto testo e non è dichiarata superata; il calcolo è una prova dell’inserimento AX. Il focus globale ha richiesto selezione esplicita del processo nativo per la chiusura. Un primo ciclo ha campionato la finestra transitoria grande quanto il display: è stato sostituito da una prova che attende e verifica uno spostamento della capsula assestata prima di chiuderla.

## Limiti e revisione

Il ripristino osservato dopo chiusura non dimostra che il monitor riesca a muovere una finestra inesistente: il codice conserva il limite già descritto nella revisione, e macOS può ripristinare la propria posizione alla riapertura. Non è stato riprodotto l’effetto utente ipotizzato; non si applica la proposta di ripristino generalizzato in clearTarget, che può interferire con la pulizia della query dopo Escape.

Restano separati tastiera/IME, VoiceOver, trascinamento continuo, combinazioni display/OS e misure prestazionali. I check handoff/scorciatoia/cancellazione AX e i6 comportamenti droplet erano già passati sullo stesso codice; non sono stati ripetuti per aumentare il numero di prove. Questa verifica non qualifica trasporto, processi o addon esterni.
