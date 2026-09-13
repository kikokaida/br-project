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

5. Runtime/test attempt: https://github.com/kikokaida/br-project/actions/runs/34774349378
   Both executables were packaged. Recorder tests passed 4/4; upstream tests had
   106 passes and 473 failures. Many failures showed allocator errors at exit.
   Disabled enabled()/boundary/phase/session queries constructed heap-owning State.
   Keep the opt-in flag independent and construct State only for an enabled
   session. This disabled-path fix is verified separately from the Windows
   allocator investigation. A regression reproduces two
   disabled allocations before the fix and zero afterward. Recording scopes,
   categories, Python detail, hot lists, reconciliation and spike capture remain.
   Also fetch the four stock add-ons at their exact upstream gitlinks; missing
   submodule contents caused add-on-load warnings in the installed runtime.

6. Allocator failure stack: https://github.com/kikokaida/br-project/actions/runs/34782270513
   node_system_exit freed scope1/2/3 with an allocator different from the one used
   by their global initializers before main. Initialize them in node_system_init,
   after allocator selection, and reset the pointers on shutdown so subsequent
   test-suite initialization is valid. Deferred node-type destruction is preserved.
   These are upstream lifetime fixes; no node evaluation or rendering changes.
7. Retained runtime investigation: https://github.com/kikokaida/br-project/actions/runs/34781791171
   The player help command reached WM_jobs_kill_all with no window manager.
   Handle a standalone -h request before initializing engine subsystems. The
   normal game launch and shutdown paths are unchanged.
8. The exact upstream Unicode asset-catalog test fixture contains unresolved
   merge markers around two identical copies. Keep one identical catalog to
   restore the existing test input. This is test data, not a project asset.
   Enable Python UTF-8 mode only in CI to write reports for Unicode fixture names.
9. Package all runtime files and benchmark tools with explicit relative ZIP
   entries. Exclude optional PDB symbols and preserve the complete engine layout.
   Transfer chunks fit the authenticated artifact tool's 512 MiB limit; verify
   chunk hashes and the whole ZIP hash after reassembly.

The original diagnostic ZIP and patch remain byte-for-byte unchanged. Both jobs
verify all 56 original hashes, apply the reviewed supplemental patch, then verify
all effective diagnostic and reviewed baseline-fix hashes before compiling. Logs contain
both manifests, SOURCE_VERIFICATION.json, and Build-Fixes.patch.

- Source: b1b35c48872b32c8bd4134f0cba759224b40f8df
- Windows dependencies: 854341cfd7e21b2cc45c7f8edbf19543cb51519c
- Original patch SHA256: 3d4b39ceb54abb37f5ef7d86bf67de86f24cdc0c8cfcc8198a53db9d97c94264
- Supplemental fixes SHA256: 0efc4cb0a15284b39509ba491d9638677a34f71a2d33e3a62b5c2c8c5726cf54

Actual runner: Windows Server 2022 x64, Visual Studio 2022 17.14.39, MSVC
19.44.35228.0, Windows SDK 10.0.26100.0, and pinned Python 3.11.13.
The first runner reported about 16 GiB RAM and 147 GiB free on its workspace
drive. No repository visibility or billing settings were changed.

The full workflow triggers for its own workflow, the supplied ZIP, and
phase1-ci/** changes on main, or manual dispatch. The recorder workflow also
triggers for phase1-tests/** and its own workflow. Both use windows-2022 and
read-only job tokens. Game content is unchanged. Enabled profiler behavior is preserved; disabled initialization avoids heap allocation.
Gameplay and FPS require the user's existing v0.2.19 project on their PC.
