# Changelog

## 1.4.1

Changed:
- The **auto-sell and keep hotkeys only add** an item to their list. Pressing one again on an item that's already there leaves it on the list (and says so), instead of taking it off. The other hotkey still moves an item between the lists; to take an item off a list, use the Alt+Right-click menu

## 1.4.0

New:
- **Hotkeys** to put the item under your mouse on the auto-sell list or the keep list, without the Alt+Right-click menu. Set them in the game's Key Bindings, under Pocket Goblin. Press the key again to take the item off the list
- A **hotkey to destroy the cheapest junk**, the same as clicking the trash can (it asks first unless you've turned that off)

## 1.3.0

New look:
- **New logo**: a goblin peeking out of a pot of gold, in full colour in the settings window and the welcome window
- The vendor panel, minimap button and AddOns list use a gold version of the new logo
- The goblin's mood faces are bigger and clearer, and sit next to its mood under the settings title

## 1.2.1

Fixed:
- In separate bags, the trash can no longer covers the "Backpack" title; it sits next to the bag icon
- The trash can on the default bags is always gold, like the sort button and the bag's title

## 1.2.0

New:
- **Sort bags** button on the default bags (and `/goblin sort`): stacks and sorts everything in your bags, hearthstone first and junk last

## 1.1.0

New:
- **Buy back all** button on the vendor panel
- **Auto-sell suggestions**: sell the same item yourself three times and the vendor panel offers to put it on the auto-sell list
- The Pocket Goblin window can be **resized** (drag the bottom-right corner) and remembers its size and position. On small screens it shrinks to fit

Simpler:
- One **Chat messages** setting (Goblin, Plain or Off) replaces the chat, goblin voice and milestone switches. `/goblin chat` switches between them
- One rule for **soulbound gear you can't use or have outgrown** replaces the two separate rules. If either was on, the combined rule is on
- Fewer pages: **Quest gear** is now a tab on the Keep list page, **Destroy** moved to Bags, and **Profiles** moved to General
- The vendor panel always lists your own sales for buyback too

Safer:
- The cheap white items rule no longer sells class reagents (Ankh, Flash Powder...), weapons, armor, fishing poles, shirts or tabards
- Profession and class tools such as Thieves' Tools, Flint and Tinder and enchanting rods are never sold

Fixed:
- Long descriptions in the sidebar wrap instead of being cut off

## 1.0.1

- Fixed the version in the window header showing as "vv1.0.0"

## 1.0.0

First public release.

- Sells grey items, white gear from level 10, outgrown food and drink, and anything on your auto-sell list
- Optional rules for cheap white items and soulbound gear you can't use or have outgrown
- Keep list, plus "always keep" rules by name, item type and value; quest gear and equipment sets are protected
- Vendor panel with a Sell junk button and buyback
- History of vendor visits with sales, buybacks and repairs, and earnings tracking
- Destroy button for the cheapest junk, bag space warning, coin and lock icons (default bags and Baganator)
- Auto-repair, profiles, and a goblin with moods, a voice and milestones
