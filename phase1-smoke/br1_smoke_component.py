"""Synthetic CI fixture only; it never loads or edits the BloodRayne project."""
import bge
from collections import OrderedDict
import json
import os
from pathlib import Path
import time


class Phase1Smoke(bge.types.KX_PythonComponent):
    args = OrderedDict()

    def start(self, args):
        self.frames_seen = 0

    def update(self):
        self.frames_seen += 1
        # Deliberate synthetic spike to exercise the shipped spike report.
        if self.frames_seen == 6:
            time.sleep(0.06)
        if self.frames_seen >= 12:
            destination = Path(os.environ['BR1_SMOKE_RESULT_DIR']) / 'COMPONENT.json'
            destination.write_text(json.dumps({'status': 'PASS', 'updates': self.frames_seen,
                                               'object': self.object.name,
                                               'synthetic_spike_seconds': 0.06}), encoding='utf-8')
            bge.logic.endGame()
