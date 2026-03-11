---@type string, TargetedSpells
local addonName, Private = ...

---@class TargetedSpellsUtils
Private.Utils = {}

Private.Utils.Pools = {
	Bar = CreateFramePool("StatusBar", UIParent, nil, nil, nil, function(bar)
		bar:SetMinMaxValues(0, 1)
		bar:SetIgnoreParentAlpha(true)
		bar:SetStatusBarTexture("")
	end),
	Frame = CreateFramePool(
		"Frame",
		UIParent,
		"TargetedSpellsFrameTemplate",
		---@param pool FramePool
		---@param frame TargetedSpellsMixin
		function(pool, frame)
			frame:Reset()

			if frame.bar ~= nil then
				Private.Utils.Pools.Bar:Release(frame.bar)
				frame.bar = nil
			end
		end
	),
}

function Private.Utils.CalculateCoordinate(index, dimension, gap, parentDimension, total, offset, grow)
	local step = dimension + gap

	if grow == Private.Enum.Grow.Start then
		return (index - 1) * step - parentDimension / 2 + offset
	elseif grow == Private.Enum.Grow.End then
		return parentDimension / 2 - index * step + offset
	end

	return 0
end

do
	local function sortAsc(a, b)
		return a:GetStartTime() < b:GetStartTime()
	end

	local function sortDesc(a, b)
		return a:GetStartTime() > b:GetStartTime()
	end

	function Private.Utils.SortFrames(frames, sortOrder)
		local isAscending = sortOrder == Private.Enum.SortOrder.Ascending

		table.sort(frames, isAscending and sortAsc or sortDesc)
	end
end

function Private.Utils.RollDice()
	return math.random(1, 6) == 6
end

do
	function Private.Utils.MaybeApplyElvUISkin(frame) end

	if ElvUI then
		local E = unpack(ElvUI)
		local S = E:GetModule("Skins")

		S:AddCallbackForAddon(addonName, addonName, function()
			function Private.Utils.MaybeApplyElvUISkin(frame)
				S:HandleButton(frame)
			end
		end)
	end
end

do
	---@type table<string, true>
	local thirdPartyFrameNames = {}
	local registerdFrames = 0
	local hasManualThirdPartyRegistrations = false

	function Private.Utils.RegisterFrameByName(frameName)
		thirdPartyFrameNames[frameName] = true
		hasManualThirdPartyRegistrations = true
		registerdFrames = registerdFrames + 1

		return true
	end

	function Private.Utils.UnregisterFrameByName(frameName)
		if thirdPartyFrameNames[frameName] == nil then
			return false
		end

		thirdPartyFrameNames[frameName] = nil
		registerdFrames = registerdFrames - 1
		hasManualThirdPartyRegistrations = registerdFrames > 0

		if not hasManualThirdPartyRegistrations then
			table.wipe(thirdPartyFrameNames)
		end

		return true
	end

	function Private.Utils.HasThirdPartyCandidates()
		return hasManualThirdPartyRegistrations
	end

	for index = 1, C_AddOns.GetNumAddOns() do
		local meta = C_AddOns.GetAddOnMetadata(index, "X-oUF")

		if meta and _G[meta] then
			hooksecurefunc(_G[meta], "SpawnHeader", function(ref)
				for _, header in next, ref.headers do
					local headerName = header:GetName()

					if headerName and string.find(headerName, "Party") ~= nil then
						for unitIndex = 1, 5 do
							Private.Utils.RegisterFrameByName(string.format("%sUnitButton%d", headerName, unitIndex))
						end
					end
				end
			end)
		end
	end

	function Private.Utils.FindThirdPartyGroupFrameForUnit(unit)
		if Grid2 then
			return (next(Grid2:GetUnitFrames(unit)))
		end

		if VUHDO_getUnitButtons then
			local frames = VUHDO_getUnitButtons(unit)

			if frames ~= nil then
				for _, frame in pairs(frames) do
					if frame.raidid == unit and frame:IsVisible() then
						return frame
					end
				end
			end
		end

		if ShadowUF and SUFHeaderparty then
			for i = 1, 5 do
				local frame = _G["SUFHeaderpartyUnitButton" .. i]

				if frame and frame.unit == unit then
					return frame
				end
			end
		end

		if EnhanceQoL and EQOLUFPartyHeader then
			for i = 1, 5 do
				local frame = _G["EQOLUFPartyHeaderUnitButton" .. i]

				if frame and frame.unit == unit then
					return frame
				end
			end
		end

		if DandersFrames and DandersFrames.Api and DandersFrames.Api.GetFrameForUnit then
			local frame = DandersFrames.Api.GetFrameForUnit(unit, Private.Enum.FrameKind.Party)

			if frame then
				return frame
			end
		end

		-- use these last, including e.g. ElvUI. people using multiple unit frame addons (god knows for what reason)
		-- _likely_ prefer using the other one over oUF derivates because what else would be the point of having them.
		if hasManualThirdPartyRegistrations then
			for frameName, bool in pairs(thirdPartyFrameNames) do
				local frame = _G[frameName]

				if frame and frame.unit == unit then
					return frame
				end
			end
		end

		return nil
	end
end

function Private.Utils.CreateEditablePopup(title, text, button1)
	return {
		text = title,
		button1 = button1,
		hasEditBox = true,
		hasWideEditBox = true,
		editBoxWidth = 350,
		hideOnEscape = true,
		OnShow = function(popupSelf)
			local editBox = popupSelf:GetEditBox()
			editBox:SetText(text)
			editBox:HighlightText()

			local ctrlDown = false

			editBox:SetScript("OnKeyDown", function(_, key)
				if key == "LCTRL" or key == "RCTRL" or key == "LMETA" or key == "RMETA" then
					ctrlDown = true
				end
			end)
			editBox:SetScript("OnKeyUp", function(_, key)
				C_Timer.After(0.2, function()
					ctrlDown = false
				end)

				if ctrlDown and (key == "C" or key == "X") then
					StaticPopup_Hide(addonName)
				end
			end)
		end,
		EditBoxOnEscapePressed = function(popupSelf)
			popupSelf:GetParent():Hide()
		end,
		EditBoxOnTextChanged = function(popupSelf)
			-- ctrl + x sets the text to "" but this triggers hiding and shouldn't trigger resetting the text
			local currentText = popupSelf:GetText()

			if currentText == "" or currentText == text then
				return
			end

			popupSelf:SetText(text)
		end,
	}
end

function Private.Utils.ShowStaticPopup(args)
	args.id = addonName
	args.whileDead = true

	StaticPopupDialogs[addonName] = args

	StaticPopup_Hide(addonName)
	StaticPopup_Show(addonName)
end

local function DecodeProfileString(string)
	return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecodeBase64(string))
end

do
	---@type table<string, Frame|nil>
	local editModeFrameByKind = {
		[Private.Enum.FrameKind.Self] = nil,
		[Private.Enum.FrameKind.Party] = nil,
	}

	function Private.Utils.RegisterEditModeFrame(frameKind, frame)
		editModeFrameByKind[frameKind] = frame
	end

	function Private.Utils.GetEditModeFrame(frameKind)
		return editModeFrameByKind[frameKind]
	end

	function Private.Utils.Import(string)
		local ok, result = pcall(DecodeProfileString, string)

		if not ok then
			if result ~= nil then
				print(result)
			end

			return false
		end

		-- just a type check
		if result == nil then
			return false
		end

		local hasAnyChange = false

		for kind, kindString in pairs(Private.Enum.FrameKind) do
			local tableRef = TargetedSpellsSaved.Settings[kind]

			if kindString == Private.Enum.FrameKind.Self then
				local frame = editModeFrameByKind[kindString]

				local point, x, y = result[kind].Position.point, result[kind].Position.x, result[kind].Position.y

				if
					frame ~= nil
					and (point ~= tableRef.Position.point or x ~= tableRef.Position.x or y ~= tableRef.Position.y)
				then
					frame:ClearAllPoints()
					PixelUtil.SetPoint(frame, point, UIParent, "CENTER", x, y)
					tableRef.Position.point = point
					tableRef.Position.x = x
					tableRef.Position.y = y
					Private.EventRegistry:TriggerEvent(Private.Enum.Events.EDIT_MODE_POSITION_CHANGED, point, x, y)
				end
			end

			local anyPrimaryLoadConditionIsDisabled = false

			local defaults = kindString == Private.Enum.FrameKind.Self and Private.Settings.GetSelfDefaultSettings()
				or Private.Settings.GetPartyDefaultSettings()
			local eventKeys = kindString == Private.Enum.FrameKind.Self and Private.Settings.Keys.Self
				or Private.Settings.Keys.Party

			for key, defaultValue in pairs(defaults) do
				local newValue = result[kind][key]
				local expectedType = type(defaultValue)

				if newValue ~= nil and type(newValue) == expectedType then
					local eventKey = eventKeys[key]
					local hasChanges = false

					if expectedType == "table" then
						local enumToCompareAgainst = nil
						if key == "LoadConditionContentType" then
							enumToCompareAgainst = Private.Enum.ContentType
						elseif key == "LoadConditionRole" then
							enumToCompareAgainst = Private.Enum.Role
						elseif key == "FontFlags" then
							enumToCompareAgainst = Private.Enum.FontFlags
						end

						-- only other case is Position but that's taken care of above

						if enumToCompareAgainst then
							local newTable = {}
							local allDisabled = true

							for _, id in pairs(enumToCompareAgainst) do
								if newValue[id] == nil then
									newTable[id] = tableRef[key][id]
								else
									newTable[id] = newValue[id]

									if newValue[id] ~= tableRef[key][id] then
										hasChanges = true
									end

									if newValue[id] then
										allDisabled = false
									end
								end
							end

							if allDisabled then
								anyPrimaryLoadConditionIsDisabled = true
							end

							if hasChanges then
								tableRef[key] = newTable
								Private.EventRegistry:TriggerEvent(
									Private.Enum.Events.SETTING_CHANGED,
									eventKey,
									newTable
								)
							end
						end
					elseif newValue ~= tableRef[key] then
						tableRef[key] = newValue
						hasChanges = true

						if eventKey and hasChanges then
							Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, eventKey, newValue)
						end
					end

					if hasChanges then
						hasAnyChange = true
					end
				end
			end

			if anyPrimaryLoadConditionIsDisabled then
				tableRef.Enabled = false
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, eventKeys.Enabled, false)
			end
		end

		return hasAnyChange
	end

	function Private.Utils.Export()
		return C_EncodingUtil.EncodeBase64(C_EncodingUtil.SerializeCBOR(TargetedSpellsSaved.Settings))
	end
end

do
	local function noop() end

	_G.TargetedSpellsAPI = {
		Import = Private.Utils.Import,
		Export = Private.Utils.Export,
		DecodeProfileString = DecodeProfileString,
		RegisterFrameByName = Private.Utils.RegisterFrameByName,
		UnregisterFrameByName = Private.Utils.UnregisterFrameByName,
		SetProfile = noop,
		GetProfileKeys = function()
			return { "Global" }
		end,
		GetCurrentProfileKey = function()
			return "Global"
		end,
		OpenConfig = noop,
		CloseConfig = noop,
	}
end
