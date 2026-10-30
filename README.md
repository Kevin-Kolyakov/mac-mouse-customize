# mac-mouse-customize

**Mouse Customize** is a small native macOS menu bar app, written in Swift and SwiftUI, for your mouse:

- **Button remapping.** Middle, back, forward and any other extra button can be set to Back, Forward, Middle Click, Mission Control, App Exposé, Show Desktop, Previous/Next Space, a keyboard shortcut you record, or Do Nothing. Left and right click are never touched.
- **Scroll wheel.** Reverse the direction (independently of the trackpad), change the speed, and turn on smooth scrolling with an adjustable glide.
- **Thumb wheel.** A side horizontal wheel, like the one on a Logitech MX Master, gets its own reverse, speed and smoothing settings.

Settings are saved in `UserDefaults` and take effect immediately.

## Permissions: Accessibility only

The app uses **one `CGEventTap`** that only listens for extra-button and scroll-wheel events. Modifying those events requires the **Accessibility** permission. It needs nothing else:

- no Input Monitoring (the tap never sees keyboard events),
- no drivers, kernel or system extensions,
- no helper tools or privileged daemons,
- no network access.

On first launch the app explains why it needs Accessibility access and asks **once**. If you skip it, the menu bar panel shows a banner with an **Open Accessibility Settings** button. The app checks for access every 2 seconds, so it starts working as soon as you flip the switch, with no relaunch needed.

## Requirements

- macOS 13 Ventura or later
- Xcode 16 or later (the project uses Xcode 16's folder-synced project format)

## Build and run in Xcode

1. Open `MouseCustomize.xcodeproj`.
2. Select the **MouseCustomize** target → **Signing & Capabilities**:
   - **Team:** pick your Apple ID's *Personal Team*. A free account works; add one under Xcode → Settings → Accounts.
   - **Signing Certificate:** *Development*.

   This matters. macOS ties the Accessibility grant to the app's code signature. With *Sign to Run Locally* (ad-hoc), the signature changes on every build and macOS silently forgets the permission. With your team's certificate it stays put.
   If Xcode says the bundle identifier is taken, change `io.github.kevin-kolyakov.MouseCustomize` to something unique.
3. Press **⌘R**. There's no Dock icon; a mouse icon appears in the menu bar.
4. Read the explanation and click **Continue**. In the system prompt, click **Open System Settings**, then turn on **MouseCustomize** under *Privacy & Security → Accessibility*.
5. Click the menu bar icon to configure buttons, the scroll wheel and the thumb wheel. The icon fills in when the app is active.

### Install it for everyday use

Builds run from Xcode live in DerivedData. To keep a copy:

1. **Product → Archive**, then **Distribute App → Custom → Copy App**, and save it. Alternatively, build, then use **Product → Show Build Folder in Finder** and take `MouseCustomize.app` from `Products/Debug`.
2. Move `MouseCustomize.app` to `/Applications` and open it.
3. If macOS asks again, or the banner appears, enable it in Accessibility settings. If an old DerivedData entry is in the list, remove it.
4. Turn on **Launch at login** in the panel. This registers the app itself with `SMAppService`, not a helper.

## How it works

| File | Role |
| --- | --- |
| `MouseCustomizeApp.swift` | `@main` entry point; `MenuBarExtra` (window style); app delegate starts the controller |
| `AppController.swift` | One-time permission explanation, trust polling, event tap lifecycle, launch at login |
| `EventTap.swift` | The single `CGEventTap`: routes extra-button and scroll events |
| `SmoothScroller.swift` | Turns wheel ticks into eased 120 Hz pixel scroll events |
| `Actions.swift` | Button actions: synthesized shortcuts, Mission Control launcher |
| `Settings.swift` | Settings models and the `UserDefaults`-backed store |
| `MenuView.swift`, `ButtonsView.swift`, `ScrollSettingsView.swift` | The SwiftUI panel |

How each kind of event is handled:

- **Trackpad and Magic Mouse.** Their scrolling is continuous and phased, and always passes through unchanged.
- **Main wheel vs thumb wheel.** Discrete wheel events that are mostly vertical belong to the main wheel. Horizontal events belong to the thumb wheel, unless Shift is held, in which case they count as Shift + main wheel.
- **Smooth scrolling.** The original tick is swallowed and replaced by a short series of pixel scroll events. With ⌘, ⌃ or ⌥ held, events are only scaled and reversed, never smoothed, so zooming still works.
- **Our own events.** Every event the app posts is tagged with `eventSourceUserData`, so the tap ignores it.
- **Remapped buttons.** The press, drag and release are all swallowed, and the action runs right after the tap callback returns.

## Troubleshooting

- **Accessibility shows the app as enabled, but the banner says access is needed, or "Couldn't start" appears.** The permission entry is stale, usually because the app was rebuilt with a different signature. In *System Settings → Privacy & Security → Accessibility*, select MouseCustomize, remove it with **−**, add it back with **+** (or relaunch the app), and turn it on.
- **The thumb wheel does nothing or ignores its settings.** It must send standard horizontal scroll events. If Logi Options+ is installed and manages that wheel, set it to plain horizontal scrolling or quit Logi Options+ so the app sees the events. Some mice need Shift for horizontal scrolling; those use the main wheel's settings.
- **Previous/Next Space does nothing.** Check that *System Settings → Keyboard → Keyboard Shortcuts → Mission Control → Move left/right a space* is turned on.
- **The mouse froze while debugging.** A breakpoint inside the event tap callback pauses all extra-button and wheel input until macOS times the tap out. Avoid breakpoints in `EventTap.swift` while the tap is running.
- **Back/Forward doesn't work in some app.** These send ⌘[ and ⌘]. For apps that use other shortcuts, pick **Keyboard Shortcut…** and record the right one.

## If the project won't open

The project file was written by hand. If your Xcode refuses it, recreate the project in a minute:

1. In Xcode, choose **File → New → Project → macOS → App**. Name it `MouseCustomize`, with Interface *SwiftUI* and Language *Swift*.
2. Delete the generated `ContentView.swift` and `MouseCustomizeApp.swift`, then drag in all the `.swift` files from this repo's `MouseCustomize/` folder.
3. Under target → **Build Settings**:
   - *Application is Agent (UIElement)* (`LSUIElement`) = **YES**
   - *Enable App Sandbox* = **NO**
   - *macOS Deployment Target* = **13.0**
   - *Swift Language Version* = **Swift 5**
   - *Default Actor Isolation*, if present = **nonisolated**
   - Under **Signing & Capabilities**, remove the *App Sandbox* capability if it's listed.
4. Continue from step 2 of *Build and run* above.
