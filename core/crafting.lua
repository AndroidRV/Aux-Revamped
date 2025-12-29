module 'aux.core.crafting'

local T = require 'T'
local aux = require 'aux'
local info = require 'aux.util.info'
local money = require 'aux.util.money'
local history = require 'aux.core.history'
local search_tab = require 'aux.tabs.search'

function aux.handle.LOAD()
    if not aux.account_data.crafting_cost then
        return
    end
    aux.event_listener('ADDON_LOADED', function()
        if arg1 == 'Blizzard_CraftUI' then
            craft_ui_loaded()
        elseif arg1 == 'Blizzard_TradeSkillUI' then
            trade_skill_ui_loaded()
        end
    end)
end

do
    -- Cache for last known cost/profit values per recipe
    local cached_costs = {}

    -- Calculate profit for a tradeskill recipe (returns cost, profit)
    local function calculate_tradeskill_profit(id)
        local total_cost = 0
        local profit = nil

        -- Calculate total cost of reagents
        for i = 1, GetTradeSkillNumReagents(id) do
            local link = GetTradeSkillReagentItemLink(id, i)
            if not link then
                total_cost = nil
                break
            end
            local item_id, suffix_id = info.parse_link(link)
            local item_key = item_id .. ':' .. suffix_id
            local count = aux.select(3, GetTradeSkillReagentInfo(id, i))
            local _, price, limited = info.merchant_info(item_id)
            local value = price and not limited and price or history.market_value(item_key) or history.recent_value(item_key)
            if not value then
                total_cost = nil
                break
            else
                total_cost = total_cost + value * count
            end
        end

        -- Calculate profit if we have total cost
        if total_cost then
            local item_link = GetTradeSkillItemLink(id)
            if item_link then
                local item_id, suffix_id = info.parse_link(item_link)
                local item_key = item_id .. ':' .. suffix_id
                local item_value = history.market_value(item_key) or history.recent_value(item_key)
                if item_value then
                    local min_made, max_made = GetTradeSkillNumMade(id)
                    local avg_made = (min_made + max_made) / 2
                    profit = (item_value * avg_made) - total_cost
                end
            end
        end

        return total_cost, profit
    end

    -- Calculate profit for a craft recipe (returns cost, profit)
    local function calculate_craft_profit(id)
        local total_cost = 0
        local profit = nil

        -- Calculate total cost of reagents
        for i = 1, GetCraftNumReagents(id) do
            local link = GetCraftReagentItemLink(id, i)
            if not link then
                total_cost = nil
                break
            end
            local item_id, suffix_id = info.parse_link(link)
            local item_key = item_id .. ':' .. suffix_id
            local count = aux.select(3, GetCraftReagentInfo(id, i))
            local _, price, limited = info.merchant_info(item_id)
            local value = price and not limited and price or history.market_value(item_key) or history.recent_value(item_key)
            if not value then
                total_cost = nil
                break
            else
                total_cost = total_cost + value * count
            end
        end

        -- Calculate profit if we have total cost
        if total_cost then
            local item_link = GetCraftItemLink(id)
            if item_link then
                local item_id, suffix_id = info.parse_link(item_link)
                local item_key = item_id .. ':' .. suffix_id
                local item_value = history.market_value(item_key) or history.recent_value(item_key)
                if item_value then
                    local min_made, max_made = GetCraftNumMade(id)
                    local avg_made = (min_made + max_made) / 2
                    profit = (item_value * avg_made) - total_cost
                end
            end
        end

        return total_cost, profit
    end

    -- Format profit as a short suffix (e.g., " +63g" or " -5g")
    local function profit_suffix(profit)
        if not profit then return '' end
        local gold = floor(abs(profit) / 10000)
        local silver = floor(mod(abs(profit), 10000) / 100)
        if profit > 0 then
            if gold > 0 then
                return GREEN_FONT_COLOR_CODE .. ' +' .. gold .. 'g' .. FONT_COLOR_CODE_CLOSE
            elseif silver > 0 then
                return GREEN_FONT_COLOR_CODE .. ' +' .. silver .. 's' .. FONT_COLOR_CODE_CLOSE
            else
                return ''
            end
        elseif profit < 0 then
            if gold > 0 then
                return RED_FONT_COLOR_CODE .. ' -' .. gold .. 'g' .. FONT_COLOR_CODE_CLOSE
            elseif silver > 0 then
                return RED_FONT_COLOR_CODE .. ' -' .. silver .. 's' .. FONT_COLOR_CODE_CLOSE
            else
                return ''
            end
        end
        return ''
    end

    local function cost_label(cost, profit, recipe_id, devilsaur_leather_value)
        -- Cache the values if they're valid
        if cost and recipe_id then
            if not cached_costs[recipe_id] then
                cached_costs[recipe_id] = {}
            end
            cached_costs[recipe_id].cost = cost
            cached_costs[recipe_id].profit = profit
            cached_costs[recipe_id].devilsaur_leather_value = devilsaur_leather_value
        end

        -- If cost is nil, try to use cached value
        if not cost and recipe_id and cached_costs[recipe_id] then
            cost = cached_costs[recipe_id].cost
            profit = cached_costs[recipe_id].profit
            devilsaur_leather_value = cached_costs[recipe_id].devilsaur_leather_value
        end

        local label = LIGHTYELLOW_FONT_COLOR_CODE .. '(Total Cost: ' .. FONT_COLOR_CODE_CLOSE
        label = label .. (cost and money.to_string2(cost, nil, LIGHTYELLOW_FONT_COLOR_CODE) or GRAY_FONT_COLOR_CODE .. '?' .. FONT_COLOR_CODE_CLOSE)

        -- Add profit if available
        if profit then
            if profit > 0 then
                label = label .. LIGHTYELLOW_FONT_COLOR_CODE .. ' | ' .. FONT_COLOR_CODE_CLOSE
                label = label .. GREEN_FONT_COLOR_CODE .. 'Profit: ' .. money.to_string2(profit) .. FONT_COLOR_CODE_CLOSE
            elseif profit < 0 then
                label = label .. LIGHTYELLOW_FONT_COLOR_CODE .. ' | ' .. FONT_COLOR_CODE_CLOSE
                label = label .. RED_FONT_COLOR_CODE .. 'Loss: ' .. money.to_string2(-profit) .. FONT_COLOR_CODE_CLOSE
            else
                label = label .. LIGHTYELLOW_FONT_COLOR_CODE .. ' | Break Even' .. FONT_COLOR_CODE_CLOSE
            end
        end

        -- Add Devilsaur Leather value if available
        if devilsaur_leather_value then
            label = label .. LIGHTYELLOW_FONT_COLOR_CODE .. ' | ' .. FONT_COLOR_CODE_CLOSE
            label = label .. '|cff4A9FF5' .. 'Leather Value: ' .. money.to_string2(devilsaur_leather_value) .. FONT_COLOR_CODE_CLOSE
        end

        label = label .. LIGHTYELLOW_FONT_COLOR_CODE .. ')' .. FONT_COLOR_CODE_CLOSE
        return label
    end
    local function hook_quest_item(f)
        f:SetScript('OnMouseUp', function()
            if arg1 == 'RightButton' then
                if aux.get_tab() then
                    aux.set_tab(1)
                    search_tab.set_filter(_G[this:GetName() .. 'Name']:GetText() .. '/exact')
                    search_tab.execute(nil, false)
                end
            end
        end)
    end
    function craft_ui_loaded()
        aux.hook('CraftFrame_SetSelection', T.vararg-function(arg)
            local ret = T.temp-T.list(aux.orig.CraftFrame_SetSelection(unpack(arg)))
            local id = GetCraftSelectionIndex()
            local total_cost = 0
            local profit = nil

            -- Calculate total cost of reagents
            for i = 1, GetCraftNumReagents(id) do
                local link = GetCraftReagentItemLink(id, i)
                if not link then
                    total_cost = nil
                    break
                end
                local item_id, suffix_id = info.parse_link(link)
                local item_key = item_id .. ':' .. suffix_id
                local count = aux.select(3, GetCraftReagentInfo(id, i))
                local _, price, limited = info.merchant_info(item_id)
                -- Use vendor price if available (and not limited supply), else try market_value, else fall back to recent value (last 3 days)
                local value = price and not limited and price or history.market_value(item_key) or history.recent_value(item_key)
                if not value then
                    total_cost = nil
                    break
                else
                    total_cost = total_cost + value * count
                end
            end

            -- Calculate profit if we have total cost
            if total_cost then
                local item_link = GetCraftItemLink(id)
                if item_link then
                    local item_id, suffix_id = info.parse_link(item_link)
                    local item_key = item_id .. ':' .. suffix_id
                    -- Try market_value (today's lowest) first, fall back to recent_value (last 3 days)
                    local item_value = history.market_value(item_key) or history.recent_value(item_key)
                    if item_value then
                        -- Calculate number created (some recipes create multiple items)
                        local min_made, max_made = GetCraftNumMade(id)
                        local avg_made = (min_made + max_made) / 2
                        profit = (item_value * avg_made) - total_cost
                    end
                end
            end

            CraftReagentLabel:SetText(SPELL_REAGENTS .. ' ' .. cost_label(total_cost, profit, 'craft_' .. id, nil))
            return unpack(ret)
        end)
        for i = 1, 8 do
            hook_quest_item(_G['CraftReagent' .. i])
        end

        -- Hook CraftFrame_Update to add profit suffixes to recipe list
        aux.hook('CraftFrame_Update', function()
            aux.orig.CraftFrame_Update()
            local num_crafts = GetNumCrafts()
            local craft_offset = FauxScrollFrame_GetOffset(CraftListScrollFrame)
            for i = 1, CRAFTS_DISPLAYED do
                local craft_index = craft_offset + i
                if craft_index <= num_crafts then
                    local craft_name, _, craft_type = GetCraftInfo(craft_index)
                    -- Only add profit to actual recipes, not headers
                    if craft_type ~= 'header' and craft_name then
                        local _, profit = calculate_craft_profit(craft_index)
                        local suffix = profit_suffix(profit)
                        if suffix ~= '' then
                            local text_element = _G['Craft' .. i .. 'Text']
                            if text_element then
                                local current_text = text_element:GetText()
                                if current_text then
                                    text_element:SetText(current_text .. suffix)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
    function trade_skill_ui_loaded()
        aux.hook('TradeSkillFrame_SetSelection', T.vararg-function(arg)
            local ret = T.temp-T.list(aux.orig.TradeSkillFrame_SetSelection(unpack(arg)))
            local id = GetTradeSkillSelectionIndex()
            local total_cost = 0
            local profit = nil
            local devilsaur_leather_value = nil

            -- Get recipe name to check if it's a Devilsaur recipe
            local recipe_name = GetTradeSkillInfo(id)
            local is_devilsaur = recipe_name and string.find(recipe_name, "Devilsaur")

            -- Track costs and reagent info for Devilsaur calculations
            local devilsaur_leather_count = 0
            local other_reagents_cost = 0
            local all_reagents_available = true

            -- Calculate total cost of reagents
            for i = 1, GetTradeSkillNumReagents(id) do
                local link = GetTradeSkillReagentItemLink(id, i)
                if not link then
                    total_cost = nil
                    all_reagents_available = false
                    break
                end
                local item_id, suffix_id = info.parse_link(link)
                local item_key = item_id .. ':' .. suffix_id
                local reagent_name = aux.select(1, GetTradeSkillReagentInfo(id, i))
                local count = aux.select(3, GetTradeSkillReagentInfo(id, i))
                local _, price, limited = info.merchant_info(item_id)
                -- Use vendor price if available (and not limited supply), else try market_value, else fall back to recent value (last 3 days)
                local value = price and not limited and price or history.market_value(item_key) or history.recent_value(item_key)
                if not value then
                    total_cost = nil
                    all_reagents_available = false
                    break
                else
                    total_cost = total_cost + value * count
                    -- Track Devilsaur Leather separately for Devilsaur recipes
                    if is_devilsaur and reagent_name and string.find(reagent_name, "Devilsaur Leather") then
                        devilsaur_leather_count = devilsaur_leather_count + count
                    else
                        other_reagents_cost = other_reagents_cost + value * count
                    end
                end
            end

            -- Calculate profit if we have total cost
            if total_cost then
                local item_link = GetTradeSkillItemLink(id)
                if item_link then
                    local item_id, suffix_id = info.parse_link(item_link)
                    local item_key = item_id .. ':' .. suffix_id
                    -- Try market_value (today's lowest) first, fall back to recent_value (last 3 days)
                    local item_value = history.market_value(item_key) or history.recent_value(item_key)
                    if item_value then
                        -- Calculate number created (some recipes create multiple items)
                        local min_made, max_made = GetTradeSkillNumMade(id)
                        local avg_made = (min_made + max_made) / 2
                        profit = (item_value * avg_made) - total_cost

                        -- Calculate Devilsaur Leather value for Devilsaur recipes
                        if is_devilsaur and devilsaur_leather_count > 0 and all_reagents_available then
                            -- Value per Devilsaur Leather = (Item Sell Price - Other Reagents Cost) / Devilsaur Leather Count
                            devilsaur_leather_value = ((item_value * avg_made) - other_reagents_cost) / devilsaur_leather_count
                        end
                    end
                end
            end

			TradeSkillReagentLabel:SetText(SPELL_REAGENTS .. ' ' .. cost_label(total_cost, profit, 'tradeskill_' .. id, devilsaur_leather_value))
			if ATSWReagentLabel then
				ATSWReagentLabel:SetText(SPELL_REAGENTS .. ' ' .. cost_label(total_cost, profit, 'tradeskill_' .. id, devilsaur_leather_value))
			end
            return unpack(ret)
        end)
        for i = 1, 8 do
            hook_quest_item(_G['TradeSkillReagent' .. i])
        end

        -- Hook TradeSkillFrame_Update to add profit suffixes to recipe list
        aux.hook('TradeSkillFrame_Update', function()
            aux.orig.TradeSkillFrame_Update()
            local num_skills = GetNumTradeSkills()
            local skill_offset = FauxScrollFrame_GetOffset(TradeSkillListScrollFrame)
            for i = 1, TRADE_SKILLS_DISPLAYED do
                local skill_index = skill_offset + i
                if skill_index <= num_skills then
                    local skill_name, skill_type = GetTradeSkillInfo(skill_index)
                    -- Only add profit to actual recipes, not headers
                    if skill_type ~= 'header' and skill_name then
                        local _, profit = calculate_tradeskill_profit(skill_index)
                        local suffix = profit_suffix(profit)
                        if suffix ~= '' then
                            local text_element = _G['TradeSkillSkill' .. i .. 'Text']
                            if text_element then
                                local current_text = text_element:GetText()
                                if current_text then
                                    text_element:SetText(current_text .. suffix)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
end