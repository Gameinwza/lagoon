# Lagoon — Agent Instructions (repo: Gameinwza/lagoon)

Lagoon: a native Dynamic-Island-style app for the Mac notch (Windows later, on the `windows` branch).
**Invisible. Intuitive. Instant. — Minimal by default, powerful by choice. — One island, every screen, zero setup.**

## Non-negotiable rules (in priority order)

1. Performance beats feature count. Every change must stay inside the budget below.
2. Usability beats looks. Minimal UI even when there is a lot underneath.
3. Zero configuration for normal users; settings are optional.
4. Native look and feel per OS (SwiftUI + AppKit on macOS).
5. Privacy-first, local-first. No telemetry or AI without explicit opt-in.
6. Ask for a permission only when the feature that needs it is first used.
7. Never steal keyboard focus. No unnecessary notifications.
8. Accessible: keyboard, VoiceOver labels, Reduce Motion.
9. No background work without a reason; stop it when the island is hidden or the feature is off.
10. Features are modules that can be turned off; a module failing must not crash the app.

## Performance budget (targets, measure with Instruments)

| Metric | Target |
|---|---|
| Idle CPU | ≤ 0.5 % |
| Idle RAM | ≤ 80 MB |
| Interaction response | ≤ 100 ms |
| Animation | 60 FPS |

Prefer events over polling, keep the main thread free (AppleScript, Process, I/O go to a background queue),
pause animation loops when nothing is visible, debounce bursty events, cap caches.

## UX states

- **Hidden** — nothing playing / nothing to show: island fades away.
- **Compact** — one piece of information (e.g. cover + wave).
- **Expanded** — on hover; at most 3 primary actions per context.
- **Banner** — short-lived system event (e.g. Bluetooth disconnect), sits *below* the notch.
- Content must never sit behind the camera notch (`IslandView.notch`).

## Architecture (where things are)

- `main.swift` — app entry, `IslandPanel` (fixed-size, click-through outside the island), mouse tracking, login item.
- `IslandView.swift` — all SwiftUI: compact / expanded / banner, scrubber, button styles, battery rings.
- `NowPlaying.swift` — Spotify / Music / YouTube (Chrome, Brave, Safari) via AppleScript on a background queue.
- `Bluetooth.swift` — connected devices (CoreAudio for headphones, IOBluetooth for others), AirPods battery
  (`system_profiler`) and in-ear state (`log stream` of bluetoothd — private format, may break).
- `Space.swift` — private SkyLight calls to keep the island visible while switching Spaces.
- `build.sh` builds `Lagoon.app` (icon from `Assets/make-icon.swift` → `Assets/AppIcon.icns`) and signs with the local "DynamicIsland Local" identity when present (stable permissions).
- `update.sh` / `install-autoupdate.sh` — launchd agent that rebuilds when `main` changes.

When adding a feature: keep platform calls behind a small type like the ones above, don't build abstractions
for Windows until that work starts, and don't add dependencies without a strong reason.

## Definition of done

Works per acceptance criteria · fits the screens in scope · stays inside the performance budget · no extra
clutter or steps · has loading / error / empty states · asks for no extra permissions · turning it off stops
its work · has tests for non-trivial logic · README updated if users see it.

## Roadmap (from the product plan)

| Phase | Scope | Priority |
|---|---|---|
| 0 Foundation | Adaptive layout, state machine, performance baseline | P0 |
| 1 Minimal core | Music, system HUD, file shelf, basic settings | P0 |
| 2 Universal UX | Multi-monitor, notchless Macs, accessibility, onboarding | P0 |
| 3 Productivity | Clipboard, timer, calendar, command palette | P1 |
| 4 Smart | Context engine, AI island, screenshot intelligence | P1 |
| 5 Developer | Claude/Codex, GitHub, Docker, plugin SDK | P2 |
| 6 Advanced | Automation, portal transfer | P2 |
| 7 Windows | Native WinUI + platform adapters | Future |

The full 126-item feature list is a backlog of ideas, not a commitment. Don't add a feature only because a
competitor has it.

## Non-goals

Showing everything at once · a mini desktop by default · AI/telemetry without consent · lots of background
polling · heavy animation for looks only · multi-page setup before first use · large dependencies ·
trading native feel for shared code.
