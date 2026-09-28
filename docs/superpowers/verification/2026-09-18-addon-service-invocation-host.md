# Invocazioni dei servizi tra SDK e runtime

18 settembre 2026. **Implementazione revisionata e consegnata: 1034 test / 93 suite PASS, build firmata e riavvio verificato.** Il [piano](../plans/2026-09-18-addon-service-invocation-host.md) riguarda il percorso interno di invocazione, non il client pubblico completo o il trasporto nativo.

## Implementazione

Sei file nuovi e sei file Runtime aggiornati collegano richiesta consumer, invocazione provider, completion raw e risposta consumer. Il runtime abilita cumulativamente 1.3 solo con assemblaggio completo, capacità preammesse e negoziazione canonica; le connessioni precedenti mantengono il comportamento previsto. Le nuove connessioni complete compongono la stessa generazione per pubblicazioni e servizi senza riscrivere grant già emessi.

Le route trattengono metadati limitati, con slot consumer/provider prenotati prima del lavoro. Ricevute esatte distinguono rilascio del payload, completamento del comando e uscita del processo. L'executor SDK interno possiede l'intera operazione, valida la risposta completa prima della proiezione e conserva l'incertezza dopo possibile esposizione, anche per operazioni chiamate read. Non ritenta automaticamente.

La revisione ha individuato due finestre che potevano lasciare una completion accodata: durante l'invio di un'altra risposta e nella parte finale del cleanup. L'owner del drenaggio ora registra gli eventi per l'intero ciclo e riprende il lavoro dopo le guardie. I rimborsi falliti sono ritentati al massimo una volta per ciclo; un nuovo rimborso arrivato durante il cleanup mantiene il diritto al primo tentativo. La revisione finale chiude entrambi i rilievi e la correzione del rimborso nuovo.

## Evidenza corrente

| Verifica | Risultato |
| --- | --- |
| Selezione originale dell'incremento | 275 funzioni / 17 suite / 417 casi, snapshot originale |
| Assemblaggio effettivo AddonContext | Un test mirato PASS; adattatore privato della fixture per invoke |
| Correzione finale del cleanup | 54 funzioni / 6 suite / 120 casi PASS |
| Suite completa sul codice finale | **1034 test / 93 suite PASS**, exit 0, 17,61 s |
| Input del codice finale | 463 sorgenti/config verificati contro il freeze |
| Copia esatta per la build app | 433 input, snapshot separato e immutabile |
| Release Runtime | PASS, exit 0, 16,11 s |
| Revisione finale | PASS; nessun P1/P2 residuo individuato |
| Build firmata e collegamento Applications | PASS, exit 0, 12,27 s |
| Riavvio normale | PID 68582 → 18542, percorso corretto e stabilità di 5 s |

Le selezioni si sovrappongono e non vanno sommate. I RED comportamentali riproducono le completion bloccate e il rimborso nuovo erroneamente saltato; gli errori di compilazione e preparazione della fixture sono conservati separatamente. Il freeze finale contiene Runtime `fc280f69be0b441822a0d536766f33d5069891b4b2490baed7f10c8764637906` e test d'integrazione `bafa5bcdc1b82417dc2ee2f1ccbc626e3b0055e66d82af175b882e4e6f8d8d68`.

[Revisione originale](../../../.scratch/codex-addon/20260918-continuation/service-host-independent-review.md) · [Prima correzione e rilievo sul cleanup](../../../.scratch/codex-addon/20260918-continuation/service-host-review-fix-independent-review.md) · [Handoff finale con prove e hash](../../../.scratch/codex-addon/20260918-continuation/service-host-cleanup-fix-report.md) · [Verifica root](../../../.scratch/codex-addon/20260918-continuation/service-host-cleanup-root-verification.json).

## Qualificazione precisa

Il test AddonContext usa storage e asset reali e inoltra invoke all'executor reale tramite un adattatore privato del test; subscribe/unsubscribe non usati sollevano errori espliciti. Non è una conformità pubblica parziale. Il limite globale 32 delle route è qualificato staticamente; il cap reale dei processi è 3 e non viene aumentato per i test.

Il checkpoint DEBUG del cleanup è immediatamente prima del vero rimborso dell'assembler. La fixture verifica risorse pendenti e contatori del governor reale, senza affermare una pausa dentro il governor o durante il suo actor hop. I checkpoint espongono solo fasi scalari, senza autorità; la compilazione Release del codice finale è passata.

Frame dedicati 196608 byte e payload 65536 byte non sono limiti misurati di allocazione Foundation/RSS. Restano da realizzare il client pubblico completo con controlli e sottoscrizioni, il trasporto e bootstrap nativi e la qualificazione di piattaforma/processi reali. Le chiamate observeExit nei test sono ingressi modellati, non prove di morte del processo. C3 globale e il gate C0d restano aperti.

[Revisione finale PASS](../../../.scratch/codex-addon/20260918-continuation/service-host-cleanup-fix-independent-review.md) · [Prova del riavvio](../../../.scratch/codex-addon/20260918-continuation/service-host-cleanup-restart-evidence.json). `/Applications/Cascade.app` punta alla build Debug Apple Development appena compilata. SHA256 dell’eseguibile: `e15bd834d0ace8067a8376786c39b93e7f83d530f48aa5eb83c39a96fed9c2f4`.
