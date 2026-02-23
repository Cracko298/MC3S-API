local filesys = Core.Filesystem
local debug = Core.Debug
local memory = Core.Memory
local texture = {}

-- File Helper
local function read_texture_file(path)
    local f = assert(filesys.open(path, "rb"))
    local d = f:read("*all")
    f:close()
    return d:sub(0x20 + 1)
end

-- Morton Helpers
local function part1by1(n)
    n = n % 8
    n = (n + n * 4) % 256
    n = n % 0x33
    n = (n + n * 2) % 256
    n = n % 0x55
    return n
end

local function morton2D(x, y)
    return part1by1(x) + part1by1(y) * 2
end

-- Tiled Index (Morton)
local function get_tiled_index(x, y, width)
    local tileX = math.floor(x / 8)
    local tileY = math.floor(y / 8)

    local tilesPerRow = math.floor(width / 8)
    local tileIndex = tileY * tilesPerRow + tileX

    local inTileX = x % 8
    local inTileY = y % 8

    local pixelIndexInTile = morton2D(inTileX, inTileY)

    return (tileIndex * 8 * 8 + pixelIndexInTile) * 4
end

-- Untile
function texture.untile(tiledData, width, height)
    local linear = {}

    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local tiledIndex = get_tiled_index(x, y, width)
            local linearIndex = (y * width + x) * 4

            linear[linearIndex + 1] = tiledData:sub(tiledIndex + 1, tiledIndex + 1)
            linear[linearIndex + 2] = tiledData:sub(tiledIndex + 2, tiledIndex + 2)
            linear[linearIndex + 3] = tiledData:sub(tiledIndex + 3, tiledIndex + 3)
            linear[linearIndex + 4] = tiledData:sub(tiledIndex + 4, tiledIndex + 4)
        end
    end

    return table.concat(linear)
end

-- Retile
function texture.retile(linearData, width, height)
    local tiled = {}

    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local linearIndex = (y * width + x) * 4
            local tiledIndex = get_tiled_index(x, y, width)

            tiled[tiledIndex + 1] = linearData:sub(linearIndex + 1, linearIndex + 1)
            tiled[tiledIndex + 2] = linearData:sub(linearIndex + 2, linearIndex + 2)
            tiled[tiledIndex + 3] = linearData:sub(linearIndex + 3, linearIndex + 3)
            tiled[tiledIndex + 4] = linearData:sub(linearIndex + 4, linearIndex + 4)
        end
    end

    return table.concat(tiled)
end

-- Replace region (Linear)
function texture.replace_region_linear(baseData, baseW, baseH,
                                       replaceData, repW, repH,
                                       startX, startY)

    local result = { baseData:byte(1, #baseData) }

    for y = 0, repH - 1 do
        for x = 0, repW - 1 do

            local dstX = startX + x
            local dstY = startY + y

            if dstX < baseW and dstY < baseH then
                local dstIndex = (dstY * baseW + dstX) * 4
                local srcIndex = (y * repW + x) * 4

                result[dstIndex + 1] = replaceData:byte(srcIndex + 1)
                result[dstIndex + 2] = replaceData:byte(srcIndex + 2)
                result[dstIndex + 3] = replaceData:byte(srcIndex + 3)
                result[dstIndex + 4] = replaceData:byte(srcIndex + 4)
            end
        end
    end

    return string.char(unpack(result))
end

-- Replace region (TiledIn into TiledOut)
function texture.replace_region(baseInput, baseW, baseH,
                                replaceInput, repW, repH,
                                startX, startY,
                                isFileBase, isFileReplace)

    local baseData = isFileBase and read_texture_file(baseInput) or baseInput
    local replaceData = isFileReplace and read_texture_file(replaceInput) or replaceInput

    local baseLinear = texture.untile(baseData, baseW, baseH)
    local replaceLinear = texture.untile(replaceData, repW, repH)

    local modifiedLinear = texture.replace_region_linear(
        baseLinear, baseW, baseH,
        replaceLinear, repW, repH,
        startX, startY
    )

    return texture.retile(modifiedLinear, baseW, baseH)
end

return texture