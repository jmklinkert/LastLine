import "CoreLibs/graphics"

local gfx = playdate.graphics

MenuScreen = {}

--Called by main.lua when switching to this scene 
--Clears all sprites so no game elements bleed through
function MenuScreen.enter()
    gfx.sprite.removeAll()
end

--Called every frame by pd.update() while this scene is active. 

function MenuScreen.update()
    gfx.clear() 

    --Title 
    gfx.drawTextAligned("*Last Line*",200, 95, kTextAlignment.center)

    --Prompt
    gfx.drawTextAligned("Press A to Start",200, 130, kTextAlignment.center)
end