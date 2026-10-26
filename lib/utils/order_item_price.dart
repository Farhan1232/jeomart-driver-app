import 'package:driver/models/cart_product_model.dart';

/// What one line of a food order costs, as the driver sees it while
/// delivering: the price paid for the item (the discount price when there is
/// one) plus its add-ons, times the quantity - the same sum the bill uses.
/// A missing or unreadable price counts as zero, so the line never throws.
double orderItemLineTotal(CartProductModel product) {
  final double discountPrice = double.tryParse(product.discountPrice.toString()) ?? 0;
  final double price = discountPrice > 0 ? discountPrice : (double.tryParse(product.price.toString()) ?? 0);
  final double extras = double.tryParse(product.extrasPrice.toString()) ?? 0;
  final double qty = double.tryParse(product.quantity.toString()) ?? 0;
  return (price + extras) * qty;
}
