--[[
    ========================================================================
    PANEL DE DESARROLLO: DETECCIÓN DE LA ÚLTIMA ZONA ROTATIVA & HUEVOS
    ========================================================================
    Diseñado para pruebas locales en Roblox Luau / Delta.
    
    Lógica de Zonas:
    - Zonas tempranas: Green Plains, Zakura/Sakura, Lush Forest, etc.
    - Zona intermedia/avanzada: Great Sun Zone (Sun Egg).
    - ÚLTIMA ZONA ROTATIVA (Post-Great Sun):
      Alterna según tu configuración entre:
        * "Hero's Base" (contiene Hero Egg)
        * "Villain's Hideout" (contiene Evil Egg)
        * U otra zona endgame que se cargue después de Great Sun.
    
    Este script:
    1. Filtra y descarta Great Sun como última zona, buscando la que viene DESPUÉS.
    2. Identifica cuál de las zonas rotativas está activa en Workspace.Eggs.
    3. Extrae exactamente qué huevos y spawns están físicamente en esa última zona.
    4. Mide coordenadas y nivel del suelo (Piso Y con Raycast).
    5. Botón para guardar coordenadas y crear balizas 3D neón en el mundo.
    ========================================================================
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local canWrite = (type(writefile) == "function")

local State = {
    savedPoints = {},
    lastScannedEggs = {},
    finalZone = {
        name = "Detectando...",
        rotationType = "N/A",
        eggs = {},
        eggSummary = "Buscando...",
        coords = nil,
        distance = 0
    },
    godlyStatus = "Buscando...",
    halloweenStatus = { fires = 0, pumpkins = 0 },
    markersFolder = nil
}

-- Carpeta para balizas 3D en Workspace
local function getMarkersFolder()
    if not State.markersFolder or not State.markersFolder.Parent then
        local folder = Workspace:FindFirstChild("Dev_Marcadores_Piso")
        if not folder then
            folder = Instance.new("Folder")
            folder.Name = "Dev_Marcadores_Piso"
            folder.Parent = Workspace
        end
        State.markersFolder = folder
    end
    return State.markersFolder
end

-- ========================================================================
-- FUNCIONES MATEMÁTICAS / FÍSICAS (POSICIÓN Y NIVEL DEL SUELO)
-- ========================================================================
local function getPlayerPos()
    local char = LocalPlayer.Character
    if not char then return Vector3.zero end
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
    return root and root.Position or Vector3.zero
end

local function getFloorDetails(pos)
    local char = LocalPlayer.Character
    if not char or not pos then return nil, nil end

    local rayOrigin = pos + Vector3.new(0, 1.5, 0)
    local rayDir = Vector3.new(0, -60, 0)

    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char, getMarkersFolder()}
    params.FilterType = RaycastFilterType.Exclude

    local result = Workspace:Raycast(rayOrigin, rayDir, params)
    if result then
        return result.Position, result.Instance
    end
    return nil, nil
end

local function formatVec(v)
    if not v then return "N/A" end
    return string.format("X: %.1f, Y: %.1f, Z: %.1f", v.X, v.Y, v.Z)
end

-- ========================================================================
-- DETECTAR LA VERDADERA ÚLTIMA ZONA (DESPUÉS DE GREAT SUN)
-- ========================================================================
local function detectTrueLastZone()
    local finalInfo = {
        name = "No detectada",
        rotationType = "Sin rotación",
        eggs = {},
        eggSummary = "Ninguno",
        coords = nil,
        distance = 0
    }

    local eggsRoot = Workspace:FindFirstChild("Eggs")
    local playerPos = getPlayerPos()

    -- 1. Buscar en Workspace.Eggs todas las carpetas de zonas presentes
    local allFoundZones = {}
    if eggsRoot then
        for _, child in ipairs(eggsRoot:GetChildren()) do
            table.insert(allFoundZones, child)
        end
    end

    -- También chequear si hay zonas cargadas en Workspace.Map o Workspace directo
    local mapFolder = Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("Zones") or Workspace
    for _, child in ipairs(mapFolder:GetChildren()) do
        local l = child.Name:lower()
        if (l:match("hero") or l:match("villain") or l:match("evil") or l:match("hideout")) and not table.find(allFoundZones, child) then
            table.insert(allFoundZones, child)
        end
    end

    -- 2. Identificar candidatos a ÚLTIMA ZONA (Rotativas: Hero's Base vs Villain's Hideout)
    local activeLastCandidate = nil
    local rotationDetected = "Desconocida"

    for _, z in ipairs(allFoundZones) do
        local lower = z.Name:lower()
        
        -- Detectar si es Hero's Base
        if lower:match("hero") then
            activeLastCandidate = z
            rotationDetected = "Héroes (Hero's Base)"
            break
        -- Detectar si es Villain's Hideout
        elseif lower:match("villain") or lower:match("evil") or lower:match("hideout") then
            activeLastCandidate = z
            rotationDetected = "Villanos (Villain's Hideout)"
            break
        end
    end

    -- 3. Si no tiene el nombre literal de hero/villain, buscar la zona que venga DESPUÉS de Sun
    if not activeLastCandidate and eggsRoot then
        -- Buscar zonas por número o comprobar cuál está físicamente después de Sun
        local sunPos = nil
        local otherZones = {}

        for _, z in ipairs(eggsRoot:GetChildren()) do
            local l = z.Name:lower()
            local p = (z:IsA("BasePart") and z.Position) or (z:FindFirstChildWhichIsA("BasePart") and z:FindFirstChildWhichIsA("BasePart").Position)
            
            if l:match("sun") then
                sunPos = p
            else
                table.insert(otherZones, { instance = z, name = z.Name, pos = p })
            end
        end

        -- Si encontramos Sun y hay otras zonas, la última suele ser la más lejana al inicio o Zone8/Zone9
        for _, oz in ipairs(otherZones) do
            local l = oz.name:lower()
            -- Ignorar zonas iniciales conocidas
            if not l:match("plain") and not l:match("sakura") and not l:match("zakura") 
               and not l:match("forest") and not l:match("cave") and not l:match("desert") 
               and not l:match("snow") and not l:match("zone1") and not l:match("zone2") 
               and not l:match("zone3") and not l:match("zone4") and not l:match("zone5") then
                activeLastCandidate = oz.instance
                rotationDetected = "Zona Avanzada (" .. oz.name .. ")"
                break
            end
        end
    end

    -- 4. Extraer los huevos que están en la zona final detectada
    if activeLastCandidate then
        finalInfo.name = activeLastCandidate.Name
        finalInfo.rotationType = rotationDetected

        local eggsFound = {}
        local firstPart = nil

        for _, desc in ipairs(activeLastCandidate:GetDescendants()) do
            local l = desc.Name:lower()
            local isEgg = l:match("egg") or (desc:IsA("Model") and desc.Name == "SpawnedEgg")
            
            if isEgg then
                local part = (desc:IsA("BasePart") and desc) or (desc:IsA("Model") and (desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")))
                if part then
                    if not firstPart then firstPart = part end

                    -- Extraer nombre real del huevo
                    local realEggName = desc.Name
                    local attr = desc:GetAttribute("EggType") or desc:GetAttribute("Type") or (desc.Parent and desc.Parent:GetAttribute("EggType"))
                    if attr then
                        realEggName = tostring(attr)
                    else
                        -- Si estamos en Hero's Base o Villain's Hideout, mapear por defecto si es SpawnedEgg
                        if rotationDetected:match("Héroes") then
                            realEggName = "Hero Egg"
                        elseif rotationDetected:match("Villanos") then
                            realEggName = "Evil Egg"
                        end
                    end

                    table.insert(eggsFound, {
                        name = realEggName,
                        position = part.Position,
                        distance = math.floor((playerPos - part.Position).Magnitude)
                    })
                end
            end
        end

        -- Si la zona no tenía modelos cargados aún, deducir según el tipo de rotación
        if #eggsFound == 0 then
            if rotationDetected:match("Héroes") then
                table.insert(eggsFound, { name = "Hero Egg (Esperando Spawn)", position = firstPart and firstPart.Position or Vector3.zero, distance = 0 })
            elseif rotationDetected:match("Villanos") then
                table.insert(eggsFound, { name = "Evil Egg (Esperando Spawn)", position = firstPart and firstPart.Position or Vector3.zero, distance = 0 })
            end
        end

        finalInfo.eggs = eggsFound
        if firstPart then
            finalInfo.coords = firstPart.Position
            finalInfo.distance = math.floor((playerPos - firstPart.Position).Magnitude)
        end

        -- Resumen de nombres de huevos
        local namesList = {}
        for _, eg in ipairs(eggsFound) do
            if not table.find(namesList, eg.name) then
                table.insert(namesList, eg.name)
            end
        end
        finalInfo.eggSummary = table.concat(namesList, " | ")
    else
        finalInfo.name = "No cargada aún en Workspace"
        finalInfo.eggSummary = "Ninguno visible"
    end

    State.finalZone = finalInfo
    return finalInfo
end

-- ========================================================================
-- ESCANEAR HUEVOS GENERALES Y BUSCAR GODLY EGG
-- ========================================================================
local function scanAllEggs()
    local list = {}
    local godlyFound = nil
    local playerPos = getPlayerPos()
    local eggsFolder = Workspace:FindFirstChild("Eggs")

    if eggsFolder then
        for _, zFolder in ipairs(eggsFolder:GetChildren()) do
            local zoneName = zFolder.Name
            for _, desc in ipairs(zFolder:GetDescendants()) do
                if desc:IsA("Model") or (desc:IsA("BasePart") and desc.Name:lower():match("egg")) then
                    local pPart = (desc:IsA("Model") and (desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart"))) or (desc:IsA("BasePart") and desc)
                    if pPart then
                        local eggName = desc.Name
                        local attrType = desc:GetAttribute("EggType") or desc:GetAttribute("Type")
                        if attrType then eggName = tostring(attrType) end

                        local dist = math.floor((playerPos - pPart.Position).Magnitude)
                        local isGodly = (eggName:lower():match("godly") ~= nil) or (desc:GetFullName():lower():match("godly") ~= nil)

                        local entry = {
                            name = eggName,
                            zone = zoneName,
                            pos = pPart.Position,
                            distance = dist,
                            isGodly = isGodly,
                            instance = desc
                        }
                        table.insert(list, entry)

                        if isGodly and (not godlyFound or dist < godlyFound.distance) then
                            godlyFound = entry
                        end
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b) return a.distance < b.distance end)
    State.lastScannedEggs = list

    if godlyFound then
        State.godlyStatus = string.format("En %s (%d studs)", godlyFound.zone, godlyFound.distance)
    else
        State.godlyStatus = "No spawneado actualmente"
    end

    return list, godlyFound
end

-- ========================================================================
-- ESCANEAR EVENTO HALLOWEEN (FUEGOS Y CALABAZAS)
-- ========================================================================
local function scanHalloween()
    local firesCount = 0
    local pumpkinsCount = 0

    for _, desc in ipairs(Workspace:GetDescendants()) do
        if not desc:IsDescendantOf(LocalPlayer.Character) then
            local l = desc.Name:lower()
            if l:match("fire") or l:match("fuego") or l:match("flame") then
                if desc:IsA("BasePart") or (desc:IsA("Model") and desc.PrimaryPart) then
                    firesCount = firesCount + 1
                end
            elseif l:match("pumpkin") or l:match("calabaza") or l:match("machinepumpkin") then
                if desc:IsA("BasePart") or (desc:IsA("Model") and desc.PrimaryPart) then
                    pumpkinsCount = pumpkinsCount + 1
                end
            end
        end
    end

    State.halloweenStatus.fires = firesCount
    State.halloweenStatus.pumpkins = pumpkinsCount
    return firesCount, pumpkinsCount
end

-- ========================================================================
-- BALIZAS 3D Y GUARDADO DE COORDENADAS
-- ========================================================================
local function createFloorMarker(index, charPos, floorPos, note)
    local targetPos = floorPos or charPos
    local folder = getMarkersFolder()

    -- Cilindro en el piso
    local disc = Instance.new("Part")
    disc.Name = "Marker_" .. index
    disc.Shape = Enum.PartType.Cylinder
    disc.Size = Vector3.new(0.3, 4, 4)
    disc.CFrame = CFrame.new(targetPos) * CFrame.Angles(0, 0, math.rad(90))
    disc.Anchored = true
    disc.CanCollide = false
    disc.Material = Enum.Material.Neon
    disc.Color = Color3.fromRGB(0, 255, 200)
    disc.Transparency = 0.25
    disc.Parent = folder

    -- Columna de luz vertical
    local beam = Instance.new("Part")
    beam.Name = "Beam_" .. index
    beam.Size = Vector3.new(0.25, 20, 0.25)
    beam.Position = targetPos + Vector3.new(0, 10, 0)
    beam.Anchored = true
    beam.CanCollide = false
    beam.Material = Enum.Material.Neon
    beam.Color = Color3.fromRGB(0, 255, 200)
    beam.Transparency = 0.4
    beam.Parent = folder

    -- Cartel 3D
    local bb = Instance.new("BillboardGui")
    bb.Adornee = beam
    bb.Size = UDim2.new(0, 200, 0, 50)
    bb.StudsOffset = Vector3.new(0, 10.5, 0)
    bb.AlwaysOnTop = true

    local txt = Instance.new("TextLabel")
    txt.Size = UDim2.new(1, 0, 1, 0)
    txt.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
    txt.BackgroundTransparency = 0.25
    txt.TextColor3 = Color3.fromRGB(0, 255, 220)
    txt.Font = Enum.Font.SourceSansBold
    txt.TextSize = 12
    txt.Text = string.format("#%d: %s\nPiso Y: %.2f", index, note or "Punto", targetPos.Y)
    txt.Parent = bb

    bb.Parent = beam
end

local function saveCurrentCoordinates(noteName)
    local pPos = getPlayerPos()
    local floorPos, floorPart = getFloorDetails(pPos)
    local floorY = floorPos and floorPos.Y or (pPos.Y - 3)

    local item = {
        id = #State.savedPoints + 1,
        note = noteName or ("Punto #" .. (#State.savedPoints + 1)),
        playerPos = pPos,
        floorPos = floorPos or Vector3.new(pPos.X, floorY, pPos.Z),
        floorY = floorY,
        floorPartName = floorPart and floorPart.Name or "Aire/Nulo",
        timestamp = os.date("%H:%M:%S")
    }

    table.insert(State.savedPoints, item)
    createFloorMarker(item.id, pPos, floorPos, item.note)

    if canWrite then
        pcall(function()
            local lines = {
                "==================================================",
                "HISTORIAL DE COORDENADAS Y PISO DE DESARROLLO",
                "Fecha/Hora: " .. os.date("!%Y-%m-%d %H:%M:%S UTC"),
                "=================================================="
            }
            for _, pt in ipairs(State.savedPoints) do
                table.insert(lines, string.format(
                    "[%02d] %-25s | Pos: (X: %.2f, Y: %.2f, Z: %.2f) | Piso Y: %.2f | Parte: %s | Hora: %s",
                    pt.id, pt.note, pt.playerPos.X, pt.playerPos.Y, pt.playerPos.Z, pt.floorY, pt.floorPartName, pt.timestamp
                ))
            end
            writefile("coordenadas_guardadas.txt", table.concat(lines, "\n"))
        end)
    end

    return item
end

-- ========================================================================
-- CONSTRUCCIÓN DE LA GUI
-- ========================================================================
local function buildGUI()
    local parentGui = (gethui and gethui()) or CoreGui or LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not parentGui then return end

    local existing = parentGui:FindFirstChild("DevZonesCoordsUI")
    if existing then existing:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "DevZonesCoordsUI"
    sg.ResetOnSpawn = false

    local main = Instance.new("Frame")
    main.Name = "MainFrame"
    main.Size = UDim2.new(0, 370, 0, 520)
    main.Position = UDim2.new(0.02, 0, 0.12, 0)
    main.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
    main.BorderSizePixel = 2
    main.BorderColor3 = Color3.fromRGB(0, 210, 255)
    main.Active = true
    main.Draggable = true
    main.Parent = sg

    -- Cabecera
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 32)
    header.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
    header.BorderSizePixel = 0
    header.Parent = main

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -70, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(0, 230, 255)
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 14
    title.Text = "🛠️ Inspector: Última Zona Rotativa & Piso"
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 26, 0, 24)
    closeBtn.Position = UDim2.new(1, -30, 0, 4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.SourceSansBold
    closeBtn.TextSize = 14
    closeBtn.Text = "X"
    closeBtn.Parent = header
    closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)

    -- Scroll principal
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -12, 1, -40)
    scroll.Position = UDim2.new(0, 6, 0, 36)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 5
    scroll.CanvasSize = UDim2.new(0, 0, 0, 750)
    scroll.Parent = main

    local currentY = 5

    -- [1] SECCIÓN: ÚLTIMA ZONA ROTATIVA (Post-Great Sun)
    local s1Box = Instance.new("Frame")
    s1Box.Size = UDim2.new(1, 0, 0, 105)
    s1Box.Position = UDim2.new(0, 0, 0, currentY)
    s1Box.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
    s1Box.BorderSizePixel = 1
    s1Box.BorderColor3 = Color3.fromRGB(255, 185, 0)
    s1Box.Parent = scroll

    local s1Title = Instance.new("TextLabel")
    s1Title.Size = UDim2.new(1, -10, 0, 22)
    s1Title.Position = UDim2.new(0, 6, 0, 2)
    s1Title.BackgroundTransparency = 1
    s1Title.TextColor3 = Color3.fromRGB(255, 205, 30)
    s1Title.Font = Enum.Font.SourceSansBold
    s1Title.TextSize = 13
    s1Title.Text = "🏁 ÚLTIMA ZONA ACTIVA (Post-Great Sun)"
    s1Title.TextXAlignment = Enum.TextXAlignment.Left
    s1Title.Parent = s1Box

    local s1Text = Instance.new("TextLabel")
    s1Text.Size = UDim2.new(1, -12, 0, 76)
    s1Text.Position = UDim2.new(0, 6, 0, 24)
    s1Text.BackgroundTransparency = 1
    s1Text.TextColor3 = Color3.fromRGB(235, 235, 235)
    s1Text.Font = Enum.Font.SourceSans
    s1Text.TextSize = 13
    s1Text.TextXAlignment = Enum.TextXAlignment.Left
    s1Text.TextYAlignment = Enum.TextYAlignment.Top
    s1Text.Text = "Detectando rotación..."
    s1Text.Parent = s1Box

    currentY = currentY + 112

    -- [2] SECCIÓN: COORDENADAS Y PISO EN VIVO
    local s2Box = Instance.new("Frame")
    s2Box.Size = UDim2.new(1, 0, 0, 95)
    s2Box.Position = UDim2.new(0, 0, 0, currentY)
    s2Box.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
    s2Box.BorderSizePixel = 1
    s2Box.BorderColor3 = Color3.fromRGB(0, 210, 255)
    s2Box.Parent = scroll

    local s2Title = Instance.new("TextLabel")
    s2Title.Size = UDim2.new(1, -10, 0, 22)
    s2Title.Position = UDim2.new(0, 6, 0, 2)
    s2Title.BackgroundTransparency = 1
    s2Title.TextColor3 = Color3.fromRGB(0, 225, 255)
    s2Title.Font = Enum.Font.SourceSansBold
    s2Title.TextSize = 13
    s2Title.Text = "📍 TU POSICIÓN Y NIVEL DEL PISO (RAYCAST)"
    s2Title.TextXAlignment = Enum.TextXAlignment.Left
    s2Title.Parent = s2Box

    local s2Text = Instance.new("TextLabel")
    s2Text.Size = UDim2.new(1, -12, 0, 66)
    s2Text.Position = UDim2.new(0, 6, 0, 24)
    s2Text.BackgroundTransparency = 1
    s2Text.TextColor3 = Color3.fromRGB(220, 255, 245)
    s2Text.Font = Enum.Font.SourceSans
    s2Text.TextSize = 13
    s2Text.TextXAlignment = Enum.TextXAlignment.Left
    s2Text.TextYAlignment = Enum.TextYAlignment.Top
    s2Text.Text = "Calculando coordenadas..."
    s2Text.Parent = s2Box

    currentY = currentY + 102

    -- [3] BOTÓN: GUARDAR COORDENADAS DE TU POSICIÓN
    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(1, 0, 0, 36)
    saveBtn.Position = UDim2.new(0, 0, 0, currentY)
    saveBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 115)
    saveBtn.BorderSizePixel = 0
    saveBtn.TextColor3 = Color3.new(1, 1, 1)
    saveBtn.Font = Enum.Font.SourceSansBold
    saveBtn.TextSize = 14
    saveBtn.Text = "📌 GUARDAR COORDENADAS Y PISO AQUÍ"
    saveBtn.Parent = scroll

    currentY = currentY + 42

    -- [4] SECCIÓN: GODLY EGG Y HALLOWEEN
    local s3Box = Instance.new("Frame")
    s3Box.Size = UDim2.new(1, 0, 0, 75)
    s3Box.Position = UDim2.new(0, 0, 0, currentY)
    s3Box.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
    s3Box.BorderSizePixel = 1
    s3Box.BorderColor3 = Color3.fromRGB(160, 100, 255)
    s3Box.Parent = scroll

    local s3Title = Instance.new("TextLabel")
    s3Title.Size = UDim2.new(1, -10, 0, 22)
    s3Title.Position = UDim2.new(0, 6, 0, 2)
    s3Title.BackgroundTransparency = 1
    s3Title.TextColor3 = Color3.fromRGB(210, 140, 255)
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
    s3Text.Text = "Escaneando..."
    s3Text.Parent = s3Box

    currentY = currentY + 82

    -- [5] BOTÓN: REFRESCAR ESCANEO
    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(1, 0, 0, 32)
    refreshBtn.Position = UDim2.new(0, 0, 0, currentY)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(45, 60, 90)
    refreshBtn.BorderSizePixel = 0
    refreshBtn.TextColor3 = Color3.fromRGB(200, 230, 255)
    refreshBtn.Font = Enum.Font.SourceSansBold
    refreshBtn.TextSize = 13
    refreshBtn.Text = "🔄 RE-ESCANEAR ROTACIÓN Y MAPA"
    refreshBtn.Parent = scroll

    currentY = currentY + 38

    -- [6] LISTA DE PUNTOS GUARDADOS
    local histLabel = Instance.new("TextLabel")
    histLabel.Size = UDim2.new(1, 0, 0, 22)
    histLabel.Position = UDim2.new(0, 0, 0, currentY)
    histLabel.BackgroundTransparency = 1
    histLabel.TextColor3 = Color3.fromRGB(180, 200, 220)
    histLabel.Font = Enum.Font.SourceSansBold
    histLabel.TextSize = 13
    histLabel.Text = "📋 Coordenadas Guardadas en esta Sesión:"
    histLabel.TextXAlignment = Enum.TextXAlignment.Left
    histLabel.Parent = scroll

    currentY = currentY + 24

    local histBox = Instance.new("TextLabel")
    histBox.Size = UDim2.new(1, 0, 0, 270)
    histBox.Position = UDim2.new(0, 0, 0, currentY)
    histBox.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
    histBox.BorderSizePixel = 1
    histBox.BorderColor3 = Color3.fromRGB(35, 40, 50)
    histBox.TextColor3 = Color3.fromRGB(140, 255, 175)
    histBox.Font = Enum.Font.Code
    histBox.TextSize = 11
    histBox.TextXAlignment = Enum.TextXAlignment.Left
    histBox.TextYAlignment = Enum.TextYAlignment.Top
    histBox.Text = "  (Presiona 'GUARDAR' para marcar tu posición)"
    histBox.Parent = scroll

    local function updateHistoryView()
        if #State.savedPoints == 0 then
            histBox.Text = "  (Aún no has guardado coordenadas)"
            return
        end
        local listTxt = ""
        for i = #State.savedPoints, 1, -1 do
            local p = State.savedPoints[i]
            listTxt = listTxt .. string.format("[%02d] %s\n  Pos: X:%.1f Y:%.1f Z:%.1f\n  Piso Y: %.2f (%s)\n---------------------------\n",
                p.id, p.note, p.playerPos.X, p.playerPos.Y, p.playerPos.Z, p.floorY, p.floorPartName)
        end
        histBox.Text = listTxt
    end

    local function performScan()
        detectTrueLastZone()
        scanAllEggs()
        scanHalloween()

        local z = State.finalZone
        local coordsStr = z.coords and formatVec(z.coords) or "No fijadas"
        s1Text.Text = string.format(
            "• Zona Final: %s\n" ..
            "• Rotación: %s\n" ..
            "• Huevo(s): %s\n" ..
            "• Coordenadas Zona: %s (%d studs)",
            z.name, z.rotationType, z.eggSummary, coordsStr, z.distance
        )

        s3Text.Text = string.format("• GodlyEgg: %s\n• Fuegos Activos: %d | Calabazas: %d",
            State.godlyStatus, State.halloweenStatus.fires, State.halloweenStatus.pumpkins)
    end

    saveBtn.MouseButton1Click:Connect(function()
        local count = #State.savedPoints + 1
        local customName = "Punto #" .. count .. " [" .. State.finalZone.name .. "]"
        saveCurrentCoordinates(customName)
        updateHistoryView()

        saveBtn.Text = "✓ ¡PUNTO #" .. count .. " GUARDADO CON BALIZA!"
        saveBtn.BackgroundColor3 = Color3.fromRGB(0, 195, 140)
        task.delay(1.5, function()
            if saveBtn then
                saveBtn.Text = "📌 GUARDAR COORDENADAS Y PISO AQUÍ"
                saveBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 115)
            end
        end)
    end)

    refreshBtn.MouseButton1Click:Connect(function()
        performScan()
    end)

    -- Bucle en tiempo real para posición y altura de piso
    local lastUpdate = 0
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if not main or not main.Parent then
            conn:Disconnect()
            return
        end

        local now = tick()
        if now - lastUpdate >= 0.2 then
            lastUpdate = now
            local pos = getPlayerPos()
            local fPos, fPart = getFloorDetails(pos)
            local floorY = fPos and fPos.Y or (pos.Y - 3)
            local partName = fPart and fPart.Name or "No detectada"

            s2Text.Text = string.format(
                "• Posición: X: %.2f, Y: %.2f, Z: %.2f\n" ..
                "• Nivel del Piso (Y): %.2f\n" ..
                "• Bloque Piso: %s\n" ..
                "• Distancia a Última Zona: %d studs",
                pos.X, pos.Y, pos.Z,
                floorY,
                partName,
                State.finalZone.distance or 0
            )
        end
    end)

    performScan()
    sg.Parent = parentGui
    print("✅ GUI de última zona rotativa iniciada.")
end

buildGUI()
