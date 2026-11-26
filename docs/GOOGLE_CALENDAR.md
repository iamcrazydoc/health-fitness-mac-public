# Connect Google Calendar

Author: Binoy Shah

The app can read your training plan straight from Google Calendar. It looks for events whose
titles start with 🏃 (runs) or 🏁 (races), from a week ago to four weeks ahead. Access is
read-only: the app never creates, changes or deletes events.

With Google connected, the app **and the desktop widgets** refresh the plan on their own. If Google
can't be reached, the app falls back to the Mac's Calendar app (if you allowed access).

You make your own small Google "app" once, so your sign-in goes straight from your Mac to Google.
It takes about 10 minutes and is free.

## 1. Make a Google Cloud project

1. Go to <https://console.cloud.google.com/> and sign in with the Google account that has your
   training calendar.
2. At the top, open the project picker, click **New project**, name it `Health and Fitness`,
   and click **Create**. Make sure it is selected.

## 2. Turn on the Calendar API

1. Go to **APIs & Services > Library**.
2. Search for **Google Calendar API**, open it, and click **Enable**.

## 3. Set up the sign-in screen

1. Go to **APIs & Services > OAuth consent screen** (it may be called **Google Auth Platform >
   Branding**).
2. Choose **External** and click **Create**. Fill in the app name (`Health and Fitness`) and your
   email in the two required email fields. Save.
3. Under **Data access** (or **Scopes**), add these two read-only scopes, then Save:
   - `https://www.googleapis.com/auth/calendar.events.readonly`
   - `https://www.googleapis.com/auth/calendar.calendarlist.readonly` (lets the app read all your calendars)
4. Under **Audience**, click **Publish app** so the status says **In production**.
   - Why: while an app is in *Testing*, Google ends its sign-ins after 7 days, and the app
     would ask you to reconnect every week.
   - You don't need Google's verification for your own use. When you sign in, Google will show
     "Google hasn't verified this app". Click **Advanced**, then **Go to Health and Fitness
     (unsafe)**. It's your own app, so this is expected.

## 4. Make the Desktop client

1. Go to **APIs & Services > Credentials** (or **Clients**), click **Create credentials >
   OAuth client ID**.
2. Application type: **Desktop app**. Name: `Health and Fitness Mac`. Click **Create**.
3. Copy the **Client ID** and **Client Secret**. You don't need to download the JSON.

## 5. Connect in the app

1. Open the app's Settings (⌘,) > **Google Calendar**.
2. Paste the Client ID and Client Secret.
3. **Calendar ID**: leave it as `primary` if your runs are in your main calendar. For another
   calendar, use its ID from Google Calendar > Settings > that calendar > *Integrate calendar*.
4. Click **Connect Google**. Your browser opens. Pick your account and allow read access.
5. The browser says "Google Calendar is connected". Close the tab. Settings shows **Connected**,
   and the plan refreshes.

## All calendars, trips, flights and hotels

The app reads every calendar on your Google account (holiday, sports, birthday and moon-phase
calendars are ignored for trips). If you connected before version 1.7.0, click **Reconnect
Google** once so it may list your calendars.

Only flights and hotel bookings count as trips:
- **Flights**: Gmail flight events, titles with "flight" or airport pairs (JFK → SFO), and Gmail
  events with an airline flight number (UA 512) that also mention the flight. A flight leaving a
  home airport starts a trip; a flight back ends it.
- **Hotels**: Gmail hotel reservations and titles with hotel words (hotel, inn, resort, suites,
  Airbnb, major chains) or starting with 🏨. The city comes from the address.

Online meetings (Zoom, Google Meet, Teams, Webex and similar links, or "meeting", "call",
"webinar" in the title) are never trips, and neither are restaurant, ticket or car-rental
reservations or events you title with trip, travel or vacation.

Set your home city and airports in Settings > Home, so anything at home isn't counted. Put
`run: treadmill` or `run: none` in an event's notes if you can't run outside there.

## Privacy and safety

- The Client ID, Client Secret and sign-in tokens are stored only in your Mac's keychain,
  shared with the widgets. They are never logged or sent anywhere except Google.
- Sign-in uses PKCE and a one-time listener on `127.0.0.1` (your own Mac), which closes after
  the sign-in or after five minutes.
- **Disconnect** in Settings forgets the tokens and asks Google to revoke them. You can also
  remove access at <https://myaccount.google.com/permissions>.

## Troubleshooting

| What you see | What to do |
| --- | --- |
| "Google Calendar isn't connected" after a week | The consent screen is still in *Testing*. Publish it (step 3.4), then Connect again. |
| `Error 400: redirect_uri_mismatch` | The client type isn't **Desktop app**. Make a new Desktop client (step 4). |
| `Google Calendar answered with error 403` | The Calendar API isn't enabled (step 2). |
| `error 404` | The Calendar ID is wrong. Use `primary`, or copy the ID again. |
| No runs show | Event titles must start with 🏃 or 🏁, and fall within the next four weeks. |
