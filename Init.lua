---@type string, TargetedSpells
local addonName, Private = ...

Private.L = {}

Private.EventRegistry = CreateFromMixins(CallbackRegistryMixin)
Private.EventRegistry:OnLoad()

do
	local tbl = {}

	for _, value in pairs(Private.Enum.Events) do
		table.insert(tbl, value)
	end

	Private.EventRegistry:GenerateCallbackEvents(tbl)
end

Private.LoginFnQueue = {}

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	---@class SavedVariables
	TargetedSpellsSaved = TargetedSpellsSaved or {}
	if TargetedSpellsSaved.nameplateShowOffscreenWasInitialized == nil then
		TargetedSpellsSaved.nameplateShowOffscreenWasInitialized = true
		C_CVar.SetCVar("nameplateShowOffscreen", 1)
	end

	---@class TargetedSpellsSettings
	TargetedSpellsSaved.Settings = TargetedSpellsSaved.Settings or {}
	---@class SavedVariablesSettingsSelf
	TargetedSpellsSaved.Settings.Self = TargetedSpellsSaved.Settings.Self or {}
	---@class SavedVariablesSettingsParty
	TargetedSpellsSaved.Settings.Party = TargetedSpellsSaved.Settings.Party or {}

	local resetKeys = {}
	local selfDefaults = Private.Settings.GetSelfDefaultSettings()
	local partyDefaults = Private.Settings.GetPartyDefaultSettings()

	for key, value in pairs(selfDefaults) do
		if
			TargetedSpellsSaved.Settings.Self[key] == nil
			or type(value) ~= type(TargetedSpellsSaved.Settings.Self[key])
		then
			TargetedSpellsSaved.Settings.Self[key] = value
		end

		if key == "Grow" and TargetedSpellsSaved.Settings.Self[key] == 1 then
			TargetedSpellsSaved.Settings.Self[key] = Private.Enum.Grow.Start
			table.insert(
				resetKeys,
				Private.L.EditMode.TargetedSpellsSelfLabel .. ": " .. Private.L.Settings.FrameGrowLabel
			)
		end

		if key == "GlowType" and TargetedSpellsSaved.Settings.Self[key] == 3 then
			TargetedSpellsSaved.Settings.Self[key] = Private.Enum.GlowType.PixelGlow
			table.insert(
				resetKeys,
				Private.L.EditMode.TargetedSpellsSelfLabel .. ": " .. Private.L.Settings.GlowTypeLabel
			)
		end
	end

	for key, value in pairs(partyDefaults) do
		if
			TargetedSpellsSaved.Settings.Party[key] == nil
			or type(value) ~= type(TargetedSpellsSaved.Settings.Party[key])
		then
			TargetedSpellsSaved.Settings.Party[key] = value
		end

		if key == "Grow" and TargetedSpellsSaved.Settings.Party[key] == 1 then
			TargetedSpellsSaved.Settings.Party[key] = Private.Enum.Grow.Start
			table.insert(
				resetKeys,
				Private.L.EditMode.TargetedSpellsPartyLabel .. ": " .. Private.L.Settings.FrameGrowLabel
			)
		end

		if key == "GlowType" and TargetedSpellsSaved.Settings.Party[key] == 3 then
			TargetedSpellsSaved.Settings.Party[key] = Private.Enum.GlowType.PixelGlow
			table.insert(
				resetKeys,
				Private.L.EditMode.TargetedSpellsPartyLabel .. ": " .. Private.L.Settings.GlowTypeLabel
			)
		end
	end

	if TargetedSpellsSaved.v2DeprecationWarningSeen == nil then
		TargetedSpellsSaved.v2DeprecationWarningSeen = true

		local function MigrateFeatureFlags(kind)
			local flagSourceMap = {
				[Private.Enum.FeatureFlag.GlowImportant] = "GlowImportant",
				[Private.Enum.FeatureFlag.OnlyImportant] = "OnlyImportant",
				[Private.Enum.FeatureFlag.ShowDuration] = "ShowDuration",
				[Private.Enum.FeatureFlag.ShowDurationFractions] = "ShowDurationFractions",
				[Private.Enum.FeatureFlag.ShowBorder] = "ShowBorder",
				[Private.Enum.FeatureFlag.ShowSwipe] = "ShowSwipe",
				[Private.Enum.FeatureFlag.IndicateInterrupts] = "IndicateInterrupts",
				[Private.Enum.FeatureFlag.RenderInterruptSourceName] = "RenderInterruptSourceName",
			}

			local settings, flagDefaults = nil, nil
			if kind == Private.Enum.FrameKind.Self then
				settings = TargetedSpellsSaved.Settings.Self
				flagDefaults = selfDefaults.FeatureFlags
			else
				flagSourceMap[Private.Enum.FeatureFlag.IncludeSelfInParty] = "IncludeSelfInParty"
				settings = TargetedSpellsSaved.Settings.Party
				flagDefaults = partyDefaults.FeatureFlags
			end

			if settings.FeatureFlags == nil then
				settings.FeatureFlags = {}
			end

			for flagId, oldKey in pairs(flagSourceMap) do
				if settings.FeatureFlags[flagId] == nil then
					settings.FeatureFlags[flagId] = (settings[oldKey] ~= nil) and settings[oldKey]
						or flagDefaults[flagId]
				end

				settings[oldKey] = nil
			end
		end

		MigrateFeatureFlags(Private.Enum.FrameKind.Self)
		MigrateFeatureFlags(Private.Enum.FrameKind.Party)

		if #resetKeys > 0 then
			C_Timer.After(3, function()
				Private.Utils.ShowStaticPopup({
					whileDead = true,
					button1 = OKAY,
					text = string.format(Private.L.Functionality.V2DeprecationWarning, table.concat(resetKeys, "\n")),
				})
			end)
		end
	end

	for i = 1, #Private.LoginFnQueue do
		local fn = Private.LoginFnQueue[i]
		fn()
	end

	table.wipe(Private.LoginFnQueue)
end)
