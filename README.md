# MC3S-API
- MC3S is an API for Minecraft 3DS Skins in-real time. Allowing for for truly custom Skins, Textures, 2D Animations, and More using for use with LunaCore.
- Very early development, and I highly suggest not depending on it until a full release is well... released.

---

## API Reference(s):

### `TextureModule.load(input, [w], [h], [is_tiled])`
The main entry point. 
- `input`: Either a string file path or a string of raw bytes.
- `w/h`: Optional. Auto-read from header if a file is provided.
- `is_tiled`: Set to `true` to "untile" the data for editing.

### `:clone()`
Returns a completely independent copy of the texture object.

### `:rotate_90()`
Rotates the texture 90° clockwise. Updates internal width/height and the binary header metadata.

### `:flip_vertical()` / `:flip_horizontal()`
Flips the image across the specified axis.

### `:color_shift(r, g, b, a)`
Adds/subtracts values to color channels. 
- Example: `tex:color_shift(50, 0, 0, 0)` makes the image more red.
- Values are automatically clamped between 0 and 255.

### `:replace_region(other_tex, x, y)`
Stamps the contents of `other_tex` onto the current texture at coordinates `(x, y)`.

### `:export_tiled()`
Converts the pixels back into the 8x8 Morton format and prepends the 32-byte header.

---

## Example Usage

```lua
-- Load a tiled texture from the filesystem
-- (Dimensions are auto-extracted from header)
local skin = textureAPI.load("sdmc:/steve.3dst", nil, nil, true)

-- Load and prepare an icon
local helmet = textureAPI.load("sdmc:/helmet.3dst", nil, nil, true)

-- We can use Method Chaining to modify and place the icon
helmet:clone()              -- Work on a copy
    :rotate_90()            -- Turn it
 -- :flip_horizontal()      -- Mirror it
    :color_shift(0, 0, 255) -- Tint it blue

skin:replace_region(helmet, 32, 48) -- add helmet to skin

-- Export and save or do other operations.
local binaryOut = skin:export_tiled()
local f = Core.Filesystem.open("sdmc:/steveWithHelmet.3dst", "wb")
f:write(binaryOut)
f:close()
