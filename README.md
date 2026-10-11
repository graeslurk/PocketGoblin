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
- **Anything on your auto-sell list**

And it never sells:

- Anything on your **keep list**
- Items whose name contains words you choose, item types you pick, or items worth more than a limit
- Weapons and armor that quests ask for
- Items in an equipment set

Hover **Preview** on the Junk rules page to see exactly what would be sold right now, and why.

## Features

- **Alt+Right-click** any item in your bags to put it on the auto-sell list or the keep list
- **Vendor panel** next to the vendor window: a *Sell junk* button, and buyback of anything you sold, one item at a time or all at once
- **Suggestions**: sell the same item yourself a few times and your goblin offers to auto-sell it
- **History** of every vendor visit: what was sold (by the goblin or by you), buybacks and repairs
- **Earnings** this session, today, per character and across all characters
- **Destroy button** in your bags for the cheapest junk, with a confirmation and a value limit
- **Bag space warning** when your bags are nearly full
- **Coin and lock icons** on junk and kept items, in the default bags and in Baganator
- **Auto-repair**, optionally from guild funds
- **Profiles**, per character
- A goblin with **moods**, a **voice** and **milestones**, or plain chat messages, or none

## Commands

| Command | |
|---|---|
| `/goblin` | Open the window |
| `/goblin sell` | Sell junk now (vendor must be open) |
| `/goblin add`, `keep`, `remove <item>` | Put an item on a list, or take it off |
| `/goblin chat [goblin\|plain\|off]` | Choose how the goblin talks in chat |
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

Bug reports and ideas are very welcome: open an issue here on GitHub (include
the text from `/goblin debug`).

If Pocket Goblin saves you some clicks and you'd like to say thanks, you can
[buy me a coffee](https://buymeacoffee.com/Graeslurk). It's completely
optional: the addon is and will stay free.

## License

All rights reserved, see `LICENSE`.
