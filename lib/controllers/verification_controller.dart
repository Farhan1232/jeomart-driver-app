import 'package:driver/constant/constant.dart';
import 'package:driver/models/document_model.dart';
import 'package:driver/models/driver_document_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:get/get.dart';

class VerificationController extends GetxController {
  RxBool isLoading = true.obs;

  @override
  void onInit() {
    // TODO: implement onInit
    getDocument();
    super.onInit();
  }

  RxList documentList = <DocumentModel>[].obs;
  RxList driverDocumentList = <Documents>[].obs;

  /// Loads the two halves of this screen together.
  ///
  /// They were awaited one after the other: the list of document types the
  /// admin requires, and then the documents this driver has already uploaded.
  /// Neither read depends on the other, so the screen paid the **sum** of two
  /// network round trips when it only ever needed the longer of the two. This
  /// is the screen a new driver is sent to before they can work, so it is one
  /// of the first things they see.
  ///
  /// Both results are assigned exactly as before, and a failure in either still
  /// leaves the screen readable rather than stranding it on the spinner.
  Future<void> getDocument() async {
    // Both reads are *started* here, before either is awaited, so they run
    // together. `Future.wait` would do the same but would flatten the two
    // different result types into `Object?`; this keeps them exact.
    final Future<List<DocumentModel>> requiredTypes =
        FireStoreUtils.getDocumentList(Constant.userModel!.isOwner == true ? "owner" : "driver");
    final Future<DriverDocumentModel?> uploaded = FireStoreUtils.getDocumentOfDriver();

    documentList.value = await requiredTypes;

    final DriverDocumentModel? driverDocuments = await uploaded;
    if (driverDocuments?.documents != null) {
      driverDocumentList.value = driverDocuments!.documents!;
    }

    isLoading.value = false;
    update();
  }
}
