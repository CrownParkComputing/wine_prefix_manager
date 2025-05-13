# Wine Prefix Manager - Feature Implementation Test Checklist

## 1. Refresh Functionality
- [ ] Click the refresh button in the Game Library page
- [ ] Verify that the loading indicator appears during refresh
- [ ] Verify that games with warning triangle (not working) have their status cleared if the file exists
- [ ] Check if the snackbar appears with "Game library refreshed" message

## 2. Category Selection Fix
- [ ] Open game details for any game
- [ ] Navigate to the Settings tab in the game details dialog
- [ ] Verify that all categories from settings appear in the dropdown
- [ ] Create a new category in Settings page
- [ ] Open game details again and verify the new category appears
- [ ] Select a category and verify it gets saved correctly

## 3. Play Time Tracking
- [ ] Launch a game from the library
- [ ] Wait for a minute and close the game
- [ ] Open game details and check the History tab
- [ ] Verify play time is recorded correctly
- [ ] Verify last played time is updated
- [ ] Launch the game again and confirm that play time accumulates

## 4. History Tab Display
- [ ] Open game details for a game that has been played
- [ ] Navigate to the History tab
- [ ] Verify that total play time is displayed correctly
- [ ] Verify that last played date and time are displayed correctly
- [ ] For a new game without play time, verify it shows the correct message

## Notes
- Remember to test across different prefixes
- Test with both new games and existing games
- Check both games on local drives and external drives (for warning flag fix)
