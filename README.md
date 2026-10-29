# Rust OS source manifest

One [`repo`](https://gerrit.googlesource.com/git-repo) checkout with
everything needed to build Rust OS for the Nothing Phone (2) from source:

- Rust OS itself
- the phone's device repository and mainline kernel
- the AOSP projects that Rust OS's Android is built from

The AOSP part is lean. It keeps 528 of the 1,084 projects in
`android17-release`: only the projects the build actually reads, each pinned
to the exact revision Rust OS builds. Projects are cloned without history.
For the big prebuilts (Clang, the SDK, Rust and others), only the
directories the build uses are checked out.

| file | what |
|---|---|
| `default.xml` | the manifest: `aosp.xml` plus the Rust OS repositories |
| `aosp.xml` | the AOSP projects, pinned |
| `sparse/` | for each big prebuilt project, the directories to check out |
| `patches/` | Rust OS's changes to AOSP projects (`build_soong` is `build/soong`) |
| `prepare.sh` | checks the tree out: sync, sparse checkouts, patches |
| `update.sh` | takes new pins from a Rust OS checkout (see [Updating](#updating)) |

After syncing, the tree has AOSP at its usual paths, with Rust OS under
`rustos/`:

```
rustos/os                       Rust OS (Pengust/rustos)
rustos/devices/nothing_phone2   device repository (Pengust/device_nothing_phone2)
rustos/kernels/nothing_pong     kernel (Pengust/kernel_nothing_pong-rustos, rustos-7.2-full)
```

AOSP's build system (Soong) must not see `rustos/`: the Android build copies
the products from there into `device/`, so Soong would find every module
twice. `prepare.sh` puts a `.find-ignore` file in `rustos/` so Soong skips it.

## 1. Set up the build machine

You need a Linux x86-64 host that meets AOSP's own requirements: 64 GB of
RAM or more, and plenty of disk. The checkout is about 55 GB, and AOSP's
`out/` needs well over 100 GB on top of that.

Install these:

- `repo`, `git`, `python3` (3.11 or newer: the build scripts use `tomllib`),
  `rsync`, `zstd` and `cpio`
- the kernel build tools (`clang`/LLVM, `lld`, `bc`, `flex`, `bison`, and the
  `libssl` and `libelf` headers)
- Rust through rustup, plus the `aarch64-unknown-linux-musl` target and the
  `rust-src` component (Rust OS's static programs cross-build with musl)
- `meson` 1.4 or newer, with `mako` and `pyyaml`, to build Mesa

This repository is private, so git needs your GitHub login:

```sh
gh auth login
gh auth setup-git
```

## 2. Get the source

```sh
mkdir rustos-src && cd rustos-src
repo init -u https://github.com/Pengust/manifest --depth=1 \
	--partial-clone --clone-filter=blob:none
.repo/manifests/prepare.sh
```

The clones are partial, so git downloads only the files that get checked
out, and the parts of the prebuilts left out by `sparse/` are never
fetched. You can run `prepare.sh` again at any time. Patches that are
already applied are skipped.

The phone's GPU (Adreno 730) faults with the Mesa in AOSP (26.1), so the
build uses upstream Mesa 27, which isn't part of this manifest:

```sh
git clone https://gitlab.freedesktop.org/mesa/mesa.git ~/mesa
```

## 3. Prepare the phone

> Unlocking the bootloader **erases the phone**. Back up first.

Rust OS is RAM-booted with `fastboot boot`. Nothing is flashed to `boot`, so
stock Nothing OS stays on the phone and comes back on a normal reboot.

1. **Unlock the bootloader.** On Nothing OS, turn on Developer options and
   then OEM unlocking. Reboot to fastboot (Power + Volume down) and run:

   ```sh
   fastboot flashing unlock
   ```

2. **Clear the DTBO.** The bootloader applies the stock device-tree overlays
   to whatever kernel it boots, and they do not fit the mainline device tree.
   Flash an empty overlay image to slot a:

   ```sh
   system/libufdt/utils/src/mkdtboimg.py create empty-dtbo.img
   fastboot flash dtbo_a empty-dtbo.img
   ```

3. **Install the root filesystem.** For now, Rust OS still runs on a
   postmarketOS root filesystem, a disk image on `userdata`. Rust OS's
   initramfs, PID 1, services and shell are installed into it. Create it
   with [pmbootstrap](https://wiki.postmarketos.org/wiki/Pmbootstrap) for
   the device `nothing-pong`:

   ```sh
   pmbootstrap init                    # device: nothing-pong
   pmbootstrap install
   pmbootstrap flasher flash_rootfs
   ```

   Write down the root partition's ext4 UUID (`blkid` on the phone, label
   `pmOS_root`). The build needs it as `RUSTOS_ROOT_UUID`.

**Stay safe on this phone's bootloader:**

- Never run `fastboot set_active`. A `set_active` that gets cut off has left
  the phone unbootable until an EDL restore.
- Flash large images in chunks (`fastboot -S 64M flash ...`). If the USB link
  hangs, stop.
- If `fastboot boot` fails with "Load Error" for an image you know is good,
  run `fastboot reboot-bootloader` and try again.
- If the phone ends up in Qualcomm crash dump mode (USB `05c6:900e`), hold
  Power + Volume down until it restarts into fastboot.

## 4. Build

Run everything from the top of the checkout. Building Android also needs
Rust OS's Android pieces and the device's AOSP product, and `build.sh`
copies both into `device/`:

```sh
TOP=$PWD

# kernel
rustos/devices/nothing_phone2/hooks/build-kernel rustos/kernels/nothing_pong out-kernel

# Android: the system image and the phone's vendor partition
rustos/os/android/tree/build.sh . rustos/devices/nothing_phone2

# the GPU driver, and the Android tree to install
cd rustos/os
MESA_SRC=~/mesa android/mesa.sh "$TOP" out/mesa-pong freedreno -Dfreedreno-kmds=msm
android/package.sh "$TOP" out/android rustos_pong out/mesa-pong

# Rust OS: root filesystem files, initramfs and boot image
MKBOOTIMG=$TOP/system/tools/mkbootimg/mkbootimg.py \
KERNEL_OUT=$TOP/out-kernel ANDROID_TREE=out/android \
RUSTOS_USER=<your user> RUSTOS_ROOT_UUID=<root UUID> \
	scripts/build.sh ../devices/nothing_phone2
```

The output is in `rustos/os/out/nothing_phone2/`: `rootfs/`,
`initramfs.cpio.zst` and `boot.img`.

The compositor links against the phone's own Mesa, libinput and libseat, so
it is built on the phone (`scripts/build-compositor.sh`). Pass the result to
`build.sh` as `COMPOSITOR=`.

If `/etc/profile.d/Z97-rbe4.sh` exists, it sets up remote build execution,
and `build.sh` uses it for the Android build.

## 5. Install and boot

Install Rust OS into the root filesystem over USB networking. The phone has
to be running a system with ssh, either postmarketOS or an earlier Rust OS:

```sh
rustos/os/scripts/install.sh rustos/os/out/nothing_phone2 <user>@172.16.42.1
```

Then boot into Rust OS from fastboot:

```sh
fastboot boot rustos/os/out/nothing_phone2/boot.img
```

The phone comes up as `172.16.42.1` over USB. To get back to fastboot from
a running Rust OS, run `sudo svc bootloader`.

## Updating

After moving to a new AOSP release, do one full build in a complete AOSP
checkout, then run `android/tree/lean.sh` there (see Rust OS's
`android/README.md`) to make new pins. Then copy them here:

```sh
./update.sh path/to/rustos
git commit -a
```
