# Feature Specification: Choose the Function Key Buttons

**Feature Branch**: `017-function-key-choice`

**Created**: 2026-10-13

**Status**: Implemented

**Input**: User description: "In Settings, tick which F1–F12 buttons the function key bar at the bottom
shows, so chosen ones can be turned off. When many are turned off, the buttons should have a maximum
width, so they do not stretch across the whole screen when, for example, only one is left."

## Context

The function key bar (spec 002, layers from spec 010) shows twelve buttons, F1–F12. They share the
bar's width evenly, and holding ⇧, ⌃, ⌥ or ⌘ shows the commands of that layer. Today the bar can only be
shown or hidden as a whole (View menu, Settings → General, the bar's context menu). Some users know a few
keys by heart and want the bar to show only the others. With fewer buttons the even sharing makes each
button very wide; one button would fill the whole window.

It ships with specs 010–016 in release 0.4.0 (maintainer, 2026-10-13).

## Clarifications

### Session 2026-10-13

- Q: What happens to a key whose button is hidden? → A: It keeps working. Only the button goes away;
  which command a key runs stays in Settings → Keyboard.
- Q: How is a button hidden when the bar shows the ⇧/⌃/⌥/⌘ layers? → A: By F-key position: unticking F3
  hides F3 in every layer (F3, ⇧F3, ⌃F3, ⌥F3, ⌘F3). Twelve tick boxes, not one per layer.
- Q: Where do the buttons go when there are few of them? → A: Each button is at most a maximum width;
  they stand side by side from the left edge in F-key order and the rest of the bar stays empty.
- The answers below were *decided while writing the spec; to review*:
  - Q: Where is the choice? → A: Settings → General, under "Show function key bar": "Buttons on the
    bar:" with twelve tick boxes F1–F12, all ticked by default. The bar's context menu gets "Choose
    Buttons…", which opens that place.
  - Q: Can every box be unticked? → A: No. The last ticked box cannot be unticked; hiding the whole
    bar stays the job of "Show function key bar".
  - Q: How wide is a button at most? → A: 140 points, about the width of a button when all twelve are
    shown in a 1,700-point wide window. Below that width the buttons share the bar evenly as today.
  - Q: Is the choice exported? → A: Yes, as a user preference in the settings file; a file or a
    configuration without it shows all twelve buttons.
- Q: Which release? → A: 0.4.0, together with specs 010–016 (maintainer, 2026-10-13).
- Q: Where does the first button start? → A: The bar leaves a small margin at both ends, so F1 does
  not sit in the window's rounded corner (maintainer, 2026-10-13); the first key cap lines up with
  the command line field above it.
- *Decided during planning; to review*: the preference stores the hidden positions as text
  (`functionKeyBar.hidden`, for example "5,6,8"), so a missing or empty value shows all twelve and
  a value that would hide every position also shows all twelve.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hide the buttons I do not need (Priority: P1)

A user who knows F5, F6 and F8 by heart opens Settings → General and unticks them. The bar shows the
other nine buttons at once, in every open window. F5 still copies.

**Why this priority**: the whole feature.

**Independent Test**: untick three boxes, check the bar in two windows, press one of the hidden keys,
tick the boxes again.

**Acceptance Scenarios**:

1. **Given** all twelve boxes are ticked, **When** the user unticks F5, **Then** the bar shows eleven
   buttons, without F5, in every window, at once.
2. **Given** F5 is unticked, **When** the user holds ⇧, **Then** the ⇧ layer shows no button at the F5
   position either.
3. **Given** F5 is unticked, **When** the user presses F5 in a panel, **Then** the copy starts as before.
4. **Given** only F3 is ticked, **When** the user tries to untick it, **Then** the box stays ticked.
5. **Given** some boxes are unticked, **When** the user exports the settings and imports them on another
   Mac, **Then** the bar there shows the same buttons.

---

### User Story 2 - Few buttons keep a normal size (Priority: P1)

A user leaves only F3 and F4 ticked. The two buttons are no wider than the maximum and stand at the left
edge of the bar; the rest of the bar is empty.

**Why this priority**: without it the feature makes the bar look broken.

**Independent Test**: tick one, two and all twelve buttons in a wide and a narrow window; compare the
button widths.

**Acceptance Scenarios**:

1. **Given** only F3 is ticked in a wide window, **Then** the F3 button is at most 140 points wide and
   starts at the left edge of the bar.
2. **Given** all twelve are ticked in a narrow window, **Then** the buttons share the bar evenly as today.
3. **Given** three buttons are ticked, **When** the user makes the window narrower until they would be
   narrower than the maximum, **Then** they shrink and share the bar evenly.

---

### User Story 3 - Get to the choice from the bar (Priority: P3)

A right click on the bar shows "Choose Buttons…" next to the item that hides the bar. It opens Settings →
General at the tick boxes.

**Why this priority**: a shortcut to the setting; Settings work without it.

**Acceptance Scenarios**:

1. **Given** the bar is shown, **When** the user right-clicks it and chooses "Choose Buttons…", **Then**
   Settings opens on General with the tick boxes visible.

---

### Edge Cases

- **A hidden key with no command**: nothing changes; it was an empty, disabled button before.
- **Keys whose command is unavailable** (for example F4 on a folder): a ticked button stays visible and
  disabled as today.
- **The bar is hidden**: the tick boxes can still be changed; the bar shows the choice when shown again.
- **The fn note** (F-keys acting as media keys): unchanged.
- **Labels in narrow buttons**: the short and long labels fit the button as today; the maximum only
  limits the width.
- **Right-to-left order or reordering**: the order is always F1 to F12; only gaps from hidden keys
  close up.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Settings → General MUST offer twelve tick boxes F1–F12 ("Buttons on the bar:"), all ticked by
  default, under "Show function key bar".
- **FR-002**: The bar MUST show only the ticked positions, in F-key order, in every layer (plain, ⇧, ⌃,
  ⌥, ⌘), and MUST follow a change at once in every window.
- **FR-003**: Hiding a button MUST NOT change what its key does.
- **FR-004**: The last ticked box MUST NOT be uncheckable.
- **FR-005**: Each button MUST be at most 140 points wide; the buttons MUST stand from the left edge of
  the bar, and narrower space MUST be shared evenly as today. The bar MUST leave a small margin at
  both ends.
- **FR-006**: The bar's context menu MUST offer "Choose Buttons…", which opens Settings → General.
- **FR-007**: The choice MUST be a user preference in the settings export (catalog of preferences, with
  the compatibility guards); a missing value MUST mean all twelve buttons.

### Key Entities

- **Visible function keys**: the set of F-key positions (1–12) the bar shows; never empty.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With one button left, it takes at most 140 points of the bar in any window width.
- **SC-002**: The layout rule (which positions, how wide, where) and the preference default have automated
  tests.

## Assumptions

- The maximum of 140 points suits the default font; it can be tuned during planning without changing the
  behavior.

## Out of Scope

- Reordering the buttons or moving them to the right or the middle.
- Hiding single layers (for example only ⇧F3).
- Turning keys off or changing their commands (Settings → Keyboard).
- A different choice per window.

## Deviations from the classic reference

- Classic two-panel managers show all their buttons or none; here the buttons can be chosen one by one.
