local CyTest = require('cylibs/tests/cy_test')
local Event = require('cylibs/events/Luvent')
local ListItem = require('cylibs/ui/list_item')
local ListTests = require('cylibs/tests/list_tests')
local ListView = require('cylibs/ui/list_view')
local ListViewItemStyle = require('cylibs/ui/style/list_view_item_style')
local TabItem = require('cylibs/ui/tabs/tab_item')
local TabbedView = require('cylibs/ui/tabs/tabbed_view')
local TextListItemView = require('cylibs/ui/items/text_list_item_view')
local VerticalListLayout = require('cylibs/ui/layouts/vertical_list_layout')

local TabbedViewTests = {}
TabbedViewTests.__index = TabbedViewTests

function TabbedViewTests:onCompleted()
    return self.completed
end

function TabbedViewTests.new()
    local self = setmetatable({}, TabbedViewTests)
    self.completed = Event.newEvent()
    return self
end

function TabbedViewTests:destroy()
    self.listView:destroy()

    self.completed:removeAllActions()
end

function TabbedViewTests:run()
    self:testTabbedView()
end

-- Tests

function TabbedViewTests:testTabbedView()
    local view1 = ListView.new(VerticalListLayout.new(500, 0))
    local view2 = ListView.new(VerticalListLayout.new(500, 0))

    local tabItems = L{
        TabItem.new("View1", view1),
        TabItem.new("View2", view2)
    }

    self.tabbed_view = TabbedView.new(tabItems)

    self.tabbed_view:set_pos(500, 200)
    self.tabbed_view:set_size(500, 500)
    self.tabbed_view:set_visible(true)
    self.tabbed_view:render()

    CyTest.assert(self.tabbed_view:getNumTabs() == 2, "TabbedView should have 2 tabs after TabbedView.new")

    CyTest.assert(self.tabbed_view:getActiveView():get_uuid() == view1:get_uuid(), "Initial active tab should be View1")
    CyTest.assert(view1:is_visible() == true, "View1 should be visible")
    CyTest.assert(view2:is_visible() == false, "View2 should not be visible")

    self.tabbed_view:switchToTab(2)
    self.tabbed_view:render()

    CyTest.assert(self.tabbed_view:getActiveView():get_uuid() == view2:get_uuid(), "Active tab should be View2")
    CyTest.assert(view2:is_visible() == true, "View2 should be visible")

    self.tabbed_view:switchToTab(1)
    self.tabbed_view:render()

    CyTest.assert(self.tabbed_view:getActiveView():get_uuid() == view1:get_uuid(), "Active tab should be View1")

    CyTest.showFailureOnly = true

    local listTest1 = ListTests.new(view1)
    listTest1:run()

    local listTest2 = ListTests.new(view2)
    listTest2:run()

    CyTest.showFailureOnly = false

    CyTest.assert(self.tabbed_view:getNumTabs() == 2, "TabbedView should have 2 tabs after addView(view2)")

    local tabItem1 = self.tabbed_view:getTabAtIndex(1)
    local tabItem2 = self.tabbed_view:getTabAtIndex(2)

    CyTest.assert(tabItem1:getIdentifier() == "View1", "View1 should be at index 1")
    CyTest.assert(tabItem2:getIdentifier() == "View2", "View2 should be at index 2")

    view1:addItem(ListItem.new({text = "View1", height = 500}, ListViewItemStyle.DarkMode.Text, "View1", TextListItemView.new))
    view2:addItem(ListItem.new({text = "View2", height = 500}, ListViewItemStyle.DarkMode.Text, "View2", TextListItemView.new))

    self.tabbed_view:destroy()

    CyTest.assert(self.tabbed_view:is_destroyed(), "TabbedView should be destroyed after destroy()")

    self:onCompleted():trigger(true)
end

return TabbedViewTests