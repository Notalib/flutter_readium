**Web: the reader ignored the height of the element it was embedded in.**
Its wrapper was forced to the viewport height minus 96px, so a reader in a shorter or taller column overflowed or left a gap. It now takes the size Flutter gives it. A full-screen reader is about 40px taller than before.
