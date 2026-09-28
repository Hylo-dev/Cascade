# Bootstrap separato per addon — prova del 12 settembre

Il prototipo con bootstrap distinto per addon e Worker che eredita la sua sandbox ha
completato tutti i quattro casi previsti sulla configurazione locale. L’isolamento dei
dati, la loro continuità e la sostituzione controllata dell’eseguibile sono stati osservati.
Il launcher produttivo resta disabilitato: questa prova usa codice fisso, non qualifica
ancora la morte del supervisore, pacchetti arbitrari o tutte le piattaforme supportate.

## Configurazione e risultato

Cinque eseguibili firmati della stessa build: Supervisor fidato senza App Sandbox,
bootstrap A/B con il solo App Sandbox, Worker A/B con App Sandbox e inherit. Tutti
usano Hardened Runtime, senza deroghe di debug o permessi aggiuntivi. La firma stretta,
il certificato previsto, le identità, i profili esatti e l’Info incorporato sono stati
controllati prima di eseguire la fixture.

| Caso | Comportamento osservato | Supervisor / figlio | Esito |
| --- | --- | --- | --- |
| O1 | A crea e rilegge il proprio campione | 45212 / 45216 | Entrambi usciti con codice 0 |
| O2 | B crea il proprio campione; apertura in lettura e scrittura del campione A negata | 45217 / 45218 | Entrambi usciti con codice 0 |
| O3 | A ritrova contenuto e inode; accesso al campione B negato | 45221 / 45222 | Entrambi usciti con codice 0 |
| O4 | Stesso confronto A sotto controllo dell’exec; nuova identità Worker verificata da fermo e singola ripresa riuscita | 45223 / 45224 | Entrambi usciti con codice 0 |

Le negazioni incrociate sono EPERM, non file mancanti. L’accesso positivo del proprietario
nel caso precedente dimostra che il bersaglio esisteva. L’apertura estranea, se fosse
riuscita, sarebbe stata chiusa senza leggere o scrivere dati. Sono stati usati soltanto
campioni sintetici: massimo 192 byte di contenuto; l’allocazione dei container da parte di
macOS rimane separata e non misurata.

Gli otto processi hanno conferme effettive di uscita, tramite wait del figlio posseduto e
notifiche kernel. Nessun guardrail è intervenuto. Le durate osservate dell’intero caso
sono circa 1,318 / 0,585 / 0,064 / 0,070 secondi: sono singole osservazioni della fixture, non
benchmark del runtime o percentili di avvio. I domini temporali nativo e Python restano
separati. O4 conserva l’allarme originale e osserva la nuova identità pubblica S3 prima
dell’unica richiesta di ripresa, seguita da S4 del Worker.

## Provenienza e verifiche

Ambiente eseguito: macOS 27.0 beta 26A5425a, arm64, SDK 27.0, Apple clang 21.0.0;
compilazione con deployment target 14.0. Team di sviluppo `A6A5HQL6K4`, certificato
leaf SHA1 `4A857D842A5406C2D3071776FDE7B27B3098FE63`. Non sono prove su macOS 14,
con un altro editore o con firma di distribuzione.

Comando: `zsh scripts/test-addon-owner-bootstrap.sh`, nella copia isolata del progetto.
Sessione 39329 conclusa con codice 0. Artefatti `/private/tmp/cascade-owner-bootstrap-hgKoR6`.
Rapporto grezzo `owner-report.json`, SHA-256
`e25739a128b3d6b53dbfe08b844ddcdb6aca9e13fb2f25fc7bcf6fd0c94bff59`.
Il record distingue `fixedOwnerBootstrapObserved` dall’ammissione produttiva, che resta falsa.

La prima invocazione era fallita durante la preparazione del comando di firma, prima di
avviare qualsiasi partecipante. Quel rapporto e il suo unico prodotto rimangono immutati
in `/private/tmp/cascade-owner-bootstrap-eNbrVB`. Dopo la revisione sono stati corretti
due argomenti del comando e il trattamento indipendente degli errori di validità della
firma. I test coprono anche timeout reali dell’osservatore simulato, conferme di uscita
mancanti e fallimenti dei controlli positivi. 54 test storici e 26 test del prototipo passano.
La nuova esecuzione è l’unico tentativo successivo alla correzione; non ci sono retry
nascosti o varianti di permesso. La revisione delle correzioni è conclusa senza rilievi aperti. Il successivo controllo sui campi malformati è stato verificato senza ripetere la prova nativa e conserva gli stessi esiti sui dati registrati.

## Limiti e prossimi passi

Questa evidenza consente di proseguire sul candidato di bootstrap con sandbox ereditata.
Restano necessari controllo e prova della morte del supervisore/host, gare all’avvio,
verifica del bootstrap distribuito e delle sue dipendenze, autenticazione del trasporto,
quote native e integrazione con lo stesso SDK dei widget del team. Le protezioni VM non
osservabili integralmente restano sconosciute. Il risultato non abilita addon nell’app.

I due campioni dei proprietari restano nei container diagnostici indicati nel rapporto.
Il solo controllo esterno creato dall’osservatore è stato rimosso. Nessun dato dell’utente
è stato usato o cancellato; non è stata effettuata pulizia ricorsiva dei container.
