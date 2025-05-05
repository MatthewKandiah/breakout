# Breakout

A wholly original project

## TODO
- pick out different textures for the ball, blocks, and paddle. Assemble them into a single sprite sheet and give the quads the appropriate uv coordinates to render them properly

## Unknowns
- initial simple plan, all sizes and positions will be on the scale [-1, 1] so they map trivially to screen coordinates, might want to think about defining separate world coordinates and mapping to screen coordinates so that we end up rendering at a sensible aspect ratio
- if we want to add a win/lose condition, we probably also need some UI with useful buttons, which probably want to have some text on them, not thought about how to do this nicely at all
