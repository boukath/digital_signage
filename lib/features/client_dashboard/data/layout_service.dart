// File: lib/features/client_dashboard/data/layout_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/layout_model.dart';

class LayoutService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Saves the complete layout design to Firestore
  Future<void> saveLayout(LayoutModel layout) async {
    try {
      await _firestore
          .collection('layouts')
          .doc(layout.layoutId)
          .set(layout.toMap());

      print('✅ Pro Layout saved successfully!');
    } catch (e) {
      print('⚠️ Error saving layout: $e');
      rethrow;
    }
  }
}