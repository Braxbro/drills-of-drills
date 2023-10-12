local drill = data.raw["mining-drill"]["burner-mining-drill"]

local layer = drill.animations.north.layers[1]
local oldShift = layer.shift
local oldHRShift = layer.hr_version.shift
layer.shift = util.by_pixel(-.5, -2.5)
layer.hr_version.shift = util.by_pixel(-.5, -2.75)

local shadow = drill.animations.north.layers[2]
shadow.shift = {shadow.shift[1] + (layer.shift[1] - oldShift[1]), shadow.shift[2] + (layer.shift[2] - oldShift[2])}
shadow.hr_version.shift = {
    shadow.hr_version.shift[1] + (layer.hr_version.shift[1] - oldHRShift[1]), 
    shadow.hr_version.shift[2] + (layer.hr_version.shift[2] - oldHRShift[2])
}