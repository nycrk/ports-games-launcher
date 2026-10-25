--[[
    ========================================================================
    INSPECTOR PRO: ZONAS, HUEVOS & PLATAFORMA SEGURA DE SUBSUELO (ANTI-CAÍDA)
    ========================================================================
    Diseñado para pruebas y desarrollo en Roblox Luau / Delta.
    
    ¿Por qué caías al vacío?
    El suelo del mapa (Baseplate) termina en Y = 0.00. Debajo de eso no hay
    piezas sólidas en el juego, por lo que la gravedad hace caer a tu personaje
    hasta el límite del vacío (FallenPartsDestroyHeight) y Roblox te elimina.
    
    Solución implementada en esta versión:
    1. PLATAFORMA DE SOPORTE LOCAL AUTOMÁTICA:
       - Al presionar '⬇️ BAJAR AL SUBSUELO', el script genera una plataforma física 
         neón debajo de ti (Anchored = true, CanCollide = true).
       - Te sitúa sobre ella para que puedas quedarte parado a Y ≈ -3.5 studs 
         sin caerte al vacío ni morir.
    2. BOTÓN DE REGRESO SEGURO:
       - '⬆️ SUBIR A LA SUPERFICIE' te regresa de vuelta al suelo normal (Y ≈ 3.5)
         y limpia la plataforma de prueba.
    3. DETECCIÓN DINÁMICA DE ZONA ROTATIVA:
       - Confirmado funcionando en tus capturas:
         * ClashStage  -> Clash Egg
         * EvilStage   -> Evil Egg
         * HeroStage   -> Hero Egg
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

local State = {
    running = true,
    isUnderground = false,
    subPlatform = nil,
    subPlatformFollow = nil,
    savedPoints = {},
    allZones = {},
    rotatingLastZone = {
        name = "EvilStage",
        egg = "Evil Egg",
        coords = nil,
        distance = 0,
        status = "Detectando..."
    },
    heldEgg = {
        isCarrying = false,
        name = "Ninguno",
        details = "Manos libres",
        isFromLastZone = false
    },
    hasMovedEgg = false,
    godlyEgg = { found = false, info = "Buscando..." },
    halloween = { fires = 0, pumpkins = 0 },
    lastSavedFeedback = "Ninguna posición guardada aún."
}

-- ========================================================================
-- FUNCIONES DE POSICIÓN Y PISO (COMPATIBILIDAD UNIVERSAL)
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
    local char = LocalPlayer.Character
    if not char then return pos.Y - 3, "Sin Personaje" end

    local rayOrigin = pos + Vector3.new(0, 3, 0)
    local rayDir = Vector3.new(0, -90, 0)

    local params = RaycastParams.new()
    pcall(function() params.FilterType = Enum.RaycastFilterType.Blacklist end)
    pcall(function() if not params.FilterType then params.FilterType = Enum.RaycastFilterType.Exclude end end)
    
    local filterList = {char}
    if State.subPlatform then table.insert(filterList, State.subPlatform) end
    params.FilterDescendantsInstances = filterList

    local ok, hit = pcall(function()
        return Workspace:Raycast(rayOrigin, rayDir, params)
    end)

    if ok and hit then
        return hit.Position.Y, (hit.Instance and hit.Instance.Name or "Piso Físico")
    end

    return 0.00, "Baseplate (Nivel 0.0)"
end

local function formatVec(v)
    if not v then return "N/A" end
    return string.format("X: %.1f, Y: %.1f, Z: %.1f", v.X, v.Y, v.Z)
end

-- ========================================================================
-- PLATAFORMA SEGURA DE SUBSUELO (ANTI-CAÍDA / ANTI-VACÍO)
-- ========================================================================
-- La plataforma sigue al jugador en X/Z antes de cada paso de física. Por eso
-- no tiene distancia máxima de caminata: no se queda en el punto inicial.
local function stopSubfloorPlatform()
    if State.subPlatformFollow then
        State.subPlatformFollow:Disconnect()
        State.subPlatformFollow = nil
    end
    if State.subPlatform and State.subPlatform.Parent then
        State.subPlatform:Destroy()
    end
    State.subPlatform = nil
end

local function startSubfloorPlatformFollow()
    if State.subPlatformFollow then
        State.subPlatformFollow:Disconnect()
        State.subPlatformFollow = nil
    end

    -- PreSimulation ocurre antes de la física. Heartbeat es el respaldo para
    -- clientes que no expongan ese evento.
    local followSignal = RunService.PreSimulation or RunService.Heartbeat
    State.subPlatformFollow = followSignal:Connect(function()
        local platform = State.subPlatform
        if not State.isUnderground or not platform or not platform.Parent then
            if State.subPlatformFollow then
                State.subPlatformFollow:Disconnect()
                State.subPlatformFollow = nil
            end
            return
        end

        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            return
        end

        -- Mantiene la altura del piso y centra la superficie bajo el jugador.
        -- Así puedes caminar todo lo que quieras mientras sigas en subsuelo.
        local desired = Vector3.new(root.Position.X, platform.Position.Y, root.Position.Z)
        if (platform.Position - desired).Magnitude > 0.05 then
            platform.CFrame = CFrame.new(desired)
        end
    end)
end

local function enterSubfloorSafe()
    local char = LocalPlayer.Character
    if not char then return false, "Sin Personaje" end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return false, "Sin RootPart" end

    local curPos = root.Position
    local targetY = -3.50 -- Nivel debajo del Baseplate

    -- Elimina una plataforma/conexión anterior antes de iniciar una nueva.
    stopSubfloorPlatform()

    -- Es amplia como margen adicional, pero el seguimiento continuo es lo que
    -- evita que desaparezca o quede atrás cuando caminas.
    local plat = Instance.new("Part")
    plat.Name = "Dev_Plataforma_Soporte_Subsuelo"
    plat.Size = Vector3.new(48, 1, 48)
    plat.CFrame = CFrame.new(curPos.X, targetY - 2.5, curPos.Z)
    plat.Anchored = true
    plat.CanCollide = true
    plat.CanQuery = true
    plat.CanTouch = true
    plat.Material = Enum.Material.Neon
    plat.Color = Color3.fromRGB(0, 220, 255)
    plat.Transparency = 0.35
    plat.CastShadow = false
    plat.Parent = Workspace

    State.subPlatform = plat
    State.isUnderground = true

    -- Mover al jugador de forma segura encima de la plataforma.
    root.CFrame = CFrame.new(curPos.X, targetY, curPos.Z)
    startSubfloorPlatformFollow()
    return true, targetY
end

local function exitSubfloorSafe()
    local char = LocalPlayer.Character
    if not char then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    local curPos = root.Position
    State.isUnderground = false
    stopSubfloorPlatform()
    root.CFrame = CFrame.new(curPos.X, 3.50, curPos.Z)
    return true, 3.50
end

-- No deja plataformas o conexiones huérfanas después de reaparecer.
LocalPlayer.CharacterAdded:Connect(function()
    State.isUnderground = false
    stopSubfloorPlatform()
end)

-- ========================================================================
-- DETECTAR ÚLTIMA ZONA ROTATIVA
-- ========================================================================
local function detectRotatingLastZone()
    local playerPos = getPlayerPos()
    local detected = {
        name = "No identificada",
        egg = "No detectado",
        coords = nil,
        distance = 0,
        status = "Buscando en Workspace..."
    }

    local targetObj = nil

    for _, desc in ipairs(Workspace:GetDescendants()) do
        local l = desc.Name:lower()
        if not desc:IsDescendantOf(LocalPlayer.Character) then
            if l:match("evilstage") or l:match("villain") or (l:match("evil") and desc:IsA("Model")) then
                targetObj = desc
                detected.name = desc.Name
                detected.egg = "Evil Egg"
                detected.status = "👺 ¡VILLAIN'S HIDEOUT ACTIVA!"
                break
            elseif l:match("clashstage") or l:match("clash arena") or l == "clash" then
                targetObj = desc
                detected.name = desc.Name
                detected.egg = "Clash Egg"
                detected.status = "🔥 ¡CLASHSTAGE / ARENA ACTIVA!"
                break
            elseif l:match("herostage") or (l:match("hero") and not l:match("shinra")) then
                targetObj = desc
                detected.name = desc.Name
                detected.egg = "Hero Egg"
                detected.status = "🦸 ¡HERO'S BASE ACTIVA!"
                break
            end
        end
    end

    if targetObj then
        local foundEggPart = nil
        for _, d in ipairs(targetObj:GetDescendants()) do
            local dl = d.Name:lower()
            if dl:match("egg") or (d:IsA("Model") and d.Name == "SpawnedEgg") then
                local p = (d:IsA("BasePart") and d) or (d:IsA("Model") and (d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")))
                if p then
                    foundEggPart = p
                    local attr = d:GetAttribute("EggType") or d:GetAttribute("Type")
                    if attr then detected.egg = tostring(attr) end
                    break
                end
            end
        end

        if not foundEggPart then
            foundEggPart = targetObj:FindFirstChildWhichIsA("BasePart", true)
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
-- DETECTAR HUEVO EN MANO
-- ========================================================================
local function checkHeldEgg()
    local char = LocalPlayer.Character
    if not char then
        State.heldEgg = { isCarrying = false, name = "Sin Personaje", details = "N/A", isFromLastZone = false }
        return State.heldEgg
    end

    local carrying = false
    local eggName = "Ninguno"
    local detailStr = "Manos libres"

    for _, child in ipairs(char:GetChildren()) do
        local l = child.Name:lower()
        if (l:match("egg") or l:match("carry") or l:match("spawned")) and (child:IsA("Model") or child:IsA("BasePart")) then
            carrying = true
            eggName = child.Name
            detailStr = "Objeto en mano: " .. child.Name
            break
        end
    end

    if not carrying then
        for _, partName in ipairs({"RightHand", "LeftHand", "Right Arm", "Left Arm", "UpperTorso", "HumanoidRootPart"}) do
            local bodyPart = char:FindFirstChild(partName)
            if bodyPart then
                for _, weld in ipairs(bodyPart:GetChildren()) do
                    if weld:IsA("Weld") or weld:IsA("WeldConstraint") or weld:IsA("Motor6D") then
                        local part1 = weld.Part1 or (weld:IsA("WeldConstraint") and weld.Part1)
                        if part1 and part1.Parent and part1.Parent ~= char then
                            local pl = part1.Parent.Name:lower()
                            if pl:match("egg") or pl:match("carry") then
                                carrying = true
                                eggName = part1.Parent.Name
                                detailStr = "Soldado a " .. partName
                                break
                            end
                        end
                    end
                end
            end
            if carrying then break end
        end
    end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local animName = (track.Animation and track.Animation.Name:lower()) or ""
                if animName:match("carry") or animName:match("hold") then
                    carrying = true
                    if eggName == "Ninguno" then
                        eggName = State.rotatingLastZone.egg or "Huevo en mano"
                    end
                    detailStr = "Pose Carry activa (" .. animName .. ")"
                    break
                end
            end
        end
    end

    local isLastZone = false
    if carrying and State.rotatingLastZone.egg ~= "No detectado" then
        local hLower = eggName:lower()
        local targetLower = State.rotatingLastZone.egg:lower()
        if hLower:match(targetLower) or targetLower:match(hLower)
           or (targetLower:match("evil") and (hLower:match("evil") or hLower:match("carry") or hLower:match("huevo")))
           or (targetLower:match("clash") and hLower:match("clash"))
           or (targetLower:match("hero") and hLower:match("hero")) then
            isLastZone = true
        end
    end

    State.heldEgg = {
        isCarrying = carrying,
        name = eggName,
        details = detailStr,
        isFromLastZone = isLastZone
    }
    return State.heldEgg
end

-- ========================================================================
-- ESCANEAR ZONAS Y EVENTOS
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
                    if p and not repPart then repPart = p end

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

    State.allZones = zonesList
    if godlyFound then
        State.godlyEgg = { found = true, info = string.format("¡En %s! a %d studs", godlyFound.zone, godlyFound.dist) }
    else
        State.godlyEgg = { found = false, info = "No spawneado actualmente" }
    end

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
-- GUARDAR POSICIÓN
-- ========================================================================
local function saveCurrentPosition()
    local pPos = getPlayerPos()
    local floorY, floorPart = getFloorY(pPos)
    local subY = floorY - 3.5

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
        subfloorY = subY,
        floorPart = floorPart,
        heldEgg = State.heldEgg.name,
        isLastZoneEgg = State.heldEgg.isFromLastZone,
        time = os.date("%H:%M:%S")
    }

    table.insert(State.savedPoints, item)

    local feedbackStr = string.format("✅ #%d: X:%.1f, Y:%.1f, Z:%.1f | Piso: %.2f | Subsuelo: %.2f",
        item.id, item.x, item.y, item.z, item.floorY, item.subfloorY)
    State.lastSavedFeedback = feedbackStr

    if canCopy then
        pcall(function()
            local copyText = string.format("Vector3.new(%.2f, %.2f, %.2f) -- Piso Y: %.2f (%s | Huevo: %s)",
                item.x, item.y, item.z, item.floorY, item.note, item.heldEgg)
            setclipboard(copyText)
        end)
    end

    if canWrite then
        pcall(function()
            local lines = {
                "==================================================",
                "HISTORIAL DE COORDENADAS, PISO Y SUBSUELO",
                "Fecha: " .. os.date("!%Y-%m-%d %H:%M:%S UTC"),
                "=================================================="
            }
            for _, pt in ipairs(State.savedPoints) do
                table.insert(lines, string.format(
                    "[%02d] %-22s | Pos: (%.2f, %.2f, %.2f) | Piso Y: %.2f | Subsuelo Y: %.2f | Huevo: %s (ÚltimaZona: %s) | Hora: %s",
                    pt.id, pt.note, pt.x, pt.y, pt.z, pt.floorY, pt.subfloorY, pt.heldEgg, tostring(pt.isLastZoneEgg), pt.time
                ))
            end
            writefile("coordenadas_guardadas.txt", table.concat(lines, "\n"))
        end)
    end

    return item, feedbackStr
end

-- ========================================================================
-- CONSTRUCCIÓN DE LA GUI
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
    main.Size = UDim2.new(0, 385, 0, 610)
    main.Position = UDim2.new(0.02, 0, 0.04, 0)
    main.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
    main.BorderSizePixel = 2
    main.BorderColor3 = Color3.fromRGB(0, 220, 255)
    main.Active = true
    main.Draggable = true
    main.Parent = sg

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
    title.Text = "🛠️ Inspector Pro: Zonas & Subsuelo"
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
        State.isUnderground = false
        stopSubfloorPlatform()
        sg:Destroy()
    end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -12, 1, -42)
    scroll.Position = UDim2.new(0, 6, 0, 38)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 5
    scroll.CanvasSize = UDim2.new(0, 0, 0, 990)
    scroll.Parent = main

    local curY = 5

    -- [1] ÚLTIMA ZONA ROTATIVA ACTIVA
    local s1Box = Instance.new("Frame")
    s1Box.Size = UDim2.new(1, 0, 0, 105)
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
    s1Text.Size = UDim2.new(1, -12, 0, 78)
    s1Text.Position = UDim2.new(0, 6, 0, 24)
    s1Text.BackgroundTransparency = 1
    s1Text.TextColor3 = Color3.fromRGB(240, 240, 240)
    s1Text.Font = Enum.Font.SourceSans
    s1Text.TextSize = 13
    s1Text.TextXAlignment = Enum.TextXAlignment.Left
    s1Text.TextYAlignment = Enum.TextYAlignment.Top
    s1Text.Text = "Buscando rotación..."
    s1Text.Parent = s1Box

    curY = curY + 112

    -- [2] SECCIÓN HUEVO EN MANO + DETECTOR ÚLTIMA ZONA
    local carryBox = Instance.new("Frame")
    carryBox.Size = UDim2.new(1, 0, 0, 75)
    carryBox.Position = UDim2.new(0, 0, 0, curY)
    carryBox.BackgroundColor3 = Color3.fromRGB(20, 28, 40)
    carryBox.BorderSizePixel = 1
    carryBox.BorderColor3 = Color3.fromRGB(0, 255, 170)
    carryBox.Parent = scroll

    local carryTitle = Instance.new("TextLabel")
    carryTitle.Size = UDim2.new(1, -10, 0, 20)
    carryTitle.Position = UDim2.new(0, 6, 0, 2)
    carryTitle.BackgroundTransparency = 1
    carryTitle.TextColor3 = Color3.fromRGB(0, 255, 200)
    carryTitle.Font = Enum.Font.SourceSansBold
    carryTitle.TextSize = 13
    carryTitle.Text = "🥚 HUEVO EN MANO / RECOLECCIÓN ([E])"
    carryTitle.TextXAlignment = Enum.TextXAlignment.Left
    carryTitle.Parent = carryBox

    local carryText = Instance.new("TextLabel")
    carryText.Size = UDim2.new(1, -12, 0, 48)
    carryText.Position = UDim2.new(0, 6, 0, 22)
    carryText.BackgroundTransparency = 1
    carryText.TextColor3 = Color3.fromRGB(240, 255, 250)
    carryText.Font = Enum.Font.SourceSans
    carryText.TextSize = 13
    carryText.TextXAlignment = Enum.TextXAlignment.Left
    carryText.Text = "• Estado: Manos libres (Sin huevo)"
    carryText.Parent = carryBox

    curY = curY + 82

    -- [3] TU POSICIÓN, PISO Y SUBSUELO EN VIVO
    local s2Box = Instance.new("Frame")
    s2Box.Size = UDim2.new(1, 0, 0, 105)
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
    s2Title.Text = "📍 TU POSICIÓN, PISO Y SUBSUELO (EN VIVO)"
    s2Title.TextXAlignment = Enum.TextXAlignment.Left
    s2Title.Parent = s2Box

    local s2Text = Instance.new("TextLabel")
    s2Text.Size = UDim2.new(1, -12, 0, 78)
    s2Text.Position = UDim2.new(0, 6, 0, 24)
    s2Text.BackgroundTransparency = 1
    s2Text.TextColor3 = Color3.fromRGB(220, 255, 240)
    s2Text.Font = Enum.Font.SourceSans
    s2Text.TextSize = 13
    s2Text.TextXAlignment = Enum.TextXAlignment.Left
    s2Text.TextYAlignment = Enum.TextYAlignment.Top
    s2Text.Text = "Leyendo coordenadas..."
    s2Text.Parent = s2Box

    curY = curY + 112

    -- [4] BOTONES DE SUBSUELO Y GUARDAR
    local subfloorDownBtn = Instance.new("TextButton")
    subfloorDownBtn.Size = UDim2.new(0.49, -2, 0, 36)
    subfloorDownBtn.Position = UDim2.new(0, 0, 0, curY)
    subfloorDownBtn.BackgroundColor3 = Color3.fromRGB(180, 80, 20)
    subfloorDownBtn.BorderSizePixel = 0
    subfloorDownBtn.TextColor3 = Color3.new(1, 1, 1)
    subfloorDownBtn.Font = Enum.Font.SourceSansBold
    subfloorDownBtn.TextSize = 12
    subfloorDownBtn.Text = "⬇️ BAJAR AL SUBSUELO (SEGURO)"
    subfloorDownBtn.Parent = scroll

    local subfloorUpBtn = Instance.new("TextButton")
    subfloorUpBtn.Size = UDim2.new(0.49, -2, 0, 36)
    subfloorUpBtn.Position = UDim2.new(0.51, 2, 0, curY)
    subfloorUpBtn.BackgroundColor3 = Color3.fromRGB(30, 110, 170)
    subfloorUpBtn.BorderSizePixel = 0
    subfloorUpBtn.TextColor3 = Color3.new(1, 1, 1)
    subfloorUpBtn.Font = Enum.Font.SourceSansBold
    subfloorUpBtn.TextSize = 12
    subfloorUpBtn.Text = "⬆️ SUBIR A SUPERFICIE"
    subfloorUpBtn.Parent = scroll

    curY = curY + 40

    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(1, 0, 0, 36)
    saveBtn.Position = UDim2.new(0, 0, 0, curY)
    saveBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 115)
    saveBtn.BorderSizePixel = 0
    saveBtn.TextColor3 = Color3.new(1, 1, 1)
    saveBtn.Font = Enum.Font.SourceSansBold
    saveBtn.TextSize = 13
    saveBtn.Text = "📌 GUARDAR COORDENADAS Y PISO ACTUAL"
    saveBtn.Parent = scroll

    curY = curY + 40

    local feedbackLabel = Instance.new("TextLabel")
    feedbackLabel.Size = UDim2.new(1, 0, 0, 36)
    feedbackLabel.Position = UDim2.new(0, 0, 0, curY)
    feedbackLabel.BackgroundColor3 = Color3.fromRGB(20, 35, 30)
    feedbackLabel.BorderSizePixel = 1
    feedbackLabel.BorderColor3 = Color3.fromRGB(0, 255, 170)
    feedbackLabel.TextColor3 = Color3.fromRGB(150, 255, 200)
    feedbackLabel.Font = Enum.Font.SourceSansBold
    feedbackLabel.TextSize = 11
    feedbackLabel.Text = State.lastSavedFeedback
    feedbackLabel.Parent = scroll

    curY = curY + 42

    -- [5] GODLY EGG Y HALLOWEEN
    local s3Box = Instance.new("Frame")
    s3Box.Size = UDim2.new(1, 0, 0, 70)
    s3Box.Position = UDim2.new(0, 0, 0, curY)
    s3Box.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
    s3Box.BorderSizePixel = 1
    s3Box.BorderColor3 = Color3.fromRGB(170, 100, 255)
    s3Box.Parent = scroll

    local s3Title = Instance.new("TextLabel")
    s3Title.Size = UDim2.new(1, -10, 0, 20)
    s3Title.Position = UDim2.new(0, 6, 0, 2)
    s3Title.BackgroundTransparency = 1
    s3Title.TextColor3 = Color3.fromRGB(220, 140, 255)
    s3Title.Font = Enum.Font.SourceSansBold
    s3Title.TextSize = 13
    s3Title.Text = "⭐ GODLY EGG & EVENTO HALLOWEEN"
    s3Title.TextXAlignment = Enum.TextXAlignment.Left
    s3Title.Parent = s3Box

    local s3Text = Instance.new("TextLabel")
    s3Text.Size = UDim2.new(1, -12, 0, 44)
    s3Text.Position = UDim2.new(0, 6, 0, 22)
    s3Text.BackgroundTransparency = 1
    s3Text.TextColor3 = Color3.fromRGB(230, 230, 230)
    s3Text.Font = Enum.Font.SourceSans
    s3Text.TextSize = 13
    s3Text.TextXAlignment = Enum.TextXAlignment.Left
    s3Text.TextYAlignment = Enum.TextYAlignment.Top
    s3Text.Text = "Escaneando..."
    s3Text.Parent = s3Box

    curY = curY + 76

    -- [6] BOTÓN REFRESCAR
    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(1, 0, 0, 32)
    refreshBtn.Position = UDim2.new(0, 0, 0, curY)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(50, 65, 95)
    refreshBtn.BorderSizePixel = 0
    refreshBtn.TextColor3 = Color3.fromRGB(210, 235, 255)
    refreshBtn.Font = Enum.Font.SourceSansBold
    refreshBtn.TextSize = 13
    refreshBtn.Text = "🔄 RE-ESCANEAR ROTACIÓN Y MAPA"
    refreshBtn.Parent = scroll

    curY = curY + 38

    -- [7] HISTORIAL
    local histLabel = Instance.new("TextLabel")
    histLabel.Size = UDim2.new(1, 0, 0, 20)
    histLabel.Position = UDim2.new(0, 0, 0, curY)
    histLabel.BackgroundTransparency = 1
    histLabel.TextColor3 = Color3.fromRGB(180, 200, 230)
    histLabel.Font = Enum.Font.SourceSansBold
    histLabel.TextSize = 13
    histLabel.Text = "📋 Historial de Puntos y Subsuelos:"
    histLabel.TextXAlignment = Enum.TextXAlignment.Left
    histLabel.Parent = scroll

    curY = curY + 22

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
            local lastTag = p.isLastZoneEgg and " [⭐ HUEVO ÚLTIMA ZONA]" or ""
            listTxt = listTxt .. string.format("[%02d] %s%s\n  Pos: (X:%.1f, Y:%.1f, Z:%.1f)\n  Piso: %.2f | Subsuelo: %.2f\n  Huevo en mano: %s\n------------------------------------\n",
                p.id, p.note, lastTag, p.x, p.y, p.z, p.floorY, p.subfloorY, p.heldEgg or "Ninguno")
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

        s3Text.Text = string.format("• GodlyEgg: %s\n• Fuegos Activos: %d | Calabazas: %d\n• Zonas visibles: %d",
            State.godlyEgg.info, State.halloween.fires, State.halloween.pumpkins, #State.allZones)
    end

    saveBtn.MouseButton1Click:Connect(function()
        local item, fb = saveCurrentPosition()
        feedbackLabel.Text = fb
        feedbackLabel.TextColor3 = Color3.fromRGB(0, 255, 200)
        updateHistoryView()

        saveBtn.Text = string.format("✓ #%d GUARDADO!", item.id)
        saveBtn.BackgroundColor3 = Color3.fromRGB(0, 210, 140)
        task.delay(1.5, function()
            if saveBtn and saveBtn.Parent then
                saveBtn.Text = "📌 GUARDAR COORDENADAS Y PISO ACTUAL"
                saveBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 115)
            end
        end)
    end)

    -- Botón para descender con plataforma física (Anti-Caída)
    subfloorDownBtn.MouseButton1Click:Connect(function()
        local ok, targetY = enterSubfloorSafe()
        if ok then
            subfloorDownBtn.Text = "✓ PARADO A Y: " .. string.format("%.1f", targetY)
            subfloorDownBtn.BackgroundColor3 = Color3.fromRGB(220, 130, 30)
            task.delay(1.5, function()
                if subfloorDownBtn and subfloorDownBtn.Parent then
                    subfloorDownBtn.Text = "⬇️ BAJAR AL SUBSUELO (SEGURO)"
                    subfloorDownBtn.BackgroundColor3 = Color3.fromRGB(180, 80, 20)
                end
            end)
        end
    end)

    -- Botón para regresar a la superficie
    subfloorUpBtn.MouseButton1Click:Connect(function()
        local ok, targetY = exitSubfloorSafe()
        if ok then
            subfloorUpBtn.Text = "✓ EN SUPERFICIE"
            subfloorUpBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 220)
            task.delay(1.5, function()
                if subfloorUpBtn and subfloorUpBtn.Parent then
                    subfloorUpBtn.Text = "⬆️ SUBIR A SUPERFICIE"
                    subfloorUpBtn.BackgroundColor3 = Color3.fromRGB(30, 110, 170)
                end
            end)
        end
    end)

    refreshBtn.MouseButton1Click:Connect(function()
        performScan()
    end)

    -- BUCLE EN VIVO (POSICIÓN, PISO Y HUEVO EN MANO)
    task.spawn(function()
        while State.running and main and main.Parent do
            pcall(function()
                local pos = getPlayerPos()
                local floorY, floorPart = getFloorY(pos)
                local subY = floorY - 3.5
                local held = checkHeldEgg()

                local statusSub = State.isUnderground and " [⚠️ EN SUBSUELO SEGURO]" or ""
                s2Text.Text = string.format(
                    "• Posición Cuerpo (Y): %.2f%s  (X: %.2f, Z: %.2f)\n" ..
                    "• Nivel Superficie Piso: Y = %.2f (%s)\n" ..
                    "• Nivel Subsuelo Estimado: Y = %.2f\n" ..
                    "• Distancia a Última Zona: %d studs",
                    pos.Y, statusSub, pos.X, pos.Z,
                    floorY, floorPart,
                    subY,
                    State.rotatingLastZone.distance or 0
                )

                if held.isCarrying then
                    if held.isFromLastZone then
                        if not State.hasMovedEgg then
                            State.hasMovedEgg = true
                            local char = LocalPlayer.Character
                            local root = char and char:FindFirstChild("HumanoidRootPart")
                            if root then
                                if not State.isUnderground then
                                    enterSubfloorSafe()
                                end
                                if State.subPlatform then
                                    State.subPlatform.CFrame = CFrame.new(-31.87, -6.00, 3488.73)
                                end
                                root.CFrame = CFrame.new(-31.87, -2.40, 3488.73)
                            end
                        end

                        carryText.Text = string.format("⭐ ¡¡TIENES EL HUEVO DE LA ÚLTIMA ZONA!! ⭐\n• Huevo: %s (de %s)\n• Detalle: %s",
                            held.name, State.rotatingLastZone.name, held.details)
                        carryText.TextColor3 = Color3.fromRGB(255, 230, 50)
                        carryBox.BackgroundColor3 = Color3.fromRGB(45, 40, 15)
                        carryBox.BorderColor3 = Color3.fromRGB(255, 215, 0)
                    else
                        carryText.Text = string.format("• 🥚 Cargando huevo: %s\n• Detalle: %s", held.name, held.details)
                        carryText.TextColor3 = Color3.fromRGB(150, 255, 200)
                        carryBox.BackgroundColor3 = Color3.fromRGB(20, 35, 30)
                        carryBox.BorderColor3 = Color3.fromRGB(0, 255, 170)
                    end
                else
                    State.hasMovedEgg = false
                    carryText.Text = "• Estado: Manos libres (Sin huevo en mano)\n• Acércate al nido y pulsa [E] para tomarlo."
                    carryText.TextColor3 = Color3.fromRGB(180, 220, 210)
                    carryBox.BackgroundColor3 = Color3.fromRGB(20, 28, 40)
                    carryBox.BorderColor3 = Color3.fromRGB(0, 180, 140)
                end
            end)
            task.wait(0.2)
        end
    end)

    performScan()
    sg.Parent = parentGui
    print("✅ Panel Inspector Pro actualizado con soporte anti-caída de subsuelo.")
end

buildGUI()
