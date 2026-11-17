# Snapchat-Style Live Protest Feed

The Snap feed is a cosmetic group chat on the left of the HUD. Four
recurring accounts each have a fixed handle, avatar, and color. The feed
keeps its original styling and six visible rows. It adds posts only
when a relevant gameplay event happens.

- **Prop destruction:** The window, garbage truck, sedan, barricade, and
  traffic-light scenes opt in with `snap_feed_topic`. The server includes
  that topic in the existing disruption event, and each HUD picks a short
  exchange specific to the prop. The other props still give Grabuge.
- **Recruitment:** The HUD batches increases to the replicated recruitment
  tally over 0.6 seconds and reacts to batches of five or more. Posts
  mention the number who just joined, since the tally includes all
  recruits in the run.
- **First megacop:** The authoritative spawner notifies `GameState` once
  the megacop enters the scene. The first spawn of each run is replicated
  reliably and can interrupt a routine exchange.
- **Replies:** A second account replies after 1.4 seconds. Routine exchanges
  start at most once every five seconds. An exchange can save a callback
  for the next pre-wave countdown, when the shop has closed. An Act
  ending clears any unused callback.

`scripts/snap_feed_data.gd` contains the French dialogue. Each post is
a handle and its text. A prop topic has alternate exchanges, and a third
post in an exchange is the optional callback. Each HUD chooses wording
locally using its own random number generator.
