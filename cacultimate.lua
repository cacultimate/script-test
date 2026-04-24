--[[
    CAC ULTIMATE SUITE - V4.5.4 (AUTO REJOIN SERVER HOP HOTFIX)
    Feature: Files > 9.5MB are saved locally to 'ROOT/dumps'.
    Engine: Hybrid R6/R15 + Heavy Duty Logic + 100MB Fix + Premium UI.
    Language: English Only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

-- Fast boot guard: some executors inject before the client finishes creating
-- LocalPlayer/PlayerGui. In normal runs this exits instantly.
do
    local bootDeadline = os.clock() + 6
    while not LocalPlayer and os.clock() < bootDeadline do
        task.wait(0.03)
        LocalPlayer = Players.LocalPlayer
    end
    if LocalPlayer and not LocalPlayer:FindFirstChild("PlayerGui") then
        pcall(function()
            LocalPlayer:WaitForChild("PlayerGui", 3)
        end)
    end
end

-- Executor Compatibility
local http_request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

-- NEW HWID GENERATOR (Forces persistent UUID to avoid resets on executor switch)
local function gethwid()
    local hwid_filename = "cac_ultimate_hwid_v4.txt"
    
    -- Check if the executor supports file read/write operations
    if isfile and readfile and writefile then
        -- If the file already exists, read the saved UUID
        if isfile(hwid_filename) then
            local saved_hwid = readfile(hwid_filename)
            -- Clear any potential whitespaces
            return saved_hwid:gsub("%s+", "")
        else
            -- If it doesn't exist, generate a new UUID in the format ac699ec0-a658...
            -- The 'false' parameter removes the default {} brackets from GenerateGUID
            local new_uuid = HttpService:GenerateGUID(false) 
            
            -- Save this new UUID to the file so it remains permanent
            pcall(function()
                writefile(hwid_filename, new_uuid)
            end)
            
            return new_uuid
        end
    else
        -- Security fallback if the executor is too weak and lacks writefile support
        return HttpService:GenerateGUID(false)
    end
end

local raw_saveinstance = saveinstance
local saveinstance = raw_saveinstance or function() error("SaveInstance not supported", 0) end
local listfiles = listfiles or function(...) return {} end
local isfile = isfile or function(f) return false end
local readfile = readfile or function(f) return "" end
local delfile = delfile or function(f) end
local writefile = writefile or function(f, c) end
local appendfile = appendfile or function(f, c) end
local makefolder = makefolder or function(f) end
local isfolder = isfolder or function(f) return false end

local function DetectExecutorName()
    local probes = {
        function()
            if identifyexecutor then
                return identifyexecutor()
            end
        end,
        function()
            if getexecutorname then
                return getexecutorname()
            end
        end,
        function()
            if getexecutor then
                return getexecutor()
            end
        end
    }

    for _, probe in ipairs(probes) do
        local ok, name = pcall(probe)
        if ok and name and tostring(name) ~= "" then
            return tostring(name)
        end
    end

    local hints = {
        { "Wave", function() return wave or Wave end },
        { "Xeno", function() return xeno or Xeno end },
        { "Synapse", function() return syn end },
        { "Fluxus", function() return fluxus end },
        { "Krnl", function() return KRNL_LOADED or krnl end },
        { "Codex", function() return Codex or codex end },
        { "Potassium", function() return Potassium or potassium end },
        { "Cosmic", function() return Cosmic or cosmic end },
        { "Volt", function() return Volt or volt end }
    }

    for _, hint in ipairs(hints) do
        local ok, value = pcall(hint[2])
        if ok and value then
            return hint[1]
        end
    end

    return "Unknown"
end

local ExecutorName = DetectExecutorName()

-- [DYNAMIC FOLDER DETECTION]
local function DetectExecutorRoot()
    if isfolder("workspace") then return "workspace" end
    if isfolder("Workspace") then return "Workspace" end
    return "CAC_Output" 
end

local DetectedRoot = DetectExecutorRoot()
local AUTO_REJOIN_MODE = "public"
local MAXIMIZE_REJOIN_SUCCESS_THRESHOLD = 5

-- CONFIGURATION STATE
local Globals = {
    WebhookURL = "",
    WorkFolder = DetectedRoot,
    DumpsFolder = DetectedRoot .. "/dumps",
    QueueFolder = DetectedRoot .. "/queue",
    IsAuthenticated = false,
    CurrentDumperName = "Unknown",
    CurrentSessionID = "",
    UserKey = "",
    CurrentUser = nil,
    SessionToken = "",
    SessionExpiresAtISO = nil,
    LicenseExpiresAt = nil,
    LicenseStatus = "unknown",
    LicensePlan = "default",
    RevalidateAfter = 60,
    UIUnlocked = false,
    AutoRejoinCodeEnabled = false,
    AutoRejoinCodeMode = AUTO_REJOIN_MODE,
    AutoRejoinPublishEnabled = false,
    AutoRejoinPublishMode = AUTO_REJOIN_MODE,
    AutoCopyAutoPublishResults = true,
    AutoPublishNamePrefix = "CAC",
    AutoPublishWaitSeconds = 0.65,
    MaximizeAutoRejoin = false,
    QueueFastResumeEnabled = true
}

-- Ensure workspace folders exist
if not isfolder(Globals.WorkFolder) then makefolder(Globals.WorkFolder) end
if not isfolder(Globals.DumpsFolder) then makefolder(Globals.DumpsFolder) end
if not isfolder(Globals.QueueFolder) then makefolder(Globals.QueueFolder) end

-- LOCAL CACHE MANAGER (Saves Key & Webhook)
local CachePath = Globals.WorkFolder .. "/CAC_Config.json"
local LocalCache = {
    Key = "",
    Webhook = "",
    AutoLoginDisabled = false,
    AutoRejoinCodeEnabled = false,
    AutoRejoinCodeMode = AUTO_REJOIN_MODE,
    AutoRejoinPublishEnabled = false,
    AutoRejoinPublishMode = AUTO_REJOIN_MODE,
    AutoCopyAutoPublishResults = true,
    AutoPublishNamePrefix = "CAC",
    AutoPublishWaitSeconds = 0.65,
    MaximizeAutoRejoin = false,
    QueueFastResumeEnabled = true,
    SessionToken = "",
    SessionExpiresAtISO = nil,
    RevalidateAfter = 60,
    LicenseExpiresAt = nil,
    LicenseStatus = "unknown",
    LicensePlan = "default",
    LastAuthAt = 0
}

pcall(function()
    if isfile(CachePath) then
        local data = HttpService:JSONDecode(readfile(CachePath))
        if data then LocalCache = data end
        if LocalCache.AutoLoginDisabled == nil then
            LocalCache.AutoLoginDisabled = false
        end
        if LocalCache.AutoRejoinCodeEnabled == nil then
            if LocalCache.AutoRejoinEnabled ~= nil then
                LocalCache.AutoRejoinCodeEnabled = LocalCache.AutoRejoinEnabled == true
            else
                LocalCache.AutoRejoinCodeEnabled = false
            end
        end
        if LocalCache.AutoRejoinCodeMode == nil or tostring(LocalCache.AutoRejoinCodeMode) == "" then
            if LocalCache.AutoRejoinMode ~= nil and tostring(LocalCache.AutoRejoinMode) ~= "" then
                LocalCache.AutoRejoinCodeMode = tostring(LocalCache.AutoRejoinMode)
            else
                LocalCache.AutoRejoinCodeMode = AUTO_REJOIN_MODE
            end
        end
        if LocalCache.AutoRejoinPublishEnabled == nil then
            if LocalCache.AutoRejoinEnabled ~= nil then
                LocalCache.AutoRejoinPublishEnabled = LocalCache.AutoRejoinEnabled == true
            else
                LocalCache.AutoRejoinPublishEnabled = false
            end
        end
        if LocalCache.AutoRejoinPublishMode == nil or tostring(LocalCache.AutoRejoinPublishMode) == "" then
            if LocalCache.AutoRejoinMode ~= nil and tostring(LocalCache.AutoRejoinMode) ~= "" then
                LocalCache.AutoRejoinPublishMode = tostring(LocalCache.AutoRejoinMode)
            else
                LocalCache.AutoRejoinPublishMode = AUTO_REJOIN_MODE
            end
        end
        if LocalCache.AutoCopyAutoPublishResults == nil then
            LocalCache.AutoCopyAutoPublishResults = true
        end
        if LocalCache.AutoPublishNamePrefix == nil or tostring(LocalCache.AutoPublishNamePrefix) == "" then
            LocalCache.AutoPublishNamePrefix = "CAC"
        end
        if LocalCache.AutoPublishWaitSeconds == nil then
            LocalCache.AutoPublishWaitSeconds = 0.65
        end
        if LocalCache.MaximizeAutoRejoin == nil then
            LocalCache.MaximizeAutoRejoin = false
        end
        if LocalCache.QueueFastResumeEnabled == nil then
            LocalCache.QueueFastResumeEnabled = true
        end
        if LocalCache.Webhook then Globals.WebhookURL = LocalCache.Webhook end
        if LocalCache.Key and tostring(LocalCache.Key):gsub("%s+", "") ~= "" then
            Globals.UserKey = tostring(LocalCache.Key):gsub("%s+", "")
        end

        Globals.AutoRejoinCodeEnabled = LocalCache.AutoRejoinCodeEnabled == true
        Globals.AutoRejoinCodeMode = AUTO_REJOIN_MODE
        Globals.AutoRejoinPublishEnabled = LocalCache.AutoRejoinPublishEnabled == true
        Globals.AutoRejoinPublishMode = AUTO_REJOIN_MODE
        Globals.AutoCopyAutoPublishResults = LocalCache.AutoCopyAutoPublishResults == true
        Globals.AutoPublishNamePrefix = tostring(LocalCache.AutoPublishNamePrefix)
        Globals.AutoPublishWaitSeconds = tonumber(LocalCache.AutoPublishWaitSeconds) or 0.65
        Globals.MaximizeAutoRejoin = LocalCache.MaximizeAutoRejoin == true
        Globals.QueueFastResumeEnabled = LocalCache.QueueFastResumeEnabled ~= false
    end
end)

local function SaveLocalCache()
    LocalCache.AutoRejoinCodeEnabled = Globals.AutoRejoinCodeEnabled == true
    LocalCache.AutoRejoinCodeMode = AUTO_REJOIN_MODE
    LocalCache.AutoRejoinPublishEnabled = Globals.AutoRejoinPublishEnabled == true
    LocalCache.AutoRejoinPublishMode = AUTO_REJOIN_MODE
    -- Legacy compatibility fields (for old cached readers)
    LocalCache.AutoRejoinEnabled = LocalCache.AutoRejoinCodeEnabled or LocalCache.AutoRejoinPublishEnabled
    LocalCache.AutoRejoinMode = LocalCache.AutoRejoinCodeMode
    LocalCache.AutoCopyAutoPublishResults = Globals.AutoCopyAutoPublishResults == true
    LocalCache.AutoPublishNamePrefix = tostring(Globals.AutoPublishNamePrefix or "CAC")
    LocalCache.AutoPublishWaitSeconds = tonumber(Globals.AutoPublishWaitSeconds) or 0.65
    LocalCache.MaximizeAutoRejoin = Globals.MaximizeAutoRejoin == true
    LocalCache.QueueFastResumeEnabled = Globals.QueueFastResumeEnabled ~= false

    pcall(function()
        writefile(CachePath, HttpService:JSONEncode(LocalCache))
    end)
end

-- ==================================================================
-- CAC PREMIUM UI LIBRARY INIT
-- ==================================================================
-- ============================================================================
-- PUT YOUR LIBRARY RAW LINK HERE:
-- Example: https://raw.githubusercontent.com/USER/REPO/refs/heads/main/livraria.lua
-- ============================================================================
local LIBRARY_RAW_URL = "https://raw.githubusercontent.com/cacultimate/Library-Test/refs/heads/main/livraria.lua"

local function ResolveLibraryRawURL()
    local finalUrl = tostring(LIBRARY_RAW_URL or "")

    pcall(function()
        local env = (_G or {})
        if getgenv then
            env = getgenv()
        end
        local override = env and env.CAC_LIBRARY_RAW_URL
        if type(override) == "string" and override:find("^https?://") then
            finalUrl = override
        end
    end)

    return finalUrl
end

local function LoadCACLibrary()
    local rawUrl = ResolveLibraryRawURL()
    if rawUrl == "" then
        error("LIBRARY_RAW_URL is empty. Set your GitHub raw URL first.")
    end

    local okRemote, remoteSource = pcall(function()
        return game:HttpGet(rawUrl)
    end)
    if okRemote and type(remoteSource) == "string" and #remoteSource > 50 then
        local okCompile, compiled = pcall(function()
            return loadstring(remoteSource)
        end)
        if okCompile and type(compiled) == "function" then
            local okRun, lib = pcall(compiled)
            if okRun and type(lib) == "table" then
                return lib, rawUrl
            end
        end
    end

    error("Failed to load CAC UI library from GitHub raw: " .. tostring(rawUrl))
end

local CAC_UI, LibrarySource = LoadCACLibrary()

local BootHasPendingQueue = false
pcall(function()
    BootHasPendingQueue = isfile(Globals.QueueFolder .. "/CAC_TaskQueue.json") == true
end)

local BootCanFastResume = false
pcall(function()
    BootCanFastResume = BootHasPendingQueue
        and LocalCache.QueueFastResumeEnabled ~= false
        and tostring(LocalCache.SessionToken or "") ~= ""
        and ((tonumber(LocalCache.LastAuthAt) or 0) <= 0 or (os.time() - (tonumber(LocalCache.LastAuthAt) or 0)) <= 900)
end)

-- Create Floating Window (Loading runs INSIDE it)
local Window = CAC_UI:CreateWindow({
    Name = "CAC Ultimate",
    LoadingTitle = BootCanFastResume and "RESUMING QUEUE..." or "AUTHENTICATING...",
    Folder = Globals.WorkFolder,
    ToggleKey = Enum.KeyCode.K,
    SkipLoading = BootCanFastResume
})

local function Notify(title, content)
    Window:Notify({
        Title = title,
        Content = content,
        Duration = 4
    })
end

local function SafeWriteText(path, content)
    local candidateList = {
        tostring(path or ""),
        tostring(path or ""):gsub("\\", "/"),
        tostring(path or ""):gsub("/", "\\")
    }

    local payload = tostring(content or "")
    for _, candidate in ipairs(candidateList) do
        if candidate ~= "" then
            local ok = pcall(function()
                writefile(candidate, payload)
            end)
            if ok then
                return true, candidate
            end
        end
    end
    return false, nil
end

local function SafeReadText(path)
    local candidateList = {
        tostring(path or ""),
        tostring(path or ""):gsub("\\", "/"),
        tostring(path or ""):gsub("/", "\\")
    }
    for _, candidate in ipairs(candidateList) do
        if candidate ~= "" then
            local okExists, exists = pcall(function()
                return isfile(candidate)
            end)
            if okExists and exists then
                local okRead, text = pcall(function()
                    return readfile(candidate)
                end)
                if okRead and type(text) == "string" then
                    return true, text, candidate
                end
            end
        end
    end
    return false, nil, nil
end

local QueueStatePath = Globals.QueueFolder .. "/CAC_TaskQueue.json"
local QueueResultsPath = Globals.QueueFolder .. "/CAC_AutoPublish_Results.txt"
local AutoPublishDebugPath = Globals.QueueFolder .. "/CAC_AutoPublish_Debug.jsonl"

local function WriteQueueState(state)
    if type(state) ~= "table" then
        return false
    end
    state.updated_at = os.time()
    local okJson, encoded = pcall(function()
        return HttpService:JSONEncode(state)
    end)
    if not okJson or type(encoded) ~= "string" then
        return false
    end
    return SafeWriteText(QueueStatePath, encoded)
end

local function ReadQueueState()
    local okRead, raw = SafeReadText(QueueStatePath)
    if not okRead or type(raw) ~= "string" or raw == "" then
        return nil
    end
    local okJson, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not okJson or type(decoded) ~= "table" then
        return nil
    end
    return decoded
end

local HideAutoRejoinActionBar

local function ClearQueueState()
    pcall(function()
        if isfile(QueueStatePath) then
            delfile(QueueStatePath)
        end
    end)
    if HideAutoRejoinActionBar then
        HideAutoRejoinActionBar()
    end
end

local function SaveAutoPublishResultLog(text)
    local line = tostring(text or "")
    if line == "" then
        return
    end
    line = line .. "\n"
    local ok = pcall(function()
        appendfile(QueueResultsPath, line)
    end)
    if not ok then
        local existing = ""
        local has, raw = SafeReadText(QueueResultsPath)
        if has and type(raw) == "string" then
            existing = raw
        end
        SafeWriteText(QueueResultsPath, existing .. line)
    end
end

local function ClearAutoPublishResultLog()
    pcall(function()
        if isfile(QueueResultsPath) then
            delfile(QueueResultsPath)
        end
    end)
end

local function SanitizeForJson(value, depth)
    depth = tonumber(depth) or 0
    if depth > 4 then
        return tostring(value)
    end

    local valueType = typeof(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "number" or valueType == "string" then
        return value
    end
    if valueType == "Instance" then
        local path = nil
        pcall(function()
            path = value:GetFullName()
        end)
        return {
            __type = "Instance",
            class = value.ClassName,
            name = value.Name,
            path = path
        }
    end
    if valueType == "EnumItem" then
        return tostring(value)
    end
    if type(value) == "table" then
        local out = {}
        local count = 0
        for k, v in pairs(value) do
            count = count + 1
            if count > 80 then
                out.__truncated = true
                break
            end
            out[tostring(k)] = SanitizeForJson(v, depth + 1)
        end
        return out
    end
    return tostring(value)
end

local function AutoPublishDebug(eventName, data)
    local payload = {
        t = os.clock(),
        unix = os.time(),
        event = tostring(eventName or "event"),
        place_id = game.PlaceId,
        job_id = tostring(game.JobId or ""),
        executor = tostring(ExecutorName or "Unknown"),
        data = SanitizeForJson(data or {}, 0)
    }

    local okJson, encoded = pcall(function()
        return HttpService:JSONEncode(payload)
    end)
    if not okJson or type(encoded) ~= "string" then
        encoded = "{\"event\":\"encode_failed\"}"
    end

    local line = encoded .. "\n"
    local okAppend = pcall(function()
        appendfile(AutoPublishDebugPath, line)
    end)
    if not okAppend then
        local existing = ""
        local has, raw = SafeReadText(AutoPublishDebugPath)
        if has and type(raw) == "string" then
            existing = raw
        end
        SafeWriteText(AutoPublishDebugPath, existing .. line)
    end
end

local function ClearAutoPublishDebugLog()
    pcall(function()
        if isfile(AutoPublishDebugPath) then
            delfile(AutoPublishDebugPath)
        end
    end)
end

local function ExportAutoPublishDebugDump(statusLabel)
    local okRead, raw = SafeReadText(AutoPublishDebugPath)
    if not okRead or type(raw) ~= "string" or raw == "" then
        Notify("Auto Publish Debug", "No debug dump found yet.")
        return false
    end

    local outputPath = Globals.WorkFolder .. "/AutoPublishDebug_" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".jsonl"
    local okWrite, savedPath = SafeWriteText(outputPath, raw)
    if okWrite then
        if statusLabel then
            statusLabel.Text = "Status: Auto publish debug dump saved to " .. tostring(savedPath or outputPath)
        end
        Notify("Auto Publish Debug", "Dump saved: " .. tostring(savedPath or outputPath))
        return true
    end

    Notify("Auto Publish Debug", "Failed to write debug dump.")
    return false
end

HideAutoRejoinActionBar = function()
    if Window and Window.HideActionBar then
        pcall(function()
            Window:HideActionBar()
        end)
    end
end

local function DisableAutoRejoin(reason, queueState)
    Globals.AutoRejoinCodeEnabled = false
    Globals.AutoRejoinPublishEnabled = false
    Globals.AutoRejoinCodeMode = AUTO_REJOIN_MODE
    Globals.AutoRejoinPublishMode = AUTO_REJOIN_MODE
    SaveLocalCache()
    HideAutoRejoinActionBar()

    if type(queueState) == "table" then
        queueState.auto_rejoin_cancelled = true
        queueState.auto_rejoin_cancelled_at = os.time()
        WriteQueueState(queueState)
    else
        local state = ReadQueueState()
        if type(state) == "table" then
            state.auto_rejoin_cancelled = true
            state.auto_rejoin_cancelled_at = os.time()
            WriteQueueState(state)
        end
    end

    Notify("Auto Rejoin", tostring(reason or "Auto rejoin cancelled. Queue remains saved."))
end

local function ShowAutoRejoinActionBar(queueState, statusLabel)
    if not Window or not Window.ShowActionBar then
        return
    end
    pcall(function()
        Window:ShowActionBar({
            Text = "If you want to cancel active auto rejoin, click here.",
            ButtonText = "Stop",
            Callback = function()
                DisableAutoRejoin("Auto rejoin cancelled by user. Queue remains saved.", queueState)
                if statusLabel then
                    statusLabel.Text = "Status: Auto rejoin cancelled. Queue remains saved."
                end
            end
        })
    end)
end

local function ConfirmQueueAutoRejoin(queueState, kind, index, statusLabel)
    if type(queueState) ~= "table" then
        return true
    end

    if queueState.auto_rejoin_cancelled == true then
        if statusLabel then
            statusLabel.Text = "Status: Auto rejoin cancelled. Queue remains saved."
        end
        return false
    end

    local rejoinKey = tostring(kind or queueState.task or "queue") .. ":" .. tostring(index or queueState.next_index or 1)
    if queueState.last_rejoin_key == rejoinKey then
        queueState.rejoin_loop_count = (tonumber(queueState.rejoin_loop_count) or 0) + 1
    else
        queueState.last_rejoin_key = rejoinKey
        queueState.rejoin_loop_count = 1
    end

    if tonumber(queueState.rejoin_loop_count) and queueState.rejoin_loop_count > 2 then
        DisableAutoRejoin("Auto rejoin paused to avoid looping on the same queue item.", queueState)
        if statusLabel then
            statusLabel.Text = "Status: Auto rejoin paused to avoid a loop. Queue is saved."
        end
        return false
    end

    if queueState.auto_rejoin_confirmed == true then
        ShowAutoRejoinActionBar(queueState, statusLabel)
        WriteQueueState(queueState)
        return true
    end

    ShowAutoRejoinActionBar(queueState, statusLabel)

    local approved = true
    local ok, result = pcall(function()
        if Window and Window.Confirm then
            return Window:Confirm({
                Title = "Auto Rejoin",
                Content = "Do you want to continue auto rejoin?",
                ConfirmText = "Yes, continue",
                CancelText = "No, stop",
                Timeout = 10
            })
        end
        return true
    end)
    if ok then
        approved = result == true
    else
        approved = false
    end

    if not approved then
        DisableAutoRejoin("Auto rejoin cancelled. Queue remains saved.", queueState)
        if statusLabel then
            statusLabel.Text = "Status: Auto rejoin cancelled. Queue remains saved."
        end
        return false
    end

    queueState.auto_rejoin_confirmed = true
    queueState.auto_rejoin_confirmed_at = os.time()
    WriteQueueState(queueState)
    return true
end

local TeleportFailureMonitorConnected = false

local function EnsureTeleportFailureMonitor()
    if TeleportFailureMonitorConnected then
        return
    end

    TeleportFailureMonitorConnected = true
    pcall(function()
        TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage, placeId)
            if player ~= LocalPlayer then
                return
            end
            AutoPublishDebug("rejoin_teleport_failed", {
                result = tostring(teleportResult),
                error = tostring(errorMessage or ""),
                place_id = tostring(placeId or game.PlaceId),
                current_job_id = tostring(game.JobId or "")
            })
        end)
    end)
end

local function FetchPublicServerJobId(excludedJobId)
    if not http_request then
        return nil, "Executor HTTP request is unavailable."
    end

    local excluded = tostring(excludedJobId or "")
    local cursor = nil
    local lastError = "No public server target found."

    for _ = 1, 3 do
        local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId) .. "/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"
        if cursor and tostring(cursor) ~= "" then
            local okEncode, encoded = pcall(function()
                return HttpService:UrlEncode(tostring(cursor))
            end)
            url = url .. "&cursor=" .. tostring(okEncode and encoded or cursor)
        end

        local okRequest, response = pcall(function()
            return http_request({
                Url = url,
                Method = "GET",
                Headers = { ["Accept"] = "application/json" }
            })
        end)

        if not okRequest or not response then
            lastError = "Public server request failed."
            break
        end

        local statusCode = tonumber(response.StatusCode) or tonumber(response.Status) or 0
        if statusCode < 200 or statusCode > 299 then
            lastError = "Public server request returned HTTP " .. tostring(statusCode) .. "."
            break
        end

        local okJson, payload = pcall(function()
            return HttpService:JSONDecode(tostring(response.Body or ""))
        end)

        if not okJson or type(payload) ~= "table" or type(payload.data) ~= "table" then
            lastError = "Public server response was invalid."
            break
        end

        local candidates = {}
        for _, server in ipairs(payload.data) do
            local jobId = tostring(server and server.id or "")
            local playing = tonumber(server and server.playing) or 0
            local maxPlayers = tonumber(server and server.maxPlayers) or math.huge
            if jobId ~= "" and jobId ~= excluded and playing < maxPlayers then
                table.insert(candidates, jobId)
            end
        end

        if #candidates > 0 then
            return candidates[math.random(1, #candidates)], nil
        end

        cursor = payload.nextPageCursor
        if not cursor or tostring(cursor) == "" then
            break
        end
    end

    return nil, lastError
end

local function AttemptAutoRejoin(reason, modeOverride, instant)
    local mode = tostring(modeOverride or AUTO_REJOIN_MODE)
    if mode ~= "public" and mode ~= "same" then
        mode = AUTO_REJOIN_MODE
    end
    local delaySeconds = instant and 0 or 3.0
    Notify("Auto Rejoin", instant and ("Rejoining now (" .. mode .. ")...") or ("Cooldown detected. Rejoining in 3s (" .. mode .. ")..."))
    EnsureTeleportFailureMonitor()
    task.delay(delaySeconds, function()
        local latestQueue = ReadQueueState()
        if type(latestQueue) == "table" and latestQueue.auto_rejoin_cancelled == true then
            Notify("Auto Rejoin", "Cancelled. Queue remains saved.")
            HideAutoRejoinActionBar()
            return
        end

        AutoPublishDebug("rejoin_attempt", {
            reason = tostring(reason or ""),
            mode = mode,
            instant = instant == true,
            current_job_id = tostring(game.JobId or "")
        })

        local function tryCall(label, fn)
            local ok, err = pcall(fn)
            AutoPublishDebug("rejoin_call_result", {
                label = tostring(label),
                ok = ok,
                error = err and tostring(err) or nil,
                current_job_id = tostring(game.JobId or "")
            })
            if ok then
                return true
            end
            warn("[CAC Rejoin] " .. tostring(label) .. " failed: " .. tostring(err))
            return false
        end

        local function tryJobHop(jobId, label)
            if not jobId or tostring(jobId) == "" then
                return false
            end

            AutoPublishDebug("rejoin_target", {
                mode = mode,
                label = tostring(label or "job_hop"),
                target_job_id = tostring(jobId),
                current_job_id = tostring(game.JobId or "")
            })

            if tryCall(tostring(label or "job hop") .. " with player", function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, tostring(jobId), LocalPlayer)
            end) then
                return true
            end

            return tryCall(tostring(label or "job hop"), function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, tostring(jobId))
            end)
        end

        local function tryPublic()
            local targetJobId, fetchErr = FetchPublicServerJobId(game.JobId)
            if targetJobId and tryJobHop(targetJobId, "public server hop") then
                return true
            end

            AutoPublishDebug("rejoin_no_public_target", {
                error = tostring(fetchErr or "TeleportToPlaceInstance failed."),
                current_job_id = tostring(game.JobId or "")
            })

            if tryCall("Teleport(placeId)", function()
                TeleportService:Teleport(game.PlaceId)
            end) then
                return true
            end
            if tryCall("Teleport(placeId, LocalPlayer)", function()
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end) then
                return true
            end
            return false
        end

        local ok = false
        if mode == "public" then
            ok = tryPublic()
        else
            if tryCall("TeleportToPlaceInstance(placeId, jobId)", function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId)
            end) then
                ok = true
            elseif tryCall("TeleportToPlaceInstance(placeId, jobId, LocalPlayer)", function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end) then
                ok = true
            else
                Notify("Auto Rejoin", "Same server failed, falling back to public...")
                ok = tryPublic()
            end
        end

        if not ok then
            Notify("Rejoin Failed", tostring(reason or "Teleport failed. Continue manually."))
        end
    end)
end

local function CreateDropdownCompat(tab, cfg)
    if tab and tab.CreateDropdown then
        return tab:CreateDropdown(cfg)
    end
    local options = cfg.Options or {}
    local default = tostring(cfg.Default or options[1] or "")
    local obj = { Value = default }
    local input = tab:CreateInput({
        Name = tostring(cfg.Name or "Option"),
        Default = default,
        Placeholder = (#options > 0) and ("Options: " .. table.concat(options, " / ")) or "Type value",
        Callback = function(v)
            obj.Value = tostring(v or "")
            if cfg.Callback then
                cfg.Callback(obj.Value)
            end
        end
    })
    function obj:SetValue(v)
        self.Value = tostring(v or "")
        input:SetValue(self.Value)
    end
    return obj
end

local PendingQueueResume = ReadQueueState()
local TryResumePendingQueue

-- ==================================================================
-- AUTHENTICATION & SINGLE SESSION LOGIC
-- ==================================================================
local AuthLogic = {
    ApiBase = "https://cac-licensing-api.cacultimatev1.workers.dev",
    SessionStartRoute = "/v1/auth/session/start",
    SessionAutoStartRoute = "/v1/auth/session/auto-start",
    SessionValidateRoute = "/v1/auth/session/validate",
    HealthRoute = "/health"
}

local SharedEnv = (_G or {})
pcall(function()
    if getgenv then
        SharedEnv = getgenv()
    end
end)

local function ParseJsonSafe(raw)
    local ok, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if ok then return data end
    return nil
end

local function ApiPost(path, payload)
    if not http_request then
        return false, nil, "Executor does not support HTTP requests."
    end

    local ok, res = pcall(function()
        return http_request({
            Url = AuthLogic.ApiBase .. path,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(payload)
        })
    end)

    if not ok or not res then
        return false, nil, "Connection to auth server failed."
    end

    local parsed = ParseJsonSafe(res.Body or "")

    local statusCode = tonumber(res.StatusCode) or tonumber(res.Status) or 0
    if statusCode < 200 or statusCode > 299 then
        local errMsg = "Authentication request failed."
        if parsed and parsed.error and parsed.error.message then
            errMsg = tostring(parsed.error.message)
        end
        return false, parsed, errMsg
    end

    return true, parsed, nil
end

local function ApiGet(path)
    if not http_request then
        return false, nil, "Executor does not support HTTP requests."
    end

    local ok, res = pcall(function()
        return http_request({
            Url = AuthLogic.ApiBase .. path,
            Method = "GET",
            Headers = {["Content-Type"] = "application/json"}
        })
    end)

    if not ok or not res then
        return false, nil, "Connection to auth server failed."
    end

    local parsed = ParseJsonSafe(res.Body or "")
    local statusCode = tonumber(res.StatusCode) or tonumber(res.Status) or 0
    if statusCode < 200 or statusCode > 299 then
        local errMsg = "Request failed."
        if parsed and parsed.error and parsed.error.message then
            errMsg = tostring(parsed.error.message)
        end
        return false, parsed, errMsg
    end

    return true, parsed, nil
end

local function TimeRemainingText()
    if not Globals.IsAuthenticated then return "Unverified" end

    local expiresAt = Globals.LicenseExpiresAt
    if not expiresAt or tostring(expiresAt) == "" then return "Permanent" end

    local parsedOk, parsedDate = pcall(function()
        return DateTime.fromIsoDate(tostring(expiresAt))
    end)
    if not parsedOk or not parsedDate then return "Syncing..." end

    local secondsLeft = parsedDate.UnixTimestamp - os.time()
    if secondsLeft <= 0 then return "Expired" end
    if secondsLeft >= 86400 then return string.format("%.1f Days", secondsLeft / 86400) end
    if secondsLeft >= 3600 then return string.format("%.1f Hours", secondsLeft / 3600) end
    return string.format("%d Min", math.max(1, math.floor(secondsLeft / 60)))
end

local function NormalizeSessionRecheckMessage(reason)
    local message = tostring(reason or "")
    local lower = message:lower()

    if message == "" or lower:find("session", 1, true) or lower:find("token", 1, true) or lower:find("expired", 1, true) then
        return "Session recheck failed. Login again when convenient."
    end

    return message
end

local function ValidateSessionNow(notifySuccess)
    if not Globals.IsAuthenticated then
        return false, "Not authenticated."
    end

    if Globals.SessionToken == "" then
        return false, NormalizeSessionRecheckMessage("Missing session token.")
    end

    local ok, data, err = ApiPost(AuthLogic.SessionValidateRoute, {
        session_token = Globals.SessionToken,
        hwid = gethwid()
    })

    if not ok then
        return false, NormalizeSessionRecheckMessage(err)
    end

    if not data or not data.ok or not data.data or data.data.valid ~= true then
        return false, "Session recheck failed. Login again when convenient."
    end

    if data.data.revalidate_after_seconds then
        Globals.RevalidateAfter = tonumber(data.data.revalidate_after_seconds) or Globals.RevalidateAfter
    end

    if data.data.session_expires_at then
        Globals.SessionExpiresAtISO = tostring(data.data.session_expires_at)
    end

    if data.data.license_expires_at ~= nil then
        Globals.LicenseExpiresAt = data.data.license_expires_at
    end

    LocalCache.SessionToken = tostring(Globals.SessionToken or "")
    LocalCache.SessionExpiresAtISO = Globals.SessionExpiresAtISO
    LocalCache.RevalidateAfter = tonumber(Globals.RevalidateAfter) or 60
    LocalCache.LicenseExpiresAt = Globals.LicenseExpiresAt
    LocalCache.LicenseStatus = Globals.LicenseStatus
    LocalCache.LicensePlan = Globals.LicensePlan
    LocalCache.LastAuthAt = os.time()
    SaveLocalCache()

    if notifySuccess then
        Notify("System", "Session validated successfully.")
    end

    return true, nil
end

local function CopyToClipboardOrNotify(value, successMsg)
    if setclipboard then
        local ok = pcall(function()
            setclipboard(tostring(value))
        end)
        if ok then
            Notify("System", successMsg)
            return
        end
    end
    Notify("Info", "Clipboard is not supported by this executor.")
end

local function ReadKeyFromKnownFiles()
    if not (isfile and readfile) then return "" end

    local candidates = {
        "cac_loader_key.txt",
        Globals.WorkFolder .. "/cac_loader_key.txt",
        "workspace/cac_loader_key.txt",
        "Workspace/cac_loader_key.txt",
        "CAC_Output/cac_loader_key.txt"
    }

    for _, path in ipairs(candidates) do
        local okExists, exists = pcall(function()
            return isfile(path)
        end)
        if okExists and exists then
            local okRead, content = pcall(function()
                return readfile(path)
            end)
            if okRead and content then
                local clean = tostring(content):gsub("%s+", "")
                if clean ~= "" then
                    return clean
                end
            end
        end
    end

    return ""
end

local function GetBestKnownKey(optionalInput)
    local fromInput = tostring(optionalInput or ""):gsub("%s+", "")
    if fromInput ~= "" then return fromInput end

    local fromUserState = tostring(Globals.UserKey or ""):gsub("%s+", "")
    if fromUserState ~= "" then return fromUserState end

    local fromCache = tostring(LocalCache.Key or ""):gsub("%s+", "")
    if fromCache ~= "" then return fromCache end

    local fromFile = ReadKeyFromKnownFiles()
    if fromFile ~= "" then
        LocalCache.Key = fromFile
        Globals.UserKey = fromFile
        SaveLocalCache()
        return fromFile
    end

    return ""
end

local function DeleteKnownLoaderKeyFiles()
    if not (delfile and isfile) then return end

    local candidates = {
        "cac_loader_key.txt",
        Globals.WorkFolder .. "/cac_loader_key.txt",
        "workspace/cac_loader_key.txt",
        "Workspace/cac_loader_key.txt",
        "CAC_Output/cac_loader_key.txt"
    }

    for _, path in ipairs(candidates) do
        pcall(function()
            if isfile(path) then
                delfile(path)
            end
        end)
    end
end

local function AutoLoginDisableFlagPaths()
    return {
        "cac_disable_auto_login.flag",
        Globals.WorkFolder .. "/cac_disable_auto_login.flag",
        "workspace/cac_disable_auto_login.flag",
        "Workspace/cac_disable_auto_login.flag",
        "CAC_Output/cac_disable_auto_login.flag"
    }
end

local function SetAutoLoginDisabledLocally(disabled)
    LocalCache.AutoLoginDisabled = disabled == true
    SaveLocalCache()

    local paths = AutoLoginDisableFlagPaths()
    if LocalCache.AutoLoginDisabled then
        if writefile then
            for _, path in ipairs(paths) do
                pcall(function()
                    writefile(path, "1")
                end)
            end
        end
    else
        if delfile and isfile then
            for _, path in ipairs(paths) do
                pcall(function()
                    if isfile(path) then
                        delfile(path)
                    end
                end)
            end
        end
    end
end

local function WipeLocalLoginData()
    Globals.IsAuthenticated = false
    Globals.SessionToken = ""
    Globals.SessionExpiresAtISO = nil
    Globals.LicenseExpiresAt = nil
    Globals.LicenseStatus = "unknown"
    Globals.LicensePlan = "default"
    Globals.RevalidateAfter = 60
    Globals.UserKey = ""
    Globals.CurrentUser = nil

    LocalCache.Key = ""
    LocalCache.SessionToken = ""
    LocalCache.SessionExpiresAtISO = nil
    LocalCache.LastAuthAt = 0
    SetAutoLoginDisabledLocally(true)
    DeleteKnownLoaderKeyFiles()

    pcall(function()
        if SharedEnv and type(SharedEnv) == "table" then
            SharedEnv.CAC_PREAUTH_TOKEN = nil
            SharedEnv.CAC_PREAUTH = nil
            SharedEnv.CAC_LAST_KEY = nil
            SharedEnv.CAC_KEY = nil
            SharedEnv.KEY = nil
            SharedEnv.cac_key = nil
        end
    end)
end

local function ForceAuthStop(reason)
    Globals.IsAuthenticated = false
    Globals.SessionToken = ""
    Globals.SessionExpiresAtISO = nil
    LocalCache.SessionToken = ""
    LocalCache.SessionExpiresAtISO = nil
    SaveLocalCache()
    local safeReason = NormalizeSessionRecheckMessage(reason)
    Notify("Session Notice", safeReason)
    warn("[CAC Auth] Session heartbeat stopped: " .. safeReason)
end

local function StartSessionHeartbeat()
    task.spawn(function()
        local failures = 0
        while Globals.IsAuthenticated do
            local waitTime = tonumber(Globals.RevalidateAfter) or 60
            if waitTime < 20 then waitTime = 20 end
            if waitTime > 300 then waitTime = 300 end
            task.wait(waitTime)

            if not Globals.IsAuthenticated then break end

            if Globals.SessionToken == "" then
                ForceAuthStop("Missing session token.")
                break
            end

            local ok, err = ValidateSessionNow(false)
            if not ok then
                failures = failures + 1
                if failures >= 3 then
                    ForceAuthStop(err or "Session validation failed.")
                    break
                end
            else
                failures = 0
            end
        end
    end)
end

local function ApplyAuthSuccess(data, usedKey)
    if not data or not data.ok or not data.data or not data.data.session_token then
        return false, "Invalid response from auth server."
    end

    Globals.IsAuthenticated = true
    Globals.SessionToken = tostring(data.data.session_token)
    Globals.SessionExpiresAtISO = data.data.session_expires_at and tostring(data.data.session_expires_at) or nil
    Globals.RevalidateAfter = tonumber(data.data.revalidate_after_seconds) or 60

    local licenseData = data.data.license or {}
    Globals.LicenseStatus = tostring(licenseData.status or "active")
    Globals.LicensePlan = tostring(licenseData.plan_name or "default")
    Globals.LicenseExpiresAt = licenseData.expires_at

    Globals.CurrentUser = {
        type = Globals.LicensePlan,
        status = Globals.LicenseStatus,
        expires_at = Globals.LicenseExpiresAt
    }

    LocalCache.SessionToken = tostring(Globals.SessionToken or "")
    LocalCache.SessionExpiresAtISO = Globals.SessionExpiresAtISO
    LocalCache.RevalidateAfter = tonumber(Globals.RevalidateAfter) or 60
    LocalCache.LicenseExpiresAt = Globals.LicenseExpiresAt
    LocalCache.LicenseStatus = Globals.LicenseStatus
    LocalCache.LicensePlan = Globals.LicensePlan
    LocalCache.LastAuthAt = os.time()

    if usedKey and tostring(usedKey) ~= "" then
        LocalCache.Key = tostring(usedKey)
        Globals.UserKey = tostring(usedKey)
        SetAutoLoginDisabledLocally(false)
    elseif LocalCache.Key and tostring(LocalCache.Key):gsub("%s+", "") ~= "" then
        Globals.UserKey = tostring(LocalCache.Key):gsub("%s+", "")
        SetAutoLoginDisabledLocally(false)
    else
        SetAutoLoginDisabledLocally(false)
    end

    if not Globals.UIUnlocked then
        Globals.UIUnlocked = true
        Notify("Welcome", "Access Granted. Initializing UI...")
        UnlockUI()
        StartSessionHeartbeat()
    end

    task.delay(0.4, function()
        TryResumePendingQueue()
    end)

    return true, nil
end

local function ValidateKey(inputKey, forceSwitch)
    local force = forceSwitch == true

    if Globals.IsAuthenticated and not force then
        return Notify("System", "Already authenticated in this session.")
    end

    if force then
        Notify("System", "Switching key...")
    end

    local cleanKey = tostring(inputKey or ""):gsub("%s+", "")
    if cleanKey == "" then return Notify("Error", "Please enter a key.") end
    
    Notify("System", "Validating credentials...")

    local ok, data, err = ApiPost(AuthLogic.SessionStartRoute, {
        key = cleanKey,
        hwid = gethwid(),
        device_label = "roblox-client",
        client_version = "cacultimate-v4.5.4"
    })

    if not ok then
        return Notify("Error", err or "Connection to auth server failed.")
    end

    local applied, msg = ApplyAuthSuccess(data, cleanKey)
    if not applied then
        return Notify("Error", msg or "Authentication failed.")
    end
end

local function TryAutoLogin(force)
    local forceAuto = force == true

    if LocalCache.AutoLoginDisabled and not forceAuto then
        Notify("System", "Auto-login is disabled on this device. Use key login or click Auto Login (HWID).")
        return
    end

    if Globals.IsAuthenticated then return end

    local preSessionToken = nil
    local keyHint = ""
    pcall(function()
        if SharedEnv and type(SharedEnv) == "table" then
            if SharedEnv.CAC_PREAUTH and SharedEnv.CAC_PREAUTH.session_token then
                preSessionToken = tostring(SharedEnv.CAC_PREAUTH.session_token)
            elseif SharedEnv.CAC_PREAUTH_TOKEN then
                preSessionToken = tostring(SharedEnv.CAC_PREAUTH_TOKEN)
            end
            if SharedEnv.CAC_LAST_KEY then
                keyHint = tostring(SharedEnv.CAC_LAST_KEY)
            end
        end
    end)

    keyHint = GetBestKnownKey(keyHint)

    if preSessionToken and preSessionToken ~= "" then
        local okValidate, dataValidate = ApiPost(AuthLogic.SessionValidateRoute, {
            session_token = preSessionToken,
            hwid = gethwid()
        })
        if okValidate and dataValidate and dataValidate.ok and dataValidate.data and dataValidate.data.valid == true then
            local bootstrapData = {
                ok = true,
                data = {
                    session_token = preSessionToken,
                    session_expires_at = dataValidate.data.session_expires_at,
                    revalidate_after_seconds = dataValidate.data.revalidate_after_seconds,
                    license = {
                        status = "active",
                        plan_name = "auto",
                        expires_at = dataValidate.data.license_expires_at
                    }
                }
            }
            local applied = ApplyAuthSuccess(bootstrapData, keyHint)
            if applied then
                Notify("System", "Automatic login successful.")
                return
            end
        end
    end

    local ok, data = ApiPost(AuthLogic.SessionAutoStartRoute, {
        hwid = gethwid(),
        device_label = "roblox-client",
        client_version = "cacultimate-v4.5.4"
    })

    if ok and data and data.ok then
        local applied, msg = ApplyAuthSuccess(data, keyHint)
        if applied then
            Notify("System", "Automatic login successful.")
            return
        end
        Notify("Error", msg or "Automatic login failed.")
        return
    end

    Notify("System", "Enter your key to login.")
end

local function CachedSessionLooksFresh()
    local token = tostring(LocalCache.SessionToken or "")
    if token == "" then
        return false
    end

    local lastAuthAt = tonumber(LocalCache.LastAuthAt) or 0
    if lastAuthAt > 0 and (os.time() - lastAuthAt) > 900 then
        return false
    end

    local expiresAt = LocalCache.SessionExpiresAtISO
    if expiresAt and tostring(expiresAt) ~= "" then
        local okDate, dt = pcall(function()
            return DateTime.fromIsoDate(tostring(expiresAt))
        end)
        if okDate and dt and dt.UnixTimestamp <= (os.time() + 15) then
            return false
        end
    end

    return true
end

local function TryFastQueueResumeFromCache()
    local state = PendingQueueResume or ReadQueueState()
    if type(state) ~= "table" then
        return false
    end
    if state.auto_rejoin_cancelled == true then
        return false
    end
    if Globals.QueueFastResumeEnabled == false or LocalCache.QueueFastResumeEnabled == false then
        return false
    end
    if not CachedSessionLooksFresh() then
        return false
    end

    Globals.IsAuthenticated = true
    Globals.SessionToken = tostring(LocalCache.SessionToken or "")
    Globals.SessionExpiresAtISO = LocalCache.SessionExpiresAtISO
    Globals.RevalidateAfter = tonumber(LocalCache.RevalidateAfter) or 60
    Globals.LicenseExpiresAt = LocalCache.LicenseExpiresAt
    Globals.LicenseStatus = tostring(LocalCache.LicenseStatus or "active")
    Globals.LicensePlan = tostring(LocalCache.LicensePlan or "cached")
    Globals.UserKey = GetBestKnownKey(LocalCache.Key or Globals.UserKey or "")
    Globals.CurrentUser = {
        type = Globals.LicensePlan,
        status = Globals.LicenseStatus,
        expires_at = Globals.LicenseExpiresAt
    }

    if not Globals.UIUnlocked then
        Globals.UIUnlocked = true
        Notify("System", "Fast queue resume enabled. Validating session in background.")
        UnlockUI()
        StartSessionHeartbeat()
    end

    task.defer(function()
        local okValidate, err = ValidateSessionNow(false)
        if not okValidate then
            Globals.IsAuthenticated = false
            Globals.SessionToken = ""
            Globals.SessionExpiresAtISO = nil
            LocalCache.SessionToken = ""
            LocalCache.SessionExpiresAtISO = nil
            SaveLocalCache()
            Notify("Session Notice", NormalizeSessionRecheckMessage(err))
        end
    end)

    return true
end

-- ==================================================================
-- FACTORY & FILE MANAGEMENT (SMART SIZE CHECK)
-- ==================================================================
local Factory = {}
local TaskState = {
    Running = false,
    CancelRequested = false,
    Name = "Idle",
    StartedAt = nil,
    CancelRequestedAt = nil,
    LastStatus = "System Status: Awaiting Command...",
    LastStatusAt = os.clock(),
    LastOutcome = "idle"
}

local function SetStatusLabel(statusLabel, text)
    if not statusLabel then return false end

    local message = tostring(text or "")
    TaskState.LastStatus = message
    TaskState.LastStatusAt = os.clock()

    local okDirect = pcall(function()
        statusLabel.Text = message
    end)
    if okDirect then return true end

    local okSetString = pcall(function()
        if statusLabel.Set then
            statusLabel:Set(message)
        elseif statusLabel.SetText then
            statusLabel:SetText(message)
        elseif statusLabel.Update then
            statusLabel:Update(message)
        else
            error("No supported status update method.")
        end
    end)
    if okSetString then return true end

    local okSetTable = pcall(function()
        if statusLabel.Set then
            statusLabel:Set({ Title = "System Status", Content = message })
        elseif statusLabel.Update then
            statusLabel:Update({ Title = "System Status", Content = message })
        else
            error("No supported table status update method.")
        end
    end)

    return okSetTable
end

local function CreateStatusProxy(statusLabel)
    if not statusLabel then return nil end

    local proxy = {}
    return setmetatable(proxy, {
        __index = function(_, key)
            if key == "Text" then
                local current = ""
                pcall(function()
                    current = statusLabel.Text
                end)
                return current
            end

            local value = nil
            pcall(function()
                value = statusLabel[key]
            end)
            return value
        end,
        __newindex = function(_, key, value)
            if key == "Text" then
                SetStatusLabel(statusLabel, value)
                return
            end
            pcall(function()
                statusLabel[key] = value
            end)
        end
    })
end

local function FormatTaskElapsed()
    if not TaskState.Running or not TaskState.StartedAt then
        return "0s"
    end

    local elapsed = math.max(0, math.floor(os.clock() - TaskState.StartedAt))
    if elapsed >= 3600 then
        local h = math.floor(elapsed / 3600)
        local m = math.floor((elapsed % 3600) / 60)
        local s = elapsed % 60
        return string.format("%dh %02dm %02ds", h, m, s)
    end
    if elapsed >= 60 then
        local m = math.floor(elapsed / 60)
        local s = elapsed % 60
        return string.format("%dm %02ds", m, s)
    end
    return string.format("%ds", elapsed)
end

local function CompactStatusText(rawText, maxLen)
    local text = tostring(rawText or ""):gsub("%s+", " ")
    local limit = tonumber(maxLen) or 28
    if #text <= limit then
        return text
    end
    if limit < 4 then
        return text:sub(1, limit)
    end
    return text:sub(1, limit - 3) .. "..."
end

local function BeginExtraction(taskName, statusLabel)
    if TaskState.Running then
        if TaskState.CancelRequested then
            local waited = TaskState.CancelRequestedAt and (os.clock() - TaskState.CancelRequestedAt) or 0
            if waited >= 6 then
                TaskState.Running = false
                TaskState.CancelRequested = false
                TaskState.Name = "Idle"
                TaskState.StartedAt = nil
                TaskState.CancelRequestedAt = nil
                TaskState.LastOutcome = "recovered"
                Notify("System", "Recovered stale queue lock. You can start a new extraction now.")
            end
        end
    end

    if TaskState.Running then
        Notify("Busy", "Another extraction is already running. Cancel it first.")
        return false
    end

    TaskState.Running = true
    TaskState.CancelRequested = false
    TaskState.Name = tostring(taskName or "Task")
    TaskState.StartedAt = os.clock()
    TaskState.CancelRequestedAt = nil
    TaskState.LastOutcome = "running"
    SetStatusLabel(statusLabel, "Status: Running " .. TaskState.Name .. "...")
    return true
end

local function EndExtraction(statusLabel, wasError)
    local cancelled = TaskState.CancelRequested == true
    local taskName = TaskState.Name
    TaskState.Running = false
    TaskState.CancelRequested = false
    TaskState.Name = "Idle"
    TaskState.StartedAt = nil
    TaskState.CancelRequestedAt = nil

    if wasError then
        TaskState.LastOutcome = "failed"
        SetStatusLabel(statusLabel, "Status: Task failed.")
    elseif cancelled then
        TaskState.LastOutcome = "cancelled"
        SetStatusLabel(statusLabel, "Status: Task cancelled by user.")
    else
        TaskState.LastOutcome = "completed"
        SetStatusLabel(statusLabel, "Status: Task completed.")
    end

    if cancelled then
        Notify("System", (taskName ~= "Idle" and taskName or "Task") .. " cancelled.")
    end
end

local function RequestCancel(statusLabel)
    if not TaskState.Running then
        Notify("Info", "No active extraction to cancel.")
        return
    end

    if TaskState.CancelRequested then
        TaskState.Running = false
        TaskState.CancelRequested = false
        TaskState.Name = "Idle"
        TaskState.StartedAt = nil
        TaskState.CancelRequestedAt = nil
        TaskState.LastOutcome = "force_cleared"
        SetStatusLabel(statusLabel, "Status: Queue lock force-cleared. Ready.")
        Notify("System", "Queue lock force-cleared. Start a new extraction now.")
        return
    end

    TaskState.CancelRequested = true
    TaskState.CancelRequestedAt = os.clock()
    SetStatusLabel(statusLabel, "Status: Cancel requested. Waiting for safe stop...")
    Notify("System", "Cancel request received. Finishing current step...")
end

local function IsCancelled()
    return TaskState.CancelRequested == true
end

local function CanReadExport(path)
    local rawPath = tostring(path or "")
    local candidates = {}

    local function PushCandidate(value)
        local v = tostring(value or "")
        if v ~= "" then
            table.insert(candidates, v)
        end
    end

    PushCandidate(rawPath)
    PushCandidate(rawPath:gsub("\\", "/"))
    PushCandidate(rawPath:gsub("/", "\\"))

    local basename = rawPath:match("[^/\\]+$")
    if basename and basename ~= "" then
        PushCandidate(basename)
        PushCandidate(Globals.WorkFolder .. "/" .. basename)
        PushCandidate(Globals.WorkFolder .. "\\" .. basename)
    end

    -- Some executors append an extension automatically (e.g. ".rbxm.rbxmx")
    if rawPath ~= "" then
        PushCandidate(rawPath .. ".rbxmx")
        PushCandidate(rawPath .. ".rbxm")
        PushCandidate(rawPath:gsub("\\", "/") .. ".rbxmx")
        PushCandidate(rawPath:gsub("\\", "/") .. ".rbxm")
    end

    local seen = {}
    for _, candidate in ipairs(candidates) do
        if not seen[candidate] then
            seen[candidate] = true

            if candidate and candidate ~= "" then
                local exists = false
                pcall(function()
                    exists = isfile(candidate)
                end)

                if exists then
                    local okRead, content = pcall(function()
                        return readfile(candidate)
                    end)
                    if okRead and type(content) == "string" and #content > 0 then
                        return true, candidate
                    end
                end
            end
        end
    end

    return false, nil
end

local function WaitForFile(path, timeoutSeconds)
    local timeout = tonumber(timeoutSeconds) or 20
    local started = os.clock()
    while (os.clock() - started) < timeout do
        local okRead, detected = CanReadExport(path)
        if okRead then
            return true, detected
        end
        task.wait(0.25)
    end
    local okRead, detected = CanReadExport(path)
    return okRead, detected
end

local SAVEINSTANCE_PROFILES = {
    default = {
        "object_filename",
        "object_FilePath",
        "object_Filename",
        "instance_filename",
        "positional_instance_filename"
    },
    xeno = {
        "object_filename",
        "object_FilePath",
        "instance_filename",
        "positional_instance_filename"
    },
    wave = {
        "object_filename",
        "instance_filename",
        "object_Filename",
        "object_FilePath",
        "positional_instance_filename"
    },
    volt = {
        "object_filename",
        "object_FilePath",
        "positional_instance_filename"
    },
    potassium = {
        "object_filename",
        "instance_filename",
        "object_FilePath",
        "positional_instance_filename"
    },
    cosmic = {
        "object_filename",
        "object_Filename",
        "instance_filename",
        "positional_instance_filename"
    }
}

local function GetSaveInstanceProfile()
    local key = string.lower(tostring(ExecutorName or ""))
    for name, profile in pairs(SAVEINSTANCE_PROFILES) do
        if name ~= "default" and string.find(key, name, 1, true) then
            return profile, name
        end
    end
    return SAVEINSTANCE_PROFILES.default, "default"
end

local function RunSaveInstanceAttempt(kind, object, filename)
    if kind == "object_filename" then
        return saveinstance({
            Object = object,
            filename = filename,
            mode = "optimized",
            SafeMode = false
        })
    elseif kind == "object_FilePath" then
        return saveinstance({
            Object = object,
            FilePath = filename,
            mode = "optimized",
            SafeMode = false
        })
    elseif kind == "object_Filename" then
        return saveinstance({
            Object = object,
            Filename = filename,
            mode = "optimized",
            SafeMode = false
        })
    elseif kind == "instance_filename" then
        return saveinstance({
            Instance = object,
            filename = filename,
            mode = "optimized",
            SafeMode = false
        })
    elseif kind == "positional_instance_filename" then
        return saveinstance(object, filename)
    end
    error("Unknown saveinstance attempt: " .. tostring(kind), 0)
end

local function ShouldSkipSaveInstanceAttempt(kind, profileName)
    local profile = string.lower(tostring(profileName or ""))
    if profile == "volt" and kind == "instance_filename" then
        return true
    end
    return false
end

local function SaveInstanceCompat(object, filename, statusLabel)
    local profile, profileName = GetSaveInstanceProfile()
    local attempted = {}
    local lastError = nil

    for _, kind in ipairs(profile) do
        if not attempted[kind] and not ShouldSkipSaveInstanceAttempt(kind, profileName) then
            attempted[kind] = true
            if statusLabel then
                statusLabel.Text = "Status: Writing file via saveinstance (" .. profileName .. "/" .. kind .. ")..."
            end

            local ok, err = pcall(function()
                RunSaveInstanceAttempt(kind, object, filename)
            end)

            if ok then
                return true, nil, kind, profileName
            end

            lastError = err
            warn("[CAC] SaveInstance attempt failed (" .. tostring(profileName) .. "/" .. tostring(kind) .. "): " .. tostring(err))
        end
    end

    for _, kind in ipairs(SAVEINSTANCE_PROFILES.default) do
        if not attempted[kind] and not ShouldSkipSaveInstanceAttempt(kind, profileName) then
            attempted[kind] = true
            local ok, err = pcall(function()
                RunSaveInstanceAttempt(kind, object, filename)
            end)

            if ok then
                return true, nil, kind, "default"
            end

            lastError = err
            warn("[CAC] SaveInstance fallback failed (" .. tostring(kind) .. "): " .. tostring(err))
        end
    end

    return false, lastError or "SaveInstance failed.", nil, profileName
end

local function FindExportFallback(targetPath)
    if not listfiles then return nil end

    local targetName = tostring(targetPath or ""):match("[^/\\]+$")
    if not targetName or targetName == "" then return nil end
    local targetStem = targetName:gsub("%.[^%.]+$", "")

    local paths = { Globals.WorkFolder, "" }
    for _, path in ipairs(paths) do
        local ok, files = pcall(function()
            if path == "" or isfolder(path) then
                return listfiles(path)
            end
            return {}
        end)

        if ok and type(files) == "table" then
            for _, file in ipairs(files) do
                local normalized = tostring(file):gsub("\\", "/")
                local fileName = normalized:match("[^/]+$") or normalized
                if normalized:sub(-#targetName) == targetName
                    or fileName == (targetName .. ".rbxmx")
                    or fileName == (targetName .. ".rbxm")
                    or (targetStem ~= "" and fileName:sub(1, #targetStem) == targetStem)
                then
                    return file
                end
            end
        end
    end

    return nil
end

local function UploadToDiscord(realFilename, fileContent, count, tag)
    if Globals.WebhookURL == "" or not Globals.WebhookURL:find("http") then return false end
    if not http_request then
        Notify("Error", "Executor does not support HTTP requests for webhook delivery.")
        return false
    end

    Notify("Status", "Uploading payload to Discord...")

    local timeStr = os.date("%H-%M-%S")
    local finalName = count .. "_Rigs_" .. tag .. "_" .. timeStr .. ".rbxmx"
    finalName = finalName:gsub(" ", "_"):gsub("[^a-zA-Z0-9_%.%-]", "")

    local boundary = "----CAC" .. tostring(os.time())
    local body = ""

    body = body .. "--" .. boundary .. "\r\n"
    body = body .. 'Content-Disposition: form-data; name="payload_json"\r\n\r\n'
    body = body .. HttpService:JSONEncode({
        embeds = {{
            title = "📦 Dump Success: " .. tag,
            description = "Rigs: **" .. count .. "**\nFile: `" .. finalName .. "`",
            color = 65280,
            footer = { text = "CAC Ultimate V4.5.4" }
        }}
    }) .. "\r\n"

    body = body .. "--" .. boundary .. "\r\n"
    body = body .. 'Content-Disposition: form-data; name="file"; filename="' .. finalName .. '"\r\n'
    body = body .. 'Content-Type: application/octet-stream\r\n\r\n'
    body = body .. fileContent .. "\r\n"
    body = body .. "--" .. boundary .. "--\r\n"

    local s, r = pcall(function()
        return http_request({
            Url = Globals.WebhookURL,
            Method = "POST",
            Headers = {["Content-Type"] = "multipart/form-data; boundary=" .. boundary},
            Body = body
        })
    end)

    local statusCode = s and r and (tonumber(r.StatusCode) or tonumber(r.Status) or 0) or 0
    if s and statusCode >= 200 and statusCode <= 299 then
        Notify("Success", "File sent: " .. finalName)
        if delfile then pcall(function() delfile(realFilename) end) end
        return true
    else
        Notify("Error", "Webhook delivery failed. HTTP " .. tostring(statusCode))
        if s and r and type(r.Body) == "string" and r.Body ~= "" then
            warn("[CAC] Webhook response: " .. tostring(r.Body):sub(1, 220))
        end
    end
    return false
end

local function UploadTextToDiscord(realFilename, fileContent, tag, summary)
    if Globals.WebhookURL == "" or not Globals.WebhookURL:find("http") then return false end
    if not http_request then
        Notify("Error", "Executor does not support HTTP requests for webhook delivery.")
        return false
    end

    local safeTag = tostring(tag or "Result")
    local finalName = tostring(realFilename or ("CAC_" .. safeTag .. ".txt")):gsub("\\", "/"):match("([^/]+)$") or ("CAC_" .. safeTag .. ".txt")
    finalName = finalName:gsub(" ", "_"):gsub("[^a-zA-Z0-9_%.%-]", "")
    if not finalName:lower():match("%.txt$") then
        finalName = finalName .. ".txt"
    end

    local boundary = "----CAC" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
    local body = ""

    body = body .. "--" .. boundary .. "\r\n"
    body = body .. 'Content-Disposition: form-data; name="payload_json"\r\n\r\n'
    body = body .. HttpService:JSONEncode({
        embeds = {{
            title = "CAC " .. safeTag,
            description = tostring(summary or ("Generated file: `" .. finalName .. "`")),
            color = 65280,
            footer = { text = "CAC Ultimate V4.5.4" }
        }}
    }) .. "\r\n"

    body = body .. "--" .. boundary .. "\r\n"
    body = body .. 'Content-Disposition: form-data; name="file"; filename="' .. finalName .. '"\r\n'
    body = body .. 'Content-Type: text/plain\r\n\r\n'
    body = body .. tostring(fileContent or "") .. "\r\n"
    body = body .. "--" .. boundary .. "--\r\n"

    local s, r = pcall(function()
        return http_request({
            Url = Globals.WebhookURL,
            Method = "POST",
            Headers = {["Content-Type"] = "multipart/form-data; boundary=" .. boundary},
            Body = body
        })
    end)

    local statusCode = s and r and (tonumber(r.StatusCode) or tonumber(r.Status) or 0) or 0
    if s and statusCode >= 200 and statusCode <= 299 then
        Notify("Discord", "Auto publish result sent to Discord.")
        return true
    end

    Notify("Discord", "Could not send result file. Local copy was kept.")
    if s and r and type(r.Body) == "string" and r.Body ~= "" then
        warn("[CAC] Discord text upload response: " .. tostring(r.Body):sub(1, 220))
    end
    return false
end

local function HandleDetectedFile(detectedFile, itemCount, sourceName, statusLabel, preloadedContent)
    local content = preloadedContent
    local readOk = true
    if not content then
        for _ = 1, 20 do
            readOk, content = pcall(function()
                return readfile(detectedFile)
            end)
            if readOk and type(content) == "string" and #content > 0 then
                break
            end
            local _, canonical = CanReadExport(detectedFile)
            if canonical then
                detectedFile = canonical
            end
            task.wait(0.2)
        end
    end
    if not readOk or type(content) ~= "string" then
        Notify("Error", "Could not read generated file.")
        warn("[CAC] Failed reading export path: " .. tostring(detectedFile))
        return false
    end
    if content == "" then
        Notify("Error", "Generated file is empty.")
        warn("[CAC] Export file is empty at path: " .. tostring(detectedFile))
        return false
    end

    local fileSize = #content
    local limitBytes = 9.5 * 1024 * 1024 -- 9.5 MB

    if fileSize > limitBytes then
        if statusLabel then statusLabel.Text = "Status: File too large, saving locally..." end
        
        if not isfolder(Globals.DumpsFolder) then makefolder(Globals.DumpsFolder) end

        local timeStr = os.date("%H-%M-%S")
        local finalName = itemCount .. "_Rigs_" .. sourceName .. "_" .. timeStr .. ".rbxmx"
        finalName = finalName:gsub(" ", "_"):gsub("[^a-zA-Z0-9_%.%-]", "")
        local targetPath = Globals.DumpsFolder .. "/" .. finalName
        
        local wrote = SafeWriteText(targetPath, content)
        if not wrote then
            Notify("Error", "Failed to save local dump file in this executor.")
            return false
        end
        pcall(function()
            delfile(detectedFile)
        end)
        
        local sizeMB = string.format("%.2f", fileSize / 1024 / 1024)
        Notify("Saved Locally", "File is " .. sizeMB .. "MB (>9.5MB). Saved to " .. Globals.DumpsFolder)
        
        if statusLabel then statusLabel.Text = "Status: Saved to local dumps folder." end
    else
        if statusLabel then statusLabel.Text = "Status: Sending via Webhook..." end
        local sent = UploadToDiscord(detectedFile, content, itemCount, sourceName)
        if statusLabel then
            statusLabel.Text = sent and "Status: Process Finished." or "Status: Webhook failed (file kept)."
        end
    end
    return true
end

local function WaitAndProcessExport(targetPath, itemCount, sourceName, statusLabel, timeoutSeconds)
    local ok, detectedPath = WaitForFile(targetPath, timeoutSeconds)
    if not ok then
        local fallback = FindExportFallback(targetPath)
        if fallback then
            detectedPath = fallback
            ok = true
        end
    end

    if ok and detectedPath then
        local _, canonicalPath = CanReadExport(detectedPath)
        if canonicalPath then
            detectedPath = canonicalPath
        end
    end

    if not ok or not detectedPath or detectedPath == "" then
        Notify("Error", "File generation timed out: " .. tostring(targetPath))
        if statusLabel then
            statusLabel.Text = "Status: Export timeout. Try again."
        end
        return false
    end

    local preloadedContent = nil
    if detectedPath then
        local readOk, content = pcall(function()
            return readfile(detectedPath)
        end)
        if readOk and type(content) == "string" and #content > 0 then
            preloadedContent = content
        end
    end

    return HandleDetectedFile(detectedPath, itemCount, sourceName, statusLabel, preloadedContent)
end

function Factory.GenerateTemplates()
    local cache = Instance.new("Folder")
    cache.Name = "_TemplateCache"
    local emptyDesc = Instance.new("HumanoidDescription")

    local r15 = Players:CreateHumanoidModelFromDescription(emptyDesc, Enum.HumanoidRigType.R15)
    r15.Name = "R15_Template"
    r15.Parent = cache

    local r6 = Players:CreateHumanoidModelFromDescription(emptyDesc, Enum.HumanoidRigType.R6)
    r6.Name = "R6_Template"
    r6.Parent = cache

    for _, rig in ipairs({r15, r6}) do
        for _, d in ipairs(rig:GetDescendants()) do
            if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Animate") then d:Destroy() end
        end
    end
    return {R15 = r15, R6 = r6, Cache = cache}
end

function Factory.CleanRig(rig)
    local hum = rig:FindFirstChild("Humanoid")
    if hum then hum:RemoveAccessories() end
    for _, c in ipairs(rig:GetChildren()) do
        if c:IsA("Accessory") or c:IsA("Shirt") or c:IsA("Pants") or c:IsA("BodyColors") or c:IsA("ShirtGraphic") or c:IsA("CharacterMesh") then
            c:Destroy()
        end
    end
end

function Factory.WaitStable(rig)
    local frames = 4
    local last = 0
    local stable = 0
    local tries = 0
    while stable < frames and tries < 40 do
        tries = tries + 1
        local count = #rig:GetDescendants()
        if count == last then stable = stable + 1 else stable = 0; last = count end
        RunService.Heartbeat:Wait()
    end
end

function Factory.ForceColors(rig, desc)
    if not desc then return end
    local bc = rig:FindFirstChild("Body Colors") or Instance.new("BodyColors", rig)
    bc.HeadColor3 = desc.HeadColor
    bc.TorsoColor3 = desc.TorsoColor
    bc.LeftArmColor3 = desc.LeftArmColor; bc.RightArmColor3 = desc.RightArmColor
    bc.LeftLegColor3 = desc.LeftLegColor; bc.RightLegColor3 = desc.RightLegColor
    
    for _, part in pairs(rig:GetChildren()) do
        if part:IsA("BasePart") then
            if part.Name == "Head" then part.Color = desc.HeadColor end
            if part.Name:find("Torso") then part.Color = desc.TorsoColor end
            if part.Name:find("Left") then 
                part.Color = (part.Name:find("Leg") or part.Name:find("Foot")) and desc.LeftLegColor or desc.LeftArmColor
            end
            if part.Name:find("Right") then 
                part.Color = (part.Name:find("Leg") or part.Name:find("Foot")) and desc.RightLegColor or desc.RightArmColor
            end
        end
    end
end

function Factory.ProcessAndSave(outfits, tag, statusLabel)
    if IsCancelled() then
        Notify("System", "Task cancelled before rig generation.")
        return
    end

    if #outfits == 0 then return Notify("Empty Queue", "No outfits found to process.") end

    if statusLabel then statusLabel.Text = "Status: Constructing " .. #outfits .. " physical rigs..." end
    Notify("Factory Engine", "Building " .. #outfits .. " rigs in memory cache...")

    local export = Instance.new("Folder")
    export.Name = "Export_Rigs"
    export.Parent = ReplicatedStorage

    local templates = Factory.GenerateTemplates()

    for i, data in ipairs(outfits) do
        if IsCancelled() then
            Notify("System", "Task cancelled during rig generation.")
            break
        end

        if statusLabel and i % 10 == 0 then
             local pct = math.floor((i / #outfits) * 100)
             statusLabel.Text = "Building Rigs: " .. i .. "/" .. #outfits .. " (" .. pct .. "%)"
        end

        local rigType = Enum.HumanoidRigType.R15 
        if data.RigType == "R6" or data.RigType == Enum.HumanoidRigType.R6 then
            rigType = Enum.HumanoidRigType.R6
        end

        local rig = (rigType == Enum.HumanoidRigType.R6) and templates.R6:Clone() or templates.R15:Clone()
        
        rig.Name = "Outfit_" .. i
        rig.Parent = export

        Factory.CleanRig(rig)
        local hum = rig:FindFirstChild("Humanoid")

        if hum and data.Description then
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
            hum.DisplayName = " "
            pcall(function() hum:ApplyDescription(data.Description) end)
            
            Factory.WaitStable(rig)
            for _, m in ipairs(rig:GetDescendants()) do
                if m:IsA("Motor6D") and not m.Enabled then
                    m.Enabled = true
                end
            end
            Factory.ForceColors(rig, data.Description)
        end
        
        local row = math.floor((i - 1) / 10)
        local col = (i - 1) % 10
        rig:PivotTo(CFrame.new(col * 7, 5, row * 7))
        
        local root = rig:FindFirstChild("HumanoidRootPart") or rig:FindFirstChild("Torso")
        if root then root.Anchored = true end
        
        if data.Code then
            local v = Instance.new("StringValue", rig)
            v.Name = "SourceCode"
            v.Value = tostring(data.Code)
        end
        
        if i % 25 == 0 then task.wait() end
    end

    templates.Cache:Destroy()
    if IsCancelled() then
        export:Destroy()
        return
    end

    if statusLabel then statusLabel.Text = "Status: Writing optimized file to disk..." end
    Notify("File System", "Writing optimized file to disk...")
    
    local filename = Globals.WorkFolder .. "/Dump_" .. os.time() .. "_" .. math.random(1000,9999) .. ".rbxm"
    export.Parent = nil 
    
    local s, e, saveKind, saveProfile = SaveInstanceCompat(export, filename, statusLabel)

    export:Destroy()

    if not s then
        warn("[CAC] SaveInstance warning: " .. tostring(e))
        Notify("Warning", "SaveInstance delayed. Attempting recovery...")
        if statusLabel then
            statusLabel.Text = "Status: Save delayed, checking file on disk..."
        end
    else
        warn("[CAC] SaveInstance dispatched via " .. tostring(saveProfile) .. "/" .. tostring(saveKind) .. " on " .. tostring(ExecutorName))
    end

    local waitTime = math.clamp(math.floor((#outfits / 35)) + 10, 10, 75)
    local processed = WaitAndProcessExport(filename, #outfits, tag, statusLabel, waitTime)
    if not processed and not s then
        Notify("Critical Error", "File generation failed: " .. tostring(e))
    elseif not processed then
        Notify("Error", "Generated file could not be processed.")
    end
end

-- ==================================================================
-- DUMPERS (PERSISTENT LOGIC)
-- ==================================================================
local Dumpers = {}
local Remote = ReplicatedStorage:FindFirstChild("CommunityOutfitsRemote")

local SerializationModule = nil

local function ResolveCommunityOutfitsRemote(timeoutSeconds)
    if Remote then
        return Remote
    end

    local deadline = os.clock() + (tonumber(timeoutSeconds) or 0)
    repeat
        Remote = ReplicatedStorage:FindFirstChild("CommunityOutfitsRemote")
        if Remote then
            return Remote
        end
        if os.clock() >= deadline then
            break
        end
        task.wait(0.05)
    until IsCancelled()

    return Remote
end

local function ResolveSerializationModule(timeoutSeconds)
    if SerializationModule then
        return SerializationModule
    end

    local deadline = os.clock() + (tonumber(timeoutSeconds) or 0)
    repeat
        local moduleScript = ReplicatedStorage:FindFirstChild("OutfitSerializationFunctions", true)
        if moduleScript and moduleScript:IsA("ModuleScript") then
            local okModule, moduleValue = pcall(function()
                return require(moduleScript)
            end)
            if okModule and moduleValue then
                SerializationModule = moduleValue
                return SerializationModule
            end
        end
        if os.clock() >= deadline then
            break
        end
        task.wait(0.05)
    until IsCancelled()

    return SerializationModule
end

local function WarmupCommunityOutfits()
    local remote = ResolveCommunityOutfitsRemote(2)
    if not remote or not LocalPlayer then return end
    pcall(function()
        remote:InvokeServer({
            Action = "GetCommunityOutfits",
            Creator = LocalPlayer.UserId,
            BatchNumber = 1,
            BatchSize = 1,
            Category = "Most Popular"
        })
    end)
end

local function RestoreCACGameUI()
    pcall(function()
        local toggle = ReplicatedStorage:FindFirstChild("ClientToggleUIVisible")
        if toggle and toggle.Fire then
            toggle:Fire(true, {}, true)
        end
    end)
end

local function HasActiveQueueResume()
    local state = PendingQueueResume or ReadQueueState()
    if type(state) ~= "table" then
        return false
    end
    if state.auto_rejoin_cancelled == true then
        return false
    end
    return state.task == "auto_publish" or state.task == "code_extract"
end

local function BuildDescriptionFromItems(items)
    local serialization = ResolveSerializationModule(2)
    if not items or not serialization then return nil end
    local desc = nil
    pcall(function()
        desc = serialization:CreateHumanDescFromPropertyValues(items)
    end)
    return desc
end

local CREATOR_BATCH_SIZE = 25
local MAX_CREATOR_BATCHES = 320
local MAX_CREATOR_OUTFITS = 4000
local CREATOR_BATCH_RETRIES = 3
local CREATOR_EMPTY_RECHECKS = 6
local CREATOR_EMPTY_RECHECK_DELAY = 0.18
local CREATOR_MAX_SEQUENTIAL_FETCH_FAILURES = 3
local CREATOR_REMOTE_ATTEMPTS = 8

local CREATOR_CATEGORY_LABELS = {
    MOST_POPULAR = "Most Popular",
    TRENDING = "Trending",
    NEWEST = "Newest",
    OLDEST = "Oldest",
    RECENT = "Recent",
    FAVORITED = "Favorited",
    PRICE_DESC = "Price (Highest to Lowest)",
    PRICE_ASC = "Price (Lowest to Highest)",
}

local CREATOR_CATEGORY_ORDER = {
    "MOST_POPULAR",
    "TRENDING",
    "NEWEST",
    "OLDEST",
    "RECENT",
    "FAVORITED",
    "PRICE_DESC",
    "PRICE_ASC",
}

local SavedOutfitsTrace = {
    Active = false,
    StartedAt = 0,
    DurationSeconds = 0,
    MaxEntries = 6000,
    Entries = {},
    Dropped = 0,
    Connections = {},
    FilePath = nil,
    NamecallHookInstalled = false,
    CaptureAllRemotes = true,
    AutoStopId = 0
}

local function TraceNowIso()
    local ok, iso = pcall(function()
        return os.date("!%Y-%m-%dT%H:%M:%SZ")
    end)
    if ok and iso and iso ~= "" then
        return tostring(iso)
    end
    return tostring(os.time())
end

local function TraceSafePath(inst)
    if typeof(inst) ~= "Instance" then
        return tostring(inst)
    end
    local ok, full = pcall(function()
        return inst:GetFullName()
    end)
    if ok and full then
        return tostring(full)
    end
    return tostring(inst.Name)
end

local function TraceShortText(value, maxLen)
    local txt = tostring(value or "")
    local lim = tonumber(maxLen) or 140
    if #txt <= lim then
        return txt
    end
    return txt:sub(1, lim - 3) .. "..."
end

local function HasSavedOutfitKeyword(value)
    local txt = string.lower(tostring(value or ""))
    if txt == "" then
        return false
    end
    return string.find(txt, "outfit", 1, true)
        or string.find(txt, "saved", 1, true)
        or string.find(txt, "wardrobe", 1, true)
        or string.find(txt, "avatar", 1, true)
        or string.find(txt, "closet", 1, true)
        or string.find(txt, "look", 1, true)
end

local function TraceValueContainsKeyword(v, depth)
    depth = depth or 0
    if depth > 2 then
        return false
    end

    local t = typeof(v)
    if t == "string" then
        return HasSavedOutfitKeyword(v)
    end
    if t == "Instance" then
        return HasSavedOutfitKeyword(v.Name) or HasSavedOutfitKeyword(TraceSafePath(v))
    end
    if t == "table" then
        local scanned = 0
        for k, val in pairs(v) do
            scanned = scanned + 1
            if scanned > 20 then
                break
            end
            if TraceValueContainsKeyword(k, depth + 1) or TraceValueContainsKeyword(val, depth + 1) then
                return true
            end
        end
    end
    return false
end

local function TraceBriefValue(v, depth)
    depth = depth or 0
    if depth > 2 then
        return "<max-depth>"
    end

    local t = typeof(v)
    if t == "nil" then
        return nil
    end
    if t == "string" then
        return TraceShortText(v, 180)
    end
    if t == "number" or t == "boolean" then
        return v
    end
    if t == "Instance" then
        return {
            type = "Instance",
            class = v.ClassName,
            name = v.Name,
            path = TraceSafePath(v)
        }
    end
    if t == "table" then
        local out = { __type = "table" }
        local scanned = 0
        for k, val in pairs(v) do
            scanned = scanned + 1
            if scanned > 12 then
                out["__truncated"] = true
                break
            end
            out[TraceShortText(tostring(k), 60)] = TraceBriefValue(val, depth + 1)
        end
        return out
    end
    return TraceShortText(tostring(v), 180)
end

local function TraceBriefArgs(args)
    local out = {}
    for i = 1, math.min(#args, 10) do
        out[tostring(i)] = TraceBriefValue(args[i], 0)
    end
    if #args > 10 then
        out["__truncated"] = #args - 10
    end
    return out
end

local function TracePush(eventType, payload)
    if not SavedOutfitsTrace.Active then
        return
    end

    if #SavedOutfitsTrace.Entries >= SavedOutfitsTrace.MaxEntries then
        SavedOutfitsTrace.Dropped = SavedOutfitsTrace.Dropped + 1
        return
    end

    table.insert(SavedOutfitsTrace.Entries, {
        ts = os.time(),
        iso = TraceNowIso(),
        since_start_s = math.max(0, math.floor(os.clock() - (SavedOutfitsTrace.StartedAt or os.clock()))),
        event = tostring(eventType or "unknown"),
        data = payload or {}
    })
end

local function TraceAttachConnection(conn)
    if conn then
        table.insert(SavedOutfitsTrace.Connections, conn)
    end
end

local function TraceDisconnectAll()
    for _, conn in ipairs(SavedOutfitsTrace.Connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    SavedOutfitsTrace.Connections = {}
end

local function TraceResolveSavedOutfitsGui()
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return nil
    end
    return playerGui:FindFirstChild("SavedOutfitsV3") or playerGui:FindFirstChild("SavedOutfits")
end

local function TraceResolveOutfitsRoot()
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    return (LocalPlayer and LocalPlayer:FindFirstChild("Outfits"))
        or (playerGui and playerGui:FindFirstChild("SavedOutfitsV3") and playerGui.SavedOutfitsV3:FindFirstChild("Outfits"))
        or (playerGui and playerGui:FindFirstChild("SavedOutfits") and playerGui.SavedOutfits:FindFirstChild("Outfits"))
end

local function BuildSavedOutfitsSnapshot()
    local snapshot = {
        generated_at = TraceNowIso(),
        local_player = LocalPlayer and LocalPlayer.Name or "unknown",
        user_id = LocalPlayer and LocalPlayer.UserId or 0,
        roots = {},
        remotes = {}
    }

    local outfitsRoot = TraceResolveOutfitsRoot()
    if outfitsRoot then
        local info = {
            path = TraceSafePath(outfitsRoot),
            class = outfitsRoot.ClassName,
            child_count = #outfitsRoot:GetChildren(),
            descendant_count = #outfitsRoot:GetDescendants(),
            humanoid_description_nodes = 0,
            sample = {}
        }

        local sampled = 0
        for _, obj in ipairs(outfitsRoot:GetDescendants()) do
            local hd = obj:FindFirstChild("HumanoidDescription")
            if hd and hd:IsA("HumanoidDescription") then
                info.humanoid_description_nodes = info.humanoid_description_nodes + 1
                if sampled < 40 then
                    sampled = sampled + 1
                    table.insert(info.sample, {
                        name = obj.Name,
                        path = TraceSafePath(obj),
                        guid = obj:GetAttribute("GUID"),
                        outfit_id = obj:GetAttribute("OutfitId"),
                        outfit_name = obj:GetAttribute("OutfitName"),
                        folder = obj:GetAttribute("Folder") or obj:GetAttribute("OutfitFolder")
                    })
                end
            end
        end

        table.insert(snapshot.roots, {
            kind = "local_outfits_root",
            data = info
        })
    else
        table.insert(snapshot.roots, {
            kind = "local_outfits_root",
            error = "not_found"
        })
    end

    local gui = TraceResolveSavedOutfitsGui()
    if gui then
        local guiInfo = {
            path = TraceSafePath(gui),
            class = gui.ClassName,
            descendant_count = #gui:GetDescendants(),
            folder_tabs = {},
            visible_cards = 0
        }

        local outfitsNode = gui:FindFirstChild("Holder")
        outfitsNode = outfitsNode and outfitsNode:FindFirstChild("Main")
        outfitsNode = outfitsNode and outfitsNode:FindFirstChild("Outfits")
        if outfitsNode then
            local selector = outfitsNode:FindFirstChild("OutfitFolderSelector")
            selector = selector and selector:FindFirstChild("List")
            if selector then
                for _, child in ipairs(selector:GetChildren()) do
                    if child:IsA("GuiObject") then
                        local tabName = child.Name
                        if child:IsA("TextButton") or child:IsA("TextLabel") or child:IsA("TextBox") then
                            tabName = child.Text
                        end
                        table.insert(guiInfo.folder_tabs, {
                            name = tostring(tabName),
                            visible = child.Visible
                        })
                    end
                end
            end
        end

        for _, node in ipairs(gui:GetDescendants()) do
            if node:IsA("GuiObject") and node.Visible and node.AbsoluteSize.X >= 80 and node.AbsoluteSize.Y >= 80 then
                guiInfo.visible_cards = guiInfo.visible_cards + 1
            end
        end

        table.insert(snapshot.roots, {
            kind = "saved_outfits_gui",
            data = guiInfo
        })
    else
        table.insert(snapshot.roots, {
            kind = "saved_outfits_gui",
            error = "not_found"
        })
    end

    local totalRemotes = 0
    local relatedRemotes = 0
    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
            totalRemotes = totalRemotes + 1
            local full = TraceSafePath(inst)
            local related = HasSavedOutfitKeyword(inst.Name) or HasSavedOutfitKeyword(full)
            if related then
                relatedRemotes = relatedRemotes + 1
                if #snapshot.remotes < 120 then
                    table.insert(snapshot.remotes, {
                        name = inst.Name,
                        class = inst.ClassName,
                        path = full
                    })
                end
            end
        end
    end
    snapshot.remote_summary = {
        total = totalRemotes,
        related = relatedRemotes
    }

    return snapshot
end

local function SaveSavedOutfitsReportFile(prefix, payload)
    if not isfolder(Globals.WorkFolder) then
        makefolder(Globals.WorkFolder)
    end

    local name = tostring(prefix or "SavedOutfitsTrace")
    local filePath = string.format("%s/%s_%d_%d.json", Globals.WorkFolder, name, os.time(), math.random(1000, 9999))

    local okEncode, encoded = pcall(function()
        return HttpService:JSONEncode(payload)
    end)
    if not okEncode or not encoded then
        return false, nil, "json_encode_failed"
    end

    local okWrite, err = pcall(function()
        writefile(filePath, encoded)
    end)
    if not okWrite then
        return false, nil, tostring(err)
    end

    return true, filePath, nil
end

local function TraceWatchTree(root, label)
    if not root then
        return
    end

    TracePush("watch_root", {
        label = label,
        path = TraceSafePath(root),
        class = root.ClassName
    })

    local function isInteresting(inst)
        if not inst then return false end
        local lowerPath = string.lower(TraceSafePath(inst))
        local inOutfitTree = string.find(lowerPath, ".outfits", 1, true)
            or string.find(lowerPath, "savedoutfitsv3.holder.main.outfits", 1, true)
            or string.find(lowerPath, "savedoutfits.holder.main.outfits", 1, true)

        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
            return true
        end
        if inst:IsA("HumanoidDescription") then
            return true
        end
        if not inOutfitTree then
            return false
        end
        if inst:IsA("StringValue") or inst:IsA("IntValue") or inst:IsA("NumberValue") then
            return true
        end
        if inst:GetAttribute("GUID") ~= nil
            or inst:GetAttribute("OutfitId") ~= nil
            or inst:GetAttribute("OutfitName") ~= nil
            or inst:GetAttribute("Folder") ~= nil
            or inst:GetAttribute("OutfitFolder") ~= nil
        then
            return true
        end
        return false
    end

    local okAdded, conAdded = pcall(function()
        return root.DescendantAdded:Connect(function(inst)
            if SavedOutfitsTrace.Active and isInteresting(inst) then
                TracePush("desc_added", {
                    label = label,
                    class = inst.ClassName,
                    name = inst.Name,
                    path = TraceSafePath(inst)
                })
            end
        end)
    end)
    if okAdded then
        TraceAttachConnection(conAdded)
    end

    local okRemoving, conRemoving = pcall(function()
        return root.DescendantRemoving:Connect(function(inst)
            if SavedOutfitsTrace.Active and isInteresting(inst) then
                TracePush("desc_removing", {
                    label = label,
                    class = inst.ClassName,
                    name = inst.Name,
                    path = TraceSafePath(inst)
                })
            end
        end)
    end)
    if okRemoving then
        TraceAttachConnection(conRemoving)
    end
end

local function TraceWatchInboundRemoteEvents()
    local function bindRemote(remote)
        if not remote or not remote:IsA("RemoteEvent") then
            return
        end
        local full = TraceSafePath(remote)
        local related = HasSavedOutfitKeyword(remote.Name) or HasSavedOutfitKeyword(full)
        if not related and not SavedOutfitsTrace.CaptureAllRemotes then
            return
        end

        local okConn, conn = pcall(function()
            return remote.OnClientEvent:Connect(function(...)
                if not SavedOutfitsTrace.Active then
                    return
                end
                local args = { ... }
                local argsRelated = TraceValueContainsKeyword(args, 0)
                if related or argsRelated or SavedOutfitsTrace.CaptureAllRemotes then
                    TracePush("remote_inbound", {
                        class = remote.ClassName,
                        name = remote.Name,
                        path = full,
                        related = related or argsRelated,
                        args = TraceBriefArgs(args)
                    })
                end
            end)
        end)
        if okConn then
            TraceAttachConnection(conn)
        end
    end

    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if inst:IsA("RemoteEvent") then
            bindRemote(inst)
        end
    end

    local okAdded, conAdded = pcall(function()
        return ReplicatedStorage.DescendantAdded:Connect(function(inst)
            if SavedOutfitsTrace.Active and (inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")) then
                TracePush("remote_discovered", {
                    class = inst.ClassName,
                    name = inst.Name,
                    path = TraceSafePath(inst)
                })
            end
            if inst:IsA("RemoteEvent") then
                bindRemote(inst)
            end
        end)
    end)
    if okAdded then
        TraceAttachConnection(conAdded)
    end
end

local function EnsureNamecallRemoteTraceHook()
    if SavedOutfitsTrace.NamecallHookInstalled then
        return true, nil
    end

    if not hookmetamethod or not getnamecallmethod or not newcclosure then
        return false, "Executor missing hookmetamethod/getnamecallmethod/newcclosure."
    end

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if SavedOutfitsTrace.Active and (method == "FireServer" or method == "InvokeServer") then
            if typeof(self) == "Instance" and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
                local args = { ... }
                local path = TraceSafePath(self)
                local related = HasSavedOutfitKeyword(self.Name) or HasSavedOutfitKeyword(path) or TraceValueContainsKeyword(args, 0)
                if related or SavedOutfitsTrace.CaptureAllRemotes then
                    TracePush("remote_outbound", {
                        method = method,
                        class = self.ClassName,
                        name = self.Name,
                        path = path,
                        related = related,
                        args = TraceBriefArgs(args)
                    })
                end
            end
        end
        return oldNamecall(self, ...)
    end))

    SavedOutfitsTrace.NamecallHookInstalled = true
    return true, nil
end

local function StopSavedOutfitsTraceInternal(statusLabel, reason)
    if not SavedOutfitsTrace.Active then
        return false, nil
    end

    TracePush("trace_stop", {
        reason = tostring(reason or "manual_stop"),
        dropped_entries = SavedOutfitsTrace.Dropped
    })
    SavedOutfitsTrace.Active = false
    TraceDisconnectAll()

    local report = {
        meta = {
            generated_at = TraceNowIso(),
            reason = tostring(reason or "manual_stop"),
            duration_seconds = math.max(0, math.floor(os.clock() - (SavedOutfitsTrace.StartedAt or os.clock()))),
            dropped_entries = SavedOutfitsTrace.Dropped,
            max_entries = SavedOutfitsTrace.MaxEntries,
            capture_all_remotes = SavedOutfitsTrace.CaptureAllRemotes
        },
        snapshot = BuildSavedOutfitsSnapshot(),
        entries = SavedOutfitsTrace.Entries
    }

    local okSave, pathOrNil, err = SaveSavedOutfitsReportFile("SavedOutfitsTrace", report)
    SavedOutfitsTrace.Entries = {}
    SavedOutfitsTrace.Dropped = 0
    SavedOutfitsTrace.FilePath = pathOrNil

    if okSave then
        if statusLabel then
            statusLabel.Text = "Status: SavedOutfits trace exported to " .. tostring(pathOrNil)
        end
        Notify("Trace Saved", "SavedOutfits trace file generated: " .. tostring(pathOrNil))
        return true, pathOrNil
    end

    if statusLabel then
        statusLabel.Text = "Status: Failed to save trace file."
    end
    Notify("Error", "Failed to save trace file: " .. tostring(err or "unknown"))
    return false, nil
end

function Dumpers.StartSavedOutfitsTrace(durationInput, statusLabel)
    if SavedOutfitsTrace.Active then
        return Notify("Info", "SavedOutfits trace is already running.")
    end

    local duration = tonumber(tostring(durationInput or "")) or 45
    duration = math.clamp(math.floor(duration), 10, 600)

    SavedOutfitsTrace.Active = true
    SavedOutfitsTrace.StartedAt = os.clock()
    SavedOutfitsTrace.DurationSeconds = duration
    SavedOutfitsTrace.Entries = {}
    SavedOutfitsTrace.Dropped = 0
    SavedOutfitsTrace.AutoStopId = SavedOutfitsTrace.AutoStopId + 1
    local myRunId = SavedOutfitsTrace.AutoStopId

    local hookOk, hookErr = EnsureNamecallRemoteTraceHook()
    if not hookOk then
        TracePush("hook_warning", { message = hookErr })
        Notify("Warning", "Remote hook unavailable: " .. tostring(hookErr))
    end

    TraceWatchTree(LocalPlayer, "LocalPlayer")
    TraceWatchTree(LocalPlayer and LocalPlayer:FindFirstChild("Outfits"), "LocalPlayer.Outfits")
    TraceWatchTree(TraceResolveSavedOutfitsGui(), "PlayerGui.SavedOutfits")
    TraceWatchInboundRemoteEvents()

    TracePush("trace_start", {
        duration_seconds = duration,
        work_folder = Globals.WorkFolder
    })
    TracePush("snapshot_start", BuildSavedOutfitsSnapshot())

    if statusLabel then
        statusLabel.Text = "Status: SavedOutfits trace running for " .. tostring(duration) .. "s..."
    end
    Notify("Tracer", "SavedOutfits trace started for " .. tostring(duration) .. " seconds.")

    task.spawn(function()
        local started = os.clock()
        while SavedOutfitsTrace.Active and myRunId == SavedOutfitsTrace.AutoStopId do
            local elapsed = math.max(0, math.floor(os.clock() - started))
            local left = math.max(0, duration - elapsed)
            if statusLabel and left >= 0 then
                statusLabel.Text = "Status: Tracing remotes/saved outfits... " .. tostring(left) .. "s left."
            end
            if elapsed >= duration then
                break
            end
            task.wait(1)
        end

        if SavedOutfitsTrace.Active and myRunId == SavedOutfitsTrace.AutoStopId then
            StopSavedOutfitsTraceInternal(statusLabel, "duration_elapsed")
        end
    end)
end

function Dumpers.StopSavedOutfitsTrace(statusLabel)
    if not SavedOutfitsTrace.Active then
        return Notify("Info", "SavedOutfits trace is not active.")
    end
    StopSavedOutfitsTraceInternal(statusLabel, "manual_stop")
end

function Dumpers.ExportSavedOutfitsSnapshot(statusLabel)
    local snapshot = BuildSavedOutfitsSnapshot()
    local okSave, pathOrNil, err = SaveSavedOutfitsReportFile("SavedOutfitsSnapshot", snapshot)
    if okSave then
        if statusLabel then
            statusLabel.Text = "Status: SavedOutfits snapshot exported."
        end
        Notify("Snapshot Saved", "SavedOutfits snapshot file: " .. tostring(pathOrNil))
        return
    end
    Notify("Error", "Could not save SavedOutfits snapshot: " .. tostring(err or "unknown"))
end

local function NormalizeCreatorBatch(response)
    if type(response) ~= "table" then
        return {}, nil
    end

    local totalHint = tonumber(response.TotalCount or response.Total or response.Count)
    if #response > 0 then
        return response, totalHint
    end

    local keys = { "Outfits", "Results", "Data", "Items" }
    for _, key in ipairs(keys) do
        if type(response[key]) == "table" then
            return response[key], totalHint
        end
    end

    return {}, totalHint
end

local function BuildCreatorUniqueKey(raw)
    if type(raw) ~= "table" then
        return nil
    end

    if type(raw.Items) == "table" and #raw.Items > 0 then
        local itemsSig = nil
        pcall(function()
            itemsSig = HttpService:JSONEncode(raw.Items)
        end)
        if itemsSig and #itemsSig > 0 then
            local stableKey = raw.Id or raw.OutfitId or raw.Code or raw.AssetId or "NO_ID"
            return string.format(
                "sig:%s|%s|%s|%s",
                tostring(stableKey),
                tostring(raw.RigType or ""),
                tostring(raw.Name or ""),
                itemsSig
            )
        end
    end

    local stableKey = raw.Id or raw.OutfitId or raw.Code or raw.AssetId
    if stableKey ~= nil then
        return string.format(
            "id:%s|%s|%s",
            tostring(stableKey),
            tostring(raw.RigType or ""),
            tostring(raw.Name or "")
        )
    end

    return nil
end

local function BuildCreatorCategoryPlan()
    local categories = {}
    for _, key in ipairs(CREATOR_CATEGORY_ORDER) do
        table.insert(categories, key)
    end
    return categories
end

local function RobustCreatorInvoke(action, args, maxAttempts)
    args = args or {}
    local attempts = maxAttempts or CREATOR_REMOTE_ATTEMPTS
    local backoff = 0.2

    for attempt = 1, attempts do
        if IsCancelled() then
            return nil, "Cancelled"
        end

        local ok, result = pcall(function()
            args.Action = action
            return Remote:InvokeServer(args)
        end)

        if ok and result ~= nil and result ~= "OnCooldown" then
            return result, nil
        end

        if attempt < attempts then
            if result == "OnCooldown" then
                task.wait(math.min(backoff + 0.2, 2.0))
            else
                task.wait(backoff)
            end
            backoff = math.min(backoff * 1.5, 2.0)
        end
    end

    return nil, "RequestFailed"
end

local function FetchCreatorBatch(creatorUserId, batchNumber, categoryKey)
    local remoteCategory = CREATOR_CATEGORY_LABELS[categoryKey] or "Most Popular"
    local response, err = RobustCreatorInvoke("GetCommunityOutfits", {
        Creator = creatorUserId,
        BatchNumber = batchNumber,
        BatchSize = CREATOR_BATCH_SIZE,
        Category = remoteCategory
    }, CREATOR_REMOTE_ATTEMPTS)

    if not response then
        return nil, nil, err or "RequestFailed"
    end

    local outfits, totalHint = NormalizeCreatorBatch(response)
    return outfits, totalHint, nil
end

local function ParseHexCodes(rawText)
    local list = {}
    local seen = {}

    if type(rawText) == "table" then
        for _, entry in ipairs(rawText) do
            local n = tonumber(entry)
            if n and not seen[n] then
                seen[n] = true
                table.insert(list, n)
            end
        end
        return list
    end

    for match in string.gmatch(tostring(rawText or ""), "[a-fA-F0-9]+") do
        if #match >= 6 and #match <= 8 then
            local parsed = tonumber(match, 16)
            if parsed and not seen[parsed] then
                seen[parsed] = true
                table.insert(list, parsed)
            end
        end
    end
    return list
end

local function BuildCollectedFromCodeRecords(records)
    local collected = {}
    for _, row in ipairs(records or {}) do
        if row and row.Items then
            local desc = BuildDescriptionFromItems(row.Items)
            if desc then
                table.insert(collected, {
                    Description = desc,
                    Name = row.Name or ("Code_" .. tostring(row.Code or "Unknown")),
                    Code = tostring(row.Code or ""),
                    RigType = row.RigType or "R15"
                })
            end
        end
    end
    return collected
end

local function RunCodeQueueState(queueState, statusLabel)
    local codes = queueState.codes or {}
    local records = queueState.records or {}
    local nextIndex = tonumber(queueState.next_index) or 1
    local cooldownCount = tonumber(queueState.cooldown_count) or 0
    local processedCount = tonumber(queueState.processed_count) or #records
    local adaptiveDelay = tonumber(queueState.adaptive_delay) or 0.5
    local successSinceRejoin = tonumber(queueState.success_since_rejoin) or 0
    local codeAutoRejoinEnabled = queueState.auto_rejoin_enabled == true or Globals.AutoRejoinCodeEnabled == true
    local codeAutoRejoinMode = tostring(queueState.auto_rejoin_mode or Globals.AutoRejoinCodeMode or AUTO_REJOIN_MODE)
    local maximizeAutoRejoin = queueState.maximize_auto_rejoin == true or Globals.MaximizeAutoRejoin == true
    local currentJobId = tostring(game.JobId or "")
    if tostring(queueState.last_job_id or "") ~= currentJobId then
        successSinceRejoin = 0
        queueState.success_since_rejoin = 0
        queueState.last_job_id = currentJobId
        WriteQueueState(queueState)
    end

    local minDelay = 0.25
    local maxDelay = 2.2
    local maxAttempts = 12

    if statusLabel then
        statusLabel.Text = "Status: Code queue found " .. tostring(#codes) .. " targets. Starting at index " .. tostring(nextIndex) .. "..."
    end
    Notify("System", "Starting queue for " .. #codes .. " targets.")

    if not ResolveCommunityOutfitsRemote(3) then
        return Notify("Error", "CommunityOutfitsRemote was not found.")
    end
    if not ResolveSerializationModule(3) then
        return Notify("Error", "OutfitSerializationFunctions module was not found.")
    end

    for i = nextIndex, #codes do
        if IsCancelled() then
            break
        end

        local code = codes[i]
        queueState.next_index = i
        queueState.cooldown_count = cooldownCount
        queueState.processed_count = processedCount
        queueState.adaptive_delay = adaptiveDelay
        queueState.success_since_rejoin = successSinceRejoin
        queueState.records = records
        WriteQueueState(queueState)

        if statusLabel then
            local remaining = #codes - i + 1
            local eta = math.ceil(remaining * math.max(0.5, adaptiveDelay + 0.5))
            statusLabel.Text = "Processing: " .. i .. "/" .. #codes .. " | Success: " .. processedCount .. " | Cooldowns: " .. cooldownCount .. " | ETA: " .. eta .. "s"
        end

        local processed = false
        local attempts = 0

        while not processed and attempts < maxAttempts do
            if IsCancelled() then
                break
            end

            local ok, response = pcall(function()
                return Remote:InvokeServer({ Action = "GetFromOutfitCode", OutfitCode = code })
            end)

            if ok then
                if response == "OnCooldown" then
                    attempts = attempts + 1
                    cooldownCount = cooldownCount + 1
                    adaptiveDelay = math.min(maxDelay, adaptiveDelay * 1.25)

                    if codeAutoRejoinEnabled then
                        queueState.next_index = i
                        queueState.cooldown_count = cooldownCount
                        queueState.processed_count = processedCount
                        queueState.adaptive_delay = adaptiveDelay
                        queueState.success_since_rejoin = 0
                        queueState.records = records
                        queueState.auto_rejoin_enabled = true
                        queueState.auto_rejoin_mode = codeAutoRejoinMode
                        WriteQueueState(queueState)
                        if statusLabel then
                            statusLabel.Text = "Status: Cooldown hit. Saving queue and rejoining..."
                        end
                        if not ConfirmQueueAutoRejoin(queueState, "code_extract", i, statusLabel) then
                            return "paused"
                        end
                        AttemptAutoRejoin("Code queue paused at index " .. tostring(i), codeAutoRejoinMode)
                        return "rejoin"
                    end

                    if statusLabel then
                        statusLabel.Text = "Status: API cooldown hit. Waiting 15s before retry..."
                    end
                    task.wait(15)
                elseif response and response.Items then
                    table.insert(records, {
                        Code = code,
                        Name = response.Name or ("Code_" .. tostring(code)),
                        RigType = response.RigType or "R15",
                        Items = response.Items
                    })
                    processedCount = processedCount + 1
                    successSinceRejoin = successSinceRejoin + 1
                    adaptiveDelay = math.max(minDelay, adaptiveDelay * 0.9)
                    queueState.last_rejoin_key = nil
                    queueState.rejoin_loop_count = 0
                    processed = true
                else
                    attempts = attempts + 1
                    adaptiveDelay = math.min(maxDelay, adaptiveDelay * 1.08)
                    task.wait(adaptiveDelay)
                end
            else
                attempts = attempts + 1
                adaptiveDelay = math.min(maxDelay, adaptiveDelay * 1.15)
                task.wait(math.max(1.2, adaptiveDelay))
            end
        end

        queueState.next_index = i + 1
        queueState.cooldown_count = cooldownCount
        queueState.processed_count = processedCount
        queueState.adaptive_delay = adaptiveDelay
        queueState.success_since_rejoin = successSinceRejoin
        queueState.records = records
        WriteQueueState(queueState)

        if not processed and statusLabel then
            statusLabel.Text = "Status: Failed to process code " .. tostring(code) .. " after max retries."
        end

        if IsCancelled() then
            break
        end
        if processed and maximizeAutoRejoin and successSinceRejoin >= MAXIMIZE_REJOIN_SUCCESS_THRESHOLD and i < #codes then
            queueState.next_index = i + 1
            queueState.cooldown_count = cooldownCount
            queueState.processed_count = processedCount
            queueState.adaptive_delay = adaptiveDelay
            queueState.success_since_rejoin = 0
            queueState.records = records
            queueState.maximize_auto_rejoin = true
            WriteQueueState(queueState)
            if statusLabel then
                statusLabel.Text = "Status: Maximize Auto-Rejoin triggered after 5 successes. Rejoining now..."
            end
            AttemptAutoRejoin("Maximize auto-rejoin triggered after 5 code successes.", codeAutoRejoinMode, true)
            return "rejoin"
        end
        task.wait(adaptiveDelay + (math.random() * 0.08))
    end

    if IsCancelled() then
        Notify("System", "Code extraction cancelled by user.")
        return "cancelled"
    end

    local collected = BuildCollectedFromCodeRecords(records)
    if #collected <= 0 then
        Notify("Empty Queue", "No valid outfits were collected from the code queue.")
        return "empty"
    end

    Factory.ProcessAndSave(collected, "CodeList", statusLabel)
    ClearQueueState()
    return "done"
end

function Dumpers.ResumeCodeQueue(statusLabel)
    local state = ReadQueueState()
    if not state or state.task ~= "code_extract" then
        return Notify("Info", "No pending code queue was found.")
    end
    if statusLabel then
        local total = type(state.codes) == "table" and #state.codes or 0
        statusLabel.Text = "Status: Code queue found " .. tostring(total) .. " targets. Starting at index " .. tostring(state.next_index or 1) .. "..."
    end
    Notify("System", "Resuming code queue from index " .. tostring(state.next_index or 1) .. ".")
    RunCodeQueueState(state, statusLabel)
end

function Dumpers.CodeList(rawText, statusLabel)
    if not ResolveCommunityOutfitsRemote(5) then
        return Notify("Error", "CommunityOutfitsRemote was not found.")
    end
    if not ResolveSerializationModule(5) then
        return Notify("Error", "OutfitSerializationFunctions module was not found.")
    end

    local codes = ParseHexCodes(rawText)
    if #codes == 0 then
        return Notify("Error", "No valid hex codes found in input.")
    end

    local queueState = {
        version = 2,
        task = "code_extract",
        created_at = os.time(),
        next_index = 1,
        codes = codes,
        records = {},
        cooldown_count = 0,
        processed_count = 0,
        adaptive_delay = 0.5,
        success_since_rejoin = 0,
        auto_rejoin_enabled = Globals.AutoRejoinCodeEnabled == true,
        auto_rejoin_mode = tostring(Globals.AutoRejoinCodeMode or AUTO_REJOIN_MODE),
        maximize_auto_rejoin = Globals.MaximizeAutoRejoin == true,
        auto_rejoin_confirmed = false,
        auto_rejoin_cancelled = false,
        rejoin_loop_count = 0
    }

    WriteQueueState(queueState)
    RunCodeQueueState(queueState, statusLabel)
end

function Dumpers.Creator(username, statusLabel)
    if not ResolveCommunityOutfitsRemote(5) then
        return Notify("Error", "CommunityOutfitsRemote was not found.")
    end
    if not ResolveSerializationModule(5) then
        return Notify("Error", "OutfitSerializationFunctions module was not found.")
    end

    local targetName = tostring(username or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if targetName == "" then
        return Notify("Error", "Enter a creator username first.")
    end

    local uid
    pcall(function() uid = Players:GetUserIdFromNameAsync(targetName) end)
    if not uid then return Notify("Error", "Target user not found.") end

    WarmupCommunityOutfits()

    local collected = {}
    local seen = {}
    local categories = BuildCreatorCategoryPlan()
    local safetyCapHit = false

    Notify("System", "Initiating deep creator scan...")

    for categoryIndex, categoryKey in ipairs(categories) do
        if IsCancelled() then break end

        local categoryLabel = CREATOR_CATEGORY_LABELS[categoryKey] or tostring(categoryKey)
        local page = 1
        local categoryExpected = nil
        local suspiciousEmptyHits = 0
        local lastBatchCount = 0
        local sequentialFetchFailures = 0

        while page <= MAX_CREATOR_BATCHES do
            if IsCancelled() then break end

            if statusLabel then
                statusLabel.Text = string.format(
                    "Creator Scan %d/%d | %s | Page %d | Rigs %d",
                    categoryIndex,
                    #categories,
                    categoryLabel,
                    page,
                    #collected
                )
            end

            local outfits, totalHint, fetchErr = nil, nil, nil
            local okBatch = false
            for retry = 1, CREATOR_BATCH_RETRIES do
                outfits, totalHint, fetchErr = FetchCreatorBatch(uid, page, categoryKey)
                if fetchErr == nil then
                    okBatch = true
                    break
                end
                if fetchErr == "Cancelled" then
                    break
                end
                if statusLabel then
                    statusLabel.Text = string.format(
                        "Creator Scan | Retrying %s page %d (%d/%d)",
                        categoryLabel,
                        page,
                        retry,
                        CREATOR_BATCH_RETRIES
                    )
                end
                task.wait(0.12 * retry)
            end

            if not okBatch then
                if fetchErr == "Cancelled" then
                    break
                end

                sequentialFetchFailures = sequentialFetchFailures + 1
                if sequentialFetchFailures >= CREATOR_MAX_SEQUENTIAL_FETCH_FAILURES then
                    Notify("Warning", "Creator scan unstable in " .. categoryLabel .. ". Moving to next category.")
                    break
                end

                task.wait(0.2 * sequentialFetchFailures)
            else
                sequentialFetchFailures = 0

                if totalHint and totalHint > 0 then
                    categoryExpected = categoryExpected and math.max(categoryExpected, totalHint) or totalHint
                end

                if #outfits == 0 then
                    local hasExpected = categoryExpected and categoryExpected > 0
                    local stillMissing = hasExpected and ((page - 1) * CREATOR_BATCH_SIZE) < categoryExpected
                    local suspiciousByShape = lastBatchCount >= CREATOR_BATCH_SIZE

                    if (stillMissing or suspiciousByShape) and suspiciousEmptyHits < CREATOR_EMPTY_RECHECKS then
                        suspiciousEmptyHits = suspiciousEmptyHits + 1
                        task.wait(CREATOR_EMPTY_RECHECK_DELAY * suspiciousEmptyHits)
                    else
                        break
                    end
                else
                    suspiciousEmptyHits = 0
                    lastBatchCount = #outfits

                    for _, item in ipairs(outfits) do
                        if IsCancelled() then break end

                        if item and item.Items then
                            local uniqueKey = BuildCreatorUniqueKey(item)
                            local shouldAdd = true

                            if uniqueKey then
                                if seen[uniqueKey] then
                                    shouldAdd = false
                                else
                                    seen[uniqueKey] = true
                                end
                            end

                            if shouldAdd then
                                local desc = BuildDescriptionFromItems(item.Items)
                                if desc then
                                    local rType = item.RigType or "R15"
                                    local idPart = item.Id or item.OutfitId or item.Code or item.AssetId
                                    local code = tostring(idPart or (categoryKey .. "_" .. page .. "_" .. (#collected + 1)))
                                    local name = item.Name or ("Outfit_" .. tostring(#collected + 1))
                                    table.insert(collected, {
                                        Description = desc,
                                        Name = name,
                                        Code = code,
                                        RigType = rType
                                    })
                                end
                            end
                        end

                        if #collected >= MAX_CREATOR_OUTFITS then
                            safetyCapHit = true
                            break
                        end
                    end

                    if safetyCapHit then
                        break
                    end

                    page = page + 1
                    task.wait(0.01)
                end
            end
        end

        if safetyCapHit then
            Notify("Warning", "Creator scan reached safety cap (" .. MAX_CREATOR_OUTFITS .. ").")
            break
        end
    end

    if IsCancelled() then
        Notify("System", "Creator scan cancelled by user.")
        return
    end

    Factory.ProcessAndSave(collected, "Creator_" .. targetName, statusLabel)
end

local function NormalizeFolderText(value)
    local txt = tostring(value or "")
    txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
    return txt
end

local function CanonicalFolderKey(value)
    local txt = string.lower(NormalizeFolderText(value))
    txt = txt:gsub("[_%-%|/\\,;:%.]+", " ")
    txt = txt:gsub("[%[%]{}\"']", " ")
    txt = txt:gsub("%s+", " ")
    txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
    return txt
end

local function CanonicalIdKey(value)
    local txt = string.lower(tostring(value or ""))
    txt = txt:gsub("%s+", "")
    txt = txt:gsub("[^%w]", "")
    return txt
end

local function AddCanonicalIdCandidates(targetSet, value)
    if not targetSet or value == nil then
        return
    end

    local function pushSingle(v)
        local key = CanonicalIdKey(v)
        if key ~= "" then
            targetSet[key] = true
        end
    end

    local valueType = typeof(value)
    if valueType == "number" then
        pushSingle(value)
        return
    end

    if valueType ~= "string" then
        return
    end

    local raw = NormalizeFolderText(value)
    if raw == "" then
        return
    end

    pushSingle(raw)

    local parsed = ParseJsonSafe(raw)
    if type(parsed) == "table" then
        for _, item in pairs(parsed) do
            if typeof(item) == "string" or typeof(item) == "number" then
                pushSingle(item)
            end
        end
    end

    for token in string.gmatch(raw, "[%w%-_]+") do
        pushSingle(token)
    end
end

local function CollectFolderIdCandidatesFromInstance(inst, outSet)
    if not inst or not outSet then
        return
    end

    local attrNames = {
        "FolderId", "FolderID", "FolderGuid", "FolderGUID", "FolderUUID",
        "OutfitFolderId", "OutfitFolderID", "OutfitFolderGuid", "OutfitFolderGUID", "OutfitFolderUUID",
        "OutfitFolders", "FolderIds", "FolderGUIDs",
        "TabId", "TabID", "TabGuid", "TabGUID", "TabUUID",
        "GroupId", "GroupID", "GroupGuid", "GroupGUID",
        "CategoryId", "CategoryID", "CollectionId", "CollectionID"
    }

    for _, attrName in ipairs(attrNames) do
        AddCanonicalIdCandidates(outSet, inst:GetAttribute(attrName))
    end

    for _, child in ipairs(inst:GetChildren()) do
        if child:IsA("StringValue") or child:IsA("IntValue") or child:IsA("NumberValue") then
            local n = string.lower(child.Name or "")
            local hasScope = string.find(n, "folder", 1, true)
                or string.find(n, "tab", 1, true)
                or string.find(n, "group", 1, true)
                or string.find(n, "category", 1, true)
                or string.find(n, "collection", 1, true)
            local hasIdHint = string.find(n, "id", 1, true)
                or string.find(n, "guid", 1, true)
                or string.find(n, "uuid", 1, true)
            if hasScope and hasIdHint then
                AddCanonicalIdCandidates(outSet, child.Value)
            end
        end
    end
end

local function BuildObjectFolderIdSet(obj, root)
    local ids = {}
    CollectFolderIdCandidatesFromInstance(obj, ids)
    local probe = obj.Parent
    local depth = 0
    while probe and probe ~= root and depth < 8 do
        CollectFolderIdCandidatesFromInstance(probe, ids)
        probe = probe.Parent
        depth = depth + 1
    end
    return ids
end

local function BuildFolderTargetContextFromUI(folderTargetKey)
    local ctx = { Ids = {} }
    if folderTargetKey == "all" then
        return ctx
    end

    local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    local gui = playerGui and (playerGui:FindFirstChild("SavedOutfitsV3") or playerGui:FindFirstChild("SavedOutfits"))
    if not gui then
        return ctx
    end

    for _, node in ipairs(gui:GetDescendants()) do
        if node:IsA("GuiObject") then
            local label = nil
            if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
                label = node.Text
            else
                label = node.Name
            end

            local key = CanonicalFolderKey(label)
            local match = (key == folderTargetKey) or (key ~= "" and string.find(key, folderTargetKey, 1, true))
            if match then
                CollectFolderIdCandidatesFromInstance(node, ctx.Ids)
                local probe = node.Parent
                for _ = 1, 6 do
                    if not probe then break end
                    CollectFolderIdCandidatesFromInstance(probe, ctx.Ids)
                    probe = probe.Parent
                end

                -- Some games keep outfit UUID references in descendants of the folder UI node
                local scanned = 0
                for _, d in ipairs(node:GetDescendants()) do
                    scanned = scanned + 1
                    if scanned > 200 then
                        break
                    end

                    if d:IsA("StringValue") or d:IsA("IntValue") or d:IsA("NumberValue") then
                        AddCanonicalIdCandidates(ctx.Ids, d.Value)
                        AddCanonicalIdCandidates(ctx.Ids, d.Name)
                    else
                        AddCanonicalIdCandidates(ctx.Ids, d:GetAttribute("GUID"))
                        AddCanonicalIdCandidates(ctx.Ids, d:GetAttribute("OutfitId"))
                        AddCanonicalIdCandidates(ctx.Ids, d:GetAttribute("OutfitGUID"))
                        AddCanonicalIdCandidates(ctx.Ids, d:GetAttribute("Id"))
                        AddCanonicalIdCandidates(ctx.Ids, d:GetAttribute("ID"))
                        AddCanonicalIdCandidates(ctx.Ids, d:GetAttribute("Code"))
                    end
                end
            end
        end
    end

    return ctx
end

local function TryActivateFolderTab(folderTargetKey)
    if folderTargetKey == "all" then
        return false
    end

    local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    local gui = playerGui and (playerGui:FindFirstChild("SavedOutfitsV3") or playerGui:FindFirstChild("SavedOutfits"))
    if not gui then
        return false
    end

    local function findClickable(inst)
        local probe = inst
        for _ = 1, 6 do
            if not probe then break end
            if probe:IsA("GuiButton") then
                return probe
            end
            probe = probe.Parent
        end
        return nil
    end

    for _, node in ipairs(gui:GetDescendants()) do
        local text = nil
        if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
            text = node.Text
        elseif node:IsA("GuiButton") then
            text = node.Name
        end

        if text then
            local key = CanonicalFolderKey(text)
            if key == folderTargetKey then
                local clickTarget = findClickable(node) or (node:IsA("GuiButton") and node or nil)
                if clickTarget then
                    local fired = false
                    if firesignal then
                        fired = pcall(function()
                            if clickTarget.MouseButton1Click then
                                firesignal(clickTarget.MouseButton1Click)
                            elseif clickTarget.Activated then
                                firesignal(clickTarget.Activated)
                            end
                        end)
                    end
                    if not fired then
                        pcall(function()
                            if clickTarget.Activate then
                                clickTarget:Activate()
                                fired = true
                            end
                        end)
                    end
                    if fired then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function ResolveOutfitsListContainer(gui)
    if not gui then
        return nil
    end

    local holder = gui:FindFirstChild("Holder")
    local main = holder and holder:FindFirstChild("Main")
    local outfits = main and main:FindFirstChild("Outfits")
    if outfits then
        local directList = outfits:FindFirstChild("List")
        if directList and directList:IsA("GuiObject") then
            return directList
        end
    end

    local fallback = gui:FindFirstChild("List", true)
    if fallback and fallback:IsA("GuiObject") then
        return fallback
    end

    return nil
end

local function GetFolderSelectionScore(inst)
    if not inst then
        return 0
    end

    local score = 0
    if inst:GetAttribute("Selected") == true or inst:GetAttribute("IsSelected") == true then
        score = score + 5
    end
    if inst:GetAttribute("Active") == true or inst:GetAttribute("IsActive") == true then
        score = score + 5
    end

    local checked = 0
    for _, d in ipairs(inst:GetDescendants()) do
        checked = checked + 1
        if checked > 50 then
            break
        end

        if d:IsA("UIStroke") and d.Enabled then
            score = score + 3
        elseif d:IsA("GuiObject") then
            local nameKey = string.lower(d.Name or "")
            if (string.find(nameKey, "select", 1, true)
                or string.find(nameKey, "active", 1, true)
                or string.find(nameKey, "indicator", 1, true)
                or string.find(nameKey, "underline", 1, true))
                and d.Visible
            then
                score = score + 4
            end
        end
    end

    return score
end

local function ResolveActiveFolderKey(gui)
    if not gui then
        return nil
    end

    local holder = gui:FindFirstChild("Holder")
    local main = holder and holder:FindFirstChild("Main")
    local outfits = main and main:FindFirstChild("Outfits")
    local selectorList = outfits and outfits:FindFirstChild("OutfitFolderSelector")
    selectorList = selectorList and selectorList:FindFirstChild("List")

    local bestKey = nil
    local bestScore = -1
    local visibleKeys = {}

    local function inspectNode(node)
        local text = nil
        if node:IsA("TextButton") or node:IsA("TextLabel") or node:IsA("TextBox") then
            text = node.Text
        elseif node:IsA("GuiButton") or node:IsA("Frame") then
            text = node.Name
        end
        local key = CanonicalFolderKey(text)
        if key == "" then
            return
        end

        local score = GetFolderSelectionScore(node)
        if score > bestScore then
            bestScore = score
            bestKey = key
        end
    end

    if selectorList then
        for _, child in ipairs(selectorList:GetChildren()) do
            if child:IsA("GuiObject") then
                if child.Visible then
                    local childText = nil
                    if child:IsA("TextButton") or child:IsA("TextLabel") or child:IsA("TextBox") then
                        childText = child.Text
                    else
                        childText = child.Name
                    end
                    local childKey = CanonicalFolderKey(childText)
                    if childKey ~= "" then
                        visibleKeys[childKey] = true
                    end
                end
                inspectNode(child)
            end
        end

        local onlyKey = nil
        local count = 0
        for k, _ in pairs(visibleKeys) do
            onlyKey = k
            count = count + 1
            if count > 1 then
                break
            end
        end
        if count == 1 and onlyKey then
            return onlyKey
        end
    end

    if not bestKey then
        for _, node in ipairs(gui:GetDescendants()) do
            if node:IsA("GuiObject") then
                local full = string.lower(node:GetFullName())
                if string.find(full, "folder", 1, true) or string.find(full, "tab", 1, true) then
                    inspectNode(node)
                end
            end
        end
    end

    if bestScore <= 0 then
        return nil
    end

    return bestKey
end

local function ResolveLocalOutfitsRoot()
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    return (LocalPlayer and LocalPlayer:FindFirstChild("Outfits"))
        or (playerGui and playerGui:FindFirstChild("SavedOutfitsV3") and playerGui.SavedOutfitsV3:FindFirstChild("Outfits"))
        or (playerGui and playerGui:FindFirstChild("SavedOutfits") and playerGui.SavedOutfits:FindFirstChild("Outfits"))
end

local function ResolveSavedOutfitsGui()
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return nil
    end
    return playerGui:FindFirstChild("SavedOutfitsV3") or playerGui:FindFirstChild("SavedOutfits")
end

local function WaitForLocalOutfitsRoot(timeoutSeconds, statusLabel)
    local timeoutAt = os.clock() + (tonumber(timeoutSeconds) or 8)
    local lastStatusAt = 0

    repeat
        local root = ResolveLocalOutfitsRoot()
        if root then
            return root
        end

        if LocalPlayer and not LocalPlayer:FindFirstChild("PlayerGui") then
            pcall(function()
                LocalPlayer:WaitForChild("PlayerGui", 0.25)
            end)
        end

        if statusLabel and (os.clock() - lastStatusAt) > 0.45 then
            lastStatusAt = os.clock()
            SetStatusLabel(statusLabel, "Status: waiting for local outfits cache after rejoin...")
        end

        task.wait(0.08)
    until os.clock() >= timeoutAt or IsCancelled()

    return ResolveLocalOutfitsRoot()
end

local function WaitForMinimumCatalogReady(timeoutSeconds, statusLabel)
    local timeoutAt = os.clock() + (tonumber(timeoutSeconds) or 8)
    local lastStatusAt = 0

    repeat
        local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        local communityRemote = Remote or ReplicatedStorage:FindFirstChild("CommunityOutfitsRemote")
        local catalogRemote = ReplicatedStorage:FindFirstChild("CatalogGuiRemote")

        if playerGui and communityRemote and catalogRemote then
            Remote = communityRemote
            return true
        end

        if statusLabel and (os.clock() - lastStatusAt) > 0.45 then
            lastStatusAt = os.clock()
            SetStatusLabel(statusLabel, "Status: waiting for CAC remotes to load...")
        end

        task.wait(0.06)
    until os.clock() >= timeoutAt or IsCancelled()

    Remote = Remote or ReplicatedStorage:FindFirstChild("CommunityOutfitsRemote")
    return Remote ~= nil and ReplicatedStorage:FindFirstChild("CatalogGuiRemote") ~= nil
end

local function BuildFolderValues(obj, root)
    local values = {}
    local seen = {}
    local function push(v)
        if v == nil then return end
        local t = typeof(v)
        if t == "string" or t == "number" then
            local s = NormalizeFolderText(v)
            if s ~= "" and not seen[s] then
                seen[s] = true
                table.insert(values, s)

                -- Split list-like metadata: "a, b | c / d"
                for token in string.gmatch(s, "[^,%|/;]+") do
                    local clean = NormalizeFolderText(token)
                    if clean ~= "" and not seen[clean] then
                        seen[clean] = true
                        table.insert(values, clean)
                    end
                end
            end
        end
    end

    local function pushFolderSignals(inst)
        if not inst then return end
        push(inst:GetAttribute("OutfitFolders"))
        push(inst:GetAttribute("OutfitFolder"))
        push(inst:GetAttribute("Folder"))
        push(inst:GetAttribute("FolderName"))
        push(inst:GetAttribute("FolderTarget"))
        push(inst:GetAttribute("Category"))
        push(inst:GetAttribute("Collection"))
        push(inst:GetAttribute("Tab"))
        push(inst:GetAttribute("TabName"))
        push(inst:GetAttribute("Group"))
        push(inst:GetAttribute("GroupName"))
        push(inst:GetAttribute("Page"))
        push(inst:GetAttribute("PageName"))
        push(inst.Name)

        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            push(inst.Text)
        end

        -- Some games store folder info in StringValue/IntValue children
        for _, child in ipairs(inst:GetChildren()) do
            if child:IsA("StringValue") or child:IsA("IntValue") or child:IsA("NumberValue") then
                local n = string.lower(child.Name or "")
                if string.find(n, "folder", 1, true)
                    or string.find(n, "tab", 1, true)
                    or string.find(n, "group", 1, true)
                    or string.find(n, "category", 1, true)
                    or string.find(n, "collection", 1, true)
                then
                    push(child.Value)
                end
            end
        end

        -- Some games store folder/category under nested "Configs" folders
        -- via attributes (e.g. Configs:GetAttribute("OutfitFolders")).
        local scanned = 0
        for _, d in ipairs(inst:GetDescendants()) do
            scanned = scanned + 1
            if scanned > 200 then
                break
            end

            push(d:GetAttribute("OutfitFolders"))
            push(d:GetAttribute("OutfitFolder"))
            push(d:GetAttribute("Folder"))
            push(d:GetAttribute("FolderName"))
            push(d:GetAttribute("FolderTarget"))
            push(d:GetAttribute("Category"))
            push(d:GetAttribute("Collection"))
            push(d:GetAttribute("Tab"))
            push(d:GetAttribute("TabName"))
            push(d:GetAttribute("Group"))
            push(d:GetAttribute("GroupName"))
            push(d:GetAttribute("Page"))
            push(d:GetAttribute("PageName"))

            if d:IsA("StringValue") or d:IsA("IntValue") or d:IsA("NumberValue") then
                local n = string.lower(d.Name or "")
                if string.find(n, "folder", 1, true)
                    or string.find(n, "tab", 1, true)
                    or string.find(n, "group", 1, true)
                    or string.find(n, "category", 1, true)
                    or string.find(n, "collection", 1, true)
                    or string.find(n, "outfitfolder", 1, true)
                    or string.find(n, "outfitfolders", 1, true)
                then
                    push(d.Value)
                end
            end
        end
    end

    pushFolderSignals(obj)

    -- Walk ancestors (important for games where folder is only in parent tab/frame)
    local depth = 0
    local probe = obj.Parent
    while probe and probe ~= root and depth < 10 do
        pushFolderSignals(probe)
        probe = probe.Parent
        depth = depth + 1
    end

    return values
end

local function MatchesFolderTarget(obj, root, folderTargetKey, folderContext)
    if folderTargetKey == "all" then
        return true
    end

    if folderContext and folderContext.Ids then
        local targetIds = folderContext.Ids
        if next(targetIds) ~= nil then
            local objectIds = BuildObjectFolderIdSet(obj, root)
            for idKey, _ in pairs(objectIds) do
                if targetIds[idKey] then
                    return true
                end
            end
        end
    end

    local values = BuildFolderValues(obj, root)
    for _, raw in ipairs(values) do
        local key = CanonicalFolderKey(raw)
        if key ~= "" then
            if key == folderTargetKey then
                return true
            end

            if string.find(key, folderTargetKey, 1, true) then
                return true
            end

            for token in string.gmatch(key, "[^%s]+") do
                if token == folderTargetKey then
                    return true
                end
            end
        end
    end

    return false
end

local function BuildOutfitPayload(obj)
    local desc = obj:FindFirstChild("HumanoidDescription") or obj:FindFirstChildWhichIsA("HumanoidDescription", true)
    if not desc or not desc:IsA("HumanoidDescription") then
        return nil, nil
    end

    local guid = obj:GetAttribute("GUID") or obj:GetAttribute("OutfitId") or obj.Name
    local guidKey = tostring(guid)
    if guidKey == "" or guidKey == "nil" then
        guidKey = tostring(obj:GetFullName())
    end

    local rType = obj:GetAttribute("RigType") or "R15"
    local oName = obj:GetAttribute("OutfitName") or obj.Name

    return {
        Description = desc,
        Name = oName,
        Code = tostring(guid),
        RigType = rType
    }, guidKey
end

local function CollectFolderOutfits(root, folderTargetKey, folderContext, statusLabel)
    local candidates = {}
    local collected = {}
    local dedupe = {}

    for _, obj in ipairs(root:GetDescendants()) do
        if obj ~= root and not obj:IsA("HumanoidDescription") then
            local desc = obj:FindFirstChild("HumanoidDescription")
            if desc and desc:IsA("HumanoidDescription") then
                table.insert(candidates, obj)
            end
        end
    end

    if statusLabel then
        statusLabel.Text = "Status: Scanning " .. #candidates .. " cached items..."
    end

    for i, obj in ipairs(candidates) do
        if IsCancelled() then
            break
        end
        if i % 50 == 0 then
            task.wait()
        end

        if MatchesFolderTarget(obj, root, folderTargetKey, folderContext) then
            local payload, guidKey = BuildOutfitPayload(obj)
            if payload and not dedupe[guidKey] then
                dedupe[guidKey] = true
                table.insert(collected, payload)
            end
        end
    end

    return collected
end

local function FindOutfitByGuid(root, targetGuid)
    local idKey = CanonicalIdKey(targetGuid)
    if idKey == "" then
        return nil
    end

    local function matchesId(value)
        return CanonicalIdKey(value) == idKey
    end

    local direct = root:FindFirstChild(targetGuid)
    if direct and direct:FindFirstChild("HumanoidDescription") then
        return direct
    end

    for _, c in ipairs(root:GetDescendants()) do
        if IsCancelled() then
            break
        end
        local guid = c:GetAttribute("GUID")
        local outfitId = c:GetAttribute("OutfitId")
        local altId = c:GetAttribute("Id") or c:GetAttribute("ID") or c:GetAttribute("Code")
        if matchesId(guid) or matchesId(outfitId) or matchesId(altId) or matchesId(c.Name)
        then
            if c:FindFirstChild("HumanoidDescription") then
                return c
            end
        end
    end

    return nil
end

local function BuildOutfitLookup(root)
    local byId = {}
    local byName = {}
    local outfits = {}
    for _, obj in ipairs(root:GetDescendants()) do
        if obj ~= root and not obj:IsA("HumanoidDescription") then
            local desc = obj:FindFirstChild("HumanoidDescription")
            if desc and desc:IsA("HumanoidDescription") then
                table.insert(outfits, obj)
                local payload, guidKey = BuildOutfitPayload(obj)
                if payload then
                    local function addId(v)
                        local k = CanonicalIdKey(v)
                        if k ~= "" and not byId[k] then
                            byId[k] = obj
                        end
                    end

                    local function addName(v)
                        local k = CanonicalFolderKey(v)
                        if k == "" then return end
                        byName[k] = byName[k] or {}
                        table.insert(byName[k], obj)
                    end

                    addId(guidKey)
                    addId(payload.Code)
                    addId(obj.Name)
                    addId(obj:GetAttribute("GUID"))
                    addId(obj:GetAttribute("OutfitId"))
                    addId(obj:GetAttribute("Id"))
                    addId(obj:GetAttribute("ID"))
                    addId(obj:GetAttribute("Code"))
                    addId(obj:GetAttribute("AssetId"))

                    addName(obj.Name)
                    addName(obj:GetAttribute("OutfitName"))
                    addName(obj:GetAttribute("Name"))
                end
            end
        end
    end
    return byId, byName, outfits
end

local function CollectNodeIdCandidates(node)
    local out = {}
    local seen = {}
    local function push(v)
        local key = CanonicalIdKey(v)
        if key ~= "" and not seen[key] then
            seen[key] = true
            table.insert(out, key)
        end
    end

    local function pullFromInstance(inst)
        if not inst then return end
        push(inst.Name)
        push(inst:GetAttribute("GUID"))
        push(inst:GetAttribute("OutfitId"))
        push(inst:GetAttribute("OutfitGUID"))
        push(inst:GetAttribute("Id"))
        push(inst:GetAttribute("ID"))
        push(inst:GetAttribute("Code"))
        push(inst:GetAttribute("AssetId"))

        for _, child in ipairs(inst:GetChildren()) do
            if child:IsA("StringValue") or child:IsA("IntValue") or child:IsA("NumberValue") then
                local n = string.lower(child.Name or "")
                if string.find(n, "guid", 1, true)
                    or string.find(n, "outfit", 1, true)
                    or string.find(n, "id", 1, true)
                    or string.find(n, "code", 1, true)
                then
                    push(child.Value)
                end
            end
        end
    end

    pullFromInstance(node)
    local probe = node.Parent
    for _ = 1, 6 do
        if not probe then break end
        pullFromInstance(probe)
        probe = probe.Parent
    end

    return out
end

local function CollectNodeNameCandidates(node)
    local out = {}
    local seen = {}
    local function push(v)
        local key = CanonicalFolderKey(v)
        if key ~= "" and not seen[key] then
            seen[key] = true
            table.insert(out, key)
        end
    end

    push(node.Name)
    push(node:GetAttribute("OutfitName"))
    push(node:GetAttribute("Name"))

    if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
        push(node.Text)
    end

    local depthCount = 0
    for _, d in ipairs(node:GetDescendants()) do
        depthCount = depthCount + 1
        if depthCount > 40 then
            break
        end
        if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
            push(d.Text)
        elseif d:IsA("StringValue") then
            local n = string.lower(d.Name or "")
            if string.find(n, "name", 1, true) or string.find(n, "outfit", 1, true) then
                push(d.Value)
            end
        end
    end

    return out
end

local function CollectVisibleFolderOutfitsFromUI(root, folderTargetKey, folderContext, statusLabel)
    local gui = ResolveSavedOutfitsGui()
    if not gui then
        return {}
    end

    local listContainer = ResolveOutfitsListContainer(gui) or gui
    local byId, byName = BuildOutfitLookup(root)
    local collected = {}
    local dedupe = {}
    local visibleNodes = 0
    local resolved = 0

    for _, node in ipairs(listContainer:GetDescendants()) do
        if IsCancelled() then
            break
        end

        if node:IsA("GuiObject") and node.Visible and node.AbsoluteSize.X >= 80 and node.AbsoluteSize.Y >= 80 then
            visibleNodes = visibleNodes + 1
            local matches = MatchesFolderTarget(node, gui, folderTargetKey, folderContext)
            if not matches then
                local probe = node.Parent
                for _ = 1, 6 do
                    if not probe then break end
                    if MatchesFolderTarget(probe, gui, folderTargetKey, folderContext) then
                        matches = true
                        break
                    end
                    probe = probe.Parent
                end
            end

            if matches then
                local obj
                for _, idKey in ipairs(CollectNodeIdCandidates(node)) do
                    obj = byId[idKey]
                    if obj then
                        break
                    end
                end

                if not obj then
                    for _, nameKey in ipairs(CollectNodeNameCandidates(node)) do
                        local bucket = byName[nameKey]
                        if bucket and #bucket > 0 then
                            obj = bucket[1]
                            break
                        end
                    end
                end

                if obj then
                    local payload, guidKey = BuildOutfitPayload(obj)
                    if payload and not dedupe[guidKey] then
                        dedupe[guidKey] = true
                        table.insert(collected, payload)
                        resolved = resolved + 1
                    end
                end
            end
        end
    end

    if statusLabel then
        statusLabel.Text = "Status: UI fallback matched " .. #collected .. " outfits (" .. resolved .. "/" .. visibleNodes .. " visible cards)."
    end

    return collected
end

local function CollectVisibleOutfitsFromCurrentList(root, statusLabel)
    local gui = ResolveSavedOutfitsGui()
    if not gui then
        return {}
    end

    local listContainer = ResolveOutfitsListContainer(gui)
    if not listContainer then
        return {}
    end

    local byId, byName = BuildOutfitLookup(root)
    local collected = {}
    local dedupe = {}
    local visibleNodes = 0

    for _, node in ipairs(listContainer:GetDescendants()) do
        if IsCancelled() then
            break
        end

        if node:IsA("GuiObject") and node.Visible and node.AbsoluteSize.X >= 80 and node.AbsoluteSize.Y >= 80 then
            visibleNodes = visibleNodes + 1

            local obj
            for _, idKey in ipairs(CollectNodeIdCandidates(node)) do
                obj = byId[idKey]
                if obj then
                    break
                end
            end

            if not obj then
                for _, nameKey in ipairs(CollectNodeNameCandidates(node)) do
                    local bucket = byName[nameKey]
                    if bucket and #bucket > 0 then
                        obj = bucket[1]
                        break
                    end
                end
            end

            if obj then
                local payload, guidKey = BuildOutfitPayload(obj)
                if payload and not dedupe[guidKey] then
                    dedupe[guidKey] = true
                    table.insert(collected, payload)
                end
            end
        end
    end

    if statusLabel then
        statusLabel.Text = "Status: Current folder visible list matched " .. #collected .. " outfits from " .. visibleNodes .. " cards."
    end

    return collected
end

function Dumpers.Folder(folderName, statusLabel)
    local folderTarget = NormalizeFolderText(folderName)
    if folderTarget == "" then
        folderTarget = "All"
    end

    local folderTargetKey = CanonicalFolderKey(folderTarget)
    if folderTargetKey == "" or folderTargetKey == "*" or folderTargetKey == "all outfits" then
        folderTargetKey = "all"
        folderTarget = "All"
    end

    local root = ResolveLocalOutfitsRoot()
    if not root then
        return Notify("Error", "Local cache directory not found.")
    end

    local folderContext = BuildFolderTargetContextFromUI(folderTargetKey)
    if folderTargetKey ~= "all" and (not folderContext or not folderContext.Ids or next(folderContext.Ids) == nil) then
        local switched = TryActivateFolderTab(folderTargetKey)
        if switched then
            task.wait(0.25)
            folderContext = BuildFolderTargetContextFromUI(folderTargetKey)
        end
    end
    local collected = {}
    local attempts = 0
    local maxAttempts = 5

    repeat
        attempts = attempts + 1
        collected = CollectFolderOutfits(root, folderTargetKey, folderContext, statusLabel)
        if #collected > 0 or IsCancelled() then
            break
        end

        if attempts < maxAttempts then
            if statusLabel then
                statusLabel.Text = "Status: No outfits yet. Rechecking cache (" .. attempts .. "/" .. (maxAttempts - 1) .. ")..."
            end
            task.wait(0.2 * attempts)
            root = ResolveLocalOutfitsRoot() or root
        end
    until attempts >= maxAttempts

    if not IsCancelled() and #collected == 0 and folderTargetKey ~= "all" then
        local gui = ResolveSavedOutfitsGui()
        local activeFolderKey = ResolveActiveFolderKey(gui)
        if activeFolderKey and activeFolderKey ~= folderTargetKey then
            return Notify("Info", "Folder '" .. folderTarget .. "' is not active in the game UI. Open it and try again.")
        end

        Notify("Info", "Folder direct lookup empty. Trying visible UI fallback...")
        collected = CollectVisibleFolderOutfitsFromUI(root, folderTargetKey, folderContext, statusLabel)
        if #collected == 0 then
            local switched = TryActivateFolderTab(folderTargetKey)
            if switched then
                task.wait(0.25)
                folderContext = BuildFolderTargetContextFromUI(folderTargetKey)
            end

            gui = ResolveSavedOutfitsGui()
            activeFolderKey = ResolveActiveFolderKey(gui)
            if activeFolderKey and activeFolderKey ~= folderTargetKey then
                return Notify("Empty Queue", "No outfits found in folder '" .. folderTarget .. "'.")
            end

            task.wait(0.25)
            collected = CollectVisibleFolderOutfitsFromUI(root, folderTargetKey, folderContext, statusLabel)
        end
    end

    if IsCancelled() then
        Notify("System", "Folder extraction cancelled by user.")
        return
    end

    if #collected == 0 then
        return Notify("Empty Queue", "No outfits found in folder '" .. folderTarget .. "'.")
    end

    Factory.ProcessAndSave(collected, "Folder_" .. folderTarget, statusLabel)
end

function Dumpers.Selection(statusLabel)
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return Notify("Error", "PlayerGui is not ready yet.")
    end

    local gui = playerGui:FindFirstChild("SavedOutfitsV3") or playerGui:FindFirstChild("SavedOutfits")
    if not gui then return Notify("Error", "Main game UI not found.") end

    local selectedGUIDs = {}
    for _, obj in pairs(gui:GetDescendants()) do
        if IsCancelled() then break end
        if obj:IsA("GuiButton") or obj:IsA("Frame") then
            local stroke = obj:FindFirstChild("SelectionUIStroke")
            if stroke and stroke:IsA("UIStroke") and stroke.Enabled then
                local guid = obj:GetAttribute("GUID") or obj:GetAttribute("OutfitId") or obj.Name
                if guid then table.insert(selectedGUIDs, tostring(guid)) end
            end
        end
    end

    if #selectedGUIDs == 0 then return Notify("Info", "No outfits selected in game UI.") end
    
    local outfitsFolder = LocalPlayer:FindFirstChild("Outfits") or gui:FindFirstChild("Outfits")
    if not outfitsFolder then
        return Notify("Error", "Outfits folder not found in current session.")
    end

    local collected = {}
    
    for i, targetGUID in ipairs(selectedGUIDs) do
        if IsCancelled() then break end
        if statusLabel then statusLabel.Text = "Status: Processing selection " .. i .. "/" .. #selectedGUIDs end
        
        local obj = outfitsFolder:FindFirstChild(targetGUID)
        if not obj then
            for _, c in pairs(outfitsFolder:GetDescendants()) do
                if c:GetAttribute("GUID") == targetGUID or c.Name == targetGUID then obj = c; break end
            end
        end
        if obj then
            local hd = obj:FindFirstChild("HumanoidDescription")
            if hd then
                local rType = obj:GetAttribute("RigType") or "R15"
                table.insert(collected, { Description = hd, Name = obj:GetAttribute("OutfitName"), Code = targetGUID, RigType = rType })
            end
        end
    end
    if IsCancelled() then
        Notify("System", "Selection extraction cancelled by user.")
        return
    end
    Factory.ProcessAndSave(collected, "Selection", statusLabel)
end

local function BuildOutfitIdCandidates(rawValue)
    local candidates = {}
    local seen = {}

    local function push(v)
        if v == nil then
            return
        end
        local key = tostring(v)
        if key == "" then
            return
        end
        if not seen[key] then
            seen[key] = true
            table.insert(candidates, v)
        end
    end

    local raw = tostring(rawValue or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if raw ~= "" then
        push(raw)
        local asNumber = tonumber(raw)
        if asNumber then
            push(asNumber)
        end
        if raw:match("^[a-fA-F0-9]+$") then
            local asHex = tonumber(raw, 16)
            if asHex then
                push(asHex)
            end
        end
    end

    return candidates
end

local function NormalizeGeneratedCode(value)
    local n = tonumber(value)
    if n then
        return string.upper(string.format("%X", n))
    end
    return tostring(value or "")
end

local function GetCooldownWaitSeconds(value)
    if value == nil then
        return nil
    end

    local text = string.lower(tostring(value))
    local explicit = tonumber(text:match("oncooldown[:%s]+(%d+)"))
        or tonumber(text:match("please%s+wait%s+(%d+)"))
        or tonumber(text:match("wait%s+(%d+)%s+seconds?"))

    if explicit then
        return explicit
    end

    return nil
end

local function IsCooldownError(value)
    if value == nil then
        return false
    end

    if GetCooldownWaitSeconds(value) ~= nil then
        return true
    end

    local text = string.lower(tostring(value))
    return text == "oncooldown"
        or string.find(text, "cooldown", 1, true) ~= nil
        or (string.find(text, "please wait", 1, true) ~= nil and string.find(text, "again", 1, true) ~= nil)
end

local function IsAlreadyPublishedError(value)
    if value == nil then
        return false
    end

    local text = string.lower(tostring(value))
    return (string.find(text, "already", 1, true) ~= nil and string.find(text, "publish", 1, true) ~= nil)
        or string.find(text, "already exists", 1, true) ~= nil
        or string.find(text, "duplicate", 1, true) ~= nil
end

local function CooldownError(seconds)
    local n = tonumber(seconds)
    if n then
        return "OnCooldown:" .. tostring(math.max(0, math.floor(n)))
    end
    return "OnCooldown"
end

local PUBLISHED_CODE_ATTRIBUTE_HINTS = {
    "OutfitCode", "GeneratedCode", "PublishCode", "PublishedCode", "CommunityCode",
    "ShareCode", "Code"
}

local function NormalizePublishedCode(raw)
    if raw == nil then
        return nil
    end
    local asNumber = tonumber(raw)
    if asNumber then
        return string.upper(string.format("%X", asNumber))
    end

    local text = tostring(raw):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    text = text:gsub("^0x", ""):gsub("^0X", "")
    local compact = text:gsub("[%s%-_]", "")
    if compact:match("^[A-Fa-f0-9]+$") and #compact >= 4 and #compact <= 32 then
        return string.upper(compact)
    end
    return nil
end

local function ExtractPublishedCodeFromObject(obj)
    if not obj or typeof(obj) ~= "Instance" then
        return nil
    end

    local attrs = {}
    pcall(function()
        attrs = obj:GetAttributes() or {}
    end)

    for _, key in ipairs(PUBLISHED_CODE_ATTRIBUTE_HINTS) do
        local normalized = NormalizePublishedCode(attrs[key])
        if normalized then
            return normalized
        end
    end

    for key, value in pairs(attrs) do
        local lower = tostring(key):lower()
        if string.find(lower, "code", 1, true) and not string.find(lower, "color", 1, true) then
            local normalized = NormalizePublishedCode(value)
            if normalized then
                return normalized
            end
        end
    end

    for _, child in ipairs(obj:GetChildren()) do
        local isValueObject = child:IsA("StringValue") or child:IsA("IntValue") or child:IsA("NumberValue")
        if isValueObject then
            local n = string.lower(child.Name or "")
            if string.find(n, "code", 1, true) and not string.find(n, "color", 1, true) then
                local normalized = NormalizePublishedCode(child.Value)
                if normalized then
                    return normalized
                end
            end
        end
    end

    return nil
end

local PUBLISHED_OUTFIT_ID_ATTRIBUTE_HINTS = {
    "PublishedOutfitId", "PublishedOutfitID", "CommunityOutfitId", "CommunityOutfitID",
    "PublishedId", "PublishedID"
}

local function ExtractPublishedOutfitIdFromObject(obj)
    if not obj or typeof(obj) ~= "Instance" then
        return nil
    end

    local attrs = {}
    pcall(function()
        attrs = obj:GetAttributes() or {}
    end)

    for _, key in ipairs(PUBLISHED_OUTFIT_ID_ATTRIBUTE_HINTS) do
        local value = attrs[key]
        if value ~= nil and tostring(value) ~= "" then
            return value
        end
    end

    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("StringValue") or child:IsA("IntValue") or child:IsA("NumberValue") then
            local n = string.lower(child.Name or "")
            if string.find(n, "published", 1, true) or string.find(n, "community", 1, true) then
                if string.find(n, "id", 1, true) and tostring(child.Value or "") ~= "" then
                    return child.Value
                end
            end
        end
    end

    return nil
end

local function TryResolvePublishedCodeByOutfitId(outfitId)
    local raw = tostring(outfitId or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if raw == "" then
        return nil
    end

    local root = ResolveLocalOutfitsRoot()
    if not root then
        return nil
    end

    local obj = FindOutfitByGuid(root, raw)
    if not obj then
        return nil
    end

    return ExtractPublishedCodeFromObject(obj)
end

local function TryResolvePublishedOutfitIdByLocalId(outfitId)
    local raw = tostring(outfitId or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if raw == "" then
        return nil
    end

    local root = ResolveLocalOutfitsRoot()
    if not root then
        return nil
    end

    local obj = FindOutfitByGuid(root, raw)
    if not obj then
        return nil
    end

    return ExtractPublishedOutfitIdFromObject(obj)
end

local function GenerateCodeForOutfitId(outfitId)
    if not Remote then
        WaitForMinimumCatalogReady(5, nil)
    end
    if not Remote then
        return nil, "CommunityOutfitsRemote was not found.", nil
    end

    local candidateIds = BuildOutfitIdCandidates(outfitId)
    if #candidateIds == 0 then
        return nil, "InvalidOutfitId", nil
    end

    local lastError = "RequestFailed"
    for _, candidate in ipairs(candidateIds) do
        AutoPublishDebug("generate_code_request", {
            outfit_id = tostring(candidate)
        })
        local ok, result = pcall(function()
            return Remote:InvokeServer({
                Action = "GenerateOutfitCode",
                OutfitId = candidate
            })
        end)
        AutoPublishDebug("generate_code_response", {
            outfit_id = tostring(candidate),
            ok = ok,
            result = result
        })
        if ok then
            if result == "OnCooldown" then
                return nil, "OnCooldown", candidate
            end
            if IsCooldownError(result) then
                return nil, CooldownError(GetCooldownWaitSeconds(result)), candidate
            end
            if result then
                return NormalizeGeneratedCode(result), nil, candidate
            end
            lastError = "EmptyResponse"
        else
            lastError = "InvokeFailed"
        end
    end

    return nil, lastError, nil
end

local CatalogModuleForPublish = nil

local function GetCatalogModuleForPublish()
    if CatalogModuleForPublish ~= nil then
        return CatalogModuleForPublish
    end

    local moduleScript = ReplicatedStorage:FindFirstChild("CatalogModule")
    if moduleScript and moduleScript:IsA("ModuleScript") then
        local ok, mod = pcall(function()
            return require(moduleScript)
        end)
        if ok and type(mod) == "table" then
            CatalogModuleForPublish = mod
            return CatalogModuleForPublish
        end
    end

    CatalogModuleForPublish = false
    return nil
end

local function TryBuildPublishProperties(description)
    if not description then
        return nil
    end

    local catalogModule = GetCatalogModuleForPublish()
    if not catalogModule or type(catalogModule.ToDictionary) ~= "function" then
        return nil
    end

    local okDict, properties = pcall(function()
        return catalogModule:ToDictionary(description)
    end)
    if not okDict or type(properties) ~= "table" then
        return nil
    end

    -- Only cache JSON-safe payloads. If a game update adds userdata here,
    -- we still keep the old live-cache path instead of corrupting the queue.
    local okJson = pcall(function()
        HttpService:JSONEncode(properties)
    end)
    if not okJson then
        return nil
    end

    return properties
end

local function ResolveRigTypeValue(rawRig)
    local rigName = tostring(rawRig or "R15")
    if rigName ~= "R6" and rigName ~= "R15" then
        rigName = "R15"
    end
    return Enum.HumanoidRigType[rigName] or Enum.HumanoidRigType.R15
end

local function EquipSavedOutfitForPublish(item, statusLabel)
    local outfitId = tostring(item and item.outfit_id or "")
    if outfitId == "" then
        return false, "Missing local outfit id."
    end

    WaitForMinimumCatalogReady(7, statusLabel)

    local root = WaitForLocalOutfitsRoot(9, statusLabel)
    local obj = root and FindOutfitByGuid(root, outfitId) or nil
    local payload = nil
    local properties = type(item and item.description_properties) == "table" and item.description_properties or nil

    if obj then
        payload = BuildOutfitPayload(obj)
        if payload and payload.Description and not properties then
            properties = TryBuildPublishProperties(payload.Description)
        end
    end

    if not properties then
        if not root then
            return false, "Local outfits cache was not found."
        end
        if not obj then
            return false, "Saved outfit was not found in your local cache."
        end
        return false, "Saved outfit has no publishable HumanoidDescription."
    end

    local catalogRemote = ReplicatedStorage:FindFirstChild("CatalogGuiRemote")
        or ReplicatedStorage:WaitForChild("CatalogGuiRemote", 6)
    if not catalogRemote then
        return false, "CatalogGuiRemote was not found."
    end

    local rigType = ResolveRigTypeValue((payload and payload.RigType) or item.rig_type)
    AutoPublishDebug("equip_saved_outfit_request", {
        outfit_id = outfitId,
        outfit_name = item and item.name,
        rig_type = tostring(rigType),
        has_live_object = obj ~= nil,
        has_properties = type(properties) == "table"
    })
    local okEquip, equipResult = pcall(function()
        return catalogRemote:InvokeServer({
            Action = "CreateAndWearHumanoidDescription",
            Properties = properties,
            RigType = rigType
        })
    end)
    AutoPublishDebug("equip_saved_outfit_response", {
        outfit_id = outfitId,
        ok = okEquip,
        result = equipResult
    })

    if not okEquip then
        return false, "Failed to equip saved outfit before publish."
    end

    if obj then
        local wornEvent = ReplicatedStorage:FindFirstChild("Events")
            and ReplicatedStorage.Events:FindFirstChild("OnSavedOutfitWorn")
        if wornEvent and wornEvent.FireServer then
            local okWorn, wornErr = pcall(function()
                wornEvent:FireServer(obj)
            end)
            AutoPublishDebug("on_saved_outfit_worn_fire", {
                outfit_id = outfitId,
                ok = okWorn,
                error = wornErr
            })
        else
            AutoPublishDebug("on_saved_outfit_worn_missing", {
                outfit_id = outfitId
            })
        end
    end

    task.wait(Globals.MaximizeAutoRejoin and 0.45 or 0.65)
    return true, nil, obj, payload, equipResult
end

local function PublishCurrentOutfitForCode(outfitName)
    if not Remote then
        WaitForMinimumCatalogReady(5, nil)
    end
    if not Remote then
        return nil, "CommunityOutfitsRemote was not found."
    end

    local cleanName = tostring(outfitName or "CAC Outfit"):gsub("^%s+", ""):gsub("%s+$", "")
    if cleanName == "" then
        cleanName = "CAC Outfit"
    end
    if #cleanName > 40 then
        cleanName = string.sub(cleanName, 1, 40)
    end

    AutoPublishDebug("publish_request", {
        outfit_name = cleanName
    })
    local okPublish, result = pcall(function()
        return Remote:InvokeServer({
            Action = "PublishMyOutfit",
            OutfitName = cleanName
        })
    end)
    AutoPublishDebug("publish_response", {
        outfit_name = cleanName,
        ok = okPublish,
        result = result
    })

    if not okPublish then
        return nil, "Publish request failed."
    end

    if result == "OnCooldown" or IsCooldownError(result) then
        return nil, CooldownError(GetCooldownWaitSeconds(result))
    end

    if type(result) == "table" and result.Success and result.PublishedOutfitInfo then
        return result.PublishedOutfitInfo, nil
    end

    if type(result) == "table" and result.Message then
        local msg = tostring(result.Message)
        if IsCooldownError(msg) then
            return nil, CooldownError(GetCooldownWaitSeconds(msg))
        end
        if IsAlreadyPublishedError(msg) then
            return nil, "AlreadyPublished"
        end
        return nil, msg
    end

    return nil, "Publish returned no outfit info."
end

local function PublishSavedOutfitAndGenerateCode(item, statusLabel)
    local existingCode = NormalizePublishedCode(item and item.existing_code or nil)
        or TryResolvePublishedCodeByOutfitId(item and item.outfit_id)
    if existingCode then
        return existingCode, nil, item and item.outfit_id, "existing"
    end

    local publishedId = TryResolvePublishedOutfitIdByLocalId(item and item.outfit_id)
        or (item and item.published_outfit_id)
    if publishedId then
        if item then
            item.published_outfit_id = tostring(publishedId)
        end
        local code, err, usedId = GenerateCodeForOutfitId(publishedId)
        if code then
            return code, nil, usedId or publishedId, "published_id"
        end
        return nil, err or "CodeGenerationFailed", publishedId, "published_id"
    end

    if statusLabel then
        statusLabel.Text = "Auto Publish: equipping saved outfit before publishing..."
    end
    local okEquip, equipErr = EquipSavedOutfitForPublish(item, statusLabel)
    if not okEquip then
        return nil, equipErr or "EquipFailed", nil, "equip_failed"
    end

    if statusLabel then
        statusLabel.Text = "Auto Publish: publishing current outfit..."
    end
    local publishedInfo, publishErr = PublishCurrentOutfitForCode(item and item.name)
    if not publishedInfo then
        if IsAlreadyPublishedError(publishErr) then
            local resolvedId = TryResolvePublishedOutfitIdByLocalId(item and item.outfit_id)
            if resolvedId then
                if item then
                    item.published_outfit_id = tostring(resolvedId)
                end
                local code, err, usedId = GenerateCodeForOutfitId(resolvedId)
                if code then
                    return code, nil, usedId or resolvedId, "published_id"
                end
                return nil, err or "CodeGenerationFailed", resolvedId, "published_id"
            end
        end
        return nil, publishErr or "PublishFailed", nil, "publish_failed"
    end

    local newPublishedId = publishedInfo.Id or publishedInfo.id or publishedInfo.OutfitId or publishedInfo.OutfitID
    if not newPublishedId then
        return nil, "Published outfit id missing.", nil, "publish_failed"
    end
    if item then
        item.published_outfit_id = tostring(newPublishedId)
    end

    if statusLabel then
        statusLabel.Text = "Auto Publish: generating code for published outfit..."
    end
    local code, genErr, usedId = GenerateCodeForOutfitId(newPublishedId)
    if code then
        return code, nil, usedId or newPublishedId, "published"
    end

    return nil, genErr or "CodeGenerationFailed", usedId or newPublishedId, "published"
end

local function CollectSelectionPayloads(statusLabel)
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return {}
    end
    local gui = playerGui:FindFirstChild("SavedOutfitsV3") or playerGui:FindFirstChild("SavedOutfits")
    if not gui then
        return {}
    end

    local selectedGUIDs = {}
    for _, obj in pairs(gui:GetDescendants()) do
        if obj:IsA("GuiButton") or obj:IsA("Frame") then
            local stroke = obj:FindFirstChild("SelectionUIStroke")
            if stroke and stroke:IsA("UIStroke") and stroke.Enabled then
                local guid = obj:GetAttribute("GUID") or obj:GetAttribute("OutfitId") or obj.Name
                if guid then
                    table.insert(selectedGUIDs, tostring(guid))
                end
            end
        end
    end

    if #selectedGUIDs <= 0 then
        return {}
    end

    local outfitsFolder = ResolveLocalOutfitsRoot()
    if not outfitsFolder then
        return {}
    end

    local collected = {}
    for i, targetGUID in ipairs(selectedGUIDs) do
        if statusLabel then
            statusLabel.Text = "Status: Resolving selected outfits " .. i .. "/" .. #selectedGUIDs
        end
        local obj = outfitsFolder:FindFirstChild(targetGUID)
        if not obj then
            for _, c in pairs(outfitsFolder:GetDescendants()) do
                if c:GetAttribute("GUID") == targetGUID or c.Name == targetGUID then
                    obj = c
                    break
                end
            end
        end
        if obj then
            local payload = BuildOutfitPayload(obj)
            if payload then
                table.insert(collected, payload)
            end
        end
    end
    return collected
end

local function CollectFolderPayloadsForAutoPublish(mode, folderInput, statusLabel)
    WaitForMinimumCatalogReady(5, statusLabel)
    local root = WaitForLocalOutfitsRoot(7, statusLabel)
    if not root then
        return {}, "Local cache directory not found."
    end

    local sourceMode = tostring(mode or "Current Folder")
    if sourceMode == "Selected Items" then
        local selected = CollectSelectionPayloads(statusLabel)
        return selected, nil
    end

    if sourceMode == "Current Folder" then
        local visible = CollectVisibleOutfitsFromCurrentList(root, statusLabel)
        return visible, nil
    end

    local folderTarget = NormalizeFolderText(folderInput)
    if sourceMode == "All Folders" then
        folderTarget = "All"
    elseif folderTarget == "" then
        folderTarget = "All"
    end

    local folderTargetKey = CanonicalFolderKey(folderTarget)
    if folderTargetKey == "" or folderTargetKey == "*" or folderTargetKey == "all outfits" then
        folderTargetKey = "all"
    end

    local folderContext = BuildFolderTargetContextFromUI(folderTargetKey)
    if folderTargetKey ~= "all" and (not folderContext or not folderContext.Ids or next(folderContext.Ids) == nil) then
        local switched = TryActivateFolderTab(folderTargetKey)
        if switched then
            task.wait(0.25)
            folderContext = BuildFolderTargetContextFromUI(folderTargetKey)
        end
    end

    local payloads = CollectFolderOutfits(root, folderTargetKey, folderContext, statusLabel)
    if #payloads == 0 and folderTargetKey ~= "all" then
        payloads = CollectVisibleFolderOutfitsFromUI(root, folderTargetKey, folderContext, statusLabel)
    end
    return payloads, nil
end

local function NormalizeAutoPublishProgress(queueState)
    local rawResults = type(queueState.results) == "table" and queueState.results or {}
    local cleanResults = {}
    local completed = {}

    for _, row in ipairs(rawResults) do
        local code = NormalizePublishedCode(row and row.code or nil)
        local index = tonumber(row and row.index)
        if code and index and index > 0 then
            row.code = code
            completed[index] = true
            table.insert(cleanResults, row)
        end
    end

    local expected = 1
    while completed[expected] do
        expected = expected + 1
    end

    queueState.results = cleanResults
    queueState.next_index = expected
    return expected, cleanResults
end

local function RunAutoPublishQueueState(queueState, statusLabel)
    local items = queueState.items or {}
    local nextIndex, results = NormalizeAutoPublishProgress(queueState)
    nextIndex = math.clamp(tonumber(nextIndex) or 1, 1, math.max(#items + 1, 1))
    local waitSeconds = tonumber(queueState.wait_seconds) or 0.65
    waitSeconds = math.clamp(waitSeconds, 0.05, 4)
    local successSinceRejoin = tonumber(queueState.success_since_rejoin) or 0
    local autoRejoinEnabled = queueState.auto_rejoin_enabled == true or Globals.AutoRejoinPublishEnabled == true
    local autoRejoinMode = tostring(queueState.auto_rejoin_mode or Globals.AutoRejoinPublishMode or AUTO_REJOIN_MODE)
    local maximizeAutoRejoin = queueState.maximize_auto_rejoin == true or Globals.MaximizeAutoRejoin == true
    local currentJobId = tostring(game.JobId or "")

    if queueState.awaiting_job_change == true then
        local rejoinFromJobId = tostring(queueState.last_rejoin_from_job_id or "")
        local cooldownUntil = tonumber(queueState.cooldown_until)
        if rejoinFromJobId ~= "" and rejoinFromJobId == currentJobId and cooldownUntil and cooldownUntil > os.time() then
            local remaining = math.clamp(math.ceil(cooldownUntil - os.time()) + 1, 1, 75)
            AutoPublishDebug("queue_same_job_after_rejoin_wait", {
                current_job_id = currentJobId,
                cooldown_until = cooldownUntil,
                wait_seconds = remaining,
                next_index = tonumber(queueState.next_index) or 1
            })
            if statusLabel then
                statusLabel.Text = "Status: Rejoin stayed in the same server. Waiting " .. tostring(remaining) .. "s before retry..."
            end
            task.wait(remaining)
        elseif rejoinFromJobId ~= "" and rejoinFromJobId ~= currentJobId then
            AutoPublishDebug("queue_job_changed_after_rejoin", {
                from_job_id = rejoinFromJobId,
                current_job_id = currentJobId,
                next_index = tonumber(queueState.next_index) or 1
            })
        end

        queueState.awaiting_job_change = false
        queueState.cooldown_until = nil
        queueState.last_rejoin_from_job_id = nil
        WriteQueueState(queueState)
    end

    if tostring(queueState.last_job_id or "") ~= currentJobId then
        successSinceRejoin = 0
        queueState.success_since_rejoin = 0
        queueState.last_job_id = currentJobId
        WriteQueueState(queueState)
    end
    local knownCodesByOutfitId = {}
    AutoPublishDebug("queue_run_start", {
        total_items = #items,
        next_index = nextIndex,
        results = #results,
        auto_rejoin_enabled = autoRejoinEnabled,
        maximize_auto_rejoin = maximizeAutoRejoin
    })

    for _, row in ipairs(results) do
        local code = NormalizePublishedCode(row and row.code or nil)
        local idKey = CanonicalIdKey(row and (row.used_id or row.outfit_id) or "")
        if code and idKey ~= "" then
            knownCodesByOutfitId[idKey] = code
        end
    end

    for i = nextIndex, #items do
        if IsCancelled() then
            break
        end

        local item = items[i]
        queueState.next_index = i
        queueState.results = results
        queueState.success_since_rejoin = successSinceRejoin
        WriteQueueState(queueState)

        local displayName = tostring(item.name or ("Outfit_" .. tostring(i)))
        AutoPublishDebug("queue_item_start", {
            index = i,
            name = displayName,
            outfit_id = tostring(item.outfit_id or ""),
            published_outfit_id = tostring(item.published_outfit_id or ""),
            existing_code = tostring(item.existing_code or "")
        })
        if statusLabel then
            statusLabel.Text = "Auto Publish: " .. i .. "/" .. #items .. " | " .. displayName
        end

        local generatedCode = nil
        local genErr = nil
        local usedId = nil
        local sourceKind = "generated"

        local itemIdKey = CanonicalIdKey(item.outfit_id or "")
        local existingKnownCode = NormalizePublishedCode(item.existing_code)
            or (itemIdKey ~= "" and knownCodesByOutfitId[itemIdKey] or nil)
            or TryResolvePublishedCodeByOutfitId(item.outfit_id)

        if existingKnownCode then
            generatedCode = existingKnownCode
            usedId = item.outfit_id
            sourceKind = "existing"
            AutoPublishDebug("queue_item_existing_code", {
                index = i,
                code = tostring(generatedCode),
                outfit_id = tostring(item.outfit_id or "")
            })
        end

        if not generatedCode then
            generatedCode, genErr, usedId, sourceKind = PublishSavedOutfitAndGenerateCode(item, statusLabel)
        end
        AutoPublishDebug("queue_item_result", {
            index = i,
            code = generatedCode,
            error = genErr,
            used_id = usedId,
            source = sourceKind
        })
        if usedId and tostring(usedId) ~= "" and (sourceKind == "published" or sourceKind == "published_id") then
            item.published_outfit_id = tostring(usedId)
            queueState.items = items
            WriteQueueState(queueState)
        end

        if not generatedCode and IsCooldownError(genErr) then
            local cooldownWait = GetCooldownWaitSeconds(genErr)
            if usedId and tostring(usedId) ~= "" then
                item.published_outfit_id = tostring(usedId)
                queueState.items = items
                WriteQueueState(queueState)
            end
            if autoRejoinEnabled and (not cooldownWait or cooldownWait > 3) then
                queueState.next_index = i
                queueState.results = results
                queueState.success_since_rejoin = 0
                queueState.auto_rejoin_enabled = true
                queueState.auto_rejoin_mode = autoRejoinMode
                queueState.awaiting_job_change = true
                queueState.last_rejoin_from_job_id = currentJobId
                queueState.last_cooldown_wait = cooldownWait
                if cooldownWait then
                    queueState.cooldown_until = os.time() + math.max(0, math.floor(cooldownWait))
                else
                    queueState.cooldown_until = nil
                end
                WriteQueueState(queueState)
                AutoPublishDebug("queue_cooldown_rejoin", {
                    index = i,
                    cooldown_wait = cooldownWait,
                    used_id = usedId,
                    source = sourceKind,
                    current_job_id = currentJobId
                })
                if statusLabel then
                    statusLabel.Text = "Status: Publish/code cooldown detected (" .. tostring(cooldownWait or "?") .. "s). Saving queue and rejoining..."
                end
                if not ConfirmQueueAutoRejoin(queueState, "auto_publish", i, statusLabel) then
                    return "paused"
                end
                AttemptAutoRejoin("Auto publish queue paused at index " .. tostring(i), autoRejoinMode)
                return "rejoin"
            end
            local localWait = math.clamp((tonumber(cooldownWait) or 15) + 1, 2, 35)
            if statusLabel then
                statusLabel.Text = "Status: Cooldown detected. Waiting " .. tostring(localWait) .. "s..."
            end
            task.wait(localWait)
            generatedCode, genErr, usedId, sourceKind = PublishSavedOutfitAndGenerateCode(item, statusLabel)
            if usedId and tostring(usedId) ~= "" and (sourceKind == "published" or sourceKind == "published_id") then
                item.published_outfit_id = tostring(usedId)
                queueState.items = items
                WriteQueueState(queueState)
            end
        end

        if generatedCode then
            if itemIdKey ~= "" then
                knownCodesByOutfitId[itemIdKey] = tostring(generatedCode)
            end
            queueState.last_rejoin_key = nil
            queueState.rejoin_loop_count = 0
            local row = {
                index = i,
                outfit_name = displayName,
                outfit_id = tostring(item.outfit_id or ""),
                used_id = tostring(usedId or item.outfit_id or ""),
                code = tostring(generatedCode),
                source = tostring(sourceKind or "generated")
            }
            table.insert(results, row)
            if sourceKind == "existing" or sourceKind == "published_id" then
                SaveAutoPublishResultLog(string.format("[%d] %s | id=%s | code=%s | reused", i, row.outfit_name, row.used_id, row.code))
            else
                SaveAutoPublishResultLog(string.format("[%d] %s | id=%s | code=%s", i, row.outfit_name, row.used_id, row.code))
            end
            if sourceKind ~= "existing" then
                successSinceRejoin = successSinceRejoin + 1
            end
        else
            queueState.next_index = i
            queueState.results = results
            queueState.items = items
            queueState.success_since_rejoin = successSinceRejoin
            queueState.last_error = tostring(genErr or "failed")
            WriteQueueState(queueState)

            if autoRejoinEnabled or maximizeAutoRejoin then
                local partialRejoinKey = "auto_publish_partial:" .. tostring(i)
                if queueState.last_rejoin_key == partialRejoinKey then
                    queueState.rejoin_loop_count = (tonumber(queueState.rejoin_loop_count) or 0) + 1
                else
                    queueState.last_rejoin_key = partialRejoinKey
                    queueState.rejoin_loop_count = 1
                end
                WriteQueueState(queueState)
                if tonumber(queueState.rejoin_loop_count) and queueState.rejoin_loop_count > 2 then
                    AutoPublishDebug("queue_partial_pause", {
                        index = i,
                        error = genErr,
                        rejoin_loop_count = queueState.rejoin_loop_count
                    })
                    if statusLabel then
                        statusLabel.Text = "Status: Auto publish paused at index " .. tostring(i) .. " after repeated partial retries. Queue saved."
                    end
                    Notify("Auto Publish", "Paused at index " .. tostring(i) .. " after repeated partial retries. Queue saved.")
                    return "paused"
                end
                if statusLabel then
                    statusLabel.Text = "Status: Auto publish kept index " .. tostring(i) .. " pending after a partial result. Rejoining now..."
                end
                AutoPublishDebug("queue_partial_rejoin", {
                    index = i,
                    error = genErr,
                    rejoin_loop_count = queueState.rejoin_loop_count
                })
                AttemptAutoRejoin("Auto publish preserved pending index " .. tostring(i) .. " after partial publish state.", autoRejoinMode, true)
                return "rejoin"
            end

            if statusLabel then
                statusLabel.Text = "Status: Auto publish paused at index " .. tostring(i) .. ". Queue saved. Error: " .. tostring(genErr or "failed")
            end
            Notify("Auto Publish", "Paused at index " .. tostring(i) .. ". Queue saved; item was not marked complete.")
            return "paused"
        end

        queueState.next_index = i + 1
        queueState.results = results
        queueState.success_since_rejoin = successSinceRejoin
        WriteQueueState(queueState)

        if IsCancelled() then
            break
        end
        if generatedCode and maximizeAutoRejoin and successSinceRejoin >= MAXIMIZE_REJOIN_SUCCESS_THRESHOLD and i < #items then
            queueState.next_index = i + 1
            queueState.results = results
            queueState.success_since_rejoin = 0
            queueState.maximize_auto_rejoin = true
            WriteQueueState(queueState)
            AutoPublishDebug("queue_maximize_rejoin", {
                index = i,
                success_since_rejoin = successSinceRejoin
            })
            if statusLabel then
                statusLabel.Text = "Status: Maximize Auto-Rejoin triggered after 5 publish successes. Rejoining now..."
            end
            AttemptAutoRejoin("Maximize auto-rejoin triggered after 5 auto publish successes.", autoRejoinMode, true)
            return "rejoin"
        end
        task.wait(waitSeconds)
    end

    if IsCancelled() then
        Notify("System", "Auto publish queue cancelled by user.")
        return "cancelled"
    end

    local now = os.date("%Y-%m-%d_%H-%M-%S")
    local outputPath = Globals.WorkFolder .. "/AutoPublishCodes_" .. now .. ".txt"
    local lines = {
        "CAC Auto Publish Result",
        "Generated at: " .. tostring(os.date("%Y-%m-%d %H:%M:%S")),
        "Total queued: " .. tostring(#items),
        "Success: pending",
        ""
    }
    local codeList = {}
    local successCount = 0
    for _, row in ipairs(results) do
        if row.code then
            successCount = successCount + 1
            table.insert(lines, string.format("[%d] %s | %s", row.index or 0, row.outfit_name or "Outfit", row.code))
            table.insert(codeList, tostring(row.code))
        else
            table.insert(lines, string.format("[%d] %s | ERROR: %s", row.index or 0, row.outfit_name or "Outfit", tostring(row.error or "failed")))
        end
    end
    lines[4] = "Success: " .. tostring(successCount)

    if #codeList == 0 then
        table.insert(lines, "No codes were generated.")
    end

    local finalText = table.concat(lines, "\n")
    local okWrite = SafeWriteText(outputPath, finalText)
    AutoPublishDebug("queue_finished", {
        total_items = #items,
        success_count = successCount,
        output_path = outputPath,
        wrote_result = okWrite
    })
    if okWrite then
        Notify("Auto Publish", "Finished. Saved result to: " .. tostring(outputPath))
    else
        Notify("Auto Publish", "Finished, but failed to write output file.")
    end

    if okWrite and Globals.WebhookURL ~= "" and Globals.WebhookURL:find("http") then
        UploadTextToDiscord(outputPath, finalText, "Auto Publish Result", "Auto publish finished with **" .. tostring(successCount) .. "** generated/reused code(s).")
    end

    if Globals.AutoCopyAutoPublishResults and #codeList > 0 and setclipboard then
        pcall(function()
            setclipboard(table.concat(codeList, " "))
        end)
        Notify("Clipboard", "Generated outfit codes copied to clipboard.")
    end

    ClearQueueState()
    return "done"
end

function Dumpers.ResumeAutoPublishQueue(statusLabel)
    local state = ReadQueueState()
    if not state or state.task ~= "auto_publish" then
        return Notify("Info", "No pending auto publish queue was found.")
    end
    Notify("System", "Resuming auto publish queue from index " .. tostring(state.next_index or 1) .. ".")
    WaitForMinimumCatalogReady(8, statusLabel)
    WaitForLocalOutfitsRoot(10, statusLabel)
    RunAutoPublishQueueState(state, statusLabel)
end

function Dumpers.AutoPublish(sourceMode, folderInput, statusLabel, namePrefix)
    local payloads, err = CollectFolderPayloadsForAutoPublish(sourceMode, folderInput, statusLabel)
    if err then
        return Notify("Error", err)
    end
    if #payloads <= 0 then
        return Notify("Empty Queue", "No outfits were found for auto publish.")
    end

    local prefix = tostring(namePrefix or Globals.AutoPublishNamePrefix or "CAC")
    local items = {}
    local dedupeIds = {}
    for i, payload in ipairs(payloads) do
        local id = tostring(payload.Code or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local idKey = CanonicalIdKey(id)
        if id ~= "" then
            if idKey == "" or not dedupeIds[idKey] then
                dedupeIds[idKey] = true
                local cachedProperties = TryBuildPublishProperties(payload.Description)
                table.insert(items, {
                    name = tostring(payload.Name or (prefix .. "_" .. tostring(i))),
                    outfit_id = id,
                    rig_type = tostring(payload.RigType or "R15"),
                    existing_code = TryResolvePublishedCodeByOutfitId(id),
                    description_properties = cachedProperties
                })
            end
        end
    end

    if #items <= 0 then
        return Notify("Empty Queue", "No publishable outfit IDs found in selected source.")
    end

    ClearAutoPublishResultLog()
    ClearAutoPublishDebugLog()

    local queueState = {
        version = 2,
        task = "auto_publish",
        created_at = os.time(),
        source_mode = tostring(sourceMode or "Current Folder"),
        folder_target = tostring(folderInput or ""),
        wait_seconds = tonumber(Globals.AutoPublishWaitSeconds) or 0.65,
        next_index = 1,
        items = items,
        results = {},
        auto_rejoin_confirmed = false,
        auto_rejoin_cancelled = false,
        auto_rejoin_enabled = Globals.AutoRejoinPublishEnabled == true,
        auto_rejoin_mode = tostring(Globals.AutoRejoinPublishMode or AUTO_REJOIN_MODE),
        maximize_auto_rejoin = Globals.MaximizeAutoRejoin == true,
        success_since_rejoin = 0,
        rejoin_loop_count = 0
    }

    WriteQueueState(queueState)
    AutoPublishDebug("queue_created", {
        total_items = #items,
        source_mode = tostring(sourceMode or "Current Folder"),
        folder_target = tostring(folderInput or ""),
        wait_seconds = tonumber(Globals.AutoPublishWaitSeconds) or 0.65,
        auto_rejoin_enabled = Globals.AutoRejoinPublishEnabled == true,
        maximize_auto_rejoin = Globals.MaximizeAutoRejoin == true
    })
    Notify("Auto Publish", "Queue created with " .. tostring(#items) .. " outfits.")
    RunAutoPublishQueueState(queueState, statusLabel)
end

function Dumpers.ClearSavedQueue()
    ClearQueueState()
    ClearAutoPublishResultLog()
    ClearAutoPublishDebugLog()
    Notify("System", "Saved queue data cleared.")
end

function Dumpers.ExportAutoPublishDebug(statusLabel)
    ExportAutoPublishDebugDump(statusLabel)
end

local function RunExtractionTask(taskName, statusLabel, runner)
    if type(runner) ~= "function" then
        Notify("Error", "Queue runner is invalid.")
        return
    end

    if not BeginExtraction(taskName, statusLabel) then
        return
    end

    local safeStatus = CreateStatusProxy(statusLabel) or statusLabel

    task.spawn(function()
        local ok, err = xpcall(function()
            runner(safeStatus)
        end, function(e)
            local trace = tostring(e)
            pcall(function()
                trace = debug.traceback(tostring(e), 2)
            end)
            return trace
        end)
        if not ok then
            warn(err)
            Notify("Error", "Task failed: " .. tostring(err))
            EndExtraction(statusLabel, true)
            if not HasActiveQueueResume() then
                RestoreCACGameUI()
            end
            return
        end
        EndExtraction(statusLabel, false)
        if not HasActiveQueueResume() then
            RestoreCACGameUI()
        end
    end)
end

local function ApplyUIPostBuildPatches()
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return end

    for _, obj in ipairs(playerGui:GetDescendants()) do
        if obj:IsA("TextLabel") then
            local txt = tostring(obj.Text or "")
            if txt:find("CAC Ultimate", 1, true) and not txt:find("v4.5.4", 1, true) and (txt:find("v4.5.3", 1, true) or txt:find("v4.5.2", 1, true) or txt:find("v4.5.1", 1, true) or txt:find("v4.5", 1, true) or txt:find("v4.4", 1, true) or txt:find("v4.3", 1, true) or txt:find("v3.0", 1, true)) then
                obj.Text = txt:gsub("v4%.3", "v4.5.4"):gsub("v4%.4", "v4.5.4"):gsub("v4%.5%.3", "v4.5.4"):gsub("v4%.5%.2", "v4.5.4"):gsub("v4%.5%.1", "v4.5.4"):gsub("v4%.5", "v4.5.4"):gsub("v3%.0", "v4.5.4")
            end

            if txt == "PROCESS STATUS" then
                local card = obj.Parent
                if card then
                    for _, sibling in ipairs(card:GetChildren()) do
                        if sibling:IsA("TextLabel") and sibling ~= obj then
                            sibling.TextSize = 12
                            sibling.TextWrapped = false
                            sibling.TextScaled = false
                        end
                    end
                end
            end
        end
    end
end

local function ScheduleUIPostBuildPatches()
    task.spawn(function()
        for _ = 1, 14 do
            ApplyUIPostBuildPatches()
            task.wait(0.35)
        end
    end)
end

local ResumeExtractorStatusRef = nil

TryResumePendingQueue = function()
    local state = PendingQueueResume or ReadQueueState()
    if not state or type(state) ~= "table" then
        return
    end
    if not Globals.IsAuthenticated then
        return
    end
    if TaskState.Running then
        return
    end

    PendingQueueResume = nil
    if not ResumeExtractorStatusRef then
        return
    end

    if state.task == "code_extract" then
        if ResumeExtractorStatusRef then
            local total = type(state.codes) == "table" and #state.codes or 0
            SetStatusLabel(ResumeExtractorStatusRef, "Status: Code queue found " .. tostring(total) .. " targets. Starting at index " .. tostring(state.next_index or 1) .. "...")
        end
        Notify("System", "Pending code queue detected. Resuming automatically...")
        RunExtractionTask("Code Dump Resume", ResumeExtractorStatusRef, function(status)
            Dumpers.ResumeCodeQueue(status)
        end)
    elseif state.task == "auto_publish" then
        Notify("System", "Pending auto publish queue detected. Resuming automatically...")
        RunExtractionTask("Auto Publish Resume", ResumeExtractorStatusRef, function(status)
            Dumpers.ResumeAutoPublishQueue(status)
        end)
    end
end

-- ==================================================================
-- INTERFACE CREATION (Dynamically unlocks after Auth)
-- ==================================================================

function UnlockUI()
    local TabHome = Window:CreateTab("Dashboard", "rbxassetid://10888331510")
    local TabTools = Window:CreateTab("Extractors", "rbxassetid://10888331510")
    local TabAutoPublish = Window:CreateTab("Auto Publish", "rbxassetid://6031265976")
    local TabSettings = Window:CreateTab("Settings", "rbxassetid://10888331510")
    local ExtractorStatus = { Text = "System Status: Awaiting Command..." }
    SetStatusLabel(ExtractorStatus, "System Status: Awaiting Command...")
    ResumeExtractorStatusRef = ExtractorStatus
    local queueResumeMode = HasActiveQueueResume()
    local earlyResumeStarted = false
    if queueResumeMode then
        earlyResumeStarted = true
        task.spawn(function()
            TryResumePendingQueue()
        end)
    end

    -- DASHBOARD
    TabHome:CreateSection("Session Details")
    TabHome:CreateDashboardStats({
        {
            Title = "License Status",
            Value = "UNVERIFIED",
            UpdateHook = function()
                if not Globals.IsAuthenticated then return "UNVERIFIED" end
                local status = tostring(Globals.LicenseStatus or "unknown"):upper()
                local plan = tostring(Globals.LicensePlan or "default")
                return status .. " / " .. plan
            end
        },
        {
            Title = "Time Remaining",
            Value = "Calculating...",
            UpdateHook = function()
                return TimeRemainingText()
            end
        }
    })
    
    TabHome:CreateSection("Server Telemetry")
    TabHome:CreateDashboardStats({
        { 
            Title = "Server Ping", 
            Value = "0ms", 
            UpdateHook = function() 
                local s, ping = pcall(function() return math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()) end)
                return s and (ping .. "ms") or "0ms"
            end 
        },
        { 
            Title = "Players", 
            Value = "0", 
            UpdateHook = function() return #Players:GetPlayers() .. "/" .. Players.MaxPlayers end 
        }
    })

    TabHome:CreateSection("Information")
    TabHome:CreateLabel("v4.5.4 (Auto rejoin server hop hotfix.)")
    TabHome:CreateLabel("Executor: " .. tostring(ExecutorName))
    TabHome:CreateLabel("UI Library Source: " .. tostring(LibrarySource))
    TabHome:CreateLabel("Queue Save Path: " .. tostring(QueueStatePath))

    -- EXTRACTORS / TOOLS
    TabTools:CreateSection("Queue Monitor")
    TabTools:CreateDashboardStats({
        {
            Title = "Queue State",
            Value = "IDLE",
            UpdateHook = function()
                if TaskState.Running then
                    return TaskState.CancelRequested and "CANCEL REQUESTED" or "RUNNING"
                end
                return "IDLE"
            end
        },
        {
            Title = "Current Task",
            Value = "NONE",
            UpdateHook = function()
                return TaskState.Running and tostring(TaskState.Name or "Task") or "NONE"
            end
        },
        {
            Title = "Elapsed",
            Value = "0s",
            UpdateHook = function()
                return FormatTaskElapsed()
            end
        },
        {
            Title = "Last Outcome",
            Value = "idle",
            UpdateHook = function()
                return tostring(TaskState.LastOutcome or "idle"):upper()
            end
        }
    })
    TabTools:CreateDashboardStats({
        {
            Title = "Process Status",
            Value = "AWAITING COMMAND",
            UpdateHook = function()
                return CompactStatusText(TaskState.LastStatus or "System Status: Awaiting Command...", 28)
            end
        },
        {
            Title = "Updated",
            Value = "0s ago",
            UpdateHook = function()
                local dt = math.max(0, math.floor(os.clock() - (TaskState.LastStatusAt or os.clock())))
                return tostring(dt) .. "s ago"
            end
        }
    })

    TabTools:CreateSection("Hex Data Processor")
    local codeInput = TabTools:CreateInput({ Name = "Hex Codes", Placeholder = "Paste space-separated codes..." })
    TabTools:CreateSection("Code Mode Auto Rejoin")
    local codeRejoinToggle = TabTools:CreateToggle({
        Name = "Enable Auto Rejoin on Code Cooldown",
        Default = Globals.AutoRejoinCodeEnabled,
        Callback = function(v)
            Globals.AutoRejoinCodeEnabled = v == true
            Globals.AutoRejoinCodeMode = AUTO_REJOIN_MODE
            SaveLocalCache()
        end
    })
    TabTools:CreateLabel("AUTO REJOIN: turn on this if u want more speed to publish/extract code.")
    TabTools:CreateButton({ 
        Name = "Execute Code Dump", 
        Callback = function()
            Globals.AutoRejoinCodeEnabled = codeRejoinToggle.Value == true
            Globals.AutoRejoinCodeMode = AUTO_REJOIN_MODE
            SaveLocalCache()
            RunExtractionTask("Code Dump", ExtractorStatus, function(status)
                Dumpers.CodeList(codeInput.Value, status)
            end)
        end
    })

    TabTools:CreateSection("Creator Scanning")
    local creatorInput = TabTools:CreateInput({ Name = "Target Creator", Placeholder = "Username..." })
    TabTools:CreateButton({ 
        Name = "Scan Creator Profile", 
        Callback = function()
            RunExtractionTask("Creator Scan", ExtractorStatus, function(status)
                Dumpers.Creator(creatorInput.Value, status)
            end)
        end
    })

    TabTools:CreateSection("Cache Extraction")
    local folderInput = TabTools:CreateInput({ Name = "Folder Target", Default = "All", Placeholder = "Folder name or All" })
    TabTools:CreateButton({ 
        Name = "Dump Cache Folder", 
        Callback = function()
            RunExtractionTask("Folder Dump", ExtractorStatus, function(status)
                Dumpers.Folder(folderInput.Value, status)
            end)
        end
    })
    
    TabTools:CreateSection("Custom Extraction")
    TabTools:CreateButton({ 
        Name = "Dump Selected Items", 
        Callback = function()
            RunExtractionTask("Selection Dump", ExtractorStatus, function(status)
                Dumpers.Selection(status)
            end)
        end
    })

    TabTools:CreateSection("SavedOutfits Forensics")
    local traceDurationInput = TabTools:CreateInput({
        Name = "Trace Duration (sec)",
        Default = "45",
        Placeholder = "10 - 600"
    })
    TabTools:CreateButton({
        Name = "Start SavedOutfits Trace",
        Callback = function()
            Dumpers.StartSavedOutfitsTrace(traceDurationInput.Value, ExtractorStatus)
        end
    })
    TabTools:CreateButton({
        Name = "Stop + Export SavedOutfits Trace",
        Callback = function()
            Dumpers.StopSavedOutfitsTrace(ExtractorStatus)
        end
    })
    TabTools:CreateButton({
        Name = "Export SavedOutfits Snapshot",
        Callback = function()
            Dumpers.ExportSavedOutfitsSnapshot(ExtractorStatus)
        end
    })

    TabTools:CreateSection("Task Control")
    TabTools:CreateButton({
        Name = "Cancel Active Task",
        Callback = function()
            RequestCancel(ExtractorStatus)
        end
    })
    TabTools:CreateButton({
        Name = "Cancel Auto Rejoin",
        Callback = function()
            DisableAutoRejoin("Auto rejoin cancelled by user.")
            if codeRejoinToggle and codeRejoinToggle.SetValue then
                codeRejoinToggle:SetValue(false)
            end
            SetStatusLabel(ExtractorStatus, "Status: Auto rejoin cancelled. Queue remains saved.")
        end
    })

    -- AUTO PUBLISH
    TabAutoPublish:CreateSection("Source")
    local autoPublishMode = CreateDropdownCompat(TabAutoPublish, {
        Name = "Source Mode",
        Options = { "Current Folder", "Specific Folder", "Selected Items", "All Folders" },
        Default = "Current Folder"
    })
    local autoPublishFolder = TabAutoPublish:CreateInput({
        Name = "Folder Target",
        Default = "All",
        Placeholder = "Used in Specific Folder mode"
    })
    local autoPublishPrefix = TabAutoPublish:CreateInput({
        Name = "Name Prefix",
        Default = Globals.AutoPublishNamePrefix,
        Placeholder = "Prefix for generated entries"
    })

    TabAutoPublish:CreateSection("Output")
    local autoCopyToggle = TabAutoPublish:CreateToggle({
        Name = "Copy Codes to Clipboard",
        Default = Globals.AutoCopyAutoPublishResults,
        Callback = function(v)
            Globals.AutoCopyAutoPublishResults = v == true
            SaveLocalCache()
        end
    })
    TabAutoPublish:CreateLabel("Result files are saved in: " .. tostring(Globals.WorkFolder))

    TabAutoPublish:CreateSection("Auto Rejoin (Publish Queue)")
    local publishRejoinToggle = TabAutoPublish:CreateToggle({
        Name = "Enable Auto Rejoin on Publish Cooldown",
        Default = Globals.AutoRejoinPublishEnabled,
        Callback = function(v)
            Globals.AutoRejoinPublishEnabled = v == true
            Globals.AutoRejoinPublishMode = AUTO_REJOIN_MODE
            SaveLocalCache()
        end
    })
    TabAutoPublish:CreateLabel("turn on this if u want more speed to publish/extract code.")
    local waitSliderConfig = {}
    waitSliderConfig.Name = "Delay Between Publish Calls (sec)"
    waitSliderConfig.Min = 5
    waitSliderConfig.Max = 300
    waitSliderConfig.Default = math.floor((tonumber(Globals.AutoPublishWaitSeconds) or 0.65) * 100)
    waitSliderConfig.Callback = function(v)
        Globals.AutoPublishWaitSeconds = tonumber(v) / 100
        SaveLocalCache()
    end
    local waitSlider = TabAutoPublish:CreateSlider(waitSliderConfig)

    TabAutoPublish:CreateSection("Queue Actions")
    TabAutoPublish:CreateButton({
        Name = "Start Auto Publish Queue",
        Callback = function()
            Globals.AutoPublishNamePrefix = tostring(autoPublishPrefix.Value or Globals.AutoPublishNamePrefix or "CAC")
            Globals.AutoRejoinPublishEnabled = publishRejoinToggle.Value == true
            Globals.AutoCopyAutoPublishResults = autoCopyToggle.Value == true
            Globals.AutoRejoinPublishMode = AUTO_REJOIN_MODE
            Globals.AutoPublishWaitSeconds = (tonumber(waitSlider.Value) or 65) / 100
            SaveLocalCache()

            RunExtractionTask("Auto Publish", ExtractorStatus, function(status)
                Dumpers.AutoPublish(autoPublishMode.Value, autoPublishFolder.Value, status, autoPublishPrefix.Value)
            end)
        end
    })
    TabAutoPublish:CreateButton({
        Name = "Resume Saved Queue",
        Callback = function()
            RunExtractionTask("Auto Publish Resume", ExtractorStatus, function(status)
                Dumpers.ResumeAutoPublishQueue(status)
            end)
        end
    })
    TabAutoPublish:CreateButton({
        Name = "Resume Saved Code Queue",
        Callback = function()
            RunExtractionTask("Code Queue Resume", ExtractorStatus, function(status)
                Dumpers.ResumeCodeQueue(status)
            end)
        end
    })
    TabAutoPublish:CreateButton({
        Name = "Clear Saved Queue",
        Callback = function()
            Dumpers.ClearSavedQueue()
            SetStatusLabel(ExtractorStatus, "Status: Saved queue cleared.")
        end
    })
    TabAutoPublish:CreateButton({
        Name = "Cancel Auto Rejoin",
        Callback = function()
            DisableAutoRejoin("Auto rejoin cancelled by user.")
            if publishRejoinToggle and publishRejoinToggle.SetValue then
                publishRejoinToggle:SetValue(false)
            end
            SetStatusLabel(ExtractorStatus, "Status: Auto rejoin cancelled. Queue remains saved.")
        end
    })
    TabAutoPublish:CreateButton({
        Name = "Copy Last Auto Publish Result File",
        Callback = function()
            local okRead, raw = SafeReadText(QueueResultsPath)
            if not okRead or not raw or raw == "" then
                return Notify("Info", "No result log found yet.")
            end
            CopyToClipboardOrNotify(raw, "Auto publish result log copied.")
        end
    })
    TabAutoPublish:CreateButton({
        Name = "Export Auto Publish Debug Dump",
        Callback = function()
            Dumpers.ExportAutoPublishDebug(ExtractorStatus)
        end
    })

    -- SETTINGS
    TabSettings:CreateSection("Delivery Integrations")
    TabSettings:CreateInput({
        Name = "Discord Webhook", 
        Default = LocalCache.Webhook,
        Placeholder = "https://discord.com/api/webhooks/...",
        Callback = function(val) 
            Globals.WebhookURL = val 
            LocalCache.Webhook = val
            SaveLocalCache()
        end
    })
    TabSettings:CreateLabel("Required for automatic payload delivery.")

    TabSettings:CreateSection("Queue Resume")
    TabSettings:CreateToggle({
        Name = "Maximize Auto-Rejoin",
        Default = Globals.MaximizeAutoRejoin == true,
        Callback = function(v)
            Globals.MaximizeAutoRejoin = v == true
            SaveLocalCache()
        end
    })
    TabSettings:CreateLabel("Rejoins instantly after every 5 successful queue operations. Only enable this if you know what you are doing.")
    TabSettings:CreateToggle({
        Name = "Fast Queue Resume After Rejoin",
        Default = Globals.QueueFastResumeEnabled ~= false,
        Callback = function(v)
            Globals.QueueFastResumeEnabled = v == true
            SaveLocalCache()
        end
    })
    TabSettings:CreateLabel("When a saved queue rejoins, CAC skips the long login screen and validates the session in the background.")

    if queueResumeMode then
        task.delay(2.8, ScheduleUIPostBuildPatches)
    else
        ScheduleUIPostBuildPatches()
    end

    if not earlyResumeStarted then
        task.delay(queueResumeMode and 0.12 or 0.8, function()
            TryResumePendingQueue()
        end)
    end
end

-- ==================================================================
-- LOGIN GATEWAY (Shown immediately after loading finishes)
-- ==================================================================
local LicenseTab = Window:CreateTab("Security", "rbxassetid://6031280882")
LicenseTab:CreateSection("Access Control")

local keyBox = LicenseTab:CreateInput({ 
    Name = "License Key", 
    Default = LocalCache.Key,
    Placeholder = "Enter License Key..." 
})

LicenseTab:CreateButton({
    Name = "Login with Key",
    Callback = function()
        ValidateKey(keyBox.Value)
    end
})

LicenseTab:CreateButton({
    Name = "Switch Key (Force)",
    Callback = function()
        ValidateKey(keyBox.Value, true)
    end
})

LicenseTab:CreateButton({
    Name = "Copy Saved Key",
    Callback = function()
        local keyToCopy = GetBestKnownKey(keyBox and keyBox.Value or "")
        if keyToCopy == "" then
            Notify("Info", "No key found locally. Login once with key to store it.")
            return
        end
        CopyToClipboardOrNotify(keyToCopy, "License key copied to clipboard.")
    end
})

LicenseTab:CreateButton({
    Name = "Auto Login (HWID)",
    Callback = function()
        TryAutoLogin(true)
    end
})

LicenseTab:CreateButton({
    Name = "Validate Active Session",
    Callback = function()
        local ok, err = ValidateSessionNow(true)
        if not ok then
            Notify("Session Notice", NormalizeSessionRecheckMessage(err or "Session recheck failed. Login again when convenient."))
        end
    end
})

LicenseTab:CreateSection("Security Tools")
LicenseTab:CreateButton({
    Name = "Show License Snapshot",
    Callback = function()
        if not Globals.IsAuthenticated then
            Notify("Info", "No active session yet.")
            return
        end
        local status = tostring(Globals.LicenseStatus or "unknown"):upper()
        local plan = tostring(Globals.LicensePlan or "default")
        local remaining = TimeRemainingText()
        local message = "Status: " .. status .. " | Plan: " .. plan .. " | Remaining: " .. remaining
        Notify("License Snapshot", message)
    end
})

LicenseTab:CreateButton({
    Name = "Check API Connectivity",
    Callback = function()
        local ok, data, err = ApiGet(AuthLogic.HealthRoute)
        if ok and data and data.ok then
            Notify("System", "Auth API online.")
        else
            Notify("Error", err or "Auth API check failed.")
        end
    end
})

LicenseTab:CreateButton({
    Name = "Wipe Local Login Data",
    Callback = function()
        WipeLocalLoginData()
        pcall(function()
            if keyBox then
                keyBox.Value = ""
            end
        end)
        Notify("System", "Local key/session data wiped (no key revoked). Run login again.")
    end
})

LicenseTab:CreateSection("Hardware")
LicenseTab:CreateButton({
    Name = "Copy HWID",
    Callback = function()
        CopyToClipboardOrNotify(gethwid(), "Hardware ID copied to clipboard.")
    end
})
LicenseTab:CreateLabel("Security note: license checks are handled server-side.")

-- Finish the initial loading overlay
Window:FinishLoading()

task.defer(function()
    task.wait(PendingQueueResume and 0 or 0.25)
    if not TryFastQueueResumeFromCache() then
        TryAutoLogin(false)
    end
    task.delay(1.2, function()
        if not HasActiveQueueResume() then
            RestoreCACGameUI()
        end
    end)
end)
