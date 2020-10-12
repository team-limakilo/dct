--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- IAgent<StaticAsset>
--
--]]

local class = require("libs.class")
local StaticAsset = require("dct.assets.StaticAsset")
local Logger = require("dct.utils.Logger").getByName("Asset")

local IAgent = class(StaticAsset)
function IAgent:__init(template, region)
	self.__clsname = "IAgent"
	StaticAsset.__init(self, template, region)
end

### Issue:
 1. How to genericly handle sending DCS AI commands at the asset level?

AssetBase -> StaticAsset -> MovableAssets

Idealy the Asset class would have a way to send commands to the underlying
DCS groups. Why would we want this and what are the issues?

Wanted:
 - can treat all groups represented by the asset as one
 - 

Issues:
 - lack of fine control
 - no direct access to the Controller class so no ability to get
   detection information
