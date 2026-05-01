import '../models/chat_message.dart';

/// In-memory copy of chat bubbles when the home chat screen is disposed (e.g. opening History).
/// Not persisted — must be cleared when local chat is wiped (logout, clear history, account switch).
class ChatSessionSnapshot {
  ChatSessionSnapshot._();

  static List<ChatMessage>? _messages;

  static List<ChatMessage>? get current => _messages;

  static void replace(List<ChatMessage> messages) {
    _messages = List<ChatMessage>.from(messages);
  }

  static void clear() {
    _messages = null;
  }
}
