# Phase 1 Windows runtime investigation

Replays the retained outputs of engine run 34774349378 to capture the native
call stacks for the player help-command crash and guarded-allocator failures.
This workflow does not rebuild or modify the retained executables or game files.
Its token only reads repository contents and Actions artifacts.

Microsoft documents CDB as part of Debugging Tools for Windows:
https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/debugger-download-tools
