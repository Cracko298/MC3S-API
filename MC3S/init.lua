local filesys = Core.Filesystem
local debug = Core.Debug
local memory = Core.Memory

local TextureModule = {}
local Texture = {}
Texture.__index = Texture

-- Precomputed Morton LUT for 8x8 tiles
local morton_lut = {}
for y = 0, 7 do
    morton_lut[y] = {}
    for x = 0, 7 do
        local m = 0
        if x % 2 == 1 then m = m + 1 end
        if y % 2 == 1 then m = m + 2 end
        if math.floor(x/2) % 2 == 1 then m = m + 4 end
        if math.floor(y/2) % 2 == 1 then m = m + 8 end
        if math.floor(x/4) % 2 == 1 then m = m + 16 end
        if math.floor(y/4) % 2 == 1 then m = m + 32 end
        morton_lut[y][x] = m
    end
end

local function bytes_to_int(str, offset)
    local b1, b2, b3, b4 = string.byte(str, offset + 1, offset + 4)
    return b1 + (b2 * 256) + (b3 * 65536) + (b4 * 16777216)
end

local function int_to_bytes(val)
    return string.char(val % 256, 
                       math.floor(val / 256) % 256, 
                       math.floor(val / 65536) % 256, 
                       math.floor(val / 16777216) % 256)
end

local function array_to_string(arr)
    local out = {}
    local chunk_size = 7000 
    for i = 1, #arr, chunk_size do
        local j = math.min(i + chunk_size - 1, #arr)
        out[#out+1] = string.char(unpack(arr, i, j))
    end
    return table.concat(out)
end

-- Syncs the binary header with current self.width and self.height
function Texture:_sync_header()
    local h = self.header
    self.header = h:sub(1, 12) .. int_to_bytes(self.width) .. 
                 h:sub(17, 16) .. int_to_bytes(self.height) .. 
                 h:sub(21)
end


-- load file

function TextureModule.load(input, w, h, is_tiled)
    local data
    local header = ""
    
    local success, file = pcall(filesys.open, input, "rb")
    if success and file then
        local full_content = file:read("*all")
        file:close()
        w = bytes_to_int(full_content, 0x0C)
        h = bytes_to_int(full_content, 0x10)
        header = full_content:sub(1, 0x20)
        data = full_content:sub(0x21)
    else
        if not w or not h then
            error("Dimensions required for raw bytes.")
        end
        data = input
        header = string.rep("\0", 12) .. int_to_bytes(w) .. string.rep("\0", 0) .. int_to_bytes(h) .. string.rep("\0", 12)
    end

    local self = setmetatable({}, Texture)
    self.width = w
    self.height = h
    self.header = header
    self.pixels = {}

    for i = 1, #data do self.pixels[i] = string.byte(data, i) end
    if is_tiled then self:_untile() end

    return self
end

function Texture:clone()
    local copy = setmetatable({}, Texture)
    copy.width = self.width
    copy.height = self.height
    copy.header = self.header
    copy.pixels = {}
    for i = 1, #self.pixels do copy.pixels[i] = self.pixels[i] end
    return copy
end

function Texture:rotate_90()
    local p = self.pixels
    local new_p = {}
    local old_w, old_h = self.width, self.height
    for y = 0, old_h - 1 do
        for x = 0, old_w - 1 do
            local srcIdx = (y * old_w + x) * 4
            local dstX = (old_h - 1) - y
            local dstY = x
            local dstIdx = (dstY * old_h + dstX) * 4
            for i = 1, 4 do new_p[dstIdx + i] = p[srcIdx + i] end
        end
    end
    self.pixels = new_p
    self.width = old_h
    self.height = old_w
    self:_sync_header()
    return self
end

function Texture:flip_vertical()
    local p = self.pixels
    local new_p = {}
    local w, h = self.width, self.height
    for y = 0, h - 1 do
        local dstY = h - 1 - y
        for x = 0, w - 1 do
            local srcIdx = (y * w + x) * 4
            local dstIdx = (dstY * w + x) * 4
            for i = 1, 4 do new_p[dstIdx + i] = p[srcIdx + i] end
        end
    end
    self.pixels = new_p
    return self
end

function Texture:flip_horizontal()
    local p = self.pixels
    local new_p = {}
    local w, h = self.width, self.height
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local srcIdx = (y * w + x) * 4
            local dstIdx = (y * w + (w - 1 - x)) * 4
            for i = 1, 4 do new_p[dstIdx + i] = p[srcIdx + i] end
        end
    end
    self.pixels = new_p
    return self
end

function Texture:color_shift(r, g, b, a)
    local p = self.pixels
    local shifts = {r or 0, g or 0, b or 0, a or 0}
    for i = 1, #p, 4 do
        for j = 1, 4 do
            p[i+j-1] = math.max(0, math.min(255, p[i+j-1] + shifts[j]))
        end
    end
    return self
end

function Texture:replace_region(other_tex, startX, startY)
    local p, op = self.pixels, other_tex.pixels
    local bw, bh = self.width, self.height
    local rw, rh = other_tex.width, other_tex.height
    for y = 0, rh - 1 do
        local dstY = startY + y
        if dstY >= 0 and dstY < bh then
            for x = 0, rw - 1 do
                local dstX = startX + x
                if dstX >= 0 and dstX < bw then
                    local dstIdx = (dstY * bw + dstX) * 4
                    local srcIdx = (y * rw + x) * 4
                    for i = 1, 4 do p[dstIdx + i] = op[srcIdx + i] end
                end
            end
        end
    end
    return self
end

function Texture:_untile()
    local linear = {}
    local w, h = self.width, self.height
    local tilesPerRow = math.floor(w / 8)
    local p = self.pixels
    for y = 0, h - 1 do
        local lutY = morton_lut[y % 8]
        local tileY = math.floor(y / 8)
        for x = 0, w - 1 do
            local tileIndex = tileY * tilesPerRow + math.floor(x / 8)
            local tiledIndex = (tileIndex * 64 + lutY[x % 8]) * 4
            local linearIndex = (y * w + x) * 4
            for i = 1, 4 do linear[linearIndex + i] = p[tiledIndex + i] end
        end
    end
    self.pixels = linear
end

function Texture:export_tiled()
    local tiled = {}
    local w, h = self.width, self.height
    local tilesPerRow = math.floor(w / 8)
    local p = self.pixels
    for y = 0, h - 1 do
        local lutY = morton_lut[y % 8]
        local tileY = math.floor(y / 8)
        for x = 0, w - 1 do
            local tileIndex = tileY * tilesPerRow + math.floor(x / 8)
            local tiledIndex = (tileIndex * 64 + lutY[x % 8]) * 4
            local linearIndex = (y * w + x) * 4
            for i = 1, 4 do tiled[tiledIndex + i] = p[linearIndex + i] end
        end
    end
    return self.header .. array_to_string(tiled)
end

return TextureModule
