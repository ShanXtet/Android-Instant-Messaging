// lib/message_bubble_example.dart
//
// Example usage of MessageInteractionBubble widget
// Run this file to see the message bubble in action

import 'package:flutter/material.dart';
import 'message_interaction_bubble.dart';

void main() {
  runApp(const MessageBubbleExampleApp());
}

class MessageBubbleExampleApp extends StatelessWidget {
  const MessageBubbleExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Message Bubble Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MessageBubbleExample(),
    );
  }
}

