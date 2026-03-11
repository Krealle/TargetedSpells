-- MIT License

-- Copyright (c) 2022 Benjamin Staneck

-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

-- this file is a modified version of LibCustomGlow due to the methods below calling frame:GetSize().
-- in my use case in this addon, these values are situationally secret and thus you cannot perform any logic on them.
-- instead, methods have been modified to accept width/height as arguments to circumvent this.
-- additionally, I've also largely added types, cleaned up one character variables etc and made some stylistic adjustments.

---@diagnostic disable: undefined-field, inject-field

---@type string, TargetedSpells
local _, Private = ...

---@diagnostic disable-next-line: missing-fields
Private.Glows = {}

local textureList = {
	empty = [[Interface\AdventureMap\BrokenIsles\AM_29]],
	white = [[Interface\BUTTONS\WHITE8X8]],
	shine = [[Interface\Artifacts\Artifacts]],
}
local shineCoords = { 0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625 }
local GlowParent = UIParent

local GlowMaskPool = {
	createFunc = function(self)
		return self.parent:CreateMaskTexture()
	end,
	resetFunc = function(_, mask)
		mask:Hide()
		mask:ClearAllPoints()
	end,
	AddObject = function(self, object)
		self.activeObjects[object] = true
		self.activeObjectCount = self.activeObjectCount + 1
	end,
	ReclaimObject = function(self, object)
		tinsert(self.inactiveObjects, object)
		self.activeObjects[object] = nil
		self.activeObjectCount = self.activeObjectCount - 1
	end,
	Release = function(self, object)
		local active = self.activeObjects[object] ~= nil

		if active then
			self:resetFunc(object)
			self:ReclaimObject(object)
		end

		return active
	end,
	Acquire = function(self)
		local object = tremove(self.inactiveObjects)
		local isNew = object == nil

		if isNew then
			object = self:createFunc()
			self:resetFunc(object, isNew)
		end

		self:AddObject(object)

		return object, isNew
	end,
	Init = function(self, parent)
		self.activeObjects = {}
		self.inactiveObjects = {}
		self.activeObjectCount = 0
		self.parent = parent
	end,
}

---@type FramePool<GlowFrame>
local GlowFramePool

local GlowTexPool

local function EnsureSharedPools()
	if GlowFramePool then
		return
	end

	GlowMaskPool:Init(GlowParent)

	GlowTexPool = CreateTexturePool(
		GlowParent,
		"ARTWORK",
		7,
		nil,
		---@param tex Texture
		function(_, tex)
			local maskNum = tex:GetNumMaskTextures()

			for Idx = maskNum, 1, -1 do
				tex:RemoveMaskTexture(tex:GetMaskTexture(Idx))
			end

			tex:Hide()
			tex:ClearAllPoints()
		end
	)

	GlowFramePool = CreateFramePool(
		"Frame",
		GlowParent,
		nil,
		---@param frame GlowFrame
		function(_, frame)
			frame:SetScript("OnUpdate", nil)

			local parent = frame:GetParent()
			if parent and parent[frame.name] then
				parent[frame.name] = nil
			end

			if frame.textures then
				for _, texture in pairs(frame.textures) do
					GlowTexPool:Release(texture)
				end
			end

			if frame.bg then
				GlowTexPool:Release(frame.bg)
				frame.bg = nil
			end

			if frame.masks then
				for _, mask in pairs(frame.masks) do
					GlowMaskPool:Release(mask)
				end
				frame.masks = nil
			end

			frame.textures = {}
			frame.info = {}
			frame.name = nil
			frame.timer = nil
			frame:Hide()
			frame:ClearAllPoints()
		end
	)
end

---@param frame Frame
---@param color number[]|ColorMixin
---@param name string
---@param count number
---@param texture string
---@param texCoord number[]
---@param desaturated boolean?
---@return GlowFrame
local function AddFrameAndTex(frame, color, name, count, texture, texCoord, desaturated)
	EnsureSharedPools()

	if not frame[name] then
		frame[name] = GlowFramePool:Acquire()
		frame[name]:SetParent(frame)
		frame[name].name = name
	end

	---@type GlowFrame
	local GlowFrame = frame[name]
	GlowFrame:SetFrameLevel(frame:GetFrameLevel() + 8)
	GlowFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0.05, 0.05)
	GlowFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0.05)
	GlowFrame:Show()

	if not GlowFrame.textures then
		GlowFrame.textures = {}
	end

	for Idx = 1, count do
		if not GlowFrame.textures[Idx] then
			GlowFrame.textures[Idx] = GlowTexPool:Acquire()
			GlowFrame.textures[Idx]:SetTexture(texture)
			GlowFrame.textures[Idx]:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4])
			GlowFrame.textures[Idx]:SetDesaturated(desaturated)
			GlowFrame.textures[Idx]:SetParent(GlowFrame)
			GlowFrame.textures[Idx]:SetDrawLayer("ARTWORK", 7)
		end

		if type(color) == "table" and color.GetRGBA then
			GlowFrame.textures[Idx]:SetVertexColor(color:GetRGBA())
		else
			GlowFrame.textures[Idx]:SetVertexColor(color[1], color[2], color[3], color[4])
		end

		GlowFrame.textures[Idx]:Show()
	end

	while #GlowFrame.textures > count do
		GlowTexPool:Release(GlowFrame.textures[#GlowFrame.textures])
		table.remove(GlowFrame.textures)
	end

	return GlowFrame
end

do
	local color = { 0.95, 0.95, 0.32, 1 }
	local count = 8
	local th = 1

	---@param progress number
	---@param size number
	---@param thickness number
	---@param phases table
	---@return number
	local function PCalc1(progress, size, thickness, phases)
		local coord

		if progress > phases[3] or progress < phases[0] then
			coord = 0
		elseif progress > phases[2] then
			coord = size - thickness - (progress - phases[2]) / (phases[3] - phases[2]) * (size - thickness)
		elseif progress > phases[1] then
			coord = size - thickness
		else
			coord = (progress - phases[0]) / (phases[1] - phases[0]) * (size - thickness)
		end

		return math.floor(coord + 0.5)
	end

	---@param progress number
	---@param size number
	---@param thickness number
	---@param phases table
	---@return number
	local function PCalc2(progress, size, thickness, phases)
		local coord

		if progress > phases[3] then
			coord = size - thickness - (progress - phases[3]) / (phases[0] + 1 - phases[3]) * (size - thickness)
		elseif progress > phases[2] then
			coord = size - thickness
		elseif progress > phases[1] then
			coord = (progress - phases[1]) / (phases[2] - phases[1]) * (size - thickness)
		elseif progress > phases[0] then
			coord = 0
		else
			coord = size - thickness - (progress + 1 - phases[3]) / (phases[0] + 1 - phases[3]) * (size - thickness)
		end

		return math.floor(coord + 0.5)
	end

	---@param self GlowFrame
	---@param elapsed number
	local function PUpdate(self, elapsed)
		self.timer = self.timer + elapsed / self.info.period

		if self.timer > 1 or self.timer < -1 then
			self.timer = self.timer % 1
		end

		local progress = self.timer
		local width = self.info.width
		local height = self.info.height

		if self.info.needsUpdate then
			self.info.needsUpdate = nil
			local perimeter = 2 * (width + height)

			if not (perimeter > 0) then
				return
			end

			self.info.width = width
			self.info.height = height
			self.info.pTLx = {
				[0] = (height + self.info.length / 2) / perimeter,
				[1] = (height + width + self.info.length / 2) / perimeter,
				[2] = (2 * height + width - self.info.length / 2) / perimeter,
				[3] = 1 - self.info.length / 2 / perimeter,
			}
			self.info.pTLy = {
				[0] = (height - self.info.length / 2) / perimeter,
				[1] = (height + width + self.info.length / 2) / perimeter,
				[2] = (height * 2 + width + self.info.length / 2) / perimeter,
				[3] = 1 - self.info.length / 2 / perimeter,
			}
			self.info.pBRx = {
				[0] = self.info.length / 2 / perimeter,
				[1] = (height - self.info.length / 2) / perimeter,
				[2] = (height + width - self.info.length / 2) / perimeter,
				[3] = (height * 2 + width + self.info.length / 2) / perimeter,
			}
			self.info.pBRy = {
				[0] = self.info.length / 2 / perimeter,
				[1] = (height + self.info.length / 2) / perimeter,
				[2] = (height + width - self.info.length / 2) / perimeter,
				[3] = (height * 2 + width - self.info.length / 2) / perimeter,
			}
		end

		if self:IsShown() then
			if not (self.masks[1]:IsShown()) then
				self.masks[1]:Show()
				self.masks[1]:SetPoint("TOPLEFT", self, "TOPLEFT", self.info.th, -self.info.th)
				self.masks[1]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -self.info.th, self.info.th)
			end

			if self.masks[2] and not (self.masks[2]:IsShown()) then
				self.masks[2]:Show()
				self.masks[2]:SetPoint("TOPLEFT", self, "TOPLEFT", self.info.th + 1, -self.info.th - 1)
				self.masks[2]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -self.info.th - 1, self.info.th + 1)
			end

			if self.bg and not (self.bg:IsShown()) then
				self.bg:Show()
			end

			for index, line in pairs(self.textures) do
				line:SetPoint(
					"TOPLEFT",
					self,
					"TOPLEFT",
					PCalc1((progress + self.info.step * (index - 1)) % 1, width, self.info.th, self.info.pTLx),
					-PCalc2((progress + self.info.step * (index - 1)) % 1, height, self.info.th, self.info.pTLy)
				)
				line:SetPoint(
					"BOTTOMRIGHT",
					self,
					"TOPLEFT",
					self.info.th
						+ PCalc2((progress + self.info.step * (index - 1)) % 1, width, self.info.th, self.info.pBRx),
					-height
						+ PCalc1((progress + self.info.step * (index - 1)) % 1, height, self.info.th, self.info.pBRy)
				)
			end
		end
	end

	function Private.Glows.PixelGlow_Start(frame, width, height)
		if not frame then
			return
		end

		local length = math.floor((width + height) * (2 / count - 0.1))
		length = min(length, min(width, height))

		local GlowFrame = AddFrameAndTex(frame, color, "_PixelGlow", count, textureList.white, { 0, 1, 0, 1 })

		if not GlowFrame.masks then
			GlowFrame.masks = {}
		end

		if not GlowFrame.masks[1] then
			GlowFrame.masks[1] = GlowMaskPool:Acquire()
			GlowFrame.masks[1]:SetTexture(textureList.empty, "CLAMPTOWHITE", "CLAMPTOWHITE")
			GlowFrame.masks[1]:Show()
		end

		GlowFrame.masks[1]:SetPoint("TOPLEFT", GlowFrame, "TOPLEFT", th, -th)
		GlowFrame.masks[1]:SetPoint("BOTTOMRIGHT", GlowFrame, "BOTTOMRIGHT", -th, th)

		-- if not (border == false) then
		if not GlowFrame.masks[2] then
			GlowFrame.masks[2] = GlowMaskPool:Acquire()
			GlowFrame.masks[2]:SetTexture(textureList.empty, "CLAMPTOWHITE", "CLAMPTOWHITE")
		end

		GlowFrame.masks[2]:SetPoint("TOPLEFT", GlowFrame, "TOPLEFT", th + 1, -th - 1)
		GlowFrame.masks[2]:SetPoint("BOTTOMRIGHT", GlowFrame, "BOTTOMRIGHT", -th - 1, th + 1)

		if not GlowFrame.bg then
			GlowFrame.bg = GlowTexPool:Acquire()
			GlowFrame.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
			GlowFrame.bg:SetParent(GlowFrame)
			GlowFrame.bg:SetAllPoints(GlowFrame)
			GlowFrame.bg:SetDrawLayer("ARTWORK", 6)
			GlowFrame.bg:AddMaskTexture(GlowFrame.masks[2])
		end
		-- else
		-- 	if GlowFrame.bg then
		-- 		GlowTexPool:Release(GlowFrame.bg)
		-- 		GlowFrame.bg = nil
		-- 	end

		-- 	if GlowFrame.masks[2] then
		-- 		GlowMaskPool:Release(GlowFrame.masks[2])
		-- 		GlowFrame.masks[2] = nil
		-- 	end
		-- end

		for _, tex in pairs(GlowFrame.textures) do
			if tex:GetNumMaskTextures() < 1 then
				tex:AddMaskTexture(GlowFrame.masks[1])
			end
		end

		GlowFrame.timer = GlowFrame.timer or 0
		GlowFrame.info = GlowFrame.info or {}
		GlowFrame.info.step = 1 / count
		GlowFrame.info.period = 4
		GlowFrame.info.th = th
		GlowFrame.info.length = length
		if GlowFrame.info.width ~= width or GlowFrame.info.height ~= height then
			GlowFrame.info.width = width
			GlowFrame.info.height = height
			GlowFrame.info.needsUpdate = true
		end

		PUpdate(GlowFrame, 0)

		GlowFrame:SetScript("OnUpdate", PUpdate)
	end
end

function Private.Glows.PixelGlow_Stop(frame)
	if frame and frame._PixelGlow and GlowFramePool ~= nil then
		GlowFramePool:Release(frame._PixelGlow)
	end
end

do
	local color = { 0.95, 0.95, 0.32, 1 }
	local count = 4
	local sizes = { 7, 6, 5, 4 }

	---@param self Frame
	---@param elapsed number
	local function AutoCastGlowOnUpdate(self, elapsed)
		local width = self.info.width
		local height = self.info.height

		if self.info.needsUpdate then
			self.info.needsUpdate = nil
			if width * height == 0 then
				return
			end

			self.info.width = width
			self.info.height = height
			self.info.perimeter = 2 * (width + height)
			self.info.bottomlim = height * 2 + width
			self.info.rightlim = height + width
			self.info.space = self.info.perimeter / self.info.N
		end

		local TexIndex = 0
		for ring = 1, 4 do
			self.timer[ring] = self.timer[ring] + elapsed / (self.info.period * ring)

			if self.timer[ring] > 1 or self.timer[ring] < -1 then
				self.timer[ring] = self.timer[ring] % 1
			end

			for ParticleIdx = 1, self.info.N do
				TexIndex = TexIndex + 1
				local position = (self.info.space * ParticleIdx + self.info.perimeter * self.timer[ring])
					% self.info.perimeter
				if position > self.info.bottomlim then
					self.textures[TexIndex]:SetPoint("CENTER", self, "BOTTOMRIGHT", -position + self.info.bottomlim, 0)
				elseif position > self.info.rightlim then
					self.textures[TexIndex]:SetPoint("CENTER", self, "TOPRIGHT", 0, -position + self.info.rightlim)
				elseif position > self.info.height then
					self.textures[TexIndex]:SetPoint("CENTER", self, "TOPLEFT", position - self.info.height, 0)
				else
					self.textures[TexIndex]:SetPoint("CENTER", self, "BOTTOMLEFT", 0, position)
				end
			end
		end
	end

	function Private.Glows.AutoCastGlow_Start(frame, width, height)
		if not frame then
			return
		end

		local GlowFrame = AddFrameAndTex(frame, color, "_AutoCastGlow", count * 4, textureList.shine, shineCoords, true)

		for SizeIndex, size in pairs(sizes) do
			for ParticleIdx = 1, count do
				GlowFrame.textures[ParticleIdx + count * (SizeIndex - 1)]:SetSize(size, size)
			end
		end

		GlowFrame.timer = GlowFrame.timer or { 0, 0, 0, 0 }
		GlowFrame.info = GlowFrame.info or {}
		GlowFrame.info.N = count
		GlowFrame.info.period = 8
		if GlowFrame.info.width ~= width or GlowFrame.info.height ~= height then
			GlowFrame.info.width = width
			GlowFrame.info.height = height
			GlowFrame.info.needsUpdate = true
		end
		GlowFrame.info.perimeter = 2 * (width + height)
		GlowFrame.info.bottomlim = height * 2 + width
		GlowFrame.info.rightlim = height + width
		GlowFrame.info.space = GlowFrame.info.perimeter / count

		GlowFrame:SetScript("OnUpdate", AutoCastGlowOnUpdate)
		AutoCastGlowOnUpdate(GlowFrame, 0)
	end
end

function Private.Glows.AutoCastGlow_Stop(frame)
	if frame and frame._AutoCastGlow and GlowFramePool ~= nil then
		GlowFramePool:Release(frame._AutoCastGlow)
	end
end

---@param group AnimationGroup
---@param target string
---@param order number
---@param duration number
---@param scaleX number
---@param scaleY number
---@param delay number?
local function CreateScaleAnim(group, target, order, duration, scaleX, scaleY, delay)
	local scale = group:CreateAnimation("Scale")

	scale:SetChildKey(target)
	scale:SetOrder(order)
	scale:SetDuration(duration)
	scale:SetScale(scaleX, scaleY)

	if delay then
		scale:SetStartDelay(delay)
	end
end

---@param group ButtonGlowAnimGroup
---@param target string
---@param order number
---@param duration number
---@param fromAlpha number
---@param toAlpha number
---@param delay number?
---@param appear boolean
local function CreateAlphaAnim(group, target, order, duration, fromAlpha, toAlpha, delay, appear)
	local alpha = group:CreateAnimation("Alpha")

	alpha:SetChildKey(target)
	alpha:SetOrder(order)
	alpha:SetDuration(duration)
	alpha:SetFromAlpha(fromAlpha)
	alpha:SetToAlpha(toAlpha)

	if delay then
		alpha:SetStartDelay(delay)
	end

	if appear then
		table.insert(group.Appear, alpha)
	else
		table.insert(group.Fade, alpha)
	end
end

---@param group AnimationGroup
local function AnimInOnPlay(group)
	---@type ButtonGlowFrame
	local GlowFrame = group:GetParent()
	local width = GlowFrame.width * 1.4
	local height = GlowFrame.height * 1.4

	PixelUtil.SetSize(GlowFrame.Spark, width, height)
	GlowFrame.Spark:SetAlpha(not GlowFrame.color and 1.0 or 0.3 * GlowFrame.color[4])
	PixelUtil.SetSize(GlowFrame.InnerGlow, width / 2, height / 2)
	GlowFrame.InnerGlow:SetAlpha(not GlowFrame.color and 1.0 or GlowFrame.color[4])
	GlowFrame.InnerGlowOver:SetAlpha(not GlowFrame.color and 1.0 or GlowFrame.color[4])
	PixelUtil.SetSize(GlowFrame.OuterGlow, width * 2, height * 2)
	GlowFrame.OuterGlow:SetAlpha(not GlowFrame.color and 1.0 or GlowFrame.color[4])
	GlowFrame.OuterGlowOver:SetAlpha(not GlowFrame.color and 1.0 or GlowFrame.color[4])
	PixelUtil.SetSize(GlowFrame.Ants, width * 0.85, height * 0.85)
	GlowFrame.Ants:SetAlpha(0)

	GlowFrame:Show()
end

---@param group AnimationGroup
local function AnimInOnFinished(group)
	---@type ButtonGlowFrame
	local GlowFrame = group:GetParent()
	local width = GlowFrame.width * 1.4
	local height = GlowFrame.height * 1.4

	GlowFrame.Spark:SetAlpha(0)
	GlowFrame.InnerGlow:SetAlpha(0)
	PixelUtil.SetSize(GlowFrame.InnerGlow, width, height)
	GlowFrame.InnerGlowOver:SetAlpha(0.0)
	PixelUtil.SetSize(GlowFrame.OuterGlow, width, height)
	GlowFrame.OuterGlowOver:SetAlpha(0.0)
	PixelUtil.SetSize(GlowFrame.OuterGlowOver, width, height)
	GlowFrame.Ants:SetAlpha(not GlowFrame.color and 1.0 or GlowFrame.color[4])
end

---@param group AnimationGroup
local function AnimInOnStop(group)
	---@type ButtonGlowFrame
	local GlowFrame = group:GetParent()
	GlowFrame.Spark:SetAlpha(0)
	GlowFrame.InnerGlow:SetAlpha(0)
	GlowFrame.InnerGlowOver:SetAlpha(0.0)
	GlowFrame.OuterGlowOver:SetAlpha(0.0)
end

---@type FramePool<ButtonGlowFrame>?
local ButtonGlowPool = nil

---@param self ButtonGlowFrame
local function BgHide(self)
	if self.AnimOut:IsPlaying() then
		self.AnimOut:Stop()
		assert(ButtonGlowPool ~= nil)
		ButtonGlowPool:Release(self)
	end
end

local function EnsureButtonGlowPool()
	if ButtonGlowPool == nil then
		ButtonGlowPool = CreateFramePool(
			"Frame",
			GlowParent,
			nil,
			---@param glowFrame ButtonGlowFrame
			function(_, glowFrame)
				glowFrame:SetScript("OnUpdate", nil)

				local parent = glowFrame:GetParent()

				if parent and parent._ButtonGlow then
					parent._ButtonGlow = nil
				end

				glowFrame:Hide()
				glowFrame:ClearAllPoints()
			end,
			nil,
			function(frame)
				frame.Spark = frame:CreateTexture(nil, "BACKGROUND")
				frame.Spark:SetPoint("CENTER")
				frame.Spark:SetAlpha(0)
				frame.Spark:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
				frame.Spark:SetTexCoord(0.00781250, 0.61718750, 0.00390625, 0.26953125)

				frame.InnerGlow = frame:CreateTexture(nil, "ARTWORK")
				frame.InnerGlow:SetPoint("CENTER")
				frame.InnerGlow:SetAlpha(0)
				frame.InnerGlow:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
				frame.InnerGlow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)

				frame.InnerGlowOver = frame:CreateTexture(nil, "ARTWORK")
				frame.InnerGlowOver:SetPoint("TOPLEFT", frame.InnerGlow, "TOPLEFT")
				frame.InnerGlowOver:SetPoint("BOTTOMRIGHT", frame.InnerGlow, "BOTTOMRIGHT")
				frame.InnerGlowOver:SetAlpha(0)
				frame.InnerGlowOver:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
				frame.InnerGlowOver:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)

				frame.OuterGlow = frame:CreateTexture(nil, "ARTWORK")
				frame.OuterGlow:SetPoint("CENTER")
				frame.OuterGlow:SetAlpha(0)
				frame.OuterGlow:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
				frame.OuterGlow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)

				frame.OuterGlowOver = frame:CreateTexture(nil, "ARTWORK")
				frame.OuterGlowOver:SetPoint("TOPLEFT", frame.OuterGlow, "TOPLEFT")
				frame.OuterGlowOver:SetPoint("BOTTOMRIGHT", frame.OuterGlow, "BOTTOMRIGHT")
				frame.OuterGlowOver:SetAlpha(0)
				frame.OuterGlowOver:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
				frame.OuterGlowOver:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)

				frame.Ants = frame:CreateTexture(nil, "OVERLAY")
				frame.Ants:SetPoint("CENTER")
				frame.Ants:SetAlpha(0)
				frame.Ants:SetTexture([[Interface\SpellActivationOverlay\IconAlertAnts]])

				frame.AnimIn = frame:CreateAnimationGroup()
				frame.AnimIn.Appear = {}
				frame.AnimIn.Fade = {}
				CreateScaleAnim(frame.AnimIn, "Spark", 1, 0.2, 1.5, 1.5)
				CreateAlphaAnim(frame.AnimIn, "Spark", 1, 0.2, 0, 1, nil, true)
				CreateScaleAnim(frame.AnimIn, "InnerGlow", 1, 0.3, 2, 2)
				CreateScaleAnim(frame.AnimIn, "InnerGlowOver", 1, 0.3, 2, 2)
				CreateAlphaAnim(frame.AnimIn, "InnerGlowOver", 1, 0.3, 1, 0, nil, false)
				CreateScaleAnim(frame.AnimIn, "OuterGlow", 1, 0.3, 0.5, 0.5)
				CreateScaleAnim(frame.AnimIn, "OuterGlowOver", 1, 0.3, 0.5, 0.5)
				CreateAlphaAnim(frame.AnimIn, "OuterGlowOver", 1, 0.3, 1, 0, nil, false)
				CreateScaleAnim(frame.AnimIn, "Spark", 1, 0.2, 2 / 3, 2 / 3, 0.2)
				CreateAlphaAnim(frame.AnimIn, "Spark", 1, 0.2, 1, 0, 0.2, false)
				CreateAlphaAnim(frame.AnimIn, "InnerGlow", 1, 0.2, 1, 0, 0.3, false)
				CreateAlphaAnim(frame.AnimIn, "Ants", 1, 0.2, 0, 1, 0.3, true)
				frame.AnimIn:SetScript("OnPlay", AnimInOnPlay)
				frame.AnimIn:SetScript("OnStop", AnimInOnStop)
				frame.AnimIn:SetScript("OnFinished", AnimInOnFinished)

				frame.AnimOut = frame:CreateAnimationGroup()
				frame.AnimOut.Appear = {}
				frame.AnimOut.Fade = {}
				CreateAlphaAnim(frame.AnimOut, "OuterGlowOver", 1, 0.2, 0, 1, nil, true)
				CreateAlphaAnim(frame.AnimOut, "Ants", 1, 0.2, 1, 0, nil, false)
				CreateAlphaAnim(frame.AnimOut, "OuterGlowOver", 2, 0.2, 1, 0, nil, false)
				CreateAlphaAnim(frame.AnimOut, "OuterGlow", 2, 0.2, 1, 0, nil, false)
				frame.AnimOut:SetScript("OnFinished", function(self)
					assert(ButtonGlowPool ~= nil)
					ButtonGlowPool:Release(self:GetParent())
				end)

				frame:SetScript("OnHide", BgHide)
			end
		)
	end
end

---@param self ButtonGlowFrame
---@param elapsed number
local function ButtonGlowOnUpdate(self, elapsed)
	AnimateTexCoords(self.Ants, 256, 256, 48, 48, 22, elapsed, self.throttle)

	local cooldown = self:GetParent().cooldown
	local duration = cooldown and cooldown:IsShown() and cooldown:GetCooldownDuration()

	if (not issecretvalue or not issecretvalue(duration)) and duration and duration > 3000 then
		self:SetAlpha(0.5)
	else
		self:SetAlpha(1.0)
	end
end

---@param glowFrame ButtonGlowFrame
---@param alpha number
local function UpdateAlphaAnim(glowFrame, alpha)
	for _, anim in pairs(glowFrame.AnimIn.Appear) do
		anim:SetToAlpha(alpha)
	end
	for _, anim in pairs(glowFrame.AnimIn.Fade) do
		anim:SetFromAlpha(alpha)
	end
	for _, anim in pairs(glowFrame.AnimOut.Appear) do
		anim:SetToAlpha(alpha)
	end
	for _, anim in pairs(glowFrame.AnimOut.Fade) do
		anim:SetFromAlpha(alpha)
	end
end

local ButtonGlowTextures = {
	["Spark"] = true,
	["InnerGlow"] = true,
	["InnerGlowOver"] = true,
	["OuterGlow"] = true,
	["OuterGlowOver"] = true,
	["Ants"] = true,
}

---@param num number
---@return number
local function NoZero(num)
	return num == 0 and 0.001 or num
end

---@param frame Frame
---@param width number
---@param height number
function Private.Glows.ButtonGlow_Start(frame, width, height)
	if not frame then
		return
	end

	local frameLevel = 8
	local throttle = 0.01

	if frame._ButtonGlow then
		---@type ButtonGlowFrame
		local GlowFrame = frame._ButtonGlow
		GlowFrame.width = width
		GlowFrame.height = height

		GlowFrame:SetFrameLevel(frame:GetFrameLevel() + frameLevel)
		PixelUtil.SetSize(GlowFrame, width * 1.4, height * 1.4)
		GlowFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -width * 0.2, height * 0.2)
		GlowFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", width * 0.2, -height * 0.2)
		PixelUtil.SetSize(GlowFrame.Ants, width * 1.4 * 0.85, height * 1.4 * 0.85)

		AnimInOnFinished(GlowFrame.AnimIn)

		if GlowFrame.AnimOut:IsPlaying() then
			GlowFrame.AnimOut:Stop()
			GlowFrame.AnimIn:Play()
		end

		for TexName in pairs(ButtonGlowTextures) do
			GlowFrame[TexName]:SetDesaturated(nil)
			GlowFrame[TexName]:SetVertexColor(1, 1, 1)
			local alpha =
				math.min(GlowFrame[TexName]:GetAlpha() / NoZero(GlowFrame.color and GlowFrame.color[4] or 1), 1)
			GlowFrame[TexName]:SetAlpha(alpha)
			UpdateAlphaAnim(GlowFrame, 1)
		end

		GlowFrame.color = false

		GlowFrame.throttle = throttle
	else
		EnsureButtonGlowPool()
		assert(ButtonGlowPool ~= nil)
		local GlowFrame, isNew = ButtonGlowPool:Acquire()

		if not isNew then
			UpdateAlphaAnim(GlowFrame, 1)
		end

		GlowFrame.width = width
		GlowFrame.height = height
		frame._ButtonGlow = GlowFrame
		GlowFrame:SetParent(frame)
		GlowFrame:SetFrameLevel(frame:GetFrameLevel() + frameLevel)
		PixelUtil.SetSize(GlowFrame, width * 1.4, height * 1.4)
		GlowFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -width * 0.2, height * 0.2)
		GlowFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", width * 0.2, -height * 0.2)

		GlowFrame.color = false
		for TexName in pairs(ButtonGlowTextures) do
			GlowFrame[TexName]:SetDesaturated(nil)
			GlowFrame[TexName]:SetVertexColor(1, 1, 1)
		end

		GlowFrame.throttle = throttle
		GlowFrame:SetScript("OnUpdate", ButtonGlowOnUpdate)
		GlowFrame.AnimIn:Play()
	end
end

---@param frame Frame
function Private.Glows.ButtonGlow_Stop(frame)
	if ButtonGlowPool ~= nil and frame._ButtonGlow then
		---@type ButtonGlowFrame
		local GlowFrame = frame._ButtonGlow
		if GlowFrame.AnimOut:IsPlaying() then
			-- AnimOut finishing will release
		elseif GlowFrame.AnimIn:IsPlaying() then
			GlowFrame.AnimIn:Stop()
			ButtonGlowPool:Release(GlowFrame)
		elseif frame:IsVisible() then
			GlowFrame.AnimOut:Play()
		else
			ButtonGlowPool:Release(GlowFrame)
		end
	end
end

---@type FramePool<ProcGlowFrame>?
local ProcGlowPool = nil

local function EnsureProcGlowPool()
	if ProcGlowPool == nil then
		ProcGlowPool = CreateFramePool(
			"Frame",
			GlowParent,
			nil,
			---@param glowFrame ProcGlowFrame
			function(_, glowFrame)
				glowFrame:Hide()
				glowFrame:ClearAllPoints()
				glowFrame:SetScript("OnShow", nil)
				glowFrame:SetScript("OnHide", nil)
				local parent = glowFrame:GetParent()
				if parent and glowFrame.key and parent[glowFrame.key] then
					parent[glowFrame.key] = nil
				end
			end,
			nil,
			function(frame)
				frame.ProcStart = frame:CreateTexture(nil, "ARTWORK")
				frame.ProcStart:SetBlendMode("ADD")
				frame.ProcStart:SetAtlas("UI-HUD-ActionBar-Proc-Start-Flipbook")
				frame.ProcStart:SetAlpha(1)
				frame.ProcStart:SetSize(150, 150)
				frame.ProcStart:SetPoint("CENTER")

				frame.ProcLoop = frame:CreateTexture(nil, "ARTWORK")
				frame.ProcLoop:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
				frame.ProcLoop:SetAlpha(0)
				frame.ProcLoop:SetAllPoints()

				---@type ProcGlowAnimGroup
				frame.ProcLoopAnim = frame:CreateAnimationGroup()
				frame.ProcLoopAnim:SetLooping("REPEAT")
				frame.ProcLoopAnim:SetToFinalAlpha(true)

				local AlphaRepeat = frame.ProcLoopAnim:CreateAnimation("Alpha")
				AlphaRepeat:SetChildKey("ProcLoop")
				AlphaRepeat:SetFromAlpha(1)
				AlphaRepeat:SetToAlpha(1)
				AlphaRepeat:SetDuration(0.001)
				AlphaRepeat:SetOrder(0)
				frame.ProcLoopAnim.AlphaRepeat = AlphaRepeat

				local FlipbookRepeat = frame.ProcLoopAnim:CreateAnimation("FlipBook")
				FlipbookRepeat:SetChildKey("ProcLoop")
				FlipbookRepeat:SetDuration(1)
				FlipbookRepeat:SetOrder(0)
				FlipbookRepeat:SetFlipBookRows(6)
				FlipbookRepeat:SetFlipBookColumns(5)
				FlipbookRepeat:SetFlipBookFrames(30)
				FlipbookRepeat:SetFlipBookFrameWidth(0)
				FlipbookRepeat:SetFlipBookFrameHeight(0)
				frame.ProcLoopAnim.FlipbookRepeat = FlipbookRepeat

				frame.ProcStartAnim = frame:CreateAnimationGroup()
				frame.ProcStartAnim:SetToFinalAlpha(true)

				local FlipbookStartAlphaIn = frame.ProcStartAnim:CreateAnimation("Alpha")
				FlipbookStartAlphaIn:SetChildKey("ProcStart")
				FlipbookStartAlphaIn:SetDuration(0.001)
				FlipbookStartAlphaIn:SetOrder(0)
				FlipbookStartAlphaIn:SetFromAlpha(1)
				FlipbookStartAlphaIn:SetToAlpha(1)

				local FlipbookStart = frame.ProcStartAnim:CreateAnimation("FlipBook")
				FlipbookStart:SetChildKey("ProcStart")
				FlipbookStart:SetDuration(0.7)
				FlipbookStart:SetOrder(1)
				FlipbookStart:SetFlipBookRows(6)
				FlipbookStart:SetFlipBookColumns(5)
				FlipbookStart:SetFlipBookFrames(30)
				FlipbookStart:SetFlipBookFrameWidth(0)
				FlipbookStart:SetFlipBookFrameHeight(0)
				local FlipbookStartAlphaOut = frame.ProcStartAnim:CreateAnimation("Alpha")
				FlipbookStartAlphaOut:SetChildKey("ProcStart")
				FlipbookStartAlphaOut:SetDuration(0.001)
				FlipbookStartAlphaOut:SetOrder(2)
				FlipbookStartAlphaOut:SetFromAlpha(1)
				FlipbookStartAlphaOut:SetToAlpha(0)

				frame.ProcStartAnim:SetScript("OnFinished", function(self)
					frame.ProcLoopAnim:Play()
					frame.ProcLoop:Show()
				end)
			end
		)
	end
end

function Private.Glows.ProcGlow_Start(frame, width, height)
	if not frame then
		return
	end

	local GlowFrame

	if frame._ProcGlow then
		GlowFrame = frame._ProcGlow
	else
		EnsureProcGlowPool()
		assert(ProcGlowPool ~= nil)
		GlowFrame = ProcGlowPool:Acquire()

		frame._ProcGlow = GlowFrame
	end

	GlowFrame:SetParent(frame)
	GlowFrame:SetFrameLevel(frame:GetFrameLevel() + 8)

	local xOffset = width * 0.2
	local yOffset = height * 0.2

	GlowFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -xOffset, yOffset)
	GlowFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", xOffset, -yOffset)

	GlowFrame:SetScript("OnHide", function(self)
		if self.ProcStartAnim:IsPlaying() then
			self.ProcStartAnim:Stop()
		end
		if self.ProcLoopAnim:IsPlaying() then
			self.ProcLoopAnim:Stop()
		end
	end)

	GlowFrame:SetScript("OnShow", function(self)
		if self.StartAnim then
			if not self.ProcStartAnim:IsPlaying() and not self.ProcLoopAnim:IsPlaying() then
				self.ProcStart:SetSize((width / 42 * 150) / 1.4, (height / 42 * 150) / 1.4)
				self.ProcStart:Show()
				self.ProcLoop:Hide()
				self.ProcStartAnim:Play()
			end
		else
			if not self.ProcLoopAnim:IsPlaying() then
				self.ProcStart:Hide()
				self.ProcLoop:Show()
				self.ProcLoopAnim:Play()
			end
		end
	end)

	GlowFrame.ProcStart:SetDesaturated(nil)
	GlowFrame.ProcStart:SetVertexColor(1, 1, 1, 1)
	GlowFrame.ProcLoop:SetDesaturated(nil)
	GlowFrame.ProcLoop:SetVertexColor(1, 1, 1, 1)

	GlowFrame.ProcLoopAnim.FlipbookRepeat:SetDuration(1)
	GlowFrame.StartAnim = true

	GlowFrame:Show()
end

function Private.Glows.ProcGlow_Stop(frame)
	if ProcGlowPool ~= nil and frame._ProcGlow then
		ProcGlowPool:Release(frame._ProcGlow)
	end
end
