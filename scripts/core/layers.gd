extends RefCounted
## Physics layer bit masks shared by every system.

const WORLD := 1
const PLAYER := 2
const ENEMY := 4
const DEBRIS := 8
const SHOTS := WORLD | PLAYER | ENEMY
## Bullet-only zones around humanoid infected (wide enough for reaching arms);
## nothing moves or collides on this layer.
const HITZONE := 16
