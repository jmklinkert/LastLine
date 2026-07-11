import "CoreLibs/graphics"

local gfx = playdate.graphics

-- Placeholder tutorial scene. For now it just shows a "coming soon" message and
-- returns to the menu on A; the real tutorial content will replace this later.
TutorialScreen = {}

--Called by main.lua when switching to this scene.
--Clears all sprites so no game elements bleed through.
function TutorialScreen.enter()
    gfx.sprite.removeAll()
end

--Called every frame by pd.update() while this scene is active.
function TutorialScreen.update()
    gfx.clear()

    gfx.drawTextAligned("*Tutorial*", 200, 90, kTextAlignment.center)
    gfx.drawTextAligned("Coming soon", 200, 120, kTextAlignment.center)
    gfx.drawTextAligned("Press A to go back", 200, 200, kTextAlignment.center)
end
