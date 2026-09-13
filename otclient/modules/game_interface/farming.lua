local FARMING_OPCODE = 217
local PICK_ITEM_ID = 3456
local BUILD_MAX_RANGE = 7
local BUILD_MAX_TILES = 40
local BUILD_GHOST_SHADER = 'Outfit - Build Ghost'

local materialsWindow = nil
local woodValueLabel = nil
local stoneValueLabel = nil
local statusLabel = nil
local buildSelectionLabel = nil
local buildQueueLabel = nil
local confirmBuildButton = nil
local rotateBuildButton = nil
local cancelBuildButton = nil
local rewardResetEvent = nil

local walletValues = { wood = 0, stone = 0 }
local buildCatalog = { wood = {}, stone = {} }
local buildButtons = {}
local buildMode = nil
local buildQueue = {}
local buildQueueOrder = {}
local buildPending = false
local buildCursorActive = false
local buildGhostShaderReady = false
local hoverPreview = nil
local hoverRelative = nil
local mapPanel = nil
local previousMapMouseRelease = nil
local previousMapMouseMove = nil
local previousMapHoverChange = nil
local mapHandlerInstalled = false

local structureNames = {
    wall = 'Wall',
    door = 'Door',
    window = 'Window'
}

local function splitPayload(buffer)
    local parts = {}
    for value in tostring(buffer or ''):gmatch('([^|]+)') do
        parts[#parts + 1] = value
    end
    return parts
end

local function buildRelativeKey(relative)
    return string.format('%d:%d:%d', relative.x, relative.y, relative.z or 0)
end

local function setStatus(text, color)
    if not statusLabel then
        return
    end

    statusLabel:setText(text or '')
    if color then
        statusLabel:setColor(color)
    end
end

local function getStructureLabel(material, structureType)
    local materialName = material == 'wood' and tr('Wood') or tr('Stone')
    local structureName = tr(structureNames[structureType] or structureType)
    return string.format('%s %s', materialName, structureName)
end

local function getBuildConfig()
    if not buildMode then
        return nil
    end
    return buildCatalog[buildMode.material] and buildCatalog[buildMode.material][buildMode.structureType] or nil
end

local function hasAlternateOrientation(config)
    return config and config.rotatedItemId and config.rotatedItemId ~= config.itemId
end

local function getSelectedBuildItemId(config)
    if not config then
        return nil
    end
    if buildMode and buildMode.orientation == 1 and hasAlternateOrientation(config) then
        return config.rotatedItemId
    end
    return config.itemId
end

local function getOrientationLabel()
    if not buildMode then
        return ''
    end
    return buildMode.orientation == 1 and tr('Vertical') or tr('Horizontal')
end

local function ensureBuildGhostShader()
    if buildGhostShaderReady then
        return true
    end
    if not g_shaders then
        return false
    end

    local existing = g_shaders.getShader(BUILD_GHOST_SHADER)
    if not existing then
        g_shaders.createFragmentShader(BUILD_GHOST_SHADER, 'shaders/build_ghost.frag', false)
        g_shaders.setupOutfitShader(BUILD_GHOST_SHADER)
        existing = g_shaders.getShader(BUILD_GHOST_SHADER)
    end

    buildGhostShaderReady = existing ~= nil
    return buildGhostShaderReady
end

local function queueCount()
    local count = 0
    for _, key in ipairs(buildQueueOrder) do
        if buildQueue[key] then
            count = count + 1
        end
    end
    return count
end

local function queuedCost()
    local config = getBuildConfig()
    return config and (config.cost * queueCount()) or 0
end

local function updateBuildUi()
    local count = queueCount()
    local cost = queuedCost()
    local config = getBuildConfig()

    if buildSelectionLabel then
        if buildMode then
            local unitCost = config and config.cost or 0
            local orientation = hasAlternateOrientation(config) and (' | ' .. getOrientationLabel()) or ''
            buildSelectionLabel:setText(string.format('%s  (%d)%s', getStructureLabel(buildMode.material, buildMode.structureType), unitCost, orientation))
        else
            buildSelectionLabel:setText(tr('Select a structure'))
        end
    end

    if buildQueueLabel then
        if count > 0 and buildMode then
            local available = walletValues[buildMode.material] or 0
            buildQueueLabel:setText(string.format('%d tile%s | %d / %d', count, count == 1 and '' or 's', cost, available))
            buildQueueLabel:setColor(cost <= available and '#7ee787ff' or '#ff7b72ff')
        else
            buildQueueLabel:setText(tr('Click map squares to plan'))
            buildQueueLabel:setColor('#9d9d9dff')
        end
    end

    if confirmBuildButton then
        local enough = buildMode and cost > 0 and cost <= (walletValues[buildMode.material] or 0)
        confirmBuildButton:setEnabled(not buildPending and enough)
    end
    if rotateBuildButton then
        rotateBuildButton:setEnabled(not buildPending and buildMode ~= nil and hasAlternateOrientation(config))
        if buildMode and hasAlternateOrientation(config) then
            rotateBuildButton:setTooltip(string.format('%s: %s', tr('Orientation'), getOrientationLabel()))
        else
            rotateBuildButton:setTooltip(tr('No alternate orientation is available for this structure yet.'))
        end
    end
    if cancelBuildButton then
        cancelBuildButton:setEnabled(buildMode ~= nil or count > 0)
    end
end

local function setBuildButtonSelected(selectedWidget)
    for _, widget in pairs(buildButtons) do
        if widget then
            widget:setBorderWidth(widget == selectedWidget and 2 or 1)
            widget:setBorderColor(widget == selectedWidget and '#7ee787ff' or '#5a5a5aff')
        end
    end
end

local function getRelativePosition(position)
    local player = g_game.getLocalPlayer()
    if not player or not position then
        return nil
    end

    local playerPos = player:getPosition()
    return {
        x = position.x - playerPos.x,
        y = position.y - playerPos.y,
        z = position.z - playerPos.z
    }
end

local function getAbsolutePosition(relative)
    local player = g_game.getLocalPlayer()
    if not player or not relative then
        return nil
    end

    local playerPos = player:getPosition()
    return {
        x = playerPos.x + relative.x,
        y = playerPos.y + relative.y,
        z = playerPos.z + (relative.z or 0)
    }
end

local function isRelativeBuildable(relative)
    if not relative or relative.z ~= 0 then
        return false
    end
    return math.max(math.abs(relative.x), math.abs(relative.y)) <= BUILD_MAX_RANGE
end

local function detachGhost(effect)
    if not effect then
        return
    end
    local player = g_game.getLocalPlayer()
    if player then
        player:detachEffect(effect)
    end
end

local function removePreview(entry)
    if entry and entry.preview then
        detachGhost(entry.preview)
        entry.preview = nil
    end
end

local function clearHoverPreview()
    if hoverPreview then
        detachGhost(hoverPreview)
        hoverPreview = nil
    end
    hoverRelative = nil
end

local function clearBuildQueue()
    for _, entry in pairs(buildQueue) do
        removePreview(entry)
    end
    buildQueue = {}
    buildQueueOrder = {}
    updateBuildUi()
end

local function removeQueueOrderKey(targetKey)
    local filtered = {}
    for _, key in ipairs(buildQueueOrder) do
        if key ~= targetKey then
            filtered[#filtered + 1] = key
        end
    end
    buildQueueOrder = filtered
end

local function enableBuildCursor()
    if buildCursorActive then
        return
    end
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.setSystemCursor('cross')
    else
        g_mouse.pushCursor('target')
    end
    buildCursorActive = true
end

local function disableBuildCursor()
    if not buildCursorActive then
        return
    end
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.restoreMouseCursor()
    else
        g_mouse.popCursor('target')
    end
    buildCursorActive = false
end

local function cancelBuildMode(silent)
    clearHoverPreview()
    clearBuildQueue()
    buildMode = nil
    buildPending = false
    disableBuildCursor()
    setBuildButtonSelected(nil)
    updateBuildUi()
    if not silent then
        setStatus(tr('Ready'), '#9d9d9dff')
    end
end

-- Build ghosts are AttachedEffects owned by the local player instead of Things
-- inserted into g_map. They therefore never change tile walk/path flags, and their
-- pixel offsets remain anchored to the player while the player walks.
local function createBuildPreview(relative)
    local config = getBuildConfig()
    local itemId = getSelectedBuildItemId(config)
    local player = g_game.getLocalPlayer()
    if not itemId or not player or not relative then
        return nil
    end

    local preview = AttachedEffect.create(itemId, ThingCategoryItem)
    if not preview then
        setStatus(tr('Could not create construction preview.'), '#ff7b72ff')
        return nil
    end

    local spriteSize = g_gameConfig.getSpriteSize()
    preview:setOffset(-relative.x * spriteSize, -relative.y * spriteSize)
    preview:setOnTop(true)
    preview:setFollowOwner(true)
    preview:setPermanent(true)

    if ensureBuildGhostShader() then
        preview:setShader(BUILD_GHOST_SHADER)
    else
        preview:setOpacity(0.46)
    end

    player:attachEffect(preview)
    return preview
end

local function addBuildPreview(relative)
    if not buildMode or not relative then
        return false
    end

    local preview = createBuildPreview(relative)
    if not preview then
        return false
    end

    local key = buildRelativeKey(relative)
    buildQueue[key] = {
        relative = { x = relative.x, y = relative.y, z = relative.z or 0 },
        preview = preview
    }
    buildQueueOrder[#buildQueueOrder + 1] = key
    return true
end

local function refreshHoverPreview()
    if not hoverRelative then
        return
    end

    local relative = { x = hoverRelative.x, y = hoverRelative.y, z = hoverRelative.z or 0 }
    clearHoverPreview()

    if buildQueue[buildRelativeKey(relative)] then
        return
    end

    hoverRelative = relative
    hoverPreview = createBuildPreview(relative)
end

local function refreshBuildPreviews()
    for _, key in ipairs(buildQueueOrder) do
        local entry = buildQueue[key]
        if entry then
            removePreview(entry)
            entry.preview = createBuildPreview(entry.relative)
        end
    end
    refreshHoverPreview()
end

local function updateHoverPreview(position)
    if not buildMode or buildPending or not position then
        clearHoverPreview()
        return
    end

    local relative = getRelativePosition(position)
    if not isRelativeBuildable(relative) then
        clearHoverPreview()
        return
    end

    local key = buildRelativeKey(relative)
    if buildQueue[key] then
        clearHoverPreview()
        return
    end

    if hoverRelative and hoverPreview and buildRelativeKey(hoverRelative) == key then
        return
    end

    clearHoverPreview()
    hoverRelative = relative
    hoverPreview = createBuildPreview(relative)
end

local function rotateBuildMode()
    if not buildMode or buildPending then
        return
    end

    local config = getBuildConfig()
    if not hasAlternateOrientation(config) then
        setStatus(tr('This structure has no alternate orientation yet.'), '#ffb86cff')
        updateBuildUi()
        return
    end

    buildMode.orientation = buildMode.orientation == 1 and 0 or 1
    refreshBuildPreviews()
    setStatus(string.format('%s: %s', tr('Orientation'), getOrientationLabel()), '#7ee787ff')
    updateBuildUi()
end

local function toggleBuildPosition(position)
    if not buildMode or buildPending then
        return
    end

    local relative = getRelativePosition(position)
    if not isRelativeBuildable(relative) then
        setStatus(tr('Build within 7 squares of your character.'), '#ffb86cff')
        return
    end

    local key = buildRelativeKey(relative)
    local existing = buildQueue[key]
    if existing then
        removePreview(existing)
        buildQueue[key] = nil
        removeQueueOrderKey(key)
        updateHoverPreview(position)
        updateBuildUi()
        return
    end

    if queueCount() >= BUILD_MAX_TILES then
        setStatus(string.format('Maximum %d squares per build batch.', BUILD_MAX_TILES), '#ffb86cff')
        return
    end

    clearHoverPreview()
    if addBuildPreview(relative) then
        local suffix = hasAlternateOrientation(getBuildConfig()) and (' | ' .. getOrientationLabel()) or ''
        setStatus(tr('Planning construction...') .. suffix, '#7ee787ff')
    end
    updateBuildUi()
end

local function onBuildMapMouseMove(self, mousePosition, mouseMoved)
    if buildMode and not buildPending then
        updateHoverPreview(self:getPosition(mousePosition))
    end

    if previousMapMouseMove then
        return previousMapMouseMove(self, mousePosition, mouseMoved)
    end
    return false
end

local function onBuildMapHoverChange(self, hovered)
    if not hovered then
        clearHoverPreview()
    end
    if previousMapHoverChange then
        previousMapHoverChange(self, hovered)
    end
end

local function onBuildMapMouseRelease(self, mousePosition, mouseButton)
    if buildMode and mouseButton == MouseLeftButton then
        local position = self:getPosition(mousePosition)
        if position then
            toggleBuildPosition(position)
        end
        return true
    elseif buildMode and mouseButton == MouseRightButton then
        rotateBuildMode()
        return true
    end

    if previousMapMouseRelease then
        return previousMapMouseRelease(self, mousePosition, mouseButton)
    end
    return false
end

local function installMapHandler()
    if mapHandlerInstalled then
        return
    end
    mapPanel = modules.game_interface.getMapPanel()
    if not mapPanel then
        return
    end

    previousMapMouseRelease = mapPanel.onMouseRelease
    previousMapMouseMove = mapPanel.onMouseMove
    previousMapHoverChange = mapPanel.onHoverChange
    mapPanel.onMouseRelease = onBuildMapMouseRelease
    mapPanel.onMouseMove = onBuildMapMouseMove
    mapPanel.onHoverChange = onBuildMapHoverChange
    mapHandlerInstalled = true
end

local function restoreMapHandler()
    if mapHandlerInstalled and mapPanel then
        mapPanel.onMouseRelease = previousMapMouseRelease
        mapPanel.onMouseMove = previousMapMouseMove
        mapPanel.onHoverChange = previousMapHoverChange
    end
    previousMapMouseRelease = nil
    previousMapMouseMove = nil
    previousMapHoverChange = nil
    mapPanel = nil
    mapHandlerInstalled = false
end

local function selectBuildMode(material, structureType, widget)
    local config = buildCatalog[material] and buildCatalog[material][structureType]
    if not config then
        setStatus(tr('Construction catalogue is still loading.'), '#ffb86cff')
        return
    end

    clearHoverPreview()
    if buildMode and (buildMode.material ~= material or buildMode.structureType ~= structureType) then
        clearBuildQueue()
    end

    buildMode = { material = material, structureType = structureType, orientation = 0 }
    buildPending = false
    setBuildButtonSelected(widget)
    enableBuildCursor()
    local rotationHint = hasAlternateOrientation(config) and (' | ' .. tr('Right-click or Rotate to turn')) or ''
    setStatus(string.format('%s: %s%s', tr('Build mode'), getStructureLabel(material, structureType), rotationHint), '#7ee787ff')
    updateBuildUi()
end

local function confirmBuild()
    if not buildMode or buildPending then
        return
    end

    local positions = {}
    for _, key in ipairs(buildQueueOrder) do
        local entry = buildQueue[key]
        if entry then
            local position = getAbsolutePosition(entry.relative)
            if position then
                positions[#positions + 1] = string.format('%d,%d,%d', position.x, position.y, position.z)
            end
        end
    end

    if #positions == 0 then
        return
    end

    local protocol = g_game.getProtocolGame()
    if not protocol then
        return
    end

    clearHoverPreview()
    buildPending = true
    updateBuildUi()
    setStatus(tr('Confirming construction...'), '#f0df9fff')
    protocol:sendExtendedOpcode(
        FARMING_OPCODE,
        string.format(
            'build|confirm|%s|%s|%d|%s',
            buildMode.material,
            buildMode.structureType,
            buildMode.orientation or 0,
            table.concat(positions, ';')
        )
    )
end

local function configureBuildButton(id, material, structureType)
    if not materialsWindow then
        return
    end
    local widget = materialsWindow:recursiveGetChildById(id)
    if not widget then
        return
    end

    buildButtons[material .. ':' .. structureType] = widget
    widget:setVirtual(true)
    widget:setBorderWidth(1)
    widget:setBorderColor('#5a5a5aff')

    -- Select on mouse-down instead of click-release so the preview already exists
    -- while the player drags the pointer from the panel into the map.
    widget.onMousePress = function(self, mousePosition, mouseButton)
        if mouseButton == MouseLeftButton then
            selectBuildMode(material, structureType, widget)
            return true
        end
        return false
    end
end

local function refreshCatalogUi(material)
    local structures = buildCatalog[material]
    if not structures then
        return
    end
    for structureType, config in pairs(structures) do
        local widget = buildButtons[material .. ':' .. structureType]
        if widget and config.itemId then
            widget:setItemId(config.itemId)
            local rotationText = hasAlternateOrientation(config) and ('\n' .. tr('Rotatable')) or ''
            widget:setTooltip(string.format('%s\nCost: %d %s%s', getStructureLabel(material, structureType), config.cost, material == 'wood' and tr('Wood') or tr('Stone'), rotationText))
        end
    end
    updateBuildUi()
end

local function createWindow()
    if materialsWindow then
        return
    end

    materialsWindow = g_ui.loadUI('farming', modules.game_interface.getRightPanel())
    if not materialsWindow then
        return
    end

    materialsWindow:setup()
    woodValueLabel = materialsWindow:recursiveGetChildById('woodValue')
    stoneValueLabel = materialsWindow:recursiveGetChildById('stoneValue')
    statusLabel = materialsWindow:recursiveGetChildById('farmingStatus')
    buildSelectionLabel = materialsWindow:recursiveGetChildById('buildSelection')
    buildQueueLabel = materialsWindow:recursiveGetChildById('buildQueue')
    confirmBuildButton = materialsWindow:recursiveGetChildById('confirmBuild')
    rotateBuildButton = materialsWindow:recursiveGetChildById('rotateBuild')
    cancelBuildButton = materialsWindow:recursiveGetChildById('cancelBuild')

    configureBuildButton('woodWall', 'wood', 'wall')
    configureBuildButton('woodDoor', 'wood', 'door')
    configureBuildButton('woodWindow', 'wood', 'window')
    configureBuildButton('stoneWall', 'stone', 'wall')
    configureBuildButton('stoneDoor', 'stone', 'door')
    configureBuildButton('stoneWindow', 'stone', 'window')

    if confirmBuildButton then
        confirmBuildButton.onClick = confirmBuild
    end
    if rotateBuildButton then
        rotateBuildButton.onClick = function()
            rotateBuildMode()
            return true
        end
    end
    if cancelBuildButton then
        cancelBuildButton.onClick = function()
            cancelBuildMode(false)
        end
    end

    refreshCatalogUi('wood')
    refreshCatalogUi('stone')
    setStatus(tr('Ready'), '#9d9d9dff')
    updateBuildUi()
end

local function destroyWindow()
    if rewardResetEvent then
        removeEvent(rewardResetEvent)
        rewardResetEvent = nil
    end

    cancelBuildMode(true)

    if materialsWindow then
        materialsWindow:destroy()
        materialsWindow = nil
    end

    woodValueLabel = nil
    stoneValueLabel = nil
    statusLabel = nil
    buildSelectionLabel = nil
    buildQueueLabel = nil
    confirmBuildButton = nil
    rotateBuildButton = nil
    cancelBuildButton = nil
    buildButtons = {}
end

local function syncWallet()
    if not g_game.isOnline() then
        return
    end

    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(FARMING_OPCODE, 'sync')
    end
end

local function armFarming(menuPosition, lookThing, useThing, creatureThing)
    if not useThing or useThing:getId() ~= PICK_ITEM_ID then
        return
    end

    cancelBuildMode(true)

    local protocol = g_game.getProtocolGame()
    if not protocol then
        return
    end

    protocol:sendExtendedOpcode(FARMING_OPCODE, 'arm')
    setStatus(tr('Select a resource...'), '#f0df9fff')
    modules.game_interface.startUseWith(useThing)
end

local function canFarm(menuPosition, lookThing, useThing, creatureThing)
    return g_game.isOnline() and useThing and useThing:isItem() and useThing:getId() == PICK_ITEM_ID
end

local function handleWallet(parts)
    local values = {}
    local index = 2
    while index + 1 <= #parts do
        values[parts[index]] = tonumber(parts[index + 1]) or 0
        index = index + 2
    end

    walletValues.wood = values.wood or 0
    walletValues.stone = values.stone or 0
    if woodValueLabel then
        woodValueLabel:setText(tostring(walletValues.wood))
    end
    if stoneValueLabel then
        stoneValueLabel:setText(tostring(walletValues.stone))
    end
    updateBuildUi()
end

local function handleCatalog(parts)
    local material = parts[2]
    if not buildCatalog[material] then
        return
    end
    local index = 3
    while index + 2 <= #parts do
        local structureType = parts[index]
        local itemId = tonumber(parts[index + 1])
        local cost = tonumber(parts[index + 2])
        if structureType and itemId and cost then
            local previous = buildCatalog[material][structureType] or {}
            buildCatalog[material][structureType] = {
                itemId = itemId,
                rotatedItemId = previous.rotatedItemId,
                cost = cost
            }
        end
        index = index + 3
    end
    refreshCatalogUi(material)
end

local function handleCatalog2(parts)
    local material = parts[2]
    if not buildCatalog[material] then
        return
    end

    local index = 3
    while index + 3 <= #parts do
        local structureType = parts[index]
        local itemId = tonumber(parts[index + 1])
        local rotatedItemId = tonumber(parts[index + 2])
        local cost = tonumber(parts[index + 3])
        if structureType and itemId and rotatedItemId and cost then
            buildCatalog[material][structureType] = {
                itemId = itemId,
                rotatedItemId = rotatedItemId,
                cost = cost
            }
        end
        index = index + 4
    end

    if buildMode and buildMode.material == material then
        refreshBuildPreviews()
    end
    refreshCatalogUi(material)
end

local function handleReward(parts)
    local material = parts[2] or 'material'
    local total = tonumber(parts[3]) or 0
    local materialName = material == 'wood' and tr('Wood') or (material == 'stone' and tr('Stone') or material)
    setStatus(string.format('+1 %s  (%d)', materialName, total), '#7ee787ff')

    if rewardResetEvent then
        removeEvent(rewardResetEvent)
    end
    rewardResetEvent = scheduleEvent(function()
        rewardResetEvent = nil
        if buildMode then
            setStatus(tr('Planning construction...'), '#7ee787ff')
        else
            setStatus(tr('Farming...'), '#9d9d9dff')
        end
    end, 900)
end

local function handleStatus(parts)
    local state = parts[2]
    if state == 'armed' then
        setStatus(tr('Select a resource...'), '#f0df9fff')
    elseif state == 'started' then
        local material = parts[3]
        local label = material == 'wood' and tr('Wood') or (material == 'stone' and tr('Stone') or tr('resource'))
        setStatus(string.format('%s: %s', tr('Farming'), label), '#9d9d9dff')
    elseif state == 'stopped' then
        local reason = parts[3] or ''
        if reason == 'depleted' then
            setStatus(tr('Resource depleted'), '#ffb86cff')
        elseif reason == 'too-far' then
            setStatus(tr('Too far from resource'), '#ffb86cff')
        elseif not buildMode then
            setStatus(tr('Ready'), '#9d9d9dff')
        end
    end
end

local function handleBuild(parts)
    local result = parts[2]
    if result == 'success' then
        local count = tonumber(parts[5]) or 0
        local cost = tonumber(parts[6]) or 0
        buildPending = false
        clearHoverPreview()
        clearBuildQueue()
        setStatus(string.format('Built %d tile%s (-%d)', count, count == 1 and '' or 's', cost), '#7ee787ff')
        updateBuildUi()
    elseif result == 'error' then
        buildPending = false
        setStatus(parts[3] or tr('Construction failed.'), '#ff7b72ff')
        updateBuildUi()
    end
end

function onExtendedOpcode(protocol, opcode, buffer)
    createWindow()

    local parts = splitPayload(buffer)
    local messageType = parts[1]
    if messageType == 'wallet' then
        handleWallet(parts)
    elseif messageType == 'catalog' then
        handleCatalog(parts)
    elseif messageType == 'catalog2' then
        handleCatalog2(parts)
    elseif messageType == 'reward' then
        handleReward(parts)
    elseif messageType == 'status' then
        handleStatus(parts)
    elseif messageType == 'build' then
        handleBuild(parts)
    end
end

function onGameStart()
    createWindow()
    installMapHandler()
    if materialsWindow then
        materialsWindow:setupOnStart()
        materialsWindow:open()
    end
    scheduleEvent(syncWallet, 300)
end

function onGameEnd()
    cancelBuildMode(true)
    if materialsWindow then
        materialsWindow:hide()
    end
end

function init()
    ensureBuildGhostShader()

    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    ProtocolGame.registerExtendedOpcode(FARMING_OPCODE, onExtendedOpcode)
    modules.game_interface.addMenuHook('elderaFarming', tr('Farm'), armFarming, canFarm)

    createWindow()
    installMapHandler()
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    modules.game_interface.removeMenuHook('elderaFarming', tr('Farm'))
    ProtocolGame.unregisterExtendedOpcode(FARMING_OPCODE)

    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    destroyWindow()
    restoreMapHandler()
end
