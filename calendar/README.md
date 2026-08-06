# Voice Calendar

A scheduling calendar you talk to. Press the mic, say *“lunch with Sarah tomorrow at
noon for 90 minutes”*, and the event lands on the calendar — no forms, no date pickers.

Plain HTML/CSS/JS. No build step, no dependencies, no server, no account. Events live
in `localStorage` on your machine and nothing is sent anywhere.

## Running it

Dictation needs a secure context, so serve the folder rather than opening the file:

```sh
python3 -m http.server 8000
# then open http://localhost:8000/calendar/
```

Any static host works too (GitHub Pages, Netlify, …) as long as it's HTTPS.

Speech recognition is available in Chrome, Edge and Safari. Elsewhere the mic is
disabled and the text box below it accepts exactly the same phrases.

## What you can say

| You say | You get |
| --- | --- |
| `lunch with Sarah tomorrow at noon for 90 minutes` | Tomorrow, 12:00–13:30 |
| `dentist next Thursday at 2:30pm` | Following week's Thursday, 14:30 |
| `standup every weekday at 9:15 for 15 minutes` | Repeating Mon–Fri |
| `gym every Monday and Wednesday at 7am` | Repeating, two days a week |
| `design review Friday from 2 to 4` | Friday, 14:00–16:00 |
| `sprint review every other Tuesday at 10am` | Fortnightly |
| `mum's birthday on 12 September` | All-day event |
| `payroll every month on the 1st` | Monthly |
| `call Priya in 30 minutes` | Half an hour from now |
| `cancel my dentist appointment` | Removes the soonest match |

Dates understood: `today`, `tonight`, `tomorrow`, `day after tomorrow`, weekday names
(`friday`, `next friday`), `the 12th`, `12 September` / `September 12`, `12/25`,
`2026-09-01`, `in 3 days`, `in 2 weeks`, `next week/month/year`, `this weekend`.

Times understood: `at 3`, `3pm`, `15:30`, `9 15`, `noon`, `midnight`, `half past three`,
`quarter to four`, `in the morning/afternoon/evening`, `tonight`, and ranges like
`from 2 to 4`, `9am to 5pm`, `between 10 and 11`.

Durations: `for 20 minutes`, `for an hour`, `for half an hour`,
`for an hour and a half`, `30 minute call`. Defaults to an hour; a phrase with no time
at all becomes an all-day event.

Two conventions worth knowing:

* A bare hour with no am/pm reads 1–6 as afternoon and 7–11 as morning, so “at 3” is
  15:00 and “at 9” is 09:00. Say “at 3 in the morning” to override.
* A bare weekday means the next one (today counts). “Next Friday” means the Friday of
  the following week.

Anything the parser gets wrong is one click away from being fixed — every event opens in
a normal edit dialog, and every add/delete leaves an **Undo** in the toast.

## The rest of the app

* Month grid with a day agenda; click a day to select it, a chip to edit it.
* Recurring events with per-occurrence deletion (“this day only” vs. “whole series”).
* Export everything to `.ics` (with `RRULE`/`EXDATE`) for Google/Apple/Outlook.
* “Speak back” reads each confirmation aloud; “hands-free” keeps the mic open so you can
  dictate several events in a row.
* Keyboard: `v` mic, `n` new event, `t` today, `←`/`→` months, `Esc` closes dialogs.

## Files

| File | Purpose |
| --- | --- |
| `index.html` | Markup for the grid, voice panel, agenda and dialogs |
| `styles.css` | Theme (follows light/dark), layout, responsive rules |
| `parser.js` | Phrase → event. Pure functions, no DOM — usable on its own |
| `app.js` | State, recurrence expansion, rendering, speech, storage, `.ics` |
| `test/parser.test.js` | 52 parser cases |

## Tests

```sh
node calendar/test/parser.test.js
```

The parser is deliberately DOM-free so the whole language layer is testable in Node
against a fixed "now" (Thursday 6 August 2026), which keeps relative phrases like
"next Thursday" honest.
