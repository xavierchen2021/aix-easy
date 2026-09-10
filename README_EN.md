<p align="center">
  <img src="Sources/Resources/AppIcon.png" width="128" height="128" alt="AIX Logo" />
</p>

<p align="center">
  <a href="README.md">简体中文</a> | <b>English</b>
</p>

# AIX Feature Overview

<p align="center">
  <img src="doc/CleanShot 2026-09-08 at 13.29.36@2x.png" alt="AIX Screenshot 1" height="380" />
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="doc/CleanShot 2026-09-08 at 08.15.43@2x.png" alt="AIX Screenshot 2" height="380" />
</p>

## 1. Floating Button System

### 1.1 Basic Features
| # | Feature | Description |
|---|---------|-------------|
| 1 | Multi-Button Support | Create and manage 1–10 independent floating buttons concurrently, each individually configurable |
| 2 | Size Adjustment | Adjust the size of each floating button independently (30–150 px) |
| 3 | Drag & Move | Drag floating buttons freely anywhere across the screen |
| 4 | Screen Edge Snapping | Automatically snap and align to screen edges within 20 px |
| 5 | Position Persistence | Retain each button's position and restore it across restarts |
| 6 | Always on Top | All floating button windows remain pinned above other windows |
| 7 | Visible Across Spaces | Floating buttons stay visible across all desktop spaces and in full-screen applications |
| 8 | Add New Button | Add a new floating button via the status bar menu item "Add" |
| 9 | Delete Button | Delete designated floating buttons when there is more than 1 button |
| 10 | Hide Individually | Hide individual floating buttons via the right-click context menu |
| 11 | Show / Hide All | Toggle the visibility of all floating buttons with a single click from the status bar menu |
| 12 | Rearrange Buttons | Reposition and rearrange all floating buttons to the bottom-right corner of the screen |

### 1.2 Appearance Customization
| # | Feature | Description |
|---|---------|-------------|
| 13 | Color Themes | 7 preset gradient color schemes: Ocean Blue, Forest Green, Sunset Orange, Pink Rose, Blue Purple, Pure Black, and Pure White |
| 14 | Per-Button Colors | Each floating button can override the global color scheme with an independent color |
| 15 | Button Shapes | Supports Circle and Capsule shapes, configurable globally or per-button |
| 16 | Display Modes | Supports "Icon Only" and "Text Only" display modes |
| 17 | Custom Icons | Assign distinct SF Symbols icons to individual floating buttons |
| 18 | SF Symbols Picker | Browse and select icons categorized into 14 themes (Common, Communication, Weather, Objects, Arrows, Devices, People, Nature, Transport, Fitness, Text, Health, etc.) |
| 19 | Radial Gradient Fill | Floating buttons are rendered with aesthetic radial gradient fills |

### 1.3 Animation Effects
| # | Feature | Description |
|---|---------|-------------|
| 20 | Hover Zoom | Gently scales up (1.1x) with an outer glow on mouse hover |
| 21 | Click Bounce Animation | Plays a spring scale animation (0.95 → 1.0) upon clicking |
| 22 | Ripple Animation | Emits an expanding water-ripple effect from the button center on click |
| 23 | Light Burst Animation | Triggers a transient burst-of-light effect on click |
| 24 | Glow Layer Effect | Soft outer glow effect surrounding the floating button |
| 25 | Edge Stroke Effect | Renders a matching silhouette edge stroke illumination on mouse hover |

### 1.4 Breathing Effect & Transparency
| # | Feature | Description |
|---|---------|-------------|
| 26 | Breathing Animation | Toggleable periodic breathing animation simulating gentle pulsating light |
| 27 | Breathing Speed Adjustment | Adjustable breathing animation speed (0.2x–3.0x) |
| 28 | Glow Intensity Adjustment | Adjustable outer glow intensity (0%–100%) |
| 29 | Note Transparency | Adjustable opacity for note content area (10%–100%) |
| 30 | Toolbar Transparency | Adjustable opacity for note top toolbar (10%–100%) |
| 31 | Group Transparency | Adjustable opacity for group management area (10%–100%) |
| 32 | Breathing Effect Transparency | Adjustable opacity for the breathing light effect itself (0%–100%) |

### 1.5 Action Binding
| # | Feature | Description |
|---|---------|-------------|
| 33 | Action Types | Each button can bind to 7 click actions: None / Open Note / Show Completed / Show Clipboard / Show Favorites / Window Control / Plugin |
| 34 | Individual Settings Panel | Right-click any floating button to open its dedicated customization window |

### 1.6 Button Grouping
| # | Feature | Description |
|---|---------|-------------|
| 35 | Create Groups | Group multiple floating buttons into named clusters |
| 36 | Linked Dragging | Dragging any button within a group moves all other buttons in that group together |
| 37 | Group Layouts | Supports horizontal and vertical alignment orientations |
| 38 | Group Member Management | Add/remove buttons from groups or migrate them between groups |
| 39 | Auto-Arrangement | Automatically re-aligns positions of all buttons within the group upon applying settings |

---

## 2. Notes System

### 2.1 Note Operations
| # | Feature | Description |
|---|---------|-------------|
| 40 | Quick Note Creation | Type into the input box and press Enter to instantly create a note |
| 41 | Shift+Enter Line Break | Press Shift+Enter in the input box to insert a newline without submitting |
| 42 | Note Editing | Supports both inline editing and detached large-window modal editing |
| 43 | Large Window Editor | Dedicated floating window for editing notes with an expanded workspace |
| 44 | Note Deletion (Soft Delete) | Deleting a note moves it to the Trash instead of permanent erasure |
| 45 | Mark as Completed | Mark notes as completed to keep work organized |
| 46 | Save to Knowledge Base | Archive regular notes into Knowledge Base entries with destination group selection |
| 47 | Move Across Groups | Relocate notes seamlessly between different groups |
| 48 | Random Color Tagging | Automatically assign random color accents to individual notes |
| 49 | Auto-Edit Empty Note | Newly created empty notes automatically enter edit mode |
| 50 | Copy Note Content | Copy note text to system clipboard via right-click context menu |

### 2.2 Note Views
| # | Feature | Description |
|---|---------|-------------|
| 51 | Multi-View Modes | 6 viewing modes for note lists: All / Completed / Clipboard / Knowledge Base / Favorites / Trash |
| 52 | Search & Filter | Keyword search and real-time filtering within the active view |
| 53 | Hover Quick Actions | Hover over any note row to reveal quick action buttons (Edit, Complete, Delete, etc.) |
| 54 | Context Menu | Right-click notes for rich actions: Edit, Complete, Save to Knowledge Base, Copy, Move, Delete, etc. |
| 55 | Toast Notifications | Brief visual feedback popups on completed actions |

### 2.3 Trash
| # | Feature | Description |
|---|---------|-------------|
| 56 | View Deleted Notes | Browse all soft-deleted notes in the Trash view |
| 57 | Restore Notes | Restore notes from Trash back to their original groups |
| 58 | Permanently Delete | Permanently erase individual notes from Trash |
| 59 | Empty Trash | One-click permanent deletion of all notes in Trash |

### 2.4 Note Window
| # | Feature | Description |
|---|---------|-------------|
| 60 | Floating Panel | Built with `NSPanel` for non-activating panel interactions |
| 61 | Configurable Window Height | Customize the height of the note popup window in settings |
| 62 | Auto-Widen on Search | Window width automatically expands when search bar is opened |
| 63 | Frosted Glass Effect | Native macOS blur/vibrancy material implemented with `NSVisualEffectView` |

---

## 3. Note Group Management

| # | Feature | Description |
|---|---------|-------------|
| 64 | Create Note Group | Create custom groups with custom names and icons |
| 65 | Edit Group | Rename groups and change group icons |
| 66 | Delete Group | Remove non-default groups (default groups are protected) |
| 67 | Drag-and-Drop Sorting | Drag to reorder the sequence of groups |
| 68 | Knowledge Base Flag | Mark groups as Knowledge Base type for isolated management |
| 69 | Default Note Group | Configure the default destination group for newly created notes |
| 70 | Default Knowledge Group | Configure the default target group for knowledge entries |
| 71 | Group Display Modes | Switch between tabbed, dropdown, and other group presentation styles |
| 72 | Group Icon Selection | Assign independent SF Symbols icons to each group |
| 73 | Integrated Group Settings | Access and configure group settings within the group manager popup |

---

## 4. Clipboard Management

| # | Feature | Description |
|---|---------|-------------|
| 74 | Clipboard Monitoring | Polls system pasteboard every second to automatically capture copied content |
| 75 | Multi-Type Support | Supports text, images, and file paths in clipboard history |
| 76 | History Deduplication | Identical items are automatically deduplicated |
| 77 | Configurable History Limit | Set clipboard history capacity from 1 to 100 items |
| 78 | Copy Sound Effect | Optional sound notification played on new copy events |
| 79 | Clipboard Preview | Preview clipboard history in the dedicated Clipboard view of the note window |
| 80 | Image Preview | View thumbnail previews for captured clipboard images directly |
| 81 | Re-Copy to Clipboard | One-click copy of any historical item back to system clipboard |
| 82 | Save as Note | Convert copied clipboard text items into notes with one click |
| 83 | JSON File Persistence | Persists clipboard history reliably to local JSON storage |

---

## 5. Favorites (Quick Access Files)

| # | Feature | Description |
|---|---------|-------------|
| 84 | Drag-and-Drop Pinning | Drag files or folders into the favorites list to bookmark them |
| 85 | Path Deduplication | Prevents duplicate entries for identical file paths |
| 86 | One-Click Open | Click any favorited item to open it with the default system application |
| 87 | Reveal in Finder | Locate files in Finder directly via right-click menu |
| 88 | Remove from Favorites | Remove items via hover button or right-click context menu |
| 89 | Smart File Icons | Automatically matches file type icons based on extensions (supporting 20+ types including PDF, Word, Excel, PPT, Code, Images, Videos, Audio, Archives, etc.) |
| 90 | SQLite Persistence | Stores favorites list securely in SQLite database |

---

## 6. Window Control

| # | Feature | Description |
|---|---------|-------------|
| 91 | Window Selection Overlay | Select any app window via a full-screen semi-transparent overlay to bind it to a floating button |
| 92 | Toggle Window Visibility | Click the floating button to toggle the bound window between shown and hidden |
| 93 | Multi-Strategy Window Resolution | Accurately locates target windows using window IDs, coordinates, and titles |
| 94 | Bring to Front & Focus | Activates and focuses the target application window upon showing |
| 95 | Minimize & Restore | Minimizes the target window when hidden, restores when toggled back |
| 96 | Rebind Window | Clear and re-select target windows via right-click menu |
| 97 | Accessibility API Integration | Interacts directly with windows via macOS Accessibility (AXUIElement) APIs |
| 98 | Multi-Display Support | Window selection overlay spans all connected monitors |

---

## 7. Smart Break Reminder

### 7.1 Activity Detection
| # | Feature | Description |
|---|---------|-------------|
| 99 | Smart Activity Detection | Detects active user presence via keyboard, mouse, and scroll wheel events |
| 100 | Three-State Decision Logic | Active input → Working; Inactive + Audio playing → Watching video / listening to music (timer paused); Inactive + Silent → Idle |
| 101 | System Audio Detection | Detects active system audio playback using CoreAudio |
| 102 | Auto-Pause on Video | Automatically pauses the work timer when full-screen video playback is detected |
| 103 | Lock Screen Detection | Automatically pauses timers when screen is locked |
| 104 | CGEventTap Monitoring | Tracks global keyboard, mouse, and scroll events with event taps |
| 105 | Accessibility Permission Check | Automatically validates whether accessibility permissions have been granted |
| 106 | Screen Lock & Sleep Listening | Observes `screenIsLocked` and `screensDidSleep` system notifications |

### 7.2 Reminder Mechanism
| # | Feature | Description |
|---|---------|-------------|
| 107 | Work Duration Setting | Configurable continuous work threshold (25–120 minutes) |
| 108 | Rest Duration Setting | Configurable rest duration after reminder triggers (5–15 minutes) |
| 109 | Idle Threshold Setting | Configurable inactivity threshold to recognize idle state (60–180 seconds) |
| 110 | Rest Recognition Threshold | Inactivity exceeding this duration is recognized as an accomplished break, resetting the timer |
| 111 | Full-Screen Break Overlay | Semi-transparent full-screen mask prompts user when break time arrives |
| 112 | Three-Stage Break Workflow | Work Complete → Rest Countdown → Rest Complete, each stage featuring distinct prompts and controls |
| 113 | Rest Countdown Display | Displays live remaining rest time directly on the overlay |
| 114 | Keyboard & Scroll Interception | Intercepts keyboard and scroll inputs while the break overlay is active |
| 115 | Custom Reminder Message | Personalize text messages shown during breaks |
| 116 | Alert Sound Selection | 14 built-in system alert sounds available to choose from |
| 117 | Rest End Sound | Separate selectable notification sound when the break finishes |
| 118 | Test Reminder | Preview and test the reminder overlay with one click |
| 119 | Across-Restart State Recovery | Records exit timestamp and resumes timing seamlessly across brief restarts |
| 120 | Reminder Logging | Logs timestamps and statuses of all reminder events |
| 121 | Smart Settings Reset | Closing settings window only resets timers if time-related parameters were actually modified |

### 7.3 Menu Bar Timer
| # | Feature | Description |
|---|---------|-------------|
| 122 | Menu Bar Work Timer | Displays accumulated active working time in the macOS menu bar |
| 123 | Menu Bar Rest Countdown | Shows remaining break time in the menu bar during rest periods |
| 124 | Permission Status Indicator | Displays the real-time status of accessibility permissions in the menu bar |

---

## 8. App Auto-Hide

| # | Feature | Description |
|---|---------|-------------|
| 125 | App Auto-Hide | Automatically hides inactive background applications after a defined duration |
| 126 | Configurable Timeout | Set idle timeout before applications are hidden (20–60 minutes) |
| 127 | Excluded Apps List | Specify applications that should never be auto-hidden |
| 128 | App Picker Modal | Popup window to easily check and exclude active running applications |
| 129 | Automatic System Process Exclusion | System processes like Finder, Dock, and Control Center are automatically whitelisted |

---

## 9. Browser Selection & URL Scheme

| # | Feature | Description |
|---|---------|-------------|
| 130 | URL Scheme Support | Handles links launched via the custom `aix://` URL scheme |
| 131 | Automatic Browser Detection | Scans the system for all installed browsers registered to handle HTTP/HTTPS protocols |
| 132 | Browser Picker Modal | Pops up an intuitive selection window to choose the desired browser when opening a link |
| 133 | Default Browser Setting Shortcut | Quick access from general settings to system default browser configuration |
| 134 | Direct Launch with Preferred Browser | Set a preferred default browser in AIX to launch links directly without prompt |

---

> Total of **134** features across **9** functional modules.
