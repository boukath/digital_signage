// File: lib/features/kiosk_player/data/kiosk_layout_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
// 👇 We import the model we created earlier in the dashboard!
import '../../client_dashboard/domain/layout_model.dart';

class KioskLayoutService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Creates a live stream to a specific layout.
  /// If the dashboard updates the layout, this stream instantly pushes the new data!
  Stream<LayoutModel?> listenToLayout(String layoutId) {
    return _firestore.collection('layouts').doc(layoutId).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }

      // Parse the JSON back into our Flutter objects
      final data = snapshot.data() as Map<String, dynamic>;

      // We need to map the JSON zones back into ZoneModel objects
      List<ZoneModel> parsedZones = (data['zones'] as List<dynamic>).map((z) {
        return ZoneModel.fromMap(z as Map<String, dynamic>);
      }).toList();

      return LayoutModel(
        layoutId: data['layoutId'] ?? '',
        name: data['name'] ?? '',
        isLandscape: data['isLandscape'] ?? true,
        zones: parsedZones,
      );
    });
  }
}