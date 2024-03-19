RNGFIX entirely made by justa, has working telefix (unlike the other repo) and seems to be generally more consistent with height given & speed taken from slopes. Also only works with Garrysbhop/PG gamemode but with some slight tweaks works for any bhop gamemode.

# Installation
Drop rngfix folder into /garrysmod/addons
Drop ent_trigger into /lua/entities


# Other gamemodes
To get this rngfix to work with other gamemodes all you have to do is go to line 108 on sh_rngfix.lua and replace ply.style with whatever your gamemode uses to get the players style, and the style it should be looking for is sideways.
