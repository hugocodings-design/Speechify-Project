# TalkTome Boost

The PC speeds up the app: AI voices and Qwen run on the RTX 2080 Super instead of the phone. If the PC can't be reached, the phone does everything itself, as before.

Everything is installed in `%LOCALAPPDATA%\TalkTomeBoost` (venv, models, llama.cpp, `config.json` holding the pairing code).

## Start automatically with Windows (one time)

```powershell
powershell -ExecutionPolicy Bypass -File "pc_server\install_boost.ps1"
```

The script also starts it right away. Windows will ask about the firewall: allow it on **private networks**.

**Already installed under the old name (`%LOCALAPPDATA%\SpeechifyBoost`)?** Run the same command: it stops the old server, moves the folder to `TalkTomeBoost` as is (Python environment, models and pairing code are kept, nothing is downloaded again) and replaces the startup shortcut. Windows asks about the firewall once more because the path changed.

## On the phone

Profile → Computer acceleration → TalkTome Boost:
- addresses: `192.168.0.18` (home Wi-Fi), plus the PC's Tailscale address `100.x.y.z`
- code: the `token` value in `%LOCALAPPDATA%\TalkTomeBoost\config.json`

## Anywhere (Tailscale)

Install Tailscale on the PC and on the phone, signed in to the same account. Then add the PC's `100.x.y.z` address to the phone's address list.

## Uninstall

Delete the "TalkTome Boost" shortcut from `shell:startup`. Optionally delete `%LOCALAPPDATA%\TalkTomeBoost` too.
