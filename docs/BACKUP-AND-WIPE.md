# Backup and Wipe — Windows to Linux Migration

End-to-end runbook for replacing a Windows node (`bullfrog`, `jaxton`, `pulsar`) with Ubuntu Server 24.04 LTS, with a pre-wipe Google Drive backup as insurance.

**Target Google account:** `brazeltonshane@gmail.com`

> **Authority note:** the wipe is the irreversible step. Do not start Step 4 until Step 3 (verify backup) passes cleanly. If anything is unclear, stop and ask Shane.

---

## Overview — five steps

```
Step 1: Set up rclone Google Drive auth (ONE TIME, on first node only)
Step 2: Run the backup script (per node)
Step 3: Verify the backup landed in Google Drive (per node)
Step 4: Wipe and install Ubuntu Server 24.04 LTS (per node)
Step 5: Post-install bring-up — bootstrap into the mesh (per node)
```

---

## Step 1 — Set up rclone Google Drive auth (one time)

Do this on the FIRST Windows node you're going to wipe. The resulting config (`%USERPROFILE%\.config\rclone\rclone.conf` or `%APPDATA%\rclone\rclone.conf`) can be copied to subsequent nodes so you only do the OAuth dance once.

### 1a. Install rclone

```cmd
:: Option A — winget (Windows 10/11)
winget install Rclone.Rclone

:: Option B — manual
:: Download https://downloads.rclone.org/rclone-current-windows-amd64.zip
:: Extract rclone.exe to C:\rclone\
:: Add C:\rclone\ to PATH (System Properties > Environment Variables)
```

> **Heads-up: PATH does not refresh in already-open cmd windows.** After `winget install`, your current cmd session won't see `rclone` even though it's installed. Two fixes:
>
> - **Open a fresh cmd window** — the new shell picks up the updated user PATH.
> - **Or patch this session in place:**
>   ```cmd
>   set PATH=%PATH%;%LOCALAPPDATA%\Microsoft\WinGet\Links
>   ```
>
> After either, `rclone version` should print a version number.

Verify:

```cmd
where rclone
rclone version
```

### 1b. Configure the Google Drive remote

```cmd
rclone config
```

Walk-through (text-mode; safe over SSH/Termius):

```
n) New remote
name> gdrive
Storage> drive                                     <-- type "drive" or pick from list
client_id>                                          <-- leave blank, press Enter
client_secret>                                      <-- leave blank, press Enter
scope> 1                                            <-- "Full access all files"
service_account_file>                               <-- leave blank, press Enter
Edit advanced config? n
Use auto config? n                                  <-- IMPORTANT: say N (not Y)
                                                    <-- rclone will hint "If not sure try Y" — IGNORE
                                                    <-- Y opens http://127.0.0.1:53682/ which only
                                                    <-- works if your browser is ON this machine.
                                                    <-- You're SSH'd from your phone, so 127.0.0.1
                                                    <-- on this Windows box is unreachable from
                                                    <-- your phone. N gives a paste-able URL.
```

When it shows the auth URL:
1. Open it in any browser (your phone works fine).
2. Sign in as **brazeltonshane@gmail.com**.
3. Approve the access.
4. Google gives you a verification code — paste it back into rclone.

Then:

```
Configure this as a Shared Drive? n
y) Yes this is OK
e) Edit this remote
d) Delete this remote
y/e/d> y

q) Quit config
```

### 1c. Test

```cmd
rclone listremotes
rclone ls gdrive:
rclone mkdir gdrive:claude-memory-backups
```

If `mkdir` works, you're ready.

### 1d. Copy the config to other nodes (skip the OAuth dance per node)

The config lives at `%APPDATA%\rclone\rclone.conf` (or `%USERPROFILE%\.config\rclone\rclone.conf` depending on rclone version). Copy that file to the same path on each subsequent Windows node and the auth carries over.

```cmd
:: On the first node:
type "%APPDATA%\rclone\rclone.conf"

:: Copy the output. On the next node:
mkdir "%APPDATA%\rclone" 2>nul
:: Then paste the conf into a new file at that location with notepad or echo
```

Or use rclone over Tailscale to copy: `rclone copy <source-node>:<path> .` — but the simpler "copy-paste the conf file" works fine for 3 nodes.

---

## Step 2 — Run the backup script (per node)

The repo has the script at `scripts\backup-windows-to-gdrive.cmd`. If you've bootstrapped this node already, it's at `%USERPROFILE%\claude-memory\scripts\`. If not, clone the repo first per `docs\NODE-BOOTSTRAP.md`.

```cmd
cd /d %USERPROFILE%\claude-memory
git pull
cd scripts
backup-windows-to-gdrive.cmd
```

What the script does:

- Checks rclone is installed and remote `gdrive` is configured.
- Tests Google Drive reachability.
- Uploads `Documents`, `Desktop`, `Downloads`, `Pictures`, `Videos`, `Music` (anything that exists) to `gdrive:claude-memory-backups/<HOSTNAME>/`.
- Writes a manifest with hostname, OS version, hardware, IP, Tailscale status.
- Exits 1 (no wipe!) on any failure.

If anything fails, the script tells you what failed. **Do not proceed to Step 4 until Step 2 exits with `=== DONE ===`.**

---

## Step 3 — Verify the backup landed

Two ways:

### 3a. From the same node

```cmd
rclone ls gdrive:claude-memory-backups/%COMPUTERNAME%/
rclone size gdrive:claude-memory-backups/%COMPUTERNAME%/
```

Expect a list of files and a total size > 0.

### 3b. From your phone or another device

Open https://drive.google.com in a browser, sign in as **brazeltonshane@gmail.com**. Look for the folder `claude-memory-backups/<HOSTNAME>/`. Open a file or two to confirm they actually opened.

**Both checks must pass.** Phone-browse is the more important one — it confirms the data is actually retrievable through the regular Google Drive surface, not just through rclone.

---

## Step 4 — Wipe and install Ubuntu Server 24.04 LTS

### 4a. Pre-flight (one final check before the irreversible step)

```cmd
:: 1. Confirm hostname matches what you intend to wipe
hostname

:: 2. Confirm backup is in Google Drive
rclone ls gdrive:claude-memory-backups/%COMPUTERNAME%/ | findstr manifest.txt

:: 3. For pulsar specifically: verify MEGA Crew is NOT depending on this node's Ollama
::    See docs/MEGA-CREW.md "Verification queue" — if pulsar IS serving MEGA Crew
::    inference, you must migrate that role to another node BEFORE wiping pulsar.
curl http://localhost:11434/api/ps
```

### 4b. Prepare the USB installer

On a different machine (your Pi, your phone, anywhere with internet):

1. Download Ubuntu Server 24.04 LTS ISO: https://ubuntu.com/download/server
2. Flash to USB stick:
   - **Windows:** Rufus (https://rufus.ie) — pick the ISO, pick the USB, "Start"
   - **Linux/macOS:** `dd if=ubuntu-24.04-server.iso of=/dev/sdX bs=4M status=progress` (substitute correct device)
3. Eject cleanly.

### 4c. Boot the target node from USB

1. Insert USB into the target Windows node.
2. Reboot.
3. At BIOS/UEFI splash, press the boot menu key (varies — F12 / F11 / Esc / Del). For Surface Pro: hold Volume-Down while pressing Power.
4. Pick the USB stick.
5. Ubuntu installer boots.

### 4d. Install — minimum-viable choices

Walk through the installer with these answers:

| Question | Answer |
|---|---|
| Language | English |
| Keyboard | (your default) |
| Network | Confirm internet (DHCP usually fine; we'll switch to Tailscale later) |
| Proxy | (blank) |
| Mirror | (default) |
| Storage | "Use entire disk" — wipes Windows. Confirm twice. |
| Profile name | shane |
| Server name | `bullfrog`, `jaxton`, `pulsar`, etc. — match what's already in `docs/MESH.md` |
| Username | `shane` (or your existing user pattern; `hubby` for pulsar if continuity matters) |
| Password | Strong password — **store in `shanebrain_vault` after the install** |
| SSH | **YES — install OpenSSH server**. Import keys from GitHub user `thebardchat` (optional but convenient) |
| Snaps | None. Keep it lean. |

Click through. Reboot when finished. Remove the USB during reboot.

---

## Step 5 — Post-install bring-up

SSH into the freshly installed node from your Pi or phone:

```bash
ssh shane@<node-hostname>     # via Tailscale once it's up; for now use IP/local
```

### 5a. System update + base packages

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git python3 python3-pip jq vim
```

### 5b. Install Tailscale + join the mesh

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=<node-hostname> --ssh
```

Browser-auth as you normally do for Tailscale. Confirm:

```bash
tailscale status
```

Node should appear in the mesh under its hostname.

### 5c. Headless / lid-close-safe profile (Surface Pros, laptops)

```bash
sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind
sudo loginctl enable-linger $USER
```

### 5d. Bootstrap the repo (discovery layer)

```bash
git clone https://github.com/thebardchat/claude-memory.git ~/claude-memory \
  || (cd ~/claude-memory && git fetch origin && git pull)

mkdir -p ~/.claude
if [ ! -f ~/.claude/CLAUDE.md ]; then
  cp ~/claude-memory/docs/global-CLAUDE.md.template.md ~/.claude/CLAUDE.md.suggested
  echo "Suggested global at ~/.claude/CLAUDE.md.suggested — review then mv to ~/.claude/CLAUDE.md"
fi
```

### 5e. Smoke test

```bash
cd ~/claude-memory && claude
```

Ask Claude: **"What node am I on, what's my role, what should I do here?"** It should answer based on `docs/MESH.md`.

### 5f. Per-node role assignment

Open `docs/MESH.md`. Confirm or update the row for this node now that it's online and Linux. If a role got reassigned (e.g., pulsar took over MEGA Crew inference), update the table and commit on the dev branch.

---

## Quick reference — order of operations across all three Windows nodes

| Order | Node | Why this order |
|---|---|---|
| 1 | `bullfrog` | Confirmed idle. Lowest risk. Use it to debug the backup + install procedure end-to-end. |
| 2 | `jaxton` | Probably idle. Repeat the procedure. |
| 3 | `pulsar` | Highest risk if it's serving MEGA Crew. Verify with `curl http://localhost:11434/api/ps`. If serving, plan inference migration BEFORE wiping. |

---

## What this runbook does NOT cover

- Migrating Ollama-served roles (e.g., MEGA Crew inference if pulsar is serving it). Handle separately, before wiping the node that's actually doing the work.
- Restoring backed-up data onto the new Linux install. Most files will be irrelevant on a server-profile Linux box; restore selectively if needed via `rclone copy gdrive:claude-memory-backups/<host>/ ~/restore/`.
- Decommissioning Tailscale's record of the old Windows hostname. After the new Linux install registers under the same hostname, the old machine appears in the Tailscale admin console as offline. Remove it manually if you want the list clean.

---

## Failure recovery

| Symptom | Action |
|---|---|
| `rclone config` won't authenticate | Check the URL is from `accounts.google.com`. Make sure you're signing in as `brazeltonshane@gmail.com`, not a different Google account. |
| Backup script fails partway | Re-run. `rclone copy` is idempotent; it'll skip what's already uploaded and continue. |
| Ubuntu installer doesn't see the USB | BIOS/UEFI may have Secure Boot enabled. Disable Secure Boot OR re-flash USB in UEFI mode (Rufus has a toggle). |
| Tailscale up fails post-install | `sudo systemctl status tailscaled` for clues. Reauth: `sudo tailscale logout && sudo tailscale up`. |
| Hostname collision in Tailscale | The old Windows entry is still listed. Remove it from the Tailscale admin console: https://login.tailscale.com/admin/machines |
