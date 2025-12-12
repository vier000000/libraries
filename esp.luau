-- rewrite of https://sirius.menu/sense

local run_service = game:GetService("RunService")
local players = game:GetService("Players")

local local_player = players.LocalPlayer
local current_camera = workspace.CurrentCamera

local viewport_size = current_camera.ViewportSize

local container = Instance.new("Folder", gethui())

local floor = math.floor
local round = math.round
local sin = math.sin
local cos = math.cos
local clear = table.clear
local unpack = table.unpack
local find = table.find
local create = table.create
local from_matrix = CFrame.fromMatrix

local world_to_viewport_point = current_camera.WorldToViewportPoint
local is_a = workspace.IsA
local get_pivot = workspace.GetPivot
local find_first_child = workspace.FindFirstChild
local find_first_child_of_class = workspace.FindFirstChildOfClass
local get_children = workspace.GetChildren
local to_orientation = CFrame.identity.ToOrientation
local point_to_object_space = CFrame.identity.PointToObjectSpace
local lerp_color3 = Color3.new().Lerp
local min_vector2 = Vector2.zero.Min
local max_vector2 = Vector2.zero.Max
local lerp_vector2 = Vector2.zero.Lerp
local min_vector3 = Vector3.zero.Min
local max_vector3 = Vector3.zero.Max

local HEALTH_BAR_OFFSET = Vector2.new(5, 0)
local HEALTH_TEXT_OFFSET = Vector2.new(3, 0)
local HEALTH_BAR_OUTLINE_OFFSET = Vector2.new(0, 1)
local NAME_OFFSET = Vector2.new(0, 2)
local DISTANCE_OFFSET = Vector2.new(0, 2)
local VERTICES = {
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(-1, -1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
	Vector3.new(1, -1, 1)
}

local function is_body_part(name)
    return name == "Head" or name:find("Torso") or name:find("Leg") or name:find("Arm")
end

local function get_bounding_box(parts)
    local minimum = nil
    local maximum = nil

    for index = 1, #parts do
        local part = parts[index]
        
        local cframe = part.CFrame
        local size = part.Size

        minimum = min_vector3(minimum or cframe.Position, (cframe - size * 0.5).Position)
        maximum = max_vector3(maximum or cframe.Position, (cframe + size * 0.5).Position)
    end

    local center = (minimum + maximum) * 0.5
    local front = Vector3.new(center.X, center.Y, maximum.Z)

    return CFrame.new(center, front), maximum - minimum
end

local function world_to_screen(world)
    local screen_position, on_screen = world_to_viewport_point(current_camera, world)

    return Vector2.new(screen_position.X, screen_position.Y), on_screen, screen_position.Z
end

local function calculate_corners(cframe, size)
    local corners = create(#VERTICES)

    for index = 1, #VERTICES do
        corners[index] = world_to_screen((cframe + size * 0.5 * VERTICES[index]).Position)
    end

    local minimum = min_vector2(viewport_size, unpack(corners))
    local maximum = max_vector2(Vector2.zero, unpack(corners))

    return {
        corners = corners,
        top_left = Vector2.new(floor(minimum.X), floor(minimum.Y)),
		top_right = Vector2.new(floor(maximum.X), floor(minimum.Y)),
		bottom_left = Vector2.new(floor(minimum.X), floor(maximum.Y)),
		bottom_right = Vector2.new(floor(maximum.X), floor(maximum.Y))
    }
end

local function rotate_vector(vector, radians)
    local x = vector.X
    local y = vector.Y

    local c = cos(radians)
    local s = sin(radians)

    return Vector2.new(x * c - y * s, x * s + y * c)
end

local function parse_color(self, color, is_outline)
    if color == "Team Color" or (self.interface.shared_settings.use_team_color and not is_outline) then
        return self.interface.get_team_color(self.player) or Color3.new(1, 1, 1)
    end

    return color
end

local esp_object = {} do
    esp_object.__index = esp_object

    function esp_object.new(player, interface)
        local self = setmetatable({}, esp_object)

        self.player = assert(player, "Argument #1 -> Player Expected")
        self.interface = assert(interface, "Argument #2 -> Table Expected")

        self:construct()

        return self
    end

    function esp_object:draw_object(object, properties)
        local drawing = Drawing.new(object)

        for property, value in properties do
            drawing[property] = value
        end

        self.bin[#self.bin + 1] = drawing

        return drawing
    end

    function esp_object:construct()
        self.character_cache = {}
        self.child_count = 0
        self.bin = {}
        self.drawings = {
            box_3d = {
                {self:draw_object("Line", {Thickness = 1, Visible = false}), self:draw_object("Line", {Thickness = 1, Visible = false}), self:draw_object("Line", {Thickness = 1, Visible = false})},
                {self:draw_object("Line", {Thickness = 1, Visible = false}), self:draw_object("Line", {Thickness = 1, Visible = false}), self:draw_object("Line", {Thickness = 1, Visible = false})},
                {self:draw_object("Line", {Thickness = 1, Visible = false}), self:draw_object("Line", {Thickness = 1, Visible = false}), self:draw_object("Line", {Thickness = 1, Visible = false})},
                {self:draw_object("Line", {Thickness = 1, Visible = false}), self:draw_object("Line", {Thickness = 1, Visible = false}), self:draw_object("Line", {Thickness = 1, Visible = false})}
            },
		    visible = {
			    tracer_outline = self:draw_object("Line", { Thickness = 3, Visible = false }),
			    tracer = self:draw_object("Line", { Thickness = 1, Visible = false }),
			    box_fill = self:draw_object("Square", { Filled = true, Visible = false }),
			    box_outline = self:draw_object("Square", { Thickness = 3, Visible = false }),
			    box = self:draw_object("Square", { Thickness = 1, Visible = false }),
			    health_bar_outline = self:draw_object("Line", { Thickness = 3, Visible = false }),
			    health_bar = self:draw_object("Line", { Thickness = 1, Visible = false }),
			    health_text = self:draw_object("Text", { Center = true, Visible = false }),
			    name = self:draw_object("Text", { Text = self.player.DisplayName, Center = true, Visible = false }),
			    distance = self:draw_object("Text", { Center = true, Visible = false }),
			    weapon = self:draw_object("Text", { Center = true, Visible = false }),
		    },
		    hidden = {
			    arrow_outline = self:draw_object("Triangle", { Thickness = 3, Visible = false }),
			    arrow = self:draw_object("Triangle", { Filled = true, Visible = false })
		    }
        }

        self.render_connection = run_service.Heartbeat:Connect(function(delta_time)
            self:update(delta_time)
            self:render(delta_time)
        end)
    end

    function esp_object:destruct()
        self.render_connection:Disconnect()

        for index = 1, #self.bin do
            self.bin[index]:Destroy()
        end

        clear(self)
    end

    function esp_object:update()
        local interface = self.interface

        self.options = interface.team_settings[interface.is_friendly(self.player) and "friendly" or "enemy"]
        self.character = interface.get_character(self.player)
        self.health, self.max_health = interface.get_health(self.player)
        self.weapon = interface.get_weapon(self.player)
        self.enabled = self.options.enabled and self.character and not (#interface.whitelist > 0 and not find(interface.whitelist, self.player.UserId))

        local head = self.enabled and find_first_child(self.character, "Head")

        if not head then
            self.character_cache = {}
            self.on_screen = false

            return
        end

        local _, on_screen, depth = world_to_screen(head.Position)

        self.on_screen = on_screen
        self.distance = depth

        if interface.shared_settings.limit_distance and depth > interface.shared_settings.max_distance then
            self.on_screen = false
        end

        if self.on_screen then
            local character_cache = self.character_cache
            local children = get_children(self.character)

            if not character_cache[1] or self.child_count ~= #children then
                clear(character_cache)

                for index = 1, #children do
                    local part = children[index]

                    if is_a(part, "BasePart") and is_body_part(part.Name) then
                        character_cache[#character_cache + 1] = part
                    end
                end

                self.child_count = #children
            end

            self.corners = calculate_corners(get_bounding_box(character_cache))
        elseif self.options.off_screen_arrow then
            local cframe = current_camera.CFrame
            local flat = from_matrix(cframe.Position, cframe.RightVector, Vector3.yAxis)
            local object_space = point_to_object_space(flat, head.Position)

            self.direction = Vector2.new(object_space.X, object_space.Z).Unit
        end
    end

    function esp_object:render()
        local on_screen = self.on_screen or false
        local enabled = self.enabled or false
        local visible = self.drawings.visible
        local hidden = self.drawings.hidden
        local box3d = self.drawings.box_3d
        local interface = self.interface
        local options = self.options
        local corners = self.corners

        visible.box.Visible = enabled and on_screen and options.box
        visible.box_outline.Visible = visible.box.Visible and options.box_outline

        if visible.box.Visible then
            local box = visible.box
            local box_outline = visible.box_outline

            box.Position = corners.top_left
            box.Size = corners.bottom_right - corners.top_left
            box.Color = parse_color(self, options.box_color[1])
            box.Transparency = options.box_color[2]

            box_outline.Position = box.Position
            box_outline.Size = box.Size
            box_outline.Color = parse_color(self, options.box_outline_color[1], true)
            box_outline.Transparency = options.box_outline_color[2]
        end

        visible.box_fill.Visible = enabled and on_screen and options.box_fill

        if visible.box_fill.Visible then
            local box_fill = visible.box_fill

            box_fill.Postion = corners.top_left
            box_fill.Size = corners.bottom_right - corners.top_left
            box_fill.Color = parse_color(self, options.box_fill_color[1])
            box_fill.Transparency = options.box_fill_color[2]
        end

        visible.health_bar.Visible = enabled and on_screen and options.health_bar
        visible.health_bar_outline.Visible = visible.health_bar.Visible and options.health_bar_outline

        if visible.health_bar_visible then
            local bar_to = corners.bottom_left - HEALTH_BAR_OFFSET
            local bar_from = corners.top_left - HEALTH_BAR_OFFSET

            local health_bar = visible.health_bar
            local health_bar_outline = visible.health_bar_outline

            health_bar.To = bar_to
            health_bar.From = lerp_vector2(bar_to, bar_from, self.health / self.max_health)
            health_bar.Color = lerp_color3(options.dying_color, options.healthy_color, self.health / self.max_health)

            health_bar_outline.To = bar_to + HEALTH_BAR_OUTLINE_OFFSET
            health_bar_outline.From = bar_from - HEALTH_BAR_OUTLINE_OFFSET
            health_bar_outline.Color = parse_color(self, options.health_bar_outline_color[1], true)
            health_bar_outline.Transparency = options.health_bar_outline_color[2]
        end

        visible.health_text.Visible = enabled and on_screen and options.health_text

        if visible.health_text.Visible then
            local bar_to = corners.bottom_left - HEALTH_BAR_OFFSET
            local bar_from = corners.top_left - HEALTH_BAR_OFFSET

            local health_text = visible.health_text

            health_text.Text = round(self.health) .. "hp"
            health_text.Size = interface.shared_settings.text_size
            health_text.Font = interface.shared_settings.text_font
            health_text.Color = parse_color(self, options.health_text_color[1])
            health_text.Transparency = options.health_text_color[2]
            health_text.Outline = options.health_text_outline
            health_text.OutlineColor = parse_color(self, options.health_text_outline_color, true)
            health_text.Position = lerp_vector2(bar_to, bar_from, self.health / self.max_health) - health_text.TextBounds * 0.5 - HEALTH_TEXT_OFFSET
        end

        visible.name.Visible = enabled and on_screen and options.name

        if visible.name.Visible then
            local name = visible.name

            name.Size = interface.shared_settings.text_size
            name.Font = interface.shared_settings.text_font
            name.Color = parse_color(self, options.name_color[1])
            name.Transparency = options.name_color[2]
            name.Outline = options.name_outline
            name.OutlineColor = parse_color(self, options.name_outline_color, true)
            name.Position = (corners.top_left + corners.top_right) * 0.5 - Vector2.yAxis * name.TextBounds.Y - NAME_OFFSET
        end

        visible.distance.Visible = enabled and on_screen and self.distance and options.distance

        if visible.distance.Visible then
            local distance = visible.distance

            distance.Text = round(self.distance) .. " studs"
            distance.Size = interface.shared_settings.text_size
            distance.Font = interface.shared_settings.text_font
            distance.Color = parse_color(self, options.distance_color[1])
            distance.Transparency = options.distance_color[2]
            distance.Outline = options.distance_outline
            distance.OutlineColor = parse_color(self, options.distance_outline_color, true)
            distance.Position = (corners.bottom_left + corners.bottom_right) * 0.5 + DISTANCE_OFFSET
        end

        visible.weapon.Visible = enabled and on_screen and options.weapon

        if visible.weapon.Visible then
            local weapon = visible.weapon

            weapon.Text = self.weapon
            weapon.Size = interface.shared_settings.text_size
            weapon.Font = interface.shared_settings.text_font
            weapon.Color = parse_color(self, options.weapon_color[1])
            weapon.Transparency = options.weapon_color[2]
            weapon.Outline = options.weapon_outline
            weapon.OutlineColor = parse_color(self, options.weapon_outline_color, true)
            weapon.Position = (corners.bottom_left + corners.bottom_right) * 0.5 + (visible.distance.Visible and DISTANCE_OFFSET + Vector2.yAxis * visible.distance.TextBounds.Y or Vector2.zero)
        end

        visible.tracer.Visible = enabled and on_screen and options.tracer
        visible.tracer_outline.Visible = visible.tracer.Visible and options.tracer_outline

        if visible.tracer.Visible then
            local tracer = visible.tracer
            local tracer_outline = visible.tracer_outline

            tracer.Color = parse_color(self, options.tracer_color[1])
            tracer.Transparency = options.tracer_color[2]
            tracer.To = (corners.bottom_left + corners.bottom_right) * 0.5
            tracer.From = options.tracer_origin == "Middle" and viewport_size * 0.5 or options.tracer_origin == "Top" and viewport_size * Vector2.new(0.5, 0) or options.tracer_origin == "Bottom" and viewport_size * Vector2.new(0.5, 1)

            tracer_outline.Color = parse_color(self, options.tracer_outline_color[1], true)
            tracer_outline.Transparency = options.tracer_outline_color[2]
            tracer_outline.To = tracer.To
            tracer_outline.From = tracer.From
        end

        hidden.arrow.Visible = enabled and (not on_screen) and options.off_screen_arrow
        hidden.arrow_outline.Visible = hidden.arrow.Visible and options.off_screen_arrow_outline

        if hidden.arrow.Visible and self.direction then
            local arrow = hidden.arrow
            local arrow_outline = hidden.arrow_outline

            arrow.PointA = min_vector2(max_vector2(viewport_size * 0.5 + self.direction * options.off_screen_arrow_radius, Vector2.one * 25), viewport_size - Vector2.one * 25)
            arrow.PointB = arrow.PointA - rotate_vector(self.direction, 0.45) * options.off_screen_arrow_size
            arrow.PointC = arrow.PointA - rotate_vector(self.direction, -0.45) * options.off_screen_arrow_size
            arrow.Color = parse_color(self, options.off_screen_arrow_color[1])
            arrow.Transparency = options.off_screen_arrow_color[2]

            arrow_outline.PointA = arrow.PointA
            arrow_outline.PointB = arrow.PointB
            arrow_outline.PointC = arrow.PointC
            arrow_outline.Color = parse_color(self, options.off_screen_arrow_outline_color[1], true)
            arrow_outline.Transparency = options.off_screen_arrow_outline_color[2]
        end
    end
end

local esp_interface = {
    has_loaded = false,
    object_cache = {},
    whitelist = {},
    shared_settings = {
        text_size = 13,
        text_font = 2,
        limit_distance = false,
        max_distance = 150,
        use_team_color = false
    },
    team_settings = {
        enemy = {
            enabled = false,
            box = false,
            box_color = {Color3.new(1, 0, 0), 1},
            box_outline = true,
            box_outline_color = {Color3.new(), 1},
            box_fill = false,
            box_fill_color = {Color3.new(1, 0, 0), 0.5},
            health_bar = false,
            healthy_color = Color3.new(0, 1, 0),
            dying_color = Color3.new(1, 0, 0),
            health_bar_outline = true,
			health_bar_outline_color = {Color3.new(), 0.5},
			health_text = false,
			health_text_color = {Color3.new(1, 1, 1), 1},
			health_text_outline = true,
			health_text_outline_color = Color3.new(),
			name = false,
			name_color = {Color3.new(1, 1, 1), 1},
			name_outline = true,
			name_outline_color = Color3.new(),
			weapon = false,
			weapon_color = {Color3.new(1, 1, 1), 1},
			weapon_outline = true,
			weapon_outline_color = Color3.new(),
			distance = false,
			distance_color = {Color3.new(1, 1, 1), 1},
			distance_outline = true,
			distance_outline_color = Color3.new(),
			tracer = false,
			tracer_origin = "Bottom",
			tracer_color = {Color3.new(1, 0, 0), 1},
			tracer_outline = true,
			tracer_outline_color = {Color3.new(), 1},
			off_screen_arrow = false,
			off_screen_arrow_color = {Color3.new(1, 1, 1), 1},
			off_screen_arrow_size = 15,
			off_screen_arrow_radius = 150,
			off_screen_arrow_outline = true,
			off_screen_arrow_outline_color = {Color3.new(), 1}
        },
        friendly = {
            enabled = false,
            box = false,
            box_color = {Color3.new(0, 1, 0), 1},
            box_outline = true,
            box_outline_color = {Color3.new(), 1},
            box_fill = false,
            box_fill_color = {Color3.new(0, 1, 0), 0.5},
            health_bar = false,
            healthy_color = Color3.new(0, 1, 0),
            dying_color = Color3.new(1, 0, 0),
            health_bar_outline = true,
			health_bar_outline_color = {Color3.new(), 0.5},
			health_text = false,
			health_text_color = {Color3.new(1, 1, 1), 1},
			health_text_outline = true,
			health_text_outline_color = Color3.new(),
			name = false,
			name_color = {Color3.new(1, 1, 1), 1},
			name_outline = true,
			name_outline_color = Color3.new(),
			weapon = false,
			weapon_color = {Color3.new(1, 1, 1), 1},
			weapon_outline = true,
			weapon_outline_color = Color3.new(),
			distance = false,
			distance_color = {Color3.new(1, 1, 1), 1},
			distance_outline = true,
			distance_outline_color = Color3.new(),
			tracer = false,
			tracer_origin = "Bottom",
			tracer_color = {Color3.new(0, 1, 0), 1},
			tracer_outline = true,
			tracer_outline_color = {Color3.new(), 1},
			off_screen_arrow = false,
			off_screen_arrow_color = {Color3.new(1, 1, 1), 1},
			off_screen_arrow_size = 15,
			off_screen_arrow_radius = 150,
			off_screen_arrow_outline = true,
			off_screen_arrow_outline_color = {Color3.new(), 1}
        }
    }
} do
    function esp_interface.initialize()
        assert(not esp_interface.has_loaded, "ESP has already been initialized.")

        local function create_object(player)
            esp_interface.object_cache[player] = {
                esp_object.new(player, esp_interface)
            }
        end

        local function remove_object(player)
            local object = esp_interface.object_cache[player]

            if object then
                for index = 1, #object do
                    object[index]:Destruct()
                end

                esp_interface.object_cache[player] = nil
            end
        end

        for index = 2, #players:GetPlayers() do
            create_object(players:GetPlayers()[index])
        end

        esp_interface.player_added = players.PlayerAdded:Connect(create_object)
        esp_interface.player_removing = players.PlayerRemoving:Connect(remove_object)

        esp_interface.has_loaded = true
    end

    function esp_interface.deinitialize()
        assert(esp_interface.has_loaded, "ESP has not been initialized yet.")

        for player, object in esp_interface.object_cache do
            for index = 1, #object do
                object[index]:Destruct()
            end

            esp_interface.objectcache[player] = nil
        end

        esp_interface.player_added:Disconnect()
        esp_interface.player_removing:Disconnect()

        esp_interface.has_loaded = false
    end

    function esp_interface.get_weapon(player)
        return "Unknown"
    end

    function esp_interface.is_friendly(player)
        return player.Team and player.Team == local_player.Team
    end

    function esp_interface.get_team_color(player)
        return player.Team and player.Team.TeamColor and player.Team.TeamColor.Color
    end

    function esp_interface.get_character(player)
        return player.Character
    end

    function esp_interface.get_health(player)
        local character = player and esp_interface.get_character(player)
        local humanoid = character and find_first_child_of_class(character, "Humanoid")

        if humanoid then
            return humanoid.Health, humanoid.MaxHealth
        end

        return 100, 100
    end
end

return esp_interface
