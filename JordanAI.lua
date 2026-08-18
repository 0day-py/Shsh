local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
if not player then
    return
end

local playerGui = player:WaitForChild("PlayerGui")

local function getRequest()
    if syn and syn.request then
        return syn.request
    end

    if http and http.request then
        return http.request
    end

    if request then
        return request
    end

    if http_request then
        return http_request
    end

    return nil
end

local PROVIDERS = {
    groq = {
        name = "Groq",
        url = "https://api.groq.com/openai/v1/chat/completions",
        models = {
            "llama-3.3-70b-versatile",
            "llama-3.1-8b-instant",
            "gemma2-9b-it",
            "mixtral-8x7b-32768"
        }
    },
    openrouter = {
        name = "OpenRouter",
        url = "https://openrouter.ai/api/v1/chat/completions",
        models = {
            "meta-llama/llama-3.3-70b-instruct:free",
            "google/gemini-2.0-flash-exp:free",
            "mistralai/mistral-7b-instruct:free",
            "qwen/qwen-2.5-72b-instruct:free"
        }
    },
    cerebras = {
        name = "Cerebras",
        url = "https://api.cerebras.ai/v1/chat/completions",
        models = {
            "llama-3.3-70b",
            "llama3.1-8b",
            "qwen-3-32b"
        }
    }
}

for _, provider in pairs(PROVIDERS) do
    provider.defaultModel = provider.models[1]
end

local PROVIDER_ORDER = {"groq", "openrouter", "cerebras"}

local function loadSettings()
    local defaults = {
        provider = "groq",
        groqApi = "",
        groqModel = PROVIDERS.groq.defaultModel,
        openrouterApi = "",
        openrouterModel = PROVIDERS.openrouter.defaultModel,
        cerebrasApi = "",
        cerebrasModel = PROVIDERS.cerebras.defaultModel,
        prompt = "You are a helpful AI assistant.",
        enabled = true,
        range = 0,
        cooldown = 6
    }

    if not isfile or not readfile then
        return defaults
    end

    local okFile, exists = pcall(function()
        return isfile("JordanAI_Config.json")
    end)

    if not okFile or not exists then
        return defaults
    end

    local ok, result = pcall(function()
        return HttpService:JSONDecode(
            readfile("JordanAI_Config.json")
        )
    end)

    if ok and type(result) == "table" then
        for k, v in pairs(defaults) do
            if result[k] == nil then
                result[k] = v
            end
        end

        return result
    end

    return defaults
end

local settings = loadSettings()

local MAX_HISTORY = 12
local MAX_USER_MESSAGE_LEN = 400
local MAX_REPLY_TOKENS = 250
local conversations = {}

local function getConversation(userId)
    if not conversations[userId] then
        conversations[userId] = {}
    end

    return conversations[userId]
end

local function pushMessage(convo, role, content)
    table.insert(convo, {role = role, content = content})

    while #convo > MAX_HISTORY do
        table.remove(convo, 1)
    end
end

local function saveSettings()
    if not writefile then
        return false
    end

    local ok = pcall(function()
        writefile(
            "JordanAI_Config.json",
            HttpService:JSONEncode(settings)
        )
    end)

    return ok
end

local oldGui = playerGui:FindFirstChild("JordanAI")
if oldGui then
    oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "JordanAI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local FONT_SIZE = 12

local function round(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = obj
    return c
end

local function outline(obj, colour, thickness)
    local s = Instance.new("UIStroke")
    s.Color = colour
    s.Thickness = thickness or 1
    s.Parent = obj
    return s
end

local function button(parent, text, size, position)
    local baseColor = Color3.fromRGB(38, 38, 38)
    local hoverColor = Color3.fromRGB(48, 48, 48)

    local b = Instance.new("TextButton")
    b.Size = size
    b.Position = position
    b.BackgroundColor3 = baseColor
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.fromRGB(205, 205, 205)
    b.TextSize = FONT_SIZE
    b.Font = Enum.Font.GothamMedium
    b.AutoButtonColor = false
    b.Parent = parent

    round(b, 7)
    outline(b, Color3.fromRGB(65, 65, 65), 1)

    local scale = Instance.new("UIScale")
    scale.Parent = b

    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = hoverColor}):Play()
    end)

    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = baseColor}):Play()
        TweenService:Create(scale, TweenInfo.new(0.12), {Scale = 1}):Play()
    end)

    b.MouseButton1Down:Connect(function()
        TweenService:Create(scale, TweenInfo.new(0.08), {Scale = 0.95}):Play()
    end)

    b.MouseButton1Up:Connect(function()
        TweenService:Create(scale, TweenInfo.new(0.12), {Scale = 1}):Play()
    end)

    return b
end

local function textbox(parent, placeholder, text, size, position, multiline)
    local b = Instance.new("TextBox")
    b.Size = size
    b.Position = position
    b.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    b.BorderSizePixel = 0
    b.Text = text or ""
    b.PlaceholderText = placeholder
    b.PlaceholderColor3 = Color3.fromRGB(90, 90, 90)
    b.TextColor3 = Color3.fromRGB(205, 205, 205)
    b.TextSize = FONT_SIZE
    b.Font = Enum.Font.Gotham
    b.ClearTextOnFocus = false
    b.MultiLine = multiline or false
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
    b.Parent = parent

    round(b, 7)
    outline(b, Color3.fromRGB(55, 55, 55), 1)

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.PaddingTop = UDim.new(0, 6)
    padding.PaddingBottom = UDim.new(0, 6)
    padding.Parent = b

    return b
end

local function label(parent, text, size, position, fontSize)
    local l = Instance.new("TextLabel")
    l.Size = size
    l.Position = position
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Color3.fromRGB(170, 170, 170)
    l.TextSize = fontSize or FONT_SIZE
    l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

local function makeWindow(name, titleText, size, minSize, maxSize)
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Size = size
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
    frame.BorderSizePixel = 0
    frame.Parent = gui

    round(frame, 12)
    outline(frame, Color3.fromRGB(68, 68, 68), 1.5)

    if minSize or maxSize then
        local constraint = Instance.new("UISizeConstraint")
        constraint.MinSize = minSize or Vector2.new(0, 0)
        constraint.MaxSize = maxSize or Vector2.new(math.huge, math.huge)
        constraint.Parent = frame
    end

    local drag = Instance.new("UIDragDetector")
    drag.Parent = frame

    local title = label(
        frame,
        titleText,
        UDim2.new(1, -24, 0, 26),
        UDim2.new(0, 12, 0, 6),
        15
    )

    title.Font = Enum.Font.GothamBold
    title.TextColor3 = Color3.fromRGB(220, 220, 220)

    return frame
end

local function makeSlider(parent, title, y, minValue, maxValue, initialValue, valueText, onChange)
    label(parent, title, UDim2.new(0.5, 0, 0, 20), UDim2.new(0, 0, 0, y))

    local valueLabel = label(parent, "", UDim2.new(0.5, 0, 0, 20), UDim2.new(0.5, 0, 0, y))
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 6)
    bar.Position = UDim2.new(0, 0, 0, y + 28)
    bar.BackgroundColor3 = Color3.fromRGB(43, 43, 43)
    bar.BorderSizePixel = 0
    bar.Parent = parent
    round(bar, 4)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    fill.BorderSizePixel = 0
    fill.Parent = bar
    round(fill, 4)

    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0, 15, 0, 15)
    knob.BackgroundColor3 = Color3.fromRGB(175, 175, 175)
    knob.BorderSizePixel = 0
    knob.Text = ""
    knob.Parent = bar
    round(knob, 8)

    local dragging = false

    local function update(value)
        value = math.clamp(math.floor(value + 0.5), minValue, maxValue)
        local ratio = (value - minValue) / (maxValue - minValue)

        fill.Size = UDim2.new(ratio, 0, 1, 0)
        knob.Position = UDim2.new(ratio, -7, 0.5, -7)
        valueLabel.Text = valueText(value)

        onChange(value)

        return value
    end

    local function fromX(x)
        local ratio = math.clamp(
            (x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X,
            0,
            1
        )

        update(minValue + ratio * (maxValue - minValue))
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            fromX(input.Position.X)
        end
    end)

    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            fromX(input.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    update(initialValue)

    return update
end

local notifyContainer = Instance.new("Frame")
notifyContainer.Size = UDim2.new(0, 220, 1, -20)
notifyContainer.Position = UDim2.new(1, -236, 0, 10)
notifyContainer.BackgroundTransparency = 1
notifyContainer.Parent = gui

local notifyLayout = Instance.new("UIListLayout")
notifyLayout.Padding = UDim.new(0, 6)
notifyLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notifyLayout.Parent = notifyContainer

local NOTIFY_COLORS = {
    info = Color3.fromRGB(45, 45, 45),
    success = Color3.fromRGB(35, 90, 58),
    error = Color3.fromRGB(105, 40, 40)
}

local notifyCounter = 0

local function notify(text, kind)
    kind = kind or "info"
    notifyCounter = notifyCounter + 1

    local card = Instance.new("Frame")
    card.LayoutOrder = notifyCounter
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = NOTIFY_COLORS[kind] or NOTIFY_COLORS.info
    card.BackgroundTransparency = 1
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.Parent = notifyContainer

    round(card, 7)
    local stroke = outline(card, Color3.fromRGB(70, 70, 70), 1)
    stroke.Transparency = 1

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, -16, 0, 0)
    textLabel.AutomaticSize = Enum.AutomaticSize.Y
    textLabel.Position = UDim2.new(0, 8, 0, 6)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = text
    textLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
    textLabel.TextSize = FONT_SIZE
    textLabel.Font = Enum.Font.GothamMedium
    textLabel.TextWrapped = true
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.TextTransparency = 1
    textLabel.Parent = card

    local padding = Instance.new("UIPadding")
    padding.PaddingBottom = UDim.new(0, 6)
    padding.Parent = card

    card.Position = UDim2.new(0.15, 0, 0, 0)

    TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0.05,
        Position = UDim2.new(0, 0, 0, 0)
    }):Play()

    TweenService:Create(stroke, TweenInfo.new(0.25), {Transparency = 0.3}):Play()
    TweenService:Create(textLabel, TweenInfo.new(0.25), {TextTransparency = 0}):Play()

    task.delay(4, function()
        if not card.Parent then
            return
        end

        local outTween = TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            BackgroundTransparency = 1,
            Position = UDim2.new(0.15, 0, 0, 0)
        })

        TweenService:Create(stroke, TweenInfo.new(0.2), {Transparency = 1}):Play()
        TweenService:Create(textLabel, TweenInfo.new(0.2), {TextTransparency = 1}):Play()

        outTween:Play()
        outTween.Completed:Wait()
        card:Destroy()
    end)
end

local keyWindow = makeWindow(
    "KeyWindow",
    "Key System",
    UDim2.new(0.7, 0, 0, 165),
    Vector2.new(230, 165),
    Vector2.new(300, 165)
)

label(
    keyWindow,
    "Enter your access key to continue",
    UDim2.new(1, -24, 0, 18),
    UDim2.new(0, 12, 0, 38),
    11
)

local keyBox = textbox(
    keyWindow,
    "Enter key",
    "",
    UDim2.new(1, -24, 0, 34),
    UDim2.new(0, 12, 0, 60)
)

local enterButton = button(
    keyWindow,
    "Enter Key",
    UDim2.new(0.47, -4, 0, 34),
    UDim2.new(0, 12, 0, 106)
)

local getKeyButton = button(
    keyWindow,
    "Get Key",
    UDim2.new(0.47, -4, 0, 34),
    UDim2.new(0.53, -8, 0, 106)
)

getKeyButton.MouseButton1Click:Connect(function()
    if setclipboard then
        setclipboard("https://discord.gg/a2UB4qGnEH")
        notify("Discord link copied.", "success")
    else
        notify("Discord: a2UB4qGnEH", "info")
    end
end)

local aiWindow = makeWindow(
    "AIWindow",
    "AI Chatbot made by Jordan",
    UDim2.new(0.8, 0, 0.68, 0),
    Vector2.new(300, 360),
    Vector2.new(360, 440)
)

aiWindow.Visible = false

local tabs = Instance.new("Frame")
tabs.Size = UDim2.new(1, -24, 0, 30)
tabs.Position = UDim2.new(0, 12, 0, 38)
tabs.BackgroundTransparency = 1
tabs.Parent = aiWindow

local chatTab = button(
    tabs,
    "Chat",
    UDim2.new(0.32, -4, 1, 0),
    UDim2.new(0, 0, 0, 0)
)

local settingsTab = button(
    tabs,
    "Settings",
    UDim2.new(0.32, -4, 1, 0),
    UDim2.new(0.34, 0, 0, 0)
)

local creditsTab = button(
    tabs,
    "Credits",
    UDim2.new(0.32, -4, 1, 0),
    UDim2.new(0.68, 0, 0, 0)
)

local chatPage = Instance.new("CanvasGroup")
chatPage.Size = UDim2.new(1, -24, 1, -78)
chatPage.Position = UDim2.new(0, 12, 0, 74)
chatPage.BackgroundTransparency = 1
chatPage.Parent = aiWindow

local settingsPage = Instance.new("CanvasGroup")
settingsPage.Size = UDim2.new(1, -24, 1, -78)
settingsPage.Position = UDim2.new(0, 12, 0, 74)
settingsPage.BackgroundTransparency = 1
settingsPage.Visible = false
settingsPage.Parent = aiWindow

local settingsScroll = Instance.new("ScrollingFrame")
settingsScroll.Size = UDim2.new(1, 0, 1, 0)
settingsScroll.BackgroundTransparency = 1
settingsScroll.BorderSizePixel = 0
settingsScroll.ScrollBarThickness = 3
settingsScroll.ScrollBarImageColor3 = Color3.fromRGB(75, 75, 75)
settingsScroll.CanvasSize = UDim2.new(0, 0, 0, 500)
settingsScroll.Parent = settingsPage

local creditsPage = Instance.new("CanvasGroup")
creditsPage.Size = UDim2.new(1, -24, 1, -78)
creditsPage.Position = UDim2.new(0, 12, 0, 74)
creditsPage.BackgroundTransparency = 1
creditsPage.Visible = false
creditsPage.Parent = aiWindow

local history = Instance.new("ScrollingFrame")
history.Size = UDim2.new(1, 0, 1, -50)
history.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
history.BorderSizePixel = 0
history.ScrollBarThickness = 3
history.ScrollBarImageColor3 = Color3.fromRGB(75, 75, 75)
history.AutomaticCanvasSize = Enum.AutomaticSize.Y
history.CanvasSize = UDim2.new(0, 0, 0, 0)
history.Parent = chatPage

round(history, 8)
outline(history, Color3.fromRGB(48, 48, 48), 1)

local historyLayout = Instance.new("UIListLayout")
historyLayout.Padding = UDim.new(0, 6)
historyLayout.SortOrder = Enum.SortOrder.LayoutOrder
historyLayout.Parent = history

local historyPadding = Instance.new("UIPadding")
historyPadding.PaddingTop = UDim.new(0, 6)
historyPadding.PaddingBottom = UDim.new(0, 6)
historyPadding.PaddingLeft = UDim.new(0, 6)
historyPadding.PaddingRight = UDim.new(0, 6)
historyPadding.Parent = history

local messageBox = textbox(
    chatPage,
    "Ask the AI something...",
    "",
    UDim2.new(1, -76, 0, 38),
    UDim2.new(0, 0, 1, -40),
    false
)

local sendButton = button(
    chatPage,
    "Send",
    UDim2.new(0, 68, 0, 38),
    UDim2.new(1, -68, 1, -40)
)

local function addMessage(author, text)
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, -2, 0, 0)
    item.AutomaticSize = Enum.AutomaticSize.Y
    item.BackgroundColor3 = Color3.fromRGB(29, 29, 29)
    item.BorderSizePixel = 0
    item.Text = author .. "\n" .. text
    item.TextColor3 = Color3.fromRGB(195, 195, 195)
    item.TextSize = FONT_SIZE
    item.Font = Enum.Font.Gotham
    item.TextWrapped = true
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextYAlignment = Enum.TextYAlignment.Top
    item.Parent = history

    round(item, 6)

    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, 7)
    p.PaddingRight = UDim.new(0, 7)
    p.PaddingTop = UDim.new(0, 6)
    p.PaddingBottom = UDim.new(0, 6)
    p.Parent = item

    task.defer(function()
        history.CanvasPosition = Vector2.new(
            0,
            math.max(0, history.AbsoluteCanvasSize.Y)
        )
    end)
end

local function clearHistory()
    for _, child in ipairs(history:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end
end

label(
    settingsScroll,
    "AI Provider",
    UDim2.new(0.5, 0, 0, 20),
    UDim2.new(0, 0, 0, 0)
)

local providerButton = button(
    settingsScroll,
    "",
    UDim2.new(0, 100, 0, 26),
    UDim2.new(1, -100, 0, -2)
)

label(
    settingsScroll,
    "API Key",
    UDim2.new(1, 0, 0, 16),
    UDim2.new(0, 0, 0, 34)
)

local apiBox = textbox(
    settingsScroll,
    "",
    "",
    UDim2.new(1, 0, 0, 32),
    UDim2.new(0, 0, 0, 52)
)

label(
    settingsScroll,
    "Model Name",
    UDim2.new(1, 0, 0, 16),
    UDim2.new(0, 0, 0, 92)
)

local modelBox = textbox(
    settingsScroll,
    "",
    "",
    UDim2.new(1, 0, 0, 32),
    UDim2.new(0, 0, 0, 110)
)

label(
    settingsScroll,
    "System Prompt",
    UDim2.new(1, 0, 0, 16),
    UDim2.new(0, 0, 0, 150)
)

local promptBox = textbox(
    settingsScroll,
    "Tell the AI how it should behave...",
    settings.prompt,
    UDim2.new(1, 0, 0, 62),
    UDim2.new(0, 0, 0, 168),
    true
)

local function refreshProviderFields()
    providerButton.Text = PROVIDERS[settings.provider].name
    apiBox.Text = settings[settings.provider .. "Api"]
    apiBox.PlaceholderText = "Paste your " .. PROVIDERS[settings.provider].name .. " API key"
    modelBox.Text = settings[settings.provider .. "Model"]
    modelBox.PlaceholderText = "Example: " .. PROVIDERS[settings.provider].defaultModel
end

providerButton.MouseButton1Click:Connect(function()
    settings[settings.provider .. "Api"] = apiBox.Text
    settings[settings.provider .. "Model"] = modelBox.Text

    local currentIndex = table.find(PROVIDER_ORDER, settings.provider) or 1
    local nextIndex = (currentIndex % #PROVIDER_ORDER) + 1
    settings.provider = PROVIDER_ORDER[nextIndex]

    refreshProviderFields()
    notify("Switched to " .. PROVIDERS[settings.provider].name, "info")
end)

refreshProviderFields()

label(
    settingsScroll,
    "AI Enabled",
    UDim2.new(0.5, 0, 0, 22),
    UDim2.new(0, 0, 0, 242)
)

local enabledButton = button(
    settingsScroll,
    "",
    UDim2.new(0, 64, 0, 26),
    UDim2.new(1, -64, 0, 240)
)

local function updateEnabled()
    if settings.enabled then
        enabledButton.Text = "ON"
        enabledButton.BackgroundColor3 = Color3.fromRGB(65, 65, 65)
    else
        enabledButton.Text = "OFF"
        enabledButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    end
end

enabledButton.MouseButton1Click:Connect(function()
    settings.enabled = not settings.enabled
    updateEnabled()
    notify(settings.enabled and "AI enabled." or "AI disabled.", "info")
end)

makeSlider(settingsScroll, "Speech Range", 276, 0, 500, settings.range, function(value)
    if value == 0 then
        return "0 — Infinite"
    end

    return tostring(value)
end, function(value)
    settings.range = value
end)

makeSlider(settingsScroll, "Request Cooldown", 336, 1, 30, settings.cooldown, function(value)
    return value .. "s"
end, function(value)
    settings.cooldown = value
end)

local clearButton = button(
    settingsScroll,
    "Clear Memory",
    UDim2.new(1, 0, 0, 32),
    UDim2.new(0, 0, 0, 392)
)

local saveButton = button(
    settingsScroll,
    "Save Configuration",
    UDim2.new(1, 0, 0, 32),
    UDim2.new(0, 0, 0, 430)
)

saveButton.MouseButton1Click:Connect(function()
    settings[settings.provider .. "Api"] = apiBox.Text
    settings[settings.provider .. "Model"] = modelBox.Text
    settings.prompt = promptBox.Text

    if settings[settings.provider .. "Api"] == "" then
        notify("Enter your " .. PROVIDERS[settings.provider].name .. " API key.", "error")
        return
    end

    if settings[settings.provider .. "Model"] == "" then
        notify("Enter a model name.", "error")
        return
    end

    if saveSettings() then
        notify("Configuration saved.", "success")
    else
        notify("Saved for this session only.", "info")
    end
end)

local creditsText = label(
    creditsPage,
    "Made by Jordan",
    UDim2.new(1, 0, 0, 44),
    UDim2.new(0, 0, 0.35, 0),
    18
)

creditsText.TextXAlignment = Enum.TextXAlignment.Center
creditsText.TextColor3 = Color3.fromRGB(210, 210, 210)
creditsText.Font = Enum.Font.GothamBold

local creditsSub = label(
    creditsPage,
    "AI Chatbot",
    UDim2.new(1, 0, 0, 24),
    UDim2.new(0, 0, 0.48, 0),
    11
)

creditsSub.TextXAlignment = Enum.TextXAlignment.Center

local pages = {
    chat = chatPage,
    settings = settingsPage,
    credits = creditsPage
}

local function showPage(pageName)
    for name, page in pairs(pages) do
        if name == pageName then
            page.Visible = true
            page.GroupTransparency = 1
            TweenService:Create(page, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                GroupTransparency = 0
            }):Play()
        else
            page.Visible = false
        end
    end
end

chatTab.MouseButton1Click:Connect(function()
    showPage("chat")
end)

settingsTab.MouseButton1Click:Connect(function()
    showPage("settings")
end)

creditsTab.MouseButton1Click:Connect(function()
    showPage("credits")
end)

local function getInventoryNames()
    local names = {}

    local backpack = player:FindFirstChild("Backpack")

    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(names, item.Name)
            end
        end
    end

    local character = player.Character

    if character then
        for _, item in ipairs(character:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(names, item.Name .. " (equipped)")
            end
        end
    end

    return names
end

local function buildSystemPrompt(speakerName)
    local tools = getInventoryNames()
    local toolsText = #tools > 0 and table.concat(tools, ", ") or "none"

    return "You control this Roblox character. You are currently talking with " .. speakerName .. "; "
        .. "you may address them by name. Current tools: " .. toolsText .. ". "
        .. "If asked what tools you have, list them plainly and ask which to equip. If told which one, confirm "
        .. "briefly and add [ACTION:EQUIP:ExactToolName] using the exact name from the list. If also asked to "
        .. "use, drink, eat, or swing it, also add [ACTION:USE] right after the equip tag. If asked to unequip, "
        .. "add [ACTION:UNEQUIP]. To jump, add [ACTION:JUMP] once, or [ACTION:JUMP:N] to jump N times in a row "
        .. "(max 5) if asked for multiple jumps. For emotes add exactly one of [ACTION:WAVE], [ACTION:POINT], "
        .. "[ACTION:DANCE], [ACTION:DANCE2], [ACTION:DANCE3], [ACTION:LAUGH], or [ACTION:CHEER] depending on what "
        .. "was asked for (DANCE2 and DANCE3 are alternate dances if asked for a different one). If asked to "
        .. "stop dancing or stop emoting, add [ACTION:STOP]. If asked to hit or attack a specific player, add "
        .. "[ACTION:HIT:ExactUsername] — you will automatically draw a weapon if one is available. Only include "
        .. "a tag when actually requested. Keep replies short."
end

local EMOTE_ANIMATION_IDS = {
    wave = "rbxassetid://507770239",
    point = "rbxassetid://507770453",
    dance = "rbxassetid://507771019",
    dance2 = "rbxassetid://507776043",
    dance3 = "rbxassetid://507777268",
    laugh = "rbxassetid://507770818",
    cheer = "rbxassetid://507770677"
}

local activeEmoteTrack = nil

local function stopEmote()
    if activeEmoteTrack then
        pcall(function()
            activeEmoteTrack:Stop()
        end)
        activeEmoteTrack = nil
    end
end

local function playEmote(name)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not humanoid then
        return
    end

    stopEmote()

    local animId = EMOTE_ANIMATION_IDS[name]

    if not animId then
        pcall(function()
            humanoid:PlayEmote(name)
        end)
        return
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")

    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    pcall(function()
        local animation = Instance.new("Animation")
        animation.AnimationId = animId

        local track = animator:LoadAnimation(animation)
        track.Looped = true
        track:Play()
        activeEmoteTrack = track
    end)
end

local function findWeaponTool()
    local backpack = player:FindFirstChild("Backpack")

    if not backpack then
        return nil
    end

    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") and item.Name:lower():find("sword", 1, true) then
            return item
        end
    end

    return nil
end

local ACTIONS = {
    jump = function(param)
        local count = math.clamp(math.floor(tonumber(param) or 1), 1, 5)
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if not humanoid then
            return
        end

        for _ = 1, count do
            humanoid.Jump = true
            task.wait(0.5)
        end
    end,

    wave = function()
        playEmote("wave")
    end,

    dance = function()
        playEmote("dance")
    end,

    dance2 = function()
        playEmote("dance2")
    end,

    dance3 = function()
        playEmote("dance3")
    end,

    laugh = function()
        playEmote("laugh")
    end,

    cheer = function()
        playEmote("cheer")
    end,

    point = function()
        playEmote("point")
    end,

    equip = function(toolName)
        if not toolName or toolName == "" then
            return
        end

        local backpack = player:FindFirstChild("Backpack")
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if not backpack or not humanoid then
            return
        end

        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower() == toolName:lower() then
                humanoid:EquipTool(item)
                break
            end
        end
    end,

    unequip = function()
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if humanoid then
            humanoid:UnequipTools()
        end
    end,

    stop = function()
        stopEmote()
    end,

    use = function()
        local character = player.Character
        local tool = character and character:FindFirstChildOfClass("Tool")

        if not tool then
            return
        end

        pcall(function()
            tool:Activate()
        end)
    end,

    hit = function(targetName)
        if not targetName or targetName == "" then
            return
        end

        local targetPlayer

        for _, other in ipairs(Players:GetPlayers()) do
            if other.Name:lower() == targetName:lower()
            or other.DisplayName:lower() == targetName:lower() then
                targetPlayer = other
                break
            end
        end

        if not targetPlayer then
            return
        end

        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")

        if not humanoid or not rootPart then
            return
        end

        for _ = 1, 40 do
            local targetChar = targetPlayer.Character
            local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")

            if not targetRoot then
                return
            end

            if (rootPart.Position - targetRoot.Position).Magnitude <= 5 then
                break
            end

            humanoid:MoveTo(targetRoot.Position)
            humanoid.MoveToFinished:Wait(1)
        end

        local tool = character:FindFirstChildOfClass("Tool")

        if not tool then
            local weapon = findWeaponTool()

            if weapon then
                humanoid:EquipTool(weapon)
                task.wait(0.2)
                tool = character:FindFirstChildOfClass("Tool")
            end
        end

        if tool then
            pcall(function()
                tool:Activate()
            end)
        end
    end
}

local function processReply(rawText)
    local triggered = {}

    local cleaned = rawText:gsub("%[ACTION:([%w_]+):?([^%]]*)%]", function(name, param)
        table.insert(triggered, {name = name:lower(), param = param})
        return ""
    end)

    cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s%s+", " ")

    if #triggered > 0 then
        task.spawn(function()
            for _, action in ipairs(triggered) do
                local actionFn = ACTIONS[action.name]

                if actionFn then
                    actionFn(action.param)
                end
            end
        end)
    end

    if cleaned == "" and #triggered > 0 then
        cleaned = "*" .. triggered[1].name .. "*"
    end

    return cleaned
end

local function requestCompletion(provider, apiKey, model, messages)
    local req = getRequest()

    if not req then
        return false, "This environment does not provide an HTTP request function.", nil
    end

    local payload = {
        model = model,
        messages = messages,
        max_tokens = MAX_REPLY_TOKENS
    }

    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. apiKey
    }

    if settings.provider == "openrouter" then
        headers["HTTP-Referer"] = "https://www.roblox.com"
        headers["X-Title"] = "JordanAI"
    end

    local ok, response = pcall(function()
        return req({
            Url = provider.url,
            Method = "POST",
            Headers = headers,
            Body = HttpService:JSONEncode(payload)
        })
    end)

    if not ok then
        return false, "Request failed.", nil
    end

    if not response then
        return false, "No response was returned.", nil
    end

    if response.StatusCode < 200 or response.StatusCode >= 300 then
        local message = provider.name .. " request failed."

        local decoded = pcall(function()
            return HttpService:JSONDecode(response.Body)
        end)

        if decoded then
            local data = HttpService:JSONDecode(response.Body)

            if data
            and data.error
            and data.error.message then
                message = tostring(data.error.message)
            end
        end

        return false, message, response.StatusCode
    end

    local decodedOk, data = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)

    if not decodedOk or type(data) ~= "table" then
        return false, "Invalid response from " .. provider.name .. ".", response.StatusCode
    end

    local answer = data
        and data.choices
        and data.choices[1]
        and data.choices[1].message
        and data.choices[1].message.content

    if type(answer) ~= "string" or answer == "" then
        return false, provider.name .. " returned no message.", response.StatusCode
    end

    return true, answer, response.StatusCode
end

local function isRateLimited(statusCode, message)
    if statusCode == 429 then
        return true
    end

    local lowered = (message or ""):lower()

    return lowered:find("rate limit") ~= nil
        or lowered:find("rate_limit") ~= nil
        or lowered:find("too many requests") ~= nil
end

local function isTokenLimitError(message)
    local lowered = message:lower()

    return lowered:find("token") ~= nil
        or lowered:find("context length") ~= nil
        or lowered:find("context_length") ~= nil
        or lowered:find("too long") ~= nil
        or lowered:find("reduce the length") ~= nil
end

local function buildCandidateModels(provider, preferredModel)
    local list = {preferredModel}

    for _, model in ipairs(provider.models) do
        if model ~= preferredModel then
            table.insert(list, model)
        end
    end

    return list
end

local function tryModels(provider, apiKey, messages, preferredModel)
    local candidates = buildCandidateModels(provider, preferredModel)
    local lastError = "No models available."

    for index, model in ipairs(candidates) do
        local ok, result, statusCode = requestCompletion(provider, apiKey, model, messages)

        if ok then
            if index > 1 then
                notify("Rate limited — switched to " .. model, "info")
            end

            return true, result
        end

        lastError = result

        if not isRateLimited(statusCode, result) then
            return false, result
        end
    end

    return false, lastError
end

local function describeSpeaker(who)
    if who.DisplayName ~= "" and who.DisplayName ~= who.Name then
        return who.DisplayName .. " (@" .. who.Name .. ")"
    end

    return who.Name
end

local function askAI(userId, userText, speakerName, isRetry)
    if not settings.enabled then
        return false, "AI is disabled."
    end

    local provider = PROVIDERS[settings.provider]
    local apiKey = settings[settings.provider .. "Api"]
    local model = settings[settings.provider .. "Model"]

    if apiKey == "" then
        return false, "No " .. provider.name .. " API key has been configured."
    end

    if model == "" then
        return false, "No model has been configured."
    end

    if #userText > MAX_USER_MESSAGE_LEN then
        userText = userText:sub(1, MAX_USER_MESSAGE_LEN) .. "..."
    end

    local convo = getConversation(userId)
    local messages = {}

    if settings.prompt ~= "" then
        table.insert(messages, {
            role = "system",
            content = settings.prompt
        })
    end

    table.insert(messages, {
        role = "system",
        content = buildSystemPrompt(speakerName)
    })

    for _, entry in ipairs(convo) do
        table.insert(messages, {
            role = entry.role,
            content = entry.content
        })
    end

    table.insert(messages, {
        role = "user",
        content = userText
    })

    local ok, result = tryModels(provider, apiKey, messages, model)

    if not ok then
        if not isRetry and isTokenLimitError(result) then
            table.clear(convo)
            notify("Conversation was too long — memory trimmed automatically.", "info")
            return askAI(userId, userText, speakerName, true)
        end

        return false, result
    end

    pushMessage(convo, "user", userText)
    pushMessage(convo, "assistant", result)

    return true, result
end

clearButton.MouseButton1Click:Connect(function()
    table.clear(conversations)
    clearHistory()
    notify("Conversation memory cleared.", "success")
end)

local sending = false

sendButton.MouseButton1Click:Connect(function()
    if sending then
        return
    end

    local text = messageBox.Text

    if text == "" then
        return
    end

    sending = true
    sendButton.Text = "..."

    messageBox.Text = ""

    addMessage("You", text)

    task.spawn(function()
        local ok, result = askAI(player.UserId, text, describeSpeaker(player))

        if ok then
            addMessage("AI", processReply(result))
        else
            addMessage("System", result)
            notify(result, "error")
        end

        sending = false
        sendButton.Text = "Send"
    end)
end)

messageBox.FocusLost:Connect(function(enterPressed)
    if enterPressed and not UserInputService.TouchEnabled then
        sendButton:Activate()
    end
end)

local function openAiWindow()
    aiWindow.Visible = true
    aiWindow.BackgroundTransparency = 1

    local scale = Instance.new("UIScale")
    scale.Scale = 0.94
    scale.Parent = aiWindow

    TweenService:Create(aiWindow, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0
    }):Play()

    TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Scale = 1
    }):Play()
end

local function closeKeyWindow()
    local tween = TweenService:Create(keyWindow, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        BackgroundTransparency = 1
    })

    tween:Play()
    tween.Completed:Connect(function()
        keyWindow.Visible = false
        keyWindow.BackgroundTransparency = 0
    end)
end
        showPage("chat")

enterButton.Activated:Connect(function()
    local enteredKey = tostring(keyBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if enteredKey == "Key" then
        keyBox:ReleaseFocus()
        keyWindow.Visible = false
        aiWindow.Visible = true
        showPage("chat")

        notify("AI companion initialized.", "success")
        addMessage(
            "System",
            "AI Chatbot initialized. Configure your provider in Settings."
        )
    else
        notify("Invalid key.", "error")
    end
end)

local function withinSpeechRange(otherPlayer)
    if settings.range <= 0 then
        return true
    end

    local myChar = player.Character
    local theirChar = otherPlayer.Character

    if not myChar or not theirChar then
        return false
    end

    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
    local theirRoot = theirChar:FindFirstChild("HumanoidRootPart")

    if not myRoot or not theirRoot then
        return false
    end

    return (myRoot.Position - theirRoot.Position).Magnitude <= settings.range
end

local function speakInGameChat(text)
    for i = 1, #text, MAX_CHAT_LEN do
        local chunk = text:sub(i, i + MAX_CHAT_LEN - 1)

        pcall(function()
            if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
                local channel = TextChatService.TextChannels
                    and TextChatService.TextChannels:FindFirstChild("RBXGeneral")

                if channel then
                    channel:SendAsync(chunk)
                end
            else
                player:Chat(chunk)
            end
        end)

        task.wait(0.15)
    end
end

local function handleIncomingChat(fromPlayer, message)
    if not settings.enabled then
        return
    end

    if message == nil or message == "" then
        return
    end

    if not withinSpeechRange(fromPlayer) then
        return
    end

    local now = os.clock()
    local last = lastTriggered[fromPlayer.UserId]

    if last and (now - last) < settings.cooldown then
        return
    end

    lastTriggered[fromPlayer.UserId] = now

    addMessage(fromPlayer.Name, message)

    task.spawn(function()
        local ok, result = askAI(fromPlayer.UserId, message, describeSpeaker(fromPlayer))

        if ok then
            local cleaned = processReply(result)
            addMessage("AI", cleaned)
            speakInGameChat(cleaned)
        else
            addMessage("System", result)
            notify(result, "error")
        end
    end)
end

local function hookPlayer(otherPlayer)
    if otherPlayer == player then
        return
    end

    otherPlayer.Chatted:Connect(function(message)
        handleIncomingChat(otherPlayer, message)
    end)

    otherPlayer.AncestryChanged:Connect(function(_, parent)
        if not parent then
            conversations[otherPlayer.UserId] = nil
            lastTriggered[otherPlayer.UserId] = nil
        end
    end)
end

for _, existingPlayer in ipairs(Players:GetPlayers()) do
    hookPlayer(existingPlayer)
end

Players.PlayerAdded:Connect(hookPlayer)

updateEnabled()
showPage("chat")
