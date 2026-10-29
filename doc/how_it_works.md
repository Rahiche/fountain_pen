# How it works

## Hands

A hand (`PenHand`) holds every character's strokes as centre lines, in the order a hand draws them. They're traced from
a font's outlines:
1. Each glyph is thinned to its centre line and cut into a graph.
2. The graph is walked the way a pen would go, carrying on through each fork along the smoothest way.
3. Small detached parts, like an i's dot, wait until the word is written.

To trace a font of your own, see [Trace your own hand](../tool/trace/README.md).

## The pen

`PenWriting` draws those lines with a nib, not with the font's own outlines:

- **Width:** the line is broad going down and fine coming up, and broader again across the nib's edge.
- **Timing:** the pen moves as a hand does, by the two-thirds power law. It's quick along the straights and slower
  round the tight turns, its speed falling as the curvature to the −1/3. It sets off from rest and comes back to it at
  each stroke's ends. [tool/eval](../tool/eval/README.md) measures it.
- **Ink:** it feathers into the paper, dries darker at its edges, and catches the light while it's wet. It pools a
  little where the pen lands.
- **Variation:** each letter is a little turned, sized, lifted and spaced its own way. The line wanders and the hand
  wavers, all from the `seed`.

## Limits

- Characters a hand has no strokes for are left as spaces.
- In Latin, letters connect only where the font's own strokes meet; strokes aren't joined across letters.
