// This file automatically picks the right code based on where the app is running!
export 'thumbnail_io.dart' // Default to Native (Windows/Mac/Android)
if (dart.library.html) 'thumbnail_web.dart'; // Switch to Web Canvas if on Edge/Chrome