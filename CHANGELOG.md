# Crafter's Journal

## 0.35.0

- **Start route.** New "Start route" button under the summary: it locks the route you've chosen. While you buy on the Auction House, from vendors or take items from your mailbox, neither the route nor its cost change, and what you buy for it no longer shows up as free materials. Steps you've already passed are marked as done. "Recalculate route" unlocks it; changing the target or an option, or removing a recipe, also unlocks it.
- **Planned and actual.** With a route started, the summary at the top shows a second row with what you've actually spent and earned since you started it: vendor and Auction House purchases, trainer costs and deposits, and what you get for selling what you craft (to vendors, and Auction House sales read from your mail). Only route items count.
- **Sell and post from the Profit view.** With a vendor open, click a crafted item to sell what the route says to sell; with the Auction House open, click it to post it at the suggested price. Otherwise the click marks the nearest vendor or auctioneer on your map. Nothing is ever bought or sold without your click. The Profit view also shows how many of each item you've sold since starting the route.
- **Craft from the route.** Click a crafting step to open your profession with that recipe selected, or press "Craft N" on the step to craft what's left of it (at most what your materials allow).
- **Remove a recipe from the route.** Every step of the route now has a small ✕: click it if you don't want to use that recipe (for example, because its pattern is sold far away) and the route is recalculated with the next best option. A row at the end of the route brings removed recipes back.
- **No more expensive patterns for a handful of crafts.** The route could tell you to buy a pricey pattern (e.g. Deviate Scale Cloak for 70s on the Auction House) and then use it for only 3 crafts. Recipes you have to buy now only make it into the route when they pay off for the points they're actually used for.
- **"Use bags and bank" now picks a better route.** If the materials you're carrying make a different route cheaper overall (for example, leather in your bags makes Embossed Leather Gloves cheaper than buying Pattern: Deviate Scale Cloak), the route switches to it. Routes are compared as a whole, so it won't zigzag between recipes just to use up your materials.
- **Live shopping list.** Each item now shows how many you have and how many are still missing for the rest of the route ("You have 12/20 · 8 missing"), and it updates as you buy, take items from your mailbox or craft.
- **Cleaner routes.** Where the route used to alternate two recipes every single point (e.g. Light Leather and Light Armor Kit from 1 to 20), it now sticks to one when that costs next to nothing extra: Leatherworking goes from 32 steps to 14.
- **Merchant's Favor recipes, your choice.** Recipes bought with Merchant's Favor tokens and camp reputation used to be counted as free in the route. Now they're left out by default, and a new Merchant's Favor icon next to the bag and quest icons lets you include them (they cost tokens, not gold; you need the camp reputation each one asks for).
- **Routes in progress on the home page.** Professions with a started route get a green border and a "Route in progress" note on their card.
- **Fixed recipe skill requirements.** 362 recipes learned from patterns, plans and formulas asked for less skill than they really need in Forever (e.g. Pattern: Dark Leather Tunic was shown at 50 but needs Leatherworking 75), so the route could tell you to learn a recipe you couldn't learn yet. They now use the exact skill each pattern requires.

## 0.34.3 (beta)

- **Report a bug.** New "Report" button in the top-left corner of the window: it shows our Discord link, ready to copy, so you can send us bugs, wrong data or new discoveries (with a screenshot).
- **Clearer Auction House scans.** If a scan doesn't finish (for example because the Auction House was closed before it ended), the header now says "Cancelled · last: …" instead of just showing the date of the previous scan, and the scan button's tooltip explains why. The message also reminds you to keep the Auction House open until the scan finishes.
- New minimap and addon-list icon.

## 0.34.2 (beta)

First public beta for WoW Forever.

- **Level your professions the cheapest way.** A step-by-step route from your current skill to 225 for Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking and First Aid, using Auction House prices from your own scans.
- **Trainers by rank.** Each step sends you to a trainer who really teaches that rank in Forever, with a waypoint on your map.
- **Recipe collection.** Every recipe of each profession in a journal-style list: which ones you know, which you can learn now, where to get the rest (trainer, vendor, quest, drop, reputation, Merchant's Favor) and what they cost and earn.
- **English and Spanish,** switchable at any time, including recipe and item names.
