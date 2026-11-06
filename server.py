#!/usr/bin/env python3
"""Deck Chat: type a chat message on the phone, it appears in World of Warcraft on the Steam Deck.

The phone page (index.html) posts a message here. The agent on the Deck (deck/agent.py) keeps asking for the next
message (long poll) through the same https address, types it into WoW with a virtual keyboard and reports back.
The Deck connects out to this server, so nothing on the Deck listens on a port.

Listens on 127.0.0.1 only: put a reverse proxy with https and a login in front of it (the author's runs behind a
Tailscale-only gateway). DECK_CHAT_HOSTS lists the hostnames it answers to, e.g. "chat.example.com"; set it in
~/.config/deck-chat.env. Python standard library only. Messages live in memory; nothing is written to disk.
"""
import json
import os
import threading
import time
import unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST, PORT = "127.0.0.1", int(os.environ.get("DECK_CHAT_PORT", "3022"))
PAGE = Path(__file__).with_name("index.html")
ASSETS = Path(__file__).with_name("assets")  # WoW interface art and font, from the game files (wago.tools)
TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".ttf": "font/ttf"}
HOSTNAMES = {h.strip() for h in os.environ.get("DECK_CHAT_HOSTS", "").split(",") if h.strip()} | {
    f"127.0.0.1:{PORT}", f"localhost:{PORT}"}
MAX_LINE = 255          # WoW's chat box takes at most 255 bytes (UTF-8: a Chinese character is 3), prefix included
MAX_TEXT = 1000         # one message is split into at most 4 or 5 chat lines
AGENT_FRESH = 40        # the Deck counts as connected if it asked for work within this many seconds
QUEUE_TIMEOUT = 30      # a message the Deck has not picked up by then fails (it would arrive too late)
TYPING_TIMEOUT = 60     # a message the Deck picked up but never confirmed fails

# Channel → what is typed before the text. "" keeps the channel the chat box is already on.
PREFIX = {"current": "", "say": "/s ", "party": "/p ", "guild": "/g ", "instance": "/i ", "whisper": "/w "}

# What the iPhone keyboard and dictation put in that a US keyboard can't type.
REPLACE = {"‘": "'", "’": "'", "“": '"', "”": '"', "–": "-", "—": "-",
           "…": "...", " ": " ", "\n": " ", "\r": " ", "\t": " "}

lock = threading.Condition()
messages = []           # newest last: {id, text, lines, status, error, at}
next_id = 1
agent_seen = 0.0


def clean(text):
    text = unicodedata.normalize("NFC", text)
    text = "".join(REPLACE.get(c, c) for c in text)
    return " ".join(text.split())


BREAKS = " ，。！？；：、,.!?;:"  # good places to cut a long message, after the character


def split_lines(prefix, text):
    """Cut so each chat line, prefix included, fits in MAX_LINE bytes; at a space or punctuation when possible."""
    room = MAX_LINE - len(prefix.encode())
    lines, rest = [], text
    while rest:
        fit = 0  # how many characters fit
        size = 0
        for c in rest:
            size += len(c.encode())
            if size > room:
                break
            fit += 1
        cut = fit
        if fit < len(rest):
            best = max(rest.rfind(b, 0, fit) for b in BREAKS)
            if best > fit // 2:
                cut = best + 1
        lines.append(prefix + rest[:cut].strip())
        rest = rest[cut:].strip()
    return lines


def expire(now):
    """Called with the lock held."""
    for m in messages:
        if m["status"] == "queued" and now - m["at"] > QUEUE_TIMEOUT:
            m["status"], m["error"] = "failed", "The Deck did not pick it up in time"
        elif m["status"] == "typing" and now - m["picked"] > TYPING_TIMEOUT:
            m["status"], m["error"] = "failed", "The Deck did not confirm it"
    del messages[:-20]


def public(m):
    return {k: m[k] for k in ("id", "text", "channel", "status", "error", "at")}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # no access log
        pass

    def reply(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def ok_host(self):
        if self.headers.get("Host", "") not in HOSTNAMES:
            self.reply(403, {"error": "unknown host"})
            return False
        return True

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(min(n, 20000)) or b"{}")

    def do_GET(self):
        global agent_seen
        if not self.ok_host():
            return
        path = self.path.split("?")[0]
        if path == "/":
            return self.reply(200, PAGE.read_bytes(), "text/html; charset=utf-8")
        if path.startswith("/assets/"):
            f = ASSETS / path[len("/assets/"):]
            if f.parent != ASSETS or f.suffix not in TYPES or not f.is_file():
                return self.reply(404, {"error": "not found"})
            self.send_response(200)
            self.send_header("Content-Type", TYPES[f.suffix])
            self.send_header("Cache-Control", "max-age=86400")
            data = f.read_bytes()
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path == "/api/state":
            with lock:
                now = time.time()
                expire(now)
                return self.reply(200, {"deck": now - agent_seen < AGENT_FRESH,
                                        "messages": [public(m) for m in messages[-10:]][::-1]})
        if path == "/api/next":  # the Deck agent, long poll
            if self.headers.get("X-Deck-Agent") != "1":
                return self.reply(403, {"error": "agent only"})
            deadline = time.time() + 25
            with lock:
                while True:
                    now = time.time()
                    agent_seen = now
                    expire(now)
                    job = next((m for m in messages if m["status"] == "queued"), None)
                    if job or now >= deadline:
                        break
                    lock.wait(min(5, deadline - now))
                if job:
                    job["status"], job["picked"] = "typing", now
                    lock.notify_all()
                    return self.reply(200, {"id": job["id"], "lines": job["lines"]})
            return self.reply(204, b"")
        self.reply(404, {"error": "not found"})

    def do_POST(self):
        global next_id
        if not self.ok_host():
            return
        path = self.path.split("?")[0]
        try:
            data = self.body()
        except ValueError:
            return self.reply(400, {"error": "bad JSON"})
        if path == "/api/send":
            origin = self.headers.get("Origin")
            if origin and origin.split("://", 1)[-1] not in HOSTNAMES:  # another web page can't post here
                return self.reply(403, {"error": "wrong origin"})
            text = clean(str(data.get("text", "")))
            channel = str(data.get("channel", "current"))
            target = clean(str(data.get("target", ""))).replace(" ", "")
            if not text:
                return self.reply(400, {"error": "Nothing to send"})
            if len(text) > MAX_TEXT:
                return self.reply(400, {"error": f"Too long: {len(text)} characters, at most {MAX_TEXT}"})
            if channel not in PREFIX:
                return self.reply(400, {"error": "Unknown channel"})
            if channel == "whisper" and not target:
                return self.reply(400, {"error": "Whisper needs a name"})
            if any(unicodedata.category(c)[0] == "C" for c in text + target):  # control characters
                return self.reply(400, {"error": "The text has characters chat can't take"})
            prefix = PREFIX[channel] + (target + " " if channel == "whisper" else "")
            with lock:
                now = time.time()
                if now - agent_seen >= AGENT_FRESH:
                    return self.reply(503, {"error": "The Deck is not connected (asleep, or off the home Wi-Fi)"})
                m = {"id": next_id, "text": text, "channel": channel if channel != "whisper" else "whisper " + target,
                     "lines": split_lines(prefix, text),
                     "status": "queued", "error": "", "at": now}
                next_id += 1
                messages.append(m)
                lock.notify_all()
            return self.reply(200, public(m))
        if path == "/api/done":  # the Deck agent reports one message
            if self.headers.get("X-Deck-Agent") != "1":
                return self.reply(403, {"error": "agent only"})
            with lock:
                m = next((m for m in messages if m["id"] == data.get("id")), None)
                if m:
                    m["status"] = "sent" if data.get("ok") else "failed"
                    m["error"] = "" if data.get("ok") else str(data.get("error", "failed"))[:200]
                    lock.notify_all()
            return self.reply(200, {"ok": True})
        self.reply(404, {"error": "not found"})


if __name__ == "__main__":
    ThreadingHTTPServer.daemon_threads = True
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
