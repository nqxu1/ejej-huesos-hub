-- EjejHuesos Hub
-- LocalScript -> StarterPlayer > StarterPlayerScripts
-- Функции: Auto Farm Doors, Instant E, Fly (настраиваемый бинд), Auto Block, Player ESP (дистанция + HP), Door ESP (таймер)
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
	LiftHeight = 12,     -- на сколько стадов поднимаемся вертикально с земли / крыши (чтобы перелететь бортики)
	CollectTime = 2,     -- сколько секунд стоим у двери после лута, чтобы забрать конфеты
	LootedSkip = 8,      -- сколько секунд не возвращаемся к только что залутанной двери
	SafeZone = nil,      -- своя безопасная точка, например Vector3.new(0, 300, 0); nil = ищем игровую SafeZone, иначе крышу подальше от игроков
	UseGameSafeZone = true, -- если в карте есть деталь с именем SafeZone — прячемся там
	FreezeTime = 1,      -- сколько секунд стоим заморожены у двери перед лутом
	PromptRange = 60,

	-- AUTO BLOCK
	AutoBlock = false,
	FaceAttacker = true,   -- всегда включён вместе с Auto Block: бьют в спину -> на время блока разворачиваемся к атакующему
	BlockKey = Enum.KeyCode.F,
	BlockDistance = 18,    -- на каком расстоянии (стадов) реагируем на удар
	BlockHold = 0.3,       -- сколько секунд держим блок (подобрано, в меню не выводится)
	BlockDelay = 0,        -- задержка перед блоком после начала чужого удара (подгони под тайминг)
	AttackFacingDot = 0,   -- реагируем, только если атакующий повёрнут к нам (1 = строго на нас, -1 = всегда)
	BlockAttributes = { "LastM1", "LastM2" }, -- атрибуты персонажа, которые меняются при ударе
	AnimDetectV2 = true,   -- самообучение: анимация, которая совпала с кликом M1/M2, дальше вызывает блок мгновенно
	BlockDebug = false,    -- true = писать в консоль F9, какая анимация / атрибут вызвали блок
	DoorName = "HalloweenDoor",
	ChaseDoors = true,     -- догонять и бить бегающую дверь (модель "Door" с Humanoid)
	ChaseTimeout = 30,     -- сколько секунд максимум гонимся за одной дверью
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
	"FlySpeed", "FarmDelay", "FarmSpeed", "WaitRadius", "CollectTime",
	"ChaseDoors", "AutoBlock", "BlockDistance",
}
local canFile = (writefile ~= nil and readfile ~= nil and isfile ~= nil)

local function serializeConfig()
	local data = { FlyKey = Config.FlyKey.Name, BlockKey = Config.BlockKey.Name }
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
	if type(data.BlockKey) == "string" then
		local okKey, key = pcall(function() return Enum.KeyCode[data.BlockKey] end)
		if okKey and key then Config.BlockKey = Enum.KeyCode.F end -- клавиша блока зафиксирована
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
	Bg = Color3.fromRGB(8, 6, 18),
	Panel = Color3.fromRGB(17, 12, 32),
	Item = Color3.fromRGB(27, 18, 48),
	Stroke = Color3.fromRGB(43, 28, 70),
	Accent = Color3.fromRGB(151, 71, 255),
	AccentDark = Color3.fromRGB(69, 30, 125),
	Lavender = Color3.fromRGB(199, 143, 255),
	VioletSoft = Color3.fromRGB(118, 74, 180),
	Text = Color3.fromRGB(248, 248, 250),
	SubText = Color3.fromRGB(156, 156, 168),
	Off = Color3.fromRGB(43, 28, 70),
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
	label.Position = UDim2.new(0, 0, 0, 12)
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
	info.Visible = false -- надпись Evasive / Ult убрана
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
		if d.bb2 then d.bb2.Enabled = Config.SkillESP end
		if d.bb3 then d.bb3.Enabled = Config.SkillESP end
	end
end

task.spawn(function()
	while task.wait(0.2) do
		if Config.SkillESP then
			for player, d in pairs(playerESP) do
				if d.info then
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

	doors[model] = { hl = hl, bb = bb, label = label, nextSearch = 0, born = os.clock() }
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
-- AUTO FARM DOORS (без ноклипа, без ходьбы и прыжков: здания обходим сверху твином)
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
local farmStatusText, farmLooted = "выключен", 0
local farmStatusLabel -- создаётся в меню
local function setFarmStatus(t)
	if t == nil then t = farmStatusText end
	if t == farmStatusText and farmStatusLabel and farmStatusLabel.Text ~= "" then return end
	farmStatusText = t
	if farmStatusLabel then
		farmStatusLabel.Text = string.format("Статус: %s\nДверей залутано: %d", farmStatusText, farmLooted)
	end
end
local lastSafe -- безопасная точка (возвышенность у последней залутанной двери)

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
	local now = os.clock()
	local lbl = d.timer
	if lbl and lbl.Parent then
		local m, sec = lbl.Text:match("^%s*(%d+):(%d%d)%s*$")
		if m then
			local v = (tonumber(m) or 0) * 60 + (tonumber(sec) or 0)
			d.lastSecs, d.lastT = v, now
			return v
		end
	end
	-- метка на миг пропала / сменила текст: не считаем дверь «готовой», а продолжаем отсчёт
	-- от последнего известного значения (раньше из-за этого скрипт иногда летел к двери с таймером 1:18)
	if d.lastSecs and now - d.lastT < 600 then
		return math.max(0, d.lastSecs - (now - d.lastT))
	end
	-- дверь только появилась и таймер ещё не нашли
	if now - (d.born or 0) < 4 then return 60 end
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
-- ---------- запоминаем места, где сервер откатывает ----------
-- Если полёт сорвался (откат / упёрлись), точка отмечается как препятствие: планировщик
-- маршрута обходит её, а прямой путь через неё не используется. Метки живут 15 минут.
local learnedBlocks = {}
local LEARN_TTL = 900

local function learnBlock(p)
	local now = os.clock()
	for i = #learnedBlocks, 1, -1 do
		local b = learnedBlocks[i]
		if now - b.t > LEARN_TTL then
			table.remove(learnedBlocks, i)
		elseif (b.p - p).Magnitude < 3 then
			b.t = now
			return
		end
	end
	learnedBlocks[#learnedBlocks + 1] = { p = p, t = now }
	if #learnedBlocks > 80 then table.remove(learnedBlocks, 1) end
end

local function nearLearned(p, r)
	local now = os.clock()
	for _, b in ipairs(learnedBlocks) do
		if now - b.t <= LEARN_TTL then
			local d = b.p - p
			if Vector3.new(d.X, 0, d.Z).Magnitude < r and math.abs(d.Y) < 9 then return true end
		end
	end
	return false
end

local function pathHitsLearned(a, b)
	local d = b - a
	local n = math.max(1, math.ceil(d.Magnitude / 3))
	for i = 0, n do
		if nearLearned(a + d * (i / n), 6) then return true end
	end
	return false
end

local farmSpeedMul = 1 -- падает после отката сервером, чтобы не ловить телепорт назад

local function tweenTo(hrp, pos)
	local dist = (pos - hrp.Position).Magnitude
	if dist < 0.5 then return true end
	local speed = Config.FarmSpeed * farmSpeedMul
	local tw = TweenService:Create(
		hrp,
		TweenInfo.new(dist / speed, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.new(pos) * hrp.CFrame.Rotation }
	)
	local done = false
	tw.Completed:Connect(function() done = true end)
	tw:Play()

	local last = hrp.Position
	local deadline = os.clock() + dist / speed + 2
	local checkAt = os.clock() + 0.5
	local checkDist = dist
	while not done do
		local dt = task.wait()
		if not Config.AutoFarm or not hrp:IsDescendantOf(Workspace) then
			tw:Cancel()
			return false
		end
		-- сервер откатил (телепорт назад) или мы застряли -> прерываем, чтобы не зависнуть
		local cur = hrp.Position
		if (cur - last).Magnitude > speed * dt * 2 + 8 or os.clock() > deadline then
			warn(string.format("[EjejHuesos Hub] полёт прерван (откат сервером / таймаут) около %d, %d, %d",
				last.X, last.Y, last.Z))
			local toward = pos - last
			learnBlock(last + (toward.Magnitude > 0.1 and toward.Unit * 4 or Vector3.zero))
			tw:Cancel()
			return false
		end
		last = cur
		-- застряли у стены: за 0.5 сек почти не приблизились к цели
		if os.clock() >= checkAt then
			local nowDist = (pos - cur).Magnitude
			if checkDist - nowDist < speed * 0.5 * 0.3 then
				warn(string.format("[EjejHuesos Hub] упёрлись в препятствие около %d, %d, %d", cur.X, cur.Y, cur.Z))
				local toward = pos - cur
				learnBlock(cur + (toward.Magnitude > 0.1 and toward.Unit * 4 or Vector3.zero))
				tw:Cancel()
				return false
			end
			checkDist = nowDist
			checkAt = os.clock() + 0.5
		end
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

-- ---------- карта проходимости (сетка + A*) ----------
-- Скрипт сам «рисует карту» вокруг маршрута: на высоте цели проверяет клетки сетки на стены
-- и ищет путь в обход. Путь сглаживается, поэтому персонаж летит прямыми отрезками между углами.
local farmIgnoreModel -- дверь, к которой летим (её детали не считаем стенами)

local function blockingPart(inst, y)
	if inst:IsA("Terrain") then return false end
	if not (inst.CanCollide or (inst.Transparency < 0.95 and inst.Size.Magnitude >= 6)) then return false end
	local m = inst:FindFirstAncestorOfClass("Model")
	if m and m:FindFirstChildOfClass("Humanoid") then return false end -- другие игроки / NPC
	local cf, sz = inst.CFrame, inst.Size
	local ext = (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z) / 2
	if cf.Position.Y + ext < y - 0.8 then return false end -- пол / земля ниже нашей высоты
	return true
end

local function gridRoute(startPos, goalPos)
	local CELL = 4
	local y = goalPos.Y
	local s2 = Vector3.new(startPos.X, y, startPos.Z)
	if (s2 - goalPos).Magnitude > 450 then return nil end

	local params = makeRayParams()
	if math.abs(startPos.Y - y) > 1.5 and not segmentClear(startPos, s2, params) then return nil end

	local minX = math.min(s2.X, goalPos.X) - 60
	local maxX = math.max(s2.X, goalPos.X) + 60
	local minZ = math.min(s2.Z, goalPos.Z) - 60
	local maxZ = math.max(s2.Z, goalPos.Z) + 60
	local cols = math.ceil((maxX - minX) / CELL) + 1
	local rows = math.ceil((maxZ - minZ) / CELL) + 1
	if cols * rows > 9000 then return nil end

	local function cellOf(p) return math.floor((p.X - minX) / CELL), math.floor((p.Z - minZ) / CELL) end
	local function center(cx, cz) return Vector3.new(minX + (cx + 0.5) * CELL, y, minZ + (cz + 0.5) * CELL) end
	local function key(cx, cz) return cx * 10000 + cz end

	local filter = { LocalPlayer.Character }
	if farmIgnoreModel then filter[#filter + 1] = farmIgnoreModel end
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = filter
	op.RespectCanCollide = false

	local sx, sz = cellOf(s2)
	local gx, gz = cellOf(goalPos)
	local forced = { [key(sx, sz)] = true, [key(gx, gz)] = true }
	local cache = {}
	local function free(cx, cz)
		if cx < 0 or cz < 0 or cx >= cols or cz >= rows then return false end
		local k = key(cx, cz)
		if forced[k] then return true end
		local v = cache[k]
		if v ~= nil then return v end
		local ok = not nearLearned(center(cx, cz), CELL * 0.5 + 4)
		for _, inst in ipairs(ok and Workspace:GetPartBoundsInBox(CFrame.new(center(cx, cz)), Vector3.new(CELL + 2, 2.2, CELL + 2), op) or {}) do
			if blockingPart(inst, y) then ok = false break end
		end
		cache[k] = ok
		return ok
	end

	-- A* с бинарной кучей
	local heap, hn = {}, 0
	local function push(k, f)
		hn += 1
		heap[hn] = { k, f }
		local i = hn
		while i > 1 do
			local par = i // 2
			if heap[par][2] <= heap[i][2] then break end
			heap[par], heap[i] = heap[i], heap[par]
			i = par
		end
	end
	local function pop()
		local top = heap[1]
		heap[1] = heap[hn]
		heap[hn] = nil
		hn -= 1
		local i = 1
		while true do
			local l, r, m = i * 2, i * 2 + 1, i
			if l <= hn and heap[l][2] < heap[m][2] then m = l end
			if r <= hn and heap[r][2] < heap[m][2] then m = r end
			if m == i then break end
			heap[m], heap[i] = heap[i], heap[m]
			i = m
		end
		return top[1]
	end

	local startKey, goalKey = key(sx, sz), key(gx, gz)
	local g, came, closed = { [startKey] = 0 }, {}, {}
	local function h(cx, cz)
		local dx, dz = math.abs(cx - gx), math.abs(cz - gz)
		return (dx + dz) + (1.41421 - 2) * math.min(dx, dz)
	end
	push(startKey, h(sx, sz))
	local found, steps = false, 0
	while hn > 0 do
		local k = pop()
		if not closed[k] then
			closed[k] = true
			if k == goalKey then found = true break end
			local cx, cz = k // 10000, k % 10000
			for dx = -1, 1 do
				for dz = -1, 1 do
					if dx ~= 0 or dz ~= 0 then
						local nx, nz = cx + dx, cz + dz
						local nk = key(nx, nz)
						if not closed[nk] and free(nx, nz)
							and (dx == 0 or dz == 0 or (free(cx + dx, cz) and free(cx, cz + dz))) then
							local ng = g[k] + ((dx ~= 0 and dz ~= 0) and 1.41421 or 1)
							if not g[nk] or ng < g[nk] then
								g[nk] = ng
								came[nk] = k
								push(nk, ng + h(nx, nz))
							end
						end
					end
				end
			end
			steps += 1
			if steps % 250 == 0 then task.wait() end
			if steps > 6000 then return nil end
		end
	end
	if not found then return nil end

	local pts, k = {}, goalKey
	while k do
		table.insert(pts, 1, center(k // 10000, k % 10000))
		k = came[k]
	end
	pts[1] = s2
	pts[#pts] = goalPos

	local function lineFree(a, b)
		local d = b - a
		local n = math.max(1, math.ceil(d.Magnitude / (CELL * 0.5)))
		for i = 1, n - 1 do
			local cx, cz = cellOf(a + d * (i / n))
			if not free(cx, cz) then return false end
		end
		return true
	end
	local out, i = { s2 }, 1
	while i < #pts do
		local j = #pts
		while j > i + 1 and not lineFree(pts[i], pts[j]) do j -= 1 end
		out[#out + 1] = pts[j]
		i = j
	end
	return out
end

-- перелёт над зданием вместо прыжков: строго вверх -> вбок на высоте выше крыш -> вниз.
-- Всё твином. Если сверху навес / потолок — пробуем соседние колонки подъёма и чуть более высокие эшелоны.
-- Возвращает (нашли ли маршрут, долетели ли).
local function overFly(hrp, goal, params)
	local start = hrp.Position
	local base = cruiseY(start, goal, params)
	local ceilingY = math.max(start.Y, goal.Y) + 220 -- выше не лезем (потолки карты / античит)
	local offsets = {
		Vector3.zero, Vector3.new(10, 0, 0), Vector3.new(-10, 0, 0),
		Vector3.new(0, 0, 10), Vector3.new(0, 0, -10),
	}
	for _, extra in ipairs({ 0, 30, 70 }) do
		local y = base + extra
		if y > ceilingY then break end
		for _, off in ipairs(offsets) do
			if not Config.AutoFarm then return false, false end
			local s0 = start + off
			local p1 = Vector3.new(s0.X, y, s0.Z)
			local p2 = Vector3.new(goal.X, y, goal.Z)
			if (off == Vector3.zero or segmentClear(start, s0, params))
				and segmentClear(s0, p1, params)
				and segmentClear(p1, p2, params)
				and segmentClear(p2, goal, params)
				and not nearLearned(p1, 6) then
				if off ~= Vector3.zero and not tweenTo(hrp, s0) then return true, false end
				return true, (tweenTo(hrp, p1) and tweenTo(hrp, p2) and tweenTo(hrp, goal))
			end
		end
	end
	return false, false
end

-- безопасный полёт без ноклипа.
-- обычный порядок: прямо -> над постройками -> по навмешу
-- preferGround (между дверями): прямо -> по навмешу -> над постройками (только если иначе никак)
local descending = false
local function flyTo(goal, preferGround)
	local _, hrp = getChar()
	if not hrp then return false end
	local params = makeRayParams()
	local start = hrp.Position

	if segmentClear(start, goal, params) and not pathHitsLearned(start, goal) then
		return tweenTo(hrp, goal)
	end

	-- мы высоко над целью (укрытие на крыше): сначала спускаемся по ближайшей свободной вертикали
	if start.Y - goal.Y > 5 and not descending then
		local best, bestD
		for _, radius in ipairs({ 0, 10, 20, 30, 45, 60 }) do
			for deg = 0, (radius == 0 and 0 or 330), 30 do
				local rad = math.rad(deg)
				local p = Vector3.new(start.X + math.cos(rad) * radius, start.Y, start.Z + math.sin(rad) * radius)
				local low = Vector3.new(p.X, goal.Y, p.Z)
				if (radius == 0 or segmentClear(start, p, params)) and segmentClear(p, low, params) and not nearLearned(p, 6) then
					local dd = Vector3.new(p.X - goal.X, 0, p.Z - goal.Z).Magnitude
					if not bestD or dd < bestD then best, bestD = p, dd end
				end
			end
			if best then break end -- ближайшая свободная колонна найдена
		end
		if best then
			local low = Vector3.new(best.X, goal.Y, best.Z)
			if (best - start).Magnitude > 1 and not tweenTo(hrp, best) then return false end
			if not tweenTo(hrp, low) then return false end
			descending = true
			local ok = flyTo(goal, preferGround)
			descending = false
			return ok
		end
	end

	-- обход стен по сетке (основной способ)
	local okRoute, route = pcall(gridRoute, start, goal)
	if okRoute and route then
		if (route[1] - start).Magnitude > 1 then
			if not tweenTo(hrp, route[1]) then return false end
		end
		for i = 2, #route do
			if not Config.AutoFarm then return false end
			if not tweenTo(hrp, route[i]) then return false end
		end
		return Config.AutoFarm
	elseif not okRoute then
		warn("[EjejHuesos Hub] ошибка построения маршрута: " .. tostring(route))
	end

	if preferGround then
		if walkPathTo(hrp, goal, params) then return true end
		if not Config.AutoFarm then return false end
		local _, ok = overFly(hrp, goal, params)
		return ok
	end

	local tried, ok = overFly(hrp, goal, params)
	if tried then return ok end
	return walkPathTo(hrp, goal, params)
end

local function isGrounded(hrp)
	local params = makeRayParams()
	return Workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0), params) ~= nil
end

-- взлёт: с земли / крыши сначала строго вверх выше бортиков и заборов, и только потом вбок
local function liftOff(hrp)
	if not isGrounded(hrp) then return end
	local up = hrp.Position + Vector3.new(0, Config.LiftHeight, 0)
	if segmentClear(hrp.Position, up, makeRayParams()) then
		tweenTo(hrp, up)
	end
end

-- полёт с повторами. Пешком не ходим и не прыгаем: упёрлись — пересчитываем маршрут
-- (место срыва запоминается и обходится), летим чуть медленнее; здания обходим сверху твином (overFly).
local function flyRetry(goal, preferGround, noHop)
	farmSpeedMul = 1
	for _ = 1, (noHop and 2 or 4) do
		if not Config.AutoFarm then return false end
		local _, hrp = getChar()
		if hrp then
			setFarmAnchored(hrp, true)
			liftOff(hrp)
		end
		if flyTo(goal, preferGround) then return true end
		if not Config.AutoFarm then return false end
		farmSpeedMul = math.max(0.6, farmSpeedMul - 0.1)
		task.wait(0.3)
	end
	return false
end

-- ---------- выбор точек ----------
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

-- безопасная точка: высокое место (крыша / возвышенность) подальше от других игроков
local function nearestPlayerDist(pos)
	local best = math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and p.Character then
			local r = p.Character:FindFirstChild("HumanoidRootPart")
			if r then best = math.min(best, (r.Position - pos).Magnitude) end
		end
	end
	return best
end

local safeSpot -- текущее укрытие
local airSpot -- запасное укрытие: просто вверх над текущим местом (если ничего лучше не нашлось)
local badSpots = {} -- точки, куда долететь не удалось

-- игровая безопасная зона: деталь с именем SafeZone / Safe Zone / safe_zone (ищем один раз)
local gameSafeZone
local gameSafeZoneSearched = false
local function gameSafeZonePoint()
	if not (gameSafeZone and gameSafeZone.Parent) then
		if gameSafeZoneSearched then return nil end
		gameSafeZoneSearched = true
		for _, o in ipairs(Workspace:GetDescendants()) do
			if o:IsA("BasePart") then
				local n = (o.Name:lower():gsub("[%s_%-]", ""))
				if n == "safezone" then
					gameSafeZone = o
					warn("[EjejHuesos Hub] найдена безопасная зона: " .. o:GetFullName())
					break
				end
			end
		end
		if not gameSafeZone then return nil end
	end
	local _, hrp0, hum0 = getChar()
	local feet = (hum0 and hum0.HipHeight or 2) + (hrp0 and hrp0.Size.Y / 2 or 1) + 0.3
	local c, sz = gameSafeZone.Position, gameSafeZone.Size
	local r = Workspace:Raycast(c + Vector3.new(0, sz.Y / 2 + 1, 0), Vector3.new(0, -sz.Y - 300, 0), makeRayParams())
	local p = (r and r.Position or c) + Vector3.new(0, feet, 0)
	for _, b in ipairs(badSpots) do
		if (b - p).Magnitude < 25 then return nil end -- сюда уже не долетели
	end
	return p
end

-- крыша / возвышенность подальше от игроков. Улицу (землю) выбираем только если крыш вообще нет:
-- на улице убивают.
local function pickSafeSpot(fromPos)
	local params = makeRayParams()
	local _, hrp0, hum0 = getChar()
	local feet = (hum0 and hum0.HipHeight or 2) + (hrp0 and hrp0.Size.Y / 2 or 1) + 0.3
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { LocalPlayer.Character }
	op.RespectCanCollide = true
	local cands, minY = {}, math.huge
	for _, radius in ipairs({ 50, 100, 160 }) do
		for deg = 0, 330, 30 do
			local rad = math.rad(deg)
			local x = fromPos.X + math.cos(rad) * radius
			local z = fromPos.Z + math.sin(rad) * radius
			local r = Workspace:Raycast(Vector3.new(x, fromPos.Y + 300, z), Vector3.new(0, -800, 0), params)
			if r and r.Normal.Y > 0.9 then -- только ровная поверхность (крыша / земля)
				local m = r.Instance:FindFirstAncestorOfClass("Model")
				if not (m and m:FindFirstChildOfClass("Humanoid")) then
					local p = r.Position + Vector3.new(0, feet, 0) -- стоим НА поверхности
					local bad = false
					for _, b in ipairs(badSpots) do
						if (b - p).Magnitude < 25 then bad = true break end
					end
					if not bad and #Workspace:GetPartBoundsInBox(CFrame.new(p + Vector3.new(0, 1, 0)), Vector3.new(4, 4, 4), op) == 0 then
						cands[#cands + 1] = { p = p, y = r.Position.Y, radius = radius, dist = nearestPlayerDist(p) }
						minY = math.min(minY, r.Position.Y)
					end
				end
			end
		end
	end
	if #cands == 0 then return nil end

	local function best(minElev)
		local bp, bs
		for _, c in ipairs(cands) do
			local elev = c.y - minY -- высота над уличным уровнем
			if elev >= minElev then
				local score = math.min(c.dist, 150) + elev * 0.8 - c.radius * 0.15
				if not bs or score > bs then bp, bs = c.p, score end
			end
		end
		return bp
	end
	return best(12) or best(0) -- сначала настоящие крыши (выше улицы минимум на 12), потом что угодно
end

-- летим в укрытие и стоим там (без прыжков и без ходьбы)
local function goToShelter(hrp)
	farmIgnoreModel = nil
	local safe = Config.SafeZone
	if not safe and Config.UseGameSafeZone then
		safe = gameSafeZonePoint()
	end
	if not safe then
		-- выбираем укрытие заново, если его нет или рядом появился игрок
		if not safeSpot or nearestPlayerDist(safeSpot) < 45 then
			safeSpot = pickSafeSpot(hrp.Position) or lastSafe
		end
		safe = safeSpot
	end
	if not safe then
		-- крыш не нашлось: хотя бы поднимаемся вверх, а не стоим на улице
		if not airSpot then
			local up = hrp.Position + Vector3.new(0, 40, 0)
			if segmentClear(hrp.Position, up, makeRayParams()) then airSpot = up end
		end
		safe = airSpot
	else
		airSpot = nil
	end
	setFarmAnchored(hrp, true)
	if safe and (hrp.Position - safe).Magnitude > 3 then
		setFarmStatus("лечу в укрытие")
		-- к крыше подлетаем сверху (над бортиками) и опускаемся вертикально
		local above = safe + Vector3.new(0, Config.LiftHeight, 0)
		local arrived = flyRetry(above, false, true)
		if arrived then
			local _, h2 = getChar()
			if h2 then arrived = tweenTo(h2, safe) end
		end
		if not arrived and Config.AutoFarm then
			warn("[EjejHuesos Hub] не долетел до укрытия, выберу другое")
			badSpots[#badSpots + 1] = safe
			if #badSpots > 10 then table.remove(badSpots, 1) end
			if safe == safeSpot then safeSpot = nil end
			if safe == airSpot then airSpot = nil end
			task.wait(0.5)
		end
	else
		setFarmStatus("в укрытии, жду")
		local _, _, hum = getChar()
		if hum then hum.Jump = false end
		task.wait(0.3)
	end
end

-- ============================================================
-- БЕГАЮЩАЯ ДВЕРЬ: модель "Door" с Humanoid (R6-риг, рядом с персонажами игроков).
-- Её нужно догнать и ударить (M1). Ищем один раз и дальше следим за появлением/исчезновением.
-- ============================================================
local runnerDoors = {}
local skipRunner = setmetatable({}, { __mode = "k" })
local okVIM2, VIM2 = pcall(function() return game:GetService("VirtualInputManager") end)

local function registerRunner(m)
	if runnerDoors[m] or not m:IsA("Model") or m.Name ~= "Door" then return end
	if Players:GetPlayerFromCharacter(m) then return end
	task.spawn(function()
		local hum = m:WaitForChild("Humanoid", 3)
		local root = m:WaitForChild("HumanoidRootPart", 3)
		if hum and root and m.Parent then runnerDoors[m] = true end
	end)
end

task.spawn(function()
	local n = 0
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst.Name == "Door" then registerRunner(inst) end
		n += 1
		if n % 3000 == 0 then task.wait() end
	end
end)
Workspace.DescendantAdded:Connect(function(inst)
	if inst.Name == "Door" then registerRunner(inst) end
end)
Workspace.DescendantRemoving:Connect(function(inst)
	if runnerDoors[inst] then runnerDoors[inst] = nil end
end)

-- «настоящая» бегающая дверь: видимая, не декорация/заготовка
local function runnerVisible(m)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 then return true end
		if d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then return true end
	end
	return false
end

local function runnerAlive(m)
	if not m.Parent then return false end
	local root = m:FindFirstChild("HumanoidRootPart")
	local hum = m:FindFirstChildOfClass("Humanoid")
	return root ~= nil and root.Parent ~= nil and (hum == nil or hum.Health > 0)
end

local function pickRunner(hrp)
	local best, bestD = nil, math.huge
	for m in pairs(runnerDoors) do
		if runnerAlive(m) and runnerVisible(m) and (skipRunner[m] or 0) < os.clock() then
			local dist = (m.HumanoidRootPart.Position - hrp.Position).Magnitude
			if dist < bestD then best, bestD = m, dist end
		end
	end
	return best
end

local function clickM1()
	if not (okVIM2 and VIM2) then return end
	local cam = Workspace.CurrentCamera
	local c = cam and cam.ViewportSize / 2 or Vector2.new(400, 300)
	pcall(function()
		VIM2:SendMouseButtonEvent(c.X, c.Y, 0, true, game, 1)
		VIM2:SendMouseButtonEvent(c.X, c.Y, 0, false, game, 1)
	end)
end

-- догоняем и бьём, пока дверь не исчезнет / не умрёт / не истечёт таймаут
local function chaseRunner(model)
	local rhrp = model:FindFirstChild("HumanoidRootPart")
	if not rhrp then return end
	local t0, lastClick, fails, lastT = os.clock(), 0, 0, os.clock()
	farmIgnoreModel = model
	setFarmStatus("гонюсь за бегущей дверью")
	while Config.AutoFarm and Config.ChaseDoors and runnerAlive(model) and os.clock() - t0 < Config.ChaseTimeout do
		local _, hrp, hum = getChar()
		if not hrp or not hum or hum.Health <= 0 then return end
		setFarmAnchored(hrp, true)
		local target = rhrp.Position
		local dist = (target - hrp.Position).Magnitude
		local now = os.clock()
		local dt = math.clamp(now - lastT, 0.01, 0.2)
		lastT = now

		local near = false
		if dist > 14 then
			-- далеко: обычный полёт с обходом препятствий (цель подвижна, поэтому после прилёта пересчитаем)
			local back = (hrp.Position - target)
			back = back.Magnitude > 0.1 and back.Unit or Vector3.new(0, 0, 1)
			if flyTo(target + back * 4, false) then fails = 0 else
				fails += 1
				if fails >= 3 then
					skipRunner[model] = os.clock() + 8
					setFarmStatus("не догнать дверь")
					return
				end
				task.wait(0.2)
			end
		else
			-- рядом: прижимаемся вплотную (~1.8 стада) и смотрим на дверь
			local toMe = hrp.Position - target
			toMe = Vector3.new(toMe.X, 0, toMe.Z)
			toMe = toMe.Magnitude > 0.1 and toMe.Unit or Vector3.new(0, 0, 1)
			local want = Vector3.new(target.X, target.Y, target.Z) + toMe * 1.8 -- вплотную к двери
			local step = math.min((want - hrp.Position).Magnitude, Config.FarmSpeed * dt)
			local dirv = want - hrp.Position
			local newPos = dirv.Magnitude > 0.05 and hrp.Position + dirv.Unit * step or hrp.Position
			if segmentClear(hrp.Position, newPos, makeRayParams(model)) then
				hrp.CFrame = CFrame.lookAt(newPos, Vector3.new(target.X, newPos.Y, target.Z))
				near = (target - newPos).Magnitude <= 4.5
			elseif not flyTo(want, false) then
				fails += 1
				if fails >= 3 then skipRunner[model] = os.clock() + 8 return end
			end
			task.wait(0.03)
		end
		if near and now - lastClick > 0.22 then
			lastClick = now
			clickM1()
		end
	end
	if not runnerAlive(model) then
		farmLooted += 1
		setFarmStatus("дверь побита")
	else
		skipRunner[model] = os.clock() + 8
	end
end

local function farmStep()
		if not Config.AutoFarm then
			if farmAnchoredHrp then releaseFarm() end
			setFarmStatus("выключен")
			return
		end

		local _, hrp, hum = getChar()
		if not hrp or not hum or hum.Health <= 0 then
			farmAnchoredHrp = nil
			task.wait(0.5)
			return
		end

		-- бегающая дверь важнее: она убегает, статичные никуда не денутся
		-- только во время ивента: пока нет дверей / таймера, никуда не летим
		local eventOn = false
		for dm, dd in pairs(doors) do
			if dm.Parent and getPrompt(dm, dd) then eventOn = true break end
		end
		if Config.ChaseDoors and eventOn then
			local runner = pickRunner(hrp)
			if runner then
				chaseRunner(runner)
				return
			end
		end

		local model, d, prompt = pickDoor(hrp)
		if not model then
			-- других дверей нет: в укрытие и ждём
			goToShelter(hrp)
			return
		end

		setFarmAnchored(hrp, true)
		farmIgnoreModel = model

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

		-- 1) пока таймер большой — ждём в укрытии, вылетаем только когда пора
		local fromPos = hrp.Position
		local travel = (doorPos - hrp.Position).Magnitude / Config.FarmSpeed + 3
		if doorSecondsLeft(d) > travel then
			goToShelter(hrp)
			return
		end
		farmIgnoreModel = model

		-- 2) к двери (без ноклипа). Между дверями наверх не поднимаемся
		prompt = getPrompt(model, d)
		if not prompt then return end
		doorPos = promptPosition(prompt, model)
		local spot = pickDoorSpot(model, doorPos, fromPos)
		if not spot then
			giveUp(model, 20)
			return
		end
		setFarmStatus("лечу к двери")
		if not flyRetry(spot, true) then
			warn("[EjejHuesos Hub] не долетел до двери, пропускаю её на 3 сек")
			setFarmStatus("не долететь до двери")
			giveUp(model, 3)
			return
		end
		setFarmStatus("жду таймер у двери")

		-- 3) если таймер ещё не кончился — ждём у двери, потом замораживаемся и лутаем
		if not waitReady(30) then
			giveUp(model, 10)
			return
		end

		setFarmStatus("забираю лут")
		local frozen = 0
		while frozen < Config.FreezeTime and Config.AutoFarm and model.Parent do
			task.wait(0.05)
			frozen += 0.05
		end
		if model.Parent and Config.AutoFarm then
			-- безопасную точку считаем заранее: после лута дверь может исчезнуть
			lastSafe = pickSafeSpot(doorPos) or lastSafe
			pcall(firePrompt, prompt)
			-- стоим на месте, пока конфеты долетят до нас
			local t = 0
			while t < Config.CollectTime and Config.AutoFarm do
				task.wait(0.05)
				t += 0.05
			end
			-- эту дверь пропускаем, чтобы сразу лететь к следующей (или в безопасную точку)
			skipDoor[model] = os.clock() + Config.LootedSkip
			farmLooted += 1
			setFarmStatus("лут собран")
		end
end

-- любая ошибка (например, при смерти персонажа) не должна убивать цикл автофарма насовсем
task.spawn(function()
	while true do
		task.wait(0.1)
		local ok, err = pcall(farmStep)
		if not ok then
			warn("[EjejHuesos Hub] ошибка автофарма: " .. tostring(err))
			pcall(releaseFarm)
			farmSpeedMul = 1
			task.wait(0.5)
		end
	end
end)

-- ============================================================
-- AUTO BLOCK
-- Чужой удар = изменение атрибута LastM1 / LastM2 на его персонаже (Explorer -> Characters -> модель).
-- В момент удара на долю секунды зажимаем кнопку блока. Если бьют в спину — на время блока
-- разворачиваем персонажа лицом к атакующему, а после блока возвращаем прежний поворот.
-- ============================================================
local okVIM, VIM = pcall(function() return game:GetService("VirtualInputManager") end)
local blocking = false
local blockUntil = 0
local aimTarget -- HumanoidRootPart атакующего, на которого сейчас развёрнуты
local savedRot, savedAutoRotate -- поворот и AutoRotate до разворота

local function sendBlockKey(down)
	local key = Config.BlockKey
	local sent = false
	if okVIM and VIM then
		sent = pcall(function() VIM:SendKeyEvent(down, key, false, game) end)
	end
	if not sent then
		-- запасной вариант: keypress / keyrelease (только для клавиш-букв и цифр)
		local fn = down and keypress or keyrelease
		if fn and #key.Name == 1 then pcall(fn, string.byte(key.Name:upper())) end
	end
end

-- отпускаем блок и возвращаем персонажа в прежнее положение
local function stopBlock()
	if blocking then
		blocking = false
		sendBlockKey(false)
	end
	local _, hrp, hum = getChar()
	if savedRot and hrp and hrp.Parent then
		hrp.CFrame = CFrame.new(hrp.Position) * savedRot
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
	if hum and savedAutoRotate ~= nil then hum.AutoRotate = savedAutoRotate end
	savedRot, savedAutoRotate, aimTarget = nil, nil, nil
end

local function startBlock(attackerHrp)
	if not Config.AutoBlock then return end
	if UserInputService:GetFocusedTextBox() then return end -- пишем в чат
	local char, hrp, hum = getChar()
	if not char or not hrp or not hum or hum.Health <= 0 then return end

	-- в рагдолле блокировать нечем
	local rag = char:GetAttribute("Ragdoll")
	if rag == true or (type(rag) == "number" and rag ~= 0) then return end

	-- бьют в спину / сбоку: разворачиваемся к атакующему
	if Config.FaceAttacker and attackerHrp and attackerHrp.Parent then
		local to = attackerHrp.Position - hrp.Position
		local flat = Vector3.new(to.X, 0, to.Z)
		local look = hrp.CFrame.LookVector
		local front = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.5 and front.Magnitude > 0.01 and front.Unit:Dot(flat.Unit) < 0.5 then
			if not savedRot then
				savedRot = hrp.CFrame.Rotation
				savedAutoRotate = hum.AutoRotate
			end
			hum.AutoRotate = false
			aimTarget = attackerHrp
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
			hrp.AssemblyAngularVelocity = Vector3.zero
			task.wait() -- кадр на поворот, и только потом блок
		end
	end

	blockUntil = math.max(blockUntil, os.clock() + Config.BlockHold)
	if not blocking then
		blocking = true
		sendBlockKey(true)
	end
end

-- пока блок держится: следим за атакующим и отпускаем по таймеру
RunService.Heartbeat:Connect(function()
	if not blocking and not savedRot then return end
	local _, hrp, hum = getChar()
	if not hrp or not hum or hum.Health <= 0 then
		if blocking then sendBlockKey(false) end
		blocking = false
		savedRot, savedAutoRotate, aimTarget = nil, nil, nil
		return
	end
	if aimTarget and aimTarget.Parent then
		local a = aimTarget.Position
		local flat = Vector3.new(a.X - hrp.Position.X, 0, a.Z - hrp.Position.Z)
		if flat.Magnitude > 0.5 then
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
		end
	end
	if os.clock() >= blockUntil or not Config.AutoBlock then
		stopBlock()
	end
end)

-- анимации, которые точно не являются ударом (блок / уклон / стан / эмоции ...)
local NON_ATTACK = { "block", "guard", "parry", "dodge", "evasive", "evade", "dash", "stun", "ragdoll",
	"emote", "dance", "idle", "walk", "run", "sprint", "jump", "fall", "land", "hurt", "knock", "getup", "equip" }
local function isNonAttackAnim(name)
	name = tostring(name):lower()
	for _, w in ipairs(NON_ATTACK) do
		if name:find(w, 1, true) then return true end
	end
	return false
end

-- противник сам держит блок: он не бьёт (и его «блок» не должен запускать наш)
local function isBlockingNow(char)
	for name, v in pairs(char:GetAttributes()) do
		if tostring(name):lower():find("block", 1, true) and (v == true or (type(v) == "number" and v ~= 0)) then
			return true
		end
	end
	return false
end

local function onAttack(char, reason)
	if not Config.AutoBlock then return end
	local _, hrp, hum = getChar()
	if not hrp or not hum or hum.Health <= 0 then return end
	local ahrp = char:FindFirstChild("HumanoidRootPart")
	if not ahrp then return end
	if isBlockingNow(char) then return end
	local d = hrp.Position - ahrp.Position -- от атакующего к нам
	if d.Magnitude > Config.BlockDistance or d.Magnitude < 0.01 then return end
	-- бьёт ли он в нашу сторону (иначе удар мимо, блок не нужен)
	if ahrp.CFrame.LookVector:Dot(d.Unit) < Config.AttackFacingDot then return end
	if Config.BlockDebug then warn("[EjejHuesos Hub] удар от " .. char.Name .. ": " .. tostring(reason)) end
	if Config.BlockDelay > 0 then
		task.delay(Config.BlockDelay, startBlock, ahrp)
	else
		task.spawn(startBlock, ahrp)
	end
end

local blockWatch = {} -- [player] = { соединения }
local attackAnims = {}  -- [AnimationId] = true: анимации, которые реально были ударом (выучены по кликам M1/M2)

local function unwatchAttacker(player)
	local conns = blockWatch[player]
	if conns then
		for _, c in ipairs(conns) do c:Disconnect() end
		blockWatch[player] = nil
	end
end

local function watchAttacker(player, char)
	unwatchAttacker(player)
	local conns, t0 = {}, os.clock()
	local lastAction = nil -- { id, t } последняя «боевая» анимация этого игрока
	blockWatch[player] = conns
	for _, attr in ipairs(Config.BlockAttributes) do
		local last = char:GetAttribute(attr)
		conns[#conns + 1] = char:GetAttributeChangedSignal(attr):Connect(function()
			local v = char:GetAttribute(attr)
			-- первую секунду после спавна игнорируем: там атрибуты просто выставляются
			if os.clock() - t0 < 1 or v == nil or v == last then
				last = v
				return
			end
			last = v
			-- клик: запоминаем анимацию, которая только что началась, как анимацию удара
			if lastAction and os.clock() - lastAction.t < 0.6 and not attackAnims[lastAction.id] then
				attackAnims[lastAction.id] = true
				if Config.BlockDebug then warn("[EjejHuesos Hub] выучена анимация удара: " .. lastAction.id) end
			end
			onAttack(char, "атрибут " .. attr)
		end)
	end

	-- детект по анимации: AnimationPlayed срабатывает в начале замаха, раньше чем игра обновит LastM1
	task.spawn(function()
		local hum = char:WaitForChild("Humanoid", 5)
		local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5))
		if not animator or blockWatch[player] ~= conns then return end
		local ACTION = {
			[Enum.AnimationPriority.Action] = true,
			[Enum.AnimationPriority.Action2] = true,
			[Enum.AnimationPriority.Action3] = true,
			[Enum.AnimationPriority.Action4] = true,
		}
		conns[#conns + 1] = animator.AnimationPlayed:Connect(function(track)
			if os.clock() - t0 < 1 then return end
			if not ACTION[track.Priority] then return end -- ходьба / idle / падение не считаем
			if isNonAttackAnim(track.Name) then return end -- блок, уклон, эмоции и т.п. — не удар
			local id = tostring(track.Animation and track.Animation.AnimationId or track.Name)
			lastAction = { id = id, t = os.clock() }
			-- реагируем мгновенно только на анимации, которые уже были ударом (клик M1/M2)
			if not (Config.AnimDetectV2 and attackAnims[id]) then return end
			onAttack(char, string.format("анимация %s (%s, приоритет %s)", track.Name, tostring(track.Animation and track.Animation.AnimationId), track.Priority.Name))
		end)
	end)
end

local function setupBlockWatch(player)
	if player == LocalPlayer then return end
	if player.Character then watchAttacker(player, player.Character) end
	player.CharacterAdded:Connect(function(char) watchAttacker(player, char) end)
end

Players.PlayerAdded:Connect(setupBlockWatch)
Players.PlayerRemoving:Connect(unwatchAttacker)
for _, p in ipairs(Players:GetPlayers()) do setupBlockWatch(p) end

LocalPlayer.CharacterAdded:Connect(function()
	farmAnchoredHrp = nil
	farmSpeedMul = 1
	farmIgnoreModel = nil
	safeSpot, airSpot = nil, nil
end)

LocalPlayer.CharacterRemoving:Connect(function()
	if blocking then sendBlockKey(false) end
	blocking = false
	savedRot, savedAutoRotate, aimTarget = nil, nil, nil
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

-- свечение и тень за окном
local glow = Instance.new("Frame")
glow.Name = "Glow"
glow.AnchorPoint = Vector2.new(0.5, 0.5)
glow.Size = UDim2.new(0, 575, 0, 415)
glow.Position = UDim2.new(0.5, 0, 0.5, 0)
glow.BackgroundColor3 = Theme.Accent
glow.BackgroundTransparency = 0.93
glow.BorderSizePixel = 0
glow.Parent = gui
corner(glow, 30)
local glowGrad = Instance.new("UIGradient")
glowGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.AccentDark),
	ColorSequenceKeypoint.new(0.5, Theme.Accent),
	ColorSequenceKeypoint.new(1, Theme.AccentDark),
})
glowGrad.Rotation = 90
glowGrad.Parent = glow

local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Size = UDim2.new(0, 540, 0, 380)
shadow.Position = UDim2.new(0.5, 0, 0.5, 8)
shadow.BackgroundColor3 = Color3.new(0, 0, 0)
shadow.BackgroundTransparency = 0.48
shadow.BorderSizePixel = 0
shadow.Parent = gui
corner(shadow, 22)

local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Size = UDim2.new(0, 540, 0, 380)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.BackgroundColor3 = Theme.Bg
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
corner(main, 22)
local mainStroke = stroke(main, Theme.VioletSoft, 1, 0.55)

local scale = Instance.new("UIScale")
scale.Parent = main

local bgGrad = Instance.new("UIGradient")
bgGrad.Color = ColorSequence.new(Color3.fromRGB(23, 12, 42), Theme.Bg)
bgGrad.Rotation = 90
bgGrad.Parent = main

-- свечение и тень следуют за окном (перетаскивание, показ / скрытие)
local function syncBack()
	glow.Position = main.Position
	shadow.Position = main.Position + UDim2.new(0, 0, 0, 8)
	glow.Visible = main.Visible
	shadow.Visible = main.Visible
end
main:GetPropertyChangedSignal("Position"):Connect(syncBack)
main:GetPropertyChangedSignal("Visible"):Connect(syncBack)

-- неоновая линия под шапкой
local edge = Instance.new("Frame")
edge.Name = "Edge"
edge.Position = UDim2.new(0, 18, 0, 68)
edge.Size = UDim2.new(1, -36, 0, 1)
edge.BackgroundColor3 = Theme.Accent
edge.BorderSizePixel = 0
edge.Parent = main
local edgeGrad = Instance.new("UIGradient")
edgeGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.85),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 0.85),
})
edgeGrad.Parent = edge

-- шапка
local header = Instance.new("Frame")
header.Size = UDim2.new(1, -20, 0, 54)
header.Position = UDim2.new(0, 10, 0, 8)
header.BackgroundTransparency = 1
header.Active = true
header.BorderSizePixel = 0
header.Parent = main

local logoGlow = Instance.new("Frame")
logoGlow.Size = UDim2.new(0, 43, 0, 43)
logoGlow.Position = UDim2.new(0, 8, 0.5, -21)
logoGlow.BackgroundColor3 = Theme.Accent
logoGlow.BackgroundTransparency = 0.8
logoGlow.BorderSizePixel = 0
logoGlow.Parent = header
corner(logoGlow, 13)

local logo = Instance.new("Frame")
logo.Size = UDim2.new(0, 39, 0, 39)
logo.Position = UDim2.new(0, 10, 0.5, -19)
logo.BackgroundColor3 = Theme.AccentDark
logo.BorderSizePixel = 0
logo.Parent = header
corner(logo, 12)
stroke(logo, Theme.Accent, 1, 0.32)
local logoGrad = Instance.new("UIGradient")
logoGrad.Color = ColorSequence.new(Theme.Accent, Theme.AccentDark)
logoGrad.Rotation = 45
logoGrad.Parent = logo

local logoBolt = Instance.new("TextLabel")
logoBolt.Size = UDim2.new(1, 0, 1, 0)
logoBolt.BackgroundTransparency = 1
logoBolt.Text = "E"
logoBolt.TextSize = 21
logoBolt.TextColor3 = Theme.Text
logoBolt.Font = Enum.Font.GothamBlack
logoBolt.Parent = logo

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -140, 0, 24)
title.Position = UDim2.new(0, 64, 0, 7)
title.BackgroundTransparency = 1
title.Text = "EJEJHUESOS HUB"
title.TextColor3 = Theme.Text
title.TextSize = 16
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -150, 0, 18)
subtitle.Position = UDim2.new(0, 65, 0, 31)
subtitle.BackgroundTransparency = 1
subtitle.Text = "FARM  •  ESP  •  FLY"
subtitle.TextColor3 = Theme.Lavender
subtitle.TextSize = 9
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 31, 0, 31)
minBtn.Position = UDim2.new(1, -41, 0.5, -15)
minBtn.BackgroundColor3 = Theme.Item
minBtn.Text = "—"
minBtn.TextColor3 = Theme.SubText
minBtn.TextSize = 16
minBtn.Font = Enum.Font.GothamBold
minBtn.AutoButtonColor = false
minBtn.Parent = header
corner(minBtn, 9)
stroke(minBtn, Theme.VioletSoft, 1, 0.65)
minBtn.MouseEnter:Connect(function() tween(minBtn, { BackgroundColor3 = Theme.AccentDark, TextColor3 = Theme.Text }, 0.14) end)
minBtn.MouseLeave:Connect(function() tween(minBtn, { BackgroundColor3 = Theme.Item, TextColor3 = Theme.SubText }, 0.14) end)

-- сайдбар
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 130, 1, -84)
sidebar.Position = UDim2.new(0, 10, 0, 74)
sidebar.BackgroundColor3 = Theme.Panel
sidebar.BackgroundTransparency = 0.15
sidebar.BorderSizePixel = 0
sidebar.Parent = main
corner(sidebar, 12)
stroke(sidebar, Theme.Stroke, 1, 0.2)

local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 5)
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
contentHolder.BackgroundTransparency = 0.15
contentHolder.BorderSizePixel = 0
contentHolder.Parent = main
corner(contentHolder, 12)
stroke(contentHolder, Theme.Stroke, 1, 0.2)

-- вкладки
local tabs = {}

local function selectTab(name)
	for n, t in pairs(tabs) do
		local active = n == name
		t.active = active
		t.page.Visible = active
		tween(t.btn, {
			BackgroundTransparency = active and 0 or 1,
			BackgroundColor3 = active and Theme.AccentDark or Theme.Item,
		}, 0.16)
		tween(t.label, { TextColor3 = active and Theme.Text or Theme.SubText }, 0.16)
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
	bar.BackgroundColor3 = Theme.Lavender
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
	label.TextSize = 13
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
	btn.MouseEnter:Connect(function()
		if not tabs[name].active then tween(btn, { BackgroundTransparency = 0.6, BackgroundColor3 = Theme.Item }, 0.14) end
	end)
	btn.MouseLeave:Connect(function()
		if not tabs[name].active then tween(btn, { BackgroundTransparency = 1 }, 0.14) end
	end)
	return page
end

-- элементы
local function addSection(page, text, order)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 18)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Theme.Lavender
	l.TextSize = 11
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
	lbl.Font = Enum.Font.GothamMedium
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

	row.MouseEnter:Connect(function() tween(rowStroke, { Transparency = 0.1, Color = Theme.Accent }) end)
	row.MouseLeave:Connect(function() tween(rowStroke, { Transparency = 0.5, Color = Theme.Stroke }) end)
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
	lbl.Font = Enum.Font.GothamMedium
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
	lbl.Font = Enum.Font.GothamMedium
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
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	row.MouseEnter:Connect(function() tween(rowStroke, { Transparency = 0.1, Color = Theme.Accent }) end)
	row.MouseLeave:Connect(function() tween(rowStroke, { Transparency = 0.5, Color = Theme.Stroke }) end)
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
addToggle(pageMain, "🏃", "Chase Running Door", Config.ChaseDoors, 1.5, function(v) Config.ChaseDoors = v end)
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
addSection(pageMain, "COMBAT", 7)
addToggle(pageMain, "🛡", "Auto Block", Config.AutoBlock, 8, function(v)
	Config.AutoBlock = v
	if not v then stopBlock() end
end)
addSlider(pageMain, "Block Trigger Distance (studs)", 5, 60, 1, Config.BlockDistance, 10, function(v) Config.BlockDistance = v end)

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
addSlider(pageMisc, "Collect Time (сек у двери)", 0, 5, 0.5, Config.CollectTime, 4, function(v) Config.CollectTime = v end)
local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -4, 0, 56)
hint.BackgroundColor3 = Theme.Item
hint.TextColor3 = Theme.SubText
hint.TextSize = 13
hint.Font = Enum.Font.Gotham
hint.LayoutOrder = 5
hint.Parent = pageMisc
corner(hint, 9)
updateHint = function()
	hint.Text = "RightShift — меню\n" .. Config.FlyKey.Name .. " — полёт   Space / Ctrl — вверх / вниз"
end
updateHint()

farmStatusLabel = Instance.new("TextLabel")
farmStatusLabel.Size = UDim2.new(1, -4, 0, 44)
farmStatusLabel.BackgroundColor3 = Theme.Item
farmStatusLabel.TextColor3 = Theme.SubText
farmStatusLabel.TextSize = 12
farmStatusLabel.Font = Enum.Font.GothamMedium
farmStatusLabel.LayoutOrder = 20
farmStatusLabel.Text = ""
farmStatusLabel.Parent = pageMain
corner(farmStatusLabel, 9)
setFarmStatus()

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
ball.BackgroundTransparency = 1
ball.Text = ""
ball.AutoButtonColor = false
ball.Visible = false
ball.Parent = gui

-- вид как у логотипа в шапке меню: скруглённый квадрат с градиентом, обводкой и буквой E
local ballFace = Instance.new("Frame")
ballFace.Size = UDim2.new(1, 0, 1, 0)
ballFace.BackgroundColor3 = Theme.AccentDark
ballFace.BorderSizePixel = 0
ballFace.Active = false
ballFace.Parent = ball
corner(ballFace, 14)
local ballStroke = stroke(ballFace, Theme.Accent, 1, 0.32)
local ballGrad = Instance.new("UIGradient")
ballGrad.Color = ColorSequence.new(Theme.Accent, Theme.AccentDark)
ballGrad.Rotation = 45
ballGrad.Parent = ballFace
local ballLetter = Instance.new("TextLabel")
ballLetter.Size = UDim2.new(1, 0, 1, 0)
ballLetter.BackgroundTransparency = 1
ballLetter.Text = "E"
ballLetter.TextSize = 24
ballLetter.TextColor3 = Theme.Text
ballLetter.Font = Enum.Font.GothamBlack
ballLetter.Parent = ballFace
ball.MouseEnter:Connect(function()
	tween(ballFace, { Size = UDim2.new(1, 4, 1, 4), Position = UDim2.new(0, -2, 0, -2) }, 0.14)
	if ballStroke then tween(ballStroke, { Transparency = 0 }, 0.14) end
end)
ball.MouseLeave:Connect(function()
	tween(ballFace, { Size = UDim2.new(1, 0, 1, 0), Position = UDim2.new(0, 0, 0, 0) }, 0.14)
	if ballStroke then tween(ballStroke, { Transparency = 0.32 }, 0.14) end
end)

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
		glow.BackgroundTransparency = 1
		TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		tween(glow, { BackgroundTransparency = 0.93 }, 0.4)
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

-- ---------- декор: искры и пульсация (только визуал) ----------
local function spawnSparkle(index)
	local sparkle = Instance.new("TextLabel")
	sparkle.Name = "Sparkle_" .. index
	sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
	sparkle.Position = UDim2.fromScale(math.random(5, 95) / 100, math.random(5, 95) / 100)
	sparkle.Size = UDim2.fromOffset(12, 12)
	sparkle.BackgroundTransparency = 1
	sparkle.Text = index % 3 == 0 and "✧" or "✦"
	sparkle.TextColor3 = Theme.Lavender
	sparkle.TextTransparency = 0.2
	sparkle.Font = Enum.Font.GothamBold
	sparkle.TextSize = math.random(8, 13)
	sparkle.ZIndex = 0
	sparkle.Parent = main

	task.spawn(function()
		local startPos = sparkle.Position
		local function sine(t) return TweenInfo.new(t, Enum.EasingStyle.Sine) end
		while gui.Parent and sparkle.Parent do
			if main.Visible then
				sparkle.Rotation = math.random(-20, 20)
				local t1 = math.random(7, 12) / 10
				TweenService:Create(sparkle, sine(t1), {
					TextTransparency = 0.78,
					Position = startPos + UDim2.fromOffset(math.random(-5, 5), math.random(-8, 8)),
				}):Play()
				task.wait(t1)
				local t2 = math.random(7, 12) / 10
				TweenService:Create(sparkle, sine(t2), { TextTransparency = 0.18, Position = startPos }):Play()
				task.wait(t2 + math.random(5, 10) / 10)
			else
				task.wait(0.5)
			end
		end
	end)
end
for i = 1, 9 do spawnSparkle(i) end

local function breathe(obj, prop, a, b, t, startDelay)
	task.spawn(function()
		task.wait(startDelay or 0)
		local info = TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local toB = true
		while gui.Parent do
			if main.Visible then
				TweenService:Create(obj, info, { [prop] = toB and b or a }):Play()
				toB = not toB
			end
			task.wait(t)
		end
	end)
end
breathe(glow, "BackgroundTransparency", 0.94, 0.89, 1.8, 0.8)
breathe(edge, "BackgroundTransparency", 0.7, 0.15, 1.1, 0)

-- входная анимация
scale.Scale = 0.9
glow.BackgroundTransparency = 1
shadow.BackgroundTransparency = 1
TweenService:Create(scale, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
tween(glow, { BackgroundTransparency = 0.93 }, 0.65)
tween(shadow, { BackgroundTransparency = 0.48 }, 0.55)

print("[EjejHuesos Hub] loaded")
