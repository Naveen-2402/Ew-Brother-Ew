# Ew Brother Ew: ideas to make it the best all-rounder

A wish list, not a plan. Nothing here is built yet. Each idea says **what** it is, **why** it helps, the **trade-off**, and a rough **size** (S = an evening, M = a few days, L = a week or more). The last section picks a sensible order.

The app today: counts Reels and Shorts, pauses every N, daily limit, focus mode, tasks with reminders, habits (multi-count, interval reminders, streaks), stats and history, widget, tile, backups. Fully offline.

---

## 1. Looking at it from different angles

| Who | What they want | What the app should do for them |
|---|---|---|
| **The scroller trying to cut down** | Fewer reels without white-knuckling it | Make each extra reel cost a little more, show progress, celebrate reels *not* watched |
| **The student** | Study blocks without the phone pulling them away | Focus sessions with a timer, block lists per session, a quiet "study mode" |
| **The working professional** | Deep work in the day, guilt-free scrolling later | Scheduled blocks, "allowed windows" for reels, a weekly report |
| **Someone who wants peace** | Calm, not another nagging app | Gentle tone, breathing, wind-down at night, fewer notifications |
| **The habit builder** | Consistency and proof of progress | Flexible streaks, history, small wins, reminders that adapt |
| **The privacy-minded** | Nothing leaves the phone | Keep it offline; encrypted backups; no accounts |
| **The battery-conscious** | It shouldn't drain the phone | Work only when Instagram/YouTube is open; no constant polling |

Rule of thumb from all of them: **help more, nag less.** Every new feature should either save time, give calm, or show progress, and should be easy to switch off.

---

## 2. Counting and awareness

| Idea | Why it helps | Trade-off | Size |
|---|---|---|---|
| **More apps**: Facebook Reels, Snapchat Spotlight, Moj, Josh, ShareChat (configurable list) | Most people just move to the next app when one is limited | Each app needs its own detection rules and testing; IDs change | M |
| **"Time on reels" as the main number** (alongside count) | Minutes feel more real than counts for long videos | Watch time is an estimate (capped per reel) | S |
| **Session view**: "This session: 23 reels, 14 min" in the bubble | Most binges are one long session; seeing it live breaks the trance | Slightly busier bubble | S |
| **Reels saved** counter: reels below your 7-day average | Rewards progress, not just shames usage | Needs a baseline week | S |
| **Night-time awareness**: different colour/limit after 11 PM | Late-night scrolling hurts sleep most | Another setting to explain | S |
| **Unlock count and first-pickup time** | Shows the habit loop, not just the reels | Needs a screen-on receiver; small battery cost | M |
| **"Why did I open this?" log** (the interrupt's answer saved) | Patterns: "80% just scrolling" is a wake-up call | One more tap on the interrupt (already there) | S |

## 3. Blocking and friction

| Idea | Why it helps | Trade-off | Size |
|---|---|---|---|
| **Growing pauses**: each pause after the limit gets longer (30 s, 60 s, 2 min) | Friction that scales beats a hard wall people learn to bypass | Can feel punishing; make it optional | S |
| **Allowed windows**: reels only between e.g. 8–9 PM | Guilt-free scrolling at a chosen time keeps it sustainable | Rigid; needs an override with friction | M |
| **Shorts-only block** (keep normal YouTube) and **Reels-only** (keep Instagram DMs) everywhere, not only at the limit | People need the app for messages/learning, not the feed | Detection must be reliable, or it blocks the wrong screens | M |
| **Typing challenge to override** ("I choose to waste time" typed out) | Strong pause for the impulsive brain | Annoying if overused; only for hard limits | S |
| **Cool-down after closing**: reels stay blocked for 15 min after you tap "Close reels" | Stops the instant re-open loop | Must be visible and explainable | S |
| **Grayscale while in reel apps** (via accessibility color filter, if allowed) | Colour drives the dopamine pull | Android only allows it through system settings; may not be possible | L |
| **Strict mode**: changing limits/turning off monitoring needs a 10-minute wait | Protects your morning self from your midnight self | Can't help in a real emergency; needs an escape | M |

## 4. Focus and productivity

| Idea | Why it helps | Trade-off | Size |
|---|---|---|---|
| **Focus sessions (Pomodoro)**: start 25/50 min, chosen apps blocked, break timer after | Turns "I should focus" into one tap | Overlaps with focus mode; merge the two | M |
| **Link a task to a focus session**: "Work on: Report" with time logged to the task | Shows where time actually went | Extra data per task | M |
| **Daily plan in the morning notification**: pick top 3 from the notification | Planning in 10 seconds, before the scrolling starts | Notification actions are limited to 3 buttons | S |
| **Due dates and "today / upcoming / someday"** for tasks | Real task management without another app | More UI; keep the quick-add fast | M |
| **Subtasks / checklist inside a task** | Big tasks feel doable when split | More screens | M |
| **End-of-day review** (2 questions: what went well, what to drop) | Reflection is where improvement happens | Optional; easy to ignore | S |
| **Calendar view of tasks done** in Stats | Visible proof of work | Small | S |

## 5. Habits

| Idea | Why it helps | Trade-off | Size |
|---|---|---|---|
| **Weekly targets** ("gym 3× a week") instead of only daily | Many good habits aren't daily; daily streaks punish rest days | Streak logic per week | M |
| **Streak freeze / rest days** (1 per week) | One missed day shouldn't wipe a 40-day streak; less guilt, more consistency | Can be gamed; keep it limited | S |
| **Amount habits** with units (2.5 L water, 30 min reading) | More natural than "8 taps" for some habits | Input UI for numbers | M |
| **Negative habits** ("no reels before 10 AM", "no sugar") ticked automatically when true | Ties habits to the counter, which is this app's superpower | Needs rules per habit type | M |
| **Auto-tick from reel data**: "Under 50 reels today" habit | Rewards the core goal every day | Ticks only at the end of the day | S |
| **Habit notes** (one line per day) | Context for why a day failed | Small extra UI | S |
| **Year heatmap** per habit (GitHub-style) | Motivating long-term view | Fine on phones with a horizontal scroll | S |

## 6. Peace and wellbeing

| Idea | Why it helps | Trade-off | Size |
|---|---|---|---|
| **Breathing pause**: the pause screen shows a 4-7-8 breathing animation | Turns a block into a calm moment instead of a punishment | Needs good animation; no sound by default | S |
| **Wind-down mode** after a set hour: dims bubble, longer pauses, one gentle "time to sleep" | Sleep is the biggest win for most people | Must be soft, not alarming | M |
| **Kind messages pool**: replace "Ew" lines at night or after a bad day | Tone matters; shame works short-term only | Message curation | S |
| **Mood check-in** (1 tap, 5 faces) after closing reels | Shows "I feel worse after scrolling" in your own data | Optional; easy to skip | S |
| **Offline alternatives** on the pause screen ("Walk 5 min", "Drink water", one of your habits) | Gives the brain something to do instead | Needs a small list | S |
| **No-phone challenge**: start a 30/60 min timer, count down in the notification | Simple and rewarding | Overlaps with focus sessions | S |

## 7. Insights and stats

| Idea | Why it helps | Trade-off | Size |
|---|---|---|---|
| **Weekly report screen** (not just a notification): best day, worst hour, habits %, tasks done, reels trend | One place to see the week | Design work | M |
| **Hour-of-day chart** for reels | Shows the danger hours (after lunch, before bed) | Data is already in reel_events | S |
| **Correlations**: "on days you walked, you watched 35% fewer reels" | Very motivating, personal evidence | Needs enough days; avoid false claims (show "might") | M |
| **Goals with progress**: "Average under 40 reels a day this month" | Long-term direction | Goal UI | M |
| **Export to CSV** | Your data, your spreadsheet | Small | S |

## 8. Everywhere-on-the-phone touches

| Idea | Why it helps | Trade-off | Size |
|---|---|---|---|
| **Bigger widget**: reels ring + top task + 3 habits, tappable | The home screen is where the day starts | RemoteViews layout limits | M |
| **Lock-screen / always-on notification glance** | See the day without opening the app | Must stay minimal | S |
| **More Quick Settings tiles**: "Start focus", "Log water" | One swipe actions | Tiles are limited per app (fine) | S |
| **App shortcuts** (long-press icon): Add task, Start focus, Log habit | Faster than opening the app | Small | S |
| **Wear OS tile** for habits | Tick water from the watch | Separate module | L |

## 9. Trust, privacy and safety

| Idea | Why it helps | Trade-off | Size |
|---|---|---|---|
| **App lock** (fingerprint) for Settings | Stops the impulsive "turn it off" | Needs the biometric API; easy escape for emergencies | M |
| **Encrypted backups** with a password | Backups can be stored in the cloud safely | Lose the password, lose the backup | M |
| **Auto weekly backup to a chosen folder** | Phone loss doesn't lose history | Storage Access Framework permission once | S |
| **"What this app can see" screen** | Builds trust in an accessibility app | Just text, worth it | S |
| **Health check**: warns if the counter was killed by the phone (gap in data) | Catches HyperOS/One UI killing the service | Detection heuristics | M |

## 10. Design and feel

| Idea | Why it helps | Trade-off | Size |
|---|---|---|---|
| **Onboarding in 3 screens** (what it does, permissions, first goal) | New phones, new users understand it fast | Upfront work | M |
| **Themes / accent colours**, Material You colours on Android 12+ | Personal feel | Must keep contrast | S |
| **Small celebrations** (confetti on a 7-day streak, "100 reels saved") | Positive moments keep people using it | Keep tasteful, no sounds by default | S |
| **Tamil/Hindi language** options | Messages land better in your own language | Translations | M |

---

## 11. Pros and cons of the big directions

| Direction | Pros | Cons |
|---|---|---|
| **Stricter blocking** | Works for people who need hard limits | People uninstall apps that feel like a cage; must keep escapes |
| **Gentler, calm-first** | Sustainable, pleasant, fewer uninstalls | Less effect on heavy scrollers |
| **All-in-one productivity** (tasks, focus, habits) | One app for the day, everything linked to reel data | Feature creep; every screen must stay fast |
| **More apps covered** | Closes the "just switch apps" loophole | Most maintenance; detection breaks with app updates |
| **Deeper insights** | Personal evidence motivates change | Needs weeks of data before it's useful |

Best balance: **calm by default, strict when you ask for it**, everything optional, all data offline.

---

## 12. Suggested order

1. **Quick wins (S)**: session count in the bubble, breathing pause, hour-of-day chart, streak freeze, auto-tick "under N reels" habit, cool-down after "Close reels", app shortcuts, CSV export.
2. **Core upgrades (M)**: focus sessions merged with focus mode, weekly targets for habits, weekly report screen, allowed windows, health check for a killed counter, more reel apps (Facebook, Snapchat).
3. **Bigger bets (L/M)**: strict mode and app lock, encrypted auto-backups, correlations, onboarding, bigger widget, Wear OS.

Each step should ship with a switch to turn it off, and should be tested on at least one non-Xiaomi phone too.
