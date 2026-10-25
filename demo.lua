--[[
    ========================================================================
    PANEL DE DESARROLLO: DETECCIÓN DE ZONAS ROTATIVAS, HUEVOS Y MARCADOR DE PISO
    ========================================================================
    Diseñado para pruebas locales en Roblox Luau / Delta.
    
    Funcionalidades:
    1. ZONA FINAL ROTATIVA:
       - Detecta si la última zona activa es "Hero's Base" (Hero Egg) o 
         "Villain's Hideout" (Evil Egg), o la zona tras "Great Sun".
       - Muestra en la GUI el nombre de la zona activa y qué huevo contiene.
    2. LOCALIZADOR DE HUEVOS & GODLY EGG:
       - Mapea 'Workspace.Eggs' y busca 'GodlyEgg' y demás huevos de las zonas.
    3. DETECTOR DE NIVEL DEL PISO (RAYCASTING):
       - Calcula la coordenada exacta donde estás parado y la altura real 
         del suelo (piso Y) debajo de tus pies mediante Raycast.
    4. BOTÓN "GUARDAR / MARCAR COORDENADA":
       - Guarda las coordenadas actuales (X, Y, Z + Piso Y).
       - Crea una baliza / marcador 3D visual en el mundo.
       - Guarda el historial en 'coordenadas_guardadas.txt' (writefile).
       - Botón para copiar al portapapeles si Delta lo soporta.
    5. DETECCIÓN DE EVENTO HALLOWEEN:
       - Conteo y ubicación de Fuegos y Calabazas.
    ========================================================================
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local canWrite = (type(writefile) == "function")
local canCopy = (type(setclipboard) == "function")

-- Estado global
local State = {
    savedPoints = {},
    lastScannedEggs = {},
    activeLastZone = { name = "Detectando...", egg = "Desconocido", details = "" },
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

-- Detección precisa de la superficie del piso con Raycast
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
    return string.format("X: %.2f, Y: %.2f, Z: %.2f", v.X, v.Y, v.Z)
end

-- ========================================================================
-- DETECTAR ÚLTIMA ZONA ROTATIVA (Hero's Base vs Villain's Hideout vs Sun)
-- ========================================================================
local function detectRotatingLastZone()
    local lastZoneInfo = {
        name = "No identificada",
        egg = "Ninguno",
        details = ""
    }

    -- 1. Consultar módulos de configuración en ReplicatedStorage
    local heroEvilCfg = nil
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    if modules then
        local heMod = modules:FindFirstChild("HeroAndEvilConfigurations")
        if heMod and heMod:IsA("ModuleScript") then
            pcall(function()
                heroEvilCfg = require(heMod)
            end)
        end
    end

    -- 2. Inspeccionar Workspace.Eggs y Workspace general para ver cuál está instanciada
    local eggsFolder = Workspace:FindFirstChild("Eggs")
    local foundHero = false
    local foundEvil = false
    local foundSun = false
    local heroEggs = {}
    local evilEggs = {}

    if eggsFolder then
        for _, zoneFolder in ipairs(eggsFolder:GetChildren()) do
            local zName = zoneFolder.Name:lower()

            if zName:match("hero") then
                foundHero = true
                for _, d in ipairs(zoneFolder:GetDescendants()) do
                    if d.Name:lower():match("egg") or d:IsA("Model") then
                        table.insert(heroEggs, d.Name)
                    end
                end
            elseif zName:match("evil") or zName:match("villain") then
                foundEvil = true
                for _, d in ipairs(zoneFolder:GetDescendants()) do
                    if d.Name:lower():match("egg") or d:IsA("Model") then
                        table.insert(evilEggs, d.Name)
                    end
                end
            elseif zName:match("sun") then
                foundSun = true
            end
        end
    end

    -- Búsqueda adicional en el mapa general por si la zona se carga fuera de Workspace.Eggs
    if not foundHero and not foundEvil then
        for _, obj in ipairs(Workspace:GetChildren()) do
            local oName = obj.Name:lower()
            if oName:match("hero") then
                foundHero = true
            elseif oName:match("villain") or oName:match("evil") then
                foundEvil = true
            end
        end
    end

    -- Determinar estado actual
    if foundHero and not foundEvil then
        lastZoneInfo.name = "Hero's Base (Héroes)"
        lastZoneInfo.egg = "Hero Egg"
        lastZoneInfo.details = "Rotación activa: Bando Heroico"
    elseif foundEvil and not foundHero then
        lastZoneInfo.name = "Villain's Hideout (Villanos)"
        lastZoneInfo.egg = "Evil Egg"
        lastZoneInfo.details = "Rotación activa: Bando Villano"
    elseif foundHero and foundEvil then
        lastZoneInfo.name = "Hero's Base & Villain's Hideout"
        lastZoneInfo.egg = "Hero Egg / Evil Egg"
        lastZoneInfo.details = "Ambas zonas presentes en Workspace"
    elseif foundSun then
        lastZoneInfo.name = "Great Sun Zone"
        lastZoneInfo.egg = "Sun Egg"
        lastZoneInfo.details = "Zona previa a la rotación activa"
    else
        -- Comprobar si hay alguna zona nombrada como última (ej. Zone8)
        if eggsFolder and eggsFolder:FindFirstChild("Zone8") then
            lastZoneInfo.name = "Zone 8 (Última Zona)"
            lastZoneInfo.egg = "Rotativo / Especial"
            lastZoneInfo.details = "Detectada carpeta Zone8 en Workspace.Eggs"
        else
            lastZoneInfo.name = "Esperando rotación"
            lastZoneInfo.egg = "N/A"
            lastZoneInfo.details = "No se detectaron zonas Hero/Evil activas"
        end
    end

    State.activeLastZone = lastZoneInfo
    return lastZoneInfo
end

-- ========================================================================
-- ESCANEAR HUEVOS Y BUSCAR GODLY EGG
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
                        -- Atributos / valores
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
        State.godlyStatus = string.format("Zona: %s (%d studs)", godlyFound.zone, godlyFound.distance)
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
-- GUARDAR Y CREAR BALIZA 3D EN EL MUNDO
-- ========================================================================
local function createFloorMarker(index, charPos, floorPos, note)
    local targetPos = floorPos or charPos
    local folder = getMarkersFolder()

    -- Cilindro base en el piso
    local disc = Instance.new("Part")
    disc.Name = "Marker_" .. index
    disc.Shape = Enum.PartType.Cylinder
    disc.Size = Vector3.new(0.4, 4, 4)
    disc.CFrame = CFrame.new(targetPos) * CFrame.Angles(0, 0, math.rad(90))
    disc.Anchored = true
    disc.CanCollide = false
    disc.Material = Enum.Material.Neon
    disc.Color = Color3.fromRGB(0, 255, 200)
    disc.Transparency = 0.3
    disc.Parent = folder

    -- Baliza vertical (columna de luz)
    local beam = Instance.new("Part")
    beam.Name = "Beam_" .. index
    beam.Size = Vector3.new(0.3, 16, 0.3)
    beam.Position = targetPos + Vector3.new(0, 8, 0)
    beam.Anchored = true
    beam.CanCollide = false
    beam.Material = Enum.Material.Neon
    beam.Color = Color3.fromRGB(0, 255, 200)
    beam.Transparency = 0.5
    beam.Parent = folder

    -- Cartel flotante con datos
    local bb = Instance.new("BillboardGui")
    bb.Adornee = beam
    bb.Size = UDim2.new(0, 180, 0, 48)
    bb.StudsOffset = Vector3.new(0, 8.5, 0)
    bb.AlwaysOnTop = true

    local txt = Instance.new("TextLabel")
    txt.Size = UDim2.new(1, 0, 1, 0)
    txt.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    txt.BackgroundTransparency = 0.3
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
    local floorY = floorPos and floorPos.Y or (pPos.Y - 3) -- aproximación si no hay hit

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

    -- Guardar en archivo local
    if canWrite then
        pcall(function()
            local lines = {
                "==================================================",
                "REGISTRO DE COORDENADAS Y NIVELES DE PISO",
                "Fecha/Hora: " .. os.date("!%Y-%m-%d %H:%M:%S UTC"),
                "=================================================="
            }
            for _, pt in ipairs(State.savedPoints) do
                table.insert(lines, string.format(
                    "[%02d] %-15s | Posición: (X: %.2f, Y: %.2f, Z: %.2f) | Piso Y: %.2f | Objeto piso: %s | Hora: %s",
                    pt.id, pt.note, pt.playerPos.X, pt.playerPos.Y, pt.playerPos.Z, pt.floorY, pt.floorPartName, pt.timestamp
                ))
            end
            writefile("coordenadas_guardadas.txt", table.concat(lines, "\n"))
        end)
    end

    return item
end

-- ========================================================================
-- CONSTRUCCIÓN DE LA INTERFAZ GRÁFICA (GUI)
-- ========================================================================
local function buildGUI()
    local parentGui = (gethui and gethui()) or CoreGui or LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not parentGui then return end

    local existing = parentGui:FindFirstChild("DevZonesCoordsUI")
    if existing then existing:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "DevZonesCoordsUI"
    sg.ResetOnSpawn = false

    -- Marco Principal
    local main = Instance.new("Frame")
    main.Name = "MainFrame"
    main.Size = UDim2.new(0, 360, 0, 480)
    main.Position = UDim2.new(0.02, 0, 0.15, 0)
    main.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
    main.BorderSizePixel = 2
    main.BorderColor3 = Color3.fromRGB(0, 200, 255)
    main.Active = true
    main.Draggable = true
    main.Parent = sg

    -- Barra superior
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 32)
    header.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
    header.BorderSizePixel = 0
    header.Parent = main

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -70, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(0, 230, 255)
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 15
    title.Text = "🛠️ Inspector: Zonas, Huevos & Coords"
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    -- Botón Cerrar
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 26, 0, 24)
    closeBtn.Position = UDim2.new(1, -30, 0, 4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.SourceSansBold
    closeBtn.TextSize = 14
    closeBtn.Text = "X"
    closeBtn.Parent = header
    closeBtn.MouseButton1Click:Connect(function()
        sg:Destroy()
    end)

    -- Contenedor interno desplazable
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -12, 1, -40)
    scroll.Position = UDim2.new(0, 6, 0, 36)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 5
    scroll.CanvasSize = UDim2.new(0, 0, 0, 680)
    scroll.Parent = main

    local currentY = 5

    -- 1. SECCIÓN: ÚLTIMA ZONA ROTATIVA
    local s1Box = Instance.new("Frame")
    s1Box.Size = UDim2.new(1, 0, 0, 92)
    s1Box.Position = UDim2.new(0, 0, 0, currentY)
    s1Box.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    s1Box.BorderSizePixel = 1
    s1Box.BorderColor3 = Color3.fromRGB(255, 180, 0)
    s1Box.Parent = scroll

    local s1Title = Instance.new("TextLabel")
    s1Title.Size = UDim2.new(1, -10, 0, 22)
    s1Title.Position = UDim2.new(0, 5, 0, 2)
    s1Title.BackgroundTransparency = 1
    s1Title.TextColor3 = Color3.fromRGB(255, 200, 0)
    s1Title.Font = Enum.Font.SourceSansBold
    s1Title.TextSize = 13
    s1Title.Text = "🔄 ÚLTIMA ZONA ACTIVA (Rotativa)"
    s1Title.TextXAlignment = Enum.TextXAlignment.Left
    s1Title.Parent = s1Box

    local s1Text = Instance.new("TextLabel")
    s1Text.Size = UDim2.new(1, -10, 0, 64)
    s1Text.Position = UDim2.new(0, 5, 0, 24)
    s1Text.BackgroundTransparency = 1
    s1Text.TextColor3 = Color3.fromRGB(230, 230, 230)
    s1Text.Font = Enum.Font.SourceSans
    s1Text.TextSize = 13
    s1Text.TextXAlignment = Enum.TextXAlignment.Left
    s1Text.TextYAlignment = Enum.TextYAlignment.Top
    s1Text.Text = "Cargando zona..."
    s1Text.Parent = s1Box

    currentY = currentY + 98

    -- 2. SECCIÓN: COORDENADAS EN VIVO & PISO
    local s2Box = Instance.new("Frame")
    s2Box.Size = UDim2.new(1, 0, 0, 100)
    s2Box.Position = UDim2.new(0, 0, 0, currentY)
    s2Box.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    s2Box.BorderSizePixel = 1
    s2Box.BorderColor3 = Color3.fromRGB(0, 200, 255)
    s2Box.Parent = scroll

    local s2Title = Instance.new("TextLabel")
    s2Title.Size = UDim2.new(1, -10, 0, 22)
    s2Title.Position = UDim2.new(0, 5, 0, 2)
    s2Title.BackgroundTransparency = 1
    s2Title.TextColor3 = Color3.fromRGB(0, 220, 255)
    s2Title.Font = Enum.Font.SourceSansBold
    s2Title.TextSize = 13
    s2Title.Text = "📍 TU POSICIÓN Y NIVEL DEL SUELO"
    s2Title.TextXAlignment = Enum.TextXAlignment.Left
    s2Title.Parent = s2Box

    local s2Text = Instance.new("TextLabel")
    s2Text.Size = UDim2.new(1, -10, 0, 70)
    s2Text.Position = UDim2.new(0, 5, 0, 24)
    s2Text.BackgroundTransparency = 1
    s2Text.TextColor3 = Color3.fromRGB(220, 255, 240)
    s2Text.Font = Enum.Font.SourceSans
    s2Text.TextSize = 13
    s2Text.TextXAlignment = Enum.TextXAlignment.Left
    s2Text.TextYAlignment = Enum.TextYAlignment.Top
    s2Text.Text = "Calculando coordenadas..."
    s2Text.Parent = s2Box

    currentY = currentY + 106

    -- 3. BOTÓN: GUARDAR COORDENADA ACTUAL
    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(1, 0, 0, 36)
    saveBtn.Position = UDim2.new(0, 0, 0, currentY)
    saveBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 110)
    saveBtn.BorderSizePixel = 0
    saveBtn.TextColor3 = Color3.new(1, 1, 1)
    saveBtn.Font = Enum.Font.SourceSansBold
    saveBtn.TextSize = 14
    saveBtn.Text = "📌 GUARDAR COORDENADAS Y PISO AQUÍ"
    saveBtn.Parent = scroll

    currentY = currentY + 42

    -- 4. SECCIÓN: ESTADO DE GODLY EGG Y EVENTOS
    local s3Box = Instance.new("Frame")
    s3Box.Size = UDim2.new(1, 0, 0, 80)
    s3Box.Position = UDim2.new(0, 0, 0, currentY)
    s3Box.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    s3Box.BorderSizePixel = 1
    s3Box.BorderColor3 = Color3.fromRGB(150, 100, 255)
    s3Box.Parent = scroll

    local s3Title = Instance.new("TextLabel")
    s3Title.Size = UDim2.new(1, -10, 0, 22)
    s3Title.Position = UDim2.new(0, 5, 0, 2)
    s3Title.BackgroundTransparency = 1
    s3Title.TextColor3 = Color3.fromRGB(200, 140, 255)
    s3Title.Font = Enum.Font.SourceSansBold
    s3Title.TextSize = 13
    s3Title.Text = "⭐ GODLY EGG & EVENTO HALLOWEEN"
    s3Title.TextXAlignment = Enum.TextXAlignment.Left
    s3Title.Parent = s3Box

    local s3Text = Instance.new("TextLabel")
    s3Text.Size = UDim2.new(1, -10, 0, 52)
    s3Text.Position = UDim2.new(0, 5, 0, 24)
    s3Text.BackgroundTransparency = 1
    s3Text.TextColor3 = Color3.fromRGB(230, 230, 230)
    s3Text.Font = Enum.Font.SourceSans
    s3Text.TextSize = 13
    s3Text.TextXAlignment = Enum.TextXAlignment.Left
    s3Text.TextYAlignment = Enum.TextYAlignment.Top
    s3Text.Text = "Escaneando..."
    s3Text.Parent = s3Box

    currentY = currentY + 86

    -- 5. BOTÓN: RE-ESCANEAR TODO
    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(1, 0, 0, 32)
    refreshBtn.Position = UDim2.new(0, 0, 0, currentY)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(50, 65, 95)
    refreshBtn.BorderSizePixel = 0
    refreshBtn.TextColor3 = Color3.fromRGB(200, 230, 255)
    refreshBtn.Font = Enum.Font.SourceSansBold
    refreshBtn.TextSize = 13
    refreshBtn.Text = "🔄 RE-ESCANEAR ZONAS Y MAPA"
    refreshBtn.Parent = scroll

    currentY = currentY + 38

    -- 6. HISTORIAL DE PUNTOS GUARDADOS
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
    histBox.Size = UDim2.new(1, 0, 0, 250)
    histBox.Position = UDim2.new(0, 0, 0, currentY)
    histBox.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
    histBox.BorderSizePixel = 1
    histBox.BorderColor3 = Color3.fromRGB(40, 45, 55)
    histBox.TextColor3 = Color3.fromRGB(150, 255, 180)
    histBox.Font = Enum.Font.Code
    histBox.TextSize = 11
    histBox.TextXAlignment = Enum.TextXAlignment.Left
    histBox.TextYAlignment = Enum.TextYAlignment.Top
    histBox.Text = "  (Presiona 'GUARDAR' para marcar tu posición)"
    histBox.Parent = scroll

    -- Actualizar visualización del historial
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

    -- Evento Botón Guardar
    saveBtn.MouseButton1Click:Connect(function()
        local count = #State.savedPoints + 1
        local customName = "Punto #" .. count .. " (" .. State.activeLastZone.name .. ")"
        local saved = saveCurrentCoordinates(customName)
        updateHistoryView()

        saveBtn.Text = "✓ ¡PUNTO #" .. count .. " GUARDADO!"
        saveBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 140)
        task.delay(1.5, function()
            if saveBtn then
                saveBtn.Text = "📌 GUARDAR COORDENADAS Y PISO AQUÍ"
                saveBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 110)
            end
        end)
    end)

    -- Evento Botón Refrescar
    local function performScan()
        detectRotatingLastZone()
        scanAllEggs()
        scanHalloween()

        s1Text.Text = string.format("• Zona Activa: %s\n• Huevo: %s\n• Estado: %s",
            State.activeLastZone.name, State.activeLastZone.egg, State.activeLastZone.details)

        s3Text.Text = string.format("• GodlyEgg: %s\n• Fuegos Activos: %d\n• Calabazas: %d",
            State.godlyStatus, State.halloweenStatus.fires, State.halloweenStatus.pumpkins)
    end

    refreshBtn.MouseButton1Click:Connect(function()
        performScan()
    end)

    -- Loop ligero para actualizar coordenadas en vivo cada 0.2 segundos
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
            local partName = fPart and fPart.Name or "No detectado"

            s2Text.Text = string.format(
                "• Posición: X: %.2f, Y: %.2f, Z: %.2f\n" ..
                "• Nivel Piso (Y): %.2f\n" ..
                "• Superficie: %s\n" ..
                "• Zona actual más cercana: %s",
                pos.X, pos.Y, pos.Z,
                floorY,
                partName,
                (#State.lastScannedEggs > 0 and State.lastScannedEggs[1].zone or "Buscando...")
            )
        end
    end)

    -- Escaneo inicial
    performScan()
    sg.Parent = parentGui
    print("✅ Panel de inspección y marcador de coordenadas iniciado correctamente.")
end

-- Iniciar GUI
buildGUI()
