# WoW phone helper: design

Status: proposal, 2026-11-05. Nothing in it is built yet except chat (phone → WoW), which works today.

## Goal

WoW runs on the Steam Deck, which has no keyboard and a small screen. The phone becomes a second screen for it:

- **Chat both ways**: send (done) and read your party's, guild's and whispers' replies.
- **Spell buttons**: tap a button on the phone, the spell on that action-bar key fires.
- **Live map and quests**: the minimap, the quest tracker, and the world map when it is open, on the phone while you play.
- **Bags, skills, character**: what is in your bags, your spells, talents, professions and quest log.

## What WoW allows

These limits decide the design:

1. **Add-ons can't send data out.** No network, no files, except their own saved-settings file, which the game writes
   only on `/reload` or logout. So add-on data is a snapshot, never live.
2. **The game draws everything on screen.** Anything visible can be shown live on the phone as a picture: the
   Deck screenshots itself (`gamescopectl screenshot`, already used in testing) and crops the part you want.
3. **The chat log is a live file.** `/chatlog` makes WoW append chat to `Logs/WoWChatLog.txt` as it happens.
4. **Blizzard's rule for input is one action per key press.** One tap on the phone = one key press, never a
   repeat, never a sequence, never anything the helper decides by itself. Reading game memory is out entirely.

## How the parts talk

Three parts; the first two exist.

| Part | Where | New work |
|---|---|---|
| Phone page | server (`server.py`, `index.html`) | tabs, live pictures, chat log, bags |
| Deck agent | Steam Deck (`deck/agent.py`) | key taps, screen crops, chat-log reader, snapshot reader |
| Snapshot add-on | inside WoW (new, `addon/DeckHelper/`) | writes bags, spells and quests on reload |

Data per feature:

| Feature | Way | Fresh |
|---|---|---|
| Send chat | keys / paste (done) | instant |
| Spell buttons | one key tap | instant |
| Minimap, quest tracker, world map | screenshot → crop → JPEG | about every second |
| Read chat | agent reads WoWChatLog.txt | a few seconds (not measured) |
| Bags, spells, talents, skills, quests | add-on snapshot | at your last reload or logout |

The agent already keeps one connection to the server (long poll). New jobs come over the same line: "tap key 3",
"send pictures of the minimap while the Map tab is open". The agent sends pictures and chat lines back with POSTs.
Pictures are taken only while someone has the Map tab open, so the Deck does no extra work otherwise.

## Phone screens

Tabs along the bottom, same WoW look as the chat page:

- **Chat**: the send box (as now) above a WoW-coloured log of incoming party, guild and whisper lines.
- **Actions**: a grid of action-bar buttons. Before the first snapshot they are plain keys `1`–`0`, `-`, `=`; after
  it, each shows the spell's icon and name. Tap = one key press. A button greys out while its tap is being sent.
- **Map**: the live minimap and quest tracker; when the world map is open in the game, the whole map instead.
- **Bags**: items with icons and counts, grouped by bag. From the snapshot, with its time on top.
- **Character**: level, gold, spells, talents, professions and other skills. From the snapshot.
- **Quests**: the quest log with objectives, from the snapshot; the live tracker picture sits on top.

## Details per feature

**Spell buttons.** The agent presses the key with the virtual keyboard it already has, only while WoW is the window
in front (as for chat). A tap that arrives while the chat box is open would type the key into chat, so the page
says "close chat first" after a chat send. Not checked yet: whether EasyController's gamepad layout changes what
keys `1`–`0` do. The snapshot add-on reads the real key for each action button, so the labels can't drift.

**Live pictures.** The full screenshot is 1280 × 800. The agent crops on the Deck (ffmpeg, already on SteamOS) and
sends a small JPEG, so only a few tens of KB travel per picture. Crop boxes depend on the UI layout, so the page has
a "set areas" screen: one full screenshot, drag a box for each area, saved on the server. Not measured yet: how
long one screenshot takes and what it costs in battery; the first build measures it and sets the rate from that.

**Chat log.** The add-on turns `/chatlog` on at login. The agent follows the file and sends new party, guild,
whisper and say lines. Kept in memory only, last 200 lines. Not checked yet: whether WoW Forever writes the file
right away or in batches.

**Snapshot add-on.** One small add-on, public game API only, no frames, nothing on screen. It refreshes its saved
table on bag, spell, skill and quest events, and WoW writes it on reload or logout. The agent notices the file
change, reads the Lua table, and sends it as JSON. Item and spell icons: the snapshot holds each icon's file id; the
server fetches the icon once from the game files (as `fetch_assets.py` does) and caches it. A "Refresh" button
could send `/reload` through the chat path, at the cost of a few seconds of loading screen.

## Build order

1. **Live**: Actions (plain keys), Map (live pictures, crop editor), incoming chat. No add-on needed; testable in
   one evening of play.
2. **Snapshot**: the add-on, the reader, Bags, Character, Quests, and spell icons and names on the Actions buttons.
3. **Polish**: add to home screen as an app, tab memory, vibration on tap.

Each step ends with a test in the game and a note in the README's Status.

## Risks

- **Account**: the helper sends one key per tap and reads the screen as a picture, the same as a keyboard and a
  stream. It reads no memory and decides nothing by itself. Blizzard has not ruled on tools like this.
- **Battery**: screenshots cost power. Pictures stop when the Map tab is closed or the phone locks.
- **Layout drift**: an add-on or UI-scale change moves the minimap; the crop editor fixes it in a few taps.
- **Two add-ons on one key**: EasyController and other gamepad add-ons may claim keys; the snapshot shows the real
  binding.

## Related

- [README](../README.md): what runs now and how to install it.
- Similar projects: [WoWU](https://github.com/ShoValentine/WoWU-Gamepad-Assistant) (second screen through a
  streamed Windows display; needs a Windows PC), [Adventurer's Pouch](https://github.com/BaronCyrus/adventurers-pouch)
  (add-on snapshot to an Android app), [Elemental DeckKeys](https://github.com/Koutasora/Elemental-DeckKeys)
  (general phone keyboard for the Deck).
