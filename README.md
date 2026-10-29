# Rust OS manifest

The [`repo`](https://gerrit.googlesource.com/git-repo) manifest for Rust OS:
every repository it is built from, checked out where the build expects it.

| file | what |
|---|---|
| `default.xml` | the manifest: `aosp.xml` and Rust OS's repositories |
| `aosp.xml` | the AOSP projects Rust OS's Android is built from (528 of `android17-release`'s 1,084), pinned |
| `sparse/` | for each big AOSP prebuilt, the directories the build reads |
| `patches/` | Rust OS's changes to AOSP projects (`build_soong` is `build/soong`) |
| `prepare.sh` | checks the tree out after `repo init` |
| `update.sh` | takes new AOSP pins from Rust OS's `android/tree/` |

## Getting the source

The repositories are private: git needs your GitHub login (`gh auth login`,
then `gh auth setup-git`).

```sh
mkdir rustos-src && cd rustos-src
repo init -u https://github.com/Pengust/manifest --depth=1 \
	--partial-clone --clone-filter=blob:none
.repo/manifests/prepare.sh
```

`prepare.sh` syncs, checks the big prebuilts out sparsely, applies the
patches to AOSP, and hides `rustos/` from AOSP's build. Run it again to
update. The clones are partial: git downloads only files that get checked
out.

```
.                                  AOSP
rustos/envsetup.sh                 the build environment
rustos/os                          the base OS (rustos)
rustos/os/android                  Android on Rust OS (android)
rustos/os/apps/<app>               apps_settings, apps_phone, apps_messages, apps_modem, apps_notifyd
rustos/devices/pc                  device_generic_pc
rustos/devices/nothing_phone2      device_nothing_phone2
rustos/kernels/nothing_pong        kernel_nothing_pong-rustos
rustos/external/android_translation_layer
```

## Building

```sh
. rustos/envsetup.sh
lunch                              # the devices
lunch nothing_phone2-userdebug
m
```

`m` builds the kernel, Android, the shell and apps, Rust OS and the root
filesystem image into `rustos/os/out/<device>`. Rust OS's
[docs/build.md](https://github.com/Pengust/rustos/blob/main/docs/build.md)
has the targets and what each needs from the build machine.

## Updating the AOSP pins

After moving to a new AOSP release, build once in a complete AOSP checkout,
run `android/tree/lean.sh` there, then here:

```sh
./update.sh path/to/rustos/os
git commit -a
```
