# Aseprite-Scripts-by-pepe
Custom LUA scripts for Aseprite. Feel free to use!

## How to Use
Download the Lua file and copy it to the Aseprite scripts folder.

## add_easing_animation
- Select **multiple cels in the same layer** and run the script. Animations for the intermediate cels will be generated based on the position of the images in the first and last cels.
- The transformations are based on **the top-left corner** rather than the center of the image.
- When moving, if the Bézier curve option is not checked, the movement will be along a straight line; if checked, it will move along a curve. If the movement range of Bezier curve control points too limited, 
  try expanding the canvas size.
- The faster the speed, the closer the trail length is to the maximum trail length.
- Path previews and trail may not render correctly in indexed mode.

## circular_shift
- Select **multiple cels in the same layer** and run the script. The selected cels will be shifted forward or backward while maintaining the loop.
