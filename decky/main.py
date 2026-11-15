"""Decky backend: start / stop the two Deck Chat user services (the phone page server and the WoW typing agent)."""
import asyncio
import os

import decky

SERVICES = ["deck-chat.service", "deck-chat-agent.service"]
URL = "https://steamdeck.king-algieba.ts.net/"


def _env():
    uid = os.getuid()
    env = dict(os.environ)
    env["XDG_RUNTIME_DIR"] = f"/run/user/{uid}"
    env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path=/run/user/{uid}/bus"
    return env


async def _systemctl(*args):
    proc = await asyncio.create_subprocess_exec(
        "systemctl", "--user", *args,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT, env=_env())
    out, _ = await proc.communicate()
    return proc.returncode, out.decode().strip()


class Plugin:
    async def get_state(self) -> dict:
        _, out = await _systemctl("is-active", *SERVICES)
        states = out.splitlines()
        return {"on": all(s == "active" for s in states), "states": states, "url": URL}

    async def set_on(self, on: bool) -> dict:
        # enable/disable too, so the switch also holds after a reboot
        verb = ["enable", "--now"] if on else ["disable", "--now"]
        code, out = await _systemctl(*verb, *SERVICES)
        if code:
            decky.logger.error(f"systemctl {verb} failed: {out}")
        return await self.get_state()

    async def _main(self):
        decky.logger.info("WoW Chat switch loaded")

    async def _unload(self):
        pass
