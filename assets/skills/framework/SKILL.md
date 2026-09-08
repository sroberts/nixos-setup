---
name: framework
description: Use when inspecting or controlling Framework laptop hardware via the framework_tool CLI — battery and charge limits, fan speed and thermals, keyboard backlight, USB-C PD ports, expansion cards, privacy switches, firmware versions, or the EC console. Also use for questions like "why are my fans loud", "limit charging to 80%", "what's my battery health", or "what firmware am I on". Not for firmware flashing unless explicitly asked.
user-invocable: true
---

# framework_tool

Framework's CLI for the embedded controller. Installed system-wide
(nixpkgs `framework-tool`). `framework-tool-tui` is an interactive TUI over the
same hardware and is usually nicer for browsing.

**Run `sudo framework_tool --help` for the command list — it is accurate and
complete.** This skill only covers what that output does not tell you.

## Four things --help won't tell you

**1. Everything needs root, and the failure is misleading.** Without `sudo`:

```
Must be root to get SMBIOS data.
[ERROR] Failed to communicate with EC. Reason: "Not a Framework Laptop"
```

That is not a detection failure and not the wrong hardware. It means you forgot
`sudo`. Don't go debugging the EC.

**2. `--fansetduty` / `--fansetrpm` disable automatic fan control.** The fan
stays pinned where you put it — the EC's thermal curve is off until you run
`sudo framework_tool --autofanctrl` or reboot. Setting a low duty and walking
away leaves the machine with no thermal management. Always hand control back.

**3. Nothing here persists.** Fan and charge settings live in EC RAM and reset
on reboot. If a setting should survive, it belongs in the NixOS config in
`nixos-setup` (feature branch → PR → merge), not a command someone has to
remember to re-run.

**4. Firmware updates go through fwupd, not this tool.**

```bash
fwupdmgr get-devices && sudo fwupdmgr refresh && sudo fwupdmgr update
```

`services.fwupd.enable` is already on. The `--flash-*` family says it "may
render your hardware unbootable" — treat those, plus `--pd-reset/-disable/
-enable` and `--reboot-ec`, as requiring explicit confirmation from the user.

## This machine

`sjr-fw13` is a Framework 13 AMD (Ryzen 7040):

- Power modes are `power-profiles-daemon` (`powerprofilesctl`), **not TLP** —
  Framework's guidance for 7040, and the config disables TLP explicitly. Use
  `framework_tool` only for what the daemon doesn't expose: fans, charge limit,
  EC console.
- Options for Laptop 12/16 will not apply: `--expansion-bay`, `--tablet-mode`,
  `--touchscreen-enable`, `--rgbkbd`, `--haptic-intensity`, `--click-force`,
  `--stylus-battery`. Expect "not supported" rather than damage.
- `--driver` defaults to `portio`; no reason to change it on Linux.

## Worth knowing

`--smartbattery` reports cycle count and full-charge vs design capacity — the
useful one for judging battery health. `--console recent|follow` dumps the EC
log, the first stop when fans, charging, or the input deck misbehave.
