// File: lib/app.dart

import 'package:flutter/material.dart';
import 'core/routing/auth_gatekeeper.dart'; // Import our new router

class DigitalSignageApp extends StatelessWidget {
  const DigitalSignageApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digital Signage Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      // We set the AuthGatekeeper as the permanent home of the app!
      home: const AuthGatekeeper(),
    );
  }
}