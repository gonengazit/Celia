This file details keybinds specifically for cctas, make sure to read the general tas keybinds [here](/README.md)

# Usage
`<path to your love executable> . cctas cartname.p8`

for a cart to be tasable by cctas it has to be generally based on celeste. (i.e. use the same general object system, objects list, player object, etc)

the functions for loading the level, and getting the level index (i.e. load\_room, level\_index()) must be based on vanilla celeste, smalleste, or new versions of evercore (v1.3+).

carts not based on these may or may not work. for a cart that uses a different scheme, it may be tased by defining the functions `__tas_load_level(idx)` and `__tas_level_index()`. These functions must be consistent with one another.

in addition, a table called `__tas_settings` may be defined, which may contain the following values
* `disable_loading_jank` - if set to true, don't apply loading jank on any level, and don't allow modifying it

# Keybinds
* __F__ - go to next level
* __S__ - go to previous level
* __Shift + D__ - rewind/fast forward to the first frame of control
* __Shift + G__ - record gif of entire level
* __U__ - save cleaned up version of the file - not containing frames after the end of the level (this requires the TAS to playback until the end of the level). can be interrupted by pressing any input
cctas files will be saved and loaded from the path `<love data folder>/Celia/<cartname>/TAS<level_index>.tas`
* __Shift + N__ - begin full game playback. the game will play from the start, and load the input file for every level it reaches. this can be interrupted by pressing any key.
* __Shift + = (+)__ - increase max\_djump by 1. by default, in vanilla based carts, max\_djump will be 1 before 2200, and 2 afterwards
* __-__ - decrease max\_djump by 1
* __=__ - restore max\_djump to default behaviour
* __A__ - enable loading jank offset mode
* __B__ - enable rng seeding mode
* __Y__ - print player position to console
* __Ctrl + C__ - copy player position to clipboard

## loading jank offset mode
By default, the amount of objects that have loading jank applied will depend on the amount of objects present on the previous level (not including room title).  This corresponds to offset 0. If, before exiting the previous level, this amount will change (or if levels in the mod are not ordered sequentially), you can modify the offset.

When entering loading jank offset mode, the level will be rewinded to the first frame. all objects which have loading jank applied, will be surrounded by gray boxes. on the bottom left, you can see the current loading jank offset. by pressing __Up__, you can increase the loading jank offset. this corrosponds to more objects existing in the previous room before exiting = less objects in the current room get loading jank applied. similarly, you can decrease the offset by pressing __Down__. after you're done with the changes, you can press __A__ again, and the level will be reloaded with the new offsets applied.

If this is gibberish to you, don't worry, loading jank doesn't matter in the vast majority of cases. if you get a desync in a cycle based mechanic (i.e. clouds, berries), when playing back a full tas, you can try messing with it.

## rng seeding mode
by default, the rng seed of balloons and chests can be modified. In the future, there will be an api to define rng seeds for other objects. In rng modification mode, the current object will be highlighted with an orange box, with its seed drawn below. you can cycle through the seedable objects by pressing __Left__ or __Right__. you can update the current object's seed by pressing __Up__ or __Down__. Note that the box may move, but the object will stay in place. due to a technical limitation, it will not be redrawn until the frame is advanced to (for example by rewinding then advancing to it).

Warning: rng seeding in the middle of a level can cause a desync if it affects previous parts of it.


