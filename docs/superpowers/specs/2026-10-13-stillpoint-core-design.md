# Stillpoint — Sub-project 1: Core Mac App (Design Spec)

- **Date:** 2026-10-13
- **Status:** Draft, awaiting review
- **License:** GPL-3.0
- **Repo:** `~/Developer/Stillpoint`

## 1. Purpose and intent

Stillpoint is a free, open-source task manager with **Things 3's feature set and workflow**, for macOS first, then iPhone, then iPad. It exists because Things 3 costs about ₹10,000 across Mac, iPhone and iPad. Sync is optional: each user connects **their own Supabase project**.

**Ground rules:**
- **Feature parity with Things 3, no more and no less.** If Things has it, Stillpoint gets it in some phase. If Things doesn't have it (priorities, attachments, start times other than reminders), Stillpoint doesn't either.
- **Original identity.** Stillpoint has its own name, icon, glyph mapping, palette and code. No Cultured Code assets, images, theme files or code are copied. Behaviour, keyboard shortcuts and workflow may match; visuals must not imitate.
- **Platforms:** macOS 26+, then iOS 26+ and iPadOS 26+. The Liquid Glass design language is used throughout.

**Success criteria for this sub-project:** Someone who uses Things 3 on the Mac every day can switch to Stillpoint for local, single-device use and not miss anything, except the items listed in §2.2, which arrive in later phases.

## 2. Scope

### 2.1 In scope (sub-project 1)

- Data model, storage, migrations and backups. The model is sync-ready (§4.4).
- Item types: to-dos, projects, headings, checklist items, areas, tags (nested, with keyboard shortcuts).
- Built-in lists: Inbox, Today (with This Evening), Upcoming (without calendar events), Anytime, Someday, Logbook, Trash, Deadlines, All Projects, Later Projects.
- Scheduling: When (Today, This Evening, a specific day, Someday, clear), Deadline, Evening. The reminder time is stored and editable, but notifications arrive in phase 3.
- Projects: notes, progress pie, headings, archiving headings, "later items" toggle, converting a heading or a to-do into a project, completing a project that still has open to-dos (prompt to complete or cancel them).
- Areas: contain projects and loose to-dos, can be tagged, collapse in the sidebar.
- Expanded to-do card, edited in place: title, notes (plain text in this phase), checklist, tags, When, Deadline.
- Quick Find: search titles and notes, and jump to lists, projects, areas and tags.
- Tag filter bar on lists.
- Multi-select, bulk actions, drag and drop, context menus, full keyboard control, undo/redo.
- Logbook policy (immediately / daily / manually) and Log Completed.
- Trash, Put Back, Empty Trash.
- Multiple main windows, with each window's state restored on relaunch.
- Settings: General (Logbook policy, group Today by project, accent colour), Appearance (Light / Dark / Black / Automatic, text size), Backups.
- Liquid Glass chrome, accessibility, and VoiceOver.

### 2.2 Out of scope (later phases)

| Phase | Adds |
|---|---|
| 2 Capture | Global Quick Entry panel, Quick Entry with Autofill (helper app), natural-language dates, Share extension, Markdown notes with find/replace in text |
| 3 Time | Repeating items (fixed schedule and after-completion; pause, stop, next copy, exceptions), reminder notifications, calendar events in Today and Upcoming, Repeating list, Reminders Inbox |
| 4 Automation | `stillpoint:///` URL scheme (add, update, show, search, json, auth token), App Intents and Shortcuts, Apple Intelligence (Siri) Reminders assistant schema, widgets and Control Center controls, AppleScript, Handoff, Spotlight |
| 5 Sync | Bring-your-own Supabase: SQL migrations, row-level security, auth, push/pull of the change log, realtime |
| 6 Onboarding | Tutorial project, imports (Reminders, Todoist, Things via its URL scheme or AppleScript export), Mail-to-Stillpoint (needs a server, so evaluated in phase 5), printing |
| 7–8 | iPhone app, then iPad app, reusing `StillpointModel` and `StillpointUI` |

**Deliberately excluded:**
- Contacts and delegation. This is legacy Things 2 data that Things 3 no longer exposes in its interface.
- Things' internal-only experimental AI features. They aren't shipped to users.

## 3. Architecture

```
Stillpoint/
├── project.yml                  # XcodeGen spec; .xcodeproj is generated, not committed
├── App/                         # macOS app target (SwiftUI + AppKit)
│   ├── StillpointApp.swift
│   ├── Windows/  Sidebar/  TaskList/  Popovers/  Settings/  Commands/
├── Packages/
│   ├── StillpointModel/         # GRDB, records, queries, change log, undo; no UI imports
│   └── StillpointUI/            # design tokens and reusable SwiftUI views
├── supabase/                    # (phase 5)
└── docs/
```

- **Language:** Swift 6.4, Swift 6 language mode (strict concurrency).
- **Dependencies:** GRDB.swift 7.x (SQLite), swift-snapshot-testing (tests only). Nothing else.
- **Build:** the XcodeGen `project.yml` generates the Xcode project, so contributors don't get `.pbxproj` merge conflicts.

**Boundaries:**
- `StillpointModel` exposes a `Store` actor holding the database writer, plus:
  - read-only `ListQuery` values: `.inbox`, `.today`, `.project(id)` and so on;
  - observation streams for those queries;
  - command functions: `createTodo`, `complete`, `schedule`, `move`, `reorder`, and others.

  Every write goes through a command, which validates the rules (§4.3), writes rows and change-log entries in one transaction, and returns an `UndoStep`.
- `StillpointUI` depends on nothing but SwiftUI. It holds design tokens and leaf views: checkbox, tag pill, progress pie, date badge, sidebar row.
- **The app target** composes the two. Its task list is an `NSTableView` subclass hosted in SwiftUI through `NSViewRepresentable`, with cell content rendered by SwiftUI views from `StillpointUI` via `NSHostingView`. Everything else (window, sidebar, toolbar, popovers, settings) is SwiftUI.

## 4. Data model

### 4.1 Tables

Every table except `change` and the join tables has `id TEXT PRIMARY KEY` (a UUIDv7 string). Every synced table, join tables included, has `ownerID TEXT` (null until sync is set up), `createdAt REAL`, `modifiedAt REAL` and `deletedAt REAL` (sync tombstone).

| Table | Columns (beyond the common ones) |
|---|---|
| `item` | `kind` INT (0 to-do, 1 project, 2 heading); `title` TEXT; `notes` TEXT; `status` INT (0 open, 2 canceled, 3 completed); `stopDate` REAL; `bucket` INT (0 inbox, 1 anytime, 2 someday); `startDay` INT (YYYYMMDD) nullable; `isEvening` BOOL; `reminderTime` INT (minutes after midnight) nullable; `deadlineDay` INT nullable; `projectID`; `headingID`; `areaID`; `sortKey` TEXT; `todaySortKey` TEXT; `trashedAt` REAL; repeat fields for phase 3: `repeatRule` BLOB, `repeatTemplateID`, `repeatPaused` BOOL, `repeatNextDay` INT |
| `area` | `title`, `sortKey`, `isCollapsed` |
| `tag` | `title`, `parentID`, `shortcut` (single character), `sortKey` |
| `item_tag` / `area_tag` | `itemID`/`areaID`, `tagID` (composite primary key; still has tombstones for sync) |
| `checklist_item` | `itemID`, `title`, `isDone`, `sortKey` |
| `settings` | single row: `logPolicy` INT (0 immediately, 1 daily, 2 manually), `manualLogCutoff` REAL, `groupTodayByProject` BOOL, `appearance` INT, `textSize` INT, `accentColor` TEXT nullable (null = system accent) |
| `change` | `seq` INTEGER PK, `entity` TEXT, `entityID` TEXT, `fields` TEXT (JSON array of column names), `hlc` TEXT (hybrid logical clock), `deviceID` TEXT, `pushedAt` REAL nullable |

### 4.2 List definitions

`today` comes from an injected clock and calendar. "Visible" means not trashed, no tombstone, and not logged. "Logged" means `status ≠ open` and `stopDate` is before the log cutoff for the current Logbook policy.

| List | Rule | Grouping and order |
|---|---|---|
| Inbox | to-do, `bucket = inbox`, no project or area | `sortKey` |
| Today | to-do or project, `bucket = anytime`, `startDay ≤ today`, *or* `deadlineDay ≤ today` | Main section, then This Evening (`isEvening`). Optionally grouped by project (setting). Order by `todaySortKey` |
| Upcoming | `startDay > today` or `deadlineDay > today` | Each of the next 7 days, then the rest of the month, then by month |
| Anytime | `bucket = anytime`, (`startDay` null or `≤ today`), not inside a Someday project | By area, then project. Today items are marked |
| Someday | `bucket = someday`, `startDay` null | By area, then project |
| Deadlines | `deadlineDay` not null, open | By deadline day ascending |
| Logbook | logged | Grouped by `stopDate` day, newest first |
| Trash | `trashedAt` not null | By `trashedAt`, newest first |
| Project | `projectID = X` | Headings in `sortKey` order. Items with a future or Someday start are hidden behind "Show N later items" |
| Area | `areaID = X` | Loose to-dos, then projects. Later projects hidden behind a toggle |
| Tag filter | any list ∩ items tagged with the tag or its descendants | Same as the base list |

When a to-do's start day arrives it moves into Today. Overdue start days stay in Today. Upcoming items are scheduled to-dos and projects.

### 4.3 Rules enforced in commands

1. A heading's `projectID` is non-null, and it has no `headingID` or `areaID`.
2. A project has no `projectID` or `headingID`. Projects can't be nested.
3. A to-do with a `headingID` has `projectID` equal to that heading's project.
4. A to-do inside a project has `areaID = null`; it inherits the project's area.
5. Setting `startDay` forces `bucket = anytime`. Choosing Someday clears `startDay` and `isEvening`.
6. `isEvening` requires a `startDay`. A minimum of today isn't enforced: yesterday's evening items roll into today and must stay editable. A `reminderTime` also requires a `startDay`.
7. Completing a project with open children asks the user to complete or cancel them. The command takes the user's choice as a parameter.
8. Checklist items belong only to to-dos.

Breaking a rule is a programmer error: `assertionFailure` in debug builds; in release builds the error is logged and the transaction rolled back.

### 4.4 Sync-ready properties

These are built in now so phase 5 needs no schema migration:
- **UUIDv7 IDs** are globally unique and sort by creation time.
- **Days are `YYYYMMDD` integers**, so they don't depend on time zone.
- **Fractional `sortKey` strings** (base-62, generated between two neighbours) mean a reorder writes exactly one row.
- **Every write appends `change` rows** listing the changed fields and a hybrid logical clock timestamp. Phase 5 pushes unpushed rows and merges per field, last writer wins.
- **Deletion is a tombstone** (`deletedAt`). A purge after sync acknowledgement is phase 5's job.

## 5. UI and visual language

### 5.1 Layout

- **Main window:** a `NavigationSplitView`.
  - **Sidebar (glass):** Quick Find field; fixed lists; areas with nested projects and progress pies; a bottom bar with "+ New List" (to-do list, project or area) and Settings.
  - **Detail:**
    - List header: large title with icon. Projects also show notes, deadline and progress.
    - Rows, then section and heading rows.
    - A floating glass toolbar at the bottom: New To-Do, New Heading (in projects), When, Move, Quick Find, More.
- **Expanded to-do:** double-click or Return opens the row into a card in place, pushing the rows below it down. It shows the title, notes, checklist, and a detail row of tags, When and Deadline buttons. Esc or clicking outside collapses it.
- **Popovers (glass):** When (Today, This Evening, a month calendar, Someday, reminder time, Clear), Deadline (calendar), Move (searchable list of lists, projects, areas and headings), Tags (searchable, multi-select, create new).

### 5.2 Visual identity (original)

- **Accent colour:** the system accent colour by default, overridable in Settings.
- **List icons** (SF Symbols):

  | List | Symbol | Colour |
  |---|---|---|
  | Inbox | `tray` | blue |
  | Today | `sun.max.fill` | amber |
  | This Evening | `moon.fill` | indigo |
  | Upcoming | `calendar` | red |
  | Anytime | `square.stack` | teal |
  | Someday | `archivebox` | sand |
  | Logbook | `checkmark.seal` | green |
  | Trash | `trash` | gray |
  | Deadlines | `flag` | crimson |

- **Neutrals:** a warm gray ramp. Text uses primary, secondary and tertiary opacities of a warm near-black or near-white.
- **Type:** SF Pro through system fonts. **A single text-size setting** (S / M / L / XL → scale 0.9 / 1.0 / 1.15 / 1.3) multiplies all spacing and font tokens. Tokens live in `StillpointUI/Tokens.swift`.
- **Appearance:** Light, Dark, Black (true-dark backgrounds), Automatic.
- **Glass:** toolbar, sidebar, popovers, the floating toolbar, and later the Quick Entry panel. Rows and cards use solid backgrounds for readability. With Reduce Transparency on, solid fallbacks are used everywhere.

### 5.3 Motion

- SwiftUI spring animations throughout.
- The checkbox completion animation is drawn in code (shape trim plus fill).
- Completed items stay visible, struck through and faded, until logged.
- The card expands and collapses with a spring. Rows animate on reorder and insertion.
- Reduce Motion replaces springs with fades.

## 6. Interactions

### 6.1 Keyboard

Default bindings, to match Things 3:

| Action | Keys |
|---|---|
| New to-do / new to-do below the selection | ⌘N / Space |
| New project / new heading | ⌥⌘N / ⇧⌘N |
| Open / close an item | Return / Esc |
| Complete / cancel | ⌘K / ⌥⌘K |
| Today / This Evening / Someday / clear When | ⌘T / ⌘E / ⌘O / ⌘R |
| When / Deadline / Move / Tags popover | ⇧⌘W / ⇧⌘D / ⇧⌘M / ⇧⌘T |
| Start date +1 / −1 day | ⌃] / ⌃[ |
| Move up / down | ⌘↑ / ⌘↓ |
| Go to list | ⌘1 … ⌘7 |
| Quick Find | type anywhere, or ⌘F |
| Duplicate / delete | ⌘D / ⌫ |
| Undo / redo | ⌘Z / ⇧⌘Z |
| Apply a tag | ⌃ + the tag's shortcut |
| Toggle sidebar | ⌘/ |

**Required check:** the first keyboard task in the implementation plan compares each binding with Things 3.24's *Help → Keyboard Shortcuts* sheet and corrects this table before shortcuts are coded.

### 6.2 Selection and bulk actions

Click, ⇧-click and ⌘-click; ⇧↑/↓ and ↑/↓. All commands accept the whole selection. Bulk edits of more than 50 items ask for confirmation.

### 6.3 Drag and drop

- Reorder within a list and across headings.
- Drop onto a sidebar list, project or area (Today schedules for today; Someday moves to Someday). Collapsed areas spring open on hover.
- Drag several items at once.
- Drop text, URLs or files in from other apps to create to-dos. URLs and file paths go into the notes.
- Drag out as plain text, or as `stillpoint:///show?id=` links.
- Reorder areas and projects in the sidebar.

### 6.4 Undo

Each command returns an `UndoStep`, the inverse set of field writes. It's registered with the window's `UndoManager` under a localized action name. Bulk actions and drags count as one step each.

### 6.5 Context menus

Row and sidebar context menus mirror the Items menu.

## 7. Error handling and data safety

- **Backups:** at launch and every 24 hours, via the SQLite online backup API, to `~/Library/Application Support/Stillpoint/Backups/`, keeping 10. Settings → Backups has "Restore…".
- **Migrations:** back up first, run each migration in a transaction, and refuse to open a half-migrated database. On failure, restore and alert.
- **Integrity:** `PRAGMA quick_check` at launch. If it fails, move the file aside and offer the newest backup.
- **Typing:** text fields save on a 300 ms debounce and when focus is lost.
- **Write failures** (for example, a full disk) show a non-blocking banner and keep the in-memory edit for retry.
- **Logging:** `os.Logger` with categories `db`, `ui` and `commands`. Help → Copy Diagnostics copies the version, OS, database stats and recent logs.

## 8. Testing

- **`StillpointModel`** (Swift Testing, in-memory GRDB):
  - every list rule in §4.2, including around midnight, DST changes and time-zone changes, using an injected clock and calendar;
  - every rule in §4.3;
  - sort-key generation: 10,000 random reorders with no collisions;
  - migrations from each schema version fixture;
  - undo/redo round trips;
  - change-log contents for each command.
- **`StillpointUI`:** snapshot tests in Light, Dark and Black, at all four text sizes.
- **App:** XCUITest for create, complete, schedule, move, drag, multi-select, undo, and keyboard-only operation.
- **Performance:** a 10,000-item fixture opens any list in under 100 ms (measured in tests), and scrolling holds 120 fps (checked manually with Instruments).
- **CI:** a GitHub Actions macOS runner generates the project, builds, and runs all tests on every pull request.

## 9. Open items deferred to later phases

- The Supabase schema, auth flow and conflict-resolution details (phase 5; the local model is ready for them).
- Mail-to-Stillpoint, which needs a server (evaluated in phase 5).
- Brand icon artwork (needed before the first public release; a placeholder SF Symbol icon until then).
