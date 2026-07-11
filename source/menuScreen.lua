import "CoreLibs/graphics"

local gfx = playdate.graphics

MenuScreen = {}

-- The selectable options, top to bottom. `id` is what main.lua switches on when
-- A is pressed; `label` is what's drawn on the button.
local OPTIONS = {
    { id = "start",       label = "Start" },
    { id = "leaderboard", label = "Leaderboard" },
    { id = "tutorial",    label = "Tutorial" },
}

-- Button layout: a vertical stack, centred horizontally on the screen.
local BTN_W      = 200
local BTN_H      = 28
local BTN_GAP    = 8      -- vertical gap between buttons
local BTN_TOP    = 118    -- y of the first button's top edge
local BTN_RADIUS = 4

local selected = 1        -- 1-based index into OPTIONS of the highlighted button

--Called by main.lua when switching to this scene
--Clears all sprites so no game elements bleed through, and resets the highlight.
function MenuScreen.enter()
    gfx.sprite.removeAll()
    selected = 1
end

--Move the highlight by delta (wrapping around the ends). Driven by the arrow keys.
function MenuScreen.moveSelection(delta)
    selected = (selected - 1 + delta) % #OPTIONS + 1
end

--The id of the currently highlighted option, so main.lua can act on an A press.
function MenuScreen.selectedId()
    return OPTIONS[selected].id
end

--Called every frame by pd.update() while this scene is active.
function MenuScreen.update()
    gfx.clear()

    --Title
    gfx.drawTextAligned("*Last Line*", 200, 70, kTextAlignment.center)

    --Buttons: the highlighted one is a filled box with inverted (white) text; the
    --rest are outlined with black text.
    local x = 200 - BTN_W // 2
    for i, opt in ipairs(OPTIONS) do
        local y = BTN_TOP + (i - 1) * (BTN_H + BTN_GAP)
        local _, th = gfx.getTextSize(opt.label)
        local textY = y + (BTN_H - th) // 2

        gfx.setColor(gfx.kColorBlack)
        if i == selected then
            gfx.fillRoundRect(x, y, BTN_W, BTN_H, BTN_RADIUS)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            gfx.drawTextAligned(opt.label, 200, textY, kTextAlignment.center)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        else
            gfx.drawRoundRect(x, y, BTN_W, BTN_H, BTN_RADIUS)
            gfx.drawTextAligned(opt.label, 200, textY, kTextAlignment.center)
        end
    end
end
