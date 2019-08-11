local _, addonTable = ...
---
-- Controls all Playe related functionality.
-- @file XToLevel.Player.lua
-- @release 7.0.3_46
-- @copyright Atli Þór (atli.j@advefir.com)
---
--module "XToLevel.Player" -- For documentation purposes. Do not uncomment!

local L = addonTable.GetLocale()

---
-- Control object for player functionality and calculations.
-- @class table
-- @name XToLevel.Player
-- @field isActive Indicates whether the object has been sucessfully initialized.
-- @field level The current level of the player.
-- @field maxLevel The max level for the player, according to the account type.
-- @field currentXP The current XP of the player.
-- @field restedXP The amount of extra "rested" XP the player has accumulated.
-- @field maxXP The total XP required for the current level.
-- @field killAverage Holds the latest value of the GetAverageKillXP method. Do
--        not use this field directly. Call the funciton instead.
-- @field killRange Holds the lates value of the GetKillXpRange method. Do not
--        use this field directly. Call the function instead.
-- @field questAverage Holds the latest value of the GetAverageQuestXP method.
--        Do not use this field directly. Call the funciton instead.
-- @field questRange Holds the lates value of the GetQuestXpRange method. Do not
--        use this field directly. Call the function instead.
-- @field bgAverage Holds the latest value of the GetAverageBGXP method. Do not
--        use this field directly. Call the funciton instead.
-- @field dungeonAverage Holds the latest value of the GetAverageDungeonXP method. 
--        Do not use this field directly. Call the funciton instead.
-- @field killListLength The max number of kills to record.
-- @field questListLength The max number of quests to record.
-- @field dungeonListLength The max number of dungeons to record.
-- @field dungeonList A list of dungeon names. Set by the GetDungeonsListed function
-- @field latestDungeonData The data for the lates/current dungeon.
---
XToLevel.Player = {
	-- Members
	isActive = false,
	level = nil,
	maxLevel = nil, -- Assume WotLK-enabled. Will be corrected once properly initialized.
	class = nil,
	currentXP = nil,
    restedXP = 0,
	maxXP = nil,
    killAverage = nil,
    killRange = { low = nil, high = nil, average = nil },
	questAverage = nil,
	questRange = { low = nil, high = nil, average = nil },
    dungeonAverage = nil,
	killListLength = 100, -- The max allowed value, not the current selection.
	questListLength = 100,
	dungeonListLength = 100,
	
	timePlayedTotal = nil,
	timePlayedLevel = nil,
	timePlayedUpdated = nil,
	
	dungeonList = {},
	latestDungeonData = { totalXP = nil, killCount = nil, xpPerKill = nil, otherXP = nil },
	
	lastSync = time(),
	lastXpPerHourUpdate = time() - 60,
	xpPerSec = nil,
	xpPerSecTimeout = 2, -- The number of seconds between re-calculating the xpPerSec
	timerHandler = nil,

    percentage = nil,
	lastKnownXP = nil,
}
	
-- Constructor
function XToLevel.Player:Initialize()
    self:SyncData()

    self:GetMaxLevel();

    if self.level == self.maxLevel then
        self.isActive = false
    else
        self.isActive = true
    end

    self.killAverage = nil
    self.questAverage = nil

    if XToLevel.db.profile.timer.enabled then
        self.timerHandler = XToLevel.timer:ScheduleRepeatingTimer(XToLevel.Player.TriggerTimerUpdate, self.xpPerSecTimeout)
    end
end

---
-- Calculates the max level for the player, based on the expansion level
-- available to the player.
---
function XToLevel.Player:GetMaxLevel()
    if self.maxLevel == nil then
        self.maxLevel = 60
    end
    return self.maxLevel
end

---
-- Returns the player class in English, fully capitalized. For example:
-- "HUNTER", "WARRIOR".
function XToLevel.Player:GetClass()
    if self.class == nil then
        local playerClass, englishClass = UnitClass("player");
        self.class = englishClass
    end
    return self.class
end

---
-- Creates an empty template entry for the bg list.
-- @return The empty template table.
--- 
function XToLevel.Player:CreateBgDataArray()
    return {
        inProgress = false,
        level = nil,
        name = nil,
        totalXP = 0,
        objTotal = 0,
        objCount = 0,
        killCount = 0,
        killTotal = 0,
        objMinorTotal = 0,
        objMinorCount = 0,
    }
end

---
-- Creates an empty template entry for the dungeon list.
-- @return The empty template table.
--- 
function XToLevel.Player:CreateDungeonDataArray()
    return {
        inProgress = false,
        level = nil,
        name = nil,
        totalXP = 0,
        killCount = 0,
        killTotal = 0,
        rested = 0,
    }
end

---
-- Updates the level and XP values in the table with the actual values on
-- the server.
---
function XToLevel.Player:SyncData()
    self.level = UnitLevel("player")
    self.currentXP = UnitXP("player")
    self.maxXP = UnitXPMax("player")
    self.lastSync = time() -- Used for the XP/hr calculations. May be altered elsewhere!

    local rested = GetXPExhaustion() or 0
    self.restedXP = rested / 2
end

--- Updates the time played values.
-- @param total The total time played on this char, in seconds.
-- @param level The total time played this level, in seconds.
function XToLevel.Player:UpdateTimePlayed(total, level)
    if type(level) == "number" and level > 0 then
        self.timePlayedLevel = level
    end
    if type(total) == "number" and total > 0 then
        self.timePlayedTotal = total
    end
    self.timePlayedUpdated = GetTime()
end

--- Callback for the timer registration function.
function XToLevel.Player:TriggerTimerUpdate()
    XToLevel.Player:UpdateTimer()
end
function XToLevel.Player:UpdateTimer()
    self = XToLevel.Player
    self.lastXpPerHourUpdate = GetTime();
    XToLevel.db.char.data.timer.lastUpdated = self.lastXpPerHourUpdate;

    local useMode = XToLevel.db.profile.timer.mode

    -- Use the session data
    if useMode == 1 then
        if type(XToLevel.db.char.data.timer.start) == "number" and type(XToLevel.db.char.data.timer.total) == "number" and XToLevel.db.char.data.timer.total > 0 then
            XToLevel.db.char.data.timer.xpPerSec = XToLevel.db.char.data.timer.total / (XToLevel.db.char.data.timer.lastUpdated - XToLevel.db.char.data.timer.start)
            local secondsToLevel = (self.maxXP - self.currentXP) / XToLevel.db.char.data.timer.xpPerSec
            XToLevel.Average:UpdateTimer(secondsToLevel)
        elseif type(XToLevel.db.char.data.timer.xpPerSec) == "number" and XToLevel.db.char.data.timer.xpPerSec > 0 then
            -- Fallback method #1, in case no XP has been gained this session, but data remains from the last session.
            local secondsToLevel = (self.maxXP - self.currentXP) / XToLevel.db.char.data.timer.xpPerSec
            XToLevel.Average:UpdateTimer(secondsToLevel)
        else
            -- Fallback method #2. Use level data.
            useMode = 2
        end
    end

    -- Use the level data.
    if useMode == 2 then
        if type(self.timePlayedLevel) == "number" and (self.timePlayedLevel + (XToLevel.db.char.data.timer.lastUpdated - self.timePlayedUpdated)) > 0 then
            local xpPerSec = self.currentXP / (self.timePlayedLevel + (XToLevel.db.char.data.timer.lastUpdated - self.timePlayedUpdated))
            local secondsToLevel = (self.maxXP - self.currentXP) / xpPerSec
            XToLevel.Average:UpdateTimer(secondsToLevel)
        else
            useMode = false
        end
    end

    -- Fallback, in case both above failed.
    if useMode == false then		
        XToLevel.db.char.data.timer.xpPerSec = 0
        XToLevel.Average:UpdateTimer(nil)
    end
    XToLevel.LDB:UpdateTimer()
end

--- Returns details about the estimated time remaining.
-- @return mode, timeToLevel, timePlayed, xpPerHour, totalXP, warning
function XToLevel.Player:GetTimerData()
    local mode = XToLevel.db.profile.timer.mode == 1 and (L['Session'] or "Session") or (L['Level'] or "Level")
    local timePlayed, totalXP, xpPerSecond, xpPerHour, timeToLevel, warning;
    if XToLevel.db.profile.timer.mode == 1 and tonumber(XToLevel.db.char.data.timer.total) > 0 then
        mode = 1
        warning = 0
        timePlayed = GetTime() - XToLevel.db.char.data.timer.start
        totalXP = XToLevel.db.char.data.timer.total
        xpPerSecond = totalXP / timePlayed 
        xpPerHour = ceil(xpPerSecond * 3600)
        timeToLevel = (self.maxXP - self.currentXP) / xpPerSecond
    elseif XToLevel.db.profile.timer.mode == 1 and XToLevel.db.char.data.timer.xpPerSec ~= nil and tonumber(XToLevel.db.char.data.timer.xpPerSec) > 0 then
        mode = 1
        warning = 1
        timePlayed = GetTime() - XToLevel.db.char.data.timer.start
        totalXP = self.currentXP
        xpPerSecond = XToLevel.db.char.data.timer.xpPerSec   
        xpPerHour = ceil(xpPerSecond * 3600)
        timeToLevel = (self.maxXP - self.currentXP) / xpPerSecond
    elseif XToLevel.Player.timePlayedLevel then
        if XToLevel.Player.currentXP > 0 then
            mode = 2
            if XToLevel.db.profile.timer.mode ~= 2 then
                warning = 2
            else
                warning = 0;
            end
            timePlayed = self.timePlayedLevel + (GetTime() - self.timePlayedUpdated)
            totalXP = self.currentXP
            xpPerSecond = totalXP / timePlayed 
            xpPerHour = ceil(xpPerSecond * 3600)
            timeToLevel = (self.maxXP - self.currentXP) / xpPerSecond
        else
            mode = nil
            warning = 3
            timePlayed = self.timePlayedLevel + (GetTime() - self.timePlayedUpdated)
            totalXP = 0
            xpPerSecond = nil
            xpPerHour = nil
            timeToLevel = 0
        end
    else
        mode = nil
        warning = 3
        timePlayed = 0
        totalXP = nil
        xpPerSecond = nil
        xpPerHour = nil
        timeToLevel = 0
    end

    return mode, timeToLevel, timePlayed, xpPerHour, totalXP, warning
end

---
-- Calculatest the unrested XP. If a number is passed, it will be used instead of
-- the player's remaining XP.
-- @param totalXP The total XP gained from a kill
function XToLevel.Player:GetUnrestedXP(totalXP)
    if totalXP == nil then
        totalXP = self.maxXP - self.currentXP
    end
    local killXP = totalXP
    if self.restedXP > 0 then
        if self.restedXP > totalXP / 2 then
            killXP = totalXP / 2
            --self.restedXP = self.restedXP - killXP
        else
            killXP = totalXP - self.restedXP
            --self.restedXP = 0
        end
    end
    return killXP
end

---
-- Adds a kill to the kill list and updates the recorded XP value.
-- @param xpGained The TOTAL amount of XP gained, including bonuses.
-- @param mobName The name of the killed mob.
-- @return The gained XP without any rested bounses.
---
function XToLevel.Player:AddKill(xpGained, mobName)
    self.currentXP = self.currentXP + xpGained

    local killXP = self:GetUnrestedXP(xpGained)

    if self.restedXP > killXP then
        self.restedXP = self.restedXP - killXP
    elseif self.restedXP > 0 then
        self.restedXP = 0
    end

    self.killAverage = nil
    table.insert(XToLevel.db.char.data.killList, 1, {mob=mobName, xp=killXP})
    if(# XToLevel.db.char.data.killList > self.killListLength) then
        table.remove(XToLevel.db.char.data.killList)
    end
    XToLevel.db.char.data.total.mobKills = (XToLevel.db.char.data.total.mobKills or 0) + 1

    return killXP
end

---
-- Adds a quest to the quest list and updates the recorded XP value.
-- @param xpGained The XP gained from the quest.
---
function XToLevel.Player:AddQuest (xpGained)
    self.questAverage = nil
    self.currentXP = self.currentXP + xpGained
    table.insert(XToLevel.db.char.data.questList, 1, xpGained)
    if(# XToLevel.db.char.data.questList > self.questListLength) then
        table.remove(XToLevel.db.char.data.questList)
    end
    XToLevel.db.char.data.total.quests = (XToLevel.db.char.data.total.quests or 0) + 1
end

---
-- Starts recording a dungeon. Fails if already recording a dungeon.
-- @return boolean
---
function XToLevel.Player:DungeonStart()
    if self.isActive and not self:IsDungeonInProgress() then
        local dungeonName = GetRealZoneText()
        local dungeonDataArray = self:CreateDungeonDataArray()
        table.insert(XToLevel.db.char.data.dungeonList, 1, dungeonDataArray)
        if(# XToLevel.db.char.data.dungeonList > self.dungeonListLength) then
            table.remove(XToLevel.db.char.data.dungeonList)
        end

        XToLevel.db.char.data.dungeonList[1].inProgress = true
        XToLevel.db.char.data.dungeonList[1].name = dungeonName or false
        XToLevel.db.char.data.dungeonList[1].level = self.level
        console:log("Dungeon Started! (" .. tostring(XToLevel.db.char.data.dungeonList[1].name) .. ")")
        return true
    else
        console:log("Attempt to start a dungeon failed. Player either not active or already in a dungeon.")
        return false
    end

end

---
-- Stops recording a dungeon. If not recording a dungeon, the function fails.
-- If the dungeon being recorded has yielded no XP, the entry is removed and
-- the function fails.
-- @return boolean
---
function XToLevel.Player:DungeonEnd()
    if XToLevel.db.char.data.dungeonList[1].inProgress == true then
        XToLevel.db.char.data.dungeonList[1].inProgress = false
        self:UpdateDungeonName()
        console:log("Dungeon Ended! (" .. tostring(XToLevel.db.char.data.dungeonList[1].name)  .. ")")

        self.dungeonAverage = nil

        if XToLevel.db.char.data.dungeonList[1].totalXP == 0 then
            table.remove(XToLevel.db.char.data.dungeonList, 1)
            console:log("Dungeon ended without any XP gain. Disregarding it.)")
            return false
        else
            console:log("Dungeon ended successfully")
            return true
        end
    else
        console:log("Attempted to end a Dungeon before one was started.")
        return false
    end
end

---
-- Checks whether a dungeon is in progress.
-- @return boolean
---
function XToLevel.Player:IsDungeonInProgress()
    if # XToLevel.db.char.data.dungeonList > 0 then
        return XToLevel.db.char.data.dungeonList[1].inProgress
    else
        return false
    end
end

---
-- Update the name of the dungeon currently being recorded. If not recording
-- a dungeon, or if the name does not need to be updated, the function fails.
-- @return boolean
---
function XToLevel.Player:UpdateDungeonName()
    local inInstance, type = IsInInstance()
    if self:IsDungeonInProgress() and inInstance and type == "party" then
        local zoneName = GetRealZoneText()
        if XToLevel.db.char.data.dungeonList[1].name ~= zoneName then
            XToLevel.db.char.data.dungeonList[1].name = zoneName
            console:log("Dungeon name updated (" .. tostring(zoneName) ..")")
            return true
        else
            return false
        end
    else
        return false
    end
end

---
-- Adds a kill to the dungeon being recorded. If no dungeon is being recorded
-- the function fails. Note, this function triggers the UpdateDungeonName
-- method, so all dungeons that have a single kill can be asumed to have the
-- correct name associated with it. (Those who do not are discarded anyways)
-- @param xpGained The UNRESTED XP gained from the kill. Ideally, the return
--        value of the AddKill function should be used.
-- @param name The name of the killed mob.
-- @param rested The amount of rested bonus that was gained on top of the
--        base XP.
-- @return boolean
---
function XToLevel.Player:AddDungeonKill(xpGained, name, rested)
    if self:IsDungeonInProgress() then
        XToLevel.db.char.data.dungeonList[1].totalXP = XToLevel.db.char.data.dungeonList[1].totalXP + xpGained
        XToLevel.db.char.data.dungeonList[1].killCount = XToLevel.db.char.data.dungeonList[1].killCount + 1
        XToLevel.db.char.data.dungeonList[1].killTotal = XToLevel.db.char.data.dungeonList[1].killTotal + xpGained
        if type(rested) == "number" and rested > 0 then
            XToLevel.db.char.data.dungeonList[1].rested = XToLevel.db.char.data.dungeonList[1].rested + rested
        end
        XToLevel.db.char.data.total.dungeonKills = (XToLevel.db.char.data.total.dungeonKills or 0) + 1
        self:UpdateDungeonName()
        return true
    else
        console:log("Attempt to add a Dungeon kill without starting a Dungeon.")
        return false
    end
end

---
-- Gets the amount of kills required to reach the next level, based on the
-- passed XP value. The rested bonus is taken into account.
-- @param xp The XP assumed per kill
-- @return An integer or -1 if the input parameter is invalid.
---
function XToLevel.Player:GetKillsRequired(xp)
    if xp > 0 then
        local xpRemaining = self.maxXP - self.currentXP
        local xpRested = self:IsRested()
        if xpRested then
            if((xpRemaining / 2) > xpRested) then
                xpRemaining = xpRemaining - xpRested
            else
                xpRemaining = xpRemaining / 2
            end
        end
        return ceil(xpRemaining / xp)
    else
        return -1
    end
end

---
-- Gets the amount of quests required to reach the next level, based on the
-- passed XP value.
-- @param xp The XP assumed per quest
-- @return An integer or -1 if the input parameter is invalid.
---
function XToLevel.Player:GetQuestsRequired(xp)
    local xpRemaining = self.maxXP - self.currentXP
    if(xp > 0) then
        return ceil(xpRemaining / xp)
    else
        return -1
    end
end

---
-- Gets the percentage of XP already gained towards the next level.
-- @param fractions The number of fraction digits to be used. Defaults to 1.
-- @return A number between 0 and 100, representing the percentage. 
---
function XToLevel.Player:GetProgressAsPercentage(fractions)
    if type(fractions) ~= "number" or fractions <= 0 then
        fractions = 1
    end
    if self.percentage == nil or self.lastKnownXP == nil or self.lastKnownXP ~= self.currentXP then
        self.lastKnownXP = self.currentXP
        self.percentage = (self.currentXP or 0) / (self.maxXP or 1) * 100
    end
    return XToLevel.Lib:round(self.percentage, fractions)
end

---
-- Get the number of "bars" remaining until the next level is reached. Each
-- "bar" represents 5% of the total value.
-- This has become a common measurement used by players when referring
-- to their progress, inspired by the default WoW UI, where the XP progress
-- bar is split into 20 induvidual cells.
-- @param fractions The number of fraction digits to be used. Defautls to 0.
---
function XToLevel.Player:GetProgressAsBars(fractions)
    if type(fractions) ~= "number" or fractions <= 0 then
        fractions = 0
    end
    local barsRemaining = ceil((100 - ((self.currentXP or 0) / (self.maxXP or 1) * 100)) / 5, fractions)
    return barsRemaining
end

function XToLevel.Player:GetXpRemaining() 
    return self.maxXP - self.currentXP
end

function XToLevel.Player:GetRestedPercentage(fractions)
    if type(fractions) ~= "number" or fractions <= 0 then
        fractions = 0
    end
    return XToLevel.Lib:round((self.restedXP * 2) / self.maxXP * 100, fractions, true);
end

---
-- Get the average XP per kill. The number of kills used is limited by the
-- XToLevel.db.profile.averageDisplay.playerKillListLength configuration directive. 
-- The value returned is stored in the killAverage member, so calling this 
-- function twice only calculates the value once. If no data is avaiable, a 
-- level based estimate  is used.
-- Note that the function applies the Recruit-A-Friend bonus when applicable
-- but that does not affect the actual value stored. It is applied only when
-- the value is about to be returned.
-- @return A number.
---
function XToLevel.Player:GetAverageKillXP ()
    if self.killAverage == nil then
        if(# XToLevel.db.char.data.killList > 0) then
            local total = 0
            local maxUsed = # XToLevel.db.char.data.killList
            if maxUsed > XToLevel.db.profile.averageDisplay.playerKillListLength then
                maxUsed = XToLevel.db.profile.averageDisplay.playerKillListLength
            end
            for index, value in ipairs(XToLevel.db.char.data.killList) do
                if index > maxUsed then
                    break;
                end
                total = total + value.xp
            end
            self.killAverage = (total / maxUsed);
        else
            self.killAverage = XToLevel.Lib:MobXP()
        end
    end

    -- Recruit A Friend beta test.
    -- Simply tripples the DISPLAY value. The actual data remains intact.
    if XToLevel.Lib:IsRafApplied() then 
        return (self.killAverage * 3);
    else
        return self.killAverage
    end
end

---
-- Calculates the average, highest and lowest XP values recorded for kills.
-- The range of data used is limited by the 
-- XToLevel.db.profile.averageDisplay.playerKillListLength config directive. If no data 
-- is available, a level based estimate is used. Note that the function 
-- applies the Recruit-A-Friend bonus when applicable but that does not 
-- affect the actual value stored. It is applied only when the value is 
-- about to be returned.
-- @return A table as : { 'average', 'high', 'low' }
---
function XToLevel.Player:GetKillXpRange ()
    if(# XToLevel.db.char.data.killList > 0) then
        self.killRange.high = 0
        self.killRange.low = 0
        self.killRange.average = 0
        local total = 0
        local maxUsed = # XToLevel.db.char.data.killList
        if maxUsed > XToLevel.db.profile.averageDisplay.playerKillListLength then
            maxUsed = XToLevel.db.profile.averageDisplay.playerKillListLength
        end
        for index, value in ipairs(XToLevel.db.char.data.killList) do
            if index > maxUsed then
                break;
            end
            if value.xp < self.killRange.low or self.killRange.low == 0 then
                self.killRange.low = value.xp
            end
            if value.xp > self.killRange.high then
                self.killRange.high = value.xp
            end
            total = total + value.xp
        end
        self.killRange.average = (total / maxUsed);
    else
        self.killRange.average = XToLevel.Lib:MobXP()
        self.killRange.high = self.killRange.average
        self.killRange.low = self.killRange.average
    end

    -- Recruit A Friend beta test.
    -- Simply tripples the DISPLAY value. The actual data remains intact.
    if XToLevel.Lib:IsRafApplied() then 
        return {
            high = self.killRange.high * 3,
            low = self.killRange.low * 3,
            average = self.killRange.average * 3
        }
    else
        return self.killRange
    end
end

---
-- Gets the average number of kills needed to reache the next level, based
-- on the XP value returned by the GetAverageKillXP function.
-- @return A number. -1 if the function fails.
---
function XToLevel.Player:GetAverageKillsRemaining ()
    if(self:GetAverageKillXP() > 0) then
        return self:GetKillsRequired(self:GetAverageKillXP())
    else
        return -1
    end
end

---
-- Get the average XP per quest. The number of quests used is limited by the
-- XToLevel.db.profile.averageDisplay.playerQuestListLength configuration directive. - 
-- The value returned is stored in the questAverage member, so calling this 
-- function twice only calculates the value once. If no data is avaiable, 
-- a level based estimate is used.
-- Note that the function applies the Recruit-A-Friend bonus when applicable
-- but that does not affect the actual value stored. It is applied only when
-- the value is about to be returned.
-- @return A number.
---
function XToLevel.Player:GetAverageQuestXP ()
    if self.questAverage == nil then
        if(# XToLevel.db.char.data.questList > 0) then
            local total = 0
            local maxUsed = # XToLevel.db.char.data.questList
            if maxUsed > XToLevel.db.profile.averageDisplay.playerQuestListLength then
                maxUsed = XToLevel.db.profile.averageDisplay.playerQuestListLength
            end
            for index, value in ipairs(XToLevel.db.char.data.questList) do
                if index > maxUsed then
                    break;
                end
                total = total + value
            end
            self.questAverage = (total / maxUsed);
        else
            -- A very VERY rought and quite possibly very wrong estimate.
            -- But it is accurate for the first few levels, which is where the inaccuracy would be most visible, so...
            self.questAverage = XToLevel.Lib:MobXP() * math.floor(((self.level + 9) / (self.maxLevel + 9)) * 20)
        end
    end
    -- Recruit A Friend beta test.
    -- Simply tripples the DISPLAY value. The actual data remains intact.
    if XToLevel.Lib:IsRafApplied() then 
        return (self.questAverage * 3);
    else
        return self.questAverage
    end
end

---
-- Calculates the average, highest and lowest XP values recorded for quests.
-- The range of data used is limited by the 
-- XToLevel.db.profile.averageDisplay.playerQuestListLength config directive. If no data 
-- is available, a level based estimate is used. Note that the function 
-- applies the Recruit-A-Friend bonus when applicable but that does not 
-- affect the actual value stored. It is applied only whenthe value is about 
-- to be returned.
-- @return A table as : { 'average', 'high', 'low' }
---
function XToLevel.Player:GetQuestXpRange ()
    if(# XToLevel.db.char.data.questList > 0) then
        self.questRange.high = 0
        self.questRange.low = 0
        self.questRange.average = 0
        local total = 0
        local maxUsed = # XToLevel.db.char.data.questList
        if maxUsed > XToLevel.db.profile.averageDisplay.playerQuestListLength then
            maxUsed = XToLevel.db.profile.averageDisplay.playerQuestListLength
        end
        for index, value in ipairs(XToLevel.db.char.data.questList) do
            if index > maxUsed then
                break;
            end
            if value < self.questRange.low or self.questRange.low == 0 then
                self.questRange.low = value
            end
            if value > self.questRange.high then
                self.questRange.high = value
            end
            total = total + value
        end
        self.questAverage = (total / maxUsed);
        self.questRange.average = self.questAverage
    else
        -- A very VERY rought and quite possibly very wrong estimate.
        -- But it is accurate for the first few levels, which is where the inaccuracy would be most visible, so...
        self.questAverage = XToLevel.Lib:MobXP() * math.floor(((self.level + 9) / (self.maxLevel + 9)) * 20)
        self.questRange.high = self.questAverage
        self.questRange.low = self.questAverage
        self.questRange.average = self.questAverage
    end

    -- Recruit A Friend beta test.
    -- Simply tripples the DISPLAY value. The actual data remains intact.
    if XToLevel.Lib:IsRafApplied() then 
        return {
            high = self.questRange.high * 3,
            low = self.questRange.low * 3,
            average = self.questRange.average * 3
        }
    else
        return self.questRange
    end
end

---
-- Gets the average number of quests needed to reache the next level, based
-- on the XP value returned by the GetAverageQuestXP function.
-- @return A number. -1 if the function fails.
---
function XToLevel.Player:GetAverageQuestsRemaining ()
    if(self:GetAverageQuestXP() > 0) then
        return self:GetQuestsRequired(self:GetAverageQuestXP())
    else
        return -1
    end
end

---
-- Gets the average number of quests needed to reach the next level, based
-- on the XP value returned by the GetAverageQuestXP function.
-- @return A number. -1 if the function fails.
---
function XToLevel.Player:GetAveragePetBattlesRemaining ()
    if(self:GetAveragePetBattleXP() > 0) then
        return self:GetPetBattlesRequired(self:GetAveragePetBattleXP())
    else
        return -1
    end
end

---
-- Checks whether any battleground data has been recorded yet.
-- @return boolean
---
function XToLevel.Player:HasBattlegroundData()
    return (# XToLevel.db.char.data.bgList > 0)
end

---
-- Checks whether any dungeon data has been recorded yet.
-- @return boolean
---
function XToLevel.Player:HasDungeonData()
    return (# XToLevel.db.char.data.dungeonList > 0)
end

---
-- Get the average XP per dungeon. The number of dungeons used is limited by
-- the XToLevel.db.profile.averageDisplay.playerDungeonListLength configuration directive.
-- The value returned is stored in the dungeonAverage member, so calling  
-- this function twice only calculates the value once. If no data is, 
-- avaiable a rough level based estimate is used.
-- @return A number.
---
function XToLevel.Player:GetAverageDungeonXP ()
    if self.dungeonAverage == nil then
        if(# XToLevel.db.char.data.dungeonList > 0) and not ((# XToLevel.db.char.data.dungeonList == 1) and XToLevel.db.char.data.dungeonList[1].inProgress) then
            local total = 0
            local maxUsed = # XToLevel.db.char.data.dungeonList
            if maxUsed > XToLevel.db.profile.averageDisplay.playerDungeonListLength then
                maxUsed = XToLevel.db.profile.averageDisplay.playerDungeonListLength
            end
            local usedCounter = 0
            for index, value in ipairs(XToLevel.db.char.data.dungeonList) do
                if usedCounter >= maxUsed then
                    break;
                end
                -- To compensate for the fact that levels were not recorded before 3.3.3_12r.
                if value.level == nil then
                    XToLevel.db.char.data.dungeonList[index].level = self.level
                    value.level = self.level
                end
                if self.level - value.level < 5 then
                    total = total + value.totalXP
                    usedCounter = usedCounter + 1
                end
            end
            if usedCounter > 0 then
                self.dungeonAverage = (total / usedCounter)
            else
                self.dungeonAverage = XToLevel.Lib:MobXP() * 100
            end
        else
            self.dungeonAverage = XToLevel.Lib:MobXP() * 100
        end
    end
    return self.dungeonAverage
end

---
-- Gets the average number of dungeons needed to reache the next level, 
-- basedon the XP value returned by the GetAverageDungeonXP function.
-- @return A number. nil if the function fails.
---
function XToLevel.Player:GetAverageDungeonsRemaining()
    local dungeonAverage = self:GetAverageDungeonXP()
    if(dungeonAverage > 0) then
        return self:GetKillsRequired(dungeonAverage)
    else
        return nil
    end
end

---
-- Gets the names of all dungeons that have been recorded so far.
-- @return A { 'name' = count, ... } table on success or nil if no data exists.
---
function XToLevel.Player:GetDungeonsListed ()
    if # XToLevel.db.char.data.dungeonList > 0 then
        -- Clear list in a memory efficient way.
        for index, value in pairs(self.dungeonList) do
            self.dungeonList[index] = 0
        end
        local count = 0
        for index, value in ipairs(XToLevel.db.char.data.dungeonList) do
            if value.level == nil then
                XToLevel.db.char.data.dungeonList[index].level = self.level
                value.level = self.level
            end
            if self.level - value.level < 5 and value.totalXP > 0 and not value.inProgress then
                self.dungeonList[value.name] = (self.dungeonList[value.name] or 0) + 1
                count = count + 1
            end
        end
        if count > 0 then
            return self.dungeonList;
        else
            return nil
        end
    else
        return nil
    end
end

---
-- Returns the average XP for the given dungeon. The data is limited by
-- the XToLevel.db.profile.averageDisplay.playerDungeonListLength config directive. Note
-- that dungeons currently in progress will not be counted.
-- @param name The name of the dungeon to be used.
-- @return A number. If the database has no entries, it returns 0.
---
function XToLevel.Player:GetDungeonAverage(name)
    if(# XToLevel.db.char.data.dungeonList > 0) then
        local total = 0
        local count = 0
        local maxcount = XToLevel.db.profile.averageDisplay.playerDungeonListLength
        for index, value in ipairs(XToLevel.db.char.data.dungeonList) do
            if count >= maxcount then
                break
            end
            if value.level == nil then
                XToLevel.db.char.data.dungeonList[index].level = self.level
                value.level = self.level
            end
            if value.name == name and not value.inProgress and (self.level - value.level < 5) then
                total = total + value.totalXP
                count = count + 1
            end
        end
        if count == 0 then
            return 0
        else
            return XToLevel.Lib:round(total / count, 0)
        end
    else
        return 0
    end
end

---
-- Gets details for the last entry in the dungeon list.
-- @return A table matching the CreateDungeonDataArray template, or nil if
--         no battlegrounds have been recorded yet.
---
function XToLevel.Player:GetLatestDungeonDetails()
    if # XToLevel.db.char.data.dungeonList > 0 then
        self.latestDungeonData.totalXP = XToLevel.db.char.data.dungeonList[1].totalXP
        self.latestDungeonData.killCount = XToLevel.db.char.data.dungeonList[1].killCount
        self.latestDungeonData.xpPerKill = 0
        self.latestDungeonData.rested = XToLevel.db.char.data.dungeonList[1].rested
        self.latestDungeonData.otherXP = XToLevel.db.char.data.dungeonList[1].totalXP - XToLevel.db.char.data.dungeonList[1].killTotal          
        if self.latestDungeonData.killCount > 0 then
            self.latestDungeonData.xpPerKill = XToLevel.Lib:round(XToLevel.db.char.data.dungeonList[1].killTotal / self.latestDungeonData.killCount, 0)
        end

        return self.latestDungeonData
    else
        return nil
    end
end

---
-- Clears the kill list. If the initialValue parameter is passed, a single
-- entry with that value is added.
-- @param initalValue The inital value for the list. [optional]
function XToLevel.Player:ClearKills (initialValue)
    XToLevel.db.char.data.killList = { }
    self.killAverage = nil;
    if initialValue ~= nil and tonumber(initialValue) > 0 then
        table.insert(XToLevel.db.char.data.killList, {mob='Initial', xp=tonumber(initialValue)})
    end
end

---
-- Clears the quest list. If the initialValue parameter is passed, a single
-- entry with that value is added.
-- @param initalValue The inital value for the list. [optional]
function XToLevel.Player:ClearQuests (initialValue)
    XToLevel.db.char.data.questList = { }
    self.questAverage = nil;
    if initialValue ~= nil and tonumber(initialValue) > 0 then
        table.insert(XToLevel.db.char.data.questList, tonumber(initialValue))
    end
end

---
-- Clears the dungeon list. If the initialValue parameter is passed, a 
-- single entry with that value is added.
function XToLevel.Player:ClearDungeonList(initialValue)
    XToLevel.db.char.data.dungeonList = { }
    self.dungeonAverage = nil;

    local inInstance, type = IsInInstance()
    if inInstance and type == "party" then
        self:DungeonStart()
    end
end

---
-- Checks whether the player is rested.
-- @return The additional XP the player will get until he is unrested again
--         or FALSE if the player is not rested.
---
function XToLevel.Player:IsRested()
    if self.restedXP > 0 then
        return self.restedXP
    else
        return false
    end
end

---
-- Sets the number of kills used for average calculations
function XToLevel.Player:SetKillAverageLength(newValue)
    XToLevel.db.profile.averageDisplay.playerKillListLength = newValue
    self.killAverage = nil
    XToLevel.Average:Update()
    XToLevel.LDB:BuildPattern()
    XToLevel.LDB:Update()
end

---
-- Sets the number of quests used for average calculations
function XToLevel.Player:SetQuestAverageLength(newValue)
    XToLevel.db.profile.averageDisplay.playerQuestListLength = newValue
    self.questAverage = nil
    XToLevel.Average:Update()
    XToLevel.LDB:BuildPattern()
    XToLevel.LDB:Update()
end

---
-- Sets the number of dungeon used for average calculations
function XToLevel.Player:SetDungeonAverageLength(newValue)
    XToLevel.db.profile.averageDisplay.playerDungeonListLength = newValue
    self.dungeonAverage = nil
    XToLevel.Average:Update()
    XToLevel.LDB:BuildPattern()
    XToLevel.LDB:Update()
end
