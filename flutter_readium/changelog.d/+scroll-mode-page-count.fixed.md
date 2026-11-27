**iOS/Android: scroll mode no longer reports `currentPage`/`totalPages`.**
A typo in the scroll-mode check made the helper compute column-based page counts while scrolling. They are now left out in scroll mode, as documented.
