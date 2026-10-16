# Changelog

## 1.5.0

New:
- **Import lists from another profile**: on the Profiles card, add another profile's auto-sell and keep lists to yours without changing your settings. Items already on one of your lists stay as they are
- An **empty auto-sell or keep list** offers to import from your other profiles that have items on that list, showing how many each has
- **Make room**: when your bags are full, the loot window gets a button that destroys your cheapest junk and loots, in one click. It uses the trash can's junk, confirmation and value limit, and can be turned off on the Bags page
- New junk rule, **armor lighter than yours**: soulbound cloth, leather and mail lighter than the heaviest armor you can wear, like leather on a warrior. Bind-on-equip pieces are left alone for the auction house (off by default)
- New junk rule, **recipes you already know** (off by default)
- **Upgrades are protected**: gear with a higher item level than what you wear in its slot, or that would fill an empty slot, is never sold or destroyed (unless it's on your auto-sell list). Gear your class can't use and armor lighter than yours don't count. On by default
- **Auction prices**: with Auctionator or TradeSkillMaster installed, items worth at least twice their vendor price at the auction house are kept, also when they're on your auto-sell list, since prices change. Grey items always sell. Choose how much more under Kept automatically
- **Open containers**: while you carry clams, sacks of loot or other containers, a button next to the trash can opens the next one with each click, with a count. Also a hotkey. Locked boxes are skipped

Changed:
- **Tidier options**: shorter descriptions throughout. On the Junk rules page, your own keep rules and the ones Pocket Goblin applies by itself (quest gear, upgrades, valuable items, auction prices) are now separate cards. The Bags page is grouped into Bag icons, Bag buttons and Full bags
- Scrolling the options with the mouse wheel no longer gets caught by a slider the pointer passes over. To change a slider with the wheel, stop for a moment over it first
- The Profiles card now says that the keep list is part of a profile too, and that resetting a profile empties both lists

## 1.4.2

New look:
- The **logo** has a deep navy background instead of white, so the goblin and his gold stand out. The settings and welcome windows use it too

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
