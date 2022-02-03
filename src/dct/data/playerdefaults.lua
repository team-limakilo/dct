--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Default aircraft-specific settings.
--]]

local utils = require("dct.utils")

return {
    ["gridfmt"] = {
        -- default is DMS
        ["Ka-50"]         = utils.posfmt.DDM,
        ["Mi-8MT"]        = utils.posfmt.DDM,
        ["SA342M"]        = utils.posfmt.DDM,
        ["SA342L"]        = utils.posfmt.DDM,
        ["UH-1H"]         = utils.posfmt.DDM,
        ["A-10A"]         = utils.posfmt.MGRS,
        ["A-10C"]         = utils.posfmt.MGRS,
        ["A-10C_2"]       = utils.posfmt.MGRS,
        ["F-5E-3"]        = utils.posfmt.DDM,
        ["F-16C_50"]      = utils.posfmt.DDM,
        ["FA-18C_hornet"] = utils.posfmt.DDM,
        ["M-2000C"]       = utils.posfmt.DDM,
    },
    ["units"] = {
        -- default is imperial
        ["AJS37"]     = utils.units.METRIC,
        ["Bf-109K-4"] = utils.units.METRIC,
        ["FW-190A8"]  = utils.units.METRIC,
        ["FW-190D9"]  = utils.units.METRIC,
        ["I-16"]      = utils.units.METRIC,
        ["Ka-50"]     = utils.units.METRIC,
        ["Mi-8MT"]    = utils.units.METRIC,
        ["Mi-24P"]    = utils.units.METRIC,
        ["MiG-15bis"] = utils.units.METRIC,
        ["MiG-19P"]   = utils.units.METRIC,
        ["MiG-21Bis"] = utils.units.METRIC,
        ["MiG-29A"]   = utils.units.METRIC,
        ["MiG-29S"]   = utils.units.METRIC,
        ["Su-25"]     = utils.units.METRIC,
        ["Su-25T"]    = utils.units.METRIC,
        ["Su-27"]     = utils.units.METRIC,
        ["Su-33"]     = utils.units.METRIC,
        ["Yak-52"]    = utils.units.METRIC,
    },
    ["ato"] = {},
}
