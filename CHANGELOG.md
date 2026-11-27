# Changelog

## Unreleased

New:
- **What you sold**: the History page has a second view, next to your visits. It adds up everything you sell at vendors (by Pocket Goblin, you or another addon, minus buybacks) by item type or by quality: a bar for each, with its gold, how many items and its share. Below are the items that made you the most; click a type or quality to see its own. Or by **Rule**: which junk rule sold it (grey items, your auto-sell list, white gear, old food and so on), and what you or another addon sold, so you see what each setting earns you. Hover a rule for what it means. Choose today, the last 7 days, this character or all characters. The counting starts with the visits your history already holds; Pocket Goblin's sales from before this update show as **Earlier sales** under Rule. Items this version of the game doesn't know, sold on a beta or another version and brought along in a copied WTF folder, are left out
- **Characters** card on the General page: every character Pocket Goblin keeps history and earnings for. **Forget** one you deleted, or one copied over from another version of the game, and its sales leave the All characters totals. A character that shows up twice because the game renamed its realm gets **Merge into this character**: log on to it and its history, earnings, sales and milestones come together again

Fixed:
- **A renamed realm no longer splits your characters**: when Forever stopped reporting its realm name, Pocket Goblin took every character for a new one, with an empty history and earnings. Characters are now recognised by their game ID too, so they carry on after a rename. Join the halves from before with **Merge into this character** on the General page
- **RestedXP Guides and Cheap Upgrades sell junk too**: Pocket Goblin now warns when their auto-sell is on (**Auto Sell Junk** in RestedXP Guides, **Sell grey items automatically** in Cheap Upgrades), like it does for Leatrix Plus or EllesmereUI. They sell your greys the moment a vendor opens, before Pocket Goblin, so those sales showed as yours in the history
- The vendor panel no longer suggests auto-selling grey items: they're junk by their own rule (**Grey and white items**)

## 1.11.0

New:
- **Tour**: a short tour for new players, in speech bubbles like Fanny Pack's. The first time your bags open, it points at an item with the coin (and Alt+Right-click), the trash can (and its hotkey), the open button and the window; the first time the vendor panel shows, at the panel. Closing the bags or the vendor, or a fight, pauses it until they're back. Play it again with **Show the tour** on the General page or `/goblin tour`
- **What's new**: after an update with new features, one line in chat says what's new, and a card at the top of the window lists it, each point with a **Show me** link to its page, until you press **Got it**. A gold dot marks the pages and settings that changed. Turn the chat line off with **Tell me about new features** on the General page. A first install gets none of it

Changed:
- **Tidier settings**. **Junk rules** starts with what gets sold (grey and white items, food and drink, soulbound gear, recipes), then what's asked about and kept; the Keep list row is gone, as the sidebar has the page. **Bags** has four cards: Bag icons (with Grey out junk next to the coin), Bag buttons (Sort, Open, Trash can), **Destroying junk** (Ask before destroying and the value limit, which also cover the hotkey and Make room, with Make room itself) and Bag space. On **General**, Tell me about new features moved to Chat messages. Nothing changes what it does

Fixed:
- Settings that depend on another (the destroy value limit, the bag warning's free slots, the other junk sellers warning, guild repairs) now dim as soon as you switch that one off, not only when the window is opened again

## 1.10.0

New:
- **Bagnon**: Pocket Goblin now works with Bagnon. Its items get Pocket Goblin's icons (coin, "?" coin, lock, equipment set icon and upgrade arrow, in the corner you choose) and junk is greyed out, in your own bags (not the bank, or another character's bags). The trash can and the open-containers button sit in Bagnon's row of buttons at the top left, next to its bag, sort and search buttons. Bagnon's own sort button is used there instead of Pocket Goblin's

Fixed:
- **Make room** shows whenever your loot doesn't all fit, not only when your bags are completely full: with 1 free slot and 3 items, it used to stay away until you'd looted one. It counts free slots, room on stacks you already carry, and profession bags that take the item (herbs in a herb bag)

Changed:
- On the Bags page, **Show open button** moved up next to the sort button, so it's no longer lost among the trash can's settings

## 1.9.1

Fixed:
- **Baganator**: the trash can and the open-containers button show again. Baganator's latest version (870) stopped placing add-on buttons at the top of the backpack, so they had vanished; they now sit at the bottom, right of Baganator's currency button, with the trash can in the same gold style as the open button

## 1.9.0

New:
- **EllesmereUI bags**: Pocket Goblin now works with EllesmereUI's bag module. Its items get Pocket Goblin's icons (coin, "?" coin, lock, equipment set icon and upgrade arrow, one per item, in the corner you choose), and the trash can and the open-containers button sit in its header, left of EllesmereUI's own icons. EllesmereUI's own sort button is used there instead of Pocket Goblin's
- **EllesmereUI's "Auto Sell Junk"** (in its Quality of Life settings, on unless you turn it off) is now on the list of other addons Pocket Goblin warns about, since two addons selling at once can sell items on your keep list

## 1.8.0

New:
- **Share your lists or your whole profile**: the new **Share** card on the Profiles page exports your auto-sell and keep lists (with your keep words and item types), or the whole profile with all its settings, as a text to copy. Paste it on another account, or give it to a friend. **Import** shows what a pasted text holds before anything changes: lists are added to yours (nothing of yours is removed, and items you've already listed stay as they are), and a whole profile becomes a new profile that this character switches to. Your minimap button position, auto-sell suggestions and list filters aren't part of a shared profile. A text that's cut short or changed is caught and nothing is imported
- **Upgrade arrow** (needs **Pawn**): a green arrow on gear in your bags that Pawn says is better than what you wear, by the scales you use in Pawn, in the same corner as the coin (each item shows one icon: the coin, then the lock, then the equipment set icon, then the arrow, so gear you've set aside on purpose keeps its own icon). Gear you're too low a level for gets no arrow yet. If Pawn's own bag arrows are on, Pocket Goblin leaves the default bags to them. Also a Baganator corner icon. Turn it off on the Bags page, for example if Naowh Forever's bag marks already show upgrades
- **Grey gear Pawn calls an upgrade** is no longer sold or destroyed as junk: it's kept like any other upgrade. Without Pawn, grey gear is still junk
- With the coin icons on, the game's own coin on grey items is hidden everywhere, so a grey Pocket Goblin keeps doesn't look like junk
- The **Upgrades** keep rule uses Pawn too when it's installed, and judges each item by its own stats ("of the Bear" and "of the Eagle" copies can differ). Without Pawn it goes by item level, as before

Changed:
- **Profiles have their own page** again, at the bottom of the settings: switching, creating, copying, sharing and deleting profiles. General now holds only the interface and chat settings
- **White weapons and armor your class can never use**, like plate on a mage, are now sold from level 1 when "Sell white weapons and armor" is on. Before the level you set (10 by default), white gear you can use is still kept, as before

## 1.7.0

New:
- **Repair costs and net profit**: each earnings tile on the History page (this session, today, this character, all characters) now also shows what you spent on repairs and your **net**: everything you sold at vendors minus the repairs you paid yourself, in green or red. Hover a tile for the full breakdown, with what the guild paid for and your **most expensive repair** (for all characters, also whose it was)
- The minimap button's tooltip shows today's repairs
- With the goblin's voice on:
  - **Repair milestones** at 1, 10, 50, 100, 500 and 1,000 gold spent on repairs. Repairs before this version count, without a cheer for the milestones you'd already passed
  - The goblin **groans at big repair bills**, three times your usual one, and makes a fuss when it's a new record
  - Once a day it grumbles when **repairs cost more than you've sold** that day
- **No chat at all**: the chat messages setting has a new choice, **None**. Pocket Goblin then says nothing on its own, not even what it sold or repaired; the History page and the vendor panel still show every sale and repair. It still tells you when you can't afford repairs, and still answers your own commands and clicks
- **Items to disenchant**: on a character with Enchanting, green, blue and purple weapons and armor are kept instead of sold or destroyed, so you can disenchant them, soulbound ones too. Their tooltip says "kept (for disenchanting)". A new switch under **Kept automatically** on the Junk rules page, on by default; it does nothing on characters without Enchanting
- **Ask before selling**: items a junk rule picks (outgrown, unusable or lighter gear) of the quality you choose or better aren't sold on their own anymore. The vendor panel lists them under **Waiting for your OK**, with their value and why, and a **Sell** and **Keep** button each, plus **Sell all**. In your bags they get a coin with a question mark, and the trash can and Make room leave them alone. Choose Green and better, Blue and better (the default) or Epic only at the top of the Junk rules page. Items on your auto-sell list never ask
- **Epics**: the soulbound gear rules can now pick epics too, which always wait for your OK
- **Gear you swap to**: green or better gear you've put on more than once in the last 30 days is kept, like a resistance set or a swap weapon you use without an equipment set. Gear you wore once and replaced, like while levelling, can still be sold. Under **Kept automatically**, on by default. It starts counting from this version
- **Equipment set icon**: items in one of your equipment sets show that set's icon from the Equipment Manager in the coin's corner, so you can see which set they belong to and why they're never sold. Turn it off on the Bags page

Changed:
- The repairs total next to "Recent visits" is gone; it's in the earnings tiles now
- The chat setting's **Off** is now called **Summaries only**, since it always showed what was sold, repaired and bought back. Your choice is kept. `/goblin chat off` now picks None

## 1.6.0

New:
- **Warning about other junk sellers**: if another addon also sells junk when a vendor opens (Naowh Forever, Enhance QoL, Leatrix Plus, ElvUI, Scrap, Peddler and others), the vendor panel shows a warning at the top for as long as both are selling. Hover it to see which addons and the option to turn off in them. While another addon sells junk too, it can sell items on your keep list, and its sales don't show in your history (some not even in the buyback tab). For Naowh Forever, Enhance QoL, Leatrix Plus and ElvUI it only warns when their selling is actually turned on. With the vendor panel off, it's said in chat instead. Turn the warning off on the Vendor page

## 1.5.2

Fixed:
- The **Open** button no longer sells or hands over a container when a vendor, bank, guild bank, trade, mail or auction window is open: it asks you to close that first
- Cancelling the destroy confirmation after clicking **Make room** no longer loots everything later on its own
- The chat note about items kept for their auction price now knows when your copy is soulbound (and so sells)

Changed:
- Faster junk checks: the keep rules (upgrades, auction prices and the rest) now only run for items a junk rule would sell, instead of for everything in your bags

## 1.5.1

Changed:
- **Make room** loots the most valuable item first: quest items, then the item worth most, at a vendor or (with Auctionator or TradeSkillMaster) at the auction house. Its tooltip shows both the junk it destroys and the item that gets the slot
- With your bags still full and no junk left that it may destroy, the Make room button stays greyed out instead of disappearing, and its tooltip says why
- **Auction prices** now go by profit: an item is kept when it earns at least a set amount more at the auction house than at a vendor, after the auction house's 5% cut. 10 silver by default (Junk rules, Kept automatically). This replaces the multiplier, so cheap things like an empty vial, worth 1c at a vendor and 17c at auction, sell again
- Putting an item on the auto-sell list that the auction rule keeps now says so in chat
- In the Make room tooltip and its choice of what to loot first, grey items count at their vendor price, and prices from the auction house are marked "(auction)"

Fixed:
- The **Make room** button now also shows up when the loot window holds several items. It moves above the loot window when there's no room below it, and `/goblin debug` says why it's shown or not

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
