# Phase 1 Windows build fixes

The following actual Windows failures were diagnosed:

1. Full engine attempt: https://github.com/kikokaida/br-project/actions/runs/34765633735
   CMake rejected backslashes in LIBDIR as an invalid character escape. Normalize
   that one build-script variable to forward slashes.
2. Recorder attempt: https://github.com/kikokaida/br-project/actions/runs/34766061964
   MSVC reported std::to_string was undeclared. Add the required standard
   <string> include to br1_diagnostics.cc. No executable statements change.

3. Full engine compiler attempt: https://github.com/kikokaida/br-project/actions/runs/34766460753
   MSVC could not find the profiler adapter header in bpy_app_handlers.cc,
   bpy_app_timers.cc and bpy_msgbus.cc. Use the existing relative generic-header
   convention. bpy_driver.cc also guarded its profiler header with WITH_PYTHON,
   which bf_python does not define; include it unconditionally in this Python-only
   translation unit. All instrumentation scopes and executable statements remain.

4. Full engine packaging attempt: https://github.com/kikokaida/br-project/actions/runs/34770560128
   Both blender.exe and blenderplayer.exe compiled and linked successfully. The
   pinned player CMake rules install the player only on Apple, so the Windows
   install was missing blenderplayer.exe. Copy the same-build player (and its PDB
   when present) beside the installed Blender executable and shared runtime.
   Preserve JUnit test results and run installed executable startup checks.

The original diagnostic ZIP and patch remain byte-for-byte unchanged. Both jobs
verify all 56 original hashes, apply the reviewed supplemental patch, then verify
all 56 effective hashes against expected values before compiling. Logs contain
both manifests, SOURCE_VERIFICATION.json, and Build-Fixes.patch.

- Source: b1b35c48872b32c8bd4134f0cba759224b40f8df
- Windows dependencies: 854341cfd7e21b2cc45c7f8edbf19543cb51519c
- Original patch SHA256: 3d4b39ceb54abb37f5ef7d86bf67de86f24cdc0c8cfcc8198a53db9d97c94264
- Supplemental fixes SHA256: a719a5ea3a9645724a23e44e980a340ff8a6f470ed88691526216a0c62987897

Actual runner: Windows Server 2022 x64, Visual Studio 2022 17.14.39, MSVC
19.44.35228.0, Windows SDK 10.0.26100.0, and pinned Python 3.11.13.
The first runner reported about 16 GiB RAM and 147 GiB free on its workspace
drive. No repository visibility or billing settings were changed.

The full workflow triggers for its own workflow, the supplied ZIP, and
phase1-ci/** changes on main, or manual dispatch. The recorder workflow also
triggers for phase1-tests/** and its own workflow. Both use windows-2022 and
read-only job tokens. Game content and profiler behavior are unchanged.
Gameplay and FPS require the user's existing v0.2.19 project on their PC.
