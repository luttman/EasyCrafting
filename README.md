# Easy Crafting

Easy Crafting replaces the profession window in WoW Classic with one that shows what each recipe costs and what it earns. It also builds a shopping list for the materials you need and buys them for you at merchants.

## Features

- **Profit per recipe.** See the Auction House profit for every recipe. Vendor profit is available as an option.
- **Craft queue.** Queue recipes, reorder them, and click **Craft next** to open the right profession and craft the next item.
- **Shopping list.** Add the materials for your queue to a list. At a merchant, buy everything the merchant sells from your list with one click.
- **Break-even prices.** See the lowest price at which a recipe still pays for itself.
- **Sell crafts.** Sell the items you crafted to a merchant with one click.
- **Filters.** Show only the recipes you have the materials for, and show or hide unlearned recipes.
- **Alt professions.** Look up the professions and recipes of your other characters.
- **Bulk buying.** Shift-click an item at a merchant to choose how many to buy.

## Requirements

- WoW Classic, Interface version 16001.
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator), which supplies the Auction House prices.
- Optional: QuestieDB, which adds location data for recipe sources.

## Install

1. Download the latest release.
2. Extract the `EasyCrafting` folder into the `Interface\AddOns` folder of your WoW installation.
3. Restart the game or type `/reload`.

## Usage

Open any profession. The Easy Crafting window opens in place of the standard one.

| Command | Description |
|---|---|
| `/easycrafting` | Switch between the Easy Crafting window and the standard window. |
| `/ecsettings` | Open the settings. |

## Settings

Open the settings with `/ecsettings`. These options are available:

| Option | Default |
|---|---|
| Use the Easy Crafting profession window | On |
| Blizzard window style (needs `/reload`) | Off |
| Show unlearned recipes | On |
| Show craftable and merchant counts in the recipe list | On |
| Remember your alts' professions | On |
| Vendor profit in the recipe list | Off |
| Auction House profit | On |
| Shift-click merchant items to buy in bulk | On |

## Data sources and license

Easy Crafting is licensed under GPL-3.0-or-later. The profession data comes from several sources. See [DATA_SOURCES.md](DATA_SOURCES.md) for the list.
