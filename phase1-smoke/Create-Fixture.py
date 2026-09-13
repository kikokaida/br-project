"""Create a new default-scene fixture with the pinned UPBGE component operator."""
import bpy
import json
import os
from pathlib import Path
import sys

root = Path(os.environ['BR1_SMOKE_FIXTURE_DIR'])
print('BR1_FIXTURE_STAGE: Python script started', flush=True)
sys.path.insert(0, str(root))
cube = bpy.data.objects['Cube']
cube.name = 'BR1_SmokeCube'
bpy.context.view_layer.objects.active = cube
cube.select_set(True)
bpy.data.texts.load(str(root / 'br1_smoke_component.py'))
print('BR1_FIXTURE_STAGE: registering component', flush=True)
result = bpy.ops.logic.python_component_register(component_name='br1_smoke_component.Phase1Smoke')
print('BR1_FIXTURE_STAGE: component registered', result, flush=True)
assert result == {'FINISHED'}, result
assert len(cube.game.components) == 1
assert bpy.context.scene.camera is not None
destination = root / 'BR1_Phase1_Smoke.blend'
assert not destination.exists(), 'Refusing to replace an existing fixture'
bpy.ops.wm.save_as_mainfile(filepath=str(destination), check_existing=False)
print('BR1_FIXTURE', json.dumps({'status': 'PASS', 'file': str(destination),
                                 'components': len(cube.game.components),
                                 'render_engine': bpy.context.scene.render.engine}))
