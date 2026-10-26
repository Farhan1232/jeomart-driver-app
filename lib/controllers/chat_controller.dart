import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/constant/send_notification.dart';
import 'package:driver/models/conversation_model.dart';
import 'package:driver/models/inbox_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/shared_order_chat.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

class ChatController extends GetxController {
  Rx<TextEditingController> messageController = TextEditingController().obs;

  Rx<ScrollController> scrollController = ScrollController().obs;

  @override
  void onInit() {
    getArgument();
    super.onInit();
  }

  RxBool isLoading = true.obs;
  RxString orderId = "".obs;
  RxString senderId = "".obs;
  RxString senderName = "".obs;
  RxString senderProfileUrl = "".obs;
  RxString receivedId = "".obs;
  RxString receivedName = "".obs;
  RxString receivedProfileUrl = "".obs;
  RxString token = "".obs;
  RxString chatType = "".obs;

  /// What the chat header prints under the name. Empty means `Order #<id>`,
  /// which is what every existing caller gets and what this screen has always
  /// shown; a driver-posted trip passes its own line instead.
  RxString subtitle = "".obs;
  Rx<UserModel?> receiverUser = UserModel().obs;

  /// Set when this chat belongs to a store order: one conversation for the
  /// customer, the store and the driver. Null for every other chat.
  Rxn<SharedOrderChat> sharedChat = Rxn<SharedOrderChat>();
  Future<SharedOrderChat?>? _sharedChatLoad;

  Future<void> getArgument() async {
    // if (scrollController.value.hasClients) {
    //   Timer(const Duration(milliseconds: 500), () => scrollController.value.jumpTo(scrollController.value.position.minScrollExtent));
    // }
    dynamic argumentData = Get.arguments;
    if (argumentData != null) {
      // Every field is read defensively. A caller that spells one of these
      // keys differently used to throw here - assigning null to an RxString -
      // and abandon `getArgument()` half way, which left the screen with no
      // receiver and a send button that wrote a message addressed to nobody.
      orderId.value = _text(argumentData['orderId']);
      senderId.value = _text(argumentData['senderId']);
      senderName.value = _text(argumentData['senderName']);
      senderProfileUrl.value = _text(argumentData['senderProfileUrl']);
      receivedId.value = _text(argumentData['receivedId']);
      receivedName.value = _text(argumentData['receivedName']);
      receivedProfileUrl.value = _text(argumentData['receivedProfileUrl']);
      token.value = _text(argumentData['token']);
      chatType.value = _text(argumentData['chatType']);
      subtitle.value = _text(argumentData['chatSubtitle']);
      // Whether this is a store order's chat; the lookup runs beside the rest
      // of the opening, not in front of it.
      if (orderId.value.isNotEmpty) {
        _sharedChatLoad = _loadSharedChat();
      }
      if (receivedId.value.isNotEmpty) {
        receiverUser.value = await FireStoreUtils.getUserProfile(receivedId.value);
      }
    }
    setSeen();
    isLoading.value = false;
  }

  static String _text(Object? raw) => raw?.toString() ?? '';

  Future<SharedOrderChat?> _loadSharedChat() async {
    final SharedOrderChat? chat = await SharedOrderChat.load(orderId.value);
    if (!isClosed) sharedChat.value = chat;
    return chat;
  }

  Future<void> setSeen() async {
    FireStoreUtils.setSeenChatForOrder(orderId: orderId.value);
  }

  Future<void> sendMessage(String message, Url? url, String videoThumbnail, String messageType) async {
    // Read before anything is awaited: the send button clears the field right
    // after calling this.
    final String typedText = messageController.value.text;
    SharedOrderChat? shared = sharedChat.value;
    if (shared == null && _sharedChatLoad != null) shared = await _sharedChatLoad;
    if (shared != null) {
      await shared.send(
        _orderMessage(message, url, videoThumbnail, messageType),
        senderRole: SharedOrderChat.driver,
        fallbackName: senderName.value,
        lastMessage: typedText,
        lastMessageType: messageType,
      );
      return;
    }

    List<String> senderReceiverId = [senderId.value, receivedId.value];
    InboxModel inboxModel = InboxModel(
        chatType: chatType.value,
        senderReceiverId: senderReceiverId,
        lastSenderId: senderId.value,
        senderId: senderId.value,
        receiverId: receivedId.value,
        createdAt: Timestamp.now(),
        orderId: orderId.value,
        lastMessage: typedText,
        lastMessageType: messageType,
        type: 'orderChat');

    FireStoreUtils.addInbox(inboxModel);

    ConversationModel conversationModel = ConversationModel(
        id: const Uuid().v4(),
        message: message,
        senderId: FireStoreUtils.getCurrentUid(),
        receiverId: receivedId.value,
        createdAt: Timestamp.now(),
        url: url,
        orderId: orderId.value,
        messageType: messageType,
        videoThumbnail: videoThumbnail,
        seen: false);

    if (url != null) {
      if (url.mime.contains('image')) {
        conversationModel.message = "sent a message".tr;
      } else if (url.mime.contains('video')) {
        conversationModel.message = "Sent a video".tr;
      } else if (url.mime.contains('audio')) {
        conversationModel.message = "Sent a audio".tr;
      }
    }

    FireStoreUtils.addChat(conversationModel);

    SendNotification.sendChatFcmMessage(senderName.value, conversationModel.message.toString(), receiverUser.value?.fcmToken ?? '', {'type': inboxModel.type, 'chatType': inboxModel.chatType});
  }

  /// A message for an order's shared chat, built the way [sendMessage] builds
  /// every other message.
  ConversationModel _orderMessage(String message, Url? url, String videoThumbnail, String messageType) {
    final ConversationModel conversationModel = ConversationModel(
        id: const Uuid().v4(),
        message: message,
        senderId: FireStoreUtils.getCurrentUid(),
        receiverId: receivedId.value,
        createdAt: Timestamp.now(),
        url: url,
        orderId: orderId.value,
        messageType: messageType,
        videoThumbnail: videoThumbnail,
        seen: false);
    if (url != null) {
      if (url.mime.contains('image')) {
        conversationModel.message = "sent a message".tr;
      } else if (url.mime.contains('video')) {
        conversationModel.message = "Sent a video".tr;
      } else if (url.mime.contains('audio')) {
        conversationModel.message = "Sent a audio".tr;
      }
    }
    return conversationModel;
  }

  final ImagePicker imagePicker = ImagePicker();

// Future pickFile({required ImageSource source}) async {
//   try {
//     XFile? image = await imagePicker.pickImage(source: source);
//     if (image == null) return;
//     Url url = await FireStoreUtils.uploadChatImageToFireStorage(File(image.path), Get.context!);
//     sendMessage('', url, '', 'image');
//     Get.back();
//   } on PlatformException catch (e) {
//     ShowToastDialog.showToast("${"failed_to_pick".tr} : \n $e");
//   }
// }
}
