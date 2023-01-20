--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Default aircraft-specific settings.
--]]

local utils = require("dct.utils")

local UNITS_IMPERIAL_MBAR = {
    [utils.units.IMPERIAL] = true,
    [utils.units.MBAR]     = true,
}
local UNITS_METRIC_MMHG = {
    [utils.units.METRIC]   = true,
    [utils.units.MMHG]     = true,
}
local UNITS_METRIC_HPA = {
    [utils.units.METRIC]   = true,
    [utils.units.HPA]      = true,
}

return {
    ["ato"] = {},
    ["costs"] = {},
    ["gridfmt"] = {
        -- default is DMS
        ["Ka-50"]         = utils.posfmt.DDM,
        ["Ka-50_3"]       = utils.posfmt.DDM,
        ["Mi-8MT"]        = utils.posfmt.DDM,
        ["SA342M"]        = utils.posfmt.DDM,
        ["SA342L"]        = utils.posfmt.DDM,
        ["UH-1H"]         = utils.posfmt.DDM,
        ["A-10A"]         = utils.posfmt.MGRS,
        ["A-10C"]         = utils.posfmt.MGRS,
        ["A-10C_2"]       = utils.posfmt.MGRS,
        ["AH-64D_BLK_II"] = utils.posfmt.MGRS,
        ["F-5E-3"]        = utils.posfmt.DDM,
        ["F-14A-95-GR"]   = utils.posfmt.DDM,
        ["F-14A-135-GR"]  = utils.posfmt.DDM,
        ["F-14B"]         = utils.posfmt.DDM,
        ["F-16C_50"]      = utils.posfmt.DDM,
        ["FA-18C_hornet"] = utils.posfmt.DDM,
        ["M-2000C"]       = utils.posfmt.DDM,
    },
    ["payloadlimits"] = {},
    ["units"] = {
        -- default units are imperial and inHg
        ["AH-64D_BLK_II"] = {
            [utils.units.US_ARMY] = true,
            [utils.units.INHG] = true,
        },
        ["AJS37"] = UNITS_METRIC_HPA,
        ["Bf-109K-4"] = UNITS_METRIC_HPA,
        ["FW-190A8"] = UNITS_METRIC_HPA,
        ["FW-190D9"] = UNITS_METRIC_HPA,
        ["I-16"] = UNITS_METRIC_MMHG,
        ["Ka-50"] = UNITS_METRIC_MMHG,
        ["M-2000C"] = UNITS_IMPERIAL_MBAR,
        ["Mi-8MT"] = UNITS_METRIC_MMHG,
        ["Mi-24P"] = UNITS_METRIC_MMHG,
        ["MiG-15bis"] = UNITS_METRIC_MMHG,
        ["MiG-19P"] = UNITS_METRIC_MMHG,
        ["MiG-21Bis"] = UNITS_METRIC_MMHG,
        ["MiG-29A"] = UNITS_METRIC_MMHG,
        ["MiG-29S"] = UNITS_METRIC_MMHG,
        ["MiG-29G"] = {
            [utils.units.METRIC] = true,
            [utils.units.INHG] = true,
        },
        ["Mirage-F1CE"] = UNITS_IMPERIAL_MBAR,
        ["Mirage-F1BE"] = UNITS_IMPERIAL_MBAR,
        ["Mirage-F1EE"] = UNITS_IMPERIAL_MBAR,
        ["Mirage-F1M"] = UNITS_IMPERIAL_MBAR,
        ["Su-25"] = UNITS_METRIC_MMHG,
        ["Su-25T"] = UNITS_METRIC_MMHG,
        ["Su-27"] = UNITS_METRIC_MMHG,
        ["Su-33"] = UNITS_METRIC_HPA,
        ["Yak-52"] = UNITS_METRIC_MMHG,
    },
}
