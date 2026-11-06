<div align="center" markdown="1">

# 💬 deck-chat

**在手机上说话或打字，消息出现在 Steam Deck 上 WoW 的聊天框里。**

![状态](https://img.shields.io/badge/%E7%8A%B6%E6%80%81-%E5%BC%80%E5%8F%91%E4%B8%AD-d29922?style=flat-square) ![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white) ![仓库](https://img.shields.io/badge/%E4%BB%93%E5%BA%93-%E5%85%AC%E5%BC%80-0969da?style=flat-square)

[![python](https://img.shields.io/badge/python-57606a?style=flat-square)](https://github.com/topics/python) [![steam-deck](https://img.shields.io/badge/steam--deck-57606a?style=flat-square)](https://github.com/topics/steam-deck) [![world-of-warcraft](https://img.shields.io/badge/world--of--warcraft-57606a?style=flat-square)](https://github.com/topics/world-of-warcraft) [![uinput](https://img.shields.io/badge/uinput-57606a?style=flat-square)](https://github.com/topics/uinput) [![homelab](https://img.shields.io/badge/homelab-57606a?style=flat-square)](https://github.com/topics/homelab)

[English](README.md) · **中文**

</div>

Steam Deck 没有键盘，在 WoW 里跟队友打字聊天很慢。Deck Chat 把聊天框放到手机上：打字或用手机键盘的麦克风说话，
点 Send，这句话就出现在 Deck 上 WoW 的聊天框里。英文一个键一个键打；中文（美式键盘打不出的字）用粘贴。页面做成
WoW 聊天框的样子，每个频道用游戏里的颜色。

## Run it

两部分：一台常开机器上的小网页服务，和 Steam Deck 上的 agent。

**服务端**（Python 3，只用标准库）：

1. `pip install pillow`，再 `python3 fetch_assets.py`，把 WoW 的图和字体下载到 `assets/`
   （它们是暴雪的，所以不放在这个仓库里）。
2. 把网页的主机名写进 `~/.config/deck-chat.env`：
   `DECK_CHAT_HOSTS=chat.example.com`（可选 `DECK_CHAT_PORT`，默认 3022）。
3. 把 `systemd/deck-chat.service` 拷到 `~/.config/systemd/user/`（改好 `server.py` 的路径），再
   `systemctl --user enable --now deck-chat`。
4. 它只听 `127.0.0.1`，自己没有登录。前面放一个带 https 和登录的反向代理，只让手机和 Deck 能连（用 Tailscale
   这类 VPN 最省事）。

**Steam Deck**（SteamOS 自带 python3、python-evdev、libX11 和 xprop，不用 sudo）：

1. 把 `deck/agent.py` 拷到 `~/deck-chat/agent.py`，`deck/deck-chat-agent.service` 拷到 `~/.config/systemd/user/`。
2. `~/.config/deck-chat.env`：`DECK_CHAT_SERVER=https://chat.example.com`。
3. `systemctl --user enable --now deck-chat-agent`。

## How it works

1. 页面把消息发给 `server.py`，它检查（最多 1000 个字符），拆成每行最多 255 字节的聊天行，频道前缀
   （`/p `、`/g `、`/w Name ` …）算在里面。
2. agent 一直向服务端要下一条消息（长轮询）。是 Deck 向外连，所以 Deck 上什么都不监听。
3. 每一行：agent 用虚拟键盘（`/dev/uinput`，`deck` 用户可写）按 Enter、打字、按 Enter。有美式键盘打不出的字的行，
   放到 WoW 的 X 剪贴板里，用 Ctrl+V 粘贴。只在 gamescope 最前面的窗口是 `Wow.exe` 时打字，所以字不会打进 Steam
   的菜单。
4. agent 回报结果；页面上每条消息显示 waiting、typing、sent 或 failed。

## Files

- `server.py`：页面和消息队列（消息只在内存里）。
- `index.html`：手机页面。
- `deck/agent.py`：Deck 上的 agent。
- `fetch_assets.py`：从 wago.tools 提供的游戏文件下载 WoW 的字体和界面贴图，做成页面用的样子。
- `assets/background.jpg`：黑暗之门的截图；换成什么图都行。
- `systemd/deck-chat.service`、`deck/deck-chat-agent.service`：两个服务。
- `addon/QuietChat/`：WoW 插件：聊天窗口平时隐藏，打开聊天才显示；悄悄话、队伍、团队、公会和副本消息在一个小框里显示
  15 秒后淡出（`/quietchat` 开关）。`/qc`（或它的按键绑定）打开聊天窗口：最近 400 行，可筛选全部、悄悄话、队伍、公会、
  综合、交易、说；手柄十字键左右换筛选、上下滚动，B 关闭。`Bars.lua` 隐藏游戏的玩家框和目标框：经验条正上方两条细条显示
  生命和能量（平时半透明，战斗中不透明），选中的敌人在屏幕顶部有一条带名字的细条（`/quietchat bars` 切换回原样）。
- `docs/DESIGN.md`：下一步「手机助手」的设计（技能按钮、实时地图、背包、双向聊天）。

## Status

- 在 SteamOS 3.8 游戏模式、Proton 跑的 WoW 上测过：打的英文和粘贴的中文都进了聊天框。
- 消息到的时候聊天框要是已经开着，第一个 Enter 会把它关掉，字会变成游戏按键：先关聊天框。
- 暴雪对这类工具没有正式说法。它只发聊天，点一次发一条。
