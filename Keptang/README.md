# Snapceipt

Snap a receipt, see where your money goes. A personal finance app for iPhone and iPad that builds
your spending history from receipts, with Thai VAT and tax built in. Everything is read on the
device, in Thai and English. Made for YIDH 2026 Hack Day. Open source under the [MIT License](../LICENSE).

The Xcode project, targets and folders keep the working name **Keptang**; the app shows up as
**Snapceipt**.

## What it does

- **Overview**: the money goal on top, then spending for a day, a Sunday-to-Saturday week, a calendar
  month or year as a line, bars or candles.
  - Turn the range knob, page with ‹ ›, or pick a date from the calendar.
  - Touch the chart for one bucket's receipts.
  - Below the chart: money in / out / net, a category watchlist, and the latest receipts.
- **Add** (+):
  - **Scan** with the camera, pick from the **Photo album**, or **Type it** ("Pop corn 60",
    "ข้าวมันไก่ 50 เมื่อวาน", "เงินเดือน 30000").
  - Typed lines are read into a checklist you confirm line by line.
  - **Share → Snapceipt** from Photos, LINE, Files or Mail sends a receipt straight in.
- **Receipts**: category tiles, then every receipt and income by month, with search. There's also a
  spending calendar.
- **Bills**: electricity, water and internet over the year.
- **Data analysis**:
  - insights and a forecast;
  - Thai personal income tax with the shopping deduction (full tax invoices only);
  - an Obsidian-style graph of receipts, shops, items and categories. It has search and
    jump-to-result, and links suggested by an on-device model that you confirm or dismiss.
- **Income** as well as spending (salary, side work, sales, refunds, gifts, interest). Income is kept
  out of spending, VAT and the goal.
- **Settings**:
  - four colours and four styles (console, classic, gruv, kawaii), each with light and dark;
  - **Your data**: export a backup (JSON, optionally with photos) or a spreadsheet (CSV), and import
    either, or a bank's CSV, with duplicates skipped;
  - **Chat bots** (below).

## How reading works (all on the device)

1. **Straighten**: VisionKit's document camera, or Vision rectangle detection and a Core Image
   perspective fix.
2. **Read**: Vision text recognition in Thai and English.
3. **Understand**: Apple Intelligence (Foundation Models, Guided Generation) where available.
   `ReceiptRules` and `QuickEntryRules` work without it and check its numbers.
4. **Sort**: each item gets a category, trying these in order:
   - your past corrections;
   - the merchant;
   - a Create ML text classifier (`ItemCategory.mlmodel`, trained by `Tools/TrainItemCategory.swift`);
   - Thai/English keywords.

Without Apple Intelligence (or in the Simulator) the rules do everything on their own.

## Building

Requirements: Xcode 26 or later, iOS/iPadOS 26.

1. Copy `Keptang/Config/Signing.example.xcconfig` to `Keptang/Config/Signing.xcconfig` and put your
   Apple Developer Team ID in it. That file is ignored by git.
2. The bundle IDs (`com.pepperonilover1234.keptang`, `….share`) and the App Group
   (`group.com.pepperonilover1234.keptang`) belong to the original developer's team. To run on your
   own device, change them in the target settings, `Config/*.entitlements`,
   `ShareExtension/ShareViewController.swift` and `Cloud/SharedInbox.swift`.
3. Open `Keptang/Keptang.xcodeproj` and run the **Keptang** scheme. The first launch loads six months
   of sample Bangkok spending; reload or clear it in Settings.

Tests: `xcodebuild test -project Keptang/Keptang.xcodeproj -scheme Keptang -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
(app, 84 tests), and `npm test` in `Keptang/cloud/bot` (bot, 14 tests).

Launch arguments for demos and screenshots include `-tab analysis -page graph`, `-range 1Y`,
`-skin kawaii -colour kawaii`, `-appearance dark`, `-add type -quick "Pop corn 60"` and `-sheet settings`.
See `LaunchOption` uses in the code.

## Optional: the Discord bot and cloud inbox

Send the bot `Pop corn 60` or a receipt photo and it lands in the app. The cloud only holds what's
sent through the bot until the app imports it, plus an opt-in monthly summary.

- `Keptang/cloud/supabase/setup.sql`: the database, with row-level security.
- `Keptang/cloud/bot`: the Discord bot (Node.js, discord.js).
- `Keptang/cloud/README.md`: setup. `cloud/setup.sh` asks for your keys and keeps them in an ignored `.env`.

Never commit `.env` or a Supabase service key. The app only ever holds the public (anon/publishable) key.

## Layout

| Folder | What's in it |
|---|---|
| `Keptang/App` | App entry, tabs, router |
| `Keptang/Views` | Screens and components (`OverviewLayouts.swift` holds the per-style layouts) |
| `Keptang/Design` | Colours (`Paint`) and styles (`Skin`) |
| `Keptang/Analysis` | `SpendingAnalyzer`, time ranges, money goal, the graph model |
| `Keptang/Intelligence` | Categorising, the typed-entry reader, link suggestions, Apple Intelligence |
| `Keptang/Scan` | Camera, OCR, receipt rules |
| `Keptang/Model` | SwiftData models, income, import/export |
| `Keptang/Cloud` | Supabase client, chat inbox, shared-photo inbox |
| `ShareExtension` | The share sheet extension |
| `KeptangTests` | Swift Testing suites |
| `cloud` | Supabase SQL and the Discord bot |

## Privacy

Receipts, photos and income stay in the app's SwiftData store on the device. Nothing is sent
anywhere unless you connect the optional chat bot. Settings → Chat bots → Delete my cloud data
removes everything from the cloud.

## Contributing

Issues and pull requests are welcome. Keep changes small and tested, match the code style around
them, and never include personal data, keys or a `Signing.xcconfig`.
