local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FireRemote = ReplicatedStorage:WaitForChild("FireBulletRemote")

-- made this using raycast instead of roblox physics
-- physics can bug with fast objects so this feels more consistent

local Config = {
	Speed = 180,
	Gravity = Vector3.new(0, -25, 0),
	MaxDistance = 1000,
	Lifetime = 6,
	MaxBounces = 2,
	BulletSize = Vector3.new(0.3, 0.3, 2),
	BulletColor = Color3.fromRGB(255, 170, 0)
}

-- small helper so shots are not 100% perfect every time
local function applySpread(direction)
	local spread = 0.05
	local offset = Vector3.new(
		(math.random() - 0.5) * spread,
		(math.random() - 0.5) * spread,
		(math.random() - 0.5) * spread
	)
	return (direction + offset).Unit
end

-- basic class using metatable
local Bullet = {}
Bullet.__index = Bullet

function Bullet.new(origin, direction, owner)
	local self = setmetatable({}, Bullet)

	-- starting values
	self.Position = origin
	self.Direction = direction.Unit
	self.Velocity = self.Direction * Config.Speed
	self.Owner = owner

	self.DistanceTravelled = 0
	self.SpawnTime = tick()
	self.BounceCount = 0
	self.Active = true

	-- visual part only
	local part = Instance.new("Part")
	part.Size = Config.BulletSize
	part.Color = Config.BulletColor
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.new(origin, origin + direction)
	part.Parent = workspace

	self.Part = part

	-- simple trail so it looks nicer
	local att0 = Instance.new("Attachment")
	local att1 = Instance.new("Attachment")
	att0.Parent = part
	att1.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Parent = part

	self.Trail = trail

	return self
end

function Bullet:Destroy()
	-- just cleanup
	if self.Part then
		self.Part:Destroy()
	end
	self.Active = false
end

function Bullet:Reflect(normal)
	-- reflect velocity based on surface normal
	self.Velocity = self.Velocity - 2 * self.Velocity:Dot(normal) * normal
	self.Direction = self.Velocity.Unit
	self.BounceCount += 1
end

function Bullet:Update(dt)
	if not self.Active then return end

	local prevPos = self.Position

	-- manual gravity
	self.Velocity = self.Velocity + Config.Gravity * dt

	-- movement step
	local move = self.Velocity * dt
	local nextPos = prevPos + move

	-- raycast to avoid passing through objects
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {self.Part, self.Owner.Character}

	local result = workspace:Raycast(prevPos, move, params)

	if result then
		local hit = result.Instance
		local model = hit:FindFirstAncestorOfClass("Model")

		-- damage if humanoid
		if model and model:FindFirstChild("Humanoid") then
			model.Humanoid:TakeDamage(15)
			self:Destroy()
			return
		end

		-- bounce or destroy
		if self.BounceCount < Config.MaxBounces then
			self.Position = result.Position
			self:Reflect(result.Normal)
		else
			self:Destroy()
			return
		end
	else
		self.Position = nextPos
	end

	-- rotate to match direction
	if self.Velocity.Magnitude > 0.01 then
		self.Part.CFrame = CFrame.lookAt(self.Position, self.Position + self.Velocity)
	end

	-- track distance
	local dist = (self.Position - prevPos).Magnitude
	self.DistanceTravelled += dist

	if self.DistanceTravelled > Config.MaxDistance then
		self:Destroy()
	end

	-- lifetime limit
	if tick() - self.SpawnTime > Config.Lifetime then
		self:Destroy()
	end
end

-- manager to control all bullets
local BulletManager = {}
BulletManager.__index = BulletManager

function BulletManager.new()
	local self = setmetatable({}, BulletManager)
	self.ActiveBullets = {}
	return self
end

function BulletManager:Fire(origin, direction, player)
	local bullet = Bullet.new(origin, direction, player)
	table.insert(self.ActiveBullets, bullet)
end

function BulletManager:Update(dt)
	for i = #self.ActiveBullets, 1, -1 do
		local bullet = self.ActiveBullets[i]

		if bullet.Active then
			bullet:Update(dt)
		else
			table.remove(self.ActiveBullets, i)
		end
	end
end

local manager = BulletManager.new()

-- update loop
RunService.Heartbeat:Connect(function(dt)
	manager:Update(dt)
end)

-- cooldown so player can't spam too fast
local lastShot = 0
local cooldown = 0.2

-- tool to test everything
local function giveTool(player)
	local tool = Instance.new("Tool")
	tool.Name = "Launcher"
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1,1,2)
	handle.Parent = tool

	tool.Parent = player.Backpack
end

-- handle fire requests from the client (carries the world point the mouse is over)
FireRemote.OnServerEvent:Connect(function(player, targetPos)
	if typeof(targetPos) ~= "Vector3" then return end
	if tick() - lastShot < cooldown then return end
	lastShot = tick()

	local char = player.Character
	if not char then return end

	local head = char:FindFirstChild("Head")
	if not head then return end

	local origin = head.Position
	local direction = applySpread((targetPos - origin).Unit)

	manager:Fire(origin, direction, player)
end)

-- give tool when player joins
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		giveTool(player)
	end)
end)

-- for players already in game
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		giveTool(player)
	end
end
