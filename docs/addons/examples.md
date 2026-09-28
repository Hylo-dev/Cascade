# Esempi sorgente con SDK pubblico

Gli esempi sono librerie SwiftPM indipendenti. Si compilano indicando esplicitamente il package SDK tramite `CASCADE_SDK_PATH`; ciascun README mostra come copiarli e verificarli fuori dal checkout. Dipendono dai prodotti pubblici `CascadeAddonSDK` e `CascadeContracts` e dalle loro dipendenze pubbliche.

| Esempio | Comportamento | Stato e autorità richiesti |
| --- | --- | --- |
| [StandaloneClock](../../Examples/StandaloneClock/README.md) | Ora e minuti dichiarativi, senza tick del provider | Identità e revisione precedente assegnate dall’host; nessuno storage o servizio |
| [StandaloneFocus](../../Examples/StandaloneFocus/README.md) | Avvio, pausa, ripresa e fine di un timer con countdown dichiarativo | Identità assegnata dall’host, storage autorevole e un solo writer; revisioni e ricevute persistenti |
| [ServiceConsumer](../../Examples/ServiceConsumer/README.md) | Richiesta di un grant e lettura di un conteggio sintetico da un provider dimostrativo | Grant e client forniti dall’host; revisioni locali per una nuova assegnazione |

## Timer persistente

StandaloneFocus separa lo stato del timer dalla vita dell’actor. La modalità iniziale distingue una nuova assegnazione dichiarata dal chiamante dal ripristino di una precedente; dati mancanti, corrotti o appartenenti a un’altra assegnazione non vengono sostituiti con un timer nuovo.

Ogni snapshot riserva una revisione nello stesso record dello stato. Le ricevute conservano gli esiti recenti delle azioni: un risultato già noto rimane distinto dall’esito di una successiva scrittura dello snapshot. Quando la cronologia non è utilizzabile, una richiesta valida non riceve una falsa conferma di rifiuto. I dettagli dei limiti, del recupero e delle scadenze sono nel README dell’esempio.

Il countdown è un valore dichiarativo disegnato dall’host. L’esempio non crea un task che aggiorni la pubblicazione ogni secondo. Il token di una scadenza persistito non dimostra che l’host abbia ammesso il corrispondente evento pianificato; una successiva richiesta può riconciliare uno stato già scaduto.

## Consumer e provider dimostrativi

ServiceConsumer include un contratto d’esempio, un provider che restituisce il valore sintetico 3 e un consumer. Il consumer dipende dal contratto condiviso, senza importare l’implementazione del provider. Quel valore non proviene dalla cronologia del timer StandaloneFocus.

Il consumer seleziona un grant fornito nel contesto per lo specifico servizio, scope e generazione. Se non ne ha uno utilizzabile, emette una richiesta di servizio e attende una successiva chiamata dell’host. Non risolve da solo le versioni, non ottiene consenso e non attiva automaticamente altri processi. I test controllano i messaggi pubblici e la propagazione degli esiti forniti dal client; la reale risoluzione REQUIRES e la revoca canonica restano dell’host.

## Dal sorgente all’addon installato

I manifest degli esempi descrivono contratti sorgente e non forniscono un eseguibile di bootstrap, una firma o un contenitore distribuibile. La build indipendente e i test del provider non dimostrano ammissione nativa, parità bundled/external, arresto del processo o esecuzione su tutte le versioni macOS supportate. Queste prove restano nel [piano di completamento](../superpowers/plans/2026-09-10-addon-runtime-completion.md).

Per creare un esempio più semplice usare la [guida al generatore](quickstart.md); per progettare i test consultare [Verificare un provider addon](testing.md).
