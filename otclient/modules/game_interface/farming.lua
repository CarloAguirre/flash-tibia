local FARMING_OPCODE = 217
local PICK_ITEM_ID = 3456

local materialsWindow = nil
local woodValueLabel = nil
local stoneValueLabel = nil
local statusLabel = nil
local rewardResetEvent = nil

local function splitPayload(buffer)
    local parts = {}
    for value in tostring(buffer or ''):gmatch('([^|]+)') do
        parts[#parts + 1] = value
    end
    return parts
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
    setStatus(tr('Ready'), '#9d9d9dff')
end

local function destroyWindow()
    if rewardResetEvent then
        removeEvent(rewardResetEvent)
        rewardResetEvent = nil
    end

    if materialsWindow then
        materialsWindow:destroy()
        materialsWindow = nil
    end

    woodValueLabel = nil
    stoneValueLabel = nil
    statusLabel = nil
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

    if woodValueLabel then
        woodValueLabel:setText(tostring(values.wood or 0))
    end
    if stoneValueLabel then
        stoneValueLabel:setText(tostring(values.stone or 0))
    end
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
        setStatus(tr('Farming...'), '#9d9d9dff')
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
        else
            setStatus(tr('Ready'), '#9d9d9dff')
        end
    end
end

function onExtendedOpcode(protocol, opcode, buffer)
    createWindow()

    local parts = splitPayload(buffer)
    local messageType = parts[1]
    if messageType == 'wallet' then
        handleWallet(parts)
    elseif messageType == 'reward' then
        handleReward(parts)
    elseif messageType == 'status' then
        handleStatus(parts)
    end
end

function onGameStart()
    createWindow()
    if materialsWindow then
        materialsWindow:setupOnStart()
        materialsWindow:open()
    end
    scheduleEvent(syncWallet, 300)
end

function onGameEnd()
    if materialsWindow then
        materialsWindow:hide()
    end
end

function init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    ProtocolGame.registerExtendedOpcode(FARMING_OPCODE, onExtendedOpcode)
    modules.game_interface.addMenuHook('elderaFarming', tr('Farm'), armFarming, canFarm)

    createWindow()
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
end
