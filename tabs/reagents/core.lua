module 'aux.tabs.reagents'

local T = require 'T'
local aux = require 'aux'
local info = require 'aux.util.info'
local scan = require 'aux.core.scan'
local history = require 'aux.core.history'
local money = require 'aux.util.money'
local gui = require 'aux.gui'

local tab = aux.tab 'Reagents'

function aux.handle.LOAD()
	reagent_scan_list = aux.realm_data.reagent_scan_list
end

function tab.OPEN()
    frame:Show()
    update_listing()
end

function tab.CLOSE()
    frame:Hide()
end

-- Convert timestamp to relative time string
function format_relative_time(timestamp)
	if not timestamp then
		return '|cff888888Never|r'
	end

	local diff = time() - timestamp

	if diff < 60 then
		return '|cff00ff00' .. diff .. 's ago|r'
	elseif diff < 3600 then
		local mins = floor(diff / 60)
		return '|cff00ff00' .. mins .. 'm ago|r'
	elseif diff < 86400 then
		local hours = floor(diff / 3600)
		return '|cffffff00' .. hours .. 'h ago|r'
	else
		local days = floor(diff / 86400)
		return '|cffff8800' .. days .. 'd ago|r'
	end
end

function update_listing()
	local reagent_rows = T.acquire()
	local scanning_item_id = M.get_scanning_item_id and M.get_scanning_item_id() or nil

	for i = 1, getn(reagent_scan_list) do
		local reagent = reagent_scan_list[i]
		local item_key = reagent.item_id .. ':0'
		local market_price = history.market_value(item_key)
		local historical_value = history.value(item_key)
		local market_str = market_price and money.to_string2(market_price) or '|cff888888-|r'

		-- Calculate historical percentage (market / historical * 100)
		local pct_str = '|cff888888-|r'
		if market_price and historical_value and historical_value > 0 then
			local pct = aux.round(market_price / historical_value * 100)
			pct_str = gui.percentage_historical(pct)
		end

		-- Show "Scanning..." if this item is currently being scanned
		local last_scanned_str
		if scanning_item_id and reagent.item_id == scanning_item_id then
			last_scanned_str = '|cff00ff00Scanning...|r'
		else
			last_scanned_str = format_relative_time(reagent.last_scanned)
		end

		tinsert(reagent_rows, T.map(
			'cols', T.list(
				T.map('value', reagent.name),
				T.map('value', market_str),
				T.map('value', pct_str),
				T.map('value', last_scanned_str)
			),
			'reagent', reagent,
			'index', i
		))
	end
	listing:SetData(reagent_rows)
end

function M.add_reagent(name, item_id)
	-- Check for duplicates by item_id
	for _, reagent in reagent_scan_list do
		if reagent.item_id == item_id then
			return false -- Already exists
		end
	end
	tinsert(reagent_scan_list, T.map(
		'name', name,
		'item_id', item_id,
		'last_scanned', nil
	))
	update_listing()
	return true
end

function remove_reagent(index)
	tremove(reagent_scan_list, index)
	update_listing()
end

function M.clear_reagent_list()
	while tremove(reagent_scan_list) do end
	update_listing()
end

-- Reagent scanning logic
do
	local scanning = false
	local scan_queue = {}
	local current_scan_index = 1
	local current_scanning_item_id = nil

	function M.get_scanning_item_id()
		return current_scanning_item_id
	end

	function M.scan_reagents()
		if scanning then
			aux.print('Reagent scan already in progress!')
			return
		end

		if getn(reagent_scan_list) == 0 then
			aux.print('No reagents in scan list! Add reagents from the crafting window.')
			return
		end

		-- Build scan queue
		T.wipe(scan_queue)
		for i = 1, getn(reagent_scan_list) do
			tinsert(scan_queue, {reagent = reagent_scan_list[i], index = i})
		end

		scanning = true
		current_scan_index = 1
		scan_button:SetText('Scanning...')
		scan_button:Disable()
		status_bar:update_status(0, 0)
		status_bar:set_text('|cff3399ffStarting reagent scan...|r')

		aux.print('Starting reagent scan for ' .. getn(scan_queue) .. ' items...')
		scan_next_reagent()
	end

	function scan_next_reagent()
		if current_scan_index > getn(scan_queue) then
			-- All done
			scanning = false
			current_scanning_item_id = nil
			scan_button:SetText('Scan All')
			scan_button:Enable()
			status_bar:update_status(1, 1)
			status_bar:set_text('|cff00ff00Scan complete|r')
			aux.print('Reagent scan complete!')
			update_listing()
			return
		end

		local entry = scan_queue[current_scan_index]
		local reagent = entry.reagent
		local total = getn(scan_queue)

		current_scanning_item_id = reagent.item_id
		update_listing()

		status_bar:update_status((current_scan_index - 1) / total, 0)
		status_bar:set_text(format('|cff3399ffScanning|r %s', reagent.name))

		scan.start{
			type = 'list',
			queries = {{
				blizzard_query = T.map('name', reagent.name),
				validator = function(record)
					return record.item_id == reagent.item_id
				end,
			}},
			on_page_loaded = function(page, total_pages)
				status_bar:update_status((current_scan_index - 1 + page/total_pages) / total, 0)
				status_bar:set_text(format('|cff3399ffScanning|r %s (|cffff8000%d|r/|cff00ff00%d|r)', reagent.name, page, total_pages))
			end,
			on_auction = function(auction_record)
				-- Price recording happens automatically in scan
			end,
			on_complete = function()
				-- Update last scanned time
				reagent.last_scanned = time()
				update_listing()
				current_scan_index = current_scan_index + 1
				scan_next_reagent()
			end,
			on_abort = function()
				aux.print('Scan aborted for: ' .. reagent.name)
				current_scan_index = current_scan_index + 1
				scan_next_reagent()
			end,
		}
	end

	function M.is_scanning()
		return scanning
	end
end
