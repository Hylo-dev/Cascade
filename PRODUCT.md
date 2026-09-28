# Product

## Register

product

## Users

Utenti macOS che consultano attività e controlli contestuali senza lasciare l'app in uso.

## Product Purpose

Cascade raccoglie widget, Live Activities e strumenti contestuali in un notch modulare, mantenendo basso il consumo di CPU, memoria ed energia.

## Brand Personality

Nativo, discreto, reattivo. Riferimenti funzionali: Dynamic Island e BoringNotch; per il futuro stile glass, Sapphire.

## Anti-references

Controlli che rubano il focus, animazioni decorative continue, interfacce che interrompono il lavoro e duplicazione degli avvisi di sistema. Vincoli ricavati da CLAUDE.md e dalla specifica interattiva approvata.

## Design Principles

- Mostrare il contesto senza interrompere l'azione in corso.
- Conservare il legame fisico con il notch e le convenzioni native macOS.
- Rendere i moduli indipendenti attraverso contratti piccoli e verificabili.
- Sviluppare anche i widget Cascade con lo stesso [SDK e runtime degli addon](docs/superpowers/specs/2026-09-09-addon-runtime-design.md): identici permessi, isolamento e limiti, senza percorsi privati privilegiati.
- Conservare i contenuti validi senza tenere inutilmente attivo il codice che li ha prodotti; separare visibilità, lavoro e durata dell'attività.
- Aggiornare la UI solo quando cambia un input reale.
- Attività e avvisi seguono i [contratti del notch](docs/architecture/live-activity-contracts.md), adattati dalle HIG Apple Live Activities.

## Design Workflow

Per il design usare **Impeccable** e **Taste** (`design-taste-frontend`), applicando le loro indicazioni al prodotto nativo SwiftUI/AppKit e alle [linee guida Apple per Live Activities e Dynamic Island](https://developer.apple.com/design/human-interface-guidelines/live-activities). Il widget Musica è il riferimento interno per dimensioni, densità, colori diffusi e movimento.

- Nessuna pagina del ripiano supera l'ingombro standard del notch: ridisporre il contenuto, non ingrandire la superficie.
- Il taglio fisico esclude solo il centro superiore; i lati possono usare la fascia superiore. Mantenere margini coerenti con la sagoma, senza una fascia vuota uniforme.
- Usare bagliori contenuti e colore del notch per dare identità al contenuto, come la musica; rispettare Riduci trasparenza e Riduci movimento.
- La priorità di una pagina occupata non implica apertura permanente: il ripiano rimane il contesto principale fino allo svuotamento, con normali apertura e chiusura del notch.
- Il riconoscimento e l'ammissione del drag non dipendono dalla durata delle animazioni.

## Accessibility & Inclusion

Usare controlli nativi con etichette accessibili, contrasto leggibile, preferenze di movimento ridotto e aptica facoltativa. Nessun obiettivo formale di certificazione è stato specificato.
