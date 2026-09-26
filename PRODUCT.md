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

## Accessibility & Inclusion

Usare controlli nativi con etichette accessibili, contrasto leggibile, preferenze di movimento ridotto e aptica facoltativa. Nessun obiettivo formale di certificazione è stato specificato.
