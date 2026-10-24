<p align="center"><img src="Resources/icon.png" width="128" alt="Isle icon"></p>

<h1 align="center">Isle</h1>

<p align="center">A to-do list that lives in your MacBook's notch.</p>

![The open island: today's tasks around a "now" line, with a quick-add chip that reads "Fri, Oct 9 · 3:30 PM"](docs/quick-add.png)

Isle turns the notch into a small Dynamic Island for your tasks. Press **⌃⌥T** from any app, type
`groceries 5pm`, and press Return. The task exists before you lose your train of thought. At 5 PM the
island drops down and asks if it is done.

## What it does

- **Lives in the notch.** When closed, the island hides in the notch. Two small wings show today's
  progress ring and the time of your next task.
- **Peeks on hover.** Point at the notch to see the next task. Click to open.
- **Quick add with plain words or chips.** The trailing words of a task set its day and time. While you
  type, day and time chips appear under the field. A chip writes its words into the field, so you
  always see what the task gets, and a tag at the right shows where it will go.
- **Three lists.** *Today* (with overdue tasks and a "now" line), *Upcoming* (grouped by day), and
  *Backlog* (no date yet).
- **Plan your day.** Press ⌘P or click the pencil in the header. Write one task on each line, from the
  top of your head, and press ⌘Return to add them all, in order. Return starts a new line, ↑ and ↓ move
  between lines, and a list marker such as `- ` or `1. ` is dropped. The time words still work:
  `call mom 6pm`. The open tasks already on Today show on one line, so you do not write them twice.
  One Undo removes the whole plan.
- **A morning question.** Once a day, the first time you use the Mac after 5 AM, the island drops down
  with "Good morning. Plan your Friday?" and the buttons **Later** and **Plan**. It does not take the
  keyboard from your app. It does not come after 6 PM, after you already planned, or while a reminder
  is due. Turn it off in settings with **Morning plan**.
- **Move a task in two clicks.** Hover a row and click ☀︎ to move it to today. Click the calendar to pick a day
  chip, a time chip, or type a phrase like `fri 4pm`. Click **Done**, or press Return or Esc, to close it.
- **Rename in place.** Click a title to edit it. Return or a click elsewhere saves. Esc cancels.
- **Reminders in the island.** At a task's time, the island expands with **Done** and **Snooze 10m**.
- **Undo.** A delete, or a move that takes a task out of the list, shows a short undo bar.
- **Two themes.** *Standard* is the black island. *Glass* uses Apple's Liquid Glass for the peek, the
  open island, and reminders, in a System, Light, or Dark look. The closed island stays black in both,
  so it still hides in the notch.
- **Settings in the island.** Click the gear or press ⌘, to pick a theme, turn the reminder sound and
  the morning question on or off, and start Isle at login.
- **Local and private.** Tasks stay in one JSON file on your Mac. No account, no network.

| Closed | Peek | Reminder |
|---|---|---|
| ![Closed island with a progress ring and the next time](docs/closed.png) | ![Peek shows the next task](docs/peek.png) | ![Reminder with Done and Snooze](docs/alert.png) |

![Backlog with the schedule editor open](docs/schedule.png)

## Phrases

Isle reads only the **last words** of a task, so "Monday night football" stays a title.

| You type | Isle adds |
|---|---|
| `groceries 5pm` | groceries · today 5:00 PM |
| `call mom tomorrow at 6` | call mom · tomorrow 6:00 PM |
| `dentist fri 3:30pm` | dentist · next Friday 3:30 PM |
| `run tomorrow morning` | run · tomorrow 9:00 AM |
| `taxes apr 30` | taxes · April 30 |
| `renew passport in 3 days` | renew passport · in 3 days |
| `hike this weekend` | hike · Saturday |
| `learn Rust` (on Backlog) | learn Rust · backlog |

- A task with no date goes to the list you are on: today, tomorrow (Upcoming), or the backlog.
- A bare hour needs `at` or `@`: `gym at 7` is 7 AM, `dinner at 6` is 6 PM (1–6 mean PM).
- Day parts: `morning` 9 AM, `noon`, `afternoon` 3 PM, `evening` 6 PM, `tonight` 8 PM.

## Keys

| Key | Action |
|---|---|
| ⌃⌥T | Open the island with the add field focused. Press again to close. |
| Return | Add the task. |
| ⌘1 / ⌘2 / ⌘3 | Today / Upcoming / Backlog |
| ⌘P | Plan your day. Press again to go back to the list. |
| ⌘Return | On the plan page: add every line as a task. |
| ⌘, | Settings |
| Esc | Leave the plan or settings page, cancel the edit, clear the field, then close. The plan you typed stays. |
| Right-click | Launch at Login, Show Data File, Quit. |

## Install

You need Xcode 26 or later to build (Liquid Glass needs the macOS 26 SDK). Isle runs on macOS 14 or
later. The Glass theme needs macOS 26; on earlier systems, settings offer only Standard.

```sh
git clone https://github.com/nisarg-11-here/Isle.git
cd Isle
Scripts/bundle.sh
```

The script builds a release binary, wraps it in `Isle.app`, signs it ad hoc, installs it in
`~/Applications`, and starts it. Right-click the island and turn on **Launch at Login**.

On a Mac with no notch, Isle draws a notch-sized island at the top center of the main screen.

## How it works

```
Sources/
  IsleCore/        Foundation only, fully unit tested
    Todo.swift         the model and "yyyy-MM-dd" day keys
    Queries.swift      today / upcoming / backlog / progress / next / due
    QuickParse.swift   "dentist fri 3:30pm" → title, day, minute; a plan of many lines
    Morning.swift      when to ask "Plan your day?"
    Format.swift       "Tomorrow", "Fri, Oct 9 · 3:30 PM"
    TodoStore.swift    @Observable list, saved as JSON after each change
  Isle/            AppKit + SwiftUI
    IslandPanel.swift  borderless NSPanel over the notch
    IslandModel.swift  modes (closed, peek, open, alert, morning), focus, undo, the plan draft
    IslandView.swift   island shape, wings, peek, reminder, morning question
    OpenView.swift     tabs, add field, lists
    PlanView.swift     the plan page
    TaskRow.swift      rows and the schedule editor
    SettingsView.swift themes, glass look, sound, launch at login
    Settings.swift     theme and settings types
    Harness.swift      snapshot and self-test modes for development
```

Some details that took more than one try:

- **No jump on resize.** The window always matches the island, so it never blocks clicks on the menu
  bar. The SwiftUI canvas has one fixed size and is pinned to the top of the window. A resize only clips
  it. If the canvas resized with the window, SwiftUI would lay out one frame late and the island would
  jump.
- **Focus.** A click reaches the non-activating panel without taking focus from your app. Only the
  hotkey activates Isle, and closing hands focus back to the app you were in.
- **One palette for black and glass.** Every view draws with `Color.ink`: white in the dark scheme, black
  in the light one. `Color.primary` would not do, because it is the label color at 85 % opacity and would
  dim the Standard theme. A pixel diff proved Standard did not change.
- **Liquid Glass.** Glass uses `glassEffect(.regular, in: NotchShape)` on macOS 26, after Apple's
  "Applying Liquid Glass to custom views". The Glass theme tile
  uses a material, not glass, because Apple advises against glass on glass. On glass, the island sits
  on a 1 % black fill: the window server sends a click on a fully transparent pixel to the window
  below, and Liquid Glass leaves the island's own pixels transparent.
- **Floating days.** A task stores its day as a local `yyyy-MM-dd` key and its time as minutes after
  midnight. 5 PM stays 5 PM when you change time zones.
- **Safe storage.** Isle saves after every change with an atomic write, so a crash cannot leave half a
  file. On each launch it copies the file that loaded to `todos.backup.json`. If `todos.json` does not
  decode, Isle moves it aside as `todos.corrupt-<time>.json` and starts empty. Quit Isle before you
  edit the file by hand, or the next save replaces your edit.

## Develop

```sh
swift test                                   # parser, queries, and store
ISLE_SELFTEST=1 ISLE_DATA=/tmp/t.json swift run Isle   # drives the panel with real key events
ISLE_SNAPSHOT=/tmp/shots swift run Isle      # saves a PNG of each island state
```

- `ISLE_DATA` points Isle at another data file, so tests and demos never touch your list.
- The harness modes run the panel invisibly and ignore your pointer, so you can keep working.
- `swift Scripts/make-icon.swift` redraws the app icon.

Your tasks live in `~/Library/Application Support/Isle/todos.json`, beside `todos.backup.json`.
Time Machine backs up that folder. Settings live in `UserDefaults`: `theme`, `glassLook`,
`reminderSound`, `morningPlan`, and `planAskedDay` (the last day the morning question showed).

## Not yet

Sync, recurring tasks, subtasks, tags, a settings window, and a custom hotkey.

## License

MIT. See [LICENSE](LICENSE).
