# NH_GameFixes

A Metamod:Source plugin that bundles a set of CS2 server fixes. This is the NovaHunters fork of
[SlynxCZ/GameFixes_mm](https://github.com/SlynxCZ/GameFixes_mm), kept working on current CS2 builds.

Repo: [github.com/NovaHunterZ/GameFixes_mm](https://github.com/NovaHunterZ/GameFixes_mm)

## Why the fork, and why the new name

The original author archived GameFixes_mm on 2026-10-30 and moved the fixes to a different framework
(Source2Mod, as `GameFixes_s2m`). The last Metamod release, v1.0.18, stopped working with the CS2 update of
2026-11-11. We run plain Metamod and wanted to keep these fixes, so we picked the project up ourselves.

We call it **NH_GameFixes** so nobody mixes it up with the original:

* the original `GameFixes_mm` is archived and its releases no longer work on current CS2;
* `GameFixes_s2m` is the author's own successor, but it needs Source2Mod;
* this one is neither of those, and bug reports for it belong here, not with the original author.

Our versions carry an `-nh` suffix (`v1.0.20-nh`) for the same reason.

What did **not** change: the fixes, the `game_fixes.ini` config, the install paths
(`addons/game_fixes/...`) and the `IGameFixes001` interface. It is a drop-in replacement for v1.0.18.
The license is still GPLv3 and the original author keeps full credit for his work.

**One Metamod:Source plugin for the CS2 server fixes that used to be five separate ones (BeamCrashFix, DemoRecordFix, HammerIdFix, SlowAnimationFix, WorkshopVoiceFix), the GC-ban whitelist that used to live in FUNPLAY Core, and a few more (team limit, input activator crash, sv_cheats noclip, server list players).** Every fix is toggled in `game_fixes.ini`.

---

## Fixes

| Block | What it fixes |
|---|---|
| `beam_crash` | `CBeam::SetBeamOrigin` / `SetBeamEndPos` loop forever on a beam without a parent, crashing the server. The unparented path is reimplemented. |
| `demo_record` | With `tv_enable 1`, the GOTV client is never disconnected and gets a slot on top of the session's maxplayers, so demo recording survives match restarts on the same map. |
| `hammer_id` | `SetSchemaHammerUniqueId` skips `m_sUniqueHammerID` behind a `jnz`; patched to `jmp` so every entity gets its id. |
| `slow_animation` | `curtime` is a 32-bit float and loses precision after a day or two on one map (sluggish animations, movement, lag compensation). While the server is empty at a check, the map is reloaded; the remaining `mp_timelimit` is carried over. `reload_interval` sets the check period in seconds. |
| `workshop_voice` | Clients key voice playback off the `xuid` in `svc_VoiceData`; on workshop maps it doesn't identify the speaker uniquely, streams collide and players stop hearing each other. Every speaker gets a distinct xuid per listener, rewritten in place in `CServerSideClient::SendNetMessage` (once per recipient). Seeds reset on every map change. |
| `steam_ban` | The engine's per-frame GC ban / competitive cooldown kick pass (`GameSystem_Think_CheckSteamBan`, hooked by signature). Accounts in `whitelist` (SteamID64s) are stripped out before it runs, so are competitive cooldowns while `sv_kick_players_with_cooldown` is below 2, and with `clear_after_pass` whatever it leaves behind is cleared so a stale entry can't hit the next player to join. Other plugins allow accounts at runtime through `IGameFixes` (below); an account nobody allowed yet is held for `hold_seconds` before the pass may kick it. |
| `team_limit` | `CCSGameRules`' max T/CT counts and enabled spawn point counts are kept at maxplayers every frame, so a join is never refused because a team is "full", also on maps with few spawns. |
| `input_activator_crash` | `CBaseFilter::InputTestActivator` dereferences the input's activator unchecked; a `TestActivator` fired with none crashes the server. Those calls are dropped. |
| `sv_cheats` | Turning `sv_cheats` off leaves anyone in noclip flying. Every such pawn goes back to `MOVETYPE_WALK` the moment the cvar flips to 0. |
| `rampbug` | Surf ramps: a movement trace that stops short of a ramp or lands on its edge feeds `TryPlayerMove` a plane the player never hit, and they are flung off. The traces are redone from a small offset along the last valid plane and, with `tryplayermove_override` (off by default, the game has its own mitigation now), a bad result is put back (CS2KZ's fix, via CS2Fixes-RampbugFix). What a player was on is forgotten on a teleport. Lessens rampbugs, does not end them. |
| `water_jump` | Touching the bottom of a body of water, the `CategorizePosition` after `WaterMove` counts the player as standing on it and a jump out of the water no longer takes. That one call is skipped. |
| `voice_flood` | Malformed (`clc_VoiceData` with no audio, a sender other than the client, an unknown format, packets with no data) or oversized voice messages -- over 16 KiB or 64 packets -- are dropped in `CServerSideClient::ProcessVoiceData` before the engine handles them, and every client is held to 192 messages, 256 KiB and 1024 packets per second. Nobody is kicked. |
| `server_list_players` | Pushes every connected player's SteamID, name and score to the Steam game server API every `update_interval` seconds, so the server browser lists the players. Port of [Source2ZE/ServerListPlayersFix](https://github.com/Source2ZE/ServerListPlayersFix). |

A fix that fails to find what it needs (a signature, a vtable) is logged and left off; the rest of the plugin still loads.

## Configuration

`addons/game_fixes/game_fixes.ini` -- one block per fix, `"enable" "1"` turns it on, a missing block counts as off. Extra options live in the same block:

```
"slow_animation"
{
	"enable"			"1"
	"reload_interval"	"1800"
}

"steam_ban"
{
	"enable"	"1"
	"clear_after_pass"	"1"
	"hold_seconds"	"15"
	"whitelist"
	{
		"Slynx"	"76561198000000000"
	}
}
```

## Interface for other plugins

`public/IGameFixes.h` (`IGameFixes001`), through metamod:

```cpp
IGameFixes* pGameFixes = static_cast<IGameFixes*>(g_SMAPI->MetaFactory(GAMEFIXES_INTERFACE_VERSION, nullptr, nullptr));
pGameFixes->SteamBanAllowAccount(steamId64);    // steam_ban leaves the account alone
pGameFixes->SteamBanDisallowAccount(steamId64);
```

A call to a fix that is off does nothing and returns false.

## Layout

```
public/
  IGameFixes.h      what other plugins can call
src/
  plugin.*          metamod glue: interfaces, ini, the shared GameFrame/StartupServer hooks
  scheduler.*       timers + next-frame queue, ticked from GameFrame
  utils.hpp         WIN_LINUX and WriteCode, the one code-byte patch (on DynLibUtils)
  vprof.hpp         GF_VPROF, the profiler scope every hook handler and timer callback opens
  fixes/fix.h       the CFix interface every fix implements
  fixes/<name>.*    one fix per file pair
  sdk/              schema field access and the few SDK classes the fixes touch
```

Hooks go through KHook, metamod's own detour library (`third_party/khook` in metamod-source, handed to the plugin by `PLUGIN_SAVEVARS()`), so they share one detour backend with every other plugin. Signature scanning and vtable lookup use `vendor/dynlibutils`.

Every handler shows up in the engine's profiler as `GameFixes::<fix>::<function>`, under the `GameFixes` budget group: `vprof_on`, let it run, `vprof_generate_report`, `vprof_off` (the commands are development-only, so something has to unlock them first).

## Building

Linux, no docker needed -- only `git`, `curl` and `bwrap` (the `bubblewrap` package):

```
./build.sh             # first run fetches the SDKs and the build runtime into .deps/ (about 4 GB)
./build.sh --update    # pull the newest s2sdk / metamod-source first, then build
```

The result is `dist/addons/` (copy it into `game/csgo/`) and `dist/NH_GameFixes_<version>-linux.tar.gz`.
The compile runs inside Valve's Steam Runtime 3 "sniper" SDK with its gcc-14, the compiler the game's own
`libtier0.so` is built with, so the binary runs wherever the game does.

**After a CS2 update that breaks the plugin**, `./build.sh --update` is the first thing to try: most
breakages are engine classes whose layout changed, and [s2sdk](https://github.com/alliedmodders/s2sdk)
follows those within a day or two. If it then fails to compile, the SDK renamed or removed something the
plugin uses and the source needs a matching edit; if a fix logs `NOT loaded -- ... not found` at server
start, its byte signature in `src/fixes/<name>.cpp` has to be found again (cs2kz-metamod and CS2Fixes keep
theirs current and share most of them).

The original CMake / AMBuild / docker files are still in the tree (`S2SDK` and `MMSOURCE_DEV` in the
environment, then `cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build`); only
`build.sh` is what this fork is built and checked with. The Windows build is untouched and untested here.

## Changes in this fork

* **v1.0.19-nh** -- CS2 14197 (2026-11-11) changed the engine's network message classes; the v1.0.18
  binary calls virtuals that no longer exist. Rebuilt against the updated s2sdk: `workshop_voice` reads
  the message info straight off the message (`INetworkMessageInternal` is gone) and the local copy of the
  typed message wrappers was dropped. Every Linux signature was compared with projects updated after that
  game update (the author's own successor plugin, Source2Mod's gamedata, cs2kz-metamod): all unchanged.
  DynLibUtils is vendored in `vendor/` instead of being a submodule, and `build.sh` and
  `tools/check_signatures.py` were added. `meta list` shows the plugin as "NH Game Fixes".

* **v1.0.20-nh** -- timer fix: the plugin's clock jumped ahead on the first game frame, so every timer
  fired once right at server start. In practice `slow_animation` reloaded the map a couple of seconds
  after boot instead of waiting for `reload_interval`. This bug was in the original too.

## Requirements

* Metamod:Source (CS2)

## Author

Original plugin: Slynx (˙·٠● S l y n x ●٠·˙), [https://slynxdev.cz](https://slynxdev.cz)
This fork: NovaHunters, [github.com/NovaHunterZ/GameFixes_mm](https://github.com/NovaHunterZ/GameFixes_mm)
