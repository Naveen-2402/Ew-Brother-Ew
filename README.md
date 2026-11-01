# Ew Brother Ew

A personal Android app that counts the Instagram Reels and YouTube Shorts you scroll, makes you stop for a few seconds every N reels, and keeps your tasks and habits next to the count. Everything stays on the phone: the app has no internet permission.

Android only (minSdk 26, targetSdk 36, so Android 8 and newer). Works on any Android phone; the Setup screen detects the phone maker and only shows the extra steps that phone needs (Xiaomi/Redmi/POCO, Samsung, Oppo/Realme/OnePlus, Vivo/iQOO, Huawei/Honor). Mainly tested on a Xiaomi phone with HyperOS.

## What it does

| Area | What you get |
|---|---|
| Reel counter | Counts Reels and Shorts as you swipe forward (scrolling back doesn't count again). Shows a floating counter over Instagram and YouTube: a ring that fills toward your daily limit, the count, and a pop on every new reel. Tap it for the Reels/Shorts split, reels until the next pause and how many are left today. |
| Pause | A calm full-screen countdown every N reels (separate N for Instagram and YouTube), with a random message and your top task. Leaving mid-pause doesn't skip it: the rest comes back when you return. |
| Daily limit | Optional hard limit for Reels and Shorts together. **Block reels at the limit** on: the Reels and Shorts feeds are blocked (messages and normal videos still work). Off: a 30-second pause after every reel over the limit. |
| Focus mode | Blocks chosen apps during a time window, with an "Allow 10 minutes" escape. Re-checked every 15 seconds, so it also catches the window starting while you're already in the app. |
| Tasks | Quick add, top 3 stars, repeat daily, reminders (once at a date and time, or daily for repeating tasks, with a Done button on the notification), swipe right to finish, swipe left to delete, drag to reorder. |
| Habits | One tap to tick today, or several times a day (e.g. 8 glasses of water: each tap adds one, done at 8 whenever you do them). Reminders: off, once, or every 15 min to 3 h within a time range; range reminders stay quiet when you're on track and stop once it's done. 7-day strip, streaks, and a history sheet per habit (current and best streak, last 30 days, total, 5-week calendar). |
| Stats and history | 7 / 30 / 90 days, 1 year or any custom range. Look at reels (both apps or one), screen time, habits or tasks. Totals, daily average, change against the previous period, best and worst day, and a day-by-day list. Tap any day or bar for its full details. |
| Extras | Home-screen widget, Quick Settings tile and status notification with pause/resume (both ask you to unlock first when the phone is locked), morning top 3, evening habit check, Sunday summary, backup and restore to a file. |

## How it works

- **Counting** runs in an Android accessibility service (`EwAccessibilityService`). It watches scroll events from Instagram and YouTube only, and counts a reel when the feed's page index moves forward. YouTube sends a scroll event when Shorts opens but usually none for later swipes, so while YouTube is in front (screen on) the service also checks every 0.7 s which Short fills the Shorts pager (`reel_recycler`) and counts when it changes; scroll events from YouTube then don't count, so nothing is counted twice. All detection rules are in one file, `detect/DetectionRules.kt`.
- **Overlays** (pause, limit, focus gate, bubble) are drawn by that service as accessibility overlays, so the app doesn't need the "display over other apps" permission.
- **Data** is one SQLite database (`focuspal.db`). The Kotlin side creates and migrates the schema (`data/EwDatabase.kt`), because counting can start after a reboot before the Flutter UI is opened. Flutter reads and writes the same file through `sqflite`.
- **Day boundary**: a day starts at 4 AM by default. A new "day starts at" hour only takes effect after the current day ends, and moving the phone's clock forward doesn't start a new day early, so neither can reset today's count.
- **UI**: Flutter with `provider` view models, MVVM style. Notifications, the widget, the tile, backups and screen time use Android framework APIs directly, not Flutter plugins.

## Project layout

```
ew_brother_ew/
  lib/
    core/        logical day, formatting, native bridge (method channel "ew/native")
    data/        repositories (settings, reels, tasks, habits, usage, history)
    domain/      models and the daily score
    ui/          app shell, theme, shared widgets, one folder per screen
  android/app/src/main/kotlin/com/ewbrother/app/
    data/        database schema and migrations, Store (native DB access)
    detect/      reel detection rules and detector
    service/     accessibility service
    overlay/     pause screen, bubble, mascot and ring views
    notify/      notifications, alarms, boot and action receivers
    widget/ tile/ usage/
  test/          unit tests for day logic, score and date helpers
BUILD_ON_EC2.md  exact build commands, then a full uninstall of the build tools
project_state.json  decisions and pinned versions
```

## Build

The app is built on a temporary Ubuntu EC2 machine, not on the PC. Follow `BUILD_ON_EC2.md`: it installs Flutter 3.47.9 and the Android SDK, builds the signed release APK, and at the end removes everything it installed.

Short version, once the machine is set up:

```bash
source ~/ew-env.sh && cd ~/ew_brother_ew
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

Pinned versions: Flutter 3.47.9 (Dart 3.13.7), AGP 9.1.0, Gradle 9.3.1, Kotlin 2.4.0, compileSdk 36. Packages: `provider`, `sqflite`, `fl_chart`.

## Install on the phone

1. Play Protect blocks sideloaded apps that use accessibility. In Play Store: profile picture, **Play Protect**, settings, turn off **Scan apps with Play Protect**. Install the APK, then turn scanning back on.
2. Open the app, go to **Settings > Setup and permissions**, and turn on each item:
   - Accessibility service. If the switch is greyed out: App info, ⋮ menu, **Allow restricted settings**, then try again.
   - Usage access.
   - Notifications.
   - Battery: pick the unrestricted option (recommended). Xiaomi calls the two choices **No restrictions** / **Battery saver**; stock Android, Samsung and most others call them **Unrestricted** / **Optimized** (App info > Battery).
   - **Phone extras**, only on phones that add their own background limits: Autostart (Xiaomi, Oppo/Realme/OnePlus, Vivo, Huawei/Honor), Never sleeping apps (Samsung), lock the app in Recents. Pixel, Motorola, Nokia and other stock Android phones need nothing extra.
   The buttons stay after a step is done, so you can go back and change or turn things off.
3. Open Reels and swipe a few. The bubble should count up.

New builds signed with the same key install as updates and keep your data. A release build without `android/key.properties` stops with an error instead of quietly using a different key.

## If counting stops after an Instagram or YouTube update

Open **Settings > Detection check**, swipe a few reels, and tap **Count this** on the row for the reel feed. That adds the feed's ID without a rebuild. If that doesn't help, the IDs in `detect/DetectionRules.kt` need updating.

## Signing key

The release key (`ewbrother-release.jks`) and its passwords (`key.properties`) are **not** in this repository, and must never be committed (see `.gitignore`). Keep them in a password manager or an encrypted archive. Without them, you can't install an update over the existing app; you'd have to uninstall, which deletes app data, so export a backup first.

## Backups

**Settings > Backup > Export** saves the whole database to a file you choose. **Restore** replaces everything with that file. Backups from older app versions are upgraded automatically. A restore checks the file first (version, integrity, size up to 200 MB) and keeps your current data if the backup can't be opened. Nothing is copied off the phone automatically: cloud backup and phone-to-phone transfer are both turned off.
