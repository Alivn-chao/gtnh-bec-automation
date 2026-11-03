# Remove the 64-nanite minimum in V2/V3 ME-IO mode

A nonempty cell can now supply a recipe if its nanite tier is sufficient. The physical display cap, exact quantity readback, IO conservation checks and interrupted-operation protections are unchanged.

Quit BEC normally with Q before running install.lua on OpenOS. The patch edits the installed module in place, preserving local aliases and physical hatch support. It saves the original as runtime/nanites_cell.lua.before-small-hive and leaves the production and IO journals intact.
