import 'dart:async';

import 'package:flutter/services.dart';

class CallNotificationAction {
  const CallNotificationAction(this.type, {this.message = ''});

  final String type;
  final String message;
}

abstract interface class CallNotificationBridge {
  Stream<CallNotificationAction> get actions;

  Future<bool> requestPermission();

  Future<void> start({
    required String server,
    required String status,
    required bool muted,
    required bool speaker,
    String transientStatus = '',
  });

  Future<void> update({
    required String server,
    required String status,
    required bool muted,
    required bool speaker,
    String transientStatus = '',
  });

  Future<void> stop();
}

class NativeCallNotificationBridge implements CallNotificationBridge {
  NativeCallNotificationBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel =
            methodChannel ?? const MethodChannel('simple_voice_app/notification'),
        _eventChannel = eventChannel ??
            const EventChannel('simple_voice_app/notification_actions');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<CallNotificationAction>? _actions;

  @override
  Stream<CallNotificationAction> get actions {
    return _actions ??= _eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        final data = Map<Object?, Object?>.from(event);
        return CallNotificationAction(
          data['type']?.toString() ?? '',
          message: data['message']?.toString() ?? '',
        );
      }
      return CallNotificationAction(event?.toString() ?? '');
    });
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _methodChannel.invokeMethod<bool>('requestPermission') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> start({
    required String server,
    required String status,
    required bool muted,
    required bool speaker,
    String transientStatus = '',
  }) async {
    try {
      await _methodChannel.invokeMethod<void>('start', _payload(
        server: server,
        status: status,
        muted: muted,
        speaker: speaker,
        transientStatus: transientStatus,
      ));
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<void> update({
    required String server,
    required String status,
    required bool muted,
    required bool speaker,
    String transientStatus = '',
  }) async {
    try {
      await _methodChannel.invokeMethod<void>('update', _payload(
        server: server,
        status: status,
        muted: muted,
        speaker: speaker,
        transientStatus: transientStatus,
      ));
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod<void>('stop');
    } on MissingPluginException {
      return;
    }
  }

  Map<String, Object?> _payload({
    required String server,
    required String status,
    required bool muted,
    required bool speaker,
    required String transientStatus,
  }) {
    return {
      'server': server,
      'status': status,
      'muted': muted,
      'speaker': speaker,
      'transientStatus': transientStatus,
    };
  }
}
