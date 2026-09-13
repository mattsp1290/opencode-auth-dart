enum OpenCodeProtocol { chatCompletions, messages, responses }

extension OpenCodeProtocolSupport on OpenCodeProtocol {
  bool get isSupported => this == OpenCodeProtocol.chatCompletions;
}
