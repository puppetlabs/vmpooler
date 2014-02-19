TO DO
=====

Features
--------

* ...


Enhancements
------------

* Launch the dashboard/API app in a thread from the main app
* 'first-out-first-in' processing (as opposed to current 'loop' design) should allow for faster (or at least more uniform) pool-refilling overall
* Separate threads for pending/running/completed queues (either rather than or in addition to per-pool threads)
* Namespace the whole app
* Require 'authorization key' (returned in POST JSON) to DELETE via the API

