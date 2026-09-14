-- Central guard for the shared construction panel.
-- Every construction mode owns the same Build/Cancel controls and map handlers;
-- before a new inventory entry is selected, unwind every currently active mode
-- and reset all selection borders so two builders can never stay active together.

local BUILD_BUTTON_IDS = {
    'woodWall', 'woodDoor', 'woodWindow', 'woodStair', 'woodCatapult', 'woodFloor',
    'stoneWall', 'stoneDoor', 'stoneWindow'
}

local wrappedHandlers = {}
local cancelButton = nil
local guardWindow = nil

local function resetSelectionBorders()
    if not guardWindow then
        return
    end

    for _, id in ipairs(BUILD_BUTTON_IDS) do
        local widget = guardWindow:recursiveGetChildById(id)
        if widget then
            widget:setBorderWidth(1)
            widget:setBorderColor('#5a5a5aff')
        end
    end
end

local function cancelEveryConstructionMode()
    -- The farming client is layered (normal -> siege -> catapult -> floor). Each
    -- Cancel invocation removes the outermost active owner and delegates down when
    -- inactive. Repeating it guarantees stale modes from older wrappers are also
    -- cleared before the next button becomes selected.
    if cancelButton and cancelButton.onClick then
        for _ = 1, 5 do
            cancelButton.onClick()
        end
    end
    resetSelectionBorders()
end

function initFarmingSelectionGuard()
    guardWindow = modules.game_interface.getRightPanel():recursiveGetChildById('farmingMaterialsWindow')
    if not guardWindow then
        return false
    end

    cancelButton = guardWindow:recursiveGetChildById('cancelBuild')
    if not cancelButton then
        return false
    end

    for _, id in ipairs(BUILD_BUTTON_IDS) do
        local widget = guardWindow:recursiveGetChildById(id)
        if widget and widget.onMousePress and not wrappedHandlers[id] then
            local previous = widget.onMousePress
            wrappedHandlers[id] = previous
            widget.onMousePress = function(self, mousePosition, mouseButton)
                if mouseButton == MouseLeftButton then
                    cancelEveryConstructionMode()
                end
                return previous(self, mousePosition, mouseButton)
            end
        end
    end

    return true
end

function terminateFarmingSelectionGuard()
    if guardWindow then
        for id, handler in pairs(wrappedHandlers) do
            local widget = guardWindow:recursiveGetChildById(id)
            if widget then
                widget.onMousePress = handler
            end
        end
    end

    wrappedHandlers = {}
    cancelButton = nil
    guardWindow = nil
end
