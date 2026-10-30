The online transport implements the Noray protocol and adapts its UDP handshake from Fox’s Sake netfox.noray (MIT).

Upstream reference: https://github.com/foxssake/netfox/tree/cf5189d18e98766022c8c1c5e637a6a30c4c3703/addons/netfox.noray
Protocol: https://github.com/foxssake/noray

Only the small connection layer is adapted; netfox gameplay/rollback plugins are not required. Private session identifiers stay in memory and are never displayed or saved.
