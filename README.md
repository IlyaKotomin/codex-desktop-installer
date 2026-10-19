# codex-desktop-installer

One script that installs or updates OpenAI's Codex desktop app on Fedora and
Arch Linux. On Linux, Codex ships inside the ChatGPT desktop app (preview).

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/IlyaKotomin/codex-desktop-installer/main/install-codex-desktop.sh)
```

Run it as your normal user. It asks for your sudo password when it needs root.
Run the same command again any time to update. Add `-y` at the end to accept
the package manager's prompts.

Use `bash <(curl ...)` rather than `curl ... | bash`: with a pipe, dnf and
pacman cannot read your answers to their prompts.

## What it does

- **Fedora 43/44**: downloads OpenAI's RPM, checks its signature against the
  pinned OpenAI key `3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4`, and installs
  it with dnf. The package adds OpenAI's signed dnf repo, so a normal
  `sudo dnf upgrade` keeps it current. Fedora Atomic is not supported.
- **Arch**: runs OpenAI's own `install-arch.sh`, which adds their signed
  pacman repo. Later runs do `pacman -Syu chatgpt-bin`, a full system
  upgrade, because Arch does not support partial upgrades. Needs `diffutils`.

Both x86_64 and aarch64 work. Everything is downloaded from OpenAI's servers
(`persistent.oaistatic.com`). This repo only holds the script.

Start the app from the menu or with `chatgpt`. Native Wayland is experimental:
`chatgpt --ozone-platform=wayland`.

## Uninstall

- Fedora: `sudo dnf remove chatgpt`
- Arch: `sudo pacman -Rns chatgpt-bin`, then delete
  `/etc/pacman.d/openai-chatgpt.conf` and its `Include` line in
  `/etc/pacman.conf`.

Not affiliated with OpenAI. Official docs:
<https://learn.chatgpt.com/codex/linux/linux-app>
