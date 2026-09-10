local WHEAT_GLOW_EFFECT_ID = 12
local WHEAT_GLOW_SHADER = 'Outfit - Wheat Violet'
local WHEAT_CUT_ID = 3651
local WHEAT_GROWING_ID = 3652
local WHEAT_RIPE_ID = 3653
local GLOW_REFRESH_MS = 250

-- Keep this client-side cue scoped to the custom Thais farm. Normal Tibia
-- wheat elsewhere must retain its original appearance.
local THAIS_WHEAT_FIELD = {
    fromX = 32371,
    toX = 32383,
    z = 7,
    rows = { 32206, 32208, 32210, 32212 }
}

local wheatGlowEvent = nil

local function isWheat(itemId)
    return itemId == WHEAT_CUT_ID or itemId == WHEAT_GROWING_ID or itemId == WHEAT_RIPE_ID
end

local function forEachFieldWheat(callback)
    if not g_game.isOnline() then
        return
    end

    for _, y in ipairs(THAIS_WHEAT_FIELD.rows) do
        for x = THAIS_WHEAT_FIELD.fromX, THAIS_WHEAT_FIELD.toX do
            local tile = g_map.getTile({ x = x, y = y, z = THAIS_WHEAT_FIELD.z })
            if tile then
                local things = tile:getThings()
                if things then
                    for _, thing in ipairs(things) do
                        if thing and thing:isItem() then
                            local itemId = thing:getId()
                            if isWheat(itemId) then
                                callback(thing, itemId)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function refreshWheatGlow()
    if not g_attachedEffects then
        return
    end

    local effectTemplate = g_attachedEffects.getById(WHEAT_GLOW_EFFECT_ID)
    if not effectTemplate then
        return
    end

    forEachFieldWheat(function(wheat, itemId)
        local currentGlow = wheat:getAttachedEffectById(WHEAT_GLOW_EFFECT_ID)

        if itemId == WHEAT_RIPE_ID then
            if not currentGlow then
                local glow = effectTemplate:clone()
                -- Apply the shader only now, after game_shaders is guaranteed to be loaded.
                -- Registering it earlier in game_attachedeffects left the effect with a null
                -- shader and therefore rendered the original Ki carrier image unchanged.
                glow:setShader(WHEAT_GLOW_SHADER)
                wheat:attachEffect(glow)
            end
        elseif currentGlow then
            -- Cut (3651) and growing (3652) wheat deliberately have no aura.
            wheat:detachEffectById(WHEAT_GLOW_EFFECT_ID)
        end
    end)
end

local function clearWheatGlow()
    forEachFieldWheat(function(wheat)
        if wheat:getAttachedEffectById(WHEAT_GLOW_EFFECT_ID) then
            wheat:detachEffectById(WHEAT_GLOW_EFFECT_ID)
        end
    end)
end

function initWheatGlow()
    if wheatGlowEvent then
        return
    end

    wheatGlowEvent = cycleEvent(refreshWheatGlow, GLOW_REFRESH_MS)
    scheduleEvent(refreshWheatGlow, 100)
end

function terminateWheatGlow()
    clearWheatGlow()

    if wheatGlowEvent then
        removeEvent(wheatGlowEvent)
        wheatGlowEvent = nil
    end
end
