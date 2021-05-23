--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Implements RPC methods for OverlordBot if the GRPC library was loaded at
-- mission start.
--]]
local class   = require("libs.class")
local Logger  = require("dct.libs.Logger").getByName("OverlordBotRPC")
local Theater = require("dct.Theater")
local dctEnum = require("dct.enum")

local function getGroup(unitName)
	local unit = Unit.getByName(unitName)
	if unit == nil then
		return nil, GRPC.errorNotFound(string.format(
			"Could not find unit with name '%s'", unitName))
	end
	local group = unit:getGroup()
	if group == nil then
		return nil, GRPC.errorNotFound(string.format(
			"Could not find group of unit '%s'", unitName))
	end
	return group:getName(), nil
end

local OverlordBotRPC = class()
function OverlordBotRPC:__init()
	if GRPC then
		Logger:info("loaded")

		function GRPC.methods.requestMissionAssignment(params)
			local group, err = getGroup(params.unitName)
			if err ~= nil then
				return err
			end

			local missionTypeMap = {
				["CAS"] = dctEnum.missionType.CAS,
				["CAP"] = dctEnum.missionType.CAP,
				["Strike"] = dctEnum.missionType.STRIKE,
				["DEAD"] = dctEnum.missionType.SEAD,
				["SEAD"] = dctEnum.missionType.SEAD,
				["BAI"] = dctEnum.missionType.BAI,
				["OCA"] = dctEnum.missionType.OCA,
				["Recon"] = dctEnum.missionType.ARMEDRECON,
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
			local group, err = getGroup(params.unitName)
			if err ~= nil then
				return err
			end

			Theater.playerRequest({
				name = group,
				type = dctEnum.uiRequestType.MISSIONJOIN,
				missioncode = params.missionCode
			})

			return GRPC.success(nil)
		end

	end
end

return OverlordBotRPC
