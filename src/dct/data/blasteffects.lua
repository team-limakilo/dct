--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Arctic Fox ver.
--]]

-- luacheck: max_line_length 240

local tntrel = {
	["TNT"]       = 1,
	["Tritonal"]  = 1.05,
	["PBXN5"]     = 1.376, -- Source: TM 9-1300-214 (1990). RE factor assumed based on HMX factor 1.7.
	["PBXN109"]   = 1.17,
	["PBXC116"]   = 1.376, -- Source: TM 9-1300-214 (1990). RE factor assumed based on RDX factor 1.6.
	["Torpex"]    = 1.30,
	["CompB"]     = 1.33,
	["Pentolite"] = 1.33,
	["H6"]        = 1.356,
	["TGA12"]     = 1.33,  -- Source: "History of Aviation Weapons". RE factor assumed based on similarity to TGAF-5 and H6.
	["TGAF5"]     = 1.3    -- Source: https://www.gichd.org/fileadmin/GICHD-resources/rec-documents/Explosive_weapon_effects_web.pdf
}

-- exmass - mass of explosive compound in kilograms
local function tnt_equiv_mass(exmass, tntfactor)
	tntfactor = tntfactor or tntrel.TNT
	return exmass * tntfactor
end

-- Due to lack of information, modern Soviet/Russian weapons are assumed to use TGA-12 (for earlier weapons) or TGAF-5 (for later weapons) unless specified otherwise
-- This lines up with TNT equivalent yield numbers from sources such as Rosoboronexport
-- Other known Soviet/Russian compositions such as TG-40 have similar yields
-- HEAT weapons omitted except in specific circumstances
local wpnmass = {
	-- IRON BOMS
	-- US weapons
	-- WWII bombs given in typical TNT configuration, later versions (A1) in tritonal or Composition B
	-- Source: OP 1664 (1947), Volume 2
	["AN_M30A1"]     = tnt_equiv_mass( 28, tntrel.Tritonal),
	["AN-M57"]       = tnt_equiv_mass( 59, tntrel.TNT),
	["AN-M64"]       = tnt_equiv_mass(121, tntrel.TNT),
	["AN-M65"]       = tnt_equiv_mass(253, tntrel.TNT),
	["AN-M66"]       = tnt_equiv_mass(518, tntrel.CompB),
	["M_117"]        = tnt_equiv_mass(175, tntrel.Tritonal), -- Source: TM 9-1325-200 (1966)
	-- Mk 80 series
	-- Source: http://www.ordtech-industries.com/2products/Bomb_General/Bomb_General.html
	["Mk_81"]        = tnt_equiv_mass( 45, tntrel.H6),
	["Mk_82"]        = tnt_equiv_mass( 87, tntrel.H6),
	["Mk_83"]        = tnt_equiv_mass(202, tntrel.H6),
	["Mk_84"]        = tnt_equiv_mass(443, tntrel.H6),
	["BLU_109"]      = tnt_equiv_mass(240, tntrel.PBXN109), -- Source: Jane's Air-Launched Weapons
	-- Soviet/Russian weapons
	-- Source: Jane's Air-Launched Weapons
	["FAB_100SV"]        = tnt_equiv_mass( 53, tntrel.TNT), -- Extrapolated from FAB-50SV: http://vvs.hobbyvista.com/Research/Ordnance/FAB50/
	-- M43 series
	-- Source: "History of Aviation Weapons"
	-- These bombs were filled with different filler mixtures including TNT, Ammatol, TGA-12 and others. Given here with TNT for consistency with US bombs.
	["FAB_50"]           = tnt_equiv_mass( 24, tntrel.TNT), -- Source: http://vvs.hobbyvista.com/Research/Ordnance/FAB50/
	["FAB_100M"]         = tnt_equiv_mass( 48, tntrel.TNT), -- Extrapolated from above
	-- M54 series
	["FAB_100"]          = tnt_equiv_mass( 45, tntrel.TGA12), -- This value is for M62 but I don't have anything better.
	["FAB_250"]          = tnt_equiv_mass( 94, tntrel.TGA12),
	["FAB-500M54"]       = tnt_equiv_mass(201, tntrel.TGA12),
	["FAB_1500"]         = tnt_equiv_mass(667, tntrel.TGA12),
	-- M62 series
	["FAB-250-M62"]      = tnt_equiv_mass(113, tntrel.TGAF5),
	["FAB_500"]          = tnt_equiv_mass(214, tntrel.TGAF5),
	["BetAB_500"]        = tnt_equiv_mass( 76, tntrel.TGAF5), -- Filler "TA 77/23", composition unknown. TNT equivalence similar to TGAF according to Rosoboronexport.
	["BetAB_500ShP"]     = tnt_equiv_mass( 77, tntrel.TGAF5),
	["OFAB-100-120TU"]   = tnt_equiv_mass( 45, tntrel.TGAF5), -- Source: http://www.airwar.ru/weapon/ab/ofab-100-120.html
	["OFAB-100 Jupiter"] = tnt_equiv_mass( 45, tntrel.TGAF5), -- Assumed simiar
	-- French weapons
	-- Source: Jane's Air-Launched Weapons
	-- Composition B assumed based on other French bombs of the era according to same source
	["BAT-120"]      = tnt_equiv_mass( 6,  tntrel.CompB),
	["SAMP125LD"]    = tnt_equiv_mass(58,  tntrel.CompB),
	["SAMP250LD"]    = tnt_equiv_mass(124, tntrel.CompB),
	["SAMP400LD"]    = tnt_equiv_mass(200, tntrel.CompB), -- Assumed based on explosive filling in other series bombs
	-- Spanish weapons
	-- Source: Jane's Air-Launched Weapons
	["BR_250"]       = tnt_equiv_mass(112, tntrel.H6),
	["BR_500"]       = tnt_equiv_mass(206, tntrel.H6),
	-- Swedish weapons
	-- Source: Jane's Air-Launched Weapons
	["HEBOMB"]       = tnt_equiv_mass( 30, tntrel.CompB), -- "RDX/TNT"
	-- British weapons
	-- WWII
	-- Source: OP 1665
	["British_GP_250LB_Bomb_Mk1"]       = tnt_equiv_mass( 31, tntrel.TNT),
	["British_GP_250LB_Bomb_Mk4"]       = tnt_equiv_mass( 31, tntrel.TNT),
	["British_GP_500LB_Bomb_Mk1"]       = tnt_equiv_mass( 66, tntrel.TNT), -- WIP
	["British_GP_500LB_Bomb_Mk4"]       = tnt_equiv_mass( 66, tntrel.TNT),
	["British_MC_250LB_Bomb_Mk1"]       = tnt_equiv_mass( 51, tntrel.Pentolite),
	["British_MC_500LB_Bomb_Mk1_Short"] = tnt_equiv_mass( 95, tntrel.Pentolite), -- Assumed
	["British_SAP_250LB_Bomb_Mk5"]      = tnt_equiv_mass( 18, tntrel.Torpex),
	["British_SAP_500LB_Bomb_Mk5"]      = tnt_equiv_mass( 40, tntrel.TNT),


	-- GUIDED BOMBS
	-- US weapons
	-- Source: Jane's Air-Launched Weapons
	["AGM_62"]       = tnt_equiv_mass(424, tntrel.H6),   -- it has a linear star shaped charge warhead designed to affect an area around the impact point, so I left it at full power
	["AGM_154C"]     = tnt_equiv_mass(245, tntrel.TNT),  -- Total warhead weight 245kg, containing WDU-44 shaped charge and WDU-45 follow-on bomb. Exact weights unknown so estimated at that.
	-- Soviet/Russian weapons
	-- Source: Jane's Air-Launched Weapons
	["KAB_500"]      = tnt_equiv_mass(195, tntrel.TGAF5),
	["KAB_500Kr"]    = tnt_equiv_mass(200, tntrel.TGAF5),
	["KAB_1500Kr"]   = tnt_equiv_mass(440, tntrel.TGAF5), -- Source: "Russia's Arms and Technologies: The XXI Century Encyclopaedia"

	-- ROCKETS
	-- rockets use total warhead weight due to lack of proper fragmentation modeling
	-- US weapons
	-- Source: TM 43-0001-30
	["HVAR"]             = tnt_equiv_mass( 21, tntrel.TNT),   -- Source: Wiki
	["HYDRA_70_M151"]    = tnt_equiv_mass(  4, tntrel.CompB), -- Composition B4
	["HYDRA_70_M229"]    = tnt_equiv_mass(  8, tntrel.CompB), -- Composition B4
	["Zuni_127"]         = tnt_equiv_mass( 23, tntrel.CompB), -- Source: Jane's Air-Launched Weapons
	-- Soviet/Russian weapons
	["S-5M"]             = tnt_equiv_mass(  1, tntrel.TGA12),
	["S5M1_HEFRAG_FFAR"] = tnt_equiv_mass(  1, tntrel.TGA12),
	["S5MO_HEFRAG_FFAR"] = tnt_equiv_mass(  2, tntrel.TGA12),
	["C_8OFP2"]          = tnt_equiv_mass( 10, tntrel.TGAF5), -- Source: DCS Mi-8 manual
	["C_13"]             = tnt_equiv_mass( 33, tntrel.TGAF5), -- S-13OF. Source: "Russia's Arms and Technologies: The XXI Century Encyclopaedia"
	["C_24"]             = tnt_equiv_mass(125, tntrel.TGAF5), -- Source: "Russia's Arms and Technologies: The XXI Century Encyclopaedia"
	-- These really don't need any help
	--["S-24A"]          = tnt_equiv_mass(123, tntrel.TGAF5),
	--["S-24B"]          = tnt_equiv_mass(125, tntrel.TGAF5),
	["C_25"]             = tnt_equiv_mass(151, tntrel.TGAF5), -- S-25OFM
	["S-25O"]            = tnt_equiv_mass(151, tntrel.TGAF5),
	-- French weapons
	-- Source: Jane's Air-Launched Weapons, French wiki
	["SNEB_TYPE251_F1B"] = tnt_equiv_mass(1, tntrel.CompB),
	["SNEB_TYPE256_F1B"] = tnt_equiv_mass(3, tntrel.CompB),
	["SNEB_TYPE257_F1B"] = tnt_equiv_mass(5, tntrel.CompB),
	-- Swedish weapons
	-- Source: Jane's Air-Launched Weapons
	["ARAKM70BHE"]      = tnt_equiv_mass( 21, tntrel.CompB), -- filler composition referenced online but no solid source
	-- Italian Weapons
	-- Source: Jane's Air-Launched Weapons
	["ARF8M3HEI"]       = tnt_equiv_mass( 2, tntrel.Tritonal), -- "SNIA BPD" 51mm rocket system
	-- British weapons
	-- WWII
	-- Source: AP 2802, Vol 1 (1944)
	["British_HE_60LBFNo1_3INCHNo1"]        = tnt_equiv_mass( 27, tntrel.TNT),
	["British_HE_60LBSAPNo2_3INCHNo1"]      = tnt_equiv_mass( 27, tntrel.TNT),

	-- GUIDED MISSILES
	-- Whenever explosive composition is unknown, total warhead weight is divided by half and a typical filler composition is used
	-- US weapons
	-- Source: Jane's Air-Launched Weapons
	["AGM_84D"]        = tnt_equiv_mass( 98, tntrel.Tritonal), -- Source: https://man.fas.org/dod-101/sys/smart/agm-84.htm. DESTEX is desensitized tritonal.
	["AGM_84H"]        = tnt_equiv_mass(109, tntrel.Tritonal), -- Exact filler unknown, assumed equivalent explosive fraction in 247kg warhead (Source: Jane's)
	["AGM_88C"]        = tnt_equiv_mass( 21, tntrel.PBXC116),  -- Source: https://man.fas.org/dod-101/sys/smart/agm-88.htm
	["AGM_119"]        = tnt_equiv_mass( 60, tntrel.Tritonal),  --  120kg Penguin 2 WDU-39/B warhead/2.
	["AGM_122"]        = tnt_equiv_mass(  5, tntrel.PBXN5),     -- Similar AIM-9D uses "HMX-nylon high explosive" according to OP 3352 so PBXN-5 assumed. 10kg WDU-31/B warhead/2.
	-- Soviet/Russian weapons
	-- Source: http://www.airwar.ru/enc/weapon/avz_data.html, "Russia's Arms and Technologies: The XXI Century Encyclopaedia"
	-- Kh-25 explosive fill factor is twice the Kh-29's one-third per: http://www.airwar.ru/weapon/avz/x29l.html
	["X_29L"]          = tnt_equiv_mass(116, tntrel.TGAF5),
	["X_25ML"]         = tnt_equiv_mass( 60, tntrel.TGAF5), -- 90kg warhead * 2/3.
	["X_25MR"]         = tnt_equiv_mass( 93, tntrel.TGAF5), -- Source: Jane's Air-Launched Weapons. 140kg warhead * 2/3. This seems questionable but is referenced in several other places.
	["X_28"]           = tnt_equiv_mass( 74, tntrel.TGAF5),
	["X_58"]           = tnt_equiv_mass( 59, tntrel.TGAF5),
	["Ataka_9M120F"]   = tnt_equiv_mass(  7, tntrel.TGAF5), -- Total warhead weight used as with rockets
	--["KH-66_Grom"]   = tnt_equiv_mass(51),  -- This doesn't need help either. Source: Jane's Air-Launched Weapons.
	-- Swedish weapons
	["Rb 05A"]         = tnt_equiv_mass(80, tntrel.CompB), -- Source: Wiki, I have nothing better. 160kg warhead/2.

	-- GROUND LAUNCHED WEAPONS
	-- Soviet weapons
	["SMERCH_9M55F"] = tnt_equiv_mass(148), -- Unchanged
}

-- weapons that use the same warheads
wpnmass["MK_82AIR"]                           = wpnmass["Mk_82"]
wpnmass["MK_82SNAKEYE"]                       = wpnmass["Mk_82"]
wpnmass["Mk_82Y"]                             = wpnmass["Mk_82"]
wpnmass["GBU_12"]                             = wpnmass["Mk_82"]
wpnmass["GBU_38"]                             = wpnmass["Mk_82"]
wpnmass["GBU_54_V_1B"]                        = wpnmass["Mk_82"]
wpnmass["GBU_16"]                             = wpnmass["Mk_83"]
wpnmass["GBU_32_V_2B"]                        = wpnmass["Mk_83"]
wpnmass["AGM_123"]                            = wpnmass["Mk_83"] -- Skipper missile
wpnmass["Mk_84AIR_GP"]                        = wpnmass["Mk_84"]
wpnmass["AGM_130"]                            = wpnmass["Mk_84"]
wpnmass["GBU_10"]                             = wpnmass["Mk_84"]
wpnmass["GBU_31"]                             = wpnmass["Mk_84"]
wpnmass["GBU_31_V_2B"]                        = wpnmass["Mk_84"]
wpnmass["GBU_31_V_3B"]                        = wpnmass["BLU_109"]
wpnmass["GBU_31_V_4B"]                        = wpnmass["BLU_109"]
wpnmass["GBU_24"]                             = wpnmass["BLU_109"]
wpnmass["FAB-250M54TU"]                       = wpnmass["FAB_250"]
wpnmass["FAB-250M54TU"]                       = wpnmass["FAB_250"]
wpnmass["FAB-500M54TU"]                       = wpnmass["FAB-500M54"]
wpnmass["SAMP250HD"]                          = wpnmass["SAMP250LD"]
wpnmass["SAMP400HD"]                          = wpnmass["SAMP400LD"]
wpnmass["HEBOMBD"]                            = wpnmass["HEBOMB"] -- Swedish M/71 high drag bomb
wpnmass["British_GP_250LB_Bomb_Mk4"]          = wpnmass["British_GP_250LB_Bomb_Mk5"]
wpnmass["British_GP_500LB_Bomb_Mk4_Short"]    = wpnmass["British_GP_500LB_Bomb_Mk4"]
wpnmass["British_GP_500LB_Bomb_Mk5"]          = wpnmass["British_GP_500LB_Bomb_Mk4"]
wpnmass["British_MC_250LB_Bomb_Mk2"]          = wpnmass["British_MC_250LB_Bomb_Mk1"]
wpnmass["British_MC_500LB_Bomb_Mk2"]          = wpnmass["British_MC_500LB_Bomb_Mk1_Short"]
wpnmass["FFAR Mk1 HE"]                        = wpnmass["HYDRA_70_M151"] -- Assumed
wpnmass["S-25OFM"]                            = wpnmass["C_25"] -- This shouldn't be necessary but it has two names for some reason, so just in case
wpnmass["SNEB_TYPE251_H1"]                    = wpnmass["SNEB_TYPE251_F1B"]
wpnmass["SNEB_TYPE256_H1"]                    = wpnmass["SNEB_TYPE256_F1B"]
wpnmass["SNEB_TYPE257_H1"]                    = wpnmass["SNEB_TYPE257_F1B"]
wpnmass["AGM_84A"]                            = wpnmass["AGM_84D"]
wpnmass["AGM_84E"]                            = wpnmass["AGM_84D"]
wpnmass["S_25L"]                              = wpnmass["C_25"] -- this is inconsistent with other missiles but the in-game damage value is already high so it doesn't matter
wpnmass["Kh25MP_PRGS1VP"]                     = wpnmass["X_25ML"]
wpnmass["X_25MP"]                             = wpnmass["X_25ML"]
wpnmass["X_29T"]                              = wpnmass["X_29L"]
wpnmass["X_29TE"]                             = wpnmass["X_29L"]
wpnmass["AGR_20_M151_unguided"]               = wpnmass["HYDRA_70_M151"] -- I don't know what this is

return wpnmass