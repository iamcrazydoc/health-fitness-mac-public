# Using the app with Strava only (no athletedata)

Author: Binoy Shah

You don't need athletedata. If your watch (Garmin, COROS, Apple Watch, Polar, Suunto…) already
uploads runs to Strava, the app gets every run from Strava. athletedata only adds the watch
**recovery** numbers: readiness, sleep, HRV and steps.

## What works with Strava only

| Feature | Works? | Where the data comes from |
|---|---|---|
| Recent runs (distance, pace, heart rate) | ✅ | Strava |
| Best half marathon | ✅ | Strava |
| Predicted half time and gap to your goal | ✅ | Strava (outdoor runs of 3+ miles in the last 6 weeks) |
| This week's miles vs plan, days since last run | ✅ | Strava + your calendar |
| Next run, with weather and what to wear | ✅ | Your calendar + Open-Meteo |
| Recovery tab (check-ins, cited exercise plans, weekly PubMed check) | ✅ | Your own check-ins, saved on your Mac |
| Widgets: **Next run** and **Half goal** | ✅ | As above |
| Today rings: readiness, sleep, HRV, steps | Hidden | Needs athletedata (Strava doesn't share sleep or HRV). The Today card shows your run and last run instead |
| Widget: **Today** | ✅ run view | Shows today's run and your last run; the rings appear only with athletedata |
| "Low readiness, keep today easy" tip in Recovery | ❌ | Same as above |

## Setup

### 1. Make sure your watch uploads to Strava
- **Garmin:** in the Garmin Connect app, go to More > Settings > Connected Apps > Strava > Connect. New runs appear in Strava a few minutes after they sync. (Menu names can differ slightly between app versions.)
- **Other watches:** connect Strava in the watch maker's app (COROS, Polar Flow, Suunto, or Apple Health through the Strava app).

Check that your last run shows up at [strava.com](https://www.strava.com) before you go on.

### 2. Install the app
Follow **Install** in the [README](../README.md): install Xcode, sign in with your Apple ID, then run `bash setup.sh`.

### 3. Create your own Strava API app (free, about 2 minutes)
1. Go to [strava.com/settings/api](https://www.strava.com/settings/api).
2. Fill in:
   - **Application Name:** anything, e.g. "Health and Fitness Mac"
   - **Category:** Training
   - **Website:** `http://localhost`
   - **Authorization Callback Domain:** `localhost` (exactly this)
3. Upload any icon and save.
4. Copy the **Client ID** and **Client Secret**.

The app only asks Strava for read access. It never posts, edits or deletes anything.

### 4. Connect in the app
1. Open the app and press **⌘,** for Settings.
2. Under **Strava**, paste the Client ID and Client Secret, then click **Connect Strava**.
3. Approve in the browser. It comes back to the app and loads your runs.
4. Leave the **athletedata** section empty.
5. Under **Calendar**, click **Allow** if you keep your plan as calendar events. Run events must start with 🏃 (or 🏁 for races) and include the distance, e.g. `🏃 Long run · 6 mi`.

### 5. Add widgets
Right-click the desktop > **Edit Widgets** > search "Health and Fitness". Add **Next run** and
**Half goal**. **Today** shows your run for the day (rings only with athletedata).

## Set your home, goal and race date
In Settings (⌘,): **Home** sets the city and airports (the weather and trips use it), and **Goal**
sets the half marathon goal time, race date and race name. Nothing is built into the app, and
dates follow your Mac's time zone.

## Known limitations without athletedata
- Since 1.4.0, every watch-data feature (rings, readiness hints, the "your watch shows" recovery
  note) is hidden until athletedata is connected, and the setup card lists athletedata only as optional.
- Treadmill runs from Strava are listed, but only outdoor GPS runs count toward the prediction.

## Adding athletedata later
If you get an athletedata account, paste its server URL and API key into Settings > athletedata
and click **Save and test**. The rings and the Today widget fill in on the next refresh.
