local SIEGE_OPCODE = 217
local VALID_GHOST_SHADER = 'Outfit - Build Ghost'
local INVALID_GHOST_SHADER = 'Outfit - Build Ghost Invalid'
local FLOOR_VIEW_ALWAYS_TRANSPARENT = 4

local CATAPULT_PARTS = {
    { itemId = 5609, dx = 0, dy = 0 }, -- north-west
    { itemId = 5610, dx = 1, dy = 0 }, -- north-east
    { itemId = 5611, dx = 0, dy = 1 }, -- south-west
    { itemId = 5612, dx = 1, dy = 1 }, -- south-east
}

local specialCatalog = {
    stair = { itemId = 1958, rotatedItemId = 7881, cost = 12 },
    catapult = { itemId = 5609, rotatedItemId = 5609, cost = 30 },
}

local specialMode = nil
local specialOrientation = 0
local specialAnchor = nil
local specialHover = nil
local specialValid = false
local specialPending = false
local specialPreviews = {}

local siegeOnPlatform = false
local siegeHasCatapult = false
local fireTargeting = false
local fireCursorActive = false
local previousFloorViewMode = nil

local siegeMapPanel = nil
local previousMouseMove = nil
local previousMouseRelease = nil
local previousHoverChange = nil
local siegeHandlersInstalled = false

local stairWidget = nil
local catapultWidget = nil
local fireButton = nil
local confirmButton = nil
local rotateButton = nil
local cancelButton = nil
local selectionLabel = nil
local queueLabel = nil
local statusLabel = nil
local normalButtonHandlers = {}
local baseConfirmClick = nil
local baseRotateClick = nil
local baseCancelClick = nil

local baseExtendedOpcode = onExtendedOpcode

local function positionKey(position)
    if not position then
        return ''
    end
    return string.format('%d:%d:%d', position.x, position.y, position.z)
end

local function copyPosition(position)
    if not position then
        return nil
    end
    return { x = position.x, y = position.y, z = position.z }
end

local function setSiegeStatus(text, color)
    if statusLabel then
        statusLabel:setText(text or '')
        if color then
            statusLabel:setColor(color)
        end
    end
end

local function protocolSend(payload)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(SIEGE_OPCODE, payload)
        return true
    end
    return false
end

local function detachPreview(entry)
    if entry and entry.effect and entry.owner then
        entry.owner:detachEffect(entry.effect)
    end
end

local function clearSpecialPreviews()
    for _, entry in ipairs(specialPreviews) do
        detachPreview(entry)
    end
    specialPreviews = {}
end

local function attachGhost(position, itemId, valid)
    local tile = g_map.getTile(position)
    if not tile then
        return nil
    end

    local effect = AttachedEffect.create(itemId, ThingCategoryItem)
    if not effect then
        return nil
    end
    effect:setOnTop(true)
    effect:setPermanent(true)
    effect:setFollowOwner(false)

    local shaderName = valid and VALID_GHOST_SHADER or INVALID_GHOST_SHADER
    if g_shaders and g_shaders.getShader(shaderName) then
        effect:setShader(shaderName)
    else
        effect:setOpacity(valid and 0.46 or 0.28)
    end

    tile:attachEffect(effect)
    local entry = { effect = effect, owner = tile }
    specialPreviews[#specialPreviews + 1] = entry
    return entry
end

local function isAdjacent(position)
    local player = g_game.getLocalPlayer()
    if not player or not position then
        return false
    end
    local playerPosition = player:getPosition()
    if playerPosition.z ~= position.z then
        return false
    end
    return math.max(math.abs(playerPosition.x - position.x), math.abs(playerPosition.y - position.y)) == 1
end

local function hasGround(position)
    local tile = g_map.getTile(position)
    return tile and tile:getGround() ~= nil
end

local function isCatapultPlacementValid(anchor)
    if not siegeOnPlatform or not isAdjacent(anchor) then
        return false
    end

    local player = g_game.getLocalPlayer()
    local playerPosition = player and player:getPosition() or nil
    if not playerPosition then
        return false
    end

    for _, part in ipairs(CATAPULT_PARTS) do
        local position = { x = anchor.x + part.dx, y = anchor.y + part.dy, z = anchor.z }
        if not hasGround(position) then
            return false
        end
        if position.x == playerPosition.x and position.y == playerPosition.y and position.z == playerPosition.z then
            return false
        end
    end
    return true
end

local function placementValid(position)
    if specialMode == 'catapult' then
        return isCatapultPlacementValid(position)
    end
    return specialMode == 'stair' and isAdjacent(position)
end

local function refreshSpecialPreview(position)
    clearSpecialPreviews()
    if not specialMode or specialPending or not position then
        specialValid = false
        return
    end

    local valid = placementValid(position)
    specialValid = valid

    if specialMode == 'catapult' then
        for _, part in ipairs(CATAPULT_PARTS) do
            attachGhost(
                { x = position.x + part.dx, y = position.y + part.dy, z = position.z },
                part.itemId,
                valid
            )
        end
    else
        local config = specialCatalog.stair
        local itemId = specialOrientation == 1 and config.rotatedItemId or config.itemId
        attachGhost(position, itemId, valid)
    end
end

local function updateSpecialUi()
    if not specialMode then
        if fireButton then
            fireButton:setEnabled(siegeOnPlatform and siegeHasCatapult and not fireTargeting)
        end
        return
    end

    local config = specialCatalog[specialMode]
    if selectionLabel then
        if specialMode == 'stair' then
            selectionLabel:setText(string.format('Wood Stair (%d) | %s', config.cost, specialOrientation == 1 and 'West' or 'North'))
        else
            selectionLabel:setText(string.format('Catapult 2x2 (%d)', config.cost))
        end
    end
    if queueLabel then
        if specialPending then
            queueLabel:setText('Construction in progress...')
            queueLabel:setColor('#f0df9fff')
        elseif specialAnchor then
            queueLabel:setText(specialValid and 'Prebuild ready' or 'Invalid position')
            queueLabel:setColor(specialValid and '#7ee787ff' or '#ff7b72ff')
        else
            queueLabel:setText('Choose an adjacent square')
            queueLabel:setColor('#9d9d9dff')
        end
    end
    if confirmButton then
        confirmButton:setEnabled(not specialPending and specialAnchor ~= nil and specialValid)
    end
    if rotateButton then
        rotateButton:setEnabled(not specialPending and specialMode == 'stair')
        rotateButton:setTooltip(specialMode == 'stair' and 'Rotate stair North/West' or 'The 2x2 catapult has a fixed orientation.')
    end
    if cancelButton then
        cancelButton:setEnabled(not specialPending)
    end
    if fireButton then
        fireButton:setEnabled(false)
    end
end

local function stopFireTargeting(silent)
    if not fireTargeting then
        return
    end
    fireTargeting = false
    if fireCursorActive then
        if modules.client_options and modules.client_options.getOption('nativeCursor') then
            g_window.restoreMouseCursor()
        else
            g_mouse.popCursor('target')
        end
        fireCursorActive = false
    end
    if not silent then
        setSiegeStatus('Catapult targeting cancelled.', '#9d9d9dff')
    end
    updateSpecialUi()
end

local function cancelSpecialMode(silent)
    if specialPending then
        return
    end
    clearSpecialPreviews()
    specialMode = nil
    specialOrientation = 0
    specialAnchor = nil
    specialHover = nil
    specialValid = false
    if stairWidget then
        stairWidget:setBorderWidth(1)
        stairWidget:setBorderColor('#5a5a5aff')
    end
    if catapultWidget then
        catapultWidget:setBorderWidth(1)
        catapultWidget:setBorderColor('#5a5a5aff')
    end
    if selectionLabel then
        selectionLabel:setText(tr('Select a structure'))
    end
    if queueLabel then
        queueLabel:setText(tr('Plan only on adjacent squares'))
        queueLabel:setColor('#9d9d9dff')
    end
    if not silent then
        setSiegeStatus('Ready', '#9d9d9dff')
    end
    updateSpecialUi()
end

local function cancelMainBuild()
    if baseCancelClick and cancelButton and cancelButton:isEnabled() then
        baseCancelClick()
    end
end

local function selectSpecialMode(mode)
    if specialPending then
        return
    end
    stopFireTargeting(true)
    cancelMainBuild()
    clearSpecialPreviews()
    specialMode = mode
    specialOrientation = 0
    specialAnchor = nil
    specialHover = nil
    specialValid = false

    if stairWidget then
        stairWidget:setBorderWidth(mode == 'stair' and 2 or 1)
        stairWidget:setBorderColor(mode == 'stair' and '#7ee787ff' or '#5a5a5aff')
    end
    if catapultWidget then
        catapultWidget:setBorderWidth(mode == 'catapult' and 2 or 1)
        catapultWidget:setBorderColor(mode == 'catapult' and '#7ee787ff' or '#5a5a5aff')
    end

    if mode == 'catapult' and not siegeOnPlatform then
        setSiegeStatus('Climb onto your supported upper floor before building a catapult.', '#ffb86cff')
    else
        setSiegeStatus(mode == 'stair' and 'Place the stair beside a built wall.' or 'Place the 2x2 catapult on your upper floor.', '#7ee787ff')
    end
    updateSpecialUi()
end

local function confirmSpecialBuild()
    if not specialMode or specialPending or not specialAnchor or not specialValid then
        return
    end

    local config = specialCatalog[specialMode]
    specialPending = true
    updateSpecialUi()
    setSiegeStatus('Preparing construction...', '#f0df9fff')
    protocolSend(string.format(
        'build|confirm|wood|%s|v2|%d,%d,%d,%d',
        specialMode,
        specialAnchor.x,
        specialAnchor.y,
        specialAnchor.z,
        specialMode == 'stair' and specialOrientation or 0
    ))
end

local function rotateSpecial()
    if specialMode ~= 'stair' or specialPending then
        return
    end
    specialOrientation = specialOrientation == 1 and 0 or 1
    local position = specialAnchor or specialHover
    if position then
        refreshSpecialPreview(position)
    end
    setSiegeStatus(specialOrientation == 1 and 'Stair orientation: West' or 'Stair orientation: North', '#7ee787ff')
    updateSpecialUi()
end

local function findTarget(tile, localPlayer)
    if not tile then
        return nil
    end
    local creatures = tile:getCreatures()
    if not creatures then
        return nil
    end
    for _, creature in ipairs(creatures) do
        if creature and creature ~= localPlayer then
            return creature
        end
    end
    return nil
end

local function findTargetAtMouse(self, mousePosition)
    local player = g_game.getLocalPlayer()
    if not player then
        return nil
    end

    local target = findTarget(self:getTile(mousePosition), player)
    if target then
        return target
    end

    local mapPosition = self:getPosition(mousePosition)
    if not mapPosition then
        return nil
    end
    local playerPosition = player:getPosition()
    local lowerTile = g_map.getTile({ x = mapPosition.x, y = mapPosition.y, z = playerPosition.z + 1 })
    return findTarget(lowerTile, player)
end

local function startFireTargeting()
    if specialMode or not siegeOnPlatform or not siegeHasCatapult then
        return
    end
    fireTargeting = true
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.setSystemCursor('cross')
    else
        g_mouse.pushCursor('target')
    end
    fireCursorActive = true
    setSiegeStatus('Select a creature or player on the floor below.', '#f0df9fff')
    updateSpecialUi()
end

local function onSiegeMouseMove(self, mousePosition, mouseMoved)
    if specialMode and not specialPending then
        local position = self:getPosition(mousePosition)
        specialHover = copyPosition(position)
        if not specialAnchor then
            refreshSpecialPreview(position)
            updateSpecialUi()
        end
    end

    if previousMouseMove then
        return previousMouseMove(self, mousePosition, mouseMoved)
    end
    return false
end

local function onSiegeMouseRelease(self, mousePosition, mouseButton)
    if fireTargeting then
        if mouseButton == MouseRightButton then
            stopFireTargeting(false)
            return true
        elseif mouseButton == MouseLeftButton then
            local target = findTargetAtMouse(self, mousePosition)
            if not target then
                setSiegeStatus('No creature or player found on the floor below.', '#ff7b72ff')
                return true
            end
            protocolSend('siege|fire|' .. tostring(target:getId()))
            stopFireTargeting(true)
            setSiegeStatus('Catapult fired...', '#f0df9fff')
            return true
        end
    end

    if specialMode and not specialPending then
        if mouseButton == MouseRightButton then
            rotateSpecial()
            return true
        elseif mouseButton == MouseLeftButton then
            local position = self:getPosition(mousePosition)
            if not position then
                return true
            end
            specialHover = copyPosition(position)
            specialAnchor = copyPosition(position)
            refreshSpecialPreview(specialAnchor)
            if not specialValid then
                specialAnchor = nil
                setSiegeStatus('That special construction cannot be placed there.', '#ff7b72ff')
            else
                setSiegeStatus('Prebuild anchored. Press Build to confirm.', '#7ee787ff')
            end
            updateSpecialUi()
            return true
        end
    end

    if previousMouseRelease then
        return previousMouseRelease(self, mousePosition, mouseButton)
    end
    return false
end

local function onSiegeHoverChange(self, hovered)
    if not hovered and specialMode and not specialAnchor then
        clearSpecialPreviews()
        specialHover = nil
    end
    if previousHoverChange then
        previousHoverChange(self, hovered)
    end
end

local function installSiegeMapHandlers()
    if siegeHandlersInstalled then
        return
    end
    siegeMapPanel = modules.game_interface.getMapPanel()
    if not siegeMapPanel then
        return
    end
    previousMouseMove = siegeMapPanel.onMouseMove
    previousMouseRelease = siegeMapPanel.onMouseRelease
    previousHoverChange = siegeMapPanel.onHoverChange
    siegeMapPanel.onMouseMove = onSiegeMouseMove
    siegeMapPanel.onMouseRelease = onSiegeMouseRelease
    siegeMapPanel.onHoverChange = onSiegeHoverChange
    siegeHandlersInstalled = true
end

local function restoreSiegeMapHandlers()
    if siegeHandlersInstalled and siegeMapPanel then
        siegeMapPanel.onMouseMove = previousMouseMove
        siegeMapPanel.onMouseRelease = previousMouseRelease
        siegeMapPanel.onHoverChange = previousHoverChange
    end
    previousMouseMove = nil
    previousMouseRelease = nil
    previousHoverChange = nil
    siegeHandlersInstalled = false
end

local function applyPlatformView(enabled)
    if not siegeMapPanel then
        return
    end
    if enabled then
        if previousFloorViewMode == nil then
            previousFloorViewMode = siegeMapPanel:getFloorViewMode()
        end
        siegeMapPanel:setFloorViewMode(FLOOR_VIEW_ALWAYS_TRANSPARENT)
    elseif previousFloorViewMode ~= nil then
        siegeMapPanel:setFloorViewMode(previousFloorViewMode)
        previousFloorViewMode = nil
    end
end

local function requestSiegeStatus()
    if g_game.isOnline() then
        protocolSend('siege|status')
    end
end

local function handleSpecialCatalog(parts)
    if parts[2] ~= 'wood' then
        return
    end
    local index = 3
    while index + 3 <= #parts do
        local structureType = parts[index]
        if structureType == 'stair' or structureType == 'catapult' then
            specialCatalog[structureType] = {
                itemId = tonumber(parts[index + 1]) or specialCatalog[structureType].itemId,
                rotatedItemId = tonumber(parts[index + 2]) or specialCatalog[structureType].rotatedItemId,
                cost = tonumber(parts[index + 3]) or specialCatalog[structureType].cost,
            }
        end
        index = index + 4
    end
    if stairWidget then
        stairWidget:setItemId(specialCatalog.stair.itemId)
        stairWidget:setTooltip(string.format('Wood Stair\nCost: %d wood\nBuild beside one of your walls.', specialCatalog.stair.cost))
    end
    if catapultWidget then
        catapultWidget:setItemId(specialCatalog.catapult.itemId)
        catapultWidget:setTooltip(string.format('Catapult (2x2)\nCost: %d wood\nRequires your supported upper floor.', specialCatalog.catapult.cost))
    end
end

local function handleSiege(parts)
    if parts[2] == 'status' then
        local values = {}
        local index = 3
        while index + 1 <= #parts do
            values[parts[index]] = tonumber(parts[index + 1]) or 0
            index = index + 2
        end
        siegeOnPlatform = values.platform == 1
        siegeHasCatapult = values.catapult == 1
        applyPlatformView(siegeOnPlatform)
        if specialMode == 'catapult' and not siegeOnPlatform then
            clearSpecialPreviews()
            specialAnchor = nil
            specialValid = false
        end
        updateSpecialUi()
    elseif parts[2] == 'fire' then
        if parts[3] == 'success' then
            local damage = tonumber(parts[5]) or 0
            setSiegeStatus(string.format('Catapult hit for %d physical damage.', damage), '#7ee787ff')
        elseif parts[3] == 'error' then
            setSiegeStatus(parts[4] or 'Catapult attack failed.', '#ff7b72ff')
        end
    end
end

function onExtendedOpcode(protocol, opcode, buffer)
    local parts = {}
    for value in tostring(buffer or ''):gmatch('([^|]+)') do
        parts[#parts + 1] = value
    end

    if parts[1] == 'catalog2' then
        handleSpecialCatalog(parts)
    elseif parts[1] == 'siege' then
        handleSiege(parts)
    elseif parts[1] == 'build' and specialMode then
        if parts[2] == 'error' then
            specialPending = false
            setSiegeStatus(parts[3] or 'Special construction failed.', '#ff7b72ff')
            updateSpecialUi()
        elseif parts[2] == 'success' and parts[4] == specialMode then
            specialPending = false
            clearSpecialPreviews()
            specialAnchor = nil
            specialValid = false
            setSiegeStatus(parts[4] == 'catapult' and 'Catapult built.' or 'Stair built; upper floor generated.', '#7ee787ff')
            updateSpecialUi()
            scheduleEvent(requestSiegeStatus, 150)
        end
    end

    if baseExtendedOpcode then
        return baseExtendedOpcode(protocol, opcode, buffer)
    end
end

local function onSiegePositionChange(player, newPosition, oldPosition)
    if specialMode and not specialPending then
        clearSpecialPreviews()
        specialAnchor = nil
        specialValid = false
        updateSpecialUi()
    end
    scheduleEvent(requestSiegeStatus, 80)
end

local function wrapNormalBuildButtons(window)
    for _, id in ipairs({ 'woodWall', 'woodDoor', 'woodWindow', 'stoneWall', 'stoneDoor', 'stoneWindow' }) do
        local widget = window:recursiveGetChildById(id)
        if widget and widget.onMousePress then
            local previous = widget.onMousePress
            normalButtonHandlers[id] = previous
            widget.onMousePress = function(self, mousePosition, mouseButton)
                if specialMode and not specialPending then
                    cancelSpecialMode(true)
                end
                return previous(self, mousePosition, mouseButton)
            end
        end
    end
end

local function configureSiegeUi()
    local window = modules.game_interface.getRightPanel():recursiveGetChildById('farmingMaterialsWindow')
    if not window then
        return false
    end

    stairWidget = window:recursiveGetChildById('woodStair')
    catapultWidget = window:recursiveGetChildById('woodCatapult')
    fireButton = window:recursiveGetChildById('catapultFire')
    confirmButton = window:recursiveGetChildById('confirmBuild')
    rotateButton = window:recursiveGetChildById('rotateBuild')
    cancelButton = window:recursiveGetChildById('cancelBuild')
    selectionLabel = window:recursiveGetChildById('buildSelection')
    queueLabel = window:recursiveGetChildById('buildQueue')
    statusLabel = window:recursiveGetChildById('farmingStatus')

    if not stairWidget or not catapultWidget or not confirmButton or not rotateButton or not cancelButton then
        return false
    end

    stairWidget:setVirtual(true)
    catapultWidget:setVirtual(true)
    stairWidget:setItemId(specialCatalog.stair.itemId)
    catapultWidget:setItemId(specialCatalog.catapult.itemId)
    stairWidget:setTooltip(string.format('Wood Stair\nCost: %d wood\nBuild beside one of your walls.', specialCatalog.stair.cost))
    catapultWidget:setTooltip(string.format('Catapult (2x2)\nCost: %d wood\nRequires your supported upper floor.', specialCatalog.catapult.cost))

    stairWidget.onMousePress = function(self, mousePosition, mouseButton)
        if mouseButton == MouseLeftButton then
            selectSpecialMode('stair')
            return true
        end
        return false
    end
    catapultWidget.onMousePress = function(self, mousePosition, mouseButton)
        if mouseButton == MouseLeftButton then
            selectSpecialMode('catapult')
            return true
        end
        return false
    end

    baseConfirmClick = confirmButton.onClick
    baseRotateClick = rotateButton.onClick
    baseCancelClick = cancelButton.onClick

    confirmButton.onClick = function(...)
        if specialMode then
            confirmSpecialBuild()
            return true
        end
        if baseConfirmClick then
            return baseConfirmClick(...)
        end
    end
    rotateButton.onClick = function(...)
        if specialMode then
            rotateSpecial()
            return true
        end
        if baseRotateClick then
            return baseRotateClick(...)
        end
    end
    cancelButton.onClick = function(...)
        if specialMode then
            cancelSpecialMode(false)
            return true
        end
        if baseCancelClick then
            return baseCancelClick(...)
        end
    end

    if fireButton then
        fireButton.onClick = startFireTargeting
    end

    wrapNormalBuildButtons(window)
    updateSpecialUi()
    return true
end

function initSiege()
    installSiegeMapHandlers()
    configureSiegeUi()
    connect(LocalPlayer, { onPositionChange = onSiegePositionChange })
    scheduleEvent(function()
        configureSiegeUi()
        requestSiegeStatus()
    end, 350)
end

function terminateSiege()
    stopFireTargeting(true)
    specialPending = false
    cancelSpecialMode(true)
    applyPlatformView(false)
    disconnect(LocalPlayer, { onPositionChange = onSiegePositionChange })
    restoreSiegeMapHandlers()
end
