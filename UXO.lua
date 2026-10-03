--[[[
    UXOSUIM STUDIO  ·  UI LIBRARY
    ───────────────────────────
    UI only — no game features or logic.
    · Exposes Library / ThemeManager / SaveManager
    · The studio loader builds its tabs and controls
    · RightShift toggles the menu
    · Key status reads SCRIPT_KEY or SetKeyExpiry / SetKeyType
]]--]

------------------------------------------------------------------
--  Executor compatibility (UI only)
--  Gives the menu a safe place to live. No game hooks here.
------------------------------------------------------------------
local function bootstrapUI()
    local genv = (type(getgenv) == "function" and getgenv()) or _G

    local function resolve(name)
        local value = rawget(_G, name)
        if value == nil and genv ~= _G then value = genv[name] end
        return value
    end

    if type(resolve("hidegui")) ~= "function" then
        local hidden = resolve("gethui")
        local guard = resolve("protect_gui")
        if guard == nil and type(genv.syn) == "table" then guard = genv.syn.protect_gui end

        local function hide(gui)
            if type(guard) == "function" then pcall(guard, gui) end
            if type(hidden) == "function" then
                local ok, container = pcall(hidden)
                if ok and typeof(container) == "Instance" then
                    gui.Parent = container
                    return
                end
            end
            local ok, core = pcall(game.GetService, game, "CoreGui")
            if ok and core then
                local placed = pcall(function() gui.Parent = core end)
                if placed then return end
            end
            gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        end

        pcall(function() genv.hidegui = hide end)
        pcall(function() _G.hidegui = hide end)
    end
end

bootstrapUI()

local Library = (function()
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")
    local HttpService = game:GetService("HttpService")
    local LocalPlayer = Players.LocalPlayer

    local Theme = {
        Accent = Color3.fromRGB(174, 96, 255),
        AccentSoft = Color3.fromRGB(103, 48, 188),
        Shell = Color3.fromRGB(7, 6, 11),
        ShellTop = Color3.fromRGB(16, 11, 23),
        Panel = Color3.fromRGB(14, 11, 20),
        Raised = Color3.fromRGB(25, 19, 35),
        Sunken = Color3.fromRGB(9, 7, 13),
        Line = Color3.fromRGB(67, 50, 92),
        LineSoft = Color3.fromRGB(35, 27, 48),
        Text = Color3.fromRGB(248, 245, 252),
        SubText = Color3.fromRGB(184, 172, 204),
        Faint = Color3.fromRGB(116, 105, 137),
        Success = Color3.fromRGB(69, 224, 142),
        Warning = Color3.fromRGB(255, 197, 101),
        Danger = Color3.fromRGB(255, 105, 125),
    }

    local PILL = UDim.new(1, 0)
    local EASE = TweenInfo.new(0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

    local Lib = {
        Version = "3.0.0",
        Build = "Uxosuim-Studio-Enhanced",
        Options = {},
        Toggles = {},
        Controls = {},
        Theme = Theme,
        CornerRadius = 12,
        ForceCheckbox = false,
        ShowToggleFrameInKeybinds = true,
        NotifySide = "Right",
        Unloaded = false,
        ToggleKeybind = nil,
        DefaultToggleKey = "RightShift",
        AnimationsEnabled = true,
        ReducedMotion = false,
        NotifyLimit = 6,
        CallbackErrors = {},
    }

    local conns = {}
    local activeTweens = setmetatable({}, { __mode = "k" })
    local panels = {}
    local pickers = {}
    local pages = {}
    local unloadCallbacks = {}
    local activeNotifications = {}
    local configFolder = "UxosuimStudio"

    local function new(class, props, parent)
        local inst = Instance.new(class)
        for key, value in pairs(props) do
            inst[key] = value
        end
        if parent then
            inst.Parent = parent
        end
        return inst
    end

    local function round(inst, radius, tracked)
        local corner = new("UICorner", { CornerRadius = radius }, inst)
        if tracked then
            table.insert(panels, corner)
        end
        return corner
    end

    local function outline(inst, color, thickness, transparency)
        return new("UIStroke", {
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            LineJoinMode = Enum.LineJoinMode.Round,
            Color = color or Theme.Line,
            Thickness = thickness or 1,
            Transparency = transparency or 0,
        }, inst)
    end

    local function pad(inst, left, right, top, bottom)
        return new("UIPadding", {
            PaddingLeft = UDim.new(0, left or 0),
            PaddingRight = UDim.new(0, right or 0),
            PaddingTop = UDim.new(0, top or 0),
            PaddingBottom = UDim.new(0, bottom or 0),
        }, inst)
    end

    local function stack(inst, gap, dir)
        return new("UIListLayout", {
            FillDirection = dir or Enum.FillDirection.Vertical,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, gap or 0),
        }, inst)
    end

    local function glide(inst, props, speed)
        if not inst or not inst.Parent then return nil end
        local previous = activeTweens[inst]
        if previous then previous:Cancel() activeTweens[inst] = nil end
        if not Lib.AnimationsEnabled or Lib.ReducedMotion or speed == 0 then
            for key, value in pairs(props) do inst[key] = value end
            return nil
        end
        local info = speed and TweenInfo.new(speed, Enum.EasingStyle.Quart, Enum.EasingDirection.Out) or EASE
        local anim = TweenService:Create(inst, info, props)
        activeTweens[inst] = anim
        anim.Completed:Once(function()
            if activeTweens[inst] == anim then activeTweens[inst] = nil end
        end)
        anim:Play()
        return anim
    end

    local function bind(signal, fn)
        local link = signal:Connect(fn)
        table.insert(conns, link)
        return link
    end

    local function runCallback(fn, ...)
        if type(fn) ~= "function" then return false end
        local args = table.pack(...)
        task.spawn(function()
            local ok, err = pcall(fn, table.unpack(args, 1, args.n))
            if not ok then
                local record = { Message = tostring(err), Time = os.time() }
                table.insert(Lib.CallbackErrors, record)
                while #Lib.CallbackErrors > 25 do table.remove(Lib.CallbackErrors, 1) end
                if type(Lib.OnCallbackError) == "function" then pcall(Lib.OnCallbackError, record) end
            end
        end)
        return true
    end

    local function tag()
        return string.char(math.random(97, 122), math.random(97, 122), math.random(97, 122), math.random(97, 122)) .. tostring(math.random(100000, 999999))
    end

    local Root = new("ScreenGui", {
        Name = tag(),
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        AutoLocalize = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 9999,
    })

    do
        local placed = false
        if type(hidegui) == "function" then
            placed = pcall(hidegui, Root)
        end
        if not placed or not Root.Parent then
            Root.Parent = LocalPlayer:WaitForChild("PlayerGui")
        end
        pcall(function()
            UserInputService.MouseIconEnabled = true
        end)
    end

    local NotifyHolder = new("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -18, 0, 18),
        Size = UDim2.fromOffset(280, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex = 180,
    }, Root)
    stack(NotifyHolder, 8)

    local TipCard = new("Frame", {
        BackgroundColor3 = Theme.Raised,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.XY,
        Size = UDim2.fromOffset(0, 0),
        Visible = false,
        ZIndex = 190,
    }, Root)
    round(TipCard, UDim.new(0, 8))
    outline(TipCard, Theme.Line, 1)
    pad(TipCard, 10, 10, 7, 7)

    local TipText = new("TextLabel", {
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.XY,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "",
        ZIndex = 191,
    }, TipCard)

    local function pointer()
        return UserInputService:GetMouseLocation()
    end

    local function attachTip(frame, text)
        if not text or text == "" then return end
        local function moveTip()
            local at, viewport = pointer(), Root.AbsoluteSize
            local x = math.min(at.X + 16, viewport.X - TipCard.AbsoluteSize.X - 8)
            local y = math.min(at.Y + 18, viewport.Y - TipCard.AbsoluteSize.Y - 8)
            TipCard.Position = UDim2.fromOffset(math.max(8, x), math.max(8, y))
        end
        bind(frame.MouseEnter, function()
            TipText.Text = text
            moveTip()
            TipCard.Visible = true
        end)
        bind(frame.MouseMoved, function()
            if TipCard.Visible then moveTip() end
        end)
        bind(frame.MouseLeave, function()
            TipCard.Visible = false
        end)
    end

    Lib.Root = Root
    Lib.ScreenGui = Root

    function Lib:Notify(payload, seconds)
        local text, title, accent, closable = payload, "", Theme.Accent, true
        if type(payload) == "table" then
            title = tostring(payload.Title or "")
            text = payload.Description or payload.Text or (title ~= "" and title) or ""
            if payload.Description or payload.Text then title = tostring(payload.Title or "") else title = "" end
            seconds = seconds ~= nil and seconds or payload.Time
            closable = payload.Closable ~= false
            if typeof(payload.Color) == "Color3" then
                accent = payload.Color
            else
                local kind = tostring(payload.Type or ""):lower()
                if kind == "success" then accent = Theme.Success end
                if kind == "warning" then accent = Theme.Warning end
                if kind == "error" or kind == "danger" then accent = Theme.Danger end
            end
        end
        text = tostring(text or "")
        local duration = math.max(0, tonumber(seconds) or 4)

        local card = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Raised,
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            ZIndex = 181,
        }, NotifyHolder)
        round(card, UDim.new(0, 10))
        local edge = outline(card, accent, 1, 1)
        pad(card, 16, closable and 30 or 12, 10, 12)
        local rail = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, -8, 0.5, 0),
            Size = UDim2.new(0, 3, 1, -12),
            BackgroundColor3 = accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 182,
        }, card)
        round(rail, PILL)

        local content = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            ZIndex = 182,
        }, card)
        stack(content, title ~= "" and 3 or 0)
        local titleLabel
        if title ~= "" then
            titleLabel = new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 15),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = accent,
                TextTransparency = 1,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = title,
                LayoutOrder = 1,
                ZIndex = 183,
            }, content)
        end
        local body = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextColor3 = Theme.Text,
            TextTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            Text = text,
            LayoutOrder = 2,
            ZIndex = 182,
        }, content)
        local progress = new("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, -8, 1, 8),
            Size = UDim2.new(1, 16, 0, 2),
            BackgroundColor3 = accent,
            BackgroundTransparency = duration > 0 and 0.15 or 1,
            BorderSizePixel = 0,
            ZIndex = 183,
        }, card)
        round(progress, PILL)

        local closed = false
        local function removeReference()
            local at = table.find(activeNotifications, card)
            if at then table.remove(activeNotifications, at) end
        end
        local function dismiss(instant)
            if closed then return end
            closed = true
            removeReference()
            if instant or Lib.ReducedMotion or not Lib.AnimationsEnabled then
                if card.Parent then card:Destroy() end
                return
            end
            glide(card, { BackgroundTransparency = 1 }, 0.14)
            glide(edge, { Transparency = 1 }, 0.14)
            glide(rail, { BackgroundTransparency = 1 }, 0.14)
            glide(body, { TextTransparency = 1 }, 0.14)
            if titleLabel then glide(titleLabel, { TextTransparency = 1 }, 0.14) end
            task.delay(0.15, function() if card.Parent then card:Destroy() end end)
        end

        if closable then
            local close = new("TextButton", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 20, 0, -4),
                Size = UDim2.fromOffset(20, 20),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 10,
                TextColor3 = Theme.Faint,
                Text = "X",
                AutoButtonColor = false,
                ZIndex = 184,
            }, card)
            bind(close.MouseEnter, function() glide(close, { TextColor3 = Theme.Danger }, 0.1) end)
            bind(close.MouseLeave, function() glide(close, { TextColor3 = Theme.Faint }, 0.1) end)
            bind(close.Activated, dismiss)
        end

        table.insert(activeNotifications, card)
        while #activeNotifications > math.max(1, tonumber(Lib.NotifyLimit) or 6) do
            local oldest = table.remove(activeNotifications, 1)
            if oldest and oldest.Parent then oldest:Destroy() end
        end

        glide(card, { BackgroundTransparency = 0 })
        glide(edge, { Transparency = 0 })
        glide(rail, { BackgroundTransparency = 0 })
        glide(body, { TextTransparency = 0 })
        if titleLabel then glide(titleLabel, { TextTransparency = 0 }) end
        if duration > 0 then
            glide(progress, { Size = UDim2.new(0, 0, 0, 2) }, duration)
            task.delay(duration, dismiss)
        end

        local notification = { Instance = card }
        function notification:Close() dismiss() end
        function notification:SetText(value) body.Text = tostring(value or "") return self end
        function notification:SetTitle(value)
            if titleLabel then titleLabel.Text = tostring(value or "") end
            return self
        end
        return notification
    end

    function Lib:SetNotifySide(side)
        side = tostring(side or "Right"):lower() == "left" and "Left" or "Right"
        Lib.NotifySide = side
        if side == "Left" then
            NotifyHolder.AnchorPoint = Vector2.new(0, 0)
            NotifyHolder.Position = UDim2.new(0, 18, 0, 18)
        else
            NotifyHolder.AnchorPoint = Vector2.new(1, 0)
            NotifyHolder.Position = UDim2.new(1, -18, 0, 18)
        end
        return self
    end

    function Lib:SetNotifyLimit(value)
        self.NotifyLimit = math.clamp(math.floor(tonumber(value) or 6), 1, 20)
        while #activeNotifications > self.NotifyLimit do
            local card = table.remove(activeNotifications, 1)
            if card and card.Parent then card:Destroy() end
        end
        return self
    end

    function Lib:ClearNotifications()
        for _, card in ipairs(activeNotifications) do
            if card and card.Parent then card:Destroy() end
        end
        table.clear(activeNotifications)
        return self
    end

    local function keepOnScreen(target)
        local viewport = Root.AbsoluteSize
        local position, size = target.AbsolutePosition, target.AbsoluteSize
        if viewport.X <= 0 or viewport.Y <= 0 then return end
        local dx = math.clamp(position.X, 0, math.max(0, viewport.X - size.X)) - position.X
        local dy = math.clamp(position.Y, 0, math.max(0, viewport.Y - size.Y)) - position.Y
        if dx ~= 0 or dy ~= 0 then
            target.Position = target.Position + UDim2.fromOffset(dx, dy)
        end
    end

    local function dragify(handle, target)
        local holding, origin, base = false, nil, nil
        bind(handle.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                holding = true
                origin = input.Position
                base = target.Position
            end
        end)
        bind(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                holding = false
            end
        end)
        bind(UserInputService.InputChanged, function(input)
            if not holding then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local shift = input.Position - origin
                target.Position = UDim2.new(base.X.Scale, base.X.Offset + shift.X, base.Y.Scale, base.Y.Offset + shift.Y)
                keepOnScreen(target)
            end
        end)
    end


    -- ===== control constructors (API used by the Uxosuim Studio script) =====
    local listeningPicker, openDropdownRef, openPaletteRef = nil, nil, nil
    local activeSlider, captureConnection = nil, nil

    local function inputName(input)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            return input.KeyCode.Name
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2
            or input.UserInputType == Enum.UserInputType.MouseButton3 then
            return input.UserInputType.Name
        end
        return nil
    end

    local function normalizeBind(value)
        if typeof(value) == "EnumItem" then return value.Name end
        local key = tostring(value or "")
        key = key:match("^Enum%.KeyCode%.(.+)$") or key:match("^Enum%.UserInputType%.(.+)$") or key
        local aliases = { MB1 = "MouseButton1", MB2 = "MouseButton2", MB3 = "MouseButton3" }
        return aliases[key:upper()] or key
    end

    local function beginKeyCapture(picker)
        if captureConnection then
            captureConnection:Disconnect()
            captureConnection = nil
        end
        if listeningPicker and listeningPicker ~= picker then
            listeningPicker.Chip.Text = listeningPicker.Value ~= "" and listeningPicker.Value or "NONE"
            glide(listeningPicker.Chip, { TextColor3 = Theme.SubText, BackgroundColor3 = Theme.Sunken }, 0.12)
            glide(listeningPicker.Edge, { Color = Theme.Line }, 0.12)
        end

        listeningPicker = picker
        picker.Chip.Text = "..."
        glide(picker.Chip, { TextColor3 = Theme.Accent, BackgroundColor3 = Theme.Raised }, 0.12)
        glide(picker.Edge, { Color = Theme.Accent }, 0.12)

        captureConnection = UserInputService.InputBegan:Connect(function(input)
            local key = inputName(input)
            if not key or listeningPicker ~= picker then return end

            listeningPicker = nil
            captureConnection:Disconnect()
            captureConnection = nil

            if key == "Backspace" then
                picker:SetValue("", true)
            elseif key ~= "Escape" then
                picker:SetValue(key, true)
            end
            picker.Chip.Text = picker.Value ~= "" and picker.Value or "NONE"
            glide(picker.Chip, { TextColor3 = Theme.SubText, BackgroundColor3 = Theme.Sunken }, 0.12)
            glide(picker.Edge, { Color = Theme.Line }, 0.12)
        end)
    end

    -- invisible full-screen button that eats a click to close popups
    local sink = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        ZIndex = 90,
        Visible = false,
        AutoButtonColor = false,
    }, Root)

    local function closePopups()
        sink.Visible = false
        if openDropdownRef then openDropdownRef.close() end
        if openPaletteRef then openPaletteRef.close() end
    end
    bind(sink.Activated, closePopups)

    local PALETTE = {
        Color3.fromRGB(255, 255, 255), Color3.fromRGB(178, 178, 190), Color3.fromRGB(41, 41, 51), Color3.fromRGB(0, 0, 0),
        Color3.fromRGB(255, 82, 82), Color3.fromRGB(255, 140, 66), Color3.fromRGB(255, 214, 79), Color3.fromRGB(140, 235, 92),
        Theme.Success, Color3.fromRGB(72, 208, 208), Color3.fromRGB(86, 156, 255), Color3.fromRGB(124, 92, 255),
        Color3.fromRGB(178, 107, 255), Color3.fromRGB(224, 107, 216), Color3.fromRGB(255, 122, 176), Color3.fromRGB(178, 122, 92),
    }

    local function openPalette(Picker)
        if openPaletteRef then openPaletteRef.close() end
        local viewport = Root.AbsoluteSize
        local x = math.clamp(Picker.Chip.AbsolutePosition.X - 100, 8, math.max(8, viewport.X - 216))
        local y = math.clamp(Picker.Chip.AbsolutePosition.Y + 22, 8, math.max(8, viewport.Y - 82))
        local panel = new("Frame", {
            Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(208, 74),
            BackgroundColor3 = Theme.Raised,
            BorderSizePixel = 0,
            ZIndex = 95,
        }, Root)
        round(panel, UDim.new(0, 8), true)
        outline(panel, Theme.Line, 1)
        local grid = new("Frame", {
            Position = UDim2.fromOffset(6, 6),
            Size = UDim2.new(1, -12, 1, -12),
            BackgroundTransparency = 1,
        }, panel)
        new("UIGridLayout", {
            CellSize = UDim2.fromOffset(44, 26),
            CellPadding = UDim2.fromOffset(4, 4),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, grid)
        for i, color in ipairs(PALETTE) do
            local swatch = new("TextButton", {
                Size = UDim2.fromOffset(44, 26),
                BackgroundColor3 = color,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = i,
                ZIndex = 96,
            }, grid)
            round(swatch, UDim.new(0, 6))
            outline(swatch, Theme.Line, 1)
            bind(swatch.Activated, function()
                Picker:SetValue(color)
                closePopups()
            end)
        end
        sink.Visible = true
        openPaletteRef = {
            close = function()
                panel:Destroy()
                if openPaletteRef and openPaletteRef.panel == panel then openPaletteRef = nil end
                if not openDropdownRef then sink.Visible = false end
            end,
            panel = panel,
        }
    end

    local function makeKeyPicker(host, index, opts, parent)
        opts = opts or {}
        local defaultKey = normalizeBind(opts.Default)
        local chip = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(58, 20),
            BackgroundColor3 = Theme.Sunken,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 9,
            TextColor3 = Theme.SubText,
            Text = defaultKey ~= "" and defaultKey or "NONE",
            AutoButtonColor = false,
        }, parent)
        round(chip, PILL)
        local chipEdge = outline(chip, Theme.Line, 1)

        local Picker = {
            Type = "KeyPicker",
            Index = index,
            Host = host,
            Chip = chip,
            Edge = chipEdge,
            Value = defaultKey,
            Default = defaultKey,
            Mode = table.find({ "Press", "Hold", "Toggle", "Always" }, opts.Mode) and opts.Mode or "Press",
            SyncToggleState = opts.SyncToggleState and true or false,
            Text = opts.Text or "",
            NoUI = opts.NoUI and true or false,
            Active = false,
            KeyDown = false,
            Disabled = false,
            NoSave = opts.NoSave and true or false,
            Callbacks = {},
            ChangedCallbacks = {},
        }
        if type(opts.Callback) == "function" then table.insert(Picker.Callbacks, opts.Callback) end
        if type(opts.ChangedCallback) == "function" then table.insert(Picker.ChangedCallbacks, opts.ChangedCallback) end

        local function paintChip()
            chip.Text = Picker.Value ~= "" and Picker.Value or "NONE"
            chipEdge.Color = Theme.Line
            chip.TextColor3 = Theme.SubText
        end

        function Picker:SetValue(key, force)
            key = normalizeBind(key)
            if key == self.Value and not force then return end
            self.Value = key
            paintChip()
            for _, fn in ipairs(self.ChangedCallbacks) do runCallback(fn, key) end
        end

        function Picker:GetState()
            if self.Mode == "Toggle" then return self.Active end
            return self.KeyDown
        end

        function Picker:GetValue()
            return self.Value
        end

        function Picker:Reset()
            self:SetValue(self.Default)
            return self
        end

        function Picker:SetMode(mode)
            mode = tostring(mode or "Press")
            if table.find({ "Press", "Hold", "Toggle", "Always" }, mode) then self.Mode = mode end
            self.Active, self.KeyDown = false, false
            return self
        end

        function Picker:SetVisible(state)
            chip.Visible = state and true or false
            return self
        end

        function Picker:IsDisabled()
            return self.Disabled
        end

        function Picker:IsVisible()
            return chip.Visible
        end

        function Picker:OnClick(fn)
            if type(fn) == "function" then table.insert(self.Callbacks, fn) end
            return self
        end

        function Picker:OnChanged(fn)
            if type(fn) == "function" then
                table.insert(self.ChangedCallbacks, fn)
                runCallback(fn, self.Value)
            end
            return self
        end

        function Picker:SetDisabled(state)
            self.Disabled = state and true or false
            glide(chip, { BackgroundTransparency = self.Disabled and 0.4 or 0, TextTransparency = self.Disabled and 0.5 or 0 }, 0.14)
            glide(chipEdge, { Transparency = self.Disabled and 0.55 or 0 }, 0.14)
            return self
        end

        bind(chip.MouseEnter, function()
            if not Picker.Disabled and listeningPicker ~= Picker then
                glide(chip, { BackgroundColor3 = Theme.Raised })
                chipEdge.Color = Theme.Accent
            end
        end)
        bind(chip.MouseLeave, function()
            if listeningPicker ~= Picker then
                glide(chip, { BackgroundColor3 = Theme.Sunken })
                chipEdge.Color = Theme.Line
            end
        end)
        bind(chip.Activated, function()
            if Lib.Unloaded or Picker.Disabled then return end
            closePopups()
            chipEdge.Color = Theme.Accent
            beginKeyCapture(Picker)
        end)

        if opts.Disabled then Picker:SetDisabled(true) end
        table.insert(pickers, Picker)
        Lib.Options[index] = Picker
        Lib.Controls[index] = Picker
        if opts.ToggleMenu or tostring(index):lower() == "menukeybind" then
            Lib.ToggleKeybind = Picker
        end
        if host and host.Type == "Toggle" then host.Picker = Picker end
        return Picker
    end

    local function makeColorPicker(host, index, opts, parent)
        opts = opts or {}
        local chip = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(44, 18),
            BackgroundColor3 = opts.Default or Theme.Accent,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
        }, parent)
        round(chip, UDim.new(0, 6))
        local chipEdge = outline(chip, Theme.Line, 1)
        local chipScale = new("UIScale", { Scale = 1 }, chip)

        local Picker = {
            Type = "ColorPicker",
            Index = index,
            Chip = chip,
            Value = opts.Default or Theme.Accent,
            Default = opts.Default or Theme.Accent,
            Disabled = false,
            NoSave = opts.NoSave and true or false,
            Callbacks = {},
        }
        if type(opts.Callback) == "function" then table.insert(Picker.Callbacks, opts.Callback) end

        function Picker:SetValue(color)
            if typeof(color) ~= "Color3" then return self end
            if color == self.Value then return self end
            self.Value = color
            chip.BackgroundColor3 = color
            for _, fn in ipairs(self.Callbacks) do runCallback(fn, color) end
            return self
        end

        function Picker:GetValue()
            return self.Value
        end

        function Picker:Reset()
            return self:SetValue(self.Default)
        end

        function Picker:SetVisible(state)
            chip.Visible = state and true or false
            return self
        end

        function Picker:IsDisabled()
            return self.Disabled
        end

        function Picker:IsVisible()
            return chip.Visible
        end

        function Picker:OnChanged(fn)
            if type(fn) == "function" then
                table.insert(self.Callbacks, fn)
                runCallback(fn, self.Value)
            end
            return self
        end

        function Picker:SetDisabled(state)
            self.Disabled = state and true or false
            glide(chip, { BackgroundTransparency = self.Disabled and 0.45 or 0 }, 0.14)
            glide(chipEdge, { Transparency = self.Disabled and 0.55 or 0 }, 0.14)
            return self
        end

        bind(chip.MouseEnter, function()
            if Picker.Disabled then return end
            glide(chipEdge, { Color = Theme.Accent }, 0.12)
            glide(chipScale, { Scale = 1.06 }, 0.12)
        end)
        bind(chip.MouseLeave, function()
            glide(chipEdge, { Color = Theme.Line }, 0.12)
            glide(chipScale, { Scale = 1 }, 0.12)
        end)
        bind(chip.Activated, function()
            if Lib.Unloaded or Picker.Disabled then return end
            openPalette(Picker)
        end)
        if opts.Disabled then Picker:SetDisabled(true) end
        Lib.Options[index] = Picker
        Lib.Controls[index] = Picker
        return Picker
    end

    local function makeGroup(holder)
        local Group = { Holder = holder, Order = 0 }

        function Group:SetVisible(state)
            holder.Visible = state and true or false
            return self
        end

        function Group:IsVisible()
            return holder.Visible
        end

        function Group:GetInstance()
            return holder
        end

        local function nextOrder()
            Group.Order = Group.Order + 1
            return Group.Order
        end

        function Group:AddLabel(text)
            local box = new("Frame", {
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundTransparency = 1,
                LayoutOrder = nextOrder(),
            }, holder)
            new("TextLabel", {
                Size = UDim2.new(1, -72, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = text or "",
            }, box)
            local Label = { Type = "Label", Box = box }
            function Label:SetText(value)
                local inner = box:FindFirstChildOfClass("TextLabel")
                if inner then inner.Text = tostring(value or "") end
                return self
            end
            function Label:SetVisible(state)
                box.Visible = state and true or false
                return self
            end
            function Label:SetColor(color)
                local inner = box:FindFirstChildOfClass("TextLabel")
                if inner and typeof(color) == "Color3" then inner.TextColor3 = color end
                return self
            end
            function Label:AddKeyPicker(index, opts)
                return makeKeyPicker(Label, index, opts, box)
            end
            function Label:AddColorPicker(index, opts)
                return makeColorPicker(Label, index, opts, box)
            end
            return Label
        end

        function Group:AddParagraph(title, content)
            local box = new("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Sunken,
                BackgroundTransparency = 0.3,
                BorderSizePixel = 0,
                LayoutOrder = nextOrder(),
            }, holder)
            round(box, UDim.new(0, 8))
            outline(box, Theme.LineSoft, 1)
            pad(box, 10, 10, 8, 8)
            local layout = stack(box, 4)
            layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
            local heading = new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 15),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = tostring(title or ""),
                LayoutOrder = 1,
            }, box)
            local body = new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 10,
                TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                TextWrapped = true,
                Text = tostring(content or ""),
                LayoutOrder = 2,
            }, box)
            local Paragraph = { Type = "Paragraph", Instance = box }
            function Paragraph:SetTitle(value) heading.Text = tostring(value or "") return self end
            function Paragraph:SetContent(value) body.Text = tostring(value or "") return self end
            function Paragraph:SetVisible(state) box.Visible = state and true or false return self end
            function Paragraph:IsVisible() return box.Visible end
            function Paragraph:SetColor(color)
                if typeof(color) == "Color3" then body.TextColor3 = color end
                return self
            end
            return Paragraph
        end

        function Group:AddDivider()
            local box = new("Frame", {
                Size = UDim2.new(1, 0, 0, 9),
                BackgroundTransparency = 1,
                LayoutOrder = nextOrder(),
            }, holder)
            local line = new("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.fromScale(0, 0.5),
                Size = UDim2.new(1, 0, 0, 1),
                BackgroundColor3 = Theme.LineSoft,
                BorderSizePixel = 0,
            }, box)
            local Divider = { Type = "Divider", Instance = box }
            function Divider:SetVisible(state) box.Visible = state and true or false return self end
            function Divider:SetColor(color) if typeof(color) == "Color3" then line.BackgroundColor3 = color end return self end
            return Divider
        end

        function Group:AddSpacer(height)
            local spacer = new("Frame", {
                Size = UDim2.new(1, 0, 0, math.max(0, tonumber(height) or 6)),
                BackgroundTransparency = 1,
                LayoutOrder = nextOrder(),
            }, holder)
            return spacer
        end

        function Group:AddToggle(index, opts)
            opts = opts or {}
            local row = new("Frame", {
                Size = UDim2.new(1, 0, 0, 32),
                BackgroundTransparency = 1,
                LayoutOrder = nextOrder(),
            }, holder)

            local labelArea = new("TextButton", {
                Size = UDim2.new(1, -56, 1, 0),
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
            }, row)
            local label = new("TextLabel", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = opts.Text or "",
            }, labelArea)

            local track = new("Frame", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -6, 0.5, 0),
                Size = UDim2.fromOffset(42, 22),
                BackgroundColor3 = Theme.Sunken,
                BorderSizePixel = 0,
            }, row)
            round(track, PILL)
            local trackEdge = outline(track, Theme.Line, 1)
            local trackScale = new("UIScale", { Scale = 1 }, track)
            local knob = new("Frame", {
                Position = UDim2.fromOffset(3, 3),
                Size = UDim2.fromOffset(16, 16),
                BackgroundColor3 = Theme.SubText,
                BorderSizePixel = 0,
            }, track)
            round(knob, PILL)

            local Toggle = {
                Type = "Toggle",
                Index = index,
                Value = opts.Default and true or false,
                Default = opts.Default and true or false,
                Text = tostring(opts.Text or ""),
                Row = row,
                LabelArea = labelArea,
                Disabled = false,
                NoSave = opts.NoSave and true or false,
                Callbacks = {},
            }
            if type(opts.Callback) == "function" then table.insert(Toggle.Callbacks, opts.Callback) end

            local function paint(instant)
                local trackProps = {
                    BackgroundColor3 = Toggle.Value and Theme.AccentSoft or Theme.Sunken,
                }
                local edgeProps = { Color = Toggle.Value and Theme.Accent or Theme.Line }
                local knobProps = {
                    BackgroundColor3 = Toggle.Value and Theme.Text or Theme.SubText,
                    Position = Toggle.Value and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3),
                }
                local labelProps = { TextColor3 = Toggle.Value and Theme.Text or Theme.SubText }
                if instant then
                    for key, value in pairs(trackProps) do track[key] = value end
                    for key, value in pairs(edgeProps) do trackEdge[key] = value end
                    for key, value in pairs(knobProps) do knob[key] = value end
                    for key, value in pairs(labelProps) do label[key] = value end
                else
                    glide(track, trackProps, 0.16)
                    glide(trackEdge, edgeProps, 0.16)
                    glide(knob, knobProps, 0.18)
                    glide(label, labelProps, 0.14)
                end
            end

            function Toggle:SetValue(value)
                value = value and true or false
                if value == self.Value then return self end
                self.Value = value
                paint()
                if self.Picker and self.Picker.SyncToggleState then
                    self.Picker.Active = value
                end
                for _, fn in ipairs(self.Callbacks) do runCallback(fn, value) end
                return self
            end

            function Toggle:GetValue()
                return self.Value
            end

            function Toggle:Reset()
                self:SetValue(self.Default)
                return self
            end

            function Toggle:SetText(value)
                self.Text = tostring(value or "")
                label.Text = self.Text
                return self
            end

            function Toggle:IsDisabled()
                return self.Disabled
            end

            function Toggle:IsVisible()
                return row.Visible
            end

            function Toggle:OnChanged(fn)
                if type(fn) == "function" then
                    table.insert(self.Callbacks, fn)
                    runCallback(fn, self.Value)
                end
                return self
            end

            function Toggle:SetDisabled(state)
                self.Disabled = state and true or false
                glide(label, { TextTransparency = self.Disabled and 0.45 or 0 }, 0.14)
                glide(track, { BackgroundTransparency = self.Disabled and 0.35 or 0 }, 0.14)
                glide(knob, { BackgroundTransparency = self.Disabled and 0.35 or 0 }, 0.14)
                glide(trackEdge, { Transparency = self.Disabled and 0.55 or 0 }, 0.14)
                return self
            end

            function Toggle:SetVisible(state)
                row.Visible = state and true or false
                return self
            end

            function Toggle:AddKeyPicker(pickerIndex, pickerOpts)
                self.LabelArea.Size = UDim2.new(1, -122, 1, 0)
                local picker = makeKeyPicker(self, pickerIndex, pickerOpts, row)
                picker.Chip.Position = UDim2.new(1, -56, 0.5, 0)
                return picker
            end

            bind(labelArea.Activated, function()
                if not Lib.Unloaded and not Toggle.Disabled then Toggle:SetValue(not Toggle.Value) end
            end)
            bind(track.InputBegan, function(input)
                if (input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch) and not Lib.Unloaded and not Toggle.Disabled then
                    Toggle:SetValue(not Toggle.Value)
                end
            end)
            bind(row.MouseEnter, function()
                if not Toggle.Disabled then glide(trackScale, { Scale = 1.05 }, 0.12) end
            end)
            bind(row.MouseLeave, function()
                glide(trackScale, { Scale = 1 }, 0.12)
            end)

            paint(true)
            if opts.Disabled then Toggle:SetDisabled(true) end
            attachTip(row, opts.Tooltip)
            Lib.Toggles[index] = Toggle
            Lib.Controls[index] = Toggle
            return Toggle
        end

        function Group:AddSlider(index, opts)
            opts = opts or {}
            local min = tonumber(opts.Min) or 0
            local max = tonumber(opts.Max) or 100
            if max < min then min, max = max, min end
            local rounding = math.clamp(tonumber(opts.Rounding) or 0, 0, 6)
            local prefix, suffix = tostring(opts.Prefix or ""), tostring(opts.Suffix or "")
            local row = new("Frame", {
                Size = UDim2.new(1, 0, 0, 38),
                BackgroundTransparency = 1,
                LayoutOrder = nextOrder(),
            }, holder)

            local sliderLabel = new("TextLabel", {
                Size = UDim2.new(1, -56, 0, 16),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = opts.Text or "",
            }, row)
            local valueLabel = new("TextLabel", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.fromOffset(50, 16),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                TextColor3 = Theme.Accent,
                TextXAlignment = Enum.TextXAlignment.Right,
                Text = "",
            }, row)

            local track = new("Frame", {
                Position = UDim2.fromOffset(0, 22),
                Size = UDim2.new(1, 0, 0, 8),
                BackgroundColor3 = Theme.Sunken,
                BorderSizePixel = 0,
            }, row)
            round(track, PILL)
            outline(track, Theme.LineSoft, 1)
            local fill = new("Frame", {
                Size = UDim2.new(0, 0, 1, 0),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
            }, track)
            round(fill, PILL)
            new("UIGradient", {
                Color = ColorSequence.new(Theme.AccentSoft, Theme.Accent),
            }, fill)
            local knob = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.fromOffset(12, 12),
                BackgroundColor3 = Theme.Text,
                BorderSizePixel = 0,
                ZIndex = 2,
            }, track)
            round(knob, PILL)
            outline(knob, Theme.Accent, 1)
            local trackScale = new("UIScale", { Scale = 1 }, track)

            local Slider = {
                Type = "Slider",
                Index = index,
                Min = min,
                Max = max,
                Rounding = rounding,
                Value = nil,
                Default = tonumber(opts.Default) or min,
                Text = tostring(opts.Text or ""),
                Row = row,
                Disabled = false,
                NoSave = opts.NoSave and true or false,
                Callbacks = {},
            }
            if type(opts.Callback) == "function" then table.insert(Slider.Callbacks, opts.Callback) end

            local initialized = false
            local function paint()
                local frac = math.clamp((Slider.Value - min) / math.max(0.0001, max - min), 0, 1)
                local fillSize = UDim2.new(frac, 0, 1, 0)
                local knobPosition = UDim2.new(frac, 0, 0.5, 0)
                if initialized then
                    glide(fill, { Size = fillSize }, 0.08)
                    glide(knob, { Position = knobPosition }, 0.08)
                    glide(valueLabel, { TextColor3 = Theme.Text }, 0.08)
                else
                    fill.Size = fillSize
                    knob.Position = knobPosition
                    initialized = true
                end
                valueLabel.Text = prefix .. string.format("%." .. rounding .. "f", Slider.Value) .. suffix
            end

            function Slider:SetValue(value)
                value = tonumber(value) or min
                value = math.clamp(value, min, max)
                if rounding > 0 then
                    value = tonumber(string.format("%." .. rounding .. "f", value))
                end
                if value == self.Value then return self end
                self.Value = value
                paint()
                for _, fn in ipairs(self.Callbacks) do runCallback(fn, value) end
                return self
            end

            function Slider:Seek(x)
                local frac = (x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X)
                self:SetValue(min + (max - min) * math.clamp(frac, 0, 1))
            end

            function Slider:GetValue()
                return self.Value
            end

            function Slider:Reset()
                self:SetValue(self.Default)
                return self
            end

            function Slider:SetText(value)
                self.Text = tostring(value or "")
                sliderLabel.Text = self.Text
                return self
            end

            function Slider:SetRange(newMin, newMax)
                newMin, newMax = tonumber(newMin) or self.Min, tonumber(newMax) or self.Max
                if newMax < newMin then newMin, newMax = newMax, newMin end
                self.Min, self.Max, min, max = newMin, newMax, newMin, newMax
                self:SetValue(math.clamp(self.Value, min, max))
                paint()
                return self
            end

            function Slider:IsDisabled()
                return self.Disabled
            end

            function Slider:IsVisible()
                return row.Visible
            end

            function Slider:OnChanged(fn)
                if type(fn) == "function" then
                    table.insert(self.Callbacks, fn)
                    runCallback(fn, self.Value)
                end
                return self
            end

            function Slider:SetDisabled(state)
                self.Disabled = state and true or false
                if self.Disabled and activeSlider == self then activeSlider = nil end
                local transparency = self.Disabled and 0.5 or 0
                glide(sliderLabel, { TextTransparency = transparency }, 0.14)
                glide(valueLabel, { TextTransparency = transparency }, 0.14)
                glide(track, { BackgroundTransparency = self.Disabled and 0.4 or 0 }, 0.14)
                glide(fill, { BackgroundTransparency = self.Disabled and 0.45 or 0 }, 0.14)
                glide(knob, { BackgroundTransparency = self.Disabled and 0.45 or 0 }, 0.14)
                return self
            end

            function Slider:SetVisible(state)
                row.Visible = state and true or false
                return self
            end

            bind(track.InputBegan, function(input)
                if not Slider.Disabled and (input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch) then
                    activeSlider = Slider
                    Slider:Seek(input.Position.X)
                end
            end)
            bind(row.MouseEnter, function()
                if not Slider.Disabled then
                    glide(trackScale, { Scale = 1.025 }, 0.12)
                    glide(valueLabel, { TextColor3 = Theme.Text }, 0.12)
                end
            end)
            bind(row.MouseLeave, function()
                glide(trackScale, { Scale = 1 }, 0.12)
                glide(valueLabel, { TextColor3 = Theme.Accent }, 0.12)
            end)

            Slider:SetValue(tonumber(opts.Default) or min)
            if opts.Disabled then Slider:SetDisabled(true) end
            attachTip(row, opts.Tooltip)
            Lib.Options[index] = Slider
            Lib.Controls[index] = Slider
            return Slider
        end

        function Group:AddDropdown(index, opts)
            opts = opts or {}
            local btn = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 30),
                BackgroundColor3 = Theme.Sunken,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = nextOrder(),
            }, holder)
            round(btn, UDim.new(0, 8))
            local btnEdge = outline(btn, Theme.Line, 1)

            local dropdownLabel = new("TextLabel", {
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(0.5, -10, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 10,
                TextColor3 = Theme.Faint,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = opts.Text or "",
            }, btn)
            local valueLabel = new("TextLabel", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -26, 0, 0),
                Size = UDim2.new(0.5, -26, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 10,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = "",
            }, btn)
            local arrow = new("TextLabel", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -10, 0, 0),
                Size = UDim2.fromOffset(12, 30),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 10,
                TextColor3 = Theme.Faint,
                Text = "v",
            }, btn)

            local Dropdown = {
                Type = "Dropdown",
                Index = index,
                Value = opts.Default,
                Default = opts.Default,
                Text = tostring(opts.Text or ""),
                Values = opts.Values or {},
                Instance = btn,
                Open = false,
                Disabled = false,
                NoSave = opts.NoSave and true or false,
                Callbacks = {},
            }
            if type(opts.Callback) == "function" then table.insert(Dropdown.Callbacks, opts.Callback) end
            if Dropdown.Value ~= nil and #Dropdown.Values > 0 and not table.find(Dropdown.Values, Dropdown.Value) then
                Dropdown.Value = nil
            end

            local list = nil
            local function paint()
                valueLabel.Text = Dropdown.Value ~= nil and tostring(Dropdown.Value) or "-"
            end

            local function closeList()
                Dropdown.Open = false
                glide(arrow, { Rotation = 0, TextColor3 = Theme.Faint }, 0.14)
                glide(btn, { BackgroundColor3 = Theme.Sunken }, 0.14)
                if list then list:Destroy() list = nil end
                if openDropdownRef and openDropdownRef.owner == Dropdown then openDropdownRef = nil end
                if not openPaletteRef then sink.Visible = false end
            end

            local function openList()
                if openDropdownRef then openDropdownRef.close() end
                local count = #Dropdown.Values
                if count == 0 then return end
                local viewport = Root.AbsoluteSize
                local width = math.min(math.max(170, btn.AbsoluteSize.X), math.max(170, viewport.X - 16))
                local height = math.min(count, 8) * 24 + 8
                local x = math.clamp(btn.AbsolutePosition.X, 8, math.max(8, viewport.X - width - 8))
                local below = btn.AbsolutePosition.Y + btn.AbsoluteSize.Y + 4
                local y = below + height <= viewport.Y - 8 and below or btn.AbsolutePosition.Y - height - 4
                y = math.clamp(y, 8, math.max(8, viewport.Y - height - 8))
                list = new("ScrollingFrame", {
                    Position = UDim2.fromOffset(x, y),
                    Size = UDim2.fromOffset(width, height),
                    BackgroundColor3 = Theme.Raised,
                    BorderSizePixel = 0,
                    CanvasSize = UDim2.new(),
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    ScrollBarThickness = 2,
                    ScrollBarImageColor3 = Theme.Line,
                    ZIndex = 95,
                }, Root)
                round(list, UDim.new(0, 8), true)
                outline(list, Theme.Line, 1)
                stack(list, 2)
                pad(list, 4, 4, 4, 4)
                for order, value in ipairs(Dropdown.Values) do
                    local item = new("TextButton", {
                        Size = UDim2.new(1, 0, 0, 22),
                        BackgroundColor3 = Theme.Raised,
                        BackgroundTransparency = 1,
                        BorderSizePixel = 0,
                        Font = Enum.Font.GothamMedium,
                        TextSize = 11,
                        TextColor3 = value == Dropdown.Value and Theme.Accent or Theme.SubText,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Text = "  " .. tostring(value),
                        AutoButtonColor = false,
                        LayoutOrder = order,
                        ZIndex = 96,
                    }, list)
                    round(item, UDim.new(0, 6))
                    bind(item.MouseEnter, function() glide(item, { BackgroundTransparency = 0.85, BackgroundColor3 = Theme.AccentSoft }) end)
                    bind(item.MouseLeave, function() glide(item, { BackgroundTransparency = 1 }) end)
                    bind(item.Activated, function()
                        Dropdown:SetValue(value)
                        closeList()
                    end)
                end
                Dropdown.Open = true
                glide(arrow, { Rotation = 180, TextColor3 = Theme.Accent }, 0.16)
                glide(btn, { BackgroundColor3 = Theme.Raised }, 0.16)
                sink.Visible = true
                openDropdownRef = { close = closeList, owner = Dropdown }
            end

            function Dropdown:SetValue(value)
                if value ~= nil and #self.Values > 0 and not table.find(self.Values, value) then
                    return
                end
                if value == self.Value then return end
                self.Value = value
                paint()
                for _, fn in ipairs(self.Callbacks) do runCallback(fn, value) end
            end

            function Dropdown:SetValues(values)
                local clean, seen = {}, {}
                if type(values) == "table" then
                    for _, value in ipairs(values) do
                        local token = typeof(value) .. ":" .. tostring(value)
                        if value ~= nil and not seen[token] then
                            seen[token] = true
                            table.insert(clean, value)
                        end
                    end
                end
                self.Values = clean
                if self.Value ~= nil and #self.Values > 0 and not table.find(self.Values, self.Value) then
                    self.Value = nil
                end
                paint()
                return self
            end

            function Dropdown:GetValue()
                return self.Value
            end

            function Dropdown:Reset()
                local value = self.Default
                if value ~= nil and #self.Values > 0 and not table.find(self.Values, value) then value = nil end
                self:SetValue(value)
                return self
            end

            function Dropdown:SetText(value)
                self.Text = tostring(value or "")
                dropdownLabel.Text = self.Text
                return self
            end

            function Dropdown:Clear()
                self:SetValues({})
                self:SetValue(nil)
                return self
            end

            function Dropdown:OpenMenu()
                if not self.Disabled and not self.Open then openList() end
                return self
            end

            function Dropdown:CloseMenu()
                if self.Open then closeList() end
                return self
            end

            function Dropdown:IsOpen()
                return self.Open
            end

            function Dropdown:IsDisabled()
                return self.Disabled
            end

            function Dropdown:IsVisible()
                return btn.Visible
            end

            function Dropdown:OnChanged(fn)
                if type(fn) == "function" then
                    table.insert(self.Callbacks, fn)
                    runCallback(fn, self.Value)
                end
                return self
            end

            function Dropdown:SetDisabled(state)
                self.Disabled = state and true or false
                if self.Disabled and self.Open then closeList() end
                glide(btn, { BackgroundTransparency = self.Disabled and 0.35 or 0 }, 0.14)
                glide(valueLabel, { TextTransparency = self.Disabled and 0.5 or 0 }, 0.14)
                glide(arrow, { TextTransparency = self.Disabled and 0.5 or 0 }, 0.14)
                return self
            end

            function Dropdown:SetVisible(state)
                if not state and self.Open then closeList() end
                btn.Visible = state and true or false
                return self
            end

            bind(btn.MouseEnter, function()
                if Dropdown.Disabled then return end
                glide(btnEdge, { Color = Theme.Accent }, 0.12)
                if not Dropdown.Open then glide(btn, { BackgroundColor3 = Theme.Raised }, 0.12) end
            end)
            bind(btn.MouseLeave, function()
                glide(btnEdge, { Color = Dropdown.Open and Theme.Accent or Theme.Line }, 0.12)
                if not Dropdown.Open then glide(btn, { BackgroundColor3 = Theme.Sunken }, 0.12) end
            end)
            bind(btn.Activated, function()
                if Lib.Unloaded or Dropdown.Disabled then return end
                local wasOpen = Dropdown.Open
                closePopups()
                if not wasOpen then openList() end
            end)

            paint()
            if opts.Disabled then Dropdown:SetDisabled(true) end
            attachTip(btn, opts.Tooltip)
            Lib.Options[index] = Dropdown
            Lib.Controls[index] = Dropdown
            return Dropdown
        end

        function Group:AddInput(index, opts)
            opts = opts or {}
            local defaultValue = opts.Numeric and (tonumber(opts.Default) or 0) or (opts.Default or "")
            local maxLength = math.max(0, math.floor(tonumber(opts.MaxLength) or 0))
            local box = new("Frame", {
                Size = UDim2.new(1, 0, 0, 46),
                BackgroundTransparency = 1,
                LayoutOrder = nextOrder(),
            }, holder)
            local inputLabel = new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 14),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 10,
                TextColor3 = Theme.Faint,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = opts.Text or "",
            }, box)
            local field = new("TextBox", {
                Position = UDim2.fromOffset(0, 17),
                Size = UDim2.new(1, 0, 0, 28),
                BackgroundColor3 = Theme.Sunken,
                BorderSizePixel = 0,
                Font = Enum.Font.GothamMedium,
                TextSize = 11,
                TextColor3 = Theme.Text,
                PlaceholderText = opts.Placeholder or "",
                PlaceholderColor3 = Theme.Faint,
                Text = tostring(defaultValue),
                TextXAlignment = Enum.TextXAlignment.Left,
                ClearTextOnFocus = false,
                ClipsDescendants = true,
            }, box)
            round(field, UDim.new(0, 8))
            local fieldEdge = outline(field, Theme.Line, 1)
            pad(field, 8, 8, 0, 0)

            local Input = {
                Type = "Input",
                Index = index,
                Value = defaultValue,
                Default = defaultValue,
                Text = tostring(opts.Text or ""),
                Numeric = opts.Numeric and true or false,
                Instance = field,
                Row = box,
                Disabled = false,
                NoSave = opts.NoSave and true or false,
                Callbacks = {},
            }
            if type(opts.Callback) == "function" then table.insert(Input.Callbacks, opts.Callback) end

            local function commit()
                local value = field.Text
                if opts.Trim ~= false then value = value:gsub("^%s+", ""):gsub("%s+$", "") end
                if maxLength > 0 then value = value:sub(1, maxLength) end
                if value == "" and opts.AllowEmpty == false then
                    field.Text = tostring(Input.Value)
                    return false
                end
                if Input.Numeric then
                    value = tonumber(value)
                    if value == nil then
                        field.Text = tostring(Input.Value)
                        return false
                    end
                    if tonumber(opts.Min) then value = math.max(tonumber(opts.Min), value) end
                    if tonumber(opts.Max) then value = math.min(tonumber(opts.Max), value) end
                end
                field.Text = tostring(value)
                if value ~= Input.Value then
                    Input.Value = value
                    for _, fn in ipairs(Input.Callbacks) do runCallback(fn, value) end
                end
                return true
            end

            bind(field:GetPropertyChangedSignal("Text"), function()
                if maxLength > 0 and #field.Text > maxLength then field.Text = field.Text:sub(1, maxLength) end
                if opts.Live == true and not Input.Disabled then commit() end
            end)
            bind(field.Focused, function()
                glide(field, { BackgroundColor3 = Theme.Raised }, 0.14)
                glide(fieldEdge, { Color = Theme.Accent }, 0.14)
            end)
            bind(field.FocusLost, function()
                commit()
                glide(field, { BackgroundColor3 = Theme.Sunken }, 0.14)
                glide(fieldEdge, { Color = Theme.Line }, 0.14)
            end)

            function Input:SetValue(value)
                field.Text = tostring(value == nil and "" or value)
                commit()
                return self
            end

            function Input:GetValue()
                return self.Value
            end

            function Input:Reset()
                self:SetValue(self.Default)
                return self
            end

            function Input:SetText(value)
                self.Text = tostring(value or "")
                inputLabel.Text = self.Text
                return self
            end

            function Input:SetPlaceholder(value)
                field.PlaceholderText = tostring(value or "")
                return self
            end

            function Input:Focus()
                if not self.Disabled then pcall(function() field:CaptureFocus() end) end
                return self
            end

            function Input:Commit()
                return commit()
            end

            function Input:IsFocused()
                return UserInputService:GetFocusedTextBox() == field
            end

            function Input:IsDisabled()
                return self.Disabled
            end

            function Input:IsVisible()
                return box.Visible
            end

            function Input:OnChanged(fn)
                if type(fn) == "function" then
                    table.insert(self.Callbacks, fn)
                    runCallback(fn, self.Value)
                end
                return self
            end

            function Input:SetDisabled(state)
                self.Disabled = state and true or false
                field.TextEditable = not self.Disabled
                glide(field, {
                    BackgroundTransparency = self.Disabled and 0.35 or 0,
                    TextTransparency = self.Disabled and 0.5 or 0,
                }, 0.14)
                glide(fieldEdge, { Transparency = self.Disabled and 0.55 or 0 }, 0.14)
                return self
            end

            function Input:SetVisible(state)
                box.Visible = state and true or false
                return self
            end

            if opts.Disabled then Input:SetDisabled(true) end
            attachTip(box, opts.Tooltip)
            Lib.Options[index] = Input
            Lib.Controls[index] = Input
            return Input
        end

        function Group:AddButton(opts)
            opts = opts or {}
            local btn = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 30),
                BackgroundColor3 = Theme.Sunken,
                BorderSizePixel = 0,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                TextColor3 = Theme.SubText,
                Text = opts.Text or "",
                AutoButtonColor = false,
                LayoutOrder = nextOrder(),
            }, holder)
            round(btn, UDim.new(0, 8))
            local btnEdge = outline(btn, Theme.Line, 1)
            local btnScale = new("UIScale", { Scale = 1 }, btn)
            local disabled, busy = false, false
            local callbacks = {}
            if type(opts.Func) == "function" then table.insert(callbacks, opts.Func) end
            if type(opts.Callback) == "function" and opts.Callback ~= opts.Func then table.insert(callbacks, opts.Callback) end
            bind(btn.MouseEnter, function()
                if disabled then return end
                glide(btn, { BackgroundColor3 = Theme.AccentSoft, TextColor3 = Theme.Text }, 0.14)
                glide(btnEdge, { Color = Theme.Accent }, 0.14)
                glide(btnScale, { Scale = 1.01 }, 0.12)
            end)
            bind(btn.MouseLeave, function()
                glide(btn, { BackgroundColor3 = Theme.Sunken, TextColor3 = Theme.SubText }, 0.14)
                glide(btnEdge, { Color = Theme.Line }, 0.14)
                glide(btnScale, { Scale = 1 }, 0.12)
            end)
            bind(btn.InputBegan, function(input)
                if not disabled and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                    glide(btnScale, { Scale = 0.975 }, 0.06)
                end
            end)
            bind(btn.InputEnded, function(input)
                if not disabled and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                    glide(btnScale, { Scale = 1.01 }, 0.1)
                end
            end)
            local function press()
                if Lib.Unloaded or disabled or busy then return false end
                for _, callback in ipairs(callbacks) do runCallback(callback) end
                return true
            end
            bind(btn.Activated, press)
            local Button = {
                Type = "Button",
                Index = opts.Index,
                Instance = btn,
                Disabled = false,
                Busy = false,
                Text = tostring(opts.Text or ""),
                DefaultText = tostring(opts.Text or ""),
                Callbacks = callbacks,
            }
            function Button:SetText(text)
                self.Text = tostring(text or "")
                btn.Text = self.Text
                return self
            end
            function Button:ResetText()
                return self:SetText(self.DefaultText)
            end
            function Button:OnClick(fn)
                if type(fn) == "function" then table.insert(self.Callbacks, fn) end
                return self
            end
            function Button:Press()
                return press()
            end
            function Button:SetBusy(state, text)
                busy = state and true or false
                self.Busy = busy
                btn.Text = busy and tostring(text or "WORKING…") or self.Text
                btn.Active = not busy
                glide(btn, { BackgroundTransparency = busy and 0.22 or 0 }, 0.12)
                return self
            end
            function Button:IsDisabled()
                return self.Disabled
            end
            function Button:IsVisible()
                return btn.Visible
            end
            function Button:SetDisabled(state)
                disabled = state and true or false
                self.Disabled = disabled
                glide(btn, {
                    BackgroundTransparency = disabled and 0.35 or 0,
                    TextTransparency = disabled and 0.5 or 0,
                }, 0.14)
                glide(btnEdge, { Transparency = disabled and 0.55 or 0 }, 0.14)
                return self
            end
            function Button:SetVisible(state)
                btn.Visible = state and true or false
                return self
            end
            if opts.Disabled then Button:SetDisabled(true) end
            attachTip(btn, opts.Tooltip)
            if opts.Index ~= nil then Lib.Controls[opts.Index] = Button end
            return Button
        end

        return Group
    end

    -- picker + slider input plumbing
    bind(UserInputService.InputBegan, function(input, processed)
        if Lib.Unloaded then return end
        local key = inputName(input)
        if not key then return end

        if listeningPicker then return end

        if key == "Escape" then
            if openDropdownRef or openPaletteRef then closePopups() end
            return
        end

        if Lib.PromptOpen then return end
        local typing = UserInputService:GetFocusedTextBox() ~= nil

        for _, picker in ipairs(pickers) do
            if picker.Value ~= "" and picker.Value == key then
                local hostDisabled = picker.Disabled or (picker.Host and picker.Host.Disabled)
                local allowed = not hostDisabled and (picker.Mode == "Always" or (not processed and not typing))
                if allowed then
                    picker.KeyDown = true
                    if picker.Mode == "Toggle" then
                        picker.Active = not picker.Active
                        if picker.SyncToggleState and picker.Host and picker.Host.Type == "Toggle" then
                            picker.Host:SetValue(picker.Active)
                        else
                            for _, fn in ipairs(picker.Callbacks) do runCallback(fn, picker.Active) end
                        end
                    else
                        for _, fn in ipairs(picker.Callbacks) do runCallback(fn, true) end
                    end
                end
            end
        end
    end)

    bind(UserInputService.InputEnded, function(input)
        if activeSlider and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
            activeSlider = nil
        end
        local key = inputName(input)
        if not key then return end
        for _, picker in ipairs(pickers) do
            if picker.Value == key then
                if picker.Mode == "Hold" then
                    for _, fn in ipairs(picker.Callbacks) do runCallback(fn, false) end
                end
                picker.KeyDown = false
            end
        end
    end)

    bind(UserInputService.InputChanged, function(input)
        if not activeSlider then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            activeSlider:Seek(input.Position.X)
        end
    end)

    local Shell, Scale, TabRail, PageHolder, ActiveTab

    function Lib:CreateWindow(config)
        if Lib.Window and Shell and Shell.Parent then return Lib.Window end
        config = config or {}
        local compact = config.Compact and true or false
        local initialView = Root.AbsoluteSize
        if initialView.X < 1 or initialView.Y < 1 then
            local camera = workspace.CurrentCamera
            initialView = camera and camera.ViewportSize or Vector2.new(1280, 720)
        end
        local mobile = not compact and (config.Mobile == true
            or (config.Mobile ~= false and (initialView.X < 650
                or (UserInputService.TouchEnabled and initialView.X < 900))))
        local windowWidth = compact and 400 or (mobile and 380 or 724)
        local windowHeight = compact and 424 or (mobile and 560 or 516)

        Shell = new("Frame", {
            Name = tag(),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(windowWidth, windowHeight),
            BackgroundColor3 = Theme.Shell,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Visible = false,
        }, Root)
        round(Shell, UDim.new(0, Lib.CornerRadius), true)
        outline(Shell, Theme.Line, 1)
        Scale = new("UIScale", { Scale = 1 }, Shell)

        local mobileToggleButton
        if mobile and config.MobileToggle ~= false then
            mobileToggleButton = new("TextButton", {
                Name = "MobileToggle",
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(1, -34, 0.72, 0),
                Size = UDim2.fromOffset(48, 48),
                BackgroundColor3 = Theme.AccentSoft,
                BorderSizePixel = 0,
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = Theme.Text,
                Text = tostring(config.MobileToggleText or "UX"),
                AutoButtonColor = false,
                ZIndex = 175,
            }, Root)
            round(mobileToggleButton, PILL)
            local mobileToggleEdge = outline(mobileToggleButton, Theme.Accent, 1.5)
            local mobileToggleScale = new("UIScale", { Scale = 1 }, mobileToggleButton)
            new("UIGradient", {
                Rotation = 135,
                Color = ColorSequence.new(Theme.Accent, Theme.AccentSoft),
            }, mobileToggleButton)

            bind(mobileToggleButton.InputBegan, function(input)
                if input.UserInputType == Enum.UserInputType.Touch
                    or input.UserInputType == Enum.UserInputType.MouseButton1 then
                    glide(mobileToggleScale, { Scale = 0.9 }, 0.08)
                    glide(mobileToggleEdge, { Color = Theme.Text }, 0.08)
                end
            end)
            bind(mobileToggleButton.InputEnded, function(input)
                if input.UserInputType == Enum.UserInputType.Touch
                    or input.UserInputType == Enum.UserInputType.MouseButton1 then
                    glide(mobileToggleScale, { Scale = 1 }, 0.12)
                    glide(mobileToggleEdge, { Color = Theme.Accent }, 0.12)
                end
            end)
            bind(mobileToggleButton.Activated, function()
                if Lib.Unloaded then return end
                if Shell.Visible then
                    closePopups()
                    TipCard.Visible = false
                end
                Shell.Visible = not Shell.Visible
            end)
        end

        local function refit()
            if not Scale then return end
            local view = Root.AbsoluteSize
            if view.X < 1 or view.Y < 1 then
                local camera = workspace.CurrentCamera
                view = camera and camera.ViewportSize or Vector2.new(1280, 720)
            end
            local fit = math.min(1, (view.X - 16) / windowWidth,
                (view.Y - 16) / windowHeight)
            Scale.Scale = math.clamp(math.min(Lib.DPI or 1, fit), 0.35, 2)
        end
        Lib.Refit = refit
        bind(Root:GetPropertyChangedSignal("AbsoluteSize"), function()
            refit()
            keepOnScreen(Shell)
        end)
        new("UIGradient", {
            Rotation = 90,
            Color = ColorSequence.new(Theme.ShellTop, Theme.Shell),
        }, Shell)

        local top = new("Frame", {
            Size = UDim2.new(1, 0, 0, 56),
            BackgroundColor3 = Theme.ShellTop,
            BackgroundTransparency = 0.12,
            BorderSizePixel = 0,
        }, Shell)
        dragify(top, Shell)

        local logo = new("ImageLabel", {
            Position = UDim2.fromOffset(18, 14),
            Size = UDim2.fromOffset(28, 28),
            BackgroundColor3 = Theme.Raised,
            BorderSizePixel = 0,
            ScaleType = Enum.ScaleType.Crop,
            Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        }, top)
        round(logo, PILL)
        outline(logo, Theme.Accent, 1.5)
        local logoStatus = new("Frame", {
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, 0, 1, 0),
            Size = UDim2.fromOffset(8, 8),
            BackgroundColor3 = Theme.Success,
            BorderSizePixel = 0,
            ZIndex = 3,
        }, logo)
        round(logoStatus, PILL)
        outline(logoStatus, Theme.ShellTop, 1.5)
        attachTip(logo, LocalPlayer.DisplayName .. "  @" .. LocalPlayer.Name)

        local titleLabel = new("TextLabel", {
            Position = UDim2.fromOffset(54, 14),
            Size = UDim2.fromOffset(mobile and 210 or 240, 16),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = 15,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = config.Title or "Menu",
        }, top)

        local footerLabel = new("TextLabel", {
            Position = UDim2.fromOffset(54, 31),
            Size = UDim2.fromOffset(mobile and 220 or 300, 14),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            TextColor3 = Theme.Faint,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = config.Footer or "",
        }, top)

        new("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -90, 0.5, 0),
            Size = UDim2.fromOffset(160, 14),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            TextSize = 10,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "UI made by : VIPRAVE",
            Visible = not mobile,
        }, top)

        local hideButton = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -18, 0.5, 0),
            Size = UDim2.fromOffset(26, 26),
            BackgroundColor3 = Theme.Raised,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = Theme.SubText,
            Text = "X",
            AutoButtonColor = false,
        }, top)
        round(hideButton, PILL)
        local hideEdge = outline(hideButton, Theme.Line, 1)
        local hideScale = new("UIScale", { Scale = 1 }, hideButton)
        bind(hideButton.MouseEnter, function()
            glide(hideButton, { BackgroundColor3 = Color3.fromRGB(92, 42, 70), TextColor3 = Theme.Text }, 0.14)
            glide(hideEdge, { Color = Color3.fromRGB(255, 122, 176) }, 0.14)
            glide(hideScale, { Scale = 1.06 }, 0.12)
        end)
        bind(hideButton.MouseLeave, function()
            glide(hideButton, { BackgroundColor3 = Theme.Raised, TextColor3 = Theme.SubText }, 0.14)
            glide(hideEdge, { Color = Theme.Line }, 0.14)
            glide(hideScale, { Scale = 1 }, 0.12)
        end)
        bind(hideButton.Activated, function()
            closePopups()
            TipCard.Visible = false
            Shell.Visible = false
        end)

        local topDivider = new("Frame", {
            Position = UDim2.fromOffset(0, 56),
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
        }, Shell)
        new("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Theme.LineSoft),
                ColorSequenceKeypoint.new(0.35, Theme.Accent),
                ColorSequenceKeypoint.new(0.65, Theme.Accent),
                ColorSequenceKeypoint.new(1, Theme.LineSoft),
            }),
        }, topDivider)

        local sidebar
        if not compact then
            if not mobile then
                sidebar = new("Frame", {
                    Position = UDim2.fromOffset(0, 57),
                    Size = UDim2.new(0, 170, 1, -77),
                    BackgroundTransparency = 1,
                    ClipsDescendants = true,
                }, Shell)
            end

            TabRail = new("ScrollingFrame", {
                Position = mobile and UDim2.fromOffset(12, 64) or UDim2.fromOffset(183, 64),
                Size = mobile and UDim2.new(1, -24, 0, 40) or UDim2.new(1, -195, 0, 40),
                BackgroundColor3 = Theme.Sunken,
                BackgroundTransparency = 0.08,
                BorderSizePixel = 0,
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.X,
                ScrollBarThickness = 0,
                ScrollingDirection = Enum.ScrollingDirection.X,
            }, Shell)
            round(TabRail, UDim.new(0, 11), true)
            outline(TabRail, Theme.LineSoft, 1)
            stack(TabRail, 7, Enum.FillDirection.Horizontal)
            pad(TabRail, 6, 6, 6, 6)
        end

        -- ===== player card =====
        local CARD_W = compact and 200 or 170
        local CARD_H = compact and 330 or 112
        local SEG_N = 12

        local card = new("Frame", {
            Position = compact and UDim2.fromOffset((400 - CARD_W) / 2, 64)
                or UDim2.fromOffset(0, 0),
            Size = UDim2.fromOffset(CARD_W, CARD_H),
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Visible = not mobile,
        }, (compact or mobile) and Shell or sidebar)
        round(card, UDim.new(0, Lib.CornerRadius), true)
        local cardEdge = outline(card, Theme.LineSoft, 1)
        new("UIGradient", {
            Rotation = 120,
            Color = ColorSequence.new(Theme.Raised, Theme.Panel),
        }, card)
        if not compact then
            local accentRail = new("Frame", {
                Size = UDim2.new(0, 3, 1, 0),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
            }, card)
            round(accentRail, PILL)
            bind(card.MouseEnter, function()
                glide(cardEdge, { Color = Theme.Accent, Transparency = 0.25 }, 0.16)
            end)
            bind(card.MouseLeave, function()
                glide(cardEdge, { Color = Theme.LineSoft, Transparency = 0 }, 0.16)
            end)
        end

        local chip = new("TextLabel", {
            Position = compact and UDim2.fromOffset(10, 10) or UDim2.fromOffset(CARD_W - 44, 9),
            Size = compact and UDim2.fromOffset(42, 16) or UDim2.fromOffset(34, 14),
            BackgroundColor3 = Theme.Sunken,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = compact and 8 or 7,
            TextColor3 = Theme.Accent,
            Text = "PRO",
        }, card)
        round(chip, PILL)
        outline(chip, Theme.Line, 1)

        local AV = compact and 72 or 38
        local avatar = new("ImageLabel", {
            Position = compact and UDim2.fromOffset((CARD_W - AV) / 2, 34) or UDim2.fromOffset(10, 8),
            Size = UDim2.fromOffset(AV, AV),
            BackgroundColor3 = Theme.Raised,
            BorderSizePixel = 0,
            ScaleType = Enum.ScaleType.Crop,
            Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        }, card)
        round(avatar, PILL)
        outline(avatar, Theme.Accent, 2)

        local dot = new("Frame", {
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -1, 1, -1),
            Size = compact and UDim2.fromOffset(12, 12) or UDim2.fromOffset(9, 9),
            BackgroundColor3 = Theme.Success,
            BorderSizePixel = 0,
            ZIndex = 3,
        }, avatar)
        round(dot, PILL)
        outline(dot, Theme.Panel, 2)

        new("TextLabel", {
            Position = compact and UDim2.fromOffset(10, 34 + AV + 8) or UDim2.fromOffset(56, 8),
            Size = compact and UDim2.new(1, -20, 0, 16) or UDim2.fromOffset(66, 16),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = compact and 13 or 11,
            TextColor3 = Theme.Text,
            TextXAlignment = compact and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = LocalPlayer.DisplayName,
        }, card)

        new("TextLabel", {
            Position = compact and UDim2.fromOffset(10, 34 + AV + 25) or UDim2.fromOffset(56, 27),
            Size = compact and UDim2.new(1, -20, 0, 12) or UDim2.fromOffset(66, 12),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            TextSize = compact and 10 or 9,
            TextColor3 = Theme.Faint,
            TextXAlignment = compact and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "@" .. LocalPlayer.Name,
        }, card)

        new("Frame", {
            Position = compact and UDim2.fromOffset(10, 34 + AV + 44) or UDim2.fromOffset(10, 52),
            Size = UDim2.new(1, -20, 0, 1),
            BackgroundColor3 = Theme.LineSoft,
            BorderSizePixel = 0,
        }, card)

        local rowsY = compact and (34 + AV + 54) or 59
        local rowStep = compact and 20 or 17
        local function infoRow(caption, y)
            new("TextLabel", {
                Position = UDim2.fromOffset(10, y),
                Size = UDim2.new(0.5, -10, 0, 12),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = compact and 8 or 7,
                TextColor3 = Theme.Faint,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = caption,
            }, card)
            return new("TextLabel", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -10, 0, y - 1),
                Size = UDim2.new(0.55, 0, 0, 14),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = compact and 10 or 8,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = "",
            }, card)
        end

        local typeValue = infoRow("KEY TYPE", rowsY)
        local timerValue = infoRow("EXPIRES IN", rowsY + rowStep)
        local idValue = infoRow("KEY ID", rowsY + rowStep * 2)
        idValue.Text = string.format("UXS-%04X-%04X", LocalPlayer.UserId % 0x10000, (LocalPlayer.UserId * 7919) % 0x10000)

        local barY = rowsY + rowStep * 3 + 2
        local SEG_GAP = 3
        local SEG_W = math.floor((CARD_W - 20 - SEG_GAP * (SEG_N - 1)) / SEG_N)
        local segs = {}
        if compact then
            for i = 1, SEG_N do
                local seg = new("Frame", {
                    Position = UDim2.fromOffset(10 + (i - 1) * (SEG_W + SEG_GAP), barY),
                    Size = UDim2.fromOffset(SEG_W, 8),
                    BackgroundColor3 = Theme.Sunken,
                    BorderSizePixel = 0,
                }, card)
                round(seg, UDim.new(0, 2))
                outline(seg, Theme.LineSoft, 1)
                segs[i] = seg
            end
        end

        local function statBlock(caption, anchorRight)
            local x = anchorRight and 1 or 0
            local anchor = Vector2.new(anchorRight and 1 or 0, 0)
            new("TextLabel", {
                AnchorPoint = anchor,
                Position = UDim2.new(x, anchorRight and -10 or 10, 0, CARD_H - 36),
                Size = UDim2.fromOffset(70, 10),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 8,
                TextColor3 = Theme.Faint,
                TextXAlignment = anchorRight and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left,
                Text = caption,
            }, card)
            return new("TextLabel", {
                AnchorPoint = anchor,
                Position = UDim2.new(x, anchorRight and -10 or 10, 0, CARD_H - 23),
                Size = UDim2.fromOffset(90, 15),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = anchorRight and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = "--",
            }, card)
        end

        local sessionValue, pingValue
        if compact then
            sessionValue = statBlock("SESSION", false)
            pingValue = statBlock("PING", true)
        end

        local KEY_TYPES = {
            { Label = "KEYLESS",      Color = Color3.fromRGB(154, 161, 181), Total = 0 },
            { Label = "24 HOUR KEY",  Color = Color3.fromRGB(178, 107, 255), Total = 86400 },
            { Label = "48 HOUR KEY",  Color = Color3.fromRGB(196, 122, 255), Total = 172800 },
            { Label = "WEEK KEY",     Color = Color3.fromRGB(143, 123, 255), Total = 604800 },
            { Label = "MONTH KEY",    Color = Color3.fromRGB(224, 107, 216), Total = 2592000 },
            { Label = "LIFETIME KEY", Color = Theme.Warning,  Total = math.huge },
            { Label = "FREE WEEKEND", Color = Theme.Success,              Total = 604800 },
        }
        local TYPE_MAP = { keyless = 1, ["24h"] = 2, ["48h"] = 3, week = 4, month = 5, lifetime = 6, free = 7 }

        local function fmtTime(t)
            t = math.max(0, math.floor(t))
            local d = math.floor(t / 86400)
            local h = math.floor((t % 86400) / 3600)
            local m = math.floor((t % 3600) / 60)
            local sec = t % 60
            if d > 0 then
                return string.format("%dd %02d:%02d:%02d", d, h, m, sec)
            end
            return string.format("%02d:%02d:%02d", h, m, sec)
        end

        local function paintKey()
            local info = (type(Lib.KeyInfo) == "function" and Lib.KeyInfo()) or { Type = "keyless" }
            local k = KEY_TYPES[TYPE_MAP[info.Type] or 1]
            local remain = 0
            if type(info.Expiry) == "number" then
                remain = math.max(0, info.Expiry - os.time())
            else
                remain = math.max(0, tonumber(info.Remaining) or 0)
            end
            typeValue.Text = k.Label
            typeValue.TextColor3 = k.Color
            timerValue.TextColor3 = k.Color
            local sessionText, sessionColor = "--", Theme.Faint
            local filled = 0
            if k.Total == 0 then
                timerValue.Text = "NOT REQUIRED"
            elseif k.Total == math.huge then
                timerValue.Text = "NEVER"
                sessionText, sessionColor, filled = "INFINITY", Theme.Success, SEG_N
            elseif remain <= 0 then
                timerValue.Text = "EXPIRED"
            else
                timerValue.Text = fmtTime(remain)
                sessionText, sessionColor = fmtTime(k.Total - remain), Theme.Success
                filled = math.ceil(remain / k.Total * SEG_N)
            end
            if sessionValue then
                sessionValue.Text = sessionText
                sessionValue.TextColor3 = sessionColor
            end
            for i, seg in ipairs(segs) do
                seg.BackgroundColor3 = i <= filled and Theme.Success or Theme.Sunken
            end
            return remain, k
        end

        local initialRemain = paintKey()

        -- ===== lightweight status line =====
        local statusStrip = new("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 0, 1, 0),
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
        }, Shell)
        new("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.LineSoft,
            BorderSizePixel = 0,
        }, statusStrip)

        local statusDot = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 10, 0.5, 0),
            Size = UDim2.fromOffset(6, 6),
            BackgroundColor3 = Theme.Success,
            BorderSizePixel = 0,
        }, statusStrip)
        round(statusDot, PILL)

        local statusText = new("TextLabel", {
            Position = UDim2.fromOffset(22, 0),
            Size = UDim2.new(1, -32, 1, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            TextSize = 10,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = "ONLINE  ·  PING --",
        }, statusStrip)

        task.spawn(function()
            local lastRemain = initialRemain
            while not Lib.Unloaded and card.Parent do
                local pingOk, ping = pcall(function() return LocalPlayer:GetNetworkPing() end)
                ping = pingOk and math.floor(ping * 1000 + 0.5) or nil
                statusText.Text = ping and ("ONLINE  ·  PING " .. ping .. " ms") or "ONLINE  ·  PING --"
                if pingValue then pingValue.Text = ping and (ping .. " ms") or "--" end

                local remain, keyType = paintKey()
                if lastRemain > 0 and remain <= 0 and keyType.Total > 0 and keyType.Total ~= math.huge then
                    Lib:Notify("Your " .. keyType.Label:sub(1, 1) .. keyType.Label:sub(2):lower() .. " has expired!")
                end
                lastRemain = remain
                task.wait(1)
            end
        end)

        if not compact then
            if not mobile then
                new("Frame", {
                    Position = UDim2.fromOffset(170, 57),
                    Size = UDim2.new(0, 1, 1, -77),
                    BackgroundColor3 = Theme.LineSoft,
                    BorderSizePixel = 0,
                }, Shell)
            end
            new("Frame", {
                Position = mobile and UDim2.fromOffset(12, 111) or UDim2.fromOffset(171, 111),
                Size = mobile and UDim2.new(1, -24, 0, 1) or UDim2.new(1, -171, 0, 1),
                BackgroundColor3 = Theme.LineSoft,
                BackgroundTransparency = 0.25,
                BorderSizePixel = 0,
            }, Shell)

            PageHolder = new("Frame", {
                Position = mobile and UDim2.fromOffset(0, 112) or UDim2.fromOffset(171, 112),
                Size = mobile and UDim2.new(1, 0, 1, -132) or UDim2.new(1, -171, 1, -132),
                BackgroundTransparency = 1,
            }, Shell)
        end

        local minimized = false
        local fullSize = Shell.Size

        local minButton = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -50, 0.5, 0),
            Size = UDim2.fromOffset(26, 26),
            BackgroundColor3 = Theme.Raised,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = Theme.SubText,
            Text = "-",
            AutoButtonColor = false,
        }, top)
        round(minButton, PILL)
        local minEdge = outline(minButton, Theme.Line, 1)
        local minScale = new("UIScale", { Scale = 1 }, minButton)

        bind(minButton.MouseEnter, function()
            glide(minButton, { BackgroundColor3 = Theme.AccentSoft, TextColor3 = Theme.Text }, 0.14)
            glide(minEdge, { Color = Theme.Accent }, 0.14)
            glide(minScale, { Scale = 1.06 }, 0.12)
        end)
        bind(minButton.MouseLeave, function()
            glide(minButton, { BackgroundColor3 = Theme.Raised, TextColor3 = Theme.SubText }, 0.14)
            glide(minEdge, { Color = Theme.Line }, 0.14)
            glide(minScale, { Scale = 1 }, 0.12)
        end)

        local function setMinimized(state)
            minimized = state and true or false
            minButton.Text = minimized and "+" or "-"
            if not minimized then
                if TabRail then TabRail.Visible = true end
                if PageHolder then PageHolder.Visible = true end
                card.Visible = not mobile
                statusStrip.Visible = true
            end
            glide(Shell, { Size = minimized and UDim2.new(fullSize.X.Scale, fullSize.X.Offset, 0, 56) or fullSize }, 0.14)
            if minimized then
                task.delay(0.15, function()
                    if minimized then
                        if TabRail then TabRail.Visible = false end
                        if PageHolder then PageHolder.Visible = false end
                        card.Visible = false
                        statusStrip.Visible = false
                    end
                end)
            else
                task.delay(0.15, function()
                    if not minimized then keepOnScreen(Shell) end
                end)
            end
        end

        bind(minButton.Activated, function()
            setMinimized(not minimized)
        end)

        local Window = {
            Instance = Shell,
            Mobile = mobile,
            MobileToggleButton = mobileToggleButton,
        }

        function Window:SetMinimized(state)
            setMinimized(state)
            return self
        end

        function Window:IsMinimized()
            return minimized
        end

        function Window:SetTitle(value)
            titleLabel.Text = tostring(value or "")
            return self
        end

        function Window:SetFooter(value)
            footerLabel.Text = tostring(value or "")
            return self
        end

        function Window:Center()
            Shell.Position = UDim2.fromScale(0.5, 0.5)
            keepOnScreen(Shell)
            return self
        end

        function Window:GetSelectedTab()
            return ActiveTab
        end

        function Window:SelectTab(target)
            for index, entry in ipairs(pages) do
                if target == index or target == entry.Tab or tostring(target) == entry.Tab.Name then
                    entry.Tab:Select()
                    return entry.Tab
                end
            end
            return nil
        end

        function Window:SelectNextTab(step)
            if #pages == 0 then return nil end
            local current = 1
            for index, entry in ipairs(pages) do
                if entry.Tab == ActiveTab then current = index break end
            end
            local nextIndex = ((current - 1 + (tonumber(step) or 1)) % #pages) + 1
            pages[nextIndex].Tab:Select()
            return pages[nextIndex].Tab
        end

        function Window:AddTab(name)
            local tabName = tostring(name or "")
            local tabWidth = mobile and math.clamp(#tabName * 6 + 24, 78, 118)
                or math.clamp(#tabName * 7 + 30, 90, 142)
            local button = new("TextButton", {
                Size = UDim2.fromOffset(tabWidth, 28),
                BackgroundColor3 = Theme.Panel,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = #pages + 1,
            }, TabRail)
            round(button, PILL)
            local edge = outline(button, Theme.Line, 1, 1)
            local buttonScale = new("UIScale", { Scale = 1 }, button)

            local mark = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 1),
                Position = UDim2.new(0.5, 0, 1, -3),
                Size = UDim2.fromOffset(0, 2),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
            }, button)
            round(mark, PILL)

            local label = new("TextLabel", {
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -20, 1, -2),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 10,
                TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = tabName,
            }, button)

            local page = new("Frame", {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                Visible = false,
            }, PageHolder)
            pad(page, mobile and 12 or 16, mobile and 12 or 16, 14, 0)

            local left = new("ScrollingFrame", {
                Size = mobile and UDim2.new(1, 0, 1, 0) or UDim2.new(0.5, -8, 1, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = Theme.Line,
                ScrollingDirection = Enum.ScrollingDirection.Y,
            }, page)
            stack(left, 12)
            pad(left, 2, 8, 2, 16)

            local right = left
            if not mobile then
                right = new("ScrollingFrame", {
                    Position = UDim2.new(0.5, 8, 0, 0),
                    Size = UDim2.new(0.5, -8, 1, 0),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    CanvasSize = UDim2.new(),
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    ScrollBarThickness = 2,
                    ScrollBarImageColor3 = Theme.Line,
                    ScrollingDirection = Enum.ScrollingDirection.Y,
                }, page)
                stack(right, 12)
                pad(right, 2, 8, 2, 16)
            end

            local Tab = { Name = tabName, Page = page, Left = left, Right = right, Button = button, Groups = {} }

            function Tab:GetName()
                return self.Name
            end

            function Tab:SetName(value)
                self.Name = tostring(value or "")
                label.Text = self.Name
                local width = mobile and math.clamp(#self.Name * 6 + 24, 78, 118)
                    or math.clamp(#self.Name * 7 + 30, 90, 142)
                button.Size = UDim2.fromOffset(width, 28)
                return self
            end

            function Tab:IsSelected()
                return ActiveTab == self
            end

            function Tab:SetVisible(state)
                state = state and true or false
                button.Visible = state
                if not state and ActiveTab == self then
                    for _, entry in ipairs(pages) do
                        if entry.Tab ~= self and entry.Button.Visible then entry.Tab:Select() break end
                    end
                end
                return self
            end

            function Tab:IsVisible()
                return button.Visible
            end

            function Tab:ScrollToTop()
                left.CanvasPosition = Vector2.new(0, 0)
                if right ~= left then right.CanvasPosition = Vector2.new(0, 0) end
                return self
            end

            function Tab:Select()
                for _, other in ipairs(pages) do
                    other.Page.Visible = false
                    glide(other.Button, { BackgroundTransparency = 1 })
                    glide(other.Edge, { Transparency = 1 })
                    glide(other.Label, { TextColor3 = Theme.SubText })
                    glide(other.Mark, { Size = UDim2.fromOffset(0, 2) })
                    glide(other.Scale, { Scale = 1 }, 0.12)
                end
                page.Position = UDim2.fromOffset(8, 0)
                page.Visible = true
                glide(page, { Position = UDim2.fromOffset(0, 0) }, 0.16)
                task.defer(function()
                    if not button.Parent then return end
                    local current = TabRail.CanvasPosition.X
                    local left = button.AbsolutePosition.X - TabRail.AbsolutePosition.X + current
                    local right = left + button.AbsoluteSize.X
                    local visibleWidth = TabRail.AbsoluteSize.X
                    local target = current
                    if left < current + 6 then target = left - 6 end
                    if right > current + visibleWidth - 6 then target = right - visibleWidth + 6 end
                    local maxCanvas = math.max(0, TabRail.AbsoluteCanvasSize.X - visibleWidth)
                    glide(TabRail, { CanvasPosition = Vector2.new(math.clamp(target, 0, maxCanvas), 0) }, 0.16)
                end)
                glide(button, { BackgroundTransparency = 0.78, BackgroundColor3 = Theme.AccentSoft })
                glide(edge, { Transparency = 0.25, Color = Theme.Accent })
                glide(label, { TextColor3 = Theme.Text })
                glide(mark, { Size = UDim2.fromOffset(34, 2) })
                glide(buttonScale, { Scale = 1.015 }, 0.14)
                ActiveTab = Tab
                return self
            end

            local function makeBox(column, title)
                local box = new("Frame", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundColor3 = Theme.Panel,
                    BorderSizePixel = 0,
                    LayoutOrder = #column:GetChildren(),
                }, column)
                round(box, UDim.new(0, Lib.CornerRadius), true)
                local boxEdge = outline(box, Theme.LineSoft, 1)
                new("UIGradient", {
                    Rotation = 135,
                    Color = ColorSequence.new(Theme.Panel, Theme.ShellTop),
                }, box)
                pad(box, 14, 14, 12, 14)
                bind(box.MouseEnter, function()
                    glide(boxEdge, { Color = Theme.Line, Transparency = 0.2 }, 0.16)
                end)
                bind(box.MouseLeave, function()
                    glide(boxEdge, { Color = Theme.LineSoft, Transparency = 0 }, 0.16)
                end)

                local head = new("Frame", {
                    Size = UDim2.new(1, 0, 0, 20),
                    BackgroundTransparency = 1,
                    LayoutOrder = 0,
                }, box)

                local badge = new("Frame", {
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 0, 0.5, 0),
                    Size = UDim2.fromOffset(3, 13),
                    BackgroundColor3 = Theme.Accent,
                    BorderSizePixel = 0,
                }, head)
                round(badge, PILL)
                new("UIGradient", {
                    Rotation = 90,
                    Color = ColorSequence.new(Theme.Accent, Theme.AccentSoft),
                }, badge)
                new("Frame", {
                    Position = UDim2.new(0, 12, 1, -1),
                    Size = UDim2.new(1, -12, 0, 1),
                    BackgroundColor3 = Theme.LineSoft,
                    BackgroundTransparency = 0.35,
                    BorderSizePixel = 0,
                }, head)

                local boxTitle = new("TextLabel", {
                    Position = UDim2.fromOffset(12, 0),
                    Size = UDim2.new(1, -12, 1, 0),
                    BackgroundTransparency = 1,
                    Font = Enum.Font.GothamBold,
                    TextSize = 12,
                    TextColor3 = Theme.Text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Text = title or "",
                }, head)

                local body = new("Frame", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    LayoutOrder = 1,
                }, box)
                stack(body, 10)
                pad(body, 0, 0, 10, 0)

                stack(box, 0)
                local group = makeGroup(body)
                group.Box = box
                group.TitleLabel = boxTitle
                group.Collapsed = false
                function group:SetTitle(value)
                    boxTitle.Text = tostring(value or "")
                    return self
                end
                function group:SetCollapsed(state)
                    self.Collapsed = state and true or false
                    body.Visible = not self.Collapsed
                    return self
                end
                function group:ToggleCollapsed()
                    return self:SetCollapsed(not self.Collapsed)
                end
                function group:SetVisible(state)
                    box.Visible = state and true or false
                    return self
                end
                function group:IsVisible()
                    return box.Visible
                end
                table.insert(Tab.Groups, group)
                return group
            end

            function Tab:AddLeftGroupbox(title)
                return makeBox(left, title)
            end

            function Tab:AddRightGroupbox(title)
                return makeBox(right, title)
            end

            function Tab:AddGroupbox(title, side)
                return tostring(side or "Left"):lower() == "right" and self:AddRightGroupbox(title) or self:AddLeftGroupbox(title)
            end

            function Tab:GetGroupboxes()
                return table.clone(self.Groups)
            end

            bind(button.Activated, function() Tab:Select() end)
            bind(button.MouseEnter, function()
                if ActiveTab ~= Tab then
                    glide(button, { BackgroundTransparency = 0.35, BackgroundColor3 = Theme.Raised })
                    glide(buttonScale, { Scale = 1.01 }, 0.12)
                end
            end)
            bind(button.MouseLeave, function()
                if ActiveTab ~= Tab then
                    glide(button, { BackgroundTransparency = 1 })
                    glide(buttonScale, { Scale = 1 }, 0.12)
                end
            end)

            table.insert(pages, { Tab = Tab, Page = page, Button = button, Edge = edge, Label = label, Mark = mark, Scale = buttonScale })
            if #pages == 1 then
                Tab:Select()
            end
            return Tab
        end

        function Window:SetCornerRadius(radius)
            radius = math.clamp(tonumber(radius) or Lib.CornerRadius, 0, 32)
            Lib.CornerRadius = radius
            for _, corner in ipairs(panels) do
                corner.CornerRadius = UDim.new(0, radius)
            end
            return self
        end

        function Window:SetVisible(state)
            state = state and true or false
            if not state then
                closePopups()
                TipCard.Visible = false
            end
            Shell.Visible = state
            return self
        end

        function Window:IsVisible()
            return Shell.Visible
        end

        function Window:SetMobileToggleVisible(state)
            if mobileToggleButton then
                mobileToggleButton.Visible = state and true or false
            end
            return self
        end

        function Window:SetMobileToggleText(text)
            if mobileToggleButton then
                mobileToggleButton.Text = tostring(text or "UX")
            end
            return self
        end

        function Window:Toggle()
            self:SetVisible(not Shell.Visible)
            return self
        end

        function Window:GetTitle()
            return titleLabel.Text
        end

        function Window:GetFooter()
            return footerLabel.Text
        end

        function Window:GetPosition()
            return Shell.Position
        end

        function Window:SetPosition(position)
            if typeof(position) == "UDim2" then
                Shell.Position = position
                keepOnScreen(Shell)
            end
            return self
        end

        function Window:GetSize()
            return Shell.Size
        end

        function Window:SetStatus(text, color)
            statusText.Text = tostring(text or "")
            if typeof(color) == "Color3" then
                statusText.TextColor3 = color
                statusDot.BackgroundColor3 = color
            end
            return self
        end

        function Window:GetTabs()
            local tabs = {}
            for _, entry in ipairs(pages) do table.insert(tabs, entry.Tab) end
            return tabs
        end

        function Window:GetTab(name)
            for _, entry in ipairs(pages) do
                if entry.Tab.Name == tostring(name) then return entry.Tab end
            end
            return nil
        end

        function Window:ScrollActiveTabToTop()
            if ActiveTab then
                ActiveTab.Left.CanvasPosition = Vector2.new(0, 0)
                if ActiveTab.Right ~= ActiveTab.Left then ActiveTab.Right.CanvasPosition = Vector2.new(0, 0) end
            end
            return self
        end

        function Window:SetDPI(value)
            Lib:SetDPI(value)
            return self
        end

        Lib.Window = Window
        Lib:SetNotifySide(config.NotifySide or "Right")

        refit()
        Shell.Visible = true

        return Window
    end

    bind(UserInputService.InputBegan, function(input, processed)
        if listeningPicker or processed or Lib.Unloaded or not Shell then return end
        local key = inputName(input)
        if not key or UserInputService:GetFocusedTextBox() then return end
        local wanted = Lib.ToggleKeybind and Lib.ToggleKeybind.Value or Lib.DefaultToggleKey
        if wanted ~= "" and key == wanted then
            if Shell.Visible then
                closePopups()
                TipCard.Visible = false
            end
            Shell.Visible = not Shell.Visible
        end
    end)


    function Lib:SetAnimationsEnabled(state)
        self.AnimationsEnabled = state and true or false
        if not self.AnimationsEnabled then
            for instance, tween in pairs(activeTweens) do
                if tween then tween:Cancel() end
                activeTweens[instance] = nil
            end
        end
        return self
    end

    function Lib:SetReducedMotion(state)
        self.ReducedMotion = state and true or false
        self:SetAnimationsEnabled(not self.ReducedMotion)
        return self
    end

    function Lib:GetControl(index)
        return self.Controls[index] or self.Toggles[index] or self.Options[index]
    end

    function Lib:HasControl(index)
        return self:GetControl(index) ~= nil
    end

    function Lib:GetValue(index, fallback)
        local control = self:GetControl(index)
        if not control then return fallback end
        if type(control.GetValue) == "function" then return control:GetValue() end
        if control.Value ~= nil then return control.Value end
        return fallback
    end

    function Lib:SetValue(index, value)
        local control = self:GetControl(index)
        if not control or type(control.SetValue) ~= "function" then return false end
        local ok = pcall(control.SetValue, control, value)
        return ok
    end

    function Lib:SetValues(values)
        local report = { Updated = 0, Missing = {}, Failed = {} }
        if type(values) ~= "table" then return report end
        for index, value in pairs(values) do
            local control = self:GetControl(index)
            if not control then
                table.insert(report.Missing, index)
            elseif type(control.SetValue) ~= "function" then
                table.insert(report.Failed, index)
            else
                local ok = pcall(control.SetValue, control, value)
                if ok then report.Updated = report.Updated + 1 else table.insert(report.Failed, index) end
            end
        end
        return report
    end

    function Lib:GetState(includeNoSave)
        local state = {}
        for index, control in pairs(self.Controls) do
            if includeNoSave or not control.NoSave then
                if type(control.GetValue) == "function" then
                    local ok, value = pcall(control.GetValue, control)
                    if ok then state[index] = value end
                elseif control.Value ~= nil then
                    state[index] = control.Value
                end
            end
        end
        return state
    end

    function Lib:ResetControl(index)
        local control = self:GetControl(index)
        if not control or type(control.Reset) ~= "function" then return false end
        return pcall(control.Reset, control)
    end

    function Lib:ResetAll(includeNoSave)
        local reset = 0
        for _, control in pairs(self.Controls) do
            if (includeNoSave or not control.NoSave) and type(control.Reset) == "function" then
                if pcall(control.Reset, control) then reset = reset + 1 end
            end
        end
        return reset
    end

    function Lib:SetControlDisabled(index, state)
        local control = self:GetControl(index)
        if not control or type(control.SetDisabled) ~= "function" then return false end
        return pcall(control.SetDisabled, control, state)
    end

    function Lib:SetControlVisible(index, state)
        local control = self:GetControl(index)
        if not control or type(control.SetVisible) ~= "function" then return false end
        return pcall(control.SetVisible, control, state)
    end

    function Lib:FindControls(query)
        query = tostring(query or ""):lower()
        local found = {}
        for index, control in pairs(self.Controls) do
            local haystack = (tostring(index) .. " " .. tostring(control.Text or "") .. " " .. tostring(control.Type or "")):lower()
            if query == "" or haystack:find(query, 1, true) then
                table.insert(found, { Index = index, Control = control })
            end
        end
        table.sort(found, function(a, b) return tostring(a.Index) < tostring(b.Index) end)
        return found
    end

    function Lib:GetControlStats()
        local stats = { Total = 0, Toggles = 0, Options = 0, Disabled = 0, Hidden = 0 }
        for _, control in pairs(self.Controls) do
            stats.Total = stats.Total + 1
            if control.Type == "Toggle" then stats.Toggles = stats.Toggles + 1 else stats.Options = stats.Options + 1 end
            if control.Disabled then stats.Disabled = stats.Disabled + 1 end
            if type(control.IsVisible) == "function" then
                local ok, visible = pcall(control.IsVisible, control)
                if ok and not visible then stats.Hidden = stats.Hidden + 1 end
            end
        end
        return stats
    end

    function Lib:GetCallbackErrors(clear)
        local errors = table.clone(self.CallbackErrors)
        if clear then table.clear(self.CallbackErrors) end
        return errors
    end

    function Lib:ClearCallbackErrors()
        table.clear(self.CallbackErrors)
        return self
    end

    function Lib:ClosePopups()
        closePopups()
        TipCard.Visible = false
        return self
    end

    function Lib:SetToggleKey(value)
        self.DefaultToggleKey = normalizeBind(value)
        if self.ToggleKeybind then self.ToggleKeybind:SetValue(self.DefaultToggleKey) end
        return self
    end

    function Lib:IsMobile()
        return self.Window and self.Window.Mobile or false
    end

    function Lib:OnUnload(fn)
        if type(fn) == "function" then table.insert(unloadCallbacks, fn) end
        return self
    end

    function Lib:SetDPI(scale)
        Lib.DPI = math.clamp(tonumber(scale) or 1, 0.5, 2)
        if Lib.Refit then Lib.Refit() end
    end

    function Lib:SetKeyExpiry(expiry)
        Lib.KeyExpiryOverride = tonumber(expiry) or nil
    end

    function Lib:SetKeyType(label)
        local text = tostring(label or ""):lower()
        local mapped
        if text:find("life", 1, true) then
            mapped = "lifetime"
        elseif text:find("free", 1, true) then
            mapped = "free"
        elseif text:find("month", 1, true) or text:find("30", 1, true) then
            mapped = "month"
        elseif text:find("week", 1, true) or text:find("7 day", 1, true) then
            mapped = "week"
        elseif text:find("48", 1, true) then
            mapped = "48h"
        elseif text:find("24", 1, true) then
            mapped = "24h"
        end
        Lib.KeyTypeOverride = mapped
    end

    function Lib:KeyPrompt(config)
        if Lib.PromptOpen then return false end
        config = config or {}
        Lib.PromptOpen = true
        Lib.PromptUsed = true

        local result = nil
        local finished = false
        local completion = Instance.new("BindableEvent")
        local promptView = Root.AbsoluteSize
        if promptView.X < 1 then
            local camera = workspace.CurrentCamera
            promptView = camera and camera.ViewportSize or Vector2.new(1280, 720)
        end
        local promptWidth = math.clamp(promptView.X - 24, 320, 560)
        local promptHeight = math.max(280, math.min(560, promptView.Y - 24))
        local promptCompact = promptWidth < 440

        local backdrop = new("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 0.32,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            Active = true,
            Modal = true,
            ZIndex = 100,
        }, Root)

        -- ===== floating draggable panel =====
        local host = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(promptWidth, promptHeight),
            BackgroundColor3 = Theme.Shell,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            ZIndex = 102,
        }, backdrop)
        local hostScale = new("UIScale", { Scale = 0.965 }, host)
        round(host, UDim.new(0, Lib.CornerRadius), true)
        outline(host, Theme.Line, 1)
        new("UIGradient", {
            Rotation = 90,
            Color = ColorSequence.new(Theme.ShellTop, Theme.Shell),
        }, host)
        pad(host, 0, 0, 0, 24)
        task.defer(function()
            if host.Parent then glide(hostScale, { Scale = 1 }, 0.18) end
        end)

        local function finish(value)
            if finished then return end
            finished = true
            result = value and true or false
            Lib.PromptOpen = false
            if not result and type(config.OnCancel) == "function" then pcall(config.OnCancel) end
            if type(config.OnClose) == "function" then pcall(config.OnClose, result) end
            completion:Fire()
            backdrop:Destroy()
        end
        bind(backdrop.Activated, function()
            if config.CloseOnOutside == true then finish(false) end
        end)
        local hostRemovedConn = host.AncestryChanged:Connect(function(_, parent)
            if parent == nil then finish(false) end
        end)

        -- ===== top bar =====
        local bar = new("Frame", {
            Size = UDim2.new(1, 0, 0, 46),
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            ZIndex = 101,
        }, host)
        new("UIGradient", {
            Color = ColorSequence.new(Theme.ShellTop, Theme.Panel),
        }, bar)
        new("Frame", {
            Position = UDim2.new(0, 0, 1, -1),
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            ZIndex = 102,
        }, bar)

        local logo = new("Frame", {
            Position = UDim2.fromOffset(18, 13),
            Size = UDim2.fromOffset(20, 20),
            BackgroundColor3 = Theme.Raised,
            BorderSizePixel = 0,
            ZIndex = 102,
        }, bar)
        round(logo, PILL)
        outline(logo, Theme.Accent, 1)
        new("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = Theme.Accent,
            Text = "U",
            ZIndex = 103,
        }, logo)

        new("TextLabel", {
            Position = UDim2.fromOffset(46, 0),
            Size = UDim2.new(1, -100, 1, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = 15,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = string.upper(tostring(config.Title or "UXOSUIM STUDIO")),
            ZIndex = 102,
        }, bar)

        local service = new("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -54, 0.5, 0),
            Size = UDim2.fromOffset(150, 22),
            BackgroundColor3 = Theme.Sunken,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 8,
            TextColor3 = Theme.Accent,
            Text = string.upper(tostring(config.Service or "")),
            Visible = not promptCompact,
            ZIndex = 102,
        }, bar)
        round(service, PILL)
        outline(service, Theme.Line, 1)

        local close = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -14, 0.5, 0),
            Size = UDim2.fromOffset(26, 26),
            BackgroundColor3 = Theme.Raised,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = Theme.SubText,
            Text = "X",
            AutoButtonColor = false,
            ZIndex = 102,
        }, bar)
        round(close, PILL)
        local closeEdge = outline(close, Theme.Line, 1)
        local closeScale = new("UIScale", { Scale = 1 }, close)
        bind(close.MouseEnter, function()
            glide(close, { BackgroundColor3 = Theme.Danger, TextColor3 = Theme.Text }, 0.12)
            glide(closeEdge, { Color = Theme.Danger }, 0.12)
            glide(closeScale, { Scale = 1.06 }, 0.12)
        end)
        bind(close.MouseLeave, function()
            glide(close, { BackgroundColor3 = Theme.Raised, TextColor3 = Theme.SubText }, 0.12)
            glide(closeEdge, { Color = Theme.Line }, 0.12)
            glide(closeScale, { Scale = 1 }, 0.12)
        end)
        bind(close.Activated, function() finish(false) end)

        dragify(bar, host)

        -- ===== center column (key side) =====
        local ONLINE = Theme.Success

        local colMargin = promptCompact and 18 or 35
        local col = new("ScrollingFrame", {
            Position = UDim2.fromOffset(colMargin, 70),
            Size = UDim2.new(1, -colMargin * 2, 1, -88),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = promptCompact and 2 or 3,
            ScrollBarImageColor3 = Theme.Accent,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
            ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
            ZIndex = 101,
        }, host)
        local colLayout = stack(col, 0)
        colLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

        local function spacer(order, height)
            new("Frame", {
                Size = UDim2.new(1, 0, 0, height),
                BackgroundTransparency = 1,
                LayoutOrder = order,
            }, col)
        end

        -- identity row: avatar + user + online chip
        local idRow = new("Frame", {
            Size = UDim2.new(1, 0, 0, 64),
            BackgroundColor3 = Theme.Raised,
            BackgroundTransparency = 0.28,
            BorderSizePixel = 0,
            LayoutOrder = 1,
            ZIndex = 102,
        }, col)
        round(idRow, UDim.new(0, 12))
        outline(idRow, Theme.LineSoft, 1)

        local idAvatar = new("ImageLabel", {
            Position = UDim2.fromOffset(8, 8),
            Size = UDim2.fromOffset(48, 48),
            BackgroundColor3 = Theme.Raised,
            BorderSizePixel = 0,
            ScaleType = Enum.ScaleType.Crop,
            Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
            ZIndex = 103,
        }, idRow)
        round(idAvatar, PILL)
        outline(idAvatar, Theme.Accent, 2)

        new("TextLabel", {
            Position = UDim2.fromOffset(68, 8),
            Size = UDim2.new(1, -68 - 110, 0, 20),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = 16,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = LocalPlayer.DisplayName,
            ZIndex = 103,
        }, idRow)

        new("TextLabel", {
            Position = UDim2.fromOffset(68, 30),
            Size = UDim2.new(1, -68 - 110, 0, 14),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            TextColor3 = Theme.Faint,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "@" .. LocalPlayer.Name,
            ZIndex = 103,
        }, idRow)

        local onlineChip = new("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -8, 0.5, 0),
            Size = UDim2.fromOffset(promptCompact and 76 or 96, 24),
            BackgroundColor3 = Color3.fromRGB(18, 38, 27),
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 9,
            TextColor3 = ONLINE,
            Text = "● ONLINE",
            ZIndex = 103,
        }, idRow)
        round(onlineChip, PILL)
        outline(onlineChip, ONLINE, 1)

        spacer(2, 22)

        local promptTitle = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = promptCompact and 22 or 26,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = string.upper(tostring(config.Title or "UXOSUIM STUDIO")),
            LayoutOrder = 3,
            ZIndex = 102,
        }, col)

        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 14),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = Theme.Accent,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = string.upper(tostring(config.Subtitle or "SECURE KEY ACCESS")),
            LayoutOrder = 4,
            ZIndex = 102,
        }, col)

        spacer(5, 10)

        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextColor3 = Theme.SubText,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = tostring(config.Message or ""),
            LayoutOrder = 6,
            ZIndex = 102,
        }, col)

        local trustRow = new("Frame", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundTransparency = 1,
            LayoutOrder = 7,
            ZIndex = 102,
        }, col)
        stack(trustRow, 6, Enum.FillDirection.Horizontal)
        local function trustChip(text)
            local chip = new("TextLabel", {
                Size = UDim2.new(1 / 3, -4, 1, 0),
                BackgroundColor3 = Theme.Sunken,
                BorderSizePixel = 0,
                Font = Enum.Font.GothamBold,
                TextSize = promptCompact and 7 or 8,
                TextColor3 = Theme.SubText,
                Text = text,
                ZIndex = 103,
            }, trustRow)
            round(chip, PILL)
            outline(chip, Theme.LineSoft, 1)
        end
        trustChip("◆ SECURE")
        trustChip("● PRIVATE")
        trustChip("⚡ FAST")

        -- key input + REDEEM
        local inputRow = new("Frame", {
            Size = UDim2.new(1, 0, 0, promptCompact and 100 or 46),
            BackgroundTransparency = 1,
            LayoutOrder = 8,
            ZIndex = 102,
        }, col)

        local input = new("TextBox", {
            Size = promptCompact and UDim2.new(1, 0, 0, 44) or UDim2.new(1, -282, 1, 0),
            BackgroundColor3 = Theme.Raised,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamMedium,
            TextSize = 14,
            TextColor3 = Theme.Text,
            PlaceholderText = tostring(config.Placeholder or "Enter your key"),
            PlaceholderColor3 = Theme.Faint,
            Text = tostring(config.DefaultKey or ""),
            TextXAlignment = Enum.TextXAlignment.Left,
            ClearTextOnFocus = false,
            ClipsDescendants = true,
            ZIndex = 103,
        }, inputRow)
        round(input, UDim.new(0, 10))
        local inputEdge = outline(input, Theme.Line, 1)
        pad(input, 12, 58, 0, 0)

        local keyLimit = math.max(16, math.floor(tonumber(config.MaxKeyLength) or 128))
        local keyCount = new("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.fromOffset(42, 16),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            TextSize = 8,
            TextColor3 = Theme.Faint,
            TextXAlignment = Enum.TextXAlignment.Right,
            Text = "0/" .. keyLimit,
            ZIndex = 104,
        }, input)

        local paste = new("TextButton", {
            AnchorPoint = promptCompact and Vector2.new(0, 0) or Vector2.new(1, 0),
            Position = promptCompact and UDim2.fromOffset(0, 54) or UDim2.new(1, -190, 0, 0),
            Size = UDim2.fromOffset(82, promptCompact and 44 or 46),
            BackgroundColor3 = Theme.Raised,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            TextColor3 = Theme.SubText,
            Text = tostring(config.PasteText or "PASTE"),
            AutoButtonColor = false,
            ZIndex = 103,
        }, inputRow)
        round(paste, UDim.new(0, 10))
        local pasteEdge = outline(paste, Theme.Line, 1)
        bind(paste.MouseEnter, function()
            glide(paste, { BackgroundColor3 = Theme.AccentSoft, TextColor3 = Theme.Text }, 0.12)
            glide(pasteEdge, { Color = Theme.Accent }, 0.12)
        end)
        bind(paste.MouseLeave, function()
            glide(paste, { BackgroundColor3 = Theme.Raised, TextColor3 = Theme.SubText }, 0.12)
            glide(pasteEdge, { Color = Theme.Line }, 0.12)
        end)

        local redeem = new("TextButton", {
            AnchorPoint = promptCompact and Vector2.new(0, 0) or Vector2.new(1, 0),
            Position = promptCompact and UDim2.fromOffset(92, 54) or UDim2.new(1, 0, 0, 0),
            Size = promptCompact and UDim2.new(1, -92, 0, 44) or UDim2.fromOffset(180, 46),
            BackgroundColor3 = Theme.AccentSoft,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = Theme.Text,
            Text = tostring(config.RedeemText or "REDEEM"),
            AutoButtonColor = false,
            ZIndex = 103,
        }, inputRow)
        round(redeem, UDim.new(0, 12))
        local redeemEdge = outline(redeem, Theme.Accent, 1)
        local redeemScale = new("UIScale", { Scale = 1 }, redeem)
        bind(redeem.MouseEnter, function()
            glide(redeem, { BackgroundColor3 = Theme.Accent }, 0.12)
            glide(redeemEdge, { Color = Theme.Text }, 0.12)
            glide(redeemScale, { Scale = 1.015 }, 0.12)
        end)
        bind(redeem.MouseLeave, function()
            glide(redeem, { BackgroundColor3 = Theme.AccentSoft }, 0.12)
            glide(redeemEdge, { Color = Theme.Accent }, 0.12)
            glide(redeemScale, { Scale = 1 }, 0.12)
        end)
        bind(redeem.InputBegan, function(inputEvent)
            if inputEvent.UserInputType == Enum.UserInputType.MouseButton1
                or inputEvent.UserInputType == Enum.UserInputType.Touch then
                glide(redeemScale, { Scale = 0.97 }, 0.06)
            end
        end)
        bind(redeem.InputEnded, function(inputEvent)
            if inputEvent.UserInputType == Enum.UserInputType.MouseButton1
                or inputEvent.UserInputType == Enum.UserInputType.Touch then
                glide(redeemScale, { Scale = 1 }, 0.1)
            end
        end)
        bind(input.Focused, function()
            glide(input, { BackgroundColor3 = Theme.Sunken }, 0.12)
            glide(inputEdge, { Color = Theme.Accent, Thickness = 1.5 }, 0.12)
        end)
        bind(input.FocusLost, function()
            glide(input, { BackgroundColor3 = Theme.Raised }, 0.12)
            glide(inputEdge, { Color = Theme.Line, Thickness = 1 }, 0.12)
        end)

        spacer(9, 10)

        spacer(11, 10)

        local status = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = Theme.Raised,
            BackgroundTransparency = 0.2,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "",
            Visible = false,
            LayoutOrder = 12,
            ZIndex = 102,
        }, col)
        round(status, UDim.new(0, 9))
        local statusEdge = outline(status, Theme.LineSoft, 1)
        pad(status, 12, 12, 0, 0)

        local function setStatus(text, color)
            status.Text = tostring(text or "")
            status.TextColor3 = color or Theme.SubText
            status.Visible = status.Text ~= ""
            if type(config.OnStatus) == "function" then pcall(config.OnStatus, status.Text, color) end
            if status.Visible then
                glide(status, { BackgroundTransparency = 0.2 }, 0.12)
                glide(statusEdge, { Color = color or Theme.LineSoft, Transparency = 0.2 }, 0.12)
            end
        end

        local adjustingText = false
        bind(input:GetPropertyChangedSignal("Text"), function()
            if adjustingText then return end
            adjustingText = true
            if #input.Text > keyLimit then input.Text = input.Text:sub(1, keyLimit) end
            keyCount.Text = tostring(#input.Text) .. "/" .. keyLimit
            keyCount.TextColor3 = #input.Text >= keyLimit and Theme.Warning or Theme.Faint
            if status.Visible then status.Visible = false end
            adjustingText = false
        end)
        if #input.Text > keyLimit then input.Text = input.Text:sub(1, keyLimit) end
        keyCount.Text = tostring(#input.Text) .. "/" .. keyLimit
        bind(paste.Activated, function()
            local reader = type(config.ReadClipboard) == "function" and config.ReadClipboard or getclipboard
            if type(reader) ~= "function" then
                return setStatus("Clipboard access is unavailable", Theme.Warning)
            end
            local ok, value = pcall(reader)
            if not ok or type(value) ~= "string" or value == "" then
                return setStatus("Clipboard is empty", Theme.Warning)
            end
            input.Text = value:sub(1, keyLimit)
            input.CursorPosition = #input.Text + 1
            setStatus("Key pasted from clipboard", Theme.Success)
        end)

        -- GET KEY + DISCORD
        local btnRow = new("Frame", {
            Size = UDim2.new(1, 0, 0, 38),
            BackgroundTransparency = 1,
            LayoutOrder = 10,
            ZIndex = 102,
        }, col)

        local function copyAccessLink(kind, configuredUrl, callback)
            local url = tostring(configuredUrl or "")
            if type(callback) == "function" then
                local ran, replacement = pcall(callback, url)
                if not ran then return setStatus(kind .. " action failed", Theme.Warning) end
                if replacement == true then return setStatus(kind .. " action completed", Theme.Success) end
                if type(replacement) == "string" and replacement ~= "" then url = replacement end
            end
            if url == "" then return setStatus(kind .. " link is unavailable", Theme.Warning) end
            if type(setclipboard) == "function" then
                local ok = pcall(setclipboard, url)
                return setStatus(ok and (kind .. " link copied") or ("Unable to copy " .. kind:lower() .. " link"), ok and Theme.Success or Theme.Warning)
            end
            setStatus(url, Theme.Accent)
        end

        local getKey = new("TextButton", {
            Size = UDim2.new(0.5, -5, 1, 0),
            BackgroundColor3 = Theme.AccentSoft,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = Theme.Text,
            Text = tostring(config.GetKeyText or "GET KEY"),
            AutoButtonColor = false,
            ZIndex = 103,
        }, btnRow)
        round(getKey, UDim.new(0, 10))
        local getKeyEdge = outline(getKey, Theme.Accent, 1)
        local getKeyScale = new("UIScale", { Scale = 1 }, getKey)
        bind(getKey.MouseEnter, function()
            glide(getKey, { BackgroundColor3 = Theme.Accent }, 0.12)
            glide(getKeyEdge, { Color = Theme.Text }, 0.12)
            glide(getKeyScale, { Scale = 1.01 }, 0.12)
        end)
        bind(getKey.MouseLeave, function()
            glide(getKey, { BackgroundColor3 = Theme.AccentSoft }, 0.12)
            glide(getKeyEdge, { Color = Theme.Accent }, 0.12)
            glide(getKeyScale, { Scale = 1 }, 0.12)
        end)
        bind(getKey.Activated, function()
            copyAccessLink("Get key", config.GetKeyUrl, config.OnGetKey)
        end)

        local discord = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 0),
            Size = UDim2.new(0.5, -5, 1, 0),
            BackgroundColor3 = Theme.Raised,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = Theme.SubText,
            Text = tostring(config.DiscordText or "DISCORD"),
            AutoButtonColor = false,
            ZIndex = 103,
        }, btnRow)
        round(discord, UDim.new(0, 10))
        local discordEdge = outline(discord, Theme.Line, 1)
        local discordScale = new("UIScale", { Scale = 1 }, discord)
        bind(discord.MouseEnter, function()
            glide(discord, { BackgroundColor3 = Theme.AccentSoft, TextColor3 = Theme.Text }, 0.12)
            glide(discordEdge, { Color = Theme.Accent }, 0.12)
            glide(discordScale, { Scale = 1.01 }, 0.12)
        end)
        bind(discord.MouseLeave, function()
            glide(discord, { BackgroundColor3 = Theme.Raised, TextColor3 = Theme.SubText }, 0.12)
            glide(discordEdge, { Color = Theme.Line }, 0.12)
            glide(discordScale, { Scale = 1 }, 0.12)
        end)
        bind(discord.Activated, function()
            copyAccessLink("Discord", config.DiscordUrl, config.OnDiscord)
        end)

        -- ===== slim stats strip (executor / device / game / ping / session) =====
        local function detectExecutor()
            if type(identifyexecutor) == "function" then
                local ok, name = pcall(identifyexecutor)
                if ok and type(name) == "string" and name ~= "" then
                    return name
                end
            end
            local env = (type(getgenv) == "function" and getgenv()) or _G
            if type(env.syn) == "table" then return "Synapse X" end
            if type(env.http_request) == "function" or type(request) == "function" then return "Executor" end
            return "Unknown"
        end

        local function detectDevice()
            if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
                return "Mobile"
            end
            if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
                return "Console"
            end
            return "PC"
        end

        local function detectGame()
            local ok, name = pcall(function() return game.Name end)
            if ok and type(name) == "string" and name ~= "" then return name end
            return "Unknown"
        end

        spacer(13, 18)
        new("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.LineSoft,
            BorderSizePixel = 0,
            LayoutOrder = 14,
        }, col)
        spacer(15, 10)

        local statsRow = new("Frame", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
            LayoutOrder = 16,
            ZIndex = 102,
        }, col)
        stack(statsRow, 12, Enum.FillDirection.Horizontal)
        local statCells = {}

        local function statCell(caption)
            local cell = new("Frame", {
                Size = promptCompact and UDim2.new(1 / 3, -8, 1, 0) or UDim2.new(0.2, -10, 1, 0),
                BackgroundTransparency = 1,
                Visible = not promptCompact or caption == "DEVICE" or caption == "PING" or caption == "SESSION",
                ZIndex = 103,
            }, statsRow)
            statCells[caption] = cell
            new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 10),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 8,
                TextColor3 = Theme.Faint,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = caption,
                ZIndex = 103,
            }, cell)
            return new("TextLabel", {
                Position = UDim2.fromOffset(0, 12),
                Size = UDim2.new(1, 0, 0, 15),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = "--",
                ZIndex = 103,
            }, cell)
        end

        statCell("EXECUTOR").Text = detectExecutor()
        statCell("DEVICE").Text = detectDevice()
        statCell("GAME").Text = detectGame()
        local gatePing = statCell("PING")
        local gateSession = statCell("SESSION")
        local promptStarted = os.clock()
        local function refreshDiagnostics()
            local pingOk, ping = pcall(function() return LocalPlayer:GetNetworkPing() end)
            gatePing.Text = pingOk and (math.floor(ping * 1000 + 0.5) .. " ms") or "--"
            local elapsed = math.floor(os.clock() - promptStarted)
            gateSession.Text = elapsed >= 60 and string.format("%dm %02ds", math.floor(elapsed / 60), elapsed % 60)
                or (tostring(elapsed) .. "s")
        end
        refreshDiagnostics()

        local function refitPrompt()
            local view = Root.AbsoluteSize
            if view.X < 1 then return end
            local width = math.clamp(view.X - 24, 320, 560)
            local height = math.max(280, math.min(560, view.Y - 24))
            promptCompact = width < 440
            colMargin = promptCompact and 18 or 35
            host.Size = UDim2.fromOffset(width, height)
            host.Position = UDim2.fromScale(0.5, 0.5)
            col.Position = UDim2.fromOffset(colMargin, 70)
            col.Size = UDim2.new(1, -colMargin * 2, 1, -88)
            col.ScrollBarThickness = promptCompact and 2 or 3
            onlineChip.Size = UDim2.fromOffset(promptCompact and 76 or 96, 24)
            promptTitle.TextSize = promptCompact and 22 or 26
            inputRow.Size = UDim2.new(1, 0, 0, promptCompact and 100 or 46)
            input.Size = promptCompact and UDim2.new(1, 0, 0, 44) or UDim2.new(1, -282, 1, 0)
            paste.AnchorPoint = promptCompact and Vector2.new(0, 0) or Vector2.new(1, 0)
            paste.Position = promptCompact and UDim2.fromOffset(0, 54) or UDim2.new(1, -190, 0, 0)
            paste.Size = UDim2.fromOffset(82, promptCompact and 44 or 46)
            redeem.AnchorPoint = promptCompact and Vector2.new(0, 0) or Vector2.new(1, 0)
            redeem.Position = promptCompact and UDim2.fromOffset(92, 54) or UDim2.new(1, 0, 0, 0)
            redeem.Size = promptCompact and UDim2.new(1, -92, 0, 44) or UDim2.fromOffset(180, 46)
            for caption, cell in pairs(statCells) do
                cell.Size = promptCompact and UDim2.new(1 / 3, -8, 1, 0) or UDim2.new(0.2, -10, 1, 0)
                cell.Visible = not promptCompact or caption == "DEVICE" or caption == "PING" or caption == "SESSION"
            end
        end
        local resizeConn = Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(refitPrompt)

        task.spawn(function()
            while host.Parent do
                task.wait(1)
                if host.Parent then refreshDiagnostics() end
            end
        end)

        local validating = false
        local function setValidationBusy(state)
            validating = state and true or false
            input.TextEditable = not validating
            redeem.Active = not validating
            paste.Active = not validating
            redeem.Text = validating and tostring(config.CheckingText or "CHECKING…") or tostring(config.RedeemText or "REDEEM")
            redeem.TextTransparency = validating and 0.15 or 0
            glide(redeem, { BackgroundTransparency = validating and 0.18 or 0 }, 0.1)
        end

        local function attempt()
            if validating then return false end
            local key = tostring(input.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if type(config.KeyTransform) == "function" then
                local transformed, value = pcall(config.KeyTransform, key)
                if not transformed then return setStatus("Key formatting failed", Theme.Warning) end
                key = tostring(value or "")
            end
            if key == "" then
                setStatus("Enter a key before redeeming", Theme.Warning)
                pcall(function() input:CaptureFocus() end)
                return false
            end
            local minimum = math.max(1, math.floor(tonumber(config.MinKeyLength) or 1))
            if #key < minimum then
                setStatus("Key must contain at least " .. minimum .. " characters", Theme.Warning)
                pcall(function() input:CaptureFocus() end)
                return false
            end
            input.Text = key
            setValidationBusy(true)
            setStatus("Checking your key…", Theme.Accent)

            local ok, reason, expiry = true, nil, nil
            if type(config.Validate) == "function" then
                local ran
                ran, ok, reason, expiry = pcall(config.Validate, key)
                if not ran then
                    ok, reason = false, "Validation service failed"
                elseif type(ok) == "table" then
                    local response = ok
                    ok = response.Success == true or response.Valid == true
                    reason = response.Reason or response.Message or reason
                    expiry = response.Expiry or expiry
                end
            end
            if ok == true then
                setStatus("Key accepted", Theme.Success)
                if type(config.OnAccept) == "function" then
                    pcall(config.OnAccept, key, expiry)
                end
                finish(true)
                return true
            end

            local displayReason = reason or "Invalid key"
            if type(config.ReasonText) == "function" then
                local ran, text = pcall(config.ReasonText, reason)
                if ran and text ~= nil then displayReason = text end
            end
            setValidationBusy(false)
            setStatus(tostring(displayReason), Theme.Danger)
            if type(config.OnReject) == "function" then pcall(config.OnReject, key, reason) end
            return false
        end

        bind(redeem.Activated, attempt)
        bind(input.FocusLost, function(enter)
            if enter and config.SubmitOnEnter ~= false then attempt() end
        end)

        local escConn
        escConn = UserInputService.InputBegan:Connect(function(inputEvent)
            if config.CloseOnEscape ~= false and inputEvent.KeyCode.Name == "Escape" and host.Parent then
                escConn:Disconnect()
                finish(false)
            end
        end)

        task.defer(function()
            if config.AutoFocus ~= false and host.Parent then pcall(function() input:CaptureFocus() end) end
        end)

        completion.Event:Wait()
        completion:Destroy()
        if hostRemovedConn.Connected then hostRemovedConn:Disconnect() end
        if resizeConn.Connected then resizeConn:Disconnect() end
        if escConn.Connected then escConn:Disconnect() end
        return result == true
    end

    -- ===== config system (used through SaveManager) =====
    local function fileApi()
        if type(writefile) ~= "function" or type(readfile) ~= "function" then
            return nil
        end
        local api = {}
        function api.write(name, data) writefile(name, data) end
        function api.read(name) return readfile(name) end
        function api.remove(name)
            if type(delfile) ~= "function" then return false end
            return pcall(delfile, name)
        end
        function api.list()
            if type(listfiles) ~= "function" then return {} end
            local ok, files = pcall(listfiles, configFolder)
            if ok and type(files) == "table" then return files end
            return {}
        end
        return api
    end

    local function ensureFolder()
        if type(makefolder) ~= "function" then return true end
        if type(isfolder) ~= "function" then
            pcall(makefolder, configFolder)
            return true
        end
        local path = ""
        for part in configFolder:gmatch("[^/\\]+") do
            path = path == "" and part or (path .. "/" .. part)
            if not isfolder(path) then
                local ok = pcall(makefolder, path)
                if not ok then return false end
            end
        end
        return true
    end

    local function configName(value)
        local name = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        name = name:gsub("%.%.", ""):gsub("[/\\:*?\"<>|]", "_")
        return name
    end

    local function collect()
        local dump = { version = 2, savedAt = os.time(), toggles = {}, options = {} }
        local ignore = Lib.ConfigIgnoreIndexes
        for index, Toggle in pairs(Lib.Toggles) do
            if not Toggle.NoSave and not (ignore and table.find(ignore, index)) then
                dump.toggles[index] = Toggle.Value and true or false
            end
        end
        for index, Option in pairs(Lib.Options) do
            if not Option.NoSave and not (ignore and table.find(ignore, index)) then
                if Option.Type == "ColorPicker" then
                    dump.options[index] = { Option.Value.R, Option.Value.G, Option.Value.B }
                else
                    dump.options[index] = Option.Value
                end
            end
        end
        return dump
    end

    local function restore(dump)
        if type(dump) ~= "table" then return end
        if type(dump.toggles) == "table" then
            for index, value in pairs(dump.toggles) do
                local Toggle = Lib.Toggles[index]
                if Toggle then Toggle:SetValue(value) end
            end
        end
        if type(dump.options) == "table" then
            for index, value in pairs(dump.options) do
                local Option = Lib.Options[index]
                if Option then
                    if Option.Type == "ColorPicker" and type(value) == "table" then
                        Option:SetValue(Color3.new(value[1] or 0, value[2] or 0, value[3] or 0))
                    elseif Option.Type ~= "ColorPicker" then
                        Option:SetValue(value)
                    end
                end
            end
        end
    end

    function Lib:SaveConfig(name)
        local api = fileApi()
        name = configName(name)
        if not api or name == "" or not ensureFolder() then return false end
        local ok, encoded = pcall(function() return HttpService:JSONEncode(collect()) end)
        if not ok then return false end
        return pcall(api.write, configFolder .. "/" .. name .. ".json", encoded)
    end

    function Lib:LoadConfig(name)
        local api = fileApi()
        name = configName(name)
        if not api or name == "" then return false end
        local ok, raw = pcall(api.read, configFolder .. "/" .. name .. ".json")
        if not ok or type(raw) ~= "string" or raw == "" then return false end
        local parsed, dump = pcall(function() return HttpService:JSONDecode(raw) end)
        if not parsed then return false end
        restore(dump)
        return true
    end

    function Lib:ListConfigs()
        local api = fileApi()
        local out = {}
        if not api then return out end
        for _, file in ipairs(api.list()) do
            local name = tostring(file):match("([^/\\]+)%.json$")
            if name then table.insert(out, name) end
        end
        table.sort(out)
        return out
    end

    function Lib:ExportConfig()
        local ok, encoded = pcall(function() return HttpService:JSONEncode(collect()) end)
        return ok and encoded or nil
    end

    function Lib:ImportConfig(encoded)
        if type(encoded) ~= "string" or encoded == "" then return false end
        local ok, dump = pcall(function() return HttpService:JSONDecode(encoded) end)
        if not ok or type(dump) ~= "table" then return false end
        restore(dump)
        return true
    end

    function Lib:ConfigExists(name)
        name = configName(name)
        if name == "" or type(isfile) ~= "function" then return false end
        local ok, exists = pcall(isfile, configFolder .. "/" .. name .. ".json")
        return ok and exists == true
    end

    function Lib:DeleteConfig(name)
        local api = fileApi()
        name = configName(name)
        if not api or name == "" then return false end
        return api.remove(configFolder .. "/" .. name .. ".json")
    end

    function Lib:GetAutoloadConfig()
        local api = fileApi()
        if not api then return nil end
        local ok, name = pcall(api.read, configFolder .. "/autoload.txt")
        name = ok and configName(name) or ""
        return name ~= "" and name or nil
    end

    function Lib:SetAutoloadConfig(name)
        local api = fileApi()
        name = configName(name)
        if not api or name == "" or not ensureFolder() then return false end
        return pcall(api.write, configFolder .. "/autoload.txt", name)
    end

    function Lib:ClearAutoloadConfig()
        local api = fileApi()
        if not api then return false end
        return api.remove(configFolder .. "/autoload.txt")
    end

    function Lib:GetConfigFolder()
        return configFolder
    end

    function Lib:SetConfigFolder(name)
        local folder = tostring(name or "UxosuimStudio"):gsub("[/\\]+$", "")
        configFolder = folder ~= "" and folder or "UxosuimStudio"
        return self
    end

    function Lib:LoadAutoloadConfig()
        local api = fileApi()
        if not api then return false end
        local ok, name = pcall(api.read, configFolder .. "/autoload.txt")
        name = ok and configName(name) or ""
        if name == "" then return false end
        return Lib:LoadConfig(name)
    end

    function Lib:BuildConfigSection(tab)
        local group = tab:AddRightGroupbox("Configuration")
        local api = fileApi()

        local nameBox = group:AddInput("ConfigName", { Text = "Config name", Default = "config", Placeholder = "config name", NoSave = true })
        local list = group:AddDropdown("ConfigList", { Text = "Saved configs", Values = Lib:ListConfigs(), NoSave = true })

        group:AddButton({ Text = "Create config", Func = function()
            if not api then return Lib:Notify("Your executor has no file support") end
            local name = configName(nameBox.Value)
            if name == "" then return Lib:Notify("Type a config name first") end
            if not Lib:SaveConfig(name) then return Lib:Notify("Could not save config " .. name) end
            list:SetValues(Lib:ListConfigs())
            list:SetValue(name)
            Lib:Notify("Saved config " .. name)
        end })

        group:AddButton({ Text = "Load config", Func = function()
            local name = list.Value
            if not name then return Lib:Notify("Select a config to load") end
            if Lib:LoadConfig(name) then
                Lib:Notify("Loaded config " .. name)
            else
                Lib:Notify("Could not load config " .. name)
            end
        end })

        group:AddButton({ Text = "Delete config", Func = function()
            local name = configName(list.Value)
            if name == "" or not api then return Lib:Notify("Select a config to delete") end
            if not api.remove(configFolder .. "/" .. name .. ".json") then
                return Lib:Notify("Could not delete config " .. name)
            end
            list:SetValues(Lib:ListConfigs())
            list:SetValue(nil)
            Lib:Notify("Deleted config " .. name)
        end })

        local autoLabel = group:AddLabel("Autoload: none")

        group:AddButton({ Text = "Set as autoload", Func = function()
            local name = configName(list.Value)
            if not api or name == "" then return Lib:Notify("Select a config first") end
            if not ensureFolder() or not pcall(api.write, configFolder .. "/autoload.txt", name) then
                return Lib:Notify("Could not set autoload")
            end
            autoLabel:SetText("Autoload: " .. name)
            Lib:Notify("Autoload set to " .. name)
        end })

        group:AddButton({ Text = "Clear autoload", Func = function()
            if not api then return Lib:Notify("Your executor has no file support") end
            if not api.remove(configFolder .. "/autoload.txt") then
                return Lib:Notify("Could not clear autoload")
            end
            autoLabel:SetText("Autoload: none")
            Lib:Notify("Autoload cleared")
        end })

        if api then
            local ok, current = pcall(api.read, configFolder .. "/autoload.txt")
            current = ok and configName(current) or ""
            if current ~= "" then autoLabel:SetText("Autoload: " .. current) end
        end
        return group
    end

    function Lib:Unload()
        if Lib.Unloaded then return false end
        Lib.Unloaded = true
        closePopups()
        TipCard.Visible = false
        if captureConnection then
            captureConnection:Disconnect()
            captureConnection = nil
        end
        for _, fn in ipairs(unloadCallbacks) do pcall(fn) end
        for _, link in ipairs(conns) do pcall(function() link:Disconnect() end) end
        for _, tween in pairs(activeTweens) do pcall(function() tween:Cancel() end) end
        table.clear(conns)
        table.clear(unloadCallbacks)
        table.clear(activeNotifications)
        table.clear(Lib.Controls)
        table.clear(Lib.Options)
        table.clear(Lib.Toggles)
        table.clear(pickers)
        table.clear(pages)
        activeTweens = setmetatable({}, { __mode = "k" })
        Lib.Window = nil
        Lib.ToggleKeybind = nil
        if Root.Parent then Root:Destroy() end
        return true
    end

    return Lib
end)()
local Options = Library.Options
local Toggles = Library.Toggles

-- Linoria-style managers the studio script expects. The purple Uxosuim Studio look
-- is fixed by design, so ThemeManager only records the settings; the
-- SaveManager wraps the library config system.
local ThemeManager = {}
function ThemeManager:SetLibrary(lib) self.Library = lib or Library return self end
function ThemeManager:GetLibrary() return self.Library or Library end
function ThemeManager:SetFolder(name) self.Folder = tostring(name or "UxosuimStudio") return self end
function ThemeManager:GetFolder() return self.Folder or "UxosuimStudio" end
function ThemeManager:ApplyToTab(tab) self.SettingsTab = tab return self end
function ThemeManager:GetTheme() return (self.Library or Library).Theme end
function ThemeManager:SetReducedMotion(state) (self.Library or Library):SetReducedMotion(state) return self end

local SaveManager = {}
function SaveManager:SetLibrary(lib) self.Library = lib or Library return self end
function SaveManager:GetLibrary() return self.Library or Library end
function SaveManager:SetFolder(name)
    (self.Library or Library):SetConfigFolder(name)
    return self
end
function SaveManager:GetFolder() return (self.Library or Library):GetConfigFolder() end
function SaveManager:IgnoreThemeSettings() return self end
function SaveManager:SetIgnoreIndexes(list) (self.Library or Library).ConfigIgnoreIndexes = list return self end
function SaveManager:BuildConfigSection(tab) return (self.Library or Library):BuildConfigSection(tab) end
function SaveManager:LoadAutoloadConfig() return (self.Library or Library):LoadAutoloadConfig() end
function SaveManager:Save(name) return (self.Library or Library):SaveConfig(name) end
function SaveManager:Load(name) return (self.Library or Library):LoadConfig(name) end
function SaveManager:Delete(name) return (self.Library or Library):DeleteConfig(name) end
function SaveManager:List() return (self.Library or Library):ListConfigs() end
function SaveManager:Export() return (self.Library or Library):ExportConfig() end
function SaveManager:Import(data) return (self.Library or Library):ImportConfig(data) end
function SaveManager:SetAutoload(name) return (self.Library or Library):SetAutoloadConfig(name) end
function SaveManager:GetAutoload() return (self.Library or Library):GetAutoloadConfig() end
function SaveManager:ClearAutoload() return (self.Library or Library):ClearAutoloadConfig() end

-- Key status for the player card, read from the ticket the Uxosuim Studio
-- key-system bot sets on the generated script:
--   getgenv().SCRIPT_KEY      = "UXOSUIM-STUDIO-<id>-<expiry-hex>-<sig>"
--   getgenv().SCRIPT_KEY_TYPE = "24h" | "week" | "month" | "lifetime"
-- Older bot builds send no SCRIPT_KEY_TYPE: the tier is then
-- bucketed from the time left on the ticket.
local function scriptKeyInfo()
    local overrideType, overrideExpiry = Library.KeyTypeOverride, Library.KeyExpiryOverride
    if overrideType or overrideExpiry then
        if not overrideType then
            local left = overrideExpiry and (overrideExpiry - os.time()) or 0
            overrideType = left <= 2 * 86400 and "24h" or (left <= 8 * 86400 and "week" or "month")
        end
        return { Type = overrideType, Expiry = overrideExpiry }
    end
    local genv = (type(getgenv) == "function" and getgenv()) or _G
    local key = genv.SCRIPT_KEY
    if type(key) ~= "string" or not key:match("^UXOSUIM%-STUDIO%-") then
        return { Type = "keyless" }
    end
    local hex = key:match("^UXOSUIM%-STUDIO%-[A-Z2-7]+%-(%x+)%-[0-9A-F]+$")
    local expires = hex and tonumber(hex, 16) or nil
    local keyType = genv.SCRIPT_KEY_TYPE
    if keyType ~= "24h" and keyType ~= "week" and keyType ~= "month" and keyType ~= "lifetime" then
        local left = expires and (expires - os.time()) or 0
        keyType = left <= 2 * 86400 and "24h" or (left <= 8 * 86400 and "week" or "month")
    end
    return { Type = keyType, Expiry = expires }
end

Library.KeyInfo = scriptKeyInfo

return { Library = Library, ThemeManager = ThemeManager, SaveManager = SaveManager }
