--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Implements RPC methods for OverlordBot if the GRPC library was loaded at
-- mission start.
--]]
local class   = require("libs.class")
local Logger  = require("dct.libs.Logger").getByName("OverlordBotRPC")
local Theater = require("dct.Theater")
local Command = require("dct.Command")
local dctEnum = require("dct.enum")

local OverlordBotRPC = class()
function OverlordBotRPC:__init(theater)
	theater:queueCommand(5, Command("OverlordBotRPC.init", self.init, self))
end

function OverlordBotRPC:init()
	if GRPC and GRPC.methods then
		Logger:info("loaded")

		function GRPC.methods.requestMissionAssignment(params)
			-- Backwards compatible with previous API
			local group = params.groupName or params.unitName

			local missionTypeMap = {
				["CAS"] = dctEnum.missionType.CAS,
				["CAP"] = dctEnum.missionType.CAP,
				["Strike"] = dctEnum.missionType.STRIKE,
				["DEAD"] = dctEnum.missionType.SEAD,
				["SEAD"] = dctEnum.missionType.SEAD,
				["BAI"] = dctEnum.missionType.BAI,
				["OCA"] = dctEnum.missionType.OCA,
				["Recon"] = dctEnum.missionType.ARMEDRECON,
				["ASuW"] = dctEnum.missionType.ANTISHIP,
			}

			if missionTypeMap[params.missionType] == nil then
				return GRPC.errorNotFound(string.format(
					"No mission type found that matches '%s'", params.missionType))
			end

			Theater.playerRequest({
				name = group,
				value = missionTypeMap[params.missionType],
				type = dctEnum.uiRequestType.MISSIONREQUEST
			})

			return GRPC.success(nil)
		end


		function GRPC.methods.joinMission(params)
			-- Backwards compatible with previous API
			local group = params.groupName or params.unitName

			Theater.playerRequest({
				name = group,
				type = dctEnum.uiRequestType.MISSIONJOIN,
				missioncode = tostring(params.missionCode)
			})

			return GRPC.success(nil)
		end

	else
		Logger:info("aborting: GRPC not in global scope")
	end
end

return OverlordBotRPC
