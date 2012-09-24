-- $Id$

function widget:GetInfo()
  return {
    name      = "UDefid",
    desc      = "as above",
    author    = "nixtux",
    date      = "Sep 24, 2012",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = true  --  loaded by default?
  }
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

local uDefs = UnitDefs

function widget:UnitCreated(unitID, unitDefID, unitTeam)
      local uDef = uDefs[unitDefID]
      Spring.Echo("Unitname:-  " .. uDef.name .. "     UnitdefID:-  " .. unitDefID)
end