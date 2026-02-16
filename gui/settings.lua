module 'aux.gui.settings'

local aux = require 'aux'
local gui = require 'aux.gui'
local post = require 'aux.tabs.post'

local settings_frame

function M.toggle()
    if settings_frame and settings_frame:IsVisible() then
        settings_frame:Hide()
    else
        if not settings_frame then
            create_settings_frame()
        end
        settings_frame:Show()
    end
end

function status_text(enabled)
    if enabled then
        return aux.color.green'on'
    else
        return aux.color.red'off'
    end
end

function create_checkbox(parent, text, y, on_click)
    local cb = gui.checkbox(parent)
    cb:SetPoint('TOPLEFT', 8, y)
    cb:SetScript('OnClick', on_click)

    local lbl = gui.label(parent, gui.font_size.small)
    lbl:SetPoint('LEFT', cb, 'RIGHT', 5, 0)
    lbl:SetText(text)
    lbl:SetTextColor(aux.color.text.enabled())

    return cb
end

function create_settings_frame()
    settings_frame = CreateFrame('Frame', 'aux_settings_frame', UIParent)
    tinsert(UISpecialFrames, 'aux_settings_frame')
    gui.set_window_style(settings_frame)
    gui.set_size(settings_frame, 500, 520)
    settings_frame:SetPoint('CENTER', 0, 0)
    settings_frame:SetToplevel(true)
    settings_frame:SetMovable(true)
    settings_frame:EnableMouse(true)
    settings_frame:SetClampedToScreen(true)
    settings_frame:CreateTitleRegion():SetAllPoints()
    -- Semi-transparent backdrop
    settings_frame:SetBackdropColor(0.1, 0.1, 0.1, 0.85)
    settings_frame:Hide()

    local title = gui.label(settings_frame, gui.font_size.large)
    title:SetPoint('TOP', 0, -10)
    title:SetText(aux.color.label.enabled'Aux Settings')

    -- Scroll frame
    local scroll = CreateFrame('ScrollFrame', 'aux_settings_scroll', settings_frame)
    scroll:SetPoint('TOPLEFT', 10, -35)
    scroll:SetPoint('BOTTOMRIGHT', -28, 40)

    -- Scroll child
    local content = CreateFrame('Frame', nil, scroll)
    content:SetWidth(462)
    content:SetHeight(700)
    scroll:SetScrollChild(content)

    -- Scrollbar
    local scrollbar = CreateFrame('Slider', nil, settings_frame)
    scrollbar:SetOrientation('VERTICAL')
    scrollbar:SetWidth(12)
    scrollbar:SetPoint('TOPRIGHT', settings_frame, 'TOPRIGHT', -10, -38)
    scrollbar:SetPoint('BOTTOMRIGHT', settings_frame, 'BOTTOMRIGHT', -10, 42)
    gui.set_panel_style(scrollbar)
    scrollbar:SetMinMaxValues(0, 1)
    scrollbar:SetValueStep(20)
    scrollbar:SetValue(0)

    local thumb = scrollbar:CreateTexture(nil, 'ARTWORK')
    thumb:SetTexture(0.3, 0.3, 0.3, 0.8)
    thumb:SetWidth(10)
    thumb:SetHeight(40)
    scrollbar:SetThumbTexture(thumb)

    scrollbar:SetScript('OnValueChanged', function()
        scroll:SetVerticalScroll(this:GetValue())
    end)

    -- Mouse wheel scrolling
    local function on_mouse_wheel()
        local current = scrollbar:GetValue()
        local _, max_scroll = scrollbar:GetMinMaxValues()
        local step = 30
        if arg1 > 0 then
            scrollbar:SetValue(math.max(0, current - step))
        else
            scrollbar:SetValue(math.min(max_scroll, current + step))
        end
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript('OnMouseWheel', on_mouse_wheel)
    settings_frame:EnableMouseWheel(true)
    settings_frame:SetScript('OnMouseWheel', on_mouse_wheel)

    -- =============================================
    -- Content
    -- =============================================
    local y = -5

    -- GENERAL SETTINGS
    local h1 = content:CreateFontString()
    h1:SetFont(gui.font, gui.font_size.medium)
    h1:SetPoint('TOPLEFT', 5, y)
    h1:SetText(aux.color.blue'General Settings')
    y = y - 20

    local scale_slider = gui.slider(content)
    scale_slider:SetPoint('TOPLEFT', 8, y)
    scale_slider:SetPoint('TOPRIGHT', -8, y)
    scale_slider.label:SetText('UI Scale')
    scale_slider:SetMinMaxValues(0.5, 1.5)
    scale_slider:SetValueStep(0.05)
    scale_slider:SetValue(aux.account_data.scale)
    scale_slider.editbox:SetText(string.format('%.2f', aux.account_data.scale))
    scale_slider:SetScript('OnValueChanged', function()
        local v = this:GetValue()
        this.editbox:SetText(string.format('%.2f', v))
        aux.frame:SetScale(v)
        aux.account_data.scale = v
    end)
    y = y - 35

    local cb1 = create_checkbox(content, 'Ignore own auctions in searches', y, function()
        aux.account_data.ignore_owner = not aux.account_data.ignore_owner
        aux.print('ignore owner ' .. status_text(aux.account_data.ignore_owner))
    end)
    cb1:SetChecked(aux.account_data.ignore_owner)
    y = y - 25

    local cb2 = create_checkbox(content, 'Enable sharing with guild/party', y, function()
        aux.account_data.sharing = not aux.account_data.sharing
        aux.print('sharing ' .. status_text(aux.account_data.sharing))
    end)
    cb2:SetChecked(aux.account_data.sharing)
    y = y - 25

    local cb3 = create_checkbox(content, 'Show hidden post profiles', y, function()
        aux.account_data.showhidden = not aux.account_data.showhidden
        aux.print('show hidden ' .. status_text(aux.account_data.showhidden))
    end)
    cb3:SetChecked(aux.account_data.showhidden)
    y = y - 30

    -- POST SETTINGS
    local h2 = content:CreateFontString()
    h2:SetFont(gui.font, gui.font_size.medium)
    h2:SetPoint('TOPLEFT', 5, y)
    h2:SetText(aux.color.blue'Post Settings')
    y = y - 20

    local cb5 = create_checkbox(content, 'Enable stack posting', y, function()
        aux.account_data.post_stack = not aux.account_data.post_stack
        aux.print('post stack ' .. status_text(aux.account_data.post_stack))
    end)
    cb5:SetChecked(aux.account_data.post_stack)
    y = y - 25

    local cb6 = create_checkbox(content, 'Enable bid price when posting', y, function()
        aux.account_data.post_bid = not aux.account_data.post_bid
        aux.print('post bid ' .. status_text(aux.account_data.post_bid))
    end)
    cb6:SetChecked(aux.account_data.post_bid)
    y = y - 25

    local dlbl = gui.label(content, gui.font_size.small)
    dlbl:SetPoint('TOPLEFT', 8, y)
    dlbl:SetText('Default duration:')
    y = y - 20

    local b6h = gui.button(content, gui.font_size.small)
    gui.set_size(b6h, 55, 22)
    b6h:SetPoint('TOPLEFT', 8, y)
    b6h:SetText('6h')

    local b24h = gui.button(content, gui.font_size.small)
    gui.set_size(b24h, 55, 22)
    b24h:SetPoint('LEFT', b6h, 'RIGHT', 5, 0)
    b24h:SetText('24h')

    local b72h = gui.button(content, gui.font_size.small)
    gui.set_size(b72h, 55, 22)
    b72h:SetPoint('LEFT', b24h, 'RIGHT', 5, 0)
    b72h:SetText('72h')

    local function upd_dur()
        local d = aux.account_data.post_duration
        b6h:GetFontString():SetTextColor(d == post.DURATION_2 and 0.5 or 1, d == post.DURATION_2 and 1 or 0.8, d == post.DURATION_2 and 0.5 or 0.5)
        b24h:GetFontString():SetTextColor(d == post.DURATION_8 and 0.5 or 1, d == post.DURATION_8 and 1 or 0.8, d == post.DURATION_8 and 0.5 or 0.5)
        b72h:GetFontString():SetTextColor(d == post.DURATION_24 and 0.5 or 1, d == post.DURATION_24 and 1 or 0.8, d == post.DURATION_24 and 0.5 or 0.5)
    end

    b6h:SetScript('OnClick', function() aux.account_data.post_duration = post.DURATION_2; upd_dur(); aux.print('duration 6h') end)
    b24h:SetScript('OnClick', function() aux.account_data.post_duration = post.DURATION_8; upd_dur(); aux.print('duration 24h') end)
    b72h:SetScript('OnClick', function() aux.account_data.post_duration = post.DURATION_24; upd_dur(); aux.print('duration 72h') end)
    upd_dur()
    y = y - 30

    -- CRAFTING SETTINGS
    local h3 = content:CreateFontString()
    h3:SetFont(gui.font, gui.font_size.medium)
    h3:SetPoint('TOPLEFT', 5, y)
    h3:SetText(aux.color.blue'Crafting Settings')
    y = y - 20

    local cb7 = create_checkbox(content, 'Show crafting cost in tooltips', y, function()
        aux.account_data.crafting_cost = not aux.account_data.crafting_cost
        aux.print('crafting cost ' .. status_text(aux.account_data.crafting_cost))
    end)
    cb7:SetChecked(aux.account_data.crafting_cost)
    y = y - 30

    -- UNDERCUT SETTINGS
    local h_uc = content:CreateFontString()
    h_uc:SetFont(gui.font, gui.font_size.medium)
    h_uc:SetPoint('TOPLEFT', 5, y)
    h_uc:SetText(aux.color.blue'Undercut Settings')
    y = y - 20

    local qlbl = gui.label(content, gui.font_size.small)
    qlbl:SetPoint('TOPLEFT', 8, y)
    qlbl:SetText('Minimum rarity to check:')
    y = y - 20

    -- Quality buttons: White (1), Green (2), Blue (3), Epic (4)
    local bWhite = gui.button(content, gui.font_size.small)
    gui.set_size(bWhite, 55, 22)
    bWhite:SetPoint('TOPLEFT', 8, y)
    bWhite:SetText('White')

    local bGreen = gui.button(content, gui.font_size.small)
    gui.set_size(bGreen, 55, 22)
    bGreen:SetPoint('LEFT', bWhite, 'RIGHT', 5, 0)
    bGreen:SetText('Green')

    local bBlue = gui.button(content, gui.font_size.small)
    gui.set_size(bBlue, 55, 22)
    bBlue:SetPoint('LEFT', bGreen, 'RIGHT', 5, 0)
    bBlue:SetText('Blue')

    local bEpic = gui.button(content, gui.font_size.small)
    gui.set_size(bEpic, 55, 22)
    bEpic:SetPoint('LEFT', bBlue, 'RIGHT', 5, 0)
    bEpic:SetText('Epic')

    local function upd_quality()
        local q = aux.account_data.undercut_min_quality or 2
        -- White
        if q == 1 then
            bWhite:GetFontString():SetTextColor(1, 1, 1)
        else
            bWhite:GetFontString():SetTextColor(0.4, 0.4, 0.4)
        end
        -- Green
        if q == 2 then
            bGreen:GetFontString():SetTextColor(0.12, 1, 0)
        else
            bGreen:GetFontString():SetTextColor(0.05, 0.4, 0)
        end
        -- Blue
        if q == 3 then
            bBlue:GetFontString():SetTextColor(0, 0.44, 0.87)
        else
            bBlue:GetFontString():SetTextColor(0, 0.18, 0.35)
        end
        -- Epic
        if q == 4 then
            bEpic:GetFontString():SetTextColor(0.64, 0.21, 0.93)
        else
            bEpic:GetFontString():SetTextColor(0.26, 0.08, 0.37)
        end
    end

    bWhite:SetScript('OnClick', function() aux.account_data.undercut_min_quality = 1; upd_quality(); aux.print('undercut min rarity: White') end)
    bGreen:SetScript('OnClick', function() aux.account_data.undercut_min_quality = 2; upd_quality(); aux.print('undercut min rarity: Green') end)
    bBlue:SetScript('OnClick', function() aux.account_data.undercut_min_quality = 3; upd_quality(); aux.print('undercut min rarity: Blue') end)
    bEpic:SetScript('OnClick', function() aux.account_data.undercut_min_quality = 4; upd_quality(); aux.print('undercut min rarity: Epic') end)
    upd_quality()
    y = y - 25

    local cb_dbg = create_checkbox(content, 'Enable undercut debug mode', y, function()
        aux.account_data.undercut_debug = not aux.account_data.undercut_debug
        aux.print('undercut debug ' .. status_text(aux.account_data.undercut_debug))
    end)
    cb_dbg:SetChecked(aux.account_data.undercut_debug or false)
    y = y - 30

    -- TOOLTIP SETTINGS
    local h4 = content:CreateFontString()
    h4:SetFont(gui.font, gui.font_size.medium)
    h4:SetPoint('TOPLEFT', 5, y)
    h4:SetText(aux.color.blue'Tooltip Settings')
    y = y - 20

    local ts = aux.character_data.tooltip

    local t1 = create_checkbox(content, 'Show auction value', y, function()
        ts.value = not ts.value
        aux.print('tooltip value ' .. status_text(ts.value))
    end)
    t1:SetChecked(ts.value)
    y = y - 25

    local t2 = create_checkbox(content, 'Show daily price data', y, function()
        ts.daily = not ts.daily
        aux.print('tooltip daily ' .. status_text(ts.daily))
    end)
    t2:SetChecked(ts.daily)
    y = y - 25

    local t3 = create_checkbox(content, 'Show merchant buy price', y, function()
        ts.merchant_buy = not ts.merchant_buy
        aux.print('tooltip merchant buy ' .. status_text(ts.merchant_buy))
    end)
    t3:SetChecked(ts.merchant_buy)
    y = y - 25

    local t4 = create_checkbox(content, 'Show merchant sell price', y, function()
        ts.merchant_sell = not ts.merchant_sell
        aux.print('tooltip merchant sell ' .. status_text(ts.merchant_sell))
    end)
    t4:SetChecked(ts.merchant_sell)
    y = y - 25

    local t5 = create_checkbox(content, 'Show disenchant value', y, function()
        ts.disenchant_value = not ts.disenchant_value
        aux.print('tooltip disenchant value ' .. status_text(ts.disenchant_value))
    end)
    t5:SetChecked(ts.disenchant_value)
    y = y - 25

    local t6 = create_checkbox(content, 'Show disenchant distribution', y, function()
        ts.disenchant_distribution = not ts.disenchant_distribution
        aux.print('tooltip disenchant distribution ' .. status_text(ts.disenchant_distribution))
    end)
    t6:SetChecked(ts.disenchant_distribution)
    y = y - 30

    -- ACTIONS
    local h5 = content:CreateFontString()
    h5:SetFont(gui.font, gui.font_size.medium)
    h5:SetPoint('TOPLEFT', 5, y)
    h5:SetText(aux.color.blue'Actions')
    y = y - 22

    local clr = gui.button(content, gui.font_size.small)
    gui.set_size(clr, 130, 22)
    clr:SetPoint('TOPLEFT', 8, y)
    clr:SetText('Clear Item Cache')
    clr:SetScript('OnClick', function()
        aux.account_data.items = {}
        aux.account_data.item_ids = {}
        aux.account_data.auctionable_items = {}
        aux.print('Item cache cleared.')
    end)

    local pop = gui.button(content, gui.font_size.small)
    gui.set_size(pop, 130, 22)
    pop:SetPoint('LEFT', clr, 'RIGHT', 5, 0)
    pop:SetText('Populate WDB')
    pop:SetScript('OnClick', function()
        require('aux.util.info').populate_wdb()
        aux.print('Populating WDB...')
    end)
    y = y - 30

    -- Set final content height and scroll range
    local total_content = math.abs(y) + 10
    content:SetHeight(total_content)
    local visible_height = 445 -- 520 frame - 35 top - 40 bottom
    local max_scroll = math.max(0, total_content - visible_height)
    scrollbar:SetMinMaxValues(0, max_scroll)
    if max_scroll == 0 then
        scrollbar:Hide()
    end

    -- Close button
    local cls = gui.button(settings_frame)
    cls:SetPoint('BOTTOM', 0, 10)
    gui.set_size(cls, 80, 24)
    cls:SetText('Close')
    cls:SetScript('OnClick', function() settings_frame:Hide() end)
end
