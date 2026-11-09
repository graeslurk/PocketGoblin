# Pocket Goblin

A goblin lives in your bags. Every time you open a vendor it sells your junk,
repairs your gear and tells you what it earned. Made for **WoW Forever**.

## What it sells

You decide, with simple rules (all can be turned off):

- **Grey items**
- **White weapons and armor** once you're past the starting levels (from level 10 by default)
- **Food and drink you've outgrown** when you carry enough of something better
- **Cheap white items** below a price you choose (off by default; never class reagents or profession tools)
- **Soulbound gear your class can't use, or that you've outgrown** (off by default)
- **Soulbound armor lighter than you wear**, like leather on a warrior (off by default)
- **Recipes you already know** (off by default)
- **Anything on your auto-sell list**

Hover **Preview** on the Junk rules page to see exactly what would be sold right now, and why.

## Ask first

Nervous about an addon selling good gear? Choose a quality, **green**, **blue**
(the default) or **epic**, and anything a rule picks from that quality up
waits for your OK instead of being sold. The vendor panel lists it with its
value and the reason, and a **Sell** and **Keep** button. In your bags it gets
a coin with a question mark. Epics always ask.

## What it never sells

- Anything on your **keep list**
- Items whose name contains words you choose, item types you pick, or items worth more than a limit
- Weapons and armor that quests ask for
- **Upgrades**: gear better than what you wear in its slot, or that would fill an empty one. With **Pawn** installed, Pawn decides
- **Gear you swap to**: green or better gear you've put on more than once in the last 30 days, like a resistance set or a swap weapon. Levelling gear you wore once and replaced still sells
- **Items to disenchant**, on enchanters: green and better weapons and armor
- Items that earn at least 10 silver (or an amount you choose) more at the **auction house** than at a vendor, when Auctionator or TradeSkillMaster is installed
- Items in an **equipment set**, which show the set's icon in your bags

None of these are destroyed by the trash can or Make room either.

## At the vendor

- **Sells your junk** as soon as you open a vendor, 12 at a time so every sale can be bought back
- **Vendor panel** next to the vendor window: *Sell junk*, the items waiting for your OK, and buyback of anything you sold, one item at a time or all at once
- **Auto-repair**, optionally from guild funds
- **Suggestions**: sell the same item yourself a few times and your goblin offers to auto-sell it
- **Warns** when another addon (Naowh Forever, Leatrix Plus, Scrap and others) also sells junk at vendors, since two sellers can sell what you meant to keep

## In your bags

- **Alt+Right-click** any item to put it on the auto-sell list or the keep list
- **Coin and lock icons** on junk and kept items, and a green **upgrade arrow** on better gear (with Pawn), in the default bags, Baganator and EllesmereUI's bags, plus **equipment set icons** in the default bags and EllesmereUI's
- **Destroy button** for the cheapest junk, with a confirmation and a value limit
- **Make room** when your bags are full: a button on the loot window destroys your cheapest junk and loots, in one click
- **Open containers**: a button (and a hotkey) opens clams, sacks of loot and other containers, one per click
- **Sort button** on the default bags: stacks and sorts everything, with junk last
- **Bag space warning** when your bags are nearly full
- **Hotkeys** in the game's Key Bindings (Pocket Goblin): put the item under your mouse on the auto-sell or keep list, or destroy the cheapest junk. Pressing a key again leaves the item where it is, so a quick tap is always safe

## The goblin's ledger

- **History** of every vendor visit: what was sold (by the goblin or by you), buybacks and repairs
- **Earnings** this session, today, per character and across all characters
- **Repair costs and net profit** for the same periods: what you sold minus what you paid to repair. Hover for the full breakdown and your most expensive repair

## Your goblin, your way

- A goblin with **moods**, a **voice** and **milestones** for sales and repairs, who groans at big repair bills
- Or plain chat messages, only the summaries, or no chat at all
- **Profiles**, per character, each with its own auto-sell and keep lists. Import another profile's lists into yours without copying its settings
- **Share** your lists or a whole profile as text: paste it on another account, or give it to a friend

## Commands

| Command | |
|---|---|
| `/goblin` | Open the window |
| `/goblin sell` | Sell junk now (vendor must be open) |
| `/goblin sort` | Stack and sort your bags |
| `/goblin add`, `keep`, `remove <item>` | Put an item on a list, or take it off |
| `/goblin chat [goblin\|plain\|summaries\|none]` | Choose how the goblin talks in chat |
| `/goblin profile [name]` | Show or switch this character's profile |
| `/goblin welcome` | Show the welcome window again |
| `/goblin debug` | Details to copy into a bug report |

## Reporting bugs

Type `/goblin debug`, copy the text from the window that opens and include it in your report.

## Translations

Pocket Goblin is in English. Translations are welcome: see `Locales/` for how to add one.

## About me

Hi, I'm Graeslurk! I play WoW Forever and got tired of clicking through
vendor windows to sell junk, so I built a goblin to do it for me. Pocket
Goblin is my first addon, and I'm working on it in my spare time.

Bug reports and ideas are very welcome: open an issue on GitHub (include
the text from `/goblin debug`).

If Pocket Goblin saves you some clicks and you'd like to say thanks, you can
[buy me a coffee](https://buymeacoffee.com/Graeslurk). It's completely
optional: the addon is and will stay free.

## License

All rights reserved, see `LICENSE`.
