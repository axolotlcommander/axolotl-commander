# Research: Thumbnails View

## R1. Where the view lives

- **Decision**: A third view next to the table and the Brief grid: `ThumbnailGridView`, an
  `NSCollectionView` with a vertical flow layout, in its own scroll view inside the same `lists` container
  as the other two. `PanelViewMode` gets a `thumbnails` case; `listView` and the hide/show code in
  `viewModeChanged()` handle three views.
- The Brief grid's mouse code (press rules, rubber band, drag & drop source and target, right button) is
  moved into a shared base class `PanelGridView` that both grids subclass. Each subclass gives its
  geometry (`items(in:)`) and its cell's name zone; the Brief behavior stays the same.
- **Rationale**: Spec 024's rules then apply to the new view without a copy (FR-021), and Brief keeps
  working (FR-024). A collection view recycles its cells, so 100 000 items cost only the visible cells.
- **Alternatives considered**: One grid that switches its layout and cells by mode: fewer types, but the
  reload bookkeeping, item sizes and scroll direction differ enough that every method would branch.

## R2. Grid geometry and keyboard movement in the core

- **Decision**: A pure `PanelGrid` value in `CommanderCore` describes the arrangement:
  `.list(pageRows)` (Detailed), `.columns(rowsPerColumn, visibleColumns)` (Brief, filled top to bottom),
  `.rows(columnsPerRow, visibleRows)` (Thumbnails, filled left to right). `PanelGrid.target(from:count:key:)`
  returns the new cursor index for ↑ ↓ ← → Home End Page Up Page Down (FR-019). `handleMovement` in
  `PanelViewController` asks the current view for its `PanelGrid` and uses it for all three views, so the
  ⇧ marking code keeps one path (FR-020).
- `GridGeometry` (origin, cell size, horizontal and vertical stride, items per line, orientation) maps a
  rectangle to the covered indices by arithmetic (one range per line touched), for both grids' rubber
  band; Brief's current `items(in:)` arithmetic moves there.
- **Rationale**: Constitution IV: the movement and the rectangle rules get unit tests (SC-005) instead of
  living in view code.

## R3. Making the previews

- **Decision**: `QLThumbnailGenerator` (QuickLookThumbnailing) with a request per cell: the file URL, the
  square size in points, the window's backing scale, representation types `.icon` and `.thumbnail`,
  delivered through `generateRepresentations(for:update:)`. The per-file icon arrives first (custom folder
  icons, app icons) and is replaced by the thumbnail when the system can make one (FR-007, FR-010). Errors
  and missing thumbnails are ignored (FR-012).
- Before any representation arrives, the cell shows the type icon from a cache by type, sized to the cell
  (NSImage icons have every resolution, so no extra work).
- The generator manages its own work in the background; the panel never waits on it (FR-010). Requests
  are cancelled with `cancel(_:)` when their cell leaves the wanted area (FR-011).
- **Rationale**: The system knows every type with a Quick Look extension (images, PDF, video, Office, text)
  and makes huge images and long videos without the app decoding them (edge cases).
- **Alternatives considered**: `NSWorkspace.icon(forFile:)` plus ImageIO for images only: misses PDF, video
  and documents, and decodes large images in the app.

## R4. Which items get previews

- **Decision**: A core rule `ThumbnailPolicy.allowsPreviews(inArchive:onServer:isNetwork:)` per panel,
  and per item: the URL is a file URL that is not a path inside an archive (`ArchivePath.split` finds no
  archive). Branch view and search results pass when their items are on disk. Everything else shows type
  icons only and no request is made (FR-015).
- Same panel flags as the Quick View panel's `QuickViewSubject` uses, so both features agree.

## R5. Scheduling and limits

- **Decision**: A core `ThumbnailQueue` keeps the wanted keys (visible cells plus one screen of margin
  ahead and behind, in that order: visible first), the running requests and a limit of 8 running at once.
  On every scroll, resize, size change or reload the view gives the new wanted list; the queue answers
  which requests to cancel and which to start (FR-011). The AppKit side (`ThumbnailLoader`) only carries
  out these answers with the generator and hands finished images to the cache and the visible cell.
- **Rationale**: The decisions are pure and testable; the loader stays small.

## R6. Memory cache

- **Decision**: A core `ThumbnailCache<Value>` generic LRU keyed by `ThumbnailKey(path, modificationDate,
  size)` with a cost limit (cost = pixel width × height × 4 bytes) of 256 MB; inserting over the limit
  drops the least recently used entries (FR-013, SC-003). The AppKit side stores `NSImage` values. Nothing
  is ever written to disk (FR-014). The key's date makes a changed file miss the cache after a refresh.
- **Alternatives considered**: `NSCache`: evicts in an unspecified order and at unspecified times, so the
  limit and order cannot be tested.

## R7. Size setting and steps

- **Decision**: `ThumbnailSize` enum (small 64, medium 128, large 256) in the core with `larger` /
  `smaller`, stored under `panel.thumbnailSize` (default medium) with a `PreferenceSpec`, a picker in
  Settings → General → Panels (FR-016). Two new commands, View → Larger Thumbnails (⌘+, ⌘=) and View →
  Smaller Thumbnails (⌘−), in the panel scope and enabled only when the active panel shows thumbnails
  (FR-017); the viewer and the file comparison keep their own ⌘+ / ⌘− in their scopes. `ThumbnailGridView`
  turns ⌘ + scroll wheel (accumulated delta) and the pinch gesture (accumulated magnification, a step per
  0.25) into the same steps. Panels observe the setting (the existing `UserDefaults.didChangeNotification`
  observer) and re-layout every Thumbnails view, keeping the cursor visible (FR-018).

## R8. Cell layout and drawing

- **Decision**: `ThumbnailCellView`: an image view (proportional scaling up or down, centered) in a
  square of the chosen size, and a label below on at most two lines, centered, cutting the end of the
  second line with "…" (`maximumNumberOfLines = 2`, `truncatesLastVisibleLine`), the full name as tooltip
  (FR-006). Cell width = size + 16 points, height = size + two text lines + 10 points; line spacing 4,
  item spacing 4. Implementation note: a small layout of our own (`ThumbnailGridLayout`) replaces the flow
  layout: every row has the same column positions (the free width spread evenly over the columns, also in
  a short last row), only the rows in the asked rectangle are built, and `GridGeometry` comes straight
  from it. The cursor and marked drawing reuse
  the Brief colors: the cursor cell gets the active or inactive cursor background/frame, marked cells the
  marked name color and font plus a light marked background (FR-008).
- Name zone for clicks and drags (FR-022): the image's drawn rectangle (aspect-fit inside the square, at
  least 4 points thick) and the label's text lines; the rest of the cell is empty space.
- Pictures with extreme shapes keep at least a 1-point visible edge (edge cases).

## R9. Layout persistence

- **Decision**: `PanelViewMode.thumbnails` is saved in `WindowLayout` like the others (FR-003). Decoding a
  mode an older build does not know would make the whole layout fail, so the mode is decoded through a
  tolerant wrapper that falls back to `detailed`; this keeps a layout written by a newer build readable.

## R10. Testing

- Core unit tests: `PanelGrid.target` for all three arrangements (edges, short last row, page moves);
  `GridGeometry` rectangles in both orientations (gaps, beyond the last item); `ThumbnailSize` steps and
  the setting; `ThumbnailCache` (limit, LRU order, key with date and size); `ThumbnailQueue` (limit,
  cancel when leaving, visible first); `ThumbnailPolicy`; `WindowLayout` round trip with the new mode and
  the unknown-mode fallback.
- GUI check on the test copy in a scratch folder (generated images of several shapes, a PDF, a text file,
  a folder, a 2 000-file folder): see [quickstart.md](quickstart.md).
