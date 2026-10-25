--[[
    Auditoría pasiva del cliente Roblox (Luau / Delta)

    Uso autorizado: ejecútalo únicamente en experiencias que controles o para
    las que tengas autorización expresa. No decompila ni copia Source de scripts,
    no intercepta tráfico y no modifica instancias del juego. Sólo inventaría lo
    que el cliente ya puede ver y guarda un informe local.

    Limitación importante: los ServerScriptService, ServerStorage y las
    validaciones del servidor no son auditables desde un cliente. Una ausencia
    en este informe nunca prueba que exista o no exista una protección.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local SETTINGS = {
    outputFolder = "Roblox_Auditoria_Cliente",
    checkpointEvery = 250,     -- guarda avances cada N instancias exploradas
    maxListedItems = 20000,    -- evita informes inutilizables en juegos muy grandes
    valuePreviewLength = 180,
}

local state = {
    running = false,
    allLines = {},
    pendingLines = {},
    reportPath = nil,
    reportId = nil,
    canWrite = type(writefile) == "function",
    canAppend = type(appendfile) == "function",
    ui = {},
}

local function nowForFile()
    return os.date("!%Y-%m-%d_%H-%M-%S")
end

local function timestamp()
    return os.date("!%Y-%m-%d %H:%M:%S UTC")
end

local function oneLine(value)
    value = tostring(value or "")
    value = value:gsub("[\r\n\t]", " ")
    value = value:gsub("%s+", " ")
    return value
end

local function getPath(instance)
    local ok, path = pcall(function()
        return instance:GetFullName()
    end)
    return ok and path or ("<ruta no disponible: " .. oneLine(instance.Name) .. ">")
end

local function setStatus(text, color)
    if state.ui.status then
        state.ui.status.Text = text
        if color then
            state.ui.status.TextColor3 = color
        end
    end
end

local function writeRaw(path, text)
    if not state.canWrite then
        return false, "writefile no está disponible en este entorno"
    end
    local ok, err = pcall(writefile, path, text)
    return ok, err
end

local function ensureFolder()
    if not state.canWrite then
        return false
    end
    if type(makefolder) == "function" then
        local exists = false
        if type(isfolder) == "function" then
            pcall(function()
                exists = isfolder(SETTINGS.outputFolder)
            end)
        end
        if not exists then
            -- Si la carpeta ya existe, la mayoría de ejecutores devuelven un
            -- error inofensivo; el writefile posterior confirma el resultado.
            pcall(makefolder, SETTINGS.outputFolder)
        end
    end
    return true
end

local function flushAuto(reason)
    if #state.pendingLines == 0 then
        return
    end
    if not state.reportPath or not state.canWrite then
        return
    end

    local chunk = table.concat(state.pendingLines, "\n") .. "\n"
    local ok
    if state.canAppend then
        ok = pcall(appendfile, state.reportPath, chunk)
    end
    if not ok then
        -- Algunos ejecutores sólo exponen writefile. Reescribir el informe completo
        -- o fallan en appendfile conserva todo lo registrado hasta el último punto.
        ok = pcall(writefile, state.reportPath, table.concat(state.allLines, "\n") .. "\n")
    end
    if ok then
        table.clear(state.pendingLines)
    end
end

local function log(line)
    line = oneLine(line)
    table.insert(state.allLines, line)
    table.insert(state.pendingLines, line)
end

local function beginReport()
    state.allLines = {}
    state.pendingLines = {}
    state.reportId = nowForFile() .. "_" .. string.sub(HttpService:GenerateGUID(false):gsub("-", ""), 1, 8)
    state.reportPath = SETTINGS.outputFolder .. "/auditoria_cliente_" .. state.reportId .. ".txt"

    log("============================================================")
    log("AUDITORÍA PASIVA DEL CLIENTE ROBLOX")
    log("Inicio: " .. timestamp())
    log("Jugador local: " .. oneLine(LocalPlayer and LocalPlayer.Name or "no disponible"))
    log("Lugar: " .. tostring(game.PlaceId) .. " | JobId: " .. oneLine(game.JobId))
    log("Alcance: instancias y metadatos visibles por este cliente.")
    log("No se lee Source, no se decompila código, no se altera el juego.")
    log("ADVERTENCIA: este informe no puede confirmar seguridad del servidor.")
    log("============================================================")

    if ensureFolder() then
        local ok, err = writeRaw(state.reportPath, table.concat(state.allLines, "\n") .. "\n")
        if ok then
            table.clear(state.pendingLines)
            return true
        end
        log("[AVISO] No se pudo crear el archivo inicial: " .. oneLine(err))
    else
        log("[AVISO] Guardado local no disponible; el informe sólo existirá mientras el cliente siga abierto.")
    end
    return false
end

local noisyClasses = {
    Part = true, MeshPart = true, UnionOperation = true, Terrain = true,
    Decal = true, Texture = true, Attachment = true, Bone = true,
    Sound = true, ParticleEmitter = true, Trail = true, Beam = true,
    SpecialMesh = true, WrapLayer = true, WrapTarget = true,
}

local relevantClasses = {
    RemoteEvent = "REMOTE_EVENT",
    RemoteFunction = "REMOTE_FUNCTION",
    UnreliableRemoteEvent = "UNRELIABLE_REMOTE",
    BindableEvent = "BINDABLE_EVENT",
    BindableFunction = "BINDABLE_FUNCTION",
    ModuleScript = "MODULE_VISIBLE",
    LocalScript = "LOCAL_SCRIPT_META",
    Script = "SCRIPT_META",
    Configuration = "CONFIGURATION",
    BoolValue = "CONFIG_VALUE",
    NumberValue = "CONFIG_VALUE",
    IntValue = "CONFIG_VALUE",
    StringValue = "CONFIG_VALUE",
    ObjectValue = "OBJECT_REFERENCE",
    Folder = "FOLDER_FLAGGED",
}

local function suspiciousName(name)
    local lower = string.lower(name)
    return lower:find("honeypot", 1, true)
        or lower:find("decoy", 1, true)
        or lower:find("canary", 1, true)
        or lower:find("trap", 1, true)
        or lower:find("bait", 1, true)
end

local function sensitiveName(name)
    local lower = string.lower(name)
    return lower:find("password", 1, true)
        or lower:find("secret", 1, true)
        or lower:find("token", 1, true)
        or lower:find("apikey", 1, true)
        or lower:find("api_key", 1, true)
end

local function previewValue(instance)
    if sensitiveName(instance.Name) then
        return "<oculto: nombre sensible>"
    end
    local ok, value = pcall(function()
        return instance.Value
    end)
    if not ok then
        return "<no legible>"
    end
    if typeof(value) == "Instance" then
        return value and getPath(value) or "nil"
    end
    local text = oneLine(value)
    if #text > SETTINGS.valuePreviewLength then
        text = string.sub(text, 1, SETTINGS.valuePreviewLength) .. "…"
    end
    return text
end

local function attributeNames(instance)
    local ok, attributes = pcall(function()
        return instance:GetAttributes()
    end)
    if not ok then
        return ""
    end
    local names = {}
    for name in pairs(attributes) do
        table.insert(names, name)
    end
    table.sort(names)
    return #names > 0 and (" | atributos=" .. table.concat(names, ",")) or ""
end

local function includeInstance(instance)
    if relevantClasses[instance.ClassName] then
        if instance:IsA("Folder") then
            return suspiciousName(instance.Name) or instance:GetAttribute("SecurityRelevant") == true
        end
        return true
    end
    if noisyClasses[instance.ClassName] then
        return false
    end
    return suspiciousName(instance.Name)
end

local function describeInstance(instance, rootLabel)
    local tag = relevantClasses[instance.ClassName] or "NOMBRE_SOSPECHOSO"
    local extras = attributeNames(instance)

    if suspiciousName(instance.Name) then
        extras = extras .. " | POSIBLE_SEÑUELO_POR_NOMBRE=true"
    end

    if instance:IsA("ValueBase") then
        extras = extras .. " | valor=" .. previewValue(instance)
    elseif instance:IsA("BaseScript") then
        local ok, disabled = pcall(function()
            return instance.Disabled
        end)
        extras = extras .. " | disabled=" .. tostring(ok and disabled or "no legible")
    elseif instance:IsA("ObjectValue") then
        extras = extras .. " | destino=" .. previewValue(instance)
    end

    return string.format("[%s] raíz=%s | clase=%s | ruta=%s%s", tag, rootLabel, instance.ClassName, getPath(instance), extras)
end

local function getService(name)
    local ok, service = pcall(game.GetService, game, name)
    return ok and service or nil
end

local function addLoadedModules(summary)
    if type(getloadedmodules) ~= "function" then
        log("[INFO] getloadedmodules no está disponible; sólo se listan ModuleScripts visibles.")
        return
    end

    local ok, modules = pcall(getloadedmodules)
    if not ok or type(modules) ~= "table" then
        log("[AVISO] No se pudieron consultar módulos cargados en el cliente.")
        return
    end

    local unique = {}
    for _, module in ipairs(modules) do
        if typeof(module) == "Instance" and module:IsA("ModuleScript") then
            unique[module] = true
        end
    end
    local list = {}
    for module in pairs(unique) do
        table.insert(list, getPath(module))
    end
    table.sort(list)
    summary.loadedModules = #list
    log("--- MÓDULOS CARGADOS EN ESTE CLIENTE (no representa dependencias require) ---")
    for _, path in ipairs(list) do
        log("[MODULE_LOADED] " .. path)
    end
end

local function scanRoot(root, label, summary)
    if not root then
        log("[NO_DISPONIBLE] " .. label)
        return
    end

    local ok, descendants = pcall(function()
        return root:GetDescendants()
    end)
    if not ok then
        log("[NO_LEGIBLE] " .. label)
        return
    end

    log("--- RAÍZ " .. label .. " | descendientes observables=" .. tostring(#descendants) .. " ---")
    for index, instance in ipairs(descendants) do
        summary.examined = summary.examined + 1
        if includeInstance(instance) then
            if summary.listed < SETTINGS.maxListedItems then
                log(describeInstance(instance, label))
                summary.listed = summary.listed + 1
            else
                summary.truncated = true
            end

            if instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction") or instance:IsA("UnreliableRemoteEvent") then
                summary.remotes = summary.remotes + 1
            elseif instance:IsA("ModuleScript") then
                summary.modules = summary.modules + 1
            elseif instance:IsA("LocalScript") then
                summary.localScripts = summary.localScripts + 1
            elseif instance:IsA("ObjectValue") then
                summary.references = summary.references + 1
            elseif suspiciousName(instance.Name) then
                summary.honeypotCandidates = summary.honeypotCandidates + 1
            end
        end

        if index % SETTINGS.checkpointEvery == 0 then
            flushAuto("checkpoint")
            setStatus(string.format("Escaneando %s: %d/%d", label, index, #descendants), Color3.fromRGB(255, 217, 102))
            task.wait()
        end
    end
end

local function appendInterpretation(summary)
    log("============================================================")
    log("RESUMEN")
    log("Instancias examinadas: " .. summary.examined)
    log("Elementos relevantes listados: " .. summary.listed .. (summary.truncated and " (LÍMITE ALCANZADO)" or ""))
    log("Remotes visibles: " .. summary.remotes)
    log("ModuleScripts visibles: " .. summary.modules)
    log("Módulos cargados en cliente: " .. (summary.loadedModules or 0))
    log("LocalScripts visibles: " .. summary.localScripts)
    log("Referencias ObjectValue: " .. summary.references)
    log("Candidatos a honeypot por nombre: " .. summary.honeypotCandidates)
    log("============================================================")
    log("LECTURA PROFESIONAL / LÍMITES")
    log("- Un Remote listado es una frontera cliente-servidor que debe validar tipo, rango, permisos y frecuencia EN EL SERVIDOR.")
    log("- Un nombre como honeypot, decoy, canary, trap o bait sólo es una pista nominal; no confirma comportamiento de señuelo.")
    log("- Un ModuleScript visible no revela quién lo require ni su código. Este informe evita recuperar Source deliberadamente.")
    log("- Las ObjectValue muestran relaciones de datos explícitas, no conexiones de funciones ni dependencias implícitas.")
    log("- Ausencia de ServerScriptService/ServerStorage es esperable desde cliente y no es una anomalía.")
    log("- Para auditar validaciones y dependencias reales, exporta tu experiencia autorizada y revisa el código de servidor fuera del cliente.")
    log("Fin: " .. timestamp())
end

local function runScan()
    beginReport()
    local summary = {
        examined = 0, listed = 0, remotes = 0, modules = 0,
        localScripts = 0, references = 0, honeypotCandidates = 0,
        loadedModules = 0, truncated = false,
    }

    log("--- INVENTARIO DE SERVICIOS / CONEXIONES OBSERVABLES ---")
    local roots = {
        { "ReplicatedFirst", getService("ReplicatedFirst") },
        { "ReplicatedStorage", getService("ReplicatedStorage") },
        { "StarterGui", getService("StarterGui") },
        { "StarterPlayer", getService("StarterPlayer") },
        { "PlayerGui", LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui") },
        { "Workspace", workspace },
        { "Lighting", getService("Lighting") },
        { "SoundService", getService("SoundService") },
        { "TextChatService", getService("TextChatService") },
    }

    for _, entry in ipairs(roots) do
        scanRoot(entry[2], entry[1], summary)
    end
    addLoadedModules(summary)
    appendInterpretation(summary)
    flushAuto("final")

    if state.canWrite and state.reportPath then
        setStatus("Escaneo terminado. Informe: " .. state.reportPath, Color3.fromRGB(111, 207, 151))
    else
        setStatus("Escaneo terminado, pero este ejecutor no permitió guardar el TXT.", Color3.fromRGB(255, 180, 100))
    end
end

local function saveCopy()
    if #state.allLines == 0 then
        setStatus("Aún no hay resultados para guardar.", Color3.fromRGB(255, 180, 100))
        return
    end
    if not ensureFolder() then
        setStatus("writefile/makefolder no está disponible.", Color3.fromRGB(255, 120, 120))
        return
    end
    local copyPath = SETTINGS.outputFolder .. "/auditoria_guardada_" .. nowForFile() .. ".txt"
    local ok, err = writeRaw(copyPath, table.concat(state.allLines, "\n") .. "\n")
    if ok then
        setStatus("Copia guardada: " .. copyPath, Color3.fromRGB(111, 207, 151))
    else
        setStatus("No se pudo guardar: " .. oneLine(err), Color3.fromRGB(255, 120, 120))
    end
end

local function makeButton(parent, text, position, color)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(130, 32)
    button.Position = position
    button.BackgroundColor3 = color
    button.BorderSizePixel = 0
    button.Font = Enum.Font.GothamSemibold
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextSize = 13
    button.Text = text
    button.Parent = parent
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)
    return button
end

local function createGui()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("AuditoriaClienteGui")
    if existing then
        existing:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "AuditoriaClienteGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.Size = UDim2.fromOffset(360, 160)
    frame.Position = UDim2.new(0, 18, 0.5, -80)
    frame.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -24, 0, 28)
    title.Position = UDim2.fromOffset(12, 8)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "Auditoría pasiva del cliente"
    title.TextColor3 = Color3.fromRGB(235, 240, 255)
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local description = Instance.new("TextLabel")
    description.Size = UDim2.new(1, -24, 0, 42)
    description.Position = UDim2.fromOffset(12, 37)
    description.BackgroundTransparency = 1
    description.Font = Enum.Font.Gotham
    description.Text = "Inventario de metadatos visibles. El detalle se escribe automáticamente en un TXT, no en esta ventana."
    description.TextColor3 = Color3.fromRGB(180, 190, 210)
    description.TextSize = 12
    description.TextWrapped = true
    description.TextXAlignment = Enum.TextXAlignment.Left
    description.TextYAlignment = Enum.TextYAlignment.Top
    description.Parent = frame

    local scanButton = makeButton(frame, "Escanear", UDim2.fromOffset(12, 89), Color3.fromRGB(42, 113, 186))
    local saveButton = makeButton(frame, "Guardar copia", UDim2.fromOffset(151, 89), Color3.fromRGB(73, 137, 92))
    local closeButton = makeButton(frame, "Cerrar", UDim2.fromOffset(290, 89), Color3.fromRGB(122, 65, 75))
    closeButton.Size = UDim2.fromOffset(58, 32)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -24, 0, 25)
    status.Position = UDim2.fromOffset(12, 128)
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.Gotham
    status.Text = "Listo. El TXT se guarda en Roblox_Auditoria_Cliente/."
    status.TextColor3 = Color3.fromRGB(180, 190, 210)
    status.TextSize = 11
    status.TextTruncate = Enum.TextTruncate.AtEnd
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame
    state.ui.status = status

    scanButton.MouseButton1Click:Connect(function()
        if state.running then
            setStatus("Ya hay un escaneo en curso.", Color3.fromRGB(255, 217, 102))
            return
        end
        state.running = true
        setStatus("Preparando informe…", Color3.fromRGB(255, 217, 102))
        task.spawn(function()
            local ok, err = pcall(runScan)
            if not ok then
                log("[ERROR_DE_ESCANEO] " .. oneLine(err))
                flushAuto("error")
                setStatus("El escaneo se interrumpió; se guardó el avance disponible.", Color3.fromRGB(255, 120, 120))
            end
            state.running = false
        end)
    end)

    saveButton.MouseButton1Click:Connect(saveCopy)
    closeButton.MouseButton1Click:Connect(function()
        gui:Destroy()
    end)

    -- Arrastre sencillo del panel; no depende de APIs del ejecutor.
    local dragging, dragStart, startPosition
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPosition = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
end

createGui()
