class SessionUser {
  final bool authenticated;
  final int? id;
  final String? username;
  final String? picture;
  final String? status;
  final bool hasPassword;

  const SessionUser({
    required this.authenticated,
    this.id,
    this.username,
    this.picture,
    this.status,
    this.hasPassword = false,
  });

  factory SessionUser.unauthenticated() {
    return const SessionUser(authenticated: false);
  }

  factory SessionUser.fromJson(Map<String, dynamic> json) {
    return SessionUser(
      authenticated: json['authenticated'] == true,
      id: json['id'] as int?,
      username: json['username'] as String?,
      picture: json['picture'] as String?,
      status: json['status'] as String? ?? json['about_me'] as String?,
      hasPassword: json['has_password'] == true,
    );
  }

  SessionUser copyWith({
    bool? authenticated,
    int? id,
    String? username,
    String? picture,
    String? status,
    bool? hasPassword,
  }) {
    return SessionUser(
      authenticated: authenticated ?? this.authenticated,
      id: id ?? this.id,
      username: username ?? this.username,
      picture: picture ?? this.picture,
      status: status ?? this.status,
      hasPassword: hasPassword ?? this.hasPassword,
    );
  }
}

class RoomParticipant {
  final int id;
  final String username;
  final String? picture;

  const RoomParticipant({
    required this.id,
    required this.username,
    this.picture,
  });

  factory RoomParticipant.fromJson(Map<String, dynamic> json) {
    return RoomParticipant(
      id: json['id'] as int,
      username: json['username'] as String,
      picture: json['picture'] as String?,
    );
  }
}

class MessagePreview {
  final String body;

  const MessagePreview({required this.body});

  factory MessagePreview.fromJson(Map<String, dynamic> json) {
    return MessagePreview(body: json['body'] as String? ?? '');
  }
}

class RoomSummary {
  final int id;
  final bool isGroup;
  final String? name;
  final String? picture;
  final DateTime updatedAt;
  final List<RoomParticipant> participants;
  final MessagePreview? lastMessage;

  const RoomSummary({
    required this.id,
    required this.isGroup,
    required this.updatedAt,
    required this.participants,
    this.name,
    this.picture,
    this.lastMessage,
  });

  factory RoomSummary.fromJson(Map<String, dynamic> json) {
    return RoomSummary(
      id: json['id'] as int,
      isGroup: json['is_group'] == true,
      name: json['name'] as String?,
      picture: json['picture'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      participants: ((json['participants'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>())
          .map(RoomParticipant.fromJson)
          .toList(),
      lastMessage: json['last_message'] is Map<String, dynamic>
          ? MessagePreview.fromJson(json['last_message'] as Map<String, dynamic>)
          : null,
    );
  }

  static List<RoomSummary> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .cast<Map<String, dynamic>>()
        .map(RoomSummary.fromJson)
        .toList();
  }

  RoomParticipant? otherParticipantFor(SessionUser me) {
    final currentUserId = me.id;
    if (currentUserId == null) {
      return participants.isEmpty ? null : participants.first;
    }
    for (final participant in participants) {
      if (participant.id != currentUserId) {
        return participant;
      }
    }
    return participants.isEmpty ? null : participants.first;
  }

  String displayTitleFor(SessionUser me) {
    if (isGroup || !me.authenticated) {
      return name ?? '';
    }
    return otherParticipantFor(me)?.username ?? name ?? '';
  }

  String? displayPictureFor(SessionUser me) {
    if (isGroup || !me.authenticated) {
      return picture;
    }
    return otherParticipantFor(me)?.picture;
  }
}

class ChatMessage {
  final String id;
  final String body;
  final int senderId;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.body,
    required this.senderId,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: '${json['id']}',
      body: json['body'] as String? ?? '',
      senderId: json['sender_id'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  static List<ChatMessage> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .cast<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
  }
}

class NearbyUser {
  final int id;
  final String username;
  final String? picture;
  final String? status;
  final int distance;
  final DateTime lastSeen;

  const NearbyUser({
    required this.id,
    required this.username,
    required this.distance,
    required this.lastSeen,
    this.picture,
    this.status,
  });

  factory NearbyUser.fromJson(Map<String, dynamic> json) {
    return NearbyUser(
      id: json['id'] as int,
      username: json['username'] as String,
      picture: json['picture'] as String?,
      status: json['status'] as String? ?? json['about_me'] as String?,
      distance: json['distance'] as int? ?? 0,
      lastSeen: DateTime.parse(json['last_seen'] as String),
    );
  }

  static List<NearbyUser> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .cast<Map<String, dynamic>>()
        .map(NearbyUser.fromJson)
        .toList();
  }
}
