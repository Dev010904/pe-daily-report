# Daily Report – Panchal Enterprise (v2, cloud)

Daily cylinder register (supply / empty / cash / bill), daily stock and
company-wise cylinder balances. One Flutter code base for:

- **Android app** – works offline at the godown, syncs when internet is back.
- **PC website** – https://pe-daily-report.daily-report.workers.dev (same screens in Chrome; can be installed as a desktop icon).

Data lives in Supabase project **pe-systems** (Mumbai), shared by future PE
systems. Login is username + password.

## Install / update the phone app
Either: on the phone open the website, log in, **Settings → Install App →
Download Android App**, open the file, tap **Update**.
Or: send `Releases/PE Daily Report v<version>.apk` on WhatsApp → open →
**Update**. Never uninstall first. On the first login after updating from
v1, the old phone data is uploaded to the cloud automatically.

On a PC: open the website, log in, **Settings → Install App → Install on
this computer** (desktop icon). The website asks for the login every time.

## PC use with the keyboard only (v2.1, like Tally)
Menu on the left; press the letter (no Ctrl needed):
D Dashboard · S Supply · K Stock · C Companies · L Filling Report · N New Entry · F Filling /
Plant · X Damaged Cylinders · B Loan Cylinders · V Vehicles · O Opening Stock · T Today · G Go to date · P PDF of this day ·
R Reports · E Settings & Lists · I Install App · A Account · Q Log out.
← / → (or PgUp / PgDn) = previous / next day. Esc = back (asks first when
something typed is not saved). Ctrl+A = save the form now.

New entry: Company → Enter → Challan → Enter → Bill (Y / N, only when full
is supplied) → Enter → type the gas name (list filters as you type) → Enter
→ Full → Enter → Empty → Enter → next gas … Enter on an empty gas line =
End of List → cash line (type, amount, C/G) → Enter on an empty cash line →
"Save this entry?" (Enter = Yes, Esc = No). On every form, ↑ or Backspace
in an empty box goes back to the box before; erasing a gas / cash name
offers "Remove this line". Entries with only empties need no bill. On the PC a fresh
entry opens after saving, like Tally.

Other pages (v2.2.5): Stock and a company page scroll with ↑ ↓; company
page A / M / L / D = All / This month / Last month / Dates; Settings, its
lists (Companies, Filling Plants, Cash Types: Enter = rename, Del = remove,
N = add), Reports (M / Y / D, ← →, F / T, Enter) and Account (C, U, Q) all
work with the keyboard; every pop-up box answers Enter / Esc. Gas names:
AR Comm. is shown as ARGON and N2 Comm. as NITROGEN (codes unchanged).

Old dates: the top bar turns orange with OLD DATE and a warning strip
(T = back to today). The Dashboard lists entries whose bill is not made
(Space = mark made) and entries without a challan number.

## Updates (v2.2.4)
Right after login (and when the app comes back to the front) the app quietly
reads `version.json` from the website. Nothing is downloaded by itself: if
the build number is newer, a green **New update available – Update** bar
stays under every page. **Update** on the phone downloads the APK (login
needed) and hands it to Android's installer (first time: allow "Install
unknown apps"; on Android 12+ later updates need no tap); Android closes the
app while it updates and a "Daily Report is updated" message opens it again.
On the website / PC, Update reloads into the new version. Phones on 2.0.2
or older: update once from the website (Settings → Install App → Download
Android App). Keep `kBuildNumber` equal to the +number in `pubspec.yaml`.

## Filling plants (v2.0.2)
Empties are written as **sent** to a plant (taken out of the godown); filled
cylinders that come back are written as **filled back** from that plant
(added to full stock, taken off that plant's empties, not off the godown).
The app keeps the count at each plant: at plant = start + sent − filled back.
Example: 40 CO2 sent to ABC → godown 0, ABC 40; 25 come back filled → full
+25, godown still 0, ABC 15. Days written before v2.0.2 (plant count typed
directly) still calculate the old way; opening such a day in Filling /
Plant and saving turns it into sent / filled back with the same totals.

**Step by step (v2.2):** filled more than once in a day? Type the new number
and press Enter; it is added (+11, later +3 = 14), nothing to add up by hand.
Enter on an empty box moves on, Backspace takes the last number off. The
Stock tab shows the steps above the total ("+11 +3" / "= +14"), and so does
the day PDF. Only the totals count; the steps are kept to show how it was
filled (older app versions that change a total just show the new total).

**DA in the plant lines (v2.2.8):** DA has a line like the other gases, at
the plant it is swapped at (Empty sent = DA empty given, Filled back = DA
filled received). The DA logic is unchanged: filled back is added to full
stock, empty sent is taken out of the godown, and no DA empties are kept at
the plant (so a DA line has no "at plant" count). One DA line a day; a new
day starts with an empty DA line at the last DA plant. Stored as before
(`filling.DA`, `daEmptyGiven`) plus `daPlant` on the day. Days saved
without a plant (all DA before 2.2.8) count at the plant named "Aims Oxygen
…"; that plant is fixed in setting `daPlant.old` the first time DA is saved,
so renaming it or moving DA to another plant later never moves old days.

## Filling report (v2.2.8)
PC menu L, phone tab **Filling**. The list shows each plant's cylinders
filled back this month (up to the chosen date) and the empties waiting
there. Enter / tap opens a plant: D = day-wise (one month, ← → = month),
M = month-wise (business year April - March, ← → = year), Y = year-wise,
C = choose dates, P = PDF. Enter on a year shows its months, on a month its
days, on a day opens that day's Filling / Plant; Backspace goes up a level.

## AR SPL removed, line remarks (v2.4.1)
AR SPL is no longer a gas (user, 2026-10-29): every old AR SPL cylinder counts
as ARGON. Old records are merged exactly in lib/logic/argon_spl.dart (numbers
added; hand-corrected starts of day become ARGON start + AR SPL start, so the
ARGON stock = old ARGON + AR SPL every day); entries that held AR SPL get the
remark "ARGON SPL" (or "ARGON SPL: 2 full" when mixed with ARGON). Screens show
the merged data at once; the rewritten records are saved after a successful
sync (AppStore.saveSplMerge), so nothing newer from another device is lost.
Every entry line (ours and loan lines) has a **Remarks** box after Empty
received (Enter: numbers -> remarks -> next gas); stored on the entry as
`remarks` {gas code or "gas|plant": text}; shown in the Supply list, company
page, Save box and the day / register PDFs.

## Vehicles & papers (v2.4)
V on the PC (phone: Settings -> Vehicles & Papers, or the Dashboard list).
Each delivery vehicle by its number; each vehicle has papers (PUC, Insurance,
Fitness (FC), Permit, Road Tax, RC Book, or any name typed) with Valid from
(optional) and Valid till (last valid day; dates typed dd-mm-yyyy or picked on
the calendar; future dates allowed). From 10 days before the till date the
Dashboard lists the paper every day (RENEW SOON, orange); from the till date
it is URGENT - RENEW (red) until renewed. The first time the app opens each day
a reminder box lists them (V = open Vehicles); the phone Dashboard tab shows a
warning sign. **Renewed** (Enter / R on the paper): type the new dates; they
replace the old ones (no old dates are kept) and the countdown starts again.
E = change, N = add paper, Del = remove, C = change the number. Stored as
settings records vehicle_<id> (no cloud change).

## Damaged cylinders (v2.3)
X on the PC (or the Damaged Cylinders button on the Stock tab). **A damaged
cylinder keeps its gas** (changed in v2.3): 2 Oxygen + 1 CO2 declared damaged
= 3 damaged cylinders, and only 2 Oxygen and 1 CO2 can come back. Per gas:
damaged = start + declared today − repaired; the total is all gases added up.
The page has three lists (the gas is only chosen from a list: ↓ or its first
letter, Enter; nothing can be written; the list opens only when asked for):
1. **Damaged at the start of this day** - carried on from the day before; the
   first time, choose each gas and type the damaged cylinders already there
   (stored per day as `openDamagedGas`, only gases that differ; the old
   typeless `openDamaged` number is kept in the record but not used).
2. **Declared damaged today** - from the godown empties / from full stock.
3. **Repaired today** - only gases that have damaged cylinders; each comes back
   as an EMPTY of its own gas in the godown.
The cursor opens on the empty line (never on a saved one). Stock shows it in
red on that gas ("− 2 (damaged)", "+ 1 (repaired)", "−1 damaged" under Closing
Full) and a **Damaged** row at the bottom (start, +today, − repaired, total,
and the gases it is made of); also on the Dashboard, the day and register PDFs.
Nothing can go below zero, gas by gas (repairing 3 CO2 when 1 CO2 is damaged
is refused).

## Loan cylinders (v2.3)
Borrowed from a filling plant when ours are short. They come FULL (supplied
straight away, not filled), go to companies, come back empty, and are given
back to their plant. They look different from ours, so they are kept apart:
- **B Loan Cylinders** (PC; phone: button on the Stock tab): one line per
  plant + gas: Taken from plant / Given back empty / Given back full. Each line
  shows full and empty in our godown, with which companies, and still to give
  back. Stored on the day: `loanIn`, `loanBackEmpty`, `loanBackFull`
  (gas -> plant -> qty).
- **Entry**: while any loan cylinders are out, a "Loan cylinders" list comes
  after our gas lines (choice "ARGON · ABC Plant", Loan full supplied / Loan
  empty received) and before cash. A company can return ours and loan ones
  together. Stored on the entry: `loanFull`, `loanEmpty`. Loan full supplied
  needs a bill like ours. Entries now keep unknown parts (`_extra`), but app
  versions before 2.3 drop the loan parts when they save an entry: update every
  device.
- Our stock and company stock never include loan cylinders. Stock shows a purple
  "↳ loan" line under the gas (full in godown under Closing Full, empty under
  Empty); Dashboard: "Loan cylinders to give back" + list; Companies and the
  company page: "LOAN ARGON 10 (ABC Plant)"; Filling report: loan to give back
  per plant, loan taken / given back day-, month- and year-wise; PDFs: day
  (loan table and loan lines in entries), register, company statement (loan
  table), plant report (loan section).
- Nothing can go below zero: supplying more loan cylinders than are full in the
  godown, a company returning more than it has, or giving back more than we have.

On the PC every table and form is kept to a readable width, so numbers stay
next to their gas / company name. O2 is shown as **Oxygen** everywhere (the
stored code is still O2).

## First time setup (once)
On the login screen tap **First time? Set up the owner account**, enter the
one-time setup code, choose a username and a password (8+ characters).
The owner can then add more users in Settings → Account & Users.

## Updating the app later
1. Change the code, raise `version:` in `pubspec.yaml` (e.g. `2.0.3+5`) and
   `kAppVersion` in `lib/config.dart` (a test checks they match).
2. Phone: `tool/build_apk.ps1` (ARM phones, compressed, signed) → copies it to
   `Releases`. Keep the build number rising, or phones refuse the update.
3. Website: `tool/deploy_web.ps1` builds the site, adds the APK for Install
   App and runs `npx wrangler deploy` (settings in `wrangler.jsonc`).

### Keep these safe – never lose or change them
`android/key.properties` and `android/app/pe-release.jks` (the app's signing
key). Updates only install over the old app when signed with this key.

## Security
- Row-level security: only members in `pe_members` can read/write
  `dr_records`; everything else is denied (tested with a non-member and an
  anonymous user).
- Accounts are created only through database functions (owner setup needs a
  one-time code, locks after 10 wrong tries); logins use an internal
  `@pe-systems.invalid` address so password-reset mail cannot be abused.
- Every change is kept in `dr_history` (owner can read; nobody can edit).
- Phone: session in Android encrypted storage, app data excluded from
  Google backups, release code obfuscated.
- Website: `worker/index.js` forces https and adds strict security headers
  (CSP, no framing, HSTS). The login is kept only in memory (closing or
  refreshing asks again) and old browser storage is wiped on load.
- The Android app on the website (`/private-app/`) is never served
  directly; `/download/android` hands it out only after checking the login
  token with the database (`pe_me`).
- Public sign-up is blocked inside the database; the one-time setup
  functions are locked after setup.

## Developer notes
- `flutter test` – stock rules, never-below-zero guard, company balances,
  sync between devices, offline queue, v1 → v2 migration, PDFs, and the full
  tap-through flow at phone / small phone / PC sizes.
- `flutter build web --dart-define=PE_DEMO=true` / `flutter build apk
  --dart-define=PE_DEMO=true` make a demo build with a fake cloud and no
  login – for testing only, never give it to users.
- `flutter test integration_test/app_test.dart -d <device>` runs the full flow
  on a phone/emulator. **It wipes the app data on that device.**
- Stock rules: `lib/logic/stock.dart`; company balances: `lib/logic/ledger.dart`;
  sync: `lib/data/repo.dart`; PDFs: `lib/export/`.
- This PC times out on IPv6 downloads: `android/gradle.properties` sets
  `java.net.preferIPv4Stack=true`; also set `GRADLE_OPTS=-Djava.net.preferIPv4Stack=true`.
