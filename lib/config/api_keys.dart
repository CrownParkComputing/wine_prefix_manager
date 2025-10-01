// Store your API keys here.
// IMPORTANT: Add this file to your .gitignore to avoid committing your secrets!

import 'dart:convert';

// Simple obfuscation helper (NOT encryption, just makes it less obvious in code)
String _deobfuscate(String obfuscated) {
  try {
    return utf8.decode(base64.decode(obfuscated));
  } catch (e) {
    return '';
  }
}

// IGDB API credentials - stored with basic obfuscation
// For production use, consider more robust encryption methods
String get globalIgdbClientId {
  // Obfuscated value: iwv8b7b2j538q7q956u8kpclmkwo3x
  return _deobfuscate('aXd2OGI3YjJqNTM4cTdxOTU2dThrcGNsbWt3bzN4');
}

String get globalIgdbClientSecret {
  // Obfuscated value: 4e14lzqxur9qetl2fm418mco671zkm
  return _deobfuscate('NGUxNGx6cXh1cjlxZXRsMmZtNDE4bWNvNjcxemtt');
}

// API URLs
String get globalTwitchOAuthUrl {
  return 'https://id.twitch.tv/oauth2/token';
}

String get globalIgdbApiBaseUrl {
  return 'https://api.igdb.com/v4';
}

String get globalIgdbImageBaseUrl {
  return 'https://images.igdb.com/igdb/image/upload';
} 