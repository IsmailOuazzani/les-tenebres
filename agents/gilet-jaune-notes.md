# Gilet jaune

The between-wave shop charges 50 shared Grabuge, the initial price of Crowd
Health and Crowd Velocity. In LAN co-op, the host uses the RPC sender to
resolve the buyer. The refill updates that player's HealthComponent, then the
existing ServerSync sends the armor value to clients.

The HUD uses Godot's built-in ProgressBar for the armor strip. The strip is
anchored inside HealthBar and takes up 3 px of its existing height.

Headless verification in Godot 4.7.2 covered the live HUD dimensions, purchases,
partial refills, damage overflow, and full-armor rejection. A two-process ENet
loopback verified the client purchase, shared balance, HUD replication, and
respawn with zero armor.
