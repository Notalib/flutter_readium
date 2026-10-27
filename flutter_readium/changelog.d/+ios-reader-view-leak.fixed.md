**iOS: closed reader views leaked, and reopening a book after a hot restart froze the app.**
The reader's method-channel handler held its view strongly, so no EPUB or PDF reader view was ever released. After a hot restart, view IDs start again at 0, and replacing the stale handler deadlocked the main thread. The handler now holds the view weakly.
