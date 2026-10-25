--[[
    ========================================================================
    INSPECTOR PRO: 12-13 ZONAS, CLASH ARENA, ROTACIONES & MARCADOR DE PISO
    ========================================================================
    Diseñado para pruebas y desarrollo en Roblox Luau / Delta.
    
    Novedades de esta versión:
    1. Búsqueda profunda de la última zona rotativa:
       - CLASH ARENA (Clash Egg)
       - HERO'S BASE (Hero Egg)
       - VILLAIN'S HIDEOUT (Evil Egg)
    2. Detección de todas las 12 a 13 zonas del mapa (revisando Workspace y
       ReplicatedStorage.Modules.ZoneConfigurations).
    3. Arreglo definitivo de coordenadas en vivo:
       - Bucle indestructible en task.spawn con pcall.
       - Cálculo de altura exacta del piso (Raycast hacia abajo).
    4. Guardado de posición con confirmación visual clara:
       - Cartel inmediato con las coordenadas y el nivel del piso guardados.
       - Copiado automático al portapapeles (setclipboard).
       - Historial completo en pantalla y en 'coordenadas_guardadas.txt'.
    ========================================================================
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local canWrite = (type(writefile) == "function")
local canCopy = (type(setclipboard) == "function")

-- Estado Global
local State = {
    running = true,
    savedPoints = {},
    allZones = {},
    rotatingLastZone = {
        name = "Buscando...",
        egg = "Buscando...",
        coords = nil,
        distance = 0,
        status = "Analizando mapa..."
    },
    godlyEgg = { found = false, info = "Buscando..." },
    halloween = { fires = 0, pumpkins = 0 },
    lastSavedFeedback = "Ninguna posición guardada aún."
}

-- ========================================================================
-- FUNCIONES DE POSICIÓN Y PISO (PROTEGIDAS CON PCALL)
-- ========================================================================
local function getPlayerPos()
    local ok, pos = pcall(function()
        local char = LocalPlayer.Character
        if not char then return Vector3.zero end
        local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
        return root and root.Position or Vector3.zero
    end)
    return ok and pos or Vector3.zero
end

local function getFloorY(pos)
    local ok, resY, resPart = pcall(function()
        local char = LocalPlayer.Character
        if not char then return pos.Y - 3, "Sin Personaje" end

        local rayOrigin = pos + Vector3.new(0, 2.5, 0)
        local rayDir = Vector3.new(0, -80, 0)

        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {char}
        params.FilterType = RaycastFilterType.Exclude

        local hit = Workspace:Raycast(rayOrigin, rayDir, params)
        if hit then
            return hit.Position.Y, (hit.Instance and hit.Instance.Name or "Piso")
        end
        return pos.Y - 3, "Aprox (Sin impacto)"
    end)

    if ok then
        return resY, resPart
    end
    return pos.Y - 3, "Error Raycast"
end

local function formatVec(v)
    if not v then return "N/A" end
    return string.format("X: %.1f, Y: %.1f, Z: %.1f", v.X, v.Y, v.Z)
end

-- ========================================================================
-- EXPLORACIÓN DE LAS 12-13 ZONAS Y MÓDULOS DE CONFIGURACIÓN
-- ========================================================================
local function inspectConfigurations()
    local zoneConfig = nil
    local eggConfig = nil

    pcall(function()
        local modules = ReplicatedStorage:FindFirstChild("Modules")
        if modules then
            local zm = modules:FindFirstChild("ZoneConfigurations")
            if zm and zm:IsA("ModuleScript") then
                zoneConfig = require(zm)
            end
            local em = modules:FindFirstChild("EggConfigurations")
            if em and em:IsA("ModuleScript") then
                eggConfig = require(em)
            end
        end
    end)

    return zoneConfig, eggConfig
end

-- ========================================================================
-- DETECTAR LA ÚLTIMA ZONA ROTATIVA (CLASH ARENA, HERO'S BASE, VILLAIN)
-- ========================================================================
local function detectRotatingLastZone()
    local playerPos = getPlayerPos()
    local zoneCfg, eggCfg = inspectConfigurations()

    local detected = {
        name = "No identificada",
        egg = "No detectado",
        coords = nil,
        distance = 0,
        status = "Buscando en Workspace..."
    }

    -- 1. Búsqueda directa por palabras clave en Workspace (Clash Arena, Hero, Villain)
    local clashObj = nil
    local heroObj = nil
    local villainObj = nil

    for _, desc in ipairs(Workspace:GetDescendants()) do
        local l = desc.Name:lower()
        if not desc:IsDescendantOf(LocalPlayer.Character) then
            if l:match("clash") or l:match("arena") then
                if desc:IsA("Folder") or desc:IsA("Model") then
                    clashObj = desc
                end
            elseif l:match("hero") and not l:match("shinra") then
                if desc:IsA("Folder") or desc:IsA("Model") then
                    heroObj = desc
                end
            elseif l:match("villain") or l:match("evil") or l:match("hideout") then
                if desc:IsA("Folder") or desc:IsA("Model") then
                    villainObj = desc
                end
            end
        end
    end

    -- Determinar cuál está activa
    local targetZoneInst = nil
    if clashObj then
        detected.name = clashObj.Name
        detected.egg = "Clash Egg"
        detected.status = "🔥 ¡CLASH ARENA ACTIVA!"
        targetZoneInst = clashObj
    elseif heroObj then
        detected.name = heroObj.Name
        detected.egg = "Hero Egg"
        detected.status = "🦸 ¡HERO'S BASE ACTIVA!"
        targetZoneInst = heroObj
    elseif villainObj then
        detected.name = villainObj.Name
        detected.egg = "Evil Egg"
        detected.status = "🦹 ¡VILLAIN'S HIDEOUT ACTIVA!"
        targetZoneInst = villainObj
    else
        -- Revisar si en Workspace.Eggs hay alguna carpeta con número alto (ej. Zone12, Zone13)
        local eggsRoot = Workspace:FindFirstChild("Eggs")
        if eggsRoot then
            local highestZone = nil
            local highestNum = 0
            for _, child in ipairs(eggsRoot:GetChildren()) do
                local num = tonumber(child.Name:match("%d+"))
                if num and num > highestNum then
                    highestNum = num
                    highestZone = child
                end
            end
            if highestZone and highestNum >= 7 then
                detected.name = highestZone.Name
                detected.egg = "Huevo de " .. highestZone.Name
                detected.status = string.format("Detectada Zona #%d en Workspace.Eggs", highestNum)
                targetZoneInst = highestZone
            end
        end
    end

    -- Buscar huevo físico dentro de la zona detectada
    if targetZoneInst then
        local foundEggPart = nil
        for _, d in ipairs(targetZoneInst:GetDescendants()) do
            local dl = d.Name:lower()
            if dl:match("egg") or (d:IsA("Model") and d.Name == "SpawnedEgg") then
                local p = (d:IsA("BasePart") and d) or (d:IsA("Model") and (d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")))
                if p then
                    foundEggPart = p
                    local attr = d:GetAttribute("EggType") or d:GetAttribute("Type")
                    if attr then
                        detected.egg = tostring(attr)
                    end
                    break
                end
            end
        end

        if not foundEggPart then
            foundEggPart = targetZoneInst:FindFirstChildWhichIsA("BasePart", true)
        end

        if foundEggPart then
            detected.coords = foundEggPart.Position
            detected.distance = math.floor((playerPos - foundEggPart.Position).Magnitude)
        end
    end

    State.rotatingLastZone = detected
    return detected
end

-- ========================================================================
-- ESCANEAR TODAS LAS 12-13 ZONAS Y HUEVOS
-- ========================================================================
local function scanAllZonesAndEggs()
    local playerPos = getPlayerPos()
    local zonesList = {}
    local godlyFound = nil

    local eggsRoot = Workspace:FindFirstChild("Eggs")
    if eggsRoot then
        for _, zFolder in ipairs(eggsRoot:GetChildren()) do
            local zName = zFolder.Name
            local eggNames = {}
            local repPart = nil

            for _, desc in ipairs(zFolder:GetDescendants()) do
                local dl = desc.Name:lower()
                if dl:match("egg") or desc.Name == "SpawnedEgg" then
                    local p = (desc:IsA("BasePart") and desc) or (desc:IsA("Model") and (desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")))
                    if p and not repPart then
                        repPart = p
                    end

                    local detectedEgg = desc.Name
                    local attr = desc:GetAttribute("EggType") or desc:GetAttribute("Type")
                    if attr then detectedEgg = tostring(attr) end

                    if not table.find(eggNames, detectedEgg) and detectedEgg ~= "EggSpawn" and detectedEgg ~= "EggNest" and not detectedEgg:match("Mesh") then
                        table.insert(eggNames, detectedEgg)
                    end

                    if dl:match("godly") or (attr and tostring(attr):lower():match("godly")) then
                        godlyFound = { name = detectedEgg, zone = zName, pos = p and p.Position, dist = p and math.floor((playerPos - p.Position).Magnitude) }
                    end
                end
            end

            table.insert(zonesList, {
                name = zName,
                eggs = (#eggNames > 0 and table.concat(eggNames, ", ") or "SpawnedEgg"),
                coords = repPart and repPart.Position or nil,
                distance = repPart and math.floor((playerPos - repPart.Position).Magnitude) or 9999
            })
        end
    end

    table.sort(zonesList, function(a, b) return a.distance < b.distance end)
    State.allZones = zonesList

    if godlyFound then
        State.godlyEgg = { found = true, info = string.format("¡En %s! a %d studs", godlyFound.zone, godlyFound.dist) }
    else
        State.godlyEgg = { found = false, info = "No spawneado actualmente" }
    end

    -- Conteo rápido de Halloween
    local fires = 0
    local pumpkins = 0
    for _, d in ipairs(Workspace:GetDescendants()) do
        if not d:IsDescendantOf(LocalPlayer.Character) then
            local l = d.Name:lower()
            if l:match("fire") or l:match("fuego") then
                if d:IsA("BasePart") or (d:IsA("Model") and d.PrimaryPart) then fires = fires + 1 end
            elseif l:match("pumpkin") or l:match("calabaza") then
                if d:IsA("BasePart") or (d:IsA("Model") and d.PrimaryPart) then pumpkins = pumpkins + 1 end
            end
        end
    end
    State.halloween.fires = fires
    State.halloween.pumpkins = pumpkins

    return zonesList
end

-- ========================================================================
-- GUARDADO SEGURO DE COORDENADAS
-- ========================================================================
local function saveCurrentPosition()
    local pPos = getPlayerPos()
    local floorY, floorPart = getFloorY(pPos)

    local pointId = #State.savedPoints + 1
    local zoneTag = State.rotatingLastZone.name
    local note = string.format("Punto #%d [%s]", pointId, zoneTag)

    local item = {
        id = pointId,
        note = note,
        x = pPos.X,
        y = pPos.Y,
        z = pPos.Z,
        floorY = floorY,
        floorPart = floorPart,
        time = os.date("%H:%M:%S")
    }

    table.insert(State.savedPoints, item)

    -- Feedback visible
    local feedbackStr = string.format("✅ #%d Guardado: X:%.1f, Y:%.1f, Z:%.1f | Piso Y:%.2f (%s)",
        item.id, item.x, item.y, item.z, item.floorY, item.floorPart)
    State.lastSavedFeedback = feedbackStr

    -- Copiar al portapapeles para pegar rápido en Luau/Bloc de notas
    if canCopy then
        pcall(function()
            local copyText = string.format("Vector3.new(%.2f, %.2f, %.2f) -- Piso Y: %.2f (%s)",
                item.x, item.y, item.z, item.floorY, item.note)
            setclipboard(copyText)
        end)
    end

    -- Guardar archivo en disco
    if canWrite then
        pcall(function()
            local lines = {
                "==================================================",
                "COORDENADAS GUARDADAS DEL JUEGO",
                "Fecha: " .. os.date("!%Y-%m-%d %H:%M:%S UTC"),
                "=================================================="
            }
            for _, pt in ipairs(State.savedPoints) do
                table.insert(lines, string.format(
                    "[%02d] %-25s | Pos: (%.2f, %.2f, %.2f) | Piso Y: %.2f | Objeto: %s | Hora: %s",
                    pt.id, pt.note, pt.x, pt.y, pt.z, pt.floorY, pt.floorPart, pt.time
                ))
            end
            writefile("coordenadas_guardadas.txt", table.concat(lines, "\n"))
        end)
    end

    return item, feedbackStr
end

-- ========================================================================
-- CONSTRUCCIÓN DE LA INTERFAZ GRÁFICA
-- ========================================================================
local function buildGUI()
    local parentGui = (gethui and gethui()) or CoreGui or LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not parentGui then return end

    local old = parentGui:FindFirstChild("DevZonesProUI")
    if old then old:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "DevZonesProUI"
    sg.ResetOnSpawn = false

    local main = Instance.new("Frame")
    main.Name = "MainFrame"
    main.Size = UDim2.new(0, 380, 0, 560)
    main.Position = UDim2.new(0.02, 0, 0.08, 0)
    main.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
    main.BorderSizePixel = 2
    main.BorderColor3 = Color3.fromRGB(0, 220, 255)
    main.Active = true
    main.Draggable = true
    main.Parent = sg

    -- Barra superior
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 34)
    header.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
    header.BorderSizePixel = 0
    header.Parent = main

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -70, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(0, 230, 255)
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 15
    title.Text = "🛠️ Inspector Pro: Zonas & Coordenadas"
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 28, 0, 26)
    closeBtn.Position = UDim2.new(1, -32, 0, 4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(210, 40, 40)
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.SourceSansBold
    closeBtn.TextSize = 14
    closeBtn.Text = "X"
    closeBtn.Parent = header
    closeBtn.MouseButton1Click:Connect(function()
        State.running = false
        sg:Destroy()
    end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -12, 1, -42)
    scroll.Position = UDim2.new(0, 6, 0, 38)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 5
    scroll.CanvasSize = UDim2.new(0, 0, 0, 840)
    scroll.Parent = main

    local curY = 5

    -- [1] SECCIÓN: ÚLTIMA ZONA ROTATIVA (CLASH ARENA, HERO'S, VILLAIN'S)
    local s1Box = Instance.new("Frame")
    s1Box.Size = UDim2.new(1, 0, 0, 115)
    s1Box.Position = UDim2.new(0, 0, 0, curY)
    s1Box.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
    s1Box.BorderSizePixel = 1
    s1Box.BorderColor3 = Color3.fromRGB(255, 180, 0)
    s1Box.Parent = scroll

    local s1Title = Instance.new("TextLabel")
    s1Title.Size = UDim2.new(1, -10, 0, 22)
    s1Title.Position = UDim2.new(0, 6, 0, 2)
    s1Title.BackgroundTransparency = 1
    s1Title.TextColor3 = Color3.fromRGB(255, 210, 40)
    s1Title.Font = Enum.Font.SourceSansBold
    s1Title.TextSize = 13
    s1Title.Text = "🏆 ÚLTIMA ZONA ROTATIVA ACTIVA"
    s1Title.TextXAlignment = Enum.TextXAlignment.Left
    s1Title.Parent = s1Box

    local s1Text = Instance.new("TextLabel")
    s1Text.Size = UDim2.new(1, -12, 0, 85)
    s1Text.Position = UDim2.new(0, 6, 0, 24)
    s1Text.BackgroundTransparency = 1
    s1Text.TextColor3 = Color3.fromRGB(240, 240, 240)
    s1Text.Font = Enum.Font.SourceSans
    s1Text.TextSize = 13
    s1Text.TextXAlignment = Enum.TextXAlignment.Left
    s1Text.TextYAlignment = Enum.TextYAlignment.Top
    s1Text.Text = "Buscando rotación..."
    s1Text.Parent = s1Box

    curY = curY + 122

    -- [2] SECCIÓN: POSICIÓN EN VIVO Y NIVEL DEL PISO
    local s2Box = Instance.new("Frame")
    s2Box.Size = UDim2.new(1, 0, 0, 95)
    s2Box.Position = UDim2.new(0, 0, 0, curY)
    s2Box.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
    s2Box.BorderSizePixel = 1
    s2Box.BorderColor3 = Color3.fromRGB(0, 220, 255)
    s2Box.Parent = scroll

    local s2Title = Instance.new("TextLabel")
    s2Title.Size = UDim2.new(1, -10, 0, 22)
    s2Title.Position = UDim2.new(0, 6, 0, 2)
    s2Title.BackgroundTransparency = 1
    s2Title.TextColor3 = Color3.fromRGB(0, 230, 255)
    s2Title.Font = Enum.Font.SourceSansBold
    s2Title.TextSize = 13
    s2Title.Text = "📍 TU POSICIÓN Y NIVEL DEL SUELO (EN VIVO)"
    s2Title.TextXAlignment = Enum.TextXAlignment.Left
    s2Title.Parent = s2Box

    local s2Text = Instance.new("TextLabel")
    s2Text.Size = UDim2.new(1, -12, 0, 68)
    s2Text.Position = UDim2.new(0, 6, 0, 24)
    s2Text.BackgroundTransparency = 1
    s2Text.TextColor3 = Color3.fromRGB(220, 255, 240)
    s2Text.Font = Enum.Font.SourceSans
    s2Text.TextSize = 13
    s2Text.TextXAlignment = Enum.TextXAlignment.Left
    s2Text.TextYAlignment = Enum.TextYAlignment.Top
    s2Text.Text = "Iniciando lector de coordenadas..."
    s2Text.Parent = s2Box

    curY = curY + 102

    -- [3] BOTÓN: GUARDAR COORDENADA ACTUAL
    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(1, 0, 0, 38)
    saveBtn.Position = UDim2.new(0, 0, 0, curY)
    saveBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 120)
    saveBtn.BorderSizePixel = 0
    saveBtn.TextColor3 = Color3.new(1, 1, 1)
    saveBtn.Font = Enum.Font.SourceSansBold
    saveBtn.TextSize = 14
    saveBtn.Text = "📌 GUARDAR MI POSICIÓN Y PISO AQUÍ"
    saveBtn.Parent = scroll

    curY = curY + 44

    -- [3.1] CARTEL VISUAL DE CONFIRMACIÓN DE GUARDADO
    local feedbackLabel = Instance.new("TextLabel")
    feedbackLabel.Size = UDim2.new(1, 0, 0, 36)
    feedbackLabel.Position = UDim2.new(0, 0, 0, curY)
    feedbackLabel.BackgroundColor3 = Color3.fromRGB(20, 35, 30)
    feedbackLabel.BorderSizePixel = 1
    feedbackLabel.BorderColor3 = Color3.fromRGB(0, 255, 170)
    feedbackLabel.TextColor3 = Color3.fromRGB(150, 255, 200)
    feedbackLabel.Font = Enum.Font.SourceSansBold
    feedbackLabel.TextSize = 12
    feedbackLabel.Text = State.lastSavedFeedback
    feedbackLabel.Parent = scroll

    curY = curY + 42

    -- [4] SECCIÓN: ESTADO DE GODLY EGG Y EVENTOS
    local s3Box = Instance.new("Frame")
    s3Box.Size = UDim2.new(1, 0, 0, 75)
    s3Box.Position = UDim2.new(0, 0, 0, curY)
    s3Box.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
    s3Box.BorderSizePixel = 1
    s3Box.BorderColor3 = Color3.fromRGB(170, 100, 255)
    s3Box.Parent = scroll

    local s3Title = Instance.new("TextLabel")
    s3Title.Size = UDim2.new(1, -10, 0, 22)
    s3Title.Position = UDim2.new(0, 6, 0, 2)
    s3Title.BackgroundTransparency = 1
    s3Title.TextColor3 = Color3.fromRGB(220, 140, 255)
    s3Title.Font = Enum.Font.SourceSansBold
    s3Title.TextSize = 13
    s3Title.Text = "⭐ GODLY EGG & EVENTO HALLOWEEN"
    s3Title.TextXAlignment = Enum.TextXAlignment.Left
    s3Title.Parent = s3Box

    local s3Text = Instance.new("TextLabel")
    s3Text.Size = UDim2.new(1, -12, 0, 48)
    s3Text.Position = UDim2.new(0, 6, 0, 24)
    s3Text.BackgroundTransparency = 1
    s3Text.TextColor3 = Color3.fromRGB(230, 230, 230)
    s3Text.Font = Enum.Font.SourceSans
    s3Text.TextSize = 13
    s3Text.TextXAlignment = Enum.TextXAlignment.Left
    s3Text.TextYAlignment = Enum.TextYAlignment.Top
    s3Text.Text = "Escaneando eventos..."
    s3Text.Parent = s3Box

    curY = curY + 82

    -- [5] BOTÓN: RE-ESCANEAR TODO
    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(1, 0, 0, 32)
    refreshBtn.Position = UDim2.new(0, 0, 0, curY)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(50, 65, 95)
    refreshBtn.BorderSizePixel = 0
    refreshBtn.TextColor3 = Color3.fromRGB(210, 235, 255)
    refreshBtn.Font = Enum.Font.SourceSansBold
    refreshBtn.TextSize = 13
    refreshBtn.Text = "🔄 RE-ESCANEAR ZONAS Y MAPA"
    refreshBtn.Parent = scroll

    curY = curY + 38

    -- [6] HISTORIAL COMPLETO DE COORDENADAS GUARDADAS
    local histLabel = Instance.new("TextLabel")
    histLabel.Size = UDim2.new(1, 0, 0, 22)
    histLabel.Position = UDim2.new(0, 0, 0, curY)
    histLabel.BackgroundTransparency = 1
    histLabel.TextColor3 = Color3.fromRGB(180, 200, 230)
    histLabel.Font = Enum.Font.SourceSansBold
    histLabel.TextSize = 13
    histLabel.Text = "📋 Coordenadas Guardadas en esta Sesión:"
    histLabel.TextXAlignment = Enum.TextXAlignment.Left
    histLabel.Parent = scroll

    curY = curY + 24

    local histBox = Instance.new("TextLabel")
    histBox.Size = UDim2.new(1, 0, 0, 280)
    histBox.Position = UDim2.new(0, 0, 0, curY)
    histBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
    histBox.BorderSizePixel = 1
    histBox.BorderColor3 = Color3.fromRGB(35, 42, 55)
    histBox.TextColor3 = Color3.fromRGB(130, 255, 180)
    histBox.Font = Enum.Font.Code
    histBox.TextSize = 11
    histBox.TextXAlignment = Enum.TextXAlignment.Left
    histBox.TextYAlignment = Enum.TextYAlignment.Top
    histBox.Text = "  (Presiona 'GUARDAR' para marcar tu posición actual)"
    histBox.Parent = scroll

    local function updateHistoryView()
        if #State.savedPoints == 0 then
            histBox.Text = "  (Aún no has guardado coordenadas)"
            return
        end
        local listTxt = ""
        for i = #State.savedPoints, 1, -1 do
            local p = State.savedPoints[i]
            listTxt = listTxt .. string.format("[%02d] %s\n  Pos: (X:%.1f, Y:%.1f, Z:%.1f)\n  Piso Y: %.2f | Objeto: %s | Hora: %s\n------------------------------------\n",
                p.id, p.note, p.x, p.y, p.z, p.floorY, p.floorPart, p.time)
        end
        histBox.Text = listTxt
    end

    local function performScan()
        detectRotatingLastZone()
        scanAllZonesAndEggs()

        local z = State.rotatingLastZone
        local coordsStr = z.coords and formatVec(z.coords) or "No fijadas"
        s1Text.Text = string.format(
            "• Estado: %s\n" ..
            "• Zona Detectada: %s\n" ..
            "• Huevo(s): %s\n" ..
            "• Coordenadas: %s (%d studs)",
            z.status, z.name, z.egg, coordsStr, z.distance
        )

        s3Text.Text = string.format("• GodlyEgg: %s\n• Fuegos Activos: %d | Calabazas: %d\n• Zonas visibles en Workspace: %d",
            State.godlyEgg.info, State.halloween.fires, State.halloween.pumpkins, #State.allZones)
    end

    -- Evento Guardar con confirmación clara
    saveBtn.MouseButton1Click:Connect(function()
        local item, fb = saveCurrentPosition()
        feedbackLabel.Text = fb
        feedbackLabel.TextColor3 = Color3.fromRGB(0, 255, 200)
        updateHistoryView()

        saveBtn.Text = string.format("✓ ¡PUNTO #%d GUARDADO Y COPIADO!", item.id)
        saveBtn.BackgroundColor3 = Color3.fromRGB(0, 210, 140)
        task.delay(1.8, function()
            if saveBtn and saveBtn.Parent then
                saveBtn.Text = "📌 GUARDAR MI POSICIÓN Y PISO AQUÍ"
                saveBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 120)
            end
        end)
    end)

    refreshBtn.MouseButton1Click:Connect(function()
        performScan()
    end)

    -- BUCLE EN TIEMPO REAL ULTRA RESISTENTE (task.spawn + pcall)
    task.spawn(function()
        while State.running and main and main.Parent do
            pcall(function()
                local pos = getPlayerPos()
                local floorY, floorPart = getFloorY(pos)

                s2Text.Text = string.format(
                    "• Posición: X: %.2f, Y: %.2f, Z: %.2f\n" ..
                    "• Nivel del Piso (Y): %.2f\n" ..
                    "• Objeto Debajo: %s\n" ..
                    "• Distancia a Última Zona: %d studs",
                    pos.X, pos.Y, pos.Z,
                    floorY,
                    floorPart,
                    State.rotatingLastZone.distance or 0
                )
            end)
            task.wait(0.2)
        end
    end)

    performScan()
    sg.Parent = parentGui
    print("✅ Panel Inspector Pro iniciado con soporte para Clash Arena y guardado visual.")
end

buildGUI()
