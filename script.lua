-- EjejHuesos Hub
-- LocalScript -> StarterPlayer > StarterPlayerScripts
-- Функции: Auto Farm Doors, Instant E, Fly (настраиваемый бинд), Player ESP (дистанция + HP), Door ESP (таймер)
-- RightShift — открыть/скрыть меню, бинд полёта меняется во вкладке Main
-- Настройки автоматически сохраняются для каждого игрока (файл EjejHuesosHub_<UserId>.json)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
	-- кому доступно меню. Пустой список = всем игрокам.
	-- Пример: {123456789, 987654321}
	AllowedUserIds = {},

	PlayerESP = true,
	SkillESP = true,
	DoorESP = true,
	InstantE = true,
	AutoFarm = false,
	Fly = false,

	FlyKey = Enum.KeyCode.V,
	FlySpeed = 50,
	FarmDelay = 0.35,
	FarmSpeed = 120,     -- скорость полёта (стадов/сек)
	WaitRadius = 75,     -- на каком расстоянии от двери ждём таймер (50-100)
	FarmClearance = 20,  -- запас высоты над постройками
	WaitHeight = 5,      -- высота ожидания над уровнем двери (ниже = меньше)
	FreezeTime = 1,      -- сколько секунд стоим заморожены у двери перед лутом
	PromptRange = 60,
	DoorName = "HalloweenDoor",
}

if #Config.AllowedUserIds > 0 and not table.find(Config.AllowedUserIds, LocalPlayer.UserId) then
	return
end

-- ============================================================
-- SAVE / LOAD (автосохранение настроек для каждого игрока)
-- ============================================================
local SAVE_FILE = "EjejHuesosHub_" .. LocalPlayer.UserId .. ".json"
local SAVE_KEYS = {
	"PlayerESP", "SkillESP", "DoorESP", "InstantE", "AutoFarm", "Fly",
	"FlySpeed", "FarmDelay", "FarmSpeed", "WaitRadius",
}
local canFile = (writefile ~= nil and readfile ~= nil and isfile ~= nil)

local function serializeConfig()
	local data = { FlyKey = Config.FlyKey.Name }
	for _, k in ipairs(SAVE_KEYS) do data[k] = Config[k] end
	return HttpService:JSONEncode(data)
end

local function loadSettings()
	if not canFile or not isfile(SAVE_FILE) then return end
	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(SAVE_FILE)) end)
	if not ok or type(data) ~= "table" then return end
	for _, k in ipairs(SAVE_KEYS) do
		if data[k] ~= nil and type(data[k]) == type(Config[k]) then
			Config[k] = data[k]
		end
	end
	if type(data.FlyKey) == "string" then
		local okKey, key = pcall(function() return Enum.KeyCode[data.FlyKey] end)
		if okKey and key then Config.FlyKey = key end
	end
end

loadSettings()

-- раз в секунду проверяем, изменились ли настройки, и пишем файл
local lastSaved = serializeConfig()
task.spawn(function()
	while task.wait(1) do
		if canFile then
			local cur = serializeConfig()
			if cur ~= lastSaved and pcall(writefile, SAVE_FILE, cur) then
				lastSaved = cur
			end
		end
	end
end)

local Theme = {
	Bg = Color3.fromRGB(10, 8, 18),
	Panel = Color3.fromRGB(16, 12, 28),
	Item = Color3.fromRGB(22, 17, 38),
	Stroke = Color3.fromRGB(60, 35, 110),
	Accent = Color3.fromRGB(150, 70, 255),
	AccentDark = Color3.fromRGB(95, 35, 190),
	Text = Color3.fromRGB(240, 238, 250),
	SubText = Color3.fromRGB(150, 140, 175),
	Off = Color3.fromRGB(45, 40, 62),
	PlayerColor = Color3.fromRGB(0, 255, 100),
	DoorColor = Color3.fromRGB(255, 140, 0),
}

local function tween(obj, props, t)
	TweenService:Create(obj, TweenInfo.new(t or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function getChar()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return char, hrp, hum
end

-- ============================================================
-- PLAYER ESP (ник, дистанция, HP)
-- ============================================================
local playerESP = {}

local function removePlayerESP(player)
	local d = playerESP[player]
	if d then
		if d.hl then d.hl:Destroy() end
		if d.bb then d.bb:Destroy() end
		if d.bb2 then d.bb2:Destroy() end
		if d.bb3 then d.bb3:Destroy() end
		playerESP[player] = nil
	end
end

local function createPlayerESP(player, char)
	removePlayerESP(player)
	if not Config.PlayerESP or not char then return end
	local head = char:WaitForChild("Head", 5)
	if not head then return end

	local hl = Instance.new("Highlight")
	hl.Name = "Ejej_PlayerESP"
	hl.Adornee = char
	hl.FillTransparency = 1
	hl.OutlineColor = Theme.PlayerColor
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = char

	local bb = Instance.new("BillboardGui")
	bb.Name = "Ejej_PlayerTag"
	bb.Adornee = head
	bb.Size = UDim2.new(0, 260, 0, 44)
	bb.StudsOffset = Vector3.new(0, 3.4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 2000
	bb.Parent = char

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 22)
	label.Position = UDim2.new(0, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Theme.PlayerColor
	label.TextStrokeTransparency = 0.3
	label.Text = player.Name
	label.Parent = bb

	-- одна строка над ником: Evasive + Ult (в том же BillboardGui, чтобы не наезжало)
	local info = Instance.new("TextLabel")
	info.Size = UDim2.new(1, 0, 0, 18)
	info.Position = UDim2.new(0, 0, 0, 0)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.GothamBold
	info.TextSize = 12
	info.RichText = true
	info.TextWrapped = false
	info.TextColor3 = Color3.new(1, 1, 1)
	info.TextStrokeTransparency = 0.3
	info.Text = ""
	info.Visible = Config.SkillESP
	info.Parent = bb

	-- скиллы под персонажем (отдельный billboard под ногами)
	local root = char:FindFirstChild("HumanoidRootPart") or head
	local bb2 = Instance.new("BillboardGui")
	bb2.Name = "Ejej_SkillTag"
	bb2.Adornee = root
	bb2.Size = UDim2.new(10, 0, 1.7, 0) -- в стадах: уменьшается с расстоянием
	bb2.StudsOffset = Vector3.new(0, -4.3, 0) -- ниже/выше: меняй это число
	bb2.AlwaysOnTop = true
	bb2.MaxDistance = 2000
	bb2.Enabled = Config.SkillESP
	bb2.Parent = char

	local skills = Instance.new("Frame")
	skills.Name = "Skills"
	skills.Size = UDim2.new(1, 0, 1, 0)
	skills.BackgroundTransparency = 1
	skills.Parent = bb2
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Horizontal
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sl.VerticalAlignment = Enum.VerticalAlignment.Center
	sl.Padding = UDim.new(0.03, 0)
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Parent = skills

	-- 2 вертикальных бара справа от персонажа: Ult (U) и Evasive (E)
	local bb3 = Instance.new("BillboardGui")
	bb3.Name = "Ejej_SideBars"
	bb3.Adornee = root
	-- размер в СТАДАХ (Scale), поэтому бары уменьшаются с расстоянием вместе с персонажем
	bb3.Size = UDim2.new(2.4, 0, 5.4, 0)
	bb3.StudsOffset = Vector3.new(2.8, 0, 0) -- правее/левее: меняй первое число
	bb3.AlwaysOnTop = true
	bb3.MaxDistance = 2000
	bb3.Enabled = Config.SkillESP
	bb3.Parent = char

	local function makeSideBar(xScale, letter, color)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(0.36, 0, 0.14, 0)
		l.Position = UDim2.new(xScale, 0, 0, 0)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.3
		l.Text = letter
		l.Parent = bb3

		local bg = Instance.new("Frame")
		bg.Size = UDim2.new(0.36, 0, 0.84, 0)
		bg.Position = UDim2.new(xScale, 0, 0.16, 0)
		bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		bg.BackgroundTransparency = 0.15
		bg.BorderSizePixel = 0
		bg.Parent = bb3
		corner(bg, 3)
		stroke(bg, color, 1, 0.3)

		local fill = Instance.new("Frame")
		fill.AnchorPoint = Vector2.new(0, 1)
		fill.Position = UDim2.new(0, 0, 1, 0)
		fill.Size = UDim2.new(1, 0, 0, 0)
		fill.BackgroundColor3 = color
		fill.BorderSizePixel = 0
		fill.Parent = bg
		corner(fill, 3)
		return fill
	end
	local ultFill = makeSideBar(0.08, "U", Color3.fromRGB(80, 255, 120))
	local evFill = makeSideBar(0.56, "E", Color3.fromRGB(60, 200, 255))

	playerESP[player] = { player = player, hl = hl, bb = bb, bb2 = bb2, bb3 = bb3, ultFill = ultFill, evFill = evFill, maxEv = 0, label = label, char = char, info = info, skills = skills, boxes = {}, maxCd = {} }
end

local function setupPlayer(player)
	if player == LocalPlayer then return end
	if player.Character then task.spawn(createPlayerESP, player, player.Character) end
	player.CharacterAdded:Connect(function(char) createPlayerESP(player, char) end)
	player.CharacterRemoving:Connect(function() removePlayerESP(player) end)
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(removePlayerESP)
for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end

local function applyPlayerESP()
	if Config.PlayerESP then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer and p.Character and not playerESP[p] then
				task.spawn(createPlayerESP, p, p.Character)
			end
		end
	else
		for p in pairs(playerESP) do removePlayerESP(p) end
	end
end

task.spawn(function()
	while task.wait(0.15) do
		for player, d in pairs(playerESP) do
			local hum = d.char and d.char:FindFirstChildOfClass("Humanoid")
			if hum and d.label then
				local hp = math.max(0, math.floor(hum.Health))
				d.label.Text = string.format("%s  ❤ %d", player.Name, hp)
				-- цвет подсветки (Highlight) меняется от зелёного к красному по HP
				local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
				d.hl.OutlineColor = Color3.fromRGB(255, 50, 50):Lerp(Theme.PlayerColor, ratio)
			end
		end
	end
end)

-- ============================================================
-- SKILL ESP (ульта / эвейсив / скилы)
-- Читаем Attributes и Value-объекты игрока и персонажа + Tool в рюкзаке.
-- Если в игре названия другие — подправь SkillPatterns или проверь имена в Explorer
-- и посмотри имена в консоли (F9).
-- ============================================================
local SkillPatterns = {
	Ultimate = { "ultimate", "^ult", "ult$", "[_%s]ult" },
	Evasive = { "evasive", "evade", "dodge", "dash" },
}

local GREEN, RED, CYAN = "#6bff8a", "#ff5a5a", "#3cd9ff"
local EVASIVE_MAX = 20 -- значение евейсива при полном заряде (20 = 100%)

local function matchAny(name, pats)
	name = name:lower()
	for _, pat in ipairs(pats) do
		if name:find(pat) then return true end
	end
	return false
end

local function collectValues(root, depth, out)
	for k, v in pairs(root:GetAttributes()) do
		local t = type(v)
		if t == "number" or t == "boolean" or t == "string" then
			out[#out + 1] = { name = k, value = v }
		end
	end
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("ValueBase") then
			local v = c.Value
			local t = type(v)
			if t == "number" or t == "boolean" or t == "string" then
				out[#out + 1] = { name = c.Name, value = v }
			end
		elseif depth > 0 and (c:IsA("Folder") or c:IsA("Configuration")) then
			collectValues(c, depth - 1, out)
		end
	end
end

local function playerValues(player)
	local out = {}
	collectValues(player, 2, out)
	local char = player.Character
	if char then
		collectValues(char, 1, out)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then collectValues(hum, 0, out) end
	end
	return out
end

local function fmtEvasive(e)
	local v, n = e.value, e.name:lower()
	local cdLike = n:find("cooldown") or n:find("oncd") or n:find("debounce")
	if type(v) == "boolean" then
		local ready = cdLike and (not v) or ((not cdLike) and v)
		return ready and ("<font color='" .. GREEN .. "'>READY</font>") or ("<font color='" .. RED .. "'>CD</font>")
	elseif type(v) == "number" then
		if cdLike then
			if v > 0.05 then return string.format("<font color='%s'>CD %.1fs</font>", RED, v) end
			return "<font color='" .. GREEN .. "'>READY</font>"
		end
		local pct = v / EVASIVE_MAX * 100
		return string.format("<font color='%s'>%d%%</font>", CYAN, math.floor(math.clamp(pct, 0, 100) + 0.5))
	end
	return tostring(e.value)
end

local function fmtUlt(e)
	local v = e.value
	if type(v) == "number" then
		local pct = v <= 1 and v * 100 or v
		pct = math.clamp(pct, 0, 100)
		return string.format("<font color='%s'>%d%%</font>", GREEN, math.floor(pct))
	elseif type(v) == "boolean" then
		return string.format("<font color='%s'>%d%%</font>", GREEN, v and 100 or 0)
	end
	return tostring(v)
end

-- доли (0..1) для боковых баров
local function evasiveFrac(e, d)
	local v, n = e.value, e.name:lower()
	local cdLike = n:find("cooldown") or n:find("oncd") or n:find("debounce")
	if type(v) == "boolean" then
		local ready = cdLike and (not v) or ((not cdLike) and v)
		return ready and 1 or 0
	elseif type(v) == "number" then
		if cdLike then
			if v > 0.05 then
				d.maxEv = math.max(d.maxEv or 0, v)
				return 1 - math.clamp(v / d.maxEv, 0, 1)
			end
			return 1
		end
		return math.clamp(v / EVASIVE_MAX, 0, 1)
	end
	return 0
end

local function ultFrac(e)
	local v = e.value
	if type(v) == "number" then return math.clamp(v <= 1 and v or v / 100, 0, 1) end
	if type(v) == "boolean" then return v and 1 or 0 end
	return 0
end

local function findEvUlt(player)
	local values = playerValues(player)
	local evasive, ult
	for _, e in ipairs(values) do
		if matchAny(e.name, SkillPatterns.Evasive) then
			if not evasive or e.name:lower():find("cooldown") then evasive = e end
		end
	end
	for _, e in ipairs(values) do
		if matchAny(e.name, SkillPatterns.Ultimate) and type(e.value) ~= "string" then
			ult = e
			break
		end
	end
	return evasive, ult
end

local function updateSideBars(d, player)
	if not d.ultFill then return end
	local ev, ult = findEvUlt(player)
	d.evFill.Size = UDim2.new(1, 0, ev and evasiveFrac(ev, d) or 0, 0)
	d.ultV = ult and ultFrac(ult) or 0
	d.ultFill.Size = UDim2.new(1, 0, d.ultV, 0)
end

local function buildInfo(player)
	local lines = {}
	local values = playerValues(player)

	local evasive
	for _, e in ipairs(values) do
		if matchAny(e.name, SkillPatterns.Evasive) then
			-- приоритет значению с cooldown в имени
			if not evasive or e.name:lower():find("cooldown") then evasive = e end
		end
	end
	local ult
	for _, e in ipairs(values) do
		if matchAny(e.name, SkillPatterns.Ultimate) and type(e.value) ~= "string" then
			ult = e
			break
		end
	end

	if evasive then lines[#lines + 1] = "Evasive: " .. fmtEvasive(evasive) end
	if ult then lines[#lines + 1] = "Ult: " .. fmtUlt(ult) end
	return table.concat(lines, "  |  ")
end

-- ---------- скиллы под персонажем ----------
local NAME_COL = Color3.fromRGB(40, 160, 255)   -- название (как на скрине)
local BAR_BG   = Color3.fromRGB(110, 210, 255)  -- голубой фон
local BAR_FILL = Color3.fromRGB(80, 255, 120)   -- зелёная заливка

local function prettyName(raw)
	local n = raw:gsub("[Cc]ooldowns?", "")
	n = n:gsub("[_%-]", " ")
	n = n:gsub("%s+[Cc][Dd]$", "")
	n = n:gsub("^%s+", ""):gsub("%s+$", "")
	return n ~= "" and n or raw
end

local function isCdName(n)
	n = n:lower()
	return n:find("cool") or n:find("cd$") or n:find("^cd") or n:find("_cd")
end

-- таймстемп (os.time / server time) -> секунды до конца
local function normLeft(v)
	if v > 100000 then
		local l = v - Workspace:GetServerTimeNow()
		if l > 3600 then return nil end
		return math.max(l, 0)
	end
	return v
end

local function toolInfo(t)
	local left, onCd = nil, false
	local vals = {}
	collectValues(t, 0, vals)
	for _, e in ipairs(vals) do
		if isCdName(e.name) then
			if type(e.value) == "number" then
				local l = normLeft(e.value)
				if l then
					left = l
					if l > 0.05 then onCd = true end
				end
			elseif type(e.value) == "boolean" and e.value then
				onCd = true
			end
		end
	end
	if t.Enabled == false then onCd = true end
	return { name = t.Name, left = left, cd = onCd }
end

local function skillList(player)
	local list, seen = {}, {}
	local function add(name, left, onCd)
		if seen[name] or #list >= 6 then return end
		seen[name] = true
		list[#list + 1] = { name = name, left = left, cd = onCd }
	end

	-- тулы: у чужих игроков виден только тот, что в руках (Backpack не реплицируется)
	local function scan(container)
		if not container then return end
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") then
				local i = toolInfo(t)
				add(i.name, i.left, i.cd)
			end
		end
	end
	scan(player:FindFirstChildOfClass("Backpack"))
	scan(player.Character)

	-- любые значения / атрибуты с cooldown / cd в названии
	for _, e in ipairs(playerValues(player)) do
		if isCdName(e.name)
			and not matchAny(e.name, SkillPatterns.Evasive)
			and not matchAny(e.name, SkillPatterns.Ultimate)
		then
			if type(e.value) == "number" then
				local l = normLeft(e.value)
				if l then add(prettyName(e.name), l, l > 0.05) end
			elseif type(e.value) == "boolean" then
				add(prettyName(e.name), nil, e.value)
			end
		end
	end
	return list
end

-- скиллы из Character.Moveset (NumberValue + атрибуты Key / LastUse / ReadyAt)
local function secondsLeft(readyAt)
	local l = readyAt - Workspace:GetServerTimeNow()
	if l > 3600 or l < -86400 then l = readyAt - os.time() end -- вдруг время в os.time
	return l
end

local READY_ATTRS = { "ReadyAt", "ReadyTime", "CooldownEnd", "CooldownEndsAt", "EndTime", "NextUse" }

local function readyAttr(v)
	for _, n in ipairs(READY_ATTRS) do
		local x = v:GetAttribute(n)
		if type(x) == "number" then return x end
	end
	-- длительность + время использования
	local lu = v:GetAttribute("LastUse")
	local cd = v:GetAttribute("Cooldown") or v:GetAttribute("CD")
	if type(lu) == "number" and type(cd) == "number" and cd > 0 then return lu + cd end
	return nil
end

local function entryFromInst(v)
	local ra = readyAttr(v)
	local lu = v:GetAttribute("LastUse")
	local key = v:GetAttribute("Key")
	local total
	if type(ra) == "number" and type(lu) == "number" and ra > lu then total = ra - lu end
	if not total and v:IsA("ValueBase") and type(v.Value) == "number" and v.Value > 0 then total = v.Value end
	local left = type(ra) == "number" and secondsLeft(ra) or 0
	return {
		inst = v,
		name = v.Name,
		key = key ~= nil and tostring(key) or nil,
		order = tonumber(key) or 99,
		left = left,
		total = total,
		cd = left > 0.05,
	}
end

local function movesetList(char)
	local folder = char and char:FindFirstChild("Moveset")
	if not folder then return nil end
	local list = {}
	for _, v in ipairs(folder:GetChildren()) do
		if #list >= 8 then break end
		list[#list + 1] = entryFromInst(v)
	end
	table.sort(list, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.name < b.name
	end)
	return list
end

local function ensureBox(d, i)
	local b = d.boxes[i]
	if b then return b end

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 1, 0)
	row.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	row.BackgroundTransparency = 0.05
	row.BorderSizePixel = 0
	row.LayoutOrder = i
	row.ClipsDescendants = true
	row.Parent = d.skills
	corner(row, 4)
	local st = stroke(row, BAR_FILL, 2, 0)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.DominantAxis = Enum.DominantAxis.Height
	ar.Parent = row

	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.new(0, 0, 1, 0)
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = BAR_FILL
	fill.BackgroundTransparency = 0.2
	fill.BorderSizePixel = 0
	fill.Parent = row

	local num = Instance.new("TextLabel")
	num.Size = UDim2.new(1, 0, 1, 0)
	num.BackgroundTransparency = 1
	num.Font = Enum.Font.GothamBlack
	num.TextScaled = true
	num.TextColor3 = Color3.new(1, 1, 1)
	num.TextStrokeTransparency = 0.2
	num.Parent = row

	b = { row = row, name = num, fill = fill, stroke = st }
	d.boxes[i] = b
	return b
end

local function paintBox(d, b, sk, label)
	b.row.Visible = true
	b.name.Text = label
	if not sk then
		-- кулдаун не найден: серый квадрат
		b.fill.Size = UDim2.new(1, 0, 0, 0)
		b.stroke.Color = Color3.fromRGB(150, 150, 150)
		return
	end
	if sk.cd and sk.left and sk.left > 0.05 then
		local total = sk.total
		if not total then
			total = math.max(d.maxCd[sk.name] or 0, sk.left)
			d.maxCd[sk.name] = total
		end
		local frac = 1 - math.clamp(sk.left / math.max(total, 0.1), 0, 1)
		b.fill.Size = UDim2.new(1, 0, frac, 0)
		b.fill.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
		b.stroke.Color = Color3.fromRGB(255, 80, 80)
	else
		b.fill.Size = UDim2.new(1, 0, 1, 0)
		b.fill.BackgroundColor3 = BAR_FILL
		b.stroke.Color = BAR_FILL
	end
end

local function updateSkillBoxes(d, list)
	if not d.skills then return end
	local shown = math.min(#list, 4)
	for i = 1, shown do
		paintBox(d, ensureBox(d, i), list[i], list[i].key or tostring(i))
	end
	for i = shown + 1, #d.boxes do
		d.boxes[i].row.Visible = false
	end
end

local function applySkillESP()
	for _, d in pairs(playerESP) do
		if d.info then d.info.Visible = Config.SkillESP end
		if d.bb2 then d.bb2.Enabled = Config.SkillESP end
		if d.bb3 then d.bb3.Enabled = Config.SkillESP end
	end
end

task.spawn(function()
	while task.wait(0.2) do
		if Config.SkillESP then
			for player, d in pairs(playerESP) do
				if d.info then
					local ok, text = pcall(buildInfo, player)
					d.info.Text = ok and text or ""
					local ok2, list = pcall(function() return movesetList(d.char) or skillList(player) end)
					updateSkillBoxes(d, ok2 and list or {})
					pcall(updateSideBars, d, player)
				end
			end
		end
	end
end)

-- ============================================================
-- DOORS (ESP + таймер)
-- ============================================================
local doors = {} -- [model] = {hl, bb, label, prompt, timer, nextSearch}

local function applyDoorESP()
	for _, d in pairs(doors) do
		for _, box in ipairs(d.hl:GetChildren()) do box.Visible = Config.DoorESP end
		d.bb.Enabled = Config.DoorESP
	end
end

local function removeDoor(model)
	local d = doors[model]
	if d then
		d.hl:Destroy()
		d.bb:Destroy()
		doors[model] = nil
	end
end

local function setupDoor(model)
	if not model:IsA("Model") or model.Name ~= Config.DoorName or doors[model] then return end

	-- обводка (12 рёбер габаритной рамки) через BoxHandleAdornment:
	-- видна сквозь стены, без лимита Highlight, цвет как у текста
	local hl = Instance.new("Folder")
	hl.Name = "Ejej_DoorESP"
	hl.Parent = model
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if anchor then
		local bbCF, bbSize = model:GetBoundingBox()
		local rel = anchor.CFrame:ToObjectSpace(bbCF)
		local sx, sy, sz, t = bbSize.X, bbSize.Y, bbSize.Z, 0.15
		local function edge(center, size)
			local box = Instance.new("BoxHandleAdornment")
			box.Adornee = anchor
			box.CFrame = rel * CFrame.new(center)
			box.Size = size
			box.Color3 = Theme.DoorColor
			box.Transparency = 0
			box.AlwaysOnTop = true
			box.ZIndex = 5
			box.Visible = Config.DoorESP
			box.Parent = hl
		end
		for _, y in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do
				edge(Vector3.new(0, y * sy / 2, z * sz / 2), Vector3.new(sx, t, t))
			end
		end
		for _, x in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do
				edge(Vector3.new(x * sx / 2, 0, z * sz / 2), Vector3.new(t, sy, t))
			end
		end
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				edge(Vector3.new(x * sx / 2, y * sy / 2, 0), Vector3.new(t, t, sz))
			end
		end
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "Ejej_DoorTag"
	bb.Adornee = model
	bb.Size = UDim2.new(0, 150, 0, 26)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 1000
	bb.Enabled = Config.DoorESP
	bb.Parent = model

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "Door"
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Theme.DoorColor
	label.TextStrokeTransparency = 0.3
	label.Parent = bb

	doors[model] = { hl = hl, bb = bb, label = label, nextSearch = 0 }
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then removeDoor(model) end
	end)
end

for _, obj in ipairs(Workspace:GetDescendants()) do
	if obj.Name == Config.DoorName then setupDoor(obj) end
end
Workspace.DescendantAdded:Connect(function(obj)
	if obj.Name == Config.DoorName then
		task.wait(0.1)
		if obj.Parent then setupDoor(obj) end
	end
end)

-- ищем родной таймер игры (TextLabel вида "0:01") внутри двери
local TIME_PATTERN = "^%s*(%d+:%d%d)%s*$"

local function findTimerLabel(model)
	for _, o in ipairs(model:GetDescendants()) do
		if o:IsA("TextLabel") and not o:FindFirstAncestor("Ejej_DoorTag") then
			if o.Text:match(TIME_PATTERN) then
				return o
			end
		end
	end
	return nil
end

task.spawn(function()
	while task.wait(0.1) do
		for model, d in pairs(doors) do
			if not (d.timer and d.timer.Parent) and os.clock() >= d.nextSearch then
				d.timer = findTimerLabel(model)
				d.nextSearch = os.clock() + 1
			end
			if Config.DoorESP then
				local t = d.timer and d.timer.Parent and d.timer.Text:match(TIME_PATTERN)
				d.label.Text = t and ("Door  [" .. t .. "]") or "Door"
			end
		end
	end
end)

local function getPrompt(model, d)
	if d.prompt and d.prompt.Parent then return d.prompt end
	d.prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	return d.prompt
end

local function promptPosition(prompt, model)
	local p = prompt.Parent
	if p and p:IsA("BasePart") then return p.Position end
	if p and p:IsA("Attachment") then return p.WorldPosition end
	return model:GetPivot().Position
end

-- ============================================================
-- INSTANT E (с возвратом обычных значений при выключении)
-- ============================================================
local origPrompt = setmetatable({}, { __mode = "k" })

task.spawn(function()
	while task.wait(0.1) do
		local _, hrp = getChar()
		for model, d in pairs(doors) do
			local prompt = getPrompt(model, d)
			if prompt then
				local inRange = false
				if hrp then
					inRange = (promptPosition(prompt, model) - hrp.Position).Magnitude <= Config.PromptRange
				end
				if Config.InstantE and inRange then
					if not origPrompt[prompt] then
						origPrompt[prompt] = {
							prompt.HoldDuration,
							prompt.RequiresLineOfSight,
							prompt.MaxActivationDistance,
						}
					end
					prompt.HoldDuration = 0
					prompt.RequiresLineOfSight = false
					prompt.MaxActivationDistance = Config.PromptRange
				elseif origPrompt[prompt] then
					local o = origPrompt[prompt]
					prompt.HoldDuration = o[1]
					prompt.RequiresLineOfSight = o[2]
					prompt.MaxActivationDistance = o[3]
					origPrompt[prompt] = nil
				end
			end
		end
	end
end)

-- ============================================================
-- AUTO FARM DOORS (без ноклипа)
-- 1) выбираем самую высокую (возвышенность) точку ожидания на кольце WaitRadius
-- 2) твином летим туда, ждём конец таймера
-- 3) твином летим к свободной точке рядом с дверью, 1 сек стоим, лутаем
-- Каждый отрезок пути проверяется кастами: сквозь стены/потолки не летим.
-- Если прямо и над постройками нельзя — идём по навмешу (PathfindingService).
-- ============================================================
local PathfindingService = game:GetService("PathfindingService")
local fpp = fireproximityprompt
local farmAnchoredHrp
local skipDoor = setmetatable({}, { __mode = "k" })

local function setFarmAnchored(hrp, state)
	hrp.Anchored = state
	hrp.AssemblyLinearVelocity = Vector3.zero
	farmAnchoredHrp = state and hrp or nil
end

local function releaseFarm()
	if farmAnchoredHrp and farmAnchoredHrp.Parent then
		farmAnchoredHrp.Anchored = false
		farmAnchoredHrp.AssemblyLinearVelocity = Vector3.zero
	end
	farmAnchoredHrp = nil
end

local function firePrompt(prompt)
	if fpp then
		fpp(prompt)
		return
	end
	local hold = prompt.HoldDuration
	prompt:InputHoldBegin()
	if hold > 0 then task.wait(hold + 0.05) end
	prompt:InputHoldEnd()
end

local function doorSecondsLeft(d)
	local lbl = d.timer
	if lbl and lbl.Parent then
		local m, sec = lbl.Text:match("^%s*(%d+):(%d%d)%s*$")
		if m then return tonumber(m) * 60 + tonumber(sec) end
	end
	return 0
end

local function isDoorReady(model, d)
	local prompt = getPrompt(model, d)
	return prompt ~= nil and prompt.Enabled and doorSecondsLeft(d) <= 0
end

-- ---------- геометрия / касты ----------
local function makeRayParams(ignoreModel)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { LocalPlayer.Character }
	if ignoreModel then table.insert(ignore, ignoreModel) end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return params
end

local function pointFree(p)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { LocalPlayer.Character }
	op.RespectCanCollide = true
	return #Workspace:GetPartBoundsInRadius(p, 3, op) == 0
end

-- Проверка пути. Преградой считаем:
--  * всё с CanCollide = true
--  * видимые стены/бордюры даже с CanCollide = false (сервер за них телепортирует назад)
-- Невидимые и мелкие неколлизионные части (триггеры, декор) игнорируем.
local function segmentClear(a, b, params)
	local dir = b - a
	if dir.Magnitude < 0.5 then return true end
	local cp = RaycastParams.new()
	cp.FilterType = Enum.RaycastFilterType.Exclude
	cp.RespectCanCollide = false
	local ignore = { LocalPlayer.Character }
	cp.FilterDescendantsInstances = ignore
	for _ = 1, 12 do
		local r = Workspace:Spherecast(a, 2.5, dir, cp)
		if not r then return true end
		local inst = r.Instance
		if inst.CanCollide or (inst.Transparency < 0.95 and inst.Size.Magnitude >= 6) then
			return false
		end
		table.insert(ignore, inst)
		cp.FilterDescendantsInstances = ignore
	end
	return false
end

local function surfaceTop(x, z, params)
	local r = Workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), params)
	return r and r.Position.Y or -math.huge
end

local function cruiseY(a, b, params)
	local y = math.max(a.Y, b.Y)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = flat.Magnitude
	local dir = len > 0 and flat.Unit or Vector3.zero
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local steps = math.max(1, math.ceil(len / 8))
	for i = 0, steps do
		local p = Vector3.new(a.X, 0, a.Z) + dir * (len * i / steps)
		for _, off in ipairs({ -8, 0, 8 }) do
			local q = p + side * off
			local top = surfaceTop(q.X, q.Z, params)
			if top + Config.FarmClearance > y then
				y = top + Config.FarmClearance
			end
		end
	end
	return y
end

-- ---------- движение ----------
local function tweenTo(hrp, pos)
	local dist = (pos - hrp.Position).Magnitude
	if dist < 0.5 then return true end
	local tw = TweenService:Create(
		hrp,
		TweenInfo.new(dist / Config.FarmSpeed, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.new(pos) * hrp.CFrame.Rotation }
	)
	local done = false
	tw.Completed:Connect(function() done = true end)
	tw:Play()

	local last = hrp.Position
	local deadline = os.clock() + dist / Config.FarmSpeed + 5
	while not done do
		local dt = task.wait()
		if not Config.AutoFarm or not hrp:IsDescendantOf(Workspace) then
			tw:Cancel()
			return false
		end
		-- сервер откатил (телепорт назад) или мы застряли -> прерываем, чтобы не зависнуть
		local cur = hrp.Position
		if (cur - last).Magnitude > Config.FarmSpeed * dt * 2 + 8 or os.clock() > deadline then
			tw:Cancel()
			return false
		end
		last = cur
	end
	return Config.AutoFarm
end

local function groundPoint(p, params)
	local r = Workspace:Raycast(p, Vector3.new(0, -300, 0), params)
	return r and r.Position or p
end

-- путь по навмешу (если по воздуху пройти нельзя)
local function walkPathTo(hrp, goal, params)
	local lift = Vector3.new(0, 3, 0)
	local from = groundPoint(hrp.Position, params)
	local to = groundPoint(goal, params)

	local path = PathfindingService:CreatePath({
		AgentRadius = 2.5,
		AgentHeight = 5,
		AgentCanJump = true,
	})
	local ok = pcall(function() path:ComputeAsync(from, to) end)
	if not ok or path.Status ~= Enum.PathStatus.Success then return false end

	-- спуск из воздуха на путь — только если вертикаль свободна
	if not segmentClear(hrp.Position, from + lift, params) then return false end
	if not tweenTo(hrp, from + lift) then return false end

	for _, wp in ipairs(path:GetWaypoints()) do
		if not tweenTo(hrp, wp.Position + lift) then return false end
	end

	if segmentClear(hrp.Position, goal, params) then
		return tweenTo(hrp, goal)
	end
	return Config.AutoFarm
end

-- безопасный полёт без ноклипа.
-- обычный порядок: прямо -> над постройками -> по навмешу
-- preferGround (между дверями): прямо -> по навмешу -> над постройками (только если иначе никак)
local function flyTo(goal, preferGround)
	local _, hrp = getChar()
	if not hrp then return false end
	local params = makeRayParams()
	local start = hrp.Position

	if segmentClear(start, goal, params) then
		return tweenTo(hrp, goal)
	end

	local function tryAir()
		local y = cruiseY(start, goal, params)
		local p1 = Vector3.new(start.X, y, start.Z)
		local p2 = Vector3.new(goal.X, y, goal.Z)
		if segmentClear(start, p1, params) and segmentClear(p1, p2, params) and segmentClear(p2, goal, params) then
			return true, tweenTo(hrp, p1) and tweenTo(hrp, p2) and tweenTo(hrp, goal)
		end
		return false, false
	end

	if preferGround then
		if walkPathTo(hrp, goal, params) then return true end
		if not Config.AutoFarm then return false end
		local _, ok = tryAir()
		return ok
	end

	local tried, ok = tryAir()
	if tried then return ok end
	return walkPathTo(hrp, goal, params)
end

-- ---------- выбор точек ----------
-- точка ожидания: на кольце WaitRadius выбираем самую ВЫСОКУЮ свободную (возвышенность)
local function pickWaitPoint(doorPos, fromPos)
	local params = makeRayParams()
	local best, bestScore
	for deg = 0, 330, 30 do
		local rad = math.rad(deg)
		local x = doorPos.X + math.cos(rad) * Config.WaitRadius
		local z = doorPos.Z + math.sin(rad) * Config.WaitRadius
		local r = Workspace:Raycast(Vector3.new(x, doorPos.Y + 60, z), Vector3.new(0, -220, 0), params)
		if r then
			local p = Vector3.new(x, r.Position.Y + Config.WaitHeight, z)
			if pointFree(p) then
				local score = r.Position.Y - (p - fromPos).Magnitude / 1000 -- главное высота, потом близость
				if not bestScore or score > bestScore then
					best, bestScore = p, score
				end
			end
		end
	end
	return best
end

-- точка у двери: свободная, с землёй под ногами и прямой видимостью на дверь
local function pickDoorSpot(model, doorPos, fromPos)
	local params = makeRayParams()
	local doorParams = makeRayParams(model)
	local best, bestScore
	for _, radius in ipairs({ 6, 9, 12 }) do
		for deg = 0, 330, 30 do
			local rad = math.rad(deg)
			local p = Vector3.new(doorPos.X + math.cos(rad) * radius, doorPos.Y, doorPos.Z + math.sin(rad) * radius)
			if pointFree(p)
				and Workspace:Raycast(p, Vector3.new(0, -8, 0), params)
				and Workspace:Raycast(p, doorPos - p, doorParams) == nil
			then
				local score = radius * 2 + (p - fromPos).Magnitude / 50
				if not bestScore or score < bestScore then
					best, bestScore = p, score
				end
			end
		end
	end
	return best
end

-- выбираем дверь, которая раньше всего будет готова
local function pickDoor(hrp)
	local bestModel, bestD, bestPrompt, bestCost = nil, nil, nil, math.huge
	for model, d in pairs(doors) do
		if model.Parent and (skipDoor[model] or 0) < os.clock() then
			local prompt = getPrompt(model, d)
			if prompt then
				local travel = (promptPosition(prompt, model) - hrp.Position).Magnitude / Config.FarmSpeed
				local cost = math.max(doorSecondsLeft(d), travel)
				if cost < bestCost then
					bestModel, bestD, bestPrompt, bestCost = model, d, prompt, cost
				end
			end
		end
	end
	return bestModel, bestD, bestPrompt
end

local function giveUp(model, seconds)
	if Config.AutoFarm then skipDoor[model] = os.clock() + seconds end
end

task.spawn(function()
	while true do
		task.wait(0.1)
		if not Config.AutoFarm then
			if farmAnchoredHrp then releaseFarm() end
			continue
		end

		local _, hrp, hum = getChar()
		if not hrp or not hum or hum.Health <= 0 then
			farmAnchoredHrp = nil
			task.wait(0.5)
			continue
		end

		local model, d, prompt = pickDoor(hrp)
		if not model then
			task.wait(0.5)
			continue
		end

		setFarmAnchored(hrp, true)

		local doorPos = promptPosition(prompt, model)

		local function waitReady(maxSeconds)
			local t0 = os.clock()
			while Config.AutoFarm and model.Parent do
				if isDoorReady(model, d) then return true end
				if os.clock() - t0 > maxSeconds then return false end
				task.wait(0.1)
			end
			return false
		end

		-- 1) на возвышенность летим ТОЛЬКО если надо ждать таймер
		local fromPos = hrp.Position
		if doorSecondsLeft(d) > 3 then
			local wp = pickWaitPoint(doorPos, hrp.Position)
			if not wp then
				giveUp(model, 20)
				continue
			end
			if not flyTo(wp) then
				giveUp(model, 10)
				continue
			end
			fromPos = wp
			if not waitReady(240) then
				giveUp(model, 30)
				continue
			end
		end

		-- 2) к двери (без ноклипа). Между дверями наверх не поднимаемся
		prompt = getPrompt(model, d)
		if not prompt then continue end
		doorPos = promptPosition(prompt, model)
		local spot = pickDoorSpot(model, doorPos, fromPos)
		if not spot then
			giveUp(model, 20)
			continue
		end
		if not flyTo(spot, true) then
			giveUp(model, 10)
			continue
		end

		-- 3) если таймер ещё не кончился — ждём у двери, потом замораживаемся и лутаем
		if not waitReady(30) then
			giveUp(model, 10)
			continue
		end

		local frozen = 0
		while frozen < Config.FreezeTime and Config.AutoFarm and model.Parent do
			task.wait(0.05)
			frozen += 0.05
		end
		if model.Parent and Config.AutoFarm then
			pcall(firePrompt, prompt)
			local waited = 0
			while model.Parent and waited < 1.5 do
				task.wait(0.05)
				waited += 0.05
			end
			if model.Parent then giveUp(model, 3) end
		end

		task.wait(Config.FarmDelay)
	end
end)

-- ============================================================
-- FLY
-- ============================================================
local flyObjs

local function stopFly()
	if flyObjs then
		for _, o in pairs(flyObjs) do o:Destroy() end
		flyObjs = nil
	end
	local _, _, hum = getChar()
	if hum then hum.PlatformStand = false end
end

local function startFly()
	stopFly()
	local _, hrp, hum = getChar()
	if not hrp or not hum then return end

	local att = Instance.new("Attachment")
	att.Name = "Ejej_FlyAtt"
	att.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Name = "Ejej_FlyVel"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.Parent = hrp

	local ao = Instance.new("AlignOrientation")
	ao.Name = "Ejej_FlyAlign"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 40
	ao.CFrame = hrp.CFrame
	ao.Parent = hrp

	hum.PlatformStand = true
	flyObjs = { att = att, lv = lv, ao = ao }
end

local function applyFly()
	if Config.Fly then startFly() else stopFly() end
end

RunService.RenderStepped:Connect(function()
	if not Config.Fly or not flyObjs then return end
	local _, hrp, hum = getChar()
	local cam = Workspace.CurrentCamera
	if not hrp or not hum or not cam then return end

	local look = cam.CFrame.LookVector
	local right = cam.CFrame.RightVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flatRight = Vector3.new(right.X, 0, right.Z)
	flatLook = flatLook.Magnitude > 0 and flatLook.Unit or Vector3.zero
	flatRight = flatRight.Magnitude > 0 and flatRight.Unit or Vector3.zero

	local move = hum.MoveDirection
	local fwd = move:Dot(flatLook)
	local side = move:Dot(flatRight)

	local vel = look * fwd + right * side
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vel += Vector3.new(0, 1, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then vel -= Vector3.new(0, 1, 0) end

	flyObjs.lv.VectorVelocity = vel * Config.FlySpeed
	if flatLook ~= Vector3.zero then
		flyObjs.ao.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flatLook)
	end
end)

LocalPlayer.CharacterAdded:Connect(function(char)
	flyObjs = nil
	if Config.Fly then
		char:WaitForChild("HumanoidRootPart")
		char:WaitForChild("Humanoid")
		task.wait(0.3)
		startFly()
	end
end)

-- ============================================================
-- VFX (события от сервера)
-- ============================================================
local function candyEffect(pos, amount)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = pos
	part.Parent = Workspace

	local att = Instance.new("Attachment")
	att.Parent = part

	local em = Instance.new("ParticleEmitter")
	em.Color = ColorSequence.new(Color3.fromRGB(255, 140, 0), Color3.fromRGB(180, 60, 255))
	em.Lifetime = NumberRange.new(0.6, 1.2)
	em.Speed = NumberRange.new(12, 22)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Size = NumberSequence.new(0.8, 0)
	em.Acceleration = Vector3.new(0, -30, 0)
	em.Rate = 0
	em.LightEmission = 0.6
	em.Parent = att
	em:Emit(25)

	if amount then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 120, 0, 30)
		bb.AlwaysOnTop = true
		bb.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
		bb.Parent = part

		local txt = Instance.new("TextLabel")
		txt.Size = UDim2.new(1, 0, 1, 0)
		txt.BackgroundTransparency = 1
		txt.Text = "+" .. amount .. " 🍬"
		txt.Font = Enum.Font.GothamBlack
		txt.TextSize = 22
		txt.TextColor3 = Color3.fromRGB(255, 170, 60)
		txt.TextStrokeTransparency = 0.3
		txt.Parent = bb

		TweenService:Create(bb, TweenInfo.new(1.4, Enum.EasingStyle.Quad), {
			StudsOffsetWorldSpace = Vector3.new(0, 7, 0),
		}):Play()
		TweenService:Create(txt, TweenInfo.new(1.4), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end

	Debris:AddItem(part, 2)
end

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	local vfx = remotes and remotes:WaitForChild("HALLOWEEN_VFX", 10)
	if not vfx then return end

	vfx.OnClientEvent:Connect(function(kind, a, b, c, d)
		if kind == "OpenDoor" then
			local door = a
			local ok, pos = pcall(function() return door:GetPivot().Position end)
			if ok and pos then candyEffect(pos, nil) end
		elseif kind == "Candy" then
			-- a = игрок, b = позиция, c = было, d = стало
			if typeof(b) == "Vector3" and type(c) == "number" and type(d) == "number" then
				candyEffect(b, d - c)
			end
		end
	end)
end)

-- ============================================================
-- UI
-- ============================================================
for _, n in ipairs({ "EjejHub", "EjejHuesosHub" }) do
	local old = PlayerGui:FindFirstChild(n)
	if old then old:Destroy() end
end

local gui = Instance.new("ScreenGui")
gui.Name = "EjejHuesosHub"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 100
gui.IgnoreGuiInset = true
gui.Parent = PlayerGui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 540, 0, 380)
main.Position = UDim2.new(0.5, -270, 0.5, -190)
main.BackgroundColor3 = Theme.Bg
main.BorderSizePixel = 0
main.Parent = gui
corner(main, 14)

local mainStroke = stroke(main, Color3.new(1, 1, 1), 2)
local mainGrad = Instance.new("UIGradient")
mainGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Accent),
	ColorSequenceKeypoint.new(0.5, Theme.AccentDark),
	ColorSequenceKeypoint.new(1, Theme.Accent),
})
mainGrad.Rotation = 45
mainGrad.Parent = mainStroke

local scale = Instance.new("UIScale")
scale.Parent = main

local bgGrad = Instance.new("UIGradient")
bgGrad.Color = ColorSequence.new(Color3.fromRGB(22, 14, 40), Theme.Bg)
bgGrad.Rotation = 90
bgGrad.Parent = main

-- шапка
local header = Instance.new("Frame")
header.Size = UDim2.new(1, -20, 0, 54)
header.Position = UDim2.new(0, 10, 0, 10)
header.BackgroundColor3 = Theme.Panel
header.BorderSizePixel = 0
header.Parent = main
corner(header, 10)
stroke(header, Theme.Stroke, 1, 0.3)

local logo = Instance.new("Frame")
logo.Size = UDim2.new(0, 36, 0, 36)
logo.Position = UDim2.new(0, 10, 0.5, -18)
logo.BackgroundColor3 = Theme.Accent
logo.Parent = header
corner(logo, 18)
local logoGrad = Instance.new("UIGradient")
logoGrad.Color = ColorSequence.new(Color3.fromRGB(200, 120, 255), Theme.AccentDark)
logoGrad.Rotation = 135
logoGrad.Parent = logo

local logoBolt = Instance.new("TextLabel")
logoBolt.Size = UDim2.new(1, 0, 1, 0)
logoBolt.BackgroundTransparency = 1
logoBolt.Text = "⚡"
logoBolt.TextSize = 20
logoBolt.TextColor3 = Color3.new(1, 1, 1)
logoBolt.Font = Enum.Font.GothamBold
logoBolt.Parent = logo

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 220, 1, 0)
title.Position = UDim2.new(0, 56, 0, 0)
title.BackgroundTransparency = 1
title.Text = "EjejHuesos Hub"
title.TextColor3 = Theme.Text
title.TextSize = 19
title.Font = Enum.Font.GothamBlack
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 34, 0, 34)
minBtn.Position = UDim2.new(1, -44, 0.5, -17)
minBtn.BackgroundColor3 = Theme.Item
minBtn.Text = "—"
minBtn.TextColor3 = Theme.SubText
minBtn.TextSize = 16
minBtn.Font = Enum.Font.GothamBold
minBtn.AutoButtonColor = false
minBtn.Parent = header
corner(minBtn, 8)
minBtn.MouseEnter:Connect(function() tween(minBtn, { BackgroundColor3 = Theme.AccentDark }) end)
minBtn.MouseLeave:Connect(function() tween(minBtn, { BackgroundColor3 = Theme.Item }) end)

-- сайдбар
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 130, 1, -84)
sidebar.Position = UDim2.new(0, 10, 0, 74)
sidebar.BackgroundColor3 = Theme.Panel
sidebar.BorderSizePixel = 0
sidebar.Parent = main
corner(sidebar, 10)
stroke(sidebar, Theme.Stroke, 1, 0.3)

local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 6)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Parent = sidebar
local sidePad = Instance.new("UIPadding")
sidePad.PaddingTop = UDim.new(0, 8)
sidePad.PaddingLeft = UDim.new(0, 8)
sidePad.PaddingRight = UDim.new(0, 8)
sidePad.Parent = sidebar

local contentHolder = Instance.new("Frame")
contentHolder.Size = UDim2.new(1, -160, 1, -84)
contentHolder.Position = UDim2.new(0, 150, 0, 74)
contentHolder.BackgroundColor3 = Theme.Panel
contentHolder.BorderSizePixel = 0
contentHolder.Parent = main
corner(contentHolder, 10)
stroke(contentHolder, Theme.Stroke, 1, 0.3)

-- вкладки
local tabs = {}

local function selectTab(name)
	for n, t in pairs(tabs) do
		local active = n == name
		t.page.Visible = active
		tween(t.btn, {
			BackgroundTransparency = active and 0 or 1,
			BackgroundColor3 = active and Theme.AccentDark or Theme.Item,
		})
		t.label.TextColor3 = active and Color3.new(1, 1, 1) or Theme.SubText
		t.bar.Visible = active
	end
end

local function addTab(name, icon, order)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 36)
	btn.BackgroundColor3 = Theme.Item
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.LayoutOrder = order
	btn.Parent = sidebar
	corner(btn, 8)

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 3, 0.6, 0)
	bar.Position = UDim2.new(0, 0, 0.2, 0)
	bar.BackgroundColor3 = Color3.fromRGB(220, 170, 255)
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = btn
	corner(bar, 2)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -14, 1, 0)
	label.Position = UDim2.new(0, 14, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = icon .. "  " .. name
	label.TextColor3 = Theme.SubText
	label.TextSize = 14
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = btn

	local page = Instance.new("ScrollingFrame")
	page.Size = UDim2.new(1, -16, 1, -16)
	page.Position = UDim2.new(0, 8, 0, 8)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 3
	page.ScrollBarImageColor3 = Theme.Accent
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.Visible = false
	page.Parent = contentHolder

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page

	tabs[name] = { btn = btn, page = page, label = label, bar = bar }
	btn.MouseButton1Click:Connect(function() selectTab(name) end)
	return page
end

-- элементы
local function addSection(page, text, order)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 18)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Theme.Accent
	l.TextSize = 12
	l.Font = Enum.Font.GothamBold
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.LayoutOrder = order
	l.Parent = page
end

local function addToggle(page, icon, text, initial, order, callback)
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, -4, 0, 40)
	row.BackgroundColor3 = Theme.Item
	row.Text = ""
	row.AutoButtonColor = false
	row.LayoutOrder = order
	row.Parent = page
	corner(row, 9)
	local rowStroke = stroke(row, Theme.Stroke, 1, 0.5)

	local ic = Instance.new("TextLabel")
	ic.Size = UDim2.new(0, 24, 1, 0)
	ic.Position = UDim2.new(0, 10, 0, 0)
	ic.BackgroundTransparency = 1
	ic.Text = icon
	ic.TextSize = 16
	ic.TextColor3 = initial and Theme.Accent or Theme.SubText
	ic.Font = Enum.Font.GothamBold
	ic.Parent = row

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -110, 1, 0)
	lbl.Position = UDim2.new(0, 40, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = Theme.Text
	lbl.TextSize = 14
	lbl.Font = Enum.Font.GothamSemibold
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local sw = Instance.new("Frame")
	sw.Size = UDim2.new(0, 42, 0, 22)
	sw.Position = UDim2.new(1, -54, 0.5, -11)
	sw.BackgroundColor3 = initial and Theme.Accent or Theme.Off
	sw.BorderSizePixel = 0
	sw.Parent = row
	corner(sw, 11)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 16, 0, 16)
	knob.Position = initial and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Parent = sw
	corner(knob, 8)

	local state = initial
	local function apply(newState)
		state = newState
		tween(knob, { Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8) })
		tween(sw, { BackgroundColor3 = state and Theme.Accent or Theme.Off })
		tween(ic, { TextColor3 = state and Theme.Accent or Theme.SubText })
		callback(state)
	end

	row.MouseEnter:Connect(function() tween(rowStroke, { Transparency = 0.1 }) end)
	row.MouseLeave:Connect(function() tween(rowStroke, { Transparency = 0.5 }) end)
	row.MouseButton1Click:Connect(function() apply(not state) end)

	return { Set = apply }
end

local function addSlider(page, text, min, max, step, initial, order, callback)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 54)
	row.BackgroundColor3 = Theme.Item
	row.LayoutOrder = order
	row.Parent = page
	corner(row, 9)
	stroke(row, Theme.Stroke, 1, 0.5)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -90, 0, 24)
	lbl.Position = UDim2.new(0, 12, 0, 4)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = Theme.Text
	lbl.TextSize = 14
	lbl.Font = Enum.Font.GothamSemibold
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local valLbl = Instance.new("TextLabel")
	valLbl.Size = UDim2.new(0, 70, 0, 24)
	valLbl.Position = UDim2.new(1, -82, 0, 4)
	valLbl.BackgroundTransparency = 1
	valLbl.TextColor3 = Theme.Accent
	valLbl.TextSize = 14
	valLbl.Font = Enum.Font.GothamBold
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	valLbl.Parent = row

	local hit = Instance.new("TextButton")
	hit.Size = UDim2.new(1, -24, 0, 20)
	hit.Position = UDim2.new(0, 12, 0, 28)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.Parent = row

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.new(0, 0, 0.5, -3)
	track.BackgroundColor3 = Theme.Off
	track.BorderSizePixel = 0
	track.Parent = hit
	corner(track, 3)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.Accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 3)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 14, 0, 14)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Parent = track
	corner(knob, 7)

	local function show(v)
		local rel = math.clamp((v - min) / (max - min), 0, 1)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, 0, 0.5, 0)
		valLbl.Text = string.format("%g", v)
	end
	show(initial)

	local dragging = false
	local function setFromX(x)
		local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local v = min + math.floor((max - min) * rel / step + 0.5) * step
		v = math.clamp(v, min, max)
		show(v)
		callback(v)
	end

	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- выбор клавиши (клик -> нажми клавишу; Esc / RightShift — отмена)
local listeningForBind = false
local updateHint = function() end

local function addKeybind(page, icon, text, initial, order, callback)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 40)
	row.BackgroundColor3 = Theme.Item
	row.LayoutOrder = order
	row.Parent = page
	corner(row, 9)
	stroke(row, Theme.Stroke, 1, 0.5)

	local ic = Instance.new("TextLabel")
	ic.Size = UDim2.new(0, 24, 1, 0)
	ic.Position = UDim2.new(0, 10, 0, 0)
	ic.BackgroundTransparency = 1
	ic.Text = icon
	ic.TextSize = 16
	ic.TextColor3 = Theme.Accent
	ic.Font = Enum.Font.GothamBold
	ic.Parent = row

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -150, 1, 0)
	lbl.Position = UDim2.new(0, 40, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = Theme.Text
	lbl.TextSize = 14
	lbl.Font = Enum.Font.GothamSemibold
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 90, 0, 26)
	btn.Position = UDim2.new(1, -100, 0.5, -13)
	btn.BackgroundColor3 = Theme.AccentDark
	btn.Text = initial.Name
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextSize = 13
	btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = false
	btn.Parent = row
	corner(btn, 7)

	local current = initial
	btn.MouseButton1Click:Connect(function()
		if listeningForBind then return end
		listeningForBind = true
		btn.Text = "..."
		local conn
		conn = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			conn:Disconnect()
			local key = input.KeyCode
			if key ~= Enum.KeyCode.Escape and key ~= Enum.KeyCode.RightShift and key ~= Enum.KeyCode.Unknown then
				current = key
				callback(key)
			end
			btn.Text = current.Name
			task.defer(function() listeningForBind = false end)
		end)
	end)
end

local function addButton(page, icon, text, order, callback)
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, -4, 0, 40)
	row.BackgroundColor3 = Theme.Item
	row.Text = ""
	row.AutoButtonColor = false
	row.LayoutOrder = order
	row.Parent = page
	corner(row, 9)
	local rowStroke = stroke(row, Theme.Stroke, 1, 0.5)

	local ic = Instance.new("TextLabel")
	ic.Size = UDim2.new(0, 24, 1, 0)
	ic.Position = UDim2.new(0, 10, 0, 0)
	ic.BackgroundTransparency = 1
	ic.Text = icon
	ic.TextSize = 16
	ic.TextColor3 = Theme.Accent
	ic.Font = Enum.Font.GothamBold
	ic.Parent = row

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -50, 1, 0)
	lbl.Position = UDim2.new(0, 40, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = Theme.Text
	lbl.TextSize = 14
	lbl.Font = Enum.Font.GothamSemibold
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	row.MouseEnter:Connect(function() tween(rowStroke, { Transparency = 0.1 }) end)
	row.MouseLeave:Connect(function() tween(rowStroke, { Transparency = 0.5 }) end)
	row.MouseButton1Click:Connect(callback)
end

-- страницы
local pageMain = addTab("Main", "🏠", 1)
local pageESP = addTab("ESP", "👁", 2)
local pageMisc = addTab("Misc", "⚙", 3)

addSection(pageMain, "FARM", 0)
addToggle(pageMain, "🚪", "Auto Farm Doors", Config.AutoFarm, 1, function(v)
	Config.AutoFarm = v
	if not v then releaseFarm() end
end)
addToggle(pageMain, "⚡", "Instant E", Config.InstantE, 2, function(v) Config.InstantE = v end)
addSection(pageMain, "MOVEMENT", 3)
local flyToggle = addToggle(pageMain, "🕊", "Fly", Config.Fly, 4, function(v)
	Config.Fly = v
	applyFly()
end)
addKeybind(pageMain, "⌨", "Fly Key", Config.FlyKey, 5, function(k)
	Config.FlyKey = k
	updateHint()
end)
addSlider(pageMain, "Fly Speed", 10, 150, 5, Config.FlySpeed, 6, function(v) Config.FlySpeed = v end)

addSection(pageESP, "ESP", 0)
addToggle(pageESP, "👤", "Player ESP", Config.PlayerESP, 1, function(v)
	Config.PlayerESP = v
	applyPlayerESP()
end)
addToggle(pageESP, "🚪", "Door ESP", Config.DoorESP, 2, function(v)
	Config.DoorESP = v
	applyDoorESP()
end)
addToggle(pageESP, "⚔", "Cooldown/Ult info ESP", Config.SkillESP, 3, function(v)
	Config.SkillESP = v
	applySkillESP()
end)

addSection(pageMisc, "MISC", 0)
addSlider(pageMisc, "Farm Delay (сек)", 0.1, 2, 0.05, Config.FarmDelay, 1, function(v) Config.FarmDelay = v end)
addSlider(pageMisc, "Wait Radius (до двери)", 50, 100, 5, Config.WaitRadius, 2, function(v) Config.WaitRadius = v end)
addSlider(pageMisc, "Farm Speed", 40, 300, 10, Config.FarmSpeed, 3, function(v) Config.FarmSpeed = v end)
local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -4, 0, 56)
hint.BackgroundColor3 = Theme.Item
hint.TextColor3 = Theme.SubText
hint.TextSize = 13
hint.Font = Enum.Font.Gotham
hint.LayoutOrder = 4
hint.Parent = pageMisc
corner(hint, 9)
updateHint = function()
	hint.Text = "RightShift — меню\n" .. Config.FlyKey.Name .. " — полёт   Space / Ctrl — вверх / вниз"
end
updateHint()

selectTab("Main")

-- перетаскивание
local function makeDraggable(frame, handle, onMove)
	local dragging, dragStart, startPos
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			if onMove and d.Magnitude > 5 then onMove() end
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

makeDraggable(main, header)

-- круглая кнопка
local ball = Instance.new("TextButton")
ball.Name = "Ball"
ball.Size = UDim2.new(0, 48, 0, 48)
ball.Position = UDim2.new(0, 30, 0.5, 0)
ball.BackgroundColor3 = Color3.fromRGB(14, 14, 14)
ball.Text = "⚡"
ball.TextColor3 = Color3.new(1, 1, 1)
ball.TextSize = 26
ball.Font = Enum.Font.GothamBold
ball.AutoButtonColor = false
ball.Visible = false
ball.Parent = gui
corner(ball, 24)
stroke(ball, Color3.new(1, 1, 1), 2)

local ballMoved = false
makeDraggable(ball, ball, function() ballMoved = true end)
ball.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		ballMoved = false
	end
end)

-- открыть / закрыть
local menuOpen = true
local function setMenu(open)
	menuOpen = open
	if open then
		main.Visible = true
		ball.Visible = false
		scale.Scale = 0.9
		tween(scale, { Scale = 1 }, 0.2)
	else
		tween(scale, { Scale = 0.9 }, 0.12)
		task.delay(0.12, function()
			if not menuOpen then
				main.Visible = false
				ball.Visible = true
			end
		end)
	end
end

minBtn.MouseButton1Click:Connect(function() setMenu(false) end)
ball.MouseButton1Click:Connect(function()
	if not ballMoved then setMenu(true) end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or listeningForBind then return end
	if input.KeyCode == Enum.KeyCode.RightShift then
		setMenu(not menuOpen)
	elseif input.KeyCode == Config.FlyKey then
		flyToggle.Set(not Config.Fly)
	end
end)

-- применяем загруженный из файла полёт
if Config.Fly then
	task.spawn(function()
		local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
		char:WaitForChild("HumanoidRootPart")
		char:WaitForChild("Humanoid")
		task.wait(0.3)
		applyFly()
	end)
end

print("[EjejHuesos Hub] loaded")
