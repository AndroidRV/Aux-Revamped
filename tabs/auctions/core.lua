module 'aux.tabs.auctions'

local T = require 'T'
local aux = require 'aux'
local info = require 'aux.util.info'
local scan_util = require 'aux.util.scan'
local scan = require 'aux.core.scan'
local crafting = require 'aux.core.crafting'

local tab = aux.tab 'Auctions'

auction_records = T.acquire()

-- Public function to get auction records
function M.get_auction_records()
    return auction_records
end

function tab.OPEN()
    frame:Show()
    scan_auctions()
end

function tab.CLOSE()
    frame:Hide()
end

function update_listing()
    listing:SetDatabase(auction_records)
end

function M.scan_auctions()

    status_bar:update_status(0, 0)
    status_bar:set_text('|cff3399ffScanning auctions...|r')

    T.wipe(auction_records)
    update_listing()
    scan.start{
        type = 'owner',
        queries = {{blizzard_query = T.acquire()}},
        on_page_loaded = function(page, total_pages)
            status_bar:update_status(page / total_pages, 0)
            status_bar:set_text(format('|cff3399ffScanning|r (Page |cffff8000%d|r / |cff00ff00%d|r)', page, total_pages))
        end,
        on_auction = function(auction_record)
            tinsert(auction_records, auction_record)
        end,
        on_complete = function()
            status_bar:update_status(1, 1)
            status_bar:set_text('|cff00ff00Scan complete|r')
            update_listing()
            -- Invalidate crafting cache so "In AH" indicators update
            crafting.invalidate_auction_cache()
        end,
        on_abort = function()
            status_bar:update_status(1, 1)
            status_bar:set_text('|cffff0000Scan aborted|r')
        end,
    }
end

do
    local scan_id = 0
    local IDLE, SEARCHING, FOUND = aux.enum(3)
    local state = IDLE
    local found_index

    function find_auction(record)
        if not listing:ContainsRecord(record) then return end

        scan.abort(scan_id)
        state = SEARCHING
        scan_id = scan_util.find(
            record,
            status_bar,
            function() state = IDLE end,
            function() state = IDLE; listing:RemoveAuctionRecord(record) end,
            function(index)
                state = FOUND
                found_index = index

                cancel_button:SetScript('OnClick', function()
                    if scan_util.test(record, index) and listing:ContainsRecord(record) then
                        aux.cancel_auction(index, function() listing:RemoveAuctionRecord(record) end)
                    end
                end)
                cancel_button:Enable()
            end
        )
    end

    function on_update()
        if state == IDLE or state == SEARCHING then
            cancel_button:Disable()
        end

        if state == SEARCHING then return end

        local selection = listing:GetSelection()
        if not selection then
            state = IDLE
        elseif selection and state == IDLE then
            find_auction(selection.record)
        elseif state == FOUND and not scan_util.test(selection.record, found_index) then
            cancel_button:Disable()
            if not aux.cancel_in_progress() then state = IDLE end
        end
    end
end

do
    local checking = false
    local check_queue = {}
    local current_check_index = 1
    local canceling = false
    local cancel_queue = {}
    local cancel_index = 1

    -- Debug logging helper
    local function debug_log(msg)
        if aux.account_data.undercut_debug then
            DEFAULT_CHAT_FRAME:AddMessage(msg)
        end
    end

    -- Extract first word from item name for dynamic prefix detection
    local function extract_first_word(item_name)
        if not item_name then
            return nil
        end

        -- Find first space
        local space_pos = string.find(item_name, ' ')

        if space_pos then
            -- Return substring before first space
            return string.sub(item_name, 1, space_pos - 1)
        else
            -- No space found - single word name
            return item_name
        end
    end

    function M.check_undercuts()
        if checking or canceling then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff0000Operation already in progress!|r')
            return
        end

        if table.getn(auction_records) == 0 then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff0000No auctions to check!|r')
            return
        end

        -- Reset queue and status
        T.wipe(check_queue)
        current_check_index = 1
        checking = true

        -- Group items by prefix + class combination for efficient batch checking
        local prefix_class_groups = {}  -- Keyed by "prefix|class_index"
        local solo_items = {}

        -- Pass 1: Initial grouping by prefix + class
        local min_quality = aux.account_data.undercut_min_quality or 2
        for i = 1, table.getn(auction_records) do
            local record = auction_records[i]
            if record.buyout_price and record.buyout_price > 0 then
                record.undercut_status = nil

                -- Extract first word as prefix
                local prefix = extract_first_word(record.name)
                if not prefix then
                    record.undercut_status = 'error'
                    debug_log('|cffff0000[Group] Item has no name: ' .. tostring(record.item_id) .. '|r')
                else
                    -- Get item info for class and quality
                    local item_info = info.item(record.item_key)

                    -- Only check items at or above the configured minimum quality
                    if not item_info or not item_info.quality or item_info.quality < min_quality then
                        -- Skip items below rare quality
                        record.undercut_status = nil
                        debug_log('|cff888888[Skip] ' .. record.name .. ' - quality too low (' .. tostring(item_info and item_info.quality or 'unknown') .. ')|r')
                    else
                        -- Get class, subclass, and quality indices
                        local class_index = nil
                        local subclass_index = nil
                        local quality = item_info.quality

                        if item_info.class then
                            class_index = info.item_class_index(item_info.class)
                            if class_index and item_info.subclass then
                                subclass_index = info.item_subclass_index(class_index, item_info.subclass)
                            end
                        end

                        -- Create composite key: "prefix|class|subclass|quality"
                        local group_key = prefix .. '|' .. tostring(class_index or 'nil') .. '|' .. tostring(subclass_index or 'nil') .. '|' .. tostring(quality or 'nil')

                        -- Create group if doesn't exist
                        if not prefix_class_groups[group_key] then
                            prefix_class_groups[group_key] = {
                                prefix = prefix,
                                class = class_index,
                                subclass = subclass_index,
                                quality = quality,
                                items = {},
                            }
                        end

                        -- Add item to group
                        tinsert(prefix_class_groups[group_key].items, record)
                    end
                end
            else
                record.undercut_status = 'no_buyout'
            end
        end

        -- Pass 2: Separate multi-item groups from solo items
        for group_key, group in pairs(prefix_class_groups) do
            local item_count = table.getn(group.items)

            if item_count >= 2 then
                -- Multi-item group: Use prefix search
                tinsert(check_queue, {
                    search_name = group.prefix,
                    class = group.class,
                    subclass = group.subclass,
                    quality = group.quality,
                    items = group.items,
                })
                debug_log('|cff00ff00[Group] ' .. group.prefix .. ' (class=' .. tostring(group.class) .. ' subclass=' .. tostring(group.subclass) .. ' quality=' .. tostring(group.quality) .. ') -> ' .. item_count .. ' items (prefix search)|r')
            else
                -- Solo item: Store with all filters for later
                tinsert(solo_items, {
                    item = group.items[1],
                    class = group.class,
                    subclass = group.subclass,
                    quality = group.quality,
                })
            end
        end

        -- Pass 3: Add solo items to queue with full name searches
        for i = 1, table.getn(solo_items) do
            local solo = solo_items[i]
            tinsert(check_queue, {
                search_name = solo.item.name,  -- Full name, not prefix
                class = solo.class,
                subclass = solo.subclass,
                quality = solo.quality,
                items = {solo.item},           -- Single item in array
            })
            debug_log('|cff00ffff[Solo] "' .. solo.item.name .. '" (class=' .. tostring(solo.class) .. ' subclass=' .. tostring(solo.subclass) .. ' quality=' .. tostring(solo.quality) .. ') (individual search)|r')
        end

        if table.getn(check_queue) == 0 then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff0000No auctions with buyouts to check!|r')
            checking = false
            return
        end

        debug_log('|cff00ff00[Undercut] Grouped ' .. table.getn(auction_records) .. ' items into ' .. table.getn(check_queue) .. ' search queries|r')

        undercut_button:SetText('Checking...')
        undercut_button:Disable()
        status_bar:update_status(0, 0)
        status_bar:set_text('|cff3399ffStarting undercut check...|r')
        update_listing()

        -- Start checking first group
        check_next_item()
    end

    function check_next_item()
        if current_check_index > table.getn(check_queue) then
            -- All done
            checking = false
            undercut_button:SetText('Check Undercuts')
            undercut_button:Enable()
            status_bar:update_status(1, 1)
            status_bar:set_text('|cff00ff00Undercut check complete|r')

            -- Count results
            local undercut_count = 0
            for i = 1, table.getn(auction_records) do
                if auction_records[i].undercut_status == 'undercut' then
                    undercut_count = undercut_count + 1
                end
            end

            if undercut_count > 0 then
                DEFAULT_CHAT_FRAME:AddMessage('|cffff0000' .. undercut_count .. ' auction(s) have been undercut! Auto-canceling...|r')
                -- Automatically start canceling undercut items
                cancel_all_undercut()
            else
                DEFAULT_CHAT_FRAME:AddMessage('|cff00ff00No auctions undercut|r')
                undercut_button:SetText('Check Undercuts')
                undercut_button:Enable()
            end
            return
        end

        local group = check_queue[current_check_index]
        local total = table.getn(check_queue)

        -- Update progress
        status_bar:update_status((current_check_index - 1) / total, 0)
        status_bar:set_text(format('|cff3399ffChecking undercuts...|r (|cffff8000%d|r / |cff00ff00%d|r)', current_check_index, total))

        -- Mark all items in group as checking
        for i = 1, table.getn(group.items) do
            group.items[i].undercut_status = 'checking'
        end
        update_listing()

        -- Query AH for this prefix (checks multiple items in one query)
        local auction_count = 0
        local item_names = {}
        for i = 1, table.getn(group.items) do
            tinsert(item_names, group.items[i].name)
        end

        debug_log('|cff00ffff[Undercut] Searching for: "' .. group.search_name .. '" (' .. table.getn(group.items) .. ' items)|r')

        -- Build query with all available filters
        local query = {
            name = group.search_name,
        }
        if group.class then
            query.class = group.class
        end
        if group.subclass then
            query.subclass = group.subclass
        end
        if group.quality then
            query.quality = group.quality
        end

        debug_log('|cffff00ff[Query] name=' .. tostring(query.name) .. ', class=' .. tostring(query.class) .. ', subclass=' .. tostring(query.subclass) .. ', quality=' .. tostring(query.quality) .. '|r')

        scan.start{
            type = 'list',
            queries = {{
                blizzard_query = query
            }},
            on_page_loaded = function(page, total_pages)
                debug_log('|cff00ffff[Undercut] Page ' .. page .. ' of ' .. total_pages .. ' loaded|r')
            end,
            on_auction = function(auction_record)
                auction_count = auction_count + 1

                -- Check this auction against ALL items in the group
                for i = 1, table.getn(group.items) do
                    local item = group.items[i]

                    -- Only check matching item
                    if auction_record.item_key == item.item_key and
                       auction_record.buyout_price > 0 then

                        local is_own = info.is_player(auction_record.owner)
                        local is_undercut = auction_record.unit_buyout_price <= item.unit_buyout_price

                        debug_log(format('|cff00ffff[Compare] %s: AH=%s (own=%s) price=%d vs Your price=%d -> %s|r',
                            item.name or "Unknown",
                            auction_record.owner or "Unknown",
                            tostring(is_own),
                            auction_record.unit_buyout_price or 0,
                            item.unit_buyout_price or 0,
                            (not is_own and is_undercut) and 'UNDERCUT' or 'OK'
                        ))

                        if not is_own and is_undercut then
                            -- This auction undercuts or ties this item
                            item.undercut_status = 'undercut'
                            item.undercut_by_price = auction_record.unit_buyout_price
                        end
                    end
                end
            end,
            on_complete = function()
                -- Mark any items not undercut as lowest
                local undercut_in_group = 0
                for i = 1, table.getn(group.items) do
                    if group.items[i].undercut_status == 'undercut' then
                        undercut_in_group = undercut_in_group + 1
                    elseif group.items[i].undercut_status == 'checking' then
                        group.items[i].undercut_status = 'lowest'
                    end
                end

                debug_log('|cff00ff00[Undercut] Checked ' .. auction_count .. ' auctions - ' .. undercut_in_group .. ' of ' .. table.getn(group.items) .. ' items undercut|r')
                update_listing()
                current_check_index = current_check_index + 1
                check_next_item()
            end,
            on_abort = function()
                DEFAULT_CHAT_FRAME:AddMessage('|cffff0000[Undercut Error] Failed to check group "' .. group.search_name .. '"|r')
                for i = 1, table.getn(group.items) do
                    group.items[i].undercut_status = 'error'
                end
                update_listing()
                current_check_index = current_check_index + 1
                check_next_item()
            end,
        }
    end

    -- Cancel all undercut items automatically
    function cancel_all_undercut()
        if canceling then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff0000Cancel already in progress!|r')
            return
        end

        -- Build queue of undercut items
        T.wipe(cancel_queue)
        for i = 1, table.getn(auction_records) do
            if auction_records[i].undercut_status == 'undercut' then
                tinsert(cancel_queue, auction_records[i])
            end
        end

        if table.getn(cancel_queue) == 0 then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff0000No undercut items to cancel!|r')
            return
        end

        canceling = true
        cancel_index = 1
        undercut_button:SetText('Canceling...')
        undercut_button:Disable()
        status_bar:update_status(0, 0)
        status_bar:set_text('|cffff0000Starting auto-cancel...|r')

        DEFAULT_CHAT_FRAME:AddMessage('|cffff0000Auto-canceling ' .. table.getn(cancel_queue) .. ' undercut auction(s)...|r')

        -- Start canceling first item
        cancel_next_item()
    end

    function cancel_next_item()
        if cancel_index > table.getn(cancel_queue) then
            -- All done
            canceling = false
            undercut_button:SetText('Check Undercuts')
            undercut_button:Enable()
            status_bar:update_status(1, 1)
            status_bar:set_text('|cff00ff00Auto-cancel complete|r')
            DEFAULT_CHAT_FRAME:AddMessage('|cff00ff00Successfully canceled ' .. table.getn(cancel_queue) .. ' auction(s)!|r')

            -- Refresh auction list
            scan_auctions()
            return
        end

        local record = cancel_queue[cancel_index]
        local total = table.getn(cancel_queue)

        -- Update progress
        status_bar:update_status((cancel_index - 1) / total, 0)
        status_bar:set_text(format('|cffff0000Canceling...|r (|cffff8000%d|r / |cff00ff00%d|r)', cancel_index, total))

        -- Show which item we're canceling
        DEFAULT_CHAT_FRAME:AddMessage(format('|cffff8000[%d/%d] Canceling:|r |cff00ffff%s|r', cancel_index, total, record.name))

        debug_log('|cffffff00[Cancel] Finding and canceling: ' .. record.name .. '|r')

        -- Find and cancel this auction
        scan_util.find(
            record,
            status_bar,
            function()
                -- Not found / search complete
                DEFAULT_CHAT_FRAME:AddMessage('|cffff0000[Cancel Error] Could not find ' .. record.name .. ' - skipping|r')
                cancel_index = cancel_index + 1
                cancel_next_item()
            end,
            function()
                -- Auction no longer exists
                debug_log('|cffffff00[Cancel] Auction already gone: ' .. record.name .. '|r')
                listing:RemoveAuctionRecord(record)
                cancel_index = cancel_index + 1
                cancel_next_item()
            end,
            function(index)
                -- Found the auction, now cancel it
                debug_log('|cff00ff00[Cancel] Found ' .. record.name .. ' at index ' .. index .. ', canceling...|r')
                if scan_util.test(record, index) then
                    aux.cancel_auction(index, function()
                        debug_log('|cff00ff00[Cancel] Successfully canceled: ' .. record.name .. '|r')
                        listing:RemoveAuctionRecord(record)
                        cancel_index = cancel_index + 1
                        cancel_next_item()
                    end)
                else
                    DEFAULT_CHAT_FRAME:AddMessage('|cffff0000[Cancel Error] Auction mismatch for ' .. record.name .. ' - skipping|r')
                    cancel_index = cancel_index + 1
                    cancel_next_item()
                end
            end
        )
    end
end