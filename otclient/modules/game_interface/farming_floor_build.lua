-- Manual upper-floor placement for the farming construction panel.
-- The server remains authoritative: this mode is only available while standing
-- on an owned generated platform and never allows closing the stair shaft.

local FLOOR_OPCODE = 217
local FLOOR_ITEM_ID = 408
local FLOOR_COST = 2
local VALID_GHOST_SHADER = 'Outfit - Build Ghost'
local INVALID_GHOST_SHADER = 'Outfit - Build Ghost Invalid'

local floorConfig = {
    itemId = FLOOR_ITEM_ID,
    cost = FLOOR_COST,
}

local active = false
local pending = false
local onPlatform = false
local anchor = nil
local hover = nil
local valid = false
local preview = nil
local previewOwner = nil

local mapPanel = nil
local previousMouseMove = nil
local previousMouseRelease = nil
local previousHoverChange = nil
local previousConfirm = nil
local previousRotate = nil
local previousCancel = nil
local previousButtonHandlers = {}

local floorWidget = nil
local confirmButton = nil
local rotateButton = nil
local cancelButton = nil
local selectionLabel = nil
local queueLabel = nil
local statusLabel = nil

local baseExtendedOpcode = onExtendedOpcode

local function copyPosition(position)
    if not position then
        return nil
    end
    return { x = position.x, y = position.y, z = position.z }
end

local function setStatus(text, color)
    if statusLabel then
        statusLabel:setText(text or '')
        if color then
            statusLabel:setColor(color)
        end
    end
end

local function protocolSend(payload)
    local protocol = g_game.getProtocolGame()
    if not protocol then
        return false
    end
    protocol:sendExtendedOpcode(FLOOR_OPCODE, payload)
    return true
end

local function clearPreview()
    if preview and previewOwner then
        previewOwner:detachEffect(preview)
    end
    preview = nil
    previewOwner = nil
end

local function attachPreview(position, isValid)
    clearPreview()
    if not position then
        return
    end

    local tile = g_map.getTile(position)
    if not tile then
        -- Empty upper-level squares may not yet have a client Tile object. The
        -- server can still create the dynamic tile after confirmation.
        return
    end

    local effect = AttachedEffect.create(floorConfig.itemId, ThingCategoryItem)
    if not effect then
        return
    end
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
    preview = effect
    previewOwner = tile
end

local function isPlacementValid(position)
    if not active or not onPlatform or not position then
        return false
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return false
    end
    local playerPosition = player:getPosition()
    if playerPosition.z ~= position.z then
        return false
    end

    local distance = math.max(math.abs(playerPosition.x - position.x), math.abs(playerPosition.y - position.y))
    if distance ~= 1 then
        return false
    end

    local tile = g_map.getTile(position)
    if tile and tile:getGround() then
        return false
    end

    return true
end

local function refreshPreview(position)
    valid = isPlacementValid(position)
    attachPreview(position, valid)
end

local function updateUi()
    if not active then
        return
    end

    if selectionLabel then
        selectionLabel:setText(string.format('Wood Floor (%d)', floorConfig.cost))
    end
    if queueLabel then
        if pending then
            queueLabel:setText('Building upper floor...')
            queueLabel:setColor('#f0df9fff')
        elseif not onPlatform then
            queueLabel:setText('Available only on your second floor')
            queueLabel:setColor('#ffb86cff')
        elseif anchor then
            queueLabel:setText(valid and 'Floor prebuild ready' or 'Invalid floor square')
            queueLabel:setColor(valid and '#7ee787ff' or '#ff7b72ff')
        else
            queueLabel:setText('Choose an empty adjacent square')
            queueLabel:setColor('#9d9d9dff')
        end
    end
    if confirmButton then
        confirmButton:setEnabled(not pending and onPlatform and anchor ~= nil and valid)
    end
    if rotateButton then
        rotateButton:setEnabled(false)
        rotateButton:setTooltip('Floor does not require rotation.')
    end
    if cancelButton then
        cancelButton:setEnabled(not pending)
    end
end

local function stopMode(silent)
    clearPreview()
    active = false
    pending = false
    anchor = nil
    hover = nil
    valid = false

    if floorWidget then
        floorWidget:setBorderWidth(1)
        floorWidget:setBorderColor('#5a5a5aff')
    end
    if not silent then
        setStatus('Ready', '#9d9d9dff')
    end
end

local function requestContext()
    if not g_game.isOnline() then
        return
    end
    protocolSend('siege|status')
end

local function startMode()
    if pending then
        return
    end

    -- Cancel any normal, stair or catapult mode before taking ownership of the
    -- shared Build/Cancel buttons and map mouse handlers.
    if previousCancel then
        previousCancel()
    end

    active = true
    pending = false
    anchor = nil
    hover = nil
    valid = false
    clearPreview()

    if floorWidget then
        floorWidget:setBorderWidth(2)
        floorWidget:setBorderColor('#7ee787ff')
    end

    requestContext()
    if onPlatform then
        setStatus('Place Wood Floor on an empty square beside you.', '#7ee787ff')
    else
        setStatus('Wood Floor is available only while standing on your second floor.', '#ffb86cff')
    end
    updateUi()
end

local function confirmFloor()
    if not active or pending or not anchor or not valid then
        return true
    end

    pending = true
    updateUi()
    setStatus('Building upper floor...', '#f0df9fff')
    protocolSend(string.format(
        'build|confirm|wood|floor|v2|%d,%d,%d,0',
        anchor.x,
        anchor.y,
        anchor.z
    ))
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

    if previousMouseMove then
        return previousMouseMove(self, mousePosition, mouseMoved)
    end
    return false
end

local function onMouseRelease(self, mousePosition, mouseButton)
    if active and not pending then
        if mouseButton == MouseRightButton then
            stopMode(false)
            return true
        elseif mouseButton == MouseLeftButton then
            local position = self:getPosition(mousePosition)
            if not position then
                return true
            end

            hover = copyPosition(position)
            anchor = copyPosition(position)
            refreshPreview(anchor)
            if not valid then
                anchor = nil
                setStatus(onPlatform and 'Choose an empty square beside you.' or 'Climb to your second floor first.', '#ff7b72ff')
            else
                setStatus('Floor prebuild anchored. Press Build.', '#7ee787ff')
            end
            updateUi()
            return true
        end
    end

    if previousMouseRelease then
        return previousMouseRelease(self, mousePosition, mouseButton)
    end
    return false
end

local function onHoverChange(self, hovered)
    if active and not hovered and not anchor then
        clearPreview()
        hover = nil
        valid = false
    end
    if previousHoverChange then
        previousHoverChange(self, hovered)
    end
end

local function handleCatalog(parts)
    if parts[1] ~= 'catalog2' or parts[2] ~= 'wood' then
        return
    end

    local index = 3
    while index + 3 <= #parts do
        local structureType = parts[index]
        if structureType == 'floor' then
            floorConfig.itemId = tonumber(parts[index + 1]) or floorConfig.itemId
            floorConfig.cost = tonumber(parts[index + 3]) or floorConfig.cost
            if floorWidget then
                floorWidget:setItemId(floorConfig.itemId)
                floorWidget:setTooltip(string.format(
                    'Wood Floor\nCost: %d wood\nCan only be placed on your player-built second floor.',
                    floorConfig.cost
                ))
            end
        end
        index = index + 4
    end
end

local function handleSiegeStatus(parts)
    if parts[1] ~= 'siege' or parts[2] ~= 'status' then
        return
    end

    local values = {}
    local index = 3
    while index + 1 <= #parts do
        values[parts[index]] = tonumber(parts[index + 1]) or 0
        index = index + 2
    end
    onPlatform = values.platform == 1

    if active and not onPlatform then
        clearPreview()
        anchor = nil
        hover = nil
        valid = false
        setStatus('Wood Floor is available only while standing on your second floor.', '#ffb86cff')
    end
    updateUi()
end

local function handleBuild(parts)
    if not active or parts[1] ~= 'build' then
        return
    end

    if parts[2] == 'error' then
        pending = false
        setStatus(parts[3] or 'Floor construction failed.', '#ff7b72ff')
        updateUi()
    elseif parts[2] == 'success' and parts[4] == 'floor' then
        local count = tonumber(parts[5]) or 1
        local cost = tonumber(parts[6]) or floorConfig.cost
        pending = false
        clearPreview()
        anchor = nil
        hover = nil
        valid = false
        setStatus(string.format('Built %d floor square%s (-%d wood).', count, count == 1 and '' or 's', cost), '#7ee787ff')
        updateUi()
        requestContext()
    end
end

function onExtendedOpcode(protocol, opcode, buffer)
    local result = nil
    if baseExtendedOpcode then
        result = baseExtendedOpcode(protocol, opcode, buffer)
    end

    local parts = {}
    for value in tostring(buffer or ''):gmatch('([^|]+)') do
        parts[#parts + 1] = value
    end

    handleCatalog(parts)
    handleSiegeStatus(parts)
    handleBuild(parts)
    return result
end

local function onFloorPositionChange(player, newPosition, oldPosition)
    if active and not pending then
        clearPreview()
        anchor = nil
        hover = nil
        valid = false
        updateUi()
    end
    scheduleEvent(requestContext, 80)
end

local function wrapOtherBuildButtons(window)
    local ids = {
        'woodWall', 'woodDoor', 'woodWindow', 'woodStair', 'woodCatapult',
        'stoneWall', 'stoneDoor', 'stoneWindow'
    }

    for _, id in ipairs(ids) do
        local widget = window:recursiveGetChildById(id)
        if widget and widget.onMousePress then
            local previous = widget.onMousePress
            previousButtonHandlers[id] = previous
            widget.onMousePress = function(self, mousePosition, mouseButton)
                if active and not pending then
                    stopMode(true)
                end
                return previous(self, mousePosition, mouseButton)
            end
        end
    end
end

local function restoreOtherBuildButtons(window)
    if not window then
        return
    end
    for id, handler in pairs(previousButtonHandlers) do
        local widget = window:recursiveGetChildById(id)
        if widget then
            widget.onMousePress = handler
        end
    end
    previousButtonHandlers = {}
end

function initFloorBuild()
    local window = modules.game_interface.getRightPanel():recursiveGetChildById('farmingMaterialsWindow')
    mapPanel = modules.game_interface.getMapPanel()
    if not window or not mapPanel then
        return false
    end

    floorWidget = window:recursiveGetChildById('woodFloor')
    confirmButton = window:recursiveGetChildById('confirmBuild')
    rotateButton = window:recursiveGetChildById('rotateBuild')
    cancelButton = window:recursiveGetChildById('cancelBuild')
    selectionLabel = window:recursiveGetChildById('buildSelection')
    queueLabel = window:recursiveGetChildById('buildQueue')
    statusLabel = window:recursiveGetChildById('farmingStatus')
    if not floorWidget or not confirmButton or not rotateButton or not cancelButton then
        return false
    end

    floorWidget:setVirtual(true)
    floorWidget:setItemId(floorConfig.itemId)
    floorWidget:setTooltip(string.format(
        'Wood Floor\nCost: %d wood\nCan only be placed on your player-built second floor.',
        floorConfig.cost
    ))
    floorWidget.onMousePress = function(self, mousePosition, mouseButton)
        if mouseButton == MouseLeftButton then
            startMode()
            return true
        end
        return false
    end

    previousConfirm = confirmButton.onClick
    confirmButton.onClick = function(...)
        if active then
            return confirmFloor()
        end
        if previousConfirm then
            return previousConfirm(...)
        end
    end

    previousRotate = rotateButton.onClick
    rotateButton.onClick = function(...)
        if active then
            return true
        end
        if previousRotate then
            return previousRotate(...)
        end
    end

    previousCancel = cancelButton.onClick
    cancelButton.onClick = function(...)
        if active then
            stopMode(false)
            return true
        end
        if previousCancel then
            return previousCancel(...)
        end
    end

    previousMouseMove = mapPanel.onMouseMove
    previousMouseRelease = mapPanel.onMouseRelease
    previousHoverChange = mapPanel.onHoverChange
    mapPanel.onMouseMove = onMouseMove
    mapPanel.onMouseRelease = onMouseRelease
    mapPanel.onHoverChange = onHoverChange

    wrapOtherBuildButtons(window)
    connect(LocalPlayer, { onPositionChange = onFloorPositionChange })

    -- farming.lua registered opcode 217 before this extension replaced the global
    -- callback. Re-register it so floor catalogue/status/build packets reach us.
    ProtocolGame.unregisterExtendedOpcode(FLOOR_OPCODE)
    ProtocolGame.registerExtendedOpcode(FLOOR_OPCODE, onExtendedOpcode)

    protocolSend('sync')
    requestContext()
    return true
end

function terminateFloorBuild()
    stopMode(true)

    local window = modules.game_interface.getRightPanel():recursiveGetChildById('farmingMaterialsWindow')
    restoreOtherBuildButtons(window)

    disconnect(LocalPlayer, { onPositionChange = onFloorPositionChange })

    if mapPanel then
        mapPanel.onMouseMove = previousMouseMove
        mapPanel.onMouseRelease = previousMouseRelease
        mapPanel.onHoverChange = previousHoverChange
    end
    if confirmButton and previousConfirm then
        confirmButton.onClick = previousConfirm
    end
    if rotateButton and previousRotate then
        rotateButton.onClick = previousRotate
    end
    if cancelButton and previousCancel then
        cancelButton.onClick = previousCancel
    end

    ProtocolGame.unregisterExtendedOpcode(FLOOR_OPCODE)
    if baseExtendedOpcode then
        ProtocolGame.registerExtendedOpcode(FLOOR_OPCODE, baseExtendedOpcode)
    end
end
