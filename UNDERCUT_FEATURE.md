# Aux Undercut Detection Feature

## Overview

Added undercut detection functionality to the aux addon's Auctions tab. This allows you to quickly check if any of your auctions have been undercut by other players.

## Features

### 1. New "Undercut" Column
Added a new column in the Auctions tab that shows the undercut status of each auction:

- **UNDERCUT** (red) - Someone has posted the same item for a lower buyout price
- **Lowest** (green) - You have the lowest buyout price
- **No Buyout** (orange) - Your auction has no buyout set
- **Not Checked** (gray) - Status not yet checked
- **Checking...** (yellow) - Currently scanning the AH
- **Error** (gray) - Failed to check status

### 2. "Check Undercuts" Button
New button next to the "Refresh" button that starts an automated undercut check for all your auctions.

## How It Works

1. Click the "Check Undercuts" button in the Auctions tab
2. The addon automatically scans the auction house for each of your items
3. Compares your buyout price (per unit) with all other auctions
4. Updates the "Undercut" column with the status
5. Displays a summary message when complete

## Technical Details

### Files Modified

1. **aux-addon/gui/auction_listing.lua** (lines 236-395)
   - Added new "Undercut" column to `auctions_columns`
   - Adjusted column widths to fit the new column
   - Added color-coded status display
   - Added sorting functionality for undercut status

2. **aux-addon/tabs/auctions/frame.lua** (lines 55-72)
   - Added "Check Undercuts" button
   - Connected button to `check_undercuts()` function

3. **aux-addon/tabs/auctions/core.lua** (lines 103-227)
   - Added undercut detection logic
   - Created sequential scanning system
   - Added progress tracking
   - Added status updates and completion messages

### How Undercut Detection Works

The system:
1. Resets all undercut statuses
2. Iterates through each auction sequentially
3. For each auction with a buyout:
   - Searches the AH for that item name
   - Scans the first page of results
   - Compares unit buyout prices
   - Marks as "undercut" if a cheaper auction from another player is found
   - Marks as "lowest" if no cheaper auction exists
4. Updates the UI in real-time as it checks
5. Shows final summary with undercut count

### Important Notes

- **Only checks auctions with buyouts** - Bid-only auctions show "No Buyout"
- **Compares unit prices** - Correctly handles different stack sizes
- **Ignores own auctions** - Only flags undercuts from other players
- **First page only** - For speed, only scans the first 50 results (sorted by price)
- **Sequential checking** - Checks one item at a time to avoid AH query rate limits
- **0.1 second delay** - Between each item check for stability

## Usage

### Basic Use
1. Open the Auction House
2. Click the "Auctions" tab in aux
3. Click "Check Undercuts" button
4. Wait for the scan to complete
5. Review the "Undercut" column

### What to Do When Undercut
When you see items marked as "UNDERCUT":
1. Select the item
2. Click "Cancel" to cancel that auction
3. Re-post at a competitive price

### Auto-Cancel (Future Feature)
Currently, canceling must be done manually. A future enhancement could:
- Add "Cancel All Undercut" button
- Automatically cancel undercut auctions
- Automatically repost at competitive prices

## Color Legend

- 🔴 **Red (UNDERCUT)** - Action needed! Someone undercut you
- 🟢 **Green (Lowest)** - You're good! Lowest price on AH
- 🟠 **Orange (No Buyout)** - Can't check (bid-only auction)
- ⚪ **Gray (Not Checked)** - Haven't run check yet
- 🟡 **Yellow (Checking...)** - Currently scanning
- ⚪ **Gray (Error)** - Scan failed (retry)

## Performance

- **Speed**: ~0.5-1 second per item (includes AH query + 0.1s delay)
- **6 items**: ~3-6 seconds total
- **20 items**: ~10-20 seconds total
- **Status updates**: Real-time progress bar and item count

## Limitations

- Cannot automatically cancel auctions (WoW API limitation - requires manual click)
- Only checks first page of AH results (50 items max)
- Respects AH query rate limits (sequential, not parallel)
- Requires AH to be open

## Future Enhancements

Possible improvements:
1. **Auto-cancel undercut items** - One-click cancel all undercut
2. **Continuous monitoring** - Auto-check every X minutes
3. **Sound alerts** - Beep when undercut
4. **Deep scan** - Check multiple pages for accuracy
5. **Price suggestions** - Recommend new price to beat competition
6. **Undercut history** - Track how often items get undercut
7. **Ignore list** - Skip certain items from checks

## Changelog

**v1.2** (2025-12-29)
- Optimized to use direct item queries instead of full AH scans
- Removed debug spam - only logs errors
- Reduced delay between checks from 0.5s to 0.3s
- Much faster: ~0.5-1 second per item (was 2-3 seconds)

**v1.1** (2025-12-29)
- Fixed stuck checking issue - now uses aux threading system properly
- Changed from callback-based to thread-based sequential processing
- Uses `aux.when()` and `aux.later()` for proper async handling

**v1.0** (2025-12-29)
- Initial release

## Credits

Feature added 2025-12-29 for Turtle WoW aux addon
