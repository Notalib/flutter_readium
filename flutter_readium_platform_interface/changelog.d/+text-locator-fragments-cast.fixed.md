**`Locator.toTextLocator()` threw `type 'List<dynamic>' is not a subtype of type 'List<String>'` for locators without a CSS id selector.**
This crashed the reader's orientation-change workaround on audio and media-overlay locators. The empty fragment list is now typed.
