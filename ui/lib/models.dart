enum MessageDeliveryState { sending, sent }

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
      username: json['username'] as String? ?? 'Unknown user',
      picture: json['picture'] as String?,
    );
  }

  RoomParticipant copyWith({int? id, String? username, String? picture}) {
    return RoomParticipant(
      id: id ?? this.id,
      username: username ?? this.username,
      picture: picture ?? this.picture,
    );
  }

  static List<RoomParticipant> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .cast<Map<String, dynamic>>()
        .map(RoomParticipant.fromJson)
        .toList();
  }
}

class MessagePreview {
  final String body;
  final int? senderId;
  final String? senderUsername;

  const MessagePreview({
    required this.body,
    this.senderId,
    this.senderUsername,
  });

  factory MessagePreview.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] as Map<String, dynamic>?;
    return MessagePreview(
      body: json['body'] as String? ?? '',
      senderId: json['sender_id'] as int? ?? sender?['id'] as int?,
      senderUsername:
          json['sender_username'] as String? ?? sender?['username'] as String?,
    );
  }
}

class RoomSummary {
  final int id;
  final String? name;
  final String? picture;
  final DateTime updatedAt;
  final List<RoomParticipant> participants;
  final MessagePreview? lastMessage;
  final bool pushMuted;
  final int pendingJoinRequestCount;

  const RoomSummary({
    required this.id,
    required this.updatedAt,
    required this.participants,
    this.name,
    this.picture,
    this.lastMessage,
    this.pushMuted = false,
    this.pendingJoinRequestCount = 0,
  });

  factory RoomSummary.fromJson(Map<String, dynamic> json) {
    return RoomSummary(
      id: json['id'] as int,
      name: json['name'] as String?,
      picture: json['picture'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      participants:
          ((json['participants'] as List<dynamic>? ?? const [])
                  .cast<Map<String, dynamic>>())
              .map(RoomParticipant.fromJson)
              .toList(),
      lastMessage: json['last_message'] is Map<String, dynamic>
          ? MessagePreview.fromJson(
              json['last_message'] as Map<String, dynamic>,
            )
          : null,
      pushMuted: json['push_muted'] == true,
      pendingJoinRequestCount: json['pending_join_request_count'] as int? ?? 0,
    );
  }

  static List<RoomSummary> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .cast<Map<String, dynamic>>()
        .map(RoomSummary.fromJson)
        .toList();
  }

  List<RoomParticipant> otherParticipantsFor(SessionUser me) {
    final currentUserId = me.id;
    if (currentUserId == null) {
      return List<RoomParticipant>.from(participants);
    }
    final others = participants
        .where((participant) => participant.id != currentUserId)
        .toList();
    if (others.isNotEmpty) {
      return others;
    }
    return List<RoomParticipant>.from(participants);
  }

  String displayTitleFor(SessionUser me) {
    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      return trimmedName;
    }
    final participantNames = otherParticipantsFor(me)
        .map((participant) => participant.username.trim())
        .where((username) => username.isNotEmpty)
        .toList();
    if (participantNames.isNotEmpty) {
      return participantNames.join(', ');
    }
    return 'Room';
  }

  String? displayPictureFor(SessionUser me) {
    if (picture != null && picture!.isNotEmpty) {
      return picture;
    }
    final others = otherParticipantsFor(me);
    if (others.length == 1) {
      return others.first.picture;
    }
    return null;
  }

  int get memberCount => participants.length;
}

class InviteLink {
  final String token;
  final DateTime expiresAt;
  final int? roomId;

  const InviteLink({required this.token, required this.expiresAt, this.roomId});

  factory InviteLink.fromJson(Map<String, dynamic> json) {
    return InviteLink(
      token: json['token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      roomId: json['room_id'] as int?,
    );
  }
}

class ChatMessage {
  final String id;
  final String body;
  final int senderId;
  final String? senderUsername;
  final String? senderPicture;
  final DateTime timestamp;
  final List<RoomParticipant> readByUsers;
  final MessageDeliveryState deliveryState;
  final String? clientTag;

  const ChatMessage({
    required this.id,
    required this.body,
    required this.senderId,
    required this.timestamp,
    this.senderUsername,
    this.senderPicture,
    this.readByUsers = const [],
    this.deliveryState = MessageDeliveryState.sent,
    this.clientTag,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] as Map<String, dynamic>?;
    return ChatMessage(
      id: '${json['id']}',
      body: json['body'] as String? ?? '',
      senderId: json['sender_id'] as int? ?? sender?['id'] as int,
      senderUsername:
          json['sender_username'] as String? ?? sender?['username'] as String?,
      senderPicture:
          json['sender_picture'] as String? ?? sender?['picture'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      readByUsers: json['read_by_users'] is List<dynamic>
          ? RoomParticipant.listFromJson(json['read_by_users'] as List<dynamic>)
          : const [],
      deliveryState: MessageDeliveryState.sent,
    );
  }

  static List<ChatMessage> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .cast<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
  }

  ChatMessage copyWith({
    String? id,
    String? body,
    int? senderId,
    String? senderUsername,
    String? senderPicture,
    DateTime? timestamp,
    List<RoomParticipant>? readByUsers,
    MessageDeliveryState? deliveryState,
    String? clientTag,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      body: body ?? this.body,
      senderId: senderId ?? this.senderId,
      senderUsername: senderUsername ?? this.senderUsername,
      senderPicture: senderPicture ?? this.senderPicture,
      timestamp: timestamp ?? this.timestamp,
      readByUsers: readByUsers ?? this.readByUsers,
      deliveryState: deliveryState ?? this.deliveryState,
      clientTag: clientTag ?? this.clientTag,
    );
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
    final rawLastSeen = json['last_seen'];
    return NearbyUser(
      id: json['id'] as int,
      username: json['username'] as String,
      picture: json['picture'] as String?,
      status: json['status'] as String? ?? json['about_me'] as String?,
      distance: json['distance'] as int? ?? 0,
      lastSeen: rawLastSeen is String
          ? DateTime.parse(rawLastSeen)
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static List<NearbyUser> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .cast<Map<String, dynamic>>()
        .map(NearbyUser.fromJson)
        .toList();
  }
}

class NearbyRoom {
  final RoomSummary room;
  final int? distance;
  final bool joinRequested;

  const NearbyRoom({
    required this.room,
    required this.joinRequested,
    this.distance,
  });

  factory NearbyRoom.fromJson(Map<String, dynamic> json) {
    return NearbyRoom(
      room: RoomSummary.fromJson(json['room'] as Map<String, dynamic>),
      distance: json['distance'] as int?,
      joinRequested:
          (json['room'] as Map<String, dynamic>)['join_requested'] == true,
    );
  }

  NearbyRoom copyWith({RoomSummary? room, int? distance, bool? joinRequested}) {
    return NearbyRoom(
      room: room ?? this.room,
      distance: distance ?? this.distance,
      joinRequested: joinRequested ?? this.joinRequested,
    );
  }
}

class NearbyItem {
  final String type;
  final int? distance;
  final NearbyUser? user;
  final NearbyRoom? room;

  const NearbyItem({required this.type, this.distance, this.user, this.room});

  factory NearbyItem.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'user';
    return NearbyItem(
      type: type,
      distance: json['distance'] as int?,
      user: type == 'user'
          ? NearbyUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      room: type == 'room' ? NearbyRoom.fromJson(json) : null,
    );
  }

  static List<NearbyItem> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .cast<Map<String, dynamic>>()
        .map(NearbyItem.fromJson)
        .toList();
  }
}

class RoomJoinRequest {
  final NearbyUser user;
  final DateTime createdAt;
  final DateTime expiresAt;

  const RoomJoinRequest({
    required this.user,
    required this.createdAt,
    required this.expiresAt,
  });

  factory RoomJoinRequest.fromJson(Map<String, dynamic> json) {
    return RoomJoinRequest(
      user: NearbyUser.fromJson(json['user'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  static List<RoomJoinRequest> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .cast<Map<String, dynamic>>()
        .map(RoomJoinRequest.fromJson)
        .toList();
  }
}
