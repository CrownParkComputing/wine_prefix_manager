// Store your API keys here.
// IMPORTANT: Add this file to your .gitignore to avoid committing your secrets!

import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// IGDB API credentials - loaded from environment variables
// These should be set in .env file for development or as environment variables in production
String get globalIgdbClientId {
  // Try environment variable first (for production/CI), then .env file (for development)
  return Platform.environment['IGDB_CLIENT_ID'] ?? 
         dotenv.env['IGDB_CLIENT_ID'] ?? 
         '';
}

String get globalIgdbClientSecret {
  // Try environment variable first (for production/CI), then .env file (for development)
  return Platform.environment['IGDB_CLIENT_SECRET'] ?? 
         dotenv.env['IGDB_CLIENT_SECRET'] ?? 
         '';
}

// Optional URL overrides (usually not needed)
String get globalTwitchOAuthUrl {
  return Platform.environment['TWITCH_OAUTH_URL'] ?? 
         dotenv.env['TWITCH_OAUTH_URL'] ?? 
         'https://id.twitch.tv/oauth2/token';
}

String get globalIgdbApiBaseUrl {
  return Platform.environment['IGDB_API_BASE_URL'] ?? 
         dotenv.env['IGDB_API_BASE_URL'] ?? 
         'https://api.igdb.com/v4';
}

String get globalIgdbImageBaseUrl {
  return Platform.environment['IGDB_IMAGE_BASE_URL'] ?? 
         dotenv.env['IGDB_IMAGE_BASE_URL'] ?? 
         'https://images.igdb.com/igdb/image/upload';
}

// If you also want to make these URLs fixed, uncomment and use them:
// const String globalTwitchOAuthUrl = 'https://id.twitch.tv/oauth2/token';
// const String globalIgdbApiBaseUrl = 'https://api.igdb.com/v4';
// const String globalIgdbImageBaseUrl = 'https://images.igdb.com/igdb/image/upload'; 