# Definire soglie e incidenti RAM dei provider

ID: 65
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 64

## Question

Quale profilo iniziale deve trasformare il footprint valido di un provider in riduzione delle ammissioni, incidente di salute o richiesta di stop? La proposta riguarda soltanto i provider event-driven, non scene UI o audio continuo.

## Contesto

[Attribuzione al solo proprietario](64-addon-memory-attribution.md) approvata. La specifica contiene un obiettivo64MiB e una soglia candidata96MiB, ma non dice se64MiB sia già un incidente, come distinguere episodi ripetuti, o quando riaprire le ammissioni. Le riserve preventive di ResourcePolicy sono un altro meccanismo. Il footprint è già disponibile nel batch fisico; aggiungere un classificatore senza queste regole inventerebbe comportamento. [Ricognizione e proposta](../../codex-addon/20260922-memory-owner/task64-report.md).

## Alternative

1. **Riduzione progressiva con episodi distinti (consigliata).** Adottare64/96MiB come parametri del primo profilo interno dei provider: oltre64MiB e fino a96MiB inclusi, un nuovo episodio moderato chiude le sole nuove ammissioni; un campione corrente valido a64MiB o meno chiude l’episodio e rimuove il solo blocco RAM. Una permanenza continua sopra64MiB conta una volta, non a ogni campione. Un nuovo processo verificato può produrre un nuovo episodio; wake, misure mancanti e nuova registrazione dello stesso processo non azzerano il blocco né moltiplicano incidenti. Oltre96MiB, richiesta di stop immediata al primo campione valido, senza grazia aggiuntiva; non una prova di uscita avvenuta. Il caso severo prevale e non conta anche come moderato nello stesso giro.
2. **Solo soglia severa.**64MiB resta un obiettivo informativo senza pausa o incidenti moderati RAM. Oltre96MiB un campione valido richiede lo stop. Più semplice e tollerante ai picchi, ma rinuncia all’intervento progressivo e alla quarantena da episodi RAM moderati.

## Contratto della prima alternativa

- Unità MiB=1.048.576byte; valore mancante/obsoleto/identità errata non è zero, non apre nuovi episodi né riapre ammissioni. Il footprint può essere valido anche alla prima osservazione o con errore del solo calcolo CPU.
- CPU e RAM conservano blocchi indipendenti: si ammette nuovo lavoro soltanto quando nessuno dei due lo vieta e la versione non è in quarantena. Lavori già ammessi mantengono le scadenze; nessuna nuova coda, replay o cancellazione automatica dei loro dati.
- Usare la storia comune per versione: tre incidenti moderati nella finestra già scelta di300secondi producono quarantena. Se nello stesso giro CPU e RAM provano entrambe un nuovo moderato, registrare al massimo un incidente per owner, aggiornando comunque lo stato di entrambe. Il recupero RAM non azzera la storia o una quarantena.
- Lo stop per RAM è atteso e non genera un retry crash. Le riserve fisiche restano trattenute fino all’uscita realmente osservata. Un eventuale avvio host per tornare a misurare non cancella blocco o storia; il lavoro ordinario non aggira la pausa.
- Nessuna attribuzione RAM ai consumatori del servizio. Non si approvano somma provider+scena o soglie128/192MiB della UI.
- Per questo primo profilo interno, la riduzione consiste nel rifiuto dei nuovi lavori, senza nuovo messaggio al provider o promessa di liberarne la cache. La frase precedente “prima rilascio cache” resta una possibile integrazione futura da specificare, non un’azione simulata o un prerequisito indefinito dello stop.

Entrambe le alternative restano verificabili soltanto con adapter controllati finché identità, misura e arresto nativi non sono qualificati. Il launcher resta bloccato. Nessuna delle alternative è implementata prima della scelta.

## Answer

Il23settembre2026 l’utente sceglie1, il profilo progressivo descritto sopra: oltre64MiB pausa nuove ammissioni e un moderato per episodio; recupero a64MiB o meno; oltre96MiB stop atteso. Storia comune e deduplica per owner/giro come nel contratto; nessuna attribuzione ai consumatori. Parametri del profilo interno provider, nessuna abilitazione o qualifica nativa.
