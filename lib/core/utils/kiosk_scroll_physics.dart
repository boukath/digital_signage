import 'package:flutter/material.dart';

/// A custom PageScrollPhysics that multiplies user swipe velocity and distance.
/// Perfect for large 55"+ Kiosk screens.
class KioskPagePhysics extends PageScrollPhysics {
  final double dragMultiplier;

  const KioskPagePhysics({
    ScrollPhysics? parent,
    this.dragMultiplier = 2.5, // 👈 1 inch of drag = 2.5 inches of movement
  }) : super(parent: parent);

  @override
  KioskPagePhysics applyTo(ScrollPhysics? ancestor) {
    return KioskPagePhysics(
        parent: buildParent(ancestor),
        dragMultiplier: dragMultiplier
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // Multiply the user's physical swipe distance!
    return super.applyPhysicsToUserOffset(position, offset * dragMultiplier);
  }
}