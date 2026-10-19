# Crafter's Journal

## 0.35.2

- **Waypoints for new Forever NPCs.** Some NPCs added in Forever have no location in the community databases yet, so clicking them said "unknown place". Odd Child (the quest "My First Real Potion" for Minor Discolored Healing Potion: inside the barn in Moonbrook, Westfall), Patricia Egan (Alchemy trainer, Dalaran) and Kaylaena Springwhisper (Engineering trainer, Mount Hyjal) now get a waypoint. For any NPC whose location still isn't known, the message now says so clearly.

## 0.35.1

- **Fixed recipes learned at the trainer shown as known from the start.** Some recipes new to Forever (Mana Well, Camp Tent, Enchanted Lute, Sharpening Wheel, Reagent Bot, Faction Banner, Cerulean Dye, Sulfuric Acid) were treated as basic recipes you know from level 1, so the route could tell you to craft Mana Well at 15 when the trainer only teaches it at 20. They're now learned at the trainer at the right level (the trainer cost shows as "?" since it isn't known yet).
- **Fixed recipes you learn automatically.** Linen Bag and a few other recipes are learned automatically in Forever; the route no longer sends you to pay the trainer for them.

## 0.35.0

- **Start route.** New "Start route" button under the summary: it locks the route you've chosen. While you buy on the Auction House, from vendors or take items from your mailbox, neither the route nor its cost change, and what you buy for it no longer shows up as free materials. Steps you've already passed are marked as done. Prices are frozen too: a new Auction House scan doesn't change the route's totals (not even after a reload) until you choose — "Update prices" keeps the same route with the new prices, "Recalculate route" looks for a new route. Playing never unlocks it (leveling up, buying, crafting), and when you reach your target it stays as "Route completed!" until you recalculate. Changing it on purpose does: "Recalculate route", the target, an option icon or removing a recipe.
- **Live progress while you craft.** With a route started, the step you're on is highlighted and shows how many crafts you've done and how many are left ("11 of 22 crafts · 11 left"); finished steps turn grey with a ✓ as soon as you reach the end of them, and you get a "Route completed!" message when you hit your target.
- **Planned and actual.** With a route started, the summary at the top shows a second row with what you've actually spent and earned since you started it: vendor and Auction House purchases, trainer costs and deposits, and what you get for selling what you craft (to vendors, and Auction House sales read from your mail). Only route items count.
- **Shopping list at the vendor.** Opening a vendor that sells something on your shopping list shows a window right next to it: what you're still missing, with a "Buy all" button (or click a row to buy just that one), and what you already have, greyed out. Purchases go one at a time and are checked when they arrive.
- **Auction House purchases waiting in the mail.** Auction House purchases arrive by mail in Forever: they're now counted as spent when you buy them, and the shopping list counts them as yours while they wait in your mailbox ("2 in the mail"), so it doesn't ask you to buy them again.
- **Sell and post from the Profit view.** With a vendor open, click a crafted item to sell what the route says to sell; with the Auction House open, click it to post it at the suggested price. Otherwise the click marks the nearest vendor or auctioneer on your map. Nothing is ever bought or sold without your click. The Profit view also shows how many of each item you've sold since starting the route.
- **Craft from the route.** Click a crafting step and it opens your profession with that recipe selected and starts crafting what's left of that step (at most what your materials allow). Prefer to only open the recipe? Turn off "Craft when clicking a route step" in Options → AddOns → Crafter's Journal.
- **Remove a recipe from the route.** Every step of the route now has a small ✕: click it if you don't want to use that recipe (for example, because its pattern is sold far away) and the route is recalculated with the next best option. A row at the end of the route brings removed recipes back.
- **No more expensive patterns for a handful of crafts.** The route could tell you to buy a pricey pattern (e.g. Deviate Scale Cloak for 70s on the Auction House) and then use it for only 3 crafts. Recipes you have to buy now only make it into the route when they pay off for the points they're actually used for.
- **"Use bags and bank" now picks a better route.** If the materials you're carrying make a different route cheaper overall (for example, leather in your bags makes Embossed Leather Gloves cheaper than buying Pattern: Deviate Scale Cloak), the route switches to it. Routes are compared as a whole, so it won't zigzag between recipes just to use up your materials.
- **Clickable shopping list.** Click an Auction House material to mark the nearest auctioneer on your map, or, with the Auction House open, to open its purchase with the quantity you're missing already filled in (just press Buy Now). The panel next to the Auction House does the same. Click a vendor material to mark the nearest vendor that sells it, or, with that vendor open, to buy what you're missing.
- **Live shopping list.** Each item now shows how many you have and how many are still missing for the rest of the route ("You have 12/20 · 8 missing"), and it updates as you buy, take items from your mailbox or craft. With a route started, items move between "buy" and "you already have it" based on what you carry right now.
- **Each character has their own routes.** Started routes and each profession's settings (target, options, removed recipes) are saved per character: your other characters don't see them, and you get them back when you log in with that character again.
- **Picks up where you left off.** Closing and reopening the window during a session takes you back to the page you were on, including the view you had open in a profession.
- **Refreshed look.** Bigger Route / Shopping list / Profit buttons with a large icon, like the Dungeon Journal's, more breathing room around everything, the Dungeon Journal's browns on the profession pages, both home pages and the recipe collection, and a color of its own for each profession card.
- **Easier to read at a glance.** The route now has a level column on the left: the level range of each crafting step ("72–75"), and the level where you learn a recipe, train a rank or get a tool. The shopping list and the Profit view use the same column for quantities, so all three views look alike.
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
