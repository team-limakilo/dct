--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Default aircraft-specific settings.
--]]

local utils = require("dct.utils")

return {
    ["ato"] = {},
    ["costs"] = {},
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
        ["AH-64D_BLK_II"] = utils.posfmt.MGRS,
        ["F-5E-3"]        = utils.posfmt.DDM,
        ["F-16C_50"]      = utils.posfmt.DDM,
        ["FA-18C_hornet"] = utils.posfmt.DDM,
        ["M-2000C"]       = utils.posfmt.DDM,
    },
    ["payloadlimits"] = {},
    ["units"] = {
        -- default units are imperial inHg
        ["AH-64D_BLK_II"] = utils.units.APACHE_MIXED,
        ["AJS37"]         = utils.units.METRIC_HPA,
        ["Bf-109K-4"]     = utils.units.METRIC_HPA,
        ["FW-190A8"]      = utils.units.METRIC_HPA,
        ["FW-190D9"]      = utils.units.METRIC_HPA,
        ["I-16"]          = utils.units.METRIC_MMHG,
        ["Ka-50"]         = utils.units.METRIC_MMHG,
        ["Mi-8MT"]        = utils.units.METRIC_MMHG,
        ["Mi-24P"]        = utils.units.METRIC_MMHG,
        ["MiG-15bis"]     = utils.units.METRIC_MMHG,
        ["MiG-19P"]       = utils.units.METRIC_MMHG,
        ["MiG-21Bis"]     = utils.units.METRIC_MMHG,
        ["MiG-29A"]       = utils.units.METRIC_MMHG,
        ["MiG-29S"]       = utils.units.METRIC_MMHG,
        ["Su-25"]         = utils.units.METRIC_MMHG,
        ["Su-25T"]        = utils.units.METRIC_MMHG,
        ["Su-27"]         = utils.units.METRIC_MMHG,
        ["Su-33"]         = utils.units.METRIC_HPA,
        ["Yak-52"]        = utils.units.METRIC_MMHG,
        ["M-2000C"]       = utils.units.IMPERIAL_HPA,
    },
}
