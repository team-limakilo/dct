# Dynamic Campaign Tools (DCT)

Mission scripting framework for persistent Digital Combat Simulator (DCS)
missions.

Provide a set of tools to allow mission designers to easily create scenarios
for persistent dynamic campaigns within the DCS game world.

**D**ynamic **C**ampaign **T**ools relies on content that can be built
directly in the mission editor, these individuals need little to no
programming skills to provide content to a DCT enabled mission.

Scenarios are created through a theater definition consisting of templates,
created in the Mission Editor and configuration files. There is an initial
learning curve but it is no more difficult than initially learning the DCS
Mission Editor.

## Getting Started

See docs: https://team-limakilo.github.io/dct/

## Features

* **Mission Creation**
  - uses static templates for reusable asset creation
  - no large .miz to manage just place player slots
  - theater and region organization to control spawning
    and placement
  - settings to customize how you want your campaign to
    play

* **Game Play**
  - Focus on more goal based gameplay vs. "air quake"
  - mission system used by AI and players
  - ticket system to track win/loss critera
  - Integrated Air Defense per faction
  - Weapon point buy system for players to limit kinds and
    types of payloads
  - Bomb blast effects enhancement and weapon impact system

* **Technical**
  - Built for large scale scenarios
  - **Persistent campaign progress across server restarts**

## Contribution Guide

See [Quick Start](https://team-limakilo.github.io/dct/quick-start) page. Contributions
can be made through github pull requests, but features and/or changes need to be
discussed first. The code is licensed under LGPLv3, and contributions must be
under the same license. For any issues or feature requests, please use the
GitHub issue tracker to file a new issue. Please make sure to provide as much detail
about the problem or feature as possible. New development is done in feature
branches, which are eventually merged into `master`, so base your features and
fixes on `master`.

## Contact Us

This fork of DCT is maintained by kukiric for the Lima Kilo DCS servers. As such, it
has many differences from the upstream versions of DCT. There is a `#dct-forks`
channel in the official DCT Discord server for discussion and support of forks like
this, and a `#mission-making` channel in the Lima Kilo Discord server, where support
can be given to anything specific to Lima Kilo code and tools.

Official DCT Discord Server: https://discord.gg/kG38MDqDrN

Lima Kilo Discord Server: https://discord.gg/dPG9pNuxJc
