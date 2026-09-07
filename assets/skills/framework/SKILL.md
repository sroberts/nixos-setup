---
name: framework
description: Use when inspecting or controlling Framework laptop hardware via the framework_tool CLI — battery and charge limits, fan speed and thermals, keyboard backlight, fingerprint LED brightness, USB-C PD port state, expansion cards, privacy switches, firmware versions, or the EC console. Also use for questions like "why are my fans loud", "limit charging to 80%", "what's my battery health", "which expansion cards are plugged in", "is the camera switch off", or "what firmware am I on". Not for firmware flashing unless explicitly asked.
user-invocable: true
argument-hint: "[power|thermal|fans|charge|kblight|ports|cards|versions|console]"
---

# framework_tool — Framework laptop control

`framework_tool` is Framework's "swiss army knife" CLI for talking to the
embedded controller (EC) and reading SMBIOS. It reads sensors, sets fan and
charge behaviour, and can flash firmware.

Installed system-wide from nixpkgs (`framework-tool`, currently 0.6.5).
`framework-tool-tui` is the interactive TUI over the same hardware.

## Read this before running anything

**Every useful command needs root.** Without `sudo` the tool does not fail
cleanly — it prints a *misleading* error:

```
Must be root to get SMBIOS data.
[ERROR] Failed to communicate with EC. Reason: "Not a Framework Laptop"
```

That message does **not** mean detection failed or the hardware is wrong. It
means you forgot `sudo`. Always prefix with `sudo`.

**Fan and charge settings are not persistent.** They live in EC RAM and reset
on reboot. Nothing here is declarative — if a setting should survive reboots it
belongs in the NixOS config, not in a `framework_tool` invocation.

## Inspecting (safe, read-only)

```bash
sudo framework_tool --power           # battery %, charge/discharge, AC state
sudo framework_tool --thermal         # temperatures + current fan RPM
sudo framework_tool --sensors         # ambient light, G-sensor
sudo framework_tool --smartbattery    # cycle count, design vs full capacity, health
sudo framework_tool --versions        # BIOS/EC/PD/retimer firmware versions
sudo framework_tool --features        # what this firmware supports
sudo framework_tool --privacy         # camera + microphone hardware switches
sudo framework_tool --inputdeck       # keyboard/touchpad module status
sudo framework_tool --pdports         # USB-C PD port state per port
sudo framework_tool --pd-info         # PD controller details
sudo framework_tool --dp-hdmi-info    # DisplayPort / HDMI expansion cards
sudo framework_tool --audio-card-info # audio expansion card
sudo framework_tool --esrt            # UEFI ESRT firmware table
sudo framework_tool -t                # self-test: can we talk to the EC at all
```

`--power` and `--version` take `-vv` for more detail.

Battery health is the useful one for an aging laptop: `--smartbattery` reports
cycle count and full-charge capacity against design capacity.

## Fans

```bash
sudo framework_tool --thermal              # look before you touch
sudo framework_tool --fansetduty 50        # 0-100% duty cycle
sudo framework_tool --fansetrpm 3000       # explicit RPM (capped by EC fan table)
sudo framework_tool --autofanctrl          # RESTORE automatic control
```

**Setting a duty or RPM disables the EC's automatic curve.** The fan stays where
you put it until you restore auto control or reboot. Setting a low duty and
walking away means the machine has no thermal management — always hand control
back with `--autofanctrl` when done experimenting.

Diagnosing loud fans is usually `--thermal` (what is actually hot) rather than
forcing a duty cycle.

## Charging

```bash
sudo framework_tool --charge-limit         # read current limit
sudo framework_tool --charge-limit 80      # cap charging at 80%
sudo framework_tool --charge-limit 100     # back to full
sudo framework_tool --charge-current-limit <A>
sudo framework_tool --charge-rate-limit <rate>
```

An 80% cap meaningfully extends battery lifespan on a machine that lives on AC.
Remember it resets on reboot — set it again, or accept it as a per-session
thing.

## Lights

```bash
sudo framework_tool --kblight              # read keyboard backlight %
sudo framework_tool --kblight 30           # set to 30%
sudo framework_tool --fp-led-level         # fingerprint LED: high|medium|low|ultra-low|auto
sudo framework_tool --fp-led-level low
sudo framework_tool --fp-brightness 20     # fingerprint LED as a percentage
```

## EC console and state

```bash
sudo framework_tool --console recent       # recent EC log
sudo framework_tool --console follow       # tail it
sudo framework_tool --ec-hib-delay         # get/set S5→G3 hibernate delay
sudo framework_tool --intrusion            # chassis intrusion switch
sudo framework_tool --uptimeinfo
sudo framework_tool --s0ix-counter         # sleep-state entry counter
```

`--console` is the first stop when the EC is behaving oddly — fans, charging,
or the input deck misbehaving.

## Model-specific

These exist on the CLI but apply to Laptop 12/16 or specific modules, not the
Framework 13 AMD:

- `--expansion-bay` — Laptop 16 only
- `--tablet-mode`, `--touchscreen-enable` — Laptop 12
- `--haptic-intensity`, `--click-force` — haptic touchpads
- `--stylus-battery` — USI 2.0 stylus
- `--rgbkbd` — RGB keyboards (Laptop 16)
- `--inputdeck-mode auto|off|on|reset` — Laptop 12/13/16

Expect "not supported" rather than damage if run on the wrong model.

## Danger zone — firmware flashing

**Do not run these unless the user explicitly asks, and confirm first.** Their
own help text says they "may render your hardware unbootable":

```
--flash-full-ec <FILE>    --flash-ec <FILE>
--flash-ro-ec <FILE>      --flash-rw-ec <FILE>
--flash-gpu-descriptor
--dp-hdmi-update <FILE>
```

Also destructive/debug-only: `--pd-reset`, `--pd-disable`, `--pd-enable`,
`--reboot-ec`.

**Normal firmware updates go through `fwupd`, not this tool:**

```bash
fwupdmgr get-devices
sudo fwupdmgr refresh && sudo fwupdmgr update
```

That is the supported path, it is already enabled in this NixOS config
(`services.fwupd.enable`), and it will not brick an EC.

Read-only firmware *parsing* is safe: `--pd-bin`, `--ec-bin`, `--capsule`,
`--h2o-capsule`, `--dump-ec-flash`.

## Notes for this machine

`sjr-fw13` is a Framework 13 AMD (Ryzen 7040):

- Power profiles are handled by `power-profiles-daemon`, **not TLP** — that is
  Framework's guidance for 7040, and the NixOS config disables TLP explicitly.
  Prefer `powerprofilesctl` for power/performance modes; use `framework_tool`
  for hardware the daemon does not expose (fans, charge limit, EC).
- Firmware updates: `sudo fwupdmgr update`, which is in the post-install
  TODO.md checklist.
- `--driver` defaults to `portio` and should not need changing on Linux.

## Making something persistent

`framework_tool` settings are runtime-only. If a setting should survive a
reboot, it belongs in the NixOS config in the `nixos-setup` repo — a systemd
unit or an activation hook — not a command someone has to remember to re-run.
Follow the repo's workflow: feature branch → PR → merge, and never a
runtime-only change presented as a fix.
