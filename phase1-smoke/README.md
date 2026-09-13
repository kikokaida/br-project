# Actual player and recorder smoke test

This separate workflow retrieves the exact packaged engine from run 34782679996,
verifies its transfer and executable hashes, and creates a new default-scene
fixture in a temporary runner directory. It does not access a BloodRayne project.

The fixture contains one Python component that ends the game after 12 updates.
It deliberately pauses for 60 ms on one update to exercise spike capture. The
workflow attempts both disabled and full profiling, then uses the shipped report
tool to verify the real engine trace and component/object hot lists.

A missing graphics context is reported with the actual player output. It is not
a successful rendering test. No graphics driver, renderer replacement, or game
configuration change is installed to make this optional hosted-runner test pass.

These synthetic timings must not be compared with the user's 22.5 FPS baseline.
