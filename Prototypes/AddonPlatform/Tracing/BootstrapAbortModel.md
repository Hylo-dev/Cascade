# Modello offline del bootstrap

`bootstrap_abort_model.py` verifica la logica di un bootstrap fidato prima del tracing. Consuma byte e osservazioni sintetiche e restituisce previsioni immutabili. Non crea processi, non apre pipe, non invia segnali e non osserva il kernel. Non importa i driver operativi della directory.

Dal checkout eseguire soltanto la suite dedicata:

```sh
python3 -B -m unittest discover -s Prototypes/AddonPlatform/Tracing -p test_bootstrap_abort_model.py -v
```

Questo comando non esegue il driver nativo `scripts/test-addon-managed-death.sh`, che mantiene il proprio gate. L’ambiente della verifica è quello documentato nel rapporto; la suite non qualifica sistemi o processi reali.

## Protocollo modellato

Creare lo stato con `BootstrapAbortModel.begin(nonce, start_ns)` e conservare il valore restituito da ogni `observe(...)`. Non usare la costruzione diretta dei valori per simulare una transizione: non è un confine di autenticazione.

Un record contiene una lunghezza unsigned big-endian di due byte e uno dei seguenti payload ASCII esatti:

```text
1|<nonce di 32 caratteri esadecimali minuscoli>|bootstrap|1|advance
1|<stesso nonce>|bootstrap|2|complete
```

`complete` è ammesso solo dopo `advance`. Il nonce è un valore sintetico, non una credenziale. Attach, tracing, exec e comandi ulteriori sono rifiutati. Sono ammessi al massimo96 byte per payload,196 byte complessivi e due frame; rimangono al massimo97 byte parziali fra chiamate. Questi limiti riguardano lo stato del modello, senza misurare allocazioni Python o RSS.

Il tempo è un intero in nanosecondi fornito dal chiamante. La scadenza è sempre start+2secondi; frammenti, EINTR e avanzamenti validi non la rinnovano. La scadenza è terminale anche all’uguaglianza. Valori booleani al posto di interi, clock regressivo e input malformati sono rifiutati.

| Codice previsto | Causa modellata |
| --- | --- |
| 70 | EOF esplicito al confine fra frame |
| 71 | Protocollo, campo, ordine o frame troncato non valido |
| 72 | Scadenza assoluta raggiunta |
| 73 | Errore locale di setup o lettura |
| 0 | Completamento normale della baseline |

Una notifica HUP, EINTR o un batch senza dati non equivale a una lettura di zero byte: EOF va indicato esplicitamente. Il modello considera tutti i byte del batch prima di concludere con successo; dati avversi nello stesso batch prevalgono. Uno stato già terminale restituisce sé stesso nelle chiamate successive. Un token non dimostra che il suo mittente sia ancora vivo.

## Coerenza delle osservazioni sintetiche

`evaluate_synthetic_fixture` accetta soltanto lo schema chiuso `cascade.bootstrap-abort.synthetic.v1`, etichettato `simulated`. La funzione `fixture()` nei test mostra il record completo; non è un formato compatibile con i rapporti nativi storici.

Sono richiesti identità sintetiche distinte e conservate prima dell’iniezione, ricevute corrispondenti per observer/supervisor/child, una decisione EOF70 internamente possibile e otto osservazioni obbligatorie senza duplicati. Il caso modellato descrive un’iniezione signal9 e richiede entrambi gli esiti del supervisore signal9 concordi; una normale uscita0 non la sostituisce. Il codice9 è solo un dato confrontato, mai un’operazione eseguita. L’esito del child deve essere70; una concessione di completamento normale invalida questo caso.

Tutte le ricevute usano un solo dominio temporale dell’osservatore e rimangono nell’intervallo strettamente inferiore a1,5secondi. Non si sottraggono timestamp del modello da quelli dell’osservatore. Uscita mancante, log senza ricevuta, stato invalido, identità diversa, clock estraneo, timeout, guard, fallback, cleanup o altra contraddizione rendono il caso incoerente. L’input può contenere al massimo16 record; il chiamante ha già allocato i propri dati prima della valutazione.

Un esito positivo significa esclusivamente `modelAbortEvidenceConsistent`. I campi `trustedBootstrapAbortObserved`, `supervisorDeathStopsWorker`, `nativeLauncherAdmitted` e `nativeSuccess` rimangono false. Anche un record coerente e un oggetto del modello possono essere costruiti dal chiamante: non sono prove autenticate.

## Limite della prova

La previsione di un abort non dimostra l’uscita fisica del bootstrap, la sua esecuzione prima di main, l’assenza di orfani o la sicurezza dell’attach. Il requisito completo dalla creazione fino a exec e alla perdita del supervisore resta aperto. Le guardie del supervisore e dell’osservatore, le identità firmate e la matrice dei sistemi richiedono qualifiche separate.

La [verifica del modello](../../../docs/superpowers/verification/2026-09-18-addon-bootstrap-abort-offline.md) conserva test, revisione e limiti. Il [ticket sui processi gestiti](../../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md) resta distinto da questo incremento offline.
