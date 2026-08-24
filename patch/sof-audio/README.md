# SOF DSP suspend/resume panic — self-disabling compatibility fix

| | |
|---|---|
| Status | **merged upstream and released in Linux 7.2.** Obsolete there and on 7.1.10 |
| Applies to | 7.1.9 and older in the 7.1 series, and anything before 7.2 |

**This fix is preventive.** The bug it addresses never reproduced on the unit
this repo was developed on. It is shipped because the upstream fix is small and
clean and the trigger is workload-dependent, so it may surface later.

On a kernel that already carries it the installer is a no-op. See
[upstream status](#upstream-status) at the bottom.

## The upstream bug

On Intel SOF platforms including Panther Lake, the IPC4 `ipc_config_data`
buffer for copier widgets is built once during `ipc_prepare` and cached. On
suspend/resume the host and link DMA streams are released and re-allocated,
potentially with different stream tags — but because the widget list persists
across suspend, `sof_pcm_hw_params` skips `sof_pcm_setup_connected_widgets` and
`ipc_prepare` never runs again.

The stale cached payload is then sent to firmware carrying boot-time DMA
channel assignments, which collide with the newly allocated ones. Result: DMA
channel conflict, firmware panic, dead audio until reboot.

Documented upstream as
[thesofproject/sof#10700](https://github.com/thesofproject/sof/issues/10700),
*"Dell XPS 14 DA14260 (Panther Lake, `1028:0db9`): DSP error when
unsuspending"*. The fix is Peter Ujfalusi's copier-payload refresh,
[thesofproject/linux PR #5762](https://github.com/thesofproject/linux/pull/5762)
— one file, refreshing the payload before widget setup.

## Why it is here despite not reproducing

An earlier session in this repo believed a DSP panic was the cause of the
mic-mute problem. **That was wrong**, and the record is corrected here to save
anyone the same detour:

- The real cause of the mic-mute symptom is the EC firmware — see
  [`../micmute/`](../micmute/).
- The diagnostic that appeared to show DSP panics was counting *every*
  `fw_state` transition, which includes ordinary runtime-PM D3 entries. Those
  are normal power management, not crashes.
- A direct test — `pavucontrol` open, `rtcwake -m mem -s 8` three times —
  produced **zero** `DSP panic!` entries, and the six boots in the local
  journal contain zero as well.

So the backport stays as insurance only. Whether the upstream race triggers
depends on application behaviour (which PipeWire version, whether streams are
open at the moment of suspend), so a clean run today is not proof it cannot
happen.

## Installing

```sh
sudo bash patch/sof-audio/install.sh
```

Fetches the running kernel's `sound/soc/sof` tree from the upstream stable
tree, applies the patch, builds `snd-sof.ko` out-of-tree, and drops it into the
modules `updates/` overlay so it loads instead of the in-tree module.

Re-run after every kernel update. Becomes unnecessary once the fix reaches the
kernel you run — at that point delete the overlay and this directory.

## Surviving kernel updates

`snd-sof.ko` goes into the `updates/` overlay, so a kernel update does not
overwrite it, but a new kernel starts without one. The pacman hook in
[`../auto-rebuild/`](../auto-rebuild/) rebuilds it automatically.

The source list is read from `sound/soc/sof/` in the matching kernel tag rather
than hardcoded, because that directory's contents drift between versions. The
patch itself was rebased against v7.1.5 on 2026-08-01; if a future kernel moves
the code it targets, `install.sh` exits with code `3` and the hook reports the
fix as *not applicable* rather than failing.

---

## Upstream status

Merged, released, done.

* PR [#5762](https://github.com/thesofproject/linux/pull/5762) "ASoC: SOF:
  ipc4-topology: Refresh copier IPC payload before widget setup" was merged into
  `topic/sof-dev` on 2026-06-10 as commit
  `5967a530be5ee77c4b1ea00b2cbb0e09204e918d` — the sha in this directory's
  patch header.
* It reached mainline and **shipped in Linux 7.2**.
* The 7.1 series gets it in **7.1.10**, alongside the `atkbd` quirk.

So on 7.2, or 7.1.10 and later, there is nothing here to install. The installer
detects the fix in the source tree and skips the rebuild.

Two things that are easy to misread:

* **thesofproject/sof issue 10700 is still OPEN** despite the fix having
  shipped. Upstream leaves it open pending confirmation from reporters. Do not
  read that as "unfixed".
* **The reporting machine is a Dell XPS 14, not a HONOR.** The bug is a Panther
  Lake SOF issue, not a HONOR one — which is also why this repository never
  reproduced it, and why the fix stays labelled preventive rather than
  "verified here".
