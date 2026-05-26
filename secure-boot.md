# Secure Boot Runbook — Framework 13 AMD (lanzaboote)

## Bottom Line

Secure Boot is a **post-install** step. Install and boot the encrypted system
first, confirm it's stable, then enable lanzaboote, enroll your own keys (keeping
Microsoft's so firmware updates survive), and flip Secure Boot on in BIOS. Doing
this before the system boots, or enabling Secure Boot in BIOS before enrolling
keys, leaves you unbootable. The whole thing is reversible from a live USB if it
goes wrong.

Order is non-negotiable: **encrypt at install → boot → lanzaboote → enroll keys →
enable in BIOS.** Optionally, bind the LUKS key to the TPM at the end so the disk
auto-unlocks only when the signed boot chain is intact.

---

## Prerequisites

- System installed with the encrypted LVM-on-LUKS layout and booting normally.
- BIOS 3.05+ with a UEFI admin password set.
- Secure Boot currently **disabled** in BIOS (it was, for the install).

---

## Step 1 — Add lanzaboote to the flake

In `flake.nix`, uncomment the `lanzaboote` input and the
`inputs.lanzaboote.nixosModules.lanzaboote` module line.

In `configuration.nix`:
1. Add `lib` to the function args: `{ config, pkgs, lib, inputs, ... }:`
2. Uncomment the SECURE BOOT block:
   ```nix
   boot.loader.systemd-boot.enable = lib.mkForce false;
   boot.lanzaboote = {
     enable = true;
     pkiBundle = "/var/lib/sbctl";
   };
   ```
3. Add `sbctl` to `environment.systemPackages` (uncomment the line, or just add
   `sbctl` to the existing list).

Do **not** rebuild yet.

## Step 2 — Create signing keys

```bash
sudo sbctl create-keys
```

This generates your platform keys in `/var/lib/sbctl`.

## Step 3 — Rebuild (signs the boot chain, still in Secure Boot OFF)

```bash
sudo nixos-rebuild switch --flake ~/nixos-config#sjr-fw13
```

lanzaboote replaces systemd-boot and signs the kernel + initrd as a unified image.

## Step 4 — Verify everything is signed

```bash
sudo sbctl verify
```

Every `nixos-generation-*.efi` and the bootloader should report as signed. If
anything is unsigned, stop and fix it before touching BIOS.

## Step 5 — Enroll keys

```bash
sudo sbctl enroll-keys --microsoft --firmware-builtin
```

Two flags, both load-bearing on Framework:

- `--microsoft` enrolls Microsoft's OEM certificates alongside yours, so
  Option ROMs signed by Microsoft (which some hardware presents during boot)
  still validate.
- `--firmware-builtin` keeps the keys that came pre-provisioned with the
  Framework firmware. This is what allows `fwupd` BIOS/EC updates to keep
  validating after Secure Boot is on. Upstream lanzaboote docs call this out
  specifically for Framework.

Without **both**, you risk locking out legitimate firmware updates.

### Entering Setup Mode (Framework-specific)

The firmware must be in Setup Mode for `enroll-keys` to install new keys. On
Framework, do **NOT** use "Erase all Secure Boot Settings" — the firmware is
bugged and that path doesn't reliably enter Setup Mode (see the [Framework
forum thread](https://community.frame.work/t/cant-enable-secure-boot-setup-mode/57683/5)).
Instead, in the BIOS:

1. Select **Administer Secure Boot**.
2. For each of **PK Options**, **KEK Options**, and **DB Options**:
   - Select **Delete \***.
   - For each entry inside, press Enter and confirm **Delete this signature**.
3. Press F10 to save and exit, reboot back into NixOS, then re-run the
   `sbctl enroll-keys` command above.

## Step 6 — Enable Secure Boot in BIOS

Reboot into BIOS (F2) → **Administer Secure Boot** → enable **Enforce Secure
Boot**, save and exit (F10).

## Step 7 — Confirm

```bash
sudo sbctl status      # lanzaboote-aware view (Measured UKI flag)
bootctl status         # canonical upstream check
```

Expect `Secure Boot: enabled (user)` from `bootctl status`, and from `sbctl
status` confirm `Installed:	✓ sbctl is installed`, `Setup Mode:	✗ Disabled`,
and `Secure Boot:	✓ Enabled`.

---

## Optional — TPM auto-unlock for LUKS

With Secure Boot measuring the boot chain, you can enroll the LUKS passphrase into
the TPM2 so the disk unlocks automatically **only when the boot chain is intact**;
the passphrase remains a fallback. The 7040 Framework has a TPM2.

```bash
# Find the LUKS partition (the cryptsystem container, e.g. /dev/nvme0n1p2)
lsblk

# Enroll against PCRs 0+7 (firmware + secure-boot state)
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p2
```

Add to `hardware-configuration.nix` on the LUKS device entry:
```nix
boot.initrd.luks.devices."luks-<uuid>".crypttabExtraOpts = [ "tpm2-device=auto" ];
```

Caveat: any change to the signed boot chain (kernel update, firmware update)
re-measures the PCRs and invalidates the TPM binding — you fall back to the
passphrase and re-enroll. This is expected behavior, not a failure.

---

## If it breaks (recovery)

1. Boot the NixOS live USB.
2. Unlock + mount the encrypted system:
   ```bash
   cryptsetup open /dev/nvme0n1p2 cryptsystem
   vgchange -ay
   mount /dev/vg/root /mnt
   mount /dev/nvme0n1p1 /mnt/boot
   ```
3. In BIOS, disable Secure Boot (and/or clear keys) to get back to a bootable
   state, or `nixos-enter` and roll back the generation.

Secure Boot here protects the boot chain against evil-maid tampering and boot-time
persistence. It is **not** a substitute for the LUKS encryption, which is what
actually protects data at rest. Run both; treat Secure Boot as hardening on top of
encryption, not instead of it.
