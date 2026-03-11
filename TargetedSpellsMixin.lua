---@type string, TargetedSpells
local _, Private = ...
local LibEditMode = LibStub("LibEditMode")

local PreviewIconDataProvider = nil

---@return IconDataProviderMixin
local function GetRandomIcon()
	if PreviewIconDataProvider == nil then
		PreviewIconDataProvider =
			CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.Spellbook, true)
	end

	return PreviewIconDataProvider:GetRandomIcon()
end

---@param border Frame
local function CreateBorderStrips(border)
	---@param p1 string
	---@param p2 string
	---@param dimension string
	local function Strip(p1, p2, dimension)
		local texture = border:CreateTexture(nil, "BACKGROUND")

		texture:SetColorTexture(1, 1, 1, 0.8)
		texture:SetPoint(p1, border, p1)
		texture:SetPoint(p2, border, p2)

		if dimension == "h" then
			texture:SetHeight(1)
		else
			texture:SetWidth(1)
		end
	end

	Strip("TOPLEFT", "TOPRIGHT", "h")
	Strip("BOTTOMLEFT", "BOTTOMRIGHT", "h")
	Strip("TOPLEFT", "BOTTOMLEFT", "w")
	Strip("TOPRIGHT", "BOTTOMRIGHT", "w")
end

---@class TargetedSpellsMixin
TargetedSpellsMixin = {}

function TargetedSpellsMixin:OnLoad()
	Private.EventRegistry:RegisterCallback(Private.Enum.Events.SETTING_CHANGED, self.OnSettingChanged, self)

	self.Cooldown:SetCountdownFont("GameFontHighlightHugeOutline")
	self.wasInterrupted = false
	self.doNotHideBefore = nil
	self.elapsed = 0
	Private.Utils.MaybeApplyElvUISkin(self)
	CreateBorderStrips(self.Border)
end

function TargetedSpellsMixin:SetId(id)
	self.id = id
end

function TargetedSpellsMixin:GetId()
	return self.id
end

function TargetedSpellsMixin:SetInterrupted(name, color)
	self.wasInterrupted = true
	self.doNotHideBefore = GetTime() + 0.95
	self.InterruptIcon:Show()
	self.Icon:SetDesaturated(true)
	self.Cooldown:SetDrawSwipe(false)
	self:SetShowDuration(false, false)
	self:HideGlow()

	if name == nil then
		return
	end

	local renderInterruptSourceName = false

	if self.kind == Private.Enum.FrameKind.Self then
		renderInterruptSourceName = TargetedSpellsSaved.Settings.Self.RenderInterruptSourceName
	else
		renderInterruptSourceName = TargetedSpellsSaved.Settings.Party.RenderInterruptSourceName
	end

	if renderInterruptSourceName then
		self.InterruptSource:SetText(name)

		if color ~= nil then
			self.InterruptSource:SetTextColor(color.r, color.g, color.b)
		end
	end

	self.InterruptSource:Show()
end

function TargetedSpellsMixin:CanBeHidden(id)
	if self.wasInterrupted then
		return GetTime() >= self.doNotHideBefore
	end

	if id == nil then
		return true
	end

	return id == self:GetId()
end

function TargetedSpellsMixin:OnUpdate(elapsed)
	self.elapsed = self.elapsed + elapsed

	if self.elapsed < 0.1 then
		return
	end

	self.elapsed = self.elapsed - 0.1

	if self.duration == nil then
		return
	end

	local remainingDuration = type(self.duration) == "number" and self.startTime + self.duration - GetTime()
		or self.duration:GetRemainingDuration()

	self.DurationText:SetFormattedText("%.1f", remainingDuration)
end

function TargetedSpellsMixin:SetShowDuration(showDuration, showFractions)
	self.Cooldown:SetHideCountdownNumbers(not showDuration or showFractions)
	self.DurationText:SetShown(showDuration and showFractions)
	self:SetScript("OnUpdate", showDuration and showFractions and self.OnUpdate or nil)
end

function TargetedSpellsMixin:SetShowBorder(bool)
	if bool then
		self.Border:Show()
	else
		self.Border:Hide()
	end
end

--- shamelessly ~~stolen~~ repurposed from WeakAuras2
function TargetedSpellsMixin:OnSizeChanged()
	local tableRef = self.kind == Private.Enum.FrameKind.Self and TargetedSpellsSaved.Settings.Self
		or TargetedSpellsSaved.Settings.Party
	local width = tableRef.Width
	local height = tableRef.Height

	local coordinates = { 0, 0, 0, 1, 1, 0, 1, 1 }
	local aspectRatio = width / height

	local xRatio = aspectRatio < 1 and aspectRatio or 1
	local yRatio = aspectRatio > 1 and 1 / aspectRatio or 1

	for i = 1, #coordinates, 1 do
		local coordinate = coordinates[i]

		if i % 2 == 1 then
			coordinates[i] = (coordinate - 0.5) * xRatio + 0.5
		else
			coordinates[i] = (coordinate - 0.5) * yRatio + 0.5
		end
	end

	self.Icon:SetTexCoord(unpack(coordinates))

	local topleftRelativePoint = select(2, self.Overlay:GetPointByName("TOPLEFT"))
	local bottomrightRelativePoint = select(2, self.Overlay:GetPointByName("BOTTOMRIGHT"))
	self.Overlay:ClearAllPoints()

	do
		local fifteenPercent = 0.15 * width
		PixelUtil.SetPoint(self.Overlay, "TOPLEFT", topleftRelativePoint, "TOPLEFT", -fifteenPercent, fifteenPercent)
	end

	do
		local fifteenPercent = 0.15 * height
		PixelUtil.SetPoint(
			self.Overlay,
			"BOTTOMRIGHT",
			bottomrightRelativePoint,
			"BOTTOMRIGHT",
			fifteenPercent,
			-fifteenPercent
		)
	end
end

function TargetedSpellsMixin:OnSettingChanged(key, value)
	if self.kind == Private.Enum.FrameKind.Self then
		if key == Private.Settings.Keys.Self.Width then
			PixelUtil.SetSize(self, value, TargetedSpellsSaved.Settings.Self.Height)
		elseif key == Private.Settings.Keys.Self.Height then
			PixelUtil.SetSize(self, TargetedSpellsSaved.Settings.Self.Width, value)
		elseif key == Private.Settings.Keys.Self.ShowDuration then
			---@diagnostic disable-next-line: param-type-mismatch
			self:SetShowDuration(value, TargetedSpellsSaved.Settings.Self.ShowDurationFractions)
		elseif key == Private.Settings.Keys.Self.FontSize then
			self:SetFontSize()
		elseif key == Private.Settings.Keys.Self.Font or key == Private.Settings.Keys.Self.FontFlags then
			self:SetFont()
		elseif key == Private.Settings.Keys.Self.Opacity then
			self:SetAlpha(value)
		elseif key == Private.Settings.Keys.Self.ShowBorder then
			---@diagnostic disable-next-line: param-type-mismatch
			self:SetShowBorder(value)
		elseif key == Private.Settings.Keys.Self.GlowType then
			self:HideGlow()

			if TargetedSpellsSaved.Settings.Self.GlowImportant then
				self:ShowGlow(self:IsSpellImportant(LibEditMode:IsInEditMode() and Private.Utils.RollDice()))
			end
		elseif key == Private.Settings.Keys.Self.ShowDurationFractions then
			self:SetScript("OnUpdate", value and self.OnUpdate or nil)
			---@diagnostic disable-next-line: param-type-mismatch
			self.Cooldown:SetHideCountdownNumbers(value)
			---@diagnostic disable-next-line: param-type-mismatch
			self.DurationText:SetShown(value)
		elseif key == Private.Settings.Keys.Self.ShowSwipe then
			---@diagnostic disable-next-line: param-type-mismatch
			self.Cooldown:SetDrawSwipe(value)
		end
	else
		if key == Private.Settings.Keys.Party.Width then
			PixelUtil.SetSize(self, value, TargetedSpellsSaved.Settings.Party.Height)
		elseif key == Private.Settings.Keys.Party.Height then
			PixelUtil.SetSize(self, TargetedSpellsSaved.Settings.Party.Width, value)
		elseif key == Private.Settings.Keys.Party.ShowDuration then
			---@diagnostic disable-next-line: param-type-mismatch
			self:SetShowDuration(value, TargetedSpellsSaved.Settings.Party.ShowDurationFractions)
		elseif key == Private.Settings.Keys.Party.FontSize then
			self:SetFontSize()
		elseif key == Private.Settings.Keys.Party.Font or key == Private.Settings.Keys.Party.FontFlags then
			self:SetFont()
		elseif key == Private.Settings.Keys.Party.Opacity then
			self:SetAlpha(value)
		elseif key == Private.Settings.Keys.Party.ShowBorder then
			---@diagnostic disable-next-line: param-type-mismatch
			self:SetShowBorder(value)
		elseif key == Private.Settings.Keys.Party.GlowType then
			self:HideGlow()

			if TargetedSpellsSaved.Settings.Party.GlowImportant then
				self:ShowGlow(self:IsSpellImportant(LibEditMode:IsInEditMode() and Private.Utils.RollDice()))
			end
		elseif key == Private.Settings.Keys.Party.ShowDurationFractions then
			self:SetScript("OnUpdate", value and self.OnUpdate or nil)
			---@diagnostic disable-next-line: param-type-mismatch
			self.Cooldown:SetHideCountdownNumbers(value)
			---@diagnostic disable-next-line: param-type-mismatch
			self.DurationText:SetShown(value)
		elseif key == Private.Settings.Keys.Party.ShowSwipe then
			---@diagnostic disable-next-line: param-type-mismatch
			self.Cooldown:SetDrawSwipe(value)
		end
	end
end

function TargetedSpellsMixin:SetDuration(duration)
	self.duration = duration

	if type(duration) == "number" then
		self.Cooldown:SetCooldown(self.startTime, duration)
	else
		self.Cooldown:SetCooldownFromDurationObject(duration)
	end
end

function TargetedSpellsMixin:GetDuration()
	return self.duration
end

function TargetedSpellsMixin:SetStartTime(startTime)
	self.startTime = startTime or GetTime()
end

function TargetedSpellsMixin:GetStartTime()
	return self.startTime
end

---@param parent Frame
---@param width number
---@param height number
local function CreateStar4Glow(parent, width, height)
	local innerFactor = 1.9
	local outerFactor = 2.2

	local Star4 = CreateFrame("Frame", nil, parent)
	Star4:SetPoint("CENTER")
	Star4:SetFrameStrata(parent:GetFrameStrata())
	Star4:SetFrameLevel(parent:GetFrameLevel() + 1)
	PixelUtil.SetSize(Star4, width * innerFactor, height * innerFactor)

	local Inner = Star4:CreateTexture(nil, "OVERLAY")
	Inner:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	Inner:SetBlendMode("ADD")
	Inner:SetAlpha(0.9)
	Inner:SetVertexColor(1, 0.85, 0.25)
	Inner:SetPoint("CENTER")
	PixelUtil.SetSize(Inner, width * innerFactor, height * innerFactor)
	Star4.Inner = Inner

	local Outer = Star4:CreateTexture(nil, "OVERLAY")
	Outer:SetTexture("Interface\\Cooldown\\star4")
	Outer:SetBlendMode("ADD")
	Outer:SetAlpha(0.6)
	Outer:SetVertexColor(1, 0.75, 0.2)
	Outer:SetPoint("CENTER")
	PixelUtil.SetSize(Outer, width * outerFactor, height * outerFactor)
	Star4.Outer = Outer

	local Animation = Star4:CreateAnimationGroup()
	local Pulse = Animation:CreateAnimation("Alpha")
	Pulse:SetFromAlpha(0.35)
	Pulse:SetToAlpha(0.75)
	Pulse:SetDuration(0.75)
	Pulse:SetSmoothing("IN_OUT")
	Animation:SetLooping("BOUNCE")
	Star4.Animation = Animation

	return Star4
end

function TargetedSpellsMixin:ShowGlow(isImportant)
	local tableRef = self.kind == Private.Enum.FrameKind.Self and TargetedSpellsSaved.Settings.Self
		or TargetedSpellsSaved.Settings.Party
	local glowType = tableRef.GlowType

	if glowType == Private.Enum.GlowType.Star4 then
		if self._Star4 == nil then
			self._Star4 = CreateStar4Glow(self, tableRef.Width, tableRef.Height)
		end

		self._Star4:Show()
		self._Star4.Inner:Show()
		self._Star4.Outer:Show()
		self._Star4.Animation:Play()

		self._Star4:SetAlphaFromBoolean(isImportant)
	elseif glowType == Private.Enum.GlowType.PixelGlow then
		Private.Glows.PixelGlow_Start(self, tableRef.Width, tableRef.Height)

		self._PixelGlow:SetAlphaFromBoolean(isImportant)
	elseif glowType == Private.Enum.GlowType.AutoCastGlow then
		Private.Glows.AutoCastGlow_Start(self, tableRef.Width, tableRef.Height)

		self._AutoCastGlow:SetAlphaFromBoolean(isImportant)
	elseif glowType == Private.Enum.GlowType.ButtonGlow then
		Private.Glows.ButtonGlow_Start(self, tableRef.Width, tableRef.Height)

		self._ButtonGlow:SetAlphaFromBoolean(isImportant)

		for _, region in pairs({ self._ButtonGlow:GetRegions() }) do
			region:SetAlphaFromBoolean(isImportant)
		end

		---@type ButtonGlowFrame
		local ButtonGlow = self._ButtonGlow
		if ButtonGlow.AnimIn:IsPlaying() then
			local orig = ButtonGlow.AnimIn:GetScript("OnFinished")
			ButtonGlow.AnimIn:SetScript("OnFinished", function(anim)
				orig(anim)
				anim:GetParent().Ants:SetAlphaFromBoolean(isImportant)
				anim:SetScript("OnFinished", orig)
			end)
		end
	elseif glowType == Private.Enum.GlowType.ProcGlow then
		Private.Glows.ProcGlow_Start(self, tableRef.Width, tableRef.Height)

		self._ProcGlow:SetAlphaFromBoolean(isImportant)
	end
end

function TargetedSpellsMixin:HideGlow()
	if self._Star4 ~= nil then
		self._Star4:Hide()
		self._Star4.Inner:Hide()
		self._Star4.Outer:Hide()
		self._Star4.Animation:Stop()
	end

	Private.Glows.PixelGlow_Stop(self)
	Private.Glows.AutoCastGlow_Stop(self)
	Private.Glows.ButtonGlow_Stop(self)
	Private.Glows.ProcGlow_Stop(self)
end

function TargetedSpellsMixin:IsSpellImportant(boolOverride)
	if boolOverride ~= nil then
		return boolOverride
	end

	if self.spellId == nil then
		return false
	end

	return C_Spell.IsSpellImportant(self.spellId)
end

function TargetedSpellsMixin:SetSpellId(spellId)
	self.spellId = spellId
	local texture = spellId and C_Spell.GetSpellTexture(spellId) or GetRandomIcon()
	self.Icon:SetTexture(texture)

	if
		spellId ~= nil
		and (
			(self.kind == Private.Enum.FrameKind.Self and TargetedSpellsSaved.Settings.Self.GlowImportant)
			or (self.kind == Private.Enum.FrameKind.Party and TargetedSpellsSaved.Settings.Party.GlowImportant)
		)
	then
		self:ShowGlow(self:IsSpellImportant())
	end
end

function TargetedSpellsMixin:ShouldBeShown()
	return self.startTime ~= nil
end

function TargetedSpellsMixin:ClearStartTime()
	self.startTime = nil
end

function TargetedSpellsMixin:Reposition(point, relativeTo, relativePoint, offsetX, offsetY)
	self:SetParent(relativeTo)
	self:ClearAllPoints()
	self:SetFrameLevel(relativeTo:GetFrameLevel() + 10)
	PixelUtil.SetPoint(self, point, relativeTo, relativePoint, offsetX, offsetY)
	self:Show()
end

function TargetedSpellsMixin:SetUnit(unit)
	self.unit = unit
end

function TargetedSpellsMixin:SetKind(kind)
	if self.kind == kind then
		return
	end

	self.kind = kind

	local tableRef = kind == Private.Enum.FrameKind.Self and TargetedSpellsSaved.Settings.Self
		or TargetedSpellsSaved.Settings.Party

	PixelUtil.SetSize(self, tableRef.Width, tableRef.Height)
	self:SetFontSize()
	self:SetFont()
	self:HideGlow()
	self:SetShowBorder(tableRef.ShowBorder)
	self:SetAlpha(tableRef.Opacity)
	self:SetShowDuration(tableRef.ShowDuration, tableRef.ShowDurationFractions)
	self.Cooldown:SetDrawSwipe(tableRef.ShowSwipe)
end

function TargetedSpellsMixin:GetKind()
	return self.kind
end

function TargetedSpellsMixin:GetUnit()
	return self.unit
end

function TargetedSpellsMixin:PostCreate(unit, kind, castingUnit, bar)
	self:SetUnit(unit)
	self:SetKind(kind)

	if castingUnit ~= nil then
		if kind == Private.Enum.FrameKind.Self then
			self:SetAlphaFromBoolean(PlayerIsSpellTarget(castingUnit, unit))
		else
			self:SetAlphaFromBoolean(UnitIsUnit(string.format("%starget", castingUnit), unit))
		end
	end

	if bar ~= nil then
		self.bar = bar
		bar:SetValue(self:GetAlpha())
	end
end

function TargetedSpellsMixin:Reset()
	self:ClearStartTime()
	self.spellId = nil
	self.Cooldown:Clear()
	self.duration = nil
	self:ClearAllPoints()
	self.wasInterrupted = false
	self.doNotHideBefore = nil
	self.InterruptIcon:Hide()
	self.Icon:SetDesaturated(false)
	self:SetId()
	self.InterruptSource:SetText()
	self.InterruptSource:Hide()
	self.InterruptSource:SetTextColor(1, 1, 1)

	local tableRef = self.kind == Private.Enum.FrameKind.Self and TargetedSpellsSaved.Settings.Self
		or TargetedSpellsSaved.Settings.Party

	if tableRef.GlowImportant then
		local glowType = tableRef.GlowType

		if glowType == Private.Enum.GlowType.PixelGlow then
			if self._PixelGlow ~= nil then
				self._PixelGlow:SetAlpha(1)
			end
		elseif glowType == Private.Enum.GlowType.AutoCastGlow then
			if self._AutoCastGlow ~= nil then
				self._AutoCastGlow:SetAlpha(1)
			end
		elseif glowType == Private.Enum.GlowType.ButtonGlow then
			if self._ButtonGlow ~= nil then
				self._ButtonGlow:SetAlpha(1)

				for _, region in pairs({ self._ButtonGlow:GetRegions() }) do
					region:SetAlpha(1)
				end
			end
		elseif glowType == Private.Enum.GlowType.ProcGlow then
			if self._ProcGlow ~= nil then
				self._ProcGlow:SetAlpha(1)
			end
		end
	end

	self:HideGlow()

	self:SetShowDuration(tableRef.ShowDuration, tableRef.ShowDurationFractions)
	self.Cooldown:SetDrawSwipe(tableRef.ShowSwipe)
	-- important to come last - the cooldown swipe ignores display status of its parent
	self:Hide()
end

function TargetedSpellsMixin:SetFontSize()
	local tableRef = self.kind == Private.Enum.FrameKind.Self and TargetedSpellsSaved.Settings.Self
		or TargetedSpellsSaved.Settings.Party

	local fontString = nil

	if tableRef.ShowDurationFractions then
		fontString = self.DurationText
	else
		fontString = self.Cooldown:GetCountdownFontString()
	end

	local font, size, flags = fontString:GetFont()

	if size == tableRef.FontSize then
		return
	end

	fontString:SetFont(font, tableRef.FontSize, flags)
end

function TargetedSpellsMixin:SetFont()
	local tableRef = self.kind == Private.Enum.FrameKind.Self and TargetedSpellsSaved.Settings.Self
		or TargetedSpellsSaved.Settings.Party

	local fontString = nil

	if tableRef.ShowDurationFractions then
		fontString = self.DurationText
	else
		fontString = self.Cooldown:GetCountdownFontString()
	end

	fontString:SetFont(
		tableRef.Font,
		tableRef.FontSize,
		tableRef.FontFlags[Private.Enum.FontFlags.OUTLINE] and "OUTLINE" or ""
	)

	if tableRef.FontFlags[Private.Enum.FontFlags.SHADOW] then
		fontString:SetShadowOffset(1, -1)
		fontString:SetShadowColor(0, 0, 0, 1)
	else
		fontString:SetShadowOffset(0, 0)
	end
end
