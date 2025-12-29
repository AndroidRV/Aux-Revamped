module 'aux.tabs.auctions'

local T = require 'T'
local aux = require 'aux'
local info = require 'aux.util.info'
local scan_util = require 'aux.util.scan'
local scan = require 'aux.core.scan'

local tab = aux.tab 'Auctions'

auction_records = T.acquire()

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

    -- Extract common prefix from item names for batch checking
    local function get_search_prefix(item_name)
        -- Common prefixes for grouping (exact match)
        local prefixes = {
            'Devilsaur',
            'Corehound',
            'Netherwind',
            'Earthfury',
            'Giantstalker',
            'Nightslayer',
            'Cenarion',
            'Frostwolf',
        }

        for i = 1, table.getn(prefixes) do
            local prefix = prefixes[i]
            -- Check if item name starts with this prefix
            if string.find(item_name, '^' .. prefix) then
                return prefix
            end
        end

        -- Default: use full name for items without common prefix
        return item_name
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

        -- Group items by search prefix for efficient batch checking
        local prefix_groups = {}

        for i = 1, table.getn(auction_records) do
            local record = auction_records[i]
            if record.buyout_price and record.buyout_price > 0 then
                record.undercut_status = nil

                -- Get search prefix for this item
                local prefix = get_search_prefix(record.name)

                -- Create group if it doesn't exist
                if not prefix_groups[prefix] then
                    prefix_groups[prefix] = {
                        search_name = prefix,
                        items = {},
                        class = nil
                    }
                end

                -- Detect item class from first item in group
                if not prefix_groups[prefix].class then
                    local item_info = info.item(record.item_key)
                    if item_info and item_info.class then
                        -- Convert class string to numeric index
                        local class_index = info.item_class_index(item_info.class)
                        if class_index then
                            prefix_groups[prefix].class = class_index
                            debug_log('|cff00ff00[Group] ' .. prefix .. ' -> class "' .. item_info.class .. '" = ' .. tostring(class_index) .. '|r')
                        end
                    else
                        debug_log('|cffff0000[Group] ' .. prefix .. ' -> no class detected|r')
                    end
                end

                -- Add item to group
                tinsert(prefix_groups[prefix].items, record)
            else
                record.undercut_status = 'no_buyout'
            end
        end

        -- Convert groups to queue
        for prefix, group in pairs(prefix_groups) do
            tinsert(check_queue, group)
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

        -- Build query with class filter if detected
        local query = {
            name = group.search_name,
        }
        if group.class then
            query.class = group.class
            debug_log('|cff00ff00[Undercut] Using class filter: ' .. tostring(group.class) .. ' (type: ' .. type(group.class) .. ')|r')
        end

        debug_log('|cffff00ff[Query] name=' .. tostring(query.name) .. ', class=' .. tostring(query.class) .. '|r')

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