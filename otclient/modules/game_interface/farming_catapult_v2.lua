-- Client-side catapult placement v2.
-- Uses an independent 2x2 placement mode so the catapult can be anchored up to
-- two squares away while the server remains authoritative about platform ownership.

local CATAPULT_OPCODE = 217
local VALID_GHOST_SHADER = 'Outfit - Build Ghost'
local INVALID_GHOST_SHADER = 'Outfit - Build Ghost Invalid'
local CATAPULT_COST = 30
local CATAPULT_PARTS = {
    { itemId = 5609, dx = 0, dy = 0 },
    { itemId = 5610, dx = 1, dy = 0 },
    { itemId = 5611, dx = 0, dy = 1 },
    { itemId = 5612, dx = 1, dy = 1 },
}

local active = false
local pending = false
local anchor = nil
local hover = nil
local valid = false
local previews = {}
local mapPanel = nil
local previousMouseMove = nil
local previousMouseRelease = nil
local previousHoverChange = nil
local previousConfirm = nil
local previousCancel = nil
local previousCatapultPress = nil
local catapultWidget = nil
local confirmButton = nil
local cancelButton = nil
local selectionLabel = nil
local queueLabel = nil
local statusLabel = nil

local function copyPosition(position)
    if not position then return nil end
    return { x = position.x, y = position.y, z = position.z }
end

local function setStatus(text, color)
    if statusLabel then
        statusLabel:setText(text or '')
        if color then statusLabel:setColor(color) end
    end
end

local function clearPreviews()
    for _, entry in ipairs(previews) do
        if entry.effect and entry.owner then
            entry.owner:detachEffect(entry.effect)
        end
    end
    previews = {}
end

local function attachGhost(position, itemId, isValid)
    local tile = g_map.getTile(position)
    if not tile then return end
    local effect = AttachedEffect.create(itemId, ThingCategoryItem)
    if not effect then return end
    effect:setOnTop(true)
    effect:setPermanent(true)
    effect:setFollowOwner(false)
    local shaderName = isValid and VALID_GHOST_SHADER or INVALID_GHOST_SHADER
    if g_shaders and g_shaders.getShader(shaderName) then
        effect:setShader(shaderName)
    else
        effect:setOpacity(isValid and 0.46 or 0.28)
    end
    tile:attachEffect(effect)
    previews[#previews + 1] = { effect = effect, owner = tile }
end

local function isPlacementValid(position)
    local player = g_game.getLocalPlayer()
    if not player or not position then return false end
    local playerPosition = player:getPosition()
    if playerPosition.z ~= position.z then return false end
    if math.max(math.abs(playerPosition.x - position.x), math.abs(playerPosition.y - position.y)) > 2 then
        return false
    end

    for _, part in ipairs(CATAPULT_PARTS) do
        local p = { x = position.x + part.dx, y = position.y + part.dy, z = position.z }
        local tile = g_map.getTile(p)
        if not tile or not tile:getGround() then return false end
        if p.x == playerPosition.x and p.y == playerPosition.y and p.z == playerPosition.z then
            return false
        end
    end
    return true
end

local function refreshPreview(position)
    clearPreviews()
    if not active or pending or not position then
        valid = false
        return
    end
    valid = isPlacementValid(position)
    for _, part in ipairs(CATAPULT_PARTS) do
        attachGhost({ x = position.x + part.dx, y = position.y + part.dy, z = position.z }, part.itemId, valid)
    end
end

local function updateUi()
    if selectionLabel then
        selectionLabel:setText(active and string.format('Catapult 2x2 (%d)', CATAPULT_COST) or tr('Select a structure'))
    end
    if queueLabel and active then
        if pending then
            queueLabel:setText('Construction in progress...')
            queueLabel:setColor('#f0df9fff')
        elseif anchor then
            queueLabel:setText(valid and 'Prebuild ready' or 'Invalid position')
            queueLabel:setColor(valid and '#7ee787ff' or '#ff7b72ff')
        else
            queueLabel:setText('Choose a 2x2 area within two squares')
            queueLabel:setColor('#9d9d9dff')
        end
    end
    if confirmButton and active then confirmButton:setEnabled(not pending and anchor ~= nil and valid) end
    if cancelButton and active then cancelButton:setEnabled(not pending) end
end

local function stopMode(silent)
    clearPreviews()
    active = false
    pending = false
    anchor = nil
    hover = nil
    valid = false
    if catapultWidget then
        catapultWidget:setBorderWidth(1)
        catapultWidget:setBorderColor('#5a5a5aff')
    end
    if not silent then setStatus('Ready', '#9d9d9dff') end
    updateUi()
end

local function startMode()
    if pending then return end
    active = true
    anchor = nil
    hover = nil
    valid = false
    clearPreviews()
    if catapultWidget then
        catapultWidget:setBorderWidth(2)
        catapultWidget:setBorderColor('#7ee787ff')
    end
    setStatus('Place the 2x2 catapult on your upper platform.', '#7ee787ff')
    updateUi()
end

local function sendBuild()
    if not active or pending or not anchor or not valid then return true end
    local protocol = g_game.getProtocolGame()
    if not protocol then return true end
    pending = true
    updateUi()
    setStatus('Preparing catapult construction...', '#f0df9fff')
    protocol:sendExtendedOpcode(CATAPULT_OPCODE, string.format(
        'build|confirm|wood|catapult|v2|%d,%d,%d,0', anchor.x, anchor.y, anchor.z
    ))
    scheduleEvent(function()
        if active then
            stopMode(true)
            setStatus('Catapult construction finished.', '#7ee787ff')
        end
    end, 2300)
    return true
end

local function onMouseMove(self, mousePosition, mouseMoved)
    if active and not pending and not anchor then
        local position = self:getPosition(mousePosition)
        hover = copyPosition(position)
        refreshPreview(position)
        updateUi()
        return true
    end
    if previousMouseMove then return previousMouseMove(self, mousePosition, mouseMoved) end
    return false
end

local function onMouseRelease(self, mousePosition, mouseButton)
    if active and not pending then
        if mouseButton == MouseRightButton then
            stopMode(false)
            return true
        elseif mouseButton == MouseLeftButton then
            local position = self:getPosition(mousePosition)
            if not position then return true end
            hover = copyPosition(position)
            anchor = copyPosition(position)
            refreshPreview(anchor)
            if not valid then
                anchor = nil
                setStatus('Catapult needs a free 2x2 platform area within two squares.', '#ff7b72ff')
            else
                setStatus('Catapult prebuild anchored. Press Build.', '#7ee787ff')
            end
            updateUi()
            return true
        end
    end
    if previousMouseRelease then return previousMouseRelease(self, mousePosition, mouseButton) end
    return false
end

local function onHoverChange(self, hovered)
    if active and not hovered and not anchor then
        clearPreviews()
        hover = nil
    end
    if previousHoverChange then previousHoverChange(self, hovered) end
end

function initCatapultV2()
    local window = modules.game_interface.getRightPanel():recursiveGetChildById('farmingMaterialsWindow')
    mapPanel = modules.game_interface.getMapPanel()
    if not window or not mapPanel then return false end

    catapultWidget = window:recursiveGetChildById('woodCatapult')
    confirmButton = window:recursiveGetChildById('confirmBuild')
    cancelButton = window:recursiveGetChildById('cancelBuild')
    selectionLabel = window:recursiveGetChildById('buildSelection')
    queueLabel = window:recursiveGetChildById('buildQueue')
    statusLabel = window:recursiveGetChildById('farmingStatus')
    if not catapultWidget or not confirmButton or not cancelButton then return false end

    previousCatapultPress = catapultWidget.onMousePress
    catapultWidget.onMousePress = function(self, mousePosition, mouseButton)
        if mouseButton == MouseLeftButton then
            startMode()
            return true
        end
        return false
    end

    previousConfirm = confirmButton.onClick
    confirmButton.onClick = function(...)
        if active then return sendBuild() end
        if previousConfirm then return previousConfirm(...) end
    end

    previousCancel = cancelButton.onClick
    cancelButton.onClick = function(...)
        if active then
            stopMode(false)
            return true
        end
        if previousCancel then return previousCancel(...) end
    end

    previousMouseMove = mapPanel.onMouseMove
    previousMouseRelease = mapPanel.onMouseRelease
    previousHoverChange = mapPanel.onHoverChange
    mapPanel.onMouseMove = onMouseMove
    mapPanel.onMouseRelease = onMouseRelease
    mapPanel.onHoverChange = onHoverChange
    return true
end

function terminateCatapultV2()
    stopMode(true)
    if mapPanel then
        mapPanel.onMouseMove = previousMouseMove
        mapPanel.onMouseRelease = previousMouseRelease
        mapPanel.onHoverChange = previousHoverChange
    end
    if catapultWidget and previousCatapultPress then catapultWidget.onMousePress = previousCatapultPress end
    if confirmButton and previousConfirm then confirmButton.onClick = previousConfirm end
    if cancelButton and previousCancel then cancelButton.onClick = previousCancel end
end
