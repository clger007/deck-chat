#!/usr/bin/env python3
"""Deck Chat agent, runs on the Steam Deck (user deck, systemd --user unit deck-chat-agent.service).

Asks the Deck Chat server (DECK_CHAT_SERVER, set in ~/.config/deck-chat.env) for the next chat message (long poll), types it into World of Warcraft with a
virtual keyboard (/dev/uinput, which user deck may write), and reports back. For each chat line: "/" then
Backspace (opens the chat box whether it was closed or already open), the line, Enter (sends it). A line a US keyboard can't type (Chinese) is put on WoW's X clipboard and
pasted with Ctrl+V instead. It types only while WoW is the window gamescope has in front, so a message never lands
in Steam's menus.

Needs only what SteamOS ships: python3 with python-evdev, libX11 and xprop.
"""
import ctypes
import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.request

from evdev import UInput, ecodes as e

SERVER = os.environ["DECK_CHAT_SERVER"].rstrip("/")  # e.g. https://chat.example.com
HEADERS = {"X-Deck-Agent": "1", "Content-Type": "application/json"}
KEY_GAP = 0.012     # seconds a key is held, and between keys
LINE_GAP = 0.35     # after a line is sent, before the next one opens the chat box

# US layout: character → (key, shift)
KEYS = {" ": (e.KEY_SPACE, False)}
for c in "abcdefghijklmnopqrstuvwxyz":
    KEYS[c] = (getattr(e, "KEY_" + c.upper()), False)
    KEYS[c.upper()] = (getattr(e, "KEY_" + c.upper()), True)
for plain, shifted, key in zip("1234567890", "!@#$%^&*()", "1234567890"):
    KEYS[plain] = (getattr(e, "KEY_" + key), False)
    KEYS[shifted] = (getattr(e, "KEY_" + key), True)
for plain, shifted, key in [("-", "_", e.KEY_MINUS), ("=", "+", e.KEY_EQUAL), ("[", "{", e.KEY_LEFTBRACE),
                            ("]", "}", e.KEY_RIGHTBRACE), ("\\", "|", e.KEY_BACKSLASH), (";", ":", e.KEY_SEMICOLON),
                            ("'", '"', e.KEY_APOSTROPHE), ("`", "~", e.KEY_GRAVE), (",", "<", e.KEY_COMMA),
                            (".", ">", e.KEY_DOT), ("/", "?", e.KEY_SLASH)]:
    KEYS[plain], KEYS[shifted] = (key, False), (key, True)


def wow_in_front():
    """WoW's X display (":1") if gamescope's focused window belongs to Wow.exe, else None. gamescope lists focusable
    windows on display :0's root as (window, app id, pid) triples."""
    try:
        out = subprocess.run(["xprop", "-display", ":0", "-root", "GAMESCOPE_FOCUSED_WINDOW",
                              "GAMESCOPE_FOCUSABLE_WINDOWS"], capture_output=True, text=True, timeout=3).stdout
        props = {line.split("(")[0]: [int(x) for x in line.split("=", 1)[1].split(",")]
                 for line in out.splitlines() if "=" in line}
        focused = props["GAMESCOPE_FOCUSED_WINDOW"][0]
        triples = props["GAMESCOPE_FOCUSABLE_WINDOWS"]
        pids = [triples[i + 2] for i in range(0, len(triples) - 2, 3) if triples[i] == focused]
        if not pids:
            return None
        with open(f"/proc/{pids[0]}/cmdline", "rb") as f:
            if b"Wow.exe" not in f.read():
                return None
        with open(f"/proc/{pids[0]}/environ", "rb") as f:
            env = dict(v.split(b"=", 1) for v in f.read().split(b"\0") if b"=" in v)
        return env.get(b"DISPLAY", b":1").decode()
    except (OSError, KeyError, ValueError, IndexError, subprocess.SubprocessError):
        return None


class _SelReq(ctypes.Structure):  # XSelectionRequestEvent
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int),
                ("display", ctypes.c_void_p), ("owner", ctypes.c_ulong), ("requestor", ctypes.c_ulong),
                ("selection", ctypes.c_ulong), ("target", ctypes.c_ulong), ("property", ctypes.c_ulong),
                ("time", ctypes.c_ulong)]


class _SelNotify(ctypes.Structure):  # XSelectionEvent
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int),
                ("display", ctypes.c_void_p), ("requestor", ctypes.c_ulong), ("selection", ctypes.c_ulong),
                ("target", ctypes.c_ulong), ("property", ctypes.c_ulong), ("time", ctypes.c_ulong)]


def serve_clipboard(display, text, ready, stop):
    """Own the X CLIPBOARD on WoW's display and hand `text` to whoever asks (Wine, for WoW's Ctrl+V) until `stop`
    is set. All X calls stay in this thread."""
    x = ctypes.CDLL("libX11.so.6")
    x.XOpenDisplay.restype = ctypes.c_void_p
    x.XDefaultRootWindow.restype = ctypes.c_ulong
    x.XCreateSimpleWindow.restype = ctypes.c_ulong
    x.XInternAtom.restype = ctypes.c_ulong
    for f in ("XDefaultRootWindow", "XCreateSimpleWindow", "XInternAtom", "XSetSelectionOwner", "XPending",
              "XNextEvent", "XChangeProperty", "XSendEvent", "XFlush", "XDestroyWindow", "XCloseDisplay"):
        getattr(x, f).argtypes = None
    d = x.XOpenDisplay(display.encode())
    if not d:
        ready.set()
        return
    d = ctypes.c_void_p(d)
    win = x.XCreateSimpleWindow(d, ctypes.c_ulong(x.XDefaultRootWindow(d)), 0, 0, 1, 1, 0, 0, 0)
    atom = lambda name: ctypes.c_ulong(x.XInternAtom(d, name.encode(), 0))
    clipboard, targets, utf8 = atom("CLIPBOARD"), atom("TARGETS"), atom("UTF8_STRING")
    text_atoms = {utf8.value, atom("STRING").value, atom("TEXT").value, atom("text/plain;charset=utf-8").value}
    data = text.encode()
    x.XSetSelectionOwner(d, clipboard, ctypes.c_ulong(win), ctypes.c_ulong(0))
    x.XFlush(d)
    ready.set()
    event = ctypes.create_string_buffer(192)
    while not stop.is_set():
        if not x.XPending(d):
            time.sleep(0.01)
            continue
        x.XNextEvent(d, event)
        req = _SelReq.from_buffer(event)
        if req.type != 30:  # SelectionRequest
            continue
        prop = req.property or req.target
        if req.target == targets.value:
            offer = (ctypes.c_ulong * (len(text_atoms) + 1))(targets.value, *text_atoms)
            x.XChangeProperty(d, ctypes.c_ulong(req.requestor), ctypes.c_ulong(prop), ctypes.c_ulong(4), 32, 0,
                              offer, len(offer))
        elif req.target in text_atoms:
            x.XChangeProperty(d, ctypes.c_ulong(req.requestor), ctypes.c_ulong(prop), utf8, 8, 0, data, len(data))
        else:
            prop = 0  # refuse other formats
        reply = _SelNotify(type=31, send_event=1, display=d.value, requestor=req.requestor,
                           selection=req.selection, target=req.target, property=prop, time=req.time)
        x.XSendEvent(d, ctypes.c_ulong(req.requestor), 0, ctypes.c_long(0), ctypes.byref(reply))
        x.XFlush(d)
    x.XDestroyWindow(d, ctypes.c_ulong(win))
    x.XCloseDisplay(d)


def tap(ui, key, shift=False):
    if shift:
        ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 1)
        ui.syn()
    ui.write(e.EV_KEY, key, 1)
    ui.syn()
    time.sleep(KEY_GAP)
    ui.write(e.EV_KEY, key, 0)
    ui.syn()
    if shift:
        ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 0)
        ui.syn()
    time.sleep(KEY_GAP)


def paste(ui, display, line):
    """Put `line` on WoW's clipboard and press Ctrl+V; keep serving the clipboard until WoW has read it."""
    ready, stop = threading.Event(), threading.Event()
    t = threading.Thread(target=serve_clipboard, args=(display, line, ready, stop), daemon=True)
    t.start()
    ready.wait(3)
    time.sleep(0.15)
    ui.write(e.EV_KEY, e.KEY_LEFTCTRL, 1)
    ui.syn()
    tap(ui, e.KEY_V)
    ui.write(e.EV_KEY, e.KEY_LEFTCTRL, 0)
    ui.syn()
    time.sleep(0.6)
    stop.set()
    t.join(2)


def type_lines(ui, lines):
    for n, line in enumerate(lines):
        display = wow_in_front()
        if not display:
            raise RuntimeError("WoW is not the window in front" + (f" (sent {n} of {len(lines)} lines)" if n else ""))
        # Enter toggles the chat box, and some add-ons keep it open after a send, so Enter could close it and
        # turn the text into game key presses. "/" opens a closed box with "/" in it and types "/" into an open
        # one: either way the box is open, and Backspace leaves it empty, on the channel it was on.
        tap(ui, *KEYS["/"])
        time.sleep(0.4)
        tap(ui, e.KEY_BACKSPACE)
        time.sleep(0.1)
        if all(c in KEYS for c in line):
            for c in line:
                tap(ui, *KEYS[c])
        else:
            paste(ui, display, line)
        time.sleep(0.05)
        tap(ui, e.KEY_ENTER)
        time.sleep(LINE_GAP)


def call(path, body=None, timeout=35):
    req = urllib.request.Request(SERVER + path, headers=HEADERS,
                                 data=None if body is None else json.dumps(body).encode())
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read()


def main():
    keys = sorted({k for k, _ in KEYS.values()} | {e.KEY_ENTER, e.KEY_LEFTSHIFT, e.KEY_LEFTCTRL, e.KEY_ESC,
                                                 e.KEY_BACKSPACE})
    with UInput({e.EV_KEY: keys}, name="Deck Chat keyboard") as ui:
        while True:
            try:
                status, data = call("/api/next")
            except (urllib.error.URLError, OSError, TimeoutError):
                time.sleep(5)
                continue
            if status != 200:
                continue
            job = json.loads(data)
            try:
                type_lines(ui, job["lines"])
                result = {"id": job["id"], "ok": True}
            except (ValueError, RuntimeError) as err:
                result = {"id": job["id"], "ok": False, "error": str(err)}
            try:
                call("/api/done", result, timeout=10)
            except (urllib.error.URLError, OSError, TimeoutError):
                pass


if __name__ == "__main__":
    main()
