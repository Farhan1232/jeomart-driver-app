import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';

/// When a delivery order the driver holds is over, and what is written then.
///
/// A delivered order stayed in the driver's `inProgressOrderID` (and a
/// cancelled one could stay in either list), and the dispatcher skips a driver
/// whose lists are not empty while "one order at a time" is on - so that driver
/// never received another order. The driver's Home screen already follows the
/// order in those lists; when what it sees says the order is over, the id is
/// taken off the lists.
class FinishedOrder {
  const FinishedOrder._();

  /// Whether the driver is done with the order the Home screen follows.
  ///
  /// Only an answer from the server counts: a listener's first snapshot can
  /// come from the device cache, where an order that has not been downloaded
  /// yet looks exactly like one that no longer exists - acting on that would
  /// take a live order away from the driver.
  ///
  /// [found] is false when the order no longer matches the Home screen's query,
  /// which leaves out cancelled and rejected orders (or the order is gone).
  static bool isFinished({required bool fromCache, required bool found, String? status}) {
    if (fromCache) return false;
    if (!found) return true;
    return status == Constant.orderCompleted;
  }

  /// Where the driver's other services keep their orders.
  ///
  /// `inProgressOrderID` is shared by every service, so for a driver who does
  /// cabs and deliveries it also holds the cab ride they just accepted. The
  /// delivery Home screen cannot find that id among delivery orders, and
  /// "not found" alone used to release it - the cab ride vanished from the
  /// driver's own screen right after Accept. An id found in one of these is
  /// another screen's order and is left alone.
  static const List<String> otherServiceCollections = <String>[
    CollectionName.ridesBooking,
    CollectionName.parcelOrders,
    CollectionName.rentalOrders,
  ];

  /// The one update that takes [orderId] off both lists, and nothing else.
  static Map<String, Object> releaseFields(String orderId) {
    return <String, Object>{
      'inProgressOrderID': FieldValue.arrayRemove(<String>[orderId]),
      'orderRequestData': FieldValue.arrayRemove(<String>[orderId]),
    };
  }
}
