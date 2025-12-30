module 'aux.tabs.reagents'

local aux = require 'aux'
local gui = require 'aux.gui'
local listing_gui = require 'aux.gui.listing'
local search_tab = require 'aux.tabs.search'

frame = CreateFrame('Frame', nil, aux.frame)
frame:SetAllPoints()
frame:Hide()

-- Real-time update for relative timestamps
do
	local last_update = 0
	frame:SetScript('OnUpdate', function()
		if not frame:IsVisible() then return end
		local now = GetTime()
		if now - last_update > 1 then  -- Update every second
			last_update = now
			update_listing()
		end
	end)
end

frame.listing = gui.panel(frame)
frame.listing:SetPoint('TOP', frame, 'TOP', 0, -8)
frame.listing:SetPoint('BOTTOMLEFT', aux.frame.content, 'BOTTOMLEFT', 0, 0)
frame.listing:SetPoint('BOTTOMRIGHT', aux.frame.content, 'BOTTOMRIGHT', 0, 0)

listing = listing_gui.new(frame.listing)
listing:SetColInfo{
	{name='Reagent', width=.35, align='LEFT'},
	{name='Market', width=.22, align='RIGHT'},
	{name='Hist %', width=.13, align='CENTER'},
	{name='Last Scan', width=.30, align='CENTER'}
}

listing:SetHandler('OnClick', function(st, data, self, button)
	if not data then return end
	if button == 'LeftButton' then
		-- Left click: search for this reagent in AH
		aux.set_tab(1)
		search_tab.set_filter(data.reagent.name .. '/exact')
		search_tab.execute(nil, false)
	elseif button == 'RightButton' then
		-- Right click: show menu to delete
		gui.menu(
			'Delete', function()
				remove_reagent(data.index)
			end
		)
	end
end)

listing:SetHandler('OnEnter', function(st, data, self)
	if not data then return end
	GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
	GameTooltip:AddLine(data.reagent.name, 1, 1, 1)
	GameTooltip:AddLine(' ')
	GameTooltip:AddLine('Left-click to search in AH', 0.7, 0.7, 0.7)
	GameTooltip:AddLine('Right-click to remove from list', 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)

listing:SetHandler('OnLeave', function()
	GameTooltip:ClearLines()
	GameTooltip:Hide()
end)

do
	status_bar = gui.status_bar(frame)
	status_bar:SetWidth(265)
	status_bar:SetHeight(25)
	status_bar:SetPoint('TOPLEFT', aux.frame.content, 'BOTTOMLEFT', 0, -6)
	status_bar:update_status(1, 0)
	status_bar:set_text('')
end
do
	local btn = gui.button(frame)
	btn:SetPoint('TOPLEFT', status_bar, 'TOPRIGHT', 5, 0)
	btn:SetText('Scan All')
	btn:SetScript('OnClick', function()
		scan_reagents()
	end)
	scan_button = btn
end
do
	local btn = gui.button(frame)
	btn:SetPoint('LEFT', scan_button, 'RIGHT', 5, 0)
	btn:SetText('Clear All')
	btn:SetScript('OnClick', function()
		if getn(reagent_scan_list) > 0 then
			gui.menu(
				'Clear all reagents?', function()
					clear_reagent_list()
				end
			)
		end
	end)
end
