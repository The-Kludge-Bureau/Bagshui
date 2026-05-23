-- Bagshui Core: Cursor
-- Picking up, putting down, tracking what's being held.

Bagshui:LoadComponent(function()
  --- There's no `GetCursorInfo()` in 1.12 so we're going to do a little trickery in order to accomplish a couple of things:
  --- 1. Use escape to clear the cursor.
  --- 2. Allow dragging items from bags to category editors to populate item lists.
  --- This is NOT hooking the global `PickupContainerItem()`, so only Bagshui item slots are going to use this.
  ---@param item table Populated by `ItemInfo:Get()`.
  ---@param inventoryClass table? Inventory class instance that owns the item being picked up or put down.
  ---@param itemSlotButton table?
  ---@param callPickupContainerItem boolean?
  function Bagshui:PickupItem(item, inventoryClass, itemSlotButton, callPickupContainerItem)
    -- Track where the pickup call came from so we know whether it's being put down
    -- in the same inventory or moved to a different one.
    local owningFrame = inventoryClass and inventoryClass.uiFrame or _G.this

    -- Reasons to update or clear tracking properties.
    if
      -- Item was put in a different spot in the same inventory, so hold onto the
      -- "pickedUp" values and add "putDown" values. Note that these may be changed
      -- in the loop that chooses an empty slot below.
      _G.CursorHasItem()
      and self.cursorItem ~= nil
      and self.pickedUpItemBagNum ~= nil
      and self.pickedUpItemSlotNum ~= nil
      and (self.pickedUpItemBagNum ~= item.bagNum or self.pickedUpItemSlotNum ~= item.slotNum)
      and self.cursorItemOwningFrame == owningFrame
    then
      self.putDownItemBagNum = item.bagNum
      self.putDownItemSlotNum = item.slotNum
    elseif
      -- Tracking needs to be cleared when...
      (
        not _G.CursorHasItem()
        and (
          (
                        -- Item was put back down in the same spot.
self.cursorItemOwningFrame == owningFrame
            and self.pickedUpItemBagNum == item.bagNum
            and self.pickedUpItemSlotNum == item.slotNum
          )
          or (
                        -- First call with nothing on cursor but tracking hasn't been reset.
self.pickedUpItemBagNum
            and self.pickedUpItemSlotNum
            and self.putDownItemBagNum
            and self.putDownItemSlotNum
          )
        )
      )
      or (
                -- Item was moved to a different inventory.
_G.CursorHasItem()
        and self.cursorItemOwningFrame ~= nil
        and self.cursorItemOwningFrame ~= owningFrame
      )
    then
      -- Clear tracking.
      self.pickedUpItemBagNum = nil
      self.pickedUpItemSlotNum = nil
      self.putDownItemBagNum = nil
      self.putDownItemSlotNum = nil
      if self.cursorItemOwningFrame then
        self.cursorItemOwningFrame.bagshuiData.hasCursorItem = false
      end
    end

    -- Every time we're called, start fresh with the basic tracking properties.
    -- These get updated at the end when we check whether anything was picked up.
    self.cursorItem = nil
    self.cursorItemOwningFrame = nil
    if not owningFrame.bagshuiData then
      owningFrame.bagshuiData = {}
    end
    owningFrame.bagshuiData.hasCursorItem = false

    if
      inventoryClass
      and itemSlotButton
      and itemSlotButton.bagshuiData
      and itemSlotButton.bagshuiData.isEmptySlotStack
    then
      -- This is an empty slot stack.
      -- Instead of just putting the item in whatever slot happens to represent the empty slot stack, we're
      -- going to iterate all containers and find the first one with an empty slot. This also gives us a chance
      -- to work around accidentally trying to put a container into itself (see comment below).

      -- Only iterate containers that match the generic bag type of this slot.
      local allowedGenericBagType = inventoryClass.containers[item.bagNum].genericType

      -- When a bag is picked up from the bag bar and an attempt is made to place it into an empty slot,
      -- it's possible that the empty slot may belong to the bag that was picked up, especially if it's
      -- being put into an empty slot stack. This triggers an error message about not being able to put
      -- a bag into itself, which is unexpected if there are empty slots in other bags. To work around
      -- this, we iterate all empty slots that belong to non-profession bags looking for somewhere to
      -- place the bag that's on the cursor.
      local bagNumToAvoid

      -- Special handling when a bag has been picked up.
      if self.cursorBagSlotNum and _G.CursorHasItem() and inventoryClass then
        self:PrintDebug(self.cursorBagSlotNum)
        self:PrintDebug(inventoryClass.inventoryIdsToContainerIds[self.cursorBagSlotNum])
        local bagNum = inventoryClass.inventoryIdsToContainerIds[self.cursorBagSlotNum]
        if bagNum and inventoryClass.containers[bagNum].slotsFilled > 0 then
          -- Bag needs to be emptied before it can be unequipped.
          if inventoryClass:GetAdjustedEmptySlotCount(bagNum) > inventoryClass.containers[bagNum].slotsFilled then
            -- Empty the bag.
            local bagSlotNum = self.cursorBagSlotNum
            local targetBagNum = item.bagNum
            local targetSlotNum = item.slotNum
            _G.ClearCursor()
            inventoryClass:EmptyBag(inventoryClass.inventoryIdsToContainerIds[bagSlotNum], nil, function(success)
              if success then
                _G.PickupBagFromSlot(bagSlotNum)
                self:PickupItem(item, inventoryClass, itemSlotButton, callPickupContainerItem)
              end
            end)
          else
            -- Not enough empty slots.
            self:ShowErrorMessage(_G.INVENTORY_FULL, (inventoryClass and inventoryClass.inventoryType))
          end
          return
        end
        -- Skip this bag when finding empty slots.
        bagNumToAvoid = inventoryClass.inventoryIdsToContainerIds[self.cursorBagSlotNum]
      end

      -- Find the best slot to use.
      local noEmptySlots = true
      for _, bagNum in ipairs(inventoryClass.containerIds) do
        if
          bagNum ~= bagNumToAvoid -- This will work fine if bagNumToAvoid is nil.
          and inventoryClass.containers[bagNum].genericType == allowedGenericBagType
        then
          for slotNum, slotContents in ipairs(inventoryClass.inventory[bagNum]) do
            if
              slotContents.emptySlot == 1
              -- When moving an item into an empty slot stack, always peel off
              -- a new slot instead of using any that have already been peeled off.
              and not slotContents._bagshuiPreventEmptySlotStack
            then
              -- Update tracking variables so that inventory classes know that this item should
              -- have its stock state restored.
              self.putDownItemBagNum = bagNum
              self.putDownItemSlotNum = slotNum
              -- Move the item.
              _G.PickupContainerItem(bagNum, slotNum)
              noEmptySlots = false
              break
            end
          end
        end
        if not noEmptySlots then
          break
        end
      end

      -- Couldn't find anywhere to put it.
      if noEmptySlots then
        self:ShowErrorMessage(_G.INVENTORY_FULL, (inventoryClass and inventoryClass.inventoryType))
        _G.ClearCursor()
      end
    else
      -- Avoid some "can't put a bag in itself" type bag-related errors.
      -- This is sort of a duplicate of some of the empty slot stack code but
      -- I can't be bothered to refactor at the moment.
      -- It's worth doing this check instead of letting the game catch it because
      -- there can be weird cursor behavior right afterwards where picking up
      -- a bag with the left mouse button equips it, at least on local VMaNGOS.
      if self.cursorBagSlotNum and _G.CursorHasItem() and inventoryClass then
        local bagNum = inventoryClass.inventoryIdsToContainerIds[self.cursorBagSlotNum]
        if item.bagNum == bagNum then
          self:ShowErrorMessage(_G.ERR_BAG_IN_BAG, (inventoryClass and inventoryClass.inventoryType))
          _G.ClearCursor()
          return
        end
      end

      -- Not an empty slot stack (normal behavior).
      if callPickupContainerItem then
        _G.PickupContainerItem(item.bagNum, item.slotNum)
      else
        if _G.IsModifiedClick and _G.IsModifiedClick() then
          _G.ContainerFrameItemButton_OnModifiedClick(_G.this, "LeftButton")
        else
          _G.ContainerFrameItemButton_OnClick(_G.this, "LeftButton")
        end
      end
    end

    -- Store tracking info if we picked something up.
    if _G.CursorHasItem() then
      self.cursorItem = item
      owningFrame.bagshuiData.hasCursorItem = true
      self.cursorItemOwningFrame = owningFrame
      self.lastCursorItemUniqueId = BsItemInfo:GetUniqueItemId(self.cursorItem)
      self.pickedUpItemBagNum = item.bagNum
      self.pickedUpItemSlotNum = item.slotNum
    else
      self:ClearCursor()
    end
  end

  --- Reset our cursor item tracking when the cursor is emptied.
  ---@param wowApiFunctionName string? Hooked WoW API function that triggered this call.
  function Bagshui:ClearCursor(wowApiFunctionName)
    -- Protected functions cannot be called from addon code during combat lockdown.
    if _G.InCombatLockdown and _G.InCombatLockdown() then
      return
    end

    self.cursorItem = nil
    if self.cursorItemOwningFrame then
      self.cursorItemOwningFrame.bagshuiData.hasCursorItem = nil
    end
    self.cursorItemOwningFrame = nil
    self.cursorBagSlotNum = nil

    -- When the item was deleted, it can't exist any longer and lastCursorItemUniqueId
    -- needs to be cleared so that acquiring the same item again will cause it
    -- to be correctly seen as new.
    if wowApiFunctionName == "DeleteCursorItem" then
      self.lastCursorItemUniqueId = nil
    end
    self.hooks:OriginalHook(wowApiFunctionName)
  end

  --- Clear our cursor tracking if nothing is held.
  function Bagshui:CheckCursor()
    if not _G.CursorHasItem() then
      self:ClearCursor()
    end
  end

  --- Return the inventory item that was picked up via `Bagshui:PickupItem()`, if anything.
  --- Will *not* work with `PickupContainerItem()`.
  ---@return table?
  function Bagshui:GetCursorItem()
    if _G.CursorHasItem() and self.cursorItem then
      return self.cursorItem
    end
  end

  --- Post-hook for `PickupBagFromSlot()`, `PickupInventoryItem()`, and `PutItemInBag()`.
  --- Registered via `hooksecurefunc` so the original runs in its secure context
  --- and ADDON_ACTION_BLOCKED is avoided during combat lockdown.
  ---@param wowApiFunctionName string Hooked WoW API function that triggered this call.
  ---@param invSlotId number Inventory slot ID.
  function Bagshui:PickupInventoryItemPostHook(wowApiFunctionName, invSlotId)
    -- Track bag putdown: was there a bag on the cursor that was just placed?
    if
      not _G.CursorHasItem()
      and self.cursorBagSlotNum ~= nil
    then
      if self.cursorBagSlotNum ~= invSlotId then
        self.pickedUpBagSlotNum = self.cursorBagSlotNum
        self.putDownBagSlotNum = invSlotId
      else
        self.pickedUpBagSlotNum = nil
        self.putDownBagSlotNum = nil
      end
      self.cursorBagSlotNum = nil
    end

    -- A bag was picked up.
    if
      (wowApiFunctionName == "PickupBagFromSlot" or wowApiFunctionName == "PickupInventoryItem")
      and _G.CursorHasItem()
      and self.cursorItem == nil
    then
      if wowApiFunctionName == "PickupBagFromSlot" then
        self.cursorBagSlotNum = invSlotId
      else
        for _, inventoryType in pairs(BS_INVENTORY_TYPE) do
          if
            self.components[inventoryType]
            and self.components[inventoryType].inventoryIdsToContainerIds
            and self.components[inventoryType].inventoryIdsToContainerIds[invSlotId]
          then
            self.cursorBagSlotNum = invSlotId
            break
          end
        end
      end
    end

    self:QueueClassCallback(self, self.CheckCursor)
  end

  -- Register post-hooks for protected cursor functions so the original runs
  -- in its secure execution context during combat.
  _G.hooksecurefunc("PickupInventoryItem", function(invSlotId)
    Bagshui:PickupInventoryItemPostHook("PickupInventoryItem", invSlotId)
  end)
  _G.hooksecurefunc("PickupBagFromSlot", function(slotId)
    Bagshui:PickupInventoryItemPostHook("PickupBagFromSlot", slotId)
  end)
  _G.hooksecurefunc("PutItemInBag", function(slotId)
    Bagshui:PickupInventoryItemPostHook("PutItemInBag", slotId)
  end)
end)
