# Cascade

Cascade is a macOS notch that gathers widgets, ongoing activities and contextual tools. Its modularity lets other apps contribute to the experience.

## Language

**Widget**: A piece of content or a control provided by a plugin feature and laid out in the grid of a notch page.

**Live Activity**: The representation of an ongoing activity, visible in compact form at the sides of the notch and viewable in expanded form.

**Page**: A destination in the notch's open surface: a widget page, which hosts an arrangement of widgets, or a system surface such as the file shelf. An activity's expanded view is not a page.
_Avoid_: Screen, when you mean the page rather than the physical display.

**Page 0**: The notch's base page, made of customizable widgets and available even when activities are present.

**Primary activity**: The activity that occupies the notch's compact body and opens when the pointer enters the central zone.

**Bubble**: The separate compact presentation of a secondary activity, at the sides of the notch's main body.

**App contextual activity**: A surface of controls relevant to the app that has focus, such as the commands of Photoshop or of a player.

**Contextual screen**: A notch surface relevant to what the user is doing, such as the shelf during a drag or the audio manager.
_Avoid_: Unqualified smart screen, where it can be confused with a display.

**File shelf**: The notch space in which files are kept temporarily at hand for later actions. Their lifetime and the ways they are captured are the subject of the map.

**Display**: A physical screen on which Cascade can appear.

**Source app**: The application a widget, an activity, a media item or a notification comes from.

**Plugin**: A module that adds widgets, activities or notices to Cascade without a change to the host product. It is declared by a manifest and publishes data, never views. First-party plugins ship inside Cascade; external plugins are a later step, and their distribution format remains the subject of the map.
_Avoid_: Addon or extension, the names of the superseded design.

**Kernel**: Cascade itself in its role as the plugins' host: it validates and keeps their publications, dispatches every event they receive, supervises them and draws their content. In the shipped app, plugin code never runs in it.

**PluginHost**: The service bundled in Cascade that runs every first-party plugin, each on a thread of its own. A plugin that crashes or hangs costs a PluginHost restart, never Cascade.

**Feature**: One thing a plugin does, declared in its manifest with the surfaces it fills, the sources that wake it, the components it shows, its permissions and its actions. Whatever a feature declares it requires.

**Source**: An always-armed listener from the host's catalog, such as power, Bluetooth or volume, that costs nothing while it waits and wakes the plugins that declared it with its latest state.

**Publication**: What one feature shows on one surface. Cascade keeps it and shows it until the plugin replaces or withdraws it, or the kernel stops the plugin.

**Notice**: A short message on the notch, at most ten seconds, shown on the focused display, such as a device connecting or the volume changing. Unlike a **Live Activity**, it reports one change and then leaves.


**Resting silhouette**: Cascade's small closed presence on the top edge of each display, visible even when there are no activities.

**Active display**: The display of the active window; when that is not available, the one indicated by the pointer. It determines where Live Activities go in the mode that follows focus.

**Open display**: The only display on which a Cascade surface is expanded at that moment. It can differ from the active display.
