# Implementare il bootstrap C con interruzione prima del tracing

ID: 40
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 39

## Question

Tradurre il protocollo finito già verificato nel modello offline in un piccolo bootstrap C fidato, senza tracing o exec. Compilare il candidato e verificare la logica con un solo test C; lasciare separata e non eseguita la futura prova nativa con supervisore/child.

## Scope

Ripresa autorizzata il19settembre con Ponytail: due file nuovi, libc, nessuna dipendenza o nuovo modello astratto. Contratto del [modello offline](39-bootstrap-abort-offline.md): framing esatto advance/complete, input limitato, deadline assoluta2s e codici0/70/71/72/73. Il binario candidato legge soltanto il proprio stdin; nessun endpoint dinamico, caricamento addon, fork/spawn/exec, tracing, segnale, osservazione di processi o firma/entitlement.

Il test locale compila separatamente con il ramo main/IO escluso e prova la logica deterministica reale. Il main POSIX viene compilato ma non eseguito: nessuna uscita fisica o qualifica launcher è dedotta. Il gate C0d e tutti i driver preesistenti rimangono identici.

Sol medium implementa i due file; il root revisiona prima di accettare, esegue verifiche e cura documentazione/riavvio. Tetto richiesto20% settimanale Codex, con stop di dispatch al15% e arresto prudenziale del lavoro al18% per conservare margine. Baseline misurata0% nella finestra corrente; reset e campioni sono negli artefatti del19settembre. La scadenza della precedente esecuzione alle00:00 è storica e non si applica alla nuova ripresa.

## Answer

Candidato sorgente completato da Sol medium e corretto/revisionato dal root: [BootstrapAbort.c](../../../Prototypes/AddonPlatform/Tracing/BootstrapAbort.c) e [unico check C](../../../Prototypes/AddonPlatform/Tracing/BootstrapAbortTests.c). Compilazione C11 rigorosa e check in memoria con AddressSanitizer/UndefinedBehaviorSanitizer PASS. Nessuna nuova dipendenza;14 input preesistenti della diagnostica e484 input dell’app invariati.

Correzioni root: validazione nonce limitata, salvataggio immediato di errno, POLLERR terminale, conservazione dello stato iniziale invalido e deadline ricontrollata dopo il setup. [Revisione ed evidenze](../../codex-addon/20260919-ponytail/root-review.md), comandi/log/hash nella stessa directory. Il main POSIX è compilato ma non eseguito: non sono provati arresto fisico, identità, supervisore morto, attach o launcher. Il controllo C0d resta identico.

Per riprodurre il solo check in memoria dal checkout:

```sh
check_dir=$(mktemp -d /private/tmp/cascade-bootstrap-check.XXXXXX)
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun clang -std=c11 -Wall -Wextra -Werror -pedantic -fsanitize=address,undefined Prototypes/AddonPlatform/Tracing/BootstrapAbortTests.c -o "$check_dir/check"
"$check_dir/check"
```

Il modello Python può ricevere byte+EOF nello stesso batch; POSIX read li restituisce separatamente. Il main accetta quindi il comando complete come normale uscita0 nella lettura corrente. Nessun risultato locale certifica morte del supervisore; la futura prova nativa rimane separata.
