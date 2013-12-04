TO DO
=====

Features
--------

* Automatic clean-up of long-running VMs in 'running' Redis queues
* Add dashboard to Sinatra (API) app
* Allow rate-limiting of tasks


Enhancements
------------

* Launch the dashboard/API app in a thread from the main app
* 'first-out-first-in' processing (as opposed to current 'loop' design) should allow for faster (or at least more uniform) pool-refilling overall
* Separate threads for pending/running/completed queues (either rather than or in addition to per-pool threads)
* Namespace the whole app


Fixes
-----

* The dashboard should look as good in Firefox as it does in Chrome and Safari
* Threads shouldn't die as often as they do
