# Changelog

## 0.2.1

- Features:
  - Support multiple editor viewports
- Bugfixes:
  - Fix translation along local axis is affected by node's scale
  - Fix cant translate with 2 axis constraint when position of objects are too lower from world origin

## 0.2.0

- Features:
  - Support pressing SHIFT for precision mode
  - Support xx/yy/zz to toggle between global/local mode
  - Support infinite mouse movement
  - Support switching display mode with "Z" key
- Improves:
  - Enhance mouse translaiton in local mode
  - Add shadow to overlay label
- Bugfixes:
  - Fix can't transform in Right orthogonal view
  - Fix rotation offset is not relative to initial mouse position
  - Fix translation often has a big offset after setting constraint axis
  - Fix axis drawn are incorrect when there's rotation in root node
  - Fix can't transform when pivot point behind editor camera
  - Fix start_session proceed even when no selected node
  - Fix output printing axis Vector3 must be normallized when rotation in some direction under orthogonal view
  - Fix EditorSetting doesn't have selection_box_color in older version

## 0.1.0

- Features:
  - Transform with "G", "R", "S" keys and "H" key to hide
  - Revert transformation with "ALT" modifier
  - Visualize constraint axis
  - Work seamlessly with Godot Spatial Editor settings("Use Local Space", "Use Snap", "Snap Settings")
  - Type transform value
