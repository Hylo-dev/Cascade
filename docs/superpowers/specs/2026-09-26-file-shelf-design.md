# Persistent file shelf and conversion

Date: 26 September 2026.

Status: specification approved by the user with "exactly, continue" after reviewing
the document. The decisions in section 2 and the completion proposed in the
following sections form the basis of the execution plan. The other actions
in section 8 stay for later. No application code has been changed.

## 1. Goal

Collect files in the notch, keep them across relaunches, convert them and deliver
copies of them to other destinations. The experience visually links dragging,
the deck of cards, the list and conversion. The originals stay in their location.

## 2. Confirmed decisions

| ID | Decision | Constraint |
| --- | --- | --- |
| F1 | A file drag calls up the closed notch with an elastic heartbeat. | The feedback comes before entering the target; nothing is acquired before the drop. |
| F2 | Moving over the notch reveals the animated shelf. | The cards emerge from the center and settle to the left. |
| F3 | Files are represented as a hand of cards. | First card slightly rotated to the right; the following ones fanned out progressively toward the left. |
| F4 | The shelf is the main page while it contains files. | The occupancy survives the notch closing and the app relaunching. |
| F5 | Clicking the deck opens the file list with an animation. | Opening the list must be animated, like the rest of the shelf. |
| F6 | Convert offers destinations suited to the selected files. | Inputs on the left, selector and arrow in the central area, results on the right. |
| F7 | The arrow links inputs and results at the center of the composition. | It must not be placed below the flow as an element at the bottom of the page. This decision replaces the initial placement. |
| F8 | After the format is chosen, Start appears and the conversion shows animated progress. | Results become usable only after actual completion. |
| F9 | Work proceeds with FFmpeg. | The complementary technical choices and the proposed scope are detailed below. |
| F10 | The outbound drag delivers copies and empties the shelf of the delivered files. | The originals are kept; refusal, cancellation or error do not remove the file. |
| F11 | The shelf keeps the files after Cascade relaunches. | Persistent references for the originals; retention of the results produced and still present in the shelf. |

Sources of the decisions: initial request for the shelf; explicit choice
"Copy to the destination and empty the shelf; originals kept";
follow-up "let's continue with FFMPEG and keeping the files in the shelf",
with an animated list and the arrow at the center.

## 3. Acquisition, deck and navigation: proposal

At the start of a drag recognized as files, the notch performs a short double
elastic pulse. The feedback is not repeated on every mouse movement.
Global detection is indicative: entering and dropping on the target actually
verify the offered types. A drag of text or of a window must not
be treated as a file acquisition.

On entry the shelf preview appears: the cards are born in the usable central
area and reach the left side. Any hardware cut-out stays excluded
from content and targets. An exit without a drop restores the previous
page; a valid drop confirms the items and keeps the shelf.

The proposed limit is four visible cards, with a +N counter beyond the fourth.
It is not a limit of four acquirable files. New files are appended in order;
an original already present does not create a second entry. Different files with the same
name stay distinct. Folders are excluded from the first version, with explicit
feedback; a mixed batch makes any items that were not acquired visible.

Clicking the deck turns the cards into the rows of the list inside the same
notch surface. The thumbnails keep their identity and starting
position; the following rows enter with a short stagger. Back reassembles
the deck. No separate window opens. The list contains name, type, status,
multiple selection and a remove action; it scrolls when it exceeds the available height.
A click selects, while movement beyond the drag threshold starts the delivery.

While occupied, the shelf is the default destination on opening. Manual
navigation to other pages stays possible and is not undone
by shelf updates. The notch can close again. When the last item
leaves successfully, it returns to the ordinary selection of pages and activities.
A drag that explicitly enters the notch can show the temporary target;
automatic events do not replace a page the user is looking at.
Compatibility with the native Spotlight search must be verified without losing
the search text or focus if the drag is cancelled.

## 4. Conversion: proposal

The composition uses three horizontal zones: inputs, transformation, results.
The arrow occupies the vertical and horizontal center of the space between the two groups
of cards. The selector sits above the arrow in the same central zone; Start
appears below the selector in the available layout without moving the arrow
to the bottom of the page. The layout must be verified on the hardware notch and
on the software one, avoiding overlaps between controls, arrow and physical cut-out.

Opening Convert keeps the input cards on the left. On the right, a
forecast identified as such appears only after a format is selected.
Start is available when the combination is valid. For a mixed selection,
the selector offers only formats common to all the selected files; when there are
no common destinations, the list lets the user choose a compatible group.
No file is skipped silently.

During processing, motion along the arrow communicates the direction and an
indicator shows the real progress. Work with no known duration shows an
indeterminate state. The UI offers Cancel and the status of each file. Complete
results appear on the right and can be dragged; failed ones stay distinguishable
and can be retried. Conversion neither replaces nor removes the inputs.

The initial batch processes one file at a time in the background, without blocking the UI.
A hidden page does not cancel the work. No animation stays active when
it is not needed; Reduce Motion keeps state and progress with minimal transitions.

## 5. Engines and scope: proposal

| Area | Engine | Initial destinations |
| --- | --- | --- |
| Audio/video | FFmpeg and ffprobe distributed with Cascade | MP4, audio extraction, MP3, M4A/AAC, WAV, FLAC, subject to the capabilities of the build and of the single input. |
| Images | macOS ImageIO | JPEG, PNG, TIFF, HEIC when supported by the system. |
| PDF | PDFKit and ImageIO | Images to PDF; PDF pages to raster images. |

FFmpeg is invoked with separate arguments and controlled presets. ffprobe reads
tracks and duration; the selectable format depends on the real capabilities, not on the
extension alone. The bundled build must have its codecs, architectures, signing and
redistribution obligations verified. It does not depend on a user-installed Homebrew.
A second AVFoundation audio/video engine is avoided in the first version.
Office documents, OCR, animations and vector conversions stay out of scope.

Each result is born in a temporary file managed by Cascade. It becomes final
only after the process has exited successfully and the result has been verified, with a name
free of collisions. Cancellation waits for the process to stop before cleanup.
Originals and results that are already complete are not removed by cancelling the batch.

## 6. Retention and recovery: proposal

The shelf saves identity, order, file reference and the state needed for
recovery. For local originals it keeps persistent references, without
duplicating their content right away. Shelf persistence is not a backup:
a deleted original, a disconnected volume or a lost permission produces an
unavailable entry, which the user can relink or remove.

Incoming promised files and conversion results are materialized
in the app's persistent data space. They must not be entrusted to a temporary
folder that can be deleted on relaunch. A promise is acquired only after it has been
written successfully; cloud items not yet available show their
state, without pretending that the conversion can start.

On relaunch, incomplete work is marked as interrupted and retryable, with no
conversions restarted automatically. Complete inputs and results stay.
Incomplete temporary files are cleaned up only after ruling out a process that is still
active. An export without a persisted confirmation leaves the item in the shelf: the
recovery does not infer success from the mere start of the drag.

## 7. Delivery and removal: proposal

Output uses copy operations and one file promise per item, when accepted
by the destination. The card is removed only after its file has been
written successfully. In a partial drop only the cards actually
delivered leave; the others keep their position and the option to retry.

The completion of the drag session does not prove that the promise was written,
which can happen later. A successful write proves delivery to the requested
URL, not a later upload or internal save by the receiving app.
For external originals, a compatibility path based only on URLs,
without individual confirmation, keeps the items in the shelf and does not declare
the delivery verified. In the first version the results owned by Cascade
are offered through file promises: a destination that accepts only URLs
cannot receive them through this path and causes no removal. Future
URL support for results requires a distinct retention policy,
since the end of the drag does not prove that the recipient has finished reading.

Removing the entry and cleaning up the file owned by Cascade are separate.
The removal of the entry is persisted first; only afterwards can the file be cleaned up,
excluding conversions or deliveries that are using it. A crash between these two
steps can leave a file to clean up, never an entry restored without its
result. External originals are never deleted by these operations.
The manual removal of
a managed result is distinct from the removal of a reference to the original
and must make its effect clear before deleting the only copy of the result.

## 8. Other actions: later proposal

Convert is the requested action. Share (including AirDrop) and Create ZIP remain
proposals to evaluate separately, without implicitly turning them into
requirements of the first increment. Preview, Show in Finder and Remove from
Shelf complete the context menu. Sharing is not treated as equivalent to
a verified export that automatically empties the shelf.

## 9. Integration into Cascade

The existing pointer path and the display coordinator must be
reused for routing and ownership of the open notch. The persistent shelf
model is shared across displays and independent of the views. AppKit acquisition,
background conversion and animated presentation keep distinct
responsibilities, without duplicating the file state in the individual surfaces.

The composition follows the product contracts for internal and external widgets.
File access and running the converter require explicit capabilities:
the plan will have to place them within the existing boundaries, without introducing a
privileged widget path or declaring the addon runtime constraints already resolved.
The persistent page is coordinated with the contextual pages specification,
which is still under discussion; it is not assumed that that navigation is already active.

**Local exception approved on 26 September 2026.** Pending the native gate,
the shelf can be integrated directly into Cascade like the Music page,
without enabling the external addon launcher. The first increment includes
a heartbeat on drag-in, an animated deck with four cards and a +N counter, an animated list,
persistence across relaunches and outbound copying with removal of only the entry delivered
successfully. The originals stay intact. The occupied shelf is the default
page on opening; manual navigation stays possible and
automatic updates do not overwrite it. Conversion stays deferred
until supervision, cancellation and recovery are ready; the interface must
not present it as available before then. The exception is limited to
this page: no external addon code is loaded into the host process and
grants, quotas and launcher requirements do not change.

## 10. Planned verification

- Drags of files, text and windows; entry, exit, cancellation and valid drop.
- One, four and more files; same-name files, duplicates and partially valid drop.
- Animated opening and closing of the list, drag distinct from click, keyboard and Reduce Motion.
- Central arrow without overlaps on hardware/software notch and different displays.
- Relaunch with originals, complete results, missing files and interrupted work.
- Real conversions, mixed selections, unsupported format, cancellation and error.
- Single, multiple and partial export; refused destination, failed copy and crash before the persisted confirmation.
- Main page while occupied, manual navigation, return when empty and drag during search.
- Build, update of the /Applications/Cascade.app link and verified relaunch before declaring the implementation finished.

## 11. References

- [Pages and contextual selection](2026-09-26-contextual-pages-design.md).
- [Shelf collection and lifetime](../../../.scratch/cascade-product/issues/10-file-shelf.md).
- [FFmpeg: conversion and progress](https://ffmpeg.org/ffmpeg.html).
- [ffprobe: media analysis](https://ffmpeg.org/ffprobe.html).
- [FFmpeg: redistribution](https://ffmpeg.org/legal.html).
- [Apple: ImageIO writable formats](https://developer.apple.com/documentation/imageio/cgimagedestinationcopytypeidentifiers()).
- [Apple: PDFPage](https://developer.apple.com/documentation/pdfkit/pdfpage).
- [Apple: writing file promises](https://developer.apple.com/documentation/appkit/nsfilepromiseproviderdelegate/filepromiseprovider(_:writepromiseto:completionhandler:)).
- [Apple: partial drops](https://developer.apple.com/documentation/appkit/nsdragginginfo/numberofvaliditemsfordrop).

## 12. UI/UX review of 27 September 2026

The explicit request updates the first local increment: shelf priority while occupied, **without keeping the notch always open**. The reference is Music for standard size, diffuse light, color and behavior. The top band stays usable on both sides of the physical cut-out; the center must stay free. The flow cannot enlarge the notch beyond the standard size. Impeccable and Taste are the working guides, adapted to the native UI and to the [Apple principles](https://developer.apple.com/videos/play/wwdc2023/10194/).

The drop destination uses a large centered icon and title. Admission must be ready before the animation, even for fast drags. Only after an accepted delivery does the first file appear at the center, move to the left and open the fan. A click or a two-finger scroll spreads the files out in a horizontal row: the action controls disappear and an arrow leads back to the view with Convert/Clear. The files keep icon and name without a container. Reduced motion avoids translations and the animated fan; Reduce Transparency removes the glows.

These decisions replace the permanent opening and the buttons in the list of the 26 September build. Persistence, safety of the originals and real availability of the conversion stay unchanged.
