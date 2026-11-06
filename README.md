<!-- readme: {"emoji": "💬", "en": "Speak or type on your phone; the line appears in World of Warcraft chat on a Steam Deck.", "zh": "在手机上说话或打字，消息出现在 Steam Deck 上 WoW 的聊天框里。", "status": "dev", "lang": "Python", "vis": "public", "tags": ["python", "steam-deck", "world-of-warcraft", "uinput", "homelab"]} -->
<div align="center" markdown="1">

# 💬 deck-chat

**Speak or type on your phone; the line appears in World of Warcraft chat on a Steam Deck.**

![status](https://img.shields.io/badge/status-in%20development-d29922?style=flat-square) ![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white) ![repo](https://img.shields.io/badge/repo-public-0969da?style=flat-square)

[![python](https://img.shields.io/badge/python-57606a?style=flat-square)](https://github.com/topics/python) [![steam-deck](https://img.shields.io/badge/steam--deck-57606a?style=flat-square)](https://github.com/topics/steam-deck) [![world-of-warcraft](https://img.shields.io/badge/world--of--warcraft-57606a?style=flat-square)](https://github.com/topics/world-of-warcraft) [![uinput](https://img.shields.io/badge/uinput-57606a?style=flat-square)](https://github.com/topics/uinput) [![homelab](https://img.shields.io/badge/homelab-57606a?style=flat-square)](https://github.com/topics/homelab)

**English** · [中文](README.zh-CN.md)

</div>

A Steam Deck has no keyboard, so chatting with your party in World of Warcraft is slow. Deck Chat puts a chat box
on your phone: type, or use the phone keyboard's mic, tap Send, and the line appears in WoW's chat on the Deck.
English is typed key by key; Chinese (anything a US keyboard can't type) is pasted. The page is styled like WoW's
chat frame and colours each channel the way the game does.

## Run it

Two parts: a small web server on a machine that is always on, and an agent on the Steam Deck.

**Server** (Python 3, standard library only):

1. `pip install pillow`, then `python3 fetch_assets.py` to download WoW's art and font into `assets/`
   (they are Blizzard's, so they are not in this repository).
2. Put the hostname the page will be served as in `~/.config/deck-chat.env`:
   `DECK_CHAT_HOSTS=chat.example.com` (optional `DECK_CHAT_PORT`, default 3022).
3. Copy `systemd/deck-chat.service` to `~/.config/systemd/user/` (fix the path to `server.py`), then
   `systemctl --user enable --now deck-chat`.
4. It listens on `127.0.0.1` only and has no login of its own. Put a reverse proxy with https and a login in front
   of it, reachable from your phone and the Deck only (a VPN such as Tailscale is the easy way).

**Steam Deck** (SteamOS already has python3, python-evdev, libX11 and xprop; no sudo needed):

1. Copy `deck/agent.py` to `~/deck-chat/agent.py` and `deck/deck-chat-agent.service` to `~/.config/systemd/user/`.
2. `~/.config/deck-chat.env`: `DECK_CHAT_SERVER=https://chat.example.com`.
3. `systemctl --user enable --now deck-chat-agent`.

## How it works

1. The page posts a message to `server.py`, which checks it (at most 1000 characters) and splits it into chat lines
   of at most 255 bytes, the channel prefix (`/p `, `/g `, `/w Name ` …) included.
2. The agent keeps asking the server for the next message (long poll). The Deck connects out, so nothing listens
   on the Deck.
3. For each line the agent presses Enter, types the line and presses Enter on a virtual keyboard (`/dev/uinput`,
   which the `deck` user may write). A line with characters a US keyboard lacks goes on WoW's X clipboard and is
   pasted with Ctrl+V. It types only while gamescope's focused window belongs to `Wow.exe`, so text never lands in
   Steam's menus.
4. The agent reports back; the page shows each message as waiting, typing, sent or failed.

## Files

- `server.py`: the page and the message queue (messages in memory only).
- `index.html`: the phone page.
- `deck/agent.py`: the Deck agent.
- `fetch_assets.py`: downloads WoW's font and interface textures from the game files that wago.tools serves, and
  turns them into what the page uses.
- `assets/background.jpg`: a screenshot of the Dark Portal; replace it with any image.
- `systemd/deck-chat.service`, `deck/deck-chat-agent.service`: the two services.
- `docs/DESIGN.md`: the design for the next part, a phone helper (spell buttons, live map, bags, chat both ways).

## Status

- Tested on SteamOS 3.8 in Game Mode with WoW under Proton: typed English and pasted Chinese reach the chat box.
- If the chat box is already open when a message arrives, the first Enter closes it and the text becomes game key
  presses: close it first.
- Blizzard has no official word on tools like this. It only sends chat, one message per tap.
