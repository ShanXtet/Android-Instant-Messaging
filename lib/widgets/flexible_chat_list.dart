// lib/widgets/flexible_chat_list.dart
import 'package:flutter/material.dart';
import '../utils/responsive.dart';

class FlexibleChatList extends StatelessWidget {
  final List<Widget> children;
  final ScrollController? controller;
  final VoidCallback? onRefresh;
  final bool isLoading;
  final String? emptyMessage;

  const FlexibleChatList({
    super.key,
    required this.children,
    this.controller,
    this.onRefresh,
    this.isLoading = false,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final padding = Responsive.getPadding(context);
    
    Widget listView = ListView.builder(
      controller: controller,
      padding: EdgeInsets.all(padding.left),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );

    if (onRefresh != null) {
      listView = RefreshIndicator(
        onRefresh: () async => onRefresh!(),
        child: listView,
      );
    }

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (children.isEmpty) {
      return Center(
        child: Padding(
          padding: padding,
          child: Text(
            emptyMessage ?? 'No messages',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    return listView;
  }
}


