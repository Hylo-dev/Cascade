# Addon Platform Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dimostrare packaging, isolamento, autenticazione, arresto e UI remota prima di incorporare un launcher nel prodotto.

**Architecture:** Host e contenitore addon di prova distinti, con entry point headless e scena remota. Il codice di prova produce evidenza di processi effettivi e non viene importato dalla produzione.

**Tech Stack:** Swift, Xcode, Foundation/XPC, ExtensionFoundation/ExtensionKit; API pubbliche con disponibilità verificata.

**Spec:** [specifica](../specs/2026-09-09-addon-runtime-design.md), [piano principale e vincoli](2026-09-09-addon-runtime.md).

## Stato verificato

Prototipo standalone reale implementato; echo autenticato e rifiuto JSON corrotto passano. La chiusura normale/crash dell'host termina il provider nella fixture. Arresto esplicito a host aperto e controllo dei sottoprocessi non passano. **00.1/00.2 sono parziali, 00.3 ha soltanto un prototipo compilato e non qualificato; P0 non è conclusa.** Il processo figlio diretto aggiunto in seguito dimostra arresto e metriche, ma un avvio delegato a Launch Services sfugge al supervisore e mantiene il gate chiuso. [Evidenze e matrice](../verification/2026-09-09-addon-runtime-P0.md).

## Global Constraints

- macOS 14 come minimo dell'app. Non si alza implicitamente il deployment target.
- Tutti i futuri widget del team usano lo stesso SDK e controlli degli addon esterni.
- Nessuna API privata, task port privilegiata presunta, root o firma di un altro editore inventata.
- Nessun caricamento di codice addon nel processo grafico. Cascade deve essere aperta.
- Un caso non eseguibile viene marcato non verificato; una compilazione non prova il comportamento su un altro macOS.

## Task 00.1 — Contenitore indipendente e protocollo minimo

**Files:** creare Prototypes/AddonPlatform/AddonPlatform.xcodeproj/project.pbxproj, Host/ProbeHost.swift, Provider/ProbeProvider.swift, Shared/ProbeMessage.swift, Host/Info.plist, Provider/Info.plist, Provider/Provider.entitlements, README.md; creare scripts/test-addon-platform.sh.

**Interfaces:** il protocollo di prova usa solo Foundation.Data, con richiesta JSON e risposta JSON. Campi: requestID UUID, operation string, payload string; risposta requestID, providerPID Int32, value string. Operazioni ammesse: echo, checkpoint, exit, spin. L'endpoint viene ottenuto dal percorso di estensione, non indovinando il nome di un XPC service dentro l'app sorgente.

```swift
@objc protocol ProbeChannel {
    func request(_ data: Data, reply: @escaping (Data) -> Void)
}
```

- [ ] Configurare l'host e una piccola app contenitore indipendente con l'estensione. Controllare negli header/interfacce locali disponibilità, metadati legacy e modalità di firma; scrivere la matrice 14/15/26 e sistema corrente disponibile nel README.
- [ ] Implementare nel test shell una richiesta echo con UUID e testo noto, raccolta dei PID reali e timeout esterno di 2 s. Il test deve fallire prima che il listener risponda; successivamente deve affermare hostPID != providerPID e identità della risposta. Non usare un listener in-process.
- [ ] Realizzare discovery, abilitazione attraverso il percorso consentito dal sistema e canale async. Validare il peer attraverso identità di firma del sistema, non un campo dichiarato dal provider. Provare anche un client non autorizzato, con rifiuto registrato.
- [ ] Provare il profilo sandbox, non soltanto la separazione del PID: accesso diretto non concesso a file/credenziali/servizi di un altro addon, rete e creazione di sottoprocessi. Registrare gli accessi realmente negati e gli entitlement accettabili. Una firma valida con entitlement incompatibili col profilo deve essere rifiutata; se la piattaforma non consente una restrizione promessa, quel profilo non passa P0.
- [ ] Eseguire il caso con la sola app contenitore dell'addon; l'app sorgente completa dell'esempio non deve esistere né fornire file/framework. Usare ambiente e cartelle di fixture, senza disinstallare app dell'utente.
- [ ] Registrare packaging, endpoint, identità, firma e passi ripetibili; commit dei soli file di prova dopo verifica.

**Run:** `/bin/zsh scripts/test-addon-platform.sh --case standalone-echo`. Exit 0 solo con processi distinti, risposta entro timeout e prova di identità; salvare JSON in Prototypes/AddonPlatform/Results/standalone-echo.json, ignorando Results in git e citando i risultati nel rapporto.

## Task 00.2 — Arresto, fault injection e metriche

**Files:** creare Prototypes/AddonPlatform/Host/ProbeSupervisor.swift, Provider/ProbeFaults.swift, Tests/ProcessLifecycleTests.swift; modificare scripts/test-addon-platform.sh; creare docs/superpowers/verification/2026-09-09-addon-runtime-P0.md.

**Interfaces:** ProbeFaults supporta spin (loop non cooperativo), allocate (buffer progressivi entro guardrail del test), malformed (risposta non JSON). ProbeSupervisor espone `run(caseName: String) async throws -> ProcessEvidence`; ProcessEvidence contiene hostPID, providerPID, exitObserved Bool, elapsedMilliseconds Double, cpuReadable Bool, footprintReadable Bool, reason String.

- [ ] Scrivere un test che avvia spin, chiude prima normalmente l'host e poi lo termina in una seconda esecuzione. Prima della gestione corretta il test deve rilevare il processo residuo o timeout; il supervisore del test esterno ha sempre un cleanup limitato ai PID di fixture con identità verificata.
- [ ] Implementare l'arresto tramite lifecycle documentato. Per ExtensionFoundation verificare la condizione dell'ultima connessione; non equiparare NSXPCConnection.invalidate alla terminazione. Per un processo figlio diretto non presumere che muoia col padre. Verificare l'uscita anche se non risponde a stop cooperativo.
- [ ] Leggere CPU e footprint con API permesse alle identità reali e OS target. Dimostrare lettura negata, PID non più valido e riuso dell'identità di processo senza segnalare un PID estraneo. Test di allocazione con tetto di sicurezza del harness: 64 MiB aggiuntivi e deadline esterna 5 s, niente stress non limitato della macchina.
- [ ] Confrontare attesa IPC e riavvio ripetendo 20 richieste echo con pause determinate dal harness. Misurare totale CPU/footprint e p95 di risposta senza derivare un budget definitivo da un solo run. Non aggiungere congelamento al prodotto.
- [ ] Documentare scelta del launcher, API esatte utilizzate, processi controllabili, differenze di firma e OS non provati. Il passaggio a P2 è negato se l'arresto dopo crash host non è dimostrato; continuare intanto P1 sui modelli puri.

**Run:** `/bin/zsh scripts/test-addon-platform.sh --case lifecycle`; ripetere con `--case metrics` e `--case unauthorized-peer`. Ogni esito ha PID, percorso eseguibile, identità, timestamp e motivo; un processo ancora presente è FAIL, non "connessione chiusa".

## Task 00.3 — Scena SwiftUI nel pannello reale

**Files:** creare Prototypes/AddonPlatform/RemoteUI/ProbeScene.swift, Host/ProbeSceneHost.swift, Tests/RemoteSceneTests.swift; modificare progetto di prova e scripts/test-addon-platform.sh; aggiornare rapporto P0.

**Interfaces:** scena remota con titolo, pulsante incrementale e menu. L'host riceve attivazione/disattivazione e ospita EXHostViewController tramite adapter AppKit. I comandi UI usano ProbeChannel; nessuna SwiftUI.View trasferita come oggetto IPC.

- [ ] Aggiungere un test di contatore: un clic incrementa il valore ricevuto attraverso il canale, la pressione nel resto del notch resta gestita dall'host. Attendere una callback, non una sleep arbitraria come prova di correttezza.
- [ ] Montare una scena nel pannello non attivante di prova. Verificare resize, clipping, trasparenza, focus, menu, VoiceOver e chiusura; ripetere 20 aperture e registrare numero di processi e footprint dopo il rilascio.
- [ ] Far bloccare/crashare il processo della scena. L'host deve chiudere e riaprire il proprio pannello senza attendere risposte e mostrare un fallback. Verificare che rilasciare la scena non termini una lease di lavoro separata nella prova di lifecycle.
- [ ] Eseguire firme di editori distinti soltanto se disponibili; annotare esplicitamente i casi non testati. Non presentare la firma locale come verifica cross-publisher.
- [ ] Riportare esito della scena ordinaria, dei guasti e della matrice OS. Se la UI remota non funziona sul minimo target, descrivere la limitazione e la scelta necessaria prima del suo task produttivo; non introdurre fallback a codice in-process.

**Run:** `/bin/zsh scripts/test-addon-platform.sh --case remote-scene`. La parte automatica verifica messaggi/uscita; le verifiche visive e VoiceOver devono essere annotate separatamente, con immagini e passaggi, senza dichiararle coperte dal test del contatore.
