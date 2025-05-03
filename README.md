# Breakout

A wholly original project

## Rough Plan
- draw_frame will take an array of vertex data and an array of indices defining the coloured quads to draw, expect these to be relatively small, so planning to keep them in host visible memory and just write updated values to them each frame
- once we can draw multiple positioned quads on the screen, write the game logic
    - blocks created at top of screen, paddle and ball at bottom
    - paddle moves left and right on key presses
    - ball has some non-zero velocity, updates position each frame
    - ball bounces off walls, paddle, and blocks
    - ball breaks blocks on collision
    - don't worry about win/lose condition yet, just bounce off the floor for now, same as ceiling
- function to convert game state -> vertex & index arrays to pass to draw_frame, and I think we should have a working game!

## Choices
- To make it possible to draw quads of different sizes, I'm going to send 4 vertices per quad. If we made the quads fixed sizes, we could just send the positions and work out the vertices in the vertex shader, but it sounds like that will make other things more complicated (like mapping textures to quads), and I don't think we should have any performance issues given how little data we'll be transferring anyway

## Unknowns
- initial simple plan, all sizes and positions will be on the scale [-1, 1] so they map trivially to screen coordinates, might want to think about defining separate world coordinates and mapping to screen coordinates so that we end up rendering at a sensible aspect ratio
- if we want to add a win/lose condition, we probably also need some UI with useful buttons, which probably want to have some text on them, not thought about how to do this nicely at all
- sounds would be nice, but also got no idea how to do this yet
- my renderer experiment just ran as fast as possible, would be interesting to do that at first to see what frame rate we get, but guessing it might be really variable, depending on how things like how well the cache is being used / branch prediction misses? Maybe not an issue for such a simple game? Might be worth thinking about pinning to a fixed refresh rate?
