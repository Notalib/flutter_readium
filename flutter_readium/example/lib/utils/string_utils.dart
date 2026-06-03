String sanitizeForKey(String input) =>
    input.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
